#if os(iOS)
import AVKit
import SwiftUI

/// The mini player: what is playing and Play/Pause; a tap opens the player.
struct MiniPlayer_iOS: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(AppStore.self) private var store

    var body: some View {
        if let item = player.item {
            HStack(spacing: Spacing.s3) {
                Button {
                    store.isPlayerPresented = true
                } label: {
                    GrammarRow(visual: .window(item.episode.seriesWindowArt ?? item.face?.art,
                                               name: item.episode.seriesName, genre: item.episode.seriesGenre),
                               title: item.episode.displayTitle,
                               sub: [item.episode.seriesName, AirDate.display(item.episode.airDate)])
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Now playing: \(item.episode.displayTitle), \(item.episode.seriesName)")
                .accessibilityHint("Opens the player")

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .tint(Color.brandPrimary)
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            }
            .padding(.horizontal, Spacing.s4)
        }
    }
}

/// The full player, a sheet over the tabs.
struct PlayerSheet_iOS: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(CatalogStore.self) private var catalog
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var transcriptOpen = false
    @State private var sheetSize: CGSize = .zero

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.s6) {
                    controlsPage
                        .frame(minHeight: sheetSize.height)
                    if let item = player.item {
                        NowPlayingPeople(episode: item.episode) { route in
                            dismiss()
                            store.push(route)
                        }
                        .padding(.horizontal, Spacing.s6)
                        .padding(.bottom, Spacing.s6)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { sheetSize = $0 }
            .background(Color.brandBackground)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .accessibilityLabel("Close player")
                }
                if player.item?.episode.transcriptURL != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            transcriptOpen = true
                        } label: {
                            Image(systemName: "text.quote")
                        }
                        .accessibilityLabel(Transcript.label)
                    }
                }
            }
            .sheet(isPresented: $transcriptOpen) {
                if let url = player.item?.episode.transcriptURL { TranscriptSheet_iOS(url: url) }
            }
        }
    }

    /// The first screen: the picture, the title, the controls. The sections sit below it.
    private var controlsPage: some View {
        VStack(spacing: Spacing.s6) {
                Spacer(minLength: 0)
                if let item = player.item {
                    // R11a: full width, no taller than 44 % of the sheet, so Play stays on the first screen.
                    // A cap, not a fixed size: on the iPad's form sheet a fixed 44 % pushed the speed,
                    // sleep, and AirPlay row below the sheet's edge (iPad Pro 12.9, 2026-10-30), so the
                    // art takes what the controls leave, up to the cap.
                    NowPlayingArt(episode: item.episode, face: item.face)
                        .frame(maxWidth: max(0, sheetSize.width - 2 * Spacing.s4), maxHeight: sheetSize.height * 0.44)
                        .layoutPriority(1)
                        .accessibilityIdentifier("now-playing-art")
                    // Shown larger than a page's head, so a credited portrait carries its credit (Decision 069).
                    if let art = NowPlayingArt.art(item.episode, item.face), let credit = art.credit {
                        ArtCredit(credit: credit, evidence: art.evidence)
                    }
                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        Text(item.episode.displayTitle)
                            .font(TypeRamp.pageTitle)
                            .foregroundStyle(Color.brandText)
                            .multilineTextAlignment(.leading)
                        EventLine(facts: [item.episode.seriesName, AirDate.display(item.episode.airDate), item.episode.network])
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                } else {
                    EmptyState("Nothing playing", systemImage: "play.slash")
                }
                Spacer(minLength: 0)

                VStack(spacing: Spacing.s2) {
                    Scrubber()
                    TimeLabels()
                }
                TransportControls(large: true)

                HStack {
                    SpeedMenu()
                    Spacer()
                    SleepButton()
                    Spacer()
                    LevelToggle()
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                    Spacer()
                    ListenTogetherButton()
                        .labelStyle(.iconOnly)
                        .frame(width: 44, height: 44)
                    Spacer()
                    RoutePicker_iOS()
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("AirPlay")
                        .accessibilityIdentifier("RoutePicker")
                }
                .font(TypeRamp.body)

                FollowingHostNotice()
                if let message = player.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(TypeRamp.caption)
                        .foregroundStyle(Color.semanticError)
                }
                if !catalog.isOnline && !player.isLocal { OfflineNotice() }
                #if DEBUG
                if let diag = player.diagLine {
                    Text(diag).font(.caption2).monospaced().accessibilityIdentifier("PlaybackDiag")
                }
                #endif
                if let next = player.upNext.first {
                    Text("Next: \(next.displayTitle)")
                        .font(TypeRamp.caption)
                        .foregroundStyle(Color.brandTextMuted)
                        .lineLimit(1)
                }
                NextStoryButton()
                    .buttonStyle(.bordered)
                    .font(TypeRamp.body)
            }
            .padding(Spacing.s6)
    }
}

/// AirPlay's own route picker (AVKit), never a custom device list.
struct RoutePicker_iOS: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif
