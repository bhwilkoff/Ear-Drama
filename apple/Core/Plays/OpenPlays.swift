import Foundation

// Plays that need no account (owner, 2026-10-29; docs/WORKER.md "Open reads"):
// an invite link shows everything signed out, and finished ear dramas are
// listed and credited. Reads only. Claiming, recording, uploading, reporting
// and blocking stay in `WorkerPlays`, behind an account.

/// GET /plays/open/invite: the play an invite opens, for someone not signed in.
nonisolated struct OpenInvite: Codable, Equatable, Sendable {
    struct Part: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var lineCount: Int
        var status: PartState.Status
        /// The performer's chosen name; absent while the part is open.
        var performer: String?
    }

    struct Member: Codable, Equatable, Sendable {
        var name: String
        var director: Bool
    }

    /// A chosen take the viewer may hear. `audio` is a path for `WorkerOpenPlays.audio`.
    struct Take: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var lineID: String
        var part: String
        var frames: Int
        var sampleRate: Double
        var audio: String
    }

    struct Archive: Codable, Equatable, Sendable {
        var status: String
        var url: String?
    }

    var id: String
    var scriptID: String
    var scriptRevision: String
    var title: String
    var source: String?
    var parts: [Part]
    var members: [Member]
    var takes: [Take]
    var chosen: [String: String]
    var next: String?
    var archive: Archive?
    var expiresAt: Int64?

    enum CodingKeys: String, CodingKey {
        case id, scriptID, scriptRevision, title, source, parts, members, takes, chosen, next, archive
        case expiresAt = "expires_at"
    }
}

/// One finished ear drama (GET /plays/finished): `credits` run in script order, a part with
/// `name` "" when its performer is gone.
nonisolated struct FinishedPlay: Codable, Equatable, Sendable, Identifiable {
    struct Credit: Codable, Equatable, Sendable {
        var part: String
        var name: String
    }

    var id: String
    var scriptID: String
    var title: String
    var source: String?
    var credits: [Credit]
    var archiveURL: String
    /// Milliseconds since 1970 on the Worker's clock.
    var publishedAt: Int64

    enum CodingKeys: String, CodingKey {
        case id, title, source, credits
        case scriptID = "script_id"
        case archiveURL = "archive_url"
        case publishedAt = "published_at"
    }
}

/// Newest published first. `nextCursor` goes back as `cursor` for the next page; nil ends the list.
nonisolated struct FinishedPage: Codable, Equatable, Sendable {
    var productions: [FinishedPlay]
    var nextCursor: String?

    enum CodingKeys: String, CodingKey { case productions, nextCursor = "next_cursor" }
}

extension PlaysRefusal {
    /// A revoked or expired invite (the Worker's plain 410).
    var isGone: Bool { status == 410 }
}

/// The Worker's open routes through the one `APIClient`, with no bearer.
struct WorkerOpenPlays {
    let api: APIClient

    private static let root = "/v1/plays"
    static let inviteHeader = "x-invite"

    private static func escape(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_.~"))) ?? s
    }

    private func get(_ path: String, headers: [String: String] = [:]) async throws -> Data {
        let data: Data
        let status: Int
        do {
            (data, status) = try await api.openWorkerResponse(path: path, headers: headers)
        } catch {
            throw PlaysRefusal.from(error)
        }
        guard 200...299 ~= status else { throw WorkerPlays.refusal(status, data) }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw PlaysRefusal(kind: .unreachable) }
    }

    /// The token rides the `x-invite` header, never the path.
    func openInvite(_ token: String) async throws -> OpenInvite {
        try decode(OpenInvite.self, try await get("\(Self.root)/open/invite", headers: [Self.inviteHeader: token]))
    }

    func audio(_ token: String, takeID: String) async throws -> Data {
        try await get("\(Self.root)/open/invite/takes/\(Self.escape(takeID))/audio", headers: [Self.inviteHeader: token])
    }

    func finished(limit: Int? = nil, cursor: String? = nil) async throws -> FinishedPage {
        var query: [String] = []
        if let limit { query.append("limit=\(limit)") }
        if let cursor { query.append("cursor=\(Self.escape(cursor))") }
        let tail = query.isEmpty ? "" : "?" + query.joined(separator: "&")
        return try decode(FinishedPage.self, try await get("\(Self.root)/finished\(tail)"))
    }

    func finished(id: String) async throws -> FinishedPlay {
        try decode(FinishedPlay.self, try await get("\(Self.root)/finished/\(Self.escape(id))"))
    }
}
