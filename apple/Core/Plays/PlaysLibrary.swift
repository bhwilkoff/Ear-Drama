#if os(iOS) || os(macOS)
import Foundation

/// The ear dramas' state (Decision 068): the play library, the bundled castable scripts as its floor, and
/// the productions on this device. Created at launch, but it opens no audio and asks for nothing; the
/// microphone is asked for only when a performer starts recording (§2.3).
///
/// Lists read `rows`: the published library's index (contract §4.1, through the one `APIClient`, cached in
/// `Caches/PlayLibrary/`) when it loads, the bundle's scripts otherwise. A play's whole script comes from
/// `script(id:)`: the library's `scripts/<id>.json`, else the bundle, else the error the fetch gave.
@Observable
final class PlaysLibrary {
    enum State: Equatable {
        case loading
        case ready
        case unavailable
    }

    typealias Fetch = @Sendable (String) async throws -> Data?

    private(set) var state: State = .loading
    /// The scripts the bundle holds: the offline floor.
    private(set) var scripts: [PlayScript] = []
    /// Every play a list shows: the published index's rows, else the bundle's.
    private(set) var rows: [PlayRow] = []
    /// True when `rows` are the published library's.
    private(set) var fromLibrary = false
    /// The index's facets and the library's collections (contract §4.1, B31): nil in a library built before them or
    /// while only the bundle answers.
    private(set) var facets: PlayFacets?
    private(set) var collections: PlayCollections?
    let store: ProductionStore
    /// The person's own scripts on this device (PLAYS-DESIGN §13).
    let own: OwnScripts

    @ObservationIgnored private var hub: RelayHub?
    @ObservationIgnored private let fetch: Fetch
    @ObservationIgnored private let cache: URL
    @ObservationIgnored private let bundled: @Sendable () -> CastableLibrary?
    /// The Worker's reads of an own script's text (a seam so a test can stand one in).
    @ObservationIgnored var reads: any OwnScriptReads = WorkerOwnScripts(api: .shared)

    init(store: ProductionStore = ProductionStore(),
         fetch: @escaping Fetch = { try await APIClient.shared.playsData($0) },
         cache: URL = URL.cachesDirectory.appending(path: "PlayLibrary", directoryHint: .isDirectory),
         bundled: @escaping @Sendable () -> CastableLibrary? = { CastableLibrary.load() },
         own: OwnScripts? = nil) {
        self.store = store
        // Beside the productions they are cast into; a store made anywhere else keeps its scripts there too.
        let elsewhere = store.root == ProductionStore.defaultRoot ? nil : store.root.appending(path: "Scripts", directoryHint: .isDirectory)
        self.own = own ?? OwnScripts(root: elsewhere, plays: store)
        self.fetch = fetch
        self.cache = cache
        self.bundled = bundled
    }

    /// Relay across time (PLAYS-DESIGN §12.11): the one sender for the takes on this device waiting for a receiver.
    var relay: RelayHub {
        if let hub { return hub }
        let h = RelayHub(store: store)
        hub = h
        return h
    }

    func load() async {
        guard state != .ready else { return }
        let bundled = bundled, cache = cache
        let (library, cached) = await Task.detached(priority: .userInitiated) {
            (bundled(), Self.readIndex(cache))
        }.value
        scripts = library?.scripts ?? []
        if let cached {
            rows = cached.plays
            facets = cached.facets
            fromLibrary = true
            state = .ready
            Task { await refreshIndex() }
            return
        }
        await refreshIndex()
        if rows.isEmpty { rows = scripts.map(PlayRow.init) }
        state = rows.isEmpty ? .unavailable : .ready
    }

    /// Asks the site for the index; a failure or an empty index leaves the rows as they are.
    private func refreshIndex() async {
        guard let data = try? await fetch("library/index.json"),
              let index = try? JSONDecoder().decode(PlayRowIndex.self, from: data), !index.plays.isEmpty else {
            if fromLibrary, collections == nil { await loadCollections() }
            return
        }
        rows = index.plays
        facets = index.facets
        fromLibrary = true
        let cache = cache
        Task.detached(priority: .utility) { Self.write(data, to: cache.appending(path: "index.json"), in: cache) }
        await loadCollections()
    }

    /// The library's collections, read beside the index it was built with; absent in an older library.
    private func loadCollections() async {
        guard let data = try? await fetch("library/collections.json"),
              let c = try? JSONDecoder().decode(PlayCollections.self, from: data) else { return }
        collections = c
    }

    // MARK: Search (B31 §3.3): the library's own files, never an index built here

    @ObservationIgnored private var characters: PlayCharacters?
    @ObservationIgnored private var shards: [String: FindCore.Shard?] = [:]

    /// `characters.json`, read once a run; nil in an older library or the bundle.
    func characterNames() async throws -> [String: [[Int]]]? {
        guard fromLibrary else { return nil }
        if let characters { return characters.names }
        guard let data = try await fetch("library/characters.json") else { return nil }
        let c = try JSONDecoder().decode(PlayCharacters.self, from: data)
        characters = c
        return c.names
    }

