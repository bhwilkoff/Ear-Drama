import Foundation

/// One step of a run through (owner ruling 4, D3-6): the performer's own line, another
/// part's usable human take, or the words a device voice reads live. A voice step is
/// words only, never audio, so nothing of it can be stored (§5).
nonisolated enum RunStep: Equatable, Sendable {
    case mine(lineID: String, part: PartID)
    case take(lineID: String, part: PartID, take: Take)
    case voice(lineID: String, part: PartID, text: String)

    var lineID: String {
        switch self {
        case let .mine(id, _), let .take(id, _, _), let .voice(id, _, _): id
        }
    }

    var isMine: Bool { if case .mine = self { true } else { false } }
}

extension Relay {
    /// From the chosen line's cue (the previous speech when another part speaks it) to the part's
    /// last line, nothing after it. Unrecorded directions and sound are skipped, as in the listen
    /// plan. An unknown line plans nothing.
    nonisolated static func runPlan(_ production: Production, _ script: PlayScript, part: PartID,
                                    from lineID: String) -> [RunStep] {
        guard let at = script.lines.firstIndex(where: { $0.id == lineID }) else { return [] }
        let start = cueLines(before: lineID, in: script, runUp: false).first
            .flatMap { cue in script.lines.firstIndex { $0.id == cue.id } } ?? at
        var plan: [RunStep] = []
        for line in script.lines[start...] {
            if line.part == part {
                plan.append(.mine(lineID: line.id, part: line.part))
            } else if let take = production.usableTake(for: line.id) {
                plan.append(.take(lineID: line.id, part: line.part, take: take))
            } else if line.kind == .speech {
                plan.append(.voice(lineID: line.id, part: line.part, text: line.spokenText))
            }
        }
        guard let last = plan.lastIndex(where: \.isMine) else { return [] }
        return Array(plan[...last])
    }
}
