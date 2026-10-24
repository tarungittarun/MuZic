package com.auralis.player

import android.app.Activity
import android.app.ActivityManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Intent
import android.content.ComponentName
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSession
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.provider.Settings
import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.media.audiofx.Virtualizer
import android.media.audiofx.Visualizer
import android.content.ClipData
import android.net.Uri
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import androidx.documentfile.provider.DocumentFile
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import kotlin.math.max
import kotlin.math.sqrt

/**
 * Hosts the audio-effects channel. Attaches Android's Equalizer, BassBoost and
 * Virtualizer (virtual surround) to the playback audio session.
 *
 * Extends [AudioServiceActivity] so audio_service can own the system media
 * session (notification shade / lock screen / Quick Settings player).
 */
class MainActivity : AudioServiceActivity() {
    private var channel: MethodChannel? = null
    private var equalizer: Equalizer? = null
    private var bassBoost: BassBoost? = null
    private var virtualizer: Virtualizer? = null
    private var localFilesChannel: MethodChannel? = null
    private var pendingLocalResult: MethodChannel.Result? = null
    private var pendingFolderResult: MethodChannel.Result? = null
    private var visualizerChannel: EventChannel? = null
    private var visualizerCapture: Visualizer? = null
    private var visualizerSink: EventChannel.EventSink? = null
    private var visualizerHandler: Handler? = null
    private var systemChannel: MethodChannel? = null
    private var videoExportChannel: MethodChannel? = null
    private val videoExportCancel = java.util.concurrent.atomic.AtomicBoolean(false)
    @Volatile private var videoExportRunning = false
    private var videoProgressSink: EventChannel.EventSink? = null

    private companion object {
        const val PICK_AUDIO_REQUEST_CODE = 4213
        const val PICK_DOWNLOADS_FOLDER_REQUEST_CODE = 4214

        /**
         * Channel the system media player posts on. Created by
         * just_audio_background with the same id passed to
         * JustAudioBackground.init in main.dart; diagnostics only reads it.
         */
        const val AUDIO_CHANNEL_ID = "com.auralis.player.audio"
        const val AUDIO_SERVICE_CLASS = "com.ryanheise.audioservice.AudioService"
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        preferHighestRefreshRate()
    }

