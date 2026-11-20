#if os(iOS) || os(macOS)
import SwiftUI

// Item pages wear Home's hero (WEB-DESIGN §6.4g, iOS-DESIGN §4.3g, macOS-DESIGN §4.3g, Decision 081, Round 3 V7; owner,
// 2026-11-19: "We need to continue making the app more visually appealing, both from the home screen perspective ...
// and the individual item perspective."). The series, episode, person, play and finished ear drama pages open on the
// same board as Home's On the air: the window at tier L across the board's top on a phone and a 320 pt column beside the
// words from 560 pt, the words in the same order, then the strip. A picture keeps its own shape.

struct ItemHeadBoard: View {
    var kicker: AnyView? = nil
    let name: String
    let genre: String?
    /// The picture that leads, or nil for the label.
    var art: Artwork? = nil
    /// What the window draws when there is no picture: the label, at tier L.
    let label: LabelItem
    var round = false
    var facts: [String?] = []
    var credits: String? = nil
    var first: String? = nil
    var last: String? = nil
    var years: [Int]? = nil
    /// An episode's page marks its own year on the show's strip.
    var markYear: Int? = nil
    /// A play's mark where a show has its run strip.
    var cast: CastSummary? = nil
    /// A window of the caller's own (a play's opening drawn as a page), given its side.
    var customWindow: ((CGFloat) -> AnyView)? = nil
    @State private var failed = false

    private var shown: Artwork? { failed ? nil : ItemLead.shown(art) }
    private var hasMark: Bool { cast != nil || first != nil || last != nil || !(years ?? []).isEmpty }

    var body: some View {
        let ink = Color.onBoard(genre)
        VStack(alignment: .leading, spacing: Spacing.s2) {
            ItemHeadLayout(art: customWindow == nil ? shown : nil) {
                window
                words(ink)
                if hasMark { mark }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.board(genre))
            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(shown == nil && customWindow == nil ? "head-board-block" : "head-board")
            if let art = shown, art.credit != nil { PictureCredit(arts: [art], slot: 1) }
        }
        .onChange(of: art?.url) { failed = false }
    }

    /// The window fills the frame the layout gives it: a picture at its own shape, the label, or the caller's own.
    private var window: some View {
        GeometryReader { geo in
            Group {
                if let customWindow {
                    customWindow(geo.size.width)
                } else if let shown {
                    HeadPicture(art: shown, size: geo.size) { failed = true }
                } else {
                    let side = round ? max(geo.size.width - 2 * Spacing.s4, 1) : geo.size.width
                    LabelView(item: label, side: side)
                        .frame(width: side, height: side)
                        .clipShape(round ? AnyShape(Circle()) : AnyShape(Rectangle()))
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .accessibilityHidden(true)
    }

    private func words(_ ink: Color) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            if let kicker {
                kicker
                    .font(TypeRamp.caption)
                    .tracking(1.2)
                    .lineLimit(1)
            }
            Text(verbatim: name)
                .font(TypeRamp.pageTitle)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("item-head-name")
            if let credits, !credits.isEmpty {
                Text(verbatim: credits).font(TypeRamp.caption.weight(.semibold))
            }
            EventLine(facts: facts, color: ink)
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The strip takes the height the layout gives it (40 pt on a phone, 56 beside the words).
    @ViewBuilder private var mark: some View {
        if let cast {
            GeometryReader { geo in CastFingerprint(cast: cast, onBoard: genre, height: geo.size.height / 3) }
        } else {
            GeometryReader { geo in
                RunStrip(first: first, last: last, genre: genre, height: geo.size.height, years: years, ownSpan: true, markYear: markYear)
            }
        }
    }
}

/// The board's one layout (WEB-DESIGN §6.4g): the window at the frame `ItemLead.window` gives its picture, the words, and the
/// strip. Measured from the proposal in one pass, so the board is the same height whenever it is drawn.
private struct ItemHeadLayout: Layout {
    let art: Artwork?

    private struct Frame {
        let window: CGSize
        let plate: Bool
        let beside: Bool
        let pad: CGFloat
        let words: CGFloat
        let markHeight: CGFloat
    }

    private func frame(_ width: CGFloat, _ subviews: Subviews) -> (Frame, CGFloat) {
        let win = ItemLead.window(art: art, width: width)
        let beside = width >= ItemLead.besideFrom
        let pad = beside ? Spacing.s6 : Spacing.s4
        let sideBySide = beside && !win.plate
        let wordsWidth = max(width - 2 * pad - (sideBySide ? win.size.width : 0), 1)
        let words = subviews[1].sizeThatFits(ProposedViewSize(width: wordsWidth, height: nil)).height
        let markHeight: CGFloat = subviews.count > 2 ? (beside ? 56 : 40) : 0
        let gap = markHeight > 0 ? Spacing.s3 : 0
        let column = pad + words + gap + markHeight + pad
        let height = sideBySide ? max(win.size.height, column) : win.size.height + column
        return (Frame(window: win.size, plate: win.plate, beside: beside, pad: pad, words: words, markHeight: markHeight), height)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 390
        return CGSize(width: width, height: frame(width, subviews).1)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (f, height) = frame(bounds.width, subviews)
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(f.window))
        let sideBySide = f.beside && !f.plate
        let x = bounds.minX + f.pad + (sideBySide ? f.window.width : 0)
        let wordsWidth = max(bounds.width - 2 * f.pad - (sideBySide ? f.window.width : 0), 1)
        let top = bounds.minY + (sideBySide ? 0 : f.window.height) + f.pad
        subviews[1].place(at: CGPoint(x: x, y: top), anchor: .topLeading, proposal: ProposedViewSize(width: wordsWidth, height: f.words))
        if subviews.count > 2 {
            let y = sideBySide ? bounds.minY + height - f.pad - f.markHeight : top + f.words + Spacing.s3
            subviews[2].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: wordsWidth, height: f.markHeight))
        }
    }
}

