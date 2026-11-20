import AppKit
import CoreText
import SwiftUI
import XCTest

// V6: Home's first screen, drawn to PNG through ImageRenderer so a person can look at it: the On the air hero, the dial,
// the doors, the one-ink day board and Today's Scene's wide card, at a phone and a wide column, light and dark. Skipped
// unless GRAMMAR_RENDER_DIR is set (xcodebuild: TEST_RUNNER_GRAMMAR_RENDER_DIR=<dir>). The hero draws the show's label
// (a picture would load over the network, which a render does not wait for). ImageRenderer cannot draw a List, so the
// pieces are drawn in a column by their own views.

nonisolated final class HomeRenderTests: XCTestCase {
    @MainActor func testHomeFirstScreen() throws {
        let rig = try HomeRig()
        try rig.firstScreen(raw: false)
    }

    @MainActor func testHomeFirstScreenWithARawTitle() throws {
        let rig = try HomeRig()
        try rig.firstScreen(raw: true)
    }

    @MainActor func testTodaysSceneWide() throws {
        let rig = try HomeRig()
        try rig.scene()
    }
}

private final class HomeRig {
    private let out: URL
    private let repo: URL
    private let app = AppStore()

    init() throws {
        guard let path = ProcessInfo.processInfo.environment["GRAMMAR_RENDER_DIR"], !path.isEmpty else {
            throw XCTSkip("GRAMMAR_RENDER_DIR is not set")
        }
        out = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        CTFontManagerRegisterFontsForURL(repo.appending(path: "apple/Resources/Fonts/BigShoulders-Bold.ttf") as CFURL, .process, nil)
    }

    @MainActor private func render<V: View>(_ name: String, width: CGFloat, dark: Bool, @ViewBuilder _ content: (CGFloat) -> V) throws {
        let view = content(width)
            .environment(app)
            .tint(Color.brandSecondary)
            .padding(.vertical, Spacing.s4)
            .frame(width: width, alignment: .top)
            .fixedSize(horizontal: false, vertical: true)
            .background(Color.brandBackground)
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage, "\(name) did not render")
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try png.write(to: out.appending(path: "\(name)-\(Int(width))\(dark ? "-dark" : "").png"))
    }

    @MainActor private func both<V: View>(_ name: String, @ViewBuilder _ content: (CGFloat) -> V) throws {
        for width in [CGFloat(390), 900] {
            for dark in [false, true] { try render(name, width: width, dark: dark, content) }
        }
    }

    // MARK: Fixtures

    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var now: Date { start.addingTimeInterval(300) }

    private func slot(_ id: String, _ series: String, _ title: String) -> RadioSlot {
        RadioSlot(etStart: "8:00", etEnd: "8:30", lengthMin: 30, utcStart: start, utcEnd: start.addingTimeInterval(1800),
                  episode: RadioSlot.Episode(id: id, series: series, title: title, lengthS: 1800), withheld: false)
    }

    private var stations: [Station] {
        [("drama", "Drama", "sol|1948-03-02", "Soldiers of the Press"), ("mystery", "Mystery", "whistler|1944-05-01", "The Whistler"),
         ("scifi", "Science fiction", "gl|1951-02-02", "Gregory Lyons"), ("western", "Western", "ga|1949-07-07", "Gene Autry's Melody Ranch"),
         ("comedy", "Comedy", "dr|1946-10-10", "Dr I Q the Mental Banker"), ("news", "News", "cbs|1941-12-08", "CBS World News"),
         ("documentary", "Documentary", "js|1947-11-11", "The Jean Shepherd Show"), ("serial", "Serials", "jc|1945-01-15", "Jerry of the Circus")]
            .map { Station(genre: $0.0, name: $0.1, slots: [slot($0.2, $0.3, "Ep")]) }
    }

    private func episode(_ key: String, _ date: String) -> EpisodeRow {
        EpisodeRow(id: "\(key)|\(date)", seriesKey: key, seriesName: key, airDate: date, season: nil, number: nil, title: nil,
                   lengthSeconds: 1800, rights: "unclaimed", rightsBasis: nil, network: nil)
    }

    @MainActor func firstScreen(raw: Bool) throws {
        let series = SeriesRow(key: "ellery", name: "The Adventures of Ellery Queen", genre: "mystery", firstDate: "1939-06-18",
                               lastDate: "1948-05-30", networks: ["CBS"], episodeCount: 120, face: nil, picture: nil)
        let title = raw ? "AbyM #026 The Telltale Bottle" : "The Telltale Bottle"
        let station = Station(genre: "mystery", name: "Tonight in 1939", slots: [slot("ellery|1939-04-02", series.name, title)])
        let on = try XCTUnwrap(OnAirNow.pick(day: nil, stations: [station], now: now))
        let rows = [episode("a", "1938-04-02"), episode("b", "1938-04-02"), episode("c", "1939-04-02"),
                    episode("d", "1941-04-02"), episode("e", "1941-04-02"), episode("f", "1944-04-02")]
        let genres = ["a": "drama", "b": "mystery", "c": "western", "d": "comedy", "e": "drama", "f": "news"]
        let day = HomeDay(month: 4, day: 2, episodes: rows, series: [:],
                          years: ShowLine.dayYears(rows, date: \.airDate, genre: { genres[$0.seriesKey] }))
        let entries = DialEntry.entries(stations, now: now)
        try both(raw ? "home-raw" : "home-first") { width in
            VStack(alignment: .leading, spacing: Spacing.s3) {
                OnAirHeroBoard(on: on, series: series, now: now, listening: false, onListen: {}, onStations: {})
                    .padding(.horizontal, Spacing.s4)
                DialRow(entries: Array(entries.prefix(width < 500 ? 4 : 8)), listening: nil, scrolls: false, tune: { _ in })
                HomeDoors()
                    .padding(.horizontal, Spacing.s4)
                DayBoard(model: day, selected: .constant(1941), interactive: false)
                    .padding(.horizontal, Spacing.s4)
            }
        }
    }

    @MainActor func scene() throws {
        let library = try JSONDecoder().decode(CastableLibrary.self,
                                               from: Data(contentsOf: repo.appending(path: "catalog/plays/castable-scripts.json")))
        let today = try XCTUnwrap(PlayScript.todaysScene(library.scripts, dateKey: "2026-11-14"))
        let opening = today.opening(n: 4)
        try both("home-scene") { _ in
            VStack(alignment: .leading, spacing: Spacing.s3) {
                SectionHead(title: "Record a play") { EmptyView() }
                SceneWideLayout(hasPage: true, words: {
                    VStack(alignment: .leading, spacing: Spacing.s3) {
                        VStack(alignment: .leading, spacing: Spacing.s1) {
                            Text("Today\u{2019}s Scene").font(TypeRamp.caption)
                            Text(verbatim: today.title).font(TypeRamp.sectionHeader)
                        }
                        .foregroundStyle(Color.brandText)
                        ActionRow {
                            Button { } label: { Label("Try a Line", systemImage: "mic") }.pageAction(primary: true)
                            Button { } label: { ActionLabel(title: "Hear It", systemImage: "speaker.wave.2") }.pageAction()
                            Button { } label: { ActionLabel(title: "Read", systemImage: "book") }.pageAction()
                        }
                    }
                }, page: {
                    ScenePage(opening: opening, hue: { SceneScript.hue(today, $0) }, current: nil)
                })
            }
            .padding(.horizontal, Spacing.s4)
        }
    }
}
