import Foundation

/// Forwarding ids (docs/CATALOG-CONTRACT.md §3.5, catalog DECISIONS 014): the
/// one place an Apple client resolves a stored episode id. An aliased id is the
/// id it now is; a tombstoned id left with no successor; any other id this
/// catalog does not serve is kept, since it may come from a newer catalog (a
/// synced row, a link from a newer app). The open catalog hands one to every
/// store that keeps episode ids (`CatalogStore.onForwarding`), and each
/// rewrites what it kept, once.
nonisolated struct IDForwarding: Equatable, Sendable {
    var aliases: [String: String] = [:]
    var tombstones: Set<String> = []

    /// The id `id` now is: itself when it never moved.
    func resolve(_ id: String) -> String { aliases[id] ?? id }

    /// Left the catalog with no successor; it will not come back as itself.
    func isGone(_ id: String) -> Bool { tombstones.contains(id) }

    /// A list of ids forwarded: each resolved, a tombstoned one dropped, a
    /// repeat (two old ids now one episode) kept once, where it first stood.
    func forward(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.map(resolve).filter { !isGone($0) && seen.insert($0).inserted }
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

extension ListeningQueue {
    /// The queue forwarded (`IDForwarding.forward`), keeping its stamp and
    /// dirty flag, so a device on an older catalog is never overwritten by
    /// this rewrite. Returns whether anything changed.
    @discardableResult
    func forward(_ forwarding: IDForwarding) -> Bool {
        let next = forwarding.forward(items)
        guard next != items else { return false }
        replaceItemsKeepingStamp(next)
        return true
    }
}
