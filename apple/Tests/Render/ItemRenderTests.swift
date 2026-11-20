import AppKit
import CoreText
import SwiftUI
import XCTest

// V7: the item pages' heads drawn to PNG through ImageRenderer so a person can look at them: a series (a picture, the
// label, a wide hero), an episode, a person (portrait and label), a play (its opening as a page) and a finished ear
// drama, at a phone and a wide column, light and dark. Skipped unless GRAMMAR_RENDER_DIR is set. The pictures are
// stubs drawn here and seeded into the picture cache (the pipeline has not published a hero or gallery yet, and a render
// does not wait for the network). ImageRenderer cannot draw a List, so the pieces are drawn in a column by their own views.

nonisolated final class ItemRenderTests: XCTestCase {
    @MainActor func testSeries() throws {
        let rig = try ItemRig()
        try rig.series()
    }

    @MainActor func testEpisode() throws {
        let rig = try ItemRig()
        try rig.episode()
    }

    @MainActor func testPerson() throws {
        let rig = try ItemRig()
        try rig.person()
    }

    @MainActor func testPlayAndDrama() throws {
        let rig = try ItemRig()
        try rig.play()
    }
}

private final class ItemRig {
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

    /// A photograph's stand-in: a graded studio backdrop with a head and shoulders, drawn in gray at the picture's own size.
    private func stub(_ name: String, _ w: Int, _ h: Int, figures: Int = 1) -> Artwork {
        let url = URL(string: "https://upload.example/\(name).jpg")!
        let space = CGColorSpaceCreateDeviceGray()
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        let gradient = CGGradient(colorsSpace: space, colors: [CGColor(gray: 0.78, alpha: 1), CGColor(gray: 0.28, alpha: 1)] as CFArray,
                                  locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(h)), end: CGPoint(x: CGFloat(w), y: 0), options: [])
        for i in 0..<figures {
            let cx = CGFloat(w) * (CGFloat(i) + 0.5) / CGFloat(figures)
            let r = CGFloat(min(w / figures, h)) * 0.17
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: cx - r, y: CGFloat(h) * 0.5, width: 2 * r, height: 2.3 * r))
            ctx.fillEllipse(in: CGRect(x: cx - 2.4 * r, y: -r, width: 4.8 * r, height: CGFloat(h) * 0.5 + r))
        }
        let image = ctx.makeImage()!
        let art = Artwork(url: url, width: w, height: h, credit: "Library of Congress",
                          evidence: URL(string: "https://commons.wikimedia.org/wiki/File:\(name).jpg"))
        for step in Artwork.steps { PictureGrade.seed(image, url: art.url(pixels: Double(step))) }
        return art
    }

    private let genreSeries = SeriesRow(key: "suspense", name: "Suspense", genre: "mystery", firstDate: "1940-06-17", lastDate: "1962-09-30",
                                        networks: ["CBS"], episodeCount: 1077, face: nil, picture: nil,
                                        yearCounts: [1940, 6, 41, 52, 50, 52, 52, 48, 50, 52, 50, 47, 41, 35, 30, 22, 14, 6, 2, 2, 1, 1, 1])

    private var facts: [String?] { SeriesHead.facts(genreSeries) }
    private var kicker: AnyView { ItemKicker.genre("mystery", rest: "CBS") }

    // MARK: The pages

    @MainActor func series() throws {
        let s = genreSeries
        let upright = stub("jackwebb", 640, 800)
        let wide = stub("studio", 1600, 900, figures: 2)
        let gallery = [stub("g1", 900, 600, figures: 3), stub("g2", 600, 800), stub("g3", 700, 700)]
        try both("series-label") { _ in
            VStack(alignment: .leading, spacing: Spacing.s3) {
                ItemHeadBoard(kicker: kicker, name: s.name, genre: s.genre, label: s.labelItem, facts: facts,
                              first: s.firstDate, last: s.lastDate, years: s.yearCounts)
                ActionRow {
                    Button { } label: { Label("Follow", systemImage: "plus") }.pageAction(primary: true)
                    Button { } label: { ActionLabel(title: "Share", systemImage: "square.and.arrow.up") }.pageAction()
                }
            }
            .padding(.horizontal, Spacing.s4)
        }
        try both("series-picture") { _ in
            VStack(alignment: .leading, spacing: Spacing.s3) {
                ItemHeadBoard(kicker: kicker, name: s.name, genre: s.genre, art: upright, label: s.labelItem, facts: facts,
                              first: s.firstDate, last: s.lastDate, years: s.yearCounts)
                SeriesGallery(pictures: gallery)
            }
            .padding(.horizontal, Spacing.s4)
        }
        try both("series-hero") { _ in
            ItemHeadBoard(kicker: kicker, name: s.name, genre: s.genre, art: wide, label: s.labelItem, facts: facts,
                          first: s.firstDate, last: s.lastDate, years: s.yearCounts)
                .padding(.horizontal, Spacing.s4)
        }
    }

    @MainActor func episode() throws {
        let s = genreSeries
        let show = stub("showpic", 700, 700, figures: 2)
        let ep = EpisodeRow(id: "suspense|1942-12-22", seriesKey: "suspense", seriesName: "Suspense", airDate: "1942-12-22", season: "1942-43",
                            number: 22, title: "Two Sharp Knives", lengthSeconds: 1800, rights: "unclaimed", rightsBasis: nil, network: "CBS", seriesGenre: "mystery")
        try both("episode") { _ in
            VStack(alignment: .leading, spacing: Spacing.s3) {
                ItemHeadBoard(kicker: ItemKicker.show("Suspense", key: "suspense"), name: ItemLead.episodeTitle(ep), genre: "mystery",
                              label: ep.labelItem(series: s),
                              facts: Grammar.episodeFacts(date: AirDate.display(ep.airDate), network: "CBS", sponsor: nil, length: "30:00",
                                                          season: ep.season, title: ep.title, number: ep.number),
                              first: s.firstDate, last: s.lastDate, years: s.yearCounts, markYear: 1942)
                ActionRow {
                    Button { } label: { Label("Play", systemImage: "play.fill") }.pageAction(primary: true)
                    Button { } label: { ActionLabel(title: "Add to Queue", systemImage: "text.badge.plus") }.pageAction()
                    Button { } label: { ActionLabel(title: "Share", systemImage: "square.and.arrow.up") }.pageAction()
                }
                GrammarRow(visual: .window(show, name: "Suspense", genre: "mystery"), title: "Suspense", sub: facts)
                PictureCredit(arts: [show], slot: 48)
                DisclosureGroup {
                    Text("Copy 1").font(TypeRamp.body)
                } label: {
                    HStack {
                        Text("Recordings").font(TypeRamp.bodyStrong)
                        Spacer(minLength: 0)
                        Text("6").font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                    }
                }
            }
            .padding(.horizontal, Spacing.s4)
        }
    }

    @MainActor func person() throws {
        let portrait = stub("webb", 640, 860)
        let years = [1946, 4, 0, 0, 2, 12, 20, 18, 5]
        let facts: [String?] = ["1920\u{2013}1982", "406 episodes", "17 shows"]
        for (name, art) in [("person-portrait", Optional(portrait)), ("person-label", nil)] {
            try both(name) { _ in
                ItemHeadBoard(name: "Jack Webb", genre: nil, art: art,
                              label: LabelItem(kind: .person, name: "Jack Webb", first: "1946", last: "1962"), round: true,
                              facts: facts, first: "1946", last: "1962", years: years)
                    .padding(.horizontal, Spacing.s4)
            }
        }
    }

    @MainActor func play() throws {
        let library = try JSONDecoder().decode(CastableLibrary.self,
                                               from: Data(contentsOf: repo.appending(path: "catalog/plays/castable-scripts.json")))
        let script = try XCTUnwrap(library.scripts.first { $0.id == "gut-28051" })
        try both("play") { _ in
            ItemHeadBoard(kicker: ItemKicker.text(PlayHead.kicker(script)), name: script.title, genre: PlayScript.boardGenre,
                          label: script.pageLabel, facts: PlayHead.facts(script), credits: script.authorLineWithYears,
                          cast: CastSummary(script: script),
                          customWindow: { side in AnyView(PlayOpeningWindow(script: script, side: side)) })
                .padding(.horizontal, Spacing.s4)
        }
        let page = stub("titlepage", 700, 1000)
        try both("play-titlepage") { _ in
            ItemHeadBoard(kicker: ItemKicker.text(PlayHead.kicker(script)), name: script.title, genre: PlayScript.boardGenre, art: page,
                          label: script.pageLabel, facts: PlayHead.facts(script), credits: script.authorLineWithYears,
                          cast: CastSummary(script: script))
                .padding(.horizontal, Spacing.s4)
        }
        try both("drama") { _ in
            ItemHeadBoard(kicker: ItemKicker.text("Ear drama"), name: script.title, genre: PlayScript.boardGenre,
                          label: script.dramaLabel(title: script.title, published: "2026-11-03"),
                          facts: [script.authorLineWithYears, "Nov 3, 2026"], credits: "With Ann, Ben, Cora",
                          cast: CastSummary(script: script))
                .padding(.horizontal, Spacing.s4)
        }
    }
}
