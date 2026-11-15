#if os(iOS) || os(macOS)
import SwiftUI

/// A production's listen-through inside the reader (PLAYS-DESIGN §2.11): the plan from the position on, takes from
/// their files and open lines in the cast's device voices, live and never stored; the reader follows `listen.current`.
@Observable
final class AlongModel {
    /// A production's listen-through; nil for a finished drama.
    let listen: LiveListenThrough?
    /// A finished drama's files, the file playing naming the line heard (PLAYS-DESIGN 2.11 rule 6); nil for a production.
    let drama: FinishedListen?
    @ObservationIgnored private let production: Production?
    @ObservationIgnored private let play: FinishedPlay?
    @ObservationIgnored private let script: PlayScript
    @ObservationIgnored private let store: ProductionStore?

    init(production: Production, script: PlayScript, plays: PlaysLibrary) {
        self.production = production
        self.script = script
        play = nil
        drama = nil
        store = plays.store
        listen = .system(cast: .production(production.id, script: script))
    }

    init(play: FinishedPlay, script: PlayScript) {
        self.play = play
        self.script = script
        production = nil
        store = nil
        listen = nil
        drama = FinishedListen()
    }

    var isRunning: Bool { listen?.isRunning ?? drama?.isActive ?? false }
    /// The line heard now.
    var lineID: String? { listen?.current?.lineID ?? drama?.lineID }
    /// A line the device reads aloud; a finished drama has only voices.
    var deviceVoice: Bool { listen?.current?.isDeviceVoice ?? false }

    func toggle(from position: Int, player: AudioPlayer, muted: Bool = false) {
        if isRunning { stop(); return }
        player.pause()
        let from = script.lines[min(max(0, position), script.lines.count - 1)...].map(\.id)
        if let drama, let play {
            drama.muted = muted
            Task { await drama.start(archiveURL: play.archiveURL, script: script, revision: play.scriptRevision, from: from.first) }
            return
        }
        guard let listen, let production, let store else { return }
        let latest = store.production(production.id) ?? production
        let ids = Set(from)
        let plan = Relay.listenPlan(latest, script, reads: listen.reads).filter { ids.contains($0.lineID) }
        Task { await listen.run(plan) { store.takeURL(latest, $0) } }
    }

    func stop() {
        listen?.stop()
        drama?.stop()
    }
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
