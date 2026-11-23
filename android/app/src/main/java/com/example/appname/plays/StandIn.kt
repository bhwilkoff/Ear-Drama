package com.example.appname.plays

import android.content.Context
import android.media.AudioFormat
import android.os.Build
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import java.util.UUID
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.withTimeoutOrNull

/**
 * A device voice reading one line, in memory only (PLAYS-DESIGN §5). It is a
 * scene partner, never a performer: it is played, measured by the bleed check,
 * and released. It is not serializable and has no path to a file, and no file
 * writer in the app accepts it ([TakeAudio.write] takes only a [MicrophoneCapture]).
 */
class StandInAudio(val samples: FloatArray, val sampleRate: Double) {
    init {
        SyntheticPCM.mark(samples)
    }
}

/** Where stand-in lines come from. The app's is the system engine; the tests' is a signal they can look for in every file. */
interface StandInVoice {
    suspend fun render(text: String, part: PartID, rate: Float): StandInAudio?
}

/**
 * The device's text-to-speech engine, collected into memory from
 * `onAudioAvailable` (research 08a §2). On API 30 and later the engine's file copy
 * goes to /dev/null, so nothing is written anywhere; on API 29 the engine speaks at zero volume and the same
 * callback hands over the samples. Only voices that need no network are used
 * (§5 rule 5), so a script line is never sent to a speech server.
 */
class SystemStandInVoice(context: Context, private val cast: VoiceCast) : StandInVoice {
    private val ready = CompletableDeferred<Boolean>()
    private val tts = TextToSpeech(context.applicationContext) { status -> ready.complete(status == TextToSpeech.SUCCESS) }
    private val setter = TtsSetter(tts)
    @Volatile private var pending: Collector? = null

    init {
        tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {}
            override fun onDone(utteranceId: String?) { pending?.takeIf { it.id == utteranceId }?.end() }
            @Deprecated("Superseded by onError(String, Int)")
            override fun onError(utteranceId: String?) { pending?.takeIf { it.id == utteranceId }?.end() }
            override fun onError(utteranceId: String?, errorCode: Int) { pending?.takeIf { it.id == utteranceId }?.end() }
            override fun onBeginSynthesis(utteranceId: String?, sampleRateInHz: Int, audioFormat: Int, channelCount: Int) {
                pending?.takeIf { it.id == utteranceId }?.begin(sampleRateInHz, audioFormat, channelCount)
            }
            override fun onAudioAvailable(utteranceId: String?, audio: ByteArray?) {
                if (audio != null) pending?.takeIf { it.id == utteranceId }?.receive(audio)
            }
        })
    }

    override suspend fun render(text: String, part: PartID, rate: Float): StandInAudio? {
        val words = text.trim()
        if (words.isEmpty() || !ready.await()) return null
        if (!cast.prepare(part, setter, rate)) return null
        val collector = Collector(UUID.randomUUID().toString())
        pending = collector
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                // Not a pipe: its failed header seek left every line waiting the full timeout (VoiceTraitStore.DISCARD).
                if (tts.synthesizeToFile(words, Bundle(), VoiceTraitStore.DISCARD, collector.id) != TextToSpeech.SUCCESS) return null
            } else {
                val silent = Bundle().apply { putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, 0f) }
                if (tts.speak(words, TextToSpeech.QUEUE_FLUSH, silent, collector.id) != TextToSpeech.SUCCESS) return null
            }
            withTimeoutOrNull(RENDER_TIMEOUT_MS) { collector.finished.await() } ?: tts.stop()
            return collector.audio()
        } finally {
            pending = null
        }
    }

    fun close() {
        tts.stop()
        tts.shutdown()
    }

    /** Gathers one utterance's PCM on whatever thread the engine calls back on. */
    private class Collector(val id: String) {
        val finished = CompletableDeferred<Unit>()
        private val lock = Any()
        private var rate = 22_050
        private var format = AudioFormat.ENCODING_PCM_16BIT
        private var channels = 1
        private val chunks = ArrayList<FloatArray>()

        fun begin(sampleRate: Int, audioFormat: Int, channelCount: Int) = synchronized(lock) {
            rate = sampleRate
            format = audioFormat
            channels = channelCount.coerceAtLeast(1)
        }

        fun receive(bytes: ByteArray) = synchronized(lock) {
            val buf = java.nio.ByteBuffer.wrap(bytes).order(java.nio.ByteOrder.LITTLE_ENDIAN)
            val samples = when (format) {
                AudioFormat.ENCODING_PCM_FLOAT -> FloatArray(bytes.size / 4 / channels) { buf.getFloat(it * 4 * channels) }
                AudioFormat.ENCODING_PCM_8BIT -> FloatArray(bytes.size / channels) { ((bytes[it * channels].toInt() and 0xFF) - 128) / 128f }
                else -> FloatArray(bytes.size / 2 / channels) { buf.getShort(it * 2 * channels) / 32_768f }
            }
            chunks += samples
        }

        fun end() {
            finished.complete(Unit)
        }

        fun audio(): StandInAudio? = synchronized(lock) {
            val total = chunks.sumOf { it.size }
            if (total == 0) return null
            val all = FloatArray(total)
            var at = 0
            for (c in chunks) { c.copyInto(all, at); at += c.size }
            chunks.clear()
            StandInAudio(Resample.toTakeRate(all, rate.toDouble()), TakeAudio.SAMPLE_RATE.toDouble())
        }
    }

    private companion object {
        const val RENDER_TIMEOUT_MS = 30_000L
    }
}
