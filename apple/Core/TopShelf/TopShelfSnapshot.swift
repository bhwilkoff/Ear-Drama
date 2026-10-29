import Foundation

/// The Continue items the Apple TV app hands to its Top Shelf extension. The
/// extension cannot open the app's UserDefaults or the catalog, so the app
/// writes this small file into the App Group container (tvOS may write only
/// there and to Caches) and the extension reads it. Compiled into both.
nonisolated struct TopShelfSnapshot: Codable, Equatable, Sendable {
    struct Item: Codable, Equatable, Sendable {
        let id: String
        let title: String
        let series: String
        /// Nil when no face may ride the shelf: a credited portrait rides only
        /// as the face the item's Detail shows with its credit, one select away
        /// (tvOS-DESIGN §9.3). No artwork rather than a stand-in.
        let artURL: URL?
        let link: URL

        /// A sectioned item has one line of text: the series, then the episode.
        var label: String { title == series ? series : "\(series): \(title)" }
    }

    static let appGroup = "group.app.eardrama"
    static let fileName = "topshelf.json"
    /// Home's Continue shelf shows ten; so does the Top Shelf.
    static let limit = 10

    var items: [Item]

    /// `eardrama://episode/{percent-encoded id}` (DEEP_LINKS.md).
    static func link(forEpisode id: String) -> URL {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        let encoded = id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id
        return URL(string: "eardrama://episode/\(encoded)") ?? URL(string: "eardrama://library")!
    }

    /// What the Top Shelf shows: the items, or nil so tvOS keeps the static image.
    static func shelf(from snapshot: TopShelfSnapshot?) -> [Item]? {
        guard let items = snapshot?.items, !items.isEmpty else { return nil }
        return items
    }

    static func groupContainer() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    func write(to directory: URL) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: directory.appendingPathComponent(Self.fileName), options: .atomic)
    }

    static func read(from directory: URL) -> TopShelfSnapshot? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(fileName)) else { return nil }
        return try? JSONDecoder().decode(TopShelfSnapshot.self, from: data)
    }
}
