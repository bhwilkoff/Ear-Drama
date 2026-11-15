package com.example.appname.plays

// The Ear Drama page (docs/research/design, R2 play typography, PLAYS-DESIGN §2.7 rule 10): how one script line
// is set, as plain data with no drawing. A port of the web's ReaderCore.layoutOf, isVerse and cueTail
// (js/reader-core.js), held to js/reader.test.js case for case. Every run keeps its UTF-16 offset into
// ScriptReading.lineText, so marks still anchor; a character the page leaves out (a printed speaker label's
// period, a direction's enclosing bracket) is simply not drawn, and a line break inside prose is drawn as the
// space it stands for.

/** One printed run of a laid-out line (`kind`, `said` and `piece` as [ScriptReading.Run]; [at] into the line's text). */
data class PageRun(var kind: ScriptReading.RunKind, var text: String, var at: Int, val piece: Int, var said: Boolean)

/** A row: one printed verse line, the prose of a speech between cues, or a sound cue ([cue]). */
class PageRow(val cue: Boolean, var indent: Boolean, val runs: MutableList<PageRun> = ArrayList())

/** One speaker's turn: the line's own role ([name] null, drawn from [role], outside the printed words) or a second speaker run into the line. */
class PageSpeech(val role: String, val name: PageRun?, val rows: MutableList<PageRow> = ArrayList())

class PageLine(
    /** A speech's printed breaks are verse (kept), else a transcriber's wrapping (reflowed). */
    val verse: Boolean = false,
    /** A speech's turns; empty for a block. */
    val speeches: List<PageSpeech> = emptyList(),
    /** A block's one row (a direction or a cue); empty for a speech. */
    val rows: List<PageRow> = emptyList(),
)

object PlayPage {
    /** A page this many em wide sets the speaker's name in a gutter beside the words; narrower, over them. */
    const val GUTTER_MIN_EM = 30f

    private fun isSpace(c: Char) = c.isWhitespace() || c.code == 0xA0 || c.code == 0xFEFF

    private fun leadingSpace(s: String): Int {
        var n = 0
        while (n < s.length && isSpace(s[n])) n++
        return n
    }

    private fun hasLetter(s: String) = s.any { it.isLetter() }

    // MARK: Verse

    private val ROW_SKIP = "'\"‘’“”([_—–-"

    private fun rowStart(row: String): Char? = row.firstOrNull { !isSpace(it) && it !in ROW_SKIP }

    /**
     * Whether a speech's printed line breaks are verse (kept) or a transcriber's wrapping (reflowed): verse when
     * the speech has a break and every row after a break begins with a capital, and its rows are not mostly as
     * long as a wrapped prose line (60 characters and more).
     */
    fun isVerse(texts: List<String>): Boolean {
        val rows = ArrayList<String>()
        val after = ArrayList<String>()
        for (t in texts) t.split('\n').forEachIndexed { i, p ->
            rows += p
            if (i > 0) after += p
        }
        val tail = after.filter { it.isNotBlank() }
        if (tail.isEmpty()) return false
        for (r in tail) {
            val c = rowStart(r) ?: return false
            if (c.lowercaseChar() == c || !c.isLetter()) return false
        }
        val full = rows.map { it.trim() }.filter { it.isNotEmpty() }
        val body = full.dropLast(1)
        val long = body.count { it.length >= 60 }
        if (body.isNotEmpty() && long.toDouble() / body.size >= 0.7) return false
        return full.size >= 3 || (full.firstOrNull()?.length ?: 0) < 50
    }

    // MARK: Cues

    private val CUE_WORDS = Regex("^[\\s(\\[_]*(?:(?:sounds?|noises?) of\\b|music\\b)", RegexOption.IGNORE_CASE)

    /** An aside whose words begin "sound of", "noise of" or "music" is a cue, whatever the parser called it. */
    fun isCueWords(text: String): Boolean = CUE_WORDS.containsMatchIn(text)

    private val SENTENCE_BREAK = Regex("[.!?;:—]['\"’”)\\]]*\\s+(?=\\S)")

