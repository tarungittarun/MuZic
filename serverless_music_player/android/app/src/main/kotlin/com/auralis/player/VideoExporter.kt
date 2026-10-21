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
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.text.TextPaint
import android.text.TextUtils
import org.json.JSONArray
import java.io.File
import kotlin.math.abs
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Renders a shareable lyric video (cover art + live waveform + synced lyrics)
 * fully on device: frames are drawn with Canvas, encoded as H.264 and muxed
 * with AAC audio using platform MediaCodec — no FFmpeg needed.
 */
class VideoExporter(private val context: Context) {

    data class LyricLine(val timeMs: Long, val text: String)

    private val width = 720
    private val height = 720
    private val fps = 30
    private val videoBitrate = 3_500_000

    fun export(
        audioPath: String,
        artworkPath: String?,
        title: String,
        artist: String,
        lyrics: List<LyricLine>,
        durationMsHint: Long,
        outputName: String,
        onProgress: (Double) -> Unit,
    ): String {
        val extractor = MediaExtractor()
        extractor.setDataSource(audioPath)
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
        val audioEncoder =
            MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
        audioEncoder.configure(
            aacFormat,
            null,
            null,
            MediaCodec.CONFIGURE_FLAG_ENCODE,
        )
        audioEncoder.start()

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

        val outputFile = createOutputFile(outputName)
        val muxer = MediaMuxer(
            outputFile.absolutePath,
            MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4,
        )
        var muxerStarted = false
        var muxerVideoTrack = -1
        var muxerAudioTrack = -1
        val pendingAudio = ArrayList<Pair<ByteArray, MediaCodec.BufferInfo>>()
        val pendingVideo = ArrayList<Pair<ByteArray, MediaCodec.BufferInfo>>()

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

        try {
            while (!audioOutputDone || !videoOutputDone) {
                // ---- Audio: decode → re-encode AAC ----
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
                            extractor.release()
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
                        val eos = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                        if (pcm != null && info.size > 0) {
                            pcm.position(info.offset)
                            pcm.limit(info.offset + info.size)
                            lastRms = rmsOf(pcm) * 3.2
                            var offset = info.offset
                            while (offset < info.offset + info.size) {
                                val encIndex = audioEncoder.dequeueInputBuffer(5_000)
                                if (encIndex < 0) break
                                val encBuffer = audioEncoder.getInputBuffer(encIndex)!!
                                encBuffer.clear()
                                val chunk = min(encBuffer.capacity(), info.offset + info.size - offset)
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
                            val encIndex = audioEncoder.dequeueInputBuffer(5_000)
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
                var audioIndex = audioEncoder.dequeueOutputBuffer(info, 0)
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
            onProgress(1.0)
        } finally {
            runCatching { decoder.stop() }
            runCatching { decoder.release() }
            runCatching { audioEncoder.stop() }
            runCatching { audioEncoder.release() }
            runCatching { videoEncoder.stop() }
            runCatching { videoEncoder.release() }
            runCatching { if (muxerStarted) muxer.stop() }
            runCatching { muxer.release() }
            artwork?.recycle()
        }
        return publishToGallery(outputFile).also {
            if (outputFile.exists()) outputFile.delete()
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

    private fun fillYuv(image: Image, bitmap: Bitmap) {
        val w = bitmap.width
        val h = bitmap.height
        val argb = IntArray(w * h)
        bitmap.getPixels(argb, 0, w, 0, 0, w, h)
        val yPlane = image.planes[0]
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]
        val yBuffer = yPlane.buffer
        val uBuffer = uPlane.buffer
        val vBuffer = vPlane.buffer
        val yRow = yPlane.rowStride
        val yPix = yPlane.pixelStride
        val uRow = uPlane.rowStride
        val uPix = uPlane.pixelStride
        val vRow = vPlane.rowStride
        val vPix = vPlane.pixelStride
        for (row in 0 until h) {
            for (col in 0 until w) {
                val color = argb[row * w + col]
                val r = (color shr 16) and 0xFF
                val g = (color shr 8) and 0xFF
                val b = color and 0xFF
                val y = (((66 * r + 129 * g + 25 * b + 128) shr 8) + 16)
                yBuffer.put(row * yRow + col * yPix, y.coerceIn(0, 255).toByte())
                if (row % 2 == 0 && col % 2 == 0) {
                    val u = (((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128)
                    val v = (((112 * r - 94 * g - 18 * b + 128) shr 8) + 128)
                    uBuffer.put(
                        (row / 2) * uRow + (col / 2) * uPix,
                        u.coerceIn(0, 255).toByte(),
                    )
                    vBuffer.put(
                        (row / 2) * vRow + (col / 2) * vPix,
                        v.coerceIn(0, 255).toByte(),
                    )
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
        val root = context.getExternalFilesDir(Environment.DIRECTORY_MOVIES)
            ?: context.filesDir
        val directory = File(root, "exports")
        if (!directory.exists()) directory.mkdirs()
        val safe = name.replace(Regex("[^A-Za-z0-9._ -]"), "_").ifEmpty { "muzic_video" }
        return File(directory, "$safe.mp4")
    }

    /** Copies the finished MP4 into the shared Movies collection. */
    private fun publishToGallery(file: File): String {
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
            )
            if (uri != null) {
                context.contentResolver.openOutputStream(uri)?.use { output ->
                    file.inputStream().use { input -> input.copyTo(output) }
                }
                values.clear()
                values.put(MediaStore.Video.Media.IS_PENDING, 0)
                context.contentResolver.update(uri, values, null, null)
                return uri.toString()
            }
        }
        return file.absolutePath
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
            textSize = 34f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        private val artistPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#B8B5C8")
            textSize = 24f
        }
        private val lyricPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textSize = 32f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        private val nextLyricPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#7A7690")
            textSize = 24f
        }
        private val barPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#8B7CFF")
        }
        private val progressPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val artRect = RectF(60f, 90f, w - 60f, 90f + (w - 120f))

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

        fun draw(positionMs: Long, rms: Double) {
            canvas.drawRect(0f, 0f, w.toFloat(), h.toFloat(), backgroundPaint)

            val clip = Path().apply {
                addRoundRect(artRect, 34f, 34f, Path.Direction.CW)
            }
            canvas.save()
            canvas.clipPath(clip)
            if (artwork != null) {
                val src = RectF(0f, 0f, artwork.width.toFloat(), artwork.height.toFloat())
                canvas.drawBitmap(artwork, src.toIntRect(), artRect, Paint(Paint.FILTER_BITMAP_FLAG))
            } else {
                canvas.drawRect(artRect, barPaint)
            }
            canvas.restore()

            var activeIndex = 0
            for (index in lines.indices) {
                if (lines[index].timeMs <= positionMs) activeIndex = index else break
            }
            val activeText = lines.getOrNull(activeIndex)?.text ?: title
            val nextText = lines.getOrNull(activeIndex + 1)?.text ?: ""

            val ellipsis = TextUtils.TruncateAt.END
            canvas.drawText(
                TextUtils.ellipsize(title, titlePaint, (w - 120).toFloat(), ellipsis).toString(),
                60f,
                artRect.bottom + 48f,
                titlePaint,
            )
            canvas.drawText(
                TextUtils.ellipsize(artist, artistPaint, (w - 120).toFloat(), ellipsis).toString(),
                60f,
                artRect.bottom + 84f,
                artistPaint,
            )

            // Live waveform driven by the decoded audio's RMS level.
            val bars = 24
            val gap = 6f
            val barWidth = (w - 120f - gap * (bars - 1)) / bars
            val baseline = h - 210f
            val level = rms.coerceIn(0.02, 1.0)
            for (index in 0 until bars) {
                val shape = abs(
                    kotlin.math.sin(index * 0.7 + positionMs / 240.0),
                )
                val barHeight = (28f + 96f * level * shape).toFloat()
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

            canvas.drawText(
                TextUtils.ellipsize(activeText, lyricPaint, (w - 100).toFloat(), ellipsis).toString(),
                50f,
                h - 130f,
                lyricPaint,
            )
            if (nextText.isNotEmpty()) {
                canvas.drawText(
                    TextUtils.ellipsize(nextText, nextLyricPaint, (w - 100).toFloat(), ellipsis).toString(),
                    50f,
                    h - 88f,
                    nextLyricPaint,
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
