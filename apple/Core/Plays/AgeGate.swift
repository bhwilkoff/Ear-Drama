import Foundation

/// The neutral age question (PLAYS-DESIGN §12.12 item 8): only "under 13 or not" is kept, on this device, never sent.
nonisolated enum AgeGate {
    static let key = "ed.over13"
    static let oldest = 120

    /// A year alone cannot tell a 12-year-old from a 13-year-old born the same year, so that year counts as under 13.
    static func isUnder13(birthYear: Int, year: Int) -> Bool { year - birthYear <= 13 }

    /// This year back 120 years, newest first.
    static func years(now: Int) -> [Int] { (0..<oldest).map { now - $0 } }

    /// The kept answer: true over 13, false under, nil when never asked.
    static func stored(_ defaults: UserDefaults = .standard) -> Bool? {
        defaults.object(forKey: key) as? Bool
    }

    static func keep(over13: Bool, _ defaults: UserDefaults = .standard) { defaults.set(over13, forKey: key) }
}
