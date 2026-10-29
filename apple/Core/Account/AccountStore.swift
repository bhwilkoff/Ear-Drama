import AuthenticationServices
import Foundation
import Observation
#if os(iOS) || os(tvOS)
import UIKit
#endif

/// Optional sign-in and sync (Decisions 057, 063). Nobody is asked to sign in:
/// every listening verb works signed out, and this store does nothing until
/// someone does. Every call goes through `APIClient`; the tokens live in its
/// Keychain vault, and only the sync cursor and the last sync time live here.
@Observable
final class AccountStore {
    enum Status: Equatable {
        /// The build carries placeholder ids: sign-in is not offered.
        case unavailable
        case signedOut
        case signedIn(AccountProvider)
    }

    private(set) var status: Status
    private(set) var lastSync: Date?
    private(set) var lastError: String?
    private(set) var isWorking = false

    @ObservationIgnored let api: APIClient
    @ObservationIgnored private let history: ListeningHistory
    @ObservationIgnored private let follows: FollowedSeries
    @ObservationIgnored private let queue: ListeningQueue
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let device: String
    /// The open catalog's forwarding ids (contract §3.5): another device's rows
    /// may name an id this catalog moved, and land under the id it now is.
    @ObservationIgnored var forwarding: () -> IDForwarding = { IDForwarding() }

    private enum Key {
        static let since = "account.since"
        static let lastSync = "account.lastSync"
        /// The user id whose anonymous merge has been sent for this sign-in.
        static let merged = "account.mergedUser"
        static let all = [since, lastSync, merged]
    }

    init(api: APIClient = .shared, history: ListeningHistory, follows: FollowedSeries, queue: ListeningQueue,
         defaults: UserDefaults = .standard, device: String = AccountStore.deviceName) {
        self.api = api
        self.history = history
        self.follows = follows
        self.queue = queue
        self.defaults = defaults
        self.device = device
        if !api.config.isAvailable {
            status = .unavailable
        } else if let s = api.storedSession() {
            status = .signedIn(s.provider ?? .apple)
            lastSync = defaults.object(forKey: Key.lastSync) as? Date
        } else {
            status = .signedOut
        }
    }

    var isSignedIn: Bool { if case .signedIn = status { true } else { false } }
    var isGoogleAvailable: Bool { api.config.isGoogleAvailable }
    var googleClientID: String? { api.config.googleClientID }

    // MARK: - Sign-in

    /// After the provider answers: trade its token at the Worker, send what the
    /// device kept while signed out (once), then read the account's rows.
    func signIn(provider: AccountProvider, idToken: String, nonce: String, appleUserID: String? = nil) async {
        guard status == .signedOut else { return }
        isWorking = true
        do {
            _ = try await api.signIn(provider: provider, idToken: idToken, nonce: nonce, device: device,
                                     appleUserID: appleUserID)
            forgetAccountState()
            status = .signedIn(provider)
            isWorking = false
            await sync()
        } catch {
            isWorking = false
            report(error)
        }
    }

    func signInWithGoogle(code: String, request: GoogleAuthRequest) async {
        do {
            let token = try await api.googleIdentityToken(code: code, request: request)
            await signIn(provider: .google, idToken: token, nonce: request.nonce)
        } catch {
            report(error)
        }
    }

    /// A sign-in the provider refused or the person abandoned halfway.
    func report(_ error: Error) {
        if let worker = error as? WorkerError {
            lastError = worker.message
        } else {
            lastError = "Sign-in did not finish."
        }
    }

    // MARK: - Sync

