import SwiftUI

// The parts the series page and the episode page share (WEB-DESIGN §6.4d, iOS-/macOS-/tvOS-DESIGN
// R11d): one button row that never wraps apart, the picture credit, and the round faces of who is
// on the air.

/// What a series' head board says: the genre then the networks as the kicker; the years or
/// "Undated", then the count of episodes, as the facts.
enum SeriesHead {
    static func kicker(_ series: SeriesRow) -> String? {
        let parts = [series.genre.map(GenreDisplay.name), series.networks.isEmpty ? nil : series.networks.joined(separator: " \u{00B7} ")]
            .compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    /// The entry point a stranger reads first: when it ran, how much survives, and whose voice leads it
    /// (`series.star`, the face the catalog chose; never a name typed here).
    static func facts(_ series: SeriesRow) -> [String?] {
        [series.yearSpan ?? "Undated", series.episodeCount == 1 ? "1 episode" : "\(series.episodeCount.formatted()) episodes",
         series.face.map { "With \($0.name)" }]
    }
}

// MARK: - The button row

private struct ActionsFoldedKey: EnvironmentKey {
    static let defaultValue = false
}

private struct ActionBoardKey: EnvironmentKey {
    static let defaultValue: String?? = nil
}

extension EnvironmentValues {
    /// The board a button row stands on, by genre: its controls take the board's one ink.
    var actionBoard: String?? {
        get { self[ActionBoardKey.self] }
        set { self[ActionBoardKey.self] = newValue }
    }

    /// True when the row is too narrow for labels: its secondary buttons show their icons alone.
    var actionsFolded: Bool {
        get { self[ActionsFoldedKey.self] }
        set { self[ActionsFoldedKey.self] = newValue }
    }
}

/// A secondary button's label: the title and icon, or the icon alone in a folded row, the title
/// kept as the accessible name.
struct ActionLabel: View {
    let title: String
    let systemImage: String
    @Environment(\.actionsFolded) private var folded

    var body: some View {
        if folded {
            Image(systemName: systemImage).accessibilityLabel(title)
        } else {
            Label(title, systemImage: systemImage).lineLimit(1)
        }
    }
}

#if !os(tvOS)
private struct PageActionLabelStyle: LabelStyle {
    let iconOnly: Bool

    func makeBody(configuration: Configuration) -> some View {
        if iconOnly {
            configuration.icon
        } else {
            HStack(spacing: Spacing.s2) { configuration.icon; configuration.title }
        }
    }
}

private struct ActionButtonStyle: ButtonStyle {
    let primary: Bool
    @Environment(\.actionsFolded) private var folded
    @Environment(\.actionBoard) private var board
    @Environment(\.isEnabled) private var enabled

    private var fill: Color {
        if let board { return primary ? Color.onBoard(board) : .clear }
        return primary ? Color.brandPrimary : Color.brandSurfaceAlt
    }

    private var ink: Color {
        if let board { return primary ? Color.board(board) : Color.onBoard(board) }
        return primary ? Color.brandOnPrimary : Color.brandText
    }

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control)
        // A List row's automatic label style sets the icon in its own column (a wide gap before the
        // title); the row says what it means: icon and title together, or the icon alone when folded.
        return configuration.label
            .labelStyle(PageActionLabelStyle(iconOnly: folded && !primary))
            .font(TypeRamp.bodyStrong)
            .lineLimit(1)
            .foregroundStyle(ink)
            .padding(.horizontal, folded && !primary ? 0 : Spacing.s4)
            .frame(minWidth: 44, maxWidth: primary && folded ? .infinity : nil, minHeight: 44)
            .background(fill, in: shape)
            .overlay { if !primary { shape.strokeBorder(board.map { Color.onBoard($0).opacity(0.5) } ?? Color.brandBorder, lineWidth: 1) } }
            .contentShape(shape)
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}
#endif

extension View {
    /// The look of a page button: filled for the one primary, a bordered 44 pt control otherwise.
    /// The Apple TV keeps the system button, whose focus is the only emphasis.
    @ViewBuilder func pageAction(primary: Bool = false) -> some View {
        #if os(tvOS)
        self
        #else
        buttonStyle(ActionButtonStyle(primary: primary))
        #endif
    }
}

/// One row of buttons on one line, always: the primary takes the room and the secondary buttons
/// fold to their icons when the labels do not fit. Never a wrapping layout.
struct ActionRow<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        #if os(tvOS)
        HStack(spacing: Spacing.s6) { content() }
            .focusSection()
        #else
        ViewThatFits(in: .horizontal) {
            // fixedSize makes a variant's smallest width its full width: without it a label's
            // truncated width "fits", and the row squeezes every title down to a clipped sliver.
            HStack(spacing: Spacing.s2) { content().fixedSize(horizontal: true, vertical: false); Spacer(minLength: 0) }
            HStack(spacing: Spacing.s2) { content() }.environment(\.actionsFolded, true)
        }
        #endif
    }
}

