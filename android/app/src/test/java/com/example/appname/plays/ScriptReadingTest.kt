package com.example.appname.plays

import java.io.File
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The script reader's arithmetic and reading (Decision 076 S0 and S1), the port of js/reader.test.js: the golden
 * headings every stack runs (catalog/tests/golden/script_sections.json), contents over real scripts (the bundle, and a
 * spread of catalog/out/plays-library when built; never a pinned title), search, a part's next line, open parts, the
 * page arithmetic, the position kept across a re-layout, and the runs marks will anchor to.
 *
 * Seen to fail, 2026-11-14, each mutation run once then restored: lineAtPage taking the line that starts on the page
 * (`the line a page shows first is the one carried over`), contentsOf without the same-act rule (`contents - an act
 * heading that repeats the act`), sectionLevel without the part pattern (the golden, and that contents case), and
 * runsOf not counting the space between pieces (`runs - every printed run maps back`).
 */
class ScriptReadingTest {
    private fun root(): File {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            if (File(dir, "catalog/tests/golden/script_sections.json").exists()) return dir
            dir = dir.parentFile
        }
        error("repository root not found")
    }

    private val bundle: List<PlayScript> by lazy { CastableLibrary.decode(File(root(), "catalog/plays/castable-scripts.json").readText()).scripts }
    private val libDir get() = File(root(), "catalog/out/plays-library")
    private val libIndex: PlayIndex? by lazy { File(libDir, "index.json").takeIf { it.exists() }?.let { PlayIndex.decode(it.readText()) } }

    /** Library scripts that are on disk, spread across the index, never named. */
    private fun library(): List<Pair<PlayRow, PlayScript>> {
        val index = libIndex ?: return emptyList()
        return index.plays.mapNotNull { row ->
            File(libDir, row.path).takeIf { it.exists() }?.let { row to PlayScriptFile.decode(it.readText()).scripts.first() }
        }
    }

    private fun speech(id: String, role: String, say: String) = ScriptLine(id, ScriptLine.Kind.Speech, role = role, parts = listOf(LinePart.Say(say)))
    private fun direction(id: String, source: String) = ScriptLine(id, ScriptLine.Kind.Direction, source = source)
    private fun script(lines: List<ScriptLine>, sections: List<ScriptSection> = emptyList()) =
        fixtureScript().copy(lines = lines, sections = sections)

    @Test fun `section headings - the golden cases every stack runs`() {
        val g = Json.parseToJsonElement(File(root(), "catalog/tests/golden/script_sections.json").readText()).jsonObject
        val cases = g["cases"]!!.jsonArray
        assertTrue(cases.size > 20)
        for (c in cases) {
            val o = c.jsonObject
            val text = o["text"]!!.jsonPrimitive.content
            val level = o["level"]!!.jsonPrimitive.contentOrNull
            val want = when (level) { "act" -> ScriptReading.Level.Act; "scene" -> ScriptReading.Level.Scene; "part" -> ScriptReading.Level.Part; else -> null }
            assertEquals("level of $text", want, ScriptReading.sectionLevel(text))
            o["title"]?.jsonPrimitive?.contentOrNull?.let { assertEquals("title of $text", it, ScriptReading.sectionTitle(text)) }
            o["act"]?.jsonPrimitive?.contentOrNull?.let { assertEquals("act of $text", it, ScriptReading.actKey(text)) }
        }
    }

    @Test fun `contents - an act heading that repeats the act is its scene, an epilogue stands alone`() {
        val s = script(
            listOf(
                speech("L0001", "A", "Before anything."), direction("L0002", "SCENE I. A road."),
                speech("L0003", "A", "One."), speech("L0004", "A", "Two."),
                direction("L0005", "ACT I. SCENE II. The same."), speech("L0006", "A", "Three."), speech("L0007", "A", "Four."),
                direction("L0008", "_Enter_ B."), speech("L0009", "A", "Five."),
            ),
            listOf(ScriptSection("L0004", "ACT I."), ScriptSection("L0007", "ACT II."), ScriptSection("L0009", "EPILOGUE")),
        )
        val secs = ScriptReading.sectionsOf(s)
        assertEquals(
            listOf(Triple("L0002", ScriptReading.Level.Scene, true), Triple("L0004", ScriptReading.Level.Act, false), Triple("L0005", ScriptReading.Level.Scene, true),
                Triple("L0007", ScriptReading.Level.Act, false), Triple("L0009", ScriptReading.Level.Part, false)),
            secs.map { Triple(it.line, it.level, it.isLine) },
        )
        val toc = ScriptReading.contentsOf(s)
        assertEquals(
            listOf("SCENE I. A road." to emptyList(), "ACT I." to listOf("ACT I. SCENE II. The same."), "ACT II." to emptyList(), "EPILOGUE" to emptyList()),
            toc.map { it.title to it.scenes.map { sc -> sc.title } },
        )
        val place = ScriptReading.placeOf(s, 4)
        assertEquals(listOf("ACT I.", "ACT I. SCENE II. The same."), listOf(place.act!!.title, place.scene!!.title))
        assertNull(ScriptReading.placeOf(s, 0).act)
        assertTrue(ScriptReading.contentsOf(script(listOf(speech("L0001", "A", "x")))).isEmpty())
    }

    @Test fun `contents - a printed list of the acts before the play is left out`() {
        val s = script(
            listOf(
                direction("L0001", "ACT I.—“Shot in the back.”"), direction("L0002", "ACT II.—“After Taps.”"),
                direction("L0003", "ACT III.—“Home Again.”"), direction("L0004", "SCENE.—A room."),
                speech("L0005", "A", "Hello."), speech("L0006", "A", "Goodbye."),
            ),
            listOf(ScriptSection("L0004", "ACT I.")),
        )
        assertEquals(listOf("ACT I."), ScriptReading.contentsOf(s).map { it.title })
        assertTrue(ScriptReading.sectionsOf(script(listOf(speech("L0001", "A", "x"), direction("L0002", "ACT II.")))).isEmpty())
    }

    @Test fun `contents over real scripts - every section lands on a line, in order, scenes inside their acts`() {
        val picked = bundle + library().map { it.second }
        assertTrue(picked.size >= 15)
        var withContents = 0
        var setAside = 0
        for (s in picked) {
            val ids = s.lines.map { it.id }.toSet()
            val secs = ScriptReading.sectionsOf(s)
            secs.forEachIndexed { i, x ->
                assertTrue("${s.id}: a line that exists", x.line in ids)
                assertEquals("${s.id}: index matches", x.line, s.lines[x.index].id)
                assertTrue("${s.id}: a heading line is never a speech", !x.isLine || s.lines[x.index].kind != ScriptLine.Kind.Speech)
                assertTrue("${s.id}: a one-line title", x.title.isNotEmpty() && '\n' !in x.title && '_' !in x.title)
                if (i > 0) assertTrue("${s.id}: in reading order", secs[i - 1].index <= x.index)
                if (!x.isLine) setAside++
            }
            val toc = ScriptReading.contentsOf(s)
            if (toc.isNotEmpty()) withContents++
            toc.forEachIndexed { k, t ->
                val next = if (k + 1 < toc.size) toc[k + 1].index else Int.MAX_VALUE
                t.scenes.forEach { sc -> assertTrue("${s.id}: ${sc.title} inside ${t.title}", sc.index >= t.index && sc.index <= next) }
            }
            assertEquals("${s.id}: every section in the contents once", secs.size, toc.sumOf { 1 + it.scenes.size })
        }
        assertTrue(withContents > 0)
        if (libIndex != null) assertTrue("the library carries headings the parser set aside", setAside > 0)
    }

    @Test fun `search - case, accents, curly quotes and line breaks fold, with their words around them`() {
        val s = script(
            listOf(
                ScriptLine("L0001", ScriptLine.Kind.Speech, role = "ANNE", parts = listOf(LinePart.Say("I don’t know the CAFÉ"), LinePart.Direction("aside"), LinePart.Say("on the\ncorner."))),
                direction("L0002", "_Enter_ the waiter."), speech("L0003", "BEN", "The cafe is shut. Don't go."),
            ),
        )
        val r = ScriptReading.search(s, "don't")
        assertEquals(2, r.total)
        assertEquals(listOf("L0001" to "don’t", "L0003" to "Don't"), r.hits.map { it.line to it.match })
        assertEquals(listOf("ANNE", "BEN"), r.hits.map { it.role })
        assertEquals(listOf("L0001", "L0003"), ScriptReading.search(s, "café").hits.map { it.line })
        assertEquals(listOf("the corner"), ScriptReading.search(s, "the corner").hits.map { it.match })
        assertEquals(0, ScriptReading.search(s, "w").total)
        assertEquals(1, ScriptReading.search(s, "the", limit = 1).hits.size)
        assertEquals(3, ScriptReading.search(s, "the", limit = 1).total)
        val h = ScriptReading.search(s, "shut").hits[0]
        assertEquals("The cafe is shut. Don't go.", h.before + h.match + h.after)
        val real = bundle[0]
        val word = ScriptReading.lineText(real.lines.first { it.kind == ScriptLine.Kind.Speech }).split(Regex("\\s+")).first { it.length > 4 }
        assertTrue("a word from a real script is found ($word)", ScriptReading.search(real, word).total >= 1)
    }

    @Test fun `a part's next and previous line, and the open speaking parts`() {
        val s = script(
            listOf(speech("L1", "A", "x"), speech("L2", "B", "x"), direction("L3", "x"), speech("L4", "A", "x"), ScriptLine("L5", ScriptLine.Kind.Sound, source = "BELL")),
        )
        val a = PartID.role("A")
        assertEquals(listOf(0, 3, -1), listOf(ScriptReading.nextLineOf(s, a, -1), ScriptReading.nextLineOf(s, a, 0), ScriptReading.nextLineOf(s, a, 3)))
        assertEquals(listOf(0, -1), listOf(ScriptReading.nextLineOf(s, a, 3, -1), ScriptReading.nextLineOf(s, a, 0, -1)))
        assertEquals(listOf("role:A", "role:B"), ScriptReading.openSpeakingParts(emptyMap(), s))
        assertEquals(listOf("role:B"), ScriptReading.openSpeakingParts(mapOf("role:A" to "done"), s))
        assertEquals(emptyList<String>(), ScriptReading.openSpeakingParts(mapOf("directions" to "open", "sound" to "open"), null))
    }

    @Test fun `an index row and its full script count the same voices, minutes and cast`() {
        val s = bundle[0]
        assertEquals(s.castParts.filter { it.id.isSpeaking }.map { it.lineCount }, s.cast)
        val row = PlayRow.of(s)
        assertEquals(listOf(s.voices, s.minutes, s.cast), listOf(row.voices, row.minutes, row.cast))
        val index = libIndex ?: return
        val byId = index.plays.associateBy { it.id }
        var compared = 0
        for (b in bundle) {
            val r = byId[b.id] ?: error("${b.id} in the library")
            // The library was rebuilt since the bundle: a play whose text changed has a new revision and is not the same count.
            if (r.revision != b.revision) continue
            compared++
            assertEquals("${b.id}: voices", r.voices, b.voices)
            assertEquals("${b.id}: cast", r.cast, b.cast)
        }
        assertTrue("some bundled play is the library's same text ($compared)", compared > 0)
    }

    @Test fun `ReaderMath - settings default to pages and unknown values fall back`() {
        assertEquals(ReaderPrefs("pages", ReaderMath.DEFAULT_SIZE, "normal"), ReaderMath.normalizePrefs(null, null, null))
        assertEquals(ReaderPrefs("scroll", 6, "loose"), ReaderMath.normalizePrefs("scroll", 6, "loose"))
        assertEquals(ReaderPrefs("pages", ReaderMath.DEFAULT_SIZE, "normal"), ReaderMath.normalizePrefs("curl", 99, "huge"))
        assertEquals(1f, ReaderMath.SIZES[ReaderMath.DEFAULT_SIZE])
    }

    @Test fun `ReaderMath - the line a page shows first is the one carried over`() {
        val starts = intArrayOf(0, 0, 1, 2)
        val ends = intArrayOf(0, 1, 1, 4)
        assertEquals(listOf(0, 1, 3, 3, 3), (0..4).map { ReaderMath.lineAtPage(starts, ends, it) })
        assertEquals(-1, ReaderMath.lineAtPage(IntArray(0), IntArray(0), 0))
    }

    @Test fun `ReaderMath - turns, spreads, swipes, taps and keys`() {
        assertEquals(listOf(1, 1, 2, 2, 2), listOf(834f, 859f, 860f, 951f, 1440f).map { ReaderMath.perSpread(it) })
        assertEquals(listOf(0, 1, 9), listOf(ReaderMath.turn(0, -1, 1, 10), ReaderMath.turn(0, 1, 1, 10), ReaderMath.turn(9, 1, 1, 10)))
        assertEquals(listOf(2, 4, 8, 8), listOf(ReaderMath.turn(0, 1, 2, 9), ReaderMath.turn(3, 1, 2, 9), ReaderMath.turn(7, 1, 2, 9), ReaderMath.turn(8, 1, 2, 9)))
        assertEquals(
            listOf(1, -1, 1, 0, 0),
            listOf(ReaderMath.swipeTurn(-90f, 400f, 375f), ReaderMath.swipeTurn(90f, 400f, 375f), ReaderMath.swipeTurn(-40f, 60f, 375f), ReaderMath.swipeTurn(-40f, 400f, 375f), ReaderMath.swipeTurn(-10f, 5f, 375f)),
        )
        assertEquals(
            listOf(ReaderMath.Zone.Prev, ReaderMath.Zone.Middle, ReaderMath.Zone.Next),
            listOf(ReaderMath.tapZone(10f, 375f), ReaderMath.tapZone(200f, 375f), ReaderMath.tapZone(370f, 375f)),
        )
        assertEquals(
            listOf(ReaderMath.Turn.By(1), ReaderMath.Turn.By(-1), ReaderMath.Turn.By(1), ReaderMath.Turn.By(-1), ReaderMath.Turn.By(1), ReaderMath.Turn.First, null),
            listOf("ArrowRight", "PageUp", " ", "Shift ", "ArrowDown", "Home", "a").map { if (it == "Shift ") ReaderMath.keyTurn(" ", true) else ReaderMath.keyTurn(it) },
        )
        assertEquals(listOf("1 of 140", "11–12 of 140", "139 of 139"), listOf(ReaderMath.pageLabel(0, 1, 140), ReaderMath.pageLabel(10, 2, 140), ReaderMath.pageLabel(138, 2, 139)))
    }

    @Test fun `ReaderMath - the reading position survives a re-layout, text size up then down`() {
        val aStarts = intArrayOf(0, 0, 1, 1, 2, 2)
        val aEnds = intArrayOf(0, 0, 1, 1, 2, 2)
        val bStarts = intArrayOf(0, 1, 2, 3, 5, 6)
        val bEnds = intArrayOf(0, 1, 2, 4, 5, 6)
        val at = ReaderMath.lineAtPage(aStarts, aEnds, 1)
        assertEquals(2, at)
        val pageB = bStarts[at]
        assertEquals(at, ReaderMath.lineAtPage(bStarts, bEnds, pageB))
        assertEquals(1, aStarts[ReaderMath.lineAtPage(bStarts, bEnds, pageB)])
        val spread = ReaderMath.spreadStart(bStarts[3], 2)
        assertTrue(spread <= bStarts[3] && bStarts[3] < spread + 2)
    }

    @Test fun `ReaderMath - remembered positions, newest first, capped`() {
        var st: Map<String, Map<String, String?>> = emptyMap()
        for (i in 0 until 70) st = ReaderMath.remember(st, "s$i", mapOf("line" to "L0001"))
        assertEquals(60, st.size)
        assertEquals("s69", st.keys.first())
        st = ReaderMath.remember(st, "s10", mapOf("part" to "role:A"))
        assertEquals(listOf("s10", "L0001", "role:A"), listOf(st.keys.first(), st["s10"]!!["line"], st["s10"]!!["part"]))
    }

    @Test fun `ReaderStore keeps the web's JSON`() {
        assertEquals(ReaderPrefs("scroll", 4, "tight"), ReaderStore.decodePrefs("""{"layout":"scroll","size":4,"spacing":"tight"}"""))
        assertEquals(ReaderPrefs(), ReaderStore.decodePrefs("not json"))
        assertEquals(ReaderPrefs(), ReaderStore.decodePrefs("""{"layout":"curl","size":"9"}"""))
        assertEquals(ReaderPrefs("scroll", 4, "tight"), ReaderStore.decodePrefs(ReaderStore.encodePrefs(ReaderPrefs("scroll", 4, "tight"))))
        val pos = linkedMapOf<String, Map<String, String?>>("a" to mapOf("line" to "L1", "part" to null), "b" to mapOf("line" to "L2", "part" to "role:X"))
        val back = ReaderStore.decodePositions(ReaderStore.encodePositions(pos))
        assertEquals(pos, back)
        assertEquals(listOf("a", "b"), back.keys.toList())
    }

    @Test fun `runs - every printed run maps back to its line's words`() {
        val picked = bundle + library().map { it.second }
        var n = 0
        for (s in picked) for (line in s.lines) {
            val text = ScriptReading.lineText(line)
            for (r in ScriptReading.runsOf(line)) {
                n++
                assertEquals("${s.id} ${line.id}: run at ${r.at}", r.text, text.substring(r.at, r.at + r.text.length))
            }
        }
        assertTrue("runs checked ($n)", n > 1000)
        assertEquals(
            listOf(Triple(ScriptReading.RunKind.Em, "Enter", 1), Triple(ScriptReading.RunKind.Plain, " BEN, ", 7), Triple(ScriptReading.RunKind.Em, "slowly", 14), Triple(ScriptReading.RunKind.Plain, ".", 21)),
            ScriptReading.runsOf(direction("D", "_Enter_ BEN, _slowly_.")).map { Triple(it.kind, it.text, it.at) },
        )
        val speechLine = ScriptLine("S", ScriptLine.Kind.Speech, role = "A", parts = listOf(LinePart.Say("Hello"), LinePart.Direction("Looks at_ POLLY"), LinePart.Say(". Go.")))
        assertEquals(
            listOf(listOf("Say", "Hello", 0, true), listOf("Aside", "Looks at", 6, false), listOf("Plain", " POLLY", 15, false), listOf("Say", ". Go.", 22, true)),
            ScriptReading.runsOf(speechLine).map { listOf(it.kind.name, it.text, it.at, it.said) },
        )
        assertEquals(
            listOf(true, false, false, false),
            listOf(ScriptReading.spaceBetween("born.", "laughing"), ScriptReading.spaceBetween("laughing", ". Same"), ScriptReading.spaceBetween("(", "x"), ScriptReading.spaceBetween("a", ", b")),
        )
    }
}
