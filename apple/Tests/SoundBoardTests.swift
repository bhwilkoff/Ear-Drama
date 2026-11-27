import Foundation
import Testing

// The Sound part and the board on Apple (B32 §2-§5; iOS-DESIGN §4.15 "The sound board"), the mirror of js/sound.test.js
// case for case where the case is Core: Sound on every cast sheet, Stage directions that never block, the slots and the
// edits a board makes, a performed cue kept as a take that is never a line's chosen one, the pack manifest's rights gate
// (the web's fixture with its planted rows, which must be refused), own sounds left out of a published block, the live
// listen's cue schedule and Hear It in Place, own sounds on this device only and carried whole by Export my data.
// Nothing is heard and nothing reaches the network.
//
// Broken controls, 2026-11-26, each against a mutated copy of Core/Plays and seen to fail:
//   castParts without the `counts[.sound] = cueRows.count` line: the parts test fails (no Sound on a quiet script).
//   cueRows ignoring the reader's words rule (direction pieces never cues): the parts and slots tests fail.
//   Production.takes(for:) keeping performed cues: the performed-cue test fails (the take list shows it).
//   defaultPlacement always "after": the placement test fails (the bed and the Under share).
//   updateSound not clamping startMs to -2 s: the settings test fails.
//   setSilent ignoring "never silent while it holds a sound": the settings test fails.
//   prune keeping empty added slots: the slots test fails.
//   readManifest accepting any license: the manifest test fails (the planted CC-BY row is listed).
//   readManifest not checking refused hosts: the manifest test fails (the freesound row is listed).
//   withoutOwn keeping own sounds: the publish test fails.
//   listenCues placing a bed's stop at its own entry: the live-listen test fails.
//   OwnShare.sameParts comparing Sound's count: the own-share door test fails.

// MARK: - Fixtures

private func say(_ id: String, _ role: String, _ parts: LinePart...) -> ScriptLine {
    ScriptLine(id: id, kind: .speech, role: role, parts: parts)
}

private func script(_ id: String, _ lines: [ScriptLine]) -> PlayScript {
    let names = Array(Set(lines.compactMap(\.role))).sorted()
    return PlayScript(id: id, revision: "r1", kind: "radio", title: id, authors: [], source: .init(name: "Fixture", url: "https://example.org"),
                      rights: .init(bucket: "script_source_cleared", evidence: []),
                      roles: names.map { PlayScript.Role(name: $0, lines: 1, words: 1) }, lines: lines)
}

/// Caesar Rodney's shape: cues inside speeches, no sound line; one direction.
private func radioScript() -> PlayScript {
    script("fixture-radio", [
        say("L0001", "URIAH", .say("We got to make it, rain or no rain.")),
        say("L0002", "RODNEY", .say("It's sprinkling.")),
        say("L0003", "URIAH", .say("I felt it."), .sound("another peal of thunder closer")),
        say("L0004", "RODNEY", .direction("Sound of rain and wind"), .say("I guess it is on us.")),
        say("L0005", "URIAH", .say("Here, draw up your horse!"), .direction("absently"), .say("Whoa, boy!")),
        ScriptLine(id: "L0006", kind: .direction, source: "They ride off."),
        say("L0007", "RODNEY", .say("Giddap!")),
    ])
}

/// No cue rows at all, and no directions.
private func quietScript() -> PlayScript {
    script("fixture-quiet", [say("L0001", "A", .say("Hello.")), say("L0002", "B", .say("Hello yourself."))])
}

private func take(_ id: String, _ line: String, seconds: Double = 1, part: PartID = .role("X")) -> Take {
    Take(id: id, lineID: line, part: part, file: "\(id).flac", created: .now, frames: Int(seconds * 48_000), sampleRate: 48_000,
         capture: .direct, heard: [:], loudness: nil, peak: 0.5, bleed: false)
}

private let pack = SoundSource.pack(pack: "eardrama-sounds-1", cue: "thunder-close")

