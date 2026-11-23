package com.example.appname.plays

import com.example.appname.account.WorkerApi
import com.example.appname.account.WorkerException
import io.ktor.http.HttpMethod
import java.io.File
import java.io.IOException
import java.net.URLEncoder
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// Relay across time (PLAYS-DESIGN §12.11), the mirror of js/relay-core.js and js/relay-watch.js. A performer's takes are
// written on their device first; this decides when each passes through the Worker to the receiving (teacher's or
// director's) device, which is only when that device is there, and says each take's state in essential words. Nothing is
// kept anywhere but the performer's device. Tests: RelayAcrossTimeTest, against a stub Worker and a clock turned by hand.

object RelayCore {
    /** Milliseconds between asks while the receiver is away: 5, 10, 20, 40 s, then every 60 (PLAYS-DESIGN §12.11 item 3). */
    val GAPS = longArrayOf(5_000, 10_000, 20_000, 40_000, 60_000)
    fun delay(failures: Int): Long = GAPS[failures.coerceIn(0, GAPS.size - 1)]

    enum class State { Waiting, Sending, Sent }

    fun state(id: String, sent: Set<String>, sending: String?): State = when {
        id in sent -> State.Sent
        sending == id -> State.Sending
        else -> State.Waiting
    }

    /** "On this device · sends when Ms. Ortiz is in Ear Drama" (a fact, never an explanation). */
    fun wording(state: State, name: String?, fallback: String = "the director"): String = when (state) {
        State.Sent -> "Sent"
        State.Sending -> "Sending"
        State.Waiting -> "On this device · sends when ${name?.trim()?.takeIf { it.isNotEmpty() } ?: fallback} is in Ear Drama"
    }

    /** Refusals that mean "later": the take stays and the sender backs off. */
    val LATER = setOf("nobody_receiving", "one_take_at_a_time", "offline", "error", "rate_limited", "timeout", "not_configured", "not_delivered", "unauthorized")
    fun isLater(code: String) = code in LATER

    fun codeOf(e: Throwable): String = when (e) {
        is ReadFailure -> e.code
        is PlaysException -> when (e.kind) {
            PlaysException.Kind.Offline -> "offline"
            PlaysException.Kind.Unauthorized -> "unauthorized"
            PlaysException.Kind.NotConfigured -> "not_configured"
            PlaysException.Kind.RateLimited -> "rate_limited"
            else -> e.code.ifEmpty { "error" }
        }
        else -> "error"
    }

    /** The lines a seat may record: a part, or a scene range of it, from the assignments (the Worker's `covered`). */
    fun assignedLines(cast: List<Pair<String, String>>, assignments: List<ReadSnapshot.AssignmentRow>): List<String> {
        fun at(id: String) = cast.indexOfFirst { it.first == id }.takeIf { it >= 0 }
        val out = HashSet<String>()
        for (a in assignments) {
            val lo = a.from?.let(::at) ?: 0
            val hi = a.to?.let(::at) ?: (cast.size - 1)
            if (lo > hi) continue
            for (i in lo..hi) if (cast[i].second == a.part) out += cast[i].first
        }
        return cast.map { it.first }.filter { it in out }
    }

    /** A line's first words, for a row (a label from the script's own data). */
    fun excerpt(line: ScriptLine): String {
        val words = line.spokenText.split(Regex("\\s+")).filter { it.isNotEmpty() }
        return if (words.size > 7) words.take(7).joinToString(" ") + "…" else words.joinToString(" ")
    }

    /** One row of Your parts: the line, the take's state on this device, and the teacher's review. */
    data class Row(val id: String, val text: String, val state: String? = null, val review: String? = null, val again: Boolean = false)

