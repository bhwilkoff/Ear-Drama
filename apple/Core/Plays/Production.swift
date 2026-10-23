import Foundation

/// One take: the performer's line window only, never the stand-in around it
/// (PLAYS-DESIGN §4.2). Immutable once written; choosing another take never
/// deletes it (§8 rule 5).
nonisolated struct Take: Codable, Identifiable, Equatable, Sendable {
    enum Capture: String, Codable, Sendable {
        /// Headphones on, the microphone unprocessed.
        case direct
        /// No headphones: voice processing cancelled the device's own playback.
        case aec
    }

    let id: String
    let lineID: String
    let part: PartID
    /// The file name inside `takes/`.
    let file: String
    let created: Date
    let frames: Int
    let sampleRate: Double
    let capture: Capture
    /// What the performer heard before this line: a take id per cue line, or
    /// `Take.standIn` where the device voice read it live.
    let heard: [String: String]
    /// Integrated loudness (ITU-R BS.1770), stored, never written into the take.
    let loudness: Double?
    let peak: Float
    /// The bleed check found the device voice in the microphone (§5 rule 2).
    let bleed: Bool

    static let standIn = "standin"

    var seconds: Double { Double(frames) / sampleRate }
}

/// Where a part stands in the relay.
nonisolated struct PartState: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable { case open, recording, done, silent }
    var status: Status = .open
    /// The name the performer typed, or nil. It never leaves the device.
    var performer: String?
}

/// The production record (`Plays/<id>/production.json`, §6): who took which
/// part, every take and what it heard, the chosen take per line, and the state
/// the mix was rendered from.
nonisolated struct Production: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let scriptID: String
    let scriptRevision: String
    let title: String
    let created: Date
    var parts: [PartID: PartState] = [:]
    var takes: [Take] = []
    /// line id -> take id
    var chosen: [String: String] = [:]
    var roomTone: [String] = []
    var listenedThrough = false
    /// The chosen takes `mix.m4a` was rendered from; a different set means the
    /// mix is stale and is rebuilt.
    var mixedFrom: String?

    init(id: String = UUID().uuidString, script: PlayScript, created: Date = .now) {
        self.id = id
        scriptID = script.id
        scriptRevision = script.revision
        title = script.title
        self.created = created
        for part in script.castParts { parts[part.id] = PartState() }
    }

    func state(of part: PartID) -> PartState { parts[part] ?? PartState() }

    func take(_ id: String) -> Take? { takes.first { $0.id == id } }

    func chosenTake(for lineID: String) -> Take? { chosen[lineID].flatMap(take) }

    /// The chosen take when it counts toward the play: a take the bleed check
    /// flagged holds the device voice, so it is kept on disk but never counts
    /// or reaches the mix (§5 rule 2, §8 rule 3).
    func usableTake(for lineID: String) -> Take? { chosenTake(for: lineID).flatMap { $0.bleed ? nil : $0 } }

    func takes(for lineID: String) -> [Take] { takes.filter { $0.lineID == lineID } }

    /// A new take becomes the line's chosen one; the older takes stay.
    mutating func add(_ take: Take) {
        takes.append(take)
        chosen[take.lineID] = take.id
        listenedThrough = false
    }

    mutating func choose(_ takeID: String) {
        guard let take = take(takeID) else { return }
        if chosen[take.lineID] != takeID { listenedThrough = false }
        chosen[take.lineID] = takeID
    }

    var unusedTakes: [Take] {
        let keep = Set(chosen.values)
        return takes.filter { !keep.contains($0.id) }
    }

    /// Removes every take that is not a line's chosen one and returns them, so
    /// the store deletes their files (§6, "discard unused takes").
    mutating func discardUnused() -> [Take] {
        let gone = unusedTakes
        let ids = Set(gone.map(\.id))
        takes.removeAll { ids.contains($0.id) }
        return gone
    }

    var chosenFingerprint: String {
        chosen.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    }

    var isFinished: Bool { listenedThrough && mixedFrom == chosenFingerprint }
}
