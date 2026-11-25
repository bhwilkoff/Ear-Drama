#if os(macOS)
import Foundation
import Testing

// Casting an episode by ear (PLAYS-DESIGN §13 item 10, iOS-DESIGN §4.22): the port of js/ear.test.js over EarSession,
// EarCore and EarCues, and EarModel over a stand-in player. No network, no sound.
//
// Seen to fail, 2026-11-24: every mutation in tools/apple_own_mutants.py (the web's own mutants and the model's).

private let vtt = """
WEBVTT

00:00.000 --> 00:04.000
The Planet Man! This is the story of Dantro.

00:04.000 --> 00:06.000
I'm sorry, Pat.

00:06.000 --> 00:08.000
There, they're sending us a message.

00:08.000 --> 00:10.000
You are on the province of Mars.

00:12.500 --> 00:14.000
Cut your drive.

00:14.000 --> 00:16.000
Or we'll ray you out of space.
"""

private func fresh() -> OwnDoc { OwnScript.fromCues(OwnScript.parseCues(vtt)) }
private func sit() -> EarSession { EarSession(doc: fresh()) }
private func cast(_ s: EarSession) -> [String?] {
    s.cast.map { who in
        switch who {
        case let .role(name): name
        case .out: "out"
        case nil: nil
        }
    }
}
/// The audio playing from `a` to `b` milliseconds, a frame every 16 ms.
private func play(_ s: inout EarSession, _ a: Int64, _ b: Int64) {
    var t = a
    while t <= b {
        _ = s.tick(t, playing: true)
        t += 16
    }
}

@Suite struct EarSessionTests {
    @Test func theLineLitIsTheLastBegunAndAPauseKeepsIt() {
        var s = sit()
        let got = [0, 1453, 1454, 3999, 4000, 8000, 11000, 12499, 12500, 99999].map { ms -> Int in _ = s.tick(Int64(ms), playing: false); return s.lit }
        #expect(got == [1, 1, 2, 2, 3, 5, 5, 5, 6, 7])
        var t = EarSession(doc: OwnScript.fromCues(OwnScript.parseCues(vtt.replacingOccurrences(of: "00:00.000 -->", with: "00:01.000 -->"))))
        _ = t.tick(500, playing: true)
        #expect(t.lit == 0 && t.doc.heard.isEmpty)
        #expect(t.give("A") == .no_such_line && t.leaveOut() == .no_such_line)
        #expect(!s.tick(99999, playing: false).moved && s.tick(0, playing: false).moved)
    }

    @Test func aTapCarriesUntilTheNextAndOnlyOverWhatWasHeard() {
        var s = sit()
        play(&s, 0, 1000)
        #expect(s.give("announcer") == nil)
        play(&s, 1000, 5000)
        #expect(Array(cast(s).prefix(4)) == ["ANNOUNCER", "ANNOUNCER", "ANNOUNCER", nil])
        #expect(s.give("Dantro") == nil)
        play(&s, 5000, 9000)
        #expect(cast(s) == ["ANNOUNCER", "ANNOUNCER", "DANTRO", "DANTRO", "DANTRO", nil, nil])
        #expect(s.count == (5, 7))
        #expect(s.leaveOut() == nil)
        play(&s, 9000, 13000)
        #expect(cast(s) == ["ANNOUNCER", "ANNOUNCER", "DANTRO", "DANTRO", "out", "out", nil])
        #expect(EarCore.rows(s.doc).map(\.named) == [true, false, true, false, true, false, false])
    }

    @Test func aSeekHearsNothingBetweenAndCarriesNothingOverTheGap() {
        var s = sit()
        play(&s, 0, 500)
        _ = s.give("A")
        s.jumped()
        _ = s.tick(8100, playing: true)
        #expect(cast(s) == ["A", nil, nil, nil, nil, nil, nil])
        play(&s, 8100, 13000)
        #expect(cast(s) == ["A", nil, nil, nil, nil, nil, nil])
        _ = s.give("B")
        play(&s, 13000, 14100)
        #expect(cast(s) == ["A", nil, nil, nil, nil, "B", "B"])
        var t = sit()
        _ = t.tick(100, playing: true)
        _ = t.give("A")
        _ = t.tick(5000, playing: true)
        #expect(Array(cast(t).prefix(4)) == ["A", "A", "A", nil], "a slow frame hears the lines it passed")
    }

