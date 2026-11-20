import Foundation
import Testing

/// The class page's review queue (PLAYS-DESIGN §12.4 Review, §12.11), the mirror of `reviewQueue` in js/class-ui.js: the
/// seats' chosen takes with no review, in play order then script order.

private func take(_ id: String, line: String, seat: String? = "s1") -> SharedRecord.Take {
    SharedRecord.Take(id: id, lineID: line, part: "role:LUCY", created: nil, frames: 1, sampleRate: 48_000, capture: nil, heard: nil,
                      loudness: nil, peak: nil, userID: nil, seat: seat)
}

private func record(_ id: String, title: String, takes: [SharedRecord.Take], chosen: [String: String],
                    reviews: [String: SharedRecord.Review] = [:]) -> SharedRecord {
    var r = SharedRecord(id: id, scriptID: "s", scriptRevision: "r1", title: title, parts: [:], takes: takes, chosen: chosen)
    r.reviews = reviews
    return r
}

struct ClassReviewTests {
    private let order: (SharedRecord, String) -> Int = { _, line in Int(line.dropFirst()) ?? -1 }

    @Test func aTakeFromTheRoomNeverWaits() {
        let r = record("p", title: "A", takes: [take("t1", line: "l1", seat: nil)], chosen: ["l1": "t1"])
        #expect(ClassReview.queue([r], lineIndex: order).isEmpty)
    }

    @Test func onlyTheChosenTakeWaits() {
        let r = record("p", title: "A", takes: [take("t1", line: "l1"), take("t2", line: "l1")], chosen: ["l1": "t2"])
        #expect(ClassReview.queue([r], lineIndex: order).map(\.id) == ["t2"])
    }

    @Test func aReviewedTakeLeavesTheQueue() {
        let r = record("p", title: "A", takes: [take("t1", line: "l1"), take("t2", line: "l2")], chosen: ["l1": "t1", "l2": "t2"],
                       reviews: ["t1": .init(state: "approved", note: nil)])
        #expect(ClassReview.queue([r], lineIndex: order).map(\.id) == ["t2"])
    }

    @Test func theQueueRunsInPlayThenScriptOrder() {
        let b = record("pb", title: "B Play", takes: [take("tb", line: "l1")], chosen: ["l1": "tb"])
        let a = record("pa", title: "A Play", takes: [take("z9", line: "l9"), take("a1", line: "l2")], chosen: ["l9": "z9", "l2": "a1"])
        #expect(ClassReview.queue([b, a], lineIndex: order).map(\.id) == ["a1", "z9", "tb"])
    }

    @Test func theCountReadsAsWords() {
        #expect(ClassReview.waiting(0) == nil)
        #expect(ClassReview.waiting(1) == "1 take to review")
        #expect(ClassReview.waiting(4) == "4 takes to review")
    }

    @Test func anEmptyNoteIsNoNote() {
        #expect(ClassReview.note("  \n ") == nil)
        #expect(ClassReview.note(" keep the pause ") == "keep the pause")
        #expect(ClassReview.note(String(repeating: "a", count: 600))?.count == 500)
    }

    @Test func theRecordCarriesSeatAndReviewsFromTheWorker() throws {
        let json = #"{"id":"p","scriptID":"s","scriptRevision":"r1","title":"T","parts":{},"takes":[{"id":"t1","lineID":"l1","part":"role:LUCY","frames":1,"sampleRate":48000,"seat":"s1"}],"chosen":{"l1":"t1"},"reviews":{"t1":{"state":"again","note":"slower"}}}"#
        let r = try JSONDecoder().decode(SharedRecord.self, from: Data(json.utf8))
        #expect(r.takes.first?.seat == "s1")
        #expect(r.reviews["t1"] == .init(state: "again", note: "slower"))
        #expect(ClassReview.queue([r], lineIndex: order).isEmpty)
    }
}
