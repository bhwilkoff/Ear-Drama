#if os(iOS) || os(macOS)
import Foundation

/// The screens' side of shared plays (PLAYS-DESIGN §11.7): the Worker's record
/// of each shared production on this device, the invitation being looked at,
/// and the person's classes. Every verb is
/// `PlaysShare`'s; this only keeps what the Worker answered and the one line
/// a refusal shows.
@Observable
final class SharedPlays {
    private(set) var records: [String: SharedRecord] = [:]
    /// The one line per production (keyed by the local id) a refusal shows.
    private(set) var refusals: [String: String] = [:]
    private(set) var remote: [RemoteProduction] = []
    private(set) var classes: PlayClasses?
    private(set) var classRefusal: String?
    private(set) var invitation: InviteView?
    private(set) var invitationRefusal: String?
    private(set) var lastInvite: [String: MadeInvite] = [:]
    private(set) var queued: Set<String> = []
    /// Lines removed from the archive.org item in this run, as "pid line"; the record carries no per-line state.
    private(set) var removed: Set<String> = []
    private(set) var busy: Set<String> = []

    @ObservationIgnored let api: any PlaysTransport
    @ObservationIgnored private let me: () -> String?

    init(api: any PlaysTransport = WorkerPlays(api: .shared), me: @escaping () -> String? = { APIClient.shared.storedSession()?.userId }) {
        self.api = api
        self.me = me
    }

    var userID: String? { me() }

    func record(for local: Production, in store: ProductionStore) -> SharedRecord? {
        store.share(local.id).flatMap { records[$0.pid] }
    }

    func refusal(_ localID: String) -> String? { refusals[localID] }

    // MARK: The production

    /// Reads the Worker's record, follows its parts, and fetches the other
    /// members' chosen takes (§11.7 rule 7), so Listen Through is phase 1's.
    func refresh(_ localID: String, store: ProductionStore, script: PlayScript) async {
        guard let pid = store.share(localID)?.pid else { return }
        await run(localID) {
            let rec = try await self.api.get(pid)
            self.records[pid] = rec
            try PlaysShare.follow(store, localID: localID, rec: rec, me: self.me())
            if let local = store.production(localID), !PlaysShare.inStep(local, script, rec, self.me()) {
                try await PlaysShare.bringHome(api: self.api, store: store, localID: localID, rec: rec, script: script,
                                               me: self.me())
            }
        }
    }

    func share(_ local: Production, script: PlayScript, store: ProductionStore, name: String?) async {
        await run(local.id) {
            let rec = try await PlaysShare.share(api: self.api, store: store, local: local, script: script, displayName: name)
            self.records[rec.id] = rec
            try PlaysShare.follow(store, localID: local.id, rec: rec, me: self.me())
        }
    }

    func invite(_ localID: String, store: ProductionStore) async {
        guard let pid = store.share(localID)?.pid else { return }
        await run(localID) { self.lastInvite[localID] = try await self.api.invite(pid) }
    }

    /// Take Part, Leave Silent, Done with This Part, Release, Open Part.
    func act(_ localID: String, part: PartID, action: String?, store: ProductionStore) async {
        guard let pid = store.share(localID)?.pid else { return }
        await run(localID) {
            let rec = if let action { try await self.api.partAction(pid, part: part, action: action) }
                      else { try await self.api.claim(pid, part: part) }
            self.records[pid] = rec
            try PlaysShare.follow(store, localID: localID, rec: rec, me: self.me())
        }
    }

    func upload(_ localID: String, store: ProductionStore, script: PlayScript) async {
        guard let local = store.production(localID), let pid = store.share(localID)?.pid,
              let rec = records[pid] else { return }
        busy.insert(localID)
        defer { busy.remove(localID) }
        let result = await PlaysShare.upload(api: api, store: store, local: local, script: script, rec: rec, me: me())
        refusals[localID] = switch result.stopped {
        case .uploadsOff: PlaysShare.line(PlaysRefusal.code("uploads_off"))
        case nil: result.error.map(PlaysShare.line)
        }
        if result.sent > 0 { await refresh(localID, store: store, script: script) }
    }

    /// The Worker's consent words and whether it can reach archive.org; nil when it cannot be read.
    func consent() async -> PlaysConsent? { try? await api.consent() }

    func agree(_ localID: String, store: ProductionStore, script: PlayScript, consent: PlaysConsent) async {
        guard let pid = store.share(localID)?.pid else { return }
        await run(localID) {
            try await PlaysShare.agree(api: self.api, store: store, localID: localID, pid: pid, consent: consent)
        }
        await refresh(localID, store: store, script: script)
    }

    func publish(_ localID: String, store: ProductionStore, script: PlayScript, consent: PlaysConsent) async {
        guard let pid = store.share(localID)?.pid, let rec = records[pid],
              PlaysShare.canPublish(rec, script, me()) else { return }
        await run(localID) {
            _ = try await PlaysShare.publish(api: self.api, store: store, localID: localID, pid: pid, consent: consent)
            self.queued.insert(pid)
        }
        await refresh(localID, store: store, script: script)
    }

