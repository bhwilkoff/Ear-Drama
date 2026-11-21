import Foundation

// Item pages wear Home's hero (WEB-DESIGN §6.4g, Decision 081, Round 3 V7): which picture leads a page, which further
// pictures draw as a row, and how big the head's window is. The web's `API.seriesLead`, `galleryOf`, `playLead` and
// `heroArt`, with the same golden cases (ItemLeadTests).

nonisolated enum ItemLead {
    /// A picture whose short side is under this many pixels is not shown in a head window (it gives way to the label).
    static let floor = 160

    /// The picture that leads a series page: its landscape hero when it is wide, else its picture; nil is the label.
    static func seriesLead(hero: Artwork?, picture: Artwork?) -> Artwork? {
        if let hero, hero.isWide { return hero }
        return picture
    }

    /// A series' further pictures, each with its own evidence and a size, without the lead and without repeats; a row
    /// draws only from two.
    static func gallery(_ pictures: [Artwork], lead: Artwork?) -> [Artwork] {
        var seen: Set<URL> = lead.map { [$0.url] } ?? []
        var out: [Artwork] = []
        for art in pictures {
            guard art.evidence != nil, (art.width ?? 0) > 0, (art.height ?? 0) > 0, !seen.contains(art.url) else { continue }
            seen.insert(art.url)
            out.append(art)
        }
        return out.count >= 2 ? out : []
    }

    /// The picture that leads a play's page: its title page, else a photograph of its production, else its author's
    /// portrait; nil is its page as the label.
    static func playLead(titlePage: Artwork?, production: Artwork? = nil, authorArt: Artwork?) -> Artwork? { titlePage ?? production ?? authorArt }

    /// The picture a head window can show: its size is known and its short side holds the floor.
    static func shown(_ art: Artwork?) -> Artwork? {
        guard let art, let w = art.width, let h = art.height, w > 0, h > 0, min(w, h) >= floor else { return nil }
        return art
    }

    /// Past this board width the window stands beside the words (Home's hero, 560); under it, across the top.
    static let besideFrom: CGFloat = 560
    /// The window's column beside the words, and the tallest an upright picture stands.
    static let column: CGFloat = 320
    static let uprightHeight: CGFloat = 400

    /// The window's frame inside a board `width` wide: a label is a square (the column's width on a phone, 320 beside
    /// the words); a picture keeps its own shape. A wide one is a plate over the words at the board's full width, at
    /// most 360 tall (440 beside); an upright or square one stands in the window's place, at most 400 tall and 320
    /// wide beside the words. The picture is never cropped.
    static func window(art: Artwork?, width: CGFloat) -> (size: CGSize, plate: Bool) {
        let beside = width >= besideFrom
        guard let art = shown(art), let a = art.aspectRatio else {
            let side = beside ? column : width
            return (CGSize(width: side, height: side), false)
        }
        if art.isWide {
            let h = min(width / a, beside ? 440 : 360)
            return (CGSize(width: h * a, height: h), true)
        }
        let h = min(uprightHeight, (beside ? min(column, width) : width) / a)
        return (CGSize(width: h * a, height: h), false)
    }

    /// An episode's heading: its own title, or, when the title still carries an upload's tag, the broadcast's date, else
    /// its number, else its show (raw upload text never shows).
    static func episodeTitle(_ episode: EpisodeRow) -> String {
        if let title = episode.title, HomeShows.uploadTagged(title) {
            if let date = episode.airDate { return AirDate.long(date) ?? AirDate.medium(date) }
            if let number = episode.number { return "No. \(number)" }
            return episode.seriesName
        }
        return episode.displayTitle
    }
}
