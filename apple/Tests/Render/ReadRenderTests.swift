import AppKit
import CoreText
import SwiftUI
import XCTest

// Reading together (T4): the shared screen a TV or a projector shows, and a reader following a class room, drawn to PNG
// through ImageRenderer so a person can look at them. Skipped unless GRAMMAR_RENDER_DIR is set
// (xcodebuild: TEST_RUNNER_GRAMMAR_RENDER_DIR=<dir>). Nothing here plays sound or touches the network: the snapshot is a
// fixture. The class page and the casting board sit in a List and a Menu, which ImageRenderer cannot draw, so they are not
// rendered on Apple (the Android render shows the same board).

nonisolated final class ReadRenderTests: XCTestCase {
    private static let snapshotJSON = """
    {"type":"snapshot","code":"KLS456","kind":"class","mode":"read","script_id":"fixture","script_revision":"r1","cursor":"l3","cursor_gen":2,
    "generation":4,"locked":false,"ended":false,"leader":"teacher","leader_name":"Ms. Ortiz","read_open":false,"waiting_for_leader":false,
    "you":{"id":"d1","role":"reader","seat":"s1","leads":false,"owner":false},"next_mine":{"line":"l3","in":0},
    "reads_now":{"part":"role:LUCY","seat":"s1","members":["d1"]},"members":[{"id":"teacher","role":"reader","live":true},{"id":"d1","role":"reader","seat":"s1","live":true}],
    "present":9,"claims":{},"seats":[{"id":"s1","label":"Ada"},{"id":"s2","label":"Ben"}],
    "assignments":[{"part":"role:LUCY","seat":"s1"},{"part":"role:TOM","seat":"s2"}],"done":[],"server_time":1763500000000}
    """

    @MainActor private func script() -> PlayScript {
        func say(_ id: String, _ role: String, _ text: String) -> ScriptLine { ScriptLine(id: id, kind: .speech, role: role, parts: [.say(text)]) }
        let lines = [
            say("l1", "LUCY", "I thought you had gone out to the garden."),
            say("l2", "TOM", "The rain turned me back at the gate."),
            say("l3", "LUCY", "Then sit with me, and we will read the letter together."),
            say("l4", "NURSE", "Supper is on the table, if you please."),
            say("l5", "TOM", "Lucy, wait. Listen to that."),
        ]
        let roles = ["LUCY", "TOM", "NURSE"].map { n in PlayScript.Role(name: n, lines: lines.filter { $0.role == n }.count, words: 8) }
        return PlayScript(id: "fixture", revision: "r1", kind: "radio", title: "The Lost Lady", authors: [],
                          source: .init(name: "Fixture", url: "https://example.org"),
                          rights: .init(bucket: "script_source_cleared", evidence: []), roles: roles, lines: lines)
    }

    @MainActor private func render<V: View>(_ name: String, width: CGFloat, height: CGFloat, dark: Bool, out: URL, @ViewBuilder _ content: () -> V) throws {
        let view = content()
            .tint(Color.brandSecondary)
            .frame(width: width, height: height, alignment: .top)
            .background(Color.brandBackground)
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage, "\(name) did not render")
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try png.write(to: out.appending(path: "\(name)-\(Int(width))\(dark ? "-dark" : "").png"))
    }

    @MainActor func testSharedScreenAndReader() throws {
        guard let path = ProcessInfo.processInfo.environment["GRAMMAR_RENDER_DIR"], !path.isEmpty else {
            throw XCTSkip("GRAMMAR_RENDER_DIR is not set")
        }
        let out = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        CTFontManagerRegisterFontsForURL(repo.appending(path: "apple/Resources/Fonts/BigShoulders-Bold.ttf") as CFURL, .process, nil)
        let snap = try JSONDecoder().decode(ReadSnapshot.self, from: Data(Self.snapshotJSON.utf8))
        let play = script()
        let cast = play.lines.map { ($0.id, $0.part.rawValue) }
        let mine = Set(ReadCore.mineIndexes(snap.room, cast: cast, member: snap.meMember))
        for dark in [false, true] {
            try render("read-screen", width: 1280, height: 720, dark: dark, out: out) {
                ReadScreenView(snapshot: snap, status: "", script: play)
            }
            try render("read-reader", width: 390, height: 520, dark: dark, out: out) {
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    ForEach(Array(play.lines.enumerated()), id: \.element.id) { i, line in
                        ReadLineRow(line: line, current: line.id == snap.cursor, mine: mine.contains(i), hidden: false)
                    }
                    Spacer()
                    Text(verbatim: ReadCore.nextLine(snap.nextMine.map { ReadCore.Next(line: $0.line, inLines: $0.in) }) ?? "")
                        .font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                }
                .padding(Spacing.s4)
            }
        }
    }
}
