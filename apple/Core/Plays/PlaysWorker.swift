import Foundation

// Shared plays, phase 2 (PLAYS-DESIGN §11.7; docs/WORKER.md "Shared plays"):
// the Worker's JSON and the one transport that reaches it. The record keeps
// production.json's field names (camelCase), and the Worker's own additions
// are snake_case, so every type here names its keys.

/// `share.json` beside `production.json`: the Worker's id for this production,
/// and the consent version this person agreed to for it.
nonisolated struct ProductionShare: Codable, Equatable, Sendable {
    var pid: String
    var consented: String?
}

/// The production record as the Worker merges it (GET /productions/:pid).
nonisolated struct SharedRecord: Codable, Equatable, Sendable {
    struct Part: Codable, Equatable, Sendable {
        var status: PartState.Status
        var performer: String?
        var userID: String?

        enum CodingKeys: String, CodingKey { case status, performer, userID = "user_id" }
    }

    struct Take: Codable, Equatable, Sendable {
        var id: String
        var lineID: String
        var part: String
        var created: Double?
        var frames: Int
        var sampleRate: Double
        var capture: String?
        var heard: [String: String]?
        var loudness: Double?
        var peak: Double?
        var userID: String?

        enum CodingKeys: String, CodingKey {
            case id, lineID, part, created, frames, sampleRate, capture, heard, loudness, peak, userID = "user_id"
        }
    }

    struct Member: Codable, Equatable, Sendable, Identifiable {
        var userID: String
        var displayName: String?
        var director: Bool
        /// Holds a chosen take, so consents for their own recording (Decision 059).
        var performer: Bool?
        /// Agreed to publish at the Worker's current consent version.
        var consented: Bool?
        var id: String { userID }

        enum CodingKeys: String, CodingKey { case userID = "user_id", displayName = "display_name", director, performer, consented }
    }

    struct Archive: Codable, Equatable, Sendable {
        var status: String
    }

    var id: String
    var scriptID: String
    var scriptRevision: String
    var title: String
    var parts: [String: Part]
    var takes: [Take] = []
    var chosen: [String: String] = [:]
    var director: String?
    var members: [Member] = []
    var next: String?
    var hiddenTakes = 0
    var archive: Archive?
    /// The owner's switch (P1): false while the take store is off.
    var uploads: Bool?

    enum CodingKeys: String, CodingKey {
        case id, scriptID, scriptRevision, title, parts, takes, chosen, director, members, next, archive, uploads
        case hiddenTakes = "hidden_takes"
    }

    init(id: String, scriptID: String, scriptRevision: String, title: String, parts: [String: Part],
         takes: [Take] = [], chosen: [String: String] = [:], director: String? = nil, members: [Member] = [],
         next: String? = nil, hiddenTakes: Int = 0, archive: Archive? = nil, uploads: Bool? = nil) {
        self.id = id
        self.scriptID = scriptID
        self.scriptRevision = scriptRevision
        self.title = title
        self.parts = parts
        self.takes = takes
        self.chosen = chosen
        self.director = director
        self.members = members
        self.next = next
        self.hiddenTakes = hiddenTakes
        self.archive = archive
        self.uploads = uploads
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        scriptID = try c.decode(String.self, forKey: .scriptID)
        scriptRevision = try c.decode(String.self, forKey: .scriptRevision)
        title = try c.decode(String.self, forKey: .title)
        parts = try c.decodeIfPresent([String: Part].self, forKey: .parts) ?? [:]
        takes = try c.decodeIfPresent([Take].self, forKey: .takes) ?? []
        chosen = try c.decodeIfPresent([String: String].self, forKey: .chosen) ?? [:]
        director = try c.decodeIfPresent(String.self, forKey: .director)
        members = try c.decodeIfPresent([Member].self, forKey: .members) ?? []
        next = try c.decodeIfPresent(String.self, forKey: .next)
        hiddenTakes = try c.decodeIfPresent(Int.self, forKey: .hiddenTakes) ?? 0
        archive = try c.decodeIfPresent(Archive.self, forKey: .archive)
        uploads = try c.decodeIfPresent(Bool.self, forKey: .uploads)
    }

    func part(_ id: PartID) -> Part { parts[id.rawValue] ?? Part(status: .open) }
}

