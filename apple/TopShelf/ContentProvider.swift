import TVServices

/// The Top Shelf (tvOS-DESIGN §9.2): the listener's Continue items, read from
/// the snapshot the app keeps in the App Group. Nothing in progress returns
/// nil, so tvOS shows the static Top Shelf image.
final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        let snapshot = TopShelfSnapshot.groupContainer().flatMap(TopShelfSnapshot.read(from:))
        guard let items = TopShelfSnapshot.shelf(from: snapshot) else { return nil }
        let shelf = items.map { item -> TVTopShelfSectionedItem in
            let entry = TVTopShelfSectionedItem(identifier: item.id)
            entry.title = item.label
            entry.imageShape = .square
            if let art = item.artURL {
                entry.setImageURL(art, for: [.screenScale1x, .screenScale2x])
            }
            entry.playAction = TVTopShelfAction(url: item.link)
            entry.displayAction = TVTopShelfAction(url: item.link)
            return entry
        }
        let section = TVTopShelfItemCollection(items: shelf)
        section.title = "Continue listening"
        return TVTopShelfSectionedContent(sections: [section])
    }
}
