package com.auralis.player

import android.app.Activity
import android.content.Intent
import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.media.audiofx.Virtualizer
import android.net.Uri
import android.provider.OpenableColumns
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * Hosts the audio-effects channel. Attaches Android's Equalizer, BassBoost and
 * Virtualizer (virtual surround) to the playback audio session.
 */
class MainActivity : AudioServiceActivity() {
    private var channel: MethodChannel? = null
    private var equalizer: Equalizer? = null
    private var bassBoost: BassBoost? = null
    private var virtualizer: Virtualizer? = null
    private var localFilesChannel: MethodChannel? = null
    private var pendingLocalResult: MethodChannel.Result? = null

    private companion object {
        const val PICK_AUDIO_REQUEST_CODE = 4213
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
                else -> result.notImplemented()
            }
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
        releaseEffects()
        super.onDestroy()
    }
}
