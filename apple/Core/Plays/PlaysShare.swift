import Foundation

/// Shared plays, phase 2 (LOOP-PLAN M8, PLAYS-DESIGN §11.7): a production on
/// this device, linked to its record on the Worker. No SwiftUI; the cast sheet
/// draws it and `PlaysShareTests` runs it against a stub Worker. The web's
/// `js/plays-share.js` is the same logic, function for function.
///
/// The Worker is the arbiter (C7): who holds which part, which take is chosen.
/// Nothing here decides a claim; it asks and shows the answer. Takes are
/// recorded on this device exactly as phase 1 records them, then uploaded:
/// only the chosen take of each line of a part this person holds, never one
/// the bleed check flagged (it holds the device voice, §5). A take reaches only
/// the members, so uploading asks no consent (Decision 072); the CC0 consent
/// comes before Publish, which waits for the Worker to reach archive.org. The Apple TV
/// compiles only the parts that read a record (§11.7 rule 12).
enum PlaysShare {
    /// The one line shown while the Worker cannot upload to archive.org (P6).
    static let publishWaits = "Publishing opens when the Ear Drama archive account is connected."

    /// Publish for the director of a complete play (rule 9). Whether the Worker can upload is `PlaysConsent.publishes`.
    static func canPublish(_ rec: SharedRecord, _ script: PlayScript, _ me: String?) -> Bool {
        me != nil && rec.director == me && rec.archive == nil && complete(rec, script)
    }

    /// Members who hold a chosen take: each consents for their own recording (Decision 059).
    static func performers(_ rec: SharedRecord) -> [SharedRecord.Member] {
        rec.members.filter { $0.performer == true }
    }

    /// A performer who is not the director, in a complete play, who has not agreed yet.
    static func needsMyConsent(_ rec: SharedRecord, _ script: PlayScript, _ me: String?) -> Bool {
        guard let me, rec.archive == nil, rec.director != me, complete(rec, script) else { return false }
        return performers(rec).contains { $0.userID == me && $0.consented != true }
    }

    /// The performers other than the director who have not agreed: Publish waits on them.
    static func waitingOn(_ rec: SharedRecord) -> [SharedRecord.Member] {
        performers(rec).filter { $0.userID != rec.director && $0.consented != true }
    }

    #if os(iOS) || os(macOS)
    /// A performer's own agreement at the version the Worker served; nothing is queued.
    static func agree(api: any PlaysTransport, store: ProductionStore, localID: String, pid: String,
                      consent: PlaysConsent) async throws {
        guard consent.publishes == true else { throw PlaysRefusal.code("publish_waits") }
        try await api.agree(pid, version: consent.version)
        try store.setShare(localID, ProductionShare(pid: pid, consented: consent.version))
    }

    /// Publish after the consent screen (rule 6, Decisions 059 and 072): the agreement at the
    /// version the Worker served is recorded, then the job is queued.
    static func publish(api: any PlaysTransport, store: ProductionStore, localID: String, pid: String,
                        consent: PlaysConsent) async throws -> PublishJob {
        guard consent.publishes == true else { throw PlaysRefusal.code("publish_waits") }
        try await api.agree(pid, version: consent.version)
        try store.setShare(localID, ProductionShare(pid: pid, consented: consent.version))
        return try await api.publish(pid)
    }
    #endif

    nonisolated struct CastLine: Codable, Equatable, Sendable {
        let id: String
        let part: String
    }

    /// The cast sheet the Worker checks against its manifest: every line in script order.
    static func castSheet(_ script: PlayScript) -> [CastLine] {
        script.lines.map { CastLine(id: $0.id, part: $0.part.rawValue) }
    }

    static func isMine(_ rec: SharedRecord, _ part: PartID, _ me: String?) -> Bool {
        let s = rec.part(part)
        return s.status == .recording && me != nil && s.userID == me
    }

    static func recordingPart(_ rec: SharedRecord) -> PartID? {
        rec.parts.keys.sorted().first { rec.parts[$0]?.status == .recording }.map(PartID.init(rawValue:))
    }

    static func myParts(_ rec: SharedRecord, _ me: String?) -> [PartID] {
        rec.parts.keys.sorted().map(PartID.init(rawValue:)).filter { isMine(rec, $0, me) }
    }

    /// The owner's switch (Decision 066, P1): false until the take store exists.
    static func uploadsOpen(_ rec: SharedRecord?) -> Bool { rec != nil && rec?.uploads != false }

    /// Any open part may be taken while no part records (C7).
    static func canClaim(_ rec: SharedRecord, _ part: PartID) -> Bool {
        recordingPart(rec) == nil && rec.part(part).status == .open
    }