private var fixtureManifest: Data {
    var dir = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent()
    for _ in 0..<8 {
        let url = dir.appendingPathComponent("tools/fixtures/sounds/sounds.json")
        if let data = try? Data(contentsOf: url) { return data }
        dir = dir.deletingLastPathComponent()
    }
    return Data()
}

// MARK: - Parts

@Suite struct SoundPartTests {
    @Test func everyScriptHasSoundCountedByCueRowsThenDirections() {
        #expect(radioScript().castParts.map { [$0.id.rawValue, "\($0.lineCount)", $0.title] }
            == [["role:URIAH", "3", "URIAH"], ["role:RODNEY", "3", "RODNEY"], ["sound", "2", "Sound"], ["directions", "1", "Stage directions"]])
        #expect(quietScript().castParts.map(\.id) == [.role("A"), .role("B"), .sound], "a play with no cue rows still has Sound")
        #expect(radioScript().cueRows.map { "\($0.line):\($0.piece ?? -1)" } == ["L0003:1", "L0004:0"],
                "the reader's cue rows: a sound piece and an aside beginning \"sound of\"")
        #expect(PlayPage.isCueWords("Music, soft") && !PlayPage.isCueWords("absently"), "one rule for the reader and the slots")
        #expect(Production(script: quietScript()).parts.keys.contains(.sound), "a new production holds the Sound part")
        #expect(SoundBoard.partLine(quietScript(), Production(script: quietScript()), taken: false) == "Add sounds")
        #expect(SoundBoard.partLine(radioScript(), Production(script: radioScript()), taken: false) == "2 cues · none chosen")
        #expect(quietScript().castParts.last?.lengthText == "Add sounds" && radioScript().castParts[2].lengthText == "2 cues")
    }

    @Test func stageDirectionsReadByAPersonNeverBlock() throws {
        let s = radioScript()
        var p = try Relay.take(.directions, performer: nil, in: Production(script: s), script: s)
        #expect(SoundBoard.directionsLine(s, p) == "0 of 1 recorded · the rest silent")
        p.add(take("d1", "L0006", part: .directions))
        #expect(SoundBoard.directionsLine(s, p) == "1 of 1 recorded")
        #expect(Relay.missingSpeech(p, s).count == 6, "only speaking lines decide completeness")
        #expect(try Relay.finish(.directions, in: p, script: s).state(of: .directions).status == .done, "Done at any count")
    }

    /// The Worker's cast lists Sound only where the script prints a sound line; the own-share door still fits the script.
    @Test func theOwnShareDoorHoldsSoundByPresenceOnly() {
        let s = quietScript()
        let worker = [(id: "role:A", lines: Int?(1)), (id: "role:B", lines: Int?(1))]
        #expect(OwnShare.sameParts(s, worker), "a script with no sound line fits the Worker's cast without Sound")
        let radio = radioScript()
        let withSound = [(id: "role:URIAH", lines: Int?(3)), (id: "role:RODNEY", lines: Int?(3)), (id: "sound", lines: Int?(0)),
                         (id: "directions", lines: Int?(1))]
        #expect(OwnShare.sameParts(radio, withSound), "Sound held by its presence, never its count")
    }
}

// MARK: - Slots and the board's edits

