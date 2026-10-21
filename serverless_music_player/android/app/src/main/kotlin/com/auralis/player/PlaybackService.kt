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

        /** Set by MainActivity: receives transport commands from the card. */
        var commandSink: ((String, Double?) -> Unit)? = null

        @Volatile private var session: MediaSessionCompat? = null

        /** Exposed so the diagnostics probe can report "is a session active". */
        fun isSessionActive(): Boolean = session?.isActive == true
    }

    private val artworkLoader = Executors.newSingleThreadExecutor()
    private var artworkBitmap: Bitmap? = null
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

        publishSessionState()
        loadArtworkIfNeeded()
        // Must be foreground for the card to survive the app going to the
        // background, and for Android to treat it as a media notification.
        startForeground(NOTIFICATION_ID, buildNotification())
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
            publishSessionState()
            val manager = getSystemService(NotificationManager::class.java)
            manager?.notify(NOTIFICATION_ID, buildNotification())
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
