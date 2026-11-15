package com.example.appname.plays

import java.io.File
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Marks in the script reader (PLAYS-DESIGN §2.10; Decision 076 S5), the cases of js/marks.test.js over the Kotlin port:
 * the golden file every stack runs (catalog/tests/golden/marks_anchor.json: snap, point, anchor), the offsets every drawn
 * run keeps (with verse, emphasis and a run-in speaker), a selection, overlap, groups, the notebook order, a real script
 * through a new revision and a split line, storage under the script id (a fake DAO: unreadable reads as none, a bad kind
 * dropped, a failed write reported) and the export rows.
 *
 * Seen to fail, 2026-11-15, against mutated copies: `place` without the evidence floor (the short word is guessed into another
 * line), `bestIn` without the context score (the second "no" lands on the first), `add` with `<` for `<=` (adjacent highlights
 * stay two), `remove` ignoring the group, and PlayPage.layoutOf's verse rows without `at += lead` (the verse offsets case).
 */
class MarksCoreTest {
    private val json = Json { ignoreUnknownKeys = true }

    private fun root(): File {
        var dir: File? = File("").absoluteFile
        while (dir != null && !File(dir, "catalog/plays/castable-scripts.json").exists()) dir = dir.parentFile
        return dir!!
    }

    private val golden: JsonObject by lazy { json.parseToJsonElement(File(root(), "catalog/tests/golden/marks_anchor.json").readText()).jsonObject }
    private val bundle: List<PlayScript> by lazy { CastableLibrary.decode(File(root(), "catalog/plays/castable-scripts.json").readText()).scripts }

    private fun scriptOf(o: JsonObject, id: String): PlayScript {
        val body = JsonObject(
            o + mapOf(
                "id" to kotlinx.serialization.json.JsonPrimitive(id), "kind" to kotlinx.serialization.json.JsonPrimitive("radio"),
                "title" to kotlinx.serialization.json.JsonPrimitive("Test"),
                "source" to json.parseToJsonElement("""{"name":"t","url":"https://example.org"}"""),
                "rights" to json.parseToJsonElement("""{"bucket":"x"}"""),
            ),
        )
        return json.decodeFromString(PlayScript.serializer(), body.toString())
    }

    private fun speech(id: String, role: String, vararg say: String) =
        ScriptLine(id, ScriptLine.Kind.Speech, role = role, parts = say.map { LinePart.Say(it) })

    private fun script(id: String, revision: String, vararg lines: ScriptLine) = PlayScript(
        id = id, revision = revision, kind = "radio", title = "Test", source = PlayScript.Source("t", "https://example.org"),
        rights = PlayScript.Rights("x"), lines = lines.toList(),
    )

    // MARK: The golden cases

    @Test fun `golden - a selection grows to whole words, and space alone is nothing`() {
        val cases = golden["snap"]!!.jsonArray
        assertTrue(cases.size >= 5)
        for (c in cases) {
            val o = c.jsonObject
            val text = o["text"]!!.jsonPrimitive.content
            val got = MarksCore.snapWords(text, o["start"]!!.jsonPrimitive.int, o["end"]!!.jsonPrimitive.int)
            val want = (o["want"] as? JsonArray)?.map { it.jsonPrimitive.int }
            assertEquals("snap '$text' $o", want, got?.let { listOf(it.first, it.last + 1) })
        }
    }

    @Test fun `golden - a point mark goes after its word and the punctuation that follows`() {
        for (c in golden["point"]!!.jsonArray) {
            val o = c.jsonObject
            val text = o["text"]!!.jsonPrimitive.content
            assertEquals("point '$text' $o", o["want"]!!.jsonPrimitive.int, MarksCore.pointAfter(text, o["end"]!!.jsonPrimitive.int))
        }
    }

