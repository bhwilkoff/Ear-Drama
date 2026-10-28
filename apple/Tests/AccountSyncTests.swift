import Foundation
import Testing

/// Sign-in and sync against a stubbed Worker (docs/WORKER.md's endpoints, with
/// its refresh rotation: a spent refresh token comes back 401). Nothing here
/// reaches a network; the Keychain is replaced by `MemoryVault`, the same
/// contract `KeychainVault` keeps.

nonisolated final class FakeWorker: @unchecked Sendable {
    struct Logged { let method: String; let path: String; let query: String?; let body: [String: Any]; let bearer: String? }

    private let lock = NSLock()
    private var validAccess: Set<String> = []
    private var validRefresh: Set<String> = []
    private var spentRefresh: Set<String> = []
    private var counter = 0
    private var _log: [Logged] = []
    var rejectEveryAccessToken = false
    var refreshDelay: TimeInterval = 0
    var serverTime: Int64 = 1_761_200_000_000
    var down: [String: Any] = ["history": [], "follows": [], "queue": NSNull()]

    var log: [Logged] { lock.withLock { _log } }
    func count(_ method: String, _ path: String) -> Int { log.filter { $0.method == method && $0.path == path }.count }

    func grant(access: String? = nil, refresh: String? = nil) {
        lock.withLock {
            if let access { validAccess.insert(access) }
            if let refresh { validRefresh.insert(refresh) }
        }
    }

    func handle(_ request: URLRequest, body: Data) -> (Int, Any, TimeInterval) {
        let url = request.url!
        let path = url.path
        let method = request.httpMethod ?? "GET"
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        let bearer = request.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer ", with: "")
        return lock.withLock {
            _log.append(Logged(method: method, path: path, query: url.query, body: json, bearer: bearer))
            switch (method, path) {
            case ("POST", "/v1/auth/apple"), ("POST", "/v1/auth/google"):
                return (200, issue(), 0)
            case ("POST", "/v1/auth/refresh"):
                let token = json["refresh_token"] as? String ?? ""
                guard validRefresh.contains(token) else { return (401, ["error": "invalid_refresh"], refreshDelay) }
                validRefresh.remove(token)
                spentRefresh.insert(token)
                return (200, issue(), refreshDelay)
            default:
                guard let bearer, validAccess.contains(bearer), !rejectEveryAccessToken else {
                    return (401, ["error": "unauthorized"], 0)
                }
                switch (method, path) {
                case ("GET", "/v1/account"):
                    return (200, ["user_id": "u1", "created_at": 1, "providers": ["apple"]], 0)
                case ("GET", "/v1/sync"):
                    var d = down
                    d["server_time"] = serverTime
                    return (200, d, 0)
                case ("PUT", "/v1/sync"), ("POST", "/v1/sync/merge"):
                    return (200, ["server_time": serverTime, "applied": ["history": 0, "follows": 0, "queue": false]], 0)
                case ("DELETE", "/v1/account"):
                    return (200, ["deleted": true, "apple_token_revoked": true], 0)
                case ("POST", "/v1/auth/signout"):
                    return (204, [:], 0)
                default:
                    return (404, ["error": "not_found"], 0)
                }
            }
        }
    }

    private func issue() -> [String: Any] {
        counter += 1
        let access = "access-\(counter)", refresh = "refresh-\(counter)"
        validAccess.insert(access)
        validRefresh.insert(refresh)
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        return ["access_token": access, "access_expires_at": now + 3_600_000, "refresh_token": refresh,
                "refresh_expires_at": now + 86_400_000, "user_id": "u1", "provider": "apple"]
    }
}

nonisolated final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var worker: FakeWorker?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let worker = Self.worker else { return }
        let (status, object, delay) = worker.handle(request, body: Self.body(of: request))
        let data = status == 204 ? Data() : (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        let finish: @Sendable () -> Void = { [self] in
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
        if delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: finish)
        } else {
            finish()
        }
    }

    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}

