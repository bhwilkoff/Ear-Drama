import Foundation

/// One step of a listen-through (PLAYS-DESIGN §2.6): a human take, or the
/// words a device voice reads live. A voice entry carries text only, never
/// audio, so nothing of it can be stored, mixed, or exported (§5).
nonisolated enum ListenEntry: Equatable, Sendable {
    case take(lineID: String, part: PartID, take: Take)
    case voice(lineID: String, part: PartID, text: String)

    var lineID: String {
        switch self {
        case let .take(id, _, _), let .voice(id, _, _): id
        }
    }

    var isDeviceVoice: Bool { if case .voice = self { true } else { false } }
}

extension Relay {
    /// Every script line in order: its usable take, or for a speech line
    /// without one the words to read live. A direction or sound line without a
    /// take is skipped, unless `reads` says its part has been given a voice (§2.8 rule 7).
    nonisolated static func listenPlan(_ production: Production, _ script: PlayScript,
                                       reads: ((PartID) -> Bool)? = nil) -> [ListenEntry] {
        script.scoped(for: production).lines.compactMap { line in
            if let take = production.usableTake(for: line.id) {
                return .take(lineID: line.id, part: line.part, take: take)
            }
            guard line.kind == .speech || (reads?(line.part) ?? false) else { return nil }
            return .voice(lineID: line.id, part: line.part, text: line.spokenText)
        }
    }
}