    @Test fun `golden - re-anchoring a revision (same line, a split id, context, lost, nearest line)`() {
        val cases = golden["anchor"]!!.jsonArray
        assertTrue(cases.size >= 8)
        for (c in cases) {
            val o = c.jsonObject
            val name = o["name"]!!.jsonPrimitive.content
            val before = scriptOf(o["before"]!!.jsonObject, "s")
            val after = scriptOf(o["after"]!!.jsonObject, "s")
            val mk = o["mark"]!!.jsonObject
            val m = MarksCore.make(before, mk["line"]!!.jsonPrimitive.content, mk["start"]!!.jsonPrimitive.int, mk["end"]!!.jsonPrimitive.int, mk["kind"]!!.jsonPrimitive.content, now = 1000)
            assertTrue("$name: made", m != null)
            val r = MarksCore.place(after, listOf(m!!))
            val want = o["want"]!!
            if (want is kotlinx.serialization.json.JsonPrimitive) {
                assertEquals("$name: not placed", 0, r.placed.size)
                assertEquals("$name: kept exactly as stored", listOf(m), r.lost)
            } else {
                assertEquals("$name: placed", 0, r.lost.size)
                val p = r.placed[0]
                val w = want.jsonArray
                assertEquals(name, listOf(w[0].jsonPrimitive.content, w[1].jsonPrimitive.int, w[2].jsonPrimitive.int), listOf(p.line, p.start, p.end))
                val line = after.lines.first { it.id == p.line }
                assertEquals("$name: still the same words", m.text, ScriptReading.lineText(line).substring(p.start, p.end))
                assertEquals("$name: takes the new revision", after.revision, p.revision)
            }
        }
    }

    // MARK: Offsets: every drawn run maps back into lineText

    private fun same(a: String, b: String) = a.replace(Regex("[\\s ]"), " ") == b.replace(Regex("[\\s ]"), " ")

    private fun drawn(line: ScriptLine, roles: List<String>): List<PageRun> {
        val lay = PlayPage.layoutOf(line, roles)
        if (line.kind != ScriptLine.Kind.Speech || line.parts == null) return lay.rows.flatMap { it.runs }
        return lay.speeches.flatMap { s -> listOfNotNull(s.name) + s.rows.flatMap { it.runs } }
    }

    private fun checkOffsets(script: PlayScript, tag: String): Int {
        val roles = script.roles.map { it.name }
        var runs = 0
        for (line in script.lines) {
            val lt = ScriptReading.lineText(line)
            for (r in drawn(line, roles)) {
                runs++
                val claimed = lt.substring(minOf(r.at, lt.length), minOf(r.at + r.text.length, lt.length))
                assertTrue("$tag ${line.id}: a run at ${r.at} draws '${r.text}' but the line holds '$claimed'", same(claimed, r.text))
            }
        }
        return runs
    }

    @Test fun `offsets - every run layoutOf draws over every bundled script maps back into lineText`() {
        var n = 0
        for (s in bundle) n += checkOffsets(s, s.id)
        assertTrue("runs checked ($n)", n > 5000)
    }

    @Test fun `offsets - verse rows keep their offsets, an indented half line too`() {
        val l = speech("L0001", "CAPTAIN", "Doubtful it stood;\nAs two spent swimmers, that do cling together\n    And choke their art.")
        val s = script("v", "r1", l)
        assertTrue(PlayPage.layoutOf(l, listOf("CAPTAIN")).verse)
        checkOffsets(s, "fixture")
        assertEquals(listOf(false, false, true), PlayPage.layoutOf(l, listOf("CAPTAIN")).speeches[0].rows.map { it.indent })
        var verse = 0
        for (b in bundle) for (line in b.lines) {
            if (line.kind == ScriptLine.Kind.Speech && PlayPage.layoutOf(line, emptyList()).verse) {
                verse++
                checkOffsets(script(b.id, b.revision, line), b.id)
            }
        }
        assertTrue("the bundle holds verse", verse > 0)
    }

