import AVFoundation
import Foundation
import Testing

// Casting the device voices (PLAYS-DESIGN §2.8, Decision 076 S2), mirroring js/voice-cast.test.js case by
// case: fake voices, an in-memory store, a speaker that speaks nothing.
//
// Seen to fail, 2026-11-14 (each against a mutated copy of Core/Plays/VoiceCast.swift):
//   autoCast giving the best voice to the LAST speaking part: "the largest part gets the best voice" fails.
//   autoCast keyed on the part's name: "renaming every part changes nothing" fails.
//   autoCast without the gender step: "alternates the voices' own reported gender" fails.
//   resolve() returning the stored voice without checking the device has it: the fallback test fails.
//   SpeechSetting ignoring the part's rate and pitch: the per-part speed test fails.
// The one-cast test carries its own control: the old assignment (a part takes the next voice the first time
// it speaks, one map per player) still makes two players disagree.

private nonisolated func voice(_ id: String, _ name: String, lang: String = "en-US", tier: Int = 0, gender: VoiceGender? = nil) -> CastVoice {
    CastVoice(id: id, name: name, language: lang, tier: tier, gender: gender)
}

/// The web test's RAW list after its filters (local, English): Ava (Premium), Karen (Enhanced), Samantha, Daniel.
private nonisolated let ava = voice("com.ava.premium", "Ava (Premium)", tier: 2)
private nonisolated let karen = voice("com.karen", "Karen (Enhanced)", lang: "en-AU", tier: 1)
private nonisolated let samantha = voice("com.samantha", "Samantha")
private nonisolated let daniel = voice("com.daniel", "Daniel", lang: "en-GB")
private nonisolated let ordered = [ava, karen, samantha, daniel]

/// The device's voices, changeable between calls, like the Settings pane adding one.
private nonisolated final class Voices: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [CastVoice]
    init(_ list: [CastVoice] = ordered) { self.list = list }
    var now: [CastVoice] {
        get { lock.lock(); defer { lock.unlock() }; return list }
        set { lock.lock(); list = newValue; lock.unlock() }
    }
}

private func line(_ id: String, _ role: String?, _ kind: ScriptLine.Kind, _ text: String) -> ScriptLine {
    kind == .speech
        ? ScriptLine(id: id, kind: .speech, role: role, parts: [.say(text)])
        : ScriptLine(id: id, kind: kind, source: text)
}

private func fixtureScript(_ names: [String] = ["MOLLY", "FIBBER", "DOC"]) -> PlayScript {
    let (m, f, d) = (names[0], names[1], names[2])
    let lines = [
        line("L0001", nil, .direction, "(A _kitchen_.)"),
        line("L0002", f, .speech, "Well, Molly."),
        line("L0003", m, .speech, "Yes, dearie?"),
        line("L0004", nil, .sound, "SOUND: DOOR OPENS"),
        line("L0005", d, .speech, "Anybody home?"),
        line("L0006", m, .speech, "Come in."),
        line("L0007", m, .speech, "Sit down."),
        line("L0008", f, .speech, "Doc!"),
        line("L0009", m, .speech, "Tea?"),
        line("L0010", f, .speech, "Not for me."),
        line("L0011", m, .speech, "Good night."),
    ]
    return PlayScript(id: "gut-0", revision: "r1", kind: "radio", title: "Good Grammar", authors: [],
                      source: .init(name: "Fixture", url: "https://example.org"),
                      rights: .init(bucket: "script_source_cleared", evidence: []),
                      roles: names.map { n in .init(name: n, lines: lines.filter { $0.role == n }.count, words: 2) }, lines: lines)
}

private func caster(_ key: String, _ script: PlayScript, _ voices: Voices, _ storage: CastStorage, seed: String? = nil) -> VoiceCast {
    VoiceCast(key: key, seed: seed, parts: script.castParts.map(\.id), voices: { voices.now }, storage: storage)
}

private let molly = PartID.role("MOLLY"), fibber = PartID.role("FIBBER"), doc = PartID.role("DOC")

struct VoiceCastTests {
    // MARK: The voice list

