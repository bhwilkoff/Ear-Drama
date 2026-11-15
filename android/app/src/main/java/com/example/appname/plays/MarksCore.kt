package com.example.appname.plays

import java.time.Instant
import kotlinx.serialization.Serializable

// Marks in the script reader (PLAYS-DESIGN §2.10, ANDROID-DESIGN §4.17; Decision 076 S5): a port of js/marks-core.js,
// names kept, held to catalog/tests/golden/marks_anchor.json and js/marks.test.js (MarksCoreTest). A mark is anchored to
// a line, never a page: (script, revision, line id, start, end) in UTF-16 units of ScriptReading.lineText, with the
// marked words and up to 32 characters either side, so a new revision of the script re-anchors it by its words.

/** One mark; the web's JSON keys exactly, times in epoch milliseconds. */
@Serializable
data class Mark(
    val id: String,
    val kind: String,
    val line: String,
    val start: Int,
    val end: Int,
    val text: String = "",
    val prefix: String = "",
    val suffix: String = "",
    val revision: String? = null,
    val created: Long = 0,
    val updated: Long = 0,
    val hue: String? = null,
    val label: String? = null,
    val note: String? = null,
    val group: String? = null,
)

/** The extra fields `make` takes: a highlight's hue, a beat's label, a note's words, the group of a selection over lines. */
data class MarkExtra(val hue: String? = null, val label: String? = null, val note: String? = null, val group: String? = null)

/** The patch `update` takes. */
data class MarkPatch(val hue: String? = null, val label: String? = null, val note: String? = null)

/** One line's part of a selection, in raw offsets into the line's words. */
data class Piece(val line: String, val start: Int, val end: Int)

/** What `place` returns: the marks put where their words are now, those it could not place, and whether to save. */
data class Placement(val placed: List<Mark>, val lost: List<Mark>, val changed: Boolean)

/** `removed` is what went, for Undo. */
data class Removal(val marks: List<Mark>, val removed: List<Mark>)

object MarksCore {
    val KINDS = listOf("highlight", "underline", "breath", "pause", "beat", "note")
    /** Marks over words; the rest stand between two words. */
    val SPAN = setOf("highlight", "underline", "note")
    /** Marks that never stack: an overlapping or touching one of the same kind merges. */
    val MERGE = setOf("highlight", "underline")
    val HUES = listOf("yellow", "green", "blue", "pink")
    const val CONTEXT = 32
    /** Away from its own line, a mark moves only on this many characters of evidence (words plus context), or all it has. */
    const val EVIDENCE = 16
    /** In its own line, a point mark needs this much of its context to match. */
    const val POINT_EVIDENCE = 8
    const val LABEL_MAX = 24

    private fun textOf(line: ScriptLine) = ScriptReading.lineText(line)

    /** A word's characters: letters, digits, apostrophes, hyphens, and the printed `_italic_` marks. */
    fun isWord(ch: Char): Boolean {
        if (ch == '\'' || ch == '’' || ch == '_' || ch == '-') return true
        if (ch.isLetter()) return true
        return when (Character.getType(ch).toByte()) {
            Character.DECIMAL_DIGIT_NUMBER, Character.LETTER_NUMBER, Character.OTHER_NUMBER -> true
            else -> false
        }
    }

    /** JavaScript's `\s`. */
    private val SPACES = intArrayOf(0x20, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF)

    fun isSpace(ch: Char): Boolean = ch.code in 9..13 || ch.code in 0x2000..0x200A || ch.code in SPACES

    /** A selection grown to whole words and trimmed of space; null when nothing is left. */
    fun snapWords(text: String, start: Int, end: Int): IntRange? {
        var s = maxOf(0, minOf(start, end, text.length))
        var e = minOf(text.length, maxOf(start, end, 0))
        while (s < e && isSpace(text[s])) s++
        while (e > s && isSpace(text[e - 1])) e--
        if (s >= e) return null
        while (s > 0 && isWord(text[s - 1]) && isWord(text[s])) s--
        while (e < text.length && isWord(text[e]) && isWord(text[e - 1])) e++
        return s until e
    }

