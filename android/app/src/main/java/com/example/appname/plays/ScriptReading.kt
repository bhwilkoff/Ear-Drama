package com.example.appname.plays

import java.text.Normalizer
import java.util.Collections
import java.util.WeakHashMap
import kotlinx.serialization.Serializable

// Reading a script (Decision 076 S0 and S1; docs/research/design/R2-reader-port-brief.md). Pure Kotlin,
// ported from js/plays-core.js and js/reader-core.js: the headings every stack must agree on
// (catalog/tests/golden/script_sections.json), the contents, search, a part's next line, and the page
// arithmetic. A page is never stored: the position is a line id, and a page is wherever that line falls.

/** A printed heading the parser set aside, verbatim, at the id of the line it opens (contract §4.1). */
@Serializable
data class ScriptSection(val line: String, val source: String)

/** What a play's list and tile need, whether it is a whole script or a row of the published index. */
interface PlayListing {
    val id: String
    val title: String
    val kind: String
    val year: Int?
    val sortName: String?
    val voices: Int
    val minutes: Int
    /** Each speaking part's speeches, largest first. */
    val cast: List<Int>
    val authorLine: String
    val authorWithYears: String
    /** Speeches, the figure the index calls `lines`. */
    val speechCount: Int

    val voiceBand: String? get() = PlayScript.VOICE_BANDS.firstOrNull { voices in it.lo..it.hi }?.key
    val lengthBand: String? get() = PlayScript.LENGTH_BANDS.firstOrNull { minutes in it.lo..it.hi }?.key
}

object ScriptReading {
    /** A role a person can cast has at least this many speeches (catalog/tools/script_parse.py CASTABLE_LINES). */
    const val CASTABLE_LINES = 5

    enum class Level { Act, Scene, Part }

    private const val NUM = "(?:[IVXLC]+|\\d+|ONE|TWO|THREE|FOUR|FIVE|SIX|SEVEN|EIGHT|NINE|TEN|FIRST|SECOND|THIRD|FOURTH|" +
        "FIFTH|SIXTH|SEVENTH|EIGHTH|NINTH|TENTH|LAST|PRIMUS|SECUNDUS|TERTIUS|QUARTUS|QUINTUS)"
    private const val ORD = "(?:FIRST|SECOND|THIRD|FOURTH|FIFTH|SIXTH|SEVENTH|EIGHTH|NINTH|TENTH|LAST)"

    // JavaScript's \s is wider than Java's: the same set, spelled out.
    private const val S = "[\\s\\u00A0\\u1680\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000\\uFEFF]"
    private val ACT = Regex("^[\\W_]*(?:ACT(?:US)?\\.?$S+($NUM)\\b|(?:THE$S+)?($ORD)$S+ACT\\b)", RegexOption.IGNORE_CASE)
    private val SCENE = Regex("^[\\W_]*(?:SC(?:ENE|ENA|OENA)\\.?$S+$NUM\\b|(?:THE$S+)?$ORD$S+SCENE\\b)", RegexOption.IGNORE_CASE)
    private val PART = Regex("^[\\W_]*(?:PROLOGUE|EPILOGUE|INDUCTION)[\\W_]*$", RegexOption.IGNORE_CASE)
    private val RUNS_OF_SPACE = Regex("$S+")

    private fun firstLine(text: String?): String = (text ?: "").trim().split('\n')[0].trim()

    /** Act, scene, part (a prologue, epilogue or induction), or null. */
    fun sectionLevel(text: String?): Level? {
        val f = firstLine(text)
        return when {
            ACT.containsMatchIn(f) -> Level.Act
            SCENE.containsMatchIn(f) -> Level.Scene
            PART.containsMatchIn(f) -> Level.Part
            else -> null
        }
    }

    /** A heading as the reader names it: its first printed line, italic marks and runs of spaces dropped. */
    fun sectionTitle(text: String?): String = firstLine(text).replace("_", "").replace(RUNS_OF_SPACE, " ").trim()

    /** The act's number as printed, upper-cased ("ACT I. SCENE II." gives "I"), or null. */
    fun actKey(text: String?): String? {
        val m = ACT.find(firstLine(text)) ?: return null
        return (m.groupValues[1].ifEmpty { m.groupValues[2] }).uppercase()
    }