@Suite(.serialized)
struct AccountSyncTests {
    private let worker = FakeWorker()
    private let vault = MemoryVault()
    private let api: APIClient
    private let defaults: UserDefaults

    init() {
        StubURLProtocol.worker = worker
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        api = APIClient(config: AccountConfig(workerURL: "https://worker.test", googleClientID: nil),
                        vault: vault, session: URLSession(configuration: configuration))
        defaults = UserDefaults(suiteName: "account-tests-\(UUID().uuidString)")!
    }

    private func session(access: String = "access-0", refresh: String = "refresh-0",
                         expiresIn seconds: TimeInterval) -> WorkerSession {
        let now = Date()
        return WorkerSession(accessToken: access, accessExpiresAt: now.addingTimeInterval(seconds).millis,
                             refreshToken: refresh, refreshExpiresAt: now.addingTimeInterval(86_400).millis,
                             userId: "u1", provider: .apple, appleUserId: "apple-user")
    }

    private func calls() -> [String] { worker.log.map { "\($0.method) \($0.path)" } }

    // MARK: - The one API client

    @Test func refreshesBeforeTheCallWhenUnderFiveMinutesRemain() async throws {
        worker.grant(access: "access-0", refresh: "refresh-0")
        vault.save(session(expiresIn: 120))
        _ = try await api.account()
        #expect(calls() == ["POST /v1/auth/refresh", "GET /v1/account"])
        #expect(worker.log.last?.bearer == "access-1")
        #expect(vault.load()?.refreshToken == "refresh-1")
        #expect(vault.load()?.provider == .apple)
    }

    @Test func noRefreshWhileMoreThanFiveMinutesRemain() async throws {
        worker.grant(access: "access-0", refresh: "refresh-0")
        vault.save(session(expiresIn: 30 * 60))
        _ = try await api.account()
        #expect(calls() == ["GET /v1/account"])
    }

    @Test func concurrentCallsShareOneRefresh() async throws {
        worker.grant(refresh: "refresh-0")
        worker.refreshDelay = 0.3
        vault.save(session(expiresIn: -10))
        async let a = api.account()
        async let b = api.account()
        async let c = api.syncRead(since: 0)
        _ = try await (a, b, c)
        #expect(worker.count("POST", "/v1/auth/refresh") == 1)
        #expect(worker.log.filter { $0.path != "/v1/auth/refresh" }.allSatisfy { $0.bearer == "access-1" })
    }

    @Test func a401RefreshesOnceThenSurfaces() async throws {
        worker.grant(access: "access-0", refresh: "refresh-0")
        worker.rejectEveryAccessToken = true
        vault.save(session(expiresIn: 3600))
        await #expect(throws: WorkerError.http(status: 401, code: "unauthorized")) { _ = try await api.account() }
        #expect(calls() == ["GET /v1/account", "POST /v1/auth/refresh", "GET /v1/account"])
    }

    @Test func aRefusedRefreshClearsTheVault() async throws {
        vault.save(session(expiresIn: -10))
        await #expect(throws: WorkerError.sessionEnded) { _ = try await api.account() }
        #expect(vault.load() == nil)
    }

    // MARK: - The store: merge, apply, delete

    private func makeStore(history: ListeningHistory) -> AccountStore {
        AccountStore(api: api, history: history, follows: FollowedSeries(defaults: defaults),
                     queue: ListeningQueue(defaults: defaults), defaults: defaults, device: "mac")
    }

