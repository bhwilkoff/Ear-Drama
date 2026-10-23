package com.example.appname.plays

import java.util.UUID
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Apple's Codable `Date`: seconds since 2001-01-01 UTC. `production.json` keeps
 * that one shape on both apps.
 */
object ReferenceDate {
    private const val UNIX_OFFSET_S = 978_307_200.0
    fun now(): Double = System.currentTimeMillis() / 1000.0 - UNIX_OFFSET_S
}

/**
 * One take: the performer's line window only, never the stand-in around it
 * (PLAYS-DESIGN §4.2). Immutable once written; choosing another take never
 * deletes it (§8 rule 5).
 */
@Serializable
data class Take(
    val id: String,
    val lineID: String,
    val part: PartID,
    /** The file name inside `takes/`. */
    val file: String,
    val created: Double,
    val frames: Int,
    val sampleRate: Double,
    val capture: Capture,
    /** What the performer heard before this line: a take id per cue line, or [STAND_IN] where the device voice read it live. */
    val heard: Map<String, String>,
    /** Integrated loudness (ITU-R BS.1770), stored, never written into the take. */
    val loudness: Double? = null,
    val peak: Float,
    /** The bleed check found the device voice in the microphone (§5 rule 2). */
    val bleed: Boolean,
) {
    @Serializable
    enum class Capture {
        /** Headphones on, the microphone as the performance source gives it. */
        @SerialName("direct") Direct,
        /** No headphones: echo cancellation removed the device's own playback. */
        @SerialName("aec") Aec,
    }

    val seconds: Double get() = frames / sampleRate

    companion object {
        const val STAND_IN = "standin"
    }
}

/** Where a part stands in the relay. */
@Serializable
data class PartState(val status: Status = Status.Open, val performer: String? = null) {
    @Serializable
    enum class Status {
        @SerialName("open") Open,
        @SerialName("recording") Recording,
        @SerialName("done") Done,
        @SerialName("silent") Silent,
    }
}

/**
 * The production record (`Plays/<id>/production.json`, §6): who took which
 * part, every take and what it heard, the chosen take per line, and the state
 * the mix was rendered from. Immutable; every change returns a copy.
 */
@Serializable
data class Production(
    val id: String,
    val scriptID: String,
    val scriptRevision: String,
    val title: String,
    val created: Double,
    val parts: Map<PartID, PartState> = emptyMap(),
    val takes: List<Take> = emptyList(),
    /** line id to take id */
    val chosen: Map<String, String> = emptyMap(),
    val roomTone: List<String> = emptyList(),
    val listenedThrough: Boolean = false,
    /** The chosen takes `mix.m4a` was rendered from; a different set means the mix is stale. */
    val mixedFrom: String? = null,
) {
    fun state(part: PartID): PartState = parts[part] ?: PartState()

    fun take(id: String): Take? = takes.firstOrNull { it.id == id }

    fun chosenTake(lineID: String): Take? = chosen[lineID]?.let(::take)

    fun takes(lineID: String): List<Take> = takes.filter { it.lineID == lineID }

    fun withPart(part: PartID, state: PartState) = copy(parts = parts + (part to state))

    /** A new take becomes the line's chosen one; the older takes stay. */
    fun add(take: Take): Production =
        copy(takes = takes + take, chosen = chosen + (take.lineID to take.id), listenedThrough = false)

    fun choose(takeID: String): Production {
        val take = take(takeID) ?: return this
        val changed = chosen[take.lineID] != takeID
        return copy(chosen = chosen + (take.lineID to takeID), listenedThrough = listenedThrough && !changed)
    }

    val unusedTakes: List<Take>
        get() {
            val keep = chosen.values.toSet()
            return takes.filter { it.id !in keep }
        }

    /** Every take that is not a line's chosen one, removed; the store deletes their files (§6). */
    fun discardUnused(): Pair<Production, List<Take>> {
        val gone = unusedTakes
        val ids = gone.map { it.id }.toSet()
        return copy(takes = takes.filter { it.id !in ids }) to gone
    }

    val chosenFingerprint: String
        get() = chosen.entries.sortedBy { it.key }.joinToString(",") { "${it.key}=${it.value}" }

    val isFinished: Boolean get() = listenedThrough && mixedFrom == chosenFingerprint

    companion object {
        fun create(script: PlayScript, id: String = UUID.randomUUID().toString().uppercase()) = Production(
            id = id,
            scriptID = script.id,
            scriptRevision = script.revision,
            title = script.title,
            created = ReferenceDate.now(),
            parts = script.castParts.associate { it.id to PartState() },
        )
    }
}