    /** Where a point mark goes for a selection ending at [end]: after its word and any punctuation that follows. */
    fun pointAfter(text: String, end: Int): Int {
        var p = maxOf(0, minOf(end, text.length))
        while (p > 0 && isSpace(text[p - 1])) p--
        while (p < text.length && isWord(text[p])) p++
        while (p < text.length && !isSpace(text[p]) && !isWord(text[p])) p++
        return p
    }

    private var seq = 0
    private val random = java.util.Random()
    private fun newId(now: Long): String = "m${now.toString(36)}${(seq++).toString(36)}${random.nextInt(1296).toString(36)}"

    private class Quote(val text: String, val prefix: String, val suffix: String)

    /** The anchor's quote: the words and their context, read from the line as it is now. */
    private fun quote(lt: String, start: Int, end: Int) =
        Quote(lt.substring(start, end), lt.substring(maxOf(0, start - CONTEXT), start), lt.substring(end, minOf(lt.length, end + CONTEXT)))

    /** One mark on one line; null when the line or the kind is unknown. */
    fun make(script: PlayScript, lineID: String, start: Int, end: Int, kind: String, extra: MarkExtra = MarkExtra(), now: Long = System.currentTimeMillis()): Mark? {
        val line = script.lines.firstOrNull { it.id == lineID } ?: return null
        if (kind !in KINDS) return null
        val lt = textOf(line)
        val s = maxOf(0, minOf(start, lt.length))
        val e = if (kind in SPAN) maxOf(s, minOf(end, lt.length)) else s
        val q = quote(lt, s, e)
        return Mark(
            newId(now), kind, lineID, s, e, q.text, q.prefix, q.suffix, script.revision, now, now,
            hue = if (kind == "highlight") (extra.hue?.takeIf { it in HUES } ?: HUES[0]) else null,
            label = if (kind == "beat") extra.label.orEmpty().trim().take(LABEL_MAX) else null,
            note = if (kind == "note") extra.note.orEmpty() else null,
            group = extra.group?.takeIf { kind in MERGE },
        )
    }

    /**
     * The marks a selection makes. [pieces] are the selection per line in reading order. A span mark covers each piece
     * grown to whole words (a note: its first line's piece only); highlights and underlines across lines share a group. A
     * point mark goes after the last piece's last word.
     */
    fun fromSelection(script: PlayScript, pieces: List<Piece>, kind: String, extra: MarkExtra = MarkExtra(), now: Long = System.currentTimeMillis()): List<Mark> {
        val byId = script.lines.associateBy { it.id }
        class Snapped(val line: String, val lt: String, val start: Int, val end: Int)
        val snapped = ArrayList<Snapped>()
        for (p in pieces) {
            val line = byId[p.line] ?: continue
            val lt = textOf(line)
            val w = snapWords(lt, p.start, p.end) ?: continue
            snapped += Snapped(p.line, lt, w.first, w.last + 1)
        }
        if (snapped.isEmpty()) return emptyList()
        if (kind !in SPAN) {
            val last = snapped.last()
            val at = pointAfter(last.lt, last.end)
            return listOfNotNull(make(script, last.line, at, at, kind, extra, now))
        }
        val use = if (kind == "note") snapped.take(1) else snapped
        val group = if (use.size > 1 && kind in MERGE) "g${newId(now)}" else null
        return use.mapNotNull { make(script, it.line, it.start, it.end, kind, extra.copy(group = group), now) }
    }

    /**
     * Adds a mark by the overlap rules: a highlight or underline that overlaps or touches others of its kind in the line
     * merges with them into one over all their words, taking the new mark's id, hue and group; a note is always its own;
     * a breath, pause or beat replaces any point mark at its place.
     */
    fun add(script: PlayScript, marks: List<Mark>, mark: Mark?): List<Mark> {
        if (mark == null) return marks.toList()
        var out = marks.toMutableList()
        var added: Mark = mark
        if (mark.kind in MERGE) {
            var s = mark.start
            var e = mark.end
            var grew = true
            val gone = HashSet<String>()
            while (grew) {
                grew = false
                for (m in out) {
                    if (m.id in gone || m.kind != mark.kind || m.line != mark.line) continue
                    if (m.start <= e && s <= m.end) {
                        gone += m.id
                        s = minOf(s, m.start)
                        e = maxOf(e, m.end)
                        grew = true
                    }
                }
            }
            out = out.filter { it.id !in gone }.toMutableList()
            if (s != mark.start || e != mark.end) {
                val line = script.lines.firstOrNull { it.id == mark.line }
                val lt = line?.let(::textOf).orEmpty()
                val q = quote(lt, s, e)
                added = mark.copy(start = s, end = e, text = q.text, prefix = q.prefix, suffix = q.suffix)
            }
        } else if (mark.kind !in SPAN) {
            out = out.filter { it.kind in SPAN || it.line != mark.line || it.start != mark.start }.toMutableList()
        }
        out += added
        return out
    }

