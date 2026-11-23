package com.example.appname.plays

import android.content.Context
import androidx.core.content.edit
import android.content.Intent
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * This device's text-to-speech voices for casting (PLAYS-DESIGN §2.8): the engine's voice list,
 * judged castable by [VoiceCasting.castable], and the engine itself for the live readers. Only
 * voices that need no network are cast (§5 rule 5), so a script line is never sent to a speech
 * server. Android sends no broadcast when voices are installed, so [refresh] is called on init and
 * on every resume. Nothing here writes a file.
 */
class DeviceVoiceSource(context: Context) {
    private val app = context.applicationContext
    private val ready = CompletableDeferred<Boolean>()
    @Volatile private var started = false
    @Volatile private var list: List<CastVoice> = emptyList()
    private val _rev = MutableStateFlow(0)

    internal val tts = TextToSpeech(app) { status ->
        started = status == TextToSpeech.SUCCESS
        ready.complete(started)
        refreshOffMain()
    }

    /** Counts every change of the voice list, so a screen can repaint. */
    val rev: StateFlow<Int> = _rev

    /** The castable voices now, best first; empty until the engine is up. */
    fun voices(): List<CastVoice> = list

    suspend fun awaitReady(): Boolean = ready.await()

    /** The engine's voice list is a binder call that parcels every voice: never on the main thread. */
    fun refreshOffMain() {
        Thread({ refresh() }, "voices-refresh").start()
    }

    fun refresh() {
        if (!started) return
        val raw = runCatching {
            val defaultName = runCatching { tts.defaultVoice?.name }.getOrNull()
            (tts.voices ?: emptySet()).map {
                RawVoice(
                    name = it.name,
                    localeTag = it.locale.toLanguageTag(),
                    quality = it.quality,
                    networkRequired = it.isNetworkConnectionRequired,
                    notInstalled = TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED in (it.features ?: emptySet()),
                    isDefault = it.name == defaultName,
                    alias = VoiceTraitStore.ALIAS_FEATURE in (it.features ?: emptySet()),
                )
            }
        }.getOrDefault(emptyList())
        val engine = runCatching { tts.defaultEngine }.getOrNull().orEmpty()
        val ids = VoiceCasting.castable(raw).map { it.id }
        val traits = VoiceTraitStore.known(app, engine, ids)
        val next = VoiceCasting.castable(raw, traits = traits)
        if (next != list) {
            list = next
            _rev.value += 1
        }
        val missing = ids.filter { it !in traits }
        if (missing.isNotEmpty()) VoiceTraitStore.measure(app, engine, missing) { refreshOffMain() }
    }

    /** The engine's installer for more voices, or null when no activity answers (the button is then hidden). */
    fun installIntent(): Intent? {
        val intent = Intent(TextToSpeech.Engine.ACTION_INSTALL_TTS_DATA).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return intent.takeIf { app.packageManager.resolveActivity(it, 0) != null }
    }

    fun close() {
        runCatching { tts.stop() }
        runCatching { tts.shutdown() }
    }
}

/** The engine-wide settings a part's casting sets before each utterance. */
internal class TtsSetter(private val tts: TextToSpeech) : VoiceSetter {
    override fun setVoice(id: String): Boolean {
        val voice: Voice = runCatching { tts.voices?.firstOrNull { it.name == id } }.getOrNull() ?: return false
        return tts.setVoice(voice) == TextToSpeech.SUCCESS
    }

    override fun setPitch(pitch: Float) { tts.setPitch(pitch) }
    override fun setSpeechRate(rate: Float) { tts.setSpeechRate(rate) }
}

/**
 * The device voice reading one line aloud, live, through the part's cast voice, speed and pitch;
 * a scene partner, never a performer (§5): it is spoken through the system output and never kept.
 * The same speaker previews a voice in the picker with the part's own first line. A part cast to a
 * downloaded voice is read by [kokoro] from [playId]'s published phonemes, and by the part's auto-cast
 * system voice when Kokoro cannot read the line (no model, no phonemes, a refused render).
 */
