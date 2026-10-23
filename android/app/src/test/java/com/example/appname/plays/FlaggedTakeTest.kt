package com.example.appname.plays

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * §5 rule 2 and §8 rule 3, as apple/Tests/PlaysTests.swift proves them: a take
 * the bleed check flags is kept on disk, but its line still needs a re-take,
 * and the mix refuses it.
 *
 * Broken control, 2026-10-23: Production.usableTake ignoring `bleed` fails this
 * test (the play reads complete and mixes the device voice).
 */
class FlaggedTakeTest {
    @Test fun `a flagged take leaves its line to re-take and the mix refuses it`() {
        val script = fixtureScript()
        var p = completeProduction(script).let { c ->
            c.copy(takes = c.takes.filter { it.lineID != "L0005" }, chosen = c.chosen - "L0005")
        }
        p = p.add(take("leaky", "L0005", PartID.role("DOC"), 4_800, bleed = true))
        assertEquals("the flagged take is kept and chosen", "leaky", p.chosen["L0005"])
        assertFalse("a flagged take does not complete its line", Relay.isComplete(p, script))
        assertEquals(listOf("L0005"), Relay.missingSpeech(p, script))
        assertEquals(listOf("L0005"), Relay.needsRetake(p, script))
        assertEquals(listOf("L0005"), Relay.missingLines(PartID.role("DOC"), p, script))
        try {
            MixTimeline.build(script, p)
            fail("a flagged take must not be mixed")
        } catch (e: MixTimeline.Incomplete) {
            assertEquals(listOf("L0005"), e.missing)
        }

        val good = MixTimeline.build(script, completeProduction(script))
        val leaky = good.copy(placements = good.placements.mapIndexed { i, x -> if (i == 0) x.copy(bleed = true) else x })
        val sink = MemorySink()
        try {
            MixRenderer.render(leaky, temporaryRoot(), sink)
            fail("the renderer must refuse a flagged take")
        } catch (e: MixTimeline.Bleed) {
            assertEquals(listOf(good.placements[0].lineID), e.lines)
        }
        assertTrue("nothing is written", sink.samples.isEmpty())

        p = p.add(take("clean", "L0005", PartID.role("DOC"), 4_800))
        assertTrue("a later unflagged take completes the line", Relay.isComplete(p, script))
        assertEquals("the flagged take stays", listOf("leaky", "clean"), p.takes("L0005").map { it.id })
        val timeline = MixTimeline.build(script, p)
        assertEquals("clean", timeline.placements.first { it.lineID == "L0005" }.takeID)
        assertTrue(timeline.placements.none { it.bleed })

        p = p.add(take("door", "L0004", PartID.SOUND, 1_000, bleed = true))
        assertFalse("a flagged sound cue is not mixed either", Relay.isComplete(p, script))
        try {
            MixTimeline.build(script, p)
            fail("a flagged sound cue must not be mixed")
        } catch (e: MixTimeline.Bleed) {
            assertEquals(listOf("L0004"), e.lines)
        }
    }
}