    @Test func aPlaceMovedWhilePausedIsSeenNeverHeard() {
        var s = sit()
        play(&s, 0, 500)
        _ = s.give("A")
        for t in stride(from: Int64(500), to: 9000, by: 16) { _ = s.tick(t, playing: false) }
        #expect(cast(s) == ["A", nil, nil, nil, nil, nil, nil] && s.doc.heard.count == 1)
    }

    @Test func aLineHeardBeforeIsPutRightByGoingBack() {
        var s = sit()
        play(&s, 0, 9000)
        s.jumped(); _ = s.tick(100, playing: true); _ = s.give("A")
        #expect(cast(s) == ["A", "A", "A", "A", "A", nil, nil])
        s.jumped(); _ = s.tick(4100, playing: true); _ = s.give("B")
        #expect(cast(s) == ["A", "A", "B", "B", "B", nil, nil])
        s.jumped(); _ = s.tick(6100, playing: true); _ = s.give("B")
        s.jumped(); _ = s.tick(4100, playing: true); _ = s.give("A")
        #expect(cast(s) == ["A", "A", "A", "B", "B", nil, nil], "and a mark after it stands")
        var t = sit()
        _ = t.tick(100, playing: true); _ = t.give("A")
        play(&t, 100, 9000)
        t.jumped(); _ = t.tick(4100, playing: true); _ = t.leaveOut()
        #expect(cast(t) == ["A", "A", "out", "out", "out", nil, nil])
    }

    @Test func undoTakesBackTheTapsAndNeverWhatWasHeard() {
        var s = sit()
        #expect(!s.canUndo && s.undo() == .nothing_to_undo)
        play(&s, 0, 500)
        _ = s.give("A")
        play(&s, 500, 4500)
        _ = s.give("B")
        #expect(Array(cast(s).prefix(3)) == ["A", "A", "B"])
        _ = s.undo()
        #expect(Array(cast(s).prefix(3)) == ["A", "A", "A"], "the carry goes on over it")
        _ = s.undo()
        #expect(Array(cast(s).prefix(3)) == [nil, nil, nil] && !s.canUndo && s.doc.heard.count == 3)
        _ = s.tick(0, playing: false)
        _ = s.give("A"); _ = s.assign(2, .kind("direction")); _ = s.apply(OwnOp(op: .split, line: 3, at: 4))
        #expect(s.doc.lines.count == 8)
        _ = s.undo(); _ = s.undo(); _ = s.undo()
        #expect(s.doc.lines.count == 7 && !s.canUndo)
    }

    @Test func partsKeepTheOrderTheyWereNamedInAndHearPlaysTheNextOfTheirLines() {
        var s = sit()
        let added = s.add(" dantro: ")
        #expect(added.name == "DANTRO" && added.refusal == nil)
        #expect(cast(s)[0] == nil && s.parts == [OwnPart(name: "DANTRO", lines: 0)], "with no line lit it is only named")
        _ = s.tick(8100, playing: false)
        #expect(s.add("Pat").refusal == nil && cast(s)[4] == "PAT", "with a line lit it is theirs")
        #expect(s.add("").refusal == .empty && s.add(String(repeating: "x", count: 41)).refusal == .too_long)
        #expect(s.parts.map(\.name) == ["DANTRO", "PAT"])
        _ = s.add("Dantro")
        #expect(s.parts.map(\.name) == ["DANTRO", "PAT"])
        _ = s.give("PAT"); _ = s.undo()
        #expect(s.parts.map(\.name) == ["DANTRO", "PAT"])
        var t = sit()
        _ = t.tick(8100, playing: false)
        _ = t.add("A"); _ = t.undo()
        #expect(t.parts == [OwnPart(name: "A", lines: 0)] && t.give("A") == nil)
        play(&t, 8100, 13000)
        let heard = (0..<3).map { _ in t.sample("A")?.k }
        #expect(heard == [5, 6, 5] && t.sample("B") == nil)
        #expect(EarCore.span(OwnSpan(start: 1000, end: 1100)) == (1000, 1700))
        #expect(EarCore.span(OwnSpan(start: 1000, end: 4000)) == (1000, 4000))
    }