    @Test fun `offsets - emphasis and a run-in speaker keep their offsets`() {
        val s = script(
            "e", "r1",
            ScriptLine("L0001", ScriptLine.Kind.Speech, role = "CHARTERIS", parts = listOf(LinePart.Say("It is the first in which"), LinePart.Direction("I"), LinePart.Say("have been serious."))),
            ScriptLine("L0002", ScriptLine.Kind.Speech, role = "CHARTERIS", em = listOf(1), parts = listOf(LinePart.Say("I believe it"), LinePart.Say("is"), LinePart.Say("a very pleasant state."))),
            ScriptLine("L0003", ScriptLine.Kind.Speech, role = "CHARTERIS", parts = listOf(LinePart.Say("Of course. Why not?\nGRACE"), LinePart.Direction("reflecting"), LinePart.Say(". Never mind _why_."))),
        )
        val roles = listOf("CHARTERIS", "GRACE")
        for (line in s.lines) for (r in drawn(line, roles)) {
            val lt = ScriptReading.lineText(line)
            assertTrue("${line.id} run '${r.text}' at ${r.at}", same(lt.substring(r.at, r.at + r.text.length), r.text))
        }
        assertEquals(listOf("CHARTERIS", "GRACE"), PlayPage.layoutOf(s.lines[2], roles).speeches.map { it.role })
        val em = drawn(s.lines[2], roles).first { it.kind == ScriptReading.RunKind.Em }
        assertEquals("why", ScriptReading.lineText(s.lines[2]).substring(em.at, em.at + em.text.length))
    }

    // MARK: A selection

    private val play = script(
        "gut-test", "r1",
        speech("L0001", "A", "Yes--the first thing tomorrow morning, and then we go."),
        ScriptLine("L0002", ScriptLine.Kind.Direction, source = "[He crosses to the window.]"),
        speech("L0003", "B", "It is cold out there."),
    )
    private val t1 = ScriptReading.lineText(play.lines[0])

    @Test fun `a selection - span marks grow to words, a point mark goes after the last word, a note anchors to its first line`() {
        val h = MarksCore.fromSelection(play, listOf(Piece("L0001", 11, 17)), "highlight", MarkExtra(hue = "green"), 5).single()
        assertEquals(listOf(9, 20, "first thing", "green", "r1"), listOf(h.start, h.end, h.text, h.hue, h.revision))
        assertEquals("Yes--the ", h.prefix)
        assertEquals(t1.substring(20, 52), h.suffix)
        val b = MarksCore.fromSelection(play, listOf(Piece("L0001", 30, 33)), "breath", now = 5).single()
        assertEquals(listOf(38, 38, ""), listOf(b.start, b.end, b.text))
        val across = listOf(Piece("L0001", 47, t1.length), Piece("L0002", 0, 10), Piece("L0003", 0, 5))
        val hs = MarksCore.fromSelection(play, across, "underline", now = 5)
        assertEquals(listOf("L0001", "L0002", "L0003"), hs.map { it.line })
        assertTrue(hs[0].group != null && hs.all { it.group == hs[0].group })
        val ns = MarksCore.fromSelection(play, across, "note", MarkExtra(note = "warm"), 5)
        assertEquals(listOf(Triple("L0001", "warm", null as String?)), ns.map { Triple(it.line, it.note, it.group) })
        val p = MarksCore.fromSelection(play, across, "pause", now = 5).single()
        assertEquals(listOf("L0003", 5), listOf(p.line, p.start))
        val beat = MarksCore.fromSelection(play, listOf(Piece("L0003", 0, 2)), "beat", MarkExtra(label = "  the turn, a long label past the limit "), 5).single()
        assertEquals("the turn, a long label p", beat.label)
        assertEquals(emptyList<Mark>(), MarksCore.fromSelection(play, listOf(Piece("L0001", 8, 9)), "highlight"))
        assertEquals(emptyList<Mark>(), MarksCore.fromSelection(play, listOf(Piece("L9999", 0, 3)), "highlight"))
    }

