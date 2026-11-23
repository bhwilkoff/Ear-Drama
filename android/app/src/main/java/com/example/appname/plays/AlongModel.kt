package com.example.appname.plays

import android.content.SharedPreferences
import androidx.core.content.edit
import java.io.File
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume

/**
 * The read-along of a production's listen-through or of Hear the cast (PLAYS-DESIGN 2.11): one plan of entries, each a
 * take from its file or a line read live by the part's cast voice, played one after another. The line heard is the
 * entry playing; the word heard is the device voice's own callback mapped onto the printed words (rule 3), and none
 * for a take or a Kokoro line. Pause holds the line (still lit), Play starts it again, previous and next move to the
 * nearest entry (rule 6), and speed is a multiplier on each part's own (rule 7). Nothing is written: text and
 * existing take files only.
 */
class AlongModel(
    private val scope: CoroutineScope,
    private val script: PlayScript,
    private val plan: List<Relay.ListenEntry>,
    private val takesFolder: File?,
    private val speaker: CastSpeaker,
    private val muted: Boolean,
    speed: Double,
    private val onEnd: () -> Unit = {},
) {
    /** What the reader draws: the line held or heard, the word heard in it, and whether the plan is running. */
    data class State(
        val line: String? = null,
        val word: ReadAlong.Word? = null,
        val playing: Boolean = false,
        val device: Boolean = false,
        val part: PartID? = null,
    )

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state

    var speed: Double = ReadAlong.speed(speed)
        set(x) {
            field = ReadAlong.speed(x)
            speaker.speed = field
            playback?.let { p -> p.speed = field.toFloat() }
        }

    private var index = -1
    private var job: Job? = null
    private var playback: MixPlayback? = null
    private val lines = script.lines.associateBy { it.id }

    init { speaker.speed = this.speed }

    val size: Int get() = plan.size
    val position: Int get() = index

    /** Starts the entry at [from] (the held one by default) from its beginning and runs on to the end. */
    fun play(from: Int = index) {
        if (plan.isEmpty()) return
        run(from.coerceIn(0, plan.lastIndex))
    }

    /** Holds the line: whatever is sounding stops and the line stays lit. */
    fun pause() {
        job?.cancel()
        job = null
        speaker.onRange = null
        speaker.cancel()
        playback?.stop()
        _state.update { it.copy(playing = false, word = null) }
    }

    /** The nearest entry before (-1) or after (+1): playing, it goes on from there; paused, it moves the held line. */
    fun step(by: Int) {
        val to = index + by
        if (to !in plan.indices) return
        if (_state.value.playing) {
            speaker.cancel()
            run(to)
        } else {
            index = to
            val e = plan[to]
            _state.update { it.copy(line = e.lineID, word = null, device = e is Relay.ListenEntry.Voice, part = e.part) }
        }
    }

    fun stop() {
        job?.cancel()
        job = null
        speaker.onRange = null
        speaker.cancel()
        playback?.stop()
        speaker.speed = 1.0
        index = -1
        _state.value = State()
    }

    private fun run(from: Int) {
        val old = job
        speaker.onRange = null
        job = scope.launch {
            old?.cancelAndJoin()
            var i = from
            var finished = false
            try {
                while (i in plan.indices) {
                    index = i
                    val e = plan[i]
                    _state.value = State(e.lineID, null, playing = true, device = e is Relay.ListenEntry.Voice, part = e.part)
                    when (e) {
                        is Relay.ListenEntry.TakeEntry -> playTake(File(takesFolder, e.take.file))
                        is Relay.ListenEntry.Voice -> say(e)
                    }
                    i++
                }
                finished = true
            } finally {
                speaker.onRange = null
            }
            if (finished) {
                index = -1
                _state.value = State()
                onEnd()
            }
        }
    }

    private suspend fun say(e: Relay.ListenEntry.Voice) {
        val line = lines[e.lineID]
        val spoken = line?.let { ReadAlong.spoken(it) }
        val said = e.text.replace("_", "").trim()
        speaker.onRange = if (spoken != null && spoken.said == said) { s, end ->
            val w = ReadAlong.word(spoken, s, end - s)
            _state.update { it.copy(word = w) }
        } else null
        try {
            speaker.speak(e.text, e.part)
        } finally {
            speaker.onRange = null
            _state.update { it.copy(word = null) }
        }
    }

    private suspend fun playTake(file: File) {
        val player = MixPlayback().also { it.muted = muted; it.speed = speed.toFloat() }
        playback = player
        try {
            withContext(Dispatchers.Main.immediate) {
                suspendCancellableCoroutine<Unit> { done ->
                    player.onEnded = { if (done.isActive) done.resume(Unit) }
                    runCatching { player.load(file); player.toggle() }.onFailure { if (done.isActive) done.resume(Unit) }
                    done.invokeOnCancellation { player.stop() }
                }
            }
        } catch (c: CancellationException) {
            throw c
        } finally {
            player.stop()
            if (playback === player) playback = null
        }
    }

    companion object {
        /** Hear the cast (rule 1): each speech from [from] on, and a direction or a sound only when its part has a voice. */
        fun tablePlan(script: PlayScript, from: Int, reads: (PartID) -> Boolean): List<Relay.ListenEntry> =
            script.lines.drop(from.coerceAtLeast(0)).mapNotNull { line ->
                if (line.kind != ScriptLine.Kind.Speech && !reads(line.part)) return@mapNotNull null
                if (line.spokenText.isBlank()) return@mapNotNull null
                Relay.ListenEntry.Voice(line.id, line.part, line.spokenText)
            }

        /** The device's remembered speed (`ed.along.speed`, never synced). */
        fun savedSpeed(prefs: SharedPreferences): Double =
            ReadAlong.speed(if (prefs.contains(ReadAlong.SPEED_KEY)) prefs.getFloat(ReadAlong.SPEED_KEY, 1f).toDouble() else null)

        fun saveSpeed(prefs: SharedPreferences, x: Double) = prefs.edit { putFloat(ReadAlong.SPEED_KEY, ReadAlong.speed(x).toFloat()) }
    }
}
