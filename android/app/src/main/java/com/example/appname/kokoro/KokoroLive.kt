package com.example.appname.kokoro

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import com.example.appname.plays.Resample
import com.example.appname.plays.SyntheticPCM
import com.example.appname.plays.TakeAudio
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

/**
 * A Kokoro line read aloud once, live (§5: a scene partner, never a performer): each render is played through an
 * AudioTrack as it is made and dropped. Pitch is the playback rate, the model's speed carries the tempo
 * ([Kokoro.speedFor]), as on the web. Muted (the test door), nothing reaches an output at all: the line is rendered
 * and passes in a moment. Writes nothing.
 */
class KokoroLive(private val reader: KokoroReader) {
    @Volatile private var track: AudioTrack? = null
    @Volatile private var stopped = false

    /** True when Kokoro read the line; false when it cannot (the caller then reads it with the system voice). */
    suspend fun speak(playId: String, text: String, voiceId: String, rate: Double, pitch: Double, muted: Boolean): Boolean {
        stopped = false
        val speed = Kokoro.speedFor(rate, pitch)
        return reader.renderPieces(playId, text, voiceId, speed) { piece ->
            if (stopped) return@renderPieces
            if (muted) delay(MUTED_MS) else play(Resample.toTakeRate(piece, Kokoro.SAMPLE_RATE * pitch).also(SyntheticPCM::mark))
        }
    }

    private suspend fun play(samples: FloatArray) {
        val t = AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            .setAudioFormat(
                AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_FLOAT).setSampleRate(TakeAudio.SAMPLE_RATE)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build(),
            )
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
        track = t
        try {
            t.play()
            withContext(Dispatchers.IO) { t.write(samples, 0, samples.size, AudioTrack.WRITE_BLOCKING) }
            val deadline = System.currentTimeMillis() + 2_000 + samples.size * 1000L / TakeAudio.SAMPLE_RATE
            while (!stopped && t.playbackHeadPosition < samples.size && System.currentTimeMillis() < deadline) delay(20)
        } finally {
            track = null
            runCatching { t.stop() }
            t.release()
        }
    }

    fun cancel() {
        stopped = true
        track?.let { runCatching { it.pause(); it.flush() } }
    }

    private companion object {
        const val MUTED_MS = 300L
    }
}
