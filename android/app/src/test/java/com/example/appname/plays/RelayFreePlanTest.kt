package com.example.appname.plays

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The free plan (2026-11-23 audit), the mirror of the three "free plan" tests in js/relay.test.js: what an open page costs the
 * one Worker account every app shares. These COUNT asks, on the test scheduler's virtual clock; a pickup that returns nothing
 * is the Worker's 25 s wait.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class RelayFreePlanTest {
    private class Enough : Exception()

    private fun TestScope.loop(active: MutableStateFlow<Boolean>, cap: Int = 400, takeAt: Set<Int> = emptySet(), onAsk: (Int) -> Unit = {}, onIdle: () -> Unit): Pair<PickupLoop, () -> Int> {
        var calls = 0
        val l = PickupLoop(backgroundScope, active, { testScheduler.currentTime }, inbox = {
            calls++
            onAsk(calls)
            if (calls >= cap) throw Enough()
            delay(25_000)
            calls in takeAt
        }, stopOn = { it is Enough }, onIdle = onIdle)
        return l to { calls }
    }

    @Test fun aHiddenReceiverHoldsNoPickupAndStopsAfterThirtyIdleMinutes() = runTest {
        var idle = 0
        val active = MutableStateFlow(false)
        val (l, calls) = loop(active) { idle++ }
        l.start()
        advanceTimeBy(10 * 60 * 1000)
        runCurrent()
        assertEquals("no pickup in 10 hidden minutes", 0, calls())
        active.value = true
        advanceTimeBy(1_000)
        assertTrue("shown again: it asks", calls() >= 1)
        advanceTimeBy(31 * 60 * 1000)
        assertEquals("thirty minutes with no take: it stops and says so once", 1, idle)
        assertTrue(l.stopped)
        assertTrue("pickups in those 30 minutes: ${calls()}", calls() <= 74)
        val at = calls()
        advanceTimeBy(10 * 60 * 1000)
        assertEquals("stopped means no more pickups", at, calls())
    }

    @Test fun aTakeResetsTheIdleClock() = runTest {
        var idle = 0
        val (l, calls) = loop(MutableStateFlow(true), takeAt = setOf(40)) { idle++ }
        l.start()
        advanceTimeBy(80 * 60 * 1000)
        assertEquals(1, idle)
        assertTrue("a take at 16 minutes keeps it receiving past 30: ${calls()} asks", calls() >= 100)
    }

    @Test fun aPageHiddenMidWaitAsksNoMoreUntilItIsBack() = runTest {
        val active = MutableStateFlow(true)
        val (l, calls) = loop(active, onAsk = { n -> if (n == 5) active.value = false }) {}
        l.start()
        advanceTimeBy(200 * 1000)
        runCurrent()
        assertEquals("hidden after the fifth ask", 5, calls())
        advanceTimeBy(20 * 60 * 1000)
        assertEquals(5, calls())
        l.stop()
    }

    private class StubWatch : SeatWire {
        var probes = 0
        override suspend fun home(key: String) = SeatHome(
            SeatHome.Seat("s1", "Lucy"), SeatHome.Klass("c1", "Room 7"),
            listOf(SeatHome.Production("pid-1", "Good Grammar", "gut-0", "r1", listOf(ReadSnapshot.AssignmentRow(PartID.role("MOLLY").raw, "s1")), emptyList())),
        )
        override suspend fun receiver(key: String, pid: String): RelayReceiver { probes++; return RelayReceiver(false, null) }
        override suspend fun send(key: String, pid: String, takeId: String, bytes: ByteArray, meta: JsonObject) { throw ReadFailure("nobody_receiving") }
    }

    private object NoReceiver : MemberReceiverWire { override suspend fun receiver(pid: String) = RelayReceiver(false, null) }

    private fun unusedTransport(): PlaysTransport = java.lang.reflect.Proxy.newProxyInstance(
        PlaysTransport::class.java.classLoader, arrayOf(PlaysTransport::class.java),
    ) { _, _, _ -> error("unused") } as PlaysTransport

    @Test fun aBackgroundedAppAsksNothingWhenARetryComesDue() = runTest {
        for (foreground in listOf(false, true)) {
            val script = fixtureScript()
            val store = ProductionStore(temporaryRoot())
            var p = store.create(script)
            val wire = StubWatch()
            val tick = MutableSharedFlow<Unit>()
            val hub = RelayHub(store, backgroundScope, wire, unusedTransport(), NoReceiver, MemorySeatVault(), { null }, pause = { tick.first() })
            hub.linkSeat(p.id, "pid-1", "c1", "Lucy", "k".repeat(24), listOf(ReadSnapshot.AssignmentRow(PartID.role("MOLLY").raw, "s1")))
            store.takesFolder(p.id).mkdirs()
            java.io.File(store.takesFolder(p.id), "L0003.wav").writeBytes(ByteArray(4_844) { 1 })
            p = p.add(Take("T-L0003", "L0003", script.lines.first { it.id == "L0003" }.part, "L0003.wav", 0.0, 4_800, 48_000.0, Take.Capture.Direct, emptyMap(), null, 0.1f, false))
            store.save(p)
            hub.setForeground(foreground)
            hub.kick(p.id)
            assertEquals("a kick asks once", 1, wire.probes)
            repeat(12) { runCurrent(); tick.emit(Unit) }
            runCurrent()
            if (foreground) assertTrue("shown: the retries keep asking (control)", wire.probes > 1)
            else {
                assertEquals("backgrounded: 12 retries came due and none asked", 1, wire.probes)
                hub.setForeground(true)
                runCurrent()
                assertEquals("coming forward asks at once", 2, wire.probes)
            }
            hub.stop()
        }
    }
}
