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

private func caster(_ key: String, _ script: PlayScript, _ voices: Voices, _ storage: CastStorage, seed: String? = nil,
                    kokoro: [CastVoice] = [], defaults: VoiceDefaults = .empty) -> VoiceCast {
    VoiceCast(key: key, seed: seed, parts: script.castParts.map(\.id), voices: { voices.now }, downloaded: { kokoro },
              defaults: { defaults }, storage: storage)
}

private let molly = PartID.role("MOLLY"), fibber = PartID.role("FIBBER"), doc = PartID.role("DOC")

struct NoveltyVoiceTests {
    ///   Broken control: castable() trusting the trait alone: the Mac's Bahh and Bells stayed in the list.
    @Test func theKnownNoveltyIdentifiersAreNeverDefaults() {
        for id in ["com.apple.speech.synthesis.voice.Bahh", "com.apple.speech.synthesis.voice.Bells", "com.apple.speech.synthesis.voice.Boing",
                   "com.apple.speech.synthesis.voice.Zarvox", "com.apple.speech.synthesis.voice.BadNews", "com.apple.speech.synthesis.voice.Trinoids"] {
            #expect(DeviceVoices.isNovelty(identifier: id), "\(id)")
        }
        for id in ["com.apple.voice.premium.en-US.Zoe", "com.apple.voice.enhanced.en-GB.Daniel", "com.apple.ttsbundle.siri_Nicky_en-US_compact", ""] {
            #expect(!DeviceVoices.isNovelty(identifier: id), "\(id)")
        }
        #expect(DeviceVoices.castable().allSatisfy { !DeviceVoices.isNovelty(identifier: $0.id) }, "and none is in the device's castable list")
    }
}

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

    @Test func noVoiceYetMeansNothingIsCastStoredOrSpokenThenTheDefaultReadsAndIsNeverKept() throws {
        let script = fixtureScript()
        let storage = CastStorage.memory()
        let voices = Voices([])
        let cast = caster("p:P6", script, voices, storage)
        let r = cast.resolve(molly)
        #expect(r.read == false && r.none, "not read, and says there is no voice")
        #expect(storage.read() == nil, "auto-cast waits for a non-empty list")
        #expect(VoiceChipText.title(r) == "No Voice")
        voices.now = ordered
        #expect(cast.resolve(molly).voice?.name == "Ava (Premium)", "the voices land: the Default reads")
        #expect(storage.read() == nil, "and is never written into the cast (Decision 086)")
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

// MARK: - The device's voice defaults (Decision 086), mirroring js/voice-cast.test.js "The device's voice defaults"
//
// Seen to fail, 2026-11-22 (each against a mutated copy of Core/Plays/VoiceCast.swift):
//   ordered() without the engine rank (Kokoro not first): "Kokoro leads the pool" fails.
//   pool() without the unticked filter: "unticked voices leave the pool" fails.
//   ensure-style write-back in resolve (a Default saved as a choice): "a Default is never written" fails.
//   VoiceCastBook.load ignoring `v`: "an old row reads as no choice" fails.

private nonisolated func kokoroVoice(_ id: String, _ name: String, grade: String, off: Bool = false) -> CastVoice {
    CastVoice(id: id, name: "\(name) (Kokoro)", language: "en-US", tier: 0, gender: nil, engine: .kokoro, grade: grade, offByDefault: off)
}
private nonisolated let heart = kokoroVoice("af_heart", "Heart", grade: "A")
private nonisolated let bella = kokoroVoice("af_bella", "Bella", grade: "A-")
private nonisolated let jessica = kokoroVoice("af_jessica", "Jessica", grade: "D", off: true)
private nonisolated let fakeKokoro = [heart, bella, jessica]

struct VoiceDefaultsTests {
    @Test func kokoroLeadsThePoolThenThePersonsOrderThenBestFirstAndUntickedLeave() {
        let all = fakeKokoro + ordered
        #expect(VoiceCasting.ordered(all, .empty).map(\.name) == ["Heart (Kokoro)", "Bella (Kokoro)", "Jessica (Kokoro)", "Ava (Premium)",
                                                                  "Karen (Enhanced)", "Samantha", "Daniel"], "Kokoro first, each group as given")
        #expect(VoiceCasting.pool(all, .empty).map(\.name).first == "Heart (Kokoro)")
        #expect(!VoiceCasting.pool(all, .empty).contains { $0.id == "af_jessica" }, "a grade under C- starts unticked")
        var d = VoiceDefaults.empty
        d.order = [samantha.key, bella.key]
        #expect(VoiceCasting.ordered(all, d).map(\.id) == ["af_bella", "af_heart", "af_jessica", "com.samantha", "com.ava.premium", "com.karen", "com.daniel"],
                "the person's order inside each engine, the rest after in the incoming order")
        d.off = [heart.key: true, jessica.key: false]
        #expect(VoiceCasting.pool(all, d).prefix(2).map(\.id) == ["af_bella", "af_jessica"], "the person's tick beats the voice's own default")
        var none = VoiceDefaults.empty
        none.off = Dictionary(uniqueKeysWithValues: all.map { ($0.key, true) })
        #expect(VoiceCasting.pool(all, none).count == all.count, "all unticked means all")
    }

    @Test func movingAVoiceSwapsWithinItsEngineOnly() {
        let all = fakeKokoro + ordered
        let d = VoiceCasting.move(all, .empty, samantha, by: -1)
        #expect(VoiceCasting.ordered(all, d).filter { $0.engine == .system }.map(\.name) == ["Ava (Premium)", "Samantha", "Karen (Enhanced)", "Daniel"])
        #expect(VoiceCasting.ordered(all, d).prefix(3).allSatisfy { $0.engine == .kokoro }, "Kokoro stays first")
        #expect(VoiceCasting.move(all, .empty, ava, by: -1) == .empty, "the first cannot move up")
        let dragged = VoiceCasting.reorder(ordered, .empty, from: IndexSet(integer: 3), to: 0)
        #expect(VoiceCasting.ordered(ordered, dragged).first?.name == "Daniel", "a drag to the top")
    }

    @Test func untouchedPartsReadTheDefaultAtTheDefaultSpeedAndADownloadReachesThem() {
        let script = fixtureScript()
        let storage = CastStorage.memory()
        let voices = Voices()
        var d = VoiceDefaults.empty
        d.rate = 1.2
        let before = caster("p:D1", script, voices, storage, defaults: d)
        #expect(before.resolve(molly).voice?.name == "Ava (Premium)" && before.resolve(molly).isDefault)
        #expect(before.resolve(molly).rate == 1.2, "the Default speed")
        before.set(fibber) { $0.voice = daniel.id; $0.name = daniel.displayName }
        let after = caster("p:D1", script, voices, storage, kokoro: fakeKokoro, defaults: d)
        #expect(after.resolve(molly).voice?.name == "Heart (Kokoro)", "a download reaches every untouched part")
        #expect(after.resolve(doc).voice?.name == "Ava (Premium)", "the Default pool runs on into the device's own voices when Kokoro's run out")
        #expect(after.resolve(fibber).voice?.name == "Daniel" && !after.resolve(fibber).isDefault, "a chosen part keeps its voice")
        after.reset(fibber)
        #expect(after.resolve(fibber).isDefault && after.resolve(fibber).voice?.engine == .kokoro, "reset drops the choice")
        after.set(molly) { $0.rate = 0.8 }
        #expect(after.choice(molly)?.voice == heart.id && after.choice(molly)?.rate == 0.8, "set merges into the Default entry")
        after.recast()
        #expect(after.choice(molly) == nil && after.resolve(molly).isDefault, "Recast all returns every part to Default")
    }

    @Test func aDefaultIsNeverWrittenIntoTheCast() {
        let script = fixtureScript()
        let storage = CastStorage.memory()
        let cast = caster("p:D2", script, Voices(), storage, kokoro: fakeKokoro)
        for part in script.castParts.map(\.id) { _ = cast.resolve(part); _ = cast.entry(part) }
        #expect(storage.read() == nil, "reading a cast writes nothing")
        cast.reset(molly)
        #expect(storage.read() == nil, "resetting a Default writes nothing")
    }

    @Test func anOldUnversionedRowIsNoChoice() throws {
        let script = fixtureScript()
        let storage = CastStorage.memory()
        let old: [String: Any] = ["p:D3": ["parts": ["role:MOLLY": ["engine": "system", "voice": daniel.id, "name": "Daniel", "rate": 1, "pitch": 1]], "at": 1.0]]
        storage.write(try JSONSerialization.data(withJSONObject: old))
        let cast = caster("p:D3", script, Voices(), storage)
        #expect(cast.choice(molly) == nil && cast.resolve(molly).voice?.name == "Ava (Premium)", "a row without v is not a choice")
        cast.set(molly) { $0.voice = daniel.id; $0.name = daniel.displayName }
        #expect(caster("p:D3", script, Voices(), storage).choice(molly)?.voice == daniel.id, "a row written now is a choice (v 2)")
    }

    @Test func theFallbackForAKokoroLineIsTheDefaultAmongTheDevicesOwnVoices() {
        let script = fixtureScript()
        let cast = caster("p:D4", script, Voices(), CastStorage.memory(), kokoro: fakeKokoro)
        #expect(cast.resolve(molly).voice?.engine == .kokoro)
        #expect(cast.systemFallback(molly).voice?.name == "Ava (Premium)" && cast.systemFallback(molly).voice?.engine == .system)
    }

    @Test func defaultsPersistNormalizeAndSurviveABrokenRow() throws {
        let suite = UserDefaults(suiteName: "ed.test.voices.\(UUID().uuidString)")!
        #expect(VoiceDefaultsStore.load(suite) == .empty)
        var d = VoiceDefaults.empty
        d.order = ["kokoro:af_heart"]
        d.off = ["system:x": true]
        d.rate = 9
        VoiceDefaultsStore.save(d, suite)
        let back = VoiceDefaultsStore.load(suite)
        #expect(back.order == ["kokoro:af_heart"] && back.off == ["system:x": true] && back.rate == 2, "kept, and the speed clamped")
        suite.set(Data("not json".utf8), forKey: VoiceDefaultsStore.key)
        #expect(VoiceDefaultsStore.load(suite) == .empty, "a broken row reads as the defaults")
        #expect(VoiceDefaults.normalize(["order": [1, "a"], "off": ["k": "no"], "rate": "fast"]) == VoiceDefaults(order: ["a"], off: [:], rate: 1))
    }

    @Test func kokoroGradesUnderCMinusStartUnticked() {
        let off = Kokoro.castable(ready: true).filter(\.offByDefault).map(\.name)
        #expect(Set(off) == Set(["Jessica", "River", "Echo", "Eric", "Liam", "Onyx", "Santa", "Adam", "Alice", "Lily", "Daniel", "Lewis"].map { "\($0) (Kokoro)" }))
        #expect(Kokoro.castable(ready: true).first?.id == "af_heart", "best grade first")
        #expect(Kokoro.castable(ready: false).isEmpty)
    }

    @Test func settingsStatesAndTheBetterVoicesOffer() {
        #expect(KokoroDownloadState.of(.absent, supported: false) == .unsupported, "unsupported beats every state")
        #expect(KokoroDownloadState.of(.absent, supported: true) == .absent)
        #expect(KokoroDownloadState.of(.downloading(done: 1, total: 2), supported: true) == .downloading)
        #expect(KokoroDownloadState.of(.ready, supported: true) == .ready)
        #expect(KokoroDownloadState.offersBetterVoices(ready: false, flag: true) && !KokoroDownloadState.offersBetterVoices(ready: true, flag: true)
                && !KokoroDownloadState.offersBetterVoices(ready: false, flag: false),
                "offered only while Kokoro could run and is not here")
    }
}

