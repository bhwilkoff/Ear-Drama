import Foundation
import Observation

/// Where the listener stopped in each episode: the person's own data, kept on
/// the device in UserDefaults (writable on tvOS, unlike Application Support).
/// `continueListening` (contract §5) reads it.
@Observable
final class ListeningHistory {
    nonisolated struct Entry: Codable, Hashable, Sendable {
        var position: Double
        var duration: Double?
        var updatedAt: Date
        var finished: Bool
    }

    private static let key = "listeningHistory.v1"
    private static let removalsKey = "listeningHistory.removals.v1"
    private static let pendingKey = "listeningHistory.pending.v1"
    /// Enough for a long habit; the oldest entries fall off.
    static let capacity = 500
    /// Under this many seconds in, an episode is not "in progress".
    static let startedThreshold: Double = 30
    /// Within this many seconds of the end, it counts as finished.
    static let finishedSlack: Double = 45

    private(set) var entries: [String: Entry]
    /// Removal markers: when each removed episode left the history, so a sync
    /// can tell another device (a row is never removed by leaving it out).
    @ObservationIgnored private(set) var removals: [String: Date]
    /// Episodes changed here since the last upload that took them.
    @ObservationIgnored private(set) var pending: Set<String>
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
        removals = defaults.data(forKey: Self.removalsKey)
            .flatMap { try? JSONDecoder().decode([String: Date].self, from: $0) } ?? [:]
        pending = Set(defaults.stringArray(forKey: Self.pendingKey) ?? [])
    }

    func entry(for id: String) -> Entry? { entries[id] }

    /// The saved position, exactly (Decision 062: only an interruption
    /// rewinds); nil when there is nothing to resume.
    func resumePosition(for id: String) -> Double? {
        guard let e = entries[id], !e.finished, e.position >= Self.startedThreshold else { return nil }
        return e.position
    }

    func record(_ id: String, position: Double, duration: Double?, now: Date = Date()) {
        var finished = false
        if let duration, duration > 0, position >= duration - Self.finishedSlack { finished = true }
        entries[id] = Entry(position: position, duration: duration, updatedAt: now, finished: finished)
        changed(id)
        trimAndSave()
    }

    func markFinished(_ id: String, duration: Double?, now: Date = Date()) {
        entries[id] = Entry(position: duration ?? 0, duration: duration, updatedAt: now, finished: true)
        changed(id)
        trimAndSave()
    }

    func remove(_ id: String, now: Date = Date()) {
        entries[id] = nil
        removals[id] = now
        pending.insert(id)
        trimAndSave()
    }

    /// When this device last changed the episode: its entry's stamp, or its
    /// removal marker's.
    func stamp(for id: String) -> Date? { entries[id]?.updatedAt ?? removals[id] }

    /// Applies another device's row when it is newer than this device's
    /// (last write wins). `entry` nil is a removal. Returns whether it applied.
    @discardableResult
    func applyRemote(_ id: String, entry: Entry?, at stamp: Date) -> Bool {
        if let local = self.stamp(for: id), local >= stamp { return false }
        if let entry {
            entries[id] = entry
            removals[id] = nil
        } else {
            entries[id] = nil
            removals[id] = stamp
        }
        pending.remove(id)
        return true
    }

    /// The upload took the episode as it stood at `stamp`; a change since
    /// stays pending.
    func markSynced(_ id: String, at stamp: Date) {
        guard let current = self.stamp(for: id), (current.timeIntervalSince1970 * 1000).rounded(.down) <= (stamp.timeIntervalSince1970 * 1000).rounded(.down) else { return }
        pending.remove(id)
    }

    func saveSyncState() { trimAndSave() }

    private func changed(_ id: String) {
        removals[id] = nil
        pending.insert(id)
    }

    /// In-progress episode ids, most recent first.
    var inProgressIDs: [String] {
        entries.filter { !$0.value.finished && $0.value.position >= Self.startedThreshold }
            .sorted { $0.value.updatedAt > $1.value.updatedAt }
            .map(\.key)
    }

    /// Fraction listened, for an episode row's progress mark.
    func progress(for id: String) -> Double? {
        guard let e = entries[id] else { return nil }
        if e.finished { return 1 }
        guard let d = e.duration, d > 0 else { return nil }
        return min(1, e.position / d)
    }

    private func trimAndSave() {
        if entries.count > Self.capacity {
            let keep = entries.sorted { $0.value.updatedAt > $1.value.updatedAt }.prefix(Self.capacity)
            entries = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        if removals.count > Self.capacity {
            let keep = removals.sorted { $0.value > $1.value }.prefix(Self.capacity)
            removals = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        pending = pending.filter { entries[$0] != nil || removals[$0] != nil }
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: Self.key) }
        if let data = try? JSONEncoder().encode(removals) { defaults.set(data, forKey: Self.removalsKey) }
        defaults.set(Array(pending), forKey: Self.pendingKey)
    }
}