    /// Publish again after a failure: the director's agreement stands, so the Worker is simply asked again.
    func publishAgain(_ localID: String, store: ProductionStore, script: PlayScript) async {
        guard let pid = store.share(localID)?.pid, let rec = records[pid],
              PlaysShare.canPublishAgain(rec, me()) else { return }
        await run(localID) { _ = try await self.api.publish(pid) }
        await refresh(localID, store: store, script: script)
    }

    /// Remove a line from the published item (P12): "withdrawn" for a performer's own, a report reason for the director's.
    func removeLine(_ localID: String, lineID: String, reason: String, store: ProductionStore) async {
        guard let pid = store.share(localID)?.pid else { return }
        await run(localID) {
            try await self.api.removeLine(pid, lineID: lineID, reason: reason)
            self.removed.insert("\(pid) \(lineID)")
        }
    }

    func report(_ localID: String, store: ProductionStore, takeID: String?, userID: String?, reason: ReportReason,
                note: String, script: PlayScript) async {
        guard let pid = store.share(localID)?.pid else { return }
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        await run(localID) {
            try await self.api.report(pid, takeID: takeID, userID: userID, reason: reason, note: text.isEmpty ? nil : text)
        }
        await refresh(localID, store: store, script: script)
    }

    func block(_ localID: String, store: ProductionStore, userID: String, script: PlayScript) async {
        await run(localID) { try await self.api.block(userID) }
        await refresh(localID, store: store, script: script)
    }

    // MARK: Library: remote productions, the invitation, classes

    func loadRemote() async {
        remote = (try? await api.list()) ?? remote
    }

    /// Opens a shared production this device has not opened: the record, then
    /// the bundle's script at its revision, then the production here.
    func open(_ pid: String, plays: PlaysLibrary) async -> Production? {
        do {
            let rec = try await api.get(pid)
            records[pid] = rec
            let script = PlaysShare.scriptFor(plays.scripts, id: rec.scriptID, revision: rec.scriptRevision)
            let local = try PlaysShare.localFor(store: plays.store, pid: pid, script: script)
            try PlaysShare.follow(plays.store, localID: local.id, rec: rec, me: me())
            invitationRefusal = nil
            return local
        } catch {
            invitationRefusal = PlaysShare.line(error)
            return nil
        }
    }

    func viewInvitation(_ token: String, plays: PlaysLibrary) async {
        do {
            let view = try await api.viewInvite(token)
            invitation = view
            invitationRefusal = PlaysShare.scriptFor(plays.scripts, id: view.scriptID, revision: view.scriptRevision) == nil
                ? PlaysShare.line(PlaysRefusal.code("revision_mismatch")) : nil
        } catch {
            invitation = nil
            invitationRefusal = PlaysShare.line(error)
        }
    }

    func join(_ token: String, part: PartID, name: String, plays: PlaysLibrary) async -> Production? {
        guard let view = invitation else { return nil }
        let script = PlaysShare.scriptFor(plays.scripts, id: view.scriptID, revision: view.scriptRevision)
        do {
            let (rec, local) = try await PlaysShare.join(api: api, store: plays.store, token: token, part: part,
                                                         displayName: name, script: script)
            records[rec.id] = rec
            try PlaysShare.follow(plays.store, localID: local.id, rec: rec, me: me())
            dropInvitation()
            return local
        } catch {
            invitationRefusal = PlaysShare.line(error)
            return nil
        }
    }

    func dropInvitation() {
        invitation = nil
        invitationRefusal = nil
    }

    func loadClasses() async {
        do {
            classes = try await api.classes()
            classRefusal = nil
        } catch {
            classRefusal = PlaysShare.line(error)
        }
    }

    func makeClass(_ name: String, under13: Bool) async {
        do {
            _ = try await api.createClass(name: name.trimmingCharacters(in: .whitespacesAndNewlines), under13: under13)
            await loadClasses()
        } catch {
            classRefusal = PlaysShare.line(error)
        }
    }

    func joinClass(_ code: String) async {
        do {
            _ = try await api.joinClass(code: code, displayName: nil)
            await loadClasses()
        } catch {
            classRefusal = PlaysShare.line(error)
        }
    }

    /// A teacher's class code in two groups of four (§11.7 rule 10).
    static func grouped(_ code: String) -> String {
        code.count == 8 ? "\(code.prefix(4)) \(code.suffix(4))" : code
    }

    private func run(_ localID: String, _ work: () async throws -> Void) async {
        busy.insert(localID)
        defer { busy.remove(localID) }
        do {
            try await work()
            refusals[localID] = nil
        } catch {
            refusals[localID] = PlaysShare.line(error)
        }
    }
}
#endif
