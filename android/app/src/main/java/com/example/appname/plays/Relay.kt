package com.example.appname.plays

/**
 * The relay (PLAYS-DESIGN §2.3-2.5): pure functions of the script and the
 * production, the same as apple/Core/Plays/Relay.swift, so every platform
 * proves the same order.
 *
 * Pending owner (C7): strictly one part at a time, in a fixed order, largest
 * part first. Only the next part in that order can be taken, and only while no
 * other part is being recorded. Sound effects and stage directions come last
 * and may be left silent; a speaking part may not (C6).
 */
object Relay {
    sealed class Refusal : Exception() {
        data class AnotherPartIsRecording(val part: PartID) : Refusal()
        data class NotNext(val expected: PartID?) : Refusal()
        data class LinesMissing(val lines: List<String>) : Refusal()
        data object SpeakingPartCannotBeSilent : Refusal() {
            private fun readResolve(): Any = SpeakingPartCannotBeSilent
        }

        /** The sentence the cast sheet shows. */
        val text: String
            get() = when (this) {
                is AnotherPartIsRecording -> "${part.title} is still recording."
                is NotNext -> expected?.let { "${it.title} is next." } ?: "No part is open."
                is LinesMissing -> if (lines.size == 1) "1 line still needs a take." else "${lines.size} lines still need a take."
                SpeakingPartCannotBeSilent -> "A speaking part needs a voice."
            }
    }

    fun order(script: PlayScript): List<PartID> = script.castParts.map { it.id }

    /** The part being recorded now, if any. */
    fun current(production: Production, script: PlayScript): PartID? =
        order(script).firstOrNull { production.state(it).status == PartState.Status.Recording }

    /** The part the relay hands the device to next: the first open part, or null while a part records or when all are through. */
    fun next(production: Production, script: PlayScript): PartID? {
        if (current(production, script) != null) return null
        return order(script).firstOrNull { production.state(it).status == PartState.Status.Open }
    }

    fun take(part: PartID, performer: String?, production: Production, script: PlayScript): Production {
        current(production, script)?.let { throw Refusal.AnotherPartIsRecording(it) }
        val next = next(production, script)
        if (next != part) throw Refusal.NotNext(next)
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
        if (production.state(part).status != PartState.Status.Recording) throw Refusal.NotNext(current(production, script))
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
        if (status != PartState.Status.Recording && next(production, script) != part) {
            throw Refusal.NotNext(next(production, script))
        }
        return production.withPart(part, production.state(part).copy(status = PartState.Status.Silent))
    }

    /** Back to a part that is through, to re-take a line. Still one part at a time. */
    fun reopen(part: PartID, production: Production, script: PlayScript): Production {
        current(production, script)?.let { throw Refusal.AnotherPartIsRecording(it) }
        val status = production.state(part).status
        if (status != PartState.Status.Done && status != PartState.Status.Silent) {
            throw Refusal.NotNext(next(production, script))
        }
        return production.withPart(part, production.state(part).copy(status = PartState.Status.Recording))
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
}
