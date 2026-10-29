import Foundation

// The app side only: the extension has no catalog types.
nonisolated extension TopShelfSnapshot {
    /// `episodes` arrive in Home's Continue order (most recent first) and keep it.
    /// `pageFaces` is each episode's Detail heading face (`EpisodeDetail.starFace`).
    /// The shelf cannot draw a caption, but an item's select opens that Detail,
    /// which shows this face with its credit one select away (tvOS-DESIGN §9.3),
    /// so a credited portrait rides the shelf only as the face Detail credits.
    /// The series' face, which Detail may not show, rides only when it owes none.
    static func make(from episodes: [EpisodeRow], pageFaces: [String: Face] = [:],
                     limit: Int = limit) -> TopShelfSnapshot {
        TopShelfSnapshot(items: episodes.prefix(limit).map { episode in
            let art = pageFaces[episode.id]?.art ?? (episode.seriesFace?.art).flatMap { $0.credit == nil ? $0 : nil }
            return Item(id: episode.id, title: episode.displayTitle, series: episode.seriesName,
                        artURL: art?.url(pixels: 500),
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
    static func publish(_ episodes: [EpisodeRow], pageFaces: [String: Face] = [:]) {
        guard let directory = groupContainer() else { return }
        let snapshot = make(from: episodes, pageFaces: pageFaces)
        if read(from: directory) == snapshot { return }
        do { try snapshot.write(to: directory) } catch { print("Top Shelf snapshot not written: \(error)"); return }
        TVTopShelfContentProvider.topShelfContentDidChange()
    }
}
#endif
