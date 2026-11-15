package com.example.appname.plays

import java.io.File
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.Dispatchers
import kotlin.coroutines.resume

/**
 * The listen-through of a play that is not complete (Decision 067): each take
 * from its file, each speech line without one read aloud by the device voice
 * through `speak`, live, in the part's cast voice (Decision 076 S2: the one cast
 * every player reads, with a part's directions and sound read once given a voice).
 * The voice is a local one only, and nothing here writes a file: it holds text,
 * never audio, and never marks the play listened through.
 */
class LiveListen(private val takesFolder: File, private val speaker: CastSpeaker) {
    private var playback: MixPlayback? = null

    /** The test door's mute (appname_mute): takes play at zero volume (the cast speaker has its own). */
    @Volatile var muted = false

    private val _current = MutableStateFlow<Relay.ListenEntry?>(null)

    /** The entry being heard now, for the speaker and words on screen. */
    val current: StateFlow<Relay.ListenEntry?> = _current

    /** Runs the plan to its end, or until [stop]; a voice line is skipped when its part has no voice here. */
    suspend fun run(plan: List<Relay.ListenEntry>) {
        try {
            for (entry in plan) {
                _current.value = entry
                when (entry) {
                    is Relay.ListenEntry.TakeEntry -> playTake(File(takesFolder, entry.take.file))
                    is Relay.ListenEntry.Voice -> speaker.speak(entry.text, entry.part)
                }
            }
        } finally {
            _current.value = null
        }
    }

    private suspend fun playTake(file: File) {
        val player = MixPlayback().also { it.muted = muted }
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

    fun stop() {
        speaker.cancel()
        playback?.stop()
    }

    fun close() = stop()
}
