package com.example.appname.plays

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

/** The take engine [ReadRecord] drives: the studio's [RecordingSession] in the app, a fake in tests. */
interface RoomEngine {
    val started: Boolean
    val failed: String?
    suspend fun begin()
    fun stopListening()
    suspend fun record(line: String, credit: PartID): Take?
    fun end()
}

class SessionRoomEngine(private val session: RecordingSession) : RoomEngine {
    override val started get() = session.started
    override val failed get() = (session.phase.value as? RecordingSession.Phase.Failed)?.message
    override suspend fun begin() = session.begin(echoCancelled = false)
    override fun stopListening() = session.stopListening()
    override suspend fun record(line: String, credit: PartID) = session.recordInRoom(line, credit)
    override fun end() = session.end()
}

data class RecordState(
    val localId: String? = null,
    val outbox: List<String> = emptyList(),
    val recording: String? = null,
    val armed: Boolean = false,
    val oneMic: Boolean = false,
    val receiving: Boolean = false,
    val arrived: Int = 0,
    val lastError: String? = null,
    val failed: String? = null,
)

/**
 * Record in the room on this device (PLAYS-DESIGN §12.10, ANDROID-DESIGN §4.19), the mirror of js/read-record.js: no views.
 * The room's rules are [ReadCore]'s; the engine is the studio's session with no cue played; the takes live in a local
 * production kept for this room (`room: CODE`) in the same store as every production, so Listen through, Export and Publish
 * work on it as on any other. A reader's take is written on the device first, then sent from the outbox to the room's
 * receiver; the receiver holds the pickup and imports each arrival; One microphone records the line at the cursor
 * whoever holds it. Nothing here plays sound.
 */