    /** The rows for one part: every line the seat holds, with its take's state. [remote] is what the Worker holds of this seat's takes, by line. */
    fun rows(
        lines: List<ScriptLine>,
        local: Production?,
        remote: Map<String, SeatTake>,
        sentHere: Set<String>,
        refused: Map<String, String>,
        sending: String?,
        name: String?,
        fallback: String = "your teacher",
    ): List<Row> = lines.map { l ->
        val take = local?.chosenTake(l.id)
        val r = remote[l.id]
        when {
            r != null && r.chosen -> {
                val rv = r.review
                Row(l.id, excerpt(l), wording(State.Sent, name), rv?.let { if (it.state == "approved") "Approved" else "Again" + (it.note?.takeIf { n -> n.isNotEmpty() }?.let { n -> " · $n" } ?: "") }, rv != null && rv.state != "approved")
            }
            take != null && take.bleed -> Row(l.id, excerpt(l), PlaysShare.line(PlaysException("bleed_flagged")))
            take != null && refused[take.id] != null -> Row(l.id, excerpt(l), PlaysShare.line(PlaysException(refused.getValue(take.id))).ifEmpty { "Ear Drama could not send this take." })
            take != null -> Row(l.id, excerpt(l), wording(state(take.id, sentHere, sending), name, fallback))
            else -> Row(l.id, excerpt(l))
        }
    }
}

// ---- The Worker's side, as the sender sees it ----

@Serializable data class RelayReceiver(val receiving: Boolean = false, val name: String? = null)

@Serializable data class SeatReview(val state: String, val note: String? = null)

@Serializable data class SeatTake(val id: String, val lineID: String = "", val chosen: Boolean = false, val review: SeatReview? = null)

@Serializable
data class SeatHome(val seat: Seat, val `class`: Klass, val productions: List<Production> = emptyList()) {
    @Serializable data class Seat(val id: String, val label: String)
    @Serializable data class Klass(val id: String, val name: String)
    @Serializable data class Production(
        val id: String,
        val title: String,
        val scriptID: String,
        val scriptRevision: String,
        val assignments: List<ReadSnapshot.AssignmentRow> = emptyList(),
        val takes: List<SeatTake> = emptyList(),
    )
}

/** A seat's routes (no account: its key in `x-seat-key`). */
interface SeatWire {
    suspend fun home(key: String): SeatHome
    suspend fun receiver(key: String, pid: String): RelayReceiver
    suspend fun send(key: String, pid: String, takeId: String, bytes: ByteArray, meta: kotlinx.serialization.json.JsonObject)
}

class WorkerSeat(private val worker: WorkerApi) : SeatWire {
    private val p = "/v1/plays/seat"
    private fun enc(s: String) = URLEncoder.encode(s, "UTF-8").replace("+", "%20")

    private suspend fun <T> guarded(block: suspend () -> T): T = try {
        block()
    } catch (e: CancellationException) {
        throw e
    } catch (e: WorkerException) {
        throw ReadFailure(e.code ?: if (e.status == 429) "rate_limited" else "error")
    } catch (e: IOException) {
        throw ReadFailure("offline")
    } catch (e: com.example.appname.account.SignedOutException) {
        throw ReadFailure("not_configured")
    }

    override suspend fun home(key: String): SeatHome = guarded { ShareJson.decodeFromString(worker.anonText(HttpMethod.Get, p, null, mapOf(KEY to key))) }

    override suspend fun receiver(key: String, pid: String): RelayReceiver =
        guarded { ShareJson.decodeFromString(worker.anonText(HttpMethod.Get, "$p/productions/${enc(pid)}/receiver", null, mapOf(KEY to key))) }

    override suspend fun send(key: String, pid: String, takeId: String, bytes: ByteArray, meta: kotlinx.serialization.json.JsonObject) {
        guarded {
            worker.anonBytes(
                HttpMethod.Put, "$p/productions/${enc(pid)}/takes/${enc(takeId)}", bytes,
                mapOf(KEY to key, "content-type" to "audio/wav", "x-take" to ShareJson.encodeToString(kotlinx.serialization.json.JsonObject.serializer(), meta)),
            )
        }
    }

    private companion object { const val KEY = "x-seat-key" }
}

/** An account member's receiver probe (the director's app is open). */
interface MemberReceiverWire { suspend fun receiver(pid: String): RelayReceiver }

class WorkerMemberReceiver(private val worker: WorkerApi) : MemberReceiverWire {
    override suspend fun receiver(pid: String): RelayReceiver = try {
        ShareJson.decodeFromString(worker.callText(HttpMethod.Get, "/v1/plays/productions/${URLEncoder.encode(pid, "UTF-8").replace("+", "%20")}/receiver"))
    } catch (e: CancellationException) {
        throw e
    } catch (e: WorkerException) {
        throw ReadFailure(e.code ?: "error")
    } catch (e: IOException) {
        throw ReadFailure("offline")
    }
}

