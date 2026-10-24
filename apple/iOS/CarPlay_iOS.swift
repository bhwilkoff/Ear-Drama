#if os(iOS) && canImport(CarPlay)
import CarPlay
import UIKit

/// The stores the phone app already owns, handed to the car screen. The car
/// never makes its own: one player, one history, one catalog (Decision 056,
/// "a stub grows from the core's shared code").
enum CarPlayServices {
    static var catalog: CatalogStore?
    static var player: AudioPlayer?
    static var history: ListeningHistory?
    static var store: AppStore?
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
            return connectingSceneSession.configuration
        }
        let config = UISceneConfiguration(name: "CarPlay", sessionRole: connectingSceneSession.role)
        config.delegateClass = CarPlaySceneDelegate.self
        return config
    }
}

/// The car decides the top level (R17): Continue, Radio, Series, Downloads.
/// Four tabs is CarPlay's audio maximum; every push stays within its depth of
/// five. No transcripts here: CarPlay forbids lyrics, and a transcript is one.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPTabBarTemplateDelegate {
    private var interfaceController: CPInterfaceController?
    private let continueTab = CPListTemplate(title: "Continue", sections: [])

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        continueTab.tabImage = UIImage(systemName: "play.circle")
        continueTab.emptyViewTitleVariants = ["Nothing in progress"]
        let tabs = [
            continueTab,
            Self.placeholder("Stations", symbol: "radio"),
            Self.placeholder("Browse", symbol: "square.grid.2x2"),
            Self.placeholder("Downloads", symbol: "arrow.down.circle"),
        ]
        let tabBar = CPTabBarTemplate(templates: tabs)
        tabBar.delegate = self
        interfaceController.setRootTemplate(tabBar, animated: false, completion: nil)
        // The car can launch the app with no phone window, so the catalog
        // may not have been opened yet. `start()` runs once.
        Task {
            await CarPlayServices.catalog?.start()
            await reloadContinue()
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
    }

    func tabBarTemplate(_ tabBarTemplate: CPTabBarTemplate, didSelect selectedTemplate: CPTemplate) {
        if selectedTemplate === continueTab { Task { await reloadContinue() } }
    }

    private static func placeholder(_ title: String, symbol: String) -> CPListTemplate {
        let list = CPListTemplate(title: title, sections: [])
        list.tabImage = UIImage(systemName: symbol)
        list.emptyViewTitleVariants = ["Not in the car yet"]
        return list
    }

    /// Some cars show only 12 rows, so the first 12 are the most recent.
    private func reloadContinue() async {
        guard let catalog = CarPlayServices.catalog, let history = CarPlayServices.history else { return }
        await catalog.whenReady()
        let limit = min(CPListTemplate.maximumItemCount, 12)
        let rows = await catalog.episodes(Array(history.inProgressIDs.prefix(limit)))
        let items = rows.map { row -> CPListItem in
            let item = CPListItem(text: row.displayTitle, detailText: row.seriesName)
            item.playbackProgress = CGFloat(history.progress(for: row.id) ?? 0)
            item.handler = { [weak self] _, completion in
                self?.play(row.id)
                completion()
            }
            return item
        }
        continueTab.updateSections([CPListSection(items: items)])
    }

    private func play(_ id: String) {
        guard let catalog = CarPlayServices.catalog, let player = CarPlayServices.player else { return }
        Task {
            await catalog.whenReady()
            guard let detail = await catalog.episodeDetail(id) else { return }
            player.isMuted = CarPlayServices.store?.isMuted ?? false
            player.play(detail)
            // AudioPlayer already publishes Now Playing and the remote
            // commands; the shared template reads them.
            interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
        }
    }
}
#endif
