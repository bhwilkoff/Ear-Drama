import CoreText
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// One grammar for every level of content (WEB-DESIGN §6.4b, iOS-/macOS-/tvOS-DESIGN R11b):
// one skeleton per object, richer data fills more slots and never adds, moves or resizes one.
// The decisions themselves (monogram, block size, type step, window fill, event parts, run
// span, grade) are pure functions in Core/Catalog/Grammar.swift with the web's golden cases.

// MARK: - Type

/// The display levels the grammar sets in Big Shoulders: the name steps L2 -> L3 -> L5 (the head
/// board L1 -> L2 -> L3), at the system styles' default sizes and scaling with Dynamic Type.
private enum GrammarType {
    #if os(tvOS)
    static let tileNames: [Font.TextStyle] = [.title3, .headline, .body]
    static let headNames: [Font.TextStyle] = [.title, .title3, .headline]
    #else
    static let tileNames: [Font.TextStyle] = [.title2, .headline, .caption]
    static let headNames: [Font.TextStyle] = [.largeTitle, .title2, .headline]
    #endif

    static func display(_ style: Font.TextStyle) -> Font {
        Font.custom(TypeRamp.displayFontName, size: size(style), relativeTo: style)
    }

    /// The head board across a tablet: the same steps, set for a page read at arm's length.
    static func wideHeadName(step: Int) -> Font {
        let style = headNames[min(step, 2)]
        return Font.custom(TypeRamp.displayFontName, size: size(style) * 1.6, relativeTo: style)
    }

    static func tileName(step: Int) -> Font { display(tileNames[min(step, 2)]) }
    static func headName(step: Int) -> Font { display(headNames[min(step, 2)]) }

    static func size(_ style: Font.TextStyle) -> CGFloat {
        #if canImport(UIKit)
        let ui: UIFont.TextStyle
        switch style {
        case .title: ui = .title1
        case .title2: ui = .title2
        case .title3: ui = .title3
        case .headline: ui = .headline
        case .caption: ui = .caption1
        case .largeTitle:
            #if os(tvOS)
            ui = .title1
            #else
            ui = .largeTitle
            #endif
        default: ui = .body
        }
        return UIFont.preferredFont(forTextStyle: ui, compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)).pointSize
        #else
        let ns: NSFont.TextStyle
        switch style {
        case .title: ns = .title1
        case .title2: ns = .title2
        case .title3: ns = .title3
        case .headline: ns = .headline
        case .caption: ns = .caption1
        case .largeTitle: ns = .largeTitle
        default: ns = .body
        }
        return NSFont.preferredFont(forTextStyle: ns).pointSize
        #endif
    }
}

// MARK: - The graded picture

/// A picture decoded and graded by `PictureGrade`; nothing shows until it arrives, and a failure is
/// reported so the window can fall back to its title block.
struct GradedImage: View {
    let url: URL
    let grade: Artwork.Grade
    var onFail: () -> Void = {}
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable()
            } else {
                Color.clear
            }
        }
        .task(id: url) {
            if let hit = PictureGrade.cached(url, grade) { image = hit; return }
            image = nil
            switch await PictureGrade.load(url, grade: grade) {
            case let .image(loaded): image = loaded
            case .cancelled: break
            case .failed: onFail()
            }
        }
    }
}

// MARK: - The window

/// The designed fallback (Decision 081): the label, drawn from the item's own data on its genre's board
/// (`LabelView`). The name is never drawn twice beyond its monogram, so the window is hidden from
/// accessibility and the row says it.
struct TitleBlock: View {
    let item: LabelItem
    let side: CGFloat

    var body: some View { LabelView(item: item, side: side) }
}

/// The one square slot (R11b): the series' picture cropped around its face, or drawn whole inside
/// a 6 % inset on the print ground, or the title block. Radius 4, a 1 pt hairline.
struct PictureWindow: View {
    let art: Artwork?
    let name: String
    let genre: String?
    let side: CGFloat
    var round = false
    /// What the label draws when the window holds no picture: an episode's with its own date, a show's with
    /// its run and network; by default the show (or, in a round window, the person) from `name` and `genre`.
    var label: LabelItem? = nil
    @Environment(\.displayScale) private var scale
    @State private var failed = false

    private var labelItem: LabelItem {
        if var label { label.name = label.name ?? name; label.genre = label.genre ?? genre; return label }
        return LabelItem(kind: round ? .person : .series, name: name, genre: genre)
    }

