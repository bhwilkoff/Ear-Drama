import Foundation

/// The Worker's address and the Google client id, written into Info.plist at
/// build time from `Accounts.xcconfig`. A placeholder (`REPLACE_WITH...`), an
/// empty value, or an unexpanded `$(...)` reads as absent, and an absent Worker
/// means sign-in is not available in this build: a state, not an error.
nonisolated struct AccountConfig: Sendable, Equatable {
    let workerURL: URL?
    let googleClientID: String?

    init(workerURL: String?, googleClientID: String?) {
        if let raw = Self.real(workerURL), let url = URL(string: raw),
           url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1"].contains(url.host ?? "")) {
            self.workerURL = url
        } else {
            self.workerURL = nil
        }
        self.googleClientID = Self.real(googleClientID).flatMap {
            $0.hasSuffix(".apps.googleusercontent.com") ? $0 : nil
        }
    }

    init(info: [String: Any]?) {
        self.init(workerURL: info?["EDWorkerURL"] as? String, googleClientID: info?["EDGoogleClientID"] as? String)
    }

    static let bundled = AccountConfig(info: Bundle.main.infoDictionary)

    var isAvailable: Bool { workerURL != nil }
    /// Google needs the Worker too: its token is only ever spent there.
    var isGoogleAvailable: Bool { isAvailable && googleClientID != nil }

    private static func real(_ value: String?) -> String? {
        guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty,
              !v.hasPrefix("REPLACE_WITH"), !v.contains("$(") else { return nil }
        return v
    }
}