    // MARK: Overlap

    private fun mk(line: String, s: Int, e: Int, kind: String, extra: MarkExtra = MarkExtra(), now: Long = 1000) = MarksCore.make(play, line, s, e, kind, extra, now)

    @Test fun `overlap - highlights merge (overlapping or touching) into one in the new hue, notes never merge`() {
        var ms = emptyList<Mark>()
        ms = MarksCore.add(play, ms, mk("L0001", 9, 14, "highlight", MarkExtra(hue = "yellow")))
        ms = MarksCore.add(play, ms, mk("L0001", 21, 29, "highlight", MarkExtra(hue = "blue")))
        ms = MarksCore.add(play, ms, mk("L0001", 12, 20, "highlight", MarkExtra(hue = "pink")))
        assertEquals(listOf(Triple(9, 20, "pink"), Triple(21, 29, "blue")), MarksCore.order(play, ms).filter { it.kind == "highlight" }.map { Triple(it.start, it.end, it.hue) })
        assertEquals(t1.substring(9, 20), ms.first { it.hue == "pink" }.text)
        ms = MarksCore.add(play, ms, mk("L0001", 20, 21, "highlight", MarkExtra(hue = "green")))
        assertEquals(listOf(Triple(9, 29, "green")), ms.filter { it.kind == "highlight" }.map { Triple(it.start, it.end, it.hue) })
        ms = MarksCore.add(play, ms, mk("L0001", 9, 14, "underline"))
        ms = MarksCore.add(play, ms, mk("L0001", 14, 20, "underline"))
        assertEquals(listOf(9 to 20), ms.filter { it.kind == "underline" }.map { it.start to it.end })
        assertEquals(1, ms.count { it.kind == "highlight" })
        ms = MarksCore.add(play, ms, mk("L0001", 9, 14, "note", MarkExtra(note = "a")))
        ms = MarksCore.add(play, ms, mk("L0001", 9, 14, "note", MarkExtra(note = "b")))
        assertEquals(2, ms.count { it.kind == "note" })
        ms = MarksCore.add(play, ms, mk("L0003", 0, 2, "highlight"))
        assertEquals(2, ms.count { it.kind == "highlight" })
    }

    @Test fun `overlap - one point mark a place, a pause replaces a breath, a breath elsewhere stays`() {
        var ms = emptyList<Mark>()
        ms = MarksCore.add(play, ms, mk("L0001", 38, 38, "breath"))
        ms = MarksCore.add(play, ms, mk("L0001", 47, 47, "breath"))
        ms = MarksCore.add(play, ms, mk("L0001", 9, 20, "highlight"))
        ms = MarksCore.add(play, ms, mk("L0001", 38, 38, "pause"))
        assertEquals(listOf("breath" to 47, "pause" to 38).sortedBy { it.first }, ms.filter { it.kind !in MarksCore.SPAN }.map { it.kind to it.start }.sortedBy { it.first })
        ms = MarksCore.add(play, ms, mk("L0001", 38, 38, "beat", MarkExtra(label = "turn")))
        assertEquals(listOf("beat" to "turn"), ms.filter { it.start == 38 && it.kind !in MarksCore.SPAN }.map { it.kind to it.label })
        assertEquals(1, ms.count { it.kind == "highlight" })
    }

