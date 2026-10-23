package com.example.appname.together

/**
 * Listen Together's client rules, ported from `worker/src/room-protocol.js`
 * (Decision 065, docs/WORKER.md "Listen Together rooms"), never re-derived.
 *
 * PURE. This file imports nothing and touches no network, clock, or player:
 * every function takes `now` and returns a value (AGENTS.md: the protocol
 * with no networking import, each transport a thin adapter). `RoomsApi` is
 * the HTTP adapter; `ListenTogether` applies these answers to the player.
 * `RoomProtocolTest` holds every function here to the Worker's own answers
 * (`android/scripts/room-golden.mjs`) and fails if this file gains an import.
 */

/** The room's public state: what the host's player is doing. Positions in seconds, times in server ms. */
data class RoomState(
    val episodeId: String,
    val archiveId: String,
    val file: String,
    val position: Double,
    val playing: Boolean,
    val rate: Double,
    val updatedAt: Long,
)

/** What every read answers (the room message). */
data class RoomSnapshot(
    val code: String,
    val isHost: Boolean,
    val members: Int,
    val generation: Long,
    val state: RoomState,
    val serverTime: Long,
)

/** One read's clock sample: local ms before and after, and the server's ms in between. */
data class ClockSample(val t0: Long, val serverTime: Long, val t1: Long)

/** A guest's player as the correction sees it. */
data class PlayerSample(val position: Double, val playing: Boolean)

/** A member as the server keeps it, for handoff. */
data class RoomMember(val id: String, val joinedAt: Long, val seenAt: Long)

/** What the guest's player does, applied silently. */
sealed interface Correction {
    data object None : Correction
    data class Pause(val position: Double) : Correction
    data class Seek(val position: Double, val play: Boolean) : Correction
    data class Play(val position: Double, val rate: Double) : Correction
    data class Rate(val rate: Double) : Correction
}

object RoomProtocol {
    const val CODE_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    const val CODE_LENGTH = 6
    const val MAX_MEMBERS = 20
    const val MEMBER_GONE_MS = 2 * 60 * 1000L

    /** Decision 062's speeds; a room carries one of them, never a drift nudge. */
    val SPEEDS = listOf(0.75, 1.0, 1.25, 1.5, 2.0)
    private const val MAX_POSITION_S = 7 * 86400.0

    /** Archive Watch SHAREPLAY §11.3, as `DRIFT` in room-protocol.js. Seconds and ms. */
    const val IGNORE_BELOW = 0.15
    const val SEEK_ABOVE = 2.0
    const val NUDGE = 0.03
    const val POLL_FAST_MS = 2000L
    const val POLL_SLOW_MS = 10000L
    const val SLOW_AFTER_STILL_MS = 60000L

    /** `normalizeCode`: spaces, `-` and `_` dropped, I and L read as 1, O as 0; null for anything else. */
    fun normalizeCode(typed: String?): String? {
        if (typed == null) return null
        val out = StringBuilder()
        for (ch in typed.uppercase()) {
            when {
                ch == ' ' || ch == '-' || ch == '_' -> continue
                ch == 'I' || ch == 'L' -> out.append('1')
                ch == 'O' -> out.append('0')
                ch !in CODE_ALPHABET -> return null
                else -> out.append(ch)
            }
        }
        return out.toString().takeIf { it.length == CODE_LENGTH }
    }

    /** `cleanCopy`: an archive.org identifier and a file inside it, never a URL or a path out of it. */
    fun cleanCopy(archiveId: String, file: String): Boolean {
        if (archiveId.isEmpty() || archiveId.length > 100) return false
        if (archiveId.any { !(it in 'A'..'Z' || it in 'a'..'z' || it in '0'..'9' || it == '.' || it == '_' || it == '-') }) return false
        if (file.isEmpty() || file.length > 400) return false
        if (file.startsWith("/") || file.contains('\\') || file.any { it.code < 0x20 || it.code == 0x7f }) return false
        return file.split('/').none { it == ".." || it == "." || it.isEmpty() }
    }

    /** `expectedPosition`: where the host is at server time [now]. */
    fun expectedPosition(state: RoomState, now: Long): Double {
        if (!state.playing) return state.position
        return minOf(MAX_POSITION_S, state.position + ((now - state.updatedAt) / 1000.0) * state.rate)
    }

