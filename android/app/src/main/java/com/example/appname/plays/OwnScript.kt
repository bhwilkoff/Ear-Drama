package com.example.appname.plays

import java.security.MessageDigest
import java.text.Normalizer

// Own scripts (Decision 088.3; docs/research/design/R4-record-anything.md, R4-core-port-brief.md): a port of js/own-core.js,
// function for function and rule for rule, held to catalog/tests/golden/own_script_{parse,ops}.json and ear_cast_lines.json
// (OwnScriptTest). Pure: no Android import, no storage, no clock. Offsets are UTF-16 units of a line's text; a name's cap
// while reading is 30 code points; bytes are UTF-8. No regular expression decides a rule: a row is read by the character,
// and the only classes are single code points (Character.getType), so no text can make a pattern backtrack and no ICU
// version can move a rule. Never edit a golden by hand: change the rule in js/own-core.js, all three ports and the golden
// in one change set.

/** One line of a doc being corrected. `k` is its key while it is edited, `id` null until [OwnScript.done]. */
data class OwnLine(
    val k: Int = 0,
    val id: String? = null,
    val kind: String,
    val role: String? = null,
    val text: String,
    val label: String? = null,
    val at: Pair<Long, Long>? = null,
    val mark: OwnWho? = null,
)

/** Who a line is cast to by ear: a part, or left out. */
sealed class OwnWho {
    data class Role(val name: String) : OwnWho()
    data object Out : OwnWho()
}

/** A doc is plain data, never changed in place: [OwnScript.apply] returns a new one. */
data class OwnDoc(
    val lines: List<OwnLine>,
    val nextKey: Int,
    val letters: Map<String, Int> = emptyMap(),
    val heard: List<Int> = emptyList(),
    val undo: List<List<OwnLine>> = emptyList(),
)

/** A speech's printed pieces: words to say, or a direction. */
sealed class OwnPiece {
    abstract val text: String
    data class Say(override val text: String) : OwnPiece()
    data class Direction(override val text: String) : OwnPiece()
}

sealed class OwnTarget {
    data class Role(val role: String) : OwnTarget()
    data class KindOf(val kind: String) : OwnTarget()
}

/** One change on the parts page; see [OwnScript.apply]. */
data class OwnOp(
    val op: String,
    val line: Int? = null,
    val at: Int? = null,
    val text: String = "",
    val to: OwnTarget? = null,
    val after: Int? = null,
    val kind: String = "",
    val role: String = "",
    val part: String = "",
    val rename: String = "",
)

data class OwnEnv(val takes: Set<String> = emptySet(), val shared: Boolean = false)
data class OwnResult(val doc: OwnDoc, val refusal: String?)
data class OwnParsed(val text: String, val lines: List<OwnLine>, val parts: List<Pair<String, Int>>)
data class OwnLabel(val form: String, val name: String, val key: String, val label: String, val text: String, val bare: Boolean)
data class OwnCue(val text: String, val at: Pair<Long, Long>?)
data class OwnMeta(val id: String, val title: String, val episodeId: String? = null, val episodeUrl: String? = null)

object OwnScript {
    const val MAX_BYTES = 400000
    const val MAX_LINES = 6000
    const val MAX_PART_NAME = 40
    const val MAX_TITLE = 300
    private const val MAX_NAME_POINTS = 30

    private val OWN_ID = Regex("own-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")

    /** Whether [id] is a person's own script's. No catalog id begins with `own-`. */
    fun isOwnId(id: String): Boolean = OWN_ID.matches(id)
    private val LINE_ID = Regex("L[0-9]{4}[a-z]*")

    // ---- Characters, one code point at a time ----

    private const val UPPER = 1
    private const val LOWER = 2
    private const val LETTER = 4
    private const val MARK = 8
    private const val DIGIT = 16

    private fun classOf(cp: Int): Int = when (Character.getType(cp).toByte()) {
        Character.UPPERCASE_LETTER, Character.TITLECASE_LETTER -> UPPER or LETTER
        Character.LOWERCASE_LETTER -> LOWER or LETTER
        Character.MODIFIER_LETTER, Character.OTHER_LETTER -> LETTER
        Character.NON_SPACING_MARK, Character.COMBINING_SPACING_MARK, Character.ENCLOSING_MARK -> MARK
        Character.DECIMAL_DIGIT_NUMBER -> DIGIT
        else -> 0
    }

    private fun isC(cp: Int, mask: Int): Boolean = cp >= 0 && (classOf(cp) and mask) != 0
    private fun width(cp: Int): Int = if (cp > 0xffff) 2 else 1
    private const val SPACE = 32
    private const val TAB = 9
    private fun isGap(u: Int) = u == SPACE || u == TAB
    private fun isBlankUnit(u: Int) = u == SPACE || u == TAB || u == 10

    /** JavaScript's slice for non-negative bounds: clamped, empty when backwards. */
    private fun String.sl(a: Int, b: Int = length): String {
        val x = a.coerceIn(0, length)
        val y = b.coerceIn(0, length)
        return if (x >= y) "" else substring(x, y)
    }

    private fun cpAt(s: String, i: Int): Int = if (i < 0 || i >= s.length) -1 else s.codePointAt(i)
    private fun at(s: String, p: Int, c: Char): Boolean = p >= 0 && p < s.length && s[p] == c
    private fun cps(s: String): IntArray = s.codePoints().toArray()

    fun trim(s: String): String {
        var a = 0
        var b = s.length
        while (a < b && isBlankUnit(s[a].code)) a += 1
        while (b > a && isBlankUnit(s[b - 1].code)) b -= 1
        return s.substring(a, b)
    }

    private fun skipGap(s: String, p0: Int): Int {
        var p = p0
        while (p < s.length && isGap(s[p].code)) p += 1
        return p
    }

    /** Words between runs of spaces, tabs and line breaks. */
    fun wordsOf(s: String): List<String> {
        val out = ArrayList<String>()
        var from = -1
        for (i in 0..s.length) {
            val gap = i == s.length || isBlankUnit(s[i].code)
            if (!gap && from < 0) from = i
            else if (gap && from >= 0) { out.add(s.substring(from, i)); from = -1 }
        }
        return out
    }

    fun utf8Length(s: String): Int {
        var n = 0
        var i = 0
        while (i < s.length) {
            val u = s[i].code
            if (u < 0x80) n += 1
            else if (u < 0x800) n += 2
            else if (u in 0xd800..0xdbff && i + 1 < s.length) { n += 4; i += 1 } else n += 3
            i += 1
        }
        return n
    }

    // ---- Normalizing a text ----

    private fun dropped(u: Int) = u < 9 || u == 14 || u == 15 || (u in 16..31) || (u in 0x7f..0x9f && u != 0x85) ||
        u == 0xad || u == 0x200b || u == 0x200e || u == 0x200f || u == 0x2060 || u == 0xfeff ||
        (u in 0x202a..0x202e) || (u in 0x2066..0x2069)

    private fun newline(u: Int) = u == 10 || u == 11 || u == 12 || u == 13 || u == 0x85 || u == 0x2028 || u == 0x2029
    private fun wideSpace(u: Int) = u == 0xa0 || u == 0x1680 || (u in 0x2000..0x200a) || u == 0x202f || u == 0x205f || u == 0x3000

    /**
     * The text every rule reads and every line slices: line ends one `\n`, every other space one U+0020 (a tab stays),
     * unseen characters dropped, a lone surrogate U+FFFD, NFC, then the pairs that mark italics and bold dropped.
     */
    fun normalize(raw: String?): String {
        val t = raw ?: ""
        val out = StringBuilder(t.length)
        var from = 0
        fun put(i: Int, s: String) { out.append(t, from, i).append(s); from = i + 1 }
        var i = 0
        while (i < t.length) {
            val u = t[i].code
            if (u in 32 until 0x7f) { i += 1; continue }
            if (u in 0xd800..0xdbff) {
                val v = if (i + 1 < t.length) t[i + 1].code else 0
                if (v in 0xdc00..0xdfff) i += 1 else put(i, "�")
            } else if (u in 0xdc00..0xdfff) put(i, "�")
            else if (newline(u)) put(i, if (u == 13 && i + 1 < t.length && t[i + 1].code == 10) "" else "\n")
            else if (wideSpace(u)) put(i, " ")
            else if (dropped(u)) put(i, "")
            i += 1
        }
        out.append(t, from, t.length)
        return unmark(Normalizer.normalize(out, Normalizer.Form.NFC))
    }

