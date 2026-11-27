package com.example.appname.plays

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.Transient
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.serialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json

// Plays phase 1, pass the phone (docs/PLAYS-DESIGN.md). A castable script as the
// catalog built it (catalog/tools/build_castable_scripts.py): only scripts whose
// rights state is `castable` and whose parse is clean are in the file, and every
// word is the parser's exact slice of the printed text. Nothing here rewrites,
// summarizes, or fills in a word (§8 rule 2). The model and the file names match
// apple/Core/Plays, so the two apps read and write the same shapes.

/**
 * One part on the cast sheet: a speaking role as the script names it
 * (`role:NAME`), or one of the two parts "like any other" (§2.2), stage
 * directions and sound effects.
 */
@JvmInline
@Serializable
value class PartID(val raw: String) : Comparable<PartID> {
    val roleName: String? get() = if (raw.startsWith(ROLE)) raw.removePrefix(ROLE) else null
    val isSpeaking: Boolean get() = roleName != null
    val title: String get() = roleName ?: if (this == DIRECTIONS) "Stage directions" else "Sound"

    override fun compareTo(other: PartID): Int = raw.compareTo(other.raw)
    override fun toString(): String = raw

    companion object {
        private const val ROLE = "role:"
        fun role(name: String) = PartID(ROLE + name)
        val DIRECTIONS = PartID("directions")
        val SOUND = PartID("sound")
    }
}

/** A piece of a speech, exactly as printed: what is said, and the directions, mic positions, and sounds inside it. */
@Serializable(with = LinePartSerializer::class)
sealed interface LinePart {
    val text: String
    data class Say(override val text: String) : LinePart
    data class Direction(override val text: String) : LinePart
    data class Mic(override val text: String) : LinePart
    data class Sound(override val text: String) : LinePart
}

/** `{"say": "..."}`: one key per part, any unknown key read as a direction (as Apple does). */
object LinePartSerializer : KSerializer<LinePart> {
    private val map = serializer<Map<String, String>>()
    override val descriptor: SerialDescriptor = serialDescriptor<Map<String, String>>()

    override fun deserialize(decoder: Decoder): LinePart {
        val obj = decoder.decodeSerializableValue(map)
        require(obj.size == 1) { "one key per part" }
        val (key, value) = obj.entries.first()
        return when (key) {
            "say" -> LinePart.Say(value)
            "mic" -> LinePart.Mic(value)
            "sound" -> LinePart.Sound(value)
            else -> LinePart.Direction(value)
        }
    }

    override fun serialize(encoder: Encoder, value: LinePart) {
        val key = when (value) {
            is LinePart.Say -> "say"
            is LinePart.Direction -> "direction"
            is LinePart.Mic -> "mic"
            is LinePart.Sound -> "sound"
        }
        encoder.encodeSerializableValue(map, mapOf(key to value.text))
    }

    private inline fun <reified T> serializer(): KSerializer<T> = kotlinx.serialization.serializer()
}

@Serializable
data class ScriptLine(
    val id: String,
    val kind: Kind,
    val role: String? = null,
    val parts: List<LinePart>? = null,
    val source: String? = null,
    /** Indexes into [parts] of the said parts the source printed in italics (the speaker's stress). */
    val em: List<Int>? = null,
) {
    @Serializable
    enum class Kind {
        @SerialName("speech") Speech,
        @SerialName("sound") Sound,
        @SerialName("music") Music,
        @SerialName("direction") Direction,
    }

    val part: PartID
        get() = when (kind) {
            Kind.Speech -> PartID.role(role ?: "")
            Kind.Direction -> PartID.DIRECTIONS
            Kind.Sound, Kind.Music -> PartID.SOUND
        }

    /** What a performer (or a stand-in) says: the speech's said parts, or the whole printed block for a direction or a cue. */
    val spokenText: String
        get() = if (kind == Kind.Speech) {
            parts.orEmpty().filterIsInstance<LinePart.Say>().joinToString(" ") { it.text }
        } else {
            source.orEmpty()
        }
}

