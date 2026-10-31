#if os(macOS)
import AVKit
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
                    case .home: ListenScreen()
                    case .browse: SeriesBrowseScreen()
                    case .stations: RadioScreen()
                    case .surprise: SurpriseScreen()
                    case .search: SearchScreen_macOS()
                    case .library: LibraryScreen()
                    }
                }
                .routeDestinations()
            }
            .id(store.selectedTab)
        }
        // The offline line sits above the transport (macOS-DESIGN §7.2).
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                OfflineLine().background(.bar)
                if player.item != nil { TransportBar_macOS() }
            }
        }
        .navigationTitle(player.item?.episode.displayTitle ?? "Ear Drama")
        // Space plays and pauses here, never as a menu key (macOS-DESIGN §5.3):
        // a focused text field takes the key first, so typing never pauses.
        .onKeyPress(.space) {
            guard player.item != nil else { return .ignored }
            player.togglePlayPause()
            return .handled
        }
    }
}

private struct SearchScreen_macOS: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        SearchResultsList(query: query)
            .navigationTitle("Search")
            .searchable(text: $query, placement: .toolbar, prompt: "Titles, people, spoken words")
            .searchFocused($fieldFocused)
            .onChange(of: store.wantsSearchFocus, initial: true) { _, wants in
                guard wants else { return }
                fieldFocused = true
                store.wantsSearchFocus = false
            }
            .onChange(of: store.pendingSearch, initial: true) { _, q in
                guard let q else { return }
                query = q
                store.pendingSearch = nil
            }
    }
}

/// The transport along the bottom of the window: what is playing, the
/// scrubber, skip, speed, and sleep, all on the player (R18).
struct TransportBar_macOS: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(CatalogStore.self) private var catalog
    @Environment(\.openWindow) private var openWindow
    @Environment(AppStore.self) private var store
    @State private var peopleOpen = false

    var body: some View {
        VStack(spacing: Spacing.s2) {
            Divider()
            HStack(spacing: Spacing.s6) {
                if let item = player.item {
                    // The picture the system's Now Playing shows (Decision 069, D3-4): the grammar's window.
                    PictureWindow(art: NowPlayingArt.art(item.episode, item.face), name: item.episode.seriesName,
                                  genre: item.episode.seriesGenre, side: 40)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.episode.displayTitle)
                            .font(TypeRamp.bodyStrong)
                            .lineLimit(1)
                        EventLine(facts: [item.episode.seriesName, AirDate.display(item.episode.airDate)])
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
                LevelToggle()
                    .labelStyle(.iconOnly)
                    .fixedSize()
                ListenTogetherButton()
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .fixedSize()
                RoutePicker_macOS(player: player.routedPlayer)
                    .frame(width: 24, height: 24)
                    .help("AirPlay")
                NextStoryButton()
                    .fixedSize()
                if let item = player.item {
                    PlayerQueueButton(episodeID: item.episode.id)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .fixedSize()
                    PlayerShareLink(episode: item.episode)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .fixedSize()
                    Button {
                        peopleOpen.toggle()
                    } label: {
                        Image(systemName: "person.2.wave.2")
                    }
                    .buttonStyle(.borderless)
                    .help("On the air, and that night on the radio")
                    .accessibilityLabel("On the air")
                    .popover(isPresented: $peopleOpen, arrowEdge: .top) {
                        ScrollView {
                            NowPlayingPeople(episode: item.episode) { route in
                                peopleOpen = false
                                store.push(route)
                            }
                            .padding(Spacing.s4)
                        }
                        .frame(width: 420, height: 480)
                    }
                }
                if let item = player.item, let url = item.episode.transcriptURL {
                    Button {
                        openWindow(id: TranscriptRef.windowID,
                                   value: TranscriptRef(title: item.episode.displayTitle, url: url))
                    } label: {
                        Image(systemName: "text.quote")
                    }
                    .buttonStyle(.borderless)
                    .help(Transcript.label)
                    .accessibilityLabel(Transcript.label)
                }
            }
            FollowingHostNotice()
            if let message = player.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(TypeRamp.caption)
                    .foregroundStyle(Color.semanticError)
            } else if !catalog.isOnline && !player.isLocal {
                OfflineNotice()
            }
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.bottom, Spacing.s3)
        .background(.bar)
    }
}

/// The Go menu (macOS-DESIGN §5.5): the sidebar sections, Search, and Back.
struct GoCommands_macOS: Commands {
    let store: AppStore

    var body: some Commands {
        CommandMenu("Go") {
            ForEach(Array(AppTab.allCases.enumerated()), id: \.element) { index, tab in
                Button(tab.title) { store.selectedTab = tab }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
            Divider()
            Button("Search") { store.openSearch() }
                .keyboardShortcut("f", modifiers: .command)
            Button("Back") { store.goBack() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!store.canGoBack)
        }
    }
}

/// The Help menu (macOS-DESIGN §5.6): the website's own pages.
struct HelpCommands_macOS: Commands {
    @Environment(\.openURL) private var openURL

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Ear Drama Website") { openURL(SiteLinks.root) }
            Divider()
            Button("Credits") { openURL(SiteLinks.credits) }
            Button("Privacy") { openURL(SiteLinks.privacy) }
            Button("Take-Down Requests") { openURL(SiteLinks.takedown) }
        }
    }
}

