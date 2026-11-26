package com.example.appname.plays

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.File
import java.nio.ByteOrder
import kotlin.math.floor

/**
 * A cue file (AAC `.m4a` from a pack, or anything MediaExtractor reads) as mono float samples at the take rate, so
 * the mix sums cues and takes in one format (B32 §8). Null when the file has no audio track the device can decode.
 */
object CueDecoder {
    private const val TIMEOUT_US = 10_000L

    fun decode(file: File): FloatArray? {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            extractor.setDataSource(file.path)
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: return null
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            val decoder = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME) ?: return null)
            codec = decoder
            decoder.configure(format, null, null, 0)
            decoder.start()
            var rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var floats = false
            var mono = FloatArray(rate)
            var size = 0
            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            while (!outputDone) {
                if (!inputDone) {
                    val index = decoder.dequeueInputBuffer(TIMEOUT_US)
                    if (index >= 0) {
                        val buffer = decoder.getInputBuffer(index) ?: return null
                        val read = extractor.readSampleData(buffer, 0)
                        if (read < 0) {
                            decoder.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            decoder.queueInputBuffer(index, 0, read, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val index = decoder.dequeueOutputBuffer(info, TIMEOUT_US)
                if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val out = decoder.outputFormat
                    rate = out.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    channels = out.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    floats = out.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                        out.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT
                } else if (index >= 0) {
                    val buffer = decoder.getOutputBuffer(index)
                    if (buffer != null && info.size > 0) {
                        buffer.position(info.offset).limit(info.offset + info.size)
                        buffer.order(ByteOrder.nativeOrder())
                        val frames = info.size / ((if (floats) 4 else 2) * channels)
                        if (size + frames > mono.size) mono = mono.copyOf(maxOf(mono.size * 2, size + frames))
                        for (f in 0 until frames) {
                            var sum = 0f
                            for (c in 0 until channels) sum += if (floats) buffer.getFloat() else buffer.getShort() / 32768f
                            mono[size++] = sum / channels
                        }
                    }
                    decoder.releaseOutputBuffer(index, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                }
            }
            return resample(mono.copyOf(size), rate)
        } finally {
            codec?.release()
            extractor.release()
        }
    }

    private fun resample(samples: FloatArray, rate: Int): FloatArray {
        val target = TakeAudio.SAMPLE_RATE
        if (rate == target || samples.isEmpty()) return samples
        val step = rate.toDouble() / target
        return FloatArray((samples.size / step).toInt()) { i ->
            val at = i * step
            val k = floor(at).toInt()
            val next = samples[minOf(k + 1, samples.size - 1)]
            (samples[k] + (next - samples[k]) * (at - k)).toFloat()
        }
    }
}
