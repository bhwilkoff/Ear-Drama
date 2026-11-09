import SwiftUI
#if os(iOS)
import SafariServices
#endif

// Words and pages that come from somewhere else, always with their source: a show's About in its
// source's own words (Wikipedia's text is CC BY-SA 4.0, so the source line is required), and an
// episode's script on the site that holds it. iOS opens the page in Safari over the app, the Mac in
// the default browser; the TV has no browser and shows the source as words.

#if os(iOS)
/// The system's in-app browser (`SFSafariViewController`): the page over the app, Done to come back.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// Presents a URL in `SafariView` as a sheet; nil presents nothing.
private struct SafariSheet: ViewModifier {
    @Binding var url: URL?

    func body(content: Content) -> some View {
        content.sheet(item: Binding(get: { url.map(PageURL.init) }, set: { url = $0?.url })) { page in
            SafariView(url: page.url).ignoresSafeArea()
        }
    }

    private struct PageURL: Identifiable {
        let url: URL
        var id: URL { url }
    }
}

extension View {
    func safariSheet(_ url: Binding<URL?>) -> some View { modifier(SafariSheet(url: url)) }
}
#endif

#if !os(tvOS)
/// A link to a page somewhere else: Safari over the app on iOS, the default browser on the Mac.
struct SourcePageLink<Label: View>: View {
    let url: URL
    @ViewBuilder let label: () -> Label
    #if os(iOS)
    @State private var open: URL?
    #endif

    var body: some View {
        #if os(iOS)
        Button { open = url } label: { label() }
            .safariSheet($open)
        #else
        Link(destination: url) { label() }
            .help(url.host() ?? url.absoluteString)
        #endif
    }
}

/// A show's About (iOS-DESIGN §4.3): the text in paragraphs, four lines until More opens it in
/// place, then the source line, which links to the source's page.
struct SeriesAboutBlock: View {
    let about: SeriesAbout
    @State private var expanded = false
    @State private var shownHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    static let collapsedLines = 4

    private var truncated: Bool { fullHeight > shownHeight + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(verbatim: about.text)
                .font(TypeRamp.body)
                .foregroundStyle(Color.brandText)
                .lineLimit(expanded ? nil : Self.collapsedLines)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shownHeight = $0 }
                .background(alignment: .topLeading) {
                    // The whole text at the same width, never drawn: More shows only when it is cut.
                    Text(verbatim: about.text)
                        .font(TypeRamp.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
                        .accessibilityHidden(true)
                }
                .textSelection(.enabled)
                .accessibilityIdentifier("series-about")
            HStack(spacing: Spacing.s4) {
                if truncated || expanded {
                    Button(expanded ? "Less" : "More") {
                        withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                    }
                    .buttonStyle(.borderless)
                    .accessibilityHint(expanded ? "Shows the first lines" : "Shows the whole description")
                }
                if let line = about.sourceLine {
                    if let link = about.link {
                        SourcePageLink(url: link.url) {
                            Text(verbatim: line).underline()
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Color.brandTextMuted)
                        .accessibilityIdentifier("series-about-source")
                    } else {
                        Text(verbatim: line).foregroundStyle(Color.brandTextMuted)
                    }
                }
                Spacer(minLength: 0)
            }
            .font(TypeRamp.caption)
        }
    }
}

/// "Read the script" on an episode (iOS-DESIGN §4.4). It asks `ScriptAccess.reading` how to open,
/// so the in-app reader that follows the voices replaces the source's page here, not in each screen.
struct ReadScriptControl: View {
    let access: ScriptAccess

    var body: some View {
        switch access.reading {
        case let .external(link):
            VStack(alignment: .leading, spacing: Spacing.s1) {
                SourcePageLink(url: link.url) {
                    ActionLabel(title: "Read the script", systemImage: "doc.text")
                }
                .pageAction()
                .accessibilityIdentifier("read-the-script")
                Text(verbatim: link.sourceName)
                    .font(TypeRamp.caption)
                    .foregroundStyle(Color.brandTextMuted)
            }
        case nil:
            EmptyView()
        }
    }
}
#endif

#if os(tvOS)
/// A show's About at ten feet (tvOS-DESIGN §4.3): a focusable block of the first lines that opens
/// the whole text; the source is said, never linked (no browser).
struct SeriesAboutBlock_tvOS: View {
    let about: SeriesAbout
    let title: String
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Button { open = true } label: {
                Text(verbatim: about.text)
                    .font(TypeRamp.body)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: 1400, alignment: .leading)
                    .padding(Spacing.s4)
            }
            .buttonStyle(.card)
            .accessibilityHint("Opens the whole description")
            if let line = about.sourceLine {
                Text(verbatim: line)
                    .font(TypeRamp.caption)
                    .foregroundStyle(Color.brandTextMuted)
            }
        }
        .focusSection()
        .fullScreenCover(isPresented: $open) {
            SeriesAboutReader_tvOS(about: about, title: title)
        }
    }
}

/// The whole About, full screen: the show's name, the source, then each paragraph a focus stop, so
/// the remote scrolls the text; Menu closes it.
private struct SeriesAboutReader_tvOS: View {
    let about: SeriesAbout
    let title: String

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: Spacing.s2) {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text(verbatim: title)
                        .font(TypeRamp.sectionHeader)
                        .foregroundStyle(Color.brandText)
                    if let line = about.sourceLine {
                        Text(verbatim: line)
                            .font(TypeRamp.caption)
                            .foregroundStyle(Color.brandTextMuted)
                    }
                }
                .accessibilityElement(children: .combine)
                .padding(.bottom, Spacing.s4)
                ForEach(Array(about.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    TranscriptParagraph_tvOS(text: paragraph)
                }
            }
            .padding(.horizontal, 90)
            .padding(.vertical, 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.brandBackground.ignoresSafeArea())
    }
}
#endif