    /// Merge once after sign-in, then upload what changed here, then read what
    /// changed elsewhere since the last read. One sync at a time.
    func sync() async {
        guard isSignedIn, !isWorking, let session = api.storedSession() else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            var merged = false
            if defaults.string(forKey: Key.merged) != session.userId {
                try await upload(all: true)
                defaults.set(session.userId, forKey: Key.merged)
                merged = true
            } else {
                try await upload(all: false)
            }
            let since = (defaults.object(forKey: Key.since) as? NSNumber)?.int64Value ?? 0
            let down = try await api.syncRead(since: since)
            history.apply(down.history)
            follows.apply(down.follows)
            queue.apply(down.queue, afterMerge: merged)
            let forwarding = forwarding()
            history.forward(forwarding)
            queue.forward(forwarding)
            defaults.set(NSNumber(value: down.serverTime), forKey: Key.since)
            let now = Date()
            lastSync = now
            defaults.set(now, forKey: Key.lastSync)
            lastError = nil
        } catch WorkerError.sessionEnded {
            forgetAccountState()
            status = .signedOut
            lastError = WorkerError.sessionEnded.message
        } catch {
            report(error)
        }
    }

    /// `all` is the anonymous merge (POST /v1/sync/merge); otherwise only the
    /// pending rows go, by PUT. At most 500 rows of a kind per upload.
    private func upload(all: Bool) async throws {
        let rows = history.syncRows(all: all)
        var followRows = follows.syncRows(all: all)
        var queueState = queue.syncState(all: all)
        var chunks = stride(from: 0, to: rows.count, by: SyncUpload.maximumRows).map {
            Array(rows[$0..<min($0 + SyncUpload.maximumRows, rows.count)])
        }
        if chunks.isEmpty { chunks = [[]] }
        for chunk in chunks {
            let followChunk = Array(followRows.prefix(SyncUpload.maximumRows))
            followRows.removeFirst(followChunk.count)
            let upload = SyncUpload(device: device, history: chunk.isEmpty ? nil : chunk,
                                    follows: followChunk.isEmpty ? nil : followChunk, queue: queueState)
            if upload.history == nil, upload.follows == nil, upload.queue == nil, !all { return }
            _ = all ? try await api.syncMerge(upload) : try await api.syncUpload(upload)
            history.markSynced(chunk)
            follows.markSynced(followChunk)
            if let sent = queueState { queue.markSynced(sent) }
            queueState = nil
        }
        if !followRows.isEmpty {
            let upload = SyncUpload(device: device, history: nil, follows: Array(followRows.prefix(SyncUpload.maximumRows)))
            _ = all ? try await api.syncMerge(upload) : try await api.syncUpload(upload)
            follows.markSynced(upload.follows ?? [])
        }
    }

    // MARK: - Sign out and deletion

    /// Ends this sign-in. The device's listening stays; the account's tokens
    /// and sync state leave.
    func signOut() async {
        await api.signOut()
        forgetAccountState()
        status = api.config.isAvailable ? .signedOut : .unavailable
    }

    /// Deletes the account and all its rows at the Worker. An Apple account
    /// sends a fresh authorization code so the Worker revokes the Apple token.
    /// Throws when the Worker did not confirm; the account is then kept.
    func deleteAccount(appleAuthorizationCode: String?) async throws {
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await api.deleteAccount(appleAuthorizationCode: appleAuthorizationCode)
        } catch {
            report(error)
            throw error
        }
        forgetAccountState()
        status = .signedOut
    }

    /// The provider this account signed in with, for Delete Account's
    /// re-authorization.
    var provider: AccountProvider? {
        if case let .signedIn(p) = status { p } else { nil }
    }

    /// At launch: an Apple ID that revoked this app in Settings is signed out
    /// here too (Sign in with Apple's credential state).
    func start() async {
        guard let session = api.storedSession(), session.provider == .apple, let user = session.appleUserId else { return }
        let state = try? await ASAuthorizationAppleIDProvider().credentialState(forUserID: user)
        if state == .revoked || state == .notFound { await signOut() }
    }

    private func forgetAccountState() {
        for key in Key.all { defaults.removeObject(forKey: key) }
        lastSync = nil
        lastError = nil
    }

    static var deviceName: String {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        #elseif os(tvOS)
        "appletv"
        #elseif os(macOS)
        "mac"
        #else
        "apple"
        #endif
    }
}