class ReadRecord(
    private val wire: ReadWire,
    private val session: RoomLink,
    private val store: ShareStore,
    private val script: PlayScript,
    private val scope: CoroutineScope,
    private val engineFor: suspend (Production) -> RoomEngine,
    private val upload: (suspend (pid: String, takeId: String, bytes: ByteArray, meta: JsonObject) -> Unit)? = null,
    private val retryMs: Long = RETRY_MS,
    private val io: kotlinx.coroutines.CoroutineDispatcher = Dispatchers.IO,
) {
    private val _state = MutableStateFlow(RecordState())
    val state: StateFlow<RecordState> = _state

    private val cast: List<Pair<String, String>> = script.lines.map { it.id to it.part.raw }
    private var engine: RoomEngine? = null
    private var justDid: String? = null
    private var sending = false
    private var retry: Job? = null
    private var pickup: Job? = null
    private var stopped = false
    private var watcher: Job? = null

    private fun snap(): ReadSnapshot? = session.state.value.snapshot
    private fun partOf(line: String): String? = cast.firstOrNull { it.first == line }?.second
    private fun codeOf(e: Throwable): String = (e as? ReadFailure)?.code ?: if (e is java.io.IOException) "offline" else "error"

    fun start() {
        watcher = scope.launch { session.state.collect { onSnapshot() } }
    }

    /** The local production for this room, made on the first take or arrival; its outbox is persisted with it. */
    suspend fun production(): Production {
        val s = snap() ?: error("not in a room")
        _state.value.localId?.let { id -> store.production(id)?.let { return it } }
        store.all().firstOrNull { it.room == s.code }?.let { found ->
            _state.update { it.copy(localId = found.id, outbox = found.roomOutbox) }
            return found
        }
        val made = withContext(io) { store.create(script) }
        val p = made.copy(room = s.code, roomPid = s.productionId, roomKind = s.kind, roomOutbox = emptyList())
        store.save(p)
        _state.update { it.copy(localId = p.id) }
        return p
    }

    /** The production on this device now, or null before the first take or arrival. */
    fun current(): Production? = _state.value.localId?.let { store.production(it) }

    /** Lines with a take on this device. */
    fun arrivedLines(): Set<String> = current()?.chosen?.keys.orEmpty()

    private fun saveOutbox() {
        val id = _state.value.localId ?: return
        store.production(id)?.let { store.save(it.copy(roomOutbox = _state.value.outbox)) }
    }

    private suspend fun engine(): RoomEngine {
        engine?.let { return it }
        val made = engineFor(production())
        engine = made
        return made
    }

    /** Start recording: the one tap a reader gives before the first take (the permission and room tone). */
    suspend fun arm() {
        val e = engine()
        e.begin()
        _state.update { it.copy(armed = e.started, failed = e.failed) }
        if (e.started) onSnapshot()
    }

    /** Stop: the reader's tap ends the take now (the line-end detector ends it on its silence otherwise). */
    fun stop() { engine?.stopListening() }

    private fun message(vararg pairs: Pair<String, Any>): JsonObject = buildJsonObject {
        pairs.forEach { (k, v) -> put(k, if (v is Number) JsonPrimitive(v) else JsonPrimitive(v.toString())) }
    }

    private suspend fun record(line: String, credit: Boolean = false) {
        val before = snap() ?: return
        justDid = line
        _state.update { it.copy(recording = line) }
        val part = partOf(line)
        val take = if (part == null) null else try {
            engine().record(line, PartID(part))
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            null
        }
        _state.update { it.copy(recording = null) }
        if (stopped) return
        if (take == null) {
            justDid = null
            return
        }
        val now = snap() ?: before
        if (credit) {
            val members = now.members.map { ReadCore.Member(it.id, it.role, it.seat, 0.0, if (it.live) 0.0 else Double.NEGATIVE_INFINITY, it.name) }
            val reads = ReadCore.whoReads(now.room, cast, members, line, 0.0)
            val pid = now.productionId
            val id = _state.value.localId
            if (pid != null && upload != null && id != null) {
                try {
                    val bytes = withContext(io) { store.readTake(id, take.file) }
                    val meta = PlaysShare.metaOf(take).let { m -> if (reads?.seat != null) JsonObject(m + ("seat" to JsonPrimitive(reads.seat))) else m }
                    upload.invoke(pid, take.id, bytes, meta)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    _state.update { it.copy(lastError = codeOf(e)) }
                }
            }
            val next = ReadCore.step(cast, line, 1)
            if (next != null && now.cursor == line) {
                try { session.send(message("type" to "cursor", "line" to next, "base" to now.cursorGen)) } catch (e: CancellationException) { throw e } catch (_: Exception) { }
            }
        } else {
            _state.update { it.copy(outbox = it.outbox + take.id) }
            saveOutbox()
            if (now.cursor == line) {
                try { session.send(message("type" to "line-done", "line" to line, "base" to now.cursorGen)) } catch (e: CancellationException) { throw e } catch (_: Exception) { }
            }
            flush()
        }
    }

    /** Sends the outbox one take at a time; a "later" refusal stops and waits [retryMs], any other drops it (the take stays here). */
    suspend fun flush() {
        if (sending || stopped || _state.value.outbox.isEmpty()) return
        val s = snap()
        val key = session.memberKey
        if (s == null || key == null || s.ended) return
        sending = true
        try {
            while (_state.value.outbox.isNotEmpty() && !stopped) {
                val id = _state.value.outbox.first()
                val localId = _state.value.localId
                val t = localId?.let { store.production(it) }?.takes?.firstOrNull { it.id == id }
                if (t == null) {
                    _state.update { it.copy(outbox = it.outbox.drop(1)) }
                    continue
                }
                try {
                    val bytes = withContext(io) { store.readTake(localId, t.file) }
                    wire.sendTake(s.code, key, t.id, bytes, PlaysShare.metaOf(t))
                    _state.update { it.copy(outbox = it.outbox.drop(1), lastError = null) }
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    val c = codeOf(e)
                    if (c in LATER) {
                        _state.update { it.copy(lastError = c) }
                        break
                    }
                    _state.update { it.copy(outbox = it.outbox.drop(1), lastError = c) }
                }
                saveOutbox()
            }
        } finally {
            sending = false
        }
        if (_state.value.outbox.isNotEmpty() && !stopped) {
            retry?.cancel()
            retry = scope.launch { delay(retryMs); flush() }
        }
    }

    private fun holdPickup() {
        if (_state.value.receiving) return
        _state.update { it.copy(receiving = true) }
        pickup = scope.launch {
            var wait = 0L
            while (!stopped) {
                val s = snap()
                val key = session.memberKey
                if (s == null || key == null || s.ended) break
                try {
                    val got = wire.inbox(s.code, key)
                    wait = 0
                    if (got != null) accept(got.take, got.bytes)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    if (codeOf(e) in STOP_PICKUP) break
                    wait = minOf(30_000L, if (wait == 0L) 2_000L else wait * 2)
                    delay(wait)
                }
            }
            _state.update { it.copy(receiving = false) }
        }
    }

    private fun dropPickup() {
        pickup?.cancel()
        pickup = null
        _state.update { it.copy(receiving = false) }
    }

    /** A take that arrived: written once under its own id, the line's chosen take (the newest wins, as on the Worker). */
    suspend fun accept(t: ReadTakeFields, bytes: ByteArray) {
        val p = production()
        if (p.takes.any { it.id == t.id }) return
        val file = "r-${t.id}.wav"
        withContext(io) { store.importTake(p.id, file, bytes) }
        val take = Take(
            id = t.id, lineID = t.lineID, part = PartID(t.part), file = file, created = ReferenceDate.now(), frames = t.frames,
            sampleRate = t.sampleRate, capture = Take.Capture.Room, heard = emptyMap(), peak = 0f, bleed = false, seat = t.seat, member = t.member,
        )
        store.save((store.production(p.id) ?: p).add(take))
        _state.update { it.copy(arrived = it.arrived + 1) }
    }

    /** Every snapshot: settle `justDid`, open the microphone when it is this device's line, hold or drop the pickup, send the outbox. */
    fun onSnapshot() {
        val s = snap() ?: return
        if (stopped) return
        justDid = ReadCore.settleJustDid(s, justDid)
        if (s.ended) { dropPickup(); return }
        val recording = s.mode == "record"
        if (recording && s.you?.receives == true) holdPickup() else if (_state.value.receiving) dropPickup()
        val st = _state.value
        if (st.armed && st.recording == null) {
            if (st.oneMic && s.you?.leads == true && recording) {
                val part = partOf(s.cursor)
                if (part != null && PartID(part).isSpeaking && s.cursor !in s.done && justDid != s.cursor) {
                    justDid = s.cursor
                    scope.launch { record(s.cursor, credit = true) }
                }
            } else if (ReadCore.shouldRecord(s, cast, justDid)) {
                justDid = s.cursor
                scope.launch { record(s.cursor) }
            }
        }
        if (st.outbox.isNotEmpty()) scope.launch { flush() }
    }

    /** Loads this room's production (and its outbox) when one exists already: a reload keeps waiting takes. */
    suspend fun resume() {
        val s = snap() ?: return
        store.all().firstOrNull { it.room == s.code }?.let { found -> _state.update { it.copy(localId = found.id, outbox = found.roomOutbox) } }
        if (_state.value.outbox.isNotEmpty()) flush()
    }

    /** One microphone on or off (the leader's Record every line here). */
    fun setOneMic(on: Boolean) {
        _state.update { it.copy(oneMic = on) }
        onSnapshot()
    }

    fun detach() {
        stopped = true
        watcher?.cancel()
        retry?.cancel()
        dropPickup()
        engine?.end()
    }

    companion object {
        const val RETRY_MS = 5000L

        /** Refusals that mean "try again later": the take stays in the outbox. */
        val LATER = setOf("nobody_receiving", "one_take_at_a_time", "offline", "error", "rate_limited", "timeout", "not_configured", "not_delivered")
        val STOP_PICKUP = setOf("receivers_only", "not_a_member", "room_ended", "no_such_room", "not_configured")
    }
}
