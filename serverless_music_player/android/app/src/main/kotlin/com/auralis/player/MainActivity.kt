package com.auralis.player

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Intent
import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.media.audiofx.Virtualizer
import android.media.audiofx.Visualizer
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import kotlin.math.abs
import kotlin.math.max

/**
 * Hosts the audio-effects channel. Attaches Android's Equalizer, BassBoost and
 * Virtualizer (virtual surround) to the playback audio session.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var equalizer: Equalizer? = null
    private var bassBoost: BassBoost? = null
    private var virtualizer: Virtualizer? = null
    private var localFilesChannel: MethodChannel? = null
    private var pendingLocalResult: MethodChannel.Result? = null
    private var visualizerChannel: EventChannel? = null
    private var visualizerCapture: Visualizer? = null
    private var visualizerSink: EventChannel.EventSink? = null
    private var visualizerHandler: Handler? = null
    private var systemChannel: MethodChannel? = null
    private var mediaSessionChannel: MethodChannel? = null
    private var videoExportChannel: MethodChannel? = null
    private val videoExportCancel = java.util.concurrent.atomic.AtomicBoolean(false)
    @Volatile private var videoExportRunning = false
    private var videoProgressSink: EventChannel.EventSink? = null

    private companion object {
        const val PICK_AUDIO_REQUEST_CODE = 4213

        /**
         * Channel the media card is posted on.
         *
         * Android notification channels are immutable once created, so a
         * channel that was ever created with the wrong importance stays wrong
         * on every later install - a classic "the media card never appears"
         * cause. PlaybackService creates it before posting its card.
         */
        const val PLAYBACK_CHANNEL_ID = "com.music.player.playback.v2"
        const val PLAYBACK_CHANNEL_NAME = "MuZic playback"
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        ensurePlaybackChannel()
    }

    /**
     * Creates the playback channel before the card is posted, with an
     * importance that guarantees the card is visible in the shade instead of
     * being dropped on OEM skins that hide low-importance channels.
     */
    private fun ensurePlaybackChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(PLAYBACK_CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            PLAYBACK_CHANNEL_ID,
            PLAYBACK_CHANNEL_NAME,
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
                "shareText" -> shareText(
                    call.argument<String>("subject") ?: "MuZic diagnostics",
                    call.argument<String>("text") ?: "",
                    result,
                )
                else -> result.notImplemented()
            }
        }

        mediaSessionChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "music_player/media_session",
        )
        PlaybackService.commandSink = { command, value ->
            runOnUiThread {
                mediaSessionChannel?.invokeMethod(
                    "onCommand",
                    mapOf("command" to command, "value" to value),
                )
            }
        }
        PlaybackService.errorSink = { message ->
            runOnUiThread {
                mediaSessionChannel?.invokeMethod(
                    "onLog",
                    mapOf("message" to message),
                )
            }
        }
        mediaSessionChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    val intent = Intent(this, PlaybackService::class.java).apply {
                        putExtra("title", call.argument<String>("title") ?: "MuZic")
                        putExtra("artist", call.argument<String>("artist") ?: "")
                        putExtra("album", call.argument<String>("album") ?: "")
                        putExtra("artworkUrl", call.argument<String>("artworkUrl"))
                        putExtra("artworkPath", call.argument<String>("artworkPath"))
                        putExtra("playing", call.argument<Boolean>("playing") ?: false)
                        putExtra("positionMs", call.argument<Int>("positionMs")?.toLong() ?: 0L)
                        putExtra("durationMs", call.argument<Int>("durationMs")?.toLong() ?: 0L)
                        putExtra("speed", call.argument<Double>("speed")?.toFloat() ?: 1f)
                        putExtra("hasNext", call.argument<Boolean>("hasNext") ?: true)
                        putExtra("hasPrevious", call.argument<Boolean>("hasPrevious") ?: true)
                        putExtra("shadeEnabled", call.argument<Boolean>("shadeEnabled") ?: true)
                        putExtra("shadeStyle", call.argument<String>("shadeStyle") ?: "rich")
                        putExtra("shadeTheme", call.argument<String>("shadeTheme") ?: "system")
                        putExtra("shadeArtwork", call.argument<Boolean>("shadeArtwork") ?: true)
                        putExtra("shadePrevious", call.argument<Boolean>("shadePrevious") ?: true)
                        putExtra("shadeNext", call.argument<Boolean>("shadeNext") ?: true)
                        putExtra("shadeProgress", call.argument<Boolean>("shadeProgress") ?: true)
                        putExtra("shadeKeepOnPause", call.argument<Boolean>("shadeKeepOnPause") ?: true)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }
                "hide" -> {
                    stopService(Intent(this, PlaybackService::class.java))
                    result.success(true)
                }
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
                "mediaNotificationDiagnostics" ->
                    result.success(mediaNotificationDiagnostics())
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
                            var total = 0L
                            val start = band * perBand
                            val end = minOf(waveform.size, start + perBand)
                            if (start >= end) {
                                values.add(0.0)
                                continue
                            }
                            for (index in start until end) {
                                total += abs(waveform[index].toInt())
                            }
                            val average = total.toDouble() / (end - start)
                            values.add((average / 128.0).coerceIn(0.0, 1.0))
                        }
                        handler.post { visualizerSink?.success(values) }
                    }

                    override fun onFftDataCapture(
                        visualizer: Visualizer?,
                        fft: ByteArray?,
                        samplingRate: Int,
                    ) = Unit
                },
                Visualizer.getMaxCaptureRate() / 3,
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
        val playbackChannelId = PLAYBACK_CHANNEL_ID
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

        val serviceRunning = try {
            val info = packageManager.getServiceInfo(
                android.content.ComponentName(packageName, PlaybackService::class.java.name),
                0,
            )
            info.enabled
        } catch (e: Exception) {
            false
        }

        val posted = activeNotifications().map { entry ->
            "${entry["channelId"]}#${entry["id"]}${if (entry["ongoing"] == true) " ongoing" else ""}"
        }

        val smallIconValid = try {
            getDrawable(R.drawable.ic_stat_muzic) != null
        } catch (e: Exception) {
            false
        }

        return mapOf(
            "sdkInt" to Build.VERSION.SDK_INT,
            "notificationsEnabled" to notificationsEnabled,
            "postPermission" to (
                checkSelfPermission("android.permission.POST_NOTIFICATIONS") ==
                    android.content.pm.PackageManager.PERMISSION_GRANTED
                ),
            "playbackChannelExists" to (channel != null),
            "playbackChannelImportance" to channelImportance,
            "appChannelCount" to appChannelCount,
            "audioServiceDeclared" to serviceRunning,
            "smallIconResolves" to smallIconValid,
            "mediaSessionActive" to PlaybackService.isSessionActive(),
            "playbackServiceRunning" to isServiceRunning(PlaybackService::class.java),
            "posted" to posted,
            "postedCount" to posted.size,
        )
    }

    /** True when a service of this class is currently started. */
    private fun isServiceRunning(clazz: Class<*>): Boolean {
        return try {
            val manager = getSystemService(android.app.ActivityManager::class.java)
                ?: return false
            val services = manager.getRunningServices(Int.MAX_VALUE)
            services.any { it.service.className == clazz.name }
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
            result.error("busy", "A video export is already running.", null)
            return
        }
        videoExportCancel.set(false)
        val audioPath = call.argument<String>("audioPath")
        val artworkPath = call.argument<String>("artworkPath")
        val title = call.argument<String>("title") ?: "MuZic"
        val artist = call.argument<String>("artist") ?: ""
        val durationMs = call.argument<Int>("durationMs")?.toLong() ?: 0L
        val outputName = call.argument<String>("outputName") ?: "muzic_video"
        val lyrics = parseLyrics(call.argument<String>("lyrics") ?: "[]")
        if (audioPath == null || !File(audioPath).exists()) {
            result.error("missing_audio", "The audio file is not available.", null)
            return
        }
        // The render is CPU bound for tens of seconds: keep it off the UI thread
        // and off the platform thread so the app stays fully usable (and the
        // sheet can be closed) while it runs.
        Thread({
            videoExportRunning = true
            try {
                val path = VideoExporter(this).export(
                    audioPath = audioPath,
                    artworkPath = artworkPath,
                    title = title,
                    artist = artist,
                    lyrics = lyrics,
                    durationMsHint = durationMs,
                    outputName = outputName,
                    isCancelled = { videoExportCancel.get() },
                ) { progress ->
                    runOnUiThread { videoProgressSink?.success(progress) }
                }
                runOnUiThread { result.success(path) }
            } catch (e: VideoExporter.Cancelled) {
                runOnUiThread { result.error("cancelled", "Export stopped.", null) }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("export_failed", e.message ?: "Video export failed.", null)
                }
            } finally {
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