// Register hints from the catalog (catalog DECISIONS 049): the golden every stack runs
// (catalog/tests/golden/voice_register_cast.json), the roles' `register` decoded, and a person's choice winning.
// Seen to fail, 2026-11-26, against mutated copies of VoiceCast.swift: autoCast ignoring `registers` (four cases),
// the bias orders swapped (the web case), the no-kind fallback skipped (a woman's part on a man's voice), a matched
// reuse pitched in the old order (two parts at 0.86); and PlayScript.registers returning nothing (the decode test).
struct VoiceRegisterCastTests {
    private static let golden: [String: Any] = {
        var dir = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<8 {
            let f = dir.appendingPathComponent("catalog/tests/golden/voice_register_cast.json")
            if let data = try? Data(contentsOf: f), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return json }
            dir = dir.deletingLastPathComponent()
        }
        return [:]
    }()

    /// What is wrong with one case, one line a part; empty when the cast is the case's.
    private func run(_ c: [String: Any]) -> [String] {
        let voices = (c["voices"] as? [[String: Any]] ?? []).map { v in
            var cv = CastVoice(id: v["id"] as? String ?? "", name: v["id"] as? String ?? "", language: "en-US", tier: 0,
                               gender: (v["gender"] as? String).flatMap(VoiceGender.init(rawValue:)),
                               engine: VoiceEngine(rawValue: v["engine"] as? String ?? "system") ?? .system)
            cv.register = v["register"] as? String
            return cv
        }
        let parts = (c["parts"] as? [[String: Any]] ?? []).map { PartID(rawValue: $0["id"] as? String ?? "") }
        var registers: [PartID: String] = [:]
        for p in c["parts"] as? [[String: Any]] ?? [] {
            if let r = p["register"] as? String { registers[PartID(rawValue: p["id"] as? String ?? "")] = r }
        }
        let got = VoiceCasting.autoCast(parts, voices, registers: registers)
        var bad: [String] = []
        for (part, want) in c["cast"] as? [String: [Any]] ?? [:] {
            let e = got[PartID(rawValue: part)]
            let voice = want.first as? String
            let pitch = (want.last as? NSNumber)?.doubleValue ?? .nan
            if e?.voice != voice || abs((e?.pitch ?? .nan) - pitch) > 1e-9 {
                bad.append("\(part): want \(voice ?? "-") \(pitch), got \(e?.voice ?? "-") \(e?.pitch ?? .nan)")
            }
        }
        return bad.sorted()
    }

    @Test func theGoldenOfEveryStackAndItsControl() {
        let cases = Self.golden["cases"] as? [[String: Any]] ?? []
        #expect(cases.count >= 5, "the golden file is found")
        for c in cases { #expect(run(c) == [], "\(c["name"] ?? "")") }
        #expect(!run(Self.golden["control"] as? [String: Any] ?? [:]).isEmpty, "the control is wrong on purpose and is found wrong")
    }

    @Test func aScriptsRolesCarryTheirPublishedRegisterOnlyHighOrLow() throws {
        let json = """
        {"id":"gut-1","revision":"r","kind":"stage","title":"T","authors":[],"source":{"name":"s","url":"u"},
         "rights":{"bucket":"b","evidence":[]},"lines":[],
         "roles":[{"name":"NORA","lines":3,"words":9,"register":"high"},{"name":"HELMER","lines":2,"words":5,"register":"low"},
                  {"name":"ALL","lines":1,"words":1},{"name":"ODD","lines":1,"words":1,"register":"loud"}]}
        """
        let script = try JSONDecoder().decode(PlayScript.self, from: Data(json.utf8))
        #expect(script.registers == [.role("NORA"): "high", .role("HELMER"): "low"], "high and low only; none for ALL or a bad value")
        let old = try JSONDecoder().decode(PlayScript.self, from: Data(json.replacingOccurrences(of: #","register":"high""#, with: "").utf8))
        #expect(old.registers[.role("NORA")] == nil, "a script from before the field decodes, with no register")
    }

    @Test func aRegisterReachesTheDefaultAndAPersonsChoiceWins() {
        let michael = CastVoice(id: "am_michael", name: "Michael (Kokoro)", language: "en-US", tier: 0, gender: .male, engine: .kokoro)
        let heart = CastVoice(id: "af_heart", name: "Heart (Kokoro)", language: "en-US", tier: 0, gender: .female, engine: .kokoro)
        let storage = CastStorage.memory()
        let parts: [PartID] = [.role("MOLLY"), .role("FIBBER")]
        let cast = VoiceCast(key: "p:REG", parts: parts, registers: [.role("MOLLY"): "high", .role("FIBBER"): "low"],
                             voices: { [michael, heart] }, defaults: { .empty }, storage: storage)
        #expect(cast.entry(.role("MOLLY"))?.voice == "af_heart" && cast.entry(.role("FIBBER"))?.voice == "am_michael",
                "the woman's part on the woman's voice, though it is listed second")
        #expect(VoiceCastBook.load("p:REG", storage) == nil, "the Default is never written")
        cast.set(.role("MOLLY")) { $0 = VoiceCastEntry(engine: .kokoro, voice: "am_michael", name: "Michael (Kokoro)") }
        #expect(cast.entry(.role("MOLLY"))?.voice == "am_michael", "the person's choice for the part wins over its register")
        let plain = VoiceCast(key: "p:REG2", parts: parts, voices: { [michael, heart] }, defaults: { .empty }, storage: storage)
        #expect(plain.entry(.role("MOLLY"))?.voice == "am_michael", "without a register the largest part takes the best voice, as before")
    }
}