    /** `clockOffset` (Cristian's algorithm): the smallest round trip's offset to ADD to the local clock. */
    fun clockOffset(samples: List<ClockSample>): Double? {
        var bestRtt = Long.MAX_VALUE
        var best: Double? = null
        for (s in samples) {
            val rtt = s.t1 - s.t0
            if (rtt < 0) continue
            if (best == null || rtt < bestRtt) {
                bestRtt = rtt
                best = s.serverTime - (s.t0 + s.t1) / 2.0
            }
        }
        return best
    }

    /**
     * `correction`: play and pause follow at once; under 150 ms nothing; 150 ms
     * to 2 s the host's rate times 0.97 or 1.03; over 2 s a seek. A stalled
     * guest catches up; the room never waits.
     */
    fun correction(state: RoomState, serverNow: Long, player: PlayerSample): Correction {
        val target = expectedPosition(state, serverNow)
        if (!state.playing) {
            if (player.playing) return Correction.Pause(target)
            return if (kotlin.math.abs(player.position - target) > IGNORE_BELOW) Correction.Seek(target, play = false) else Correction.None
        }
        val off = player.position - target
        val far = kotlin.math.abs(off)
        if (far > SEEK_ABOVE) return Correction.Seek(target, play = true)
        if (!player.playing) return Correction.Play(target, state.rate)
        if (far < IGNORE_BELOW) return Correction.Rate(state.rate)
        return Correction.Rate(state.rate * if (off > 0) 1 - NUDGE else 1 + NUDGE)
    }

    /** `pollInterval`: 2 s while things change, 10 s after a minute of stillness. */
    fun pollInterval(lastChangeAt: Long, now: Long): Long =
        if (now - lastChangeAt > SLOW_AFTER_STILL_MS) POLL_SLOW_MS else POLL_FAST_MS

    /** `liveMembers`. */
    fun liveMembers(members: List<RoomMember>, now: Long): List<RoomMember> = members.filter { now - it.seenAt <= MEMBER_GONE_MS }

    /** `nextHost`: the member present longest takes over (ties by id); null ends the room. */
    fun nextHost(members: List<RoomMember>, leavingId: String?, now: Long): String? =
        liveMembers(members, now).filter { it.id != leavingId }
            .sortedWith(compareBy<RoomMember> { it.joinedAt }.thenBy { it.id })
            .firstOrNull()?.id

    /** The speed a host publishes: one of [SPEEDS], so a nudged rate is never sent. */
    fun roomRate(speed: Double): Double = SPEEDS.minBy { kotlin.math.abs(it - speed) }

    private const val UNRESERVED = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()"
    private const val HEX = "0123456789ABCDEF"
    private const val DOWNLOAD = "https://archive.org/download/"

    /**
     * Every client builds the guest's URL itself from the host's copy
     * (docs/WORKER.md): `https://archive.org/download/<id>/<file>`, each path
     * segment encoded as encodeURIComponent does.
     */
    fun copyUrl(archiveId: String, file: String): String =
        DOWNLOAD + archiveId + "/" + file.split('/').joinToString("/") { encode(it) }

    /** The host's copy from the catalog's percent-encoded recording URL, or null for any other host. */
    fun copyOf(url: String): Pair<String, String>? {
        if (!url.startsWith(DOWNLOAD)) return null
        val rest = url.removePrefix(DOWNLOAD).substringBefore('?').substringBefore('#')
        val archiveId = rest.substringBefore('/')
        val file = decode(rest.substringAfter('/', "")) ?: return null
        return if (cleanCopy(archiveId, file)) archiveId to file else null
    }

    private fun encode(raw: String): String {
        val out = StringBuilder()
        for (byte in raw.encodeToByteArray()) {
            val c = byte.toInt() and 0xFF
            if (c < 0x80 && c.toChar() in UNRESERVED) out.append(c.toChar())
            else out.append('%').append(HEX[c shr 4]).append(HEX[c and 0xF])
        }
        return out.toString()
    }

    /** `%XX` as UTF-8; null for a malformed escape. */
    private fun decode(s: String): String? {
        val bytes = ArrayList<Byte>(s.length)
        var i = 0
        while (i < s.length) {
            val c = s[i]
            if (c == '%') {
                val hex = s.substring(i + 1, minOf(s.length, i + 3)).takeIf { it.length == 2 }?.toIntOrNull(16) ?: return null
                bytes.add(hex.toByte())
                i += 3
            } else {
                c.toString().encodeToByteArray().forEach { bytes.add(it) }
                i += 1
            }
        }
        return bytes.toByteArray().decodeToString()
    }
}