    @Test func aRecordedLineIsNeverMoved() {
        var s = sit()
        play(&s, 0, 500)
        _ = s.give("A")
        play(&s, 500, 5000)
        s = EarSession(doc: OwnScript.done(s.doc, keepOpen: true), takes: ["L0003"])
        _ = s.tick(100, playing: false)
        #expect(s.give("B") == .line_has_take, "a tap that would move a recorded line is refused")
        _ = s.tick(4100, playing: false)
        #expect(s.give("B") == .line_has_take && s.leaveOut() == .line_has_take && s.assign(3, .kind("direction")) == .line_has_take)
        #expect(Array(cast(s).prefix(3)) == ["A", "A", "A"])
        var t = EarSession(doc: OwnScript.done(fresh(), keepOpen: true), takes: ["L0003"])
        _ = t.tick(1400, playing: true)
        _ = t.give("A")
        play(&t, 1500, 4600)
        #expect(cast(t)[1] == "A" && cast(t)[2] == nil, "a carried part never reaches a recorded line of nobody's")
    }

    @Test func keys() {
        func k(_ c: Character, command: Bool = false, control: Bool = false, option: Bool = false, shift: Bool = false) -> EarCore.Key? {
            EarCore.key(.character(c), command: command, control: control, option: option, shift: shift)
        }
        #expect(k("1") == .part(0) && k("9") == .part(8))
        #expect(k(" ") == .toggle && EarCore.key(.left) == .back && k("u") == .undo && k("U") == .undo)
        #expect(k("z", command: true) == .undo && k("z", control: true) == .undo)
        #expect([k("0"), k("1", command: true), k("1", option: true), k(" ", control: true), k("z"), k("Z", command: true, shift: true), k("\u{0664}")].allSatisfy { $0 == nil })
        #expect(EarCore.key(.left, command: true) == nil)
    }

    @Test func aKeptCastingIsTakenUpWhereItWasLeft() throws {
        var s = sit()
        play(&s, 0, 500)
        _ = s.give("A")
        play(&s, 500, 4500)
        let kept = try JSONDecoder().decode(OwnDoc.self, from: JSONEncoder().encode(OwnScript.kept(s.doc)))
        var t = EarSession(doc: kept, names: ["A", "B"])
        #expect(cast(t) == cast(s) && t.parts.map(\.name) == ["A", "B"] && !t.canUndo)
        _ = t.tick(4500, playing: true)
        #expect(cast(t)[2] == "A")
        play(&t, 4500, 6500)
        #expect(cast(t)[3] == "A", "the carry goes on")
        func place(_ p: Int64) -> Int64 { EarCore.place(OwnRecord.Ear(sig: "", copy: "", place: p), kept) }
        #expect([place(4500), place(0), place(16000), place(9_000_000_000), EarCore.place(nil, kept)] == [4500, 0, 0, 0, 0])
        let cues = OwnScript.parseCues(vtt)
        #expect(EarCore.signature(cues) == EarCore.signature(OwnScript.parseCues(vtt)))
        #expect(EarCore.signature(cues) != EarCore.signature(OwnScript.parseCues(vtt.replacingOccurrences(of: "sorry", with: "sure"))))
        #expect(EarCore.signature(cues) != EarCore.signature(OwnScript.parseCues(vtt.replacingOccurrences(of: "00:12.500", with: "00:12.400"))))
        #expect(EarCore.refusal(fresh()) == nil && EarCore.refusal(OwnScript.newDoc([])) == .no_lines)
        #expect(EarCore.refusal(OwnScript.newDoc(Array(repeating: OwnLine(kind: "open", text: "x"), count: OwnScript.maxLines + 1))) == .too_many_lines)
    }
}

