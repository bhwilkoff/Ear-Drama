package com.example.appname.plays

import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.StandardOpenOption
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

// The person's own scripts on this device (PLAYS-DESIGN §13, ANDROID-DESIGN §4.23; Decision 088.3): the one file that keeps
// them, the port of js/own-store.js. Nothing here leaves the device and nothing asks for an account.

/** The episode a script was cast from: its id and its page. */
@Serializable data class OwnEpisode(val id: String, val url: String)

/** A casting's transcript and copy, and where it was left (milliseconds). */
@Serializable data class OwnEar(val sig: String, val copy: String, val place: Long = 0)

@Serializable data class EarCount(val cast: Int, val lines: Int)

/** A script being corrected: the working copy, its title, the text as pasted, the parts named but not yet given a line. */
data class OwnRecord(
    val id: String,
    val title: String,
    val original: String,
    val doc: OwnDoc,
    val extras: List<String> = emptyList(),
    val created: Long,
    val updated: Long,
    val done: Boolean = false,
    val episode: OwnEpisode? = null,
    val ear: OwnEar? = null,
)

/** What Record's Your scripts draws without opening the script. */
@Serializable
data class OwnRow(
    override val id: String,
    override val title: String,
    val parts: Int,
    val lines: Int,
    val open: Int,
    val done: Boolean,
    override val cast: List<Int> = emptyList(),
    override val voices: Int = 0,
    val created: Long = 0,
    val updated: Long = 0,
    val episode: String? = null,
    val ear: EarCount? = null,
    val format: Int = 1,
) : PlayListing {
    override val kind: String get() = "own"
    override val year: Int? get() = null
    override val sortName: String? get() = null
    override val minutes: Int get() = 1
    override val authorLine: String get() = ""
    override val authorWithYears: String get() = ""
    override val speechCount: Int get() = lines

    /** How far it is: cast in part, lines with no part while it is corrected, else its size. */
    val facts: String
        get() = when {
            ear != null && ear.cast < ear.lines -> OwnWords.castLine(ear.cast, ear.lines)
            !done && open > 0 -> OwnWords.noPart(open)
            else -> OwnWords.partsAndLines(parts, lines)
        }
}

@Serializable data class OwnDraft(val title: String = "", val text: String = "")

/** A text to add, as it came from a file or another app: the words, or why not. */
sealed interface OwnText {
    data class Read(val text: String, val title: String = "") : OwnText
    data class Refused(val why: String) : OwnText

    companion object {
        /** Twice the cap: a UTF-16 file holds two bytes where UTF-8 holds one. Nothing past it is ever read. */
        const val MAX_READ = 2 * OwnScript.MAX_BYTES + 2

        /** A stream's text, at most [MAX_READ] bytes of it read (the cap stands before any parsing). */
        fun read(stream: java.io.InputStream): OwnText {
            val out = java.io.ByteArrayOutputStream()
            val buffer = ByteArray(16 * 1024)
            while (out.size() <= MAX_READ) {
                val n = stream.read(buffer, 0, minOf(buffer.size, MAX_READ + 1 - out.size()))
                if (n <= 0) break
                out.write(buffer, 0, n)
            }
            return decode(out.toByteArray())
        }

        /** Words another app shared: measured by [OwnScript.textRefusal] before anything reads them. */
        fun shared(words: CharSequence, title: String = ""): OwnText {
            if (words.length > OwnScript.MAX_BYTES) return Refused("too_long")
            val text = words.toString()
            return if (OwnScript.textRefusal(text) == "too_long") Refused("too_long") else Read(text, title.take(OwnScript.MAX_TITLE))
        }

        /**
         * A file's bytes as text, or why not (`too_long`, `not_text`). Bytes are counted before anything reads them. UTF-8,
         * UTF-16 with its mark, else Windows-1252 (old .txt files).
         */
        fun decode(b: ByteArray): OwnText {
            if (b.size > MAX_READ) return Refused("too_long")
            fun starts(vararg x: Int) = b.size >= x.size && x.indices.all { (b[it].toInt() and 0xff) == x[it] }
            if (starts(0x25, 0x50, 0x44, 0x46) || starts(0x7b, 0x5c, 0x72, 0x74, 0x66) || starts(0x50, 0x4b, 3, 4)) return Refused("not_text")
            val text = when {
                starts(0xff, 0xfe) -> String(b, 2, b.size - 2, Charsets.UTF_16LE)
                starts(0xfe, 0xff) -> String(b, 2, b.size - 2, Charsets.UTF_16BE)
                b.any { it.toInt() == 0 } -> return Refused("not_text")
                else -> utf8(b) ?: windows(b) ?: return Refused("not_text")
            }
            return if (OwnScript.textRefusal(text) == "too_long") Refused("too_long") else Read(text)
        }

        private fun utf8(b: ByteArray): String? = try {
            Charsets.UTF_8.newDecoder()
                .onMalformedInput(java.nio.charset.CodingErrorAction.REPORT)
                .onUnmappableCharacter(java.nio.charset.CodingErrorAction.REPORT)
                .decode(java.nio.ByteBuffer.wrap(b)).toString().removePrefix("\uFEFF")
        } catch (_: java.nio.charset.CharacterCodingException) {
            null
        }

        private fun windows(b: ByteArray): String? {
            val controls = b.count { val u = it.toInt() and 0xff; u < 32 && u != 9 && u != 10 && u != 12 && u != 13 }
            return if (controls > b.size / 500) null else String(b, java.nio.charset.Charset.forName("windows-1252"))
        }
    }
}

