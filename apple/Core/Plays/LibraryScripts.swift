import Foundation

/// A play's whole script on any Apple platform, from the published library (contract §4.1) first and the bundle's
/// scripts after it. `PlaysLibrary` does this for the iOS and macOS screens that hold one; the shared screen
/// (`ReadScreenBody`), the Apple TV (which has no `PlaysLibrary`) and a finished drama's page read through here, so a
/// play only the library holds draws in each. The cache is the one `PlaysLibrary` writes.
nonisolated enum LibraryScripts {
    typealias Fetch = @Sendable (String) async throws -> Data?

    static let defaultCache = URL.cachesDirectory.appending(path: "PlayLibrary", directoryHint: .isDirectory)

    /// The play with this id. With a `revision`, only that revision (the library's file, else the bundle's, which may be the
    /// older one): nil when neither holds it, which the caller says as "This play has changed". Nil too when no one has
    /// the play; throws the fetch's error when the library could not be reached and the bundle does not hold it.
    static func script(id: String, revision: String? = nil,
                       fetch: Fetch = { try await APIClient.shared.playsData($0) },
                       cache: URL = defaultCache,
                       bundled: @Sendable () -> [PlayScript] = { CastableLibrary.load()?.scripts ?? [] }) async throws -> PlayScript? {
        var failure: (any Error)?
        var found: PlayScript?
        let index = await readIndex(fetch: fetch, cache: cache, failure: &failure)
        if let path = index?.first(where: { $0.id == id })?.path {
            do {
                if let data = try await fetch("library/\(path)"), let picked = pick(id, from: data) {
                    found = picked
                    let file = cache.appending(path: path)
                    Task.detached(priority: .utility) { write(data, to: file) }
                }
            } catch {
                failure = error
            }
            if found == nil, let data = try? Data(contentsOf: cache.appending(path: path)) { found = pick(id, from: data) }
        }
        let floor = bundled().first { $0.id == id }
        if let revision {
            if let found, found.revision == revision { return found }
            if let floor, floor.revision == revision { return floor }
            if found != nil || floor != nil { return nil }
        } else if let best = found ?? floor {
            return best
        }
        if let failure { throw failure }
        return nil
    }

    private static func readIndex(fetch: Fetch, cache: URL, failure: inout (any Error)?) async -> [PlayRow]? {
        do {
            if let data = try await fetch("library/index.json"),
               let index = try? JSONDecoder().decode(PlayRowIndex.self, from: data), !index.plays.isEmpty {
                let file = cache.appending(path: "index.json")
                Task.detached(priority: .utility) { write(data, to: file) }
                return index.plays
            }
        } catch {
            failure = error
        }
        guard let data = try? Data(contentsOf: cache.appending(path: "index.json")),
              let index = try? JSONDecoder().decode(PlayRowIndex.self, from: data), !index.plays.isEmpty else { return nil }
        return index.plays
    }

    /// A play as the published library last gave it, from the cache `PlaysLibrary` and `script` write, with no network and no wait:
    /// for a tile that draws a label from its parts. Nil before the library has been read; the bundle is the caller's floor.
    static func cachedScript(id: String, cache: URL = defaultCache) -> PlayScript? {
        guard let data = try? Data(contentsOf: cache.appending(path: "index.json")),
              let index = try? JSONDecoder().decode(PlayRowIndex.self, from: data),
              let path = index.plays.first(where: { $0.id == id })?.path,
              let file = try? Data(contentsOf: cache.appending(path: path)) else { return nil }
        return pick(id, from: file)
    }

    /// One play at random from the published library, else the bundle's: the Apple TV's Surprise draws from what people can read.
    static func random(fetch: Fetch = { try await APIClient.shared.playsData($0) }, cache: URL = defaultCache,
                       bundled: @Sendable () -> [PlayScript] = { CastableLibrary.load()?.scripts ?? [] }) async -> PlayScript? {
        var failure: (any Error)?
        if let row = await readIndex(fetch: fetch, cache: cache, failure: &failure)?.randomElement(),
           let found = try? await script(id: row.id, fetch: fetch, cache: cache, bundled: bundled) { return found }
        return bundled().randomElement()
    }

    static func pick(_ id: String, from data: Data) -> PlayScript? {
        (try? JSONDecoder().decode(CastableLibrary.self, from: data))?.scripts.first { $0.id == id }
    }

    private static func write(_ data: Data, to file: URL) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
