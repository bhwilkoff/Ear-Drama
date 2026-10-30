import SwiftUI

// Home and Browse in design direction D (iOS-/macOS-/tvOS-DESIGN R11c, WEB-DESIGN §6.4c): the
// day board with its years strip, the show tiles in grids, and Browse's decade by genre field.
// The decisions themselves are `ShowLine` in Core/Catalog/GrammarRules.swift.

enum BrowseScreenPage {
    /// Tiles drawn before "Show more".
    static let size = 60
}

// MARK: - The day

/// Every surviving broadcast on today's month and day, with its series, and what the strip and
/// the night need of them.
struct HomeDay {
    let month: Int
    let day: Int
    let episodes: [EpisodeRow]
    let series: [String: SeriesRow]
    let years: ShowLine.Day

    static func load(_ catalog: CatalogStore, today: Date = Date(), calendar: Calendar = .current) async -> HomeDay {
        let parts = calendar.dateComponents([.month, .day], from: today)
        let episodes = await catalog.dayEpisodes(today: today, calendar: calendar)
        let rows = await catalog.series(Array(Set(episodes.map(\.seriesKey))))
        let series = Dictionary(rows.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        return HomeDay(month: parts.month ?? 1, day: parts.day ?? 1, episodes: episodes, series: series,
                       years: ShowLine.dayYears(episodes, date: \.airDate,
                                                genre: { series[$0.seriesKey]?.genre ?? $0.seriesGenre }))
    }

    var dayName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        let names = formatter.monthSymbols ?? []
        return "\(names.indices.contains(month - 1) ? names[month - 1] : "") \(day)"
    }

    struct Show: Identifiable {
        let episode: EpisodeRow
        let series: SeriesRow
        var id: String { episode.id }
        var facts: [String] { [episode.displayTitle, episode.durationText].compactMap { $0 } }
    }

    /// The year's shows (a show's first broadcast of the night) and the count of single recordings.
    func night(_ year: Int) -> (shows: [Show], singles: Int) {
        let rows = episodes.filter { ($0.airDate ?? "").hasPrefix(String(year)) }
        let night = ShowLine.nightShows(rows, title: \.title, episodes: { series[$0.seriesKey]?.episodeCount })
        return (night.shows.compactMap { row in series[row.seriesKey].map { Show(episode: row, series: $0) } }, night.singles)
    }

    func nightHeading(_ year: Int) -> String { "\(dayName), \(year)" }
}

func countText(_ n: Int, _ one: String, _ many: String) -> String {
    n == 1 ? "1 \(one)" : "\(n.formatted()) \(many)"
}

// MARK: - Headings and links

/// A section's heading (L2), with a plain fact or a link on its right.
struct SectionHead<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
            Text(verbatim: title)
                .font(TypeRamp.sectionHeader)
                .foregroundStyle(Color.brandText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            trailing()
                .font(TypeRamp.caption)
                .foregroundStyle(Color.brandTextMuted)
                .lineLimit(1)
                .fixedSize()
        }
        .textCase(nil)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A show or an episode as the grammar's tile, opening `value`.
struct TileLink<Value: Hashable>: View {
    let value: Value
    let series: SeriesRow
    var width: CGFloat = ShowTile.defaultWidth
    var facts: [String]? = nil

    var body: some View {
        NavigationLink(value: value) { ShowTile(series: series, width: width, facts: facts) }
            #if os(tvOS)
            .buttonStyle(.card)
            #else
            .buttonStyle(.plain)
            .navigationLinkIndicatorVisibility(.hidden)
            #endif
    }
}

// MARK: - The grid

/// Tiles in rows that fill the width, each row sharing one name height (R11b). Row breaks are
/// computed from the measured width so no row is lazy: a tile that has not loaded cannot report.
struct ShowGrid<Item: Identifiable, Tile: View>: View {
    let items: [Item]
    /// A width the caller already knows (Browse's plan); nil measures it.
    var fixedWidth: CGFloat? = nil
    @ViewBuilder let tile: (Item, CGFloat) -> Tile
    @State private var measured: CGFloat = 0

    private struct Chunk: Identifiable {
        let items: [Item]
        var id: Item.ID { items[0].id }
    }