/// POST /invites/view: the cast sheet an invite opens.
nonisolated struct InviteView: Codable, Equatable, Sendable {
    struct Part: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var lineCount: Int
        var status: PartState.Status
    }
    var id: String
    var scriptID: String
    var scriptRevision: String
    var title: String
    var parts: [Part]
    var next: String?
    var member: Bool
}

nonisolated struct PlaysConsent: Codable, Equatable, Sendable, Identifiable {
    var version: String
    var text: String
    var uploads: Bool?
    var publishes: Bool?
    var id: String { version }
}

nonisolated struct MadeInvite: Codable, Equatable, Sendable {
    var id: String
    var token: String
    var expiresAt: Int64

    enum CodingKeys: String, CodingKey { case id, token, expiresAt = "expires_at" }
}

/// GET /productions: the shared productions this person is in.
nonisolated struct RemoteProduction: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var title: String
    var scriptID: String?
    var director: String?
    var updatedAt: Int64?

    enum CodingKeys: String, CodingKey { case id, title, scriptID = "script_id", director, updatedAt = "updated_at" }
}

nonisolated struct PlayClass: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var code: String?
    var under13: Bool
    var schoolConsent: Bool?

    enum CodingKeys: String, CodingKey { case id, name, code, under13, schoolConsent = "school_consent" }
}

nonisolated struct PlayClasses: Codable, Equatable, Sendable {
    var teaching: [PlayClass]
    var memberOf: [PlayClass]

    enum CodingKeys: String, CodingKey { case teaching, memberOf = "member_of" }
}

nonisolated struct PublishJob: Codable, Equatable, Sendable {
    var status: String
}

/// The reasons a report carries (docs/WORKER.md "Reports").
nonisolated enum ReportReason: String, CaseIterable, Codable, Sendable, Identifiable {
    case offensive, harassment
    case personalInformation = "personal_information"
    case notAPerformance = "not_a_performance"
    case other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .offensive: "Offensive"
        case .harassment: "Harassment"
        case .personalInformation: "Personal information"
        case .notAPerformance: "Not a performance"
        case .other: "Other"
        }
    }
}

/// A take's fields as the Worker reads them from `x-take` (production.json's names).
nonisolated struct TakeMeta: Codable, Equatable, Sendable {
    var lineID: String
    var part: String
    var file: String
    var created: Double
    var frames: Int
    var sampleRate: Double
    var capture: String
    var heard: [String: String]
    var peak: Double
    var bleed: Bool
    var loudness: Double?
}

/// A refusal or a failure, carrying the Worker's own code and detail.
nonisolated struct PlaysRefusal: Error, Equatable, Sendable {
    enum Kind: Sendable { case refused, unauthorized, notConfigured, unreachable }
    var kind: Kind = .refused
    var status = 0
    var code: String?
    /// A string detail (a part id, a version).
    var detail: String?
    /// How many items an array detail held (the lines still missing).
    var detailCount: Int?

    static func code(_ code: String, status: Int = 409, detail: String? = nil, count: Int? = nil) -> PlaysRefusal {
        PlaysRefusal(kind: .refused, status: status, code: code, detail: detail, detailCount: count)
    }

    /// Any error from a call, as a refusal.
    static func from(_ error: any Error) -> PlaysRefusal {
        if let r = error as? PlaysRefusal { return r }
        switch error as? WorkerError {
        case .notConfigured: return PlaysRefusal(kind: .notConfigured)
        case .signedOut, .sessionEnded: return PlaysRefusal(kind: .unauthorized)
        case let .http(status, code): return PlaysRefusal(kind: status == 401 ? .unauthorized : .refused, status: status, code: code)
        default: return PlaysRefusal(kind: .unreachable)
        }
    }
}

