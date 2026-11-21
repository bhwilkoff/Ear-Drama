// Reading together, the client side of worker/src/read-protocol.js (PLAYS-DESIGN §12, Decision 082).
//
// PURE, like js/read-core.js and the Kotlin ReadCore it matches: no import, no network, no clock. A PORT of
// the Worker's rules, not a re-derivation; ReadCoreTests holds it to worker/test/read-golden.json, the file
// every client reads. Also the casting board's arithmetic (§12.4): a deterministic proposal the teacher
// accepts or edits. The app never suggests who should read what.

nonisolated enum ReadCore {
    static let protocolVersion = 1
    static let codeAlphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    static let codeLength = 6
    static let maxMembers = 40
    static let memberGoneMS: Double = 2 * 60 * 1000
    static let leaderGoneMS: Double = 2 * 60 * 1000
    static let pollMS = 1000
    static let modes = ["read", "rehearse", "record"]
    /// §12.6: a polled cursor slower than this shows "Slow connection".
    static let slowMS: Double = 2000
    static let nameMax = 40

    struct Member: Equatable, Sendable {
        var id: String
        var role: String
        var seat: String?
        var joinedAt: Double
        var seenAt: Double
        var name: String?
    }

    struct Seat: Equatable, Sendable, Identifiable { var id: String; var label: String }

    struct Assignment: Equatable, Sendable {
        var part: String
        var seat: String
        var from: String?
        var to: String?
        init(part: String, seat: String, from: String? = nil, to: String? = nil) {
            self.part = part; self.seat = seat; self.from = from; self.to = to
        }
    }

    struct Room: Equatable, Sendable {
        var kind: String
        var mode = "read"
        var cursor = ""
        var cursorGen = 0
        var generation = 0
        var leader = ""
        var owner = ""
        var ownerName: String?
        var claims: [String: String] = [:]
        var seats: [Seat] = []
        var assignments: [Assignment] = []
        var done: [String] = []
        var locked = false
        var ended = false
    }

    struct PartRange: Equatable, Sendable { var part: String; var from: String?; var to: String? }
    struct Next: Equatable, Sendable { var line: String; var inLines: Int }
    struct Reads: Equatable, Sendable {
        var part: String
        var seat: String?
        var holder: String?
        var members: [String]
    }
    struct Lead: Equatable, Sendable { var leader: String; var waiting: Bool }

    // MARK: - Codes and the clock

    static func normalizeCode(_ typed: String) -> String? {
        var out = ""
        for ch in typed.uppercased() {
            if ch == " " || ch == "-" || ch == "_" { continue }
            if ch == "I" || ch == "L" { out.append("1"); continue }
            if ch == "O" { out.append("0"); continue }
            guard codeAlphabet.contains(ch) else { return nil }
            out.append(ch)
        }
        return out.count == codeLength ? out : nil
    }

    static func codeFromBytes(_ bytes: [Int]) -> String {
        String((0..<codeLength).map { codeAlphabet[bytes[$0] % codeAlphabet.count] })
    }

    struct ClockSample: Equatable, Sendable { var t0: Double; var serverTime: Double; var t1: Double }

    /// Cristian's algorithm: the sample with the smallest round trip wins, never an average.
    static func clockOffset(_ samples: [ClockSample]) -> Double? {
        var best: (rtt: Double, offset: Double)?
        for s in samples {
            let rtt = s.t1 - s.t0
            guard rtt >= 0 else { continue }
            if best == nil || rtt < best!.rtt { best = (rtt, s.serverTime - (s.t0 + s.t1) / 2) }
        }
        return best?.offset
    }

    // MARK: - Who holds a line

    static func indexOf(_ cast: [(String, String)], _ lineID: String) -> Int? {
        cast.firstIndex { $0.0 == lineID }
    }

    static func liveMembers(_ members: [Member], now: Double) -> [Member] {
        members.filter { now - $0.seenAt <= memberGoneMS }
    }

    private static func isLive(_ m: Member?, now: Double) -> Bool {
        guard let m else { return false }
        return now - m.seenAt <= memberGoneMS
    }

    private static func byJoined(_ a: Member, _ b: Member) -> Bool {
        a.joinedAt != b.joinedAt ? a.joinedAt < b.joinedAt : a.id < b.id
    }

    static func canLead(_ room: Room, memberID: String?) -> Bool {
        guard let memberID, !memberID.isEmpty else { return false }
        return room.leader == memberID
    }

    static func partsOf(_ room: Room, member: Member?) -> [PartRange] {
        guard let member else { return [] }
        if room.kind == "class" {
            guard let seat = member.seat else { return [] }
            return room.assignments.filter { $0.seat == seat }.map { PartRange(part: $0.part, from: $0.from, to: $0.to) }
        }
        return room.claims.filter { $0.value == member.id }.map(\.key).sorted().map { PartRange(part: $0, from: nil, to: nil) }
    }

    static func assignmentFor(_ room: Room, _ cast: [(String, String)], _ i: Int) -> Assignment? {
        let part = cast[i].1
        for a in room.assignments where a.part == part {
            let lo = a.from == nil ? 0 : (indexOf(cast, a.from!) ?? -1)
            let hi = a.to == nil ? cast.count - 1 : (indexOf(cast, a.to!) ?? -1)
            if i >= lo && i <= hi { return a }
        }
        return nil
    }

    static func whoReads(_ room: Room, cast: [(String, String)], members: [Member], lineID: String, now: Double) -> Reads? {
        guard let i = indexOf(cast, lineID) else { return nil }
        let part = cast[i].1
        if room.kind == "class" {
            let seat = assignmentFor(room, cast, i)?.seat
            let ids = seat.map { s in liveMembers(members, now: now).filter { $0.seat == s }.map(\.id) } ?? []
            return Reads(part: part, seat: seat, holder: nil, members: ids)
        }
        let holder = room.claims[part]
        let ids = holder != nil && isLive(members.first { $0.id == holder }, now: now) ? [holder!] : []
        return Reads(part: part, seat: nil, holder: holder, members: ids)
    }

    static func holds(_ room: Room, _ cast: [(String, String)], _ member: Member?, _ i: Int) -> Bool {
        guard let member else { return false }
        if room.kind == "class" {
            guard let a = assignmentFor(room, cast, i), let seat = member.seat else { return false }
            return a.seat == seat
        }
        return room.claims[cast[i].1] == member.id
    }

    static func nextMine(_ room: Room, cast: [(String, String)], member: Member?, cursor: String) -> Next? {
        let start = max(0, indexOf(cast, cursor) ?? 0)
        guard start < cast.count else { return nil }
        for i in start..<cast.count where holds(room, cast, member, i) {
            return Next(line: cast[i].0, inLines: i - start)
        }
        return nil
    }

    /// Every line index the member reads (their parts, or their seat's ranges).
    static func mineIndexes(_ room: Room, cast: [(String, String)], member: Member?) -> [Int] {
        cast.indices.filter { holds(room, cast, member, $0) }
    }

    static func leaderGone(_ room: Room, members: [Member], now: Double) -> Lead {
        if let l = members.first(where: { $0.id == room.leader }), now - l.seenAt <= leaderGoneMS {
            return Lead(leader: room.leader, waiting: false)
        }
        if room.kind == "class" { return Lead(leader: room.leader, waiting: true) }
        let next = liveMembers(members, now: now).filter { $0.id != room.leader && $0.role == "reader" }.sorted(by: byJoined)
        return next.first.map { Lead(leader: $0.id, waiting: false) } ?? Lead(leader: room.leader, waiting: true)
    }

    // MARK: - The client's own rules over a snapshot

    /// A snapshot replaces the one in hand only when it is as new or newer (a slow poll never rewinds the cursor).
    static func newer(prev: ReadSnapshot?, snap: ReadSnapshot) -> Bool {
        guard let prev, prev.code == snap.code else { return true }
        return snap.generation > prev.generation || (snap.generation == prev.generation && snap.serverTime >= prev.serverTime)
    }

    /// The leader's Next and Back: the line after or before the cursor, or nil at either end.
    static func step(_ cast: [(String, String)], cursor: String, delta: Int) -> String? {
        guard let i = indexOf(cast, cursor) else { return nil }
        let j = i + delta
        return j < 0 || j >= cast.count ? nil : cast[j].0
    }

    /// Rehearse's Again: the start of the scene the cursor is in (`starts` are scene heading indexes).
    static func sceneStart(_ cast: [(String, String)], cursor: String, starts: [Int]) -> String? {
        let i = max(0, indexOf(cast, cursor) ?? 0)
        var at = 0
        for s in starts where s <= i && s >= at { at = s }
        return at < cast.count ? cast[at].0 : nil
    }

    /// "Next: you, in 3 lines" (a fact); nil when nothing of theirs is left.
    static func nextLine(_ next: Next?) -> String? {
        guard let next else { return nil }
        if next.inLines == 0 { return "Your line" }
        return next.inLines == 1 ? "Next: you, in 1 line" : "Next: you, in \(next.inLines) lines"
    }

    /// Whoever a room waits for: the leader's name when the snapshot carries one, else nil ("the teacher").
    static func waitingFor(_ snap: ReadSnapshot) -> String? {
        if let n = snap.leaderName, !n.isEmpty { return n }
        let m = snap.members.first { $0.id == snap.leader }
        return m?.seat.flatMap { id in snap.seats.first { $0.id == id }?.label }
    }

    // MARK: - Names, the receiver, Record in the room (PLAYS-DESIGN §12.10)

    /// An adult's name on join: trimmed, at most 40, no control characters. `.none` for none, `.refused` for a bad one.
    enum Name: Equatable, Sendable { case none, refused, name(String) }

    static func cleanName(_ room: Room, _ raw: String?) -> Name {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .none }
        if room.kind == "class" { return .none }
        if raw.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f }) { return .refused }
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.count > nameMax ? .refused : .name(name)
    }

    /// Whose device receives the room's takes: a class's teacher whoever leads, an adult room's leader.
    static func receiverOf(_ room: Room) -> String { room.kind == "class" ? room.owner : room.leader }

    /// Whether a member may send a take of a line: the refusal's code, or nil.
    static func recordRefusal(_ room: Room, cast: [(String, String)], member: Member?, lineID: String) -> String? {
        if room.ended { return "room_ended" }
        if room.mode != "record" { return "not_recording" }
        guard let member, member.role == "reader" else { return "readers_only" }
        guard let i = indexOf(cast, lineID) else { return "no_such_line" }
        if member.id == receiverOf(room) { return "receiver_records_here" }
        if !holds(room, cast, member, i) { return "not_your_line" }
        return nil
    }

    static func leaderName(_ room: Room, members: [Member]) -> String? {
        let lead = members.first { $0.id == room.leader }
        if let seat = lead?.seat, let label = room.seats.first(where: { $0.id == seat })?.label { return label }
        if room.leader == room.owner, let n = room.ownerName { return n }
        return lead?.name
    }

    /// Who reads a line, by name: a seat's label, or the name an adult gave; nil when nobody named holds it.
    static func readerName(_ snap: ReadSnapshot, _ reads: ReadSnapshot.ReadsNow?) -> String? {
        guard let reads else { return nil }
        if let seat = reads.seat { return snap.seats.first { $0.id == seat }?.label }
        let id = reads.holder ?? reads.members.first
        return id.flatMap { id in snap.members.first { $0.id == id }?.name }
    }

    /// Whether this device opens its microphone now: Record mode, a line this member holds at the cursor and not done,
    /// never the receiving device, and not twice for the same arming (`justDid`).
    static func shouldRecord(_ snap: ReadSnapshot?, cast: [(String, String)], justDid: String?) -> Bool {
        guard let snap, !snap.ended, snap.mode == "record", let you = snap.you, you.role == "reader" else { return false }
        if you.receives == true { return false }
        guard let i = indexOf(cast, snap.cursor), holds(snap.room, cast, snap.meMember, i) else { return false }
        if snap.done.contains(snap.cursor) { return false }
        return justDid != snap.cursor
    }

    /// `justDid` after a snapshot: kept while the line stays at the cursor and undone, else cleared.
    static func settleJustDid(_ snap: ReadSnapshot?, _ justDid: String?) -> String? {
        guard let justDid, let snap else { return justDid }
        return snap.cursor != justDid || snap.done.contains(justDid) ? nil : justDid
    }

    struct TakeRow: Equatable, Sendable, Identifiable {
        enum State: String, Sendable { case recorded, away, waiting, open }
        var line: String
        var part: String
        var state: State
        var seat: String?
        var holder: String?
        var id: String { line }
    }

    struct TakeCount: Equatable, Sendable, Identifiable {
        var key: String
        var seat: String?
        var holder: String?
        var lines: Int
        var recorded: Int
        var id: String { key }
    }

    /// The receiver's Takes sheet: each speaking line in script order with its state, and the counts per reader.
    static func takeRows(_ snap: ReadSnapshot, cast: [(String, String)], arrived: Set<String>, speaking: (String) -> Bool)
        -> (rows: [TakeRow], counts: [TakeCount]) {
        let room = snap.room
        let done = Set(snap.done)
        let members = snap.members.map { Member(id: $0.id, role: $0.role, seat: $0.seat, joinedAt: 0, seenAt: $0.live ? 0 : -.infinity, name: $0.name) }
        var rows: [TakeRow] = []
        var counts: [TakeCount] = []
        for (line, part) in cast where speaking(part) {
            guard let who = whoReads(room, cast: cast, members: members, lineID: line, now: 0) else { continue }
            let key: String? = room.kind == "class" ? who.seat.map { "seat:\($0)" } : who.holder.map { "member:\($0)" }
            let state: TakeRow.State = arrived.contains(line) ? .recorded : done.contains(line) ? .away : key != nil ? .waiting : .open
            rows.append(TakeRow(line: line, part: part, state: state, seat: who.seat, holder: who.holder))
            if let key {
                var at = counts.firstIndex { $0.key == key }
                if at == nil { counts.append(TakeCount(key: key, seat: who.seat, holder: who.holder, lines: 0, recorded: 0)); at = counts.count - 1 }
                counts[at!].lines += 1
                if state == .recorded { counts[at!].recorded += 1 }
            }
        }
        return (rows, counts)
    }

    static let refusals: [String: String] = [
        "bad_code": "That is not a reading code.",
        "no_such_room": "No reading with that code.",
        "room_ended": "This reading has ended.",
        "room_full": "This reading is full.",
        "joining_locked": "Joining is locked.",
        "seat_in_use": "Someone is already in on another device.",
        "seat_key_required": "Pick your name again.",
        "seat_required": "Pick your name.",
        "part_taken": "Someone holds that part.",
        "leader_only": "Only the leader moves the reading.",
        "stale": "The reading moved on.",
        "rate_limited": "Too many tries. Try again in a minute.",
        "offline": "You are offline.",
        "not_configured": "Not available yet.",
        "class_not_found": "No class has that code.",
        "revision_mismatch": "This play has changed since it was cast.",
        "not_castable": "This play cannot be read together.",
        "bad_name": "That name is not allowed.",
        "no_such_pair": "No screen shows that code.",
        "pair_expired": "That code has expired.",
        "not_recording": "The reading is not recording.",
        "not_your_line": "That line is someone else\u{2019}s.",
        "school_consent_required": "Waits for the school\u{2019}s consent.",
        "confirmations_required": "Check both boxes first.",
        "reference_required": "Name the school or district.",
        "pending_owner_policy": "Not open yet.",
        "bad_end_date": "That is not a date.",
        "end_date_past": "Pick a later date.",
        "end_date_too_far": "Pick an earlier date.",
        "submitted": "A published play stays.",
    ]
    static func refusal(_ code: String) -> String { refusals[code] ?? "Ear Drama could not be reached." }

    // MARK: - The casting board (PLAYS-DESIGN §12.4)

    struct PartFacts: Equatable, Sendable, Identifiable {
        var part: String
        var lines: Int
        var words: Int
        var scenes: Int
        var longest: Int
        var first: Int
        var id: String { part }
    }

    static func partFacts(cast: [(String, String)], words: [Int], starts: [Int]) -> [PartFacts] {
        func sceneOf(_ i: Int) -> Int { starts.last { $0 <= i } ?? -1 }
        var by: [String: (lines: Int, words: Int, scenes: Set<Int>, longest: Int, first: Int)] = [:]
        var order: [String] = []
        for (i, c) in cast.enumerated() {
            let w = i < words.count ? words[i] : 0
            var f = by[c.1] ?? (0, 0, [], 0, i)
            if by[c.1] == nil { order.append(c.1) }
            f.lines += 1; f.words += w; f.longest = max(f.longest, w); f.scenes.insert(sceneOf(i))
            by[c.1] = f
        }
        return order.map { p in
            let f = by[p]!
            return PartFacts(part: p, lines: f.lines, words: f.words, scenes: f.scenes.count, longest: f.longest, first: f.first)
        }
    }

    struct SeatTotal: Equatable, Sendable { var seat: String; var lines: Int; var words: Int }

    static func seatTotals(cast: [(String, String)], words: [Int], assignments: [Assignment], seats: [Seat]) -> [SeatTotal] {
        let room = Room(kind: "class", assignments: assignments)
        var out = seats.map { SeatTotal(seat: $0.id, lines: 0, words: 0) }
        for i in 0..<cast.count {
            guard let a = assignmentFor(room, cast, i), let k = out.firstIndex(where: { $0.seat == a.seat }) else { continue }
            out[k].lines += 1
            out[k].words += i < words.count ? words[i] : 0
        }
        return out
    }

    /// Fill evenly: every part nobody holds goes, largest by words first, to the seat with the fewest words so far.
    static func fillEvenly(parts: [PartFacts], seats: [Seat], assignments: [Assignment], cast: [(String, String)], words: [Int]) -> [Assignment] {
        guard !seats.isEmpty else { return assignments }
        let held = Set(assignments.map(\.part))
        var totals = seatTotals(cast: cast, words: words, assignments: assignments, seats: seats)
        var out = assignments
        let open = parts.filter { !held.contains($0.part) }
            .sorted { $0.words != $1.words ? $0.words > $1.words : $0.lines != $1.lines ? $0.lines > $1.lines : $0.first < $1.first }
        for p in open {
            let k = totals.indices.min { a, b in
                let x = totals[a], y = totals[b]
                return x.words != y.words ? x.words < y.words : x.lines != y.lines ? x.lines < y.lines : a < b
            }!
            out.append(Assignment(part: p.part, seat: totals[k].seat))
            totals[k].words += p.words
            totals[k].lines += p.lines
        }
        return out
    }

    struct SceneRange: Equatable, Sendable { var from: String; var to: String; var lines: Int; var scene: Int }

    /// Split by scene: a part's lines grouped at scene boundaries, in script order.
    static func sceneRanges(cast: [(String, String)], part: String, starts: [Int]) -> [SceneRange] {
        var out: [SceneRange] = []
        var scene: Int?
        for i in 0..<cast.count where cast[i].1 == part {
            let s = starts.last { $0 <= i }
            if out.isEmpty || s != scene { out.append(SceneRange(from: cast[i].0, to: cast[i].0, lines: 0, scene: s ?? -1)); scene = s }
            out[out.count - 1].to = cast[i].0
            out[out.count - 1].lines += 1
        }
        return out
    }
}

