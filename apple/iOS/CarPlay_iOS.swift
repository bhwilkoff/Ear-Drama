#if os(iOS) && canImport(CarPlay)
import CarPlay
import ImageIO
import UIKit

/// The stores the phone app already owns, handed to the car screen. The car
/// never makes its own: one player, one history, one catalog, one live radio
/// (Decision 056, "a stub grows from the core's shared code").
enum CarPlayServices {
    static var catalog: CatalogStore?
    static var player: AudioPlayer?
    static var history: ListeningHistory?
    static var store: AppStore?
    static var downloads: DownloadStore?
    static var live: LiveRadio?
    static var follows: FollowedSeries?
}

/// Routes a CarPlay scene to `CarPlaySceneDelegate` and leaves every other
/// scene exactly as the system configured it. Without the
/// `com.apple.developer.carplay-audio` entitlement iOS never connects a car
/// scene, so this is dormant until Apple grants it (apple/README.md).
final class AppDelegate_iOS: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        guard connectingSceneSession.role == .carTemplateApplication else {
            // A fresh configuration, never `connectingSceneSession.configuration`: that one already
            // names SwiftUI's AppSceneDelegate, and handing it back makes SwiftUI wrap its own
            // delegate, recursing in responds(to:) until the stack overflows at launch (seen on an
            // iPhone 12, TestFlight 1.0.59).
            return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        }
        let config = UISceneConfiguration(name: "CarPlay", sessionRole: connectingSceneSession.role)
        config.delegateClass = CarPlaySceneDelegate.self
        return config
    }
}

/// The car's four tabs (R17): Continue, Stations, Browse, Downloads. The tree, its limits and its
/// words are `CarLibrary`'s (Core, tested); this only draws them as list templates, loads pictures
/// without blocking a row, and plays through the one `AudioPlayer` and `LiveRadio`. Every push stays
/// within the audio depth of five; Now Playing pops to the root first when the stack is that deep.
/// No transcripts here: CarPlay forbids lyrics, and a transcript is one. CPSearchTemplate is not
/// listed for audio apps, so the car has no search screen (docs/iOS-DESIGN.md §9.1).
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPTabBarTemplateDelegate {
    private static let maxDepth = 5

    private var interfaceController: CPInterfaceController?
    private var library: CarLibrary?
    private var carStations: CarStations?
    private var artTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var tabs: [(id: String, template: CPListTemplate)] = []
    private lazy var artStore = CarArtStore(dir: URL.cachesDirectory.appending(path: "carart"))

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        let symbols = [CarLibrary.continueTab: "play.circle", CarLibrary.stationsTab: "radio",
                       CarLibrary.browseTab: "square.grid.2x2", CarLibrary.downloadsTab: "arrow.down.circle"]
        tabs = CarLibrary.tabs.map { node in
            let list = CPListTemplate(title: node.title, sections: [])
            list.tabImage = UIImage(systemName: symbols[node.id] ?? "circle") ?? UIImage()
            if #available(iOS 18.4, *) { list.showsSpinnerWhileEmpty = true }
            return (node.id, list)
        }
        buildLibrary()
        let tabBar = CPTabBarTemplate(templates: tabs.map(\.template))
        tabBar.delegate = self
        interfaceController.setRootTemplate(tabBar, animated: false, completion: nil)
        // The car can launch the app with no phone window, so the catalog
        // may not have been opened yet. `start()` runs once.
        Task { [weak self] in
            await CarPlayServices.catalog?.start()
            self?.reloadAll()
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        artTasks.values.forEach { $0.cancel() }
        artTasks = [:]
        tabs = []
        library = nil
        carStations = nil
        self.interfaceController = nil
    }

    func tabBarTemplate(_ tabBarTemplate: CPTabBarTemplate, didSelect selectedTemplate: CPTemplate) {
        guard let tab = tabs.first(where: { $0.template === selectedTemplate }) else { return }
        reload(tab.id, into: tab.template)
    }

    // MARK: - The tree

    private func buildLibrary() {
        guard let catalog = CarPlayServices.catalog, let history = CarPlayServices.history,
              let player = CarPlayServices.player, let live = CarPlayServices.live else { return }
        let store = CarPlayServices.store
        let stations = CarStations(catalog: catalog) { tune in
            player.isMuted = store?.isMuted ?? false
            switch tune {
            case let .evening(day, details): live.tuneIn(day, details: details)
            case let .station(station, slots, details): live.tuneIn(station: station, slots: slots, details: details)
            }
        }
        carStations = stations
        let downloads = CarPlayServices.downloads
        let follows = CarPlayServices.follows
        library = CarLibrary(
            catalog: catalog,
            inProgressIDs: { history.inProgressIDs },
            progress: { history.progress(for: $0) },
            downloadedIDs: { downloads?.sortedRecords.filter { $0.state == .downloaded }.map(\.episodeID) ?? [] },
            followed: { follows?.followedKeys ?? [] },
            stations: { try await stations.list() }
        )
    }

    private func reloadAll() {
        for tab in tabs { reload(tab.id, into: tab.template) }
    }

    private func reload(_ id: String, into template: CPListTemplate) {
        guard let library else { return }
        Task { [weak self] in
            let nodes = await library.children(of: id) ?? []
            self?.fill(template, with: nodes)
        }
    }

    private func fill(_ template: CPListTemplate, with nodes: [CarNode]) {
        let pairs = nodes.prefix(CPListTemplate.maximumItemCount).map { (item(for: $0), $0.art) }
        template.updateSections([CPListSection(items: pairs.map(\.0))])
        loadArt(pairs.compactMap { pair in pair.1.map { (pair.0, $0) } }, for: template)
    }

    private func item(for node: CarNode) -> CPListItem {
        let item = CPListItem(text: node.title, detailText: node.subtitle)
        if let progress = node.progress { item.playbackProgress = CGFloat(progress) }
        switch node.kind {
        case .message:
            item.isEnabled = false
        case .folder:
            item.accessoryType = .disclosureIndicator
            item.handler = { [weak self] _, completion in
                Task {
                    await self?.open(node)
                    completion()
                }
            }
        case .episode:
            item.handler = { [weak self] _, completion in
                self?.play(node.id)
                completion()
            }
        case .station:
            item.handler = { [weak self] _, completion in
                Task {
                    await self?.tune(node.id)
                    completion()
                }
            }
        }
        return item
    }

    private func open(_ folder: CarNode) async {
        guard let library, let controller = interfaceController, controller.templates.count < Self.maxDepth else { return }
        let nodes = await library.children(of: folder.id) ?? []
        let list = CPListTemplate(title: folder.title, sections: [])
        list.emptyViewTitleVariants = ["Nothing here yet"]
        fill(list, with: nodes)
        controller.pushTemplate(list, animated: true, completion: nil)
    }

    // MARK: - Playing

    private func play(_ id: String) {
        guard let catalog = CarPlayServices.catalog, let player = CarPlayServices.player else { return }
        Task { [weak self] in
            await catalog.whenReady()
            guard let detail = await catalog.episodeDetail(id) else { return }
            player.isMuted = CarPlayServices.store?.isMuted ?? false
            player.play(detail)
            self?.showNowPlaying()
        }
    }

    private func tune(_ id: String) async {
        guard let stations = carStations else { return }
        if await stations.tune(id) != nil {
            showNowPlaying()
        } else {
            reloadAll()
        }
    }

    /// AudioPlayer already publishes Now Playing and the remote commands; the shared template reads
    /// them. Audio apps may stack five templates, so a deep stack pops to its root first.
    private func showNowPlaying() {
        guard let controller = interfaceController, !(controller.topTemplate is CPNowPlayingTemplate) else { return }
        if controller.templates.count >= Self.maxDepth {
            controller.popToRootTemplate(animated: false) { _, _ in
                controller.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
            }
        } else {
            controller.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
        }
    }

    // MARK: - Pictures

    /// Rows show at once; each picture follows when it is ready, in order, so a slow one never holds a
    /// row. A newer fill of the same template cancels the older.
    private func loadArt(_ rows: [(CPListItem, CarArt)], for template: CPListTemplate) {
        let key = ObjectIdentifier(template)
        artTasks[key]?.cancel()
        guard !rows.isEmpty, let catalog = CarPlayServices.catalog else { return }
        let scale = interfaceController?.carTraitCollection.displayScale ?? 2
        let side = CPListItem.maximumImageSize
        let pixels = CGSize(width: side.width * scale, height: side.height * scale)
        artTasks[key] = Task { [weak self] in
            for (item, art) in rows {
                guard !Task.isCancelled, let self else { return }
                if let image = await self.picture(art, catalog: catalog, pixels: pixels) {
                    item.setImage(image)
                }
            }
        }
    }

    private func picture(_ art: CarArt, catalog: CatalogStore, pixels: CGSize) async -> UIImage? {
        guard let source = await catalog.carArt(art) else { return nil }
        let data = await artStore.data(key: source.key, served: source.served?.url(pixels: 330)) {
            let item: LabelItem
            switch source.subject {
            case let .episode(row, series): item = row.labelItem(series: series)
            case let .series(row): item = row.labelItem
            }
            return LabelView.image(item, px: 256).flatMap { UIImage(cgImage: $0).pngData() }
        }
        guard let data, let origin = CGImageSourceCreateWithData(data as CFData, nil),
              var image = CGImageSourceCreateImageAtIndex(origin, 0, nil) else { return nil }
        // The row is square: the one centered on the published face, as Now Playing cuts it (R11a).
        if image.width != image.height, let cut = source.served?.squareCrop(width: image.width, height: image.height) {
            image = image.cropping(to: CGRect(x: cut.x, y: cut.y, width: cut.side, height: cut.side)) ?? image
        }
        let whole = UIImage(cgImage: image)
        return whole.preparingThumbnail(of: pixels) ?? whole
    }
}
#endif
