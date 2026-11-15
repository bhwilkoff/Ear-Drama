package com.example.appname.plays

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The Ear Drama page (docs/research/design, R2 play typography): the cases of js/reader.test.js ported one for
 * one, and every drawn run over real scripts mapping back to its line's words.
 *
 * Seen to fail, 2026-11-14, then restored: `isVerse` returning true for a lowercase turnover (`a lowercase turnover is prose`);
 * `layoutOf` with run-in speaker splitting removed (`a speech run into another is attributed to its speaker`).
 */
class PlayPageTest {
    private fun speech(role: String, vararg parts: LinePart) = ScriptLine("L1", ScriptLine.Kind.Speech, role = role, parts = parts.toList())
    private fun say(t: String) = LinePart.Say(t)
    private fun dir(t: String) = LinePart.Direction(t)

    private fun scripts(): List<PlayScript> {
        var dir: File? = File("").absoluteFile
        while (dir != null && !File(dir, "catalog/plays/castable-scripts.json").exists()) dir = dir.parentFile
        val bundle = CastableLibrary.decode(File(dir!!, "catalog/plays/castable-scripts.json").readText()).scripts
        val lib = File(dir, "catalog/out/plays-library/scripts").listFiles().orEmpty().sortedBy { it.name }.take(40)
            .map { PlayScriptFile.decode(it.readText()).scripts.first() }
        return bundle + lib
    }

    @Test fun `verse keeps its lines, a transcriber's wrapping is reflowed`() {
        assertTrue(PlayPage.isVerse(listOf("When shall we three meet again?\nIn thunder, lightning, or in rain?")))
        assertTrue(PlayPage.isVerse(listOf("This is the sergeant\nWho, like a good and hardy soldier, fought\n’Gainst my captivity.")))
        assertFalse(PlayPage.isVerse(listOf("I attribute it to the superior quality of the wine, sir. I have often\nobserved that in married households")))
        assertFalse(
            PlayPage.isVerse(
                listOf(
                    "Why is it that at a bachelor’s establishment the servants invariably\nDrink the champagne? I ask merely for information, and nothing more than\nThat, sir, as anyone would.",
                ),
            ),
        )
        assertFalse(PlayPage.isVerse(listOf("Who is there?")))
        assertFalse("a short lowercase turnover is prose", PlayPage.isVerse(listOf("A short line\nand a lowercase one")))
    }

    @Test fun `a speech run into another is attributed to its speaker, and cues get the sound lane`() {
        val roles = listOf("CHARTERIS", "GRACE")
        val lay = PlayPage.layoutOf(speech("CHARTERIS", say("Of course. Why not?\nGRACE"), dir("reflecting"), say(". Never mind why.")), roles)
        assertEquals(listOf("CHARTERIS", "GRACE"), lay.speeches.map { it.role })
        assertEquals("GRACE" to 20, lay.speeches[1].name?.let { it.text to it.at })
        assertEquals(listOf("reflecting" to false, "Never mind why." to true), lay.speeches[1].rows[0].runs.map { it.text to it.said })
        assertFalse(lay.verse)

        val radio = PlayPage.layoutOf(
            speech("HANCOCK", dir("sound of gavel"), say("Order!"), LinePart.Sound("knock"), say("Come in.")), listOf("HANCOCK"),
        )
        assertEquals(listOf(true, false, true, false), radio.speeches[0].rows.map { it.cue })

        val block = PlayPage.layoutOf(ScriptLine("L3", ScriptLine.Kind.Direction, source = "[_Exeunt._]"), emptyList())
        assertEquals(listOf(ScriptReading.RunKind.Plain to "Exeunt."), block.rows[0].runs.map { it.kind to it.text })
        val open = PlayPage.layoutOf(ScriptLine("L4", ScriptLine.Kind.Direction, source = "[Enter Lane."), emptyList())
        assertEquals(listOf("Enter Lane."), open.rows[0].runs.map { it.text })

        val stress = PlayPage.layoutOf(
            speech("A", say("It is the first in which"), dir("I"), say("have been serious."), dir("Sits."), say("Well.")), listOf("A"),
        )
        assertEquals(
            listOf("It is the first in which" to true, "I" to true, "have been serious." to true, "Sits." to false, "Well." to true),
            stress.speeches[0].rows[0].runs.map { it.text to it.said },
        )
        assertEquals(22, PlayPage.cueTail("I could love anybody. Any pretty woman, that is."))
        assertEquals(0, PlayPage.cueTail("Who is there?"))
    }

    @Test fun `verse rows keep their printed lines and a half line is indented`() {
        val lay = PlayPage.layoutOf(
            speech("DUNCAN", say("What bloody man is that? He can report,\nAs seemeth by his plight, of the revolt\n  The newest state.")), listOf("DUNCAN"),
        )
        assertTrue(lay.verse)
        assertEquals(3, lay.speeches[0].rows.size)
        assertEquals(listOf(false, false, true), lay.speeches[0].rows.map { it.indent })
    }

    @Test fun `every drawn run still maps back to its line's words (marks anchor through layoutOf)`() {
        var n = 0
        var split = 0
        for (s in scripts()) {
            val roles = s.roles.map { it.name }
            for (line in s.lines) {
                val text = ScriptReading.lineText(line).replace('\n', ' ')
                val lay = PlayPage.layoutOf(line, roles)
                val runs = ArrayList<PageRun>()
                if (lay.speeches.isNotEmpty()) for (sp in lay.speeches) {
                    sp.name?.let { runs += it }
                    for (rw in sp.rows) runs += rw.runs
                } else for (rw in lay.rows) runs += rw.runs
                if (lay.speeches.size > 1) split++
                for (r in runs) {
                    n++
                    val want = r.text.replace('\n', ' ')
                    val got = text.substring(minOf(r.at, text.length), minOf(r.at + want.length, text.length))
                    assertEquals("${s.id} ${line.id}: run at ${r.at}", want, got)
                }
            }
        }
        assertTrue("runs checked ($n)", n > 1000)
        assertTrue("some script runs a speech into another", split > 0)
    }
}
