import AppKit
import CoreText
import SwiftUI
import XCTest

// Reading together (T4, T5): the shared screen, a reader inside a room (the reader's own page with my lines tinted, the
// cursor lit, and the room bar with its Record row), the receiver's Takes sheet, and the TV's pairing screen, drawn to
// PNG through ImageRenderer and the reader's own Core Text layout so a person can look at them. Skipped unless
// GRAMMAR_RENDER_DIR is set (xcodebuild: TEST_RUNNER_GRAMMAR_RENDER_DIR=<dir>). Nothing here plays sound or touches the
// network: the snapshots are fixtures and the wire answers from memory. The class page and the casting board sit in a
// List and a Menu, which ImageRenderer cannot draw, so they are not rendered on Apple.

nonisolated private final class RenderWire: ReadWire, @unchecked Sendable {
    func create(body: Data, teacher: Bool) async throws -> ReadJoined { throw ReadFailure(code: "error") }
    func join(code: String, body: Data) async throws -> ReadJoined { throw ReadFailure(code: "error") }
    func poll(code: String, key: String) async throws -> ReadSnapshot { throw ReadFailure(code: "error") }
    func send(code: String, key: String, message: Data) async throws -> ReadSnapshot? { nil }
    func socket(code: String) -> (any ReadSocket)? { nil }
    func sendTake(code: String, key: String, takeID: String, audio: Data, contentType: String, meta: TakeMeta) async throws {}
    func inbox(code: String, key: String) async throws -> PickedTake? { nil }
    func pair() async throws -> ReadPairing { throw ReadFailure(code: "error") }
    func pairWait(_ pairing: ReadPairing) async throws -> ReadJoined? { nil }
    func attachScreen(code: String, key: String, pairCode: String) async throws {}
}