    /** One place in a play: its heading, the line it falls on, and whether the heading is itself that stage-direction line. */
    data class Section(
        val line: String,
        val index: Int,
        val level: Level,
        val title: String,
        val act: String?,
        val isLine: Boolean,
    )

    /** An act or part with its scenes; a scene before any act, or after a part, stands alone. */
    data class Entry(val section: Section, val scenes: List<Section>) {
        val index: Int get() = section.index
        val title: String get() = section.title
    }

    private val sectionCache: MutableMap<PlayScript, List<Section>> = Collections.synchronizedMap(WeakHashMap())

    /** Every section in reading order. An act heading repeating the act in hand is a scene; a heading with no speech under it is left out. */
    fun sectionsOf(script: PlayScript): List<Section> = sectionCache.getOrPut(script) { buildSections(script) }

    private class Draft(val line: String, val index: Int, var level: Level, val title: String, val act: String?, val isLine: Boolean, val order: Int)

    private fun buildSections(script: PlayScript): List<Section> {
        val at = HashMap<String, Int>()
        script.lines.forEachIndexed { i, l -> at.putIfAbsent(l.id, i) }
        val out = ArrayList<Draft>()
        var order = 0
        for (s in script.sections) {
            val level = sectionLevel(s.source)
            val index = at[s.line]
            if (level != null && index != null) out += Draft(s.line, index, level, sectionTitle(s.source), actKey(s.source), false, order++)
        }
        script.lines.forEachIndexed { index, l ->
            if (l.kind == ScriptLine.Kind.Speech) return@forEachIndexed
            val level = sectionLevel(l.source) ?: return@forEachIndexed
            out += Draft(l.id, index, level, sectionTitle(l.source), actKey(l.source), true, order++)
        }
        out.sortWith(compareBy<Draft> { it.index }.thenBy { if (it.isLine) 1 else 0 }.thenBy { it.order })
        var act: String? = null
        for (s in out) {
            if (s.level == Level.Act && act != null && s.act != null && s.act == act) s.level = Level.Scene
            else if (s.level == Level.Act) act = s.act
            else if (s.level == Level.Part) act = null
        }
        val speechBefore = IntArray(script.lines.size + 1)
        script.lines.forEachIndexed { i, l -> speechBefore[i + 1] = speechBefore[i] + if (l.kind == ScriptLine.Kind.Speech) 1 else 0 }
        fun rank(s: Draft) = if (s.level == Level.Scene) 1 else 0
        return out.filterIndexed { i, s ->
            val next = out.drop(i + 1).firstOrNull { rank(it) <= rank(s) }
            val end = next?.index ?: script.lines.size
            speechBefore[end] - speechBefore[s.index] > 0
        }.map { Section(it.line, it.index, it.level, it.title, it.act, it.isLine) }
    }

    private val contentsCache: MutableMap<PlayScript, List<Entry>> = Collections.synchronizedMap(WeakHashMap())

    /** The contents: acts (and prologues, epilogues) with their scenes. */
    fun contentsOf(script: PlayScript): List<Entry> = contentsCache.getOrPut(script) {
        val entries = ArrayList<Pair<Section, MutableList<Section>>>()
        var act: Pair<Section, MutableList<Section>>? = null
        for (s in sectionsOf(script)) {
            val a = act
            if (s.level == Level.Act) {
                act = s to ArrayList()
                entries += act
            } else if (s.level == Level.Scene && a != null) {
                a.second += s
            } else {
                entries += s to ArrayList()
                if (s.level == Level.Part) act = null
            }
        }
        entries.map { Entry(it.first, it.second.toList()) }
    }

    /** The act and the scene a line falls in. */
    data class Place(val act: Entry?, val scene: Section?) {
        /** "Act · scene", one line; empty before the first heading. */
        val label: String get() = listOfNotNull(act?.title, scene?.title).joinToString(" · ")
    }

