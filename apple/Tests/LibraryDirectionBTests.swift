import Foundation
import Testing

/// Library direction B (owner 2026-11-23): Up next merges started then queued for display only; the side is remembered.
struct LibraryDirectionBTests {
    @Test func upNextIsStartedThenQueueEachOnce() {
        #expect(LibraryModel.upNext(started: ["a", "b"], queued: ["c", "a", "d"]) == ["a", "b", "c", "d"])
        #expect(LibraryModel.upNext(started: [], queued: []).isEmpty)
    }

    @Test func draggingTheShownQueueRowsKeepsTheRestInOrder() {
        let queue = ["q1", "q2", "q3", "q4", "q5", "q6", "q7"]
        let moved = LibraryModel.queueAfterMove(queue: queue, shown: ["q2", "q1", "q3"])
        #expect(moved == ["q2", "q1", "q3", "q4", "q5", "q6", "q7"])
    }

    @Test func fiveRowsShowBeforeAll() {
        #expect(LibraryModel.shownRows == 5)
    }
}
