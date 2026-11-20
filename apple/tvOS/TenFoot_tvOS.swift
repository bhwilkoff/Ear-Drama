#if os(tvOS)
import SwiftUI

// The living room's parts (tvOS-DESIGN §3.0): the hero, the two cards, the round face and the shelf.
// Every page is a ScrollView of these inside the system's safe area, the one margin.

enum TV {
    static let rowGap: CGFloat = 72
    static let cardGap: CGFloat = 40
    static let wideCard = CGSize(width: 640, height: 236)
    static let dateCard = CGSize(width: 420, height: 236)
    static let heroPicture: CGFloat = 460
    /// A tab root's hero starts under the tab bar's pill.
    static let rootClearance: CGFloat = 76

    /// The largest window a picture holds up at, up to `bound` (`Grammar.windowFill`'s floor).
    static func windowSide(_ art: Artwork?, bound: CGFloat) -> CGFloat {
        guard let art, let w = art.width, let h = art.height, w > 0, h > 0 else { return bound }
        guard let rect = art.cropRect(least: 1) else { return min(bound, CGFloat(min(w, h)) * 2) }
        return min(bound, CGFloat(rect.h * Double(h)).rounded(.down))
    }
}

/// A focusable with no plate of its own: what it draws reads `\.isFocused` (a face, a field's cell).
struct TVBareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Focus on something with no plate of its own, under `TVBareButtonStyle` (a field's cell).
struct TVFocusRing<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.isFocused) private var focused

    var body: some View {
        content()
            .background { RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(focused ? 0.16 : 0)) }
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white, lineWidth: 4).opacity(focused ? 1 : 0) }
            .scaleEffect(focused ? 1.08 : 1)
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

// MARK: - The hero

/// The show's years as bars on its own span, so a short run is not a mostly empty axis.
struct TVRunStrip: View {
    let years: [Int]?
    let genre: String?
    /// An episode's head marks its own year: that bar at full ink, the rest at 45 %.
    var markYear: Int? = nil

    var body: some View {
        if let bars = Grammar.runBars(years: years), let lo = bars.first?.from, let hi = bars.last?.to, hi > lo {
            let ink = Color.onBoard(genre)
            GeometryReader { geo in
                let scale = geo.size.width / CGFloat(hi - lo)
                ZStack(alignment: .bottomLeading) {
                    Rectangle().fill(ink.opacity(0.3)).frame(height: 1)
                    ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                        Rectangle().fill(ink.opacity(Grammar.barDimmed(from: bar.from, markYear: markYear) ? 0.45 : 1))
                            .frame(width: max(2, CGFloat(bar.to - bar.from) * scale - 2),
                                   height: max(3, geo.size.height * CGFloat(bar.height)))
                            .offset(x: CGFloat(bar.from - lo) * scale)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
            }
            .frame(width: 520, height: 48)
            .accessibilityHidden(true)
        }
    }
}

struct TVHero<Actions: View>: View {
    var kicker: String? = nil
    let title: String
    var subtitle: String? = nil
    var facts: [String?] = []
    let genre: String?
    let art: Artwork?
    /// The name the window's letters are cut from.
    var pictureName: String? = nil
    var round = false
    var years: [Int]? = nil
    var markYear: Int? = nil
    var progress: Double? = nil
    var clearance: CGFloat = 0
    /// What the window's label draws when there is no picture: the show's run and network, the evening's year ticked.
    var label: LabelItem? = nil
    @ViewBuilder let actions: () -> Actions
    @State private var failed = false

    /// The picture the window holds: at its own shape, never cropped or barred (tvOS-DESIGN §3.0, WEB-DESIGN §6.4g).
    private var shown: Artwork? { failed ? nil : ItemLead.shown(art) }
    /// The widest a picture stands: a plate wider than the label's square, the same 460 pt tall.
    private var plateWidth: CGFloat { 760 }