    fun placeOf(script: PlayScript, lineIndex: Int): Place {
        var act: Entry? = null
        var scene: Section? = null
        for (top in contentsOf(script)) {
            if (top.index > lineIndex) break
            act = top
            scene = null
            for (s in top.scenes) {
                if (s.index > lineIndex) break
                scene = s
            }
        }
        return Place(act, scene)
    }

    /** The printed words of a line, as one string: a speech's pieces joined by a space, else its block. This is what marks anchor to. */
    fun lineText(line: ScriptLine): String =
        if (line.kind == ScriptLine.Kind.Speech && line.parts != null) line.parts.joinToString(" ") { it.text } else line.source.orEmpty()

    private class Folded(val text: String, val out: String, val from: IntArray)

    private val SPACE_CHAR = Regex(S)

    private fun isSpace(c: Char) = if (c.code < 128) c == ' ' || c in '\t'..'\r' else SPACE_CHAR.matches(c.toString())

    /** Folds case, accents, curly quotes and runs of space, keeping where each folded character came from. */
    private fun fold(text: String): Folded {
        val out = StringBuilder()
        val from = ArrayList<Int>()
        var space = false
        for (i in text.indices) {
            val c = text[i]
            if (isSpace(c)) {
                if (space) continue
                space = true
                out.append(' ')
                from += i
                continue
            }
            space = false
            if (c.code < 128) {
                out.append(c.lowercaseChar())
                from += i
                continue
            }
            val decomposed = Normalizer.normalize(c.toString(), Normalizer.Form.NFD).filter { it.code !in 0x300..0x36F }
            val f = decomposed.lowercase().replace('‘', '\'').replace('’', '\'').replace('“', '"').replace('”', '"')
            for (ch in f) {
                out.append(ch)
                from += i
            }
        }
        return Folded(text, out.toString(), from.toIntArray())
    }

    private val foldCache: MutableMap<PlayScript, List<Folded>> = Collections.synchronizedMap(WeakHashMap())

    data class Hit(val line: String, val index: Int, val role: String?, val before: String, val match: String, val after: String)

    data class Found(val total: Int, val hits: List<Hit>)

    /**
     * Every line whose printed words hold the query, ignoring case, accents, curly quotes and line breaks:
     * the first [limit] hits in reading order with up to [span] characters either side. Under two characters finds nothing.
     */
    fun search(script: PlayScript, query: String, limit: Int = 100, span: Int = 40): Found {
        val q = fold(query.trim()).out
        if (q.length < 2) return Found(0, emptyList())
        val folded = foldCache.getOrPut(script) { script.lines.map { fold(lineText(it)) } }
        val hits = ArrayList<Hit>()
        var total = 0
        folded.forEachIndexed { index, f ->
            val at = f.out.indexOf(q)
            if (at < 0) return@forEachIndexed
            total += 1
            if (hits.size >= limit) return@forEachIndexed
            val start = f.from[at]
            val end = f.from[at + q.length - 1] + 1
            val line = script.lines[index]
            val b = maxOf(0, start - span)
            val t = f.text
            hits += Hit(
                line.id, index, if (line.kind == ScriptLine.Kind.Speech) line.role else null,
                (if (b > 0) "…" else "") + t.substring(b, start).replace(RUNS_OF_SPACE, " ").trimStart(),
                t.substring(start, end).replace(RUNS_OF_SPACE, " "),
                t.substring(end, minOf(t.length, end + span)).replace(RUNS_OF_SPACE, " ").trimEnd() + (if (end + span < t.length) "…" else ""),
            )
        }
        return Found(total, hits)
    }

    /** A part's lines in reading order, as indexes into the script's lines. */
    fun lineIndexesOf(script: PlayScript, part: PartID): List<Int> = script.lines.indices.filter { script.lines[it].part == part }

    /** The first of [part]'s lines after [index] (direction 1) or before it (-1), or -1 when none. */
    fun nextLineOf(script: PlayScript, part: PartID, index: Int, direction: Int = 1): Int {
        val mine = lineIndexesOf(script, part)
        if (direction > 0) return mine.firstOrNull { it > index } ?: -1
        return mine.lastOrNull { it < index } ?: -1
    }

