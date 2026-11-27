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
    /** A take that arrived from a room reader's device: the seat it was credited to and the member that sent it. */
    val seat: String? = null,
    val member: String? = null,
    /** A performed cue (B32 §3.1 item 6): the slot this Sound part take belongs to. It is the slot's, never its line's take. */
    val cue: String? = null,
) {
    @Serializable
    enum class Capture {
        /** Headphones on, the microphone as the performance source gives it. */
        @SerialName("direct") Direct,
        /** No headphones: echo cancellation removed the device's own playback. */
        @SerialName("aec") Aec,
        /** Record in the room (PLAYS-DESIGN §12.10): no cue, no playback during the take. */
        @SerialName("room") Room,
    }

    val seconds: Double get() = frames / sampleRate

    companion object {
        const val STAND_IN = "standin"
    }
}

/** The sound block (B32 §5.1): lanes' duck depths, and a slot per line a cue was placed against. */
@Serializable
data class SoundBlock(
    val v: Int = 1,
    val lanes: Map<String, SoundLane> = emptyMap(),
    val slots: List<SoundSlot> = emptyList(),
)

@Serializable
data class SoundLane(val duckDb: Double? = null)

@Serializable
data class SoundSlot(
    val id: String,
    val line: String,
    val piece: Int? = null,
    val added: Boolean = false,
    val silent: Boolean = false,
    val sounds: List<SoundCue> = emptyList(),
)

/** One cue: where it comes from, where it sits against its line, and how it is shaped. */
@Serializable
data class SoundCue(
    val id: String,
    val src: SoundSource,
    val at: String,
    val until: String? = null,
    val startMs: Double = 0.0,
    val gainDb: Double = 0.0,
    val fadeInMs: Double = 0.0,
    val fadeOutMs: Double = 0.0,
    val loop: Boolean = false,
    val duckDb: Double? = null,
)

/** A pack cue (`pack`, `cue`), the person's own file (`own`), or a take they performed (`take`). */
@Serializable
data class SoundSource(
    val pack: String? = null,
    val cue: String? = null,
    val own: String? = null,
    val take: String? = null,
)

/** One line's part in a run (Run through): the take the line had before the run, and every take the run made for it. */
data class RunNote(val lineID: String, val prior: String?, val takes: List<String>)

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
    /** The read room this production keeps the takes of (PLAYS-DESIGN §12.10): its code, the Worker production, kind, and takes waiting to be sent. */
    val room: String? = null,
    val roomPid: String? = null,
    val roomKind: String? = null,
    val roomOutbox: List<String> = emptyList(),
    /** Cues placed against lines (B32 §5.1); absent from `production.json` until a sound is placed. */
    val sound: SoundBlock? = null,
) {
    /** No take and no placed sound: a production holding only a sound someone chose is the person's work, not an empty shell. */
    val isEmpty: Boolean get() = takes.isEmpty() && sound?.slots.orEmpty().none { it.silent || it.sounds.isNotEmpty() }

    fun state(part: PartID): PartState = parts[part] ?: PartState()

    fun take(id: String): Take? = takes.firstOrNull { it.id == id }

    fun chosenTake(lineID: String): Take? = chosen[lineID]?.let(::take)

    /**
     * The chosen take when it counts toward the play: a take the bleed check
     * flagged holds the device voice, so it is kept on disk but never counts or
     * reaches the mix (§5 rule 2, §8 rule 3).
     */
    fun usableTake(lineID: String): Take? = chosenTake(lineID)?.takeIf { !it.bleed }

    fun takes(lineID: String): List<Take> = takes.filter { it.lineID == lineID && it.cue == null }

    fun withPart(part: PartID, state: PartState) = copy(parts = parts + (part to state))

    /** A new take becomes the line's chosen one; the older takes stay. */
    fun add(take: Take): Production =
        copy(takes = takes + take, chosen = chosen + (take.lineID to take.id), listenedThrough = false)

    fun choose(takeID: String): Production {
        val take = take(takeID) ?: return this
        val changed = chosen[take.lineID] != takeID
        return copy(chosen = chosen + (take.lineID to takeID), listenedThrough = listenedThrough && !changed)
    }

    /**
     * Discard the run: every take the run made is removed and each line goes back to the take it
     * had before (§8 rule 5: only the person's own act removes a take). The store deletes the
     * returned takes' files.
     */
    fun discardRun(run: List<RunNote>): Pair<Production, List<Take>> {
        val ids = run.flatMap { it.takes }.toSet()
        val gone = takes.filter { it.id in ids }
        var next = chosen
        for (note in run) {
            next = if (note.prior != null && takes.any { it.id == note.prior && it.id !in ids }) next + (note.lineID to note.prior) else next - note.lineID
        }
        return copy(takes = takes.filter { it.id !in ids }, chosen = next, listenedThrough = listenedThrough && gone.isEmpty()) to gone
    }

    val unusedTakes: List<Take>
        get() {
            val keep = chosen.values.toSet() + soundTakeIDs
            return takes.filter { it.id !in keep }
        }

    /**
     * Every take that is not a line's chosen one, removed; the store deletes their files (§6). With [lines], only those
     * lines' unchosen takes go (the studio's Delete unused takes is one part's).
     */
    fun discardUnused(lines: Set<String>? = null): Pair<Production, List<Take>> {
        val gone = unusedTakes.filter { lines == null || it.lineID in lines }
        val ids = gone.map { it.id }.toSet()
        return copy(takes = takes.filter { it.id !in ids }) to gone
    }

    /**
     * One take removed, only when it is not its line's chosen take (the chosen take is the one the play uses and, in a
     * shared production, the one uploaded). Returns what went so the store deletes the file; nothing when refused.
     */
    fun deleteTake(takeID: String): Pair<Production, List<Take>> {
        val take = take(takeID) ?: return this to emptyList()
        if (chosen[take.lineID] == takeID || takeID in soundTakeIDs) return this to emptyList()
        return copy(takes = takes.filter { it.id != takeID }) to listOf(take)
    }

    /** Takes a sound slot plays (a performed cue): kept like a chosen take, never in [chosen]. */
    val soundTakeIDs: Set<String>
        get() = sound?.slots.orEmpty().flatMap { slot -> slot.sounds.mapNotNull { it.src.take } }.toSet()

    /** The chosen takes, and the sound block when it places any sound: a change to either makes the mix stale. */
    val chosenFingerprint: String
        get() {
            val takes = chosen.entries.sortedBy { it.key }.joinToString(",") { "${it.key}=${it.value}" }
            return if (MixSound.hasSound(this)) "$takes|sound=${MixSound.canonical(sound!!)}" else takes
        }

    val isFinished: Boolean get() = listenedThrough && mixedFrom == chosenFingerprint

    companion object {
        /** Signed out, a production on this device that holds a take makes the next one a second (Decision 079); an empty one does not count. */
        fun secondNeedsAccount(productions: List<Production>, signedIn: Boolean): Boolean =
            !signedIn && productions.any { !it.isEmpty }

        /** Local, unshared productions with no take: removed rather than listed (PLAYS-DESIGN §2.3 rule 3a). */
        fun abandoned(productions: List<Production>, isShared: (String) -> Boolean): List<String> =
            productions.filter { it.isEmpty && it.room == null && !isShared(it.id) }.map { it.id }

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
