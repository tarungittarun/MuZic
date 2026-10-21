package com.auralis.player

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Shader
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.view.View
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/**
 * Owns MuZic's playback card in the notification shade.
 *
 * The system media player (lock screen, Quick Settings, Bluetooth) belongs
 * to the audio_service / just_audio_background stack, exactly as on the
 * main branch. Some devices' SystemUI nevertheless keeps that player out
 * of the notification *shade* (it renders on the lock screen only), so
 * this service mirrors the same playback state into a shade-visible card:
 * full-artwork banner with synced transport controls, posted on its own
 * notification slot per style level and self-verified after every post,
 * stepping down banner -> linear -> plain until the device keeps one.
 *
 * Playback itself stays in Dart (just_audio); this service only publishes state
 * and forwards button presses back through [commandSink].
 */
class PlaybackService : Service() {

    companion object {
        const val CHANNEL_ID = "com.music.player.playback.v2"
        private const val CHANNEL_NAME = "MuZic playback"
        const val NOTIFICATION_ID = 1201

        /**
         * Plain (non-media) card so playback controls also appear in the
         * notification LIST when the shade is pulled down at the home screen.
         * Android diverts media-style notifications to the Quick Settings /
         * lock-screen media player and hides them from the notification list,
         * so the media card alone never shows there on many devices.
         * This card has no MediaStyle and no session token, so SystemUI keeps
         * it in the list. It is VISIBILITY_SECRET so the secure lock screen
         * still shows only the rich media player, not a duplicate.
         */
        const val SHADE_NOTIFICATION_ID = 1202

        /**
         * One notification slot per shade richness level (index = level):
         * the banner posts on 1222, the linear card on 1212, the plain
         * MediaStyle card on 1202. Some SystemUI builds silently discard a
         * custom-layout notification posted on a slot that previously held
         * a media-style card, so each style generation gets its own slot.
         */
        val SHADE_LEVEL_IDS = intArrayOf(
            SHADE_NOTIFICATION_ID,
            1212,
            1222,
        )

        const val EXTRA_TITLE = "title"
        const val EXTRA_ARTIST = "artist"
        const val EXTRA_ALBUM = "album"
        const val EXTRA_ARTWORK_URL = "artworkUrl"
        const val EXTRA_ARTWORK_PATH = "artworkPath"
        const val EXTRA_PLAYING = "playing"
        const val EXTRA_POSITION = "positionMs"
        const val EXTRA_DURATION = "durationMs"
        const val EXTRA_SPEED = "speed"
        const val EXTRA_HAS_NEXT = "hasNext"
        const val EXTRA_HAS_PREVIOUS = "hasPrevious"
        const val EXTRA_SHUFFLE = "shuffle"
        const val EXTRA_REPEAT_MODE = "repeatMode"
        const val EXTRA_SHADE_ENABLED = "shadeEnabled"
        const val EXTRA_SHADE_STYLE = "shadeStyle"
        const val EXTRA_SHADE_THEME = "shadeTheme"
        const val EXTRA_SHADE_ARTWORK = "shadeArtwork"
        const val EXTRA_SHADE_PREVIOUS = "shadePrevious"
        const val EXTRA_SHADE_NEXT = "shadeNext"
        const val EXTRA_SHADE_PROGRESS = "shadeProgress"
        const val EXTRA_SHADE_KEEP_ON_PAUSE = "shadeKeepOnPause"

        private const val SHADE_PREFS = "muzic_shade_card"
        private const val KEY_SHADE_LEVEL = "shade_level"
        private const val KEY_SHADE_LAYOUT_REV = "shade_layout_rev"

        /** Bump when the shade-card layouts change: re-trials level 2. */
        private const val SHADE_LAYOUT_REV = 7

        /** Set by MainActivity: receives transport commands from the card. */
        var commandSink: ((String, Double?) -> Unit)? = null

        /**
         * Set by MainActivity: receives native-side failures so they end up
         * in the app's diagnostics log instead of being silently swallowed.
         */
        var errorSink: ((String) -> Unit)? = null

        @Volatile private var session: MediaSessionCompat? = null

        /** Exposed so the diagnostics probe can report "is a session active". */
        fun isSessionActive(): Boolean = session?.isActive == true
    }

    private val artworkLoader = Executors.newSingleThreadExecutor()
    private var artworkBitmap: Bitmap? = null

    /**
     * Small copy of the artwork for the shade card's RemoteViews. RemoteViews
     * parcel their bitmaps into the notification; parcelling the full
     * 512x512 artwork twice (collapsed + expanded views) risks blowing the
     * binder transaction limit, which makes notify() fail outright.
     */
    private var shadeArtworkBitmap: Bitmap? = null

    /**
     * Wide banner copy of the artwork (512x200, bottom gradient baked in)
     * for the level-2 shade card, so the overlaid title stays readable
     * without needing an extra scrim view in the layout.
     */
    private var shadeBannerBitmap: Bitmap? = null
    private var artworkKey: String? = null
    private var latestArtworkUrl: String? = null
    private var latestArtworkPath: String? = null
    private var latestTitle: String = "MuZic"
    private var latestArtist: String = ""
    private var latestAlbum: String = ""
    private var playing = false
    private var positionMs = 0L
    private var durationMs = 0L
    private var speed = 1f
    private var hasNext = true
    private var hasPrevious = true
    private var shuffleOn = false

