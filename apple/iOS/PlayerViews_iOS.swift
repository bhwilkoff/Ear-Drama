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
                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.episode.displayTitle)
                            .font(TypeRamp.bodyStrong)
                            .foregroundStyle(Color.brandText)
                            .lineLimit(1)
                        Text(item.episode.seriesName)
                            .font(TypeRamp.caption)
                            .foregroundStyle(Color.brandTextMuted)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.s6) {
                Spacer(minLength: 0)
                if let item = player.item {
                    VStack(spacing: Spacing.s2) {
                        Text(item.episode.seriesName)
                            .font(TypeRamp.body)
                            .foregroundStyle(Color.brandTextMuted)
                        Text(item.episode.displayTitle)
                            .font(TypeRamp.pageTitle)
                            .foregroundStyle(Color.brandText)
                            .multilineTextAlignment(.center)
                        Text(verbatim: [AirDate.display(item.episode.airDate), item.episode.network]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(TypeRamp.tabular)
                            .foregroundStyle(Color.brandTextMuted)
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    ContentUnavailableView("Nothing playing", systemImage: "play.slash")
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
                    RoutePicker_iOS()
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("Play on another device")
                }
                .font(TypeRamp.body)

                if let message = player.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(TypeRamp.caption)
                        .foregroundStyle(Color.semanticError)
                }
                if !catalog.isOnline && !player.isLocal { OfflineNotice() }
                if let next = player.upNext.first {
                    Text("Next: \(next.displayTitle)")
                        .font(TypeRamp.caption)
                        .foregroundStyle(Color.brandTextMuted)
                        .lineLimit(1)
                }
            }
            .padding(Spacing.s6)
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
