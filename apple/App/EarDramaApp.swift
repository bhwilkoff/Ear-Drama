import SwiftUI

@main
struct EarDramaApp: App {
    // Owned here (not created inline in `body`) so a re-evaluated Scene body
    // never swaps in fresh stores and drops navigation or playback state.
    @State private var store: AppStore
    @State private var catalog: CatalogStore
    @State private var history: ListeningHistory
    @State private var queue: ListeningQueue
    @State private var follows: FollowedSeries
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
        LaunchDoors.resetUserStateIfAsked()
        LaunchDoors.restoreUserStateIfSetAside()
        #if os(iOS) || os(macOS)
        LaunchDoors.resetProductionsIfAsked()
        #endif
        URLCache.shared = URLCache(memoryCapacity: 20_000_000, diskCapacity: 100_000_000)
        let store = AppStore()
        let catalog = CatalogStore()
        let history = ListeningHistory()
        let player = AudioPlayer(history: history)
        player.resolveDetail = { [weak catalog] id in await catalog?.episodeDetail(id) }
        player.resolveArc = { [weak catalog] id in await catalog?.arc(id) }
        player.cardImage = { [weak catalog] episode in
            let series = await catalog?.series([episode.seriesKey]).first
            return LabelView.image(episode.labelItem(series: series))
        }
        let queue = ListeningQueue()
        player.queuedIDs = { [weak queue] in queue?.items ?? [] }
        player.dequeue = { [weak queue] id in queue?.remove(id) }
        queue.onChange = { [weak player] in player?.refreshUpNext() }
        let live = LiveRadio(player: player)
        let follows = FollowedSeries()
        let account = AccountStore(history: history, follows: follows, queue: queue)
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
        // Contract §3.5: every store that keeps episode ids or series keys rewrites
        // the ones the catalog moved, on each catalog open and after each sync.
        catalog.onForwarding = { [weak history, weak queue, weak follows] forwarding in
            history?.forward(forwarding)
            queue?.forward(forwarding)
            follows?.forward(forwarding)
            #if os(iOS) || os(macOS)
            downloads.forward(forwarding)
            #endif
        }
        account.forwarding = { [weak catalog] in catalog?.forwarding ?? IDForwarding() }
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
        _follows = State(initialValue: follows)
        _player = State(initialValue: player)
        _live = State(initialValue: live)
        _account = State(initialValue: account)
        _room = State(initialValue: room)
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(store)
                .environment(catalog)
                .environment(history)
                .environment(queue)
                .environment(follows)
                .environment(player)
                .environment(live)
                .environment(account)
                .environment(room)
                #if os(iOS) || os(macOS)
                .environment(downloads)
                .environment(plays)
                .environment(shared)
                .task { await downloads.reconnect() }
                #if DEBUG
                .task { await KokoroBench.runIfAsked() }
                #endif
                #endif
                // Custom-scheme links and Universal Links (applinks:eardrama.org)
                // never route directly: the request lands in the inbox.
                .onOpenURL { url in open(url) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { open(url) }
                }
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 780)
        .commands {
            GoCommands_macOS(store: store)
            PlaybackCommands_macOS(player: player, store: store, downloads: downloads, room: room, queue: queue)
            RecordingCommands_macOS()
            CastingCommands_macOS()
            ScriptCommands_macOS(store: store)
            ReaderCommands_macOS()
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
        WindowGroup("Shared Screen", id: ReadScreenWindow_macOS.id, for: String.self) { $code in
            if let code {
                ReadScreenWindow_macOS(code: code)
                    .tint(Color.brandSecondary)
            }
        }
        .defaultSize(width: 1024, height: 640)
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
        WindowGroup("Script", id: ReaderWindow_macOS.id, for: String.self) { $id in
            if let id {
                ReaderWindow_macOS(scriptID: id)
                    .environment(plays)
                    .environment(store)
                    .environment(account)
                    .environment(player)
                    .environment(catalog)
                    .tint(Color.brandSecondary)
            }
        }
        .defaultSize(width: 1280, height: 800)
        WindowGroup("Studio", id: StudioWindow_macOS.id, for: StudioWindowValue.self) { $value in
            if let value {
                StudioWindow_macOS(value: value)
                    .environment(plays)
                    .environment(store)
                    .environment(account)
                    .environment(player)
                    .environment(catalog)
                    .tint(Color.brandSecondary)
            }
        }
        .defaultSize(width: 1280, height: 820)
        #endif
    }

    private func open(_ url: URL) {
        // A text file from Files, the share sheet or the Finder: Add a Script opens with it.
        if url.isFileURL {
            store.post(.script(url))
            return
        }
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
    #if os(iOS) || os(macOS)
    @Environment(PlaysLibrary.self) private var plays
    #endif

    var body: some View {
        platformRoot
            .tint(Color.brandSecondary)
            .task { await catalog.start() }
            .task { await account.start() }
            #if os(iOS) || os(macOS)
            .task { await plays.relay.kick() }
            #endif
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await catalog.refresh() } }
                #if os(iOS) || os(macOS)
                // Relay across time: takes waiting for a receiver are tried again when the app comes forward; a backgrounded app asks nothing.
                plays.relay.setActive(phase == .active)
                if phase == .active { Task { await plays.relay.kick() } }
                #endif
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
