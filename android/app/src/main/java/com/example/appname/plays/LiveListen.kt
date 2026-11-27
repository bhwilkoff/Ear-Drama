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
class LiveListen(
    private val takesFolder: File,
    private val speaker: LineSpeaker,
    /** The take-playing seam; the app's is a MediaPlayer, the tests' a fake. */
    private val takePlayer: (suspend (File) -> Unit)? = null,
) {
    private var playback: MixPlayback? = null

    /** The test door's mute (appname_mute): takes play at zero volume (the cast speaker has its own). */
    @Volatile var muted = false

    /** The device's remembered read-along speed (PLAYS-DESIGN 2.11 rules 7 and 10): the TV has no control but plays at it. */
    @Volatile var speed = 1.0

    private val _current = MutableStateFlow<Relay.ListenEntry?>(null)

    /** The entry being heard now, for the speaker and words on screen. */
    val current: StateFlow<Relay.ListenEntry?> = _current

    /**
     * Runs the plan to its end, or until [stop]; a voice line is skipped when its part has no voice here. [cues] (B32 4.4) plays
     * the Sound part's sounds at their entries, ducked while each entry sounds; [range] limits the run to those plan entries
     * (Hear it in place).
     */
    suspend fun run(plan: List<Relay.ListenEntry>, cues: ListenCues? = null, range: IntRange? = null) {
        (speaker as? CastSpeaker)?.speed = speed
        cuePlayer = cues?.player
        val running = ArrayList<LiveCueHandle>()
        try {
            for ((i, entry) in plan.withIndex()) {
                if (range != null && i !in range) continue
                val at = cues?.entries?.getOrNull(i)
                if (cues != null && at != null) {
                    for (c in at.before) cues.player.start(c, cues.file(c.sound.src))?.done()
                    for (c in at.under) cues.player.start(c, cues.file(c.sound.src))?.let(running::add)
                }
                _current.value = entry
                running.forEach { it.duck(true) }
                when (entry) {
                    is Relay.ListenEntry.TakeEntry -> playTake(File(takesFolder, entry.take.file))
                    is Relay.ListenEntry.Voice -> speaker.speak(entry.text, entry.part)
                }
                running.forEach { it.duck(false) }
                if (cues != null && at != null) {
                    for (c in at.after) cues.player.start(c, cues.file(c.sound.src))?.done()
                    for (id in at.stop) running.filter { it.soundID == id }.forEach { it.stop() }
                }
            }
            if (cues != null) running.filter { !it.isBed }.forEach { it.done() }
        } finally {
            cuePlayer?.stopAll()
            cuePlayer = null
            (speaker as? CastSpeaker)?.speed = 1.0
            _current.value = null
        }
    }

    private var cuePlayer: ListenCuePlayer? = null

    private suspend fun playTake(file: File) {
        takePlayer?.let { it(file); return }
        val player = MixPlayback().also { it.muted = muted; it.speed = speed.toFloat() }
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
        cuePlayer?.stopAll()
    }

    fun close() = stop()
}
