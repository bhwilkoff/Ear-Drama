import Foundation

/// Shared API client — ALL network calls go through this singleton.
/// Views never call URLSession directly. Same architectural rule as
/// `js/api.js` (web) and `ApiClient.kt` (Android).
///
/// Every Worker call runs `refreshIfNeeded()` first (AGENTS.md hard rule;
/// Decision 063): under five minutes left on the access token, it is
/// refreshed before the call, ONE refresh at a time, because the Worker reads
/// a refresh token sent twice as stolen and ends every session of that sign-in.
/// A 401 on a call gets one refresh and one retry, then surfaces.
actor APIClient {
    static let shared = APIClient(config: .bundled, vault: KeychainVault())

    /// Refresh when less than this is left on the access token.
    static let refreshMargin: TimeInterval = 5 * 60

    nonisolated let config: AccountConfig
    private nonisolated let vault: any SessionVault
    private let session: URLSession
    private let now: @Sendable () -> Date
    private var refreshTask: Task<WorkerSession, Error>?

    init(config: AccountConfig, vault: any SessionVault, session: URLSession = .shared,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.config = config
        self.vault = vault
        self.session = session
        self.now = now
    }

    /// The pair in the Keychain, read without a call.
    nonisolated func storedSession() -> WorkerSession? { vault.load() }

    // MARK: - Hosts we do not run (no token)

    /// A plain-text file served by a host we do not run (archive.org's
    /// automatic transcripts, contract §3.1). No token: it is not a Worker.
    func text(from url: URL) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("text/plain", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200...299 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// The published evenings (contract §8), or nil when no file is published.
    /// A static file beside the catalog, not a Worker: no token.
    func tonight(from url: URL = CatalogSource.tonightURL) async throws -> TonightFile? {
        let request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 20)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 404 { return nil }
        guard 200...299 ~= http.statusCode else { throw URLError(.badServerResponse) }
        return try TonightFile.decode(data)
    }

    /// Google's token endpoint: the code and the PKCE verifier for an identity
    /// token, which is only ever handed to the Worker. An installed app's
    /// client has no secret.
    func googleIdentityToken(code: String, request auth: GoogleAuthRequest) async throws -> String {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "client_id", value: auth.clientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: auth.verifier),
            URLQueryItem(name: "redirect_uri", value: auth.redirectURI),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
        ]
        request.httpBody = Data((form.percentEncodedQuery ?? "").utf8)
        let (data, status) = try await send(request)
        guard 200...299 ~= status else { throw WorkerError.http(status: status, code: nil) }
        struct Answer: Decodable { let id_token: String }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: data) else { throw WorkerError.badResponse }
        return answer.id_token
    }

    // MARK: - The Worker: sign-in

    /// Trades a provider's identity token for the Worker's pair, kept in the
    /// Keychain. Returns the session and whether this sign-in made the account.
    func signIn(provider: AccountProvider, idToken: String, nonce: String, device: String,
                appleUserID: String? = nil) async throws -> WorkerSession {
        struct Body: Encodable { let idToken: String; let nonce: String; let device: String }
        let data = try await worker("POST", "/v1/auth/\(provider.rawValue)",
                                    body: Body(idToken: idToken, nonce: nonce, device: device), token: nil)
        var s = try decode(WorkerSession.self, data)
        s.provider = provider
        s.appleUserId = appleUserID
        vault.save(s)
        return s
    }

    /// Call BEFORE any request to the Worker. Returns a session with at least
    /// `refreshMargin` left, refreshing first when it has less.
    @discardableResult
    func refreshIfNeeded() async throws -> WorkerSession {
        guard config.isAvailable else { throw WorkerError.notConfigured }
        guard let current = vault.load() else { throw WorkerError.signedOut }
        if current.accessExpiry.timeIntervalSince(now()) > Self.refreshMargin { return current }
        return try await refresh(replacing: current)
    }

    /// One refresh at a time: a second caller waits for the first one's answer,
    /// and a caller holding a pair that was already replaced takes the new one.
    private func refresh(replacing stale: WorkerSession) async throws -> WorkerSession {
        if let running = refreshTask { return try await running.value }
        if let current = vault.load(), current.refreshToken != stale.refreshToken { return current }
        let task = Task { try await self.performRefresh(stale) }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func performRefresh(_ stale: WorkerSession) async throws -> WorkerSession {
        struct Body: Encodable { let refreshToken: String }
        do {
            let data = try await worker("POST", "/v1/auth/refresh", body: Body(refreshToken: stale.refreshToken), token: nil)
            var fresh = try decode(WorkerSession.self, data)
            fresh.provider = stale.provider
            fresh.appleUserId = stale.appleUserId
            vault.save(fresh)
            return fresh
        } catch WorkerError.http(401, _) {
            vault.clear()
            throw WorkerError.sessionEnded
        }
    }

    // MARK: - The Worker: signed-in calls

    func account() async throws -> AccountInfo {
        try decode(AccountInfo.self, try await authorized("GET", "/v1/account"))
    }

    func syncRead(since: Int64) async throws -> SyncDown {
        try decode(SyncDown.self, try await authorized("GET", "/v1/sync", query: [URLQueryItem(name: "since", value: String(since))]))
    }

    func syncUpload(_ upload: SyncUpload) async throws -> SyncAck {
        try decode(SyncAck.self, try await authorized("PUT", "/v1/sync", body: upload))
    }

    /// The one-time send of what the device kept while signed out.
    func syncMerge(_ upload: SyncUpload) async throws -> SyncAck {
        try decode(SyncAck.self, try await authorized("POST", "/v1/sync/merge", body: upload))
    }

    /// Ends this sign-in at the Worker; the Keychain is cleared whatever the
    /// Worker answers, so the device is signed out either way.
    func signOut() async {
        defer { vault.clear() }
        guard vault.load() != nil else { return }
        _ = try? await authorized("POST", "/v1/auth/signout")
    }

    /// Deletes the account and every row it owns. `appleAuthorizationCode` is
    /// a FRESH code, so the Worker can revoke the Apple token (Decision 063).
    /// The Keychain is cleared only once the Worker confirms.
    func deleteAccount(appleAuthorizationCode: String?) async throws -> DeletionResult {
        struct Body: Encodable { let appleAuthorizationCode: String? }
        let result = try decode(DeletionResult.self, try await authorized(
            "DELETE", "/v1/account", body: Body(appleAuthorizationCode: appleAuthorizationCode)))
        vault.clear()
        return result
    }

    // MARK: - Plumbing

    private func authorized(_ method: String, _ path: String, query: [URLQueryItem] = [],
                            body: (any Encodable)? = nil) async throws -> Data {
        let current = try await refreshIfNeeded()
        do {
            return try await worker(method, path, query: query, body: body, token: current.accessToken)
        } catch WorkerError.http(401, _) {
            let fresh = try await refresh(replacing: current)
            return try await worker(method, path, query: query, body: body, token: fresh.accessToken)
        }
    }

    private func worker(_ method: String, _ path: String, query: [URLQueryItem] = [],
                        body: (any Encodable)? = nil, token: String?) async throws -> Data {
        guard let base = config.workerURL else { throw WorkerError.notConfigured }
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try WorkerJSON.encoder().encode(body)
        }
        let (data, status) = try await send(request)
        guard 200...299 ~= status else {
            struct Problem: Decodable { let error: String? }
            throw WorkerError.http(status: status, code: (try? JSONDecoder().decode(Problem.self, from: data))?.error)
        }
        return data
    }

    private func send(_ request: URLRequest) async throws -> (Data, Int) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw WorkerError.transport
        }
        guard let http = response as? HTTPURLResponse else { throw WorkerError.badResponse }
        return (data, http.statusCode)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try WorkerJSON.decoder().decode(T.self, from: data) } catch { throw WorkerError.badResponse }
    }
}
