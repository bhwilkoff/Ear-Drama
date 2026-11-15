package com.example.appname.plays

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin
import kotlin.random.Random
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The studio inside the reader (PLAYS-DESIGN §2.9, ANDROID-DESIGN §4.17; Decision 076 S3), the Kotlin mirror of
 * js/studio.test.js, case for case, over the SHIPPED RecordingSession and take model with fakes that play and record
 * nothing: the current line and how each mode moves it, the take state each of my lines shows, choosing a take,
 * deleting one (never the chosen one), Delete unused takes for one part only, Record again keeping every older take,
 * the line the studio opens at, and the production the reader's Record continues.
 *
 * Seen to fail, 2026-11-15, before plays/StudioCore.kt existed (every case), and against mutated copies:
 *   StudioController.keep leaving the current line where it was: the Step case fails.
 *   Production.deleteTake without the chosen-take refusal: the delete case and the Production case fail.
 *   Production.discardUnused ignoring its line set: the part-scoped case and the Production case fail.
 *   Production.add replacing the line's takes instead of adding one: the Record again case fails.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class StudioTest {
    private val molly = PartID.role("MOLLY")
    private val fibber = PartID.role("FIBBER")

    // ---- fakes ----

    private class ChirpVoice : StandInVoice {
        override suspend fun render(text: String, part: PartID, rate: Float): StandInAudio {
            val f0 = 500.0 + abs(text.hashCode() % 300)
            val samples = FloatArray(24_000) { i ->
                val t = i / 48_000.0
                0.3f * sin(2 * PI * (f0 * t + 2_500 * t * t)).toFloat()
            }
            return StandInAudio(samples, 48_000.0)
        }
    }

    private class FakeAudio : LiveAudio {
        private var captured = FloatArray(0)
        private var captures = 0
        private val random = Random(7)
        override fun outputRoute() = AudioRoute.Headphones
        override fun start(echoCancelled: Boolean) {}
        override fun stop() {}
        override suspend fun play(cue: CueAudio) {}
        override fun beginCapture(onChunk: (FloatArray) -> Unit) {
            captures += 1
            val signal = if (captures == 1) FloatArray(48_000) { random.nextFloat() * 0.001f - 0.0005f }
            else FloatArray(9_600) + tone(listOf(150.0, 175.0), 0.6) + FloatArray(60_000)
            captured = signal
            for (start in signal.indices step 960) onChunk(signal.copyOfRange(start, minOf(start + 960, signal.size)))
        }
        override fun endCapture(): MicrophoneCapture = MicrophoneCapture(captured, 48_000.0).also { captured = FloatArray(0) }
    }

    private class Rig(val studio: StudioController, val session: RecordingSession, val store: ProductionStore) {
        val id: String get() = session.production.value.id
    }

    private suspend fun rig(part: PartID = molly, line: String? = null, seed: (Production) -> Production = { it }): Rig {
        val script = fixtureScript()
        val store = ProductionStore(temporaryRoot())
        var p = store.create(script)
        p = seed(Relay.take(part, null, p, script))
        store.save(p)
        val session = RecordingSession(p, script, part, store, FakeAudio(), ChirpVoice(), wait = {}, announce = {})
        session.begin(echoCancelled = false)
        return Rig(StudioController(session, store, line), session, store)
    }

    private fun tidy(r: Rig) {
        r.session.end()
        r.store.root.deleteRecursively()
    }

    private fun add(p: Production, id: String, line: String, part: PartID, bleed: Boolean = false) =
        p.add(take(id, line, part, 1, bleed = bleed))

    // ---- the current line and the take states ----

    @Test fun `the studio opens at the part's first line with no take, or at the line asked for`() {
        val script = fixtureScript()
        var p = Production.create(script)
        assertEquals("no takes: the part's first line", "L0003", StudioCore.startLine(p, script, molly, null))
        p = add(p, "a", "L0003", molly)
        assertEquals("the first line still without a take", "L0006", StudioCore.startLine(p, script, molly, null))
        assertEquals("a line of the part that was asked for wins", "L0009", StudioCore.startLine(p, script, molly, "L0009"))
        assertEquals("another part's line is not mine to record", "L0006", StudioCore.startLine(p, script, molly, "L0002"))
        for (id in listOf("L0006", "L0007", "L0009", "L0011")) p = add(p, "t$id", id, molly)
        assertEquals("every line taken: the first line", "L0003", StudioCore.startLine(p, script, molly, null))
    }

    @Test fun `each of my lines shows none, its takes with the chosen one, or the flag`() {
        val script = fixtureScript()
        var p = Production.create(script)
        assertEquals("no take", StudioCore.LineState(StudioCore.LineState.Kind.None, 0, 0), StudioCore.lineState(p, "L0003"))
        p = add(add(p, "a", "L0003", molly), "b", "L0003", molly)
        assertEquals("the newest take is chosen", StudioCore.LineState(StudioCore.LineState.Kind.Chosen, 2, 2), StudioCore.lineState(p, "L0003"))
        p = p.choose("a")
        assertEquals("choosing an older take", StudioCore.LineState(StudioCore.LineState.Kind.Chosen, 2, 1), StudioCore.lineState(p, "L0003"))
        p = add(p, "c", "L0003", molly, bleed = true)
        assertEquals("a flagged chosen take", StudioCore.LineState(StudioCore.LineState.Kind.Flagged, 3, 3), StudioCore.lineState(p, "L0003"))
        assertEquals("No take", StudioCore.spoken(StudioCore.lineState(Production.create(script), "L0003")))
        assertEquals("3 takes, take 3 chosen is a flag here", "Re-take: the microphone heard the device voice", StudioCore.spoken(StudioCore.lineState(p, "L0003")))
        assertEquals("3 takes, take 1 chosen", "3 takes, take 1 chosen", StudioCore.spoken(StudioCore.LineState(StudioCore.LineState.Kind.Chosen, 3, 1)))
        assertEquals("Take 2 of 3", StudioCore.takesLabel(StudioCore.LineState(StudioCore.LineState.Kind.Chosen, 3, 2)))
    }

    @Test fun `Next and Previous move by my lines only, from wherever the current line is`() = runTest {
        val r = rig()
        val st = r.studio
        assertEquals("opens at the first line", "L0003", st.current.value)
        st.move(1); assertEquals("next of mine skips the others", "L0006", st.current.value)
        st.move(1); st.move(1); st.move(1); assertEquals("to the last", "L0011", st.current.value)
        st.move(1); assertEquals("stays on the last", "L0011", st.current.value)
        st.move(-1); assertEquals("previous", "L0009", st.current.value)
        assertFalse("another part's line cannot be current", st.select("L0008"))
        assertEquals("unchanged", "L0009", st.current.value)
        assertTrue("a tap on one of my lines", st.select("L0006"))
        assertEquals("it is current", "L0006", st.current.value)
        tidy(r)
    }

    // ---- the three ways the reader moves ----

    @Test fun `Step - a take opens its review, Keep makes my next line current and waits`() = runTest {
        val r = rig()
        r.session.setMode(RecordingSession.Mode.Step)
        r.studio.primary()
        assertEquals("the take's review", RecordingSession.Phase.Review("L0003"), r.session.phase.value)
        assertEquals("still on the line just taken", "L0003", r.studio.current.value)
        r.studio.keep()
        assertEquals("Keep moves to my next line", "L0006", r.studio.current.value)
        assertEquals("and waits for a tap", RecordingSession.Phase.Idle, r.session.phase.value)
        assertEquals("it did not record the next line", StudioCore.LineState.Kind.None, r.studio.lineState("L0006").state)
        tidy(r)
    }

    @Test fun `Line by line - after a take the line stays current, ready to record again`() = runTest {
        val r = rig()
        r.session.setMode(RecordingSession.Mode.Lines)
        r.studio.select("L0007")
        r.studio.primary()
        assertEquals("ready", RecordingSession.Phase.Idle, r.session.phase.value)
        assertEquals("the same line", "L0007", r.studio.current.value)
        assertEquals("one take", 1, r.studio.lineState("L0007").takes)
        tidy(r)
    }

    @Test fun `Run through - the current line follows the run through my lines, which record as they come`() = runTest {
        val r = rig()
        r.session.setMode(RecordingSession.Mode.Run)
        r.studio.select("L0006")
        val seen = ArrayList<String>()
        r.studio.onFollow = { seen += it }
        r.studio.primary()
        assertEquals("the run ends on its review", RecordingSession.Phase.RunReview, r.session.phase.value)
        assertEquals("every line of mine from the current one", listOf("L0006", "L0007", "L0009", "L0011"), r.session.runTakes().map { it.lineID })
        assertTrue("the reader followed the other parts' lines as they were heard", "L0005" in seen && "L0008" in seen)
        assertEquals("the current line followed to my last line", "L0011", r.studio.current.value)
        r.studio.keep()
        assertNull("Keep keeps the run", r.session.run.value)
        tidy(r)
    }

    // ---- takes: choose, delete, delete unused, record again ----

    @Test fun `Record again keeps every older take and chooses the new one`() = runTest {
        val r = rig()
        r.session.setMode(RecordingSession.Mode.Lines)
        r.studio.primary()
        val first = r.studio.takes("L0003").map { it.id }
        r.studio.again()
        val takes = r.studio.takes("L0003")
        assertEquals("two takes", 2, takes.size)
        assertEquals("the first take is still there", first[0], takes[0].id)
        assertEquals("the new take is chosen", takes[1].id, r.store.production(r.id)!!.chosen["L0003"])
        tidy(r)
    }

    @Test fun `choosing a take never deletes - only an unchosen take can be deleted, by the person`() = runTest {
        val r = rig()
        r.session.setMode(RecordingSession.Mode.Lines)
        r.studio.primary()
        r.studio.again()
        val (a, b) = r.studio.takes("L0003")
        r.studio.choose(a)
        assertEquals("chosen", a.id, r.store.production(r.id)!!.chosen["L0003"])
        assertEquals("choosing deleted nothing", 2, r.studio.takes("L0003").size)
        assertFalse("the chosen take is refused", r.studio.deleteTake(a))
        assertEquals("still two", 2, r.studio.takes("L0003").size)
        assertTrue("an unchosen take goes", r.studio.deleteTake(b))
        assertEquals("one left", listOf(a.id), r.studio.takes("L0003").map { it.id })
        assertFalse("its file is gone", r.store.takesFolder(r.id).list().orEmpty().contains(b.file))
        assertTrue("the chosen take's file stays", r.store.takesFolder(r.id).list().orEmpty().contains(a.file))
        assertEquals("the session reads the record without it", 1, r.session.production.value.takes.size)
        tidy(r)
    }

    @Test fun `Delete unused takes removes only this part's unchosen takes`() = runTest {
        val r = rig(seed = { p ->
            add(add(p, "f1", "L0010", fibber), "f2", "L0010", fibber)
        })
        r.session.setMode(RecordingSession.Mode.Lines)
        r.studio.primary()
        r.studio.again()
        r.studio.move(1)
        r.studio.primary()
        assertEquals("one unused take of mine", 1, r.studio.unused.size)
        val gone = r.studio.deleteUnused()
        assertEquals("one deleted", 1, gone)
        val after = r.store.production(r.id)!!
        assertEquals("another part's unused take stays", listOf("f1", "f2"), after.takes.filter { it.part == fibber }.map { it.id })
        assertEquals("my line keeps its chosen take", 1, r.studio.takes("L0003").size)
        assertEquals("and the other", 1, r.studio.takes("L0006").size)
        tidy(r)
    }

    @Test fun `Production deleteTake refuses the chosen take and discardUnused takes a line set`() {
        val script = fixtureScript()
        var p = Production.create(script)
        p = add(add(p, "a", "L0003", molly), "b", "L0003", molly)
        p = add(add(p, "c", "L0002", fibber), "d", "L0002", fibber)
        assertEquals("the chosen take stays", emptyList<Take>(), p.deleteTake("b").second)
        val r = p.deleteTake("a")
        assertEquals("an unchosen take goes", listOf("a"), r.second.map { it.id })
        assertEquals("the rest stay", listOf("b", "c", "d"), r.first.takes.map { it.id })
        assertEquals("an unknown take is nothing", emptyList<Take>(), p.deleteTake("zzz").second)
        assertEquals("only the lines named", listOf("a"), p.discardUnused(setOf("L0003")).second.map { it.id })
        assertEquals("no set: every line, as the cast sheet does", listOf("a", "c"), p.discardUnused().second.map { it.id })
    }

    @Test fun `the store deletes the file of the take and refuses the chosen one`() = runTest {
        val r = rig()
        r.session.setMode(RecordingSession.Mode.Lines)
        r.studio.primary()
        r.studio.again()
        val (a, b) = r.studio.takes("L0003")
        assertFalse(r.store.deleteTake(r.id, b.id))
        assertTrue(r.store.deleteTake(r.id, a.id))
        assertEquals(listOf(b.file), r.store.takesFolder(r.id).list().orEmpty().toList())
        assertEquals(0, r.store.discardUnusedTakes(r.id, setOf("L0003")))
        tidy(r)
    }

    // ---- where the reader's Record records ----

    @Test fun `the reader's Record continues the part, else takes it where it is open, else makes a production`() {
        val script = fixtureScript()
        fun mk(id: String, created: Double, parts: Map<PartID, PartState> = emptyMap()) =
            Production.create(script, id).copy(created = created, parts = parts)
        val notShared = { _: String -> false }
        assertEquals("nothing yet: a new production", StudioCore.Pick.Make, StudioCore.productionFor(emptyList(), notShared, script, molly))
        val open = mk("p1", 1.0)
        assertEquals("an open part is taken", StudioCore.Pick.Take("p1"), StudioCore.productionFor(listOf(open), notShared, script, molly))
        val busy = mk("p2", 2.0, mapOf(fibber to PartState(PartState.Status.Recording)))
        assertEquals("not where another part records", StudioCore.Pick.Take("p1"), StudioCore.productionFor(listOf(busy, open), notShared, script, molly))
        val mine = mk("p3", 0.0, mapOf(molly to PartState(PartState.Status.Recording)))
        assertEquals("the part already recording wins", StudioCore.Pick.Resume("p3"), StudioCore.productionFor(listOf(busy, open, mine), notShared, script, molly))
        assertEquals("never a shared production", StudioCore.Pick.Take("p1"), StudioCore.productionFor(listOf(busy, open, mine), { it == "p3" }, script, molly))
        val other = mk("p4", 9.0).copy(scriptID = "gut-9")
        assertEquals("never another play's", StudioCore.Pick.Make, StudioCore.productionFor(listOf(other), notShared, script, molly))
        val done = mk("p5", 9.0, mapOf(molly to PartState(PartState.Status.Done)))
        assertEquals("a part already done is not reopened from the reader", StudioCore.Pick.Make, StudioCore.productionFor(listOf(done), notShared, script, molly))
    }
}