    var body: some View {
        let fill = failed ? Grammar.WindowFill.block : Grammar.windowFill(art, slot: Double(side))
        ZStack {
            switch fill {
            case .block:
                TitleBlock(item: labelItem, side: side)
            case let .crop(r):
                Color.printGround
                if let art { crop(art, r) }
            case .whole:
                Color.printGround
                if let art { whole(art) }
            }
        }
        .frame(width: side, height: side)
        .clipShape(round ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 4)))
        .overlay {
            let edge = fill == .block ? Color.onBoard(genre).opacity(0.32) : Color.printEdge
            if round {
                Circle().strokeBorder(edge, lineWidth: 1)
            } else {
                RoundedRectangle(cornerRadius: 4).strokeBorder(edge, lineWidth: 1)
            }
        }
        // A failure is about one fetch: a new picture, a new size or a return to the screen tries again.
        .onChange(of: art?.url) { failed = false }
        .onChange(of: side) { failed = false }
        .onAppear { failed = false }
        .accessibilityHidden(true)
    }

    private func crop(_ art: Artwork, _ r: Artwork.CropRect) -> some View {
        let size = CGSize(width: side / CGFloat(r.w), height: side / CGFloat(r.h))
        return GradedImage(url: art.url(pixels: Double(size.width * scale)), grade: Grammar.gradeOf(art)) { failed = true }
            .frame(width: size.width, height: size.height)
            .offset(x: -CGFloat(r.x) * size.width, y: -CGFloat(r.y) * size.height)
            .frame(width: side, height: side, alignment: .topLeading)
            .clipped()
    }

    private func whole(_ art: Artwork) -> some View {
        GradedImage(url: art.url(pixels: Double(side * scale)), grade: Grammar.gradeOf(art)) { failed = true }
            .aspectRatio(art.drawnAspect, contentMode: .fit)
            .padding(side * 0.06)
    }
}

/// A play's window (Decision 075, one rule for every play): the cast drawn in the square slot, one
/// horizontal bar per speaking part, largest first and at most seven, each as wide as its lines over
/// the largest part's (6 % at least), the first thicker, all in the board's one ink; "+N" for the rest.
/// It stands where a show's picture or monogram stands, never beside it.
struct CastWindow: View {
    let cast: CastSummary
    var genre: String? = PlayScript.boardGenre
    let side: CGFloat

    init(cast: CastSummary, genre: String? = PlayScript.boardGenre, side: CGFloat) {
        self.cast = cast
        self.genre = genre
        self.side = side
    }

    init(script: PlayScript, genre: String? = PlayScript.boardGenre, side: CGFloat) {
        self.init(cast: CastSummary(script: script), genre: genre, side: side)
    }

