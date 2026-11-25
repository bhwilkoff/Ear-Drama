import CryptoKit
import Foundation

/// An own script shared (PLAYS-DESIGN §13 items 11 to 16, docs/WORKER.md "Own scripts"): the Swift twin of js/plays-share.js's
/// own-script half. No SwiftUI, no file, no network of its own: the Worker's reads come through `OwnScriptReads` and the device's
/// copies through closures, so `OwnShareTests` runs every rule against a stub.
///
/// The Worker keeps an own script's text and never parses it. Every device that reads it therefore proves it first: its SHA-256
/// is the revision, its bytes are the canonical ones, the core keeps it, and it matches the cast sheet the door already holds
/// (`arrived`). Nothing that did not arrive whole is drawn; the one resolver (`scriptOf`) is the only way any screen gets a script.
nonisolated enum OwnShare {
    // MARK: What the Worker names

    /// `x-script`: what the text says of itself.
    struct Meta: Equatable, Sendable {
        var id: String
        var revision: String
        var title: String
        var episodeID: String?
    }

    struct Arrival: Sendable {
        var bytes: Data
        var meta: Meta?
        init(bytes: Data, meta: Meta?) { self.bytes = bytes; self.meta = meta }
    }

    /// Who asks, and so which route answers: a member, a holder of an invite, a class's seat, a member of a room.
    enum Who: Equatable, Sendable {
        case member(pid: String)
        case invite(token: String)
        case seat(key: String, pid: String)
        case room(code: String, key: String)

        /// The production this device already holds for the door, if the door names one.
        var pid: String? {
            switch self {
            case let .member(pid), let .seat(_, pid): pid
            case .invite, .room: nil
            }
        }
    }

    // MARK: The record's own_script

    struct Own: Equatable, Sendable, Codable {
        /// `owed` until the director sends it, `kept`, or `removed`.
        var state: String
        var by: String?
        var episodeID: String?

        enum CodingKeys: String, CodingKey { case state, by, episodeID = "episode_id" }
    }

    struct State: Equatable, Sendable {
        var state: String
        /// The owner removed it: nobody takes a part or opens one again.
        var held: Bool
        /// This person brought it.
        var mine: Bool
        var by: String?
    }

    static func state(_ own: Own?, me: String?) -> State? {
        guard let own else { return nil }
        return State(state: own.state, held: own.state == "removed" && own.by != nil, mine: me != nil && own.by == me, by: own.by)
    }

    /// Whether the record's script may be published at all (Decision 088): false for an own script, always.
    static func publishable(_ rec: SharedRecord) -> Bool { rec.publishable != false }

    /// Why Publish is absent, in the place it would be (PLAYS-DESIGN §13 item 16); nil when it may be offered.
    @MainActor static func neverPublishes(_ rec: SharedRecord) -> String? {
        publishable(rec) ? nil : PlayScript.isOwnID(rec.scriptID) ? "This script can\u{2019}t be published." : PlaysShare.lines["script_not_publishable"]
    }

    static let readers = "Only people you invite can read this script."
    static let classReaders = "Only this class can read this script."
    static let invitedReaders = "Only people invited can read this script."
    static let notSent = "The script was not sent."

    /// Who can read a shared own script, in the one line that says so (item 11).
    static func readersLine(_ rec: SharedRecord, me: String?) -> String {
        rec.classID != nil ? classReaders : rec.director == me ? readers : invitedReaders
    }

    // MARK: Sending

    /// The Worker's refusals that may pass by themselves: no answer, its own trouble, too many asks, signed out.
    static func passes(_ error: any Error) -> Bool {
        let r = PlaysRefusal.from(error)
        if r.kind == .unauthorized || r.status == 429 { return true }
        return !(400...499 ~= r.status)
    }

    /// The lines as they are hashed and sent: keys sorted, nothing escaped that need not be. Nil when they do not come to the
    /// script's own revision, which a script this device built always does.
    static func canonicalLines(_ script: PlayScript) -> Data? {
        let lines = OwnJSON.array(script.lines.map { l in
            if l.kind == .speech {
                return .object(["id": .string(l.id), "kind": .string("speech"), "role": l.role.map { .string($0) } ?? .null,
                                "parts": .array((l.parts ?? []).map { p in
                                    switch p {
                                    case let .say(t): .object(["say": .string(t)])
                                    case let .direction(t), let .mic(t), let .sound(t): .object(["direction": .string(t)])
                                    }
                                })])
            }
            return .object(["id": .string(l.id), "kind": .string(l.kind.rawValue), "source": .string(l.source ?? "")])
        })
        guard OwnScript.revisionOf(lines) == script.revision else { return nil }
        return Data(OwnScript.canonicalBytes(lines))
    }

    /// What makes a production on the Worker (`POST /productions`, `POST /classes/:id/productions`): an own script's carries its
    /// title and, for a cast transcript, its episode.
    struct MakeBody: Equatable, Sendable {
        var scriptID: String
        var revision: String
        var cast: [PlaysShare.CastLine]
        var own: Bool
        var title: String?
        var episodeID: String?
    }

    @MainActor static func makeBody(_ script: PlayScript) -> MakeBody {
        let own = PlayScript.isOwnID(script.id)
        return MakeBody(scriptID: script.id, revision: script.revision, cast: PlaysShare.castSheet(script), own: own,
                        title: own ? script.title : nil, episodeID: own ? script.episode : nil)
    }

    /// Sends a production's own script, once: the lines as they were hashed. A text already there is the same text.
    @MainActor static func send(_ api: any PlaysTransport, pid: String, script: PlayScript) async throws {
        guard let bytes = canonicalLines(script) else { throw PlaysRefusal.code("script_damaged", status: 0) }
        do { try await api.putScript(pid, bytes: bytes) } catch {
            if PlaysRefusal.from(error).code != "already_there" { throw error }
        }
    }

    /// `send` for a production just made: nil, or the error. From here the script is frozen (item 12); one that can never be sent
    /// takes its production with it.
    @MainActor static func sendOrUndo(_ api: any PlaysTransport, pid: String, script: PlayScript, freeze: () async -> Void) async -> (any Error)? {
        do { try await send(api, pid: pid, script: script) } catch {
            if !passes(error) { try? await api.deleteProduction(pid); return error }
            await freeze()
            return error
        }
        await freeze()
        return nil
    }

    // MARK: Arriving whole

    /// The Worker's bytes as a castable script, or `script_damaged`: their SHA-256 is the revision, they are canonical, the core
    /// keeps them, and they match the cast sheet.
    static func arrived(_ got: Arrival, id: String, revision: String, fit: (PlayScript) -> Bool,
                        link: (String) -> String) throws -> PlayScript {
        func damaged(_ why: String) -> PlaysRefusal { PlaysRefusal.code("script_damaged", status: 0, detail: why) }
        let digest = SHA256.hash(data: got.bytes).prefix(6).map { String(format: "%02x", $0) }.joined()
        guard digest == revision else { throw damaged("digest") }
        guard let tree = OwnJSON.parse(got.bytes), case .array = tree, OwnScript.canonicalBytes(tree) == [UInt8](got.bytes) else { throw damaged("text") }
        guard let meta = got.meta, meta.id == id, meta.revision == revision else { throw damaged("names") }
        let episode = meta.episodeID.flatMap { $0.isEmpty ? nil : $0 }
        let shaped = OwnScript.fromSharedLines(tree, meta: OwnMeta(id: id, title: meta.title, episodeId: episode, episodeUrl: episode.map(link)))
        if OwnScript.refusalOf(shaped) != nil { throw damaged("core") }
        guard let script = try? JSONDecoder().decode(PlayScript.self, from: Data(OwnScript.canonicalBytes(OwnScript.seal(shaped)))),
              script.revision == revision else { throw damaged("core") }
        guard fit(script) else { throw damaged("cast sheet") }
        return script
    }

    // What each door knows of the cast sheet, for a script to be held against.

    private static func sameParts(_ script: PlayScript, _ want: [(id: String, lines: Int?)]) -> Bool {
        let have = script.castParts
        return have.count == want.count && want.allSatisfy { w in have.contains { $0.id.rawValue == w.id && (w.lines == nil || $0.lineCount == w.lines) } }
    }

    private static func holdsLines(_ script: PlayScript, _ ids: [String?]) -> Bool {
        let at = Set(script.lines.map(\.id))
        return ids.allSatisfy { $0 == nil || $0 == "" || at.contains($0!) }
    }

    private static func holdsParts(_ script: PlayScript, _ ids: [String]) -> Bool {
        let at = Set(script.castParts.map(\.id.rawValue))
        return ids.allSatisfy(at.contains)
    }

    enum Fit {
        static func invite(_ inv: InviteView) -> (PlayScript) -> Bool {
            { sameParts($0, inv.parts.map { ($0.id, $0.lineCount) }) }
        }
        static func record(_ rec: SharedRecord) -> (PlayScript) -> Bool {
            { sameParts($0, rec.parts.keys.map { ($0, nil) }) && holdsLines($0, rec.takes.map(\.lineID)) }
        }
        static func room(_ snap: ReadSnapshot) -> (PlayScript) -> Bool {
            { holdsLines($0, [snap.cursor]) && holdsParts($0, Array(snap.claims.keys)) }
        }
        static func seat(_ assignments: [ReadSnapshot.Assignment]) -> (PlayScript) -> Bool {
            { holdsParts($0, assignments.map(\.part)) && holdsLines($0, assignments.flatMap { [$0.from, $0.to] }) }
        }
    }

    // MARK: The one resolver

    /// What this device holds, for the resolver to try before it asks anyone.
    struct Local {
        /// A catalog play, at a revision, from the library or the bundle (nil: neither holds it).
        var catalog: (_ id: String, _ revision: String) async throws -> PlayScript? = { _, _ in nil }
        /// The script this device's production holds for the production at `pid`.
        var kept: (_ pid: String) -> PlayScript? = { _ in nil }
        /// This device's own script at `id`.
        var mine: (_ id: String) -> PlayScript? = { _ in nil }
    }

    /// A script fetched once a page, by id and revision.
    actor Fetched {
        private var held: [String: PlayScript] = [:]
        func get(_ key: String) -> PlayScript? { held[key] }
        func put(_ key: String, _ script: PlayScript) { held[key] = script }
        func clear() { held = [:] }
        static let shared = Fetched()
    }

    /// The script of a production, an invitation, a seat's part or a room: the one way every screen gets it. A catalog play is the
    /// library's at `revision`, else the bundle's. An own script is this device's copy in the production, this device's script at that
    /// revision, then the Worker's, drawn only once it is shown to be whole (`fit`). Throws `revision_mismatch` or `script_damaged`
    /// or the Worker's own refusal; what it answers is never nil.
    @MainActor
    static func scriptOf(id: String, revision: String, who: Who? = nil, fit: (PlayScript) -> Bool = { _ in true }, local: Local,
                         reads: any OwnScriptReads, fetched: Fetched = .shared, link: (String) -> String) async throws -> PlayScript {
        guard PlayScript.isOwnID(id) else {
            if let found = try await local.catalog(id, revision) { return found }
            throw PlaysRefusal.code("revision_mismatch")
        }
        if let pid = who?.pid, let kept = local.kept(pid), kept.id == id, kept.revision == revision { return kept }
        if let mine = local.mine(id), mine.revision == revision { return mine }
        let key = "\(id)@\(revision)"
        if let held = await fetched.get(key), fit(held) { return held }
        guard let who else { throw PlaysRefusal.code("not_on_device", status: 0) }
        let script = try arrived(try await reads.read(who), id: id, revision: revision, fit: fit, link: link)
        await fetched.put(key, script)
        return script
    }

    /// A device with no `PlaysLibrary` (the Apple TV, the shared screen): the library's script or the bundle's for a catalog play, the
    /// Worker's for an own script. The same resolver, so a TV draws exactly what a phone does.
    @MainActor
    static func resolve(id: String, revision: String, who: Who? = nil, fit: (PlayScript) -> Bool = { _ in true },
                        reads: any OwnScriptReads = WorkerOwnScripts(api: .shared)) async throws -> PlayScript {
        let local = Local(catalog: { id, revision in try await LibraryScripts.script(id: id, revision: revision) })
        return try await scriptOf(id: id, revision: revision, who: who, fit: fit, local: local, reads: reads,
                                  link: { "https://eardrama.org/episode/\($0)" })
    }

    // MARK: Words

    static let lines: [String: String] = [
        "script_too_long": "This script is too long to share.",
        "scripts_full": "Sharing scripts is full.",
        "script_removed": "This script was removed.",
        "script_reported": "This script has been reported.",
        "script_damaged": "This script did not arrive whole.",
        "no_script": "This script has not been sent yet.",
        "bad_script_id": "This script cannot be shared.",
        "not_on_device": "This script is not on this device.",
        "needs_account": "Sharing needs an account.",
    ]

    private static let scriptCodes: Set<String> = Set(lines.keys).union(["too_many_scripts", "revision_mismatch", "script_not_publishable"])

    /// The refusals an own script's sharing can meet, for screens whose other words are `ReadCore`'s; "" for any other.
    @MainActor static func scriptLine(_ error: (any Error)?) -> String {
        guard let error else { return "" }
        let r = PlaysRefusal.from(error)
        guard let code = r.code else { return "" }
        if scriptCodes.contains(code) || (code == "bad_name" && r.detail != nil) { return line(error) }
        return ""
    }

    @MainActor static func line(_ error: any Error) -> String { PlaysShare.line(error) }
}

nonisolated protocol OwnScriptReads: Sendable {
    func read(_ who: OwnShare.Who) async throws -> OwnShare.Arrival
}

nonisolated extension OwnJSON {
    /// Strict JSON as plain data; nil for anything that is not whole JSON. Booleans and whole numbers keep their kinds.
    static func parse(_ data: Data) -> OwnJSON? {
        guard let any = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        return from(any)
    }

    private static func from(_ v: Any) -> OwnJSON? {
        switch v {
        case is NSNull: return .null
        case let s as String: return .string(s)
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            return Double(n.intValue) == n.doubleValue ? .int(n.intValue) : nil
        case let a as [Any]:
            var out: [OwnJSON] = []
            for x in a { guard let y = from(x) else { return nil }; out.append(y) }
            return .array(out)
        case let o as [String: Any]:
            var out: [String: OwnJSON] = [:]
            for (k, x) in o { guard let y = from(x) else { return nil }; out[k] = y }
            return .object(out)
        default: return nil
        }
    }
}
