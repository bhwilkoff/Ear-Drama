import Foundation

/// The read-along's follow logic (PLAYS-DESIGN §2.11), shared by the phone, tablet, Mac and TV. The line heard
/// comes from the listen plan; a rendered mix finds its line by its timeline.
nonisolated enum ReadAlong {
    /// The line the plan's entry `index` speaks; nil past either end.
    static func line(_ plan: [ListenEntry], at index: Int) -> String? {
        plan.indices.contains(index) ? plan[index].lineID : nil
    }

    struct Span: Equatable, Sendable {
        let lineID: String
        let start: Int
        let frames: Int
    }

    /// The line a mix is speaking at `seconds`: the last span begun, nil once the last has ended; a gap keeps the
    /// line before it.
    static func line(_ spans: [Span], rate: Double, seconds: Double) -> String? {
        let frame = seconds * rate
        guard let at = spans.last(where: { Double($0.start) <= frame }) else { return nil }
        if at == spans.last, frame >= Double(at.start + at.frames) { return nil }
        return at.lineID
    }

    /// Whether the reader turns itself to the line heard. A touch (`away`) stops it and offers Back to the Line
    /// while something plays; `back` returns the line now heard and follows again.
    struct Follow: Equatable, Sendable {
        struct Step: Equatable, Sendable {
            var turn: Bool
            var back: Bool
        }

        private(set) var following = true
        private(set) var now: String?

        mutating func line(_ id: String?) -> Step {
            now = id
            return Step(turn: following && id != nil, back: !following && id != nil)
        }

        mutating func away() { following = false }

        mutating func back() -> String? {
            following = true
            return now
        }
    }

    /// The TV panel's three lines: before, the one heard, after (nil at an end).
    static func panel(_ lines: [ScriptLine], around id: String) -> (before: ScriptLine?, current: ScriptLine?, after: ScriptLine?) {
        guard let i = lines.firstIndex(where: { $0.id == id }) else { return (nil, nil, nil) }
        return (i > 0 ? lines[i - 1] : nil, lines[i], i + 1 < lines.count ? lines[i + 1] : nil)
    }
}
