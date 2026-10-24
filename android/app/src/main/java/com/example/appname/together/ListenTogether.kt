package com.example.appname.together

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/** The player a room drives, seen through what the protocol needs (`EngineRoomPlayer` on the device). */
interface RoomPlayer {
    /** The host's state from the episode playing, its exact copy included, or null when nothing can be shared. */
    fun hostState(): RoomState?

    /** The guest's player now, or null when it holds nothing. */
    fun sample(): PlayerSample?

    /** The episode the player holds. */
    fun episodeId(): String?

    /** Loads the host's copy at [position] (seconds), playing or paused, at [rate]. */
    suspend fun load(state: RoomState, position: Double)

    fun apply(correction: Correction)

    /** Called on every play, pause, seek, speed, or episode change; the room publishes it when this device hosts. */
    fun onChange(listener: (() -> Unit)?)

    /** Called when the person, not the room, pauses (true) or plays (false): a guest's own hold. */
    fun onGuestHold(listener: ((Boolean) -> Unit)?)
}

/** What the Listen together sheet draws. */
sealed interface RoomStatus {
    /** The Worker URL is a placeholder: nothing is offered and no error shows. */
    data object Unavailable : RoomStatus

    /** Out of a room; [line] is the last plain line (a wrong code, an ended room), or null. */
    data class Out(val line: String? = null) : RoomStatus

    data object Busy : RoomStatus

    /** [held]: a guest paused their own sound (Decision 067); the room plays on. */
    data class In(val code: String, val isHost: Boolean, val members: Int, val held: Boolean = false) : RoomStatus
}

/**
 * A Listen Together room on this device (ANDROID-DESIGN §4.13). The host
 * publishes its whole state whenever its player changes; every member, the
 * host too, reads at `RoomProtocol.pollInterval` (presence needs a read at
 * least every 30 s), and a guest applies `RoomProtocol.correction` to the
 * read. When a read says this device is now host (handoff), the controls are
 * its and its speed snaps back to the room's. Only the host's key writes:
 * a guest never sends state at all. A guest may pause their own sound
 * (Decision 067): no correction applies while held, the room never hears of
 * it, and play catches them up to where the host is now.
 */