// MARK: - The picture credit

/// The credit a license asks for, linked to the file page, for each picture a window shows. A
/// required fact, so it is on screen; nothing when no shown picture owes one.
struct PictureCredit: View {
    let arts: [Artwork?]
    let slot: CGFloat

    var body: some View {
        var seen = Set<URL>()
        let owed = arts.compactMap { $0 }.filter { art in
            guard art.credit != nil, Grammar.windowFill(art, slot: Double(slot)) != .block else { return false }
            return seen.insert(art.evidence ?? art.url).inserted
        }
        if !owed.isEmpty {
            FlowLayout(spacing: Spacing.s1) {
                Text("Picture:").font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                ForEach(owed.indices, id: \.self) { i in
                    HStack(spacing: Spacing.s1) {
                        if i > 0 { Text(verbatim: "\u{00B7}").font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted) }
                        if let credit = owed[i].credit { ArtCredit(credit: credit, evidence: owed[i].evidence) }
                    }
                }
            }
        }
    }
}

// MARK: - On the air

/// The cast, in billing order, as round 72 pt windows over the name and the character; a face
/// with no picture is the title block. A name with a page opens it.
struct OnAirFaces: View {
    let credits: [Credit]
    let genre: String?
    /// Where a face opens a page without a navigation stack of its own (Now Playing's sheet).
    var open: ((Route) -> Void)? = nil

    #if !os(tvOS)
    private let columns = [GridItem(.adaptive(minimum: 88), spacing: Spacing.s2, alignment: .top)]
    #endif

    var body: some View {
        #if os(tvOS)
        TVShelf {
            ForEach(credits) { credit in
                let face = TVFace(art: credit.art, name: credit.name, line: credit.character.map { "as \($0)" }, side: 160)
                if credit.personID.isEmpty {
                    face
                } else if let open {
                    Button { open(.person(credit.personID)) } label: { face }
                        .buttonStyle(TVBareButtonStyle())
                } else {
                    NavigationLink(value: Route.person(credit.personID)) { face }
                        .buttonStyle(TVBareButtonStyle())
                }
            }
        }
        #else
        LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.s4) {
            ForEach(credits) { credit in
                if credit.personID.isEmpty {
                    OnAirFace(credit: credit, genre: genre)
                } else if let open {
                    Button { open(.person(credit.personID)) } label: { OnAirFace(credit: credit, genre: genre) }
                        .buttonStyle(.plain)
                } else {
                    NavigationLink(value: Route.person(credit.personID)) {
                        OnAirFace(credit: credit, genre: genre)
                    }
                    .buttonStyle(.plain)
                    .navigationLinkIndicatorVisibility(.hidden)
                }
            }
        }
        #endif
    }
}

private struct OnAirFace: View {
    let credit: Credit
    let genre: String?
    #if os(macOS)
    @State private var hovering = false
    #endif

    var body: some View {
        VStack(spacing: Spacing.s1) {
            PictureWindow(art: credit.art, name: credit.name, genre: genre, side: 72, round: true)
            Text(verbatim: credit.name)
                .font(TypeRamp.caption.weight(.semibold))
                .foregroundStyle(Color.brandText)
            if let character = credit.character {
                Text(verbatim: "as \(character)")
                    .font(TypeRamp.caption)
                    .foregroundStyle(Color.brandTextMuted)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        #if os(macOS)
        .opacity(hovering ? 0.8 : 1)
        .onHover { hovering = $0 }
        #endif
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(credit.character.map { "\(credit.name), as \($0)" } ?? credit.name)
    }
}

#if !os(tvOS)
// MARK: - The wide page

private struct WideColumnsKey: EnvironmentKey {
    static let defaultValue = 2
}

private extension EnvironmentValues {
    var wideColumns: Int {
        get { self[WideColumnsKey.self] }
        set { self[WideColumnsKey.self] = newValue }
    }
}

/// A series or person page at regular width (iOS-DESIGN R11g): the head board and shelves across the
/// whole page, and its rows two across, each column a phone's measure. A list one row wide leaves
/// a tablet's margins empty or its rows too long to read across.
struct WidePage<Content: View>: View {
    /// The measure a page of reading keeps, centered; nil spans the window.
    var measure: CGFloat? = nil
    @ViewBuilder let content: () -> Content
    @State private var width: CGFloat = 0

    private var columns: Int {
        #if os(macOS)
        if width >= 1320 { return 3 }
        #endif
        return width >= 700 ? 2 : 1
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.s6) { content() }
                .padding(.horizontal, Spacing.s6)
                .padding(.vertical, Spacing.s4)
                .environment(\.wideColumns, columns)
                .frame(maxWidth: measure ?? .infinity)
                .frame(maxWidth: .infinity)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        #if os(iOS)
        .background(Color(uiColor: .systemGroupedBackground))
        #endif
    }
}

/// A page's body: a `WidePage` on the Mac (macOS-DESIGN §4.0a), a `List` elsewhere.
struct PageBody<Content: View>: View {
    var measure: CGFloat? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        #if os(macOS)
        WidePage(measure: measure, content: content)
        #else
        List(content: content)
        #endif
    }
}

