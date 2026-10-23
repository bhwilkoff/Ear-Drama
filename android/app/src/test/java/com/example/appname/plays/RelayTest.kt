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

    @Test fun `the relay is one part at a time, largest first`() {
        val script = fixtureScript()
        val molly = PartID.role("MOLLY")
        val fibber = PartID.role("FIBBER")
        val doc = PartID.role("DOC")
        assertEquals(listOf(molly, fibber, doc, PartID.SOUND, PartID.DIRECTIONS), Relay.order(script))
        var p = Production.create(script)
        assertEquals(molly, Relay.next(p, script))

        refused(Relay.Refusal.NotNext(molly)) { Relay.take(fibber, null, p, script) }
        p = Relay.take(molly, "  Ada ", p, script)
        assertEquals(PartState(PartState.Status.Recording, "Ada"), p.state(molly))
        assertNull("nothing is offered while a part records", Relay.next(p, script))
        refused(Relay.Refusal.AnotherPartIsRecording(molly)) { Relay.take(fibber, null, p, script) }

        val mollyLines = script.lines(molly).map { it.id }
        refused(Relay.Refusal.LinesMissing(mollyLines)) { Relay.finish(molly, p, script) }
        for (id in mollyLines) p = p.add(take("t-$id", id, molly, 100))
        p = Relay.finish(molly, p, script)
        assertEquals("the device passes to the next largest part", fibber, Relay.next(p, script))

        refused(Relay.Refusal.SpeakingPartCannotBeSilent) { Relay.leaveSilent(fibber, p, script) }
        for (part in listOf(fibber, doc)) {
            p = Relay.take(part, null, p, script)
            for (l in script.lines(part)) p = p.add(take("t-${l.id}", l.id, part, 100))
            p = Relay.finish(part, p, script)
        }
        assertTrue("every speaking line has a human take", Relay.isComplete(p, script))
        assertEquals(PartID.SOUND, Relay.next(p, script))
        p = Relay.leaveSilent(PartID.SOUND, p, script)
        assertEquals(PartID.DIRECTIONS, Relay.next(p, script))

        p = Relay.reopen(doc, p, script)
        assertEquals(doc, Relay.current(p, script))
        refused(Relay.Refusal.AnotherPartIsRecording(doc)) { Relay.reopen(molly, p, script) }
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
        assertEquals("Stage directions is next.", Relay.Refusal.NotNext(PartID.DIRECTIONS).text)
    }
}