    var body: some View {
        let width = fixedWidth ?? measured
        let gap = BrowseLayout.gap
        let columns = BrowseLayout.columns(width: width, tileMin: ShowTile.defaultWidth)
        let tileWidth = BrowseLayout.tileWidth(width: width, columns: columns)
        let chunks = stride(from: 0, to: items.count, by: columns).map {
            Chunk(items: Array(items[$0..<min($0 + columns, items.count)]))
        }
        VStack(alignment: .leading, spacing: gap) {
            // The width comes from a view that holds no content, so nothing drawn below can change
            // what is measured (a row's disclosure chevron once fed back and widened it without end).
            if fixedWidth == nil {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 1, maxHeight: 1)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { measured = $0 }
            }
            if width > 0 {
                ForEach(chunks) { chunk in
                    HStack(alignment: .top, spacing: gap) {
                        ForEach(chunk.items) { tile($0, tileWidth) }
                    }
                    .frame(width: width, alignment: .leading)
                    .sharesNameHeight()
                }
            }
        }
        .frame(maxWidth: fixedWidth ?? .infinity, alignment: .topLeading)
    }
}

// MARK: - The day board

private func genreFill(_ genre: String) -> Color { Color.genre(genre) ?? Color.brandTextMuted }

/// The years strip: each year a bar stacked by genre in the mark colors, on the fixed axis from
/// 1930; the selected year is outlined. A tap selects the year nearest the finger.
struct YearStrip: View {
    let day: ShowLine.Day
    let selected: Int
    var height: CGFloat = 64
    var onSelect: ((Int) -> Void)?

    private var axisFrom: Int { min(1930, day.years.first?.year ?? 1930) }
    private var axisTo: Int { max(axisFrom, day.years.last?.year ?? axisFrom) }

    var body: some View {
        let from = axisFrom, to = axisTo, count = to - from + 1
        let peak = max(1, day.years.map(\.total).max() ?? 1)
        VStack(spacing: Spacing.s1) {
            Canvas { ctx, size in
                let step = size.width / CGFloat(count)
                let bar = max(1, step * 0.8)
                let usable = size.height - 4
                var present = Set<Int>()
                for y in day.years {
                    present.insert(y.year)
                    let x = CGFloat(y.year - from) * step
                    var top = size.height
                    for g in ShowLine.genreOrder + [""] {
                        guard let n = y.genres[g], n > 0 else { continue }
                        let h = CGFloat(n) / CGFloat(peak) * usable
                        top -= h
                        ctx.fill(Path(CGRect(x: x, y: top, width: bar, height: h)), with: .color(genreFill(g)))
                    }
                    if y.year == selected {
                        ctx.stroke(Path(CGRect(x: x - 1.5, y: top - 1.5, width: bar + 3, height: size.height - top + 1.5)),
                                   with: .color(Color.brandText), lineWidth: 2)
                    }
                }
                for year in from...to where !present.contains(year) {
                    let x = CGFloat(year - from) * step
                    ctx.fill(Path(CGRect(x: x, y: size.height - 1, width: bar, height: 1)), with: .color(Color.brandTextMuted))
                }
            }
            .frame(height: height)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { stripWidth = $0 }
            #if !os(tvOS)
            .gesture(SpatialTapGesture().onEnded { tap in
                guard let onSelect, stripWidth > 0, !day.years.isEmpty else { return }
                let year = from + Int(tap.location.x / stripWidth * CGFloat(count))
                if let nearest = day.years.min(by: { abs($0.year - year) < abs($1.year - year) }) { onSelect(nearest.year) }
            })
            #endif
            HStack {
                Text(verbatim: String(from))
                Spacer()
                Text(verbatim: String(selected))
                Spacer()
                Text(verbatim: String(to))
            }
            .font(TypeRamp.caption)
            .foregroundStyle(Color.brandTextMuted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Surviving broadcasts on this date by year, \(from) to \(to)")
        .accessibilityValue("\(selected), \(countText(day.years.first { $0.year == selected }?.total ?? 0, "broadcast", "broadcasts"))")
        .accessibilityAdjustableAction { direction in
            guard let onSelect, let i = day.years.firstIndex(where: { $0.year == selected }) else { return }
            switch direction {
            case .increment: if i + 1 < day.years.count { onSelect(day.years[i + 1].year) }
            case .decrement: if i > 0 { onSelect(day.years[i - 1].year) }
            @unknown default: break
            }
        }
    }

    @State private var stripWidth: CGFloat = 0
}

/// The legend: a mark and a name for each genre seen.
struct GenreLegend: View {
    let genres: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: Spacing.s2, alignment: .leading)],
                  alignment: .leading, spacing: Spacing.s1) {
            ForEach(genres, id: \.self) { g in
                HStack(spacing: Spacing.s1) {
                    Rectangle().fill(genreFill(g)).frame(width: 10, height: 10)
                    Text(verbatim: GenreDisplay.name(g)).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
        }
        .font(TypeRamp.caption)
        .foregroundStyle(Color.brandTextMuted)
        .accessibilityHidden(true)
    }
}