    /**
     * The speaking parts still open (never sound effects or stage directions). With the script, every speaking part
     * it names that the record does not hold as taken is open; without it, the record's own parts.
     */
    fun openSpeakingParts(statuses: Map<String, String>, script: PlayScript?): List<String> {
        val parts = script?.castParts?.map { it.id.raw } ?: statuses.keys.toList()
        return parts.filter { it.startsWith("role:") && (statuses[it] ?: "open") == "open" }
    }

    // MARK: Browse helpers: an index row or a whole script count the same

    /** Voices a person can cast: roles with [CASTABLE_LINES] speeches, else the speaking parts counted from the lines. */
    fun voicesOf(script: PlayScript): Int =
        if (script.roles.isNotEmpty()) script.roles.count { it.lines >= CASTABLE_LINES } else script.castParts.count { it.id.isSpeaking }

    fun minutesOf(script: PlayScript): Int =
        maxOf(1, Math.round(script.roles.sumOf { it.words } / PlayScript.WORDS_PER_MINUTE.toDouble()).toInt())

    /** Each speaking part's speeches, largest first. */
    fun castOf(script: PlayScript): List<Int> = script.castParts.filter { it.id.isSpeaking }.map { it.lineCount }

    // MARK: Runs

    enum class RunKind { Say, Em, Aside, Plain }

    /**
     * A printed run: [at] is its offset into [lineText]. A speech's pieces are [RunKind.Say] (the words) or
     * [RunKind.Aside] (a printed direction inside it); a block is [RunKind.Plain]. `_italic_` marks toggle
     * the face (said turns [RunKind.Em], an aside turns [RunKind.Plain]) and are never shown.
     */
    data class Run(val kind: RunKind, val text: String, val at: Int, val piece: Int, val said: Boolean)

    fun runsOf(line: ScriptLine): List<Run> {
        val runs = ArrayList<Run>()
        fun split(text: String, start: Int, piece: Int, said: Boolean, base: RunKind, flipped: RunKind) {
            var at = start
            var on = false
            for (seg in text.split('_')) {
                if (seg.isNotEmpty()) runs += Run(if (on) flipped else base, seg, at, piece, said)
                at += seg.length + 1
                on = !on
            }
        }
        val parts = line.parts
        if (line.kind == ScriptLine.Kind.Speech && parts != null) {
            var at = 0
            parts.forEachIndexed { i, piece ->
                if (i > 0) at += 1
                val text = piece.text
                if (piece is LinePart.Say) split(text, at, i, true, RunKind.Say, RunKind.Em) else split(text, at, i, false, RunKind.Aside, RunKind.Plain)
                at += text.length
            }
            return runs
        }
        split(line.source.orEmpty(), 0, 0, false, RunKind.Plain, RunKind.Em)
        return runs
    }

    private val NO_SPACE_BEFORE = Regex("^[.,;:!?)\\]\\u2019\\u201D\\u2026\\u2014-]")
    private val NO_SPACE_AFTER = Regex("[(\\[\\u201C\\u2018\\u2014-]$")

    /** Whether a space is drawn between two printed pieces: not before closing punctuation, not after an opening one. */
    fun spaceBetween(before: String, after: String): Boolean = !NO_SPACE_BEFORE.containsMatchIn(after) && !NO_SPACE_AFTER.containsMatchIn(before)
}

/** The reader's settings, stored as the web stores them: `{layout, size, spacing}`. */
@Serializable
data class ReaderPrefs(val layout: String = "pages", val size: Int = ReaderMath.DEFAULT_SIZE, val spacing: String = "normal") {
    val scale: Float get() = ReaderMath.SIZES[size]
    val leading: Float get() = ReaderMath.SPACING.getValue(spacing)
    val pages: Boolean get() = layout == "pages"
}

/** The reader-core.js arithmetic, no UI. */
object ReaderMath {
    val SIZES = listOf(0.875f, 0.9375f, 1f, 1.125f, 1.25f, 1.5f, 1.75f)
    const val DEFAULT_SIZE = 2
    val SPACING = linkedMapOf("tight" to 1.35f, "normal" to 1.55f, "loose" to 1.8f)
    val LAYOUTS = listOf("pages", "scroll")

