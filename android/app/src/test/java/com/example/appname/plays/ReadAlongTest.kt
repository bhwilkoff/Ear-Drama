package com.example.appname.plays

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
}
