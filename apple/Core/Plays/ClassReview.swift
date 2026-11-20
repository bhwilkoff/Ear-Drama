import Foundation

// The teacher's review queue on the class page (PLAYS-DESIGN §12.4 Review, §12.11): the seats' chosen takes that no review
// has answered yet, in play order then script order. The rule is `js/class-ui.js` reviewQueue; counts and links, never a ranking.

nonisolated struct ClassReviewItem: Identifiable, Equatable, Sendable {
    let pid: String
    let playTitle: String
    let take: SharedRecord.Take
    var id: String { take.id }
}

nonisolated enum ClassReview {
    /// Takes made by a seat, chosen for their line, with no review. `lineIndex` is the line's place in its script (unknown sorts first).
    static func queue(_ productions: [SharedRecord], lineIndex: (SharedRecord, String) -> Int) -> [ClassReviewItem] {
        var items: [(item: ClassReviewItem, order: Int)] = []
        for rec in productions {
            for take in rec.takes where take.seat != nil && rec.chosen[take.lineID] == take.id && rec.reviews[take.id] == nil {
                items.append((ClassReviewItem(pid: rec.id, playTitle: rec.title, take: take), lineIndex(rec, take.lineID)))
            }
        }
        return items.sorted { a, b in
            a.item.playTitle != b.item.playTitle ? a.item.playTitle < b.item.playTitle : a.order < b.order
        }.map(\.item)
    }

    /// "1 take to review", "3 takes to review"; nil when nothing waits.
    static func waiting(_ count: Int) -> String? {
        count == 0 ? nil : count == 1 ? "1 take to review" : "\(count) takes to review"
    }

    /// What goes to the Worker: an empty note is no note.
    static func note(_ typed: String) -> String? {
        let t = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : String(t.prefix(500))
    }
}
