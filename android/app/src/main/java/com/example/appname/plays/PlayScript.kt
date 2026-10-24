package com.example.appname.plays

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
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
    val title: String get() = roleName ?: if (this == DIRECTIONS) "Stage directions" else "Sound effects"

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
    val id: String,
    val revision: String,
    val kind: String,
    val title: String,
    val authors: List<Author> = emptyList(),
    val source: Source,
    val rights: Rights,
    val roles: List<Role> = emptyList(),
    val lines: List<ScriptLine>,
    val year: Int? = null,
) {
    @Serializable data class Author(val name: String? = null, val born: Int? = null, val died: Int? = null)
    @Serializable data class Source(val name: String, val url: String)
    @Serializable data class Evidence(val claim: String? = null, val src: String? = null)
    @Serializable data class Rights(val bucket: String, val evidence: List<Evidence> = emptyList())
    @Serializable data class Role(val name: String, val lines: Int, val words: Int)

    val authorLine: String get() = authors.mapNotNull { it.name }.joinToString(", ") { displayName(it) }

    /** The author with born and died years where the record has them. */
    val authorWithYears: String
        get() = authors.mapNotNull { a ->
            val name = a.name?.let(::displayName) ?: return@mapNotNull null
            val years = when {
                a.born != null && a.died != null -> " (${a.born}\u2013${a.died})"
                a.born != null -> " (b. ${a.born})"
                a.died != null -> " (d. ${a.died})"
                else -> ""
            }
            name + years
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
        val others = listOf(PartID.SOUND, PartID.DIRECTIONS).filter { it in counts }
        (speaking + others).map { CastPart(it, counts.getValue(it)) }
    }

    val speechLineIDs: List<String> get() = lines.filter { it.kind == ScriptLine.Kind.Speech }.map { it.id }

    companion object {
        /** "Carlton, Henry Fisk" as Gutenberg files it reads "Henry Fisk Carlton". */
        fun displayName(filed: String): String {
            val pieces = filed.split(",", limit = 2).map { it.trim() }
            if (pieces.size != 2 || pieces[1].isEmpty() || pieces[1].first().isDigit()) return filed
            return pieces[1] + " " + pieces[0]
        }
    }
}

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
