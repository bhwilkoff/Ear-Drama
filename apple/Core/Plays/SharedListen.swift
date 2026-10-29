import Foundation

/// The Apple TV's listen-through of a shared production (PLAYS-DESIGN §11.7
/// rule 12): the Worker's chosen takes, fetched into Caches, played as phase
/// 1's listen plan with the device voice reading the rest live. Pure: no
/// file or network here, so `SharedListenTests` runs it on the Mac.
nonisolated enum SharedListen {
    /// The chosen takes the Worker shows this person that the cache lacks, in line order.
    static func toFetch(_ rec: SharedRecord, have: Set<String>) -> [String] {
        rec.chosen.sorted { $0.key < $1.key }.map(\.value)
            .filter { id in !have.contains(id) && rec.takes.contains { $0.id == id } }
    }

    /// The file a fetched take is kept in: WAV or FLAC, read from its own header.
    static func fileName(_ takeID: String, _ data: Data) -> String {
        "m-\(takeID).\(data.prefix(4) == Data("RIFF".utf8) ? "wav" : "flac")"
    }

    /// A production held in memory only: each chosen take the Worker shows and
    /// the cache holds (`files`, take id to file name). A line whose take is
    /// hidden, missing, or not yet fetched has none, so the plan reads it live.
    static func production(_ rec: SharedRecord, script: PlayScript, files: [String: String]) -> Production {
        var p = Production(id: "shared-\(rec.id)", script: script)
        for (lineID, takeID) in rec.chosen.sorted(by: { $0.key < $1.key }) {
            guard let t = rec.takes.first(where: { $0.id == takeID }), t.lineID == lineID,
                  let file = files[takeID] else { continue }
            p.takes.append(Take(id: t.id, lineID: t.lineID, part: PartID(rawValue: t.part), file: file,
                                created: Date(timeIntervalSinceReferenceDate: t.created ?? 0), frames: t.frames,
                                sampleRate: t.sampleRate, capture: Take.Capture(rawValue: t.capture ?? "") ?? .direct,
                                heard: t.heard ?? [:], loudness: t.loudness, peak: Float(t.peak ?? 0), bleed: false))
            p.chosen[lineID] = takeID
        }
        return p
    }

    /// The plan the TV plays: human takes, and the device voice for every
    /// speaking line without one (§5: words only, never audio).
    static func plan(_ rec: SharedRecord, script: PlayScript, files: [String: String]) -> [ListenEntry] {
        Relay.listenPlan(production(rec, script: script, files: files), script)
    }

    /// One part's line on the TV: its state and the performer's chosen name.
    static func status(_ rec: SharedRecord, _ part: CastPart) -> String {
        let s = rec.part(part.id)
        let name = s.performer.map { " · \($0)" } ?? ""
        return switch s.status {
        case .recording: "Recording\(name)"
        case .done: "Recorded\(name)"
        case .silent: "Left silent"
        case .open: part.lineCount == 1 ? "1 line" : "\(part.lineCount) lines"
        }
    }
}