    /// Every part done or silent and every speaking line chosen: the director may publish.
    static func complete(_ rec: SharedRecord, _ script: PlayScript) -> Bool {
        recordingPart(rec) == nil
            && rec.parts.values.allSatisfy { $0.status == .done || $0.status == .silent }
            && script.speechLineIDs.allSatisfy { rec.chosen[$0] != nil }
    }

    #if os(iOS) || os(macOS)
    /// The local record follows the Worker's parts: only this person's live
    /// claim records here (so the phase 1 recorder opens for it); done and
    /// silent come across with the performer's name; anyone else's claim is
    /// open here.
    static func mirror(_ local: Production, _ rec: SharedRecord, _ me: String?) -> Production {
        var n = local
        n.parts = [:]
        for (id, s) in rec.parts {
            let status: PartState.Status = s.status == .recording ? (s.userID == me && me != nil ? .recording : .open) : s.status
            n.parts[PartID(rawValue: id)] = PartState(status: status, performer: status == .open ? nil : s.performer)
        }
        return n
    }

    @discardableResult
    static func follow(_ store: ProductionStore, localID: String, rec: SharedRecord, me: String?) throws -> Production? {
        guard let local = store.production(localID) else { return nil }
        let n = mirror(local, rec, me)
        if n != local { try store.save(n) }
        return n
    }

    /// The chosen take of each line of a part this person holds that the
    /// Worker does not have yet, never a flagged one (§5; the Worker refuses
    /// one anyway).
    static func pending(_ local: Production, _ script: PlayScript, _ rec: SharedRecord, _ me: String?) -> [Take] {
        chosenOfMine(local, script, rec, me).filter { !$0.bleed }
    }

    /// The flagged takes `pending` leaves out: each needs a re-take with headphones.
    static func flagged(_ local: Production, _ script: PlayScript, _ rec: SharedRecord, _ me: String?) -> Int {
        chosenOfMine(local, script, rec, me).filter(\.bleed).count
    }

    private static func chosenOfMine(_ local: Production, _ script: PlayScript, _ rec: SharedRecord,
                                     _ me: String?) -> [Take] {
        let onServer = Set(rec.takes.map(\.id))
        return myParts(rec, me).flatMap { part in
            script.lines(for: part).compactMap { local.chosenTake(for: $0.id) }.filter { !onServer.contains($0.id) }
        }
    }

    /// The take's fields as the Worker reads them from `x-take` (docs/WORKER.md).
    static func metaOf(_ t: Take) -> TakeMeta {
        TakeMeta(lineID: t.lineID, part: t.part.rawValue, file: t.file, created: t.created.timeIntervalSinceReferenceDate,
                 frames: t.frames, sampleRate: t.sampleRate, capture: t.capture.rawValue, heard: t.heard,
                 peak: Double(t.peak), bleed: t.bleed, loudness: t.loudness.flatMap { $0.isFinite ? $0 : nil })
    }

    static func contentType(_ file: String) -> String {
        file.lowercased().hasSuffix(".wav") ? "audio/wav" : "audio/flac"
    }

    nonisolated struct UploadResult: Equatable, Sendable {
        enum Stop: Equatable, Sendable { case uploadsOff }
        var sent = 0
        var flagged = 0
        var stopped: Stop?
        var error: PlaysRefusal?
    }

    /// Uploads this person's pending takes to the members (Decision 072: no
    /// consent is asked; `GET /consent` is read only for the owner's switch).
    static func upload(api: any PlaysTransport, store: ProductionStore, local: Production, script: PlayScript,
                       rec: SharedRecord, me: String?) async -> UploadResult {
        var result = UploadResult(flagged: flagged(local, script, rec, me))
        let send = pending(local, script, rec, me)
        guard !send.isEmpty, let link = store.share(local.id) else { return result }
        guard uploadsOpen(rec) else {
            result.stopped = .uploadsOff
            return result
        }
        do {
            let consent = try await api.consent()
            if consent.uploads == false {
                result.stopped = .uploadsOff
                return result
            }
            for t in send {
                let bytes = try store.readTake(local.id, file: t.file)
                do {
                    try await api.upload(link.pid, takeID: t.id, audio: bytes, contentType: contentType(t.file), meta: metaOf(t))
                    result.sent += 1
                } catch {
                    let r = PlaysRefusal.from(error)
                    if r.code == "take_exists" { continue }
                    throw r
                }
            }
            // The person's own choice of take wins on the Worker too.
            let fresh = try await api.get(link.pid)
            for part in myParts(fresh, me) {
                for line in script.lines(for: part) {
                    if let mine = local.chosen[line.id], fresh.chosen[line.id] != mine, fresh.takes.contains(where: { $0.id == mine }) {
                        _ = try await api.choose(link.pid, takeID: mine)
                    }
                }
            }
        } catch {
            result.error = PlaysRefusal.from(error)
        }
        return result
    }

