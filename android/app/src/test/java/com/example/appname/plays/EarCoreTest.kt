package com.example.appname.plays

import com.example.appname.data.ApiClient
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Casting an episode by ear (PLAYS-DESIGN §13 item 10, ANDROID-DESIGN §4.23), the port of js/ear.test.js's rules over the shipped
 * [EarCore]: the line that is lit, what is heard, carrying and where it stops, undo, resume, the keys, the cues' address.
 * No network, no sound.
 *
 * Seen to fail, 2026-11-24, each js/ear.test.js mutant made in EarCore.kt and restored (R4-7's commit lists the run): lit
 * never 0; moved always true; from kept at 0; a name on every line; Leave out as one line; jumped doing nothing; hear without
 * from; heard while paused; a tap as an assign; undo emptied; + Part giving nothing; names unshifted; sample always the first;
 * a line's span uncut; no takes in a tap; the carry's take check gone; key 0 a part; keys held with others; a place past the
 * end; a signature with no times; no cap on lines.
 */
class EarCoreTest {
    companion object {
        const val VTT = """WEBVTT

00:00.000 --> 00:04.000
The Planet Man! This is the story of Dantro.

00:04.000 --> 00:06.000
I'm sorry, Pat.

00:06.000 --> 00:08.000
There, they're sending us a message.

00:08.000 --> 00:10.000
You are on the province of Mars.

00:12.500 --> 00:14.000
Cut your drive.

00:14.000 --> 00:16.000
Or we'll ray you out of space.
"""
    }

    private fun fresh(vtt: String = VTT) = OwnScript.fromCues(OwnScript.parseCues(vtt))
    private fun cast(s: EarCore.Session) = OwnScript.castOf(s.doc).let { m -> s.doc.lines.map { l -> m[l.k].let { w -> if (w == OwnWho.Out) "out" else (w as? OwnWho.Role)?.name } } }

    /** The audio playing from [a] to [b] milliseconds, a frame every 16 ms. */
    private fun play(s: EarCore.Session, a: Long, b: Long) { for (t in a..b step 16) s.tick(t, true) }

    @Test fun lit() {
        val s = EarCore.Session(fresh())
        fun at(ms: Long): Int { s.tick(ms, false); return s.lit }
        assertEquals(
            "the line lit is the last begun, and a pause between lines keeps it",
            listOf(1, 1, 2, 2, 3, 5, 5, 5, 6, 7), listOf<Long>(0, 1453, 1454, 3999, 4000, 8000, 11000, 12499, 12500, 99999).map(::at),
        )
        val t = EarCore.Session(fresh(VTT.replace("00:00.000 -->", "00:01.000 -->")))
        t.tick(500, true)
        assertEquals("before the first line none is lit and none is heard", 0 to 0, t.lit to t.doc.heard.size)
        assertEquals("no_such_line", t.give("A"))
        assertEquals("a tick says when the line changes", false to true, s.tick(99999, false).moved to s.tick(0, false).moved)
    }

    @Test fun carry() {
        val s = EarCore.Session(fresh())
        play(s, 0, 1000)
        assertNull("a tap is taken", s.give("announcer"))
        play(s, 1000, 5000)
        assertEquals("the lit line and those after it as they are heard", listOf("ANNOUNCER", "ANNOUNCER", "ANNOUNCER", null), cast(s).take(4))
        s.give("Dantro")
        play(s, 5000, 9000)
        assertEquals("until the next tap, and no line not yet heard", listOf("ANNOUNCER", "ANNOUNCER", "DANTRO", "DANTRO", "DANTRO", null, null), cast(s))
        assertEquals(EarCount(5, 7), s.count())
        s.leaveOut()
        play(s, 9000, 13000)
        assertEquals("Leave out carries as a part does", listOf("ANNOUNCER", "ANNOUNCER", "DANTRO", "DANTRO", "out", "out", null), cast(s))
        assertEquals("a name is printed where the speaker changes", listOf(true, false, true, false, true, false, false), EarCore.rows(s.doc).map { it.named })
    }

    @Test fun jump() {
        val s = EarCore.Session(fresh())
        play(s, 0, 500)
        s.give("A")
        s.jumped()
        s.tick(8100, true)
        assertEquals("a seek hears nothing between", listOf("A", null, null, null, null, null, null), cast(s))
        play(s, 8100, 13000)
        assertEquals("lines after the gap are nobody's until a tap", listOf("A", null, null, null, null, null, null), cast(s))
        s.give("B")
        play(s, 13000, 14100)
        assertEquals("and then they carry", listOf("A", null, null, null, null, "B", "B"), cast(s))
        val t = EarCore.Session(fresh())
        t.tick(100, true)
        t.give("A")
        t.tick(5000, true)
        assertEquals("a slow frame hears the lines it passed", listOf("A", "A", "A", null), cast(t).take(4))
    }

    @Test fun paused() {
        val s = EarCore.Session(fresh())
        play(s, 0, 500)
        s.give("A")
        for (t in 500L..9000L step 16) s.tick(t, false)
        assertEquals("a place moved while paused is seen, never heard", listOf("A", null, null, null, null, null, null) to 1, cast(s) to s.doc.heard.size)
    }

    @Test fun again() {
        val s = EarCore.Session(fresh())
        play(s, 0, 9000)
        s.jumped(); s.tick(100, true); s.give("A")
        assertEquals("a tap on a line heard before carries over what was heard after it", listOf("A", "A", "A", "A", "A", null, null), cast(s))
        s.jumped(); s.tick(4100, true); s.give("B")
        assertEquals("a late tap put right", listOf("A", "A", "B", "B", "B", null, null), cast(s))
        s.jumped(); s.tick(6100, true); s.give("B")
        s.jumped(); s.tick(4100, true); s.give("A")
        assertEquals("and a mark after it stands", listOf("A", "A", "A", "B", "B", null, null), cast(s))
        val t = EarCore.Session(fresh())
        t.tick(100, true); t.give("A")
        play(t, 100, 9000)
        t.jumped(); t.tick(4100, true); t.leaveOut()
        assertEquals("Leave out carries over what was heard after it", listOf("A", "A", "out", "out", "out", null, null), cast(t))
    }

    @Test fun undo() {
        val s = EarCore.Session(fresh())
        assertEquals(false to "nothing_to_undo", s.canUndo to s.undo())
        play(s, 0, 500)
        s.give("A")
        play(s, 500, 4500)
        s.give("B")
        assertEquals(listOf("A", "A", "B"), cast(s).take(3))
        s.undo()
        assertEquals("one tap taken back: the carry goes on over it", listOf("A", "A", "A"), cast(s).take(3))
        s.undo()
        assertEquals("and the first", listOf(null, null, null) to false, cast(s).take(3) to s.canUndo)
        assertEquals("what was heard is never taken back", 3, s.doc.heard.size)
        s.tick(0, false); s.give("A"); s.assign(2, OwnTarget.KindOf("direction")); s.apply(OwnOp("split", line = 3, at = 4))
        s.undo(); s.undo(); s.undo()
        assertEquals("a line sheet's steps are undone in the same order", 7 to false, s.doc.lines.size to s.canUndo)
    }

    @Test fun parts() {
        val s = EarCore.Session(fresh())
        assertEquals("a part is named as a part is stored", EarCore.Session.Added("DANTRO", null), s.add(" dantro: "))
        assertEquals("with no line lit it is only named", null to listOf(EarCore.Part("DANTRO", 0)), cast(s)[0] to s.parts())
        s.tick(8100, false)
        assertEquals("with a line lit it is theirs", null to "PAT", s.add("Pat").refusal to cast(s)[4])
        assertEquals("a name the app cannot keep", "empty" to "too_long", s.add("").refusal to s.add("x".repeat(41)).refusal)
        assertEquals(listOf("DANTRO", "PAT"), s.parts().map { it.name })
        s.add("Dantro")
        assertEquals("a name twice is one part, in the order they were named", listOf("DANTRO", "PAT"), s.parts().map { it.name })
        s.give("PAT"); s.undo()
        assertEquals("a part stays when its line is taken back", listOf("DANTRO", "PAT"), s.parts().map { it.name })
        val t = EarCore.Session(fresh())
        t.tick(8100, false)
        t.add("A"); t.undo()
        assertEquals("a part stays after its first line is undone, to be tapped", listOf(EarCore.Part("A", 0)) to null, t.parts() to t.give("A"))
        play(t, 8100, 13000)
        assertEquals("Hear plays the next of a part's lines each time, around again", listOf(5, 6, 5, null), listOf(t.sample("A")?.k, t.sample("A")?.k, t.sample("A")?.k, t.sample("B")?.k))
        assertEquals("a line of a tenth of a second is heard", 1000L to 1700L, EarCore.spanOf(1000L to 1100L))
        assertEquals("and no longer than it is", 1000L to 4000L, EarCore.spanOf(1000L to 4000L))
    }

    @Test fun takes() {
        var s = EarCore.Session(fresh())
        play(s, 0, 500)
        s.give("A")
        play(s, 500, 5000)
        s = EarCore.Session(OwnScript.done(s.doc, keepOpen = true), takes = setOf("L0003"))
        s.tick(100, false)
        assertEquals("a tap that would move a recorded line is refused", "line_has_take", s.give("B"))
        s.tick(4100, false)
        assertEquals("and one on it", listOf("line_has_take", "line_has_take", "line_has_take"), listOf(s.give("B"), s.leaveOut(), s.assign(3, OwnTarget.KindOf("direction"))))
        assertEquals("nothing moved", listOf("A", "A", "A"), cast(s).take(3))
        val t = EarCore.Session(OwnScript.done(fresh(), keepOpen = true), takes = setOf("L0003"))
        t.tick(1400, true)
        t.give("A")
        play(t, 1500, 4600)
        assertEquals("a carried part never reaches a recorded line of nobody's", "A" to null, cast(t)[1] to cast(t)[2])
    }

    @Test fun keys() {
        assertEquals("1 to 9 are the parts", EarCore.Key.Part(0) to EarCore.Key.Part(8), EarCore.keyOf("1") to EarCore.keyOf("9"))
        assertEquals(listOf(EarCore.Key.Toggle, EarCore.Key.Back, EarCore.Key.Undo, EarCore.Key.Undo), listOf(" ", "ArrowLeft", "u", "U").map { EarCore.keyOf(it) })
        assertEquals("the system's own Undo", EarCore.Key.Undo to EarCore.Key.Undo, EarCore.keyOf("z", meta = true) to EarCore.keyOf("z", ctrl = true))
        val none = listOf(
            EarCore.keyOf("0"), EarCore.keyOf("ArrowRight"), EarCore.keyOf("1", meta = true), EarCore.keyOf("1", alt = true),
            EarCore.keyOf(" ", ctrl = true), EarCore.keyOf("z"), EarCore.keyOf("Z", meta = true, shift = true), EarCore.keyOf("F1"),
        )
        assertEquals("and no other key", List(8) { null }, none)
    }

    @Test fun resume() {
        val s = EarCore.Session(fresh())
        play(s, 0, 500)
        s.give("A")
        play(s, 500, 4500)
        val kept = OwnScript.kept(s.doc)
        val t = EarCore.Session(kept, listOf("A", "B"))
        assertEquals("a kept casting is the casting", listOf(cast(s), listOf("A", "B"), false), listOf(cast(t), t.parts().map { it.name }, t.canUndo))
        t.tick(4500, true)
        assertEquals("taken up where it was left, the carry goes on", "A", cast(t)[2])
        play(t, 4500, 6500)
        assertEquals("line after line", "A", cast(t)[3])
        fun ear(p: Long) = OwnEar("", "", p)
        assertEquals(
            "the place it was left, or the start", listOf(4500L, 0L, 0L, 0L, 0L),
            listOf(EarCore.placeOf(ear(4500), kept), EarCore.placeOf(ear(0), kept), EarCore.placeOf(ear(16000), kept), EarCore.placeOf(ear(9_000_000_000), kept), EarCore.placeOf(null, kept)),
        )
        val cues = OwnScript.parseCues(VTT)
        assertEquals("the same transcript is the same", EarCore.signature(cues), EarCore.signature(OwnScript.parseCues(VTT)))
        assertFalse("other words are another", EarCore.signature(cues) == EarCore.signature(OwnScript.parseCues(VTT.replace("sorry", "sure"))))
        assertFalse("other times are another", EarCore.signature(cues) == EarCore.signature(OwnScript.parseCues(VTT.replace("00:12.500", "00:12.400"))))
        assertEquals(
            "what cannot be cast", listOf(null, "no_lines", "too_many_lines"),
            listOf(EarCore.refusalOf(fresh()), EarCore.refusalOf(OwnScript.newDoc(emptyList())), EarCore.refusalOf(OwnDoc(List(OwnScript.MAX_LINES + 1) { OwnLine(it, null, "open", null, "x") }, 1))),
        )
    }

    @Test fun `the times are read beside a transcript we show and nowhere else`() {
        val txt = "https://archive.org/download/OTRR_Suspense_Singles/Suspense%20430223%20%2864-48%29.autogenerated.txt"
        assertEquals("https://archive.org/download/OTRR_Suspense_Singles/Suspense%20430223%20%2864-48%29.autogenerated.vtt", ApiClient.cuesUrl(txt))
        for (bad in listOf(null, "https://archive.org/download/x/y.txt", "https://example.com/download/x/y.autogenerated.txt", "https://archive.org/download/y.autogenerated.txt")) assertNull(bad, ApiClient.cuesUrl(bad))
    }

    @Test fun rename() {
        fun start(): EarCore.Session {
            val s = EarCore.Session(OwnScript.fromCues((0..5).map { OwnCue("Line $it here.", it * 1000L to it * 1000L + 1000) }))
            for ((ms, who) in listOf(100L to "Ann", 2100L to "Bob", 4100L to "Cy")) { s.tick(ms, true); s.add(who); s.tick(ms + 1000, true) }
            return s
        }
        fun at(s: EarCore.Session) = s.parts().map { "${it.name} ${it.lines}" }
        var s = start()
        assertEquals("three parts", listOf("ANN 2", "BOB 2", "CY 2"), at(s))
        assertEquals("renamed", EarCore.Session.Renamed("THE PLANET MAN", null), s.rename("BOB", "the planet man"))
        assertEquals("every line of theirs, in the same place: the same number and hue", listOf("ANN 2", "THE PLANET MAN 2", "CY 2"), at(s))
        s.undo()
        assertEquals("one Undo takes it back, the order with it", listOf("ANN 2", "BOB 2", "CY 2"), at(s))
        s.rename("BOB", "ann")
        assertEquals("a name another part has joins the two", listOf("ANN 4", "CY 2"), at(s))
        s.rename("CY", "Cyrus")
        s.undo()
        assertEquals("the second only", listOf("ANN 4", "CY 2"), at(s))
        s.undo()
        assertEquals("then the first", listOf("ANN 2", "BOB 2", "CY 2"), at(s))
        assertNull("and what was before it", s.undo())
        s = start()
        s.rename("ANN", "cy")
        assertEquals("the one that had the name keeps its place", listOf("BOB 2", "CY 4"), at(s))
        s = start()
        assertEquals("refusals", listOf("empty", "no_such_part", null), listOf(s.rename("ANN", "").refusal, s.rename("ZED", "X").refusal, s.rename("ANN", "ANN").refusal))
        s = start().let { EarCore.Session(it.doc, it.names + "DEE") }
        assertNull("a part with no line yet", s.rename("DEE", "Dora").refusal)
        assertEquals("renamed too", listOf("ANN 2", "BOB 2", "CY 2", "DORA 0"), at(s))
        s = start()
        s.replace(OwnScript.done(s.doc, keepOpen = true))
        s.takes = setOf("L0002")
        assertEquals("a part with a take on a carried line keeps its name", listOf("part_has_take", "ANN 2"), listOf(s.rename("ANN", "X").refusal, at(s)[0]))
        assertEquals("nothing to undo", "nothing_to_undo", s.undo())
        assertNull("another does not", s.rename("CY", "X").refusal)
    }

    @Test fun `no file here proposes a speaker or makes a sound`() {
        val code = File("src/main/java/com/example/appname/plays/EarCore.kt").readText().lines().filterNot { it.trim().startsWith("//") || it.trim().startsWith("*") || it.trim().startsWith("/**") }.joinToString("\n")
        for (word in listOf("android.", "AudioRecord", "Visualizer", "okhttp", "ktor")) assertFalse(word, code.contains(word))
        assertTrue(code.contains("object EarCore"))
    }
}
