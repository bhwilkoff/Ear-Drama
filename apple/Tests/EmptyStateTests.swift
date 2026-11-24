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

    @Test func alongDoorNamesTheProductionAndIgnoresEmpty() {
        #expect(LaunchDoors.from(environment: ["APP_START_ALONG": "p1"], arguments: []).along == "p1")
        #expect(LaunchDoors.from(environment: ["APP_START_ALONG": ""], arguments: []).along == nil)
        #expect(LaunchDoors.from(environment: [:], arguments: []).along == nil)
    }

    /// T7b: the read room's claim and Record doors read their variables; "1" arms Record, anything else does not.
    @Test func readRoomPartAndRecordDoors() {
        let doors = LaunchDoors.from(environment: ["APP_START_READ_PART": "POLLY", "APP_START_READ_RECORD": "1"], arguments: [])
        #expect(doors.readPart == "POLLY")
        #expect(doors.readRecord)
        #expect(LaunchDoors.from(environment: ["APP_START_READ_PART": "", "APP_START_READ_RECORD": "0"], arguments: []).readPart == nil)
        #expect(!LaunchDoors.from(environment: ["APP_START_READ_RECORD": "0"], arguments: []).readRecord)
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

    /// 2026-11-23 the tap tier erased the owner's lists on two phones: the door sets them aside, a second
    /// test launch never overwrites the copy, and the next ordinary launch puts them back without test leftovers.
    @Test func resetUserStateDoorPutsThePersonsListsBack() throws {
        let defaults = try #require(UserDefaults(suiteName: "reset-door-restore-test"))
        defer { defaults.removePersistentDomain(forName: "reset-door-restore-test") }
        defaults.set("mine", forKey: "listeningQueue.v1")
        defaults.set("mine", forKey: "followedSeries.v1")
        let on = LaunchDoors.from(environment: ["APP_RESET_USER_STATE": "1"], arguments: [])
        let off = LaunchDoors.from(environment: [:], arguments: [])
        #expect(LaunchDoors.resetUserStateIfAsked(on, defaults: defaults))
        #expect(!LaunchDoors.restoreUserStateIfSetAside(on, defaults: defaults))
        defaults.set("test", forKey: "listeningQueue.v1")
        defaults.set("test", forKey: "listeningHistory.v1")
        #expect(LaunchDoors.resetUserStateIfAsked(on, defaults: defaults))
        defaults.set("test", forKey: "listeningHistory.v1")
        // A test's own relaunch keeps the test's lists (a follow must survive it).
        let relaunch = LaunchDoors.from(environment: ["APP_UITEST_SESSION": "1"], arguments: [])
        #expect(!LaunchDoors.restoreUserStateIfSetAside(relaunch, defaults: defaults))
        #expect(defaults.string(forKey: "listeningHistory.v1") == "test")
        #expect(LaunchDoors.restoreUserStateIfSetAside(off, defaults: defaults))
        #expect(defaults.string(forKey: "listeningQueue.v1") == "mine")
        #expect(defaults.string(forKey: "followedSeries.v1") == "mine")
        #expect(defaults.string(forKey: "listeningHistory.v1") == nil)
        #expect(!LaunchDoors.restoreUserStateIfSetAside(off, defaults: defaults))
        #expect(defaults.dictionaryRepresentation().keys.allSatisfy { !$0.hasPrefix(LaunchDoors.setAsidePrefix) })
    }
}
