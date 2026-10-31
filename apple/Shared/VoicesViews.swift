import SwiftUI

// Voices (contract §3.3 `voices`): the most heard people as round faces, a person's portrait or
// their monogram, each opening the person's page. Browse's third scope and Home's "Most heard
// voices" shelf read the same published list; a catalog without it has none, and nothing draws.

/// A voice: the round face over the name and the episodes they are heard in.
struct VoiceFace: View {
    let row: PersonRow
    var side: CGFloat = 84

    var body: some View {
        VStack(spacing: Spacing.s1) {
            PictureWindow(art: row.person.art, name: row.person.name, genre: nil, side: side, round: true)
            Text(verbatim: row.person.name)
                .font(TypeRamp.caption.weight(.semibold))
                .foregroundStyle(Color.brandText)
                .lineLimit(2)
            Text(verbatim: PersonRowLabel.count(row.episodes))
                .font(TypeRamp.caption)
                .foregroundStyle(Color.brandTextMuted)
                .lineLimit(1)
        }
        .multilineTextAlignment(.center)
        .frame(width: side + Spacing.s6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.person.name), \(PersonRowLabel.count(row.episodes))")
    }
}

/// The face as a link to the person's page.
struct VoiceLink: View {
    let row: PersonRow
    var side: CGFloat = 84

    var body: some View {
        NavigationLink(value: Route.person(row.person.id)) { VoiceFace(row: row, side: side) }
            #if os(tvOS)
            .buttonStyle(.card)
            #else
            .buttonStyle(.plain)
            .navigationLinkIndicatorVisibility(.hidden)
            #endif
            .accessibilityIdentifier("voice-face")
    }
}

/// Browse's Voices scope: the count, then the faces, most heard first.
struct VoicesBrowse: View {
    @Environment(CatalogStore.self) private var catalog
    @State private var voices: [PersonRow]?

    #if os(tvOS)
    private let side: CGFloat = 160
    #else
    private let side: CGFloat = 84
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            if let voices {
                if voices.isEmpty {
                    EmptyState("No voices listed yet", systemImage: "person.wave.2")
                } else {
                    Text(verbatim: countText(voices.count, "voice", "voices"))
                        .font(TypeRamp.bodyStrong)
                        .foregroundStyle(Color.brandText)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: side + Spacing.s6), spacing: Spacing.s3, alignment: .top)],
                              alignment: .leading, spacing: Spacing.s4) {
                        ForEach(voices) { VoiceLink(row: $0, side: side) }
                    }
                    PictureCredit(arts: voices.map(\.person.art), slot: side)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.top, Spacing.s6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .task(id: catalog.loadKey) {
            guard catalog.state == .ready else { return }
            voices = await catalog.voices()
        }
    }
}

/// Home's "Most heard voices": a row of faces that scrolls sideways, All opening Browse's scope.
struct VoicesShelf: View {
    let voices: [PersonRow]

    #if os(tvOS)
    private let side: CGFloat = 160
    #else
    private let side: CGFloat = 84
    #endif

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: Spacing.s3) {
                ForEach(voices) { VoiceLink(row: $0, side: side) }
            }
            #if os(tvOS)
            .padding(.horizontal, 60)
            .padding(.vertical, Spacing.s6)
            #else
            .padding(.horizontal, Spacing.s4)
            .padding(.vertical, Spacing.s2)
            #endif
        }
        .scrollIndicators(.hidden)
        #if os(tvOS)
        .scrollClipDisabled()
        #endif
    }
}
