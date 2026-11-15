#if os(iOS) || os(macOS)
import SwiftUI

/// A production's listen-through inside the reader (PLAYS-DESIGN §2.11): the plan from the position on, takes from
/// their files and open lines in the cast's device voices, live and never stored; the reader follows `listen.current`.
@Observable
final class AlongModel {
    let listen: LiveListenThrough
    @ObservationIgnored private let production: Production
    @ObservationIgnored private let script: PlayScript
    @ObservationIgnored private let store: ProductionStore

    init(production: Production, script: PlayScript, plays: PlaysLibrary) {
        self.production = production
        self.script = script
        store = plays.store
        listen = .system(cast: .production(production.id, script: script))
    }

    func toggle(from position: Int, player: AudioPlayer) {
        if listen.isRunning { listen.stop(); return }
        player.pause()
        let latest = store.production(production.id) ?? production
        let ids = Set(script.lines[min(max(0, position), script.lines.count - 1)...].map(\.id))
        let plan = Relay.listenPlan(latest, script, reads: listen.reads).filter { ids.contains($0.lineID) }
        let store = store
        Task { await listen.run(plan) { store.takeURL(latest, $0) } }
    }

    func stop() { listen.stop() }
}

/// Read Along on a production's page: opens the reader on the production's own script, following its listen-through.
struct ReadAlongButton: View {
    let production: Production
    @Environment(AppStore.self) private var app
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        Button { open() } label: { ActionLabel(title: "Read Along", systemImage: "text.book.closed") }
            .pageAction()
            .accessibilityIdentifier("read-along-button")
    }

    private func open() {
        let target = StudioTarget.along(production.id)
        #if os(macOS)
        openWindow(id: StudioWindow_macOS.id, value: StudioWindowValue(target: target, line: nil))
        #else
        app.reading = ReaderTarget(scriptID: production.scriptID, studio: target)
        #endif
    }
}
#endif
