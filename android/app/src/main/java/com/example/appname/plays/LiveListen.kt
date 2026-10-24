package com.example.appname.plays

import android.content.Context
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import java.io.File
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.Dispatchers
import kotlin.coroutines.resume

/**
 * The listen-through of a play that is not complete (Decision 067): each take
 * from its file, each speech line without one read aloud by the device voice
 * through `speak`, live. The voice is a local one only, and nothing here
 * writes a file: it holds text, never audio, and never marks the play
 * listened through.
 */
class LiveListen(context: Context, private val takesFolder: File) {
    private val ready = CompletableDeferred<Boolean>()
    private val tts = TextToSpeech(context.applicationContext) { status -> ready.complete(status == TextToSpeech.SUCCESS) }
    private val assigned = HashMap<PartID, Int>()
    @Volatile private var speaking: CompletableDeferred<Unit>? = null
    @Volatile private var speakingId: String? = null
    private var playback: MixPlayback? = null

    private val _current = MutableStateFlow<Relay.ListenEntry?>(null)

    /** The entry being heard now, for the speaker and words on screen. */
    val current: StateFlow<Relay.ListenEntry?> = _current

    init {
        tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {}
            override fun onDone(utteranceId: String?) { finish(utteranceId) }
            @Deprecated("Superseded by onError(String, Int)")
            override fun onError(utteranceId: String?) { finish(utteranceId) }
            override fun onError(utteranceId: String?, errorCode: Int) { finish(utteranceId) }
        })
    }

    private fun finish(id: String?) {
        if (id == speakingId) speaking?.complete(Unit)
    }

    private fun localVoices(): List<Voice> {
        val here = Locale.getDefault()
        return (tts.voices ?: emptySet()).filter {
            !it.isNetworkConnectionRequired && it.locale.language == "en" &&
                TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED !in it.features
        }.sortedWith(compareByDescending<Voice> { it.locale == here }.thenByDescending { it.quality }.thenBy { it.name })
    }

    /** Runs the plan to its end, or until [stop]; a voice line is skipped when the device has no local voice. */
    suspend fun run(plan: List<Relay.ListenEntry>) {
        val voiceReady = ready.await()
        val voices = if (voiceReady) localVoices() else emptyList()
        try {
            for (entry in plan) {
                _current.value = entry
                when (entry) {
                    is Relay.ListenEntry.TakeEntry -> playTake(File(takesFolder, entry.take.file))
                    is Relay.ListenEntry.Voice -> if (voices.isNotEmpty()) speak(entry, voices)
                }
            }
        } finally {
            _current.value = null
        }
    }

    private suspend fun playTake(file: File) {
        val player = MixPlayback()
        playback = player
        try {
            withContext(Dispatchers.Main.immediate) {
                suspendCancellableCoroutine { done ->
                    player.onEnded = { if (done.isActive) done.resume(Unit) }
                    runCatching { player.load(file); player.toggle() }.onFailure { if (done.isActive) done.resume(Unit) }
                    done.invokeOnCancellation { player.stop() }
                }
            }
        } finally {
            player.stop()
            playback = null
        }
    }

    private suspend fun speak(entry: Relay.ListenEntry.Voice, voices: List<Voice>) {
        val words = entry.text.trim()
        if (words.isEmpty()) return
        val index = assigned.getOrPut(entry.part) { assigned.size }
        tts.voice = voices[index % voices.size]
        tts.setPitch(PITCHES[(index / voices.size) % PITCHES.size])
        val id = UUID.randomUUID().toString()
        val done = CompletableDeferred<Unit>()
        speaking = done
        speakingId = id
        try {
            if (tts.speak(words, TextToSpeech.QUEUE_FLUSH, Bundle(), id) != TextToSpeech.SUCCESS) return
            done.await()
        } finally {
            speaking = null
            speakingId = null
        }
    }

    fun stop() {
        tts.stop()
        speaking?.complete(Unit)
        playback?.stop()
    }

    fun close() {
        stop()
        tts.shutdown()
    }

    private companion object {
        val PITCHES = floatArrayOf(1.0f, 0.86f, 1.14f, 0.93f, 1.07f)
    }
}
