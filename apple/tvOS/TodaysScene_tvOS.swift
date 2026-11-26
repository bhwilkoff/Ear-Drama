#if os(tvOS)
import SwiftUI

// Today's Scene on the TV (tvOS-DESIGN §2.1, Decision 079): the same pick as every platform, one wide card in its own
// focus section, the opening at 29 pt or larger, and Hear It alone. No Try a Line (the TV records nothing) and no Read.
// The library index and the script come through the one APIClient and are kept only in the URL cache (Caches); Hear It
// speaks live and stores nothing, its cast held in memory.

struct TodaysScene_tvOS: View {
    @Environment(AudioPlayer.self) private var player
    @State private var row: PlayRow?
    @State private var script: PlayScript?
    @State private var reading = SceneReading()

    private var opening: [OpeningSpeech] { script?.opening(n: 4) ?? row?.opening(n: 4) ?? [] }

    var body: some View {
        // A stack, not a Group: a lazy stack never runs the task of a child with nothing in it yet.
        VStack(alignment: .leading, spacing: 0) {
            if let row, !opening.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    VStack(alignment: .leading, spacing: Spacing.s1) {
                        Text("Today\u{2019}s Scene").font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                        Text(verbatim: row.title).font(TypeRamp.sectionHeader).foregroundStyle(Color.brandText)
                        EventLine(facts: [row.authorLine, row.voicesText, row.minutesText])
                    }
                    ScenePage(opening: opening, hue: { SceneScript.hue(script, $0) }, current: reading.current, lines: 2)
                    if script != nil, SceneReading.hasVoice {
                        Button { hear() } label: {
                            Label(reading.isRunning ? "Stop" : "Hear It", systemImage: reading.isRunning ? "stop.fill" : "speaker.wave.2")
                        }
                        .accessibilityIdentifier("scene-hear")
                    }
                }
                .frame(maxWidth: 1400, alignment: .leading)
                .focusSection()
                .accessibilityIdentifier("todays-scene")
            }
        }
        .task { await load() }
        .onDisappear { reading.stop() }
    }

    private func hear() {
        if reading.isRunning { reading.stop(); return }
        guard let script else { return }
        let cast = VoiceCast(key: VoiceCastBook.scriptKey(script.id), parts: script.castParts.map(\.id),
                             registers: script.registers, voices: { DeviceVoices.castable() }, storage: .memory())
        reading.start(opening, cast: cast, player: player)
    }

    private func load() async {
        guard row == nil,
              let data = try? await APIClient.shared.playsData("library/index.json"),
              let index = try? JSONDecoder().decode(PlayRowIndex.self, from: data),
              let pick = PlayScript.todaysScene(index.plays, dateKey: RadioClock.localDate()) else { return }
        row = pick
        guard let path = pick.path, let file = try? await APIClient.shared.playsData("library/\(path)") else { return }
        script = (try? JSONDecoder().decode(CastableLibrary.self, from: file))?.scripts.first { $0.id == pick.id }
    }
}
#endif