    /** Two facing pages once the reading area is this wide (dp). */
    const val SPREAD_MIN = 900

    /** Settings as stored (or not): anything unknown falls back to the default. Pages by default (owner, Decision 076). */
    fun normalizePrefs(layout: Any?, size: Any?, spacing: Any?): ReaderPrefs {
        val s = (size as? Int)?.takeIf { it in SIZES.indices } ?: DEFAULT_SIZE
        return ReaderPrefs(
            layout = (layout as? String)?.takeIf { it in LAYOUTS } ?: "pages",
            size = s,
            spacing = (spacing as? String)?.takeIf { it in SPACING } ?: "normal",
        )
    }

    /** How many pages one screen shows: two from [SPREAD_MIN], else one. */
    fun perSpread(width: Float): Int = if (width >= SPREAD_MIN) 2 else 1

    /**
     * The reading position on a page: the first line still showing on it, which is the line carried over from the page
     * before when there is one (so a restore never skips words). [starts] and [ends] are the pages where each line begins and ends.
     */
    fun lineAtPage(starts: IntArray, ends: IntArray, page: Int): Int {
        for (i in ends.indices) {
            if (ends[i] >= page && starts[i] <= page) return i
            if (starts[i] > page) return i
        }
        return if (ends.isNotEmpty()) ends.size - 1 else -1
    }

    /** The first page of the screen that shows [page]: spreads begin on even pages. */
    fun spreadStart(page: Int, per: Int): Int = Math.floorDiv(page, per) * per

    /** Where a turn lands: one screen on or back, never past the first or the last. */
    fun turn(page: Int, delta: Int, per: Int, count: Int): Int {
        val last = spreadStart(maxOf(0, count - 1), per)
        return minOf(last, maxOf(0, spreadStart(page, per) + delta * per))
    }

    /** A finished drag: -1 back, 1 on, 0 stay. Past a fifth of the width, or a flick (30 px at 0.4 px/ms). */
    fun swipeTurn(dx: Float, ms: Float, width: Float): Int {
        val fast = Math.abs(dx) >= 30 && Math.abs(dx) / maxOf(1f, ms) >= 0.4f
        if (Math.abs(dx) < width / 5 && !fast) return 0
        return if (dx < 0) 1 else -1
    }

    enum class Zone { Prev, Middle, Next }

    /** A tap on the page: the outer fifth of either edge turns, the middle does not. */
    fun tapZone(x: Float, width: Float): Zone = when {
        x < width / 5 -> Zone.Prev
        x > width * 4 / 5 -> Zone.Next
        else -> Zone.Middle
    }

    /** What a key does to the page: a turn of 1 or -1, or to the first or last. */
    sealed interface Turn {
        data class By(val delta: Int) : Turn
        data object First : Turn
        data object Last : Turn
    }

    /** The keys that turn a page (pedals send arrows or Page Up/Down), named as the web names them. */
    fun keyTurn(key: String, shift: Boolean = false): Turn? = when (key) {
        "ArrowRight", "ArrowDown", "PageDown" -> Turn.By(1)
        "ArrowLeft", "ArrowUp", "PageUp" -> Turn.By(-1)
        " ", "Spacebar" -> Turn.By(if (shift) -1 else 1)
        "Home" -> Turn.First
        "End" -> Turn.Last
        else -> null
    }

    /** "12 of 140", or "12–13 of 140" for a spread. */
    fun pageLabel(page: Int, per: Int, count: Int): String {
        val a = page + 1
        val b = minOf(count, page + per)
        return if (b > a) "$a–$b of $count" else "$a of $count"
    }

    /** Positions kept per script: newest first, at most [keep]; an update keeps what it does not name. */
    fun remember(
        store: Map<String, Map<String, String?>>,
        scriptId: String,
        entry: Map<String, String?>,
        keep: Int = 60,
    ): LinkedHashMap<String, Map<String, String?>> {
        val out = LinkedHashMap<String, Map<String, String?>>()
        out[scriptId] = (store[scriptId] ?: emptyMap()) + entry
        for ((k, v) in store) if (k != scriptId && out.size < keep) out[k] = v
        return out
    }
}
