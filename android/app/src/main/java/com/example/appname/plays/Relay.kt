package com.example.appname.plays

/**
 * The relay (PLAYS-DESIGN §2.3-2.5): pure functions of the script and the
 * production, the same as apple/Core/Plays/Relay.swift, so every platform
 * proves the same order.
 *
 * Decision 067 (C7): one microphone, so one part records at a time, but any
 * open part can be taken, in any order. [next] only suggests the largest open
 * part. Sound effects and stage directions may be left silent; a speaking
 * part may not (C6).
 */
object Relay {
    sealed class Refusal : Exception() {
        data class AnotherPartIsRecording(val part: PartID) : Refusal()
        data class NotOpen(val part: PartID?) : Refusal()
        data class LinesMissing(val lines: List<String>) : Refusal()
        data object SpeakingPartCannotBeSilent : Refusal() {
            private fun readResolve(): Any = SpeakingPartCannotBeSilent
        }

        /** The sentence the cast sheet shows. */
        val text: String
            get() = when (this) {
                is AnotherPartIsRecording -> "${part.title} is still recording."
                is NotOpen -> part?.let { "${it.title} is not open." } ?: "Nothing to open."
                is LinesMissing -> if (lines.size == 1) "1 line still needs a take." else "${lines.size} lines still need a take."
                SpeakingPartCannotBeSilent -> "A speaking part needs a voice."
            }
    }

    fun order(script: PlayScript): List<PartID> = script.castParts.map { it.id }

    /** The part being recorded now, if any. */
    fun current(production: Production, script: PlayScript): PartID? =
        order(script).firstOrNull { production.state(it).status == PartState.Status.Recording }

    /** The part the relay suggests: the first open part in cast order, or null while a part records or when all are through. */
    fun next(production: Production, script: PlayScript): PartID? {
        if (current(production, script) != null) return null
        return order(script).firstOrNull { production.state(it).status == PartState.Status.Open }
    }

    fun take(part: PartID, performer: String?, production: Production, script: PlayScript): Production {
        current(production, script)?.let { throw Refusal.AnotherPartIsRecording(it) }
        if (production.state(part).status != PartState.Status.Open) throw Refusal.NotOpen(part)
        val name = performer?.trim()?.takeIf { it.isNotEmpty() }
        return production.withPart(part, PartState(PartState.Status.Recording, name))
    }

    /** Lines of the part with no chosen take, or whose chosen take the bleed check flagged. */
    fun missingLines(part: PartID, production: Production, script: PlayScript): List<String> =
        script.lines(part).map { it.id }.filter { production.usableTake(it) == null }

    /**
     * "Done with this part" (§2.5). A speaking part is done only when every one
     * of its lines has a take, because a play cannot be finished with a stand-in
     * in it (§5 rule 4). A sound or directions part may leave lines silent.
     */
    fun finish(part: PartID, production: Production, script: PlayScript): Production {
        if (production.state(part).status != PartState.Status.Recording) throw Refusal.NotOpen(part)
        if (part.isSpeaking) {
            val missing = missingLines(part, production, script)
            if (missing.isNotEmpty()) throw Refusal.LinesMissing(missing)
        }
        return production.withPart(part, production.state(part).copy(status = PartState.Status.Done))
    }

    /**
     * Pending owner (C6): only sound effects and stage directions may be left
     * silent; a speaking part nobody takes leaves the play unfinished, and it
     * never gets a stored synthetic voice.
     */
    fun leaveSilent(part: PartID, production: Production, script: PlayScript): Production {
        if (part.isSpeaking) throw Refusal.SpeakingPartCannotBeSilent
        val status = production.state(part).status
        if (status != PartState.Status.Recording && status != PartState.Status.Open) throw Refusal.NotOpen(part)
        return production.withPart(part, production.state(part).copy(status = PartState.Status.Silent))
    }

    /** Back to a part that is through, to re-take a line. Still one part at a time. */
    fun reopen(part: PartID, production: Production, script: PlayScript): Production {
        current(production, script)?.let { throw Refusal.AnotherPartIsRecording(it) }
        val status = production.state(part).status
        if (status != PartState.Status.Done && status != PartState.Status.Silent) {
            throw Refusal.NotOpen(part)
        }
        return production.withPart(part, production.state(part).copy(status = PartState.Status.Recording))
    }