/** The words these pages say, one place. */
object OwnWords {
    private fun num(n: Int) = String.format(java.util.Locale.US, "%,d", n)
    private fun count(n: Int, one: String, many: String) = if (n == 1) "1 $one" else "${num(n)} $many"
    fun lines(n: Int) = count(n, "line", "lines")
    fun partsAndLines(parts: Int, lines: Int) = "${count(parts, "part", "parts")} · ${lines(lines)}"
    fun noPart(n: Int) = if (n == 1) "1 line has no part" else "${num(n)} lines have no part"
    fun castLine(cast: Int, lines: Int) = "${num(cast)} of ${num(lines)} lines cast"

    private val REFUSAL = mapOf(
        "too_long" to "That text is too long.", "too_many_lines" to "That text is too long.", "empty" to "There are no words.",
        "bad_name" to "That name does not work.", "line_has_take" to "This line has a take.", "lines_have_take" to "A line there has a take.",
        "part_has_take" to "A line of this part has a take.", "no_parts" to "No line has a part.", "no_lines" to "No lines.",
        "not_text" to "That is not a text file.", "no_title" to "Add a title.", "title_too_long" to "That title is too long.",
        "no_such_line" to "No line is lit.",
    )

    fun say(code: String): String = REFUSAL[code] ?: "That did not work."
    fun file(code: String): String = if (code == "too_long") "That file is too long." else say(code)
    fun script(code: String): String = if (code == "too_long" || code == "too_many_lines") "This script is too long." else say(code)
    fun name(code: String): String = when (code) {
        "too_long" -> "That name is too long."
        "empty" -> "Add a name."
        else -> say(code)
    }

    /** Why a write failed. */
    fun notKept(e: Throwable): String {
        val all = generateSequence(e) { it.cause }.take(6).joinToString(" ") { it.message.orEmpty() }
        return if (all.contains("ENOSPC") || all.contains("No space left", ignoreCase = true)) "This device is out of space." else "This device could not save it."
    }
}

/**
 * `filesDir/Scripts/`, beside `Plays/`:
 *   <id>/doc.json     the working copy OwnScript corrects, the title, the text as pasted
 *   <id>/script.json  the castable shape, once Done: what the reader and the recorder read
 *   <id>/row.json     what Your scripts draws without opening either
 *   draft.json        the text being added, before Next
 * A script's folder is written whole beside the old one and swapped in, so a full disk or a kill never leaves half of one
 * ([recover] finishes a swap that was cut short). Reads are tolerant as `production.json`'s are: a field a later version added is
 * ignored, one an earlier version lacked takes its default, and a folder a newer [FORMAT] wrote is left as it is.
 */