@Serializable
data class PlayScript(
    override val id: String,
    val revision: String,
    override val kind: String,
    override val title: String,
    val authors: List<Author> = emptyList(),
    val source: Source,
    val rights: Rights,
    val roles: List<Role> = emptyList(),
    val lines: List<ScriptLine>,
    override val year: Int? = null,
    @SerialName("sort_name") override val sortName: String? = null,
    /** Printed headings the parser set aside (contract §4.1); the bundled scripts carry none. */
    val sections: List<ScriptSection> = emptyList(),
    /** A person's own script (PLAYS-DESIGN §13): when it was added (milliseconds), the episode it was cast from, and what a line with a take said before. */
    val created: Long? = null,
    val episode: String? = null,
    val edits: Map<String, List<ScriptEdit>> = emptyMap(),
    /** Set on a script cut to a production's range (PLAYS-DESIGN §2.12): the range, and the whole script it was cut from. Never stored. */
    @Transient val scopedTo: ProductionRange? = null,
    @Transient val whole: PlayScript? = null,
) : PlayListing {
    /** The whole script behind a scoped one. */
    val wholeScript: PlayScript get() = whole ?: this

    /** The indexes a range spans in this script, or null when either bound is gone or they are out of order. */
    fun rangeSpan(range: ProductionRange?): IntRange? {
        if (range == null) return null
        val a = lines.indexOfFirst { it.id == range.from }
        val z = lines.indexOfFirst { it.id == range.to }
        return if (a >= 0 && z >= a) a..z else null
    }

    /**
     * This script cut to [range]: its lines, its sections there, and each role speaking there with its lines and words
     * there, so voices and minutes are the range's. Idempotent: a script already cut, a null range, or a range that no
     * longer resolves answers this script.
     */
    fun scoped(range: ProductionRange?): PlayScript {
        if (scopedTo != null) return this
        val span = rangeSpan(range) ?: return this
        val cut = lines.slice(span)
        val ids = cut.map { it.id }.toSet()
        val said = LinkedHashMap<String, IntArray>()
        for (l in cut) {
            val who = l.role
            if (l.kind != ScriptLine.Kind.Speech || who == null) continue
            val at = said.getOrPut(who) { IntArray(2) }
            at[0] += 1
            at[1] += l.parts.orEmpty().filterIsInstance<LinePart.Say>().sumOf { it.text.split(Regex("\\s+")).count(String::isNotEmpty) }
        }
        val kept = roles.filter { it.name in said }.map { it.copy(lines = said.getValue(it.name)[0], words = said.getValue(it.name)[1]) }
        return copy(lines = cut, roles = kept, sections = sections.filter { it.line in ids }, scopedTo = range, whole = this)
    }

    /** The cast sheet for [range]: only the parts with a line there. */
    fun castParts(range: ProductionRange?): List<CastPart> = scoped(range).castParts


    /** Added by a person or cast by ear: never published, shared or read together from here. */
    val isOwn: Boolean get() = kind == "own"

    @Serializable data class Author(val name: String? = null, val display: String? = null, val born: Int? = null, val died: Int? = null) {
        /** The record's own display name, else the filed name read forward. */
        val shown: String? get() = display?.trim()?.takeIf { it.isNotEmpty() } ?: name?.let(::displayName)
    }
    @Serializable data class Source(val name: String, val url: String)
    @Serializable data class Evidence(val claim: String? = null, val src: String? = null)
    @Serializable data class Rights(val bucket: String, val evidence: List<Evidence> = emptyList())
    /** [register]: "high" or "low", the register of the part's stand-in voice where the play's own print settles it
     *  (catalog DECISIONS 049). Auto-cast reads it; nothing on screen shows it. */
    @Serializable data class Role(val name: String, val lines: Int, val words: Int, val register: String? = null)

    override val authorLine: String get() = authors.mapNotNull { it.shown }.joinToString(", ")

    /** The author with born and died years where the record has them. */
    override val authorWithYears: String
        get() = authors.mapNotNull { a ->
            val name = a.shown ?: return@mapNotNull null
            val years = lifeYears(a.born, a.died)
            if (years.isEmpty()) name else "$name ($years)"
        }.joinToString(", ")

    /** "N parts · N lines", counted from the record. */
    val lengthLine: String
        get() {
            val parts = castParts.count { it.id.isSpeaking }
            val n = lines.size
            val count = String.format(java.util.Locale.US, "%,d", n)
            return "$parts ${if (parts == 1) "part" else "parts"} \u00b7 $count ${if (n == 1) "line" else "lines"}"
        }

    fun lines(part: PartID): List<ScriptLine> = lines.filter { it.part == part }

    /** Voices a person can cast: roles with five speeches, as the published index counts them. */
    override val voices: Int get() = ScriptReading.voicesOf(this)

    /** Minutes from the words its parts speak at 150 a minute, at least 1; a length is "About N min", never exact. */
    override val minutes: Int get() = ScriptReading.minutesOf(this)

    override val cast: List<Int> get() = ScriptReading.castOf(this)

    override val speechCount: Int get() = lines.count { it.kind == ScriptLine.Kind.Speech }

    /**
     * The parts on the cast sheet: speaking parts largest first (by lines, then
     * by first appearance), then sound effects and stage directions where the
     * script has them (§2.2).
     */
    val castParts: List<CastPart> by lazy {
        val counts = LinkedHashMap<PartID, Int>()
        val first = HashMap<PartID, Int>()
        lines.forEachIndexed { index, line ->
            counts[line.part] = (counts[line.part] ?: 0) + 1
            first.putIfAbsent(line.part, index)
        }
        val speaking = counts.keys.filter { it.isSpeaking }
            .sortedWith(compareByDescending<PartID> { counts.getValue(it) }.thenBy { first.getValue(it) })
        counts[PartID.SOUND] = cueRows.size
        val others = listOf(PartID.SOUND, PartID.DIRECTIONS).filter { it in counts }
        (speaking + others).map { CastPart(it, counts.getValue(it)) }
    }

    /**
     * The script's cue rows, the Sound part's slots (B32 §3.1): a sound or music line (no piece), and inside a speech each
     * printed sound piece or aside that begins "sound of", "noise of" or "music". Never filled in: a row is only where a person
     * may put a sound. The mirror of `PlaysCore.cueRows`.
     */
    val cueRows: List<CueRow> by lazy {
        val out = ArrayList<CueRow>()
        for (line in lines) {
            if (line.kind == ScriptLine.Kind.Sound || line.kind == ScriptLine.Kind.Music) {
                out += CueRow(line.id, null, line.source.orEmpty())
            } else if (line.kind == ScriptLine.Kind.Speech) {
                line.parts.orEmpty().forEachIndexed { i, pc ->
                    if (pc is LinePart.Sound || (pc is LinePart.Direction && CUE_WORDS.containsMatchIn(pc.text))) out += CueRow(line.id, i, pc.text)
                }
            }
        }
        out
    }

    val speechLineIDs: List<String> get() = lines.filter { it.kind == ScriptLine.Kind.Speech }.map { it.id }

    /** Each role's published stand-in register by part (catalog DECISIONS 049), only "high" or "low". */
    val registers: Map<PartID, String> get() =
        roles.mapNotNull { r -> r.register?.takeIf { it == VoiceCasting.HIGH || it == VoiceCasting.LOW }?.let { PartID.role(r.name) to it } }.toMap()

    /**
     * A part's face color (direction D): the first seven speaking parts, largest first, take the
     * seven marks in [PART_HUES] order; the rest, and directions and sound, stand on neutral (null).
     * The web's and Apple's partHue return the same names.
     */
    fun partHue(part: PartID): String? {
        if (!part.isSpeaking) return null
        return PART_HUES.getOrNull(castParts.filter { it.id.isSpeaking }.indexOfFirst { it.id == part })
    }

    /** Where a part speaks: [bins] shares, each the part's lines among the lines of that stretch of the script. */
    fun presence(part: PartID, bins: Int = PRESENCE_BINS): List<Float> {
        if (lines.isEmpty()) return List(bins) { 0f }
        return List(bins) { bin ->
            val from = bin * lines.size / bins
            val to = (bin + 1) * lines.size / bins
            if (to <= from) 0f else lines.subList(from, to).count { it.part == part }.toFloat() / (to - from)
        }
    }

    companion object {
        /** An aside that is a sound cue by its words (the reader's sound lane). */
        val CUE_WORDS = Regex("^[\\s(\\[_]*(?:(?:sounds?|noises?) of\\b|music\\b)", RegexOption.IGNORE_CASE)
        const val WORDS_PER_MINUTE = 150
        val VOICE_BANDS = listOf(Band("1-2", 1, 2), Band("3-5", 3, 5), Band("6-10", 6, 10), Band("11+", 11, Int.MAX_VALUE))
        val LENGTH_BANDS = listOf(Band("short", 0, 29), Band("mid", 30, 60), Band("long", 61, Int.MAX_VALUE))

        /** FNV-1a 64 over the UTF-8 bytes, in unsigned 64-bit math (the golden: catalog/tests/golden/todays_play.json). */
        fun fnv1a64(text: String): ULong {
            var h = 0xcbf29ce484222325uL
            for (b in text.toByteArray(Charsets.UTF_8)) {
                h = h xor (b.toLong() and 0xFF).toULong()
                h *= 0x100000001b3uL
            }
            return h
        }

        /** The day's play: the id whose hash of "play:{dateKey}:{id}" is smallest, ties by id; null for none. */
        fun <T : PlayListing> todaysPlay(plays: List<T>, dateKey: String): T? =
            plays.map { it to fnv1a64("play:$dateKey:${it.id}") }
                .minWithOrNull(compareBy<Pair<T, ULong>> { it.second }.thenBy { it.first.id })?.first

        /** The scene pool (Decision 079): two voices and at most 20 min; else 2-3 voices and at most 30; else every play. */
        fun <T : PlayListing> scenePool(plays: List<T>): List<T> {
            for ((lo, hi, most) in SCENE_POOLS) {
                val pool = plays.filter { it.voices in lo..hi && it.minutes <= most }
                if (pool.isNotEmpty()) return pool
            }
            return plays
        }

        /** Today's scene: [todaysPlay]'s hash over [scenePool], so every platform with the same library and date picks the same play. */
        fun <T : PlayListing> todaysScene(plays: List<T>, dateKey: String): T? = todaysPlay(scenePool(plays), dateKey)

        private val SCENE_POOLS = listOf(Triple(2, 2, 20), Triple(2, 3, 30))
        private val LEADING_STOP = Regex("^[.,:;\u2014-]+\\s*")
        private val SPACE = Regex("\\s+")

        private fun cleanSaid(text: String): String =
            text.replace("_", "").replace(SPACE, " ").trim().replace(LEADING_STOP, "").replace("--", "\u2014")

        /** A verse speech keeps its printed rows, one per line (the reader's own [PlayPage.isVerse]); prose is one run. */
        private fun cleanOpening(text: String, texts: List<String>): Pair<String, Boolean> {
            if (!PlayPage.isVerse(texts)) return cleanSaid(text) to false
            val rows = text.split('\n').map { cleanSaid(it) }.filter { it.isNotEmpty() }
            return rows.joinToString("\n") to (rows.size > 1)
        }

        /** The first [n] speeches with said words: from the script's lines, else from the index row's `opening` (contract §4.1). */
        fun openingOf(play: PlayListing, n: Int = 4): List<OpeningSpeech> = when (play) {
            is PlayScript -> play.lines.asSequence()
                .filter { it.kind == ScriptLine.Kind.Speech }
                .mapNotNull { l ->
                    val said = l.parts.orEmpty().filterIsInstance<LinePart.Say>().map { it.text }
                    val (text, verse) = cleanOpening(l.spokenText, said)
                    text.takeIf { it.isNotEmpty() }?.let { OpeningSpeech(l.part, l.role.orEmpty(), it, l.id, verse) }
                }
                .take(n).toList()
            is PlayRow -> play.opening.orEmpty().take(n)
                .mapNotNull { o ->
                    val (text, verse) = cleanOpening(o.text, listOf(o.text))
                    text.takeIf { it.isNotEmpty() }?.let { OpeningSpeech(PartID.role(o.role), o.role, it, null, verse) }
                }
            else -> emptyList()
        }

        /** The voice Try a line takes: the one that answers (the opening's second speaker), else the second part. */
        fun answeringPart(opening: List<OpeningSpeech>, script: PlayScript?): PartID? {
            val speakers = opening.map { it.part }.distinct()
            val parts = script?.castParts?.map { it.id }?.filter { it.isSpeaking } ?: speakers
            return speakers.getOrNull(1) ?: parts.firstOrNull { it != speakers.firstOrNull() } ?: speakers.firstOrNull() ?: parts.firstOrNull()
        }

        val PART_HUES = listOf("mystery", "scifi", "western", "serial", "documentary", "comedy", "news")
        const val PRESENCE_BINS = 24

        /** "Carlton, Henry Fisk" as Gutenberg files it reads "Henry Fisk Carlton". */
        fun displayName(filed: String): String {
            val pieces = filed.split(",", limit = 2).map { it.trim() }
            if (pieces.size != 2 || pieces[1].isEmpty() || pieces[1].first().isDigit()) return filed
            return pieces[1] + " " + pieces[0]
        }
    }
}

