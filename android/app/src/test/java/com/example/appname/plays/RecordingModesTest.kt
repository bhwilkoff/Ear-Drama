package com.example.appname.plays

import java.io.File
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin
import kotlin.random.Random
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The three recording modes (owner ruling 4, 2026-10-29, D3-6), the Kotlin mirror of "The three
 * recording modes" block in js/plays.test.js, same names and the same MOLLY/FIBBER/DOC fixture.
 * Nothing here plays or records sound: the microphone, the speaker and the device voice are fakes.
 *
 * Broken controls, 2026-10-30, each against a mutated copy of plays/, and seen to fail:
 *   PlayScript.partHue taking the hue by script order instead of by size: the golden fails.
 *   Relay.runPlan not stopping after the part's last line (no trim): the run plan test fails.
 *   Relay.runPlan starting at the line itself instead of its cue: the run plan test fails.
 *   Production.discardRun leaving `chosen` on the discarded take: the discard test fails.
 *   ProductionStore.discardRun saving without deleting the files: the Run through test fails on the file count.
 *   RecordingSession.setMode ignoring a run under review: the Run through test fails (the mode must hold).
 *   RecordingSession.pause not bumping the run token: both Pause tests fail (the run goes on past the pause).
 *   RecordingSession.record always ending on Review: the Line by line test fails.
 *   RecordingSession.playCue keeping a take (calling listenAndKeep): the Cue test fails on the file count.
 *   RecordingSession.playCues reading chosenTake instead of usableTake: the flagged-take cue test fails.
 *   RecordingSession.cancel not bumping the cue token: the Cancel test fails (the line is recorded anyway).
 *   RecordingSession.listenAndKeep keeping the stand-in as the take inside a run: the writer refuses it (§5), so the
 *     run never reaches its review and the "no device voice reaches a take in a run" test, and the Run through tests, fail.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class RecordingModesTest {
    private val molly = PartID.role("MOLLY")

    @Test fun `a part's face color - the seven largest speaking parts in a fixed order, the rest neutral (golden on every platform)`() {
        val script = fixtureScript()
        assertEquals(listOf("mystery", "scifi", "western"), listOf("MOLLY", "FIBBER", "DOC").map { script.partHue(PartID.role(it)) })
        assertEquals("directions and sound stand on neutral", listOf(null, null), listOf(script.partHue(PartID.DIRECTIONS), script.partHue(PartID.SOUND)))
        val library = CastableLibrary.decode(File("../../catalog/plays/castable-scripts.json").readText())
        val rodney = library.scripts.firstOrNull { it.id == "gut-28051" }
        if (rodney != null) {
            assertEquals(
                "Caesar Rodney's Ride: the eighth part is neutral",
                listOf("mystery", "scifi", "western", "serial", "documentary", "comedy", "news", null),
                listOf("URIAH", "RODNEY", "MCKEEN", "FRANKLIN", "PRUDENCE", "RUTLEDGE", "TOM", "ANNOUNCER").map { rodney.partHue(PartID.role(it)) },
            )
        }
    }

    @Test fun `a run plan starts at the line's cue and stops after the part's last line`() {
        val script = fixtureScript()
        var p = Production.create(script)
        p = p.add(take("f2", "L0002", PartID.role("FIBBER"), 100))
        fun sources(plan: List<Relay.RunEntry>) = plan.map {
            it.lineID to when (it) {
                is Relay.RunEntry.Mine -> "mine"
                is Relay.RunEntry.TakeEntry -> "take"
                is Relay.RunEntry.Voice -> "voice"
            }
        }
        val plan = Relay.runPlan(p, script, molly, "L0006")
        assertEquals(
            "DOC's cue first, the unrecorded sound skipped, the part's lines its own",
            listOf("L0005" to "voice", "L0006" to "mine", "L0007" to "mine", "L0008" to "voice", "L0009" to "mine", "L0010" to "voice", "L0011" to "mine"),
            sources(plan),
        )
        assertEquals("a cue with a human take plays the take", listOf("L0002" to "take", "L0003" to "mine"), sources(Relay.runPlan(p, script, molly, "L0003")).take(2))
        assertEquals("nothing plays after the part's last line", "L0010", Relay.runPlan(p, script, PartID.role("FIBBER"), "L0008").last().lineID)
        for (e in plan.filterIsInstance<Relay.RunEntry.Voice>()) {
            val fields = e::class.java.declaredFields.map { it.name }.filter { !it.startsWith("$") }.sorted()
            assertEquals("${e.lineID}: words only", listOf("lineID", "part", "text"), fields)
        }
        assertEquals("an unknown line plans nothing", emptyList<Relay.RunEntry>(), Relay.runPlan(p, script, molly, "nope"))
    }

    @Test fun `discarding a run removes its takes and puts each line back on the take it had`() {
        val script = fixtureScript()
        var p = Production.create(script)
        p = p.add(take("old", "L0003", molly, 100)).add(take("r1", "L0003", molly, 100))
            .add(take("r2", "L0006", molly, 100)).add(take("r3", "L0006", molly, 100))
        val (production, gone) = p.discardRun(listOf(RunNote("L0003", "old", listOf("r1")), RunNote("L0006", null, listOf("r2", "r3"))))
        assertEquals("every take the run made goes", listOf("r1", "r2", "r3"), gone.map { it.id }.sorted())
        assertEquals("the take from before the run stays", listOf("old"), production.takes.map { it.id })
        assertEquals("each line is back where it was", mapOf("L0003" to "old"), production.chosen)
    }

    // ---- fakes ----

    /** Reads nothing aloud: every line is a distinct chirp, so a file that holds one can be found. */
    private class SignatureVoice : StandInVoice {
        val rendered = ArrayList<StandInAudio>()
        val texts = ArrayList<String>()
        override suspend fun render(text: String, part: PartID, rate: Float): StandInAudio {
            val f0 = 500.0 + abs(text.hashCode() % 300)
            val samples = FloatArray(24_000) { i ->
                val t = i / 48_000.0
                0.3f * sin(2 * PI * (f0 * t + 2_500 * t * t)).toFloat()
            }
            texts += text
            return StandInAudio(samples, 48_000.0).also { rendered += it }
        }
    }

    /** Plays nothing and records nothing; with [hold] a cue stays "playing" until [release] or [stopPlayback]. */
    private class FakeAudio(val hold: Boolean = false) : LiveAudio {
        private var captured = FloatArray(0)
        private var captures = 0
        val captureCount: Int get() = captures
        private val random = Random(7)
        private var held: CompletableDeferred<Unit>? = null
        val waiting: Boolean get() = held?.isCompleted == false
        var played = 0

        override fun outputRoute() = AudioRoute.Headphones
        override fun start(echoCancelled: Boolean) {}
        override fun stop() {}
        override suspend fun play(cue: CueAudio) {
            played += 1
            if (!hold) return
            val gate = CompletableDeferred<Unit>()
            held = gate
            gate.await()
        }

        fun release() { held?.complete(Unit) }
        override fun stopPlayback() { held?.complete(Unit) }

        override fun beginCapture(onChunk: (FloatArray) -> Unit) {
            captures += 1
            val signal = if (captures == 1) {
                FloatArray(48_000) { random.nextFloat() * 0.001f - 0.0005f }
            } else {
                FloatArray(9_600) + tone(listOf(150.0, 175.0), 0.6) + FloatArray(60_000)
            }
            captured = signal
            for (start in signal.indices step 960) onChunk(signal.copyOfRange(start, minOf(start + 960, signal.size)))
        }

        override fun endCapture(): MicrophoneCapture = MicrophoneCapture(captured, 48_000.0).also { captured = FloatArray(0) }
    }

    private class Rig(val session: RecordingSession, val store: ProductionStore, val audio: FakeAudio, val voice: SignatureVoice) {
        val id: String get() = session.production.value.id
        fun takeFiles(): List<String> = store.takesFolder(id).list()?.toList().orEmpty()
        fun phase() = session.phase.value
    }

    private suspend fun rig(hold: Boolean = false, part: PartID = molly, seed: (Production) -> Production = { it }): Rig {
        val script = fixtureScript()
        val store = ProductionStore(temporaryRoot())
        var p = store.create(script)
        p = seed(Relay.take(part, null, p, script))
        store.save(p)
        val audio = FakeAudio(hold)
        val voice = SignatureVoice()
        val session = RecordingSession(p, script, part, store, audio, voice, wait = {}, announce = {})
        session.begin(echoCancelled = false)
        return Rig(session, store, audio, voice)
    }

    private fun TestScope.tidy(r: Rig) {
        r.session.end()
        r.store.root.deleteRecursively()
    }

    // ---- the modes ----

    @Test fun `Run through records every line of the part in one pass and opens its review - Discard the run deletes the files`() = runTest {
        val r = rig()
        assertTrue("the mode can be set while nothing plays", r.session.setMode(RecordingSession.Mode.Run))
        r.session.runThrough("L0003")
        assertEquals("the run ends on its review", RecordingSession.Phase.RunReview, r.phase())
        assertEquals("every line of the part has a take from the run", listOf("L0003", "L0006", "L0007", "L0009", "L0011"), r.session.runTakes().map { it.lineID })
        assertEquals("the open parts between were read live (FIBBER twice, DOC, FIBBER), the cue before the first line too", 4, r.voice.rendered.size)
        assertFalse("the mode holds while a run is under review", r.session.setMode(RecordingSession.Mode.Step))
        assertEquals("one take file per line", 5, r.takeFiles().size)
        assertTrue("no take holds the device voice", r.session.production.value.takes.none { it.bleed })
        r.session.discardRun()
        assertEquals("back to ready", RecordingSession.Phase.Idle, r.phase())
        assertEquals("the run's files are gone", 0, r.takeFiles().size)
        assertEquals("no line keeps a run take", emptyMap<String, String>(), r.store.production(r.id)!!.chosen)
        assertNull(r.session.run.value)
        tidy(r)
    }

    @Test fun `Keep N takes keeps the run - Again in the review re-records one line and returns to the review`() = runTest {
        val r = rig()
        r.session.setMode(RecordingSession.Mode.Run)
        r.session.runThrough("L0009")
        assertEquals("a run from a later line records from there", listOf("L0009", "L0011"), r.session.runTakes().map { it.lineID })
        val first = r.session.runTakes()[0].id
        r.session.record("L0009")
        assertEquals("Again returns to the run's review", RecordingSession.Phase.RunReview, r.phase())
        assertNotEquals("the review shows the new take", first, r.session.runTakes()[0].id)
        r.session.keepRun()
        val p = r.store.production(r.id)!!
        assertEquals("the run's lines keep their takes", listOf("L0009", "L0011"), p.chosen.keys.sorted())
        assertEquals("the superseded take stays until the person discards unused takes (§8 rule 5)", 3, p.takes.size)
        assertNull("the run is over", r.session.run.value)
        assertEquals(RecordingSession.Phase.Idle, r.phase())
        tidy(r)
    }

    @Test fun `Pause ends a run mid-cue and opens the review of what it took`() = runTest {
        val r = rig(hold = true)
        r.session.setMode(RecordingSession.Mode.Run)
        val running = launch { r.session.runThrough("L0003") }
        runCurrent()
        val cue = r.phase()
        assertTrue("FIBBER's cue is being read", r.audio.waiting && cue is RecordingSession.Phase.Cue && cue.run)
        assertFalse("the mode control is disabled while the run plays", r.session.setMode(RecordingSession.Mode.Lines))
        r.audio.release()
        runCurrent()
        assertTrue("after the first line, the next open part is read", r.audio.waiting)
        r.session.pause()
        running.join()
        assertEquals("Pause opens the review", RecordingSession.Phase.RunReview, r.phase())
        assertEquals("the review holds the one line taken", listOf("L0003"), r.session.runTakes().map { it.lineID })
        tidy(r)
    }

    @Test fun `Pause before any line is taken goes back to ready`() = runTest {
        val r = rig(hold = true)
        r.session.setMode(RecordingSession.Mode.Run)
        val running = launch { r.session.runThrough("L0003") }
        runCurrent()
        r.session.pause()
        running.join()
        assertEquals("nothing to review", RecordingSession.Phase.Idle to null, r.phase() to r.session.run.value)
        tidy(r)
    }

    @Test fun `Line by line ends on the line, ready - Step ends on the take's review`() = runTest {
        val r = rig()
        r.session.setMode(RecordingSession.Mode.Lines)
        r.session.record("L0006")
        assertEquals("Line by line: the line is ready to record again", RecordingSession.Phase.Idle, r.phase())
        assertNotNull("the take is the line's", r.session.production.value.chosen["L0006"])
        r.session.setMode(RecordingSession.Mode.Step)
        r.session.record("L0007")
        assertEquals("Step: the take waits for Keep or Again", RecordingSession.Phase.Review("L0007"), r.phase())
        assertTrue("choosing a mode from a Step review drops back to ready", r.session.setMode(RecordingSession.Mode.Lines))
        assertEquals(RecordingSession.Phase.Idle, r.phase())
        tidy(r)
    }

    @Test fun `Cue and With cue play and keep nothing`() = runTest {
        val r = rig()
        r.session.setMode(RecordingSession.Mode.Lines)
        r.session.playCue("L0006")
        assertEquals("DOC's line was read", 1, r.voice.rendered.size)
        assertEquals("no take was written", 0, r.takeFiles().size)
        r.session.record("L0006")
        val before = r.store.folder(r.id).walkTopDown().count { it.isFile }
        r.session.playWithCue(r.session.production.value.chosenTake("L0006")!!)
        assertEquals("With cue writes nothing", before, r.store.folder(r.id).walkTopDown().count { it.isFile })
        assertEquals("back where it was", RecordingSession.Phase.Idle, r.phase())
        tidy(r)
    }

    @Test fun `Cancel stops the cue before a line and records nothing`() = runTest {
        val r = rig(hold = true)
        r.session.setMode(RecordingSession.Mode.Step)
        val recording = launch { r.session.record("L0003") }
        runCurrent()
        assertTrue("the cue is playing", r.audio.waiting && r.phase() is RecordingSession.Phase.Cue)
        r.session.cancel()
        recording.join()
        assertEquals("back to ready", RecordingSession.Phase.Idle, r.phase())
        assertEquals("no take", 0, r.takeFiles().size)
        assertEquals("the microphone never opened on the line", 1, r.audio.captureCount)
        tidy(r)
    }

    @Test fun `a flagged chosen take is not played as a cue - the device voice reads the line instead`() = runTest {
        val flagged = take("bad", "L0002", PartID.role("FIBBER"), 4_800, bleed = true)
        val r = rig(seed = { it.add(flagged) })
        r.session.playCue("L0003")
        assertEquals("L0002's chosen take is flagged, so the cue is read by the device voice", listOf("Well, Molly."), r.voice.texts)
        tidy(r)
    }

    @Test fun `no device voice reaches a take in a run`() = runTest {
        val r = rig()
        r.session.setMode(RecordingSession.Mode.Run)
        r.session.runThrough("L0003")
        assertEquals("every take was written", RecordingSession.Phase.RunReview, r.phase())
        assertEquals(5, r.takeFiles().size)
        for (file in r.store.takesFolder(r.id).listFiles().orEmpty()) {
            val (samples, rate) = TakeAudio.read(file)
            assertTrue(file.name, r.voice.rendered.none { BleedCheck.score(samples, it.samples, rate) >= BleedCheck.THRESHOLD })
        }
        assertTrue(r.voice.rendered.isNotEmpty())
        tidy(r)
    }
}