nonisolated final class ReadRenderTests: XCTestCase {
    private static func snapshotJSON(you: String, mode: String, cursor: String, receives: Bool, done: [String] = [], nextIn: Int? = 2,
                                     readsPart: String = "role:TOM", holder: String = "bob", nurse: Bool = true) -> String {
        """
        {"type":"snapshot","code":"KLS456","kind":"adult","mode":"\(mode)","script_id":"fixture","script_revision":"r1","cursor":"\(cursor)","cursor_gen":2,
        "generation":4,"locked":false,"ended":false,"leader":"host","leader_name":"Ben","read_open":false,"waiting_for_leader":false,"receiver":"host",
        "you":{"id":"\(you)","role":"reader","name":"Ann","leads":\(receives),"owner":\(receives),"receives":\(receives)},
        "next_mine":\(nextIn.map { "{\"line\":\"l6\",\"in\":\($0)}" } ?? "null"),"reads_now":{"part":"\(readsPart)","members":["\(holder)"],"holder":"\(holder)"},
        "members":[{"id":"host","role":"reader","name":"Ben","live":true},{"id":"ann","role":"reader","name":"Ann","live":true},{"id":"bob","role":"reader","name":"Tom","live":true}],
        "present":3,"claims":{"role:LUCY":"ann","role:TOM":"bob"\(nurse ? ",\"role:NURSE\":\"host\"" : "")},"seats":[],"assignments":[],"done":[\(done.map { "\"\($0)\"" }.joined(separator: ","))],"server_time":1763500000000}
        """
    }

    private static func lines() -> [ScriptLine] {
        func say(_ id: String, _ role: String, _ text: String) -> ScriptLine { ScriptLine(id: id, kind: .speech, role: role, parts: [.say(text)]) }
        return [
            ScriptLine(id: "l0", kind: .direction, source: "(A drawing room. Rain at the window.)"),
            say("l1", "LUCY", "I thought you had gone out to the garden."),
            say("l2", "TOM", "The rain turned me back at the gate."),
            say("l3", "LUCY", "Then sit with me, and we will read the letter together."),
            say("l4", "NURSE", "Supper is on the table, if you please."),
            say("l5", "TOM", "Lucy, wait. Listen to that."),
            say("l6", "LUCY", "It is only the wind in the chimney. Come, sit."),
            say("l7", "TOM", "No. There. Someone is at the door."),
            say("l8", "NURSE", "At this hour? I will see who it is."),
        ]
    }

    @MainActor private func script() -> PlayScript {
        let lines = Self.lines()
        let roles = ["LUCY", "TOM", "NURSE"].map { n in PlayScript.Role(name: n, lines: lines.filter { $0.role == n }.count, words: 8) }
        return PlayScript(id: "fixture", revision: "r1", kind: "radio", title: "The Lost Lady", authors: [],
                          source: .init(name: "Fixture", url: "https://example.org"),
                          rights: .init(bucket: "script_source_cleared", evidence: []), roles: roles, lines: lines)
    }

    @MainActor private func snap(_ json: String) throws -> ReadSnapshot { try JSONDecoder().decode(ReadSnapshot.self, from: Data(json.utf8)) }

    @MainActor private func png<V: View>(_ name: String, width: CGFloat, height: CGFloat, dark: Bool, scale: CGFloat = 1, out: URL,
                                         @ViewBuilder _ content: () -> V) throws {
        let view = content()
            .tint(Color.brandSecondary)
            .frame(width: width, height: height, alignment: .top)
            .background(Color.brandBackground)
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let image = try XCTUnwrap(renderer.cgImage, "\(name) did not render")
        let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try data.write(to: out.appending(path: "\(name)-\(Int(width))\(dark ? "-dark" : "").png"))
    }

    /// The reader's own page for a room, drawn by the layout the Canvas calls: my lines tinted in their part's hue, the
    /// cursor lit across the line, and my line at the cursor outlined (red while the microphone is open).
    @MainActor private func pageImage(_ play: PlayScript, width: CGFloat, height: CGFloat, dark: Bool, mine: Set<Int>, lit: Int, recording: Bool) throws -> NSImage {
        let structure = ScriptStructure(play)
        let size = CGSize(width: width - 48, height: height - ReaderLayout.headRoom)
        let layout = try ReaderLayout.build(play, structure: structure, style: ReaderStyle(base: 17, scale: 1, leading: 1.55), pageSize: size, points: [])
        let view = CGSize(width: size.width, height: size.height + ReaderLayout.headRoom)
        let scale: CGFloat = 2
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.width * scale), pixelsHigh: Int(view.height * scale),
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let ctx = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep)).cgContext
        func rgb(_ hex: UInt32) -> CGColor {
            CGColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
        let theme = ReaderLayout.Theme(
            ink: rgb(dark ? 0xF2F2F4 : 0x131316), muted: rgb(dark ? 0xC4C4CC : 0x5C5C66),
            hues: (dark ? [0x8EBBFF, 0x44D5D7, 0xC99580, 0xAA87DE, 0x7CB45A, 0xD4C27E, 0xB4B3B3] : [0x2459A5, 0x007C88, 0x864E37, 0x5A3983, 0x2F6100, 0x816B01, 0x504C3E]).map { rgb(UInt32($0)) },
            background: rgb(dark ? 0x0F0F11 : 0xFFFFFF), block: rgb(dark ? 0x232327 : 0xE8E8EB),
            record: rgb(dark ? 0xFF6A5C : 0xC8281B))
        ctx.setFillColor(theme.background)
        ctx.fill(CGRect(origin: .zero, size: CGSize(width: view.width * scale, height: view.height * scale)))
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: 0, y: view.height)
        ctx.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        var marks = ReaderLayout.Marks()
        marks.mineLines = mine
        marks.along = lit
        if mine.contains(lit) { marks.current = lit }
        marks.outline = recording ? .recording : .ink
        marks.lineIndex = structure.indexByID
        layout.draw(page: layout.starts[lit], in: ctx, theme: theme, marks: marks)
        let image = NSImage(size: NSSize(width: view.width, height: view.height))
        image.addRepresentation(rep)
        return image
    }

    @MainActor func testRoomPairingAndTakes() throws {
        guard let path = ProcessInfo.processInfo.environment["GRAMMAR_RENDER_DIR"], !path.isEmpty else {
            throw XCTSkip("GRAMMAR_RENDER_DIR is not set")
        }
        let out = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        CTFontManagerRegisterFontsForURL(repo.appending(path: "apple/Resources/Fonts/BigShoulders-Bold.ttf") as CFURL, .process, nil)
        let play = script()
        let store = ProductionStore(root: FileManager.default.temporaryDirectory.appending(path: "render-room-\(UUID().uuidString)"))
        defer { try? FileManager.default.removeItem(at: store.root) }
        let app = AppStore()
        let plays = PlaysLibrary(store: store)

        // A reader (Ann holds LUCY) mid-room in Record: the cursor is on her line l3 and her microphone is open.
        let annSnap = try snap(Self.snapshotJSON(you: "ann", mode: "record", cursor: "l3", receives: false, nextIn: 0, readsPart: "role:LUCY", holder: "ann"))
        let session = ReadSession(wire: RenderWire())
        session.adopt(ReadJoined(snapshot: annSnap, key: "k", transport: "poll"))
        let room = RoomReaderModel(session: session, script: play, store: store, publishing: nil)
        let mine = Set(ReadCore.mineIndexes(annSnap.room, cast: room.cast, member: annSnap.meMember))
        XCTAssertEqual(mine, [1, 3, 6], "LUCY's lines")
        let waitSnap = try snap(Self.snapshotJSON(you: "ann", mode: "record", cursor: "l2", receives: false, nextIn: 1))
        let waitSession = ReadSession(wire: RenderWire())
        waitSession.adopt(ReadJoined(snapshot: waitSnap, key: "k", transport: "poll"))
        let waitRoom = RoomReaderModel(session: waitSession, script: play, store: store, publishing: nil)

        for dark in [false, true] {
            room.recorder.recording = "l3"
            let page = try pageImage(play, width: 390, height: 420, dark: dark, mine: mine, lit: 3, recording: true)
            try png("apple-read-room-reader-recording", width: 390, height: 520, dark: dark, scale: 2, out: out) {
                VStack(spacing: 0) {
                    Image(nsImage: page).frame(maxWidth: .infinity)
                    RoomBar(room: room, pageLabel: "1\u{2013}2 of 3")
                }
                .environment(app).environment(plays)
            }
            let wait = try pageImage(play, width: 390, height: 420, dark: dark, mine: mine, lit: 2, recording: false)
            try png("apple-read-room-reader-waiting", width: 390, height: 520, dark: dark, scale: 2, out: out) {
                VStack(spacing: 0) {
                    Image(nsImage: wait).frame(maxWidth: .infinity)
                    RoomBar(room: waitRoom, pageLabel: "1\u{2013}2 of 3")
                }
                .environment(app).environment(plays)
            }
        }

        // The receiver (Ben leads, receives) with takes in: the Takes sheet, counts per reader, each line's state.
        let hostSnap = try snap(Self.snapshotJSON(you: "host", mode: "record", cursor: "l5", receives: true, done: ["l3"], nurse: false))
        let hostSession = ReadSession(wire: RenderWire())
        hostSession.adopt(ReadJoined(snapshot: hostSnap, key: "k", transport: "poll"))
        let hostRoom = RoomReaderModel(session: hostSession, script: play, store: store, publishing: nil)
        hostRoom.recorder.accept(PickedTake(fields: .init(id: "t1", lineID: "l1", part: "role:LUCY", frames: 48_000, sampleRate: 48_000, capture: "room", seat: nil, file: "a.wav", member: "ann"), data: Data([1])))
        hostRoom.recorder.accept(PickedTake(fields: .init(id: "t2", lineID: "l2", part: "role:TOM", frames: 48_000, sampleRate: 48_000, capture: "room", seat: nil, file: "b.wav", member: "bob"), data: Data([1])))
        for dark in [false, true] {
            try png("apple-read-takes", width: 390, height: 720, dark: dark, scale: 2, out: out) {
                ReadTakesContent(room: hostRoom, scrolls: false) { EmptyView() }.environment(app).environment(plays)
            }
        }

        // The Takes sheet with its foot: every speaking line taken, so Listen through and Export show, then Publish under my name.
        let fullSnap = try snap(Self.snapshotJSON(you: "host", mode: "record", cursor: "l6", receives: true, done: ["l1", "l2", "l3", "l4", "l5", "l6"], nurse: false))
        let fullSession = ReadSession(wire: RenderWire())
        fullSession.adopt(ReadJoined(snapshot: fullSnap, key: "k", transport: "poll"))
        let fullRoom = RoomReaderModel(session: fullSession, script: play, store: store, publishing: nil)
        for line in play.lines where line.kind == .speech {
            fullRoom.recorder.accept(PickedTake(fields: .init(id: "f-\(line.id)", lineID: line.id, part: line.part.rawValue, frames: 48_000, sampleRate: 48_000,
                                                              capture: "room", seat: nil, file: "\(line.id).wav", member: "ann"), data: Data([1])))
        }
        let footProduction = try XCTUnwrap(fullRoom.recorder.production)
        XCTAssertTrue(Relay.isComplete(footProduction, play), "every speaking line has a take, so the foot offers Export")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "render-read-\(UUID().uuidString)"))
        let audio = AudioPlayer(history: ListeningHistory(defaults: defaults))
        for dark in [false, true] {
            try png("apple-read-takes-foot", width: 390, height: 900, dark: dark, scale: 2, out: out) {
                ReadTakesContent(room: fullRoom, scrolls: false) {
                    VStack(alignment: .leading, spacing: Spacing.s3) {
                        ListenThrough(production: footProduction, script: play)
                        RoomPublishForm(room: fullRoom, pid: "p1")
                    }
                }
                .environment(app).environment(plays).environment(audio)
            }
        }

        // The class page's review queue: takes recorded at home that reached the teacher's app, each waiting for Approve or Again.
        let reviewScript = play
        let items = [
            ClassReviewItem(pid: "p1", playTitle: "The Lost Lady", take: .init(id: "r1", lineID: "l1", part: "role:LUCY", created: nil, frames: 1, sampleRate: 48_000,
                                                                              capture: nil, heard: nil, loudness: nil, peak: nil, userID: nil, seat: "s1")),
            ClassReviewItem(pid: "p1", playTitle: "The Lost Lady", take: .init(id: "r2", lineID: "l2", part: "role:TOM", created: nil, frames: 1, sampleRate: 48_000,
                                                                              capture: nil, heard: nil, loudness: nil, peak: nil, userID: nil, seat: "s2")),
        ]
        for dark in [false, true] {
            try png("apple-class-review", width: 390, height: 520, dark: dark, scale: 2, out: out) {
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    Text("Review").font(TypeRamp.bodyStrong)
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ClassReviewRow(item: item, seatLabel: index == 0 ? "Ada" : "Ben", partTitle: PartID(rawValue: item.take.part).title,
                                       words: reviewScript.lines.first { $0.id == item.take.lineID }?.spokenText ?? "", canPlay: index == 0)
                        Divider()
                    }
                }
                .padding(Spacing.s4)
            }
        }

        // The TV's pairing screen at 1920 x 1080.
        for dark in [false, true] {
            try png("apple-tv-pair", width: 1920, height: 1080, dark: dark, out: out) {
                ReadPairView(code: "K7Q4MX", status: "")
            }
        }
        // The shared screen, as before.
        for dark in [false, true] {
            try png("apple-read-screen", width: 1280, height: 720, dark: dark, out: out) {
                ReadScreenView(snapshot: hostSnap, status: "", script: play)
            }
        }
        session.pause()
        hostSession.pause()
        waitSession.pause()
        fullSession.pause()
    }
}
