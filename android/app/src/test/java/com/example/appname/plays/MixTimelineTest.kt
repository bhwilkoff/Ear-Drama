package com.example.appname.plays

import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.pow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * The mix is plain data (§4.2): script order, a gap, a ripple on a longer
 * re-take, a stored gain, and no timeline at all for a partial play (§5 rule 3).
 *
 * Broken controls, 2026-10-23: MixTimeline.build without the gap fails the
 * order test and the render test's quiet gaps; build without the
 * missing-speech guard fails the partial-play test.
 */
class MixTimelineTest {
    @Test fun `lines follow in script order with a gap, and a re-take ripples`() {
        val script = fixtureScript()
        var p = completeProduction(script, frames = 4_800)
        val gap = (MixTimeline.DEFAULT_GAP * 48_000).toInt()
        val timeline = MixTimeline.build(script, p)
        assertEquals("silent cues are left out", script.speechLineIDs, timeline.placements.map { it.lineID })
        assertEquals((0 until 9).map { it * (4_800 + gap) }, timeline.placements.map { it.start })
        assertEquals(9 * 4_800 + 8 * gap, timeline.totalFrames)

        p = p.add(take("long", "L0003", PartID.role("MOLLY"), 4_800 + 24_000))
        val rippled = MixTimeline.build(script, p)
        assertEquals(0, rippled.placements[0].start)
        assertEquals("long", rippled.placements[1].takeID)
        assertTrue(
            "a longer re-take moves every later line",
            timeline.placements.drop(2).zip(rippled.placements.drop(2)).all { (a, b) -> b.start - a.start == 24_000 },
        )

        p = p.add(take("door", "L0004", PartID.SOUND, 1_000))
        assertTrue("a recorded sound cue is placed", "L0004" in MixTimeline.build(script, p).placements.map { it.lineID })
    }

    @Test fun `a partial play has no timeline and writes no mix`() {
        val script = fixtureScript()
        val p = completeProduction(script).let { it.copy(chosen = it.chosen - "L0005") }
        try {
            MixTimeline.build(script, p)
            fail("a partial play must not be mixed")
        } catch (e: MixTimeline.Incomplete) {
            assertEquals(listOf("L0005"), e.missing)
        }
        val store = ProductionStore(temporaryRoot())
        try {
            val made = store.create(script)
            store.save(p.copy(id = made.id))
            try {
                store.renderMix(made.id) { WavSink(it, 48_000) }
                fail("the store must refuse a partial play")
            } catch (_: MixTimeline.Incomplete) {
            }
            assertFalse("no mix file", store.mixFile(made.id).exists())
            assertTrue("no partial file left behind", store.folder(made.id).list()!!.none { it.startsWith(".mix") })
        } finally {
            store.root.deleteRecursively()
        }
    }

    @Test fun `the gain reaches -16 held under the ceiling`() {
        assertEquals(10.0.pow(10.0 / 20).toFloat(), MixTimeline.gain(-26.0, 0.1f), 1e-4f)
        val clamped = MixTimeline.gain(-26.0, 0.5f)
        assertEquals("the peak lands at -1 dBFS", -1.0, 20 * log10((clamped * 0.5f).toDouble()), 1e-3)
        assertEquals(1f, MixTimeline.gain(null, 0.5f))
    }

    @Test fun `the render puts each take where the timeline says`() {
        val script = fixtureScript()
        val store = ProductionStore(temporaryRoot())
        try {
            var p = store.create(script)
            val samples = tone(listOf(440.0), 0.6)
            for (l in script.lines.filter { it.kind == ScriptLine.Kind.Speech }) {
                val file = store.writeTake(MicrophoneCapture(samples, 48_000.0), p, l.id)
                p = p.add(
                    Take(
                        "t-${l.id}", l.id, l.part, file, 0.0, samples.size, 48_000.0, Take.Capture.Direct, emptyMap(),
                        BS1770.integratedLoudness(samples, 48_000.0), BS1770.samplePeak(samples), false,
                    ),
                )
            }
            store.save(p)
            val timeline = MixTimeline.build(script, p)
            val sink = MemorySink()
            MixRenderer.render(timeline, store.takesFolder(p.id), sink)
            val mix = sink.samples.toFloatArray()
            assertEquals("the mix is as long as its timeline", timeline.totalFrames, mix.size)
            fun rms(center: Int) = LineEndDetector.rms(mix.copyOfRange(maxOf(0, center - 2_400), minOf(mix.size, center + 2_400)))
            timeline.placements.forEachIndexed { i, placement ->
                assertTrue("take $i sounds where it is placed", rms(placement.start + placement.frames / 2) > 0.05f)
                val next = timeline.placements.getOrNull(i + 1) ?: return@forEachIndexed
                assertTrue("the gap after take $i is quiet", rms((placement.start + placement.frames + next.start) / 2) < 0.01f)
            }
            // The stored gain is applied: each take lands near -16 LUFS.
            val first = timeline.placements[0]
            val loud = BS1770.integratedLoudness(mix.copyOfRange(first.start, first.start + first.frames), 48_000.0)!!
            assertTrue("gain applied ($loud)", abs(loud - -16) < 0.5)

            // Through the store: the mix file is written and the production remembers what it was made from.
            val file = store.renderMix(p.id) { WavSink(it, 48_000) }
            assertEquals(store.mixFile(p.id), file)
            assertEquals(timeline.totalFrames, TakeAudio.read(file).first.size)
            assertEquals(p.chosenFingerprint, store.production(p.id)!!.mixedFrom)
        } finally {
            store.root.deleteRecursively()
        }
    }

    @Test fun `a full scale sine reads -3 LUFS`() {
        val full = tone(listOf(1_000.0), 3.0, amplitude = 1f)
        assertEquals(-3.01, BS1770.integratedLoudness(full, 48_000.0)!!, 0.05)
        assertEquals(-23.01, BS1770.integratedLoudness(FloatArray(full.size) { full[it] * 0.1f }, 48_000.0)!!, 0.05)
        assertEquals(null, BS1770.integratedLoudness(FloatArray(48_000), 48_000.0))
    }
}
