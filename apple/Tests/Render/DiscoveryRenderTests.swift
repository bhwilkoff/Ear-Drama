import AppKit
import CoreText
import SwiftUI
import XCTest

// D3-8: Stations, Surprise, Search's people and a person's page, drawn to PNG through ImageRenderer so
// a person can look at them. Skipped unless GRAMMAR_RENDER_DIR is set
// (xcodebuild: TEST_RUNNER_GRAMMAR_RENDER_DIR=<dir>). Pictures are remote and ImageRenderer draws no
// network image, so every window here shows its title block, the designed bare case. Nothing plays.

nonisolated final class DiscoveryRenderTests: XCTestCase {
    @MainActor func testStationsSurprisePeopleAndAPersonsPage() throws {
        guard let path = ProcessInfo.processInfo.environment["GRAMMAR_RENDER_DIR"], !path.isEmpty else {
            throw XCTSkip("GRAMMAR_RENDER_DIR is not set")
        }
        let out = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        CTFontManagerRegisterFontsForURL(repo.appending(path: "apple/Resources/Fonts/BigShoulders-Bold.ttf") as CFURL, .process, nil)
        let library = try JSONDecoder().decode(CastableLibrary.self,
                                               from: Data(contentsOf: repo.appending(path: "catalog/plays/castable-scripts.json")))
        let script = try XCTUnwrap(library.scripts.first { $0.id == "gut-28051" })

        func render<V: View>(_ name: String, width: CGFloat, height: CGFloat, dark: Bool, @ViewBuilder _ content: () -> V) throws {
            let view = content()
                .environment(AppStore())
                .tint(Color.brandSecondary)
                .frame(width: width, height: height, alignment: .top)
                .background(Color.brandBackground)
                .environment(\.colorScheme, dark ? .dark : .light)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.cgImage, "\(name) did not render")
            let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try png.write(to: out.appending(path: "\(name)-\(Int(width))\(dark ? "-dark" : "").png"))
        }
        func both<V: View>(_ name: String, width: CGFloat, height: CGFloat, @ViewBuilder _ content: () -> V) throws {
            for dark in [false, true] { try render(name, width: width, height: height, dark: dark, content) }
        }

        let start = Date(timeIntervalSince1970: 1_700_000_000)
        func slot(_ minutes: Int, known: String?) -> RadioSlot {
            RadioSlot(etStart: "19:00", etEnd: "19:30", lengthMin: 30, utcStart: start.addingTimeInterval(Double(minutes) * 60),
                      utcEnd: start.addingTimeInterval(Double(minutes + 30) * 60), gap: true, knownSeries: known)
        }

        try both("stations", width: 390, height: 640) {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    StationRow(name: "Tonight in 1952", genre: nil, slot: nil, note: "Starts at 7:00 PM", isLive: false,
                               canListen: false, listen: {}, stop: {})
                    StationRow(name: "Mystery", genre: "mystery", slot: nil, note: "Not in the catalog", isLive: true,
                               canListen: true, listen: {}, stop: {})
                    StationRow(name: "Science fiction", genre: "scifi", slot: nil, note: nil, isLive: false,
                               canListen: true, listen: {}, stop: {})
                }
                Group {
                    SlotRow(slot: slot(0, known: "Lux Radio Theatre"), zone: "America/New_York", detail: nil, isNow: true) { _ in }
                    GrammarRow(visual: .window(nil, name: "Suspense", genre: "mystery"), title: "Suspense",
                               sub: ["7:30 PM", "Cabin B-13"], length: "30 min")
                    SlotRow(slot: slot(60, known: nil), zone: "America/New_York", detail: nil, isNow: false) { _ in }
                }
            }
        }

        let board = { (name: String, genre: String?, facts: [String?]) in
            HeadBoard(kicker: nil, name: name, genre: genre, art: nil, first: "1942", last: "1962", facts: facts)
        }
        try both("surprise", width: 390, height: 860) {
            VStack(alignment: .leading, spacing: Spacing.s6) {
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    Text("An episode").font(TypeRamp.sectionHeader)
                    board("The Chase and Sanborn Hour", "comedy", ["Guest Clark Gable and Vera Vague", "1940-02-18"])
                    Button { } label: { Label("Play", systemImage: "play.fill").foregroundStyle(Color.brandOnPrimary) }
                        .buttonStyle(.borderedProminent).tint(Color.brandPrimary)
                }
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    Text("An evening").font(TypeRamp.sectionHeader)
                    HeadBoard(kicker: nil, name: "Tuesday, November 10, 1942", genre: "mystery", art: nil, first: nil, last: nil,
                              facts: ["CBS", "WJSV", "Lights Out"])
                    Button { } label: { Label("Play", systemImage: "play.fill").foregroundStyle(Color.brandOnPrimary) }
                        .buttonStyle(.borderedProminent).tint(Color.brandPrimary)
                }
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    Text("A play").font(TypeRamp.sectionHeader)
                    HeadBoard(kicker: nil, name: script.title, genre: PlayScript.boardGenre, art: nil, first: nil, last: nil,
                              facts: PlayHead.facts(script), credits: script.authorLineWithYears, castScript: script)
                }
            }
            .padding(Spacing.s4)
        }

        let person = Person(id: "p", name: "Orson Welles", birth: "1915", death: "1985")
        let shows = [("Columbia Workshop", "drama", "1936", "1937", 4), ("Les Miserables", "drama", "1937", "1937", 7),
                     ("Mercury Theatre", "mystery", "1938", "1946", 17)]
        try both("person", width: 390, height: 760) {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                HeadBoard(kicker: nil, name: person.name, genre: nil, art: nil, first: "1936", last: "1946",
                          years: [1936, 4, 7, 6, 0, 0, 3, 5, 9, 1, 2, 1, 0, 0, 1],
                          facts: [person.years, "225 episodes", "30 shows"])
                    HStack(alignment: .top, spacing: Spacing.s3) {
                        ForEach(Array(shows.prefix(2)), id: \.0) { show in
                            ShowTile(series: SeriesRow(key: show.0, name: show.0, genre: show.1, firstDate: show.2, lastDate: show.3,
                                                       networks: [], episodeCount: show.4),
                                     width: 160, facts: ["\(show.2)\u{2013}\(show.3)", "\(show.4) episodes"])
                        }
                    }
                    .sharesNameHeight()
                GrammarRow(visual: .date("1936-09-19", number: nil, genre: "drama"), title: "Hamlet, Part 1", sub: ["Host"],
                           length: "30:00")
                GrammarRow(visual: .date("1937-04-11", number: nil, genre: "drama"), title: "The Fall of the City", sub: ["Cast as The Announcer"],
                           length: "30:00")
                Divider()
                PersonRowLabel(row: PersonRow(person: person, episodes: 225))
                PersonRowLabel(row: PersonRow(person: Person(id: "q", name: "Jack Webb", birth: nil, death: nil), episodes: 405))
            }
            .padding(Spacing.s4)
        }
    }
}
