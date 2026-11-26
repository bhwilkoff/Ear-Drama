#if os(iOS) || os(macOS)
import Foundation

/// When the Better Voices step is offered (PLAYS-DESIGN §2.8 rule 13, Decision 090): once at first launch, once more at
/// the first read, cast or record if it was skipped, never after that and never once a download has begun. The record
/// is one number on this device (`ed.voicesStep`), never synced: 0 never offered, 1 offered at launch, 2 done.
/// `eligible` is the caller's: the download is offered here now (Kokoro can run, is not here, is not downloading).
struct VoicesOffer {
    static let key = "ed.voicesStep"

    let defaults: UserDefaults
    /// APP_SKIP_ONBOARD=1, or any other launch door (a harness launch): never offered, nothing written.
    var skip = false
    /// APP_VOICES_STEP=1: offered at launch without reading or writing the record.
    var forced = false

    var stage: Int { defaults.integer(forKey: Self.key) }

    static var current: VoicesOffer {
        let doors = LaunchDoors.current
        var others = doors
        others.voicesStep = false
        return VoicesOffer(defaults: .standard, skip: doors.skipOnboard || !others.isEmpty, forced: doors.voicesStep)
    }

    /// Whether to show the step at launch; marks it offered.
    func atLaunch(eligible: Bool) -> Bool {
        if forced { return eligible }
        guard !skip, eligible, stage == 0 else { return false }
        defaults.set(1, forKey: Self.key)
        return true
    }

    /// Whether to show the step as a script is opened to read, cast or record; after this it is never offered again.
    func atFirstUse(eligible: Bool) -> Bool {
        guard !forced, !skip, eligible, stage < 2 else { return false }
        defaults.set(2, forKey: Self.key)
        return true
    }

    /// A download began (from the step or from Library): never offered again.
    func downloadBegan() {
        guard !forced, !skip else { return }
        defaults.set(2, forKey: Self.key)
    }

    /// Whether the download is offered on this device now.
    @MainActor static func eligible(_ store: KokoroModelStore = .shared) -> Bool {
        guard KokoroDownloadState.offersBetterVoices(ready: store.ready, flag: KokoroFlag.enabled) else { return false }
        if case .downloading = store.state { return false }
        return true
    }
}

/// Free space against the download (rule 13: under the size plus 20%, Download is refused and the warning says so).
nonisolated enum VoicesSpace {
    static func short(free: Int64?, size: Int64) -> Bool {
        guard let free else { return false }
        return Double(free) < Double(size) * 1.2
    }

    static func warning(free: Int64) -> String { "Not enough space: \(Kokoro.megabytes(free)) free." }

    /// The bytes free for important use on the volume that holds Application Support, or nil when unknown.
    static func free(at url: URL = .applicationSupportDirectory) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}
#endif
