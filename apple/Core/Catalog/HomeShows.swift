import Foundation

// A show at most once per Home (WEB-DESIGN §4.2r rule 5; js/api.js `homeShows`, with the same cases in
// HomeBrowseRulesTests): Home draws its rows in order, and a row keeps an episode only when its series is
// not in `seen` (the shows drawn higher up) and not already kept in this row. Continue is exempt.
nonisolated enum HomeShows {
    /// The kept episodes in the shelf's own order; their series join `seen`.
    static func keep(_ episodes: [EpisodeRow], seen: inout Set<String>) -> [EpisodeRow] {
        var out: [EpisodeRow] = []
        for episode in episodes where !episode.seriesKey.isEmpty && !seen.contains(episode.seriesKey) {
            seen.insert(episode.seriesKey)
            out.append(episode)
        }
        return out
    }

    /// A row of chips filtered against the shows above it. Each chip skips only what is above; the chip
    /// shown first adds its shows to the set the rows below skip. A chip left empty is dropped.
    static func chips(_ chips: [HomeChip], above: Set<String>) -> (chips: [HomeChip], seen: Set<String>) {
        var seenAfter = above
        var out: [HomeChip] = []
        for chip in chips {
            var seen = above
            let kept = keep(chip.episodes, seen: &seen)
            guard !kept.isEmpty else { continue }
            if out.isEmpty { seenAfter = seen }
            out.append(HomeChip(id: chip.id, title: chip.title, episodes: kept))
        }
        return (out, seenAfter)
    }

    /// A title that still carries an upload's catalog number ("AbyM #026 ...") or an identifier, or is a placeholder:
    /// raw upload text, which never shows (AGENTS.md; owner 2026-10-31).
    static func uploadTagged(_ title: String?) -> Bool {
        guard let title, !title.isEmpty else { return false }
        return title.contains(/(^|\s)#\s?\d+\b/) || RecordingLabel.looksLikeIdentifier(title) || placeholderTitle(title)
    }

    /// A log's or an uploader's stand-in for a title it did not have ("?? Title Unknown ??", "Ceiling Unlimited Title
    /// Unknown", "No Title Given", "Untitled"): never a title (owner 2026-11-27). The same rule as js/api.js and display_text.py.
    static func placeholderTitle(_ title: String?) -> Bool {
        let t = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        let afterWords = /(?:.*\s)?[?*\s.\-–]*(?:title\s+(?:unknown|not\s+known)|unknown\s+title|no\s+title(?:\s+given)?)[?*\s.\-–]*/
        let alone = /[?*\s.\-–]*(?:untitled(?:\s+episode)?|unknown|n\/a|tba|tbd)[?*\s.\-–]*/
        return t.wholeMatch(of: afterWords.ignoresCase()) != nil || t.wholeMatch(of: alone.ignoresCase()) != nil
    }

    /// The On the air hero's line under the show's name: the title, or the broadcast's date when the title is raw.
    static func heroTitle(_ title: String?, id: String) -> String? {
        if let title, !title.isEmpty, !uploadTagged(title) { return title }
        let date = id.split(separator: "|", omittingEmptySubsequences: false).dropFirst().first.map(String.init)
        guard let date, date.count >= 4, date.prefix(4).allSatisfy(\.isNumber) else { return nil }
        return AirDate.medium(date)
    }
}
