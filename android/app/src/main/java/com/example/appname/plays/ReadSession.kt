package com.example.appname.plays

import com.example.appname.account.WorkerApi
import com.example.appname.account.WorkerException
import io.ktor.http.HttpMethod
import java.io.IOException
import java.net.URLEncoder
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener

// A device's seat in a read room (PLAYS-DESIGN §12, Decision 082): the socket first, with the member key in a first
// "hello" and never in a URL, falling back to polling the same messages every second, and trying the socket again as
// the web's js/read-session.js and the Swift ReadSession do. Every rule is ReadCore's; this is the transport and the
// state a screen reads. Keys live in memory for the app run only (owner, 2026-11-19: a shared device keeps no seat key
// at rest).

/** The room as every member reads it (a Worker `snapshot` message). No key ever travels. */
@Serializable
data class ReadSnapshot(
    val code: String,
    val kind: String,
    val mode: String,
    @SerialName("script_id") val scriptId: String? = null,
    @SerialName("script_revision") val scriptRevision: String? = null,
    @SerialName("production_id") val productionId: String? = null,
    @SerialName("class_id") val classId: String? = null,
    val cursor: String,
    @SerialName("cursor_gen") val cursorGen: Int = 0,
    val generation: Int = 0,
    val locked: Boolean = false,
    val ended: Boolean = false,
    val leader: String = "",
    @SerialName("leader_name") val leaderName: String? = null,
    @SerialName("read_open") val readOpen: Boolean = false,
    @SerialName("waiting_for_leader") val waitingForLeader: Boolean = false,
    val you: You? = null,
    @SerialName("next_mine") val nextMine: NextMine? = null,
    @SerialName("reads_now") val readsNow: ReadsNow? = null,
    val members: List<Member> = emptyList(),
    val present: Int = 0,
    val claims: Map<String, String> = emptyMap(),
    val seats: List<Seat> = emptyList(),
    val assignments: List<AssignmentRow> = emptyList(),
    val done: List<String> = emptyList(),
    @SerialName("server_time") val serverTime: Double = 0.0,
) {
    @Serializable data class You(val id: String, val role: String, val seat: String? = null, val leads: Boolean = false, val owner: Boolean = false)
    @Serializable data class Member(val id: String, val role: String, val seat: String? = null, val live: Boolean = true)
    @Serializable data class Seat(val id: String, val label: String)
    @Serializable data class AssignmentRow(val part: String, val seat: String, val from: String? = null, val to: String? = null)
    @Serializable data class NextMine(val line: String, @SerialName("in") val inLines: Int)
    @Serializable data class ReadsNow(val part: String, val seat: String? = null, val holder: String? = null, val members: List<String> = emptyList())

    /** The room as the protocol's functions read it, rebuilt from a snapshot. */
    val room: ReadCore.Room
        get() = ReadCore.Room(
            kind, mode, cursor, cursorGen, generation, leader, claims,
            seats.map { ReadCore.Seat(it.id, it.label) }, assignments.map { ReadCore.Assignment(it.part, it.seat, it.from, it.to) }, done, locked, ended,
        )

    val meMember: ReadCore.Member? get() = you?.let { ReadCore.Member(it.id, it.role, it.seat, 0.0, serverTime) }

    /** A snapshot replaces the one in hand only when it is as new or newer (a slow poll never rewinds the cursor). */
    fun isNewerThan(prev: ReadSnapshot?): Boolean =
        prev == null || prev.code != code || generation > prev.generation || (generation == prev.generation && serverTime >= prev.serverTime)

    /** Whether a line nobody holds is the device voice's to read ("Read open parts"). */
    val readsOpenLine: Boolean get() = readsNow?.let { if (kind == "class") it.seat == null else it.holder == null } ?: false
}

/** A Worker refusal or a transport failure, by the Worker's own code ([ReadCore.refusal] words it). */
class ReadFailure(val code: String) : Exception(code)

data class ReadJoined(val snapshot: ReadSnapshot, val key: String, val transport: String)

/** One socket, as the session needs it (OkHttp's below; a fake in tests). */
interface ReadSocket {
    fun send(text: String): Boolean
    fun close()
}