@Suite struct SoundSlotTests {
    @Test func slotsAreCueRowsPlusAddedLinesNeverFilled() {
        let s = radioScript()
        var p = Production(script: s)
        #expect(SoundBoard.slots(s, p).map { "\($0.line):\($0.piece ?? -1):\($0.added):\($0.sounds.count)" }
            == ["L0003:1:false:0", "L0004:0:false:0"])
        #expect(p.sound == nil, "opening the board writes nothing")
        let r = SoundBoard.addSlot(p, line: "L0001")
        p = r.production
        #expect(SoundBoard.slots(s, p).map(\.line) == ["L0001", "L0003", "L0004"], "Add a sound here on line 1 sorts first")
        #expect(SoundBoard.addSlot(p, line: "L0001").id == r.id, "adding again finds the same slot")
        #expect(SoundBoard.prune(p).sound == nil, "an added slot left empty is removed")
        #expect(SoundBoard.prune(p, keep: r.id).sound?.slots.count == 1, "but not while it is the current slot")
    }

    @Test func aSoundTakesThePlacementTheCueImplies() {
        let s = radioScript()
        var p = Production(script: s)
        p.add(take("t3", "L0003", seconds: 2))
        p.listenedThrough = true
        var e = SoundBoard.ensure(p, SoundBoard.slots(s, p)[0])
        p = e.production
        p = SoundBoard.addSound(p, s, slotID: e.id, src: pack, kind: "effect", take: p.usableTake(for: "L0003")).production
        let x = p.sound!.slots[0].sounds[0]
        #expect(x.at == "after" && x.startMs == 0 && x.gainDb == 0 && x.duckDb == nil, "a cue after every said word: After")
        e = SoundBoard.ensure(p, SoundBoard.slots(s, p)[1])
        p = e.production
        p = SoundBoard.addSound(p, s, slotID: e.id, src: .pack(pack: "x", cue: "rain"), kind: "ambience").production
        let b = p.sound!.slots[1].sounds[0]
        #expect(b.at == "bed" && b.until == "L0004" && b.fadeInMs == 1500 && b.fadeOutMs == 2000 && b.loop, "a loop before the words: a Bed")
        let mid = script("m", [say("m", "U", .say("one two three"), .sound("bang"), .say("four"))])
        let d = SoundBoard.defaultPlacement(mid, line: "m", piece: 1, added: false)
        #expect(d.at == "under" && d.share == 0.75, "inside the words: Under at the share said before it")
        #expect(!p.listenedThrough, "a change unfinishes the play")
        // An Under start is the share of the anchor take's length, to 0.1 s.
        var q = Production(script: mid)
        q.add(take("tm", "m", seconds: 2))
        let em = SoundBoard.ensure(q, SoundBoard.slots(mid, q)[0])
        q = SoundBoard.addSound(em.production, mid, slotID: em.id, src: pack, take: q.usableTake(for: "m")).production
        #expect(q.sound!.slots[0].sounds[0].startMs == 1500)
    }

    @Test func theBoardsSettingsAreHeldToWhatItOffers() {
        let s = radioScript()
        var p = Production(script: s)
        let e = SoundBoard.ensure(p, SoundBoard.slots(s, p)[0])
        p = e.production
        let a = SoundBoard.addSound(p, s, slotID: e.id, src: .own("o1", name: "Knock"))
        p = a.production
        let id = a.id!
        p = SoundBoard.updateSound(p, slotID: e.id, soundID: id, .init(startMs: -5000, gainDb: 40, fadeInMs: 300, duckDb: .some(0)))
        var x = p.sound!.slots[0].sounds[0]
        #expect(x.startMs == -2000 && x.gainDb == 6 && x.fadeInMs == 200 && x.duckDb == 0, "Start to -2 s, +6 dB, a fade to its step, Off kept")
        p = SoundBoard.updateSound(p, slotID: e.id, soundID: id, .init(startMs: -150))
        #expect(p.sound!.slots[0].sounds[0].startMs == -100, "halves round as the web rounds them")
        p = SoundBoard.updateSound(p, slotID: e.id, soundID: id, .init(at: "bed"))
        x = p.sound!.slots[0].sounds[0]
        #expect(x.at == "bed" && x.until == "L0003" && x.loop, "Bed takes an Until")
        p = SoundBoard.updateSound(p, slotID: e.id, soundID: id, .init(until: "L0007"))
        #expect(p.sound!.slots[0].sounds[0].until == "L0007")
        p = SoundBoard.updateSound(p, slotID: e.id, soundID: id, .init(at: "before"))
        x = p.sound!.slots[0].sounds[0]
        #expect(x.at == "before" && x.until == nil && !x.loop && x.fadeInMs == 0, "leaving Bed drops its Until and fades")
        p = SoundBoard.setSilent(p, e.id, true)
        #expect(!p.sound!.slots[0].silent, "a slot holding a sound is never silent")
        p = SoundBoard.removeSound(p, slotID: e.id, soundID: id)
        p = SoundBoard.setSilent(p, e.id, true)
        #expect(p.sound!.slots[0].silent, "Leave silent on an empty slot")
        #expect(SoundBoard.summary(s, p).silent == 1)
        #expect(!SoundMix.hasSound(p.sound), "a silent slot places nothing in the mix")
    }

    @Test func aPerformedCueIsATakeOnItsSlotNeverALinesChosenTake() throws {
        let s = radioScript()
        var p = Production(script: s)
        p.add(take("t3", "L0003", seconds: 0.5))
        let e = SoundBoard.ensure(p, SoundBoard.slots(s, p)[0])
        p = SoundBoard.addPerformed(e.production, s, slotID: e.id, take: take("k1", "L0003", seconds: 0.3))
        #expect(p.chosen["L0003"] == "t3", "the actor's chosen take is unchanged")
        #expect(p.takes(for: "L0003").map(\.id) == ["t3"], "the line's take list does not show the performed cue")
        let kept = try #require(p.take("k1"))
        #expect(kept.part == .sound && kept.cue == e.id, "the take is the Sound part's, on its slot")
        #expect(p.sound?.slots[0].sounds[0].src == .take("k1"), "the slot plays it")
        var q = p
        #expect(q.deleteTake("k1").isEmpty && q.unusedTakes.isEmpty, "a performed cue in use is never deleted or unused")
        for l in s.lines where l.kind == .speech && l.id != "L0003" { q.add(take("t-\(l.id)", l.id, seconds: 0.5)) }
        let tl = try MixTimeline.build(script: s, production: q)
        #expect(tl.sounds.map(\.src) == [.take("k1")] && tl.sounds.map(\.at) == ["after"], "the timeline places it")
        // The record round-trips the take's cue field, and an old take without it reads as before.
        let data = try JSONEncoder().encode(q)
        #expect(try JSONDecoder().decode(Production.self, from: data).take("k1")?.cue == e.id)
    }
}

