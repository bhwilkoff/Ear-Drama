package com.example.appname.plays

/**
 * Reading together, the client side of worker/src/read-protocol.js (PLAYS-DESIGN §12, Decision 082).
 *
 * PURE, like js/read-core.js and the Swift ReadCore it matches: no network, no clock. A PORT of the Worker's
 * rules, not a re-derivation; ReadCoreTest holds it to worker/test/read-golden.json, the file every client
 * reads. Also the casting board's arithmetic (§12.4): a deterministic proposal the teacher accepts or edits.
 * The app never suggests who should read what.
 */
object ReadCore {
    const val CODE_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    const val CODE_LENGTH = 6
    const val MAX_MEMBERS = 40
    const val MEMBER_GONE_MS = 2 * 60 * 1000L
    const val LEADER_GONE_MS = 2 * 60 * 1000L
    const val POLL_MS = 1000L
    val MODES = listOf("read", "rehearse", "record")

    /** §12.6: a polled cursor slower than this shows "Slow connection". */
    const val SLOW_MS = 2000L

    data class Member(val id: String, val role: String, val seat: String?, val joinedAt: Double, val seenAt: Double)
    data class Seat(val id: String, val label: String)
    data class Assignment(val part: String, val seat: String, val from: String? = null, val to: String? = null)
    data class Room(
        val kind: String,
        val mode: String = "read",
        val cursor: String = "",
        val cursorGen: Int = 0,
        val generation: Int = 0,
        val leader: String = "",
        val claims: Map<String, String> = emptyMap(),
        val seats: List<Seat> = emptyList(),
        val assignments: List<Assignment> = emptyList(),
        val done: List<String> = emptyList(),
        val locked: Boolean = false,
        val ended: Boolean = false,
    )
    data class PartRange(val part: String, val from: String?, val to: String?)
    data class Next(val line: String, val inLines: Int)
    data class Reads(val part: String, val seat: String?, val holder: String?, val members: List<String>)
    data class Lead(val leader: String, val waiting: Boolean)
    data class ClockSample(val t0: Double, val serverTime: Double, val t1: Double)

    // ---- Codes and the clock ----

    fun normalizeCode(typed: String): String? {
        val out = StringBuilder()
        for (ch in typed.uppercase()) {
            when {
                ch == ' ' || ch == '-' || ch == '_' -> continue
                ch == 'I' || ch == 'L' -> out.append('1')
                ch == 'O' -> out.append('0')
                ch in CODE_ALPHABET -> out.append(ch)
                else -> return null
            }
        }
        return out.toString().takeIf { it.length == CODE_LENGTH }
    }

    fun codeFromBytes(bytes: List<Int>): String = (0 until CODE_LENGTH).map { CODE_ALPHABET[bytes[it] % CODE_ALPHABET.length] }.joinToString("")

    /** Cristian's algorithm: the sample with the smallest round trip wins, never an average. */
    fun clockOffset(samples: List<ClockSample>): Double? {
        var bestRtt = Double.NaN
        var best: Double? = null
        for (s in samples) {
            val rtt = s.t1 - s.t0
            if (rtt < 0 || rtt.isNaN()) continue
            if (best == null || rtt < bestRtt) {
                bestRtt = rtt
                best = s.serverTime - (s.t0 + s.t1) / 2
            }
        }
        return best
    }

    // ---- Who holds a line ----

    fun indexOf(cast: List<Pair<String, String>>, lineId: String): Int = cast.indexOfFirst { it.first == lineId }

    fun liveMembers(members: List<Member>, now: Double): List<Member> = members.filter { now - it.seenAt <= MEMBER_GONE_MS }

    private fun isLive(m: Member?, now: Double) = m != null && now - m.seenAt <= MEMBER_GONE_MS

    fun canLead(room: Room, memberId: String?): Boolean = !memberId.isNullOrEmpty() && room.leader == memberId

    fun partsOf(room: Room, member: Member?): List<PartRange> {
        if (member == null) return emptyList()
        if (room.kind == "class") {
            val seat = member.seat ?: return emptyList()
            return room.assignments.filter { it.seat == seat }.map { PartRange(it.part, it.from, it.to) }
        }
        return room.claims.filter { it.value == member.id }.keys.sorted().map { PartRange(it, null, null) }
    }

