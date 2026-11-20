import Foundation

/// The Worker's address and the Google client id, written into Info.plist at
/// build time from `Accounts.xcconfig`. A placeholder (`REPLACE_WITH...`), an
/// empty value, or an unexpanded `$(...)` reads as absent, and an absent Worker
/// means sign-in is not available in this build: a state, not an error.
nonisolated struct AccountConfig: Sendable, Equatable {
    private var benchURL: URL?
    private let configuredURL: URL?
    var workerURL: URL? { benchURL ?? configuredURL }
    let googleClientID: String?

    init(workerURL: String?, googleClientID: String?) {
        if let raw = Self.real(workerURL), let url = URL(string: raw),
           url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1"].contains(url.host ?? "")) {
            self.configuredURL = url
        } else {
            self.configuredURL = nil
        }
        self.googleClientID = Self.real(googleClientID).flatMap {
            $0.hasSuffix(".apps.googleusercontent.com") ? $0 : nil
        }
    }

    init(info: [String: Any]?) {
        self.init(workerURL: info?["EDWorkerURL"] as? String, googleClientID: info?["EDGoogleClientID"] as? String)
    }

    static let bundled: AccountConfig = {
        #if DEBUG
        if let door = benchWorker(ProcessInfo.processInfo.environment["APP_WORKER_URL"]) { return door }
        #endif
        return AccountConfig(info: Bundle.main.infoDictionary)
    }()

    /// DEBUG door `APP_WORKER_URL=http://<this Mac on the home network>:<port>`: the read bench's local `wrangler dev`
    /// (tools/read_bench.py --base, tools/class_bench.py). Only plain http to a private address; never compiled into Release.
    static func benchWorker(_ raw: String?) -> AccountConfig? {
        guard let raw, let url = URL(string: raw), url.scheme == "http", let host = url.host,
              host.range(of: #"^(10\.\d+\.\d+\.\d+|192\.168\.\d+\.\d+|172\.(1[6-9]|2\d|3[01])\.\d+\.\d+|[A-Za-z0-9-]+\.local)$"#,
                         options: .regularExpression) != nil else { return nil }
        var made = AccountConfig(workerURL: nil, googleClientID: nil)
        made.benchURL = url
        return made
    }

    var isAvailable: Bool { workerURL != nil }
    /// Google needs the Worker too: its token is only ever spent there.
    var isGoogleAvailable: Bool { isAvailable && googleClientID != nil }

    private static func real(_ value: String?) -> String? {
        guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty,
              !v.hasPrefix("REPLACE_WITH"), !v.contains("$(") else { return nil }
        return v
    }
}
