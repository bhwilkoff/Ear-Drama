import Foundation
import Testing

/// Plays that need no account (owner, 2026-10-29): the open invite read and the finished
/// listing, against a stubbed Worker shaped like worker/src/plays-open.js. Nothing here
/// reaches a network.

nonisolated final class OpenStub: URLProtocol, @unchecked Sendable {
    struct Seen: Sendable { let method: String; let path: String; let query: String?; let bearer: String?; let invite: String? }
    nonisolated(unsafe) static var seen: [Seen] = []
    nonisolated(unsafe) static var answer: @Sendable (URLRequest) -> (Int, Data) = { _ in (404, Data()) }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        Self.seen.append(Seen(method: request.httpMethod ?? "GET", path: request.url!.path, query: request.url!.query,
                              bearer: request.value(forHTTPHeaderField: "Authorization"),
                              invite: request.value(forHTTPHeaderField: "x-invite")))
        let (status, data) = Self.answer(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

private nonisolated func json(_ object: Any) -> Data { (try? JSONSerialization.data(withJSONObject: object)) ?? Data() }

@Suite(.serialized)
struct OpenPlaysTests {
    private let plays: WorkerOpenPlays
    private let vault = MemoryVault()

    init() {
        OpenStub.seen = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenStub.self]
        let api = APIClient(config: AccountConfig(workerURL: "https://worker.test", googleClientID: nil),
                            vault: vault, session: URLSession(configuration: configuration))
        plays = WorkerOpenPlays(api: api)
    }

    private let invite: [String: Any] = [
        "id": "P1", "scriptID": "s1", "scriptRevision": "r1", "title": "A Play", "source": "https://example.test/s1",
        "parts": [["id": "role:HAMLET", "lineCount": 3, "status": "recording", "performer": "Pat"],
                  ["id": "role:OPHELIA", "lineCount": 2, "status": "open"]],
        "members": [["name": "Pat", "director": true]],
        "takes": [["id": "T1", "lineID": "L1", "part": "role:HAMLET", "frames": 4800, "sampleRate": 48000.0,
                   "audio": "/v1/plays/open/invite/takes/T1/audio"]],
        "chosen": ["L1": "T1"], "next": "role:OPHELIA", "archive": NSNull(), "expires_at": 1_800_000_000_000,
    ]

    @Test func anInviteIsReadSignedOutWithNoBearerAndTheTokenInAHeader() async throws {
        let body = json(invite)
        OpenStub.answer = { _ in (200, body) }
        let v = try await plays.openInvite("TOKEN-0123456789012345")
        #expect(v.title == "A Play")
        #expect(v.parts.map(\.status) == [.recording, .open])
        #expect(v.parts[0].performer == "Pat")
        #expect(v.members == [.init(name: "Pat", director: true)])
        #expect(v.takes.first?.audio == "/v1/plays/open/invite/takes/T1/audio")
        #expect(v.chosen == ["L1": "T1"])
        #expect(v.next == "role:OPHELIA")
        #expect(OpenStub.seen.count == 1)
        #expect(OpenStub.seen[0].bearer == nil)
        #expect(OpenStub.seen[0].invite == "TOKEN-0123456789012345")
        #expect(OpenStub.seen[0].path == "/v1/plays/open/invite")
        #expect(OpenStub.seen[0].query == nil)
        #expect(vault.load() == nil)
    }

    @Test func aTakePlaysWithTheSameHeader() async throws {
        OpenStub.answer = { _ in (200, Data([1, 2, 3, 4])) }
        let data = try await plays.audio("TOKEN-0123456789012345", takeID: "T 1")
        #expect(data.count == 4)
        #expect(OpenStub.seen[0].path == "/v1/plays/open/invite/takes/T 1/audio")
        #expect(OpenStub.seen[0].invite == "TOKEN-0123456789012345")
        #expect(OpenStub.seen[0].bearer == nil)
    }

    @Test func aRevokedOrExpiredInviteIsGoneAndAnUnknownOneIsNot() async throws {
        let goneBody = json(["error": "invite_gone"])
        OpenStub.answer = { _ in (410, goneBody) }
        do {
            _ = try await plays.openInvite("TOKEN-0123456789012345")
            Issue.record("a 410 should throw")
        } catch let refusal as PlaysRefusal {
            #expect(refusal.isGone)
            #expect(refusal.code == "invite_gone")
        }
        let missingBody = json(["error": "invite_not_found"])
        OpenStub.answer = { _ in (404, missingBody) }
        do {
            _ = try await plays.openInvite("TOKEN-0123456789012345")
            Issue.record("a 404 should throw")
        } catch let refusal as PlaysRefusal {
            #expect(!refusal.isGone)
            #expect(refusal.code == "invite_not_found")
        }
    }

    @Test func theFinishedListingPagesByCursorAndKeepsTheDeletedCreditUnnamed() async throws {
        let page: [String: Any] = [
            "productions": [[
                "id": "F1", "script_id": "s1", "title": "A Play", "source": NSNull(),
                "credits": [["part": "role:HAMLET", "name": "Pat"], ["part": "role:OPHELIA", "name": ""]],
                "archive_url": "https://archive.org/details/eardrama-F1", "published_at": 1_800_000_000_000,
            ]],
            "next_cursor": "1800000000000:F1",
        ]
        let pageBody = json(page)
        OpenStub.answer = { _ in (200, pageBody) }
        let first = try await plays.finished(limit: 20)
        #expect(first.productions.map(\.id) == ["F1"])
        #expect(first.productions[0].credits == [.init(part: "role:HAMLET", name: "Pat"), .init(part: "role:OPHELIA", name: "")])
        #expect(first.productions[0].source == nil)
        #expect(first.productions[0].publishedAt == 1_800_000_000_000)
        #expect(first.nextCursor == "1800000000000:F1")
        _ = try await plays.finished(limit: 20, cursor: first.nextCursor)
        #expect(OpenStub.seen[0].path == "/v1/plays/finished")
        #expect(OpenStub.seen[0].query == "limit=20")
        #expect(OpenStub.seen[1].query == "limit=20&cursor=1800000000000%3AF1")
        #expect(OpenStub.seen.allSatisfy { $0.bearer == nil && $0.method == "GET" })
    }

    @Test func oneFinishedPlayById() async throws {
        let oneBody = json(["id": "F 1", "script_id": "s1", "title": "T", "credits": [],
                            "archive_url": "https://archive.org/details/x", "published_at": 1])
        OpenStub.answer = { _ in (200, oneBody) }
        let one = try await plays.finished(id: "F 1")
        #expect(one.id == "F 1")
        #expect(OpenStub.seen[0].path == "/v1/plays/finished/F 1")
    }

    @Test func aPlaceholderWorkerIsNotConfigured() async throws {
        let api = APIClient(config: AccountConfig(workerURL: nil, googleClientID: nil), vault: vault)
        do {
            _ = try await WorkerOpenPlays(api: api).finished()
            Issue.record("should throw")
        } catch let refusal as PlaysRefusal {
            #expect(refusal.kind == .notConfigured)
        }
    }
}
