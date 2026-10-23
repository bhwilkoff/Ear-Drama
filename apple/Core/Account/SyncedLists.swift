import Foundation
import Observation

// The three things that sync (Decision 057): listening history, followed
// series, and the queue. Each is the device's own data in UserDefaults, kept
// whether or not anyone signs in; these extensions turn it into the Worker's
// rows and apply the Worker's rows back, last write wins per row.

extension ListeningHistory {
    /// The pending rows, or everything kept (`all`, the anonymous merge).
    func syncRows(all: Bool = false) -> [HistoryRow] {
        let ids = all ? Set(entries.keys).union(removals.keys) : pending
        return ids.sorted().compactMap { id in
            if let e = entries[id] {
                return HistoryRow(episodeId: id, position: e.position, duration: e.duration,
                                  finished: e.finished, deleted: false, updatedAt: e.updatedAt.millis)
            }
            if let at = removals[id] {
                return HistoryRow(episodeId: id, position: 0, duration: nil, finished: false, deleted: true,
                                  updatedAt: at.millis)
            }
            return nil
        }
    }

    func apply(_ rows: [HistoryRow]) {
        for row in rows {
            let at = Date(millis: row.updatedAt)
            let entry = row.deleted ? nil
                : Entry(position: row.position, duration: row.duration, updatedAt: at, finished: row.finished)
            applyRemote(row.episodeId, entry: entry, at: at)
        }
        saveSyncState()
    }

    func markSynced(_ rows: [HistoryRow]) {
        for row in rows { markSynced(row.episodeId, at: Date(millis: row.updatedAt)) }
        saveSyncState()
    }
}

/// Followed series, with an unfollow kept as a marker so it reaches the other
/// devices. Apple has no Follow control yet (iOS-DESIGN §12); a follow made on
/// the web or Android lands here and is kept.
@Observable
final class FollowedSeries {
    nonisolated struct State: Codable, Hashable, Sendable {
        var following: Bool
        var updatedAt: Date
    }

    private static let key = "followedSeries.v1"
    private static let pendingKey = "followedSeries.pending.v1"

    private(set) var states: [String: State]
    @ObservationIgnored private(set) var pending: Set<String>
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        states = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([String: State].self, from: $0) } ?? [:]
        pending = Set(defaults.stringArray(forKey: Self.pendingKey) ?? [])
    }

    var followedKeys: [String] { states.filter(\.value.following).map(\.key).sorted() }

    func isFollowing(_ key: String) -> Bool { states[key]?.following ?? false }

    func setFollowing(_ key: String, _ following: Bool, now: Date = Date()) {
        states[key] = State(following: following, updatedAt: now)
        pending.insert(key)
        save()
    }

    func syncRows(all: Bool = false) -> [FollowRow] {
        (all ? Set(states.keys) : pending).sorted().compactMap { key in
            states[key].map { FollowRow(seriesId: key, following: $0.following, updatedAt: $0.updatedAt.millis) }
        }
    }

    func apply(_ rows: [FollowRow]) {
        for row in rows {
            let at = Date(millis: row.updatedAt)
            if let local = states[row.seriesId], local.updatedAt >= at { continue }
            states[row.seriesId] = State(following: row.following, updatedAt: at)
            pending.remove(row.seriesId)
        }
        save()
    }

    func markSynced(_ rows: [FollowRow]) {
        for row in rows where (states[row.seriesId]?.updatedAt.millis ?? .max) <= row.updatedAt {
            pending.remove(row.seriesId)
        }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(states) { defaults.set(data, forKey: Self.key) }
        defaults.set(Array(pending), forKey: Self.pendingKey)
    }
}

/// The person's own queue, one ordered list that wins or loses whole by its
/// stamp (docs/WORKER.md). Apple has no queue verbs yet (iOS-DESIGN §12: the
/// queue rule waits on the owner); a queue built elsewhere is kept here.
@Observable
final class ListeningQueue {
    private static let key = "listeningQueue.v1"

    private struct Stored: Codable {
        var items: [String]
        var updatedAt: Date?
        var dirty: Bool
    }

    private(set) var items: [String]
    @ObservationIgnored private(set) var updatedAt: Date?
    @ObservationIgnored private(set) var dirty: Bool
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
        items = stored?.items ?? []
        updatedAt = stored?.updatedAt
        dirty = stored?.dirty ?? false
    }

    func set(_ items: [String], now: Date = Date()) {
        self.items = items
        updatedAt = now
        dirty = true
        save()
    }

    /// The queue to upload: only a change made here (or, for the merge, a
    /// non-empty queue), so a device never empties another's.
    func syncState(all: Bool = false) -> QueueState? {
        guard let updatedAt, all ? !items.isEmpty : dirty else { return nil }
        return QueueState(items: items, updatedAt: updatedAt.millis)
    }

    /// `afterMerge`: the account's queue now holds this device's items after
    /// its own, at a stamp that may equal this device's, so it is taken whole.
    func apply(_ remote: QueueState?, afterMerge: Bool = false) {
        guard let remote else { return }
        let at = Date(millis: remote.updatedAt)
        if !afterMerge, let updatedAt, updatedAt >= at { return }
        items = remote.items
        updatedAt = at
        dirty = false
        save()
    }

    func markSynced(_ sent: QueueState) {
        if let updatedAt, updatedAt.millis <= sent.updatedAt { dirty = false }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(Stored(items: items, updatedAt: updatedAt, dirty: dirty)) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
