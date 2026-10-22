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
    /// Enough for a long habit; the oldest entries fall off.
    static let capacity = 500
    /// Under this many seconds in, an episode is not "in progress".
    static let startedThreshold: Double = 30
    /// Within this many seconds of the end, it counts as finished.
    static let finishedSlack: Double = 45

    private(set) var entries: [String: Entry]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
    }

    func entry(for id: String) -> Entry? { entries[id] }

    /// The position to resume from, with a small rewind so the last line of
    /// dialogue is heard again; nil when there is nothing to resume.
    func resumePosition(for id: String, rewind: Double = 3) -> Double? {
        guard let e = entries[id], !e.finished, e.position >= Self.startedThreshold else { return nil }
        return max(0, e.position - rewind)
    }

    func record(_ id: String, position: Double, duration: Double?, now: Date = Date()) {
        var finished = false
        if let duration, duration > 0, position >= duration - Self.finishedSlack { finished = true }
        entries[id] = Entry(position: position, duration: duration, updatedAt: now, finished: finished)
        trimAndSave()
    }

    func markFinished(_ id: String, duration: Double?, now: Date = Date()) {
        entries[id] = Entry(position: duration ?? 0, duration: duration, updatedAt: now, finished: true)
        trimAndSave()
    }

    func remove(_ id: String) {
        entries[id] = nil
        trimAndSave()
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
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: Self.key) }
    }
}