/**
 * A seat's key, kept encrypted under an Android Keystore key beside its takes (AGENTS.md: secrets never in cleartext on
 * disk). Put there only when a student records at home, never on joining a room (Decision c: a shared class device
 * keeps nothing at rest).
 */
interface SeatKeyVault {
    fun key(classId: String): String?
    fun set(classId: String, key: String)
    fun forget(classId: String)
}

class MemorySeatVault : SeatKeyVault {
    private val keys = HashMap<String, String>()
    @Synchronized override fun key(classId: String) = keys[classId]
    @Synchronized override fun set(classId: String, key: String) { keys[classId] = key }
    @Synchronized override fun forget(classId: String) { keys.remove(classId) }
}

class KeystoreSeatVault(private val dir: File) : SeatKeyVault {
    private companion object {
        const val ALIAS = "eardrama.seat"
        const val TRANSFORM = "AES/GCM/NoPadding"
        const val IV_BYTES = 12
        const val TAG_BITS = 128
    }

    private fun file(classId: String) = File(dir, "seat-" + classId.filter { it.isLetterOrDigit() || it == '-' || it == '_' } + ".bin")

    private fun secret(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).setKeySize(256).build(),
        )
        return gen.generateKey()
    }

    override fun key(classId: String): String? {
        val f = file(classId)
        if (!f.isFile) return null
        return try {
            val bytes = f.readBytes()
            val c = Cipher.getInstance(TRANSFORM)
            c.init(Cipher.DECRYPT_MODE, secret(), GCMParameterSpec(TAG_BITS, bytes, 0, IV_BYTES))
            c.doFinal(bytes, IV_BYTES, bytes.size - IV_BYTES).decodeToString()
        } catch (e: Exception) {
            f.delete()
            null
        }
    }

    override fun set(classId: String, key: String) {
        dir.mkdirs()
        val c = Cipher.getInstance(TRANSFORM)
        c.init(Cipher.ENCRYPT_MODE, secret())
        val tmp = File(file(classId).path + ".tmp")
        tmp.writeBytes(c.iv + c.doFinal(key.encodeToByteArray()))
        tmp.renameTo(file(classId))
    }

    override fun forget(classId: String) { file(classId).delete() }
}

// ---- The queue ----

/** What a sender needs of one production: the takes still to pass through, whether the receiver is there, and the passing. */
interface RelaySource {
    suspend fun pending(): List<Take>
    suspend fun probe(): RelayReceiver
    suspend fun send(take: Take)
    fun sent(take: Take)
    fun refused(take: Take, code: String)
}

data class RelayState(
    val receiving: Boolean? = null,
    val name: String? = null,
    val waiting: List<String> = emptyList(),
    val sending: String? = null,
    val error: String? = null,
    val failures: Int = 0,
    val revision: Int = 0,
)

class RelaySender(
    private val source: RelaySource,
    private val scope: CoroutineScope,
    private val pause: suspend (Long) -> Unit = { delay(it) },
    private val online: () -> Boolean = { true },
    private val foreground: StateFlow<Boolean> = MutableStateFlow(true),
) {
    private val _state = MutableStateFlow(RelayState())
    val state: StateFlow<RelayState> = _state
    private var timer: Job? = null
    private var running = false
    private var again = false
    private var stopped = false

    private fun update(change: RelayState.() -> RelayState) { _state.value = _state.value.change().let { it.copy(revision = it.revision + 1) } }

    private fun later() {
        timer?.cancel()
        if (stopped) { timer = null; return }
        val ms = RelayCore.delay(_state.value.failures - 1)
        // A backgrounded app asks nothing (each ask is a Worker request on the free account every app shares): the ask that came
        // due waits for the app to come forward. An empty ask sets no timer at all.
        timer = scope.launch { pause(ms); foreground.first { it }; timer = null; run() }
    }

    /** A take was saved, the network came back, or the app came to the front: ask now. */
    suspend fun kick() {
        update { copy(failures = 0) }
        timer?.cancel()
        timer = null
        run()
    }

    fun stop() { stopped = true; timer?.cancel(); timer = null }

    suspend fun run() {
        if (running) { again = true; return }
        if (stopped) return
        running = true
        try {
            do {
                again = false
                val todo = runCatching { source.pending() }.getOrDefault(emptyList())
                if (todo.isEmpty()) { update { copy(waiting = emptyList(), failures = 0, error = null, sending = null) }; break }
                update { copy(waiting = todo.map { it.id }) }
                if (!online()) { update { copy(failures = failures + 1, error = "offline") }; later(); break }
                val probe = try { source.probe() } catch (e: CancellationException) { throw e } catch (e: Exception) {
                    update { copy(failures = failures + 1, error = RelayCore.codeOf(e)) }; later(); break
                }
                update { copy(receiving = probe.receiving, name = probe.name ?: name) }
                if (!probe.receiving) { update { copy(failures = failures + 1, error = null) }; later(); break }
                var stuck = false
                for (take in todo) {
                    if (stopped) break
                    update { copy(sending = take.id) }
                    try {
                        source.send(take)
                        source.sent(take)
                        update { copy(waiting = waiting - take.id, failures = 0, error = null) }
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        val code = RelayCore.codeOf(e)
                        if (RelayCore.isLater(code)) { update { copy(failures = failures + 1, error = code) }; stuck = true; break }
                        update { copy(error = code, waiting = waiting - take.id) }
                        source.refused(take, code)
                    }
                }
                update { copy(sending = null) }
                if (stuck) { later(); break }
            } while (again && !stopped)
        } finally {
            running = false
        }
    }
}