    var body: some View {
        let picture = shown.map { $0.fitted(in: CGSize(width: plateWidth, height: TV.heroPicture)) }
        let window = picture ?? CGSize(width: TV.heroPicture, height: TV.heroPicture)
        HStack(alignment: .center, spacing: 64) {
            VStack(alignment: .leading, spacing: Spacing.s6) {
                words.foregroundStyle(Color.onBoard(genre))
                // Outside the ink: a focused button inverts its own label.
                if Actions.self != EmptyView.self {
                    HStack(spacing: Spacing.s6) { actions() }
                        .lineLimit(1)
                        .focusSection()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            Group {
                if let shown, let picture {
                    TVHeroPicture(art: shown, size: picture) { failed = true }
                } else {
                    PictureWindow(art: nil, name: pictureName ?? title, genre: genre, side: TV.heroPicture, round: round, label: label)
                }
            }
            .frame(width: window.width, height: window.height, alignment: .trailing)
            .onChange(of: art?.url) { failed = false }
        }
        .padding(.top, clearance)
        .padding(.bottom, 56)
        .background { Color.board(genre).padding(.horizontal, -200).padding(.top, -400) }
    }

    private var words: some View {
        let ink = Color.onBoard(genre)
        return VStack(alignment: .leading, spacing: Spacing.s2) {
            if let kicker, !kicker.isEmpty {
                Text(verbatim: kicker.uppercased())
                    .font(TypeRamp.caption)
                    .tracking(1.2)
                    .lineLimit(1)
            }
            Text(verbatim: title)
                .font(TypeRamp.pageTitle)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
            if let subtitle, !subtitle.isEmpty {
                Text(verbatim: subtitle)
                    .font(TypeRamp.bodyStrong)
                    .lineLimit(2)
            }
            EventLine(facts: facts, color: ink)
            if let progress, progress > 0, progress < 1 {
                ProgressView(value: progress)
                    .tint(ink)
                    .frame(width: 520)
                    .padding(.top, Spacing.s1)
                    .accessibilityHidden(true)
            }
            TVRunStrip(years: years, genre: genre, markYear: markYear)
                .padding(.top, Spacing.s2)
            if let credit = shown?.credit {
                Text(verbatim: "Picture: \(credit)")
                    .font(TypeRamp.caption)
                    .foregroundStyle(ink.opacity(0.7))
                    .lineLimit(1)
            }
        }
    }
}

/// A hero picture at its own shape, graded as everywhere; a failed load is reported so the hero falls back to the label.
private struct TVHeroPicture: View {
    let art: Artwork
    let size: CGSize
    let onFail: () -> Void
    @Environment(\.displayScale) private var scale

    var body: some View {
        GradedImage(url: art.url(pixels: Double(size.width * scale)), grade: Grammar.gradeOf(art), onFail: onFail)
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .accessibilityHidden(true)
    }
}

// MARK: - The cards

/// The wide card (§3.0): the window, then the line above, the title, the line under it, the foot.
struct TVWideCard: View {
    let art: Artwork?
    let name: String
    let genre: String?
    var top: String? = nil
    let title: String
    /// The station's name: display type, upper case.
    var display = false
    var sub: String? = nil
    var foot: String? = nil
    var badge: String? = nil
    var progress: Double? = nil

    var body: some View {
        let ink = Color.onBoard(genre)
        HStack(spacing: 0) {
            PictureWindow(art: art, name: name, genre: genre, side: TV.wideCard.height)
            VStack(alignment: .leading, spacing: 2) {
                if top != nil || badge != nil {
                    HStack(spacing: Spacing.s2) {
                        if let top { Text(verbatim: top).font(TypeRamp.caption).lineLimit(1) }
                        Spacer(minLength: 0)
                        if let badge {
                            Text(verbatim: badge)
                                .font(TypeRamp.caption.weight(.semibold))
                                .foregroundStyle(Color.brandOnPrimary)
                                .padding(.horizontal, Spacing.s2)
                                .background(Capsule().fill(Color.brandPrimary))
                        }
                    }
                }
                Text(verbatim: display ? title.uppercased() : title)
                    .font(display ? TypeRamp.sectionHeader : TypeRamp.bodyStrong)
                    .lineLimit(sub == nil ? 3 : 2)
                    .minimumScaleFactor(display ? 0.7 : 0.75)
                if let sub { Text(verbatim: sub).font(TypeRamp.caption).lineLimit(2) }
                Spacer(minLength: 0)
                if let foot { Text(verbatim: foot).font(TypeRamp.caption).lineLimit(display ? 2 : 1).opacity(0.8) }
                if let progress, progress > 0, progress < 1 {
                    ProgressView(value: progress).tint(ink).accessibilityHidden(true)
                }
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal, Spacing.s4)
            .padding(.vertical, Spacing.s3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(ink)
        .frame(width: TV.wideCard.width, height: TV.wideCard.height)
        .background(Color.board(genre))
    }
}

/// The date card (§3.0): a list of one show, so the window would only repeat itself.
struct TVDateCard: View {
    let episode: EpisodeRow
    var note: String? = nil
    @Environment(ListeningHistory.self) private var history

    var body: some View {
        let ink = Color.onBoard(episode.seriesGenre)
        let progress = history.progress(for: episode.id)
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(verbatim: Self.date(episode))
                    .font(TypeRamp.sectionHeader)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if progress ?? 0 >= 1 {
                    Image(systemName: "checkmark.circle.fill").accessibilityLabel("Played")
                }
            }
            Text(verbatim: episode.displayTitle)
                .font(TypeRamp.bodyStrong)
                .lineLimit(3)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if let foot = note ?? episode.durationText {
                Text(verbatim: foot).font(TypeRamp.caption).lineLimit(1).opacity(0.8)
            }
            if let progress, progress > 0, progress < 1 {
                ProgressView(value: progress).tint(ink).accessibilityHidden(true)
            }
        }
        .foregroundStyle(ink)
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s3)
        .frame(width: TV.dateCard.width, height: TV.dateCard.height, alignment: .topLeading)
        .background(Color.board(episode.seriesGenre))
    }

    private static func date(_ episode: EpisodeRow) -> String {
        if episode.airDate != nil { return AirDate.medium(episode.airDate) }
        return episode.number.map { "No. \($0)" } ?? "Undated"
    }
}

/// An episode as a wide card, opening its page; the date first, the show under the title.
struct TVEpisodeLink<Menu: View>: View {
    let episode: EpisodeRow
    var quote: String? = nil
    @ViewBuilder let menu: () -> Menu
    @Environment(ListeningHistory.self) private var history

