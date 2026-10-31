import Foundation
import Testing

/// The empty Library door (iOS-DESIGN §7.4): DEBUG builds read it, and only
/// "1" opens it. Broken control, 2026-10-28: `from` ignoring the variable makes
/// the first expectation fail.
struct EmptyStateTests {
    @Test func emptyLibraryDoorOpensOnlyOnOne() {
        #expect(LaunchDoors.from(environment: ["APP_EMPTY_LIBRARY": "1"], arguments: []).emptyLibrary)
        #expect(!LaunchDoors.from(environment: ["APP_EMPTY_LIBRARY": "0"], arguments: []).emptyLibrary)
        #expect(!LaunchDoors.from(environment: [:], arguments: []).emptyLibrary)
    }

    /// The reset door erases the listening lists and nothing else, and only when asked.
    @Test func resetUserStateDoorErasesTheListsOnlyWhenAsked() throws {
        let defaults = try #require(UserDefaults(suiteName: "reset-door-test"))
        defer { defaults.removePersistentDomain(forName: "reset-door-test") }
        defaults.set("x", forKey: "listeningQueue.v1")
        defaults.set("x", forKey: "listeningHistory.v1")
        defaults.set("x", forKey: "followedSeries.v1")
        defaults.set("keep", forKey: "catalog.etag")
        let off = LaunchDoors.from(environment: [:], arguments: [])
        #expect(!LaunchDoors.resetUserStateIfAsked(off, defaults: defaults))
        #expect(defaults.string(forKey: "listeningQueue.v1") == "x")
        let on = LaunchDoors.from(environment: ["APP_RESET_USER_STATE": "1"], arguments: [])
        #expect(LaunchDoors.resetUserStateIfAsked(on, defaults: defaults))
        #expect(defaults.string(forKey: "listeningQueue.v1") == nil)
        #expect(defaults.string(forKey: "listeningHistory.v1") == nil)
        #expect(defaults.string(forKey: "followedSeries.v1") == nil)
        #expect(defaults.string(forKey: "catalog.etag") == "keep")
    }
}