    @Test fun `remove and update - a group goes together, a hue changes for the group, undo restores what was removed`() {
        val across = listOf(Piece("L0001", 47, t1.length), Piece("L0003", 0, 5))
        var ms = MarksCore.fromSelection(play, across, "highlight", MarkExtra(hue = "yellow")).fold(emptyList<Mark>()) { a, m -> MarksCore.add(play, a, m) }
        ms = MarksCore.add(play, ms, mk("L0002", 1, 3, "highlight"))
        ms = MarksCore.update(ms, ms[0].id, MarkPatch(hue = "blue"))
        assertEquals(listOf("blue", "blue", "yellow"), ms.map { it.hue })
        val r = MarksCore.remove(ms, ms[1].id)
        assertEquals(1, r.marks.size)
        assertEquals(2, r.removed.size)
        assertEquals(3, (r.marks + r.removed).size)
        var n = listOf(mk("L0003", 0, 2, "note", MarkExtra(note = "x"))!!, mk("L0003", 0, 2, "beat", MarkExtra(label = "a"))!!)
        n = MarksCore.update(n, n[0].id, MarkPatch(note = "cold, say it cold"))
        n = MarksCore.update(n, n[1].id, MarkPatch(label = "shift"))
        assertEquals(listOf("cold, say it cold", "shift"), n.map { it.note ?: it.label })
    }

    @Test fun `a tap on words - the narrowest span mark under the offset, a note first`() {
        val ms = listOf(mk("L0001", 0, 40, "highlight")!!, mk("L0001", 9, 20, "underline")!!, mk("L0001", 9, 20, "note")!!, mk("L0001", 38, 38, "breath")!!)
        assertEquals(listOf("note", "underline", "highlight"), MarksCore.at(ms, "L0001", 10).map { it.kind })
        assertEquals(listOf("highlight"), MarksCore.at(ms, "L0001", 38).map { it.kind })
        assertEquals(emptyList<Mark>(), MarksCore.at(ms, "L0003", 1))
    }

    @Test fun `the notebook order - script order, lost marks apart, placing again changes nothing`() {
        val ms = listOf(mk("L0003", 3, 5, "underline")!!, mk("L0001", 38, 38, "breath")!!, mk("L0001", 9, 20, "highlight")!!, mk("L0002", 1, 3, "note")!!)
        assertEquals(listOf("L0001:9", "L0001:38", "L0002:1", "L0003:3"), MarksCore.order(play, ms).map { "${it.line}:${it.start}" })
        val next = script("gut-test", "r2", play.lines[0], speech("L0003", "B", "Warm in here."))
        val r = MarksCore.place(next, ms)
        assertEquals(listOf("breath", "highlight"), r.placed.map { it.kind }.sorted())
        assertEquals(listOf("L0002", "L0003"), r.lost.map { it.line }.sorted())
        assertTrue(r.changed)
        val again = MarksCore.place(next, r.placed)
        assertTrue(!again.changed && again.lost.isEmpty())
    }

    @Test fun `re-anchoring over a real script - marks survive the same text under a new revision, and a split line`() {
        val s = bundle.first { it.lines.size > 300 }
        val ms = ArrayList<Mark>()
        var i = 5
        while (i < s.lines.size) {
            val lt = ScriptReading.lineText(s.lines[i])
            val w = MarksCore.snapWords(lt, lt.length / 3, lt.length / 3 + 6)
            if (w != null) MarksCore.make(s, s.lines[i].id, w.first, w.last + 1, "highlight")?.let { ms += it }
            i += 37
        }
        assertTrue("marks made (${ms.size})", ms.size > 5)
        val next = s.copy(revision = "${s.revision}-next")
        val r = MarksCore.place(next, ms)
        assertEquals(0, r.lost.size)
        assertEquals(ms.map { it.line to it.start }, r.placed.map { it.line to it.start })
        val target = ms[2]
        val k = s.lines.indexOfFirst { it.id == target.line }
        val lt = ScriptReading.lineText(s.lines[k])
        val cut = target.start
        val split = s.copy(
            revision = "split",
            lines = s.lines.take(k) + listOf(
                ScriptLine(target.line, ScriptLine.Kind.Direction, source = lt.take(cut).trim().ifEmpty { "[...]" }),
                ScriptLine("${target.line}a", ScriptLine.Kind.Direction, source = lt.substring(cut)),
            ) + s.lines.drop(k + 1),
        )
        val r2 = MarksCore.place(split, listOf(target))
        assertEquals(listOf(Triple("${target.line}a", 0, target.text)), r2.placed.map { Triple(it.line, it.start, it.text) })
    }