    sealed interface ListenEntry {
        val lineID: String
        val part: PartID

        data class TakeEntry(override val lineID: String, override val part: PartID, val take: Take) : ListenEntry

        /** Text only: the device voice reads it live and it is never rendered to audio. */
        data class Voice(override val lineID: String, override val part: PartID, val text: String) : ListenEntry
    }

    /** The live listen-through: a usable take per line where there is one, else a speech line's words for the device voice; silent sound and direction lines are left out. */
    fun listenPlan(production: Production, script: PlayScript): List<ListenEntry> = script.lines.mapNotNull { line ->
        val usable = production.usableTake(line.id)
        when {
            usable != null -> ListenEntry.TakeEntry(line.id, line.part, usable)
            line.kind == ScriptLine.Kind.Speech -> ListenEntry.Voice(line.id, line.part, line.spokenText)
            else -> null
        }
    }

    /** Speaking lines with no unflagged human take. */
    fun missingSpeech(production: Production, script: PlayScript): List<String> =
        script.speechLineIDs.filter { production.usableTake(it) == null }

    /** Lines of any kind whose chosen take the bleed check flagged. */
    fun needsRetake(production: Production, script: PlayScript): List<String> =
        script.lines.map { it.id }.filter { production.chosenTake(it)?.bleed == true }

    /** Every speaking line has an unflagged human take and no chosen take is flagged: only then can the play be mixed. */
    fun isComplete(production: Production, script: PlayScript): Boolean =
        missingSpeech(production, script).isEmpty() && needsRetake(production, script).isEmpty()

    /**
     * The lines that cue a performer's line (§2.4): the previous speech where
     * another part speaks it, or, for a run-up, the two speeches before it.
     */
    fun cueLines(before: String, script: PlayScript, runUp: Boolean): List<ScriptLine> {
        val index = script.lines.indexOfFirst { it.id == before }
        if (index < 0) return emptyList()
        val me = script.lines[index].part
        val earlier = script.lines.subList(0, index).filter { it.kind == ScriptLine.Kind.Speech }
        if (runUp) return earlier.takeLast(2)
        val last = earlier.lastOrNull() ?: return emptyList()
        return if (last.part == me) emptyList() else listOf(last)
    }

    sealed interface RunEntry {
        val lineID: String
        val part: PartID

        /** The performer's own line: the microphone opens on it. */
        data class Mine(override val lineID: String, override val part: PartID) : RunEntry

        /** A line with a usable human take: the take plays. */
        data class TakeEntry(override val lineID: String, override val part: PartID, val take: Take) : RunEntry

        /** Text only: the device voice reads it live and it is never rendered to audio (§5). */
        data class Voice(override val lineID: String, override val part: PartID, val text: String) : RunEntry
    }

    /**
     * Run through (owner ruling 4): the play from the chosen line's cue (the previous speech
     * where another part speaks it, as [cueLines]) to the part's last line, nothing after it.
     * Unrecorded directions and sound are skipped, as in the listen plan.
     */
    fun runPlan(production: Production, script: PlayScript, part: PartID, fromLineID: String): List<RunEntry> {
        val at = script.lines.indexOfFirst { it.id == fromLineID }
        if (at < 0) return emptyList()
        val cue = cueLines(fromLineID, script, runUp = false).firstOrNull()
        val start = cue?.let { c -> script.lines.indexOfFirst { it.id == c.id } } ?: at
        val plan = ArrayList<RunEntry>()
        for (line in script.lines.subList(start, script.lines.size)) {
            val who = line.part
            val take = if (who == part) null else production.usableTake(line.id)
            when {
                who == part -> plan += RunEntry.Mine(line.id, who)
                take != null -> plan += RunEntry.TakeEntry(line.id, who, take)
                line.kind == ScriptLine.Kind.Speech -> plan += RunEntry.Voice(line.id, who, line.spokenText)
            }
        }
        val last = plan.indexOfLast { it is RunEntry.Mine }
        return plan.take(last + 1)
    }
}
