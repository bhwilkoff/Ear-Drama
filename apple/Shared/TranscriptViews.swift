import SwiftUI

// R16, text is a peer of sound: an episode whose automatic transcript passed
// the quality gate (contract §3.1) can be read wherever it can be played. The
// text is fetched when opened, never bundled; the reader draws loading, error,
// and offline itself, and every platform labels it `Transcript.label`.

/// Loads the transcript on demand and draws its states.
struct TranscriptReader: View {
    let url: URL
    @Environment(CatalogStore.self) private var catalog
    @State private var phase: Phase = .loading
    @State private var attempt = 0

    private enum Phase: Equatable { case loading, loaded(URL, String), failed }
    private struct Key: Hashable { let url: URL; let attempt: Int; let online: Bool }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading")
            case let .loaded(_, text):
                TranscriptText(text: text)
            case .failed:
                ContentUnavailableView {
                    if catalog.isOnline {
                        Label("The transcript did not load.", systemImage: "exclamationmark.triangle")
                    } else {
                        Label("You are offline.", systemImage: "wifi.slash")
                    }
                } actions: {
                    Button("Try Again") { attempt += 1 }
                }
            }
        }
        // Coming back online retries a failed load; a loaded text is kept.
        .task(id: Key(url: url, attempt: attempt, online: catalog.isOnline)) {
            if case let .loaded(loadedURL, _) = phase, loadedURL == url { return }
            phase = .loading
            do {
                let text = try await Transcript.load(url)
                phase = .loaded(url, text)
            } catch {
                if !Task.isCancelled { phase = .failed }
            }
        }
    }
}

#if os(tvOS)
/// The ten-foot reader: paragraphs of a few sentences, each a focus stop, so
/// the remote scrolls the text; only the focused paragraph is bright.
private struct TranscriptText: View {
    let text: String

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: Spacing.s2) {
                ForEach(Array(Transcript.paragraphs(text).enumerated()), id: \.offset) { _, paragraph in
                    TranscriptParagraph_tvOS(text: paragraph)
                }
            }
            .padding(.horizontal, 90)
            .padding(.vertical, Spacing.s8)
        }
    }
}

private struct TranscriptParagraph_tvOS: View {
    let text: String
    @FocusState private var focused: Bool

    var body: some View {
        Text(text)
            .font(TypeRamp.body)
            .foregroundStyle(focused ? Color.brandText : Color.brandTextMuted)
            .frame(maxWidth: 1400, alignment: .leading)
            .padding(Spacing.s4)
            .background(RoundedRectangle(cornerRadius: Radius.card).fill(focused ? Color.brandSurfaceAlt : .clear))
            .focusable()
            .focused($focused)
    }
}

/// Full screen from Detail or Now Playing; Menu (Back) closes it.
struct TranscriptScreen_tvOS: View {
    let title: String
    let url: URL

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(title)
                    .font(TypeRamp.sectionHeader)
                    .foregroundStyle(Color.brandText)
                Text(Transcript.label)
                    .font(TypeRamp.caption)
                    .foregroundStyle(Color.brandTextMuted)
            }
            .padding(.horizontal, 90)
            .padding(.top, 60)
            .accessibilityElement(children: .combine)
            TranscriptReader(url: url)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.brandBackground.ignoresSafeArea())
    }
}
#else
/// Plain, selectable text at the reading size, in a readable measure.
private struct TranscriptText: View {
    let text: String

    var body: some View {
        ScrollView(.vertical) {
            Text(Transcript.lines(text).joined(separator: "\n"))
                .font(TypeRamp.body)
                .foregroundStyle(Color.brandText)
                .lineSpacing(Spacing.s1)
                .textSelection(.enabled)
                .frame(maxWidth: 680, alignment: .leading)
                .padding(Spacing.s4)
                .frame(maxWidth: .infinity)
        }
        .background(Color.brandBackground)
    }
}
#endif

#if os(iOS)
/// A sheet over Detail or the player.
struct TranscriptSheet_iOS: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TranscriptReader(url: url)
                .navigationTitle(Transcript.label)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
#endif

#if os(macOS)
/// What a transcript window opens: its own resizable window, so the text can
/// sit beside the main window while the episode plays.
struct TranscriptRef: Codable, Hashable {
    let title: String
    let url: URL

    static let windowID = "transcript"
}

struct TranscriptWindow_macOS: View {
    let ref: TranscriptRef

    var body: some View {
        TranscriptReader(url: ref.url)
            .frame(minWidth: 360, minHeight: 320)
            .navigationTitle(ref.title)
            .navigationSubtitle(Transcript.label)
    }
}
#endif