    /// The chosen take of each line as this device should play it: the
    /// Worker's for every line, except a line of a part this person holds,
    /// where their own choice stands until it is uploaded. A line the Worker
    /// no longer shows (blocked, reported) has none.
    static func mergedChosen(_ local: Production, _ script: PlayScript, _ rec: SharedRecord, _ me: String?) -> [String: String] {
        var out = rec.chosen
        for part in myParts(rec, me) {
            for line in script.lines(for: part) {
                if let mine = local.chosen[line.id] { out[line.id] = mine }
            }
        }
        return out
    }

    /// The other members' chosen takes this device lacks.
    static func missingHere(_ local: Production, _ rec: SharedRecord) -> [String] {
        let have = Set(local.takes.map(\.id))
        return rec.chosen.values.sorted().filter { id in !have.contains(id) && rec.takes.contains { $0.id == id } }
    }

    static func inStep(_ local: Production, _ script: PlayScript, _ rec: SharedRecord, _ me: String?) -> Bool {
        missingHere(local, rec).isEmpty && mergedChosen(local, script, rec, me) == local.chosen
    }

    /// The file an imported take is kept in, by what the audio says it is.
    static func importedFile(_ takeID: String, _ data: Data) -> String {
        let wav = data.prefix(4) == Data("RIFF".utf8)
        return "m-\(takeID).\(wav ? "wav" : "flac")"
    }

    /// Brings the chosen takes of the other members onto this device, so the
    /// phase 1 listen-through can play the whole play. Only takes the Worker
    /// shows this person arrive (blocked and reported ones never do). Returns
    /// how many arrived.
    @discardableResult
    static func bringHome(api: any PlaysTransport, store: ProductionStore, localID: String, rec: SharedRecord,
                          script: PlayScript, me: String?) async throws -> Int {
        guard let start = store.production(localID) else { return 0 }
        var add: [Take] = []
        for takeID in missingHere(start, rec) {
            guard let t = rec.takes.first(where: { $0.id == takeID }) else { continue }
            let data = try await api.audio(rec.id, takeID: takeID)
            let file = importedFile(takeID, data)
            try store.importTake(localID, file: file, data: data)
            add.append(Take(id: t.id, lineID: t.lineID, part: PartID(rawValue: t.part), file: file,
                            created: Date(timeIntervalSinceReferenceDate: t.created ?? 0), frames: t.frames,
                            sampleRate: t.sampleRate, capture: Take.Capture(rawValue: t.capture ?? "") ?? .direct,
                            heard: t.heard ?? [:], loudness: t.loudness, peak: Float(t.peak ?? 0), bleed: false))
        }
        guard var n = store.production(localID) else { return 0 }
        n.takes.append(contentsOf: add)
        let chosen = mergedChosen(n, script, rec, me)
        if chosen != n.chosen { n.listenedThrough = false }
        n.chosen = chosen
        try store.save(n)
        return add.count
    }

    /// "Share": the Worker makes the record; the caller directs it.
    static func share(api: any PlaysTransport, store: ProductionStore, local: Production, script: PlayScript,
                      displayName: String?) async throws -> SharedRecord {
        let rec = try await api.create(scriptID: script.id, revision: script.revision, cast: castSheet(script),
                                       displayName: trimmed(displayName))
        try store.setShare(local.id, ProductionShare(pid: rec.id))
        return rec
    }

    /// The production on this device for a shared one, made from the bundle's
    /// script on first open.
    static func localFor(store: ProductionStore, pid: String, script: PlayScript?) throws -> Production {
        if let local = store.findShared(pid) { return local }
        guard let script else { throw PlaysRefusal.code("revision_mismatch") }
        let local = try store.create(script)
        try store.setShare(local.id, ProductionShare(pid: pid))
        return local
    }

    /// The bundle's script for a shared production, only at the revision it was cast from.
    static func scriptFor(_ scripts: [PlayScript], id: String, revision: String) -> PlayScript? {
        scripts.first { $0.id == id && $0.revision == revision }
    }

    /// Joins by an invite and claims `part`; makes the production on this
    /// device on the first join. The script is checked first, so a revision
    /// the bundle lacks claims nothing.
    static func join(api: any PlaysTransport, store: ProductionStore, token: String, part: PartID, displayName: String?,
                     script: PlayScript?) async throws -> (SharedRecord, Production) {
        guard script != nil else { throw PlaysRefusal.code("revision_mismatch") }
        let rec = try await api.joinByInvite(token, part: part, displayName: trimmed(displayName))
        return (rec, try localFor(store: store, pid: rec.id, script: script))
    }

