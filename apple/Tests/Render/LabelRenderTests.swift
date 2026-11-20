import AppKit
import CoreText
import SwiftUI
import XCTest

// The label (Decision 081) drawn to PNG through ImageRenderer so a person can look at it against the web's
// sheet (docs/research/design/img/v3/label-sheet-*.png). Skipped unless GRAMMAR_RENDER_DIR is set
// (xcodebuild: TEST_RUNNER_GRAMMAR_RENDER_DIR=<dir>).

nonisolated final class LabelRenderTests: XCTestCase {
    @MainActor func testLabelSheet() throws {
        guard let path = ProcessInfo.processInfo.environment["GRAMMAR_RENDER_DIR"], !path.isEmpty else {
            throw XCTSkip("GRAMMAR_RENDER_DIR is not set")
        }
        let out = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        CTFontManagerRegisterFontsForURL(repo.appending(path: "apple/Resources/Fonts/BigShoulders-Bold.ttf") as CFURL, .process, nil)

        let suspense = LabelItem(kind: .series, name: "Suspense", genre: "mystery", first: "1942-06-17", last: "1962-09-30", network: "CBS")
        let gunsmoke = LabelItem(kind: .series, name: "Gunsmoke", genre: "western", first: "1952", last: "1961", network: "CBS")
        let xminus = LabelItem(kind: .series, name: "X Minus One", genre: "scifi", first: "1955", last: "1958", network: "NBC")
        let ranger = LabelItem(kind: .series, name: "Ranger Bill", genre: "drama")
        let episode = LabelItem(kind: .episode, name: "Suspense", genre: "mystery", first: "1942-06-17", last: "1962-09-30",
                                network: "CBS", date: "1949-03-03")
        let numbered = LabelItem(kind: .episode, name: "Ranger Bill", genre: "drama", num: "7")
        let station = LabelItem(kind: .station, genre: "comedy", tickYear: "1939")
        let lady = LabelItem(kind: .drama, name: "The Lost Lady", genre: nil,
                             parts: [.init(lines: 50, hue: "mystery"), .init(lines: 42, hue: "scifi"), .init(lines: 20, hue: "western")],
                             finished: "2026-11-03")
        let person = LabelItem(kind: .person, name: "Orson Welles", first: "1934", last: "1946")
        let cast = LabelItem(kind: .play, cast: [120, 80, 40, 30, 10, 5, 5, 3, 2])
        let plain = LabelItem(kind: .series, name: "The Case Closed")

        func tile(_ item: LabelItem, _ side: CGFloat) -> some View {
            LabelView(item: item, side: side).frame(width: side, height: side)
                .clipShape(item.kind == .person ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 4)))
        }
        func sheet(dark: Bool) -> some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    tile(suspense, 320); tile(episode, 320)
                }
                HStack(alignment: .top, spacing: 16) {
                    tile(gunsmoke, 200); tile(lady, 200); tile(person, 200); tile(cast, 200)
                }
                HStack(alignment: .top, spacing: 16) {
                    ForEach(Array([suspense, xminus, ranger, plain, episode, numbered, station, lady, person, cast].enumerated()), id: \.offset) { _, it in
                        tile(it, 128)
                    }
                }
                HStack(alignment: .top, spacing: 16) {
                    ForEach(Array([suspense, xminus, ranger, plain, episode, numbered, station, lady, person, cast].enumerated()), id: \.offset) { _, it in
                        tile(it, 56)
                    }
                    tile(suspense, 40)
                }
            }
            .padding(24)
            .background(Color.brandBackground)
            .environment(\.colorScheme, dark ? .dark : .light)
        }
        for dark in [false, true] {
            let renderer = ImageRenderer(content: sheet(dark: dark))
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.cgImage, "the label sheet did not render")
            let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try png.write(to: out.appending(path: "label-sheet-apple\(dark ? "-dark" : "").png"))
        }
        let lock = try XCTUnwrap(LabelView.image(episode))
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: lock).representation(using: .png, properties: [:]))
        try png.write(to: out.appending(path: "lock-screen-apple.png"))
        XCTAssertEqual(lock.width, 512)
    }
}
