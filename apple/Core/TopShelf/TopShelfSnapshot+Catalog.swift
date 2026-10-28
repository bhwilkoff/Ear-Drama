import Foundation

// The app side only: the extension has no catalog types.
nonisolated extension TopShelfSnapshot {
    /// `episodes` arrive in Home's Continue order (most recent first) and keep it.
    static func make(from episodes: [EpisodeRow], limit: Int = limit) -> TopShelfSnapshot {
        TopShelfSnapshot(items: episodes.prefix(limit).map { episode in
            let art = episode.seriesFace?.art
            return Item(id: episode.id, title: episode.displayTitle, series: episode.seriesName,
                        artURL: art?.credit == nil ? art?.url(pixels: 500) : nil,
                        link: link(forEpisode: episode.id))
        })
    }
}

#if os(tvOS)
import TVServices

extension TopShelfSnapshot {
    /// Writes the Continue items into the App Group and tells tvOS to reload
    /// the shelf. Silent where the group is not provisioned (a plain Simulator
    /// run), so the app never fails over its Top Shelf.
    static func publish(_ episodes: [EpisodeRow]) {
        guard let directory = groupContainer() else { return }
        let snapshot = make(from: episodes)
        if read(from: directory) == snapshot { return }
        do { try snapshot.write(to: directory) } catch { print("Top Shelf snapshot not written: \(error)"); return }
        TVTopShelfContentProvider.topShelfContentDidChange()
    }
}
#endif