    nonisolated struct LibraryRow: Identifiable, Equatable, Sendable {
        var local: Production?
        var pid: String?
        var remote: RemoteProduction?
        var id: String { local?.id ?? pid ?? "" }
        var title: String { local?.title ?? remote?.title ?? "" }
    }

    /// Library's Ear dramas (Decision 068): this device's productions, then the
    /// shared ones this person is in that this device has not opened yet,
    /// newest first.
    static func libraryRows(_ store: ProductionStore, remote: [RemoteProduction]) -> [LibraryRow] {
        var rows = store.productions.map { LibraryRow(local: $0, pid: store.share($0.id)?.pid) }
        let here = Set(rows.compactMap(\.pid))
        for r in remote where !here.contains(r.id) { rows.append(LibraryRow(pid: r.id, remote: r)) }
        func when(_ r: LibraryRow) -> Double {
            if let local = r.local { return local.created.timeIntervalSince1970 }
            return Double(r.remote?.updatedAt ?? 0) / 1000
        }
        return rows.sorted { when($0) > when($1) }
    }
    #endif

    // MARK: Invite links (DEEP_LINKS.md): the token rides the fragment, so it never reaches a server log

    static func inviteLink(_ token: String, origin: String = "https://eardrama.org") -> URL {
        var root = origin
        while root.hasSuffix("/") { root.removeLast() }
        return URL(string: "\(root)/invite#\(token)")!
    }

    /// "Works for N days.": whole days left on an invite, at least one.
    static func inviteDays(_ invite: MadeInvite, now: Date = .now) -> Int {
        max(1, Int((Double(invite.expiresAt) / 1000 - now.timeIntervalSince1970) / 86_400 + 0.5))
    }

    /// The invite token a link carries (`DeepLink.inviteToken`).
    static func inviteToken(_ url: URL) -> String? { DeepLink.inviteToken(url) }

    // MARK: One plain line for each refusal (AGENTS.md: a refusal, a warning, or a fact)

    static let lines: [String: String] = [
        "storage_not_configured": "Uploads are off.",
        "uploads_off": "Uploads are off.",
        "not_open": "This part is taken.",
        "no_such_part": "This part is not in the play.",
        "line_is_another_part": "This part is not yours to record.",
        "unsupported_audio": "A take could not be read.",
        "audio_mismatch": "A take could not be read.",
        "bleed_flagged": "A take holds the device voice. Re-take it with headphones.",
        "publish_waits": publishWaits,
        "consent_version_mismatch": "The consent changed. Read it again.",
        "not_your_claim": "This part is not yours to record.",
        "not_your_part": "Only its performer or the director can open this part.",
        "speaking_part_needs_a_voice": "A speaking part needs a voice.",
        "not_finished": "This part is not finished.",
        "invite_not_found": "This invite does not work.",
        "not_found": "This production is not shared with you.",
        "no_such_take": "This take is not available.",
        "incomplete": "Every part must be done or left silent first.",
        "reported_take": "A chosen take has been reported.",
        "consent_missing": "Not every performer has agreed to the consent.",
        "school_consent_required": "This class needs its school's consent before anyone can join.",
        "class_not_found": "No class has that code.",
        "you_teach_this_class": "You teach this class.",
        "revision_mismatch": "This play has changed since it was cast.",
        "not_castable": "This play cannot be shared.",
        "cast_mismatch": "This play cannot be shared.",
        "production_full": "This production is full.",
        "too_many_productions": "You have too many shared productions.",
        "too_many_takes": "This line has too many takes.",
        "take_too_long": "A take is too long.",
        "too_large": "A take is too long.",
        "director_only": "Only the director can do that.",
        "name_too_long": "That name is too long.",
        "name_has_link": "A name cannot hold a link.",
        "name_not_allowed": "That name is not allowed.",
        "name_reserved": "That name is not allowed.",
        "bad_name": "That name is not allowed.",
        "rate_limited": "Too many tries. Try again in a minute.",
    ]

    static func line(_ error: (any Error)?) -> String {
        guard let error else { return "" }
        let r = PlaysRefusal.from(error)
        switch r.code {
        case "another_part_is_recording":
            return "\(PartID(rawValue: r.detail ?? "").title) is still recording."
        case "lines_missing":
            let n = r.detailCount ?? 0
            return n == 1 ? "1 line still needs a take." : "\(n) lines still need a take."
        default:
            if let code = r.code, let text = lines[code] { return text }
        }
        if r.status == 429 { return lines["rate_limited"]! }
        return switch r.kind {
        case .notConfigured: "Not available yet."
        case .unauthorized: "Sign in again."
        case .refused, .unreachable: "Ear Drama could not be reached."
        }
    }

    private static func trimmed(_ name: String?) -> String? {
        let t = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
