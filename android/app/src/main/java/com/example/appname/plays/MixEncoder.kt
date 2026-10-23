package com.example.appname.plays

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.File
import java.nio.ByteOrder
import kotlin.math.roundToInt

/**
 * The finished mix as `mix.m4a` (PLAYS-DESIGN §4.4, as Apple writes it): AAC-LC,
 * 96 kbps, mono, at the take rate, through MediaCodec into MediaMuxer. It is
 * fed only by [MixRenderer], which reads only human takes.
 */
class AacMixSink(private val file: File, private val sampleRate: Int = TakeAudio.SAMPLE_RATE) : MixSink {
    private val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
    private val muxer = MediaMuxer(file.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
    private val info = MediaCodec.BufferInfo()
    private var track = -1
    private var framesQueued = 0L
    private var released = false

    init {
        val format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, 1).apply {
            setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            setInteger(MediaFormat.KEY_BIT_RATE, 96_000)
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16_384)
        }
        codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        codec.start()
    }

    override fun write(samples: FloatArray, count: Int) {
        var offset = 0
        while (offset < count) {
            val index = codec.dequeueInputBuffer(TIMEOUT_US)
            if (index < 0) {
                drain(false)
                continue
            }
            val input = codec.getInputBuffer(index) ?: continue
            input.clear()
            input.order(ByteOrder.LITTLE_ENDIAN)
            val n = minOf(count - offset, input.remaining() / 2)
            for (i in 0 until n) {
                input.putShort((samples[offset + i].coerceIn(-1f, 1f) * 32_767f).roundToInt().toShort())
            }
            codec.queueInputBuffer(index, 0, n * 2, presentationUs(), 0)
            framesQueued += n
            offset += n
            drain(false)
        }
    }

    override fun finish() {
        while (true) {
            val index = codec.dequeueInputBuffer(TIMEOUT_US)
            if (index >= 0) {
                codec.queueInputBuffer(index, 0, 0, presentationUs(), MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                break
            }
            drain(false)
        }
        drain(true)
        release(stopMuxer = track >= 0)
    }

    override fun abandon() {
        runCatching { release(stopMuxer = false) }
        file.delete()
    }

    private fun presentationUs() = framesQueued * 1_000_000L / sampleRate

    private fun drain(untilEnd: Boolean) {
        while (true) {
            val index = codec.dequeueOutputBuffer(info, TIMEOUT_US)
            when {
                index == MediaCodec.INFO_TRY_AGAIN_LATER -> if (!untilEnd) return
                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    track = muxer.addTrack(codec.outputFormat)
                    muxer.start()
                }
                index >= 0 -> {
                    val output = codec.getOutputBuffer(index)
                    val config = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                    if (output != null && info.size > 0 && !config && track >= 0) {
                        output.position(info.offset).limit(info.offset + info.size)
                        muxer.writeSampleData(track, output, info)
                    }
                    codec.releaseOutputBuffer(index, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
                }
            }
        }
    }

    private fun release(stopMuxer: Boolean) {
        if (released) return
        released = true
        runCatching { codec.stop() }
        codec.release()
        if (stopMuxer) muxer.stop()
        muxer.release()
    }

    private companion object {
        const val TIMEOUT_US = 10_000L
    }
}