/** A line's words until [until] (an Apple reference date, as a take's `created` is). */
@Serializable
data class ScriptEdit(val until: Double, val text: String)

/** One speech of a play's opening: its part, the role as printed, the said words cleaned, and its line (null from an index row). */
data class OpeningSpeech(val part: PartID, val name: String, val text: String, val lineId: String?, val verse: Boolean = false)

/** A facet band: [key] holds every count from [lo] to [hi]. */
data class Band(val key: String, val lo: Int, val hi: Int)

/** A place a person may put a sound: a line (and the piece of it, null for the whole line) and the cue's own words. */
data class CueRow(val line: String, val piece: Int?, val text: String)

data class CastPart(val id: PartID, val lineCount: Int) {
    val title: String get() = id.title
}

/** The bundled castable scripts (phase 1 bundles the file; PLAYS-DESIGN §3). */
@Serializable
data class CastableLibrary(val format: Int, val scripts: List<PlayScript>) {
    companion object {
        const val ASSET = "castable-scripts.json"
        val json = Json { ignoreUnknownKeys = true }
        fun decode(text: String): CastableLibrary = json.decodeFromString(serializer(), text)
    }
}

/**
 * An author's years as the record has them, a year before the era as BCE (the label's rule, LabelSpec.lifeOf):
 * "1856–1950", "450–388 BCE", "4 BCE–65", "b. 1901", "d. 388 BCE"; "" with neither. js/plays-core.js `lifeYears`.
 */
fun lifeYears(born: Int?, died: Int?): String {
    fun year(y: Int) = if (y < 0) "${-y} BCE" else "$y"
    return when {
        born != null && died != null && born < 0 && died < 0 -> "${-born}–${-died} BCE"
        born != null && died != null -> "${year(born)}–${year(died)}"
        born != null -> "b. ${year(born)}"
        died != null -> "d. ${year(died)}"
        else -> ""
    }
}
