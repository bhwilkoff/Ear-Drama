import Foundation

/// The offline words every platform shares (web §7.3, Android `OFFLINE_LINE`)
/// and the rule for when they show. Offline is a degraded mode, not a failure:
/// what the person already loaded keeps working, and the line says why the
/// rest does not.
nonisolated enum Connectivity {
    static let offlineLine = "You are offline."

    /// The status line while offline, else nothing.
    static func line(online: Bool) -> String? { online ? nil : offlineLine }

    /// The network monitor's answer, unless the APP_FORCE_OFFLINE door holds
    /// the offline state (it fakes the state, never the network).
    static func isOnline(pathSatisfied: Bool, forcedOffline: Bool) -> Bool {
        pathSatisfied && !forcedOffline
    }

    /// The player's line for an item that would not play: the network when the
    /// failure was the network, so an undownloaded episode played offline is
    /// refused in words, never left spinning.
    static func playerProblem(_ error: Error?) -> String {
        let offlineCodes: Set<Int> = [
            NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
            NSURLErrorDataNotAllowed, NSURLErrorInternationalRoamingOff,
        ]
        var next = error as NSError?
        while let e = next {
            if e.domain == NSURLErrorDomain, offlineCodes.contains(e.code) { return offlineLine }
            next = e.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return "This recording would not play."
    }
}
