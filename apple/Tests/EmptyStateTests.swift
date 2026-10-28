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
}