class ListenTogether(
    private val api: RoomsApi,
    private val player: RoomPlayer,
    private val scope: CoroutineScope,
    private val now: () -> Long = System::currentTimeMillis,
    /** False in tests, which call [pollOnce] themselves. */
    private val autoPoll: Boolean = true,
) {
    private val _status = MutableStateFlow<RoomStatus>(if (api.available) RoomStatus.Out() else RoomStatus.Unavailable)
    val status: StateFlow<RoomStatus> = _status

    private var code: String? = null
    private var key: String? = null
    private var isHost = false
    private var generation = -1L
    private var lastChangeAt = 0L
    private val samples = ArrayDeque<ClockSample>()
    private var poller: Job? = null
    private var pendingPublish: Job? = null
    private var held = false
    private var last: RoomSnapshot? = null

    val inRoom: Boolean get() = _status.value is RoomStatus.In
    val isGuest: Boolean get() = (_status.value as? RoomStatus.In)?.isHost == false

    /** Starts a room from the episode playing, its exact copy. */
    suspend fun create() {
        if (!api.available || inRoom) return
        val state = player.hostState() ?: return
        _status.value = RoomStatus.Busy
        try {
            enter(api.create(state))
        } catch (e: RoomException) {
            _status.value = RoomStatus.Out(lineFor(e))
        }
    }

    /** Joins by a typed code; a code that cannot be one is refused without a request. */
    suspend fun join(typed: String) {
        if (!api.available || inRoom) return
        val normalized = RoomProtocol.normalizeCode(typed) ?: run {
            _status.value = RoomStatus.Out(NO_SUCH_ROOM)
            return
        }
        _status.value = RoomStatus.Busy
        try {
            val entered = api.join(normalized)
            enter(entered)
            follow(entered.snapshot)
        } catch (e: RoomException) {
            _status.value = RoomStatus.Out(lineFor(e))
        }
    }

    /** Leaves; the Worker hands the room on if this device was host. */
    suspend fun leave() {
        val (c, k) = current() ?: return
        exit(null)
        try {
            api.leave(c, k)
        } catch (_: RoomException) {
            // Gone either way: a member not heard from for two minutes has left.
        }
    }

    /** The host ends the room for everyone. A guest cannot. */
    suspend fun end() {
        val (c, k) = current() ?: return
        if (!isHost) return
        try {
            api.end(c, k)
            exit(null)
        } catch (e: RoomException) {
            // Already gone is ended; offline keeps the room, and End can be pressed again.
            if (e.status == 404 || e.status == 410) exit(null)
        }
    }

    /** Sends the host's state now. Never sends for a guest: a code lets someone listen, never drive. */
    suspend fun publishNow() {
        val (c, k) = current() ?: return
        if (!isHost) return
        val state = player.hostState() ?: return
        try {
            update(api.putState(c, k, state))
        } catch (e: RoomException) {
            handle(e)
        }
    }

    /** One read: presence, role, and for a guest the correction. */
    suspend fun pollOnce() {
        val (c, k) = current() ?: return
        try {
            val (snapshot, sample) = api.read(c, k)
            addSample(sample)
            val becameHost = snapshot.isHost && !isHost
            update(snapshot)
            if (becameHost) {
                if (held) {
                    // A held guest is handed a room that played on: they take it from where the
                    // room is, never from where they paused.
                    held = false
                    publishHeld()
                    player.apply(Correction.Seek(RoomProtocol.expectedPosition(snapshot.state, serverNow()), snapshot.state.playing))
                }
                // The controls are this device's now; a drift nudge is never the room's speed.
                player.apply(Correction.Rate(snapshot.state.rate))
            } else if (!snapshot.isHost) {
                follow(snapshot)
            }
        } catch (e: RoomException) {
            handle(e)
        }
    }

    /** Where the room's clock is now, by the best sample so far. */
    fun serverNow(): Long = now() + (RoomProtocol.clockOffset(samples.toList()) ?: 0.0).toLong()

    /** The guest's own pause (true) and play (false). Play catches up at once, from the last read. */
    fun hold(on: Boolean) {
        if (!isGuest || held == on) return
        held = on
        publishHeld()
        if (!on) last?.let { snapshot -> scope.launch { follow(snapshot) } }
    }

    private fun publishHeld() {
        (_status.value as? RoomStatus.In)?.let { _status.value = it.copy(held = held) }
    }

    private suspend fun follow(snapshot: RoomSnapshot) {
        last = snapshot
        if (held) return
        val state = snapshot.state
        val serverNow = serverNow()
        val target = RoomProtocol.expectedPosition(state, serverNow)
        val sample = player.sample()
        if (sample == null || player.episodeId() != state.episodeId) {
            player.load(state, target)
            return
        }
        player.apply(RoomProtocol.correction(state, serverNow, sample))
    }

    private fun enter(entered: Entered) {
        code = entered.snapshot.code
        key = entered.key
        samples.clear()
        generation = -1
        held = false
        last = null
        update(entered.snapshot)
        player.onChange { schedulePublish() }
        player.onGuestHold { hold(it) }
        if (autoPoll) {
            poller?.cancel()
            poller = scope.launch {
                while (isActive && inRoom) {
                    delay(RoomProtocol.pollInterval(lastChangeAt, now()))
                    pollOnce()
                }
            }
        }
    }

    private fun update(snapshot: RoomSnapshot) {
        if (snapshot.generation != generation) {
            generation = snapshot.generation
            lastChangeAt = now()
        }
        isHost = snapshot.isHost
        _status.value = RoomStatus.In(snapshot.code, snapshot.isHost, snapshot.members, held && !snapshot.isHost)
    }

    private fun schedulePublish() {
        if (!isHost) return
        pendingPublish?.cancel()
        // A seek fires a discontinuity and a play state together: one write for both.
        pendingPublish = scope.launch {
            delay(PUBLISH_SETTLE_MS)
            publishNow()
        }
    }

    private fun handle(e: RoomException) {
        when (e.status) {
            404, 410 -> exit(ENDED)
            403 -> if (e.error == "not_a_member") exit(ENDED)
            // Offline or rate limited for a moment: the next read tries again.
            else -> Unit
        }
    }

    private fun exit(line: String?) {
        poller?.cancel()
        pendingPublish?.cancel()
        player.onChange(null)
        player.onGuestHold(null)
        held = false
        last = null
        code = null
        key = null
        isHost = false
        _status.value = if (api.available) RoomStatus.Out(line) else RoomStatus.Unavailable
    }

    private fun current(): Pair<String, String>? {
        val c = code ?: return null
        val k = key ?: return null
        return c to k
    }

    private fun addSample(sample: ClockSample) {
        samples.addLast(sample)
        while (samples.size > MAX_SAMPLES) samples.removeFirst()
    }

    companion object {
        const val NO_SUCH_ROOM = "No room has that code."
        const val ENDED = "This room has ended."
        const val FULL = "This room is full."
        const val LIMITED = "Too many tries. Wait a minute."
        const val UNREACHABLE = "Could not reach the room."
        const val NOT_AVAILABLE = "Listen together is not available in this build."
        private const val MAX_SAMPLES = 8
        private const val PUBLISH_SETTLE_MS = 200L

        fun lineFor(e: RoomException): String = when (e.status) {
            404, 400 -> NO_SUCH_ROOM
            410 -> ENDED
            409 -> FULL
            429 -> LIMITED
            else -> UNREACHABLE
        }
    }
}
