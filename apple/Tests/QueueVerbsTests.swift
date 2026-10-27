import Foundation
import Testing

/// The queue verbs (the web's `enqueue`, `dequeue`, `moveInQueue`): add,
/// remove, reorder, no duplicates, and the rule they must not change.
@MainActor
struct QueueVerbsTests {
    private func makeQueue(_ items: [String] = []) -> ListeningQueue {
        let defaults = UserDefaults(suiteName: "QueueVerbsTests.\(UUID().uuidString)")!
        let queue = ListeningQueue(defaults: defaults)
        if !items.isEmpty { queue.set(items, now: Date(millis: 1000)) }
        return queue
    }

    @Test func addingAppendsAndAnEpisodeQueuedTwiceMovesToTheEnd() {
        let queue = makeQueue(["a", "b"])
        queue.add("c", now: Date(millis: 2000))
        #expect(queue.items == ["a", "b", "c"])
        queue.add("a", now: Date(millis: 3000))
        #expect(queue.items == ["b", "c", "a"])
        #expect(queue.syncState()?.updatedAt == 3000)
    }

    @Test func removingDropsOneAndIgnoresAnEpisodeThatIsNotQueued() {
        let queue = makeQueue(["a", "b", "c"])
        queue.remove("b", now: Date(millis: 2000))
        #expect(queue.items == ["a", "c"])
        queue.remove("zzz", now: Date(millis: 9000))
        #expect(queue.items == ["a", "c"])
        #expect(queue.syncState()?.updatedAt == 2000)
    }

    @Test func movingSwapsOneStepAndStopsAtTheEnds() {
        let queue = makeQueue(["a", "b", "c"])
        queue.move("c", by: -1)
        #expect(queue.items == ["a", "c", "b"])
        queue.move("a", by: -1)
        queue.move("b", by: 1)
        #expect(queue.items == ["a", "c", "b"])
    }

    @Test func aDragKeepsWhatTheListDidNotNameAndDropsDuplicates() {
        let queue = makeQueue(["a", "b", "c", "d"])
        queue.reorder(["c", "a", "a", "nope"])
        #expect(queue.items == ["c", "a", "b", "d"])
    }

    @Test func aChangeTellsThePlayerToRefreshUpNext() {
        let queue = makeQueue(["a"])
        var told = 0
        queue.onChange = { told += 1 }
        queue.add("b")
        queue.remove("a")
        queue.move("b", by: 1)
        #expect(told == 2)
        queue.apply(QueueState(items: ["x"], updatedAt: Date().millis + 60_000))
        #expect(told == 3)
    }

    @Test func theQueueRuleIsUntouchedByTheOrder() {
        let queue = makeQueue(["a", "b", "c"])
        #expect(PlaybackQueue.next(after: "a", queued: queue.items) == "b")
        queue.move("c", by: -1)
        queue.move("c", by: -1)
        #expect(PlaybackQueue.next(after: "x", queued: queue.items) == "c")
        queue.remove("c")
        #expect(PlaybackQueue.next(after: "x", queued: queue.items) == "a")
    }
}