    var body: some View {
        let cast = cast.window
        let most = Double(max(1, cast.shown.first ?? 1))
        let ink = Color.onBoard(genre)
        let inner = side * 0.76
        ZStack {
            Color.board(genre)
            VStack(alignment: .leading, spacing: side * 0.06) {
                ForEach(Array(cast.shown.enumerated()), id: \.offset) { index, lineCount in
                    Capsule()
                        .fill(ink)
                        .frame(width: inner * max(0.06, Double(lineCount) / most),
                               height: max(4, side * (index == 0 ? 0.11 : 0.07)))
                }
            }
            .frame(width: inner, alignment: .leading)
            if cast.more > 0 {
                Text(verbatim: "+\(cast.more)")
                    .font(TypeRamp.caption.weight(.semibold))
                    .foregroundStyle(ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(side * 0.06)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(ink.opacity(0.32), lineWidth: 1) }
        .accessibilityHidden(true)
    }
}

// MARK: - The run strip

/// The years from the first to the last broadcast on the fixed 1930 to 1962 axis: the baseline at
/// 30 % and the span as a solid bar; an undated show is the baseline alone.
struct RunStrip: View {
    let first: String?
    let last: String?
    let genre: String?
    var height: CGFloat = 18
    /// The run histogram (`series.year_counts`): a bar per year, its height the count; the span
    /// bar draws where the catalog has none.
    var years: [Int]? = nil
    /// The page about one show compares it with nothing: the bars take the show's own years, so a
    /// short run is not a mostly empty axis. A tile keeps the fixed axis, where shows sit side by side.
    var ownSpan = false
    /// An episode's page marks its year: that year's bar at full ink, the rest at 45 % (WEB-DESIGN §6.4g).
    var markYear: Int? = nil

    var body: some View {
        GeometryReader { geo in
            let ink = Color.onBoard(genre)
            let bars = Grammar.runBars(years: years)
            let axis = ownSpan && (bars?.count ?? 0) >= 3 ? Grammar.ownSpanAxis(bars) : nil
            let fit = axis != nil
            let lo = CGFloat(axis?.lo ?? 0)
            let scale = geo.size.width / CGFloat((axis?.hi ?? 1) - (axis?.lo ?? 0))
            ZStack(alignment: .bottomLeading) {
                Rectangle().fill(ink.opacity(0.3)).frame(height: 1)
                if let bars {
                    ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                        Rectangle().fill(ink.opacity(Grammar.barDimmed(from: bar.from, markYear: markYear) ? 0.45 : 1))
                            .frame(width: max(1, scale * CGFloat(bar.to - bar.from) - (fit ? 2 : 0.5)),
                                   height: max(2, (height - 3) * CGFloat(bar.height)))
                            .offset(x: scale * (CGFloat(bar.from) - lo), y: -1)
                    }
                } else if let span = Grammar.runSpan(first: first, last: last) {
                    Rectangle().fill(ink)
                        .frame(width: geo.size.width * CGFloat(span.to - span.from), height: height * 15 / 18)
                        .offset(x: geo.size.width * CGFloat(span.from))
                }
            }
            .frame(width: geo.size.width, height: height, alignment: .bottomLeading)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - The cast fingerprint

/// A play's mark where a show has its run strip (D3-6): one bar, each speaking part a segment whose
/// width is its share of the play's lines, largest first, a 1 pt gap between. On a board every segment
/// takes the board's one ink; off a board each takes its part's mark.
struct CastFingerprint: View {
    let cast: CastSummary
    /// The board the bar stands on; nil draws the part marks.
    var onBoard: String? = nil
    var height: CGFloat = 12

    init(cast: CastSummary, onBoard: String? = nil, height: CGFloat = 12) {
        self.cast = cast
        self.onBoard = onBoard
        self.height = height
    }

    init(script: PlayScript, onBoard: String? = nil, height: CGFloat = 12) {
        self.init(cast: CastSummary(script: script), onBoard: onBoard, height: height)
    }

    var body: some View {
        let shares = cast.shares
        GeometryReader { geo in
            let gap: CGFloat = 1
            let usable = max(0, geo.size.width - gap * CGFloat(max(0, shares.count - 1)))
            HStack(spacing: gap) {
                ForEach(Array(shares.enumerated()), id: \.offset) { share in
                    Rectangle()
                        .fill(onBoard.map { Color.onBoard($0) } ?? Color.genre(CastSummary.hue(at: share.offset)) ?? Color.brandTextMuted)
                        .frame(width: usable * CGFloat(share.element))
                }
            }
            .frame(width: geo.size.width, height: height, alignment: .leading)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - The show tile

private struct NameHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct SharedNameHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    fileprivate var sharedNameHeight: CGFloat? {
        get { self[SharedNameHeightKey.self] }
        set { self[SharedNameHeightKey.self] = newValue }
    }
}

/// Wraps a shelf's row of `ShowTile`s: each tile reports its name's natural height through a
/// preference, and every tile takes the tallest, so every strip in the shelf sits on one line.
/// The row must not be lazy, or a tile that has not loaded cannot report.
private struct SharedNameHeight: ViewModifier {
    @State private var height: CGFloat?

    func body(content: Content) -> some View {
        content
            .environment(\.sharedNameHeight, height)
            .onPreferenceChange(NameHeightKey.self) { height = $0 > 0 ? $0 : nil }
    }
}

extension View {
    /// Mark the container of a shelf's `ShowTile`s.
    func sharesNameHeight() -> some View { modifier(SharedNameHeight()) }
}

/// A series on its genre's board (R11b): the window, the name, the run strip, the facts. Never
/// shows `pictureKind`. tvOS focus scales the whole tile through the card style around it.
#if !os(tvOS)
private struct TileFillsRowKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// A grid row's tiles end on one line, whatever each says (macOS-DESIGN §4.0a; iOS since V8, 2026-11-20: the open
    /// Duo's "That night" row ended at two heights where one tile's facts took a third line).
    var tileFillsRow: Bool {
        get { self[TileFillsRowKey.self] }
        set { self[TileFillsRowKey.self] = newValue }
    }
}
#endif

struct ShowTile: View {
    let series: SeriesRow
    var width: CGFloat = Self.defaultWidth
    /// The facts lines when the tile says something other than the run and the episode count.
    var facts: [String]? = nil
    /// A play: its cast fingerprint stands where the run strip would.
    var castScript: PlayScript? = nil
    /// The same, for a play known only by its library row.
    var cast: CastSummary? = nil
    /// A play's label (B31 2.1): the window holds the row's picture of the play, else this, never the cast bars.
    var playLabel: LabelItem? = nil
    @Environment(\.sharedNameHeight) private var sharedNameHeight
    #if !os(tvOS)
    @Environment(\.tileFillsRow) private var fillsRow
    #endif
    #if os(macOS)
    @State private var hovering = false
    #endif

    #if os(tvOS)
    static let defaultWidth: CGFloat = 312
    #elseif os(macOS)
    static let defaultWidth: CGFloat = 176
    #else
    /// Two columns on a phone's list row (iPhone 12: a 326 pt row is 160 short of two tiles, so Home drew one tile as wide as the screen).
    static let defaultWidth: CGFloat = 144
    #endif

    private func factLines(_ index: Int) -> Int {
        #if os(tvOS)
        index == 0 ? 2 : 1
        #else
        2
        #endif
    }

    var body: some View {
        let ink = Color.onBoard(series.genre)
        VStack(alignment: .leading, spacing: 6) {
            if let playLabel {
                PictureWindow(art: series.windowArt, name: series.name, genre: series.genre, side: width - 12, label: playLabel)
            } else if let cast = cast ?? castScript.map(CastSummary.init(script:)) {
                CastWindow(cast: cast, genre: series.genre, side: width - 12)
            } else {
                PictureWindow(art: series.windowArt, name: series.name, genre: series.genre, side: width - 12, label: series.labelItem)
            }
            Text(verbatim: series.name.uppercased())
                .font(GrammarType.tileName(step: Grammar.nameStep(series.name)))
                .foregroundStyle(ink)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { Color.clear.preference(key: NameHeightKey.self, value: $0.size.height) })
                .frame(maxWidth: .infinity, minHeight: sharedNameHeight, maxHeight: sharedNameHeight, alignment: .topLeading)
            if let cast = cast ?? castScript.map(CastSummary.init(script:)) {
                CastFingerprint(cast: cast, onBoard: series.genre, height: 18)
            } else {
                RunStrip(first: series.firstDate, last: series.lastDate, genre: series.genre, years: series.yearCounts)
            }
            VStack(alignment: .leading, spacing: 0) {
                if let facts {
                    ForEach(Array(facts.enumerated()), id: \.offset) { Text(verbatim: $0.element).lineLimit(factLines($0.offset)) }
                } else {
                    Text(verbatim: series.yearSpan ?? "Undated")
                    Text(verbatim: series.episodeCount == 1 ? "1 episode" : "\(series.episodeCount.formatted()) episodes")
                }
            }
            .font(TypeRamp.caption)
            .foregroundStyle(ink)
            #if os(tvOS)
            // Tiles in a row are one height (§3.0): the same room for facts, whatever a tile says.
            .frame(height: facts == nil ? 76 : 112, alignment: .topLeading)
            #endif
        }
        .padding(EdgeInsets(top: 6, leading: 6, bottom: 10, trailing: 6))
        .frame(width: width, alignment: .topLeading)
        #if !os(tvOS)
        .frame(maxHeight: fillsRow ? .infinity : nil, alignment: .topLeading)
        #endif
        .background(Color.board(series.genre))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        #if os(macOS)
        .shadow(color: .black.opacity(hovering ? 0.28 : 0), radius: hovering ? 8 : 0, y: hovering ? 4 : 0)
        .offset(y: hovering ? -2 : 0)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
        #endif
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(series.name)
        .accessibilityValue(castScript != nil || cast != nil ? (facts ?? []).joined(separator: ", ") : series.metaLine)
    }
}

// MARK: - The event line

/// Lines of fragments that wrap between fragments only.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    var rowSpacing: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placed = arrange(width: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, placed.frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            if size.width > width { size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
            if x > 0, x + size.width > width {
                y += rowHeight + rowSpacing
                x = 0
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (frames, CGSize(width: widest, height: y + rowHeight))
    }
}

/// Facts joined by " ·", each separator kept with the fact before it, so a line may end on a dot
/// and never opens with one. Reads as the facts joined by commas.
struct EventLine: View {
    let facts: [String?]
    var color: Color = Color.brandTextMuted

    var body: some View {
        let parts = Grammar.eventParts(facts)
        if !parts.isEmpty {
            FlowLayout {
                ForEach(parts.indices, id: \.self) { i in
                    // A no-break space keeps the dot with its fact: a wrapped line never opens or ends on a lone dot.
                    Text(verbatim: parts[i].replacingOccurrences(of: " \u{00B7}", with: "\u{00A0}\u{00B7}"))
                        .font(TypeRamp.caption)
                        .foregroundStyle(color)
                        .multilineTextAlignment(.leading)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(facts.compactMap { $0 }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: ", "))
        }
    }
}

// MARK: - The row

/// The date block (R1: the date leads, in the visual): the month and year in small caps over the
/// day in Big Shoulders, on the series' board; an undated numbered episode says "No." over its
/// number. Says the full date to VoiceOver.
struct DateBlock: View {
    let date: String?
    let number: Int?
    let genre: String?
    let side: CGFloat

    var body: some View {
        let parts = Grammar.dateBlock(date: date, number: number)
        let ink = Color.onBoard(genre)
        ZStack {
            Color.board(genre)
            VStack(spacing: 0) {
                if !parts.small.isEmpty {
                    Text(verbatim: parts.small)
                        .font(TypeRamp.caption.lowercaseSmallCaps())
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                Text(verbatim: parts.big)
                    .font(TypeRamp.sectionHeader)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .foregroundStyle(ink)
            .padding(2)
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(ink.opacity(0.32), lineWidth: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AirDate.display(date))
    }
}

/// What a row leads with.
enum GrammarVisual {
    /// The series' window, for a list that mixes series or lists series.
    case window(Artwork?, name: String, genre: String?)
    /// The date block, for a list of one series.
    case date(String?, number: Int?, genre: String?)
    /// A series known only by its key (a station's slot): its window, read from the catalog.
    case seriesKey(String, name: String)
    /// A person: the portrait in a round window, else the monogram.
    case person(Artwork?, name: String)
}

/// A slot's episode id is `series|date`; the series key is what its window is read by.
enum GrammarSlot {
    static func seriesKey(_ episodeID: String) -> String {
        String(episodeID.split(separator: "|", maxSplits: 1).first ?? "")
    }
}

/// A window for a series the row knows only by key: the title block until the catalog answers, then
/// the series' picture and genre.
struct SeriesKeyWindow: View {
    let key: String
    let name: String
    let side: CGFloat
    @Environment(CatalogStore.self) private var catalog
    @State private var row: SeriesRow?

    var body: some View {
        PictureWindow(art: row?.windowArt, name: name, genre: row?.genre, side: side, label: row?.labelItem)
            .task(id: key) {
                guard !key.isEmpty else { return }
                row = await catalog.series([key]).first
            }
    }
}

/// The one row (R11b): 64 pt whatever it carries, a 48 pt visual, the title (L3), the sub line
/// (L5, muted, an event line), the length (L6), and Play (36 pt, where the platform has a
/// pointer or a finger; the Siri Remote plays from the row's menu). A missing sub line centers
/// the title in the same height. Play is its own control; the rest is one element for VoiceOver.
struct GrammarRow: View {
    let visual: GrammarVisual
    let title: String
    var sub: [String?] = []
    var quote: String? = nil
    var length: String? = nil
    /// Ink on the primary color where the length goes: the slot on the air.
    var badge: String? = nil
    var progress: Double? = nil
    var genre: String? = nil
    var playLabel: String? = nil
    var onPlay: (() -> Void)? = nil

    #if os(tvOS)
    private let minHeight: CGFloat = 96
    private let visualSide: CGFloat = 72
    #else
    private let minHeight: CGFloat = 64
    private let visualSide: CGFloat = 48
    #endif

    /// Where a Play button crowds the right edge, the length joins the event line and a part-played
    /// bar sits under it, so the title keeps the row's width (the Home and Stations rows at 375 pt).
    private var playAtRight: Bool {
        #if os(tvOS)
        false
        #else
        onPlay != nil
        #endif
    }

    var body: some View {
        HStack(spacing: Spacing.s3) {
            HStack(spacing: Spacing.s3) {
                visualView
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(TypeRamp.bodyStrong)
                        .foregroundStyle(Color.brandText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    if playAtRight, let progress, progress > 0, progress < 1 {
                        ProgressView(value: progress)
                            .tint(Color.brandPrimary)
                            .frame(maxWidth: 120)
                            .accessibilityHidden(true)
                    }
                    EventLine(facts: playAtRight && badge == nil ? sub + [length] : sub)
                    if let quote {
                        Text(verbatim: quote)
                            .font(TypeRamp.caption)
                            .italic()
                            .foregroundStyle(Color.brandText)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                if let badge {
                    Text(verbatim: badge)
                        .font(TypeRamp.caption.weight(.semibold))
                        .foregroundStyle(Color.brandOnPrimary)
                        .padding(.horizontal, Spacing.s2)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.brandPrimary))
                } else if let length, !playAtRight {
                    Text(verbatim: length)
                        .font(TypeRamp.tabular)
                        .foregroundStyle(Color.brandTextMuted)
                }
                progressMark
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(progressWords)
            #if !os(tvOS)
            if let onPlay {
                Button(action: onPlay) {
                    Image(systemName: "play.fill")
                        .font(TypeRamp.body)
                        .foregroundStyle(Color.brandOnPrimary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.brandPrimary))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(playLabel ?? "Play \(title)")
            }
            #endif
        }
        .frame(minHeight: minHeight)
    }

    @ViewBuilder private var visualView: some View {
        switch visual {
        case let .window(art, name, genre):
            PictureWindow(art: art, name: name, genre: genre, side: visualSide)
        case let .date(date, number, genre):
            DateBlock(date: date, number: number, genre: genre, side: visualSide)
        case let .seriesKey(key, name):
            SeriesKeyWindow(key: key, name: name, side: visualSide)
        case let .person(art, name):
            PictureWindow(art: art, name: name, genre: nil, side: visualSide, round: true)
        }
    }

    @ViewBuilder private var progressMark: some View {
        if let progress, !(playAtRight && progress < 1) {
            if progress >= 1 {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.brandTextMuted)
                    .accessibilityHidden(true)
            } else if progress > 0 {
                ProgressView(value: progress)
                    .tint(Color.brandPrimary)
                    .frame(maxWidth: 40)
                    .accessibilityHidden(true)
            }
        }
    }

    private var progressWords: String {
        guard let progress else { return "" }
        return progress >= 1 ? "Played" : "\(Int(progress * 100)) percent played"
    }
}

// MARK: - The head board (built in D3-1, adopted by the pages in D3-3)

/// The board a series, episode or ear drama stands on: the window (96, 128 from 600 pt wide, 176
/// from 1024), the kicker (L5, upper case, tracked), the name (L1 in Big Shoulders, stepping
/// down like the tile's), the facts, and the run strip full width (56) under both.
struct HeadBoard: View {
    let kicker: String?
    let name: String
    let genre: String?
    let art: Artwork?
    let first: String?
    let last: String?
    var years: [Int]? = nil
    var facts: [String?] = []
    /// Makes the board the link to the show; its name is then a line under the page's own title.
    var link: Route? = nil
    /// The genre in the kicker, as a link that opens Browse filtered to it (the series page only: an
    /// episode's board is itself the link to its show).
    var genreKey: String? = nil
    var kickerRest: String? = nil
    /// An ear drama's author facts, a line under the name.
    var credits: String? = nil
    /// A play: its cast fingerprint stands in the mark slot where a show has its run strip.
    var castScript: PlayScript? = nil
    /// The same, for a play known only by its library row.
    var cast: CastSummary? = nil
    /// The page's buttons, on the board where it runs across a tablet; a phone keeps them under it.
    var actions: AnyView? = nil
    @Environment(AppStore.self) private var store
    /// The picture's credit, under the board, when its license asks and the window shows it.
    var showsCredit = false
    @State private var width: CGFloat = 0

    static func side(forWidth width: CGFloat) -> CGFloat {
        #if !os(tvOS)
        if width >= wideFrom { return 240 }
        #endif
        return width >= 1024 ? 176 : width >= 600 ? 128 : 96
    }
    private var windowSide: CGFloat { link == nil ? Self.side(forWidth: width) : min(Self.side(forWidth: width), 176) }
    /// Past a phone's column the board is composed for the width: words and strip beside a large window.
    static let wideFrom: CGFloat = 760
    private var beside: Bool {
        #if !os(tvOS)
        width >= Self.wideFrom
        #else
        false
        #endif
    }
    /// An episode's board is a link to the show above the page's own title: strip beside the words
    /// too, but at the smaller window and name, so the episode's title leads.
    private var wide: Bool { beside && link == nil }
    /// The histogram needs height to read: 40 on a phone, 56 on an iPad or Mac, 96 across the room.
    static func stripHeight(forWidth width: CGFloat) -> CGFloat {
        #if os(tvOS)
        96
        #else
        width >= 600 ? 56 : 40
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            if let link {
                NavigationLink(value: link) { board }
                    #if os(tvOS)
                    .buttonStyle(.card)
                    #else
                    .buttonStyle(.plain)
                    .navigationLinkIndicatorVisibility(.hidden)
                    #endif
            } else {
                board
            }
            if showsCredit { PictureCredit(arts: [art], slot: windowSide) }
        }
    }

    /// The name; on a board that links to its show, followed by the chevron that says it opens.
    private var nameText: Text {
        guard link != nil else { return Text(verbatim: name) }
        let chevron = Text(Image(systemName: "chevron.right")).font(TypeRamp.bodyStrong)
        return Text("\(Text(verbatim: name))\u{00A0}\(chevron)")
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            if let genreKey {
                HStack(spacing: 0) {
                    Button { store.openBrowse(genre: genreKey) } label: {
                        Text(verbatim: GenreDisplay.name(genreKey).uppercased()).underline()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Browse \(GenreDisplay.name(genreKey))")
                    if let kickerRest, !kickerRest.isEmpty { Text(verbatim: " \u{00B7} " + kickerRest.uppercased()) }
                }
                .font(TypeRamp.caption)
                .tracking(1.2)
            } else if let kicker {
                Text(verbatim: kicker.uppercased())
                    .font(TypeRamp.caption)
                    .tracking(1.2)
            }
            nameText
                .font(wide ? GrammarType.wideHeadName(step: Grammar.headNameStep(name)) : GrammarType.headName(step: Grammar.headNameStep(name)))
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
            if let credits, !credits.isEmpty {
                Text(verbatim: credits).font(TypeRamp.caption.weight(.semibold))
            }
            EventLine(facts: facts, color: Color.onBoard(genre))
        }
        .foregroundStyle(Color.onBoard(genre))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var mark: some View {
        if let cast = cast ?? castScript.map(CastSummary.init(script:)) {
            CastFingerprint(cast: cast, onBoard: genre, height: Self.stripHeight(forWidth: width) / 3)
        } else if first != nil || last != nil || !(years ?? []).isEmpty {
            RunStrip(first: first, last: last, genre: genre, height: Self.stripHeight(forWidth: width), years: years, ownSpan: true)
        }
    }

    /// A play's board draws its cast in the window; every other board its picture or title block.
    @ViewBuilder private var window: some View {
        if let cast = cast ?? castScript.map(CastSummary.init(script:)) {
            CastWindow(cast: cast, genre: genre, side: windowSide)
        } else {
            PictureWindow(art: art, name: name, genre: genre, side: windowSide)
        }
    }

    private var board: some View {
        Group {
            if beside {
                HStack(alignment: .top, spacing: Spacing.s6) {
                    window
                    VStack(alignment: .leading, spacing: Spacing.s3) {
                        words
                        mark
                        if let actions { actions.environment(\.actionBoard, .some(genre)) }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    HStack(alignment: .top, spacing: Spacing.s4) {
                        window
                        words
                    }
                    mark
                }
            }
        }
        .padding(wide ? Spacing.s6 : Spacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.board(genre))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .accessibilityElement(children: genreKey == nil ? .combine : .contain)
        // Not spoken: tells the tap tier whether the window drew the picture or the title block.
        .accessibilityIdentifier(Grammar.windowFill(art, slot: Double(windowSide)) == .block ? "head-board-block" : "head-board")
    }
}
