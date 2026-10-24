package com.auralis.player

import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.media.Image
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.text.TextUtils
import androidx.documentfile.provider.DocumentFile
import org.json.JSONArray
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.io.OutputStream
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Renders a shareable lyric video (cover art + live waveform + synced lyrics)
 * fully on device: frames are drawn with Canvas, encoded as H.264 and muxed
 * with AAC audio using platform MediaCodec — no FFmpeg needed.
 */
class VideoExporter(private val context: Context) {

    data class LyricLine(val timeMs: Long, val text: String)

    private data class CachedLyricLayout(val layout: StaticLayout)

    private val width = 540
    private val height = 960

    // A 540×960 portrait frame keeps captions comfortably below the artwork
    // and fills a phone screen. Twenty frames per second and a modest bitrate
    // keep the added portrait pixels practical on mid-range phones.
    private val fps = 20
    private val videoBitrate = 1_800_000

    /** Thrown when the requested soundtrack disappears before it can be read. */
    class MissingAudio : RuntimeException("The audio file is not available.")

    /** Thrown when the user stops the export from the UI. */
    class Cancelled : RuntimeException("Export cancelled")

    fun export(
        audioPath: String,
        artworkPath: String?,
        title: String,
        artist: String,
        lyrics: List<LyricLine>,
        durationMsHint: Long,
        outputName: String,
        outputFolderUri: String? = null,
        isCancelled: () -> Boolean = { false },
        onStage: (String) -> Unit = {},
        onProgress: (Double) -> Unit,
    ): String {
        onStage("media_extractor")
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(audioPath)
        } catch (_: FileNotFoundException) {
            runCatching { extractor.release() }
            throw MissingAudio()
        } catch (error: Exception) {
            runCatching { extractor.release() }
            throw error
        }
        var audioTrackIndex = -1
        var inputFormat: MediaFormat? = null
        for (index in 0 until extractor.trackCount) {
            val format = extractor.getTrackFormat(index)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith("audio/")) {
                audioTrackIndex = index
                inputFormat = format
                break
            }
        }
        require(audioTrackIndex >= 0 && inputFormat != null) {
            "The audio file has no decodable audio track."
        }
        extractor.selectTrack(audioTrackIndex)

        onStage("codec_setup")
        val mime = inputFormat.getString(MediaFormat.KEY_MIME)!!
        val sampleRate = inputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        val channelCount = min(
            2,
            inputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT),
        )
        val durationUs = when {
            inputFormat.containsKey(MediaFormat.KEY_DURATION) ->
                inputFormat.getLong(MediaFormat.KEY_DURATION)
            durationMsHint > 0 -> durationMsHint * 1000
            else -> 180_000_000L
        }

        val decoder = MediaCodec.createDecoderByType(mime)
        decoder.configure(inputFormat, null, null, 0)
        decoder.start()

        // If the source is already AAC we copy the compressed samples straight
        // into the MP4. Decoding and re-encoding audio was one of the two big
        // costs of an export and buys nothing for the most common sources.
        val audioPassthrough = mime == MediaFormat.MIMETYPE_AUDIO_AAC

        val aacFormat = MediaFormat.createAudioFormat(
            MediaFormat.MIMETYPE_AUDIO_AAC,
            sampleRate,
            channelCount,
        ).apply {
            setInteger(
                MediaFormat.KEY_AAC_PROFILE,
                MediaCodecInfo.CodecProfileLevel.AACObjectLC,
            )
            setInteger(MediaFormat.KEY_BIT_RATE, 128_000)
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 32_768)
        }
        val audioEncoder = if (audioPassthrough) {
            null
        } else {
            MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC).apply {
                configure(
                    aacFormat,
                    null,
                    null,
                    MediaCodec.CONFIGURE_FLAG_ENCODE,
                )
                start()
            }
        }

        val videoFormat = MediaFormat.createVideoFormat(
            MediaFormat.MIMETYPE_VIDEO_AVC,
            width,
            height,
        ).apply {
            setInteger(
                MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible,
            )
            setInteger(MediaFormat.KEY_BIT_RATE, videoBitrate)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }
        val videoEncoder =
            MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        videoEncoder.configure(
            videoFormat,
            null,
            null,
            MediaCodec.CONFIGURE_FLAG_ENCODE,
        )
        videoEncoder.start()

        fun releaseAfterOutputSetupFailure() {
            runCatching { extractor.release() }
            runCatching { decoder.stop() }
            runCatching { decoder.release() }
            runCatching { audioEncoder?.stop() }
            runCatching { audioEncoder?.release() }
            runCatching { videoEncoder.stop() }
            runCatching { videoEncoder.release() }
        }

        onStage("prepare_output")
        val outputFile = try {
            createOutputFile(outputName)
        } catch (error: Exception) {
            releaseAfterOutputSetupFailure()
            throw error
        }
        var completed = false
        val muxer = try {
            MediaMuxer(
                outputFile.absolutePath,
                MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4,
            )
        } catch (error: Exception) {
            runCatching { outputFile.delete() }
            releaseAfterOutputSetupFailure()
            throw error
        }
        var muxerStarted = false
        var muxerVideoTrack = -1
        var muxerAudioTrack = -1
        val pendingAudio = ArrayList<Pair<ByteArray, MediaCodec.BufferInfo>>()
        val pendingVideo = ArrayList<Pair<ByteArray, MediaCodec.BufferInfo>>()

        onStage("prepare_renderer")
        val frameBitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(frameBitmap)
        val artwork = loadArtwork(artworkPath)
        val renderer = FrameRenderer(
            canvas,
            width,
            height,
            title,
            artist,
            artwork,
            lyrics,
            durationUs,
        )

        onStage("prepare_muxer")
        val info = MediaCodec.BufferInfo()
        val frameDurationUs = 1_000_000L / fps
        var nextFrameUs = 0L
        var audioInputDone = false
        var audioOutputDone = false
        var videoInputDone = false
        var videoOutputDone = false
        var lastRms = 0.12

        fun startMuxerIfReady() {
            if (muxerStarted) return
            if (muxerAudioTrack >= 0 && muxerVideoTrack >= 0) {
                muxer.start()
                muxerStarted = true
                for ((bytes, bufferInfo) in pendingAudio) {
                    muxer.writeSampleData(muxerAudioTrack, java.nio.ByteBuffer.wrap(bytes), bufferInfo)
                }
                pendingAudio.clear()
                for ((bytes, bufferInfo) in pendingVideo) {
                    muxer.writeSampleData(muxerVideoTrack, java.nio.ByteBuffer.wrap(bytes), bufferInfo)
                }
                pendingVideo.clear()
            }
        }

        // Passthrough reads compressed AAC samples straight from the source.
        val passthroughBuffer = java.nio.ByteBuffer.allocateDirect(256 * 1024)
        if (audioPassthrough) {
            muxerAudioTrack = muxer.addTrack(inputFormat)
        }

        onStage("render_frames")
        try {
            while (!audioOutputDone || !videoOutputDone) {
                if (isCancelled()) throw Cancelled()

                // ---- Audio: copy through, or decode → re-encode AAC ----
                if (audioPassthrough) {
                    if (!audioInputDone) {
                        passthroughBuffer.clear()
                        val size = extractor.readSampleData(passthroughBuffer, 0)
                        if (size < 0) {
                            audioInputDone = true
                            audioOutputDone = true
                            runCatching { extractor.release() }
                        } else {
                            val bytes = ByteArray(size)
                            passthroughBuffer.position(0)
                            passthroughBuffer.limit(size)
                            passthroughBuffer.get(bytes)
                            val flags =
                                if (extractor.sampleFlags and
                                    MediaExtractor.SAMPLE_FLAG_SYNC != 0
                                ) {
                                    MediaCodec.BUFFER_FLAG_KEY_FRAME
                                } else {
                                    0
                                }
                            val sampleInfo = MediaCodec.BufferInfo().apply {
                                set(0, size, extractor.sampleTime, flags)
                            }
                            if (muxerStarted) {
                                muxer.writeSampleData(
                                    muxerAudioTrack,
                                    java.nio.ByteBuffer.wrap(bytes),
                                    sampleInfo,
                                )
                            } else {
                                pendingAudio.add(bytes to sampleInfo)
                            }
                            extractor.advance()
                        }
                    }
                } else {
                    if (!audioInputDone) {
                        val inIndex = decoder.dequeueInputBuffer(2_000)
                        if (inIndex >= 0) {
                            val buffer = decoder.getInputBuffer(inIndex)!!
                            val size = extractor.readSampleData(buffer, 0)
                            if (size < 0) {
                                decoder.queueInputBuffer(
                                    inIndex,
                                    0,
                                    0,
                                    0,
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                                )
                                audioInputDone = true
                                runCatching { extractor.release() }
                            } else {
                                decoder.queueInputBuffer(
                                    inIndex,
                                    0,
                                    size,
                                    extractor.sampleTime,
                                    0,
                                )
                                extractor.advance()
                            }
                        }
                    }
                    if (!audioOutputDone) {
                        var decoderIndex = decoder.dequeueOutputBuffer(info, 2_000)
                        while (decoderIndex >= 0) {
                            val pcm = decoder.getOutputBuffer(decoderIndex)
                            val eos =
                                info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                            if (pcm != null && info.size > 0) {
                                pcm.position(info.offset)
                                pcm.limit(info.offset + info.size)
                                lastRms = rmsOf(pcm) * 3.2
                                var offset = info.offset
                                while (offset < info.offset + info.size) {
                                    val encIndex = audioEncoder!!.dequeueInputBuffer(5_000)
                                    if (encIndex < 0) break
                                    val encBuffer = audioEncoder.getInputBuffer(encIndex)!!
                                    encBuffer.clear()
                                    val chunk =
                                        min(encBuffer.capacity(), info.offset + info.size - offset)
                                    pcm.position(offset)
                                    pcm.limit(offset + chunk)
                                    encBuffer.put(pcm)
                                    val pts = info.presentationTimeUs +
                                        (offset - info.offset) * 1_000_000L /
                                        (sampleRate.toLong() * channelCount * 2L)
                                    audioEncoder.queueInputBuffer(encIndex, 0, chunk, pts, 0)
                                    offset += chunk
                                }
                            }
                            decoder.releaseOutputBuffer(decoderIndex, false)
                            if (eos) {
                                val encIndex = audioEncoder!!.dequeueInputBuffer(5_000)
                                if (encIndex >= 0) {
                                    audioEncoder.queueInputBuffer(
                                        encIndex,
                                        0,
                                        0,
                                        0,
                                        MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                                    )
                                }
                                break
                            }
                            decoderIndex = decoder.dequeueOutputBuffer(info, 0)
                        }
                    }
                    if (!audioOutputDone) {
                        var audioIndex = audioEncoder!!.dequeueOutputBuffer(info, 0)
                        while (audioIndex >= 0) {
                            val outBuffer = audioEncoder.getOutputBuffer(audioIndex)
                            if (outBuffer != null && info.size > 0 &&
                                info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0
                            ) {
                                outBuffer.position(info.offset)
                                outBuffer.limit(info.offset + info.size)
                                val bytes = ByteArray(info.size)
                                outBuffer.get(bytes)
                                val sampleInfo = MediaCodec.BufferInfo().apply {
                                    set(
                                        0,
                                        bytes.size,
                                        info.presentationTimeUs,
                                        info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME,
                                    )
                                }
                                if (muxerStarted) {
                                    muxer.writeSampleData(
                                        muxerAudioTrack,
                                        java.nio.ByteBuffer.wrap(bytes),
                                        sampleInfo,
                                    )
                                } else {
                                    pendingAudio.add(bytes to sampleInfo)
                                }
                            }
                            audioEncoder.releaseOutputBuffer(audioIndex, false)
                            if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                                audioOutputDone = true
                                break
                            }
                            audioIndex = audioEncoder.dequeueOutputBuffer(info, 0)
                        }
                        if (audioIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                            muxerAudioTrack = muxer.addTrack(audioEncoder.outputFormat)
                            startMuxerIfReady()
                        }
                    }
                }

                // ---- Video: draw one frame ----
                if (!videoInputDone && nextFrameUs <= durationUs) {
                    val inIndex = videoEncoder.dequeueInputBuffer(10_000)
                    if (inIndex >= 0) {
                        renderer.draw(nextFrameUs / 1000L, lastRms)
                        val image = videoEncoder.getInputImage(inIndex)
                        if (image != null) {
                            fillYuv(image, frameBitmap)
                            videoEncoder.queueInputBuffer(
                                inIndex,
                                0,
                                width * height * 3 / 2,
                                nextFrameUs,
                                0,
                            )
                            nextFrameUs += frameDurationUs
                            onProgress(
                                (nextFrameUs.toDouble() / durationUs.toDouble())
                                    .coerceIn(0.0, 0.99),
                            )
                        } else {
                            videoEncoder.queueInputBuffer(inIndex, 0, 0, nextFrameUs, 0)
                            nextFrameUs += frameDurationUs
                        }
                    }
                } else if (!videoInputDone) {
                    val inIndex = videoEncoder.dequeueInputBuffer(10_000)
                    if (inIndex >= 0) {
                        videoEncoder.queueInputBuffer(
                            inIndex,
                            0,
                            0,
                            0,
                            MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                        )
                        videoInputDone = true
                    }
                }

                var videoIndex = videoEncoder.dequeueOutputBuffer(info, 0)
                while (videoIndex >= 0) {
                    val outBuffer = videoEncoder.getOutputBuffer(videoIndex)
                    if (outBuffer != null && info.size > 0 &&
                        info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0
                    ) {
                        outBuffer.position(info.offset)
                        outBuffer.limit(info.offset + info.size)
                        val bytes = ByteArray(info.size)
                        outBuffer.get(bytes)
                        val sampleInfo = MediaCodec.BufferInfo().apply {
                            set(
                                0,
                                bytes.size,
                                info.presentationTimeUs,
                                info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME,
                            )
                        }
                        if (muxerStarted) {
                            muxer.writeSampleData(
                                muxerVideoTrack,
                                java.nio.ByteBuffer.wrap(bytes),
                                sampleInfo,
                            )
                        } else {
                            pendingVideo.add(bytes to sampleInfo)
                        }
                    }
                    videoEncoder.releaseOutputBuffer(videoIndex, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        videoOutputDone = true
                        break
                    }
                    videoIndex = videoEncoder.dequeueOutputBuffer(info, 0)
                }
                if (videoIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    muxerVideoTrack = muxer.addTrack(videoEncoder.outputFormat)
                    startMuxerIfReady()
                }
            }
            onStage("finalize_muxer")
            if (!muxerStarted) {
                throw IOException("The video muxer did not start.")
            }
            muxer.stop()
            muxerStarted = false
            // Must be set before finally: its cleanup deletes incomplete renders.
            completed = true
        } finally {
            runCatching { decoder.stop() }
            runCatching { decoder.release() }
            runCatching { audioEncoder?.stop() }
            runCatching { audioEncoder?.release() }
            runCatching { videoEncoder.stop() }
            runCatching { videoEncoder.release() }
            runCatching { if (muxerStarted) muxer.stop() }
            runCatching { muxer.release() }
            runCatching { artwork?.recycle() }
            runCatching { renderer.release() }
            // A cancelled or failed render must not leave a half-written MP4
            // behind, otherwise the video list may show a broken entry.
            if (!completed) runCatching { if (outputFile.exists()) outputFile.delete() }
        }
        return try {
            onStage(
                if (outputFolderUri.isNullOrBlank()) {
                    "publish_gallery"
                } else {
                    "publish_custom_folder"
                },
            )
            onProgress(0.99)
            if (isCancelled()) throw Cancelled()
            val published = publishToGallery(outputFile, outputFolderUri, isCancelled)
            onProgress(1.0)
            published
        } finally {
            // This is only staging. Keep the selected-folder/gallery/app copy,
            // never the intermediate file created for MediaMuxer.
            runCatching { if (outputFile.exists()) outputFile.delete() }
        }
    }

    private fun rmsOf(buffer: java.nio.ByteBuffer): Double {
        val start = buffer.position()
        val end = buffer.limit()
        if (end - start < 2) return 0.0
        var sum = 0.0
        var count = 0
        var index = start
        while (index + 1 < end) {
            val sample = ((buffer.get(index + 1).toInt() shl 8) or
                (buffer.get(index).toInt() and 0xFF)).toShort().toDouble()
            sum += sample * sample
            count++
            index += 2
        }
        buffer.position(start)
        if (count == 0) return 0.0
        return sqrt(sum / count) / 32768.0
    }

    // Scratch buffers reused for every frame: allocation per frame dominates
    // otherwise, and writing single bytes through ByteBuffer.put(index, …) is
    // ~10x slower than a row-wise array copy.
    private var argb = IntArray(width * height)
    private var yRowBytes = ByteArray(width)
    private var uRowBytes = ByteArray(width / 2)
    private var vRowBytes = ByteArray(width / 2)

    private fun fillYuv(image: Image, bitmap: Bitmap) {
        val w = bitmap.width
        val h = bitmap.height
        if (argb.size != w * h) argb = IntArray(w * h)
        bitmap.getPixels(argb, 0, w, 0, 0, w, h)
        if (yRowBytes.size != w) {
            yRowBytes = ByteArray(w)
            uRowBytes = ByteArray(w / 2)
            vRowBytes = ByteArray(w / 2)
        }

        val yPlane = image.planes[0]
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]
        val yBuffer = yPlane.buffer
        val uBuffer = uPlane.buffer
        val vBuffer = vPlane.buffer
        val yRowStride = yPlane.rowStride
        val yPix = yPlane.pixelStride
        val uRowStride = uPlane.rowStride
        val uPix = uPlane.pixelStride
        val vRowStride = vPlane.rowStride
        val vPix = vPlane.pixelStride

        var offset = 0
        for (row in 0 until h) {
            for (col in 0 until w) {
                val color = argb[offset + col]
                val r = (color shr 16) and 0xFF
                val g = (color shr 8) and 0xFF
                val b = color and 0xFF
                val y = (((66 * r + 129 * g + 25 * b + 128) shr 8) + 16)
                yRowBytes[col] = if (y > 255) 255.toByte() else if (y < 0) 0 else y.toByte()
            }
            offset += w
            val base = row * yRowStride
            if (yPix == 1) {
                yBuffer.position(base)
                yBuffer.put(yRowBytes, 0, w)
            } else {
                for (col in 0 until w) yBuffer.put(base + col * yPix, yRowBytes[col])
            }

            if (row % 2 == 0) {
                val halfW = w / 2
                for (col in 0 until halfW) {
                    val c0 = argb[row * w + col * 2]
                    val c1 = if (col * 2 + 1 < w) argb[row * w + col * 2 + 1] else c0
                    val r = ((c0 shr 16) and 0xFF) + ((c1 shr 16) and 0xFF)
                    val g = ((c0 shr 8) and 0xFF) + ((c1 shr 8) and 0xFF)
                    val b = (c0 and 0xFF) + (c1 and 0xFF)
                    val u = (((-38 * r - 74 * g + 112 * b + 256) shr 9) + 128)
                    val v = (((112 * r - 94 * g - 18 * b + 256) shr 9) + 128)
                    uRowBytes[col] = if (u > 255) 255.toByte() else if (u < 0) 0 else u.toByte()
                    vRowBytes[col] = if (v > 255) 255.toByte() else if (v < 0) 0 else v.toByte()
                }
                val uBase = (row / 2) * uRowStride
                if (uPix == 1) {
                    uBuffer.position(uBase)
                    uBuffer.put(uRowBytes, 0, halfW)
                } else {
                    for (col in 0 until halfW) {
                        uBuffer.put(uBase + col * uPix, uRowBytes[col])
                    }
                }
                val vBase = (row / 2) * vRowStride
                if (vPix == 1) {
                    vBuffer.position(vBase)
                    vBuffer.put(vRowBytes, 0, halfW)
                } else {
                    for (col in 0 until halfW) {
                        vBuffer.put(vBase + col * vPix, vRowBytes[col])
                    }
                }
            }
        }
    }

    private fun loadArtwork(path: String?): Bitmap? {
        if (path == null) return null
        return runCatching {
            val options = BitmapFactory.Options().apply { inScaled = false }
            BitmapFactory.decodeFile(path, options)
        }.getOrNull()
    }

    private fun createOutputFile(name: String): File {
        // Keep MediaMuxer's scratch output on internal app storage, then copy
        // only the completed video to the selected folder or shared Movies below.
        val directory = File(context.filesDir, "video_exports")
        if (!directory.exists() && !directory.mkdirs() && !directory.exists()) {
            throw IllegalStateException(
                "Could not prepare private video export storage."
            )
        }
        // Long song titles plus long artist credit lists can exceed Android's
        // per-file name limit and make MediaMuxer fail with a misleading
        // ENOENT. Keep the visible name useful but bounded.
        val safe = name
            .replace(Regex("[^\\p{L}\\p{M}\\p{N}._ -]"), " ")
            .replace(Regex("""\s+"""), " ")
            .trim()
            .take(82)
            .trim()
            .ifEmpty { "Unknown track" }
        var candidate = "$safe.mp4"
        var suffix = 2
        while (File(directory, candidate).exists()) {
            candidate = "$safe ($suffix).mp4"
            suffix++
        }
        return File(directory, candidate)
    }

    /** Writes the finished MP4 directly into the persisted SAF folder selected in Settings. */
    private fun publishToSelectedFolder(
        file: File,
        folderUri: String,
        isCancelled: () -> Boolean,
    ): String {
        val treeUri = Uri.parse(folderUri)
        val parent = DocumentFile.fromTreeUri(context, treeUri)
        if (parent == null || !parent.canWrite()) {
            throw IOException("The selected downloads folder cannot be written to.")
        }
        val baseName = file.nameWithoutExtension
        val extension = file.extension.ifEmpty { "mp4" }
        var candidateName = file.name
        var suffix = 2
        while (parent.findFile(candidateName) != null) {
            candidateName = "$baseName ($suffix).$extension"
            suffix++
        }
        val destination = parent.createFile("video/mp4", candidateName)
            ?: throw IOException("Could not create the video in the selected downloads folder.")
        try {
            val output = context.contentResolver.openOutputStream(destination.uri)
                ?: throw IOException("Could not open the video in the selected downloads folder.")
            output.use { stream -> copyWithCancellation(file, stream, isCancelled) }
            if (isCancelled()) throw Cancelled()
            return destination.uri.toString()
        } catch (error: Exception) {
            runCatching { destination.delete() }
            throw error
        }
    }

    /** Publishes the finished MP4 to the selected downloads folder, or the existing Movies location. */
    private fun publishToGallery(
        file: File,
        outputFolderUri: String?,
        isCancelled: () -> Boolean,
    ): String {
        if (!outputFolderUri.isNullOrBlank()) {
            return publishToSelectedFolder(file, outputFolderUri, isCancelled)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Video.Media.DISPLAY_NAME, file.name)
                put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                put(
                    MediaStore.Video.Media.RELATIVE_PATH,
                    "${Environment.DIRECTORY_MOVIES}/MuZic",
                )
                put(MediaStore.Video.Media.IS_PENDING, 1)
            }
            val uri = context.contentResolver.insert(
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                values,
            ) ?: throw IOException("Could not create the Movies video entry.")
            try {
                val output = context.contentResolver.openOutputStream(uri)
                    ?: throw IOException("Could not open the Movies video entry.")
                output.use { destination ->
                    copyWithCancellation(file, destination, isCancelled)
                }
                if (isCancelled()) throw Cancelled()
                val finalized = ContentValues().apply {
                    put(MediaStore.Video.Media.IS_PENDING, 0)
                }
                if (context.contentResolver.update(uri, finalized, null, null) <= 0) {
                    throw IOException("Could not finalize the Movies video entry.")
                }
                if (isCancelled()) throw Cancelled()
                return uri.toString()
            } catch (error: Exception) {
                runCatching { context.contentResolver.delete(uri, null, null) }
                throw error
            }
        }

        // On pre-scoped-storage Android versions retain a copy in the app's
        // Movies folder. Returning the internal staging path and deleting it
        // would report success while leaving no video behind.
        val root = context.getExternalFilesDir(Environment.DIRECTORY_MOVIES)
            ?: context.filesDir
        val directory = File(root, "MuZic")
        if (!directory.exists() && !directory.mkdirs() && !directory.exists()) {
            throw IOException("Could not create the MuZic Movies folder.")
        }
        val baseName = file.nameWithoutExtension
        val extension = file.extension.ifEmpty { "mp4" }
        var candidate = File(directory, file.name)
        var suffix = 2
        while (candidate.exists()) {
            candidate = File(directory, "$baseName ($suffix).$extension")
            suffix++
        }
        return try {
            candidate.outputStream().use { destination ->
                copyWithCancellation(file, destination, isCancelled)
            }
            if (isCancelled()) throw Cancelled()
            candidate.absolutePath
        } catch (error: Exception) {
            runCatching { candidate.delete() }
            throw error
        }
    }

    private fun copyWithCancellation(
        file: File,
        output: OutputStream,
        isCancelled: () -> Boolean,
    ) {
        val buffer = ByteArray(64 * 1024)
        file.inputStream().use { input ->
            while (true) {
                if (isCancelled()) throw Cancelled()
                val count = input.read(buffer)
                if (count < 0) break
                output.write(buffer, 0, count)
            }
        }
        output.flush()
    }

    /** Draws cover art, waveform and the current lyric line for a timestamp. */
    private inner class FrameRenderer(
        private val canvas: Canvas,
        private val w: Int,
        private val h: Int,
        private val title: String,
        private val artist: String,
        private val artwork: Bitmap?,
        private val lines: List<LyricLine>,
        private val durationUs: Long,
    ) {
        private val backgroundPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val titlePaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textSize = 32f
            textAlign = Paint.Align.CENTER
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        private val artistPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#B8B5C8")
            textSize = 23f
            textAlign = Paint.Align.CENTER
        }
        private val lyricPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textSize = 34f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        private val nextLyricPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#C2BED1")
            textSize = 25f
        }
        private val barPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#8B7CFF")
        }
        private val progressPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val artRect = RectF(60f, 72f, w - 60f, 72f + (w - 120f))
        private val lyricMaxWidth = w - 96
        private val activeLyricTop = h * 0.71f
        private val activeLyricHeight = h * 0.13f
        private val nextLyricTop = h * 0.85f
        private val nextLyricHeight = h * 0.08f
        private var cachedActiveIndex = Int.MIN_VALUE
        private var cachedActiveLayout: CachedLyricLayout? = null
        private var cachedNextIndex = Int.MIN_VALUE
        private var cachedNextLayout: CachedLyricLayout? = null

        init {
            backgroundPaint.shader = LinearGradient(
                0f,
                0f,
                w.toFloat(),
                h.toFloat(),
                intArrayOf(
                    Color.parseColor("#0B0A14"),
                    Color.parseColor("#1A1433"),
                    Color.parseColor("#0B0A14"),
                ),
                floatArrayOf(0f, 0.55f, 1f),
                Shader.TileMode.CLAMP,
            )
        }

        // The gradient, cover and track metadata never change. Draw them once
        // and blit the layer on each frame instead of repeating the expensive
        // artwork scaling during the render.
        private val staticLayer: Bitmap =
            Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888).also { layer ->
                val layerCanvas = Canvas(layer)
                layerCanvas.drawRect(0f, 0f, w.toFloat(), h.toFloat(), backgroundPaint)
                val clip = Path().apply {
                    addRoundRect(artRect, 34f, 34f, Path.Direction.CW)
                }
                layerCanvas.save()
                layerCanvas.clipPath(clip)
                if (artwork != null) {
                    val src = RectF(0f, 0f, artwork.width.toFloat(), artwork.height.toFloat())
                    layerCanvas.drawBitmap(
                        artwork,
                        src.toIntRect(),
                        artRect,
                        Paint(Paint.FILTER_BITMAP_FLAG),
                    )
                } else {
                    layerCanvas.drawRect(artRect, barPaint)
                }
                layerCanvas.restore()

                val ellipsis = TextUtils.TruncateAt.END
                val textWidth = (w - 120).toFloat()
                layerCanvas.drawText(
                    TextUtils.ellipsize(title, titlePaint, textWidth, ellipsis).toString(),
                    w / 2f,
                    artRect.bottom + 46f,
                    titlePaint,
                )
                layerCanvas.drawText(
                    TextUtils.ellipsize(artist, artistPaint, textWidth, ellipsis).toString(),
                    w / 2f,
                    artRect.bottom + 78f,
                    artistPaint,
                )
            }

        fun release() {
            if (!staticLayer.isRecycled) staticLayer.recycle()
        }

        fun draw(positionMs: Long, rms: Double) {
            canvas.drawBitmap(staticLayer, 0f, 0f, null)

            var activeIndex = -1
            for (index in lines.indices) {
                if (lines[index].timeMs <= positionMs) activeIndex = index else break
            }
            val activeText = lines.getOrNull(activeIndex)?.text ?: title
            val nextIndex = activeIndex + 1
            val nextText = lines.getOrNull(nextIndex)?.text.orEmpty()

            val activeLayout = activeLayoutFor(activeIndex, activeText)
            drawCenteredLayout(activeLayout, activeLyricTop, activeLyricHeight)
            if (nextText.isNotEmpty()) {
                val nextLayout = nextLayoutFor(nextIndex, nextText)
                drawCenteredLayout(nextLayout, nextLyricTop, nextLyricHeight)
            }

            // Live waveform driven by the decoded audio's RMS level. Keeping
            // its height bounded leaves a clean gap above the lyric captions.
            val bars = 24
            val gap = 6f
            val barWidth = (w - 120f - gap * (bars - 1)) / bars
            val baseline = h * 0.685f
            val level = rms.coerceIn(0.02, 1.0)
            for (index in 0 until bars) {
                val shape = abs(kotlin.math.sin(index * 0.7 + positionMs / 240.0))
                val barHeight = (8f + 52f * level * shape).toFloat()
                val left = 60f + index * (barWidth + gap)
                canvas.drawRoundRect(
                    left,
                    baseline - barHeight,
                    left + barWidth,
                    baseline,
                    6f,
                    6f,
                    barPaint,
                )
            }

            val progress = if (durationUs > 0) {
                (positionMs * 1000.0 / durationUs).coerceIn(0.0, 1.0).toFloat()
            } else {
                0f
            }
            progressPaint.color = Color.parseColor("#2A2540")
            canvas.drawRoundRect(
                60f,
                h - 46f,
                w - 60f,
                h - 40f,
                3f,
                3f,
                progressPaint,
            )
            progressPaint.color = Color.parseColor("#B9AEFF")
            canvas.drawRoundRect(
                60f,
                h - 46f,
                60f + (w - 120f) * progress,
                h - 40f,
                3f,
                3f,
                progressPaint,
            )
        }

        private fun activeLayoutFor(index: Int, text: String): CachedLyricLayout {
            if (cachedActiveIndex != index || cachedActiveLayout == null) {
                cachedActiveIndex = index
                cachedActiveLayout = createWrappedLayout(
                    text,
                    lyricPaint,
                    lyricMaxWidth,
                    activeLyricHeight,
                )
            }
            return cachedActiveLayout!!
        }

        private fun nextLayoutFor(index: Int, text: String): CachedLyricLayout {
            if (cachedNextIndex != index || cachedNextLayout == null) {
                cachedNextIndex = index
                cachedNextLayout = createWrappedLayout(
                    text,
                    nextLyricPaint,
                    lyricMaxWidth,
                    nextLyricHeight,
                )
            }
            return cachedNextLayout!!
        }

        private fun createWrappedLayout(
            text: String,
            sourcePaint: TextPaint,
            maxWidth: Int,
            maxHeight: Float,
        ): CachedLyricLayout {
            val paint = TextPaint(sourcePaint)
            var textSize = sourcePaint.textSize
            fun buildLayout(): StaticLayout {
                paint.textSize = textSize
                return StaticLayout.Builder.obtain(text, 0, text.length, paint, maxWidth)
                    .setAlignment(Layout.Alignment.ALIGN_CENTER)
                    .setIncludePad(false)
                    .setLineSpacing(0f, 1f)
                    .build()
            }
            var layout = buildLayout()
            while (layout.height.toFloat() > maxHeight && textSize > 14f) {
                textSize = max(14f, textSize - 2f)
                layout = buildLayout()
            }
            return CachedLyricLayout(layout)
        }

        private fun drawCenteredLayout(
            cached: CachedLyricLayout,
            top: Float,
            height: Float,
        ) {
            val left = (w - lyricMaxWidth) / 2f
            val y = top + ((height - cached.layout.height.toFloat()) / 2f).coerceAtLeast(0f)
            canvas.save()
            canvas.translate(left, y)
            cached.layout.draw(canvas)
            canvas.restore()
        }
    }
}

private fun RectF.toIntRect(): android.graphics.Rect =
    android.graphics.Rect(left.toInt(), top.toInt(), right.toInt(), bottom.toInt())

private fun JSONArray.toLyricLines(): List<VideoExporter.LyricLine> {
    val lines = ArrayList<VideoExporter.LyricLine>()
    for (index in 0 until length()) {
        val item = optJSONObject(index) ?: continue
        val text = item.optString("text").trim()
        if (text.isEmpty()) continue
        lines.add(VideoExporter.LyricLine(item.optLong("timeMs", 0L), text))
    }
    return lines
}

/** Parses the lyrics payload sent from Dart ([{timeMs, text}, ...]). */
fun parseLyrics(json: String): List<VideoExporter.LyricLine> =
    runCatching { JSONArray(json).toLyricLines() }.getOrDefault(emptyList())
