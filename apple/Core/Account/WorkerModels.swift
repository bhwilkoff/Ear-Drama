import Foundation

// The Worker's JSON (docs/WORKER.md "Endpoints"). Keys are snake_case on the
// wire; `WorkerJSON` converts, so a property named `episodeId` is `episode_id`.
// Times are milliseconds since 1970, as the Worker writes them.

nonisolated enum AccountProvider: String, Codable, Sendable, CaseIterable {
    case apple, google

    var title: String {
        switch self {
        case .apple: "Apple"
        case .google: "Google"
        }
    }
}

/// The Worker's own session pair, kept in the Keychain (`SessionVault`).
nonisolated struct WorkerSession: Codable, Equatable, Sendable {
    var accessToken: String
    var accessExpiresAt: Int64
    var refreshToken: String
    var refreshExpiresAt: Int64
    var userId: String
    var provider: AccountProvider?
    /// Sign in with Apple's `user`, for the launch credential-state check.
    var appleUserId: String?

    var accessExpiry: Date { Date(millis: accessExpiresAt) }
}

nonisolated struct HistoryRow: Codable, Equatable, Sendable {
    var episodeId: String
    var position: Double
    var duration: Double?
    var finished: Bool
    var deleted: Bool
    var updatedAt: Int64
}

nonisolated struct FollowRow: Codable, Equatable, Sendable {
    var seriesId: String
    var following: Bool
    var updatedAt: Int64
}

nonisolated struct QueueState: Codable, Equatable, Sendable {
    var items: [String]
    var updatedAt: Int64
}

nonisolated struct SyncUpload: Codable, Equatable, Sendable {
    var device: String
    var history: [HistoryRow]?
    var follows: [FollowRow]?
    var queue: QueueState?

    /// The Worker refuses more than this many rows of one kind in an upload.
    static let maximumRows = 500
}

nonisolated struct SyncDown: Codable, Equatable, Sendable {
    var serverTime: Int64
    var history: [HistoryRow]
    var follows: [FollowRow]
    var queue: QueueState?
}

nonisolated struct SyncAck: Codable, Equatable, Sendable {
    var serverTime: Int64
}

nonisolated struct AccountInfo: Codable, Equatable, Sendable {
    var userId: String
    var createdAt: Int64
    var providers: [String]
    var lastSyncAt: Int64?
}

nonisolated struct DeletionResult: Codable, Equatable, Sendable {
    var deleted: Bool
    var appleTokenRevoked: Bool?
}

nonisolated enum WorkerError: Error, Equatable, Sendable {
    /// The build carries placeholder ids.
    case notConfigured
    /// No session in the Keychain.
    case signedOut
    /// The Worker refused the refresh token: this sign-in is over.
    case sessionEnded
    case http(status: Int, code: String?)
    case transport
    case badResponse

    var message: String {
        switch self {
        case .notConfigured: "Sign-in is not available in this build."
        case .signedOut, .sessionEnded: "Signed out. Sign in again to sync."
        case .http(401, _): "The server did not accept this sign-in."
        case .http(429, _): "Too many requests. Try again in a minute."
        case .http(503, _): "Sign-in is not set up on the server yet."
        case .http(let status, _): "The server answered \(status)."
        case .transport: "Could not reach the server."
        case .badResponse: "The server's answer could not be read."
        }
    }
}

nonisolated enum WorkerJSON {
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }
}

nonisolated extension Date {
    init(millis: Int64) { self.init(timeIntervalSince1970: Double(millis) / 1000) }
    var millis: Int64 { Int64((timeIntervalSince1970 * 1000).rounded(.down)) }
}
