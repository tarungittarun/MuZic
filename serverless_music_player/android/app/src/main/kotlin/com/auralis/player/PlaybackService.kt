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
import android.media.AudioManager
import android.os.Build
import android.os.IBinder
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
 * Owns the playback card in the notification shade.
 *
 * MuZic used to rely on the audio_service plugin for this. On some devices its
 * notification was posted but never rendered as a media player, and neither its
 * channel nor its notification could be changed from the app. Building the card
 * here means every attribute that Android uses to decide "is this a media
 * player" - an active MediaSessionCompat, a MediaStyle template with the
 * session token, transport actions and artwork - is set explicitly.
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
        const val EXTRA_SHADE_ENABLED = "shadeEnabled"
        const val EXTRA_SHADE_STYLE = "shadeStyle"
        const val EXTRA_SHADE_THEME = "shadeTheme"
        const val EXTRA_SHADE_ARTWORK = "shadeArtwork"
        const val EXTRA_SHADE_PREVIOUS = "shadePrevious"
        const val EXTRA_SHADE_NEXT = "shadeNext"
        const val EXTRA_SHADE_PROGRESS = "shadeProgress"
        const val EXTRA_SHADE_KEEP_ON_PAUSE = "shadeKeepOnPause"

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
            })
            setSessionActivity(contentIntent())
            // Headset / Bluetooth buttons come through our own receiver.
            setMediaButtonReceiver(mediaButtonIntent())
            isActive = true
        }
        session = mediaSession
        if (!noisyRegistered) {
            registerReceiver(noisyReceiver, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY))
            noisyRegistered = true
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
        shadeEnabled = intent.getBooleanExtra(EXTRA_SHADE_ENABLED, shadeEnabled)
        intent.getStringExtra(EXTRA_SHADE_STYLE)?.let { shadeStyle = it }
        intent.getStringExtra(EXTRA_SHADE_THEME)?.let { shadeTheme = it }
        shadeArtwork = intent.getBooleanExtra(EXTRA_SHADE_ARTWORK, shadeArtwork)
        shadePrevious = intent.getBooleanExtra(EXTRA_SHADE_PREVIOUS, shadePrevious)
        shadeNext = intent.getBooleanExtra(EXTRA_SHADE_NEXT, shadeNext)
        shadeProgress = intent.getBooleanExtra(EXTRA_SHADE_PROGRESS, shadeProgress)
        shadeKeepOnPause =
            intent.getBooleanExtra(EXTRA_SHADE_KEEP_ON_PAUSE, shadeKeepOnPause)

        publishSessionState()
        loadArtworkIfNeeded()
        // Must be foreground for the card to survive the app going to the
        // background, and for Android to treat it as a media notification.
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
            PlaybackStateCompat.ACTION_SEEK_TO
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

    private fun loadArtworkIfNeeded() {
        val key = latestArtworkPath ?: latestArtworkUrl ?: return
        if (key == artworkKey && artworkBitmap != null) return
        artworkKey = key
        artworkLoader.execute {
            val bitmap = decodeArtwork(key)
            if (bitmap == null) return@execute
            artworkBitmap = bitmap
            shadeArtworkBitmap = Bitmap.createScaledBitmap(bitmap, 192, 192, true)
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

    private fun mediaButtonIntent(): PendingIntent {
        val intent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
            setClass(this@PlaybackService, TransportReceiver::class.java)
        }
        return PendingIntent.getBroadcast(
            this,
            1,
            intent,
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
        return if (shadeStyle == "rich") buildRichShadeCard() else buildSimpleShadeCard()
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
     * Custom-layout shade card that mirrors the lock-screen media player:
     * full-bleed artwork under a gradient scrim, title/artist bottom-left,
     * a big pale play/pause button bottom-right, previous/next and a
     * progress bar with elapsed/total times and 10-second seek buttons.
     * A RemoteViews progress bar cannot be dragged, so seeking is offered
     * as -10s/+10s taps instead of the lock screen's slider. The collapsed
     * form stays a compact artwork/title/controls strip.
     */
    private fun buildRichShadeCard(): Notification {
        val collapsed = RemoteViews(packageName, R.layout.notification_shade_collapsed)
        val expanded = RemoteViews(packageName, R.layout.notification_shade_expanded)
        populateShadeViews(collapsed, expanded = false)
        populateShadeViews(expanded, expanded = true)
        return shadeBaseBuilder()
            .setCustomContentView(collapsed)
            .setCustomBigContentView(expanded)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .build()
    }

    private fun populateShadeViews(views: RemoteViews, expanded: Boolean) {
        views.setTextViewText(R.id.shade_title, latestTitle)
        views.setTextViewText(R.id.shade_artist, latestArtist)

        val art = shadeArtworkBitmap ?: artworkBitmap
        val showArt = shadeArtwork && art != null
        if (showArt) {
            views.setViewVisibility(R.id.shade_art, View.VISIBLE)
            views.setImageViewBitmap(R.id.shade_art, art)
        } else {
            views.setViewVisibility(R.id.shade_art, View.GONE)
        }
        if (expanded) {
            // The gradient scrim only makes sense over artwork; without art
            // the card falls back to its flat themed background.
            views.setViewVisibility(
                R.id.shade_scrim,
                if (showArt) View.VISIBLE else View.GONE,
            )
        }

        // Expanded card: dark glyph on the pale circle (lock-screen look).
        // Collapsed card: white glyph on the accent circle.
        views.setImageViewResource(
            R.id.shade_play,
            when {
                expanded && playing -> R.drawable.ic_pause_dark
                expanded -> R.drawable.ic_play_dark
                playing -> R.drawable.ic_pause
                else -> R.drawable.ic_play
            },
        )
        views.setOnClickPendingIntent(R.id.shade_play, transportIntent("toggle"))

        val showPrevious = hasPrevious && shadePrevious
        views.setViewVisibility(
            R.id.shade_prev,
            if (showPrevious) View.VISIBLE else View.GONE,
        )
        if (showPrevious) {
            views.setOnClickPendingIntent(
                R.id.shade_prev,
                transportIntent("previous"),
            )
        }
        val showNext = hasNext && shadeNext
        views.setViewVisibility(
            R.id.shade_next,
            if (showNext) View.VISIBLE else View.GONE,
        )
        if (showNext) {
            views.setOnClickPendingIntent(R.id.shade_next, transportIntent("next"))
        }

        if (expanded) {
            val showProgress = shadeProgress && durationMs > 0
            views.setViewVisibility(
                R.id.shade_progress_row,
                if (showProgress) View.VISIBLE else View.GONE,
            )
            // The -10s/+10s seek taps belong to the progress row.
            views.setViewVisibility(
                R.id.shade_seek_back,
                if (showProgress) View.VISIBLE else View.GONE,
            )
            views.setViewVisibility(
                R.id.shade_seek_forward,
                if (showProgress) View.VISIBLE else View.GONE,
            )
            if (showProgress) {
                views.setProgressBar(
                    R.id.shade_progress,
                    durationMs.coerceIn(0L, Int.MAX_VALUE.toLong()).toInt(),
                    positionMs.coerceIn(0L, durationMs).toInt(),
                    false,
                )
                views.setTextViewText(R.id.shade_elapsed, formatTime(positionMs))
                views.setTextViewText(R.id.shade_duration, formatTime(durationMs))
                views.setOnClickPendingIntent(
                    R.id.shade_seek_back,
                    transportIntent("seekBack"),
                )
                views.setOnClickPendingIntent(
                    R.id.shade_seek_forward,
                    transportIntent("seekForward"),
                )
            }
        }
        applyShadeTheme(views, expanded)
    }

    /**
     * "system" leaves colours to the layout resources (which follow the
     * device's light/dark mode via values-night); an explicit user choice of
     * dark/light re-skins the card at build time.
     */
    private fun applyShadeTheme(views: RemoteViews, expanded: Boolean) {
        // Over artwork the expanded card always uses the lock-screen look
        // (white text on the gradient scrim) regardless of theme.
        if (expanded && shadeArtwork &&
            (shadeArtworkBitmap ?: artworkBitmap) != null
        ) {
            return
        }
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
            runCatching { manager.cancel(SHADE_NOTIFICATION_ID) }
            return
        }
        // Never let the shade card vanish silently: if the chosen style
        // fails to build or post (a custom RemoteViews layout can be
        // rejected on some OEM skins), fall back to the plain system-style
        // card, and report what happened so it shows up in diagnostics.
        try {
            manager.notify(SHADE_NOTIFICATION_ID, buildShadeCard())
        } catch (error: Exception) {
            errorSink?.invoke(
                "shade card ($shadeStyle) failed: ${error.javaClass.simpleName}: " +
                    "${error.message}; falling back to simple style",
            )
            try {
                manager.notify(SHADE_NOTIFICATION_ID, buildSimpleShadeCard())
            } catch (fallbackError: Exception) {
                errorSink?.invoke(
                    "shade card fallback also failed: " +
                        "${fallbackError.javaClass.simpleName}: ${fallbackError.message}",
                )
            }
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
        // Remove both cards: the media card is the foreground notification,
        // the shade card needs an explicit cancel.
        runCatching { stopForeground(true) }
        runCatching {
            getSystemService(NotificationManager::class.java)
                ?.cancel(SHADE_NOTIFICATION_ID)
        }
        if (noisyRegistered) {
            runCatching { unregisterReceiver(noisyReceiver) }
            noisyRegistered = false
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