    private fun asciiWord(u: Int) = (u in 48..57) || (u in 65..90) || (u in 97..122)

    /** Drops one `_` that does not join two ASCII letters or digits, and `**`. A run of any other length is the writer's own. */
    private fun unmark(t: String): String {
        val out = StringBuilder(t.length)
        var from = 0
        var i = 0
        while (i < t.length) {
            val u = t[i].code
            if (u != 95 && u != 42) { i += 1; continue }
            var j = i + 1
            while (j < t.length && t[j].code == u) j += 1
            val n = j - i
            val inner = i > 0 && j < t.length && asciiWord(t[i - 1].code) && asciiWord(t[j].code)
            if ((u == 95 && n == 1 && !inner) || (u == 42 && n == 2)) { out.append(t, from, i); from = j }
            i = j
        }
        out.append(t, from, t.length)
        return out.toString()
    }

    // ---- Names ----

    private fun set(words: String): Set<String> = words.split(' ').toHashSet()
    private val NOT_NAME = set(
        "ACT SCENE SCENES NOTE NOTES CAST DATE TITLE BY AUTHOR WRITTEN SETTING TIME PLACE CHARACTERS COPYRIGHT END " +
            "FINIS DRAMATIS PERSONS SYNOPSIS COSTUMES PROPERTIES SCENERY CURTAIN FADE CUT TRANSCRIBED SOURCE SERIES PROGRAM PRODUCTION " +
            "HTTP HTTPS AT FOOTNOTE FOOTNOTES APPENDIX INDEX CONTENTS CHAPTER ILLUSTRATION TABLEAU ENTER EXIT EXEUNT",
    )
    private val COMMON = set(
        "NO YES OH AH O WELL AY AYE NAY YEA INDEED TRUE NEVER GOOD HUSH COME STOP WHY WHAT NOW SO THEN THERE HERE THIS " +
            "THAT HOW WHERE WHEN WHO AGAIN NOTHING EVERYTHING PERHAPS EXACTLY CERTAINLY SURELY THANKS PLEASE SILENCE PAUSE",
    )
    private val COMMON_MIXED = set("I IT HE SHE WE YOU THEY SIR MADAM PEACE MANET FLOURISH SENNET ALARUM ALARUMS")
    private val TITLES = set("MR MRS MS DR ST LT CAPT COL GEN SGT REV PROF MME MLLE M MM MESSRS")
    private val SMALL = set("of the and in with on at to a an de la le von van der du del")
    private val WORD_NUMBERS = set(
        "ONE TWO THREE FOUR FIVE SIX SEVEN EIGHT NINE TEN FIRST SECOND THIRD FOURTH FIFTH SIXTH SEVENTH EIGHTH " +
            "NINTH TENTH LAST PRIMUS SECUNDUS TERTIUS QUARTUS QUINTUS PRIMA SECUNDA TERTIA QUARTA QUINTA SEXTA SEPTIMA OCTAVA NONA DECIMA",
    )
    private val ROMAN: Set<String> = buildSet {
        for (tens in listOf("", "X", "XX", "XXX")) {
            for (ones in listOf("", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX")) if ((tens + ones).isNotEmpty()) add(tens + ones)
        }
    }

    private fun isRoman(w: String) = w in ROMAN

    /** ASCII letters to capitals, every other character as it is, so offsets never move. */
    private fun asciiUpper(s: String): String {
        val c = s.toCharArray()
        for (i in c.indices) if (c[i] in 'a'..'z') c[i] = c[i] - 32
        return String(c)
    }

    /** A part's name as stored: one space between words, straight apostrophes, capitals, no label punctuation at its ends. */
    fun partName(raw: String): String {
        val s0 = wordsOf(raw).joinToString(" ").replace('‘', '\'').replace('’', '\'')
        fun edge(c: Char) = c == ' ' || c == '.' || c == ':' || c == '@' || c == '_' || c == '^' || c == '：'
        var a = 0
        var b = s0.length
        while (a < b && edge(s0[a])) a += 1
        while (b > a && edge(s0[b - 1])) b -= 1
        return s0.substring(a, b).uppercase(java.util.Locale.ROOT)
    }

    /** null when a part may be called this (already through [partName]), or why not: empty, too_long, bad_name. */
    fun partNameRefusal(name: String?): String? {
        if (name.isNullOrEmpty()) return "empty"
        if (name.length > MAX_PART_NAME) return "too_long"
        for (ch in name) {
            val u = ch.code
            if (u < 32 || u == 127 || (u in 0x200b..0x200f) || (u in 0x2028..0x202e)) return "bad_name"
        }
        return null
    }

    private fun isCaps(name: String): Boolean {
        var upper = false
        for (w in wordsOf(name)) {
            var s = w
            for (p in listOf("Mac", "Mc")) {
                if (s.startsWith(p) && s.length > p.length && isC(s.codePointAt(p.length), UPPER)) { s = s.substring(p.length); break }
            }
            for (cp in cps(s)) {
                if (isC(cp, LOWER)) return false
                if (isC(cp, UPPER)) upper = true
            }
        }
        return upper
    }

    private fun isTitled(name: String): Boolean {
        val words = wordsOf(name)
        return words.isNotEmpty() && words.withIndex().all { (i, w) ->
            val cp = w.codePointAt(0)
            if (isC(cp, UPPER) || (isC(cp, LETTER) && !isC(cp, LOWER))) true
            else if (i == 0) words.size > 1 && isC(cp, DIGIT)
            else isC(cp, DIGIT) || w[0] == '#' || w[0] == '&' || w in SMALL
        }
    }

    private fun hasLower(s: String): Boolean {
        for (cp in cps(s)) if (isC(cp, LOWER)) return true
        return false
    }

    private fun nameOK(name: String, maxWords: Int = 4): Boolean {
        val key = partName(name)
        val words = wordsOf(key)
        if (words.isEmpty() || words.size > maxWords || key.length > MAX_PART_NAME) return false
        for (i in 0 until words.size - 1) {
            if (words[i].endsWith(".") && words[i].dropLast(1) !in TITLES && words[i].codePointCount(0, words[i].length) != 2 &&
                words[i + 1] != "OF" && !isC(words[i + 1].codePointAt(0), DIGIT)
            ) return false
        }
        var head = words[0]
        while (head.endsWith(".") || head.endsWith("'")) head = head.dropLast(1)
        if (head in NOT_NAME || key == "THE END") return false
        if (words[0] == "PAGE" && words.size > 1 && isC(words[1].codePointAt(0), DIGIT)) return false
        for (cp in cps(key)) if (isC(cp, LETTER)) return true
        return false
    }

    /** The end (exclusive) of the bracket opening at `p`, counting nested ones of its kind, or -1. */
    private fun bracketEnd(s: String, p: Int): Int {
        val open = s[p]
        val close = if (open == '(') ')' else ']'
        var depth = 0
        for (i in p until s.length) {
            val c = s[i]
            if (c == open) depth += 1
            else if (c == close) { depth -= 1; if (depth == 0) return i + 1 }
        }
        return -1
    }

    private fun opensBracket(s: String, p: Int) = p < s.length && (s[p] == '(' || s[p] == '[')

    private val FORMS = listOf("colon", "dot", "gap", "alone", "mixed")

    private fun nameChar(cp: Int) = isC(cp, LETTER or MARK or DIGIT) || cp == 46 || cp == 39 || cp == 0x2019 || cp == 0x2018 ||
        cp == 38 || cp == 35 || cp == 45 || cp == 47 || cp == 32 || cp == 0xfffd

    private fun skipDash(s: String, p0: Int): Int {
        var p = p0
        if (s.startsWith("--", p)) { while (at(s, p, '-')) p += 1; return p }
        return if (at(s, p, '—') || at(s, p, '–')) p + 1 else p
    }

    /**
     * The label a row opens with, read every way a label is printed, best first. `s` is trimmed.
     */
    fun labels(s: String): List<OwnLabel> {
        var i = 0
        if (at(s, 0, '@')) i = 1
        val first = cpAt(s, i)
        if (first < 0 || !(isC(first, LETTER or DIGIT) && !isC(first, LOWER))) return emptyList()
        val found = HashMap<String, OwnLabel>()
        val held = HashMap<String, OwnLabel>()
        var points = 0
        var e = i
        while (e < s.length && points < MAX_NAME_POINTS) {
            val cp = s.codePointAt(e)
            if (!nameChar(cp)) break
            e += width(cp)
            points += 1
            if (cp == SPACE) continue
            ends(s, i, e, found, held)
        }
        val out = ArrayList<OwnLabel>()
        for (store in listOf(found, held)) for (form in FORMS) store[form]?.let { out.add(it) }
        return out
    }

    private fun couldEnd(s: String, e: Int): Boolean {
        val r = skipGap(s, e)
        if (r >= s.length) return true
        val c = s[r]
        return c == ':' || c == '：' || c == '(' || c == '[' || c == '^' || at(s, e, '.') || at(s, e, ',') ||
            (c == '.' && r > e) || r - e >= 3 || s.sl(e, r).contains('\t')
    }

    private fun ends(s: String, i: Int, e: Int, found: HashMap<String, OwnLabel>, held: HashMap<String, OwnLabel>) {
        if (!couldEnd(s, e)) return
        val name = s.sl(i, e)
        if (!nameOK(name)) return
        val key = partName(name)
        val words = wordsOf(key)
        val caps = isCaps(name)
        val titled = !caps && isTitled(name)
        val numeral = isRoman(key)
        val last = words[words.size - 1]
        val maybe = last in TITLES || last.codePointCount(0, last.length) == 1
        var d = ""
        var p = e
        val q = skipGap(s, if (at(s, e, ',')) e + 1 else e)
        if (opensBracket(s, q)) {
            val end = bracketEnd(s, q)
            if (end > 0) { d = s.sl(q, end); p = end }
        }
        fun put(store: HashMap<String, OwnLabel>, form: String, atIdx: Int, rest: String) {
            if (store === found && found.containsKey(form)) return
            val said = trim(rest)
            store[form] = OwnLabel(
                form, name, key, if (d.isNotEmpty()) name else trim(s.sl(0, atIdx)),
                if (d.isNotEmpty()) (if (said.isNotEmpty()) "$d $said" else d) else said, said.isEmpty(),
            )
        }
        val r = skipGap(s, p)

        if (at(s, r, ':') || at(s, r, '：')) {
            val rest = s.sl(r + 1)
            val ratio = r == e && isC(cpAt(s, e - 1), DIGIT) && isC(cpAt(rest, 0), DIGIT)
            if (!rest.startsWith("//") && !ratio) put(found, "colon", r + 1, rest)
        }
        if (numeral || key in COMMON) return

        if (caps || (titled && words.size <= 3 && key !in COMMON_MIXED)) {
            val form = if (caps) "dot" else "mixed"
            if (at(s, p, '.')) {
                val g = skipGap(s, p + 1)
                val t = skipDash(s, g)
                if (t < s.length && (t > p + 1 || opensBracket(s, t))) {
                    if (!maybe || d.isNotEmpty()) put(found, form, p + 1, s.sl(t))
                    else if (caps || last !in TITLES) put(held, form, p + 1, s.sl(t))
                }
            } else if (d.isNotEmpty() && caps) {
                val t = skipDash(s, r)
                if (t < s.length && !at(s, t, ':') && !at(s, t, '：') && !at(s, t, '.')) put(found, form, p, s.sl(t))
            }
        }
        if (r > p && r < s.length && !at(s, r, ':') && !at(s, r, '：')) {
            val gap = s.sl(p, r)
            if ((caps || titled) && gap.contains('\t')) put(found, "gap", r, s.sl(r))
            else if (caps && gap.length >= 3) put(found, "gap", r, s.sl(r))
        }
        if (caps) {
            var z = r
            if (at(s, z, '.') || at(s, z, ':') || at(s, z, '：') || at(s, z, '^')) z = skipGap(s, z + 1)
            if (z == s.length) put(found, "alone", z, "")
        }
    }

    // ---- Rows ----

    private val CUE_SOUND = listOf("SOUND EFFECTS", "SOUND EFFECT", "SOUND", "SFX")
    private val CUE_MUSIC = listOf("MUSIC", "THEME", "ORCHESTRA")
    private const val OPENERS = "([*#\"“>- \t"

    private fun skipOpeners(s: String): Int {
        var p = 0
        while (p < s.length && OPENERS.indexOf(s[p]) >= 0) p += 1
        return p
    }

    /** "sound", "music" or null: rule 1. */
    fun cueKind(s: String): String? {
        val p = skipOpeners(s)
        val up = asciiUpper(s)
        for ((kind, words) in listOf("sound" to CUE_SOUND, "music" to CUE_MUSIC)) {
            for (w in words) {
                if (!up.startsWith(w, p)) continue
                val caps = s.startsWith(w, p)
                val r = skipGap(s, p + w.length)
                val none = r >= s.length
                val c = if (none) ' ' else s[r]
                if (!none && (c == ':' || c == '：')) return kind
                if (caps && (none || c == '.' || c == '(' || c == '[' || c == '-' || c == '—' || c == '–')) return kind
                if (caps && !none && (c == ')' || c == ']') && p > 0) return kind
                if (caps && r > p + w.length && !s.contains(':') && isCaps(s) && wordsOf(s).size >= 3) return kind
            }
        }
        return null
    }

    private val HEADS = listOf(
        "ACT", "SCENE", "PROLOGUE", "EPILOGUE", "INDUCTION", "CURTAIN", "TABLEAU", "THE END", "END OF", "FINIS", "FADE IN", "FADE OUT",
        "FADE TO", "CUT TO", "INT.", "EXT.", "INT/EXT", "DISSOLVE TO",
    )
    private val HEADS_NUMBERED = listOf("ACT", "SCENE", "ACTUS", "SCENA", "SCOENA")

    private fun wordEnds(s: String, p: Int) = p >= s.length || !(isC(s.codePointAt(p), LETTER or MARK or DIGIT) || s[p] == '\'' || s[p] == '’')

    /** Rule 2: a heading of the play or its staging. */
    fun isHeading(s: String): Boolean {
        val p = skipOpeners(s)
        for (h in HEADS) if (s.startsWith(h, p) && (h.endsWith(".") || wordEnds(s, p + h.length))) return true
        val up = asciiUpper(s)
        if (up.startsWith("END OF ", p)) for (w in wordsOf(up)) if (w.startsWith("ACT") || w.startsWith("SCENE") || w.startsWith("PLAY")) return true
        for (h in HEADS_NUMBERED) {
            if (!up.startsWith(h, p) || !wordEnds(s, p + h.length)) continue
            var q = p + h.length
            if (at(s, q, '.')) q += 1
            val a = skipGap(s, q)
            if (a == q) continue
            var b = a
            while (b < s.length && isC(s.codePointAt(b), LETTER or DIGIT)) b += width(s.codePointAt(b))
            val n = up.sl(a, b)
            if (n.isNotEmpty() && (isRoman(n) || n in WORD_NUMBERS || cps(n).all { it in 48..57 })) return true
        }
        return false
    }

    /** A paragraph that opens with a printed entrance or exit. */
    fun isEntrance(s: String): Boolean {
        for (w in listOf("Enter", "Re-enter", "Reenter")) if (s.startsWith("$w ") && isC(cpAt(s, w.length + 1), LETTER)) return true
        for (w in listOf("Exit", "Exeunt", "Manet", "Manent")) if (s.startsWith(w) && (s.length == w.length || s[w.length] == '.' || s[w.length] == ' ')) return true
        return false
    }

    private fun isExit(s: String) = s == "Exit" || s == "Exit." || s == "Exeunt" || s == "Exeunt."

    /** The last row of a bracketed direction that opens row `i`'s paragraph (-1 if it does not close with the row), and whether it closes. */
    private fun bracketRows(rows: List<String>, i: Int): Pair<Int, Boolean> {
        val open = rows[i][0]
        val close = if (open == '(') ')' else ']'
        var depth = 0
        var j = i
        while (j < rows.size && rows[j].isNotEmpty()) {
            val s = rows[j]
            for (p in s.indices) {
                val c = s[p]
                if (c == open) depth += 1
                else if (c == close) {
                    depth -= 1
                    if (depth == 0) {
                        val whole = p == s.length - 1 || (p == s.length - 2 && s[p + 1] == '.')
                        return (if (whole) j else -1) to true
                    }
                }
            }
            j += 1
        }
        return -1 to false
    }

    private class Building(val kind: String, val role: String?, t: String, val label: String?) {
        val text = StringBuilder(t)
    }

    /* ---- A Project Gutenberg text's wrapping ---- */

    private val WRAP_ENDS = listOf(
        "*** END OF THE PROJECT GUTENBERG EBOOK", "*** END OF THIS PROJECT GUTENBERG EBOOK", "***END OF THE PROJECT GUTENBERG EBOOK",
        "***END OF THIS PROJECT GUTENBERG EBOOK", "END OF PROJECT GUTENBERG", "END OF THE PROJECT GUTENBERG",
    )
    private val WRAP_STARTS = listOf(
        "*** START OF THE PROJECT GUTENBERG EBOOK", "*** START OF THIS PROJECT GUTENBERG EBOOK", "***START OF THE PROJECT GUTENBERG EBOOK",
        "***START OF THIS PROJECT GUTENBERG EBOOK",
    )
    /** The older license, before its text or after it; normalizing has taken the `**` between its words. */
    private const val PRINT_START = "***STARTTHE SMALL PRINT!"
    private val PRINT_ENDS = listOf("*END*THE SMALL PRINT!", "*END THE SMALL PRINT!")

    /** The text between a Project Gutenberg file's own marker rows, and nothing else cut; one with no marker, or with nothing between them, as it was. */
    fun unwrap(text: String): String {
        if (!text.contains("PROJECT GUTENBERG") && !text.contains("Project Gutenberg") && !text.contains("SMALL PRINT!")) return text
        val rows = text.split('\n')
        val trimmed = rows.map(::trim)
        val out = ArrayList<String>()
        val kept = ArrayList<String>()
        var off = false
        var started = false
        var cut = false
        var i = 0
        while (i < rows.size) {
            val t = trimmed[i]
            val c = t.firstOrNull()
            val m = if (c == '*' || c == 'E' || c == 'e') asciiUpper(t.take(80)) else ""
            if (WRAP_STARTS.any(m::startsWith)) {
                if (!t.endsWith("***")) {
                    var j = i + 1
                    while (j <= i + 3 && j < rows.size && trimmed[j].isNotEmpty() && !trimmed[j].endsWith("***")) j += 1
                    if (j <= i + 3 && j < rows.size && trimmed[j].isNotEmpty()) i = j
                }
                kept.clear()
                off = false
                started = true
                cut = true
            } else if (!off) {
                if (PRINT_ENDS.any(m::startsWith)) {
                    kept.clear()
                    started = true
                    cut = true
                } else if (WRAP_ENDS.any(m::startsWith) || (started && m.startsWith(PRINT_START))) {
                    out.addAll(kept)
                    kept.clear()
                    off = true
                    started = false
                    cut = true
                } else kept.add(rows[i])
            }
            i += 1
        }
        out.addAll(kept)
        val body = out.joinToString("\n")
        return if (cut && trim(body).isNotEmpty()) body else text
    }

    /** The ten rules (R4 section 2.2): the normalized text, unwrapped, lines as a doc holds them, and each part's count of lines. */
    fun parse(raw: String?): OwnParsed {
        val text = unwrap(normalize(raw))
        val rows = text.split('\n').map(::trim)
        val read = arrayOfNulls<List<OwnLabel>>(rows.size)
        val seen = HashMap<String, Int>()
        val starting = HashMap<String, Int>()
        val printed = mapOf("colon" to HashMap<String, Int>(), "dot" to HashMap<String, Int>(), "alone" to HashMap<String, Int>())
        fun add(m: HashMap<String, Int>, k: String) { m[k] = (m[k] ?: 0) + 1 }
        fun row(i: Int) = rows.getOrElse(i) { "" }
        fun opensParagraph(i: Int) = i == 0 || rows[i - 1].isEmpty()

        for (i in rows.indices) {
            val s = rows[i]
            if (s.isEmpty() || cueKind(s) != null || isHeading(s)) continue
            val ls = labels(s)
            read[i] = ls
            val m = ls.firstOrNull() ?: continue
            printed[m.form]?.let { add(it, m.key) }
            if (m.form == "mixed") add(starting, m.key)
            else if (m.form != "alone" || row(i + 1).isNotEmpty() || row(i + 2).isNotEmpty()) add(seen, m.key)
        }
        val established = HashMap<String, Boolean>()
        for ((form, counts) in printed) established[form] = counts.values.count { it >= 2 } >= 2
        fun afterLabel(i: Int) = i >= 1 && read[i - 1]?.firstOrNull()?.form == "colon"
        fun known(m: OwnLabel, i: Int): Boolean {
            val n = seen[m.key] ?: 0
            if (m.form == "mixed") return (n >= 2 && opensParagraph(i)) || (starting[m.key] ?: 0) >= 5
            if (n >= 2) return true
            if (established[m.form] != true) return false
            if (m.form == "dot") return opensParagraph(i) && hasLower(m.text)
            if (m.form == "alone") return opensParagraph(i) && row(i + 1).isNotEmpty() && hasLower(row(i + 1))
            if (isCaps(m.name)) return opensParagraph(i) || afterLabel(i) || cueKind(rows[i - 1]) != null
            return opensParagraph(i) && isTitled(m.name) && wordsOf(m.name).size <= 2
        }

        val out = ArrayList<Building>()
        var cur: Building? = null
        var blank = true
        var awaiting = false
        var resume: String? = null
        fun push(kind: String, role: String?, t: String, label: String? = null) {
            cur = Building(kind, role, t, label?.takeIf { it.isNotEmpty() }).also { out.add(it) }
            awaiting = false
            resume = null
        }
        fun more(s: String) { val t = cur!!.text; if (t.isNotEmpty()) t.append('\n'); t.append(s) }
        var i = 0
        while (i < rows.size) {
            val s = rows[i]
            if (s.isEmpty()) { blank = true; i += 1; continue }
            val cue = cueKind(s)
            if (cue != null) push(cue, null, s)
            else if (isHeading(s)) push("direction", null, s)
            else {
                val aw = awaiting
                val m = (read[i] ?: emptyList()).find { x -> known(x, i) && !(aw && !blank && !isCaps(x.name)) }
                if (m != null) {
                    push("speech", m.key, m.text, m.label)
                    awaiting = m.bare
                } else if (awaiting) {
                    more(s)
                    awaiting = opensBracket(s, 0) && bracketEnd(s, 0) == s.length
                } else if (blank && opensBracket(s, 0)) {
                    val (last, closes) = bracketRows(rows, i)
                    if (last >= 0) { push("direction", null, rows.subList(i, last + 1).joinToString("\n")); i = last }
                    else push(if (s[0] == '[' && !closes) "direction" else "open", null, s)
                } else if (blank && isEntrance(s)) push("direction", null, s)
                else if (!blank && cur != null && cur.kind == "speech" && isExit(s)) {
                    val role = cur.role
                    push("direction", null, s)
                    resume = role
                } else if (!blank && resume != null) push("speech", resume, s)
                else if (!blank && cur != null) more(s)
                else push("open", null, s)
            }
            blank = false
            i += 1
        }
        val lines = out.map { l ->
            if (l.kind == "speech" && l.text.isEmpty()) OwnLine(kind = "open", text = l.label ?: "")
            else OwnLine(kind = l.kind, role = l.role, text = l.text.toString(), label = l.label)
        }
        return OwnParsed(text, lines, partsOf(lines))
    }

    /** Each part's name and its count of lines, in order of first appearance. */
    fun partsOf(lines: List<OwnLine>): List<Pair<String, Int>> {
        val m = LinkedHashMap<String, Int>()
        for (l in lines) if (l.kind == "speech") m[l.role!!] = (m[l.role] ?: 0) + 1
        return m.map { it.key to it.value }
    }

    // ---- A line's printed pieces ----

    /** Every bracket's partner: opening index to the index after the closing one, `( )` and `[ ]` each nested on their own, one pass. */
    private fun matched(s: String): HashMap<Int, Int> {
        val out = HashMap<Int, Int>()
        val round = ArrayList<Int>()
        val square = ArrayList<Int>()
        for (i in s.indices) {
            val c = s[i]
            if (c == '(') round.add(i)
            else if (c == '[') square.add(i)
            else if (c == ')' && round.isNotEmpty()) out[round.removeAt(round.size - 1)] = i + 1
            else if (c == ']' && square.isNotEmpty()) out[square.removeAt(square.size - 1)] = i + 1
        }
        return out
    }

    private fun spans(s: String): List<IntArray> {
        val m = matched(s)
        val out = ArrayList<IntArray>()
        if (m.isEmpty()) return out
        var i = 0
        while (i < s.length) {
            val end = m[i]
            if (end == null) { i += 1; continue }
            val u = if (i > 0) s[i - 1].code else 0
            if (asciiWord(u) || (u > 0x7f && isC(codePointBefore(s, i), LETTER or MARK or DIGIT))) { i += 1; continue }
            if (trim(s.sl(i + 1, end - 1)).isEmpty()) { i += 1; continue }
            out.add(intArrayOf(i, end))
            i = end
        }
        return out
    }

    /** A speech's text as the castable shape's parts, each a slice of it. */
    fun pieces(text: String): List<OwnPiece> {
        val out = ArrayList<OwnPiece>()
        var from = 0
        fun say(t: String) { val w = trim(t); if (w.isNotEmpty()) out.add(OwnPiece.Say(w)) }
        for ((a, b) in spans(text).map { it[0] to it[1] }) {
            say(text.sl(from, a))
            out.add(OwnPiece.Direction(trim(text.sl(a + 1, b - 1))))
            from = b
        }
        say(text.sl(from))
        return out
    }

    private fun evenRound(s: String): Boolean {
        var depth = 0
        for (c in s) {
            if (c == '(') depth += 1
            else if (c == ')') { depth -= 1; if (depth < 0) return false }
        }
        return depth == 0
    }

    /** The text a speech's parts read from again. */
    fun textOf(parts: List<OwnPiece>): String = parts.joinToString(" ") { p ->
        when (p) {
            is OwnPiece.Say -> p.text
            is OwnPiece.Direction -> if (evenRound(p.text)) "(${p.text})" else "[${p.text}]"
        }
    }

    // ---- Cutting a line ----

    private fun codePointBefore(s: String, i: Int): Int {
        if (i <= 0) return -1
        val u = s[i - 1].code
        if (u in 0xdc00..0xdfff && i >= 2) return s.codePointAt(i - 2)
        return u
    }

    private fun regional(cp: Int) = cp in 0x1f1e6..0x1f1ff

    private fun insideCharacter(s: String, at: Int): Boolean {
        val u = s[at].code
        if (u in 0xdc00..0xdfff) { val b = s[at - 1].code; if (b in 0xd800..0xdbff) return true }
        val cp = s.codePointAt(at)
        if (isC(cp, MARK) || cp == 0x200d || cp in 0x1f3fb..0x1f3ff) return true
        val before = codePointBefore(s, at)
        if (before == 0x200d) return true
        if (regional(cp) && regional(before)) {
            var n = 0
            var i = at
            while (i >= 2 && regional(codePointBefore(s, i))) { n += 1; i -= 2 }
            return n % 2 == 1
        }
        return false
    }

    /** Where a cut asked for at `at` goes: off a character it would break, out of a direction's brackets. -1 when one side would have nothing. */
    fun cutAt(text: String, at: Int?): Int {
        if (at == null || at <= 0 || at >= text.length) return -1
        var p: Int = at
        while (p > 0 && insideCharacter(text, p)) p -= 1
        for (span in spans(text)) {
            val a = span[0]
            val b = span[1]
            if (p > a && p < b) p = if (trim(text.sl(0, a)).isNotEmpty()) a else b
        }
        return if (trim(text.sl(0, p)).isNotEmpty() && trim(text.sl(p)).isNotEmpty()) p else -1
    }

    // ---- Ids ----

    private fun pad(n: Int) = n.toString().padStart(4, '0')

    private fun letters(n0: Int): String {
        var n = n0
        val out = StringBuilder()
        while (n > 0) { val r = (n - 1) % 26; out.insert(0, ('a' + r)); n = (n - 1 - r) / 26 }
        return out.toString()
    }

    private fun lettersValue(w: String): Int {
        var n = 0
        for (c in w) n = n * 26 + (c.code - 96)
        return n
    }

    private fun baseOf(id: String?) = if (id != null) id.sl(0, 5) else "L0000"

    // ---- A script being corrected ----

    /** A doc from parse()'s lines, or fromCues()'s. */
    fun newDoc(lines: List<OwnLine>): OwnDoc = OwnDoc(
        lines.mapIndexed { i, l -> OwnLine(i + 1, null, l.kind, l.role?.takeIf { it.isNotEmpty() }, l.text, l.label?.takeIf { it.isNotEmpty() }, l.at) },
        lines.size + 1,
    )

    private fun refuse(doc: OwnDoc, why: String) = OwnResult(doc, why)
    private fun accept(doc: OwnDoc, lines: List<OwnLine>, nextKey: Int = doc.nextKey, letters: Map<String, Int> = doc.letters, heard: List<Int> = doc.heard) =
        OwnResult(doc.copy(lines = lines, nextKey = nextKey, letters = letters, heard = heard, undo = doc.undo + listOf(doc.lines)), null)

    private fun nextID(doc: OwnDoc, above: OwnLine?, given: Boolean): Pair<String?, Map<String, Int>> {
        if (!given) return null to doc.letters
        val base = baseOf(above?.id)
        val n = (doc.letters[base] ?: 0) + 1
        return (base + letters(n)) to (doc.letters + (base to n))
    }

    /** The words of a text, letters and digits only: what tells a changed word from a changed comma. */
    private fun spoken(text: String): String {
        val out = StringBuilder()
        var gap = false
        val said = pieces(text).filterIsInstance<OwnPiece.Say>().joinToString(" ") { it.text }
        var i = 0
        while (i < said.length) {
            val cp = said.codePointAt(i)
            val ch = said.substring(i, i + width(cp))
            if (isC(cp, LETTER or MARK or DIGIT)) { if (gap && out.isNotEmpty()) out.append(' '); gap = false; out.append(ch) }
            else if (ch != "'" && ch != "’") gap = true
            i += width(cp)
        }
        return out.toString().lowercase(java.util.Locale.ROOT)
    }

    /** Whether more than punctuation and capitals changed between two versions of a line. */
    fun wordsChanged(before: String, after: String) = spoken(before) != spoken(after)

    private fun holdCast(doc: OwnDoc, lines: List<OwnLine>, i: Int): List<OwnLine> {
        val l = lines.getOrNull(i)
        if (l == null || l.kind != "open" || l.mark != null || doc.heard.isEmpty()) return lines
        val who = castOf(doc)[l.k] ?: return lines
        val out = lines.toMutableList()
        out[i] = l.copy(mark = who)
        return out
    }

    private val KINDS = listOf("direction", "sound", "music", "open")

    /**
     * One change on the parts page: assign, split, join, words, leaveOut, leaveOutAbove, leaveOutBelow, add, rename, notPart, undo. Refused, the doc is the one given.
     */
    fun apply(doc: OwnDoc, op: OwnOp, env: OwnEnv = OwnEnv()): OwnResult {
        fun taken(l: OwnLine) = l.id != null && l.id in env.takes
        if (env.shared) return refuse(doc, "shared")
        val lines = doc.lines
        if (op.op == "undo") {
            if (doc.undo.isEmpty()) return refuse(doc, "nothing_to_undo")
            return OwnResult(doc.copy(lines = doc.undo.last(), undo = doc.undo.dropLast(1)), null)
        }
        if (op.op == "rename" || op.op == "notPart") {
            val part = op.part
            // While casting by ear a part is its marks, and the lines heard after them (castOf); renaming covers both.
            fun marks(l: OwnLine) = op.op == "rename" && l.kind == "open" && l.mark == OwnWho.Role(part)
            fun mine(l: OwnLine) = (l.kind == "speech" && l.role == part) || marks(l)
            if (lines.none(::mine)) return refuse(doc, "no_such_part")
            val to = if (op.op == "rename") partName(normalize(op.rename)) else null
            if (op.op == "rename") {
                val why = partNameRefusal(to)
                if (why != null) return refuse(doc, why)
                if (to == part) return OwnResult(doc, null)
            }
            val cast = castOf(doc)
            if (lines.any { taken(it) && (if (op.op == "rename") cast[it.k] == OwnWho.Role(part) else mine(it)) }) return refuse(doc, "part_has_take")
            return accept(doc, lines.map { l ->
                if (!mine(l)) l
                else if (marks(l)) l.copy(mark = OwnWho.Role(to!!))
                else if (op.op == "rename") l.copy(role = to)
                else l.copy(kind = "open", role = null, label = null, text = if (l.label != null) l.label + " " + l.text else l.text)
            })
        }

        val given = lines.any { it.id != null }
        if (op.op == "add") {
            val i = if (op.after == 0) 0 else lines.indexOfFirst { it.k == op.after } + 1
            if (op.after != 0 && i == 0) return refuse(doc, "no_such_line")
            if (lines.size >= MAX_LINES) return refuse(doc, "too_many_lines")
            val text = trim(normalize(op.text))
            if (text.isEmpty()) return refuse(doc, "empty")
            val speech = op.kind == "speech"
            val role = if (speech) partName(normalize(op.role)) else null
            if (speech) { val why = partNameRefusal(role); if (why != null) return refuse(doc, why) }
            val n = nextID(doc, if (i > 0) lines[i - 1] else null, given)
            val line = OwnLine(doc.nextKey, n.first, if (speech || op.kind in KINDS) op.kind else "open", role, text)
            return accept(doc, lines.subList(0, i) + line + lines.subList(i, lines.size), doc.nextKey + 1, n.second)
        }

        val i = lines.indexOfFirst { it.k == op.line }
        if (i < 0) return refuse(doc, "no_such_line")
        val l = lines[i]
        fun put(vararg now: OwnLine): List<OwnLine> = lines.subList(0, i) + now.toList() + lines.subList(i + 1, lines.size)

        if (op.op == "words") {
            val text = trim(normalize(op.text))
            if (text.isEmpty()) return refuse(doc, "empty")
            return if (text == l.text) OwnResult(doc, null) else accept(doc, put(l.copy(text = text)))
        }
        if (op.op == "assign") {
            val to = op.to
            val role = if (to is OwnTarget.Role) partName(normalize(to.role)) else null
            val kind = if (to is OwnTarget.Role) "speech" else (to as? OwnTarget.KindOf)?.kind ?: ""
            if (kind != "speech" && kind !in KINDS) return refuse(doc, "bad_kind")
            if (kind == "speech") { val why = partNameRefusal(role); if (why != null) return refuse(doc, why) }
            if (l.kind == kind && l.role == role) return OwnResult(doc, null)
            if (taken(l)) return refuse(doc, "line_has_take")
            return accept(doc, holdCast(doc, put(l.copy(kind = kind, role = role, mark = null)), i + 1))
        }
        if (op.op == "leaveOutAbove" || op.op == "leaveOutBelow") {
            val above = op.op == "leaveOutAbove"
            val gone = if (above) lines.subList(0, i) else lines.subList(i + 1, lines.size)
            if (gone.isEmpty()) return refuse(doc, if (above) "no_line_above" else "no_line_below")
            if (gone.any(::taken)) return refuse(doc, "lines_have_take")
            return accept(doc, if (above) holdCast(doc, lines.subList(i, lines.size).toList(), 0) else lines.subList(0, i + 1).toList())
        }
        if (taken(l)) return refuse(doc, "line_has_take")
        if (op.op == "leaveOut") return accept(doc, holdCast(doc, put(), i))
        if (op.op == "split") {
            val p = cutAt(l.text, op.at)
            if (p < 0) return refuse(doc, "empty")
            if (lines.size >= MAX_LINES) return refuse(doc, "too_many_lines")
            val n = nextID(doc, l, given)
            var a = l.copy(text = trim(l.text.sl(0, p)))
            var b = l.copy(k = doc.nextKey, id = n.first, text = trim(l.text.sl(p)), label = null, mark = null)
            val span = l.at
            if (span != null) {
                val t = timeAt(span, l.text.length, p)
                a = a.copy(at = span.first to t)
                b = b.copy(at = t to span.second)
            }
            val heard = if (l.k in doc.heard) doc.heard + b.k else doc.heard
            return accept(doc, put(a, b), doc.nextKey + 1, n.second, heard)
        }
        if (op.op == "join") {
            if (i == 0) return refuse(doc, "no_line_above")
            val above = lines[i - 1]
            if (taken(above)) return refuse(doc, "line_has_take")
            val verse = above.text.contains('\n') || l.text.contains('\n')
            var one = above.copy(text = above.text + (if (verse) "\n" else " ") + l.text)
            if (above.at != null && l.at != null) one = one.copy(at = above.at.first to l.at.second)
            return accept(doc, holdCast(doc, lines.subList(0, i - 1) + one + lines.subList(i + 1, lines.size), i))
        }
        return refuse(doc, "no_such_op")
    }

    /** The two nearest speakers above and below, no name twice: the one-tap answers for a line with no part. */
    fun nearestParts(lines: List<OwnLine>, i: Int): List<String> {
        val out = ArrayList<String>()
        var d = 1
        while (d < lines.size && out.size < 2) {
            for (j in listOf(i - d, i + d)) {
                val l = lines.getOrNull(j)
                if (l != null && l.kind == "speech" && l.role!! !in out && out.size < 2) out.add(l.role)
            }
            d += 1
        }
        return out
    }

    /** Done: each line gets its id, once, and the steps before it can no longer be taken back. */
    fun done(doc: OwnDoc, keepOpen: Boolean = false): OwnDoc {
        var lines = doc.lines
        if (lines.none { it.id != null }) lines = lines.mapIndexed { i, l -> l.copy(id = "L" + pad(i + 1)) }
        if (!keepOpen) lines = lines.map { if (it.kind == "open" && it.mark == null) it.copy(kind = "direction") else it }
        return doc.copy(lines = lines, undo = emptyList())
    }

    // ---- The castable shape ----

    private class Shaped(val id: String?, val kind: String, val role: String?, val parts: List<OwnPiece>, val source: String)

    /**
     * A done doc as a castable script (plain data, as the catalog's JSON reads), its revision still to be sealed. Lines marked by ear
     * are theirs; left-out lines are not in it; a line with no part is a direction.
     */
    fun toScript(doc: OwnDoc, meta: OwnMeta): Map<String, Any?> {
        val shaped = settle(doc).lines.map { l ->
            if (l.kind == "speech") Shaped(l.id, "speech", l.role, pieces(l.text), "")
            else Shaped(l.id, if (l.kind == "open") "direction" else l.kind, null, emptyList(), l.text)
        }
        val roles = LinkedHashMap<String, IntArray>()
        for (l in shaped) {
            if (l.kind != "speech") continue
            val r = roles.getOrPut(l.role!!) { IntArray(2) }
            r[0] += 1
            for (p in l.parts) if (p is OwnPiece.Say) r[1] += wordsOf(p.text).size
        }
        val episode = meta.episodeId != null
        return buildMap {
            put("id", meta.id)
            put("revision", "")
            put("kind", "own")
            put("title", trim(normalize(meta.title)))
            put("authors", emptyList<Any?>())
            put("source", if (episode) mapOf("name" to "Automatic transcript", "url" to meta.episodeUrl) else mapOf("name" to "Added by you", "url" to ""))
            if (episode) put("episode", meta.episodeId)
            put("rights", mapOf("bucket" to "own", "evidence" to emptyList<Any?>()))
            put("roles", roles.map { (name, c) -> mapOf("name" to name, "lines" to c[0], "words" to c[1]) })
            put(
                "lines",
                shaped.map { l ->
                    if (l.kind == "speech") {
                        mapOf(
                            "id" to l.id, "kind" to "speech", "role" to l.role,
                            "parts" to l.parts.map { p -> mapOf((if (p is OwnPiece.Say) "say" else "direction") to p.text) },
                        )
                    } else mapOf("id" to l.id, "kind" to l.kind, "source" to l.source)
                },
            )
        }
    }

    /** A doc over a script as it stands, for Edit a copy (new script id, same line ids). */
    fun fromScript(script: Map<String, Any?>): OwnDoc {
        val given = HashMap<String, Int>()
        val src = (script["lines"] as List<*>).map { it as Map<*, *> }
        val lines = src.mapIndexed { i, l ->
            val id = l["id"] as String
            val base = baseOf(id)
            given[base] = maxOf(given[base] ?: 0, lettersValue(id.sl(5)))
            val speech = l["kind"] == "speech"
            val text = if (speech) {
                textOf((l["parts"] as List<*>).map { p ->
                    val m = p as Map<*, *>
                    if (m.containsKey("say")) OwnPiece.Say(m["say"] as String) else OwnPiece.Direction(m["direction"] as String)
                })
            } else l["source"] as String
            OwnLine(i + 1, id, l["kind"] as String, if (speech) l["role"] as String? else null, text)
        }
        return OwnDoc(lines, lines.size + 1, given.filterValues { it != 0 })
    }

    /** A doc as it is kept: everything but the steps that can be taken back. */
    fun kept(doc: OwnDoc): OwnDoc = doc.copy(undo = emptyList())

    // ---- The revision ----

    private const val HEX = "0123456789abcdef"

    private fun jsonString(s: String, out: StringBuilder) {
        out.append('"')
        for (c in s) {
            val u = c.code
            when {
                u == 34 -> out.append("\\\"")
                u == 92 -> out.append("\\\\")
                u == 10 -> out.append("\\n")
                u == 13 -> out.append("\\r")
                u == 9 -> out.append("\\t")
                u == 8 -> out.append("\\b")
                u == 12 -> out.append("\\f")
                u < 32 -> out.append("\\u00").append(HEX[u shr 4]).append(HEX[u and 15])
                else -> out.append(c)
            }
        }
        out.append('"')
    }

    private fun canonical(v: Any?, out: StringBuilder) {
        when (v) {
            is List<*> -> { out.append('['); v.forEachIndexed { i, x -> if (i > 0) out.append(','); canonical(x, out) }; out.append(']') }
            is String -> jsonString(v, out)
            is Map<*, *> -> {
                out.append('{')
                v.keys.map { it as String }.sorted().forEachIndexed { i, k -> if (i > 0) out.append(','); jsonString(k, out); out.append(':'); canonical(v[k], out) }
                out.append('}')
            }
            else -> out.append(v.toString())
        }
    }

    /** The bytes that are hashed, and sent when a script is shared: keys sorted, no spaces, nothing escaped that need not be. Over plain data: Map, List, String, numbers, null. */
    fun canonicalLines(lines: Any?): String = StringBuilder().also { canonical(lines, it) }.toString()

    /** The catalog's revision: the first 12 hex digits of the SHA-256 of the canonical lines, UTF-8. */
    fun revisionOf(lines: Any?): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(canonicalLines(lines).toByteArray(Charsets.UTF_8))
        val sb = StringBuilder()
        for (b in digest) { val x = b.toInt() and 0xFF; sb.append(HEX[x shr 4]).append(HEX[x and 15]) }
        return sb.substring(0, 12)
    }

    fun seal(script: Map<String, Any?>): Map<String, Any?> = script + ("revision" to revisionOf(script["lines"]))

    /** null when `script` may be kept and shared, or the first thing wrong with it. */
    fun refusalOf(script: Any?): String? {
        val s = script as? Map<*, *> ?: return "bad_id"
        val id = s["id"] as? String
        if (id == null || !OWN_ID.matches(id)) return "bad_id"
        val title = s["title"] as? String
        if (title == null || trim(title).isEmpty()) return "no_title"
        if (title.length > MAX_TITLE) return "title_too_long"
        val lines = s["lines"] as? List<*>
        if (lines == null || lines.isEmpty()) return "no_lines"
        if (lines.size > MAX_LINES) return "too_many_lines"
        val seen = HashSet<String>()
        for (l in lines) {
            val m = l as? Map<*, *>
            val lid = m?.get("id") as? String
            if (m == null || lid == null || !LINE_ID.matches(lid) || !seen.add(lid)) return "bad_line_id"
            val kind = m["kind"]
            if (kind == "speech") {
                val role = m["role"] as? String
                if (role == null || role != partName(role) || partNameRefusal(role) != null) return "bad_part"
                val parts = m["parts"] as? List<*>
                if (parts == null || parts.isEmpty()) return "bad_line"
                for (p in parts) {
                    val pm = p as? Map<*, *>
                    val k = pm?.keys?.toList() ?: emptyList()
                    if (pm == null || k.size != 1 || (k[0] != "say" && k[0] != "direction")) return "bad_line"
                    val v = pm[k[0]]
                    if (v !is String || v.isEmpty()) return "bad_line"
                }
            } else if (kind == "direction" || kind == "sound" || kind == "music") {
                val src = m["source"]
                if (src !is String || src.isEmpty()) return "bad_line"
            } else return "bad_line"
        }
        if (lines.none { (it as Map<*, *>)["kind"] == "speech" }) return "no_parts"
        if (utf8Length(canonicalLines(lines)) > MAX_BYTES) return "too_long"
        return null
    }

    /** null, or why Done would refuse [parse]'s lines whatever the person makes of them: too_many_lines, too_long. Asked at Next. */
    fun builtRefusal(lines: List<OwnLine>): String? {
        if (lines.size > MAX_LINES) return "too_many_lines"
        return if (utf8Length(canonicalLines(toScript(done(newDoc(lines)), OwnMeta("", ""))["lines"])) > MAX_BYTES) "too_long" else null
    }

    /** null when a text may be read, or why not: empty, too_long. Asked before [parse]. */
    fun textRefusal(raw: String?): String? {
        val t = raw ?: ""
        if (t.length > MAX_BYTES || utf8Length(t) > MAX_BYTES) return "too_long"
        return if (trim(normalize(t)).isNotEmpty()) null else "empty"
    }

    // ---- A transcript, cast by ear ----

    /** `start + (end - start) * at / length`, whole milliseconds, rounded down. */
    private fun timeAt(span: Pair<Long, Long>, length: Int, at: Int): Long = span.first + ((span.second - span.first) * at) / length

    private fun digitsAt(s: String, p: Int, max: Int): Int {
        var n = 0
        while (n < max && p + n < s.length && s[p + n] in '0'..'9') n += 1
        return n
    }

    private class Clock(val ms: Long, val end: Int)

    private fun clock(s: String, p: Int): Clock? {
        val nums = ArrayList<Long>()
        var i = p
        while (true) {
            val n = digitsAt(s, i, 4)
            if (n == 0) return null
            nums.add(s.substring(i, i + n).toLong())
            i += n
            if (at(s, i, ':') && nums.size < 3) { i += 1; continue }
            break
        }
        if (nums.size < 2 || (!at(s, i, '.') && !at(s, i, ','))) return null
        if (digitsAt(s, i + 1, 3) != 3) return null
        val ms = s.substring(i + 1, i + 4).toLong()
        val sec = nums[nums.size - 1]
        val min = nums[nums.size - 2]
        val hour = if (nums.size == 3) nums[0] else 0L
        if (sec > 59 || min > 59) return null
        return Clock((((hour * 60) + min) * 60 + sec) * 1000 + ms, i + 4)
    }

    private fun cueText(s: String): String {
        val out = StringBuilder()
        val last = s.lastIndexOf('>')
        var i = 0
        while (i < s.length) {
            if (s[i] == '<' && i < last) { i = s.indexOf('>', i) + 1; continue }
            out.append(s[i])
            i += 1
        }
        var t = out.toString()
        for ((a, b) in listOf("&lt;" to "<", "&gt;" to ">", "&nbsp;" to " ", "&quot;" to "\"", "&#39;" to "'", "&amp;" to "&")) t = t.replace(a, b)
        return wordsOf(t).joinToString(" ")
    }

    /** A transcript's cues: WebVTT (or SRT) by its times; any other text, one cue a row with no times. */
    fun parseCues(raw: String?): List<OwnCue> {
        val rows = normalize(raw).split('\n').map(::trim)
        val out = ArrayList<OwnCue>()
        if (rows.none { it.contains("-->") }) {
            for (r in rows) { val t = cueText(r); if (t.isNotEmpty() && r != "WEBVTT") out.add(OwnCue(t, null)) }
            return out
        }
        var i = 0
        while (i < rows.size) {
            val arrow = rows[i].indexOf("-->")
            if (arrow < 0) { i += 1; continue }
            val a = clock(rows[i], 0)
            val b = clock(rows[i], skipGap(rows[i], arrow + 3))
            var j = i + 1
            val said = ArrayList<String>()
            while (j < rows.size && rows[j].isNotEmpty() && !rows[j].contains("-->")) { said.add(rows[j]); j += 1 }
            val t = cueText(said.joinToString(" "))
            if (a != null && b != null && b.ms >= a.ms && t.isNotEmpty()) out.add(OwnCue(t, a.ms to b.ms))
            i = j
        }
        return out
    }

    private val ABBREVIATIONS = set("Mr Mrs Ms Dr St Col Capt Lt Gen Sgt Prof Rev")
    private fun closesQuote(c: Char) = c == '"' || c == '\'' || c == '”' || c == '’'
    private fun opensQuote(c: Char) = c == '"' || c == '\'' || c == '“' || c == '‘'

    /** Where a cue's text is cut into lines: the index after each sentence's end, when a space and a capital follow. */
    fun sentenceCuts(t: String): List<Int> {
        val out = ArrayList<Int>()
        for (i in t.indices) {
            val c = t[i]
            if (c != '.' && c != '?' && c != '!') continue
            var j = i + 1
            while (j < t.length && closesQuote(t[j])) j += 1
            if (!at(t, j, ' ')) continue
            var n = j + 1
            if (n < t.length && opensQuote(t[n])) n += 1
            if (!isC(cpAt(t, n), UPPER)) continue
            if (c == '.') {
                var w = i
                while (w > 0 && asciiWord(t[w - 1].code)) w -= 1
                val before = if (w > 0) codePointBefore(t, w) else -1
                if (t.sl(w, i) in ABBREVIATIONS && !isC(before, LETTER or MARK)) continue
            }
            out.add(j)
        }
        return out
    }

    /** Cues as lines to cast, each a sentence of one cue with its share of the cue's time by UTF-16 units. */
    fun fromCues(cues: List<OwnCue>): OwnDoc {
        val lines = ArrayList<OwnLine>()
        for (cue in cues) {
            var from = 0
            val n = cue.text.length
            for (cut in sentenceCuts(cue.text) + n) {
                val text = trim(cue.text.sl(from, cut))
                val span = cue.at
                val at = if (span != null) timeAt(span, n, from) to timeAt(span, n, if (cut == n) n else cut + 1) else null
                if (text.isNotEmpty()) lines.add(OwnLine(kind = "open", text = text, at = at))
                from = cut + 1
            }
        }
        return newDoc(lines)
    }

    /** The line being said at `ms` (its key), or the last one begun; 0 before the first. */
    fun lineAt(doc: OwnDoc, ms: Long): Int {
        var k = 0
        for (l in doc.lines) { val a = l.at ?: continue; if (a.first > ms) break; k = l.k }
        return k
    }

    /** Who each line is cast to, by key: a part, [OwnWho.Out], or null. A mark carries to the lines heard in a row after it. */
    fun castOf(doc: OwnDoc): Map<Int, OwnWho?> {
        val heard = doc.heard.toHashSet()
        val out = HashMap<Int, OwnWho?>()
        var carry: OwnWho? = null
        for (l in doc.lines) {
            if (l.kind != "open") { out[l.k] = if (l.kind == "speech") OwnWho.Role(l.role!!) else null; carry = null; continue }
            if (l.mark != null) carry = l.mark
            else if (l.k !in heard) carry = null
            out[l.k] = carry
        }
        return out
    }

    /** The audio reached line `k`, coming from line `from` (0 after a seek): it and those between are heard. Never undone. */
    fun hear(doc: OwnDoc, k: Int, from: Int = 0): OwnDoc {
        val b = doc.lines.indexOfFirst { it.k == k }
        if (b < 0) return doc
        val a0 = if (from != 0) doc.lines.indexOfFirst { it.k == from } else -1
        val a = if (a0 in 0..b) a0 else b
        val heard = LinkedHashSet(doc.heard)
        val before = heard.size
        for (i in a..b) heard.add(doc.lines[i].k)
        return if (heard.size == before) doc else doc.copy(heard = heard.toList())
    }

    /** A tap on a part (or Leave out) while line `k` is lit. */
    fun tap(doc: OwnDoc, k: Int, who: OwnWho, env: OwnEnv = OwnEnv()): OwnResult {
        if (env.shared) return refuse(doc, "shared")
        val i = doc.lines.indexOfFirst { it.k == k }
        if (i < 0) return refuse(doc, "no_such_line")
        var mark: OwnWho = OwnWho.Out
        if (who is OwnWho.Role) {
            val role = partName(normalize(who.name))
            val why = partNameRefusal(role)
            if (why != null) return refuse(doc, why)
            mark = OwnWho.Role(role)
        }
        val lines = doc.lines.toMutableList()
        lines[i] = lines[i].copy(kind = "open", role = null, mark = mark)
        return marked(doc, lines, env, listOf(k))
    }

    /** Leaves out one line and no other: the next keeps the cast it had. */
    fun leaveOutHeard(doc: OwnDoc, k: Int, env: OwnEnv = OwnEnv()): OwnResult {
        if (env.shared) return refuse(doc, "shared")
        val i = doc.lines.indexOfFirst { it.k == k }
        if (i < 0) return refuse(doc, "no_such_line")
        val lines = doc.lines.toMutableList()
        lines[i] = lines[i].copy(kind = "open", role = null, mark = OwnWho.Out)
        return marked(doc, holdCast(doc, lines, i + 1), env, listOf(k))
    }

    private fun marked(doc: OwnDoc, lines: List<OwnLine>, env: OwnEnv, heardNow: List<Int>): OwnResult {
        val heard = LinkedHashSet(doc.heard).also { it.addAll(heardNow) }.toList()
        val next = accept(doc, lines, heard = heard)
        if (env.takes.isNotEmpty()) {
            val was = castOf(doc)
            val now = castOf(next.doc)
            if (doc.lines.any { it.id != null && it.id in env.takes && was[it.k] != now[it.k] }) return refuse(doc, "line_has_take")
        }
        return next
    }

    /** "37 of 149 lines cast": lines given to a part or left out, of all of them. */
    fun castCount(doc: OwnDoc): Pair<Int, Int> {
        val cast = castOf(doc)
        var n = 0
        for (l in doc.lines) if (l.kind != "open" || cast[l.k] != null) n += 1
        return n to doc.lines.size
    }

    /** The marks made into the lines' own parts, left-out lines gone. */
    fun settle(doc: OwnDoc): OwnDoc {
        val cast = castOf(doc)
        val lines = ArrayList<OwnLine>()
        for (l in doc.lines) {
            if (l.kind != "open") { lines.add(l); continue }
            val who = cast[l.k]
            if (who == OwnWho.Out) continue
            val rest = l.copy(mark = null)
            lines.add(if (who == null) rest else rest.copy(kind = "speech", role = (who as OwnWho.Role).name))
        }
        return doc.copy(lines = lines)
    }
}