/// "This day in radio": the date, what survives, and the years strip.
struct DayBoard: View {
    let model: HomeDay
    @Binding var selected: Int
    var interactive = true

    var body: some View {
        let day = model.years
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text("This day in radio")
                .font(TypeRamp.caption)
                .foregroundStyle(Color.brandTextMuted)
            Text(verbatim: model.dayName)
                .font(TypeRamp.pageTitle)
                .foregroundStyle(Color.brandText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(verbatim: "\(countText(day.count, "surviving broadcast", "surviving broadcasts")) \u{00B7} \(countText(day.years.count, "year", "years"))")
                .font(TypeRamp.caption)
                .foregroundStyle(Color.brandTextMuted)
            YearStrip(day: day, selected: selected, height: Self.stripHeight,
                      onSelect: interactive ? { selected = $0 } : nil)
                .padding(.top, Spacing.s2)
                #if !os(tvOS)
                .sensoryFeedback(Haptic.selection.feedback, trigger: selected)
                #endif
            GenreLegend(genres: day.genres)
        }
        .padding(Spacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.brandSurfaceAlt)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
    }

    #if os(tvOS)
    static let stripHeight: CGFloat = 120
    #else
    static let stripHeight: CGFloat = 64
    #endif
}

// MARK: - Browse's field

/// Decades across, genres down; a square per cell in the genre's mark color, its area carrying
/// the number of shows, the number under it. A cell applies that genre and decade.
struct GenreField: View {
    let field: ShowLine.DecadeField
    let genre: String?
    let decade: Int?
    let pick: (String, Int) -> Void

    private let cell = BrowseLayout.cellWidth, label = BrowseLayout.labelWidth
    #if os(tvOS)
    private let unit: CGFloat = 2
    #else
    private let unit: CGFloat = 1
    #endif

    var body: some View {
        Grid(alignment: .center, horizontalSpacing: 0, verticalSpacing: 2) {
            GridRow {
                Color.clear.frame(width: label, height: 1)
                ForEach(field.decades, id: \.self) { d in
                    Text(verbatim: "\(d)s")
                        .font(TypeRamp.caption)
                        .foregroundStyle(Color.brandTextMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: cell)
                }
            }
            ForEach(field.genres, id: \.self) { g in
                GridRow {
                    HStack(spacing: Spacing.s1) {
                        Rectangle().fill(genreFill(g)).frame(width: 10, height: 10)
                        Text(verbatim: GenreDisplay.name(g)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .font(TypeRamp.caption)
                    .foregroundStyle(Color.brandText)
                    .frame(width: label, alignment: .leading)
                    ForEach(field.decades, id: \.self) { d in cellView(g, d) }
                }
            }
        }
    }

    @ViewBuilder private func cellView(_ g: String, _ d: Int) -> some View {
        let n = field.count(g, d)
        let side = CGFloat(ShowLine.fieldSide(n, max: field.max)) * unit
        let on = genre == g && decade == d
        let body = VStack(spacing: 2) {
            Rectangle().fill(genreFill(g)).frame(width: side, height: side)
                .overlay { if on { Rectangle().strokeBorder(Color.brandText, lineWidth: 2).padding(-3) } }
                .frame(height: 32 * unit + 6)
            Text(verbatim: n.formatted())
                .font(TypeRamp.caption)
                .foregroundStyle(Color.brandText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: cell)
        if n == 0 {
            body.hidden()
        } else {
            Button { pick(g, d) } label: { body.contentShape(Rectangle()) }
                #if os(tvOS)
                .buttonStyle(.card)
                #else
                .buttonStyle(.plain)
                #endif
                .accessibilityLabel("\(GenreDisplay.name(g)), \(d)s: \(countText(n, "show", "shows"))")
                .accessibilityAddTraits(on ? .isSelected : [])
        }
    }
}