    /** 0 = off, 1 = repeat all, 2 = repeat one (mirrors just_audio). */
    private var repeatMode = 0

    // Position extrapolation: Dart reports the position on state changes;
    // between reports the ticker advances it locally so the shade card's
    // progress/waveform stays in sync with the music instead of freezing.
    private var positionBaseMs = 0L
    private var positionBaseElapsed = 0L
    private val progressHandler = Handler(Looper.getMainLooper())
    private var tickerRunning = false
    private val progressTicker = object : Runnable {
        override fun run() {
            if (!playing) {
                tickerRunning = false
                return
            }
            postShadeCard()
            progressHandler.postDelayed(this, 1000)
        }
    }

    // Waveform bars for the current track (generated bitmap seekbar).
    private var waveformBars: FloatArray? = null
    private var waveformKey: String? = null

    // Shade-card customisation (user settings, forwarded from Dart).
    private var shadeEnabled = true
    private var shadeStyle = "rich"
    private var shadeTheme = "system"
    private var shadeArtwork = true
    private var shadePrevious = true
    private var shadeNext = true
    private var shadeProgress = true
    private var shadeKeepOnPause = true

    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY &&
                playing
            ) {
                commandSink?.invoke("pause", null)
            }
        }
    }
    private var noisyRegistered = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
        // Remember the richest shade-card level this device accepts, so a
        // demotion survives restarts instead of being retried every launch.
        // When the card layouts themselves change, the richest level gets
        // one fresh trial on this device.
        val shadePrefs = getSharedPreferences(SHADE_PREFS, Context.MODE_PRIVATE)
        shadeLevel = shadePrefs.getInt(KEY_SHADE_LEVEL, 2).coerceIn(0, 2)
        if (shadePrefs.getInt(KEY_SHADE_LAYOUT_REV, 0) != SHADE_LAYOUT_REV) {
            shadeLevel = 2
            shadePrefs.edit()
                .putInt(KEY_SHADE_LEVEL, shadeLevel)
                .putInt(KEY_SHADE_LAYOUT_REV, SHADE_LAYOUT_REV)
                .apply()
        }
        // Clear a stray blank ongoing notification (#0) left behind by a
        // very old build; nothing in this version posts with id 0.
        runCatching {
            getSystemService(NotificationManager::class.java)?.cancel(0)
        }
        val mediaSession = MediaSessionCompat(this, "MuZic").apply {
            setFlags(
                MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or
                    MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS,
            )
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() = commandSink?.invoke("play", null) ?: Unit
                override fun onPause() = commandSink?.invoke("pause", null) ?: Unit
                override fun onStop() = commandSink?.invoke("stop", null) ?: Unit
                override fun onSkipToNext() =
                    commandSink?.invoke("next", null) ?: Unit
                override fun onSkipToPrevious() =
                    commandSink?.invoke("previous", null) ?: Unit
                override fun onSeekTo(pos: Long) =
                    commandSink?.invoke("seek", pos.toDouble()) ?: Unit
                override fun onSetShuffleMode(shuffleMode: Int) =
                    commandSink?.invoke(
                        if (shuffleMode ==
                            PlaybackStateCompat.SHUFFLE_MODE_ALL
                        ) {
                            "shuffleOn"
                        } else {
                            "shuffleOff"
                        },
                        null,
                    ) ?: Unit
                override fun onSetRepeatMode(repeatMode: Int) =
                    commandSink?.invoke(
                        "setRepeatMode",
                        repeatMode.toDouble(),
                    ) ?: Unit
            })
            setSessionActivity(contentIntent())
            isActive = true
        }
        session = mediaSession
        if (!noisyRegistered) {
            registerReceiver(noisyReceiver, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY))
            noisyRegistered = true
        }
        if (!shadeWakeRegistered) {
            val wakeFilter = IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_ON)
                addAction(Intent.ACTION_USER_PRESENT)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(shadeWakeReceiver, wakeFilter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(shadeWakeReceiver, wakeFilter)
            }
            shadeWakeRegistered = true
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) return START_STICKY
        intent.getStringExtra(EXTRA_TITLE)?.let { latestTitle = it }
        intent.getStringExtra(EXTRA_ARTIST)?.let { latestArtist = it }
        intent.getStringExtra(EXTRA_ALBUM)?.let { latestAlbum = it }
        latestArtworkUrl = intent.getStringExtra(EXTRA_ARTWORK_URL)
        latestArtworkPath = intent.getStringExtra(EXTRA_ARTWORK_PATH)
        playing = intent.getBooleanExtra(EXTRA_PLAYING, playing)
        positionMs = intent.getLongExtra(EXTRA_POSITION, positionMs)
        durationMs = intent.getLongExtra(EXTRA_DURATION, durationMs)
        speed = intent.getFloatExtra(EXTRA_SPEED, speed)
        hasNext = intent.getBooleanExtra(EXTRA_HAS_NEXT, hasNext)
        hasPrevious = intent.getBooleanExtra(EXTRA_HAS_PREVIOUS, hasPrevious)
        shuffleOn = intent.getBooleanExtra(EXTRA_SHUFFLE, shuffleOn)
        repeatMode = intent.getIntExtra(EXTRA_REPEAT_MODE, repeatMode)
        shadeEnabled = intent.getBooleanExtra(EXTRA_SHADE_ENABLED, shadeEnabled)
        intent.getStringExtra(EXTRA_SHADE_STYLE)?.let { newStyle ->
            if (newStyle != shadeStyle) {
                shadeStyle = newStyle
                // The user changed card style: give the richest layout a
                // fresh trial on this device.
                shadeLevel = 2
            }
        }
        intent.getStringExtra(EXTRA_SHADE_THEME)?.let { shadeTheme = it }
        shadeArtwork = intent.getBooleanExtra(EXTRA_SHADE_ARTWORK, shadeArtwork)
        shadePrevious = intent.getBooleanExtra(EXTRA_SHADE_PREVIOUS, shadePrevious)
        shadeNext = intent.getBooleanExtra(EXTRA_SHADE_NEXT, shadeNext)
        shadeProgress = intent.getBooleanExtra(EXTRA_SHADE_PROGRESS, shadeProgress)
        shadeKeepOnPause =
            intent.getBooleanExtra(EXTRA_SHADE_KEEP_ON_PAUSE, shadeKeepOnPause)

        // Anchor the local position clock at the freshly reported
        // position; the 1s ticker extrapolates from here while playing.
        positionBaseMs = positionMs
        positionBaseElapsed = SystemClock.elapsedRealtime()
        if (playing) startProgressTicker() else stopProgressTicker()

        publishSessionState()
        loadArtworkIfNeeded()
        // Must be foreground for the card to survive the app going to the
        // background. The foreground notification is deliberately the
        // plain, always-valid MediaStyle card: on some devices SystemUI
        // rejects custom RemoteViews, and a rejected *foreground*
        // notification can take the whole app down with it (1.5.17 crash
        // on the Motorola Edge 60 Neo). The custom shade card is
        // therefore only ever posted as a regular notification, which
        // the system can at worst drop harmlessly.
        startForeground(NOTIFICATION_ID, buildNotification())
        postShadeCard()
        return START_STICKY
    }

    private fun publishSessionState() {
        val mediaSession = session ?: return
        mediaSession.setMetadata(
            MediaMetadataCompat.Builder()
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE, latestTitle)
                .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, latestArtist)
                .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, latestAlbum)
                .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, durationMs)
                .apply { artworkBitmap?.let { putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, it) } }
                .build(),
        )
        val actions = PlaybackStateCompat.ACTION_PLAY or
            PlaybackStateCompat.ACTION_PAUSE or
            PlaybackStateCompat.ACTION_PLAY_PAUSE or
            PlaybackStateCompat.ACTION_STOP or
            PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
            PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
            PlaybackStateCompat.ACTION_SEEK_TO or
            PlaybackStateCompat.ACTION_SET_SHUFFLE_MODE or
            PlaybackStateCompat.ACTION_SET_REPEAT_MODE
        mediaSession.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(actions)
                .setState(
                    if (playing) PlaybackStateCompat.STATE_PLAYING
                    else PlaybackStateCompat.STATE_PAUSED,
                    positionMs,
                    speed,
                )
                .build(),
        )
    }

    private fun startProgressTicker() {
        if (tickerRunning) return
        tickerRunning = true
        progressHandler.postDelayed(progressTicker, 1000)
    }

    private fun stopProgressTicker() {
        tickerRunning = false
        progressHandler.removeCallbacks(progressTicker)
    }

    /** Best current position: Dart's last report, extrapolated while playing. */
    private fun currentPositionMs(): Long {
        if (!playing) return positionMs
        val advanced =
            ((SystemClock.elapsedRealtime() - positionBaseElapsed) * speed).toLong()
        val position = positionBaseMs + advanced
        return if (durationMs > 0) {
            position.coerceIn(0L, durationMs)
        } else {
            position.coerceAtLeast(0L)
        }
    }

    /**
     * The expanded card's seekbar is a generated waveform bitmap (bars +
     * playhead dot), styled after the system media player. Bars are
     * pseudo-random but seeded by the track, so the shape is stable for a
     * song and only the played portion lights up as playback advances.
     */
    private fun waveformBitmap(): Bitmap {
        val key = "$latestTitle|$latestArtist"
        var bars = waveformBars
        if (bars == null || waveformKey != key) {
            val random = java.util.Random(key.hashCode().toLong())
            val raw = FloatArray(72) { 0.25f + random.nextFloat() * 0.75f }
            bars = FloatArray(raw.size) { i ->
                val prev = raw[(i - 1 + raw.size) % raw.size]
                val next = raw[(i + 1) % raw.size]
                (prev + raw[i] * 2f + next) / 4f
            }
            waveformBars = bars
            waveformKey = key
        }
        val width = 768
        val height = 84
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val fraction = if (durationMs > 0) {
            (currentPositionMs().toFloat() / durationMs).coerceIn(0f, 1f)
        } else {
            0f
        }
        val centerY = height / 2f
        val baseline = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0x40FFFFFF
            strokeWidth = 3f
        }
        canvas.drawLine(0f, centerY, width.toFloat(), centerY, baseline)
        val barPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        val slot = width.toFloat() / bars.size
        val barWidth = slot * 0.52f
        val playedX = fraction * width
        for (i in bars.indices) {
            val x = i * slot + slot / 2f
            val barHeight = (bars[i] * (height - 16f)).coerceAtLeast(6f)
            barPaint.color =
                if (x <= playedX) 0xFF6C5CE7.toInt() else 0x73FFFFFF
            canvas.drawRoundRect(
                x - barWidth / 2f,
                centerY - barHeight / 2f,
                x + barWidth / 2f,
                centerY + barHeight / 2f,
                barWidth / 2f,
                barWidth / 2f,
                barPaint,
            )
        }
        if (durationMs > 0) {
            val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = 0xFF6C5CE7.toInt()
            }
            val dot = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = 0xFFFFFFFF.toInt()
            }
            canvas.drawCircle(playedX, centerY, 13f, ring)
            canvas.drawCircle(playedX, centerY, 8f, dot)
        }
        return bitmap
    }

    private fun loadArtworkIfNeeded() {
        val key = latestArtworkPath ?: latestArtworkUrl ?: return
        if (key == artworkKey && artworkBitmap != null) return
        artworkKey = key
        artworkLoader.execute {
            val bitmap = decodeArtwork(key)
            if (bitmap == null) return@execute
            artworkBitmap = bitmap
            shadeArtworkBitmap = Bitmap.createScaledBitmap(bitmap, 192, 192, true)
            shadeBannerBitmap = runCatching { makeBannerBitmap(bitmap) }.getOrNull()
            publishSessionState()
            val manager = getSystemService(NotificationManager::class.java)
            manager?.notify(NOTIFICATION_ID, buildNotification())
            postShadeCard()
        }
    }

    private fun decodeArtwork(key: String): Bitmap? {
        return try {
            if (key.startsWith("http://") || key.startsWith("https://")) {
                val connection = URL(key).openConnection() as HttpURLConnection
                connection.connectTimeout = 8000
                connection.readTimeout = 8000
                connection.instanceFollowRedirects = true
                connection.inputStream.use { BitmapFactory.decodeStream(it) }
            } else {
                val file = File(key)
                if (!file.exists()) return null
                BitmapFactory.decodeFile(file.absolutePath)
            }
        } catch (e: Exception) {
            null
        }.let { bitmap ->
            if (bitmap == null) null else scaleSquare(bitmap)
        }
    }

    /**
     * Centre-crops [source] to a wide 512x200 banner and burns a bottom
     * gradient (transparent -> near-black) into it, so white title text
     * overlaid on the banner stays readable on any artwork.
     */
    private fun makeBannerBitmap(source: Bitmap): Bitmap {
        val width = 768
        val height = 576
        val output = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val scale = maxOf(
            width.toFloat() / source.width,
            height.toFloat() / source.height,
        )
        val matrix = Matrix().apply {
            setScale(scale, scale)
            postTranslate(
                (width - source.width * scale) / 2f,
                (height - source.height * scale) / 2f,
            )
        }
        canvas.drawBitmap(source, matrix, Paint(Paint.FILTER_BITMAP_FLAG))
        val gradient = LinearGradient(
            0f,
            height * 0.28f,
            0f,
            height.toFloat(),
            intArrayOf(0x00000000, 0x59000000, 0xE6000000.toInt()),
            floatArrayOf(0f, 0.55f, 1f),
            Shader.TileMode.CLAMP,
        )
        canvas.drawRect(
            0f,
            0f,
            width.toFloat(),
            height.toFloat(),
            Paint().apply {
                shader = gradient
                isDither = true
            },
        )
        return output
    }

    private fun scaleSquare(source: Bitmap): Bitmap {
        val side = minOf(source.width, source.height)
        val cropped = Bitmap.createBitmap(
            source,
            (source.width - side) / 2,
            (source.height - side) / 2,
            side,
            side,
        )
        return Bitmap.createScaledBitmap(cropped, 512, 512, true)
    }

    private fun contentIntent(): PendingIntent? {
        val launch = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            this,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }


    private fun transportIntent(action: String): PendingIntent {
        val intent = Intent(this, TransportReceiver::class.java).apply {
            this.action = action
        }
        return PendingIntent.getBroadcast(
            this,
            action.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun buildNotification(): Notification {
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_muzic)
            .setContentTitle(latestTitle)
            .setContentText(latestArtist)
            .setSubText(latestAlbum)
            .setContentIntent(contentIntent())
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setShowWhen(false)
            .setOnlyAlertOnce(true)
            .setOngoing(playing)
            .setSilent(true)

        artworkBitmap?.let { builder.setLargeIcon(it) }

        if (hasPrevious) {
            builder.addAction(
                R.drawable.ic_skip_previous,
                "Previous",
                transportIntent("previous"),
            )
        }
        builder.addAction(
            if (playing) R.drawable.ic_pause else R.drawable.ic_play,
            if (playing) "Pause" else "Play",
            transportIntent("toggle"),
        )
        if (hasNext) {
            builder.addAction(
                R.drawable.ic_skip_next,
                "Next",
                transportIntent("next"),
            )
        }

        val style = androidx.media.app.NotificationCompat.MediaStyle()
            .setMediaSession(session?.sessionToken)
            .setShowActionsInCompactView(0, 1, 2)
        builder.setStyle(style)

        return builder.build()
    }

    /**
     * The notification-list card described at [SHADE_NOTIFICATION_ID], in the
     * style the user picked: "rich" (custom layout mirroring the lock-screen
     * player) or "simple" (stock notification look). Deliberately NOT a media
     * notification either way: no MediaStyle, no session token, no transport
     * category — otherwise SystemUI would divert it out of the shade list
     * just like the main card.
     */
    private fun buildShadeCard(): Notification {
        if (shadeStyle != "rich") return buildSimpleShadeCard()
        return when {
            shadeLevel >= 2 -> buildBannerShadeCard()
            shadeLevel == 1 -> buildLinearShadeCard()
            else -> buildSimpleShadeCard()
        }
    }

    private fun shadeBaseBuilder(): NotificationCompat.Builder {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_muzic)
            .setContentTitle(latestTitle)
            .setContentText(latestArtist)
            .setContentIntent(contentIntent())
            // Hidden on a secure lock screen (the media player already shows
            // there); visible in the unlocked notification shade.
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setShowWhen(false)
            .setOnlyAlertOnce(true)
            // Ongoing so it cannot be swiped away mid-playback and stays
            // pinned in the shade; it is cancelled when playback stops.
            .setOngoing(true)
            .setAutoCancel(false)
    }

    private fun buildSimpleShadeCard(): Notification {
        val builder = shadeBaseBuilder().setSubText(latestAlbum)
        if (shadeArtwork) {
            artworkBitmap?.let { builder.setLargeIcon(it) }
        }
        if (hasPrevious && shadePrevious) {
            builder.addAction(
                R.drawable.ic_skip_previous,
                "Previous",
                transportIntent("previous"),
            )
        }
        builder.addAction(
            if (playing) R.drawable.ic_pause else R.drawable.ic_play,
            if (playing) "Pause" else "Play",
            transportIntent("toggle"),
        )
        if (hasNext && shadeNext) {
            builder.addAction(
                R.drawable.ic_skip_next,
                "Next",
                transportIntent("next"),
            )
        }
        return builder.build()
    }

    /**
     * Rich shade card, artwork-banner style: the album art spans the top of
     * the card with title/artist and the big pale play button overlaid
     * (lock-screen look), transport row on the solid card below. The root
     * is a wrap_content LinearLayout - a fixed-height full-bleed root was
     * discarded outright by some SystemUI builds.
     */
    private fun buildBannerShadeCard(): Notification {
        val collapsed = RemoteViews(packageName, R.layout.notification_shade_collapsed)
        val expanded = RemoteViews(packageName, R.layout.notification_shade_expanded)
        populateShadeViews(collapsed, expanded = false, variant = 2)
        populateShadeViews(expanded, expanded = true, variant = 2)
        return shadeBaseBuilder()
            .setCustomContentView(collapsed)
            .setCustomBigContentView(expanded)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .build()
    }

    /**
     * Rich shade card, conservative linear style (thumbnail header, controls
     * row, progress below). The automatic fallback on devices that discard
     * the banner layout.
     */
    private fun buildLinearShadeCard(): Notification {
        val collapsed = RemoteViews(packageName, R.layout.notification_shade_collapsed)
        val expanded = RemoteViews(packageName, R.layout.notification_shade_linear)
        populateShadeViews(collapsed, expanded = false, variant = 1)
        populateShadeViews(expanded, expanded = true, variant = 1)
        return shadeBaseBuilder()
            .setCustomContentView(collapsed)
            .setCustomBigContentView(expanded)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .build()
    }

    private fun populateShadeViews(views: RemoteViews, expanded: Boolean, variant: Int) {
        views.setTextViewText(R.id.shade_title, latestTitle)
        views.setTextViewText(R.id.shade_artist, latestArtist)

        val art = shadeArtworkBitmap ?: artworkBitmap
        val showArt = shadeArtwork && art != null
        if (expanded && variant == 2) {
            // Banner: always visible (branded placeholder until the real
            // artwork arrives) so the artwork header never collapses.
            // Title text is forced white here - artwork and placeholder
            // are both dark.
            views.setViewVisibility(R.id.shade_art, View.VISIBLE)
            val banner = shadeBannerBitmap ?: art
            if (shadeArtwork && banner != null) {
                views.setImageViewBitmap(R.id.shade_art, banner)
            } else {
                views.setImageViewResource(
                    R.id.shade_art,
                    R.drawable.shade_banner_placeholder,
                )
            }
            views.setTextColor(R.id.shade_title, 0xFFFFFFFF.toInt())
            views.setTextColor(R.id.shade_artist, 0xE8FFFFFF.toInt())
            // Transport glyphs overlay the banner too: force them white
            // whatever the theme (their XML tints are theme resources).
            views.setInt(R.id.shade_prev, "setColorFilter", 0xFFFFFFFF.toInt())
            views.setInt(R.id.shade_next, "setColorFilter", 0xFFFFFFFF.toInt())
        } else if (showArt) {
            views.setViewVisibility(R.id.shade_art, View.VISIBLE)
            views.setImageViewBitmap(R.id.shade_art, art)
        } else {
            views.setViewVisibility(R.id.shade_art, View.GONE)
        }

        // Banner card: dark glyph on the pale circle (lock-screen look).
        // Everywhere else: white glyph on the accent circle.
        views.setImageViewResource(
            R.id.shade_play,
            when {
                expanded && variant == 2 && playing -> R.drawable.ic_pause_dark
                expanded && variant == 2 -> R.drawable.ic_play_dark
                playing -> R.drawable.ic_pause
                else -> R.drawable.ic_play
            },
        )
        views.setOnClickPendingIntent(R.id.shade_play, transportIntent("toggle"))

        // Like the lock-screen player, previous/next are always shown
        // (subject to the user's own toggles) instead of appearing and
        // disappearing with queue position - a button that vanishes
        // mid-gesture reads as "controls are missing".
        views.setViewVisibility(
            R.id.shade_prev,
            if (shadePrevious) View.VISIBLE else View.GONE,
        )
        if (shadePrevious) {
            views.setOnClickPendingIntent(
                R.id.shade_prev,
                transportIntent("previous"),
            )
        }
        views.setViewVisibility(
            R.id.shade_next,
            if (shadeNext) View.VISIBLE else View.GONE,
        )
        if (shadeNext) {
            views.setOnClickPendingIntent(R.id.shade_next, transportIntent("next"))
        }

        if (expanded) {
            // The progress row keeps its place during track changes: while
            // the new track's duration is unknown it shows an indeterminate
            // bar instead of the whole row (and its seek buttons) vanishing
            // for a moment.
            views.setViewVisibility(
                R.id.shade_progress_row,
                if (shadeProgress) View.VISIBLE else View.GONE,
            )
            // The -10s/+10s seek taps belong to the progress row.
            views.setViewVisibility(
                R.id.shade_seek_back,
                if (shadeProgress) View.VISIBLE else View.GONE,
            )
            views.setViewVisibility(
                R.id.shade_seek_forward,
                if (shadeProgress) View.VISIBLE else View.GONE,
            )
            if (shadeProgress) {
                val position = currentPositionMs()
                if (variant == 2) {
                    // Waveform seekbar (system-player look): generated
                    // bitmap, refreshed by the 1s ticker while playing.
                    runCatching {
                        views.setImageViewBitmap(R.id.shade_wave, waveformBitmap())
                    }
                    views.setTextViewText(R.id.shade_elapsed, formatTime(position))
                    views.setTextViewText(
                        R.id.shade_duration,
                        if (durationMs > 0) formatTime(durationMs) else "--:--",
                    )
                } else if (durationMs > 0) {
                    views.setProgressBar(
                        R.id.shade_progress,
                        durationMs.coerceIn(0L, Int.MAX_VALUE.toLong()).toInt(),
                        position.coerceIn(0L, durationMs).toInt(),
                        false,
                    )
                    views.setTextViewText(R.id.shade_elapsed, formatTime(position))
                    views.setTextViewText(R.id.shade_duration, formatTime(durationMs))
                } else {
                    views.setProgressBar(R.id.shade_progress, 0, 0, true)
                    views.setTextViewText(R.id.shade_elapsed, "0:00")
                    views.setTextViewText(R.id.shade_duration, "--:--")
                }
                views.setOnClickPendingIntent(
                    R.id.shade_seek_back,
                    transportIntent("seekBack"),
                )
                views.setOnClickPendingIntent(
                    R.id.shade_seek_forward,
                    transportIntent("seekForward"),
                )
            }
            if (variant >= 1) {
                // Shuffle/repeat, mirroring the system player's control
                // row: accent tint when active, dim white when off; the
                // repeat glyph gains a "1" in repeat-one mode.
                views.setInt(
                    R.id.shade_shuffle,
                    "setColorFilter",
                    if (shuffleOn) 0xFF6C5CE7.toInt() else 0xB3FFFFFF.toInt(),
                )
                views.setOnClickPendingIntent(
                    R.id.shade_shuffle,
                    transportIntent("shuffle"),
                )
                views.setImageViewResource(
                    R.id.shade_repeat,
                    if (repeatMode == 2) {
                        R.drawable.ic_repeat_one
                    } else {
                        R.drawable.ic_repeat
                    },
                )
                views.setInt(
                    R.id.shade_repeat,
                    "setColorFilter",
                    if (repeatMode == 0) 0xB3FFFFFF.toInt() else 0xFF6C5CE7.toInt(),
                )
                views.setOnClickPendingIntent(
                    R.id.shade_repeat,
                    transportIntent("repeat"),
                )
            }
        }
        applyShadeTheme(views, expanded, variant)
    }

    /**
     * "system" leaves colours to the layout resources (which follow the
     * device's light/dark mode via values-night); an explicit user choice of
     * dark/light re-skins the card at build time.
     */
    private fun applyShadeTheme(views: RemoteViews, expanded: Boolean, variant: Int) {
        // The banner card always uses the lock-screen look (white text
        // over artwork/placeholder) regardless of theme.
        if (expanded && variant == 2) return
        val dark = when (shadeTheme) {
            "dark" -> true
            "light" -> false
            else -> return
        }
        views.setInt(
            R.id.shade_root,
            "setBackgroundResource",
            if (dark) R.drawable.shade_card_bg_dark else R.drawable.shade_card_bg_light,
        )
        val titleColor = if (dark) 0xFFFFFFFF.toInt() else 0xFF17181C.toInt()
        val subColor = if (dark) 0xFFA7AAB8.toInt() else 0xFF5F6370.toInt()
        views.setTextColor(R.id.shade_title, titleColor)
        views.setTextColor(R.id.shade_artist, subColor)
        views.setInt(R.id.shade_prev, "setColorFilter", titleColor)
        views.setInt(R.id.shade_next, "setColorFilter", titleColor)
        if (expanded) {
            views.setTextColor(R.id.shade_elapsed, subColor)
            views.setTextColor(R.id.shade_duration, subColor)
            views.setTextColor(R.id.shade_seek_back, subColor)
            views.setTextColor(R.id.shade_seek_forward, subColor)
        }
    }

    private fun formatTime(ms: Long): String {
        val totalSeconds = (ms / 1000).coerceAtLeast(0)
        val minutes = totalSeconds / 60
        val seconds = totalSeconds % 60
        return "%d:%02d".format(minutes, seconds)
    }

    /** Last shade-card gate outcome, so changes are reported once. */
    private var lastShadeGate: String? = null

    /**
     * Richness level for the shade card on this device: 2 = artwork-banner
     * layout, 1 = conservative linear rich layout, 0 = plain system card.
     * Demoted automatically (and permanently for the session) whenever a
     * level posts but does not land in the active notifications - some
     * SystemUI builds silently discard fancier custom layouts.
     */
    private var shadeLevel = 2

    /** Notification slot the currently posted shade card lives on. */
    @Volatile
    private var shadePendingId = SHADE_NOTIFICATION_ID

    /**
     * Some devices drop a freshly posted notification when the app was
     * just force-stopped or swiped away; a screen-on / unlock wake
     * re-posts the card so the shade is populated when the user looks.
     */
    private val shadeWakeReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == Intent.ACTION_SCREEN_ON ||
                intent?.action == Intent.ACTION_USER_PRESENT
            ) {
                postShadeCard()
            }
        }
    }
    private var shadeWakeRegistered = false

    /** True while a post-verification is queued. */
    private var shadeVerifyPending = false

    private fun postShadeCard() {
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val gate = when {
            !shadeEnabled -> "disabled in Settings"
            !playing && !shadeKeepOnPause -> "paused and keep-on-pause is off"
            else -> "post"
        }
        if (gate != lastShadeGate) {
            lastShadeGate = gate
            if (gate != "post") {
                errorSink?.invoke("shade card not posted: $gate")
            }
        }
        if (gate != "post") {
            runCatching {
                SHADE_LEVEL_IDS.forEach { slotId -> manager.cancel(slotId) }
            }
            return
        }
        // Device diagnostics proved a nasty failure mode: playback runs,
        // notify() returns without any exception, yet the shade card never
        // lands in the active notifications - the device's SystemUI
        // discards the custom layout. So posting is self-verifying: catch
        // Throwable, check the record stuck, and demote the richness level
        // (banner -> linear -> plain) until one lands. Every step reports
        // through errorSink so the outcome is in the diagnostics.
        //
        // Each level also posts on its OWN notification slot (1222/1212/
        // 1202): on some SystemUI builds a slot that previously held a
        // media-style card keeps diverting later custom-layout posts, so a
        // fresh slot per style generation sidesteps a poisoned slot.
        val level = if (shadeStyle == "rich") shadeLevel else 0
        val slotId = SHADE_LEVEL_IDS[level]
        shadePendingId = slotId
        try {
            manager.notify(slotId, buildShadeCard())
            shadeVerifyPending = false
            verifyShadeCardPosted(manager, level)
        } catch (error: Throwable) {
            errorSink?.invoke(
                "shade card (level $level) post threw " +
                    "${error.javaClass.simpleName}: ${error.message}",
            )
            demoteShadeLevel(level, "post threw")
        }
    }

    /**
     * Drops the shade card one richness level and reposts, unless a newer
     * post has already moved the level. At level 0 there is nowhere left
     * to demote to; that outcome is reported too.
     */
    private fun demoteShadeLevel(fromLevel: Int, reason: String) {
        if (fromLevel <= 0) {
            errorSink?.invoke(
                "shade card: even the plain style is not landing ($reason)",
            )
            return
        }
        if (shadeLevel != fromLevel) return
        shadeLevel = fromLevel - 1
        // Drop the card that never landed so the replacement style on its
        // fresh slot is the only shade card around.
        runCatching {
            getSystemService(NotificationManager::class.java)
                ?.cancel(shadePendingId)
        }
        // Persist so the next launch starts at the level this device
        // accepts instead of retrying (and briefly losing) the fancy one.
        runCatching {
            getSharedPreferences(SHADE_PREFS, Context.MODE_PRIVATE)
                .edit()
                .putInt(KEY_SHADE_LEVEL, shadeLevel)
                .apply()
        }
        errorSink?.invoke(
            "shade card: level $fromLevel $reason; switching to level $shadeLevel",
        )
        postShadeCard()
    }

    private fun verifyShadeCardPosted(manager: NotificationManager, level: Int) {
        if (shadeVerifyPending) return
        shadeVerifyPending = true
        try {
            artworkLoader.execute {
                try {
                    // SystemUI can take a moment to register a fresh card
                    // on a busy device; check twice before concluding the
                    // layout was discarded and stepping down a level.
                    var present = false
                    for (delayMs in longArrayOf(500L, 1000L)) {
                        Thread.sleep(delayMs)
                        present = manager.activeNotifications.any {
                            it.id == shadePendingId
                        }
                        if (present) break
                    }
                    shadeVerifyPending = false
                    if (!present) {
                        demoteShadeLevel(
                            level,
                            "posted but is not in active notifications afterwards",
                        )
                    }
                } catch (error: Throwable) {
                    errorSink?.invoke(
                        "shade card verify failed: " +
                            "${error.javaClass.simpleName}: ${error.message}",
                    )
                } finally {
                    shadeVerifyPending = false
                }
            }
        } catch (error: Throwable) {
            shadeVerifyPending = false
            errorSink?.invoke(
                "shade card verify could not start: " +
                    "${error.javaClass.simpleName}: ${error.message}",
            )
        }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "Playback controls for MuZic"
            setShowBadge(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            enableVibration(false)
            setSound(null, null)
        }
        manager.createNotificationChannel(channel)
    }

    override fun onDestroy() {
        stopProgressTicker()
        // Remove both cards: the media card is the foreground notification,
        // the shade card needs an explicit cancel.
        runCatching { stopForeground(true) }
        runCatching {
            val manager = getSystemService(NotificationManager::class.java)
            SHADE_LEVEL_IDS.forEach { slotId -> manager?.cancel(slotId) }
        }
        if (noisyRegistered) {
            runCatching { unregisterReceiver(noisyReceiver) }
            noisyRegistered = false
        }
        if (shadeWakeRegistered) {
            runCatching { unregisterReceiver(shadeWakeReceiver) }
            shadeWakeRegistered = false
        }
        runCatching { session?.isActive = false }
        runCatching { session?.release() }
        session = null
        artworkLoader.shutdownNow()
        super.onDestroy()
    }
}

