package com.example.appname.plays

import java.util.UUID
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * One performer recording one part (PLAYS-DESIGN §2.3-2.4) in one of the three modes of owner
 * ruling 4 (Run through, Line by line, Step): five seconds of room tone, then for each line the
 * cue before it (a human take where one exists, the device voice live where not), then the device
 * listens until the line ends or the performer stops. Only the microphone window is kept. The
 * same machine as apple/Core/Plays/RecordingSession.swift and js/plays-session.js; every call is
 * on the main thread.
 */
class RecordingSession(
    production: Production,
    val script: PlayScript,
    val part: PartID,
    private val store: ProductionStore,
    private val audio: LiveAudio,
    private val voice: StandInVoice,
    private val wait: suspend (Long) -> Unit = { delay(it) },
    /** Says "Your line" to a screen reader before listening starts, and returns once it has been said (§7). */
    private val announce: suspend () -> Unit = {},
) {
    /** Run through, Line by line, or Step (owner ruling 4); only what follows a take differs. */
    enum class Mode { Run, Lines, Step }

    /** The run on screen (Run through): its first line, and per line the take it had and the takes the run made. */
    data class RunState(val from: String, val takes: List<RunNote>)

    sealed interface Phase {
        data object Idle : Phase
        data class RoomTone(val secondsLeft: Int) : Phase
        /** A cue line is playing; [deviceVoice] labels a stand-in on screen (§5 rule 3); [run] is Run through's pass. */
        data class Cue(val lineID: String, val deviceVoice: Boolean, val run: Boolean = false) : Phase
        data class Listening(val lineID: String, val run: Boolean = false) : Phase
        data class Review(val lineID: String) : Phase
        /** The run's takes, each to be heard, taken Again, then kept or discarded. */
        data object RunReview : Phase
        data class Failed(val message: String) : Phase
    }

    private val _phase = MutableStateFlow<Phase>(Phase.Idle)
    val phase: StateFlow<Phase> = _phase
    private val _production = MutableStateFlow(production)
    val production: StateFlow<Production> = _production
    private val _mode = MutableStateFlow(Mode.Step)
    val mode: StateFlow<Mode> = _mode
    private val _run = MutableStateFlow<RunState?>(null)
    val run: StateFlow<RunState?> = _run
    private var runToken = 0
    private var cueToken = 0
    private val _level = MutableStateFlow(0f)

    /** The microphone's level while a line is being taken, 0 to 1, for the live meter. */
    val level: StateFlow<Float> = _level

    /** The stand-in's speed, adjustable (§7). */
    var standInRate = 1f
    var started = false
        private set
    var echoCancelled = false
        private set
    var lastTakeBleed = false
        private set

    private var detector: LineEndDetector? = null
    private var roomToneRMS = 0f
    private var listening: CompletableDeferred<Unit>? = null

    /** The stand-ins played for the line being taken, held only until the bleed check has read them (§5 rules 1-2). */
    private var heldStandIns = ArrayList<StandInAudio>()

    val lines: List<ScriptLine> get() = script.lines(part)

    val isBusy: Boolean
        get() = when (_phase.value) {
            is Phase.RoomTone, is Phase.Cue, is Phase.Listening -> true
            else -> false
        }

    suspend fun begin(echoCancelled: Boolean) {
        if (started) return
        try {
            audio.start(echoCancelled)
        } catch (e: Exception) {
            _phase.value = Phase.Failed(e.message ?: "The microphone could not be opened.")
            return
        }
        this.echoCancelled = echoCancelled
        started = true
        audio.beginCapture { }
        for (second in ROOM_TONE_SECONDS downTo 1) {
            _phase.value = Phase.RoomTone(second)
            wait(1_000)
        }
        val tone = audio.endCapture()
        roomToneRMS = LineEndDetector.rms(tone.samples)
        if (tone.samples.isNotEmpty()) {
            runCatching { store.writeRoomTone(tone, _production.value) }.getOrNull()?.let { name ->
                mutate { it.copy(roomTone = it.roomTone + name) }
            }
        }
        _phase.value = Phase.Idle
    }

    /** Plays the cue lines (a usable human take where one exists, the device voice live where not); [heard] says what each was. */
    private suspend fun playCues(cues: List<ScriptLine>, heard: MutableMap<String, String>, live: () -> Boolean = { started }) {
        for (cue in cues) {
            if (!live()) return
            val take = _production.value.usableTake(cue.id)
            if (take != null) {
                _phase.value = Phase.Cue(cue.id, deviceVoice = false, run = _run.value != null)
                audio.play(CueAudio.TakeFile(store.takeFile(_production.value, take)))
                heard[cue.id] = take.id
            } else {
                val line = voice.render(cue.spokenText, cue.part, standInRate) ?: continue
                if (!live()) return
                _phase.value = Phase.Cue(cue.id, deviceVoice = true, run = _run.value != null)
                heldStandIns += line
                audio.play(CueAudio.StandIn(line))
                heard[cue.id] = Take.STAND_IN
            }
        }
    }

    /** Opens the microphone on a line until it ends (or Stop), and keeps the line window as a new take; null when nothing was kept. */
    private suspend fun listenAndKeep(lineID: String, heard: Map<String, String>): Take? {
        announce()
        if (!started) return null
        _phase.value = Phase.Listening(lineID, run = _run.value != null)
        detector = LineEndDetector(TakeAudio.SAMPLE_RATE.toDouble(), roomToneRMS)
        val done = CompletableDeferred<Unit>()
        listening = done
        audio.beginCapture { chunk -> hear(chunk) }
        done.await()
        val capture = audio.endCapture()
        val window = LineEndDetector.window(detector?.onset, detector?.end, capture.samples.size, capture.sampleRate)
        detector = null
        val kept = capture.slice(window)
        val bleed = heldStandIns.any {
            BleedCheck.score(kept.samples, it.samples, kept.sampleRate) >= BleedCheck.THRESHOLD
        }
        heldStandIns = ArrayList()
        if (!started || kept.samples.isEmpty()) return null
        return try {
            val file = store.writeTake(kept, _production.value, lineID)
            val take = Take(
                id = UUID.randomUUID().toString().uppercase(),
                lineID = lineID,
                part = part,
                file = file,
                created = ReferenceDate.now(),
                frames = kept.samples.size,
                sampleRate = kept.sampleRate,
                capture = if (echoCancelled) Take.Capture.Aec else Take.Capture.Direct,
                heard = heard,
                loudness = BS1770.integratedLoudness(kept.samples, kept.sampleRate),
                peak = BS1770.samplePeak(kept.samples),
                bleed = bleed,
            )
            mutate { it.add(take) }
            lastTakeBleed = bleed
            take
        } catch (e: Exception) {
            _phase.value = Phase.Failed(e.message ?: "The take could not be saved.")
            null
        }
    }

    /** Remembers a take the run made, with the take its line had before, for Discard the run. */
    private fun noteRun(lineID: String, take: Take, prior: String?) {
        val run = _run.value ?: return
        val at = run.takes.indexOfFirst { it.lineID == lineID }
        val notes = if (at >= 0) {
            run.takes.toMutableList().also { it[at] = it[at].copy(takes = it[at].takes + take.id) }
        } else {
            run.takes + RunNote(lineID, prior, listOf(take.id))
        }
        _run.value = run.copy(takes = notes)
    }

    /**
     * Step and Line by line: plays the cue, then listens for the performer's line and keeps it as a
     * new take (the line's chosen one; older takes stay). Step ends on the take's review, Line by
     * line on the line, ready; Again in a run's review returns to the review.
     */
    suspend fun record(lineID: String, runUp: Boolean = false) {
        if (!started || isBusy) return
        val prior = _production.value.chosen[lineID]
        val heard = LinkedHashMap<String, String>()
        heldStandIns = ArrayList()
        val token = ++cueToken
        playCues(Relay.cueLines(lineID, script, runUp), heard) { started && token == cueToken }
        if (!started) return
        if (token != cueToken) {
            heldStandIns = ArrayList()
            _phase.value = Phase.Idle
            return
        }
        val take = listenAndKeep(lineID, heard)
        if (!started || _phase.value is Phase.Failed) return
        if (_run.value != null) {
            if (take != null) noteRun(lineID, take, prior)
            _phase.value = Phase.RunReview
        } else if (take == null) {
            _phase.value = Phase.Idle
        } else {
            _phase.value = if (_mode.value == Mode.Step) Phase.Review(lineID) else Phase.Idle
        }
    }

    /**
     * Run through (owner ruling 4): the play runs straight through from the line's cue, other parts
     * in their human takes or the device voice live, and the microphone opens on each of this part's
     * lines as it comes; the line-end detector closes it and the play goes on. The run ends after
     * the part's last line or at [pause], and opens its review. No new write path: a take is
     * written by the same [listenAndKeep] as [record].
     */
    suspend fun runThrough(fromLineID: String) {
        if (!started || isBusy || _run.value != null) return
        val token = ++runToken
        _run.value = RunState(fromLineID, emptyList())
        val live = { started && token == runToken }
        var heard = LinkedHashMap<String, String>()
        heldStandIns = ArrayList()
        for (entry in Relay.runPlan(_production.value, script, part, fromLineID)) {
            if (!live()) break
            val line = script.lines.firstOrNull { it.id == entry.lineID } ?: continue
            if (entry is Relay.RunEntry.Mine) {
                val prior = _production.value.chosen[line.id]
                val take = listenAndKeep(line.id, heard)
                if (!started || _phase.value is Phase.Failed) return
                if (take != null) noteRun(line.id, take, prior)
                heard = LinkedHashMap()
            } else {
                playCues(listOf(line), heard, live)
            }
        }
        if (!started) return
        if (_run.value?.takes.orEmpty().isNotEmpty()) {
            _phase.value = Phase.RunReview
        } else {
            _run.value = null
            _phase.value = Phase.Idle
        }
    }

    /** Cancel while a cue plays before a line (Step, Line by line): the cue stops and nothing is recorded. */
    fun cancel() {
        if (_phase.value !is Phase.Cue || _run.value != null) return
        cueToken += 1
        audio.stopPlayback()
    }

    /** Pause ends a run; a line being recorded is kept as far as it went. */
    fun pause() {
        if (_run.value == null || _phase.value is Phase.RunReview) return
        runToken += 1
        if (_phase.value is Phase.Listening) finishListening() else audio.stopPlayback()
    }

    private val runEnded: Boolean get() = _phase.value is Phase.RunReview || _phase.value is Phase.Failed

    /** Keep N takes: the run's takes stay their lines' chosen ones. */
    fun keepRun() {
        if (_run.value == null || !runEnded) return
        _run.value = null
        _phase.value = Phase.Idle
    }

    /** Discard the run: its takes are deleted and each line goes back to the take it had. */
    fun discardRun() {
        val run = _run.value ?: return
        if (!runEnded) return
        _run.value = null
        store.discardRun(_production.value.id, run.takes)
        _production.value = store.production(_production.value.id) ?: _production.value
        _phase.value = Phase.Idle
    }

    /** The takes the run on screen made, in script order, each its line's latest. */
    fun runTakes(): List<Take> = _run.value?.takes.orEmpty().mapNotNull { _production.value.take(it.takes.last()) }

    /** After a playback, back to where it started from (a cue or listening phase is never the place to return to). */
    private fun settle(back: Phase) {
        if (started) _phase.value = if (back is Phase.Cue || back is Phase.Listening) Phase.Idle else back
    }

    /** The cue alone, heard before recording a line (Line by line's Cue); nothing is kept. */
    suspend fun playCue(lineID: String) {
        if (!started || isBusy) return
        val back = _phase.value
        heldStandIns = ArrayList()
        playCues(Relay.cueLines(lineID, script, runUp = false), LinkedHashMap())
        heldStandIns = ArrayList()
        settle(back)
    }

    /** A take heard after its cue, as it will sit in the play (Step's With cue, the run's review); nothing is kept. */
    suspend fun playWithCue(take: Take) {
        if (!started || isBusy) return
        val back = _phase.value
        heldStandIns = ArrayList()
        playCues(Relay.cueLines(take.lineID, script, runUp = false), LinkedHashMap())
        heldStandIns = ArrayList()
        if (!started) return
        _phase.value = Phase.Cue(take.lineID, deviceVoice = false, run = _run.value != null)
        audio.play(CueAudio.TakeFile(store.takeFile(_production.value, take)))
        settle(back)
    }

    /** The mode control: refused while the microphone is armed or open, and during a run. */
    fun setMode(mode: Mode): Boolean {
        if (isBusy || _run.value != null) return false
        _mode.value = mode
        if (_phase.value is Phase.Review) _phase.value = Phase.Idle
        return true
    }

    /** The one control's second press: stop listening now. */
    fun stopListening() {
        if (_phase.value is Phase.Listening) finishListening()
    }

    /** "Hear it read": the device voice reads the performer's own line once, on request, as a rehearsal aid. Never kept. */
    suspend fun hearItRead(lineID: String) {
        if (!started || isBusy) return
        val back = _phase.value
        val line = script.lines.firstOrNull { it.id == lineID } ?: return
        val audioLine = voice.render(line.spokenText, line.part, standInRate) ?: return
        _phase.value = Phase.Cue(lineID, deviceVoice = true)
        audio.play(CueAudio.StandIn(audioLine))
        settle(back)
    }

    suspend fun playTake(take: Take) {
        if (!started || isBusy) return
        val back = _phase.value
        _phase.value = Phase.Cue(take.lineID, deviceVoice = false, run = _run.value != null)
        audio.play(CueAudio.TakeFile(store.takeFile(_production.value, take)))
        settle(back)
    }

    fun choose(take: Take) = mutate { it.choose(take.id) }

    /** Changes the store's current record, never a stale copy: the cast sheet may have moved the relay on. */
    private fun mutate(change: (Production) -> Production) {
        val latest = change(store.production(_production.value.id) ?: _production.value)
        store.save(latest)
        _production.value = latest
    }

    fun end() {
        runToken += 1
        started = false
        finishListening()
        audio.stopPlayback()
        audio.stop()
        _phase.value = Phase.Idle
    }

    private fun hear(chunk: FloatArray) {
        val d = detector ?: return
        if (listening == null) return
        _level.value = (LineEndDetector.rms(chunk) * LEVEL_GAIN).coerceIn(0f, 1f)
        if (d.feed(chunk) is LineEndDetector.Event.End) finishListening()
    }

    private fun finishListening() {
        val done = listening
        listening = null
        done?.complete(Unit)
    }

    companion object {
        const val ROOM_TONE_SECONDS = 5
        private const val LEVEL_GAIN = 6f
    }
}