// ---- Sources: a seat's production, a member's production ----

class SeatRelaySource(
    private val store: ShareStore,
    private val localId: String,
    private val script: PlayScript,
    private val wire: SeatWire,
    private val vault: SeatKeyVault,
) : RelaySource {
    private val link get() = store.share(localId)
    private val key get() = link?.seat?.let { vault.key(it.classId) }
    private fun patch(change: (ShareLink) -> ShareLink) { link?.let { store.setShare(localId, change(it)) } }

    override suspend fun pending(): List<Take> {
        val k = key ?: return emptyList()
        val pid = link?.pid ?: return emptyList()
        var remote = emptySet<String>()
        try {
            val home = wire.home(k)
            home.productions.firstOrNull { it.id == pid }?.let { p ->
                remote = p.takes.map { it.id }.toSet()
                patch { it.copy(assignments = p.assignments) }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: ReadFailure) {
            if (e.code == "seat_key_required") return emptyList()
        } catch (_: Exception) {
        }
        val lines = RelayCore.assignedLines(script.lines.map { it.id to it.part.raw }, link?.assignments.orEmpty())
        val local = store.production(localId) ?: return emptyList()
        val done = link?.sent.orEmpty().toSet() + remote
        return lines.mapNotNull { local.chosenTake(it) }.filter { !it.bleed && it.id !in done && link?.refused?.get(it.id) == null }
    }

    override suspend fun probe(): RelayReceiver {
        val k = key ?: throw ReadFailure("seat_key_required")
        return wire.receiver(k, link?.pid ?: throw ReadFailure("seat_key_required"))
    }

    override suspend fun send(take: Take) {
        val k = key ?: throw ReadFailure("seat_key_required")
        val pid = link?.pid ?: throw ReadFailure("seat_key_required")
        try { wire.send(k, pid, take.id, store.readTake(localId, take.file), PlaysShare.metaOf(take)) } catch (e: ReadFailure) { if (e.code != "take_exists") throw e }
    }

    override fun sent(take: Take) = patch { it.copy(sent = (it.sent + take.id).distinct().sorted()) }
    override fun refused(take: Take, code: String) = patch { it.copy(refused = it.refused + (take.id to code)) }
}

class MemberRelaySource(
    private val store: ShareStore,
    private val localId: String,
    private val script: PlayScript,
    private val transport: PlaysTransport,
    private val receiver: MemberReceiverWire,
    private val me: () -> String?,
) : RelaySource {
    private val link get() = store.share(localId)
    private fun patch(change: (ShareLink) -> ShareLink) { link?.let { store.setShare(localId, change(it)) } }

    override suspend fun pending(): List<Take> {
        val pid = link?.pid ?: return emptyList()
        val rec = runCatching { transport.get(pid) }.getOrNull() ?: return emptyList()
        if (!rec.uploads) return emptyList()
        val local = store.production(localId) ?: return emptyList()
        return PlaysShare.pending(local, script, rec, me()).filter { !it.bleed && link?.refused?.get(it.id) == null }
    }

    override suspend fun probe(): RelayReceiver = receiver.receiver(link?.pid ?: throw ReadFailure("not_found"))

    override suspend fun send(take: Take) {
        val pid = link?.pid ?: throw ReadFailure("not_found")
        try { transport.upload(pid, take.id, store.readTake(localId, take.file), PlaysShare.metaOf(take)) } catch (e: PlaysException) { if (e.code != "take_exists") throw e }
    }

    override fun sent(take: Take) = patch { it.copy(sent = (it.sent + take.id).distinct().sorted()) }
    override fun refused(take: Take, code: String) = patch { it.copy(refused = it.refused + (take.id to code)) }
}

// ---- The one sender per device ----

/** One RelaySender per linked production, kept alive while the app is open; kicked when a take is saved, the network returns, or the app comes forward. */
class RelayHub(
    private val store: ProductionStore,
    private val scope: CoroutineScope,
    private val seatWire: SeatWire,
    private val transport: PlaysTransport,
    private val receiver: MemberReceiverWire,
    val vault: SeatKeyVault,
    private val me: () -> String?,
    private val pause: suspend (Long) -> Unit = { delay(it) },
    private val online: () -> Boolean = { true },
) {
    private val senders = HashMap<String, RelaySender>()
    private val foreground = MutableStateFlow(true)
    private val _revision = MutableStateFlow(0)
    /** Bumped on every change so a screen reading the hub redraws. */
    val revision: StateFlow<Int> = _revision

    @Synchronized fun sender(localId: String): RelaySender? {
        senders[localId]?.let { return it }
        val link = store.share(localId) ?: return null
        val local = store.production(localId) ?: return null
        val script = store.script(local) ?: return null
        val source: RelaySource = if (link.seat != null) SeatRelaySource(store, localId, script, seatWire, vault) else MemberRelaySource(store, localId, script, transport, receiver, me)
        val s = RelaySender(source, scope, pause, online, foreground)
        senders[localId] = s
        scope.launch { s.state.collect { _revision.value += 1 } }
        return s
    }

    /** The sender's state for a production, read outside composition (a screen redraws on [revision]). */
    fun stateOf(localId: String): RelayState? = senders[localId]?.state?.value

    /** Asks now for one production, or for every linked one. */
    suspend fun kick(localId: String? = null) {
        val ids = localId?.let { listOf(it) } ?: store.all().map { it.id }.filter { store.share(it) != null }
        for (id in ids) sender(id)?.kick()
    }

    fun stop() { senders.values.forEach { it.stop() }; senders.clear() }

    /** The app came forward (started) or went to the background: a backgrounded one asks nothing until it is back. */
    fun setForeground(now: Boolean) { foreground.value = now }

    /** One take's state for a screen. */
    fun state(localId: String, takeId: String, remote: Set<String> = emptySet()): Pair<RelayCore.State, String?> {
        val sent = store.share(localId)?.sent.orEmpty().toSet() + remote
        val st = senders[localId]?.state?.value
        return RelayCore.state(takeId, sent, st?.sending) to st?.name
    }

    /** Links a production on this device to a seat's, keeping the seat key in the Keystore vault beside it (never in share.json). */
    fun linkSeat(localId: String, pid: String, classId: String, label: String, key: String, assignments: List<ReadSnapshot.AssignmentRow>) {
        vault.set(classId, key)
        val link = (store.share(localId) ?: ShareLink(pid)).copy(pid = pid, seat = SeatLink(classId, label), assignments = assignments)
        store.setShare(localId, link)
    }
}

/**
 * The receiver's pickup (mirror of RelayCore.receive in js/relay-core.js): long polls [inbox] one after another, but only while
 * [active] (the screen is started), and stops after [idleMs] with no take, calling [onIdle] so the page can offer Keep receiving
 * takes. A held pickup keeps a Durable Object awake and every app shares one free Worker account (2026-11-23), so a
 * backgrounded or forgotten page holds nothing. [inbox] returns whether a take arrived; [stopOn] ends the loop on a refusal.
 */
class PickupLoop(
    private val scope: CoroutineScope,
    private val active: StateFlow<Boolean>,
    private val now: () -> Long,
    private val inbox: suspend () -> Boolean,
    private val stopOn: (Throwable) -> Boolean = { false },
    private val onIdle: () -> Unit = {},
    private val idleMs: Long = IDLE_MS,
    private val pause: suspend (Long) -> Unit = { delay(it) },
) {
    @Volatile var stopped = false
        private set
    private var job: Job? = null

    fun start(): Job {
        job?.let { return it }
        return scope.launch {
            var lastTake = now()
            var wait = 0L
            while (isActive && !stopped) {
                if (!active.value) {
                    active.first { it }
                    lastTake = now()
                    continue
                }
                if (now() - lastTake >= idleMs) { stop(); onIdle(); return@launch }
                try {
                    val got = inbox()
                    wait = 0
                    if (stopped) break
                    if (got) lastTake = now()
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    if (stopped || stopOn(e)) break
                    wait = minOf(30_000, if (wait == 0L) 2_000 else wait * 2)
                    pause(wait)
                }
            }
            stop()
        }.also { job = it }
    }

    fun stop() { stopped = true; job?.cancel() }

    companion object {
        /** A receiver stops holding its pickup after this long with no take (PLAYS-DESIGN §12.11 item 4). */
        const val IDLE_MS = 30L * 60 * 1000
    }
}

/**
 * While the teacher's class page is open and started, one long poll per class production keeps the teacher's app "there" for the Worker
 * (`GET /productions/:pid/takes/inbox`); each take that passes through is kept in a production on this device and nowhere
 * else (Decision 082). [arrived] counts them so the progress list can refresh.
 */
class ClassInbox(
    private val store: ShareStore,
    private val transport: PlaysTransport,
    private val scope: CoroutineScope,
    private val script: suspend (String, String) -> PlayScript?,
    private val onArrival: () -> Unit = {},
    private val now: () -> Long = { System.currentTimeMillis() },
    private val idleMs: Long = PickupLoop.IDLE_MS,
    private val pause: suspend (Long) -> Unit = { delay(it) },
) {
    private val loops = HashMap<String, PickupLoop>()
    private val known = HashMap<String, Pair<String, String>>()
    private val shown = MutableStateFlow(true)
    private val _arrived = MutableStateFlow(0)
    val arrived: StateFlow<Int> = _arrived
    private val _idle = MutableStateFlow(false)
    /** Thirty minutes passed with no take: the pickups are let go and the page offers Keep receiving takes. */
    val idle: StateFlow<Boolean> = _idle

    @Synchronized fun hold(pid: String, scriptId: String, revision: String) {
        known[pid] = scriptId to revision
        if (loops.containsKey(pid) || _idle.value) return
        val loop = PickupLoop(
            scope, shown, now,
            inbox = {
                val picked = transport.nextTake(pid)
                val s = if (picked != null) script(scriptId, revision) else null
                if (picked != null && s != null) { accept(picked, pid, s); true } else false
            },
            stopOn = { e -> RelayCore.codeOf(e) in setOf("director_only", "not_found", "pass_through_unavailable", "unauthorized", "not_configured") },
            onIdle = { letGo() },
            idleMs = idleMs, pause = pause,
        )
        loops[pid] = loop
        loop.start()
    }

    /** The screen is started (lifecycle STARTED or RESUMED) or not: a hidden page holds no pickup. */
    fun setActive(now: Boolean) { shown.value = now }

    /** Keep receiving takes: the pickups start again for every production this page holds. */
    fun keepReceiving() {
        _idle.value = false
        val all = synchronized(this) { known.toMap() }
        all.forEach { (pid, k) -> hold(pid, k.first, k.second) }
    }

    @Synchronized private fun letGo() {
        loops.values.forEach { it.stop() }
        loops.clear()
        _idle.value = true
    }

    private fun accept(picked: PickedTake, pid: String, script: PlayScript) {
        val local = PlaysShare.localFor(store, pid, script)
        val t = picked.fields
        if (local.take(t.id) != null) return
        val file = "m-${t.id}.wav"
        store.importTake(local.id, file, picked.bytes)
        val cur = store.production(local.id) ?: return
        store.save(cur.add(Take(t.id, t.lineID, PartID(t.part), file, ReferenceDate.now(), t.frames, t.sampleRate,
            when (t.capture) { "aec" -> Take.Capture.Aec; "room" -> Take.Capture.Room; else -> Take.Capture.Direct }, emptyMap(), null, 0f, false)))
        _arrived.value += 1
        onArrival()
    }

    @Synchronized fun release() { loops.values.forEach { it.stop() }; loops.clear(); known.clear() }
}