/// The room as every member reads it (a Worker `snapshot` message). No key ever travels.
nonisolated struct ReadSnapshot: Codable, Equatable, Sendable {
    struct You: Codable, Equatable, Sendable {
        var id: String
        var role: String
        var seat: String?
        var name: String?
        var leads: Bool
        var owner: Bool
        var receives: Bool?
    }
    struct Member: Codable, Equatable, Sendable { var id: String; var role: String; var seat: String?; var name: String?; var live: Bool }
    struct Seat: Codable, Equatable, Sendable, Identifiable { var id: String; var label: String }
    struct Assignment: Codable, Equatable, Sendable { var part: String; var seat: String; var from: String?; var to: String? }
    struct NextMine: Codable, Equatable, Sendable {
        var line: String
        var `in`: Int
    }
    struct ReadsNow: Codable, Equatable, Sendable {
        var part: String
        var seat: String?
        var holder: String?
        var members: [String]
    }

    var code: String
    var kind: String
    var mode: String
    var scriptID: String?
    var scriptRevision: String?
    var productionID: String?
    var classID: String?
    var cursor: String
    var cursorGen: Int
    var generation: Int
    var locked: Bool
    var ended: Bool
    var leader: String
    var leaderName: String?
    var readOpen: Bool?
    var receiver: String?
    var waitingForLeader: Bool
    var you: You?
    var nextMine: NextMine?
    var readsNow: ReadsNow?
    var members: [Member]
    var present: Int
    var claims: [String: String]
    var seats: [Seat]
    var assignments: [Assignment]
    var done: [String]
    var serverTime: Double

    enum CodingKeys: String, CodingKey {
        case code, kind, mode, cursor, generation, locked, ended, leader, you, members, present, claims, seats, assignments, done, receiver
        case scriptID = "script_id", scriptRevision = "script_revision", productionID = "production_id", classID = "class_id"
        case cursorGen = "cursor_gen", leaderName = "leader_name", readOpen = "read_open", waitingForLeader = "waiting_for_leader"
        case nextMine = "next_mine", readsNow = "reads_now", serverTime = "server_time"
    }

    /// The room as the protocol's functions read it, rebuilt from a snapshot.
    var room: ReadCore.Room {
        ReadCore.Room(kind: kind, mode: mode, cursor: cursor, cursorGen: cursorGen, generation: generation, leader: leader,
                      owner: kind == "class" ? receiver ?? "" : "", claims: claims, seats: seats.map { ReadCore.Seat(id: $0.id, label: $0.label) },
                      assignments: assignments.map { ReadCore.Assignment(part: $0.part, seat: $0.seat, from: $0.from, to: $0.to) },
                      done: done, locked: locked, ended: ended)
    }

    var meMember: ReadCore.Member? {
        you.map { ReadCore.Member(id: $0.id, role: $0.role, seat: $0.seat, joinedAt: 0, seenAt: serverTime, name: $0.name) }
    }
}
