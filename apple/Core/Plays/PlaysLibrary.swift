#if os(iOS) || os(macOS)
import Foundation

/// The Plays tab's state: the bundled castable scripts and the productions on
/// this device. Created at launch, but it opens no audio and asks for nothing;
/// the microphone is asked for only when a performer starts recording (§2.3).
@Observable
final class PlaysLibrary {
    enum State: Equatable {
        case loading
        case ready
        case unavailable
    }

    private(set) var state: State = .loading
    private(set) var scripts: [PlayScript] = []
    let store: ProductionStore

    init(store: ProductionStore = ProductionStore()) {
        self.store = store
    }

    func load() async {
        guard state != .ready else { return }
        let library = await Task.detached(priority: .userInitiated) { CastableLibrary.load() }.value
        if let library {
            scripts = library.scripts
            state = .ready
        } else {
            state = .unavailable
        }
    }

    func script(_ id: String) -> PlayScript? { scripts.first { $0.id == id } }

    /// The script a production was cast from, as stored with it.
    func castScript(for production: Production) -> PlayScript? { store.script(for: production) }
}
#endif
