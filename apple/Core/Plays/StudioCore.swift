import Foundation

/// The studio inside the reader, without a view (PLAYS-DESIGN §2.9, iOS-DESIGN §4.15, macOS-DESIGN §4.7; Decision 076
/// S3), the mirror of js/studio-core.js: the line a studio opens at, the take state each of my lines shows, and the
/// production the reader's Record continues. `StudioController` drives the shipped `RecordingSession` and never records
/// or plays itself. Tests: StudioTests in PlaysTests.swift (the web's js/studio.test.js, case for case).
nonisolated enum StudioCore {
    /// What one of my lines shows beside its speaker (§2.9 rule 3).
    struct LineState: Equatable, Sendable {
        enum Kind: Equatable, Sendable { case none, chosen, flagged }
        let state: Kind
        let takes: Int
        /// The chosen take's place among the line's takes, oldest first, from 1; 0 for none.
        let chosen: Int
    }

    /// Where the reader's Record records (§2.9 rule 1).
    enum Pick: Equatable, Sendable {
        /// The part already records in this production: continue it.
        case resume(String)
        /// The part is open here and no other part records: take it.
        case take(String)
        /// Make a new production and take the part.
        case make
    }

    /// The line a studio opens at: the one asked for when it is the part's, else the first with no usable take, else
    /// the part's first line.
    static func startLine(_ production: Production, _ script: PlayScript, part: PartID, ask: String?) -> String? {
        let mine = script.lines(for: part).map(\.id)
        guard !mine.isEmpty else { return nil }
        if let ask, mine.contains(ask) { return ask }
        return mine.first { production.usableTake(for: $0) == nil } ?? mine[0]
    }

    static func lineState(_ production: Production, _ lineID: String) -> LineState {
        let takes = production.takes(for: lineID)
        guard !takes.isEmpty else { return LineState(state: .none, takes: 0, chosen: 0) }
        let chosen = production.chosenTake(for: lineID)
        return LineState(state: chosen?.bleed == true ? .flagged : .chosen, takes: takes.count,
                         chosen: chosen.flatMap { c in takes.firstIndex { $0.id == c.id } }.map { $0 + 1 } ?? 0)
    }

    /// This device's newest unshared production of the play in which the part is recording; else the newest where it
    /// is open and no other part records; else a new one.
    static func productionFor(_ productions: [Production], isShared: (String) -> Bool, script: PlayScript,
                              part: PartID) -> Pick {
        let own = productions.filter { $0.scriptID == script.id && !isShared($0.id) && $0.room == nil }.sorted { $0.created > $1.created }
        if let going = own.first(where: { $0.state(of: part).status == .recording }) { return .resume(going.id) }
        if let open = own.first(where: { $0.state(of: part).status == .open && Relay.current($0, script) == nil }) {
            return .take(open.id)
        }
        return .make
    }

    /// A first take needs no account; a second production does (Decision 079, PLAYS-DESIGN §2.3 rule 3): signed out,
    /// making a new production while another on this device holds a take. A production with no take does not count.
    static func needsAccount(productions: [Production], signedIn: Bool, makingNew: Bool) -> Bool {
        !signedIn && makingNew && productions.contains(where: \.hasTake)
    }

    /// The newest local, unshared production of the play with no take: Record This and Try a Line reuse it (rule 3a).
    static func reusableEmpty(_ productions: [Production], isShared: (String) -> Bool, scriptID: String) -> Production? {
        productions.filter { $0.scriptID == scriptID && !$0.hasTake && !isShared($0.id) && $0.room == nil }.max { $0.created < $1.created }
    }

    /// The productions to delete: local, unshared, with no take (rule 3a).
    static func emptyLocal(_ productions: [Production], isShared: (String) -> Bool) -> [String] {
        productions.filter { !$0.hasTake && !isShared($0.id) }.map(\.id)
    }

    /// Whether Yours and Library list a production: a shared one always, a local one once it holds a take.
    static func isListed(_ production: Production, shared: Bool) -> Bool { shared || production.hasTake }

    /// How a take-state mark reads to VoiceOver: "No take", "3 takes, take 2 chosen", or the re-take.
    static func spoken(_ state: LineState) -> String {
        switch state.state {
        case .none: "No take"
        case .flagged: "Re-take: the microphone heard the device voice"
        case .chosen: state.takes == 1 ? "1 take" : "\(state.takes) takes, take \(state.chosen) chosen"
        }
    }

    /// The status row's takes button: "Take 2 of 3", "No take", "Re-take".
    static func takesLabel(_ state: LineState) -> String {
        switch state.state {
        case .none: "No take"
        case .flagged: "Re-take"
        case .chosen: "Take \(state.chosen) of \(state.takes)"
        }
    }
}

#if os(iOS) || os(macOS)
/// One studio over a started (or starting) `RecordingSession`: which of my lines is current, how each of the three
/// modes moves it, a line's takes (choose, delete an unchosen one, record again) and Delete Unused Takes for the part.
/// `onFollow` has the reader follow the line being heard or recorded.
@Observable
final class StudioController {
    let session: RecordingSession
    let part: PartID
    /// My lines' ids, in script order.
    let mine: [String]
    private(set) var current: String?
    @ObservationIgnored var onFollow: ((String) -> Void)?
    @ObservationIgnored private let store: ProductionStore
    @ObservationIgnored private let order: [String: Int]

