package com.example.appname.plays

import java.io.File
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The read-along's follow logic (PLAYS-DESIGN §2.11): the line heard comes from the listen plan, a mix finds its line
 * by time, the reader turns itself while following, holds still after a turn-away, and returns. The same cases as
 * js/reader.test.js and ReadAlongTests.swift.
 */
class ReadAlongTest {
    private val a = PartID("role:A")

    @Test fun `the line comes from the plan`() {
        val plan = listOf("L1", "L3", "L4").map { Relay.ListenEntry.Voice(it, a, "x") }
        assertEquals(listOf("L1", "L3", "L4"), (0..2).map { ReadAlong.line(plan, it) })
        assertNull(ReadAlong.line(plan, 3))
        assertNull(ReadAlong.line(plan, -1))
        assertNull(ReadAlong.line(emptyList(), 0))
    }

    @Test fun `a mix finds its line by time`() {
        val spans = listOf(ReadAlong.Span("L1", 0, 100), ReadAlong.Span("L2", 150, 100))
        fun at(s: Double) = ReadAlong.line(spans, 100.0, s)
        assertEquals("L1", at(0.0))
        assertEquals("L1", at(0.99))
        assertEquals("L1", at(1.2))
        assertEquals("L2", at(1.5))
        assertEquals("L2", at(2.49))
        assertNull(at(2.6))
        assertNull(ReadAlong.line(emptyList(), 100.0, 1.0))
    }

    @Test fun `it turns while following and holds after turning away`() {
        val f = ReadAlong.Follow()
        assertEquals(ReadAlong.Follow.Step(turn = true, back = false), f.line("L1"))
        f.away()
        assertEquals(ReadAlong.Follow.Step(turn = false, back = true), f.line("L2"))
        assertEquals(ReadAlong.Follow.Step(turn = false, back = true), f.line("L3"))
        assertEquals("L3", f.back())
        assertEquals(ReadAlong.Follow.Step(turn = true, back = false), f.line("L4"))
        f.away()
        f.line(null)
        assertNull(f.back())
        f.away()
        assertEquals(ReadAlong.Follow.Step(turn = false, back = false), f.line(null))
    }

    @Test fun `the panel shows the line heard and one each side`() {
        val lines = (0..2).map { ScriptLine("L$it", ScriptLine.Kind.Speech, "A", listOf(LinePart.Say("w$it"))) }
        fun ids(id: String) = ReadAlong.panel(lines, id).toList().map { it?.id }
        assertEquals(listOf("L0", "L1", "L2"), ids("L1"))
        assertEquals(listOf(null, "L0", "L1"), ids("L0"))
        assertEquals(listOf("L1", "L2", null), ids("L2"))
        assertEquals(listOf(null, null, null), ids("nope"))
    }

    // The word heard (PLAYS-DESIGN 2.11 rule 3): the cases every stack runs, catalog/tests/golden/read_along_words.json.

    private fun golden(): JsonObject {
        var dir: File? = File("").absoluteFile
        while (dir != null && !File(dir, "catalog/tests/golden/read_along_words.json").exists()) dir = dir.parentFile
        return Json.parseToJsonElement(File(dir!!, "catalog/tests/golden/read_along_words.json").readText()).jsonObject
    }

    private fun lineOf(o: JsonObject): ScriptLine {
        val kind = when (o.getValue("kind").jsonPrimitive.content) {
            "speech" -> ScriptLine.Kind.Speech
            "sound" -> ScriptLine.Kind.Sound
            "music" -> ScriptLine.Kind.Music
            else -> ScriptLine.Kind.Direction
        }
        val parts = o["parts"]?.jsonArray?.map { p ->
            val e = p.jsonObject
            e["say"]?.let { LinePart.Say(it.jsonPrimitive.content) } ?: LinePart.Direction(e.getValue("direction").jsonPrimitive.content)
        }
        return ScriptLine(o.getValue("id").jsonPrimitive.content, kind, o["role"]?.jsonPrimitive?.content, parts, o["source"]?.jsonPrimitive?.content)
    }

