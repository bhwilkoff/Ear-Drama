import Foundation

// Finished ear dramas (owner ruling 3, 2026-10-29: "Finished ear dramas should definitely be
// listed and credited. Why else would we record them?") and the open invite's record. The rules
// that decide what a tile, a page, and a bill say live here as pure functions, so the Mac runs them.

nonisolated enum FinishedDramas {
    /// The Worker's order, stated: newest published first, ties by id descending, never engagement.
    static func newestFirst(_ plays: [FinishedPlay]) -> [FinishedPlay] {
        plays.sorted { ($0.publishedAt, $0.id) > ($1.publishedAt, $1.id) }
    }

    /// Credits with a name: a deleted account's lines stay on the item, uncredited, never given a name.
    static func named(_ credits: [FinishedPlay.Credit]) -> [FinishedPlay.Credit] {
        credits.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// The performers by the names they chose, each once, in script order; past `limit`, "and N more".
    static func creditLine(_ credits: [FinishedPlay.Credit], limit: Int = 3) -> String {
        var seen = Set<String>()
        let names = named(credits).map(\.name).filter { seen.insert($0).inserted }
        guard names.count > limit else { return names.joined(separator: ", ") }
        return names.prefix(limit).joined(separator: ", ") + " and \(names.count - limit) more"
    }

    /// The date it was published, in the viewer's calendar.
    static func dateLine(_ play: FinishedPlay) -> String {
        Date(timeIntervalSince1970: TimeInterval(play.publishedAt) / 1000)
            .formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// The archive.org identifier an item's page names.
    static func identifier(_ archiveURL: String) -> String? {
        guard let url = URL(string: archiveURL), url.host?.hasSuffix("archive.org") == true,
              let last = url.pathComponents.last, last != "/" else { return nil }
        return last
    }

    /// The item's line files in script order: the sequence-numbered WAV and FLAC originals, never a derivative.
    static func lineFiles(metadata: Data, identifier: String) -> [URL] {
        struct Meta: Decodable {
            struct File: Decodable { let name: String }
            let files: [File]?
        }
        guard let meta = try? JSONDecoder().decode(Meta.self, from: metadata) else { return [] }
        return (meta.files ?? []).map(\.name)
            .filter { $0.range(of: #"^\d{4}-.+\.(wav|flac)$"#, options: .regularExpression) != nil }
            .sorted()
            .compactMap { name in
                var c = URLComponents(string: "https://archive.org/download/\(identifier)/")
                c?.path += name
                return c?.url
            }
    }
}

nonisolated enum InviteRules {
    /// Any open part may be taken while no part records (C7).
    static func canTake(_ part: OpenInvite.Part, in inv: OpenInvite) -> Bool {
        part.status == .open && !inv.parts.contains { $0.status == .recording }
    }
}

extension OpenInvite {
    /// The same play as the signed-in record, so the listen plan and the parts read one shape. No
    /// account id leaves the Worker, so none is here.
    var record: SharedRecord {
        var partMap: [String: SharedRecord.Part] = [:]
        for p in parts { partMap[p.id] = SharedRecord.Part(status: p.status, performer: p.performer) }
        return SharedRecord(
            id: id, scriptID: scriptID, scriptRevision: scriptRevision, title: title, parts: partMap,
            takes: takes.map {
                SharedRecord.Take(id: $0.id, lineID: $0.lineID, part: $0.part, frames: $0.frames, sampleRate: $0.sampleRate)
            },
            chosen: chosen, next: next)
    }

    /// A part holder's chosen takes in line order, to hear that part alone.
    func takeIDs(forPart part: String) -> [String] {
        chosen.sorted { $0.key < $1.key }.map(\.value).filter { id in takes.contains { $0.id == id && $0.part == part } }
    }
}

/// The finished list the Worker serves, kept for the three places that show it. Loads a page at a
/// time; a failure keeps what was already read.
@Observable
final class FinishedStore {
    enum Phase: Equatable { case idle, loading, ready, failed(String) }

    static let shared = FinishedStore()
    static let pageSize = 24

    private(set) var plays: [FinishedPlay] = []
    private(set) var phase: Phase = .idle
    private(set) var nextCursor: String?
    private(set) var loadingMore = false

    @ObservationIgnored private let fetch: (Int, String?) async throws -> FinishedPage

    init(fetch: @escaping (Int, String?) async throws -> FinishedPage = { limit, cursor in
        try await WorkerOpenPlays(api: .shared).finished(limit: limit, cursor: cursor)
    }) {
        self.fetch = fetch
    }

    var hasMore: Bool { nextCursor != nil }

    /// Reads the first page. A call while one is in flight, or after one succeeded, does nothing unless `force`.
    func load(force: Bool = false) async {
        if phase == .loading || (phase == .ready && !force) { return }
        phase = .loading
        do {
            let page = try await fetch(Self.pageSize, nil)
            plays = FinishedDramas.newestFirst(page.productions)
            nextCursor = page.nextCursor
            phase = .ready
        } catch {
            phase = .failed(PlaysShare.line(error))
        }
    }

    func more() async {
        guard let cursor = nextCursor, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        guard let page = try? await fetch(Self.pageSize, cursor) else { return }
        let known = Set(plays.map(\.id))
        plays = FinishedDramas.newestFirst(plays + page.productions.filter { !known.contains($0.id) })
        nextCursor = page.nextCursor
    }
}