// MARK: - The pack

@Suite struct SoundPackTests {
    @Test func theManifestKeepsOnlyRowsWithALicenseEvidenceAndADate() throws {
        let m = try SoundBoard.readManifest(fixtureManifest)
        #expect(m.cues.map(\.id) == ["thunder-close", "thunder-distant", "rain-steady", "knock-wood", "door-creak", "calm-prelude"])
        #expect(m.refused.map { "\($0.id ?? ""):\($0.why)" }
            == ["planted-cc-by:license CC-BY-4.0", "planted-no-evidence:no evidence", "planted-refused-host:refused host freesound.org"],
                "the planted CC-BY, no-evidence and refused-host rows are refused")
        var raw = try #require(try JSONSerialization.jsonObject(with: fixtureManifest) as? [String: Any])
        var cues = raw["cues"] as! [[String: Any]]
        var lic = cues[0]["license"] as! [String: Any]
        lic["checked"] = nil
        cues[0]["license"] = lic
        raw["cues"] = cues
        let noDate = try SoundBoard.readManifest(JSONSerialization.data(withJSONObject: raw))
        #expect(noDate.refused.map(\.why) == ["no checked date", "license CC-BY-4.0", "no evidence", "refused host freesound.org"])
        raw["format"] = 2
        #expect(throws: SoundBoard.ManifestError.self) { try SoundBoard.readManifest(JSONSerialization.data(withJSONObject: raw)) }
        #expect(SoundBoard.cueLine(m.cues[0]) == "0:01 · Fixture · CC0")
        #expect(SoundBoard.seedQuery("ANOTHER PEAL OF THUNDER CLOSER", cues: m.cues) == "thunder")
        #expect(SoundBoard.seedQuery("Knocks at the door", cues: m.cues) == "knock", "a plural finds its tag")
        #expect(SoundBoard.seedQuery("All bow low", cues: m.cues) == "", "no tag: empty, never a guess")
        #expect(SoundBoard.search(m.cues, "thunder").map(\.id) == ["thunder-close", "thunder-distant"])
        #expect(SoundBoard.search(m.cues, "storm", category: "weather").count == 3)
    }

    @Test @MainActor func noPackConfiguredIsAbsentAndFetchesNothing() async {
        #expect(SoundPackStore.manifestURL == nil, "the pack's hosting waits on the owner (B32 question 2)")
        let store = SoundPackStore(manifestURL: nil, root: FileManager.default.temporaryDirectory)
        await store.load()
        #expect(store.state == .absent && store.cues.isEmpty)
    }
}

