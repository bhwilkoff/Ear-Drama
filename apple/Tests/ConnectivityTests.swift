import Foundation
import Testing

/// The offline line and the player's refusal (iOS-DESIGN §7.2). Broken
/// controls, 2026-10-27, each seen to fail before the fix was kept:
///   Connectivity.line returning the line while online: the line test fails.
///   isOnline ignoring forcedOffline: the door test fails.
struct ConnectivityTests {
    @Test func offlineLineComesAndGoesWithTheNetwork() {
        #expect(Connectivity.line(online: false) == "You are offline.")
        #expect(Connectivity.line(online: true) == nil)
    }

    @Test func forceOfflineDoorHoldsTheOfflineState() {
        #expect(Connectivity.isOnline(pathSatisfied: true, forcedOffline: false))
        #expect(!Connectivity.isOnline(pathSatisfied: true, forcedOffline: true))
        #expect(!Connectivity.isOnline(pathSatisfied: false, forcedOffline: false))
        #expect(LaunchDoors.from(environment: ["APP_FORCE_OFFLINE": "1"], arguments: []).forceOffline)
        #expect(!LaunchDoors.from(environment: [:], arguments: []).forceOffline)
    }

    @Test func anUndownloadedEpisodeOfflineIsRefusedInWords() {
        #expect(Connectivity.playerProblem(URLError(.notConnectedToInternet)) == "You are offline.")
        let wrapped = NSError(domain: "AVFoundationErrorDomain", code: -11800,
                              userInfo: [NSUnderlyingErrorKey: URLError(.networkConnectionLost) as NSError])
        #expect(Connectivity.playerProblem(wrapped) == "You are offline.")
        #expect(Connectivity.playerProblem(URLError(.badServerResponse)) == "This recording would not play.")
        #expect(Connectivity.playerProblem(nil) == "This recording would not play.")
    }
}