    // MARK: On the device

    private class FakeDao(var failWrite: Boolean = false, var failRead: Boolean = false) : MarkDao() {
        val rows = ArrayList<MarkEntity>()
        override suspend fun marksFor(scriptId: String): List<MarkEntity> {
            if (failRead) throw IllegalStateException("unreadable")
            return rows.filter { it.scriptId == scriptId }
        }
        override suspend fun all(): List<MarkEntity> {
            if (failRead) throw IllegalStateException("unreadable")
            return rows.toList()
        }
        override suspend fun deleteFor(scriptId: String) {
            if (failWrite) throw IllegalStateException("disk full")
            rows.removeAll { it.scriptId == scriptId }
        }
        override suspend fun insertAll(rows: List<MarkEntity>) {
            if (failWrite) throw IllegalStateException("disk full")
            this.rows += rows
        }
    }

    @Test fun `storage - per script, unreadable reads as none, an unknown kind is dropped, a failed write says false`() = runBlocking {
        val dao = FakeDao()
        val repo = MarksRepository(dao)
        val ms = listOf(mk("L0001", 9, 20, "highlight", MarkExtra(hue = "blue"), 1_700_000_000_000)!!, mk("L0003", 0, 2, "note", MarkExtra(note = "cold"), 1_700_000_000_000)!!)
        assertTrue(repo.save("gut-test", "Test", ms))
        assertEquals(ms, repo.load("gut-test"))
        assertEquals(emptyList<Mark>(), repo.load("other"))
        dao.rows += MarkEntity.of("gut-test", "Test", ms[0].copy(id = "bad", kind = "scribble"))
        assertEquals("a mark of an unknown kind is dropped on read", ms, repo.load("gut-test"))
        dao.failRead = true
        assertEquals("unreadable reads as none", emptyList<Mark>(), repo.load("gut-test"))
        dao.failRead = false
        dao.failWrite = true
        assertFalse("a full or failing store says false", repo.save("gut-test", "Test", ms))
        dao.failWrite = false
        assertTrue(repo.save("gut-test", "Test", emptyList()))
        assertEquals(emptyList<Mark>(), repo.load("gut-test"))
    }

    @Test fun `prefs - default shown and yellow, kept, and a bad hue falls back`() {
        assertEquals(MarkPrefs(true, "yellow"), MarksPrefsStore.decode(null))
        assertEquals(MarkPrefs(true, "yellow"), MarksPrefsStore.decode("{not json"))
        assertEquals(MarkPrefs(false, "pink"), MarksPrefsStore.decode(MarksPrefsStore.encode(MarkPrefs(false, "pink"))))
        assertEquals(MarkPrefs(true, "yellow"), MarksPrefsStore.decode("""{"show":true,"hue":"mauve"}"""))
    }

    @Test fun `export rows - every play's marks with the script and its title, sorted by script id, times as ISO 8601`() = runBlocking {
        val repo = MarksRepository(FakeDao())
        val at = java.time.Instant.parse("2026-11-15T12:00:00Z").toEpochMilli()
        repo.save("gut-test", "Test", listOf(mk("L0001", 9, 20, "highlight", MarkExtra(hue = "blue"), at)!!))
        repo.save("gut-2", "Two", listOf(mk("L0003", 0, 2, "note", MarkExtra(note = "cold"), at)!!))
        val rows = repo.exportRows()
        assertEquals(
            listOf(listOf("gut-2", "Two", "note", "It", null, "cold"), listOf("gut-test", "Test", "highlight", "first thing", "blue", null)),
            rows.map { listOf(it.script, it.title, it.kind, it.text, it.hue, it.note) }.map { r -> r.map { it } },
        )
        assertEquals("2026-11-15T12:00:00Z", rows[0].created)
        assertNull(rows[1].label)
    }
}
