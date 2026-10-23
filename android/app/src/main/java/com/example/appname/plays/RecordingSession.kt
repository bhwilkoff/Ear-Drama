package com.example.appname.plays

import java.util.UUID
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * One performer recording one part, line by line (PLAYS-DESIGN §2.3-2.4):
 * five seconds of room tone, then for each line the cue before it (a human
 * take where one exists, the device voice live where not), then the device
 * listens until the performer stops. Only the microphone window is kept. The
 * same machine as apple/Core/Plays/RecordingSession.swift; every call is on
 * the main thread.
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
    sealed interface Phase {
        data object Idle : Phase
        data class RoomTone(val secondsLeft: Int) : Phase
        /** A cue line is playing; [deviceVoice] labels a stand-in on screen (§5 rule 3). */
        data class Cue(val lineID: String, val deviceVoice: Boolean) : Phase
        data class Listening(val lineID: String) : Phase
        data class Review(val lineID: String) : Phase
        data class Failed(val message: String) : Phase
    }

    private val _phase = MutableStateFlow<Phase>(Phase.Idle)
    val phase: StateFlow<Phase> = _phase
    private val _production = MutableStateFlow(production)
    val production: StateFlow<Production> = _production

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

    /** Plays the cue, then listens for the performer's line and keeps it as a new take (the line's chosen one; older takes stay). */
    suspend fun record(lineID: String, runUp: Boolean = false) {
        if (!started || isBusy) return
        val heard = LinkedHashMap<String, String>()
        heldStandIns = ArrayList()
        for (cue in Relay.cueLines(lineID, script, runUp)) {
            val take = _production.value.chosenTake(cue.id)
            if (take != null) {
                _phase.value = Phase.Cue(cue.id, deviceVoice = false)
                audio.play(CueAudio.TakeFile(store.takeFile(_production.value, take)))
                heard[cue.id] = take.id
            } else {
                val line = voice.render(cue.spokenText, cue.part, standInRate) ?: continue
                _phase.value = Phase.Cue(cue.id, deviceVoice = true)
                heldStandIns += line
                audio.play(CueAudio.StandIn(line))
                heard[cue.id] = Take.STAND_IN
            }
        }
        announce()
        _phase.value = Phase.Listening(lineID)
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
        if (kept.samples.isEmpty()) {
            _phase.value = Phase.Idle
            return
        }
        try {
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
            _phase.value = Phase.Review(lineID)
        } catch (e: Exception) {
            _phase.value = Phase.Failed(e.message ?: "The take could not be saved.")
        }
    }

    /** The one control's second press: stop listening now. */
    fun stopListening() {
        if (_phase.value is Phase.Listening) finishListening()
    }

    /** "Hear it read": the device voice reads the performer's own line once, on request, as a rehearsal aid. Never kept. */
    suspend fun hearItRead(lineID: String) {
        if (!started || isBusy) return
        val line = script.lines.firstOrNull { it.id == lineID } ?: return
        val audioLine = voice.render(line.spokenText, line.part, standInRate) ?: return
        _phase.value = Phase.Cue(lineID, deviceVoice = true)
        audio.play(CueAudio.StandIn(audioLine))
        _phase.value = Phase.Idle
    }

    suspend fun playTake(take: Take) {
        if (!started || isBusy) return
        _phase.value = Phase.Cue(take.lineID, deviceVoice = false)
        audio.play(CueAudio.TakeFile(store.takeFile(_production.value, take)))
        _phase.value = Phase.Review(take.lineID)
    }

    fun choose(take: Take) = mutate { it.choose(take.id) }

    /** Changes the store's current record, never a stale copy: the cast sheet may have moved the relay on. */
    private fun mutate(change: (Production) -> Production) {
        val latest = change(store.production(_production.value.id) ?: _production.value)
        store.save(latest)
        _production.value = latest
    }

    fun end() {
        finishListening()
        audio.stop()
        started = false
        _phase.value = Phase.Idle
    }

    private fun hear(chunk: FloatArray) {
        val d = detector ?: return
        if (listening == null) return
        if (d.feed(chunk) is LineEndDetector.Event.End) finishListening()
    }

    private fun finishListening() {
        val done = listening
        listening = null
        done?.complete(Unit)
    }

    companion object {
        const val ROOM_TONE_SECONDS = 5
    }
}
