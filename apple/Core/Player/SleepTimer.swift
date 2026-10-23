import Foundation

/// The bedtime rule (research 05, R20) as a pure state machine, so the player
/// only applies what it returns and the rule is tested without audio:
///
/// - "End of this episode" is the first option, then durations.
/// - The volume fades over the last `fadeSeconds` before it stops.
/// - Once it has fired, nothing starts the next episode.
nonisolated struct SleepTimer: Equatable, Sendable {
    enum Option: Hashable, Sendable, Identifiable {
        case endOfEpisode
        case minutes(Int)

        var id: String {
            switch self {
            case .endOfEpisode: "end"
            case let .minutes(m): "m\(m)"
            }
        }

        var title: String {
            switch self {
            case .endOfEpisode: "End of this episode"
            case let .minutes(m): m == 60 ? "1 hour" : "\(m) minutes"
            }
        }
    }

    enum Mode: Equatable, Sendable {
        case off
        case endOfEpisode
        case until(Date)
        /// It stopped playback; the next episode must not start.
        case fired
    }

    /// End of this episode FIRST (R20), then the durations.
    static let options: [Option] = [.endOfEpisode, .minutes(15), .minutes(30), .minutes(45), .minutes(60)]

    struct Output: Equatable, Sendable {
        /// Multiplies the player's volume: 1 until the fade, then down to 0.
        var volume: Float
        /// True on the one tick that ends playback.
        var shouldPause: Bool
    }

    var fadeSeconds: TimeInterval = PlayerNumbers.sleepFadeSeconds
    private(set) var mode: Mode = .off

    var isActive: Bool { mode != .off && mode != .fired }

    mutating func set(_ option: Option, now: Date) {
        switch option {
        case .endOfEpisode: mode = .endOfEpisode
        case let .minutes(m): mode = .until(now.addingTimeInterval(TimeInterval(m * 60)))
        }
    }

    /// The listener pressed Play or turned the timer off: back to normal.
    mutating func cancel() { mode = .off }

    /// Called on every player tick. `remainingInEpisode` is wall-clock seconds
    /// left in the current episode at the current speed, nil when unknown.
    mutating func tick(now: Date, remainingInEpisode: TimeInterval?) -> Output {
        switch mode {
        case .off:
            return Output(volume: 1, shouldPause: false)
        case .fired:
            return Output(volume: 0, shouldPause: false)
        case .endOfEpisode:
            // The episode's own end stops it (`episodeDidEnd`); here it only fades.
            guard let remaining = remainingInEpisode else { return Output(volume: 1, shouldPause: false) }
            return Output(volume: fade(remaining), shouldPause: false)
        case let .until(deadline):
            let remaining = deadline.timeIntervalSince(now)
            if remaining <= 0 {
                mode = .fired
                return Output(volume: 0, shouldPause: true)
            }
            return Output(volume: fade(remaining), shouldPause: false)
        }
    }

    /// The current episode ended. Returns whether the player may start the
    /// next one: never once the timer has fired or was set for this episode.
    mutating func episodeDidEnd() -> Bool {
        switch mode {
        case .off, .until: return true
        case .endOfEpisode:
            mode = .fired
            return false
        case .fired: return false
        }
    }

    /// What the sleep control shows while active: a countdown or the mode.
    func label(now: Date) -> String? {
        switch mode {
        case .off, .fired: return nil
        case .endOfEpisode: return "End of episode"
        case let .until(deadline):
            return EpisodeRow.clock(max(0, deadline.timeIntervalSince(now)))
        }
    }

    private func fade(_ remaining: TimeInterval) -> Float {
        guard fadeSeconds > 0, remaining < fadeSeconds else { return 1 }
        return Float(max(0, remaining) / fadeSeconds)
    }
}
