package com.example.appname.plays

import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpMethod
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import kotlin.math.PI
import kotlin.math.sin
import kotlin.random.Random
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Record in the room (PLAYS-DESIGN §12.10) over fakes that open no microphone and play nothing: the client helpers
 * (shouldRecord, settleJustDid, takeRows, readerName), the refusal words for a reading that ended or never was, the record
 * flow (a holder records and the take goes to the receiver, the outbox waits on nobody_receiving and sends later, Again re-arms,
 * One microphone credits the part and moves on), the receiver's pickup, Publish's file loop, a TV's pairing poll, and the
 * studio engine's `recordInRoom`.
 *
 * Seen to fail, 2026-11-19, against a broken copy of each rule (the one named, then restored):
 *   ReadCore.shouldRecord without the receiver check: the receiver case failed.
 *   ReadCore.settleJustDid never clearing: the Again case failed (no second take).
 *   ReadRecord.LATER without nobody_receiving: the outbox case failed (the take left the outbox).
 *   RoomPublish treating not_ready as a stop: the not_ready case failed.
 *   ReadPairing keeping an expired pair: the expiry case failed.
 *   ReadSnapshot.openVoiceLine ignoring read_open: the screen's voice case failed.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ReadRoomTest {
    private val script = fixtureScript()
    private val cast = script.lines.map { it.id to it.part.raw }
    private val molly = PartID.role("MOLLY")
    private val fibber = PartID.role("FIBBER")

    private fun snap(
        cursor: String,
        mode: String = "record",
        youId: String = "ann",
        role: String = "reader",
        receives: Boolean = false,
        leads: Boolean = false,
        done: List<String> = emptyList(),
        gen: Int = 1,
        readOpen: Boolean = false,
        ended: Boolean = false,
        kind: String = "adult",
        seats: List<ReadSnapshot.Seat> = emptyList(),
        assignments: List<ReadSnapshot.AssignmentRow> = emptyList(),
        members: List<ReadSnapshot.Member> = listOf(
            ReadSnapshot.Member("host", "reader", name = "Ben"), ReadSnapshot.Member("ann", "reader", name = "Ann"), ReadSnapshot.Member("tv", "screen"),
        ),
        claims: Map<String, String> = mapOf("role:MOLLY" to "ann", "role:FIBBER" to "host"),
        productionId: String? = null,
        readsNow: ReadSnapshot.ReadsNow? = null,
    ) = ReadSnapshot(
        code = "ABC123", kind = kind, mode = mode, cursor = cursor, cursorGen = gen, generation = gen, ended = ended,
        leader = "host", readOpen = readOpen, productionId = productionId,
        you = ReadSnapshot.You(youId, role, leads = leads, receives = receives),
        members = members, receiver = "host", claims = claims, done = done, seats = seats, assignments = assignments, readsNow = readsNow,
        scriptId = script.id, serverTime = gen * 1000.0,
    )

    // ---- the client's own rules ----

    @Test fun `a holder at the cursor opens the microphone, nobody else does`() {
        val ann = snap("L0003")
        assertTrue("ann holds MOLLY, at the cursor, in Record", ReadCore.shouldRecord(ann, cast, null))
        assertFalse("another part's line", ReadCore.shouldRecord(snap("L0002"), cast, null))
        assertFalse("not in Table read", ReadCore.shouldRecord(snap("L0003", mode = "read"), cast, null))
        assertFalse("a line the room marked done", ReadCore.shouldRecord(snap("L0003", done = listOf("L0003")), cast, null))
        assertFalse("not twice for the same arming", ReadCore.shouldRecord(ann, cast, "L0003"))
        assertFalse("a screen records nothing", ReadCore.shouldRecord(snap("L0003", role = "screen"), cast, null))
        assertFalse("an ended room", ReadCore.shouldRecord(snap("L0003", ended = true), cast, null))
        val host = snap("L0002", youId = "host", receives = true, leads = true)
        assertFalse("the receiver records only in One microphone, never as a holder", ReadCore.shouldRecord(host, cast, null))
    }

    @Test fun `justDid is kept while the line stays undone at the cursor, else cleared`() {
        assertEquals("L0003", ReadCore.settleJustDid(snap("L0003"), "L0003"))
        assertNull("the room marked it done", ReadCore.settleJustDid(snap("L0003", done = listOf("L0003")), "L0003"))
        assertNull("the cursor moved on", ReadCore.settleJustDid(snap("L0006"), "L0003"))
        assertNull(ReadCore.settleJustDid(snap("L0003"), null))
    }

    @Test fun `the Takes sheet lists each speaking line with its state and counts per reader`() {
        val s = snap("L0003", done = listOf("L0003", "L0006"), claims = mapOf("role:MOLLY" to "ann"))
        val (rows, counts) = ReadCore.takeRows(s, cast, arrived = setOf("L0003"), speaking = { PartID(it).isSpeaking })
        val by = rows.associate { it.line to it.state }
        assertEquals(listOf("L0002", "L0003", "L0005", "L0006", "L0007", "L0008", "L0009", "L0010", "L0011"), rows.map { it.line })
        assertEquals(ReadCore.TakeState.Recorded, by["L0003"])
        assertEquals("done, the take not here", ReadCore.TakeState.Away, by["L0006"])
        assertEquals("held, not yet read", ReadCore.TakeState.Waiting, by["L0007"])
        assertEquals("nobody holds FIBBER", ReadCore.TakeState.Open, by["L0002"])
        assertEquals(listOf(ReadCore.TakeCount("member:ann", null, "ann", 5, 1)), counts)
    }

    @Test fun `a reader is named by their seat or the name they gave`() {
        val adult = snap("L0003", readsNow = ReadSnapshot.ReadsNow("role:MOLLY", holder = "ann", members = listOf("ann")))
        assertEquals("Ann", ReadCore.readerName(adult, ReadCore.Reads("role:MOLLY", null, "ann", listOf("ann"))))
        val seats = listOf(ReadSnapshot.Seat("s1", "Lucy"))
        val klass = snap("L0003", kind = "class", seats = seats)
        assertEquals("Lucy", ReadCore.readerName(klass, ReadCore.Reads("role:MOLLY", "s1", null, emptyList())))
        assertNull(ReadCore.readerName(adult, ReadCore.Reads("role:DOC", null, null, emptyList())))
    }

    @Test fun `a reading that ended or never was says so, never could not be reached`() {
        assertEquals("No reading with that code.", ReadCore.refusal("no_such_room"))
        assertEquals("This reading has ended.", ReadCore.refusal("room_ended"))
        assertEquals("That name is not allowed.", ReadCore.refusal("bad_name"))
        assertEquals("No screen shows that code.", ReadCore.refusal("no_such_pair"))
        assertEquals("That code has expired.", ReadCore.refusal("pair_expired"))
    }

    /** The shared client keeps the Worker's own code: a 404 and a 410 reach the join screen as their own words. */
    @Test fun `the client keeps the Worker's code for a missing and an ended room`() = runTest {
        val engine = MockEngine { request ->
            val path = request.url.encodedPath
            val (status, body) = when {
                path.endsWith("/ZZZZZZ/join") -> HttpStatusCode.NotFound to """{"error":"no_such_room"}"""
                path.endsWith("/ENDED1/join") -> HttpStatusCode.Gone to """{"error":"room_ended"}"""
                else -> HttpStatusCode.OK to "{}"
            }
            respond(body, status, headersOf(HttpHeaders.ContentType, "application/json"))
        }
        val worker = com.example.appname.account.WorkerApi(
            HttpClient(engine), com.example.appname.account.WorkerConfig("https://worker.test", "web", "svc", "https://eardrama.org/"),
            object : com.example.appname.account.SessionStore {
                override fun load(): com.example.appname.account.StoredAccount? = null
                override fun save(account: com.example.appname.account.StoredAccount?) {}
            },
        )
        val wire = WorkerReadWire(worker)
        for ((code, want) in listOf("ZZZZZZ" to "No reading with that code.", "ENDED1" to "This reading has ended.")) {
            val said = try { wire.join(code, JsonObject(emptyMap())); "joined" } catch (e: ReadFailure) { ReadCore.refusal(e.code) }
            assertEquals(want, said)
        }
    }

    /** The join screen asks the room first: a missing or ended room is named before any form, a live one (a membership refusal) is not. */
    @Test fun `a room is checked before the join form is shown`() = runTest {
        val engine = MockEngine { request ->
            val path = request.url.encodedPath
            val (status, body) = when {
                path.endsWith("/ZZZZZZ") -> HttpStatusCode.NotFound to """{"error":"no_such_room"}"""
                path.endsWith("/ENDED1") -> HttpStatusCode.Gone to """{"error":"room_ended"}"""
                else -> HttpStatusCode.Forbidden to """{"error":"not_a_member"}"""
            }
            respond(body, status, headersOf(HttpHeaders.ContentType, "application/json"))
        }
        val worker = com.example.appname.account.WorkerApi(
            HttpClient(engine), com.example.appname.account.WorkerConfig("https://worker.test", "web", "svc", "https://eardrama.org/"),
            object : com.example.appname.account.SessionStore {
                override fun load(): com.example.appname.account.StoredAccount? = null
                override fun save(account: com.example.appname.account.StoredAccount?) {}
            },
        )
        val wire = WorkerReadWire(worker)
        assertEquals("no_such_room", wire.gone("ZZZZZZ"))
        assertEquals("room_ended", wire.gone("ENDED1"))
        assertNull("a live room shows its form", wire.gone("LIVE01"))
    }

    @Test fun `the screen's voice reads an open line only while Read open parts is on`() {
        val open = ReadSnapshot.ReadsNow("role:DOC", holder = null)
        assertEquals("L0005", snap("L0005", mode = "read", readOpen = true, readsNow = open).openVoiceLine())
        assertNull("the leader's switch is off", snap("L0005", mode = "read", readOpen = false, readsNow = open).openVoiceLine())
        assertNull("a held line is never the voice's", snap("L0003", readOpen = true, readsNow = ReadSnapshot.ReadsNow("role:MOLLY", holder = "ann")).openVoiceLine())
        assertNull("an ended room", snap("L0005", readOpen = true, ended = true, readsNow = open).openVoiceLine())
    }

    // ---- fakes ----

    private class FakeLink(first: ReadSnapshot) : RoomLink {
        val flow = MutableStateFlow(ReadState(snapshot = first, code = first.code))
        override val state: StateFlow<ReadState> = flow
        override var memberKey: String? = "key-1"
        val sent = mutableListOf<JsonObject>()
        override suspend fun send(message: JsonObject) { sent += message }
        fun push(s: ReadSnapshot) { flow.value = flow.value.copy(snapshot = s) }
    }

    private class FakeWire : ReadWire {
        var failWith: String? = null
        val sentTakes = mutableListOf<String>()
        val inboxQueue = Channel<ReadTakeIn>(Channel.UNLIMITED)
        override suspend fun create(body: JsonObject, teacher: Boolean) = error("unused")
        override suspend fun join(code: String, body: JsonObject) = error("unused")
        override suspend fun poll(code: String, key: String) = error("unused")
        override suspend fun send(code: String, key: String, message: JsonObject) = error("unused")
        override fun socket(code: String, listener: ReadSocketListener): ReadSocket? = null
        override suspend fun sendTake(code: String, key: String, takeId: String, bytes: ByteArray, meta: JsonObject) {
            failWith?.let { throw ReadFailure(it) }
            sentTakes += takeId
        }
        override suspend fun inbox(code: String, key: String): ReadTakeIn = inboxQueue.receive()
        override suspend fun pairStart() = error("unused")
        override suspend fun pairPoll(pairCode: String, pairKey: String) = error("unused")
        override suspend fun attach(code: String, key: String, pairCode: String) = error("unused")
    }

    /** Keeps a real take file in the real store, as the studio engine does, without a microphone. */
    private class FakeEngine(private val store: ProductionStore, private val productionId: String) : RoomEngine {
        override var started = false
        override val failed: String? = null
        val recorded = mutableListOf<Pair<String, PartID>>()
        /** Runs while the take is open, before it ends (T7c: the leader moves the cursor during a take). */
        var during: (() -> Unit)? = null
        override suspend fun begin() { started = true }
        override fun stopListening() {}
        override fun end() { started = false }
        override suspend fun record(line: String, credit: PartID): Take? {
            recorded += line to credit
            during?.invoke()
            return store.takeWrite(productionId) {
                val p = store.production(productionId)!!
                val file = store.writeTake(MicrophoneCapture(FloatArray(4_800) { 0.1f }, 48_000.0), p, line)
                val take = Take("T${recorded.size}-$line", line, credit, file, 0.0, 4_800, 48_000.0, Take.Capture.Room, emptyMap(), null, 0.1f, false)
                store.save(p.add(take))
                take
            }
        }
    }

    private class Rig(val record: ReadRecord, val link: FakeLink, val wire: FakeWire, val store: ProductionStore, val engine: () -> FakeEngine?, val uploads: MutableList<Triple<String, String, JsonObject>>)

    private fun TestScope.rig(first: ReadSnapshot): Rig {
        val store = ProductionStore(temporaryRoot())
        val link = FakeLink(first)
        val wire = FakeWire()
        var engine: FakeEngine? = null
        val uploads = mutableListOf<Triple<String, String, JsonObject>>()
        val record = ReadRecord(
            wire, link, store, script, backgroundScope,
            engineFor = { p -> FakeEngine(store, p.id).also { engine = it } },
            upload = { pid, takeId, _, meta -> uploads += Triple(pid, takeId, meta) },
            retryMs = 5_000, io = StandardTestDispatcher(testScheduler),
        )
        record.start()
        return Rig(record, link, wire, store, { engine }, uploads)
    }

    private fun JsonObject.type() = this["type"]?.jsonPrimitive?.content

    /** Runs what is queued, background work included (`advanceUntilIdle` leaves a backgroundScope alone). */
    private fun TestScope.settle() {
        advanceTimeBy(500)
        runCurrent()
    }

    // ---- the record flow ----

    @Test fun `a holder records, the take is kept here first and goes to the receiver`() = runTest {
        val r = rig(snap("L0003", productionId = null))
        r.record.arm()
        settle()
        assertEquals("the line at the cursor, credited to its own part", listOf("L0003" to molly), r.engine()!!.recorded)
        val production = r.record.current()!!
        assertEquals("kept in this room's local production", "ABC123", production.room)
        assertEquals("the take is its line's chosen one", 1, production.takes.size)
        assertEquals(Take.Capture.Room, production.takes.single().capture)
        assertEquals("sent to the receiver", listOf(production.takes.single().id), r.wire.sentTakes)
        assertTrue("the outbox emptied", r.record.state.value.outbox.isEmpty())
        val done = r.link.sent.single { it.type() == "line-done" }
        assertEquals("L0003", done["line"]!!.jsonPrimitive.content)
        r.record.detach()
    }

    /** T7c: a take that ended after the leader moved the cursor was never marked done, so the cursor coming back opened it again. */
    @Test fun `a take that ends after the leader moved the cursor still sends its line-done, and the line opens no second microphone`() = runTest {
        val r = rig(snap("L0003"))
        r.record.arm()
        r.engine()!!.during = { r.link.push(snap("L0002", gen = 2)) }
        settle()
        assertEquals(listOf("L0003" to molly), r.engine()!!.recorded)
        val done = r.link.sent.single { it.type() == "line-done" }
        assertEquals("the take's line is done although the cursor moved", "L0003", done["line"]!!.jsonPrimitive.content)
        assertEquals("2", done["base"]!!.jsonPrimitive.content)
        r.engine()!!.during = null
        r.link.push(snap("L0003", gen = 3, done = listOf("L0003")))
        settle()
        assertEquals("the cursor back on the done line opens no second microphone", 1, r.engine()!!.recorded.size)
        r.record.detach()
    }

    @Test fun `nothing records before the reader presses Start recording`() = runTest {
        val r = rig(snap("L0003"))
        settle()
        assertNull("no engine was even made", r.engine())
        assertTrue(r.link.sent.isEmpty())
    }

    @Test fun `the receiver never records as a holder`() = runTest {
        val r = rig(snap("L0002", youId = "host", receives = true, leads = true, claims = mapOf("role:FIBBER" to "host")))
        r.record.arm()
        settle()
        assertTrue(r.engine()!!.recorded.isEmpty())
        r.record.detach()
    }

    @Test fun `a take nobody is there to receive waits in the outbox and is sent later`() = runTest {
        val r = rig(snap("L0003"))
        r.wire.failWith = "nobody_receiving"
        r.record.arm()
        advanceTimeBy(1_000)
        val id = r.record.current()!!.takes.single().id
        assertEquals("still waiting", listOf(id), r.record.state.value.outbox)
        assertEquals("nobody_receiving", r.record.state.value.lastError)
        assertEquals("the wait is kept with the production, so a restart keeps it", listOf(id), r.record.current()!!.roomOutbox)
        assertTrue(r.wire.sentTakes.isEmpty())
        r.wire.failWith = null
        advanceTimeBy(6_000)
        assertEquals("sent when someone is there", listOf(id), r.wire.sentTakes)
        assertTrue(r.record.state.value.outbox.isEmpty())
        assertTrue(r.record.current()!!.roomOutbox.isEmpty())
        r.record.detach()
    }

    @Test fun `any other refusal takes the take out of the outbox and keeps it here`() = runTest {
        val r = rig(snap("L0003"))
        r.wire.failWith = "not_your_line"
        r.record.arm()
        settle()
        assertTrue(r.record.state.value.outbox.isEmpty())
        assertEquals(1, r.record.current()!!.takes.size)
        r.record.detach()
    }

    @Test fun `Again re-arms the line and the new take is the chosen one`() = runTest {
        val r = rig(snap("L0003"))
        r.record.arm()
        settle()
        r.link.push(snap("L0003", gen = 2, done = listOf("L0003")))
        settle()
        assertEquals("done: not recorded again", 1, r.engine()!!.recorded.size)
        r.link.push(snap("L0003", gen = 3, done = emptyList()))
        settle()
        assertEquals("the leader's Again re-armed it", 2, r.engine()!!.recorded.size)
        val p = r.record.current()!!
        assertEquals("both takes stay", 2, p.takes.size)
        assertEquals("the newest is chosen", p.takes.last().id, p.chosen["L0003"])
        r.record.detach()
    }

    @Test fun `One microphone records the line at the cursor whoever holds it, credits the part and moves on`() = runTest {
        val s = snap("L0002", youId = "host", receives = true, leads = true, productionId = "P1", claims = mapOf("role:MOLLY" to "ann"))
        val r = rig(s)
        r.record.setOneMic(true)
        r.record.arm()
        settle()
        assertEquals("FIBBER's line, credited to FIBBER", listOf("L0002" to fibber), r.engine()!!.recorded)
        assertTrue("never relayed", r.wire.sentTakes.isEmpty() && r.record.state.value.outbox.isEmpty())
        val take = r.record.current()!!.takes.single()
        assertEquals(fibber, take.part)
        assertEquals("the director's own row in a production", listOf("P1" to take.id), r.uploads.map { it.first to it.second })
        val move = r.link.sent.single { it.type() == "cursor" }
        assertEquals("the cursor moves to the next line", "L0003", move["line"]!!.jsonPrimitive.content)
        r.record.detach()
    }

    @Test fun `the receiver holds the pickup and imports each arrival as the line's chosen take`() = runTest {
        val r = rig(snap("L0003", youId = "host", receives = true, leads = true, kind = "class", seats = listOf(ReadSnapshot.Seat("s1", "Lucy"))))
        settle()
        assertTrue("holding the pickup while the room records", r.record.state.value.receiving)
        r.wire.inboxQueue.send(ReadTakeIn(ReadTakeFields("A1", "L0003", "role:MOLLY", "a.wav", 4_800, 48_000.0, "room", seat = "s1", member = "m1"), ByteArray(64) { 1 }))
        settle()
        val p = r.record.current()!!
        val got = p.take("A1")!!
        assertEquals("s1", got.seat)
        assertEquals(Take.Capture.Room, got.capture)
        assertEquals("A1", p.chosen["L0003"])
        assertEquals(1, r.record.state.value.arrived)
        assertTrue("the arrival's audio is on this device", r.store.takeFile(p, got).isFile)
        r.record.detach()
    }

    // ---- Publish under my name ----

    private class FakeClass(val plan: MutableList<String>) : ReadClassWire {
        val sent = mutableListOf<String>()
        override suspend fun seatList(code: String) = error("unused")
        override suspend fun seatClaim(code: String, seat: String, move: Boolean) = error("unused")
        override suspend fun detail(id: String) = error("unused")
        override suspend fun progress(id: String) = error("unused")
        override suspend fun production(pid: String) = error("unused")
        override suspend fun addSeats(id: String, text: String) = error("unused")
        override suspend fun removeSeat(id: String, seat: String) = error("unused")
        override suspend fun releaseSeat(id: String, seat: String) = error("unused")
        override suspend fun classProduction(id: String, scriptId: String, revision: String, cast: List<Pair<String, String>>) = error("unused")
        override suspend fun assign(pid: String, assignments: List<ReadCore.Assignment>) = error("unused")
        override suspend fun review(pid: String, takeId: String, state: String, note: String?) = error("unused")
        override suspend fun consent() = error("unused")
        override suspend fun agree(pid: String, version: String) = error("unused")
        override suspend fun publish(pid: String, creditName: String) = error("unused")
        override suspend fun deleteClass(id: String) = error("unused")
        override suspend fun setEnd(id: String, endsOn: String) = error("unused")
        override suspend fun exportClass(id: String) = error("unused")
        override suspend fun schoolConsent(id: String, reference: String) = error("unused")
        override suspend fun sendFile(pid: String, lineId: String, bytes: ByteArray) {
            val next = if (plan.isEmpty()) "ok" else plan.removeAt(0)
            if (next != "ok") throw ReadFailure(next)
            sent += lineId
        }
    }

    private fun publishRig(): Pair<ProductionStore, Production> {
        val store = ProductionStore(temporaryRoot())
        var p = store.create(script).copy(roomPid = "P1", room = "ABC123")
        for (l in script.lines.filter { it.part.isSpeaking }) {
            val file = store.writeTake(MicrophoneCapture(FloatArray(480) { 0.1f }, 48_000.0), p, l.id)
            p = p.add(Take("t-${l.id}", l.id, l.part, file, 0.0, 480, 48_000.0, Take.Capture.Room, emptyMap(), null, 0.1f, false))
        }
        store.save(p)
        return store to p
    }

    @Test fun `publishing sends each chosen take once, waits on not_ready, skips already_sent`() = runTest {
        val (store, p) = publishRig()
        val wire = FakeClass(mutableListOf("not_ready", "ok", "already_sent"))
        val waits = mutableListOf<Long>()
        val stopped = RoomPublish.sendFiles(wire, store, p, script, wait = { waits += it })
        assertNull(stopped)
        assertEquals("the cron had not laid the item out for the first try", listOf(RoomPublish.WAIT_MS), waits)
        assertEquals("every speaking line, once, in script order (one skipped as already sent)", listOf("L0002", "L0005", "L0006", "L0007", "L0008", "L0009", "L0010", "L0011"), wire.sent)
    }

    @Test fun `publishing stops on a refusal that waiting cannot fix`() = runTest {
        val (store, p) = publishRig()
        val wire = FakeClass(mutableListOf("reported_take"))
        assertEquals("reported_take", RoomPublish.sendFiles(wire, store, p, script, wait = {}))
        assertTrue(wire.sent.isEmpty())
    }

    // ---- the poll fallback (2026-11-23 free-tier audit: a poll a second used up the shared Worker account) ----

    /** As read-rooms.js: a poll at the room's generation waits 20 s for a change; one without answers at once. */
    private class LongPollWire(val room: ReadSnapshot) : ReadWire {
        var polls = 0
        var sends = 0
        override suspend fun create(body: JsonObject, teacher: Boolean) = error("unused")
        override suspend fun join(code: String, body: JsonObject) = error("unused")
        override suspend fun poll(code: String, key: String): ReadSnapshot { polls += 1; return room }
        override suspend fun poll(code: String, key: String, gen: Int): ReadSnapshot {
            polls += 1
            kotlinx.coroutines.delay(20_000)
            return room.copy(heldMs = 20_000.0)
        }
        override suspend fun send(code: String, key: String, message: JsonObject): ReadSnapshot? { sends += 1; return room }
        override fun socket(code: String, listener: ReadSocketListener): ReadSocket? = null
        override suspend fun sendTake(code: String, key: String, takeId: String, bytes: ByteArray, meta: JsonObject) = error("unused")
        override suspend fun inbox(code: String, key: String) = error("unused")
        override suspend fun pairStart() = error("unused")
        override suspend fun pairPoll(pairCode: String, pairKey: String) = error("unused")
        override suspend fun attach(code: String, key: String, pairCode: String) = error("unused")
    }

    @Test fun `polling is a long poll - a quiet room costs at most 4 polls a minute and no pings`() = runTest {
        val wire = LongPollWire(snap("L0003"))
        val session = ReadSession(wire, backgroundScope, now = { testScheduler.currentTime.toDouble() })
        session.adopt(ReadJoined(snap("L0003"), "key-1", "poll"))
        runCurrent()
        advanceTimeBy(60_000); runCurrent()
        assertEquals("poll", session.state.value.transport)
        assertTrue("polls in 60 s: ${wire.polls}", wire.polls <= 4)
        assertEquals("no HTTP ping while polling", 0, wire.sends)
        assertFalse("time spent waiting is not a slow connection", session.state.value.slow)
    }

    // ---- a TV's pairing ----

    private class PairWire(val answers: MutableList<Any?>) : ReadWire {
        var starts = 0
        val polls = mutableListOf<String>()
        override suspend fun create(body: JsonObject, teacher: Boolean) = error("unused")
        override suspend fun join(code: String, body: JsonObject) = error("unused")
        override suspend fun poll(code: String, key: String) = error("unused")
        override suspend fun send(code: String, key: String, message: JsonObject) = error("unused")
        override fun socket(code: String, listener: ReadSocketListener): ReadSocket? = null
        override suspend fun sendTake(code: String, key: String, takeId: String, bytes: ByteArray, meta: JsonObject) = error("unused")
        override suspend fun inbox(code: String, key: String) = error("unused")
        override suspend fun attach(code: String, key: String, pairCode: String) = error("unused")
        override suspend fun pairStart(): PairStart { starts += 1; return PairStart("CODE0$starts", "key$starts", 0.0) }
        override suspend fun pairPoll(pairCode: String, pairKey: String): ReadJoined? {
            polls += pairCode
            val next = if (answers.isEmpty()) null else answers.removeAt(0)
            if (next is String) throw ReadFailure(next)
            return next as ReadJoined?
        }
    }

    @Test fun `a TV shows its code, asks every two seconds, and replaces an expired code without a word`() = runTest {
        val wire = PairWire(mutableListOf<Any?>(null, "pair_expired"))
        val pairing = ReadPairing(wire, backgroundScope)
        pairing.start()
        runCurrent()
        assertEquals("CODE01", pairing.state.value.code)
        advanceTimeBy(2_000); runCurrent()
        advanceTimeBy(2_000); runCurrent()
        assertEquals(listOf("CODE01", "CODE01"), wire.polls)
        assertEquals("the expiry is not shown", null, pairing.state.value.refusal)
        advanceTimeBy(2_000); runCurrent()
        assertEquals("a new code replaced it", "CODE02", pairing.state.value.code)
        assertEquals(2, wire.starts)
        assertEquals("3 + 3 split", "COD E02", ReadPairing.split("CODE02"))
    }

    @Test fun `a TV that a leader adds becomes that room's screen`() = runTest {
        val room = snap("L0003", role = "screen", youId = "tv")
        val wire = PairWire(mutableListOf<Any?>(ReadJoined(room, "tv-key", "poll")))
        val pairing = ReadPairing(wire, backgroundScope)
        pairing.start()
        runCurrent()
        advanceTimeBy(2_000); runCurrent()
        val paired = pairing.state.value.paired
        assertNotNull(paired)
        assertEquals("ABC123", paired!!.snapshot.code)
        assertEquals("screen", paired.snapshot.you!!.role)
        val before = wire.polls.size
        advanceTimeBy(10_000); runCurrent()
        assertEquals("it stops asking once paired", before, wire.polls.size)
    }

    // ---- the studio engine's recordInRoom ----

    private class RoomAudio : LiveAudio {
        var plays = 0
        private var captures = 0
        private var captured = FloatArray(0)
        private val random = Random(7)
        override fun outputRoute() = AudioRoute.Headphones
        override fun start(echoCancelled: Boolean) {}
        override fun stop() {}
        override suspend fun play(cue: CueAudio) { plays += 1 }
        override fun beginCapture(onChunk: (FloatArray) -> Unit) {
            captures += 1
            captured = if (captures == 1) FloatArray(48_000) { random.nextFloat() * 0.001f - 0.0005f }
            else FloatArray(9_600) + tone(listOf(150.0, 175.0), 0.6) + FloatArray(60_000)
            for (start in captured.indices step 960) onChunk(captured.copyOfRange(start, minOf(start + 960, captured.size)))
        }
        override fun endCapture(): MicrophoneCapture = MicrophoneCapture(captured, 48_000.0).also { captured = FloatArray(0) }
    }

    private class NoVoice : StandInVoice {
        var renders = 0
        override suspend fun render(text: String, part: PartID, rate: Float): StandInAudio? { renders += 1; return null }
    }

    @Test fun `recordInRoom keeps the line, credited to its own part, with no cue played`() = runTest {
        val store = ProductionStore(temporaryRoot())
        val p = store.create(script)
        val audio = RoomAudio()
        val voice = NoVoice()
        val session = RecordingSession(p, script, molly, store, audio, voice, wait = {}, announce = {})
        session.begin(echoCancelled = false)
        val take = session.recordInRoom("L0008", fibber)
        assertNotNull("a take was kept", take)
        assertEquals("credited to the line's own part, not the session's", fibber, take!!.part)
        assertEquals(Take.Capture.Room, take.capture)
        assertEquals("no cue was played", 0, audio.plays)
        assertEquals("the device voice was never asked", 0, voice.renders)
        assertEquals(RecordingSession.Phase.Idle, session.phase.value)
        assertEquals("the production holds it as the line's chosen take", take.id, store.production(p.id)!!.chosen["L0008"])
        session.end()
        store.root.deleteRecursively()
    }
}