/// The menu bar: every playback command, disabled (never hidden) when nothing
/// is loaded. No item takes a bare key (§5.3); Space is the main window's.
struct PlaybackCommands_macOS: Commands {
    let player: AudioPlayer
    let store: AppStore
    let downloads: DownloadStore
    let room: SharePlayRoom
    let queue: ListeningQueue
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.recordingControls) private var recording

    var body: some Commands {
        CommandMenu("Controls") {
            // Disabled while a part records, so the microphone never hears the episode.
            Button(player.isPlaying ? "Pause" : "Play") { player.togglePlayPause() }
                .disabled(player.item == nil || recording != nil)
            Button("Back 15 Seconds") { player.skip(by: -AudioPlayer.Skip.back) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(player.item == nil || player.isFollowing)
            Button("Forward 30 Seconds") { player.skip(by: AudioPlayer.Skip.forward) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(player.item == nil || player.isFollowing)
            Divider()
            Menu("Speed") {
                ForEach(AudioPlayer.speeds, id: \.self) { rate in
                    Button(SpeedMenu.label(rate)) { player.speed = rate }
                }
            }
            .disabled(player.item == nil || player.isFollowing)
            Menu("Sleep Timer") {
                ForEach(SleepTimer.options) { option in
                    Button(option.title) { player.setSleep(option) }
                }
                Divider()
                Button("Turn Off Timer") { player.cancelSleep() }
                    .disabled(!player.sleep.isActive)
            }
            .disabled(player.item == nil)
            if room.isActive {
                Button("Leave SharePlay") { room.leave() }
            } else {
                Button("SharePlay") { Task { await ListenTogetherStarter.start(room) } }
                    .disabled(player.item == nil)
            }
            Divider()
            // Acts on the episode now playing, as the other commands do.
            if let item = player.item, downloads.records[item.episode.id] != nil {
                Button("Remove Download") { downloads.remove(item.episode.id) }
            } else {
                Button("Download Episode") {
                    guard let item = player.item else { return }
                    downloads.download(episodeID: item.episode.id, title: item.episode.displayTitle,
                                       seriesName: item.episode.seriesName,
                                       seriesKey: item.episode.seriesKey, url: item.recording.url)
                }
                .disabled(player.item == nil)
            }
            Divider()
            // Acts on the episode now playing, as the other commands do.
            if let item = player.item, queue.contains(item.episode.id) {
                Button("Remove from Queue") { queue.remove(item.episode.id) }
            } else {
                Button("Add to Queue") {
                    guard let item = player.item else { return }
                    queue.add(item.episode.id)
                }
                .disabled(player.item == nil)
            }
            if let item = player.item {
                ShareLink(item: SiteLinks.episode(item.episode.id), subject: Text(item.episode.displayTitle)) {
                    Text("Share Episode")
                }
            } else {
                Button("Share Episode") {}.disabled(true)
            }
            Divider()
            Button(Transcript.label) {
                guard let item = player.item, let url = item.episode.transcriptURL else { return }
                openWindow(id: TranscriptRef.windowID, value: TranscriptRef(title: item.episode.displayTitle, url: url))
            }
            .keyboardShortcut("t", modifiers: [.command, .option])
            .disabled(player.item?.episode.transcriptURL == nil)
        }
    }
}

/// A production is a window (PLAYS-DESIGN §2.2): the cast sheet in the sidebar,
/// the part being recorded in the detail, the keyboard driving it through the
/// Recording menu.
struct ProductionWindow_macOS: View {
    static let id = "production"
    let productionID: String
    @Environment(PlaysLibrary.self) private var plays
    @State private var selected: PartID?
    @State private var replacing: String?

    var body: some View {
        if let production = plays.store.production(productionID), let script = plays.castScript(for: production) {
            NavigationSplitView {
                CastSheet(production: production, script: script, open: { selected = $0; replacing = nil },
                          replace: { selected = $0; replacing = $1 })
                    .navigationSplitViewColumnWidth(min: 280, ideal: 320)
            } detail: {
                PartDetail(production: production, script: script, part: selected ?? Relay.current(production, script),
                           replacing: replacing)
            }
            .navigationTitle(production.title)
        } else {
            EmptyState("Production not found", systemImage: "questionmark.square.dashed")
        }
    }
}

/// The recording commands, for the focused production window; disabled, never
/// hidden, when no part is being recorded.
struct RecordingCommands_macOS: Commands {
    @FocusedValue(\.recordingControls) private var recording

    var body: some Commands {
        CommandMenu("Recording") {
            Button(recording?.isListening == true ? "Stop" : recording?.session.run != nil ? "Pause" : "Record") {
                recording?.recordOrStop()
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(recording?.canPress != true)
            Button("Keep") { recording?.keep() }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(recording == nil || (recording!.session.isBusy && recording!.session.run == nil))
            Button("Again") { recording?.again() }
                .keyboardShortcut("r", modifiers: [])
                .disabled(recording == nil || recording!.session.isBusy)
            Divider()
            Button("Previous Line") { recording?.move(-1) }
                .keyboardShortcut(.upArrow, modifiers: [])
                .disabled(recording == nil || recording!.session.isBusy)
            Button("Next Line") { recording?.move(1) }
                .keyboardShortcut(.downArrow, modifiers: [])
                .disabled(recording == nil || recording!.session.isBusy)
            Divider()
            Button("Run-Up") {
                if let recording, let line = recording.line { Task { await recording.session.record(line.id, runUp: true) } }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(recording == nil || recording!.session.isBusy || recording!.session.run != nil)
        }
    }
}

/// AirPlay's own picker (AVKit), never a custom device list. The Mac routes
/// the player it is given, since it has no audio session (macOS-DESIGN §5.2).
struct RoutePicker_macOS: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.isRoutePickerButtonBordered = false
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {
        if nsView.player !== player { nsView.player = player }
    }
}
#endif