    @Test func theAnonymousHistoryIsMergedOnceAfterSignIn() async throws {
        let history = ListeningHistory(defaults: defaults)
        history.record("suspense|1948-03-11", position: 612, duration: 1795, now: Date(millis: 1_000_000))
        history.record("x-minus-one|1955-04-24", position: 90, duration: 1800, now: Date(millis: 1_000_500))
        history.remove("x-minus-one|1955-04-24", now: Date(millis: 1_000_900))
        history.record("lux|1938-01-01", position: 40, duration: 3600, now: Date(millis: 1_001_000))
        let store = makeStore(history: history)
        #expect(store.status == .signedOut)

        await store.signIn(provider: .apple, idToken: "identity", nonce: "raw-nonce", appleUserID: "apple-user")
        #expect(store.status == .signedIn(.apple))
        #expect(store.lastError == nil)
        #expect(calls() == ["POST /v1/auth/apple", "POST /v1/sync/merge", "GET /v1/sync"])
        #expect(worker.log[0].body["nonce"] as? String == "raw-nonce")
        let merged = try #require(worker.log[1].body["history"] as? [[String: Any]])
        #expect(merged.count == 3)
        #expect(merged.contains { $0["episode_id"] as? String == "x-minus-one|1955-04-24" && $0["deleted"] as? Bool == true })
        #expect(worker.log[2].query == "since=0")
        #expect(history.pending.isEmpty)

        history.record("suspense|1948-03-11", position: 700, duration: 1795)
        await store.sync()
        #expect(worker.count("POST", "/v1/sync/merge") == 1)
        #expect(worker.count("PUT", "/v1/sync") == 1)
        let put = try #require(worker.log.first { $0.method == "PUT" })
        #expect((put.body["history"] as? [[String: Any]])?.count == 1)
        #expect(worker.log.last?.query == "since=\(worker.serverTime)")
        #expect(store.lastSync != nil)
    }

    @Test func lastWriteWinsPerRowWithRemovalMarkers() {
        let history = ListeningHistory(defaults: defaults)
        history.record("a", position: 100, duration: 1000, now: Date(millis: 2000))
        history.record("b", position: 100, duration: 1000, now: Date(millis: 1000))
        history.record("c", position: 100, duration: 1000, now: Date(millis: 1000))
        history.remove("c", now: Date(millis: 3000))
        history.record("d", position: 100, duration: 1000, now: Date(millis: 3500))

        history.apply([
            HistoryRow(episodeId: "a", position: 5, duration: 1000, finished: false, deleted: false, updatedAt: 1500),
            HistoryRow(episodeId: "b", position: 99, duration: 1000, finished: false, deleted: false, updatedAt: 1800),
            HistoryRow(episodeId: "c", position: 50, duration: 1000, finished: false, deleted: false, updatedAt: 2500),
            HistoryRow(episodeId: "d", position: 0, duration: nil, finished: false, deleted: true, updatedAt: 4000),
            HistoryRow(episodeId: "e", position: 300, duration: 1000, finished: false, deleted: false, updatedAt: 100),
        ])
        #expect(history.entry(for: "a")?.position == 100)  // local is newer
        #expect(history.entry(for: "b")?.position == 99)   // remote is newer
        #expect(history.entry(for: "c") == nil)            // a newer local removal holds
        #expect(history.entry(for: "d") == nil)            // a newer remote removal applies
        #expect(history.removals["d"] == Date(millis: 4000))
        #expect(history.entry(for: "e")?.position == 300)  // new here
        #expect(history.pending == ["a", "c"])             // only what this device still owes

        let follows = FollowedSeries(defaults: defaults)
        follows.setFollowing("suspense", true, now: Date(millis: 5000))
        follows.apply([FollowRow(seriesId: "suspense", following: false, updatedAt: 4000),
                       FollowRow(seriesId: "lux", following: true, updatedAt: 1)])
        #expect(follows.followedKeys == ["suspense", "lux"])   // newest follow first
        follows.apply([FollowRow(seriesId: "suspense", following: false, updatedAt: 6000)])
        #expect(follows.followedKeys == ["lux"])

        let queue = ListeningQueue(defaults: defaults)
        queue.set(["a"], now: Date(millis: 2000))
        queue.apply(QueueState(items: ["z"], updatedAt: 1000))
        #expect(queue.items == ["a"])
        queue.apply(QueueState(items: ["b", "c"], updatedAt: 3000))
        #expect(queue.items == ["b", "c"])
        #expect(queue.syncState() == nil)
    }