// MARK: - The times

@Suite struct EarCuesTests {
    private static let txt = URL(string: "https://archive.org/download/OTRR_Suspense_Singles/Suspense%20430223%20%2864-48%29.autogenerated.txt")!

    @Test func theTimesStandBesideATranscriptWeShowAndNothingElseHasAny() {
        #expect(EarCues.url(Self.txt)?.absoluteString == "https://archive.org/download/OTRR_Suspense_Singles/Suspense%20430223%20%2864-48%29.autogenerated.vtt")
        for bad in [nil, "https://archive.org/download/x/y.txt", "https://example.com/download/x/y.autogenerated.txt", "https://archive.org/download/y.autogenerated.txt",
                    "http://archive.org/download/x/y.autogenerated.txt"] {
            #expect(EarCues.url(bad.flatMap(URL.init)) == nil)
        }
    }

    private actor Served {
        var asked = 0
        var answer: (String, Int)?
        func set(_ a: (String, Int)?) { answer = a }
        func get() throws -> (String, Int) {
            asked += 1
            guard let answer else { throw URLError(.notConnectedToInternet) }
            return answer
        }
    }

    @Test func noTimesNoDoorAndAFailureIsAskedForAgain() async throws {
        let served = Served()
        let cache = EarCueCache { _ in try await served.get() }
        func why() async -> EarCues.Failure? {
            do { _ = try await cache.cues(Self.txt); return nil } catch { return error as? EarCues.Failure }
        }
        for (answer, want) in [(("", 404), EarCues.Failure.missing), (("", 403), .missing), (("<html>busy</html>", 200), .missing),
                               (("words with no times", 200), .missing), (("", 503), .failed)] {
            await served.set(answer)
            #expect(await why() == want)
        }
        await served.set(nil)
        #expect(await why() == .failed)
        await served.set((vtt, 200))
        #expect(try await cache.cues(Self.txt).count == 6)
        let asked = await served.asked
        await served.set(("", 404))
        #expect(try await cache.cues(Self.txt).count == 6)
        #expect(await served.asked == asked, "and read once")
        await #expect(throws: EarCues.Failure.missing) { _ = try await cache.cues(URL(string: "https://example.com/a.autogenerated.txt")) }
        #expect(await served.asked == asked, "nothing else is asked for")
    }
}

// MARK: - The page's model, over a stand-in player

@MainActor
private final class FakeAudio: EarAudio {
    var on: (episode: String, copy: URL)?
    var isPlaying = false
    var isFollowing = false
    var settledSeconds: Double?
    var jumps = 0
    var speed: Float = 1
    var errorMessage: String?
    var own: Float?
    var log: [String] = []
    var hasItem: Bool { on != nil }

    func isOn(episode: String, copy: URL) -> Bool { on?.episode == episode && on?.copy == copy }
    func hold(speed x: Float) { if own == nil { own = speed }; speed = x; log.append("hold \(x)") }
    func release() { if let own { speed = own }; own = nil; log.append("release") }
    func start(_ detail: EpisodeDetail, copy: Recording, at seconds: Double) {
        on = (detail.episode.id, copy.url)
        isPlaying = true
        jumps += 1
        settledSeconds = nil
        log.append("start \(seconds)")
    }
    func resume() { isPlaying = true; log.append("resume") }
    func pause() { isPlaying = false; log.append("pause") }
    /// A seek that has not landed leaves no place to read.
    var lands = true
    func seek(to seconds: Double) { settledSeconds = lands ? seconds : nil; jumps += 1; log.append("seek \(seconds)") }
}

@MainActor @Suite struct EarModelTests {
    private struct Room {
        let root: URL
        let store: OwnScripts
        let plays: ProductionStore
        let audio = FakeAudio()
        let defaults: UserDefaults
        let detail: EpisodeDetail
        let cues = OwnScript.parseCues(vtt)

