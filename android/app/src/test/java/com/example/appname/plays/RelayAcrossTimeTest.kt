package com.example.appname.plays

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Relay across time (PLAYS-DESIGN §12.11), the mirror of js/relay.test.js and apple/Tests/RelayTests.swift: the sender's
 * queue and its states, a seat's source over a stub Worker, and the consent rule's list. Nothing is recorded aloud or sent
 * anywhere; the clock is a function the test owns (it records the asks and never fires). Each rule's break, seen to fail
 * (2026-11-19):
 *   RelayCore.delay returning GAPS[0]: backoffGrowsThenHolds failed.
 *   RelaySender.run taking probe.receiving as true: nothingIsSentWhileTheReceiverIsAway failed.
 *   LATER without "nobody_receiving": aTakeTheReceiverWasNotThereForStays failed.
 *   assignedLines ignoring `to`: aSceneRange failed.
 *   SeatRelaySource.pending without the assigned-lines filter: onlyAssignedLines failed.
 *   SeatRelaySource.pending without `!it.bleed`: aTakeTheWorkerHoldsIsNotSentAgainAndAFlaggedTakeNeverLeaves failed.
 *   performers without credits: aCreditedMakerBlocksPublish failed.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class RelayAcrossTimeTest {
    private val script = fixtureScript()
    private val cast = script.lines.map { it.id to it.part.raw }
    private val molly = PartID.role("MOLLY").raw
    private val whole = listOf(ReadSnapshot.AssignmentRow(molly, "s1"))
    private val key = "k".repeat(24)

    private class StubSeat(var assignments: List<ReadSnapshot.AssignmentRow>) : SeatWire {
        var receiving = false
        var name: String? = "Ms. Ortiz"
        val taken = ArrayList<String>()
        val sends = ArrayList<String>()
        var probes = 0
        var failWith: String? = null

        override suspend fun home(key: String) = SeatHome(
            SeatHome.Seat("s1", "Lucy"), SeatHome.Klass("c1", "Room 7"),
            listOf(SeatHome.Production("pid-1", "Good Grammar", "gut-0", "r1", assignments, taken.map { SeatTake(it, "x", true) })),
        )
        override suspend fun receiver(key: String, pid: String): RelayReceiver { probes++; return RelayReceiver(receiving, name) }
        override suspend fun send(key: String, pid: String, takeId: String, bytes: ByteArray, meta: JsonObject) {
            sends += meta.getValue("lineID").jsonPrimitive.content
            failWith?.let { throw ReadFailure(it) }
            if (!receiving) throw ReadFailure("nobody_receiving")
            taken += takeId
        }
    }

    private class Rig(val store: ProductionStore, val id: String, val hub: RelayHub, val vault: MemorySeatVault, val asked: ArrayList<Long>)

    private fun CoroutineScopeHolder.rig(wire: StubSeat, lines: List<String>, flagged: List<String> = emptyList(), assignments: List<ReadSnapshot.AssignmentRow> = whole): Rig {
        val store = ProductionStore(temporaryRoot())
        var p = store.create(script)
        val vault = MemorySeatVault()
        val asked = ArrayList<Long>()
        val hub = RelayHub(store, scope, wire, FakeTransport, FakeReceiver, vault, { null }, pause = { ms -> asked += ms; awaitCancellation() })
        hub.linkSeat(p.id, "pid-1", "c1", "Lucy", key, assignments)
        for (id in lines) {
            val file = "$id.wav"
            store.takesFolder(p.id).mkdirs()
            java.io.File(store.takesFolder(p.id), file).writeBytes(ByteArray(4_844) { 1 })
            p = p.add(Take("T-$id", id, script.lines.first { it.id == id }.part, file, 0.0, 4_800, 48_000.0, Take.Capture.Direct, emptyMap(), null, 0.1f, id in flagged))
        }
        store.save(p)
        return Rig(store, p.id, hub, vault, asked)
    }

    private class CoroutineScopeHolder(val scope: kotlinx.coroutines.CoroutineScope)

    private object FakeReceiver : MemberReceiverWire { override suspend fun receiver(pid: String) = RelayReceiver(false, null) }
    private object FakeTransport : PlaysTransport {
        override suspend fun consent() = error("unused")
        override suspend fun create(body: JsonObject) = error("unused")
        override suspend fun list() = error("unused")
        override suspend fun get(pid: String) = error("unused")
        override suspend fun invite(pid: String) = error("unused")
        override suspend fun viewInvite(token: String) = error("unused")
        override suspend fun joinByInvite(token: String, part: String, displayName: String?) = error("unused")
        override suspend fun claim(pid: String, part: String) = error("unused")
        override suspend fun partAction(pid: String, part: String, action: String) = error("unused")
        override suspend fun agree(pid: String, version: String) = error("unused")
        override suspend fun upload(pid: String, takeId: String, bytes: ByteArray, meta: JsonObject) = error("unused")
        override suspend fun nextTake(pid: String) = error("unused")
        override suspend fun choose(pid: String, takeId: String) = error("unused")
        override suspend fun publish(pid: String) = error("unused")
        override suspend fun removeLine(pid: String, lineId: String, reason: String) = error("unused")
        override suspend fun report(pid: String, takeId: String?, userId: String?, reason: String, note: String?) = error("unused")
        override suspend fun block(userId: String) = error("unused")
        override suspend fun classes() = error("unused")
        override suspend fun classDetail(id: String) = error("unused")
        override suspend fun createClass(name: String, under13: Boolean) = error("unused")
        override suspend fun joinClass(code: String, displayName: String?) = error("unused")
    }

    @Test fun theWordsAreOneFactPerState() {
        assertEquals("On this device · sends when Ms. Ortiz is in Ear Drama", RelayCore.wording(RelayCore.State.Waiting, "Ms. Ortiz"))
        assertEquals("On this device · sends when your teacher is in Ear Drama", RelayCore.wording(RelayCore.State.Waiting, null, "your teacher"))
        assertEquals("Sent", RelayCore.wording(RelayCore.State.Sent, "x"))
        assertEquals("Sending", RelayCore.wording(RelayCore.State.Sending, "x"))
        assertEquals(RelayCore.State.Sent, RelayCore.state("a", setOf("a"), "a"))
        assertEquals(RelayCore.State.Sending, RelayCore.state("b", setOf("a"), "b"))
        assertEquals(RelayCore.State.Waiting, RelayCore.state("c", setOf("a"), "b"))
    }

    @Test fun backoffGrowsThenHolds() {
        assertEquals(listOf(5_000L, 10_000L, 20_000L, 40_000L, 60_000L, 60_000L, 60_000L), listOf(0, 1, 2, 3, 4, 5, 20).map(RelayCore::delay))
    }

    @Test fun aSceneRange() {
        assertEquals(listOf("L0006", "L0007", "L0009"), RelayCore.assignedLines(cast, listOf(ReadSnapshot.AssignmentRow(molly, "s1", "L0006", "L0009"))))
        assertEquals(listOf("L0003", "L0006", "L0007", "L0009", "L0011"), RelayCore.assignedLines(cast, whole))
        assertTrue(RelayCore.assignedLines(cast, emptyList()).isEmpty())
    }

    @Test fun nothingIsSentWhileTheReceiverIsAway() = runTest {
        val wire = StubSeat(whole)
        val r = CoroutineScopeHolder(backgroundScope).rig(wire, listOf("L0003", "L0006"))
        r.hub.kick(r.id)
        assertTrue(wire.sends.isEmpty())
        assertEquals(1, wire.probes)
        runCurrent()
        assertEquals(listOf(5_000L), r.asked)
        val sender = r.hub.sender(r.id)!!
        assertEquals(1, sender.state.value.failures)
        assertEquals(RelayCore.State.Waiting, r.hub.state(r.id, "T-L0003").first)
        assertEquals("Ms. Ortiz", sender.state.value.name)
        wire.receiving = true
        r.hub.kick(r.id)
        assertEquals(listOf("L0003", "L0006"), wire.sends)
        assertEquals(RelayCore.State.Sent, r.hub.state(r.id, "T-L0003").first)
        assertEquals(listOf("T-L0003", "T-L0006"), r.store.share(r.id)?.sent)
        assertTrue(r.store.readTake(r.id, r.store.production(r.id)!!.takes.first().file).size > 44)
    }

    @Test fun aTakeTheReceiverWasNotThereForStays() = runTest {
        val wire = StubSeat(whole)
        wire.receiving = true
        val r = CoroutineScopeHolder(backgroundScope).rig(wire, listOf("L0003"))
        wire.failWith = "nobody_receiving"
        r.hub.kick(r.id)
        assertEquals(listOf("L0003"), wire.sends)
        assertEquals(RelayCore.State.Waiting, r.hub.state(r.id, "T-L0003").first)
        assertTrue(r.store.share(r.id)!!.sent.isEmpty())
        assertEquals(1, r.hub.sender(r.id)!!.state.value.failures)
    }

    @Test fun aFinalRefusalLeavesTheQueueOnceAndStaysOnTheDevice() = runTest {
        val wire = StubSeat(whole)
        wire.receiving = true
        wire.failWith = "not_assigned"
        val r = CoroutineScopeHolder(backgroundScope).rig(wire, listOf("L0003"))
        r.hub.kick(r.id)
        assertEquals("not_assigned", r.store.share(r.id)!!.refused["T-L0003"])
        r.hub.kick(r.id)
        assertEquals(1, wire.sends.size)
        assertEquals(1, r.store.production(r.id)!!.takes.size)
    }

    @Test fun onlyAssignedLines() = runTest {
        val range = listOf(ReadSnapshot.AssignmentRow(molly, "s1", "L0006", "L0006"))
        val wire = StubSeat(range)
        wire.receiving = true
        val r = CoroutineScopeHolder(backgroundScope).rig(wire, listOf("L0003", "L0006"), assignments = range)
        r.hub.kick(r.id)
        assertEquals(listOf("L0006"), wire.sends)
    }

    @Test fun aTakeTheWorkerHoldsIsNotSentAgainAndAFlaggedTakeNeverLeaves() = runTest {
        val wire = StubSeat(whole)
        wire.receiving = true
        wire.taken += "T-L0003"
        val r = CoroutineScopeHolder(backgroundScope).rig(wire, listOf("L0003", "L0006", "L0011"), flagged = listOf("L0011"))
        r.hub.kick(r.id)
        assertEquals(listOf("L0006"), wire.sends)
    }

    @Test fun theSeatKeyIsInTheVaultNeverInShareJson() {
        val store = ProductionStore(temporaryRoot())
        val p = store.create(script)
        val vault = MemorySeatVault()
        val hub = RelayHub(store, kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Job()), StubSeat(whole), FakeTransport, FakeReceiver, vault, { null })
        hub.linkSeat(p.id, "pid-1", "c1", "Lucy", key, whole)
        assertFalse(java.io.File(store.folder(p.id), "share.json").readText().contains(key))
        assertEquals(key, vault.key("c1"))
    }

    @Test fun rowsCarryTheStateOfEachLine() {
        val store = ProductionStore(temporaryRoot())
        var p = store.create(script)
        for (id in listOf("L0003", "L0006")) p = p.add(take("T-$id", id, PartID.role("MOLLY"), 4_800))
        val lines = script.lines.filter { it.part.raw == molly }.take(3)
        val remote = mapOf("L0003" to SeatTake("T-L0003", "L0003", true, SeatReview("again", "Slower.")))
        val rows = RelayCore.rows(lines, p, remote, emptySet(), emptyMap(), null, "Ms. Ortiz")
        assertEquals("Sent", rows[0].state)
        assertEquals("Again · Slower.", rows[0].review)
        assertTrue(rows[0].again)
        assertEquals("On this device · sends when Ms. Ortiz is in Ear Drama", rows[1].state)
        assertEquals(null, rows[2].state)
    }

    @Test fun aCreditedMakerBlocksPublish() {
        val rec = SharedRecord("p", "gut-0", "r1", "T", director = "dee", members = listOf(SharedMember("dee", "Dee", director = true, performer = false, consented = true)))
        val withCredit = rec.copy(credits = listOf(SharedCredit("Ann", 2, false)))
        assertEquals(listOf("Ann"), PlaysShare.performers(withCredit).map { it.displayName })
        assertEquals(listOf("Ann"), PlaysShare.waitingOn(withCredit).map { it.displayName })
        assertTrue(PlaysShare.waitingOn(rec).isEmpty())
        val decoded = ShareJson.decodeFromString<SharedRecord>("""{"id":"p","scriptID":"g","scriptRevision":"r","title":"T","credits":[{"name":"Ann","lines":2}]}""")
        assertNotNull(decoded.credits.firstOrNull())
    }
}
