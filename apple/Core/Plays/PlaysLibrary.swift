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
    let store: ProductionStore

    @ObservationIgnored private let fetch: Fetch
    @ObservationIgnored private let cache: URL
    @ObservationIgnored private let bundled: @Sendable () -> CastableLibrary?

    init(store: ProductionStore = ProductionStore(),
         fetch: @escaping Fetch = { try await APIClient.shared.playsData($0) },
         cache: URL = URL.cachesDirectory.appending(path: "PlayLibrary", directoryHint: .isDirectory),
         bundled: @escaping @Sendable () -> CastableLibrary? = { CastableLibrary.load() }) {
        self.store = store
        self.fetch = fetch
        self.cache = cache
        self.bundled = bundled
    }

    func load() async {
        guard state != .ready else { return }
        let bundled = bundled, cache = cache
        let (library, cached) = await Task.detached(priority: .userInitiated) {
            (bundled(), Self.readIndex(cache))
        }.value
        scripts = library?.scripts ?? []
        if let cached {
            rows = withBundledCast(cached)
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
              let index = try? JSONDecoder().decode(PlayRowIndex.self, from: data), !index.plays.isEmpty else { return }
        rows = withBundledCast(index.plays)
        fromLibrary = true
        let cache = cache
        Task.detached(priority: .utility) { Self.write(data, to: cache.appending(path: "index.json"), in: cache) }
    }

    /// A row published before the index carried `cast` takes it from the bundle's script of the same play.
    private func withBundledCast(_ list: [PlayRow]) -> [PlayRow] {
        list.map { row in
            guard row.castIndex == nil, let bundled = script(row.id) else { return row }
            var filled = row
            filled.castIndex = bundled.castLines
            return filled
        }
    }

    /// The bundled script, when it is one of the bundle's.
    func script(_ id: String) -> PlayScript? { scripts.first { $0.id == id } }

    /// A play's whole script: the library's file for it, else the bundle's. Nil when neither has it; throws the
    /// fetch's error when the library could not be reached and the bundle does not hold the play.
    func script(id: String) async throws -> PlayScript? {
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

    /// The script a production was cast from, as stored with it.
    func castScript(for production: Production) -> PlayScript? { store.script(for: production) }

    nonisolated static func pick(_ id: String, from data: Data) -> PlayScript? {
        (try? JSONDecoder().decode(CastableLibrary.self, from: data))?.scripts.first { $0.id == id }
    }

    nonisolated private static func readIndex(_ cache: URL) -> [PlayRow]? {
        guard let data = try? Data(contentsOf: cache.appending(path: "index.json")),
              let index = try? JSONDecoder().decode(PlayRowIndex.self, from: data), !index.plays.isEmpty else { return nil }
        return index.plays
    }

    nonisolated private static func write(_ data: Data, to file: URL, in root: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
#endif