    @Test func theCastableVoicesAreBestFirstPremiumEnhancedOwnLanguageName() {
        let shuffled = [daniel, samantha, karen, ava]
        let sorted = VoiceCasting.sorted(shuffled, language: "en-US")
        #expect(sorted.map(\.name) == ["Ava (Premium)", "Karen (Enhanced)", "Samantha", "Daniel"], "tier, then en-US, then name")
        #expect(sorted.map(\.id) == ["com.ava.premium", "com.karen", "com.samantha", "com.daniel"], "each by its identifier, never a language")
        #expect(VoiceCasting.sorted([daniel, samantha], language: "en-GB").map(\.name) == ["Daniel", "Samantha"], "the person's own language leads within a tier")
        #expect(voice("x", "Zoe", tier: 2).displayName == "Zoe (Premium)")
        #expect(ava.displayName == "Ava (Premium)", "a name that already says its quality says it once")
    }

    // MARK: Auto-cast

    @Test func autoCastIsDeterministicDistinctAndGivesTheLargestPartTheBestVoice() {
        let script = fixtureScript()
        let parts = script.castParts.map(\.id)
        #expect(parts == [molly, fibber, doc, .sound, .directions], "cast order, largest first")
        let a = VoiceCasting.autoCast(parts, ordered)
        #expect(a == VoiceCasting.autoCast(parts, Array(ordered)), "the same voice list gives the same cast")
        #expect(a[molly]?.voice == ava.id, "the largest part gets the best voice")
        #expect([molly, fibber, doc].map { a[$0]?.voice } == ordered.prefix(3).map(\.id), "distinct voices, best first")
        #expect(a[.sound]?.engine == VoiceEngine.none && a[.directions]?.engine == VoiceEngine.none, "sound and directions are Not read")
    }