    fun assignmentFor(room: Room, cast: List<Pair<String, String>>, i: Int): Assignment? {
        val part = cast[i].second
        for (a in room.assignments) {
            if (a.part != part) continue
            val lo = if (a.from == null) 0 else indexOf(cast, a.from)
            val hi = if (a.to == null) cast.size - 1 else indexOf(cast, a.to)
            if (i in lo..hi) return a
        }
        return null
    }

    fun whoReads(room: Room, cast: List<Pair<String, String>>, members: List<Member>, lineId: String, now: Double): Reads? {
        val i = indexOf(cast, lineId)
        if (i < 0) return null
        val part = cast[i].second
        if (room.kind == "class") {
            val seat = assignmentFor(room, cast, i)?.seat
            val ids = if (seat != null) liveMembers(members, now).filter { it.seat == seat }.map { it.id } else emptyList()
            return Reads(part, seat, null, ids)
        }
        val holder = room.claims[part]
        val ids = if (holder != null && isLive(members.firstOrNull { it.id == holder }, now)) listOf(holder) else emptyList()
        return Reads(part, null, holder, ids)
    }

    fun holds(room: Room, cast: List<Pair<String, String>>, member: Member?, i: Int): Boolean {
        if (member == null) return false
        if (room.kind == "class") {
            val a = assignmentFor(room, cast, i) ?: return false
            return member.seat != null && a.seat == member.seat
        }
        return room.claims[cast[i].second] == member.id
    }

    fun nextMine(room: Room, cast: List<Pair<String, String>>, member: Member?, cursor: String): Next? {
        val start = maxOf(0, indexOf(cast, cursor))
        for (i in start until cast.size) if (holds(room, cast, member, i)) return Next(cast[i].first, i - start)
        return null
    }

    fun leaderGone(room: Room, members: List<Member>, now: Double): Lead {
        val leader = members.firstOrNull { it.id == room.leader }
        if (leader != null && now - leader.seenAt <= LEADER_GONE_MS) return Lead(room.leader, false)
        if (room.kind == "class") return Lead(room.leader, true)
        val next = liveMembers(members, now).filter { it.id != room.leader && it.role == "reader" }
            .sortedWith(compareBy<Member> { it.joinedAt }.thenBy { it.id })
        return next.firstOrNull()?.let { Lead(it.id, false) } ?: Lead(room.leader, true)
    }

    // ---- The client's own rules ----

    /** The leader's Next and Back: the line after or before the cursor, or null at either end. */
    fun step(cast: List<Pair<String, String>>, cursor: String, delta: Int): String? {
        val i = indexOf(cast, cursor)
        val j = i + delta
        return if (i < 0 || j < 0 || j >= cast.size) null else cast[j].first
    }

    /** Rehearse's Again: the start of the scene the cursor is in (`starts` are scene heading indexes). */
    fun sceneStart(cast: List<Pair<String, String>>, cursor: String, starts: List<Int>): String? {
        val i = maxOf(0, indexOf(cast, cursor))
        var at = 0
        for (s in starts) if (s <= i && s >= at) at = s
        return cast.getOrNull(at)?.first
    }

    /** "Next: you, in 3 lines" (a fact); null when nothing of theirs is left. */
    fun nextLine(next: Next?): String? = when {
        next == null -> null
        next.inLines == 0 -> "Your line"
        next.inLines == 1 -> "Next: you, in 1 line"
        else -> "Next: you, in ${next.inLines} lines"
    }

    /** Whoever a room waits for: the leader's name when the snapshot carries one, else a seat's label, else null ("the teacher"). */
    fun waitingFor(snap: ReadSnapshot): String? {
        snap.leaderName?.takeIf { it.isNotEmpty() }?.let { return it }
        val seat = snap.members.firstOrNull { it.id == snap.leader }?.seat ?: return null
        return snap.seats.firstOrNull { it.id == seat }?.label
    }

