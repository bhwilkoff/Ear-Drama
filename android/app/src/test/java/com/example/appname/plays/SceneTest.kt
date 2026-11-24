package com.example.appname.plays

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Today's scene's opening and the voice Try a line takes (Decision 079; the web's js/plays.test.js `openingOf`). */
class SceneTest {
    private fun say(id: String, role: String, text: String) =
        ScriptLine(id, ScriptLine.Kind.Speech, role = role, parts = listOf(LinePart.Say(text)))

    @Test fun `the opening is the first speeches with said words, cleaned`() {
        val script = fixtureScript().copy(
            lines = listOf(
                ScriptLine("L0001", ScriptLine.Kind.Direction, source = "(A kitchen.)"),
                say("L0002", "JOE", "  . Well,   _Mary_ -- here   we are."),
                say("L0003", "MARY", "—"),
                say("L0004", "MARY", ": Yes, and\n  then Joe."),
                say("L0005", "JOE", "-- So."),
                say("L0006", "MARY", "Fine."),
                say("L0007", "JOE", "Not shown."),
            ),
        )
        val opening = PlayScript.openingOf(script, 4)
        assertEquals(listOf("L0002", "L0004", "L0005", "L0006"), opening.map { it.lineId })
        assertEquals("Well, Mary — here we are.", opening[0].text)
        assertEquals("Yes, and then Joe.", opening[1].text)
        assertEquals("So.", opening[2].text)
        assertEquals(listOf("JOE", "MARY", "JOE", "MARY"), opening.map { it.name })
        assertEquals(PartID.role("MARY"), opening[1].part)
    }

    @Test fun `a verse opening keeps its printed rows and a wrapped prose one runs together`() {
        val verse = "Is this a dagger which I see before me,\nThe handle toward my hand?\nCome, let me clutch thee."
        val prose = "I have been walking for the better part of\nan hour and the road does not seem to end."
        val script = fixtureScript().copy(lines = listOf(say("V1", "MACBETH", verse), say("V2", "BANQUO", prose)))
        val opening = PlayScript.openingOf(script, 4)
        assertEquals(verse, opening[0].text)
        assertTrue(opening[0].verse)
        assertEquals("I have been walking for the better part of an hour and the road does not seem to end.", opening[1].text)
        assertTrue(!opening[1].verse)
        val row = PlayRow(id = "r", title = "R", opening = listOf(PlayRow.Opening("MACBETH", verse), PlayRow.Opening("BANQUO", prose)))
        assertEquals(listOf(verse, "I have been walking for the better part of an hour and the road does not seem to end."), PlayScript.openingOf(row, 4).map { it.text })
        assertEquals(listOf(true, false), PlayScript.openingOf(row, 4).map { it.verse })
    }

    @Test fun `with no lines the opening is the row's own`() {
        val row = PlayRow(
            id = "gut-1", title = "T",
            opening = listOf(PlayRow.Opening("JOE", "Hello -- there"), PlayRow.Opening("MARY", "  "), PlayRow.Opening("MARY", "_Hi._")),
        )
        val opening = PlayScript.openingOf(row, 4)
        assertEquals(listOf("Hello — there", "Hi."), opening.map { it.text })
        assertEquals(listOf(null, null), opening.map { it.lineId })
        assertTrue(PlayScript.openingOf(PlayRow(id = "x", title = "x"), 4).isEmpty())
    }

    @Test fun `the index row decodes its opening`() {
        val index = PlayIndex.decode("""{"format":1,"plays":[{"id":"a","title":"A","opening":[{"role":"JOE","text":"Hi."}]}]}""")
        assertEquals(listOf(PlayRow.Opening("JOE", "Hi.")), index.plays[0].opening)
    }

    @Test fun `try a line takes the voice that answers`() {
        val script = fixtureScript()
        val opening = PlayScript.openingOf(script, 4)
        assertEquals("the second speaker of the opening", PartID.role("MOLLY"), PlayScript.answeringPart(opening, script))
        val monologue = opening.filter { it.name == "FIBBER" }
        assertEquals("else the second part", PartID.role("MOLLY"), PlayScript.answeringPart(monologue, script))
        assertNull(PlayScript.answeringPart(emptyList(), null))
    }
}
