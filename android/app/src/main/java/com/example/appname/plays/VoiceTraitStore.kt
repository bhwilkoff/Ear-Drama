package com.example.appname.plays

import android.content.Context
import android.media.AudioFormat
import android.os.Build
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import androidx.core.content.edit
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * What each device voice sounds like (PLAYS-DESIGN §2.8 rule 12), for its label: [VoiceLabels.SEED] for Google's engine,
 * else measured here once per voice and engine version and kept as four numbers in `ed.voicetraits`, this device only.
 * A voice is measured by reading [VoiceMeasure.SENTENCE] into memory through an engine instance of its own, never aloud;
 * the sound is dropped as soon as it is measured.
 */
object VoiceTraitStore {
    /** Google's engine marks its per-locale stand-ins (`en-US-language`) with this feature. */
    const val ALIAS_FEATURE = "legacySetLanguageVoice"
    const val GOOGLE = "com.google.android.tts"
    private const val PREFS = "ed.voicetraits"
    @Volatile private var running = false
    private val tried = HashSet<String>()

    private fun version(context: Context, engine: String): Long = runCatching {
        val info = context.packageManager.getPackageInfo(engine, 0)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode else @Suppress("DEPRECATION") info.versionCode.toLong()
    }.getOrDefault(0L)

    private fun key(engine: String, version: Long, name: String) = "$engine|$version|$name"

    /** The traits known now for [names]: the seed for Google's engine, else what this device measured for this engine version. */
    fun known(context: Context, engine: String, names: List<String>): Map<String, VoiceTraits> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val v = version(context, engine)
        return names.mapNotNull { n ->
            val t = (if (engine == GOOGLE) VoiceLabels.SEED[n] else null) ?: VoiceTraits.decode(prefs.getString(key(engine, v, n), null))
            t?.let { n to it }
        }.toMap()
    }

    /** Measures [names] one after another off the main thread, then calls [done]; one run at a time, each voice tried once per process. */
    fun measure(context: Context, engine: String, names: List<String>, done: () -> Unit) {
        val app = context.applicationContext
        val todo = synchronized(tried) {
            if (running) return
            names.filter { tried.add("$engine|$it") }.also { if (it.isNotEmpty()) running = true }
        }
        if (todo.isEmpty()) return
        Thread({
            try {
                run(app, engine, todo)
            } finally {
                running = false
            }
            done()
        }, "voice-traits").start()
    }

    private fun run(app: Context, engine: String, names: List<String>) {
        val ready = CountDownLatch(1)
        var ok = false
        val tts = TextToSpeech(app, { status -> ok = status == TextToSpeech.SUCCESS; ready.countDown() }, engine.ifEmpty { null })
        try {
            if (!ready.await(20, TimeUnit.SECONDS) || !ok) return
            val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val v = version(app, engine)
            val voices = tts.voices.orEmpty().associateBy { it.name }
            for (name in names) {
                val voice = voices[name] ?: continue
                if (tts.setVoice(voice) != TextToSpeech.SUCCESS) continue
                tts.setPitch(1f)
                tts.setSpeechRate(1f)
                val (pcm, rate) = render(tts, VoiceMeasure.SENTENCE) ?: continue
                val traits = VoiceMeasure.measure(pcm, rate) ?: continue
                prefs.edit { putString(key(engine, v, name), traits.encode()) }
            }
        } finally {
            runCatching { tts.shutdown() }
        }
    }

    /** One utterance's sound in memory, through the engine's audio callbacks. */
    internal fun render(tts: TextToSpeech, text: String): Pair<FloatArray, Int>? {
        val id = UUID.randomUUID().toString()
        val done = CountDownLatch(1)
        val lock = Any()
        val chunks = ArrayList<FloatArray>()
        var rate = 22_050
        var format = AudioFormat.ENCODING_PCM_16BIT
        var channels = 1
        tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {}
            override fun onDone(utteranceId: String?) { if (utteranceId == id) done.countDown() }
            @Deprecated("Superseded by onError(String, Int)")
            override fun onError(utteranceId: String?) { if (utteranceId == id) done.countDown() }
            override fun onError(utteranceId: String?, errorCode: Int) { if (utteranceId == id) done.countDown() }
            override fun onBeginSynthesis(utteranceId: String?, sampleRateInHz: Int, audioFormat: Int, channelCount: Int) {
                if (utteranceId == id) synchronized(lock) { rate = sampleRateInHz; format = audioFormat; channels = channelCount.coerceAtLeast(1) }
            }
            override fun onAudioAvailable(utteranceId: String?, audio: ByteArray?) {
                if (utteranceId == id && audio != null) synchronized(lock) { chunks += decode(audio, format, channels) }
            }
        })
        val queued = tts.synthesizeToFile(text, Bundle(), DISCARD, id)
        if (queued != TextToSpeech.SUCCESS || !done.await(30, TimeUnit.SECONDS)) return null
        return synchronized(lock) {
            val all = FloatArray(chunks.sumOf { it.size })
            var at = 0
            for (c in chunks) { c.copyInto(all, at); at += c.size }
            all to rate
        }
    }

    /**
     * Where the engine's file copy goes: nowhere. The samples arrive through onAudioAvailable. A pipe cannot stand in:
     * the framework seeks back to write the WAV header when the utterance ends, the seek fails on a pipe ("Illegal seek",
     * Pixel 8a, 2026-11-23), and onDone never comes.
     */
    internal val DISCARD = File("/dev/null")

    private fun decode(bytes: ByteArray, format: Int, channels: Int): FloatArray {
        val buf = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        return when (format) {
            AudioFormat.ENCODING_PCM_FLOAT -> FloatArray(bytes.size / 4 / channels) { buf.getFloat(it * 4 * channels) }
            AudioFormat.ENCODING_PCM_8BIT -> FloatArray(bytes.size / channels) { ((bytes[it * channels].toInt() and 0xFF) - 128) / 128f }
            else -> FloatArray(bytes.size / 2 / channels) { buf.getShort(it * 2 * channels) / 32_768f }
        }
    }
}