/**
 * Turns taps on the card's buttons - and presses on a headset/Bluetooth remote -
 * into commands for the Dart player.
 */
class TransportReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        val command = when (intent?.action) {
            Intent.ACTION_MEDIA_BUTTON -> mediaKeyCommand(intent)
            "toggle" -> "toggle"
            "next" -> "next"
            "previous" -> "previous"
            "play" -> "play"
            "pause" -> "pause"
            "seekBack" -> "seekBack"
            "seekForward" -> "seekForward"
            "shuffle" -> "shuffle"
            "repeat" -> "repeat"
            else -> return
        } ?: return
        PlaybackService.commandSink?.invoke(command, null)
    }

    private fun mediaKeyCommand(intent: Intent): String? {
        val event: android.view.KeyEvent? =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_KEY_EVENT, android.view.KeyEvent::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_KEY_EVENT) as? android.view.KeyEvent
            }
        if (event == null) return null
        if (event.action != android.view.KeyEvent.ACTION_DOWN) return null
        if (event.repeatCount > 0) return null
        return when (event.keyCode) {
            android.view.KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
            android.view.KeyEvent.KEYCODE_HEADSETHOOK -> "toggle"
            android.view.KeyEvent.KEYCODE_MEDIA_PLAY -> "play"
            android.view.KeyEvent.KEYCODE_MEDIA_PAUSE -> "pause"
            android.view.KeyEvent.KEYCODE_MEDIA_STOP -> "pause"
            android.view.KeyEvent.KEYCODE_MEDIA_NEXT -> "next"
            android.view.KeyEvent.KEYCODE_MEDIA_PREVIOUS -> "previous"
            else -> null
        }
    }
}