/// A titled run of rows in a `PageBody`: a `WideSection` on the Mac, a `Section` elsewhere.
struct PageRows<Rows: View>: View {
    let title: String
    @ViewBuilder let rows: () -> Rows

    init(_ title: String, @ViewBuilder rows: @escaping () -> Rows) {
        self.title = title
        self.rows = rows
    }

    var body: some View {
        #if os(macOS)
        WideSection(title: title, rows: rows)
        #else
        Section(title, content: rows)
        #endif
    }
}

#if os(macOS)
/// Two things read side by side once the page is wide enough, stacked otherwise.
struct TwoPanes<Left: View, Right: View>: View {
    @ViewBuilder let left: () -> Left
    @ViewBuilder let right: () -> Right
    @Environment(\.wideColumns) private var count

    var body: some View {
        let layout = count > 1 ? AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.s8))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.s6))
        layout {
            VStack(alignment: .leading, spacing: Spacing.s4) { left() }
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: Spacing.s4) { right() }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
#endif

/// A `PageBody`'s section: its heading close over its rows, the page's spacing between sections.
struct PageSection<Content: View, Header: View>: View {
    @ViewBuilder let content: () -> Content
    @ViewBuilder let header: () -> Header

    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: Spacing.s3) {
            header()
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        #else
        Section(content: content, header: header)
        #endif
    }
}

extension PageSection where Header == EmptyView {
    init(@ViewBuilder content: @escaping () -> Content) {
        self.init(content: content, header: { EmptyView() })
    }
}

extension PageSection where Header == PageSectionTitle {
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(content: content, header: { PageSectionTitle(title: title) })
    }
}

/// A section's plain heading: the List's own on iOS, the row heading's weight on a Mac page.
struct PageSectionTitle: View {
    let title: String

    var body: some View {
        Text(verbatim: title)
            #if os(macOS)
            .font(TypeRamp.bodyStrong)
            .foregroundStyle(Color.brandText)
            .accessibilityAddTraits(.isHeader)
            #endif
    }
}

/// A run of rows under its heading (a season, a show), two across, in reading order.
struct WideSection<Rows: View>: View {
    var title: String? = nil
    @ViewBuilder let rows: () -> Rows
    @Environment(\.wideColumns) private var count

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            if let title {
                Text(verbatim: title)
                    .font(TypeRamp.bodyStrong)
                    .foregroundStyle(Color.brandText)
                    .accessibilityAddTraits(.isHeader)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.s6, alignment: .top), count: count),
                      alignment: .leading, spacing: 0) { rows() }
        }
    }
}

#if os(macOS)
/// The pointer's mark on a page row, where a tile lifts: a wash behind the row, past its edges.
private struct RowHover: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: Radius.control)
                    .fill(Color.brandSurfaceAlt)
                    .padding(.horizontal, -Spacing.s1)
                    .opacity(hovering ? 1 : 0)
            }
            .onHover { hovering = $0 }
    }
}
#endif

extension View {
    /// A row outside a List: its own hairline, under the words as the List's separator is.
    func wideRow() -> some View {
        buttonStyle(.plain)
            .padding(.vertical, Spacing.s1)
            #if os(macOS)
            .modifier(RowHover())
            #endif
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.brandBorder).frame(height: 0.5).padding(.leading, 48 + Spacing.s3)
            }
    }

    /// A row in a `PageBody`: a `wideRow` on the Mac; a List draws its own elsewhere.
    @ViewBuilder func pageRow() -> some View {
        #if os(macOS)
        wideRow()
        #else
        self
        #endif
    }

    /// A shelf that scrolls to the edge of a `PageBody`, past the page's margin, on the Mac.
    @ViewBuilder func pageBleed() -> some View {
        #if os(macOS)
        padding(.horizontal, -Spacing.s6)
        #else
        self
        #endif
    }
}
#endif

/// The page's column: at regular width the content keeps a readable measure and the head board
/// spans it, instead of a portrait on the left and a wide empty area.
struct ReadableColumn: ViewModifier {
    var width: CGFloat = 720

    func body(content: Content) -> some View {
        #if os(tvOS)
        content
        #else
        content
            .frame(maxWidth: width)
            .frame(maxWidth: .infinity)
            #if os(iOS)
            // The list's own grouped backdrop stops at the column; the same color fills the margins.
            .background(Color(uiColor: .systemGroupedBackground))
            #endif
        #endif
    }
}