/// A head picture at its own shape, never cropped, graded as everywhere; a failure is reported so the board falls back to the label.
private struct HeadPicture: View {
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

/// The kicker of an item page: a genre that opens Browse, a show that opens its page, or plain words.
enum ItemKicker {
    static func genre(_ key: String, rest: String?) -> AnyView {
        AnyView(ItemGenreKicker(key: key, rest: rest))
    }

    static func show(_ name: String, key: String) -> AnyView {
        AnyView(NavigationLink(value: Route.series(key)) { Text(verbatim: name.uppercased()).underline() }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(name)")
            .accessibilityIdentifier("item-head-show"))
    }

    static func text(_ words: String) -> AnyView { AnyView(Text(verbatim: words.uppercased())) }
}

private struct ItemGenreKicker: View {
    let key: String
    let rest: String?
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: 0) {
            Button { store.openBrowse(genre: key) } label: {
                Text(verbatim: GenreDisplay.name(key).uppercased()).underline()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Browse \(GenreDisplay.name(key))")
            if let rest, !rest.isEmpty { Text(verbatim: " \u{00B7} " + rest.uppercased()) }
        }
    }
}

/// A series' further pictures (`series.gallery`): one row of whole pictures at one height, shown ungraded, each captioned
/// with its credit (else the site its evidence is on) linked to that evidence. Drawn only from `ItemLead.gallery`.
struct SeriesGallery: View {
    let pictures: [Artwork]
    @Environment(\.displayScale) private var scale
    #if os(macOS)
    private let height: CGFloat = 200
    #else
    private let height: CGFloat = 160
    #endif

    static func caption(_ art: Artwork) -> String {
        if let credit = art.credit, !credit.isEmpty { return credit }
        let host = art.evidence?.host(percentEncoded: false) ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Spacing.s3) {
                ForEach(pictures, id: \.url) { art in
                    let w = height * art.drawnAspect
                    VStack(alignment: .leading, spacing: Spacing.s1) {
                        AsyncImage(url: art.url(pixels: Double(w * scale))) { phase in
                            if let image = phase.image { image.resizable().aspectRatio(contentMode: .fit) } else { Color.brandSurfaceAlt }
                        }
                        .frame(width: w, height: height)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .accessibilityHidden(true)
                        ArtCredit(credit: Self.caption(art), evidence: art.evidence)
                            .lineLimit(1)
                            .frame(width: w, alignment: .leading)
                    }
                }
            }
        }
        .accessibilityIdentifier("series-gallery")
    }
}
#endif