    @Test func deletionSendsAFreshAppleCodeAndForgetsTheAccount() async throws {
        worker.grant(access: "access-0", refresh: "refresh-0")
        vault.save(session(expiresIn: 3600))
        defaults.set(NSNumber(value: 42), forKey: "account.since")
        defaults.set(Date(), forKey: "account.lastSync")
        defaults.set("u1", forKey: "account.mergedUser")
        let history = ListeningHistory(defaults: defaults)
        history.record("suspense|1948-03-11", position: 612, duration: 1795)
        let store = makeStore(history: history)
        #expect(store.status == .signedIn(.apple))
        #expect(store.lastSync != nil)

        try await store.deleteAccount(appleAuthorizationCode: "fresh-code")
        let delete = try #require(worker.log.first { $0.method == "DELETE" })
        #expect(delete.path == "/v1/account")
        #expect(delete.body["apple_authorization_code"] as? String == "fresh-code")
        #expect(vault.load() == nil)
        #expect(store.status == .signedOut)
        #expect(store.lastSync == nil && store.lastError == nil)
        for key in ["account.since", "account.lastSync", "account.mergedUser"] {
            #expect(defaults.object(forKey: key) == nil)
        }
        // The device's own listening stays, as it does on sign-out.
        #expect(history.entry(for: "suspense|1948-03-11") != nil)
    }

    @Test func aFailedDeletionKeepsTheAccount() async throws {
        worker.grant(refresh: "refresh-0")
        worker.rejectEveryAccessToken = true
        vault.save(session(expiresIn: 3600))
        let store = makeStore(history: ListeningHistory(defaults: defaults))
        await #expect(throws: WorkerError.self) { try await store.deleteAccount(appleAuthorizationCode: nil) }
        #expect(vault.load() != nil)
        #expect(store.status == .signedIn(.apple))
        #expect(store.lastError != nil)
    }

    // MARK: - Configuration and the sign-in requests

    @Test func placeholdersMeanSignInIsUnavailable() {
        #expect(!AccountConfig(workerURL: "REPLACE_WITH_WORKER_URL", googleClientID: nil).isAvailable)
        #expect(!AccountConfig(workerURL: "$(EARDRAMA_WORKER_URL)", googleClientID: nil).isAvailable)
        #expect(!AccountConfig(workerURL: "", googleClientID: nil).isAvailable)
        #expect(!AccountConfig(workerURL: "http://api.eardrama.org", googleClientID: nil).isAvailable)
        let real = AccountConfig(workerURL: "https://api.eardrama.org",
                                 googleClientID: "REPLACE_WITH_GOOGLE_IOS_CLIENT_ID")
        #expect(real.isAvailable && !real.isGoogleAvailable)
        let store = AccountStore(api: APIClient(config: AccountConfig(workerURL: nil, googleClientID: nil), vault: vault),
                                 history: ListeningHistory(defaults: defaults), follows: FollowedSeries(defaults: defaults),
                                 queue: ListeningQueue(defaults: defaults), defaults: defaults)
        #expect(store.status == .unavailable)
    }

    @Test func pkceMatchesRFC7636() {
        #expect(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
                == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(SignInNonce.sha256Hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func googleRequestUsesTheReversedClientIDAndChecksState() throws {
        let request = GoogleAuthRequest(clientID: "123-abc.apps.googleusercontent.com", verifier: "v", state: "s", nonce: "n")
        #expect(request.callbackScheme == "com.googleusercontent.apps.123-abc")
        let items = try #require(URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "code_challenge_method" }?.value == "S256")
        #expect(items.first { $0.name == "nonce" }?.value == "n")
        #expect(request.code(from: URL(string: "com.googleusercontent.apps.123-abc:/oauth2redirect?state=s&code=c")!) == "c")
        #expect(request.code(from: URL(string: "com.googleusercontent.apps.123-abc:/oauth2redirect?state=x&code=c")!) == nil)
    }
}