interface ReadSocketListener {
    fun onOpen()
    fun onText(text: String)
    fun onClosed()
}

/** The Worker's read routes, so the session never touches the network itself (AGENTS.md: one shared client). */
interface ReadWire {
    suspend fun create(body: JsonObject, teacher: Boolean): ReadJoined
    suspend fun join(code: String, body: JsonObject): ReadJoined
    suspend fun poll(code: String, key: String): ReadSnapshot
    suspend fun send(code: String, key: String, message: JsonObject): ReadSnapshot?
    fun socket(code: String, listener: ReadSocketListener): ReadSocket?
}

class WorkerReadWire(private val worker: WorkerApi, private val ok: OkHttpClient = OkHttpClient()) : ReadWire {
    private fun at(code: String) = "/v1/read/" + URLEncoder.encode(code, "UTF-8")

    private suspend fun <T> guarded(block: suspend () -> T): T = try {
        block()
    } catch (e: CancellationException) {
        throw e
    } catch (e: ReadFailure) {
        throw e
    } catch (e: WorkerException) {
        throw ReadFailure(e.code ?: if (e.status == 429) "rate_limited" else "error")
    } catch (e: IOException) {
        throw ReadFailure("offline")
    } catch (e: com.example.appname.account.SignedOutException) {
        throw ReadFailure("not_configured")
    }

    private fun joined(text: String): ReadJoined {
        val o = ShareJson.parseToJsonElement(text).jsonObject
        val key = o["member_key"]?.jsonPrimitive?.contentOrNull ?: throw ReadFailure("error")
        return ReadJoined(ShareJson.decodeFromString(ReadSnapshot.serializer(), text), key, o["transport"]?.jsonPrimitive?.contentOrNull ?: "socket")
    }

    private fun enc(o: JsonObject) = ShareJson.encodeToString(JsonObject.serializer(), o)

    override suspend fun create(body: JsonObject, teacher: Boolean): ReadJoined = guarded {
        joined(if (teacher) worker.callText(HttpMethod.Post, "/v1/read", enc(body)) else worker.anonText(HttpMethod.Post, "/v1/read", enc(body)))
    }

    override suspend fun join(code: String, body: JsonObject): ReadJoined = guarded {
        joined(worker.anonText(HttpMethod.Post, at(code) + "/join", enc(body)))
    }

    override suspend fun poll(code: String, key: String): ReadSnapshot = guarded {
        ShareJson.decodeFromString(ReadSnapshot.serializer(), worker.anonText(HttpMethod.Get, at(code), null, mapOf(KEY_HEADER to key)))
    }

    override suspend fun send(code: String, key: String, message: JsonObject): ReadSnapshot? = guarded {
        runCatching {
            ShareJson.decodeFromString(ReadSnapshot.serializer(), worker.anonText(HttpMethod.Post, at(code) + "/send", enc(message), mapOf(KEY_HEADER to key)))
        }.getOrElse { if (it is WorkerException) throw it else null }
    }

    override fun socket(code: String, listener: ReadSocketListener): ReadSocket? {
        val url = worker.socketUrl(at(code) + "/socket") ?: return null
        val ws: WebSocket = ok.newWebSocket(
            Request.Builder().url(url).build(),
            object : WebSocketListener() {
                override fun onOpen(webSocket: WebSocket, response: Response) = listener.onOpen()
                override fun onMessage(webSocket: WebSocket, text: String) = listener.onText(text)
                override fun onClosed(webSocket: WebSocket, code: Int, reason: String) = listener.onClosed()
                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) = listener.onClosed()
            },
        )
        return object : ReadSocket {
            override fun send(text: String) = ws.send(text)
            override fun close() { ws.close(1000, null) }
        }
    }

    companion object {
        const val KEY_HEADER = "x-read-key"
    }
}

/** Seat keys held for this app run only (decision c): a class device shared by students keeps nothing at rest. */
object ReadSeatKeys {
    private val keys = HashMap<String, String>()
    @Synchronized fun key(seat: String): String? = keys[seat]
    @Synchronized fun set(seat: String, key: String) { keys[seat] = key }
    @Synchronized fun forget() = keys.clear()
}