/// Every phase 2 route (docs/WORKER.md "Endpoints"). The app's is `WorkerPlays`;
/// the tests stand one in.
protocol PlaysTransport {
    func consent() async throws -> PlaysConsent
    func create(scriptID: String, revision: String, cast: [PlaysShare.CastLine], displayName: String?) async throws -> SharedRecord
    func list() async throws -> [RemoteProduction]
    func get(_ pid: String) async throws -> SharedRecord
    func invite(_ pid: String) async throws -> MadeInvite
    func viewInvite(_ token: String) async throws -> InviteView
    func joinByInvite(_ token: String, part: PartID, displayName: String?) async throws -> SharedRecord
    func claim(_ pid: String, part: PartID) async throws -> SharedRecord
    func partAction(_ pid: String, part: PartID, action: String) async throws -> SharedRecord
    func agree(_ pid: String, version: String) async throws
    func upload(_ pid: String, takeID: String, audio: Data, contentType: String, meta: TakeMeta) async throws
    func audio(_ pid: String, takeID: String) async throws -> Data
    func choose(_ pid: String, takeID: String) async throws -> SharedRecord
    func publish(_ pid: String) async throws -> PublishJob
    func report(_ pid: String, takeID: String?, userID: String?, reason: ReportReason, note: String?) async throws
    func block(_ userID: String) async throws
    func classes() async throws -> PlayClasses
    func createClass(name: String, under13: Bool) async throws -> PlayClass
    func joinClass(code: String, displayName: String?) async throws -> PlayClass
}

/// The Worker's plays routes through the one `APIClient`, refreshed before
/// every call (AGENTS.md hard rules).
struct WorkerPlays: PlaysTransport {
    let api: APIClient

    private static let root = "/v1/plays"
    private static func at(_ pid: String) -> String { "\(root)/productions/\(escape(pid))" }
    private static func escape(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_.~"))) ?? s
    }

    private func call(_ method: String, _ path: String, json: (any Encodable)? = nil, raw: Data? = nil,
                      contentType: String? = nil, headers: [String: String] = [:]) async throws -> Data {
        let body: Data? = if let raw { raw } else if let json { try JSONEncoder().encode(json) } else { nil }
        let data: Data
        let status: Int
        do {
            (data, status) = try await api.workerResponse(method, path: path, body: body, contentType: contentType,
                                                         headers: headers)
        } catch {
            throw PlaysRefusal.from(error)
        }
        guard 200...299 ~= status else { throw Self.refusal(status, data) }
        return data
    }