    private val REFUSALS = mapOf(
        "bad_code" to "That is not a reading code.",
        "no_such_room" to "No reading has that code.",
        "room_ended" to "This reading has ended.",
        "room_full" to "This reading is full.",
        "joining_locked" to "Joining is locked.",
        "seat_in_use" to "Someone is already in on another device.",
        "seat_key_required" to "Pick your name again.",
        "seat_required" to "Pick your name.",
        "part_taken" to "Someone holds that part.",
        "leader_only" to "Only the leader moves the reading.",
        "stale" to "The reading moved on.",
        "rate_limited" to "Too many tries. Try again in a minute.",
        "offline" to "You are offline.",
        "not_configured" to "Not available yet.",
        "class_not_found" to "No class has that code.",
        "revision_mismatch" to "This play has changed since it was cast.",
        "not_castable" to "This play cannot be read together.",
    )

    fun refusal(code: String): String = REFUSALS[code] ?: "Ear Drama could not be reached."

    // ---- The casting board (PLAYS-DESIGN §12.4) ----

    data class PartFacts(val part: String, val lines: Int, val words: Int, val scenes: Int, val longest: Int, val first: Int)

    fun partFacts(cast: List<Pair<String, String>>, words: List<Int>, starts: List<Int>): List<PartFacts> {
        fun sceneOf(i: Int) = starts.lastOrNull { it <= i } ?: -1
        class Acc(var lines: Int = 0, var words: Int = 0, val scenes: MutableSet<Int> = mutableSetOf(), var longest: Int = 0, val first: Int)
        val by = LinkedHashMap<String, Acc>()
        cast.forEachIndexed { i, c ->
            val w = words.getOrElse(i) { 0 }
            val f = by.getOrPut(c.second) { Acc(first = i) }
            f.lines += 1; f.words += w; f.longest = maxOf(f.longest, w); f.scenes += sceneOf(i)
        }
        return by.map { (p, f) -> PartFacts(p, f.lines, f.words, f.scenes.size, f.longest, f.first) }
    }

    data class SeatTotal(val seat: String, var lines: Int, var words: Int)

    fun seatTotals(cast: List<Pair<String, String>>, words: List<Int>, assignments: List<Assignment>, seats: List<Seat>): List<SeatTotal> {
        val room = Room(kind = "class", assignments = assignments)
        val out = seats.map { SeatTotal(it.id, 0, 0) }
        for (i in cast.indices) {
            val a = assignmentFor(room, cast, i) ?: continue
            val t = out.firstOrNull { it.seat == a.seat } ?: continue
            t.lines += 1
            t.words += words.getOrElse(i) { 0 }
        }
        return out
    }

    /** Fill evenly: every part nobody holds goes, largest by words first, to the seat with the fewest words so far. */
    fun fillEvenly(parts: List<PartFacts>, seats: List<Seat>, assignments: List<Assignment>, cast: List<Pair<String, String>>, words: List<Int>): List<Assignment> {
        if (seats.isEmpty()) return assignments
        val held = assignments.map { it.part }.toSet()
        val totals = seatTotals(cast, words, assignments, seats).toMutableList()
        val out = assignments.toMutableList()
        val open = parts.filter { it.part !in held }
            .sortedWith(compareByDescending<PartFacts> { it.words }.thenByDescending { it.lines }.thenBy { it.first })
        for (p in open) {
            val k = totals.indices.minWithOrNull(compareBy<Int> { totals[it].words }.thenBy { totals[it].lines }.thenBy { it })!!
            out += Assignment(p.part, totals[k].seat)
            totals[k].words += p.words
            totals[k].lines += p.lines
        }
        return out
    }

    data class SceneRange(val from: String, var to: String, var lines: Int, val scene: Int)

    /** Split by scene: a part's lines grouped at scene boundaries, in script order. */
    fun sceneRanges(cast: List<Pair<String, String>>, part: String, starts: List<Int>): List<SceneRange> {
        val out = mutableListOf<SceneRange>()
        var scene: Int? = null
        for (i in cast.indices) {
            if (cast[i].second != part) continue
            val s = starts.lastOrNull { it <= i }
            if (out.isEmpty() || s != scene) { out += SceneRange(cast[i].first, cast[i].first, 0, s ?: -1); scene = s }
            out.last().to = cast[i].first
            out.last().lines += 1
        }
        return out
    }
}