    /** Removes a mark and the rest of its group, so the removal can be undone. */
    fun remove(marks: List<Mark>, id: String): Removal {
        val m = marks.firstOrNull { it.id == id } ?: return Removal(marks.toList(), emptyList())
        fun hit(x: Mark) = x.id == id || (m.group != null && x.group == m.group)
        return Removal(marks.filter { !hit(it) }, marks.filter(::hit))
    }

    /** Changes a mark: a hue for its whole group, a beat's label, a note's words. */
    fun update(marks: List<Mark>, id: String, patch: MarkPatch, now: Long = System.currentTimeMillis()): List<Mark> {
        val m = marks.firstOrNull { it.id == id } ?: return marks.toList()
        return marks.map { x ->
            if (x.id != id && !(patch.hue != null && m.group != null && x.group == m.group)) return@map x
            var y = x.copy(updated = now)
            if (patch.hue != null && x.kind == "highlight" && patch.hue in HUES) y = y.copy(hue = patch.hue)
            if (x.id == id && patch.label != null && x.kind == "beat") y = y.copy(label = patch.label.trim().take(LABEL_MAX))
            if (x.id == id && patch.note != null && x.kind == "note") y = y.copy(note = patch.note)
            y
        }
    }

    // MARK: Re-anchoring a revision (PLAYS-DESIGN §2.10 rule 4)

    private fun commonTail(a: String, b: String): Int {
        var n = 0
        while (n < a.length && n < b.length && a[a.length - 1 - n] == b[b.length - 1 - n]) n++
        return n
    }

    private fun commonHead(a: String, b: String): Int {
        var n = 0
        while (n < a.length && n < b.length && a[n] == b[n]) n++
        return n
    }

    class Best(val at: Int, val score: Int, val off: Int)

    private fun occurrences(lt: String, needle: String): List<Int> {
        val out = ArrayList<Int>()
        var k = lt.indexOf(needle)
        while (k >= 0) {
            out += k
            k = lt.indexOf(needle, k + 1)
        }
        return out
    }

    /** The best place for a mark in one line's words: where, and how many context characters matched; null when nowhere. */
    fun bestIn(lt: String, mark: Mark): Best? {
        val text = mark.text
        val at = LinkedHashSet<Int>()
        if (text.isNotEmpty()) {
            at += occurrences(lt, text)
        } else {
            val tail = mark.prefix.takeLast(16)
            val head = mark.suffix.take(16)
            if (tail.isNotEmpty()) for (k in occurrences(lt, tail)) at += k + tail.length
            if (head.isNotEmpty()) at += occurrences(lt, head)
            if (tail.isEmpty() && head.isEmpty()) at += 0
        }
        var best: Best? = null
        for (k in at) {
            val score = commonTail(mark.prefix, lt.substring(0, k)) + commonHead(mark.suffix, lt.substring(minOf(lt.length, k + text.length)))
            val off = Math.abs(k - mark.start)
            val b = best
            if (b == null || score > b.score || (score == b.score && off < b.off)) best = Best(k, score, off)
        }
        return best
    }

    /** Where a line id sorts among the script's ids (`L0009a` after `L0009`, before `L0010`). */
    private fun sortIndex(ids: List<String>, id: String): Int {
        var i = 0
        while (i < ids.size && ids[i] < id) i++
        return i
    }

