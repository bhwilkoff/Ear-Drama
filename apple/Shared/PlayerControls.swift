import SwiftUI

// The player's controls (R18: speed, sleep, and skip live ON the player, not
// in Settings). Every control carries a VoiceOver label (R21).

struct TransportControls: View {
    @Environment(AudioPlayer.self) private var player
    var large = false

    var body: some View {
        HStack(spacing: large ? Spacing.s8 : Spacing.s6) {
            Button {
                player.skip(by: -AudioPlayer.Skip.back)
            } label: {
                Image(systemName: "gobackward.15")
            }
            .accessibilityLabel("Back 15 seconds")

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.largeTitle)
                    .imageScale(large ? .large : .medium)
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            Button {
                player.skip(by: AudioPlayer.Skip.forward)
            } label: {
                Image(systemName: "goforward.30")
            }
            .accessibilityLabel("Forward 30 seconds")
        }
        .font(.title)
        .disabled(player.item == nil)
    }
}

struct SpeedMenu: View {
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        @Bindable var player = player
        Menu {
            Picker("Speed", selection: $player.speed) {
                ForEach(AudioPlayer.speeds, id: \.self) { rate in
                    Text(Self.label(rate)).tag(rate)
                }
            }
        } label: {
            Label(Self.label(player.speed), systemImage: "gauge.with.dots.needle.33percent")
        }
        .accessibilityLabel("Playback speed")
        .accessibilityValue(Self.label(player.speed))
    }

    static func label(_ rate: Float) -> String {
        rate == rate.rounded() ? "\(Int(rate))×" : "\(rate.formatted(.number.precision(.fractionLength(1...2))))×"
    }
}

/// Opens the sleep timer's choices. They are a confirmation dialog rather than
/// a Menu so a test door can open them and so they read as one decision.
struct SleepButton: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Button {
            store.isSleepMenuPresented = true
        } label: {
            Label(player.sleep.label(now: player.clock) ?? "Sleep",
                  systemImage: player.sleep.isActive ? "moon.zzz.fill" : "moon.zzz")
        }
        .accessibilityLabel("Sleep timer")
        .accessibilityValue(player.sleep.label(now: player.clock) ?? "Off")
        .confirmationDialog("Sleep timer", isPresented: $store.isSleepMenuPresented, titleVisibility: .visible) {
            ForEach(SleepTimer.options) { option in
                Button(option.title) { player.setSleep(option) }
            }
            if player.sleep.isActive {
                Button("Turn Off Timer", role: .destructive) { player.cancelSleep() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// Elapsed and remaining time, tabular so the digits do not jitter.
struct TimeLabels: View {
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        HStack {
            Text(verbatim: EpisodeRow.clock(player.elapsed))
            Spacer()
            if let duration = player.duration {
                Text(verbatim: "-" + EpisodeRow.clock(max(0, duration - player.elapsed)))
            }
        }
        .font(TypeRamp.caption.monospacedDigit())
        .foregroundStyle(Color.brandTextMuted)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Elapsed \(EpisodeRow.clock(player.elapsed))")
    }
}

#if !os(tvOS)
/// The scrubber (tvOS has no Slider; it seeks by the skip buttons).
struct Scrubber: View {
    @Environment(AudioPlayer.self) private var player
    @State private var dragging: Double?

    var body: some View {
        let duration = max(player.duration ?? 1, 1)
        Slider(
            value: Binding(get: { dragging ?? min(player.elapsed, duration) }, set: { dragging = $0 }),
            in: 0...duration
        ) { editing in
            if !editing, let target = dragging {
                player.seek(to: target)
                dragging = nil
            }
        }
        .accessibilityLabel("Position")
        .accessibilityValue(EpisodeRow.clock(player.elapsed))
        .disabled(player.duration == nil)
    }
}
#endif