class OwnScripts(
    private val root: File,
    private val plays: () -> ProductionStore,
    private val now: () -> Long = { System.currentTimeMillis() },
    private val referenceNow: () -> Double = { ReferenceDate.now() },
    /** Productions here that took a change, so what was read of them is read again. */
    private val onAdopted: (List<String>) -> Unit = {},
    /** Writes one file; a test makes it fail. */
    private val writeFile: (File, String) -> Unit = { file, text -> writeSynced(file, text) },
) {
    private val lock = Mutex()
    private val disk = Any()
    private var recovered = false

    private val _rows = MutableStateFlow<List<OwnRow>?>(null)

    /** Your scripts, the last one changed first; null until [refresh] has read them. */
    val rows: StateFlow<List<OwnRow>?> = _rows

    suspend fun refresh() {
        _rows.value = withContext(Dispatchers.IO) { list() }
    }

    fun list(): List<OwnRow> = synchronized(disk) {
        recover()
        (root.listFiles() ?: emptyArray()).filter { it.isDirectory && OwnScript.isOwnId(it.name) }.sortedBy { it.name }
            .mapNotNull { dir -> read(File(dir, ROW))?.let { text -> runCatching { json.decodeFromString(OwnRow.serializer(), text) }.getOrNull() } }
            .filter { OwnScript.isOwnId(it.id) && it.format <= FORMAT }
            .sortedWith(compareByDescending<OwnRow> { it.updated }.thenBy { it.id })
    }

    /** A script being corrected, or null when it is not here. */
    fun get(id: String): OwnRecord? = synchronized(disk) {
        if (!OwnScript.isOwnId(id)) return null
        recover()
        val file = read(File(folder(id), DOC)) ?: return null
        val stored = json.decodeFromString(StoredRecord.serializer(), file)
        if (stored.format > FORMAT) null else stored.record()
    }

    /** The castable script, once Done; null before, and for an id not here. */
    fun script(id: String): PlayScript? = synchronized(disk) {
        if (!OwnScript.isOwnId(id)) return null
        recover()
        read(File(folder(id), SCRIPT))?.let { ProductionStore.json.decodeFromString(PlayScript.serializer(), it) }
    }

    /** A new script from a title and a text: its parts proposed, no line id given yet. */
    suspend fun create(title: String, text: String): OwnRecord {
        val at = now()
        val rec = withContext(Dispatchers.Default) {
            OwnRecord(newId(), OwnScript.trim(OwnScript.normalize(title)), OwnScript.normalize(text), OwnScript.newDoc(OwnScript.parse(text).lines), created = at, updated = at)
        }
        keep(rec)
        return rec
    }

    /** A script begun by casting an episode's transcript. Not kept until [keep]. */
    fun begin(title: String, doc: OwnDoc, episode: OwnEpisode, ear: OwnEar): OwnRecord {
        val at = now()
        return OwnRecord(newId(), OwnScript.trim(OwnScript.normalize(title)), "", doc, created = at, updated = at, episode = episode, ear = ear)
    }

    /** The script being cast from one of [ids] (an episode's own, and what it was called before), or null. */
    fun ofEpisode(isIt: (String) -> Boolean): OwnRow? = list().firstOrNull { it.episode != null && isIt(it.episode) }

    /**
     * Keeps [rec] as it stands. A Done script's castable shape is sealed and its productions follow; while its lines cannot
     * be a script ("no_parts"), the last one that could stays. The answer is that refusal or null; a failed write throws.
     * Calls are taken in the order they were made.
     */
    suspend fun keep(rec: OwnRecord): String? {
        val snap = rec.copy(doc = OwnScript.kept(rec.doc), updated = now())
        return lock.withLock {
            val (refusal, script) = withContext(Dispatchers.IO) { synchronized(disk) { write(snap) } }
            if (script != null) {
                val changed = withContext(Dispatchers.IO) { plays().adopt(script) }
                if (changed.isNotEmpty()) onAdopted(changed)
            }
            refresh()
            refusal
        }
    }

    suspend fun remove(id: String) {
        if (!OwnScript.isOwnId(id)) return
        lock.withLock {
            withContext(Dispatchers.IO) {
                synchronized(disk) {
                    recover()
                    val gone = File(root, ".$id.gone")
                    gone.deleteRecursively()
                    if (folder(id).exists() && !folder(id).renameTo(gone)) throw IOException("could not delete $id")
                    gone.deleteRecursively()
                }
            }
            refresh()
        }
    }

    /** The lines of [id] with a take in any of its productions: what may not move (§13 item 4). */
    fun takes(id: String): Set<String> = plays().takenLines(id)

    fun productions(id: String): List<Production> = plays().productionsOf(id)

    suspend fun draft(): OwnDraft? = withContext(Dispatchers.IO) {
        read(File(root, DRAFT))?.let { runCatching { json.decodeFromString(OwnDraft.serializer(), it) }.getOrNull() }
    }

    suspend fun setDraft(draft: OwnDraft?) = lock.withLock {
        withContext(Dispatchers.IO) {
            val file = File(root, DRAFT)
            if (draft == null || (draft.title.isEmpty() && draft.text.isEmpty())) {
                file.delete()
            } else {
                root.mkdirs()
                val partial = File(root, ".$DRAFT.partial")
                try {
                    writeFile(partial, json.encodeToString(OwnDraft.serializer(), draft))
                    if (!partial.renameTo(file)) throw IOException("could not save the draft")
                } finally {
                    partial.delete()
                }
            }
            Unit
        }
    }

    /** Export my data's `scripts` (docs/EXPORT.md): each one's lines as they stand, Done or not. */
    fun exportRows(): List<JsonObject> = list().mapNotNull { row ->
        val rec = get(row.id) ?: return@mapNotNull null
        fun piece(p: OwnPiece) = mapOf((if (p is OwnPiece.Say) "say" else "direction") to p.text)
        val lines = (if (rec.done) script(row.id) else null)?.lines?.map { l ->
            if (l.kind == ScriptLine.Kind.Speech) {
                mapOf("id" to l.id, "kind" to "speech", "role" to l.role, "parts" to piecesOf(l).map(::piece))
            } else {
                mapOf("id" to l.id, "kind" to l.kind.name.lowercase(java.util.Locale.ROOT), "source" to l.source.orEmpty())
            }
        } ?: OwnScript.settle(rec.doc).lines.map { l ->
            if (l.kind == "speech") mapOf("kind" to "speech", "role" to l.role, "parts" to OwnScript.pieces(l.text).map(::piece))
            else mapOf("kind" to l.kind, "source" to l.text)
        }
        buildJsonObject {
            put("id", JsonPrimitive(rec.id))
            put("title", JsonPrimitive(rec.title))
            put("source", JsonPrimitive(if (rec.episode != null) SOURCE_EPISODE else SOURCE_ADDED))
            rec.episode?.let { put("episode", JsonPrimitive(it.id)) }
            put("created", JsonPrimitive(java.time.Instant.ofEpochMilli(rec.created).toString()))
            put("done", JsonPrimitive(rec.done))
            put("lines", element(lines))
        }
    }

    // ---- The disk ----

    private fun folder(id: String) = File(root, id)
    private fun read(file: File): String? = if (file.isFile) file.readText() else null

    private fun write(snap: OwnRecord): Pair<String?, PlayScript?> {
        recover()
        val settled = OwnScript.settle(snap.doc).lines
        val parts = OwnScript.partsOf(settled).map { it.second }.sortedDescending()
        var script: PlayScript? = null
        var refusal: String? = null
        if (snap.done) {
            val taken = takes(snap.id)
            // A transcript half cast keeps its lines open: the script's are directions until they are somebody's.
            val built = OwnScript.toScript(
                OwnScript.done(snap.doc, keepOpen = snap.ear != null),
                OwnMeta(snap.id, snap.title, snap.episode?.id, snap.episode?.url),
            )
            refusal = OwnScript.refusalOf(built)
            if (refusal == null) {
                val sealed = ProductionStore.json.decodeFromJsonElement(PlayScript.serializer(), element(OwnScript.seal(built)))
                script = sealed.copy(created = snap.created, edits = editsOf(script(snap.id), sealed, taken))
            }
        }
        val row = OwnRow(
            snap.id, snap.title, parts.size, settled.size, settled.count { it.kind == "open" }, snap.done, parts,
            parts.count { it >= CASTABLE_LINES }, snap.created, snap.updated, snap.episode?.id,
            snap.ear?.let { OwnScript.castCount(snap.doc).let { (n, of) -> EarCount(n, of) } }, FORMAT,
        )
        root.mkdirs()
        val next = File(root, ".${snap.id}.next")
        next.deleteRecursively()
        try {
            if (!next.mkdirs()) throw IOException("could not save ${snap.id}")
            val was = File(folder(snap.id), SCRIPT)
            if (script != null) writeFile(File(next, SCRIPT), ProductionStore.json.encodeToString(PlayScript.serializer(), script))
            else if (was.isFile) writeFile(File(next, SCRIPT), was.readText())
            writeFile(File(next, DOC), json.encodeToString(StoredRecord.serializer(), StoredRecord.of(snap)))
            writeFile(File(next, ROW), json.encodeToString(OwnRow.serializer(), row))
        } catch (e: Throwable) {
            next.deleteRecursively()
            throw e
        }
        val old = File(root, ".${snap.id}.old")
        old.deleteRecursively()
        val dir = folder(snap.id)
        if (dir.exists() && !dir.renameTo(old)) throw IOException("could not save ${snap.id}")
        if (!next.renameTo(dir)) {
            old.renameTo(dir)
            throw IOException("could not save ${snap.id}")
        }
        old.deleteRecursively()
        return refusal to script
    }

    /** Finishes a swap that was cut short: the new folder when it was whole, else the old one; then what is left over goes. */
    private fun recover() {
        if (recovered) return
        recovered = true
        val left = root.listFiles()?.filter { it.isDirectory && it.name.startsWith(".own-") }?.sortedBy { it.name } ?: return
        for (kind in listOf("next", "old")) for (dir in left.filter { it.name.endsWith(".$kind") && it.exists() }) {
            val id = dir.name.removePrefix(".").removeSuffix(".$kind")
            if (!OwnScript.isOwnId(id) || folder(id).exists()) continue
            // The row is written last, so a folder with one is whole.
            if (kind == "old" || File(dir, ROW).isFile) dir.renameTo(folder(id))
        }
        left.forEach { if (it.exists()) it.deleteRecursively() }
    }

    /** What a line with a take said before its words changed, and until when, oldest first. */
    private fun editsOf(was: PlayScript?, now: PlayScript, taken: Set<String>): Map<String, List<ScriptEdit>> {
        if (was == null) return emptyMap()
        val edits = LinkedHashMap(was.edits)
        val before = was.lines.associate { it.id to textOf(it) }
        for (l in now.lines) {
            val old = before[l.id]
            if (l.id in taken && old != null && old != textOf(l)) edits[l.id] = edits[l.id].orEmpty() + ScriptEdit(referenceNow(), old)
        }
        return edits
    }

    @Serializable
    private data class StoredLine(
        val k: Int, val id: String? = null, val kind: String, val role: String? = null, val text: String, val label: String? = null,
        val at: List<Long>? = null, val mark: String? = null, val out: Boolean = false,
    ) {
        fun line() = OwnLine(
            k, id, kind, role, text, label, at?.takeIf { it.size == 2 }?.let { it[0] to it[1] },
            if (out) OwnWho.Out else mark?.let { OwnWho.Role(it) },
        )

        companion object {
            fun of(l: OwnLine) = StoredLine(
                l.k, l.id, l.kind, l.role, l.text, l.label, l.at?.let { listOf(it.first, it.second) },
                (l.mark as? OwnWho.Role)?.name, l.mark == OwnWho.Out,
            )
        }
    }

    @Serializable
    private data class StoredRecord(
        val format: Int = 1,
        val id: String,
        val title: String,
        val original: String = "",
        val lines: List<StoredLine> = emptyList(),
        val nextKey: Int = 1,
        val letters: Map<String, Int> = emptyMap(),
        val heard: List<Int> = emptyList(),
        val extras: List<String> = emptyList(),
        val created: Long = 0,
        val updated: Long = 0,
        val done: Boolean = false,
        val episode: OwnEpisode? = null,
        val ear: OwnEar? = null,
    ) {
        fun record() = OwnRecord(
            id, title, original, OwnDoc(lines.map { it.line() }, maxOf(nextKey, (lines.maxOfOrNull { it.k } ?: 0) + 1), letters, heard),
            extras, created, updated, done, episode, ear,
        )

        companion object {
            fun of(r: OwnRecord) = StoredRecord(
                FORMAT, r.id, r.title, r.original, r.doc.lines.map(StoredLine::of), r.doc.nextKey, r.doc.letters, r.doc.heard, r.extras,
                r.created, r.updated, r.done, r.episode, r.ear,
            )
        }
    }

    companion object {
        const val FORMAT = 1
        const val DOC = "doc.json"
        const val ROW = "row.json"
        const val SCRIPT = "script.json"
        const val DRAFT = "draft.json"
        const val CASTABLE_LINES = 5
        const val SOURCE_ADDED = "Added by you"
        const val SOURCE_EPISODE = "Automatic transcript"

        val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

        fun newId() = "own-" + UUID.randomUUID().toString().lowercase(java.util.Locale.ROOT)

        /** Text, on the disk before it is named: a swap never names a folder the disk has not taken. */
        private fun writeSynced(file: File, text: String) {
            Files.write(
                file.toPath(), text.toByteArray(Charsets.UTF_8),
                StandardOpenOption.CREATE, StandardOpenOption.TRUNCATE_EXISTING, StandardOpenOption.WRITE, StandardOpenOption.DSYNC,
            )
        }

        /** Plain data (what [OwnScript.toScript] answers) as JSON. */
        fun element(v: Any?): JsonElement = when (v) {
            null -> JsonNull
            is Map<*, *> -> JsonObject(v.entries.associate { (it.key as String) to element(it.value) })
            is List<*> -> JsonArray(v.map(::element))
            is Number -> JsonPrimitive(v)
            is Boolean -> JsonPrimitive(v)
            else -> JsonPrimitive(v.toString())
        }

        private fun piecesOf(l: ScriptLine): List<OwnPiece> =
            l.parts.orEmpty().map { if (it is LinePart.Say) OwnPiece.Say(it.text) else OwnPiece.Direction(it.text) }

        private fun textOf(l: ScriptLine): String =
            if (l.kind == ScriptLine.Kind.Speech) OwnScript.textOf(piecesOf(l)) else l.source.orEmpty()

        /** Whether the words of [take]'s line changed, more than punctuation, since it was recorded (§13 item 4). */
        fun wordsChanged(script: PlayScript?, take: Take): Boolean {
            val said = script?.edits?.get(take.lineID)?.firstOrNull { take.created < it.until } ?: return false
            val line = script.lines.firstOrNull { it.id == take.lineID } ?: return false
            return OwnScript.wordsChanged(said.text, textOf(line))
        }

        /**
         * The script as plain text, readable as Fountain and by Add a script: a name alone in capitals over its words (an `@`
         * before one with no capital letter to show), directions as paragraphs.
         */
        fun asText(script: PlayScript): String = script.lines.joinToString("\n\n") { l ->
            if (l.kind != ScriptLine.Kind.Speech) textOf(l)
            else "${if (l.role.orEmpty().any { it in 'A'..'Z' }) "" else "@"}${l.role}\n${textOf(l)}"
        } + "\n"

        fun fileName(title: String): String =
            title.replace(Regex("[\\\\/:*?\"<>|]+"), "").trim().ifEmpty { "Script" } + ".txt"

        /** Each line with no part's two nearest speakers, as [OwnScript.nearestParts] answers, for every line in two passes. */
        fun nearestAll(lines: List<OwnLine>): Map<Int, List<String>> {
            fun sweep(indices: IntProgression): Array<List<Pair<String, Int>>> {
                val out = Array(lines.size) { emptyList<Pair<String, Int>>() }
                var two = emptyList<Pair<String, Int>>()
                for (i in indices) {
                    out[i] = two
                    val l = lines[i]
                    if (l.kind == "speech") two = (listOf(l.role.orEmpty() to i) + two.filter { it.first != l.role }).take(2)
                }
                return out
            }
            val above = sweep(lines.indices)
            val below = sweep(lines.indices.reversed())
            val out = HashMap<Int, List<String>>()
            lines.forEachIndexed { i, l ->
                if (l.kind != "open") return@forEachIndexed
                val near = above[i].map { Triple(it.first, i - it.second, 0) } + below[i].map { Triple(it.first, it.second - i, 1) }
                out[l.k] = near.sortedWith(compareBy({ it.second }, { it.third })).map { it.first }.distinct().take(2)
            }
            return out
        }
    }
}