    init(session: RecordingSession, store: ProductionStore, line: String? = nil) {
        self.session = session
        self.store = store
        part = session.part
        let script = session.script
        mine = script.lines(for: session.part).map(\.id)
        order = Dictionary(script.lines.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        current = StudioCore.startLine(session.production, script, part: session.part, ask: line)
        session.onPhase = { [weak self] s in self?.phaseChanged(s) }
    }

    var script: PlayScript { session.script }

    /// Busy, a run on screen, or a run's review: the current line holds still and the mode cannot change.
    var locked: Bool { session.isBusy || session.run != nil || session.phase == .runReview }

    /// My first line at or after a script line (the run's next line of mine).
    private func mineFrom(_ lineID: String) -> String? {
        guard let k = order[lineID] else { return nil }
        return mine.first { (order[$0] ?? -1) >= k }
    }

    private func phaseChanged(_ s: RecordingSession) {
        let id: String
        let listening: Bool
        switch s.phase {
        case let .cue(lineID, _): id = lineID; listening = false
        case let .listening(lineID): id = lineID; listening = true
        default: return
        }
        onFollow?(id)
        // During a run, and whenever the microphone is open, the current line is the line being recorded or my next one.
        if s.run != nil || listening {
            let next = listening && mine.contains(id) ? id : mineFrom(id)
            if let next { current = next }
        }
    }

    /// A tap on one of my lines makes it current (refused while busy or in a run).
    @discardableResult
    func select(_ id: String) -> Bool {
        guard mine.contains(id), !locked else { return false }
        current = id
        return true
    }

    /// Next and Previous: my next or previous line from the current one, never wrapping.
    @discardableResult
    func move(_ delta: Int) -> Bool {
        guard !locked, !mine.isEmpty else { return false }
        var i = current.flatMap { mine.firstIndex(of: $0) } ?? -1
        if i < 0 {
            let from = mineFrom(current ?? mine[0])
            i = from.flatMap { mine.firstIndex(of: $0) }.map { $0 - (delta > 0 ? 1 : 0) } ?? mine.count - 1
        }
        let to = mine[max(0, min(mine.count - 1, i + delta))]
        guard to != current else { return false }
        current = to
        return true
    }

    /// The one round control (Space): in Run through, start a run from the current line or pause it; otherwise stop
    /// listening, cancel a cue, or record the current line.
    func primary() async {
        guard session.started, let current else { return }
        if session.mode == .run {
            if session.phase == .runReview { return }
            if session.run != nil { session.pause(); return }
            if case .listening = session.phase { session.stopListening(); return }
            if case .cue = session.phase { session.cancel(); return }
            if !session.isBusy { await session.runThrough(from: current) }
            return
        }
        switch session.phase {
        case .listening: session.stopListening()
        case .cue: session.cancel()
        default: if !session.isBusy { await session.record(current) }
        }
    }

    /// Record again (R): a new take of the line, chosen at once; every older take stays.
    func again(_ lineID: String? = nil) async {
        guard session.started, !session.isBusy, let lineID = lineID ?? current else { return }
        if session.run == nil { current = lineID }
        await session.record(lineID)
    }

    /// Keep (Return): Step's review moves to my next line and waits; a run's review keeps the run.
    func keep() {
        switch session.phase {
        case .review:
            session.dismissReview()
            if let c = current, let i = mine.firstIndex(of: c), i + 1 < mine.count { current = mine[i + 1] }
        case .runReview:
            session.keepRun()
        default: break
        }
    }

    func lineState(_ id: String) -> StudioCore.LineState { StudioCore.lineState(session.production, id) }

    /// A line's takes, oldest first.
    func takes(_ id: String? = nil) -> [Take] {
        guard let id = id ?? current else { return [] }
        return session.production.takes(for: id)
    }

    func choose(_ take: Take) {
        guard !session.isBusy else { return }
        session.choose(take)
    }

    /// Deletes one unchosen take and its file (the person's act); false when refused.
    @discardableResult
    func deleteTake(_ take: Take) -> Bool {
        guard !session.isBusy else { return false }
        let done = (try? store.deleteTake(session.production.id, takeID: take.id)) ?? false
        session.reload()
        return done
    }

    /// This part's unchosen takes.
    var unused: [Take] {
        let lines = Set(mine)
        return session.production.unusedTakes.filter { lines.contains($0.lineID) }
    }

    /// Delete Unused Takes for the part; returns how many went.
    @discardableResult
    func deleteUnused() -> Int {
        guard !locked else { return 0 }
        let n = (try? store.discardUnusedTakes(session.production.id, lines: Set(mine))) ?? 0
        session.reload()
        return n
    }

    /// How many of my lines have a usable take.
    var kept: Int { mine.count - Relay.missingLines(part, in: session.production, script: script).count }

    /// "Line 3 of 44": the current line's place among my lines.
    var place: (at: Int, of: Int) {
        ((current.flatMap { mine.firstIndex(of: $0) } ?? 0) + 1, mine.count)
    }
}
#endif
