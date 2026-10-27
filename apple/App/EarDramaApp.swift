import SwiftUI

@main
struct EarDramaApp: App {
    // Owned here (not created inline in `body`) so a re-evaluated Scene body
    // never swaps in fresh stores and drops navigation or playback state.
    @State private var store: AppStore
    @State private var catalog: CatalogStore
    @State private var history: ListeningHistory
    @State private var queue: ListeningQueue
    @State private var player: AudioPlayer
    @State private var live: LiveRadio
    @State private var account: AccountStore
    @State private var room: SharePlayRoom
    #if os(iOS) || os(macOS)
    @State private var downloads: DownloadStore
    @State private var plays = PlaysLibrary()
    @State private var shared = SharedPlays()
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
        player.resolveArc = { [weak catalog] id in await catalog?.arc(id) }
        player.cardImage = { episode in
            let renderer = ImageRenderer(content: TypeCard(name: episode.seriesName, line: episode.network,
                                                           genre: episode.seriesGenre).frame(width: 256, height: 256))
            renderer.scale = 2
            return renderer.cgImage
        }
        let queue = ListeningQueue()
        player.queuedIDs = { [weak queue] in queue?.items ?? [] }
        player.dequeue = { [weak queue] id in queue?.remove(id) }
        queue.onChange = { [weak player] in player?.refreshUpNext() }
        let live = LiveRadio(player: player)
        let account = AccountStore(history: history, follows: FollowedSeries(), queue: queue)
        player.onTransport = { [weak live] event in live?.handle(event) }
        let room = SharePlayRoom(player: player) { [weak catalog] id in
            await catalog?.whenReady()
            return await catalog?.episodeDetail(id)
        }
        // From launch, not from data-ready: a SharePlay hand-over cold-launches the app.
        room.start()
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
        CarPlayServices.downloads = downloads
        #endif
        _store = State(initialValue: store)
        _catalog = State(initialValue: catalog)
        _history = State(initialValue: history)
        _queue = State(initialValue: queue)
        _player = State(initialValue: player)
        _live = State(initialValue: live)
        _account = State(initialValue: account)
        _room = State(initialValue: room)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(catalog)
                .environment(history)
                .environment(queue)
                .environment(player)
                .environment(live)
                .environment(account)
                .environment(room)
                #if os(iOS) || os(macOS)
                .environment(downloads)
                .environment(plays)
                .environment(shared)
                .task { await downloads.reconnect() }
                #endif
                // Custom-scheme links and Universal Links (applinks:eardrama.org)
                // never route directly: the request lands in the inbox.
                .onOpenURL { url in open(url) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { open(url) }
                }
        }
        #if os(macOS)
        .commands {
            GoCommands_macOS(store: store)
            PlaybackCommands_macOS(player: player, store: store, downloads: downloads, room: room, queue: queue)
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
                    .tint(Color.brandSecondary)
            }
        }
        .defaultSize(width: 560, height: 680)
        WindowGroup("Production", id: ProductionWindow_macOS.id, for: String.self) { $id in
            if let id {
                ProductionWindow_macOS(productionID: id)
                    .environment(plays)
                    .environment(shared)
                    .environment(player)
                    .environment(account)
                    .environment(store)
                    .tint(Color.brandSecondary)
            }
        }
        .defaultSize(width: 960, height: 720)
        #endif
    }

    private func open(_ url: URL) {
        switch DeepLink.parse(url) {
        #if os(tvOS)
        // The TV plays back only; an invite opens nothing there.
        case .invite: break
        #endif
        case let request?: store.post(request)
        case nil: break
        }
    }
}

/// One entry point, three native view trees (iOS/iPadOS, tvOS, macOS). Each
/// platform branch is EXPLICIT; a bare #else silently gives a new platform the
/// iOS view.
struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(CatalogStore.self) private var catalog
    @Environment(AudioPlayer.self) private var player
    @Environment(AccountStore.self) private var account
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        platformRoot
            .tint(Color.brandSecondary)
            .task { await catalog.start() }
            .task { await account.start() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await catalog.refresh() } }
                // Signed in, the app syncs when it comes to the front and when
                // it leaves (iOS-DESIGN §4.10); signed out, this does nothing.
                if phase != .inactive { Task { await account.sync() } }
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