    /// Ask Android to render MuZic at the panel's fastest supported mode
    /// (90/120 Hz where available) instead of lingering at a low default.
    private fun preferHighestRefreshRate() {
        try {
            val activeDisplay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                display
            } else {
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay
            } ?: return
            val current = activeDisplay.mode
            val fastest = activeDisplay.supportedModes
                .filter { mode ->
                    mode.physicalWidth == current.physicalWidth &&
                        mode.physicalHeight == current.physicalHeight
                }
                .maxByOrNull { mode -> mode.refreshRate } ?: return
            val attributes = window.attributes
            attributes.preferredDisplayModeId = fastest.modeId
            attributes.preferredRefreshRate = fastest.refreshRate
            window.attributes = attributes
        } catch (ignored: Exception) {
            // Refresh-rate preference is best-effort; rendering still works
            // at the system default if a device rejects the request.
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "music_player/audio_effects",
        )
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "apply" -> {
                    val sessionId = call.argument<Int>("sessionId") ?: 0
                    val virtualizerEnabled = call.argument<Boolean>("virtualizerEnabled") ?: false
                    val virtualizerStrength = call.argument<Int>("virtualizerStrength") ?: 60
                    val bassEnabled = call.argument<Boolean>("bassEnabled") ?: false
                    val bassStrength = call.argument<Int>("bassStrength") ?: 50
                    val eqEnabled = call.argument<Boolean>("eqEnabled") ?: false
                    val eqPreset = call.argument<Int>("eqPreset") ?: 0
                    val ok = applyEffects(
                        sessionId,
                        virtualizerEnabled,
                        virtualizerStrength,
                        bassEnabled,
                        bassStrength,
                        eqEnabled,
                        eqPreset,
                    )
                    result.success(ok)
                }
                "release" -> {
                    releaseEffects()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        localFilesChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "music_player/local_files",
        )
        localFilesChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "pickAudioFiles" -> pickAudioFiles(result)
                "pickDownloadsFolder" -> pickDownloadsFolder(result)
                "copyToDownloadsFolder" -> copyToDownloadsFolder(
                    call.argument<String>("folderUri"),
                    call.argument<String>("sourcePath"),
                    call.argument<String>("fileName"),
                    call.argument<String>("mimeType"),
                    result,
                )
                "contentFileExists" -> result.success(
                    contentFileExists(call.argument<String>("path")),
                )
                "deleteContentFile" -> deleteContentFile(call.argument<String>("path"), result)
                "shareFile" -> shareFile(
                    call.argument<String>("path"),
                    call.argument<String>("fileName"),
                    result,
                )
                "shareText" -> shareText(
                    call.argument<String>("subject") ?: "MuZic diagnostics",
                    call.argument<String>("text") ?: "",
                    result,
                )
                else -> result.notImplemented()
            }
        }

        systemChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "music_player/system",
        )
        systemChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "notify" -> {
                    postSimpleNotification(
                        call.argument<Int>("id") ?: 1001,
                        call.argument<String>("title") ?: "MuZic",
                        call.argument<String>("body") ?: "",
                        call.argument<String>("channelId") ?: "muzic_alerts",
                        call.argument<String>("channelName") ?: "MuZic alerts",
                    )
                    result.success(true)
                }
                "cancel" -> {
                    val manager = getSystemService(NotificationManager::class.java)
                    manager?.cancel(call.argument<Int>("id") ?: 1001)
                    result.success(true)
                }
                "activeNotifications" -> result.success(activeNotifications())
                "openSoundSettings" -> result.success(openSoundSettings())
                "mediaNotificationDiagnostics" ->
                    result.success(mediaNotificationDiagnostics())
                "appTaskCount" -> {
                    val manager = getSystemService(ActivityManager::class.java)
                    result.success(manager?.appTasks?.size ?: 0)
                }
                "saveText" -> result.success(
                    saveTextToDownloads(
                        call.argument<String>("fileName") ?: "muzic_report.txt",
                        call.argument<String>("text") ?: "",
                    ),
                )
                else -> result.notImplemented()
            }
        }

        videoExportChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "music_player/video_export",
        )
        videoExportChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "export" -> exportVideo(call, result)
                "cancelExport" -> {
                    videoExportCancel.set(true)
                    result.success(true)
                }
                "exportRunning" -> result.success(videoExportRunning)
                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "music_player/video_export_progress",
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                videoProgressSink = events
            }

            override fun onCancel(arguments: Any?) {
                videoProgressSink = null
            }
        })

        visualizerChannel = EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "music_player/visualizer",
        )
        visualizerChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                visualizerSink = events
                startVisualizer(arguments as? Int ?: 0)
            }

            override fun onCancel(arguments: Any?) {
                stopVisualizer()
                visualizerSink = null
            }
        })
    }

    private fun startVisualizer(sessionId: Int) {
        stopVisualizer()
        if (sessionId == 0) {
            visualizerSink?.error("no_session", "No playback session is active yet.", null)
            return
        }
        try {
            val capture = Visualizer(sessionId)
            val range = Visualizer.getCaptureSizeRange()
            capture.captureSize = max(range[0], 512).coerceAtMost(range[1])
            val handler = Handler(Looper.getMainLooper())
            visualizerHandler = handler
            capture.setDataCaptureListener(
                object : Visualizer.OnDataCaptureListener {
                    override fun onWaveFormDataCapture(
                        visualizer: Visualizer?,
                        waveform: ByteArray?,
                        samplingRate: Int,
                    ) {
                        if (waveform == null || waveform.isEmpty()) return
                        val bands = 18
                        val perBand = max(1, waveform.size / bands)
                        val values = ArrayList<Double>(bands)
                        for (band in 0 until bands) {
                            var squaredTotal = 0.0
                            val start = band * perBand
                            val end = minOf(waveform.size, start + perBand)
                            if (start >= end) {
                                values.add(0.0)
                                continue
                            }
                            for (index in start until end) {
                                // Visualizer waveform samples are unsigned
                                // bytes centred on 128 (silence), not signed
                                // Kotlin bytes. RMS keeps each band responsive
                                // to actual musical energy instead of making
                                // near-silence look full-scale.
                                val centred = (waveform[index].toInt() and 0xFF) - 128
                                squaredTotal += centred * centred.toDouble()
                            }
                            val rms = sqrt(squaredTotal / (end - start))
                            val level = ((rms - 3.0) / 76.0).coerceIn(0.0, 1.0)
                            values.add(level)
                        }
                        handler.post { visualizerSink?.success(values) }
                    }

                    override fun onFftDataCapture(
                        visualizer: Visualizer?,
                        fft: ByteArray?,
                        samplingRate: Int,
                    ) = Unit
                },
                Visualizer.getMaxCaptureRate() / 2,
                true,
                false,
            )
            capture.enabled = true
            visualizerCapture = capture
        } catch (e: Exception) {
            visualizerSink?.error("visualizer_failed", e.message, null)
        }
    }

    private fun stopVisualizer() {
        try {
            visualizerCapture?.enabled = false
            visualizerCapture?.release()
        } catch (e: Exception) {
        }
        visualizerCapture = null
        visualizerHandler?.removeCallbacksAndMessages(null)
        visualizerHandler = null
    }

    /**
     * Full chain report for the media notification: is the app allowed to post
     * at all, does the playback channel exist and what importance does it have,
     * is the audio service actually running, and what is currently posted.
     *
     * Any "no card on screen" report can be narrowed down from this alone.
     */
    private fun mediaNotificationDiagnostics(): Map<String, Any?> {
        val manager = getSystemService(NotificationManager::class.java)
        val notificationsEnabled = manager?.areNotificationsEnabled() ?: false
        val playbackChannelId = AUDIO_CHANNEL_ID
        val channel = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager?.getNotificationChannel(playbackChannelId)
        } else {
            null
        }
        val channelImportance = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            channel?.importance ?: -1
        } else {
            -2
        }
        val appChannelCount = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager?.notificationChannels?.size ?: 0
        } else {
            -1
        }

        val serviceDeclared = try {
            val info = packageManager.getServiceInfo(
                android.content.ComponentName(packageName, AUDIO_SERVICE_CLASS),
                0,
            )
            info.enabled
        } catch (e: Exception) {
            false
        }

        val posted = activeNotifications().map { entry ->
            "${entry["channelId"]}#${entry["id"]}${if (entry["ongoing"] == true) " ongoing" else ""}"
        }

        val mediaSessionsForDiagnostics = activeMediaSessionDetails()
        val tokenSessionForDiagnostics = mediaSessionTokenDetails()

        val smallIconValid = try {
            getDrawable(R.drawable.ic_stat_muzic) != null
        } catch (e: Exception) {
            false
        }

        return mapOf(
            "sdkInt" to Build.VERSION.SDK_INT,
            "manufacturer" to (Build.MANUFACTURER ?: ""),
            "model" to (Build.MODEL ?: ""),
            "notificationsEnabled" to notificationsEnabled,
            "postPermission" to (
                checkSelfPermission("android.permission.POST_NOTIFICATIONS") ==
                    android.content.pm.PackageManager.PERMISSION_GRANTED
                ),
            "playbackChannelExists" to (channel != null),
            "playbackChannelImportance" to channelImportance,
            "playbackChannelLockscreenVisibility" to (
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    channel?.lockscreenVisibility ?: -1
                } else {
                    -2
                }
            ),
            "appChannelCount" to appChannelCount,
            "audioServiceDeclared" to serviceDeclared,
            "smallIconResolves" to smallIconValid,
            "mediaSessionActive" to (
                isServiceRunning(AUDIO_SERVICE_CLASS) ||
                    posted.any { it.startsWith(AUDIO_CHANNEL_ID) }
                ),
            "posted" to posted,
            "postedCount" to posted.size,
            "activeMediaSessions" to mediaSessionsForDiagnostics.count {
                !it.startsWith("error=")
            },
            "mediaSessionDetails" to mediaSessionsForDiagnostics,
            "sessionTokenDetails" to tokenSessionForDiagnostics,
        )
    }

    /**
     * Opens Android's Media controls settings (Pin media player / show on
     * lock screen), falling back to Sound settings, then Settings.
     */
    private fun openSoundSettings(): Boolean {
        val candidates = listOf(
            Intent("android.settings.ACTION_MEDIA_CONTROLS_SETTINGS"),
            Intent().setClassName(
                "com.android.settings",
                "com.android.settings.Settings\$MediaControlsSettingsActivity",
            ),
            Intent(Settings.ACTION_SOUND_SETTINGS),
            Intent(Settings.ACTION_SETTINGS),
        )
        for (candidate in candidates) {
            try {
                candidate.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(candidate)
                return true
            } catch (ignored: Exception) {
                // Try the next surface.
            }
        }
        return false
    }

    /**
     * What Android's session manager can actually see. Unlike the posted
     * notification check, this confirms whether SystemUI has an active
     * media session it can render in Quick Settings / on the lock screen.
     */
    private fun activeMediaSessionDetails(): List<String> {
        return try {
            val manager = getSystemService(MediaSessionManager::class.java)
                ?: return emptyList()
            val component = ComponentName(this, MainActivity::class.java)
            manager.getActiveSessions(component)
                .filter { it.packageName == packageName }
                .map { controller ->
                    val metadata = controller.metadata
                    val state = controller.playbackState?.state
                    val stateName = when (state) {
                        PlaybackState.STATE_PLAYING -> "playing"
                        PlaybackState.STATE_PAUSED -> "paused"
                        PlaybackState.STATE_BUFFERING -> "buffering"
                        PlaybackState.STATE_NONE -> "none"
                        null -> "unknown"
                        else -> "state=$state"
                    }
                    val title = metadata?.getString(MediaMetadata.METADATA_KEY_TITLE) ?: ""
                    val artist = metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: ""
                    val duration = metadata?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: -1L
                    "pkg=${controller.packageName} state=$stateName title=$title artist=$artist durationMs=$duration"
                }
        } catch (e: Exception) {
            listOf("error=${e.javaClass.simpleName}:${e.message ?: ""}")
        }
    }

    /**
     * Reads MuZic's own media session through the token carried by its
     * posted notification. Unlike getActiveSessions(), this needs no
     * notification-listener permission, so it can prove whether Android
     * can read playing state and metadata from the exact session that
     * SystemUI would render.
     */
    private fun mediaSessionTokenDetails(): List<String> {
        val manager = getSystemService(NotificationManager::class.java)
            ?: return listOf("error=no NotificationManager")
        return try {
            val status = manager.activeNotifications.firstOrNull {
                it.notification.extras.containsKey(Notification.EXTRA_MEDIA_SESSION)
            } ?: return listOf("error=no media notification posted")
            val extras = status.notification.extras
            val token = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                extras.getParcelable(
                    Notification.EXTRA_MEDIA_SESSION,
                    MediaSession.Token::class.java,
                )
            } else {
                @Suppress("DEPRECATION")
                extras.getParcelable(Notification.EXTRA_MEDIA_SESSION)
            } ?: return listOf("error=media session token missing")
            val controller = MediaController(this, token)
            val metadata = controller.metadata
            val playbackState = controller.playbackState
            val stateName = when (playbackState?.state) {
                PlaybackState.STATE_PLAYING -> "playing"
                PlaybackState.STATE_PAUSED -> "paused"
                PlaybackState.STATE_BUFFERING -> "buffering"
                PlaybackState.STATE_CONNECTING -> "connecting"
                PlaybackState.STATE_NONE -> "none"
                null -> "unknown"
                else -> "state=${playbackState?.state}"
            }
            val title = metadata?.getString(MediaMetadata.METADATA_KEY_TITLE) ?: ""
            val artist = metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: ""
            val duration = metadata?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: -1L
            val style = status.notification.extras
                .getString(Notification.EXTRA_TEMPLATE) ?: "none"
            listOf(
                "pkg=${controller.packageName} state=$stateName " +
                    "actions=${playbackState?.actions ?: -1L} " +
                    "flags=${controller.flags} " +
                    "sessionActivity=${controller.sessionActivity != null} " +
                    "style=$style title=$title artist=$artist durationMs=$duration",
            )
        } catch (e: Exception) {
            listOf("error=${e.javaClass.simpleName}:${e.message ?: ""}")
        }
    }

    /** True when a service with this class name is currently started. */
    private fun isServiceRunning(className: String): Boolean {
        return try {
            val manager = getSystemService(android.app.ActivityManager::class.java)
                ?: return false
            val services = manager.getRunningServices(Int.MAX_VALUE)
            services.any { it.service.className == className }
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Diagnostics: what Android currently shows for MuZic. If playback is
     * running but this is empty, the media notification was rejected (usually
     * an invalid small icon or a blocked channel).
     */
    private fun activeNotifications(): List<Map<String, Any?>> {
        val manager = getSystemService(NotificationManager::class.java)
            ?: return emptyList()
        return try {
            manager.activeNotifications.map { status ->
                mapOf(
                    "id" to status.id,
                    "channelId" to status.notification.channelId,
                    "ongoing" to status.notification.flags.let { flags ->
                        (flags and Notification.FLAG_ONGOING_EVENT) != 0
                    },
                    // True when the notification carries a media session
                    // token - the thing SystemUI needs before it will render
                    // a media player in the shade / Quick Settings.
                    "mediaSession" to status.notification.extras.containsKey(
                        Notification.EXTRA_MEDIA_SESSION,
                    ),
                    "category" to status.notification.category,
                    "visibility" to status.notification.visibility,
                    "title" to status.notification.extras.getCharSequence(
                        Notification.EXTRA_TITLE,
                    )?.toString(),
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun postSimpleNotification(
        id: Int,
        title: String,
        body: String,
        channelId: String,
        channelName: String,
    ) {
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                channelName,
                NotificationManager.IMPORTANCE_HIGH,
            ).apply { description = "MuZic playback alerts" }
            manager.createNotificationChannel(channel)
        }
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = PendingIntent.getActivity(
            this,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setSmallIcon(R.drawable.ic_stat_muzic)
            .setContentIntent(pending)
            .setAutoCancel(true)
        manager.notify(id, builder.build())
    }

    /** Saves a text report into the shared Downloads collection. */
    private fun saveTextToDownloads(fileName: String, text: String): String? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                    put(MediaStore.Downloads.MIME_TYPE, "text/plain")
                    put(
                        MediaStore.Downloads.RELATIVE_PATH,
                        "${Environment.DIRECTORY_DOWNLOADS}/MuZic",
                    )
                    put(MediaStore.Downloads.IS_PENDING, 1)
                }
                val uri = contentResolver.insert(
                    MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                    values,
                ) ?: return null
                contentResolver.openOutputStream(uri)?.use { output ->
                    output.write(text.toByteArray())
                }
                values.clear()
                values.put(MediaStore.Downloads.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
                "Downloads/MuZic/$fileName"
            } else {
                val directory = File(
                    Environment.getExternalStoragePublicDirectory(
                        Environment.DIRECTORY_DOWNLOADS,
                    ),
                    "MuZic",
                )
                if (!directory.exists()) directory.mkdirs()
                val file = File(directory, fileName)
                file.writeText(text)
                file.absolutePath
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun exportVideo(call: MethodCall, result: MethodChannel.Result) {
        if (videoExportRunning) {
            result.error(
                "busy",
                "A video export is already running.",
                mapOf("stage" to "queued_export", "progress" to 0.0, "elapsedMs" to 0),
            )
            return
        }
        videoExportCancel.set(false)
        val requestedAudioPath = call.argument<String>("audioPath")?.trim()
        val artworkPath = call.argument<String>("artworkPath")
        val title = call.argument<String>("title") ?: "MuZic"
        val artist = call.argument<String>("artist") ?: ""
        val durationMs = call.argument<Int>("durationMs")?.toLong() ?: 0L
        val outputName = call.argument<String>("outputName") ?: "muzic_video"
        val outputFolderUri = call.argument<String>("outputFolderUri")
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
        val lyrics = parseLyrics(call.argument<String>("lyrics") ?: "[]")
        if (requestedAudioPath.isNullOrEmpty()) {
            result.error(
                "missing_audio",
                "The audio file is not available.",
                mapOf(
                    "stage" to "resolve_source",
                    "progress" to 0.0,
                    "progressPercent" to 0,
                    "elapsedMs" to 0,
                ),
            )
            return
        }
        // Claim the job before starting its worker so a rapid second tap cannot
        // start a second encoder before the background thread gets scheduled.
        videoExportRunning = true
        // Keep the CPU-bound render off the UI/platform threads so the app
        // stays usable while it runs. SAF downloads arrive as content:// URIs;
        // stage those in persistent private storage rather than cache, which
        // Android may reclaim during a long export. Also accept file:// paths
        // from local-file providers.
        Thread({
            var temporaryAudio: File? = null
            var exportStage = "resolve_source"
            var exportProgress = 0.0
            val exportStartedAt = SystemClock.elapsedRealtime()
            val audioUri = Uri.parse(requestedAudioPath)
            val audioSourceType = when (audioUri.scheme?.lowercase()) {
                "content" -> "content_uri"
                "file" -> "file_uri"
                else -> "file_path"
            }
            fun diagnosticDetails(): Map<String, Any> = mapOf(
                "stage" to exportStage,
                "progress" to exportProgress,
                "progressPercent" to (exportProgress * 100.0).toInt(),
                "elapsedMs" to (SystemClock.elapsedRealtime() - exportStartedAt),
                "sourceType" to audioSourceType,
            )
            try {
                val audioFile = when (audioSourceType) {
                    "content_uri" -> {
                        exportStage = "prepare_private_audio"
                        val tempDirectory = File(filesDir, "muzic_video_audio")
                        if (!tempDirectory.exists() && !tempDirectory.mkdirs() && !tempDirectory.exists()) {
                            throw IllegalStateException("Could not prepare private video audio storage.")
                        }
                        val staged = File.createTempFile("audio_", ".cache", tempDirectory)
                        temporaryAudio = staged
                        exportStage = "copy_content_uri"
                        val input = contentResolver.openInputStream(audioUri)
                            ?: throw java.io.FileNotFoundException("The selected audio URI is unavailable.")
                        input.use { source ->
                            FileOutputStream(staged).use { output ->
                                val buffer = ByteArray(64 * 1024)
                                while (true) {
                                    if (videoExportCancel.get()) throw VideoExporter.Cancelled()
                                    val count = source.read(buffer)
                                    if (count < 0) break
                                    output.write(buffer, 0, count)
                                }
                            }
                        }
                        staged
                    }
                    "file_uri" -> {
                        exportStage = "resolve_file_uri"
                        File(audioUri.path ?: throw java.io.FileNotFoundException(
                            "The selected file URI is unavailable.",
                        ))
                    }
                    else -> File(requestedAudioPath)
                }
                exportStage = "validate_audio"
                if (!audioFile.exists() || !audioFile.isFile ||
                    !audioFile.canRead() || audioFile.length() <= 0L
                ) {
                    throw java.io.FileNotFoundException("The audio file is not available.")
                }
                if (videoExportCancel.get()) throw VideoExporter.Cancelled()
                exportStage = "media_export"
                var lastProgressAt = 0L
                val path = VideoExporter(this).export(
                    audioPath = audioFile.absolutePath,
                    artworkPath = artworkPath,
                    title = title,
                    artist = artist,
                    lyrics = lyrics,
                    durationMsHint = durationMs,
                    outputName = outputName,
                    outputFolderUri = outputFolderUri,
                    isCancelled = { videoExportCancel.get() },
                    onStage = { stage -> exportStage = stage },
                ) { progress ->
                    val now = SystemClock.elapsedRealtime()
                    val boundedProgress = progress.coerceIn(0.0, 1.0)
                    exportProgress = boundedProgress
                    // The renderer reports every frame. Sending a platform
                    // message for each one adds needless UI-thread work, so
                    // update at most 4 times per second, plus the final value.
                    if (boundedProgress >= 1.0 || now - lastProgressAt >= 250L) {
                        lastProgressAt = now
                        runOnUiThread { videoProgressSink?.success(boundedProgress) }
                    }
                }
                runOnUiThread { result.success(path) }
            } catch (e: VideoExporter.Cancelled) {
                runOnUiThread {
                    result.error("cancelled", "Export stopped.", diagnosticDetails())
                }
            } catch (_: VideoExporter.MissingAudio) {
                runOnUiThread {
                    result.error(
                        "missing_audio",
                        "The audio file is not available.",
                        diagnosticDetails(),
                    )
                }
            } catch (e: java.io.FileNotFoundException) {
                runOnUiThread {
                    if (exportStage == "copy_content_uri" ||
                        exportStage == "resolve_file_uri" ||
                        exportStage == "validate_audio"
                    ) {
                        result.error(
                            "missing_audio",
                            "The audio file is not available.",
                            diagnosticDetails(),
                        )
                    } else {
                        result.error(
                            "export_failed",
                            e.message ?: "Could not prepare the video export.",
                            diagnosticDetails(),
                        )
                    }
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error(
                        "export_failed",
                        e.message ?: "Video export failed.",
                        diagnosticDetails(),
                    )
                }
            } finally {
                temporaryAudio?.delete()
                videoExportRunning = false
            }
        }, "muzic-video-export").start()
    }

    private fun shareText(subject: String, text: String, result: MethodChannel.Result) {
        try {
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_SUBJECT, subject)
                putExtra(Intent.EXTRA_TEXT, text)
            }
            startActivity(Intent.createChooser(intent, "Share diagnostics report"))
            result.success(true)
        } catch (e: Exception) {
            result.error("share_failed", e.message, null)
        }
    }

    /**
     * Shares a downloaded song without touching its bytes: the file is
     * copied as-is into the share cache and handed to Android's chooser
     * through FileProvider, so the receiver gets the original quality.
     */
    private fun shareUri(uri: Uri, result: MethodChannel.Result) {
        try {
            val mime = contentResolver.getType(uri) ?: "audio/*"
            val displayName = queryDisplayName(uri) ?: "MuZic song"
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = mime
                putExtra(Intent.EXTRA_STREAM, uri)
                putExtra(Intent.EXTRA_TITLE, displayName)
                clipData = ClipData.newRawUri("", uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(intent, "Share song"))
            result.success(true)
        } catch (e: Exception) {
            result.error("share_failed", e.message, null)
        }
    }

    private fun shareFile(path: String?, fileName: String?, result: MethodChannel.Result) {
        if (!path.isNullOrBlank() && path.startsWith("content://")) {
            shareUri(Uri.parse(path), result)
            return
        }
        try {
            if (path.isNullOrBlank()) {
                result.error("missing_file", "The downloaded file is missing.", null)
                return
            }
            val source = File(path)
            if (!source.exists() || source.length() == 0L) {
                result.error("missing_file", "The downloaded file is missing.", null)
                return
            }
            val shareDirectory = File(cacheDir, "muzic_shares")
            if (!shareDirectory.exists()) shareDirectory.mkdirs()
            val safeName = (fileName?.takeIf { it.isNotBlank() } ?: source.name)
                .replace(Regex("[\\/:*?\"<>|]"), "")
                .trim()
                .ifBlank { source.name }
            val sharedFile = File(shareDirectory, safeName)
            if (source.canonicalFile != sharedFile.canonicalFile) {
                source.inputStream().use { input ->
                    FileOutputStream(sharedFile).use { output -> input.copyTo(output) }
                }
            }
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                sharedFile,
            )
            val extension = sharedFile.extension.lowercase()
            val mime = MimeTypeMap.getSingleton()
                .getMimeTypeFromExtension(extension) ?: "audio/*"
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = mime
                putExtra(Intent.EXTRA_STREAM, uri)
                putExtra(Intent.EXTRA_TITLE, safeName)
                clipData = ClipData.newRawUri("", uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(intent, "Share song"))
            result.success(true)
        } catch (e: Exception) {
            result.error("share_failed", e.message, null)
        }
    }


    private fun pickDownloadsFolder(result: MethodChannel.Result) {
        if (pendingFolderResult != null) {
            result.error("picker_busy", "A folder picker is already open", null)
            return
        }
        try {
            pendingFolderResult = result
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
                )
            }
            startActivityForResult(intent, PICK_DOWNLOADS_FOLDER_REQUEST_CODE)
        } catch (e: Exception) {
            pendingFolderResult = null
            result.error("picker_unavailable", e.message, null)
        }
    }

    private fun copyToDownloadsFolder(
        folderUriValue: String?,
        sourcePath: String?,
        fileName: String?,
        mimeType: String?,
        result: MethodChannel.Result,
    ) {
        val treeUri = folderUriValue?.let { Uri.parse(it) }
        val source = sourcePath?.let(::File)
        val safeName = (fileName ?: "track").replace(Regex("[\\\\/:*?\"<>|]"), "_")
        if (treeUri == null || source == null || !source.exists()) {
            result.error("invalid_copy", "The folder or download file was not found", null)
            return
        }
        Thread {
            try {
                val parent = DocumentFile.fromTreeUri(this, treeUri)
                if (parent == null || !parent.canWrite()) {
                    runOnUiThread {
                        result.error("folder_unwritable", "The selected folder cannot be written to", null)
                    }
                    return@Thread
                }
                val extension = safeName.substringAfterLast('.', "")
                val baseName = if (extension.isEmpty()) {
                    safeName
                } else {
                    safeName.substringBeforeLast('.')
                }
                var uniqueName = safeName
                var suffix = 2
                while (parent.findFile(uniqueName) != null) {
                    uniqueName = if (extension.isEmpty()) {
                        "$baseName ($suffix)"
                    } else {
                        "$baseName ($suffix).$extension"
                    }
                    suffix++
                }
                val target = parent.createFile(mimeType ?: "audio/mpeg", uniqueName)
                val outputUri = target?.uri
                if (outputUri == null) {
                    runOnUiThread {
                        result.error("copy_failed", "Android could not create the file", null)
                    }
                    return@Thread
                }
                FileInputStream(source).use { input ->
                    contentResolver.openOutputStream(outputUri)?.use { output ->
                        input.copyTo(output)
                    } ?: throw IllegalStateException("Could not open the destination file")
                }
                runOnUiThread { result.success(outputUri.toString()) }
            } catch (e: Exception) {
                runOnUiThread { result.error("copy_failed", e.message, null) }
            }
        }.start()
    }

    private fun contentFileExists(path: String?): Boolean {
        if (path.isNullOrBlank() || !path.startsWith("content://")) return false
        return try {
            contentResolver.openFileDescriptor(Uri.parse(path), "r")?.use { true } ?: false
        } catch (ignored: Exception) {
            false
        }
    }

    private fun deleteContentFile(path: String?, result: MethodChannel.Result) {
        if (path.isNullOrBlank() || !path.startsWith("content://")) {
            result.success(false)
            return
        }
        Thread {
            val deleted = try {
                DocumentsContract.deleteDocument(contentResolver, Uri.parse(path))
            } catch (e: Exception) {
                try {
                    contentResolver.delete(Uri.parse(path), null, null) > 0
                } catch (ignored: Exception) {
                    false
                }
            }
            runOnUiThread { result.success(deleted) }
        }.start()
    }

    private fun pickAudioFiles(result: MethodChannel.Result) {
        if (pendingLocalResult != null) {
            result.error("busy", "A file picker is already open.", null)
            return
        }
        pendingLocalResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "audio/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            startActivityForResult(intent, PICK_AUDIO_REQUEST_CODE)
        } catch (e: Exception) {
            pendingLocalResult = null
            result.error("picker_unavailable", e.message, null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == PICK_DOWNLOADS_FOLDER_REQUEST_CODE) {
            val pendingFolder = pendingFolderResult
            pendingFolderResult = null
            val treeUri = if (resultCode == Activity.RESULT_OK) data?.data else null
            if (pendingFolder == null || treeUri == null) {
                pendingFolder?.success(null)
                return
            }
            try {
                val flags = (data?.flags ?: 0) and
                    (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                val persistFlags = if (flags != 0) flags else
                    (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                contentResolver.takePersistableUriPermission(treeUri, persistFlags)
            } catch (ignored: Exception) {
                // The grant may still work for this session on some OEM builds.
            }
            val document = DocumentFile.fromTreeUri(this, treeUri)
            pendingFolder.success(
                mapOf(
                    "uri" to treeUri.toString(),
                    "name" to (document?.name ?: "Selected folder"),
                ),
            )
            return
        }
        if (requestCode != PICK_AUDIO_REQUEST_CODE) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val pending = pendingLocalResult
        pendingLocalResult = null
        if (pending == null) return
        if (resultCode != Activity.RESULT_OK || data == null) {
            pending.success(emptyList<Map<String, Any>>())
            return
        }
        val uris = ArrayList<Uri>()
        val clip = data.clipData
        if (clip != null) {
            for (index in 0 until clip.itemCount) {
                clip.getItemAt(index)?.uri?.let { uris.add(it) }
            }
        }
        data.data?.let { uris.add(it) }
        if (uris.isEmpty()) {
            pending.success(emptyList<Map<String, Any>>())
            return
        }
        Thread {
            val imported = ArrayList<Map<String, Any>>()
            try {
                val directory = File(filesDir, "imported_music")
                if (!directory.exists()) directory.mkdirs()
                for (uri in uris) {
                    val displayName = queryDisplayName(uri) ?: "track_${System.currentTimeMillis()}"
                    val safeName = displayName.replace(Regex("[^A-Za-z0-9._ -]"), "_")
                    val target = uniqueFile(directory, safeName)
                    contentResolver.openInputStream(uri)?.use { input ->
                        FileOutputStream(target).use { output -> input.copyTo(output) }
                    } ?: continue
                    imported.add(
                        mapOf(
                            "name" to displayName,
                            "path" to target.absolutePath,
                            "sizeBytes" to target.length(),
                        ),
                    )
                }
                runOnUiThread { pending.success(imported) }
            } catch (e: Exception) {
                runOnUiThread { pending.error("import_failed", e.message, null) }
            }
        }.start()
    }

    private fun queryDisplayName(uri: Uri): String? {
        return try {
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0 && cursor.moveToFirst()) cursor.getString(index) else null
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun uniqueFile(directory: File, name: String): File {
        var candidate = File(directory, name)
        if (!candidate.exists()) return candidate
        val dot = name.lastIndexOf('.')
        val base = if (dot > 0) name.substring(0, dot) else name
        val extension = if (dot > 0) name.substring(dot) else ""
        var counter = 1
        while (candidate.exists()) {
            candidate = File(directory, "${base}_$counter$extension")
            counter += 1
        }
        return candidate
    }

    private fun applyEffects(
        sessionId: Int,
        virtualizerEnabled: Boolean,
        virtualizerStrength: Int,
        bassEnabled: Boolean,
        bassStrength: Int,
        eqEnabled: Boolean,
        eqPreset: Int,
    ): Boolean {
        releaseEffects()
        if (sessionId == 0) return false
        var ok = true
        try {
            if (eqEnabled) {
                val eq = Equalizer(0, sessionId)
                eq.enabled = true
                try {
                    eq.usePreset(eqPreset.coerceIn(0, 9).toShort())
                } catch (e: Exception) {
                    ok = false
                }
                equalizer = eq
            }
            if (bassEnabled) {
                val bb = BassBoost(0, sessionId)
                bb.enabled = true
                if (bb.strengthSupported) {
                    try {
                        bb.setStrength((bassStrength.coerceIn(0, 100) * 10).toShort())
                    } catch (e: Exception) {
                        ok = false
                    }
                }
                bassBoost = bb
            }
            if (virtualizerEnabled) {
                val vz = Virtualizer(0, sessionId)
                vz.enabled = true
                if (vz.strengthSupported) {
                    try {
                        vz.setStrength(
                            (virtualizerStrength.coerceIn(0, 100) * 10).toShort(),
                        )
                    } catch (e: Exception) {
                        ok = false
                    }
                }
                virtualizer = vz
            }
        } catch (e: Exception) {
            ok = false
        }
        return ok
    }

    private fun releaseEffects() {
        try {
            equalizer?.release()
        } catch (e: Exception) {
        }
        try {
            bassBoost?.release()
        } catch (e: Exception) {
        }
        try {
            virtualizer?.release()
        } catch (e: Exception) {
        }
        equalizer = null
        bassBoost = null
        virtualizer = null
    }

    override fun onDestroy() {
        stopVisualizer()
        releaseEffects()
        super.onDestroy()
    }
}