data class ReadState(
    val snapshot: ReadSnapshot? = null,
    val transport: String? = null,
    val slow: Boolean = false,
    val offline: Boolean = false,
    /** The Worker's code once the room is over for this device. */
    val ended: String? = null,
    val refusal: String? = null,
    val clockOffsetMs: Double? = null,
    val code: String? = null,
)

class ReadSession(
    private val wire: ReadWire,
    private val scope: CoroutineScope,
    private val now: () -> Double = { System.currentTimeMillis().toDouble() },
    private val diag: Boolean = false,
) {
    private val _state = MutableStateFlow(ReadState())
    val state: StateFlow<ReadState> = _state

    private var key: String? = null
    private var forcePoll = false
    private var socket: ReadSocket? = null
    private var socketOpen = false
    private var run = 0
    private val jobs = mutableListOf<Job>()
    private val samples = ArrayDeque<ReadCore.ClockSample>()
    private var lastOk = 0.0
    private var retries = 0

    private fun said(s: String) { if (diag) println("[readdiag] $s") }

    // ---- Entering and leaving ----

    suspend fun open(body: JsonObject, teacher: Boolean) = enter(wire.create(body, teacher))

    suspend fun join(code: String, want: JsonObject = JsonObject(emptyMap())) = enter(wire.join(code, want))

    fun leave() {
        stopTransport()
        key = null
        _state.value = ReadState()
    }

    fun pause() = stopTransport()

    private fun enter(joined: ReadJoined) {
        stopTransport()
        key = joined.key
        forcePoll = joined.transport == "poll"
        _state.value = ReadState(code = joined.snapshot.code)
        apply(joined.snapshot)
        connect()
    }

    // ---- Messages ----

    /** One message to the room. On a socket the answer is the next snapshot; over HTTP the snapshot or the refusal is thrown. */
    suspend fun send(message: JsonObject) {
        val code = _state.value.code
        val k = key
        if (code == null || k == null || _state.value.ended != null) throw ReadFailure(_state.value.ended ?: "not_a_member")
        val sock = socket
        if (socketOpen && sock != null) { sock.send(ShareJson.encodeToString(JsonObject.serializer(), message)); return }
        try {
            wire.send(code, k, message)?.let(::apply)
            _state.update { it.copy(refusal = null) }
        } catch (f: ReadFailure) {
            if (f.code == "stale") runCatching { wire.poll(code, k) }.getOrNull()?.let(::apply)
            else if (f.code in GONE) end(f.code)
            else _state.update { it.copy(refusal = f.code) }
            throw f
        }
    }

    // ---- State ----

    private fun apply(snap: ReadSnapshot) {
        if (!snap.isNewerThan(_state.value.snapshot)) return
        lastOk = now()
        _state.update { it.copy(snapshot = snap, slow = false, offline = false, refusal = null) }
        if (snap.ended) end("room_ended")
    }

    private fun end(code: String) {
        if (_state.value.ended != null) return
        _state.update { it.copy(ended = code) }
        stopTransport()
        key = null
    }

    private fun stopTransport() {
        run += 1
        jobs.forEach { it.cancel() }
        jobs.clear()
        socket?.close()
        socket = null
        socketOpen = false
    }

    private fun later(ms: Long, mine: Int, body: suspend () -> Unit) {
        jobs += scope.launch {
            delay(ms)
            if (run == mine && _state.value.ended == null) body()
        }
    }

    // ---- Polling ----

    private fun poll(mine: Int) {
        val code = _state.value.code ?: return
        val k = key ?: return
        if (run != mine || _state.value.ended != null) return
        val t0 = now()
        jobs += scope.launch {
            try {
                val snap = wire.poll(code, k)
                if (run != mine) return@launch
                apply(snap)
                val slow = now() - t0 > ReadCore.SLOW_MS
                if (slow != _state.value.slow) _state.update { it.copy(slow = slow) }
            } catch (f: ReadFailure) {
                if (run != mine) return@launch
                failed(f)
                if (!_state.value.slow && now() - lastOk > ReadCore.SLOW_MS) _state.update { it.copy(slow = true) }
            }
            if (run == mine && _state.value.ended == null && _state.value.transport == "poll") later(ReadCore.POLL_MS, mine) { poll(mine) }
        }
    }

    private fun failed(f: ReadFailure) {
        when {
            f.code in GONE -> end(f.code)
            f.code == "offline" -> _state.update { it.copy(offline = true) }
            f.code == "rate_limited" -> _state.update { it.copy(refusal = f.code) }
        }
    }

    private fun startPolling(mine: Int) {
        if (_state.value.transport != "poll") { _state.update { it.copy(transport = "poll") }; said("transport poll") }
        poll(mine)
    }

    // ---- The socket ----

    private fun connect() {
        stopTransport()
        val mine = run
        val code = _state.value.code ?: return
        val k = key ?: return
        schedulePing(mine)
        val sock = if (forcePoll) null else wire.socket(code, object : ReadSocketListener {
            override fun onOpen() {
                scope.launch {
                    var waited = 0
                    while (socket == null && waited++ < 50) kotlinx.coroutines.yield()
                    if (run != mine) return@launch
                    socketOpen = true
                    retries = 0
                    socket?.send(ShareJson.encodeToString(JsonObject.serializer(), buildJsonObject { put("type", JsonPrimitive("hello")); put("key", JsonPrimitive(k)) }))
                    _state.update { it.copy(transport = "socket") }
                    said("transport socket")
                }
            }

            override fun onText(text: String) { scope.launch { if (run == mine) handle(text) } }

            override fun onClosed() { scope.launch { if (run == mine && _state.value.ended == null) fallBack(mine) } }
        })
        if (sock == null) { startPolling(mine); return }
        socket = sock
        later(OPEN_WAIT_MS, mine) { if (!socketOpen) fallBack(mine) }
    }

    private fun handle(text: String) {
        val o = runCatching { ShareJson.parseToJsonElement(text).jsonObject }.getOrNull() ?: return
        when (o["type"]?.jsonPrimitive?.contentOrNull) {
            "snapshot" -> runCatching { ShareJson.decodeFromString(ReadSnapshot.serializer(), text) }.getOrNull()?.let(::apply)
            "pong" -> {
                val t0 = o["t0"]?.jsonPrimitive?.doubleOrNull
                val st = o["server_time"]?.jsonPrimitive?.doubleOrNull
                if (t0 != null && st != null) sample(t0, st, now())
            }
            "error" -> {
                val code = o["error"]?.jsonPrimitive?.contentOrNull ?: "error"
                if (code in GONE) end(code) else _state.update { it.copy(refusal = code) }
            }
        }
    }

    private fun fallBack(mine: Int) {
        if (run != mine || _state.value.ended != null) return
        socket?.close()
        socket = null
        socketOpen = false
        startPolling(mine)
        val wait = RETRY_MS[minOf(retries, RETRY_MS.lastIndex)]
        retries += 1
        later(wait, mine) { connect() }
    }

    // ---- The clock ----

    private fun sample(t0: Double, serverTime: Double, t1: Double) {
        samples.addLast(ReadCore.ClockSample(t0, serverTime, t1))
        if (samples.size > 8) samples.removeFirst()
        val offset = ReadCore.clockOffset(samples.toList())
        _state.update { it.copy(clockOffsetMs = offset) }
        said("clock offset $offset samples ${samples.size}")
    }

    private fun schedulePing(mine: Int) {
        later(PING_MS, mine) {
            val code = _state.value.code
            val k = key
            if (code != null && k != null) {
                val t0 = now()
                val ping = buildJsonObject { put("type", JsonPrimitive("ping")); put("t0", JsonPrimitive(t0)) }
                val sock = socket
                if (socketOpen && sock != null) sock.send(ShareJson.encodeToString(JsonObject.serializer(), ping))
                else runCatching { wire.send(code, k, ping) }.getOrNull()?.let { apply(it); sample(t0, it.serverTime, now()) }
            }
            schedulePing(mine)
        }
    }

    companion object {
        val GONE = setOf("no_such_room", "room_ended", "not_a_member", "seat_key_required")
        val RETRY_MS = longArrayOf(2000, 5000, 15000, 30000)
        const val PING_MS = 10_000L
        const val OPEN_WAIT_MS = 5000L
    }
}