    /** The offset a speech's cue begins at: the last sentence break, or 0 when the whole speech is one sentence. */
    fun cueTail(text: String): Int {
        val end = text.trimEnd().length
        var at = 0
        for (m in SENTENCE_BREAK.findAll(text)) {
            val stop = m.range.first + m.value.length
            if (stop < end - 2) at = stop
        }
        return at
    }

    // MARK: Layout

    private val EMPHASIS_END = Regex("[.!?][\"’”]?\\s*$")

    /** Replaces each break and the space after it with spaces of the same length (the offsets stay put). */
    private fun flatten(text: String): String = text.replace(Regex("\n\\s*")) { " ".repeat(it.value.length) }

    private val OPEN_BRACKET = Regex("^\\s*[\\[(]\\s*")
    private val CLOSE_BRACKET = Regex("\\s*[\\])]\\s*$")

    /**
     * How a line is set. A speech gives `speeches`: one, or more when the printed text runs a second speaker's
     * speech into the first ("Why not?\nGRACE" then ". Never mind why.", a parser miss the page still
     * attributes). Verse keeps a row per printed line; prose is one row, broken only by a cue. A block gives one
     * row, its enclosing brackets left undrawn. [roles] is the script's role names.
     */
    fun layoutOf(line: ScriptLine, roles: List<String>): PageLine {
        val runs = ScriptReading.runsOf(line).map { PageRun(it.kind, it.text, it.at, it.piece, it.said) }
        val parts = line.parts
        val isSpeech = line.kind == ScriptLine.Kind.Speech && parts != null

        // A word or three printed in italics between said words that run on in lowercase is the speaker's
        // emphasis the parser took for a direction: drawn as said, in italic.
        if (isSpeech) {
            val stressed = HashSet<Int>()
            parts!!.forEachIndexed { i, p ->
                val prev = parts.getOrNull(i - 1)
                val next = parts.getOrNull(i + 1)
                if (p !is LinePart.Direction || prev !is LinePart.Say || next !is LinePart.Say) return@forEachIndexed
                val words = p.text.replace("_", "").trim().split(Regex("\\s+"))
                val first = next.text.firstOrNull { !isSpace(it) }
                val lower = first != null && first.isLowerCase()
                if (words.size <= 3 && lower && !EMPHASIS_END.containsMatchIn(prev.text)) stressed += i
            }
            for (r in runs) if (r.piece in stressed) {
                r.said = true
                r.kind = ScriptReading.RunKind.Em
            }
        }
        // A direction printed wholly in italic marks ("[_Exeunt._]") is italic, not turned roman.
        val speechKind = line.kind == ScriptLine.Kind.Speech
        val byPiece = LinkedHashMap<Int, MutableList<PageRun>>()
        for (r in runs) if (!r.said) byPiece.getOrPut(r.piece) { ArrayList() } += r
        for (rs in byPiece.values) {
            val lettered = rs.filter { hasLetter(it.text) }
            val turned = if (speechKind) ScriptReading.RunKind.Plain else ScriptReading.RunKind.Em
            if (lettered.isNotEmpty() && lettered.all { it.kind == turned }) {
                for (r in rs) r.kind = if (speechKind) ScriptReading.RunKind.Aside else ScriptReading.RunKind.Plain
            }
        }

        if (!isSpeech) {
            val out = runs.map { it.copy(text = flatten(it.text)) }.toMutableList()
            val src = line.source.orEmpty().replace("_", "")
            val opens = Regex("^\\s*[\\[(]").containsMatchIn(src)
            val closes = Regex("[\\])]\\s*$").containsMatchIn(src)
            val bracketed = opens && (closes || !Regex("[\\])]").containsMatchIn(src))
            if (out.isNotEmpty() && bracketed) {
                val first = out.first()
                val m = OPEN_BRACKET.find(first.text)
                if (m != null) {
                    first.text = first.text.substring(m.value.length)
                    first.at += m.value.length
                }
                val last = out.last()
                if (closes) last.text = last.text.replace(CLOSE_BRACKET, "")
            }
            val cue = line.kind != ScriptLine.Kind.Direction
            return PageLine(rows = listOf(PageRow(cue, false, out.filter { it.text.isNotEmpty() }.toMutableList())))
        }

        val ps = parts!!
        fun isCue(i: Int): Boolean {
            val p = ps.getOrNull(i) ?: return false
            return p is LinePart.Sound || (p is LinePart.Direction && isCueWords(p.text))
        }
        val names = roles.filter { it.length >= 2 }.sortedByDescending { it.length }
        /** The role a second speaker's name at `k + 1` of [text] is, when what follows reads as its label. */
        fun runIn(text: String, k: Int): String? {
            for (n in names) {
                if (!text.startsWith(n, k + 1)) continue
                val rest = text.substring(k + 1 + n.length)
                if (rest.isBlank() || (rest.length >= 2 && (rest[0] == '.' || rest[0] == ':') && isSpace(rest[1]))) return n
            }
            return null
        }
        fun newlines(t: String): List<Int> = t.indices.filter { t[it] == '\n' }
        // A run-in speaker's break is not a verse break.
        val said = ps.filterIsInstance<LinePart.Say>().map { p ->
            var t = p.text
            for (k in newlines(p.text)) if (runIn(t, k) != null) t = t.substring(0, k) + " " + t.substring(k + 1)
            t
        }
        val verse = isVerse(said)

        val speeches = ArrayList<PageSpeech>()
        var sp: PageSpeech? = null
        var row: PageRow? = null
        var rowKey: String? = null
        var label = false

        fun start(role: String, name: PageRun?) {
            sp = PageSpeech(role, name).also { speeches += it }
            row = null
            rowKey = null
        }
        fun newRow(key: String?): PageRow {
            val r = PageRow(key != null, false)
            sp!!.rows += r
            row = r
            rowKey = key
            return r
        }
        fun rowNow(key: String?): PageRow {
            val r = row
            return if (r != null && rowKey == key) r else newRow(key)
        }
        fun push(r: PageRun, text: String, at: Int) {
            if (text.isEmpty()) return
            rowNow(null).runs += r.copy(text = text, at = at)
        }
        fun emit(r: PageRun, text: String, start: Int) {
            var at = start
            if (!verse) {
                push(r, text.replace('\n', ' '), at)
                return
            }
            text.split('\n').forEachIndexed { i, raw ->
                var seg = raw
                if (i > 0) newRow(null)
                if (i > 0 || row == null || row!!.runs.isEmpty()) {
                    val lead = leadingSpace(seg)
                    if (i > 0 && lead >= 2) rowNow(null).indent = true
                    seg = seg.substring(lead)
                    at += lead
                }
                push(r, seg, at)
                at += seg.length + 1
            }
        }

        start(line.role.orEmpty(), null)
        for (r in runs) {
            if (isCue(r.piece)) {
                rowNow("p${r.piece}").runs += r.copy(text = flatten(r.text))
                continue
            }
            if (row?.cue == true) row = null
            if (!r.said) {
                push(r, flatten(r.text), r.at)
                continue
            }
            var text = r.text
            var at = r.at
            if (label) {
                var n = leadingSpace(text)
                if (n < text.length && (text[n] == '.' || text[n] == ':')) n++
                n += leadingSpace(text.substring(n))
                text = text.substring(n)
                at += n
                if (text.isEmpty()) continue
                label = false
            }
            // A second speaker run in: "\nNAME" at the end of the words, or "\nNAME. " before more.
            while (true) {
                var hit: Pair<Int, String>? = null
                for (k in newlines(text)) {
                    val n = runIn(text, k)
                    if (n != null) {
                        hit = k to n
                        break
                    }
                }
                if (hit == null) break
                val (k, n) = hit
                emit(r, text.substring(0, k), at)
                start(n, PageRun(ScriptReading.RunKind.Say, n, at + k + 1, r.piece, false))
                val after = text.substring(k + 1 + n.length)
                var m = if (after.isNotEmpty() && (after[0] == '.' || after[0] == ':')) 1 else 0
                m += leadingSpace(after.substring(m))
                at += k + 1 + n.length + m
                text = after.substring(m)
                if (text.isEmpty()) {
                    label = true
                    break
                }
            }
            if (text.isNotEmpty()) emit(r, text, at)
        }
        for (s in speeches) s.rows.removeAll { it.runs.isEmpty() }
        return PageLine(verse = verse, speeches = speeches)
    }
}