        init() {
            root = FileManager.default.temporaryDirectory.appending(path: "EarModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            plays = ProductionStore(root: root.appending(path: "Plays", directoryHint: .isDirectory))
            store = OwnScripts(root: root.appending(path: "Scripts", directoryHint: .isDirectory), plays: plays)
            let suite = "EarModelTests-\(UUID().uuidString)"
            defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            let copy = Recording(rank: 0, archiveID: "x", url: URL(string: "https://archive.org/download/x/y.mp3")!, format: nil, kbps: nil, lengthSeconds: 600, variant: nil, partial: false)
            let other = Recording(rank: 1, archiveID: "z", url: URL(string: "https://archive.org/download/z/y.mp3")!, format: nil, kbps: nil, lengthSeconds: 600, variant: nil, partial: false)
            let episode = EpisodeRow(id: "planetman|n53", seriesKey: "planetman", seriesName: "Planet Man", airDate: nil, season: nil, number: nil,
                                     title: "Secret Council", lengthSeconds: 600, rights: "unclaimed", rightsBasis: nil, network: nil)
            detail = EpisodeDetail(episode: episode, sponsor: nil, credits: [], recordings: [copy, other], rightsLine: nil)
        }

        func model(_ rec: OwnRecord? = nil) -> EarModel {
            EarModel(detail: detail, copy: detail.recordings[0], title: "Secret Council", rec: rec, cues: cues, doc: OwnScript.fromCues(cues),
                     store: store, audio: audio, defaults: defaults)
        }

        /// The audio playing from `a` to `b`, the page reading it.
        func play(_ m: EarModel, _ a: Int64, _ b: Int64) {
            var t = a
            while t <= b {
                audio.settledSeconds = Double(t) / 1000
                m.sync()
                if !audio.isPlaying { return }
                t += 16
            }
        }

        func clean() { try? FileManager.default.removeItem(at: root) }
    }

    private func start(_ r: Room, _ m: EarModel) {
        m.appear()
        m.toggle()
        r.audio.settledSeconds = 0
        m.sync()
    }

    @Test func lookingKeepsNothingAndNothingPlaysBeforeAPress() async throws {
        let r = Room(); defer { r.clean() }
        r.audio.on = ("other|1", URL(string: "https://archive.org/o.mp3")!)
        r.audio.isPlaying = true
        let m = r.model()
        m.appear()
        #expect(r.audio.log == ["pause"], "another episode is paused; nothing is started")
        m.sync()
        m.leave()
        #expect(r.store.rows.isEmpty && !FileManager.default.fileExists(atPath: r.store.root.path), "nothing is kept by looking")
        #expect(!r.audio.log.contains("release"), "and a player never held is not let go")
    }

    @Test func thePlayerIsHeldAtThePagesSpeedAndLetGo() {
        let r = Room(); defer { r.clean() }
        r.audio.speed = 1.25
        let m = r.model()
        start(r, m)
        #expect(r.audio.speed == EarCore.speed && m.speed == EarCore.speed && r.audio.log.contains("start 0.0"))
        m.setSpeed(1)
        #expect(r.audio.speed == 1)
        #expect(r.model().speed == 1, "the last chosen here is the next page's")
        r.audio.speed = 1.5
        m.sync()
        #expect(m.speed == 1.5, "a speed set on the lock screen is the page's")
        m.leave()
        #expect(r.audio.speed == 1.25, "and never the person's own")
        #expect(r.audio.isPlaying, "what is playing plays on")
    }

    @Test func aTapIsCastKeptAndCarried() async throws {
        let r = Room(); defer { r.clean() }
        let m = r.model()
        start(r, m)
        r.play(m, 16, 500)
        #expect(m.lit == 1)
        #expect(m.add("Announcer") == nil)
        r.play(m, 516, 4600)
        #expect(m.count == (3, 7) && m.parts == [OwnPart(name: "ANNOUNCER", lines: 3)] && m.who == .role("ANNOUNCER"))
        #expect(m.hue("ANNOUNCER") == PlayScript.partHues[0])
        #expect(await m.write())
        let row = try #require(r.store.rows.first)
        #expect(row.episode == r.detail.episode.id && row.ear == .init(cast: 3, lines: 7) && !row.done)
        #expect(row.facts == "3 of 7 lines cast")
        let rec = try #require(try r.store.get(row.id))
        #expect(rec.ear?.copy == "https://archive.org/download/x/y.mp3" && rec.ear?.sig == EarCore.signature(r.cues))
        #expect(rec.episode?.url == "https://eardrama.org/episode/planetman%7Cn53")
        #expect(r.store.row(ofEpisode: "planetman|n53")?.id == rec.id && r.store.row(ofEpisode: "other") == nil)
        var moved = IDForwarding()
        moved.aliases["planetman|n53"] = "planetman|1952-03-01"
        #expect(r.store.row(ofEpisode: "planetman|1952-03-01", forwarding: moved)?.id == rec.id, "by the id it has now")
    }

