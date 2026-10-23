#if os(macOS)
import SwiftUI

// The Mac is a pointer + keyboard + menu-bar app (macos-platform-patterns),
// not the iPhone app resized: a NavigationSplitView whose sidebar holds the
// top-level verbs, ONE NavigationPath per section feeding the detail column,
// every command in the menu bar, and the transport as a bar along the window's
// bottom edge. Audio has no picture, so the player never replaces the window
// root here (that rule is for video); the bar is the Music app's idiom.

struct ContentView_macOS: View {
    @Environment(AppStore.self) private var store
    @Environment(AudioPlayer.self) private var player

    private var section: Binding<AppTab?> {
        Binding(get: { store.selectedTab }, set: { if let tab = $0 { store.selectedTab = tab } })
    }

    var body: some View {
        NavigationSplitView {
            List(AppTab.allCases, selection: section) { tab in
                Label(tab.title, systemImage: tab.symbol).tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            NavigationStack(path: store.path(for: store.selectedTab)) {
                Group {
                    switch store.selectedTab {
                    case .listen: ListenScreen()
                    case .series: SeriesBrowseScreen()
                    case .search: SearchScreen_macOS()
                    case .library: LibraryScreen()
                    }
                }
                .routeDestinations()
            }
            .id(store.selectedTab)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if player.item != nil { TransportBar_macOS() }
        }
        .navigationTitle(player.item?.episode.displayTitle ?? "Ear Drama")
    }
}

private struct SearchScreen_macOS: View {
    @State private var query = ""

    var body: some View {
        SearchResultsList(query: query)
            .navigationTitle("Search")
            .searchable(text: $query, placement: .toolbar, prompt: "Titles, series, people")
    }
}

/// The transport along the bottom of the window: what is playing, the
/// scrubber, skip, speed, and sleep, all on the player (R18).
struct TransportBar_macOS: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(CatalogStore.self) private var catalog

    var body: some View {
        VStack(spacing: Spacing.s2) {
            Divider()
            HStack(spacing: Spacing.s6) {
                if let item = player.item {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.episode.displayTitle)
                            .font(TypeRamp.bodyStrong)
                            .lineLimit(1)
                        Text(verbatim: [item.episode.seriesName, AirDate.display(item.episode.airDate)]
                            .joined(separator: " · "))
                            .font(TypeRamp.caption)
                            .foregroundStyle(Color.brandTextMuted)
                            .lineLimit(1)
                    }
                    .frame(minWidth: 160, maxWidth: 280, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
                TransportControls()
                    .buttonStyle(.borderless)
                VStack(spacing: 0) {
                    Scrubber()
                    TimeLabels()
                }
                .frame(minWidth: 200)
                SpeedMenu().fixedSize()
                SleepButton().fixedSize()
            }
            if let message = player.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(TypeRamp.caption)
                    .foregroundStyle(Color.semanticError)
            } else if !catalog.isOnline {
                OfflineNotice()
            }
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.bottom, Spacing.s3)
        .background(.bar)
    }
}

/// The menu bar: every playback command, with its key equivalent, disabled
/// (never hidden) when nothing is loaded.
struct PlaybackCommands_macOS: Commands {
    let player: AudioPlayer
    let store: AppStore

    var body: some Commands {
        CommandMenu("Controls") {
            Button(player.isPlaying ? "Pause" : "Play") { player.togglePlayPause() }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(player.item == nil)
            Button("Back 15 Seconds") { player.skip(by: -AudioPlayer.Skip.back) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(player.item == nil)
            Button("Forward 30 Seconds") { player.skip(by: AudioPlayer.Skip.forward) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(player.item == nil)
            Divider()
            Menu("Speed") {
                ForEach(AudioPlayer.speeds, id: \.self) { rate in
                    Button(SpeedMenu.label(rate)) { player.speed = rate }
                }
            }
            .disabled(player.item == nil)
            Menu("Sleep Timer") {
                ForEach(SleepTimer.options) { option in
                    Button(option.title) { player.setSleep(option) }
                }
                Divider()
                Button("Turn Off Timer") { player.cancelSleep() }
                    .disabled(!player.sleep.isActive)
            }
            .disabled(player.item == nil)
        }
        CommandGroup(after: .sidebar) {
            ForEach(Array(AppTab.allCases.enumerated()), id: \.element) { index, tab in
                Button(tab.title) { store.selectedTab = tab }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
        }
    }
}
#endif
