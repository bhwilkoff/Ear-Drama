import Foundation

// The labels an item page's head draws for a play and for a finished ear drama (WEB-DESIGN §6.4g).

nonisolated extension PlayScript {
    /// A finished ear drama's label: its part-color disc, each speaking part an arc as long as its share of the lines,
    /// the recording month on the rim (`published` is the ISO date).
    func dramaLabel(title: String, published: String?) -> LabelItem {
        let speaking = castParts.filter { $0.id.isSpeaking }
        return LabelItem(kind: .drama, name: title, parts: speaking.map { .init(lines: $0.lineCount, hue: partHue($0.id)) },
                         finished: published)
    }

    /// A play's label as a page: the script's ground and one rule per band of voices at its foot.
    var pageLabel: LabelItem { LabelItem(kind: .play, voices: castLines.count, opening: true) }
}

nonisolated extension FinishedPlay {
    /// The recording date as an ISO day, for the drama label's rim.
    var publishedISO: String {
        let date = Date(timeIntervalSince1970: TimeInterval(publishedAt) / 1000)
        return date.formatted(.iso8601.year().month().day().dateSeparator(.dash))
    }
}