    /// One shard of `search/lines/` or `search/said/`, kept for the run: nil when the library has no such directory
    /// (a 404 for the shard), [:] for a shard with no words.
    func shard(_ dir: String, _ file: String) async throws -> FindCore.Shard? {
        let key = "\(dir)/\(file)"
        if let kept = shards[key] { return kept }
        let got: FindCore.Shard? = try await fetch("library/search/\(key).json").map { try JSONDecoder().decode(FindCore.Shard.self, from: $0) }
        shards[key] = .some(got)
        return got
    }

    /// A library script read for a line search and not kept (a line search reads many and opens few), decoded off the
    /// main actor.
    nonisolated func scriptOnce(_ row: PlayRow) async throws -> PlayScript? {
        guard let path = row.path, let data = try await fetch("library/\(path)") else { return nil }
        return Self.pick(row.id, from: data)
    }

    /// True when the library's index or the bundle lists the play.
    func has(_ id: String) -> Bool { PlayScript.isOwnID(id) ? own.row(id)?.done == true : rows.contains { $0.id == id } || script(id) != nil }

    /// The bundled script, when it is one of the bundle's.
    func script(_ id: String) -> PlayScript? { scripts.first { $0.id == id } }

    /// A play's whole script: the library's file for it, else the bundle's. Nil when neither has it; throws the
    /// fetch's error when the library could not be reached and the bundle does not hold the play.
    func script(id: String) async throws -> PlayScript? {
        // A person's own script is this device's: the one seam the reader, the studio and the pages go through.
        if PlayScript.isOwnID(id) { return own.script(id) }
        if state == .loading { await load() }
        var failure: (any Error)?
        if let path = rows.first(where: { $0.id == id })?.path {
            do {
                if let data = try await fetch("library/\(path)"), let found = Self.pick(id, from: data) {
                    let file = cache.appending(path: path)
                    let root = cache
                    Task.detached(priority: .utility) { Self.write(data, to: file, in: root) }
                    return found
                }
            } catch {
                failure = error
            }
            if let data = try? Data(contentsOf: cache.appending(path: path)), let found = Self.pick(id, from: data) { return found }
        }
        if let found = script(id) { return found }
        if let failure { throw failure }
        return nil
    }

    /// A shared production's script at the revision it was cast from: the library's file or the bundle's, nil when
    /// neither holds that revision (a library-only play opens, joins and records like a bundled one).
    func script(id: String, revision: String) async -> PlayScript? {
        if let found = (try? await script(id: id)) ?? nil, found.revision == revision { return found }
        // The library may hold a newer revision than a production cast here: the bundle's is tried too.
        return script(id).flatMap { $0.revision == revision ? $0 : nil }
    }

    /// The script of a production, an invitation, a seat's part or a room (PLAYS-DESIGN §13 item 11): the one way every screen gets it,
    /// `OwnShare.scriptOf` over what this device holds. Throws `revision_mismatch`, `script_damaged` or the Worker's own refusal.
    func resolve(id: String, revision: String, who: OwnShare.Who? = nil, fit: (PlayScript) -> Bool = { _ in true }) async throws -> PlayScript {
        if state == .loading, !PlayScript.isOwnID(id) { await load() }
        let store = store, own = own
        let local = OwnShare.Local(
            catalog: { [self] id, revision in
                if let found = await script(id: id, revision: revision) { return found }
                // Neither the library nor the bundle holds that revision: say why when the library could not be reached.
                _ = try await script(id: id)
                return nil
            },
            kept: { pid in store.findShared(pid).flatMap { store.script(for: $0) } },
            mine: { id in own.script(id) })
        return try await OwnShare.scriptOf(id: id, revision: revision, who: who, fit: fit, local: local, reads: reads,
                                           link: { "https://eardrama.org/episode/\($0)" })
    }

    /// `resolve` for a door that only needs to know whether the script is there; the refusal is `PlaysShare.line`'s.
    func resolved(id: String, revision: String, who: OwnShare.Who? = nil, fit: (PlayScript) -> Bool = { _ in true }) async -> (script: PlayScript?, failure: (any Error)?) {
        do { return (try await resolve(id: id, revision: revision, who: who, fit: fit), nil) } catch { return (nil, error) }
    }

    /// The script a production was cast from, as stored with it.
    func castScript(for production: Production) -> PlayScript? { store.script(for: production) }

    nonisolated static func pick(_ id: String, from data: Data) -> PlayScript? {
        (try? JSONDecoder().decode(CastableLibrary.self, from: data))?.scripts.first { $0.id == id }
    }

    nonisolated private static func readIndex(_ cache: URL) -> PlayRowIndex? {
        guard let data = try? Data(contentsOf: cache.appending(path: "index.json")),
              let index = try? JSONDecoder().decode(PlayRowIndex.self, from: data), !index.plays.isEmpty else { return nil }
        return index
    }

    nonisolated private static func write(_ data: Data, to file: URL, in root: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
#endif
