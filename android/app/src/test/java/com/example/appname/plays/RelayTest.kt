package com.example.appname.plays

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * The relay (PLAYS-DESIGN §2, pending owner C6 and C7): one part at a time,
 * largest first, a speaking part done only when every line has a take.
 *
 * Broken control, 2026-10-23: Relay.take without the "another part is
 * recording" guard fails this test.
 */
class RelayTest {
    private inline fun <reified R : Relay.Refusal> refused(expected: R, block: () -> Unit) {
        try {
            block()
            fail("expected $expected")
        } catch (e: Relay.Refusal) {
            assertEquals(expected, e)
        }
    }

    @Test fun `the relay records one part at a time, in any order`() {
        val script = fixtureScript()
        val molly = PartID.role("MOLLY")
        val fibber = PartID.role("FIBBER")
        val doc = PartID.role("DOC")
        assertEquals(listOf(molly, fibber, doc, PartID.SOUND, PartID.DIRECTIONS), Relay.order(script))
        var p = Production.create(script)
        assertEquals("the suggestion is the largest open part", molly, Relay.next(p, script))

        p = Relay.take(doc, "  Ada ", p, script)
        assertEquals("a smaller part can be taken first", PartState(PartState.Status.Recording, "Ada"), p.state(doc))
        assertNull("nothing is suggested while a part records", Relay.next(p, script))
        refused(Relay.Refusal.AnotherPartIsRecording(doc)) { Relay.take(fibber, null, p, script) }

        val docLines = script.lines(doc).map { it.id }
        refused(Relay.Refusal.LinesMissing(docLines)) { Relay.finish(doc, p, script) }
        for (id in docLines) p = p.add(take("t-$id", id, doc, 100))
        p = Relay.finish(doc, p, script)
        assertEquals("the suggestion skips the part that is through", molly, Relay.next(p, script))

        refused(Relay.Refusal.SpeakingPartCannotBeSilent) { Relay.leaveSilent(fibber, p, script) }
        refused(Relay.Refusal.NotOpen(doc)) { Relay.take(doc, null, p, script) }
        for (part in listOf(fibber, molly)) {
            p = Relay.take(part, null, p, script)
            for (l in script.lines(part)) p = p.add(take("t-${l.id}", l.id, part, 100))
            p = Relay.finish(part, p, script)
        }
        assertTrue("every speaking line has a human take", Relay.isComplete(p, script))
        assertEquals(PartID.SOUND, Relay.next(p, script))
        p = Relay.leaveSilent(PartID.DIRECTIONS, p, script)
        assertEquals("any open sound or directions part can be left silent", PartID.SOUND, Relay.next(p, script))
        refused(Relay.Refusal.NotOpen(PartID.DIRECTIONS)) { Relay.leaveSilent(PartID.DIRECTIONS, p, script) }

        p = Relay.reopen(doc, p, script)
        assertEquals(doc, Relay.current(p, script))
        refused(Relay.Refusal.AnotherPartIsRecording(doc)) { Relay.reopen(molly, p, script) }
        refused(Relay.Refusal.NotOpen(PartID.SOUND)) { Relay.reopen(PartID.SOUND, Production.create(script), script) }
    }

    @Test fun `the listen plan is takes and device-voice text, in script order`() {
        val script = fixtureScript()
        val molly = PartID.role("MOLLY")
        var p = Production.create(script)
        p = p.add(take("t-L0003", "L0003", molly, 100))
        p = p.add(take("t-L0006", "L0006", molly, 100, bleed = true))
        val plan = Relay.listenPlan(p, script)
        assertEquals("direction and sound lines without a take are not in the plan", listOf("L0002", "L0003") + (5..11).map { "L%04d".format(it) }, plan.map { it.lineID })
        assertTrue(plan[1] is Relay.ListenEntry.TakeEntry)
        assertEquals("a flagged take reads as a voice line", Relay.ListenEntry.Voice("L0006", molly, "Come in."), plan.first { it.lineID == "L0006" })
        assertEquals(Relay.ListenEntry.Voice("L0002", PartID.role("FIBBER"), "Well, Molly."), plan[0])
        assertTrue("a voice entry holds text, never audio", plan.filterIsInstance<Relay.ListenEntry.Voice>().all { v ->
            Relay.ListenEntry.Voice::class.java.declaredFields.none { it.type.isArray || it.type == StandInAudio::class.java } && v.text.isNotEmpty()
        })
        val whole = Relay.listenPlan(completeProduction(script), script)
        assertTrue(whole.all { it is Relay.ListenEntry.TakeEntry })
        assertEquals(9, whole.size)
    }

    @Test fun `the cue is the speech before when someone else speaks it`() {
        val script = fixtureScript()
        fun cues(id: String, runUp: Boolean = false) = Relay.cueLines(id, script, runUp).map { it.id }
        assertEquals(listOf("L0002"), cues("L0003"))
        assertEquals("my own line before: no cue", emptyList<String>(), cues("L0007"))
        assertEquals("the sound cue between is not voiced", listOf("L0005"), cues("L0006"))
        assertEquals(listOf("L0005", "L0006"), cues("L0007", runUp = true))
        assertEquals("the first speech has no cue", emptyList<String>(), cues("L0002", runUp = true))
    }

    @Test fun `refusals read as one sentence`() {
        assertEquals("MOLLY is still recording.", Relay.Refusal.AnotherPartIsRecording(PartID.role("MOLLY")).text)
        assertEquals("1 line still needs a take.", Relay.Refusal.LinesMissing(listOf("L1")).text)
        assertEquals("Stage directions is not open.", Relay.Refusal.NotOpen(PartID.DIRECTIONS).text)
    }
}