// MARK: - Own sounds: this device only

@Suite struct OwnSoundTests {
    @Test func ownSoundsNeverReachAPublishedBlock() {
        let s = radioScript()
        var p = Production(script: s)
        let e = SoundBoard.ensure(p, SoundBoard.slots(s, p)[0])
        p = SoundBoard.addSound(e.production, s, slotID: e.id, src: .own("o1", name: "Owl")).production
        p = SoundBoard.addSound(p, s, slotID: e.id, src: pack).production
        #expect(SoundBoard.withoutOwn(p.sound)?.slots[0].sounds.map(\.src) == [pack], "the publishable block leaves own sounds out")
        #expect(SoundBoard.sources(p).own == ["o1"], "and the warning knows there is one")
        #expect(SoundBoard.missingLine(["Owl at night", "Gate creak"]) == "2 sounds are on another device: Owl at night, Gate creak.")
        // The own sound's name travels in the block so another device can name what it lacks.
        let data = try? JSONEncoder().encode(p.sound)
        #expect(data.flatMap { try? JSONDecoder().decode(SoundBlock.self, from: $0) }?.slots[0].sounds[0].src == .own("o1", name: "Owl"))
    }

    @Test @MainActor func ownSoundsAreKeptListedRemovedAndExportedWhole() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "own-sounds-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OwnSoundStore(root: root)
        #expect(store.sounds.isEmpty)
        let samples = (0..<4_800).map { Float(sin(Double($0) / 5) * 0.3) }
        let row = try store.save(samples, name: "Owl at night", from: "recorded")
        #expect(OwnSoundStore(root: root).sounds.map(\.name) == ["Owl at night"], "listed, and read back from disk")
        let back = try #require(store.samples(row.id))
        #expect(abs(back[100] - samples[100]) < 1e-3, "read back as kept")
        let rows = store.exportRows()
        #expect(rows.map(\.name) == ["Owl at night"] && rows[0].from == "recorded" && abs(rows[0].seconds - 0.1) < 1e-9)
        let wav = try #require(Data(base64Encoded: rows[0].wav))
        #expect(String(decoding: wav.prefix(4), as: UTF8.self) == "RIFF" && wav.count == 44 + 4_800 * 2, "the sound itself, 16-bit")
        let export = DataExport(exportedAt: .now, history: [], following: [], queue: [], takes: [], ownSounds: rows)
        let json = try #require(try JSONSerialization.jsonObject(with: export.json()) as? [String: Any])
        #expect((json["ownSounds"] as? [[String: Any]])?.first?["id"] as? String == row.id, "the export file has ownSounds[]")
        store.delete(row.id)
        #expect(store.sounds.isEmpty && (try? FileManager.default.contentsOfDirectory(atPath: root.path))?.filter { $0.hasSuffix(".flac") }.isEmpty == true)
    }

    /// Own sounds never reach a share, an upload, a sync or the Worker: the clients that send never read them.
    @Test func noSendingClientReadsOwnSounds() throws {
        var dir = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: dir.appendingPathComponent("apple/Core").path) { dir = dir.deletingLastPathComponent() }
        for f in ["Plays/PlaysShare.swift", "Plays/SharedPlays.swift", "Plays/PlaysWorker.swift", "Plays/OwnShare.swift", "Networking/APIClient.swift"] {
            let src = try String(contentsOf: dir.appendingPathComponent("apple/Core/\(f)"), encoding: .utf8)
            #expect(!src.contains("OwnSoundStore") && !src.contains("ownSounds") && !src.contains("Sounds/mine"), "\(f) never reads own sounds")
        }
        let ui = try String(contentsOf: dir.appendingPathComponent("apple/Shared/SharedPlaysViews.swift"), encoding: .utf8)
        #expect(ui.contains("Your own sounds stay on this device. The published play leaves them out."), "Publish says so before the consent")
    }
}