    static func refusal(_ status: Int, _ data: Data) -> PlaysRefusal {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let code = object?["error"] as? String
        var r = PlaysRefusal(kind: status == 401 ? .unauthorized : .refused, status: status,
                             code: status == 429 ? (code ?? "rate_limited") : code)
        switch object?["detail"] {
        case let s as String: r.detail = s
        case let a as [Any]: r.detailCount = a.count
        default: break
        }
        return r
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) } catch {
            throw PlaysRefusal(kind: .unreachable)
        }
    }

    private struct Create: Encodable {
        let script_id: String
        let script_revision: String
        let cast: [PlaysShare.CastLine]
        let display_name: String?
    }
    private struct Token: Encodable { let token: String }
    private struct Claim: Encodable { let token: String?; let part: String; let display_name: String? }
    private struct Version: Encodable { let version: String }
    private struct Choose: Encodable { let take_id: String }
    private struct Report: Encodable {
        let production_id: String
        let take_id: String?
        let user_id: String?
        let reason: String
        let note: String?
    }
    private struct Block: Encodable { let user_id: String }
    private struct NewClass: Encodable { let name: String; let under13: Bool }
    private struct JoinClass: Encodable { let code: String; let display_name: String? }
    private struct Empty: Encodable {}
    private struct List: Decodable { let productions: [RemoteProduction] }

    func consent() async throws -> PlaysConsent {
        try decode(PlaysConsent.self, try await call("GET", "\(Self.root)/consent"))
    }

    func create(scriptID: String, revision: String, cast: [PlaysShare.CastLine], displayName: String?) async throws -> SharedRecord {
        try decode(SharedRecord.self, try await call("POST", "\(Self.root)/productions",
            json: Create(script_id: scriptID, script_revision: revision, cast: cast, display_name: displayName)))
    }

    func list() async throws -> [RemoteProduction] {
        try decode(List.self, try await call("GET", "\(Self.root)/productions")).productions
    }

    func get(_ pid: String) async throws -> SharedRecord {
        try decode(SharedRecord.self, try await call("GET", Self.at(pid)))
    }

    func invite(_ pid: String) async throws -> MadeInvite {
        try decode(MadeInvite.self, try await call("POST", "\(Self.at(pid))/invites", json: Empty()))
    }

    func viewInvite(_ token: String) async throws -> InviteView {
        try decode(InviteView.self, try await call("POST", "\(Self.root)/invites/view", json: Token(token: token)))
    }

    func joinByInvite(_ token: String, part: PartID, displayName: String?) async throws -> SharedRecord {
        try decode(SharedRecord.self, try await call("POST", "\(Self.root)/invites/claim",
            json: Claim(token: token, part: part.rawValue, display_name: displayName)))
    }

    func claim(_ pid: String, part: PartID) async throws -> SharedRecord {
        try decode(SharedRecord.self, try await call("POST", "\(Self.at(pid))/claim",
            json: Claim(token: nil, part: part.rawValue, display_name: nil)))
    }

    func partAction(_ pid: String, part: PartID, action: String) async throws -> SharedRecord {
        try decode(SharedRecord.self, try await call("POST", "\(Self.at(pid))/parts/\(Self.escape(part.rawValue))/\(action)",
                                                     json: Empty()))
    }

    func agree(_ pid: String, version: String) async throws {
        _ = try await call("POST", "\(Self.at(pid))/consent", json: Version(version: version))
    }

    func upload(_ pid: String, takeID: String, audio: Data, contentType: String, meta: TakeMeta) async throws {
        let header = String(decoding: try JSONEncoder().encode(meta), as: UTF8.self)
        _ = try await call("PUT", "\(Self.at(pid))/takes/\(Self.escape(takeID))", raw: audio, contentType: contentType,
                           headers: ["x-take": header])
    }

    func audio(_ pid: String, takeID: String) async throws -> Data {
        try await call("GET", "\(Self.at(pid))/takes/\(Self.escape(takeID))/audio")
    }

    func choose(_ pid: String, takeID: String) async throws -> SharedRecord {
        try decode(SharedRecord.self, try await call("POST", "\(Self.at(pid))/chosen", json: Choose(take_id: takeID)))
    }

    func publish(_ pid: String) async throws -> PublishJob {
        try decode(PublishJob.self, try await call("POST", "\(Self.at(pid))/publish", json: Empty()))
    }

    func report(_ pid: String, takeID: String?, userID: String?, reason: ReportReason, note: String?) async throws {
        _ = try await call("POST", "\(Self.root)/reports",
                           json: Report(production_id: pid, take_id: takeID, user_id: userID, reason: reason.rawValue, note: note))
    }

    func block(_ userID: String) async throws {
        _ = try await call("POST", "\(Self.root)/blocks", json: Block(user_id: userID))
    }

    func classes() async throws -> PlayClasses {
        try decode(PlayClasses.self, try await call("GET", "\(Self.root)/classes"))
    }

    func createClass(name: String, under13: Bool) async throws -> PlayClass {
        try decode(PlayClass.self, try await call("POST", "\(Self.root)/classes", json: NewClass(name: name, under13: under13)))
    }

    func joinClass(code: String, displayName: String?) async throws -> PlayClass {
        try decode(PlayClass.self, try await call("POST", "\(Self.root)/classes/join",
                                                  json: JoinClass(code: code, display_name: displayName)))
    }
}
