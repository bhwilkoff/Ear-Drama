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

    static func facts(_ series: SeriesRow) -> [String?] {
        [series.yearSpan ?? "Undated", series.episodeCount == 1 ? "1 episode" : "\(series.episodeCount.formatted()) episodes"]
    }
}

// MARK: - The button row

private struct ActionsFoldedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
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
private struct ActionButtonStyle: ButtonStyle {
    let primary: Bool
    @Environment(\.actionsFolded) private var folded
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control)
        return configuration.label
            .font(TypeRamp.bodyStrong)
            .lineLimit(1)
            .foregroundStyle(primary ? Color.brandOnPrimary : Color.brandText)
            .padding(.horizontal, folded && !primary ? 0 : Spacing.s4)
            .frame(minWidth: 44, maxWidth: primary && folded ? .infinity : nil, minHeight: 44)
            .background(primary ? Color.brandPrimary : Color.brandSurfaceAlt, in: shape)
            .overlay { if !primary { shape.strokeBorder(Color.brandBorder, lineWidth: 1) } }
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
        if primary { tint(Color.brandPrimary) } else { self }
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
            HStack(spacing: Spacing.s2) { content(); Spacer(minLength: 0) }
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

    #if os(tvOS)
    private let columns = [GridItem(.adaptive(minimum: 180), spacing: Spacing.s6, alignment: .top)]
    #else
    private let columns = [GridItem(.adaptive(minimum: 88), spacing: Spacing.s2, alignment: .top)]
    #endif

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.s4) {
            ForEach(credits) { credit in
                if credit.personID.isEmpty {
                    OnAirFace(credit: credit, genre: genre)
                } else if let open {
                    Button { open(.person(credit.personID)) } label: { OnAirFace(credit: credit, genre: genre) }
                        #if os(tvOS)
                        .buttonStyle(.card)
                        #else
                        .buttonStyle(.plain)
                        #endif
                } else {
                    NavigationLink(value: Route.person(credit.personID)) {
                        OnAirFace(credit: credit, genre: genre)
                    }
                    #if os(tvOS)
                    .buttonStyle(.card)
                    #else
                    .buttonStyle(.plain)
                    #endif
                }
            }
        }
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

/// The page's column: at regular width the content keeps a readable measure and the head board
/// spans it, instead of a portrait on the left and a wide empty area.
struct ReadableColumn: ViewModifier {
    func body(content: Content) -> some View {
        #if os(tvOS)
        content
        #else
        content
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        #endif
    }
}