    var body: some View {
        NavigationLink(value: Route.episode(episode.id)) {
            TVWideCard(art: episode.seriesWindowArt, name: episode.seriesName, genre: episode.seriesGenre,
                       top: AirDate.medium(episode.airDate), title: episode.displayTitle,
                       sub: quote, foot: episode.seriesName, progress: history.progress(for: episode.id))
        }
        .buttonStyle(.card)
        .contextMenu { menu() }
    }
}

extension TVEpisodeLink where Menu == QueueMenuItem {
    init(episode: EpisodeRow, quote: String? = nil) {
        self.init(episode: episode, quote: quote) { QueueMenuItem(episodeID: episode.id) }
    }
}

// MARK: - A face

/// A person: the circle, the name in two lines' room, a line under it. Focus lifts and rings the circle.
struct TVFace: View {
    let art: Artwork?
    let name: String
    var line: String? = nil
    var side: CGFloat = 190
    @Environment(\.isFocused) private var focused

    var body: some View {
        VStack(spacing: Spacing.s3) {
            PictureWindow(art: art, name: name, genre: nil, side: side, round: true)
                .overlay { Circle().strokeBorder(Color.white, lineWidth: 5).opacity(focused ? 1 : 0) }
                .scaleEffect(focused ? 1.12 : 1)
                .shadow(color: .black.opacity(focused ? 0.5 : 0), radius: 18, y: 10)
            VStack(spacing: 2) {
                Text(verbatim: name)
                    .font(TypeRamp.caption.weight(.semibold))
                    .foregroundStyle(Color.brandText)
                    .lineLimit(2, reservesSpace: true)
                if let line {
                    Text(verbatim: line)
                        .font(TypeRamp.caption)
                        .foregroundStyle(Color.brandTextMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .multilineTextAlignment(.center)
            .offset(y: focused ? 10 : 0)
        }
        .frame(width: side + 56)
        .animation(.easeOut(duration: 0.15), value: focused)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.map { "\(name), \($0)" } ?? name)
    }
}

// MARK: - The shelf

/// A section title over one row that scrolls past the margin to the screen's edge (§3.1).
struct TVShelf<Trailing: View, Content: View>: View {
    var title: String? = nil
    /// Tiles share a name height, which needs every tile laid out; cards are one height and can be lazy.
    var lazy = false
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            if let title {
                SectionHead(title: title) { trailing() }
            }
            ScrollView(.horizontal) {
                Group {
                    if lazy {
                        LazyHStack(alignment: .top, spacing: TV.cardGap) { content() }
                    } else {
                        HStack(alignment: .top, spacing: TV.cardGap) { content() }
                            .sharesNameHeight()
                    }
                }
                .padding(.vertical, Spacing.s4)
            }
            .scrollClipDisabled()
            .scrollIndicators(.hidden)
        }
        .focusSection()
    }
}

extension TVShelf where Trailing == EmptyView {
    init(title: String? = nil, lazy: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, lazy: lazy, trailing: { EmptyView() }, content: content)
    }
}
#endif
