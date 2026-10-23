import SwiftUI

@main
struct EarDramaApp: App {
    // Owned here (not created inline in `body`) so a re-evaluated Scene body
    // never swaps in fresh stores and drops navigation or playback state.
    @State private var store: AppStore
    @State private var catalog: CatalogStore
    @State private var history: ListeningHistory
    @State private var player: AudioPlayer
    #if os(iOS) || os(macOS)
    @State private var downloads: DownloadStore
    @State private var plays = PlaysLibrary()
    #endif
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate_iOS.self) private var appDelegate
    #endif

    init() {
        URLCache.shared = URLCache(memoryCapacity: 20_000_000, diskCapacity: 100_000_000)
        let store = AppStore()
        let catalog = CatalogStore()
        let history = ListeningHistory()
        let player = AudioPlayer(history: history)
        player.resolveDetail = { [weak catalog] id in await catalog?.episodeDetail(id) }
        player.resolveSeriesPage = { [weak catalog] key in await catalog?.seriesPage(key) }
        #if os(iOS) || os(macOS)
        let downloads = DownloadStore.live()
        player.localFile = { [weak downloads] id, recording in
            downloads?.localFile(for: id, recording: recording.url)
        }
        _downloads = State(initialValue: downloads)
        #endif
        #if os(iOS)
        CarPlayServices.catalog = catalog
        CarPlayServices.player = player
        CarPlayServices.history = history
        CarPlayServices.store = store
        #endif
        _store = State(initialValue: store)
        _catalog = State(initialValue: catalog)
        _history = State(initialValue: history)
        _player = State(initialValue: player)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(catalog)
                .environment(history)
                .environment(player)
                #if os(iOS) || os(macOS)
                .environment(downloads)
                .environment(plays)
                .task { await downloads.reconnect() }
                #endif
                // .onOpenURL fires for Universal Links AND custom schemes. It
                // never routes directly: the request lands in the inbox.
                .onOpenURL { url in
                    let id = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
                    if !id.isEmpty { store.post(.item(id)) }
                }
        }
        #if os(macOS)
        .commands {
            GoCommands_macOS(store: store)
            PlaybackCommands_macOS(player: player, store: store, downloads: downloads)
            RecordingCommands_macOS()
            HelpCommands_macOS()
        }
        #endif
        #if os(iOS)
        // The system relaunches the app in the background when a download
        // finishes; recreating the session here replays the delegate
        // callbacks, so the file is in place before the listener returns.
        .backgroundTask(.urlSession(DownloadStore.sessionIdentifier)) { [downloads] in
            await downloads.handleBackgroundEvents()
        }
        #endif
        #if os(macOS)
        WindowGroup(Transcript.label, id: TranscriptRef.windowID, for: TranscriptRef.self) { $ref in
            if let ref {
                TranscriptWindow_macOS(ref: ref)
                    .environment(catalog)
                    .tint(Color.brandPrimary)
            }
        }
        .defaultSize(width: 560, height: 680)
        WindowGroup("Production", id: ProductionWindow_macOS.id, for: String.self) { $id in
            if let id {
                ProductionWindow_macOS(productionID: id)
                    .environment(plays)
                    .environment(player)
                    .environment(store)
                    .tint(Color.brandPrimary)
            }
        }
        .defaultSize(width: 960, height: 720)
        #endif
    }
}

/// One entry point, three native view trees (iOS/iPadOS, tvOS, macOS). Each
/// platform branch is EXPLICIT; a bare #else silently gives a new platform the
/// iOS view.
struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(CatalogStore.self) private var catalog
    @Environment(AudioPlayer.self) private var player
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        platformRoot
            .tint(Color.brandPrimary)
            .task { await catalog.start() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await catalog.refresh() } }
            }
            // The ONE place the inbox is consumed: deep links and test doors.
            .onChange(of: store.inbox, initial: true) { _, pending in
                guard !pending.isEmpty else { return }
                let play = PlayEpisodeAction(catalog: catalog, player: player, store: store)
                for id in store.drainInbox() { play(id) }
            }
            .onChange(of: store.isMuted, initial: true) { _, muted in player.isMuted = muted }
            // Test doors (DEBUG builds only; LaunchDoors.current is empty in
            // Release). APP_DOOR_SECONDS bounds the door's activity.
            .task {
                let doors = LaunchDoors.current
                guard !doors.isEmpty, store.openDoorsOnce(doors) else { return }
                if let seconds = doors.doorSeconds {
                    guard (try? await Task.sleep(for: .seconds(seconds))) != nil else { return }
                    player.stop()
                    store.endDoor()
                }
            }
    }

    @ViewBuilder private var platformRoot: some View {
        #if os(tvOS)
        ContentView_tvOS()
        #elseif os(macOS)
        ContentView_macOS()
        #elseif os(iOS)
        ContentView_iOS()
        #endif
    }
}
