import SwiftUI

// Small views every platform's tree composes. The idioms differ per platform
// (a List row, a Mac table-like row, a TV card); the words and the order of
// facts do not: date first, because in radio the date is the identity (R1).

/// An episode as the grammar's row (R11b): the date block in a list of one series, the series'
/// window where series mix (the date then leads the sub line), the title, the sub line, the
/// length, and Play.
struct EpisodeRowLabel: View {
    let episode: EpisodeRow
    var showSeries = false
    /// Why a search row matched, when the row itself cannot show it.
    var note: String? = nil
    /// A transcript match's line, verbatim from the automatic transcript.
    var quote: String? = nil
    @Environment(ListeningHistory.self) private var history
    @Environment(CatalogStore.self) private var catalog
    @Environment(AudioPlayer.self) private var player
    @Environment(AppStore.self) private var store

    var body: some View {
        GrammarRow(
            visual: showSeries || Grammar.undatedBare(date: episode.airDate, number: episode.number)
                ? .window(episode.seriesWindowArt, name: episode.seriesName, genre: episode.seriesGenre)
                : .date(episode.airDate, number: episode.number, genre: episode.seriesGenre),
            title: episode.displayTitle,
            sub: showSeries ? [episode.seriesName, AirDate.stored(episode.airDate), note] : [note],
            quote: quote,
            length: episode.durationText,
            progress: history.progress(for: episode.id),
            playLabel: "Play \(episode.displayTitle)",
            onPlay: { PlayEpisodeAction(catalog: catalog, player: player, store: store)(episode.id) })
    }
}

/// Search's transcript match (iOS-DESIGN §4.5): the episode row and the line
/// where the words are said, read from the transcript's own URL; the row
/// stands alone when the text does not load.
struct TranscriptHitLabel: View {
    let episode: EpisodeRow
    let words: [String]
    @State private var quote: String?

    var body: some View {
        EpisodeRowLabel(episode: episode, showSeries: true, quote: quote)
            .task(id: episode.id) {
                guard let url = episode.transcriptURL else { return }
                quote = await Transcript.snippet(from: url, words: words)
            }
    }
}

/// A series as the grammar's row: its window, the name, an event line of its facts.
struct SeriesRowLabel: View {
    let series: SeriesRow

    var body: some View {
        GrammarRow(
            visual: .window(series.windowArt, name: series.name, genre: series.genre),
            title: series.name,
            sub: [series.networks.first, series.yearSpan ?? "Undated",
                  series.episodeCount > 0 ? (series.episodeCount == 1 ? "1 episode" : "\(series.episodeCount.formatted()) episodes") : nil])
    }
}

/// The catalog could not be opened at all (no seed bundled, nothing downloaded).
struct CatalogUnavailableView: View {
    @Environment(CatalogStore.self) private var catalog

    var body: some View {
        ContentUnavailableView {
            Label("Catalog unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text("It downloads when you are online.")
        } actions: {
            Button("Try Again") { Task { await catalog.refresh(force: true) } }
        }
    }
}

/// Shown where playback needs the network and there is none: a warning the
/// listener cannot otherwise discover until Play fails.
struct OfflineNotice: View {
    var body: some View {
        Label("Offline. Episodes need a connection to play.", systemImage: "wifi.slash")
            .font(TypeRamp.caption)
            .foregroundStyle(Color.semanticWarning)
    }
}

/// The app-wide status line while there is no network (web §7.3, Android
/// `OfflineLine`): a degraded mode, not a failure, so the neutral color. What
/// was already loaded keeps working under it.
struct OfflineLine: View {
    @Environment(CatalogStore.self) private var catalog

    var body: some View {
        if let line = Connectivity.line(online: catalog.isOnline) {
            Label(line, systemImage: "wifi.slash")
                .font(TypeRamp.caption)
                .foregroundStyle(Color.brandTextMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.s1)
                .accessibilityElement(children: .combine)
        }
    }
}

/// Loading placeholder that keeps the eventual layout (skeleton rows).
struct SkeletonRows: View {
    var count = 6

    var body: some View {
        ForEach(0..<count, id: \.self) { _ in
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(verbatim: "0000-00-00  Episode title here").font(TypeRamp.bodyStrong)
                Text(verbatim: "Series name · 29:30").font(TypeRamp.caption)
            }
            .redacted(reason: .placeholder)
            .accessibilityHidden(true)
        }
    }
}

/// The credits grouped by role, in the order the catalog lists them.
nonisolated enum CreditGroups {
    static func grouped(_ credits: [Credit]) -> [(role: String, credits: [Credit])] {
        var order: [String] = []
        var byRole: [String: [Credit]] = [:]
        for credit in credits {
            let role = credit.role.map(Self.roleTitle) ?? "Credits"
            if byRole[role] == nil { order.append(role) }
            byRole[role, default: []].append(credit)
        }
        return order.map { ($0, byRole[$0] ?? []) }
    }

    private static func roleTitle(_ role: String) -> String { PersonRole.title(role) }
}

extension Credit {
    var line: String { character.map { "\(name) as \($0)" } ?? name }
}

/// A person in Search: their portrait in a round window, else their monogram, the name, and how
/// many episodes credit them.
struct PersonRowLabel: View {
    let row: PersonRow

    var body: some View {
        GrammarRow(visual: .person(row.person.art, name: row.person.name), title: row.person.name,
                   sub: [Self.count(row.episodes)])
    }

    static func count(_ n: Int) -> String {
        "\(n.formatted()) \(n == 1 ? "episode" : "episodes")"
    }
}
