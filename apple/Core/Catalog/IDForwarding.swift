import Foundation

/// Forwarding ids (docs/CATALOG-CONTRACT.md §3.5, catalog DECISIONS 014): the
/// one place an Apple client resolves a stored episode id or series key. An
/// aliased id or key is the one it now is; a tombstoned one left with no
/// successor; any other this catalog does not serve is kept, since it may come
/// from a newer catalog (a synced row, a link from a newer app). The open
/// catalog hands one to every store that keeps ids or keys
/// (`CatalogStore.onForwarding`), and each rewrites what it kept, once.
///
/// Built into the watch app too (it has no catalog): the forwarding the phone
/// hands it is kept (`store(in:)`) and its own history forwarded on launch.
nonisolated struct IDForwarding: Equatable, Sendable, Codable {
    var aliases: [String: String] = [:]
    var tombstones: Set<String> = []
    var seriesAliases: [String: String] = [:]
    var seriesTombstones: Set<String> = []

    /// The id `id` now is: itself when it never moved.
    func resolve(_ id: String) -> String { aliases[id] ?? id }

    /// Left the catalog with no successor; it will not come back as itself.
    func isGone(_ id: String) -> Bool { tombstones.contains(id) }

    /// The series key `key` now is: itself when it never moved.
    func resolveSeries(_ key: String) -> String { seriesAliases[key] ?? key }

    /// A series key that left with no successor.
    func isSeriesGone(_ key: String) -> Bool { seriesTombstones.contains(key) }

    /// A list of ids forwarded: each resolved, a tombstoned one dropped, a
    /// repeat (two old ids now one episode) kept once, where it first stood.
    func forward(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.map(resolve).filter { !isGone($0) && seen.insert($0).inserted }
    }

    private static let storeKey = "idForwarding.v1"

    /// The forwarding last kept on this device (the watch's, handed over with
    /// the phone's history); none when nothing was kept or it does not decode.
    static func stored(in defaults: UserDefaults = .standard) -> IDForwarding {
        defaults.data(forKey: storeKey).flatMap { try? JSONDecoder().decode(IDForwarding.self, from: $0) } ?? IDForwarding()
    }

    func store(in defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storeKey) }
    }
}

extension ListeningHistory {
    /// Moves every kept row whose id moved to the id it now is. A moved row
    /// merges into the new id's by the newer stamp and keeps its own stamp and
    /// pending state: a rewrite is not a listen, so it is never uploaded as new
    /// (each device forwards the Worker's old-id rows for itself). A tombstoned
    /// id stays: it is the person's record. Returns how many ids moved.
    @discardableResult
    func forward(_ forwarding: IDForwarding) -> Int {
        let moved = Set(entries.keys).union(removals.keys).filter { forwarding.resolve($0) != $0 }
        for id in moved.sorted() {
            rekey(id, to: forwarding.resolve(id))
        }
        if !moved.isEmpty { saveSyncState() }
        return moved.count
    }
}