    /**
     * Re-anchors stored marks to [script] as it is now. A placed mark carries its (maybe new) line, offsets, quote and this
     * revision; a lost mark is returned exactly as stored. `changed` is true when any placed mark moved or took the new revision.
     */
    fun place(script: PlayScript, marks: List<Mark>): Placement {
        val lines = script.lines
        val texts = lines.map(::textOf)
        val ids = lines.map { it.id }
        val index = HashMap<String, Int>().also { m -> ids.forEachIndexed { i, id -> m.putIfAbsent(id, i) } }
        val rev: String? = script.revision
        val placed = ArrayList<Mark>()
        val lost = ArrayList<Mark>()
        var changed = false
        fun put(m: Mark, i: Int, at: Int) {
            val end = at + m.text.length
            val q = quote(texts[i], at, end)
            val y = m.copy(line = ids[i], start = at, end = end, prefix = q.prefix, suffix = q.suffix, revision = rev)
            if (y.line != m.line || y.start != m.start || y.end != m.end || y.revision != m.revision || y.prefix != m.prefix || y.suffix != m.suffix) changed = true
            placed += y
        }
        for (m in marks) {
            val text = m.text
            val own = index[m.line]
            // 1. The same revision, and the slice still reads the words.
            if (own != null && m.revision == rev && rev != null && m.end <= texts[own].length && texts[own].substring(m.start, m.end) == text) {
                placed += m
                continue
            }
            // 2. The same line: the best place its words (or a point mark's context) stand.
            val avail = m.prefix.length + m.suffix.length
            if (own != null) {
                val b = bestIn(texts[own], m)
                if (b != null && (text.isNotEmpty() || b.score >= minOf(POINT_EVIDENCE, avail))) {
                    put(m, own, b.at)
                    continue
                }
            }
            // 3. Every other line, nearest first, on evidence.
            val from = own ?: sortIndex(ids, m.line)
            var best: Best? = null
            var bestLine = -1
            var bestDist = 0
            for (i in lines.indices) {
                if (i == own) continue
                val b = bestIn(texts[i], m) ?: continue
                val dist = Math.abs(i - from)
                val cur = best
                if (cur == null || b.score > cur.score || (b.score == cur.score && (dist < bestDist || (dist == bestDist && b.off < cur.off)))) {
                    best = b
                    bestLine = i
                    bestDist = dist
                }
            }
            val b = best
            if (b != null && text.length + b.score >= minOf(EVIDENCE, text.length + avail) && (text.isNotEmpty() || b.score > 0)) {
                put(m, bestLine, b.at)
                continue
            }
            // 4. Not placed: kept as it was.
            lost += m
        }
        return Placement(placed, lost, changed)
    }

    /** The notebook's order: script order (line, then offset), then the kinds' order. */
    fun order(script: PlayScript, marks: List<Mark>): List<Mark> {
        val index = HashMap<String, Int>().also { m -> script.lines.forEachIndexed { i, l -> m.putIfAbsent(l.id, i) } }
        return marks.sortedWith(
            compareBy<Mark> { index[it.line] ?: 1_000_000_000 }.thenBy { it.start }.thenBy { it.end }.thenBy { KINDS.indexOf(it.kind) },
        )
    }

    /** Marks at an offset in a line, the narrowest first (what a tap on the words opens); a note before an equal underline. */
    fun at(marks: List<Mark>, lineID: String, offset: Int): List<Mark> =
        marks.filter { it.kind in SPAN && it.line == lineID && it.start <= offset && offset < it.end }
            .sortedWith(compareBy<Mark> { it.end - it.start }.thenBy { if (it.kind == "note") 0 else 1 })

    // MARK: On the device

    /** A stored mark is read back only when it is whole: a known kind, sane offsets. */
    fun valid(m: Mark): Boolean = m.id.isNotEmpty() && m.kind in KINDS && m.line.isNotEmpty() && m.start >= 0 && m.end >= m.start

    /** One row of the person's own export (docs/EXPORT.md `marks[]`); an absent field is null. */
    data class ExportRow(
        val script: String, val title: String?, val revision: String?, val line: String, val start: Int, val end: Int, val kind: String,
        val text: String, val hue: String?, val label: String?, val note: String?, val created: String?, val updated: String?,
    )

    private fun iso(ms: Long): String? = if (ms > 0) Instant.ofEpochMilli(ms).toString() else null

    fun exportRow(script: String, title: String?, m: Mark) = ExportRow(
        script, title, m.revision, m.line, m.start, m.end, m.kind, m.text, m.hue, m.label, m.note, iso(m.created), iso(m.updated),
    )
}