    @Test func autoCastNeverReadsAPartsNameRenamingEveryPartChangesNothing() throws {
        let plain = VoiceCasting.autoCast(fixtureScript().castParts.map(\.id), ordered)
        let renamed = fixtureScript(["LADY MACBETH", "MRS. GIBBS", "FATHER BROWN"])
        let named = VoiceCasting.autoCast(renamed.castParts.map(\.id), ordered)
        // Compare by place in the cast, not by name.
        let byPlace = { (script: PlayScript, cast: [PartID: VoiceCastEntry]) in script.castParts.map { cast[$0.id].map { [$0.voice ?? "-", "\($0.pitch)"] } ?? [] } }
        #expect(byPlace(fixtureScript(), plain) == byPlace(renamed, named), "the same voices by place in the cast, whatever the names say")

        let source = try String(contentsOfFile: Self.core("VoiceCast.swift"), encoding: .utf8)
        let start = try #require(source.range(of: "static func autoCast"))
        let end = try #require(source.range(of: "private static func clamp"))
        let body = String(source[start.lowerBound..<end.lowerBound])
        #expect(body.range(of: #"\.(title|roleName|rawValue|name|lines|source)\b"#, options: .regularExpression) == nil,
                "autoCast reads no title, role, name or line")
    }

    @Test func autoCastAlternatesTheVoicesOwnReportedGender() {
        let voices = [voice("a", "A", gender: .female), voice("b", "B", gender: .female), voice("c", "C", gender: .male),
                      voice("d", "D"), voice("e", "E", gender: .male)]
        let parts = (1...4).map { PartID.role("P\($0)") }
        let cast = VoiceCasting.autoCast(parts, voices)
        #expect(parts.map { cast[$0]?.voice } == ["a", "c", "b", "e"], "best first, each next of the other reported gender")
        let none = VoiceCasting.autoCast(parts, [voice("a", "A"), voice("b", "B"), voice("c", "C"), voice("d", "D")])
        #expect(parts.map { none[$0]?.voice } == ["a", "b", "c", "d"], "no genders reported: plain order")
    }

    @Test func fewerVoicesThanPartsStartTheListAgainAtTheNextPitch() {
        let cast = VoiceCasting.autoCast(fixtureScript().castParts.map(\.id), Array(ordered.prefix(2)))
        #expect([molly, fibber, doc].map { [cast[$0]?.voice, cast[$0].map { "\($0.pitch)" }] } ==
                [[ava.id, "1.0"], [karen.id, "1.0"], [ava.id, "0.86"]], "the third part repeats the best voice, pitched")
    }

    // MARK: One cast everywhere

    /// The old assignment: each player gave a part the next voice the first time it spoke.
    private func loose(_ voices: [CastVoice], speaking order: [PartID]) -> [PartID: String] {
        var assigned: [PartID: Int] = [:]
        for p in order where assigned[p] == nil { assigned[p] = assigned.count }
        return assigned.mapValues { voices[$0 % voices.count].id }
    }

    @Test func theRecorderAndTheListenThroughReadEachPartInTheSameVoice() {
        let script = fixtureScript()
        let storage = CastStorage.memory()
        let voices = Voices()
        // Recording FIBBER: the recorder cues MOLLY then DOC. The listen-through starts with FIBBER.
        let recorder = caster("p:P1", script, voices, storage)
        let listen = caster("p:P1", script, voices, storage)
        func setting(_ cast: VoiceCast, _ part: PartID) -> SpeechSetting? { SpeechSetting.of(cast.resolve(part)) }
        #expect(setting(recorder, molly) == setting(listen, molly), "MOLLY: one voice in both")
        #expect(setting(recorder, doc) == setting(listen, doc), "DOC: one voice in both")
        #expect(setting(listen, molly)?.voiceID == ava.id, "the auto-cast voice: the largest part, the best voice")

        // Control: without one cast each player assigns by who spoke first, and they disagree.
        let recorderLoose = loose(ordered, speaking: [molly, doc])
        let listenLoose = loose(ordered, speaking: [fibber, molly, doc])
        #expect(recorderLoose[molly] != listenLoose[molly], "control: the same part changes voice")
    }

    @Test func aChoiceIsReadByAnotherPlayerBuiltLaterRateTimesTheSessionRatePitchAndRecastRestoresAuto() throws {
        let script = fixtureScript()
        let storage = CastStorage.memory()
        let voices = Voices()
        caster("p:P2", script, voices, storage).set(molly) {
            $0 = VoiceCastEntry(engine: .system, voice: daniel.id, name: daniel.displayName, rate: 1.3, pitch: 0.8)
        }
        let r = caster("p:P2", script, voices, storage).resolve(molly)
        #expect(r.voice?.name == "Daniel" && r.rate == 1.3 && r.pitch == 0.8 && r.missing == nil, "another player reads the choice")
        let s = try #require(SpeechSetting.of(r, sessionRate: 1.5))
        #expect(s.voiceID == daniel.id && s.pitch == 0.8)
        #expect(abs(s.rate - min(AVSpeechUtteranceMaximumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * 1.95)) < 0.0001, "its speed times the session's")
        caster("p:P2", script, voices, storage).recast()
        #expect(caster("p:P2", script, voices, storage).resolve(molly).voice?.name == "Ava (Premium)", "Recast All puts auto-cast back")
    }

    @Test func directionsAreNotReadUntilGivenAVoiceThenTheListenThroughReadsThem() async {
        let script = fixtureScript()
        let cast = caster("p:P3", script, Voices(), CastStorage.memory())
        #expect(cast.resolve(.directions).read == false, "directions: Not read by default")
        let p = Production(script: script)
        let reads: (PartID) -> Bool = { !$0.isSpeaking && cast.resolve($0).read }
        func spoken() async -> [String] {
            let speaker = FakeSpeaker(cast)
            await LiveListenThrough(speaker: speaker, player: FakeTakes()).run(Relay.listenPlan(p, script, reads: reads)) { _ in URL(filePath: "/") }
            return speaker.spoken
        }
        #expect(await spoken().contains { $0.contains("kitchen") } == false, "no direction read")
        cast.set(.directions) { $0 = VoiceCastEntry(engine: .system, voice: karen.id, name: karen.displayName) }
        let after = await spoken()
        #expect(after.contains("(A _kitchen_.)"), "the direction is read once it has a voice")
        #expect(DeviceVoices.said("(A _kitchen_.)") == "(A kitchen.)", "the italic marks are never spoken")
        #expect(!after.contains { $0.contains("DOOR") }, "sound stays Not read")
        #expect(Relay.listenPlan(p, script).count == 9, "without the predicate the plan is unchanged: speech only")
    }

    // MARK: A voice that vanishes

    @Test func aMissingVoiceFallsBackToTheAutoCastVoiceVisiblyAndTheChoiceIsKept() {
        let script = fixtureScript()
        let storage = CastStorage.memory()
        let voices = Voices()
        let cast = caster("p:P4", script, voices, storage)
        cast.set(fibber) { $0 = VoiceCastEntry(engine: .system, voice: "com.zoe", name: "Zoe (Premium)") }
        let r = cast.resolve(fibber)
        #expect(r.read && r.missing == "Zoe (Premium)" && r.voice?.name == "Karen (Enhanced)", "read by its auto-cast voice, Zoe named as missing")
        #expect(VoiceChipText.accessibility(r, part: fibber) == "Zoe (Premium) is not on this device; Karen (Enhanced) reads instead")
        #expect(cast.entry(fibber)?.voice == "com.zoe", "the choice is kept")
        voices.now = VoiceCasting.sorted(ordered + [voice("com.zoe", "Zoe (Premium)", tier: 2)], language: "en-US")
        #expect(cast.resolve(fibber).voice?.name == "Zoe (Premium)" && cast.resolve(fibber).missing == nil, "and returns when the voice does")
        let k = caster("p:P5", script, voices, storage)
        k.set(doc) { $0 = VoiceCastEntry(engine: .kokoro, voice: "af_heart", name: "Heart") }
        #expect(k.resolve(doc).missing == "Heart", "a Kokoro voice (none until S6) falls back the same way")
    }

    @Test func noVoiceYetMeansNothingIsCastStoredOrSpokenThenAutoCastRunsAndIsKept() throws {
        let script = fixtureScript()
        let storage = CastStorage.memory()
        let voices = Voices([])
        let cast = caster("p:P6", script, voices, storage)
        let r = cast.resolve(molly)
        #expect(r.read == false && r.none, "not read, and says there is no voice")
        #expect(storage.read() == nil, "auto-cast waits for a non-empty list")
        #expect(VoiceChipText.title(r) == "No Voice")
        voices.now = ordered
        #expect(cast.resolve(molly).voice?.name == "Ava (Premium)", "the voices land: auto-cast runs")
        #expect(storage.read() != nil, "and is kept")
    }

    // MARK: Keeping it

    @Test func aProductionStartsFromItsPlaysCastKeysAreBoundedAndSyncNeverCarriesIt() throws {
        let script = fixtureScript()
        let storage = CastStorage.memory()
        let voices = Voices()
        let play = caster(VoiceCastBook.scriptKey("gut-0"), script, voices, storage)
        play.set(doc) { $0 = VoiceCastEntry(engine: .system, voice: daniel.id, name: daniel.displayName) }
        let prod = caster(VoiceCastBook.productionKey("P7"), script, voices, storage, seed: VoiceCastBook.scriptKey("gut-0"))
        #expect(prod.resolve(doc).voice?.name == "Daniel", "the production starts from the play's cast")
        prod.set(doc) { $0.voice = samantha.id; $0.name = samantha.displayName }
        #expect(play.resolve(doc).voice?.name == "Daniel", "and changing it leaves the play's alone")
        for i in 0..<100 { VoiceCastBook.save("p:x\(i)", [:], storage) }
        let data = try #require(storage.read())
        let book = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(book.count <= VoiceCastBook.keep, "the newest 80 casts are kept")
        VoiceCastBook.forget("p:P7", storage)
        #expect(VoiceCastBook.load("p:P7", storage) == nil, "a deleted production forgets its cast")

        let dir = Self.core("../Core/Account")
        for file in try FileManager.default.contentsOfDirectory(atPath: dir).sorted() where file.hasSuffix(".swift") {
            let text = try String(contentsOfFile: dir + "/" + file, encoding: .utf8)
            #expect(!text.contains("ed.cast") && !text.contains("VoiceCast"), "\(file): sync never carries the cast (Q8)")
        }
    }

    @Test func storedEntriesAreNormalizedOnRead() {
        #expect(VoiceCasting.normalize(["engine": "robot", "voice": "x"] as [String: Any]) == nil, "an unknown engine is no entry")
        #expect(VoiceCasting.normalize(["engine": "system"] as [String: Any]) == nil, "a system entry without a voice is no entry")
        let e = VoiceCasting.normalize(["engine": "system", "voice": "v", "rate": 9.0, "pitch": 0.123] as [String: Any])
        #expect(e?.rate == 2 && e?.pitch == 0.5, "rate and pitch are clamped")
        #expect(VoiceCasting.normalize(["engine": "system", "voice": "v", "rate": 1.2345] as [String: Any])?.rate == 1.23, "and rounded to 0.01")
    }

    // MARK: The words on the chip

    @Test func theChipSaysWhatTheVoiceIsAndHowItIsTuned() {
        let script = fixtureScript()
        let cast = caster("p:P9", script, Voices(), CastStorage.memory())
        #expect(VoiceChipText.title(cast.resolve(molly)) == "Ava (Premium)")
        #expect(VoiceChipText.title(cast.resolve(.directions)) == "Not read")
        #expect(VoiceChipText.tuning(cast.resolve(molly)) == nil, "the voice's own speed and pitch say nothing")
        cast.set(molly) { $0.rate = 1.2; $0.pitch = 0.9 }
        #expect(VoiceChipText.tuning(cast.resolve(molly)) == "1.2\u{00D7}, pitch \u{2212}1")
        #expect([VoiceChipText.pitch(0), VoiceChipText.pitch(1), VoiceChipText.pitch(-1)] == ["0", "+1", "\u{2212}1"])
        #expect(VoiceChipText.rate(1) == "1.0\u{00D7}")
        #expect(VoiceChipText.accessibility(cast.resolve(molly), part: molly) == "Voice for MOLLY: Ava (Premium)")
    }

    // MARK: Hear the cast

    @Test func theTableReadReadsFromALineToTheEndEachPartInItsVoiceFollowingEachLine() async {
        let script = fixtureScript()
        let cast = caster("s:gut-0", script, Voices(), CastStorage.memory())
        let speaker = FakeSpeaker(cast)
        var followed: [String] = []
        let read = TableRead(script: script, speaker: speaker) { id in if let id { followed.append(id) } }
        await read.play(from: 4)
        #expect(followed == ["L0005", "L0006", "L0007", "L0008", "L0009", "L0010", "L0011"], "from line five on")
        #expect(speaker.parts.first == doc, "DOC in its own voice")
        #expect(!read.isPlaying && read.line == nil, "done")

        cast.set(.sound) { $0 = VoiceCastEntry(engine: .system, voice: karen.id, name: karen.displayName) }
        followed = []
        await read.play(from: 3)
        #expect(followed.first == "L0004", "a part given a voice is read, sound included")
    }

    @Test func stoppingTheTableReadEndsIt() async {
        let script = fixtureScript()
        let speaker = FakeSpeaker(caster("s:gut-0", script, Voices(), CastStorage.memory()))
        let read = TableRead(script: script, speaker: speaker)
        speaker.onSpeak = { read.stop() }
        await read.play()
        #expect(speaker.spoken.count == 1 && !read.isPlaying, "Close stops it")
    }

    private static func core(_ file: String) -> String {
        let here = URL(filePath: #filePath).deletingLastPathComponent()
        return here.deletingLastPathComponent().appending(path: file.hasPrefix("../") ? String(file.dropFirst(3)) : "Core/Plays/" + file).path
    }
}

private final class FakeSpeaker: ListenSpeaker {
    private(set) var spoken: [String] = []
    private(set) var parts: [PartID] = []
    var onSpeak: (() -> Void)?
    private let cast: VoiceCast
    init(_ cast: VoiceCast) { self.cast = cast }
    func reads(_ part: PartID) -> Bool { cast.resolve(part).read }
    func speak(_ text: String, part: PartID, personalVoice: Bool) async {
        guard cast.resolve(part).read else { return }
        spoken.append(text)
        parts.append(part)
        onSpeak?()
    }
    func stop() {}
}

private final class FakeTakes: ListenTakePlayer {
    func play(_ url: URL) async {}
    func stop() {}
}