    @Test fun `a voice's range maps onto the printed word`() {
        for (c in golden().getValue("spoken").jsonArray) {
            val o = c.jsonObject
            val sp = ReadAlong.spoken(lineOf(o.getValue("line").jsonObject))
            assertEquals(o.getValue("said").jsonPrimitive.content, sp.said)
            for (k in o.getValue("cases").jsonArray) {
                val e = k.jsonObject
                val r = e.getValue("range").jsonArray.map { it.jsonPrimitive.int }
                val want = e.getValue("word").takeIf { it !is JsonNull }?.jsonArray?.map { it.jsonPrimitive.int }
                assertEquals("${sp.said} $r", want?.let { ReadAlong.Word(it[0], it[1]) }, ReadAlong.word(sp, r[0], r[1]))
            }
        }
    }

    @Test fun `the printed words of a spoken string`() {
        for (c in golden().getValue("textWords").jsonArray) {
            val o = c.jsonObject
            val want = o.getValue("words").jsonArray.map { w -> w.jsonArray.map { it.jsonPrimitive.int }.let { ReadAlong.Word(it[0], it[1]) } }
            assertEquals(o.getValue("said").jsonPrimitive.content, want, ReadAlong.textWords(o.getValue("said").jsonPrimitive.content))
        }
    }

    @Test fun `kokoro words come from the duration frames and pair only when the counts agree`() {
        for (c in golden().getValue("kokoro").jsonArray) {
            val o = c.jsonObject
            val pieces = o.getValue("pieces").jsonArray.map { p ->
                val e = p.jsonObject
                ReadAlong.KokoroPiece(e.getValue("symbols").jsonPrimitive.content, e.getValue("frames").jsonArray.map { it.jsonPrimitive.int }.toIntArray())
            }
            val said = o.getValue("said").jsonPrimitive.content
            val want = (o.getValue("words") as? JsonArray)?.map { w -> w.jsonArray.map { it.jsonPrimitive.int }.let { ReadAlong.TimedWord(it[0], ReadAlong.Word(it[1], it[2])) } }
            assertEquals(said, want, ReadAlong.kokoroWords(said, pieces))
        }
    }

    @Test fun `the word heard at a sample is the last begun`() {
        val t = listOf(ReadAlong.TimedWord(100, ReadAlong.Word(0, 4)), ReadAlong.TimedWord(500, ReadAlong.Word(5, 9)))
        assertNull(ReadAlong.word(t, 99))
        assertEquals(ReadAlong.Word(0, 4), ReadAlong.word(t, 100))
        assertEquals(ReadAlong.Word(5, 9), ReadAlong.word(t, 9999))
        assertEquals(2, ReadAlong.phonemeWordCount("wˈɛl, mˈɑli."))
    }

    @Test fun `speed takes the nearest quarter step and is named as the transport names it`() {
        assertEquals(listOf(0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0), ReadAlong.SPEEDS)
        assertEquals(1.0, ReadAlong.speed(null), 0.0)
        assertEquals(1.0, ReadAlong.speed(Double.NaN), 0.0)
        assertEquals(1.25, ReadAlong.speed(1.3), 0.0)
        assertEquals(2.0, ReadAlong.speed(9.0), 0.0)
        assertEquals(0.5, ReadAlong.speed(0.0), 0.0)
        assertEquals(listOf("0.5\u00D7", "0.75\u00D7", "1\u00D7", "1.25\u00D7", "1.5\u00D7", "1.75\u00D7", "2\u00D7"), ReadAlong.SPEEDS.map { ReadAlong.speedLabel(it) })
    }

    @Test fun `Hear the cast reads each speech and a direction only when its part has a voice`() {
        val a = PartID.role("A")
        val lines = listOf(
            ScriptLine("L0", ScriptLine.Kind.Speech, "A", listOf(LinePart.Say("Hello."))),
            ScriptLine("L1", ScriptLine.Kind.Direction, null, null, "Enter B."),
            ScriptLine("L2", ScriptLine.Kind.Speech, "A", listOf(LinePart.Say("  "))),
            ScriptLine("L3", ScriptLine.Kind.Speech, "A", listOf(LinePart.Say("Bye."))),
        )
        val script = PlayScript(
            id = "s", revision = "r", kind = "radio", title = "T", source = PlayScript.Source("Fixture", "https://example.org"),
            rights = PlayScript.Rights("script_source_cleared"), lines = lines,
        )
        assertEquals(listOf("L0", "L3"), AlongModel.tablePlan(script, 0) { false }.map { it.lineID })
        assertEquals(listOf("L0", "L1", "L3"), AlongModel.tablePlan(script, 0) { it == PartID.DIRECTIONS }.map { it.lineID })
        assertEquals(listOf("L3"), AlongModel.tablePlan(script, 3) { a == it }.map { it.lineID })
    }
}