class CastSpeaker(
    private val source: DeviceVoiceSource,
    val cast: VoiceCast,
    private val kokoro: com.example.appname.kokoro.KokoroLive? = null,
    private val playId: String? = null,
) : LineSpeaker {
    @Volatile private var speaking: CompletableDeferred<Unit>? = null
    @Volatile private var speakingId: String? = null
    /** The test door's mute (appname_mute): lines pass in time but nothing is voiced. */
    @Volatile var muted: Boolean = false

    /** The read-along's speed (PLAYS-DESIGN 2.11 rule 7): a multiplier on each part's own speed, read at each line. */
    @Volatile var speed: Double = 1.0

    /**
     * The device voice's own word callback (UtteranceProgressListener.onRangeStart): the range of the string the voice
     * was given, set by the read-along before a line and cleared after. A voice that sends none leaves the line lit only.
     */
    @Volatile var onRange: ((start: Int, end: Int) -> Unit)? = null
    private val setter = TtsSetter(source.tts)

    init {
        source.tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {}
            override fun onRangeStart(utteranceId: String?, start: Int, end: Int, frame: Int) {
                if (utteranceId == speakingId) onRange?.invoke(start, end)
            }
            override fun onDone(utteranceId: String?) { finish(utteranceId) }
            @Deprecated("Superseded by onError(String, Int)")
            override fun onError(utteranceId: String?) { finish(utteranceId) }
            override fun onError(utteranceId: String?, errorCode: Int) { finish(utteranceId) }
        })
    }

    private fun finish(id: String?) {
        if (id == speakingId) speaking?.complete(Unit)
    }

    override fun reads(part: PartID): Boolean = source.voices().isNotEmpty() && cast.resolve(part).read

    override suspend fun speak(text: String, part: PartID): Boolean {
        val words = said(text)
        if (words.isEmpty()) return false
        val r = cast.resolve(part)
        val v = r.voice
        if (r.read && v != null && v.engine == VoiceCastEntry.KOKORO && kokoro != null && playId != null) {
            if (kokoro.speak(playId, text, v.id, r.rate * speed, r.pitch, muted)) return true
        }
        if (!source.awaitReady()) return false
        if (!cast.prepare(part, setter, speed.toFloat())) return false
        return say(words)
    }

    /** The picker's preview: [text] in a voice not yet chosen, at the part's speed and pitch. Live, never kept. */
    suspend fun speakAs(text: String, voice: CastVoice, rate: Double, pitch: Double): Boolean {
        val words = said(text)
        if (words.isEmpty()) return false
        cancel()
        if (voice.engine == VoiceCastEntry.KOKORO) {
            if (kokoro != null && playId != null && kokoro.speak(playId, text, voice.id, rate, pitch, muted)) return true
            // A line Kokoro cannot read falls to a device voice, never to silence (PLAYS-DESIGN 2.8 rule 10).
            val device = source.voices().let { all -> all.firstOrNull { it.gender == voice.gender } ?: all.firstOrNull() } ?: return false
            return speakAs(text, device, rate, pitch)
        }
        if (!source.awaitReady()) return false
        if (!setter.setVoice(voice.id)) return false
        setter.setPitch(pitch.toFloat())
        setter.setSpeechRate(rate.toFloat().coerceIn(0.1f, 10f))
        return say(words)
    }

    private suspend fun say(words: String): Boolean {
        val id = UUID.randomUUID().toString()
        val done = CompletableDeferred<Unit>()
        speaking = done
        speakingId = id
        try {
            // Muted (the test door) speaks at volume 0: the engine runs in real time and still sends its word callbacks.
            val params = Bundle().apply { if (muted) putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, 0f) }
            if (source.tts.speak(words, TextToSpeech.QUEUE_FLUSH, params, id) != TextToSpeech.SUCCESS) {
                if (muted) kotlinx.coroutines.delay(300L)
                return muted
            }
            done.await()
            return true
        } catch (e: CancellationException) {
            source.tts.stop()
            throw e
        } finally {
            if (speakingId == id) {
                speaking = null
                speakingId = null
            }
        }
    }

    override fun cancel() {
        source.tts.stop()
        speaking?.complete(Unit)
        kokoro?.cancel()
    }


    private fun said(text: String) = text.replace("_", "").trim()
}

/** The voice defaults beside the cast, in the same preferences file under `ed.voices`; this device only (Decision 086). */
class PrefsDefaultsStore(context: Context) : CastStore {
    private val prefs = context.applicationContext.getSharedPreferences(VoiceCasting.KEY, Context.MODE_PRIVATE)
    override fun read(): String? = prefs.getString(VoiceDefaultsStore.KEY, null)
    override fun write(text: String) { prefs.edit { putString(VoiceDefaultsStore.KEY, text) } }
}

/** The cast kept in this device's SharedPreferences, never synced (PLAYS-DESIGN §2.8 rule 3). */
class PrefsCastStore(context: Context) : CastStore {
    private val prefs = context.applicationContext.getSharedPreferences(VoiceCasting.KEY, Context.MODE_PRIVATE)
    override fun read(): String? = prefs.getString(VoiceCasting.KEY, null)
    override fun write(text: String) { prefs.edit { putString(VoiceCasting.KEY, text) } }
}