    @Test func aSeekByAnyoneHandsNothingToAnyone() {
        let r = Room(); defer { r.clean() }
        let m = r.model()
        start(r, m)
        r.play(m, 16, 500)
        _ = m.add("A")
        // The lock screen's skip: the player moves, the page only sees it.
        r.audio.seek(to: 8.1)
        m.sync()
        #expect(cast(m.session) == ["A", nil, nil, nil, nil, nil, nil])
        r.audio.lands = false
        let heard = m.session.doc.heard
        m.back()
        m.sync()
        #expect(m.session.doc.heard == heard && m.lit == 5, "a seek in flight has no place: nothing is heard until it lands")
        r.audio.settledSeconds = 3.1
        m.sync()
        #expect(m.lit == 2 && m.session.doc.heard == heard + [2])
    }

    @Test func aCopyJustLoadedIsMovedToThePlaceItWasLeft() async throws {
        let r = Room(); defer { r.clean() }
        var m = r.model()
        start(r, m)
        r.play(m, 16, 6500)
        _ = m.add("A")
        #expect(await m.write())
        m.leave()
        let rec = try #require(try r.store.get(r.store.rows[0].id))
        r.audio.on = nil
        r.audio.isPlaying = false
        m = r.model(rec)
        m.appear()
        #expect(m.lit == 4, "the place it was left is lit before anything plays")
        m.toggle()
        let left = Double(try #require(rec.ear).place) / 1000
        #expect(r.audio.log.contains("start \(left)"))
        r.audio.settledSeconds = 0
        m.sync()
        #expect(r.audio.log.last == "seek \(left)", "a copy that reads 0 is moved")
        #expect(m.session.doc.heard == rec.doc.heard, "and nothing between was heard")
        #expect(m.parts.map(\.name) == ["A"])
    }

    @Test func hearItPlaysTheLineAndGoesBackToThePlace() {
        let r = Room(); defer { r.clean() }
        let m = r.model()
        start(r, m)
        r.play(m, 16, 8100)
        _ = m.add("A")
        m.openSheet()
        #expect(!r.audio.isPlaying, "the episode waits while a sheet is open")
        m.hear(m.session.line(1))
        #expect(m.lit == 1 && r.audio.isPlaying && m.session.lit == 5)
        let heard = m.session.doc.heard
        r.play(m, 0, 1600)
        #expect(!r.audio.isPlaying && m.lit == 5 && r.audio.settledSeconds == 8.096, "then back to its place")
        #expect(m.session.doc.heard == heard, "a line played on its own is no hearing")
        m.closeSheet()
        #expect(r.audio.isPlaying, "and it goes on when the sheet closes")
    }

    @Test func playFromHereStartsAtTheLine() {
        let r = Room(); defer { r.clean() }
        let m = r.model()
        start(r, m)
        r.play(m, 16, 500)
        m.away()
        m.openSheet()
        m.play(from: m.session.line(5)!)
        #expect(r.audio.settledSeconds == 8 && r.audio.isPlaying && !m.sheetOpen && !m.backToLine)
        #expect(m.session.lit == 5)
    }

    @Test func aScrollStopsTheFollowingAndBackToTheLineStartsIt() {
        let r = Room(); defer { r.clean() }
        let m = r.model()
        start(r, m)
        r.play(m, 16, 4100)
        let n = m.bring
        #expect(n?.k == 3 && !m.backToLine)
        m.away()
        r.play(m, 4116, 8100)
        #expect(m.backToLine && m.bring == n, "nothing is brought into view")
        m.refollow()
        #expect(!m.backToLine && m.bring?.k == 5)
    }

    @Test func doneAtAnyTimeIsAScriptAndCastingGoesOnFromIt() async throws {
        let r = Room(); defer { r.clean() }
        let m = r.model()
        start(r, m)
        #expect(await m.finish() == nil && m.refusal == "No line has a part." && r.store.rows.isEmpty, "nothing cast is no script")
        r.play(m, 16, 500)
        _ = m.add("Announcer")
        r.play(m, 516, 4500)
        _ = m.add("Dantro")
        r.play(m, 4516, 6500)
        let id = try #require(await m.finish())
        m.leave()
        let s = try #require(r.store.script(id))
        #expect(s.lines.map { $0.role ?? $0.kind.rawValue } == ["ANNOUNCER", "ANNOUNCER", "DANTRO", "DANTRO", "direction", "direction", "direction"])
        #expect(s.source.name == "Automatic transcript" && s.source.url == "https://eardrama.org/episode/planetman%7Cn53" && s.episode == "planetman|n53")
        let raw = String(decoding: try Data(contentsOf: r.store.folder(id).appending(path: "script.json")), as: UTF8.self)
        #expect(!raw.contains("\"at\"") && !raw.contains("archive.org/download"), "no time and no sound is in the script")
        #expect(r.store.row(id)?.halfCast == true)
        // Taken up again: the same ids, more of it cast.
        let rec = try #require(try r.store.get(id))
        let again = r.model(rec)
        again.appear()
        again.toggle()
        r.audio.settledSeconds = 8.1
        again.sync()
        r.audio.settledSeconds = 8.1
        again.play(from: again.session.line(5)!)
        r.play(again, 8016, 8200)
        _ = again.add("Patrol")
        r.play(again, 8216, 14100)
        #expect(await again.write())
        let more = try #require(r.store.script(id))
        #expect(more.lines.map(\.id) == s.lines.map(\.id))
        #expect(more.lines.map(\.role) == ["ANNOUNCER", "ANNOUNCER", "DANTRO", "DANTRO", "PATROL", "PATROL", "PATROL"])
        #expect(r.store.row(id)?.halfCast == false)
        // The parts page makes the marks the lines' own.
        let parts = OwnPartsModel(try #require(try r.store.get(id)), store: r.store)
        #expect(parts.lines.allSatisfy { $0.mark == nil && $0.kind == "speech" })
    }

    @Test func aTakeOnALineIsSeenByTheNextTap() async throws {
        let r = Room(); defer { r.clean() }
        let m = r.model()
        start(r, m)
        r.play(m, 16, 500)
        _ = m.add("A")
        let id = try #require(await m.finish())
        let s = try #require(r.store.script(id))
        var p = try r.plays.create(s)
        p.add(Take(id: "t", lineID: s.lines[0].id, part: .role("A"), file: "f", created: .now, frames: 1, sampleRate: 48_000, capture: .direct, heard: [:],
                   loudness: nil, peak: 0, bleed: false))
        try r.plays.save(p)
        m.leaveOut()
        #expect(m.refusal == "This line has a take." && m.who == .role("A"))
        #expect(m.add("B") == "This line has a take.")
    }

    @Test func aListenTogetherGuestAndARecordingThatFailsAreSaid() {
        let r = Room(); defer { r.clean() }
        r.audio.isFollowing = true
        let m = r.model()
        m.appear()
        m.toggle()
        #expect(m.problem?.words == "Leave SharePlay to play this." && !r.audio.log.contains("start 0.0"))
        r.audio.isFollowing = false
        m.toggle()
        r.audio.errorMessage = "x"
        m.sync()
        #expect(m.problem?.words == "This recording did not load." && m.problem?.audio == true)
        r.audio.errorMessage = nil
        m.sync()
        #expect(m.problem == nil)
    }
}
#endif
