package com.example.appname.plays

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * The studio inside the reader, without a view (PLAYS-DESIGN §2.9, ANDROID-DESIGN §4.17; Decision 076 S3), the mirror of
 * js/studio-core.js and apple/Core/Plays/StudioCore.swift: the line a studio opens at, the take state each of my lines
 * shows, and the production the reader's Record continues. [StudioController] drives the shipped [RecordingSession]
 * and never records or plays itself. Tests: StudioTest (the web's js/studio.test.js, case for case).
 */
object StudioCore {
    /** What one of my lines shows beside its speaker (§2.9 rule 3). */
    data class LineState(
        val state: Kind,
        val takes: Int,
        /** The chosen take's place among the line's takes, oldest first, from 1; 0 for none. */
        val chosen: Int,
    ) {
        enum class Kind { None, Chosen, Flagged }
    }

    /** Where the reader's Record records (§2.9 rule 1). */
    sealed interface Pick {
        /** The part already records in this production: continue it. */
        data class Resume(val id: String) : Pick

        /** The part is open here and no other part records: take it. */
        data class Take(val id: String) : Pick

        /** Make a new production and take the part. */
        data object Make : Pick
    }

    /** The line a studio opens at: the one asked for when it is the part's, else the first with no usable take, else the part's first line. */
    fun startLine(production: Production, script: PlayScript, part: PartID, ask: String?): String? {
        val mine = script.lines(part).map { it.id }
        if (mine.isEmpty()) return null
        if (ask != null && ask in mine) return ask
        return mine.firstOrNull { production.usableTake(it) == null } ?: mine[0]
    }

    fun lineState(production: Production, lineID: String): LineState {
        val takes = production.takes(lineID)
        if (takes.isEmpty()) return LineState(LineState.Kind.None, 0, 0)
        val chosen = production.chosenTake(lineID)
        val place = chosen?.let { c -> takes.indexOfFirst { it.id == c.id } + 1 } ?: 0
        return LineState(if (chosen?.bleed == true) LineState.Kind.Flagged else LineState.Kind.Chosen, takes.size, place)
    }

    /**
     * This device's newest unshared production of the play in which the part is recording; else the newest where it is
     * open and no other part records; else a new one.
     */
    fun productionFor(productions: List<Production>, isShared: (String) -> Boolean, script: PlayScript, part: PartID): Pick {
        val own = productions.filter { it.scriptID == script.id && !isShared(it.id) }.sortedByDescending { it.created }
        own.firstOrNull { it.state(part).status == PartState.Status.Recording }?.let { return Pick.Resume(it.id) }
        own.firstOrNull { it.state(part).status == PartState.Status.Open && Relay.current(it, script) == null }
            ?.let { return Pick.Take(it.id) }
        return Pick.Make
    }

    /** Beginning a new production while signed out asks for an account once another here holds a take (Decision 079). */
    fun asksAccount(pick: Pick, productions: List<Production>, signedIn: Boolean): Boolean =
        pick == Pick.Make && Production.secondNeedsAccount(productions, signedIn)

    /** The play's newest unshared production with no take, which Record this reuses while it lasts (§2.3 rule 3a). */
    fun reusable(productions: List<Production>, isShared: (String) -> Boolean, scriptID: String): String? =
        productions.filter { it.scriptID == scriptID && it.isEmpty && !isShared(it.id) }.maxByOrNull { it.created }?.id

    /** How a take-state mark reads to TalkBack: "No take", "3 takes, take 2 chosen", or the re-take. */
    fun spoken(state: LineState): String = when (state.state) {
        LineState.Kind.None -> "No take"
        LineState.Kind.Flagged -> "Re-take: the microphone heard the device voice"
        LineState.Kind.Chosen -> if (state.takes == 1) "1 take" else "${state.takes} takes, take ${state.chosen} chosen"
    }

    /** The status row's takes button: "Take 2 of 3", "No take", "Re-take". */
    fun takesLabel(state: LineState): String = when (state.state) {
        LineState.Kind.None -> "No take"
        LineState.Kind.Flagged -> "Re-take"
        LineState.Kind.Chosen -> "Take ${state.chosen} of ${state.takes}"
    }
}

/**
 * One studio over a started (or starting) [RecordingSession]: which of my lines is current, how each of the three modes
 * moves it, a line's takes (choose, delete an unchosen one, record again) and Delete unused takes for the part.
 * [onFollow] has the reader follow the line being heard or recorded. Every call is on the main thread.
 */
class StudioController(val session: RecordingSession, private val store: ProductionStore, line: String? = null) {
    val part: PartID = session.part

    /** My lines' ids, in script order. */
    val mine: List<String> = session.lines.map { it.id }
    private val order: Map<String, Int> = session.script.lines.withIndex().associate { (i, l) -> l.id to i }
    private val _current = MutableStateFlow(StudioCore.startLine(session.production.value, session.script, part, line))

    /** The current line, one of mine. */
    val current: StateFlow<String?> = _current
    var onFollow: ((String) -> Unit)? = null

    init {
        session.onPhase = { phaseChanged(it) }
    }

    val script: PlayScript get() = session.script

    /** Busy, a run on screen, or a run's review: the current line holds still and the mode cannot change. */
    val locked: Boolean get() = session.isBusy || session.run.value != null || session.phase.value is RecordingSession.Phase.RunReview

    /** My first line at or after a script line (the run's next line of mine). */
    private fun mineFrom(lineID: String): String? {
        val k = order[lineID] ?: return null
        return mine.firstOrNull { (order[it] ?: -1) >= k }
    }

    private fun phaseChanged(phase: RecordingSession.Phase) {
        val (id, listening) = when (phase) {
            is RecordingSession.Phase.Cue -> phase.lineID to false
            is RecordingSession.Phase.Listening -> phase.lineID to true
            else -> return
        }
        onFollow?.invoke(id)
        // During a run, and whenever the microphone is open, the current line is the line being recorded or my next one.
        if (session.run.value != null || listening) {
            val next = if (listening && id in mine) id else mineFrom(id)
            if (next != null) _current.value = next
        }
    }

    /** A tap on one of my lines makes it current (refused while busy or in a run). */
    fun select(id: String): Boolean {
        if (id !in mine || locked) return false
        _current.value = id
        return true
    }

    /** Next and Previous: my next or previous line from the current one, never wrapping. */
    fun move(delta: Int): Boolean {
        if (locked || mine.isEmpty()) return false
        val now = _current.value
        var i = now?.let { mine.indexOf(it) } ?: -1
        if (i < 0) {
            val from = mineFrom(now ?: mine[0])
            i = from?.let { mine.indexOf(it) - (if (delta > 0) 1 else 0) } ?: (mine.size - 1)
        }
        val to = mine[(i + delta).coerceIn(0, mine.size - 1)]
        if (to == now) return false
        _current.value = to
        return true
    }

    /**
     * The one round control (Space): in Run through, start a run from the current line or pause it; otherwise stop
     * listening, cancel a cue, or record the current line.
     */
    suspend fun primary() {
        val now = _current.value ?: return
        if (!session.started) return
        val phase = session.phase.value
        if (session.mode.value == RecordingSession.Mode.Run) {
            if (phase is RecordingSession.Phase.RunReview) return
            if (session.run.value != null) { session.pause(); return }
            if (!session.isBusy) session.runThrough(now)
            return
        }
        when {
            phase is RecordingSession.Phase.Listening -> session.stopListening()
            phase is RecordingSession.Phase.Cue -> session.cancel()
            !session.isBusy -> session.record(now)
        }
    }

    /** Record again (R): a new take of the line, chosen at once; every older take stays. */
    suspend fun again(lineID: String? = null) {
        val id = lineID ?: _current.value ?: return
        if (!session.started || session.isBusy) return
        if (session.run.value == null) _current.value = id
        session.record(id)
    }

    /** Keep (Return): Step's review moves to my next line and waits; a run's review keeps the run. */
    fun keep() {
        when (session.phase.value) {
            is RecordingSession.Phase.Review -> {
                session.dismissReview()
                val i = _current.value?.let { mine.indexOf(it) } ?: -1
                if (i >= 0 && i + 1 < mine.size) _current.value = mine[i + 1]
            }
            RecordingSession.Phase.RunReview -> session.keepRun()
            else -> Unit
        }
    }

    fun lineState(id: String): StudioCore.LineState = StudioCore.lineState(session.production.value, id)

    /** A line's takes, oldest first. */
    fun takes(id: String? = null): List<Take> {
        val line = id ?: _current.value ?: return emptyList()
        return session.production.value.takes(line)
    }

    fun choose(take: Take) {
        if (!session.isBusy) session.choose(take)
    }

    /** Deletes one unchosen take and its file (the person's act); false when refused. */
    fun deleteTake(take: Take): Boolean {
        if (session.isBusy) return false
        val done = store.deleteTake(session.production.value.id, take.id)
        session.reload()
        return done
    }

    /** This part's unchosen takes. */
    val unused: List<Take>
        get() = session.production.value.unusedTakes.filter { it.lineID in mine }

    /** Delete unused takes for the part; returns how many went. */
    fun deleteUnused(): Int {
        if (locked) return 0
        val n = store.discardUnusedTakes(session.production.value.id, mine.toSet())
        session.reload()
        return n
    }

    /** How many of my lines have a usable take. */
    val kept: Int
        get() = mine.size - Relay.missingLines(part, session.production.value, session.script).size

    /** "Line 3 of 44": the current line's place among my lines. */
    val place: Pair<Int, Int>
        get() = ((_current.value?.let { mine.indexOf(it) }?.coerceAtLeast(0) ?: 0) + 1) to mine.size
}
