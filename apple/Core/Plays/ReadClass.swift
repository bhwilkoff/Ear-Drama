import Foundation

// The class's side of reading together (Decision 082; docs/WORKER.md "Seats" and "Classes"): a student's seat
// (no account, a key held in memory for the app run) and the teacher's class page (seats, casting, progress).
// Every call goes through the one shared client; the teacher's calls refresh the JWT first.

nonisolated struct ReadSeatList: Codable, Equatable, Sendable {
    struct Klass: Codable, Equatable, Sendable { var id: String; var name: String }
    struct Seat: Codable, Equatable, Sendable, Identifiable { var id: String; var label: String; var taken: Bool }
    var `class`: Klass
    var seats: [Seat]
}

nonisolated struct ReadSeatClaim: Codable, Equatable, Sendable {
    var seatKey: String
    var seat: String
    enum CodingKeys: String, CodingKey { case seatKey = "seat_key", seat }
}

nonisolated struct ReadClassDetail: Codable, Equatable, Sendable {
    struct Seat: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var label: String
        var claimed: Bool
    }
    var id: String
    var name: String
    var code: String?
    var seats: [Seat]?
}

nonisolated struct ReadProgress: Codable, Equatable, Sendable {
    struct Part: Codable, Equatable, Sendable { var part: String; var lines: Int; var recorded: Int; var approved: Int; var again: Int }
    struct SeatRow: Codable, Equatable, Sendable, Identifiable {
        var seat: String
        var label: String
        var parts: [Part]
        var id: String { seat }
    }
    struct Production: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var title: String
        var seats: [SeatRow]
    }
    var productions: [Production]
}

nonisolated struct ReadClassProduction: Codable, Equatable, Sendable {
    var id: String
    var assignments: [ReadSnapshot.Assignment]?
}

nonisolated struct ReadProductionInfo: Codable, Equatable, Sendable {
    var id: String
    var scriptID: String
    var scriptRevision: String
    var assignments: [ReadSnapshot.Assignment]?
}

nonisolated protocol ReadClassWire: Sendable {
    func seatList(code: String) async throws -> ReadSeatList
    func seatClaim(code: String, seat: String, move: Bool) async throws -> ReadSeatClaim
    func detail(_ id: String) async throws -> ReadClassDetail
    func progress(_ id: String) async throws -> ReadProgress
    func production(_ pid: String) async throws -> ReadProductionInfo
    func addSeats(_ id: String, text: String) async throws
    func removeSeat(_ id: String, seat: String) async throws
    func releaseSeat(_ id: String, seat: String) async throws
    func classProduction(_ id: String, scriptID: String, revision: String, cast: [PlaysShare.CastLine]) async throws -> ReadClassProduction
    func assign(_ pid: String, assignments: [ReadCore.Assignment]) async throws -> [ReadCore.Assignment]
}

nonisolated struct WorkerReadClass: ReadClassWire {
    let api: APIClient
    private static let root = "/v1/plays"

    private static func esc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_.~"))) ?? s
    }

    private func call(_ method: String, _ path: String, json: [String: Any]? = nil, bearer: Bool = true) async throws -> Data {
        let body = json.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        let data: Data
        let status: Int
        do {
            (data, status) = bearer
                ? try await api.workerResponse(method, path: path, body: body)
                : try await api.anonWorkerResponse(method, path: path, body: body)
        } catch {
            throw ReadFailure(code: "offline")
        }
        guard 200...299 ~= status else {
            let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw ReadFailure(code: o?["error"] as? String ?? (status == 429 ? "rate_limited" : "error"))
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw ReadFailure(code: "error") }
    }

    func seatList(code: String) async throws -> ReadSeatList {
        try decode(ReadSeatList.self, try await call("POST", "\(Self.root)/seat/list", json: ["code": code], bearer: false))
    }

    func seatClaim(code: String, seat: String, move: Bool) async throws -> ReadSeatClaim {
        var body: [String: Any] = ["code": code, "seat": seat]
        if move { body["move"] = true }
        return try decode(ReadSeatClaim.self, try await call("POST", "\(Self.root)/seat/claim", json: body, bearer: false))
    }

    func detail(_ id: String) async throws -> ReadClassDetail {
        try decode(ReadClassDetail.self, try await call("GET", "\(Self.root)/classes/\(Self.esc(id))"))
    }

    func progress(_ id: String) async throws -> ReadProgress {
        try decode(ReadProgress.self, try await call("GET", "\(Self.root)/classes/\(Self.esc(id))/progress"))
    }

    func production(_ pid: String) async throws -> ReadProductionInfo {
        try decode(ReadProductionInfo.self, try await call("GET", "\(Self.root)/productions/\(Self.esc(pid))"))
    }

    func addSeats(_ id: String, text: String) async throws {
        _ = try await call("POST", "\(Self.root)/classes/\(Self.esc(id))/seats", json: ["text": text])
    }

    func removeSeat(_ id: String, seat: String) async throws {
        _ = try await call("DELETE", "\(Self.root)/classes/\(Self.esc(id))/seats/\(Self.esc(seat))")
    }

    func releaseSeat(_ id: String, seat: String) async throws {
        _ = try await call("POST", "\(Self.root)/classes/\(Self.esc(id))/seats/\(Self.esc(seat))/release", json: [:])
    }

    func classProduction(_ id: String, scriptID: String, revision: String, cast: [PlaysShare.CastLine]) async throws -> ReadClassProduction {
        let lines = cast.map { ["id": $0.id, "part": $0.part] }
        let body: [String: Any] = ["script_id": scriptID, "script_revision": revision, "cast": lines]
        return try decode(ReadClassProduction.self, try await call("POST", "\(Self.root)/classes/\(Self.esc(id))/productions", json: body))
    }

    func assign(_ pid: String, assignments: [ReadCore.Assignment]) async throws -> [ReadCore.Assignment] {
        let wire = ReadCore.toWire(assignments)
        let data = try await call("PUT", "\(Self.root)/productions/\(Self.esc(pid))/assignments", json: ["assignments": wire])
        let r = try decode(ReadClassProduction.self, data)
        return (r.assignments ?? []).map { ReadCore.Assignment(part: $0.part, seat: $0.seat, from: $0.from, to: $0.to) }
    }
}

nonisolated extension ReadCore {
    /// The casting the Worker takes: a whole part as `{ part, seat }`, a range with its `from` and `to`.
    static func toWire(_ assignments: [Assignment]) -> [[String: Any]] {
        assignments.map { a in
            var o: [String: Any] = ["part": a.part, "seat": a.seat]
            if a.from != nil || a.to != nil {
                o["from"] = a.from.map { $0 as Any } ?? NSNull()
                o["to"] = a.to.map { $0 as Any } ?? NSNull()
            }
            return o
        }
    }
}

/// What the casting board needs from a script, computed once: the cast, words per line, scene starts, part facts.
nonisolated struct ReadCastingFacts: Sendable {
    let cast: [(String, String)]
    let words: [Int]
    let starts: [Int]
    let facts: [ReadCore.PartFacts]

    init(_ script: PlayScript) {
        cast = script.lines.map { ($0.id, $0.part.rawValue) }
        words = script.lines.map { $0.spokenText.split(whereSeparator: { $0.isWhitespace }).count }
        starts = ScriptReading.sectionsOf(script).filter { $0.level != .part }.map(\.index)
        facts = ReadCore.partFacts(cast: cast, words: words, starts: starts).sorted { $0.words > $1.words }
    }
}
