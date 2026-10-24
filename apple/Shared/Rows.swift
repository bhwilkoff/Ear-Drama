import SwiftUI

// Small views every platform's tree composes. The idioms differ per platform
// (a List row, a Mac table-like row, a TV card); the words and the order of
// facts do not: date first, because in radio the date is the identity (R1).

/// `1943-05-25  Sorry, Wrong Number` with series, duration, and progress.
struct EpisodeRowLabel: View {
    let episode: EpisodeRow
    var showSeries = false
    /// Why a search row matched, when the row itself cannot show it.
    var note: String? = nil
    @Environment(ListeningHistory.self) private var history

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            // Decision 069: a row that mixes series leads with its series' tile; a series page's rows do not.
            if showSeries {
                ArtTile(name: episode.seriesName, genre: episode.seriesGenre, face: episode.seriesFace)
            }
            text
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(accessibilityProgress)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
                Text(verbatim: AirDate.display(episode.airDate))
                    .font(TypeRamp.tabular)
                    .foregroundStyle(Color.brandTextMuted)
                Text(episode.displayTitle)
                    .font(TypeRamp.bodyStrong)
                    .foregroundStyle(Color.brandText)
                    .multilineTextAlignment(.leading)
            }
            HStack(spacing: Spacing.s2) {
                if showSeries {
                    Text(episode.seriesName)
                }
                if let duration = episode.durationText {
                    Text(verbatim: duration).monospacedDigit()
                }
                if let note {
                    Text(note)
                }
                progressMark
            }
            .font(TypeRamp.caption)
            .foregroundStyle(Color.brandTextMuted)
        }
    }

    @ViewBuilder private var progressMark: some View {
        if let p = history.progress(for: episode.id) {
            if p >= 1 {
                Image(systemName: "checkmark.circle.fill")
                    .accessibilityHidden(true)
            } else if p > 0 {
                ProgressView(value: p)
                    .tint(Color.brandPrimary)
                    .frame(maxWidth: 60)
                    .accessibilityHidden(true)
            }
        }
    }

    private var accessibilityProgress: String {
        guard let p = history.progress(for: episode.id) else { return "" }
        return p >= 1 ? "Played" : "\(Int(p * 100)) percent played"
    }
}

struct SeriesRowLabel: View {
    let series: SeriesRow

    var body: some View {
        HStack(spacing: Spacing.s3) {
            // The tile carries the genre hue the edge used to (Decision 069).
            ArtTile(name: series.name, genre: series.genre, face: series.face)
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(series.name)
                    .font(TypeRamp.bodyStrong)
                    .foregroundStyle(Color.brandText)
                    .multilineTextAlignment(.leading)
                Text(verbatim: series.metaLine)
                    .font(TypeRamp.caption)
                    .foregroundStyle(Color.brandTextMuted)
            }
        }
        .accessibilityElement(children: .combine)
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

/// A person in Search: their portrait or initial, the name, and how many episodes credit them.
struct PersonRowLabel: View {
    let row: PersonRow

    var body: some View {
        HStack(spacing: Spacing.s3) {
            ArtTile(name: row.person.name, genre: nil, face: row.person.face)
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(row.person.name)
                    .font(TypeRamp.bodyStrong)
                    .foregroundStyle(Color.brandText)
                    .multilineTextAlignment(.leading)
                Text(verbatim: PersonRowLabel.count(row.episodes))
                    .font(TypeRamp.caption)
                    .foregroundStyle(Color.brandTextMuted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    static func count(_ n: Int) -> String {
        "\(n.formatted()) \(n == 1 ? "episode" : "episodes")"
    }
}