// MARK: - The live listen

@Suite struct SoundListenTests {
    @Test func cuesPlayAtTheirLinesAndABedStopsAtItsUntil() {
        let s = radioScript()
        var p = Production(script: s)
        for l in s.lines where l.kind == .speech { p.add(take("t-\(l.id)", l.id, seconds: 0.5)) }
        let e3 = SoundBoard.ensure(p, SoundBoard.slots(s, p)[0])
        p = SoundBoard.addSound(e3.production, s, slotID: e3.id, src: .pack(pack: "x", cue: "thunder")).production
        let e4 = SoundBoard.ensure(p, SoundBoard.slots(s, p)[1])
        let bed = SoundBoard.addSound(e4.production, s, slotID: e4.id, src: .pack(pack: "x", cue: "rain"), kind: "ambience")
        p = SoundBoard.updateSound(bed.production, slotID: e4.id, soundID: bed.id!, .init(until: "L0005"))
        let plan = Relay.listenPlan(p, s)
        #expect(plan.map(\.lineID) == ["L0001", "L0002", "L0003", "L0004", "L0005", "L0007"], "the silent direction is not in the plan")
        let cues = SoundBoard.listenCues(s, p, plan: plan)
        #expect(cues[2].after.map(\.sound.src) == [.pack(pack: "x", cue: "thunder")], "the After thunder follows line 3")
        #expect(cues[3].under.map(\.sound.src) == [.pack(pack: "x", cue: "rain")], "the bed starts with line 4")
        #expect(cues[4].stop == [bed.id!], "and stops after line 5, its Until")
        let others = [0, 1, 5].map { cues[$0].isEmpty }
        #expect(others == [true, true, true], "no other entry plays a sound")
        let r = SoundBoard.inPlace(s, plan: plan, line: "L0003")
        #expect(r.map { [plan[$0.lowerBound].lineID, plan[$0.upperBound].lineID] } == ["L0002", "L0004"],
                "Hear it in place: the line before to the line after")
        // A slot on a line the plan skips plays with the next entry.
        let gap = SoundBoard.addSlot(p, line: "L0006")
        let q = SoundBoard.addSound(gap.production, s, slotID: gap.id, src: .pack(pack: "x", cue: "hooves")).production
        #expect(SoundBoard.listenCues(s, q, plan: plan)[5].before.map(\.sound.src) == [.pack(pack: "x", cue: "hooves")])
    }

    /// Found on the 2026-11-27 listening pass: an Under sound set to loop never stopped in a live listen (the export
    /// ends it with its line), and the listen's closing wait on it never returned.
    @Test func aLoopingUnderSoundStopsWithItsLine() {
        let s = radioScript()
        var p = Production(script: s)
        for l in s.lines where l.kind == .speech { p.add(take("t-\(l.id)", l.id, seconds: 0.5)) }
        let e = SoundBoard.ensure(p, SoundBoard.slots(s, p)[1])
        let rain = SoundBoard.addSound(e.production, s, slotID: e.id, src: .pack(pack: "x", cue: "rain"))
        p = SoundBoard.updateSound(rain.production, slotID: e.id, soundID: rain.id!, .init(at: "under", loop: true))
        let plan = Relay.listenPlan(p, s)
        let cues = SoundBoard.listenCues(s, p, plan: plan)
        #expect(cues[3].under.map(\.sound.id) == [rain.id!], "it starts with line 4")
        #expect(cues[3].stop == [rain.id!], "and stops after line 4, as the export ends it")
    }
}
