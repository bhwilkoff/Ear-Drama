import Foundation
import Testing

// Sound in the mix (B32 K2) held to catalog/tests/golden/mix_sound.json, which tools/mix_sound_golden.mjs writes from
// js/plays-core.js: the timeline's shape with and without sound, the duck envelope, and the rendered samples through
// the arithmetic chunk mixer with its two-pass scalar. The inputs are synthetic floats made here from the golden's
// recipes. Nothing here reads a file or plays sound.
//
// Broken controls, 2026-11-26, each against a mutated copy of Core/Plays and seen to fail:
//   SoundMix.attackMs 120 -> 121: the envelope, duck-probe and rendered-sample tests fail.
//   SoundMix.releaseMs 600 -> 500: the same three fail.
//   No merge of voice gaps under 1 s (holdMs 0): the timeline-shape test fails on `voice`.
//   A Before cue not moving the line (cursor not advanced past it): the full-shape test fails (the run then ends early).
//   The duck jumping instead of ramping (duckGains taking the next breakpoint's level): the probes fail.
//   No fade out (fadeOut forced to 0): the full-shape and rendered-sample tests fail.
//   Loop ignored (placement never loops): the full-shape and rendered-sample tests fail.
//   MixRenderer.scale not applying the scalar in the writing pass: the rendered-sample test fails (4 issues).
//   A sound-part line counted as voice (no `.sound` exclusion): the voice-activity assertions fail.
//   chosenFingerprint without the sound block: the moved-sound fingerprint test fails.
//   Production.unusedTakes ignoring slot takes: the kept-take test fails.

// MARK: - The golden

nonisolated private enum SoundGolden {
    static let root: URL = {
        var dir = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("catalog/tests/golden/mix_sound.json").path) { return dir }
            dir = dir.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: ProcessInfo.processInfo.environment["EAR_DRAMA_ROOT"] ?? FileManager.default.currentDirectoryPath)
    }()

    nonisolated(unsafe) static let json: [String: Any] = {
        let data = (try? Data(contentsOf: root.appendingPathComponent("catalog/tests/golden/mix_sound.json"))) ?? Data()
        return ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
    }()

    static var rate: Double { num(json["sampleRate"]) }
    static var expect: [String: Any] { json["expect"] as? [String: Any] ?? [:] }
    static var takeRows: [[String: Any]] { json["takes"] as? [[String: Any]] ?? [] }
    static var cueRows: [[String: Any]] { json["cues"] as? [[String: Any]] ?? [] }

    static func num(_ any: Any?) -> Double { (any as? NSNumber)?.doubleValue ?? .nan }
    static func int(_ any: Any?) -> Int { Int(num(any)) }

    static func data(_ object: Any?) -> Data { (try? JSONSerialization.data(withJSONObject: object ?? [:])) ?? Data() }

    static var script: PlayScript {
        get throws { try JSONDecoder().decode(PlayScript.self, from: data(json["script"])) }
    }

    static var sound: SoundBlock {
        get throws { try JSONDecoder().decode(SoundBlock.self, from: data(json["sound"])) }
    }

    static func block(version: Int? = nil, silentOnly: Bool = false) throws -> SoundBlock {
        var b = try sound
        if let version { b.v = version }
        if silentOnly { b.slots = [b.slots[2]] }
        return b
    }

    static func production(_ sound: SoundBlock?) throws -> Production {
        var p = Production(id: "P", script: try script, created: Date(timeIntervalSince1970: 0))
        p.takes = takeRows.map { t in
            Take(id: t["id"] as? String ?? "", lineID: t["lineID"] as? String ?? "", part: PartID(rawValue: t["part"] as? String ?? ""),
                 file: "\(t["id"] as? String ?? "").wav", created: Date(timeIntervalSince1970: 0), frames: int(t["frames"]),
                 sampleRate: rate, capture: .direct, heard: [:], loudness: num(t["loudness"]), peak: Float(num(t["peak"])), bleed: false)
        }
        p.chosen = (json["chosen"] as? [String: String]) ?? [:]
        p.sound = sound
        return p
    }

    static func resolver(_ have: @escaping (String) -> Bool = { _ in true }) -> (SoundSource, SoundCue) -> SoundInfo? {
        { src, _ in
            guard case let .pack(pack, cue) = src,
                  let c = cueRows.first(where: { $0["pack"] as? String == pack && $0["cue"] as? String == cue }),
                  have(cue) else { return nil }
            return SoundInfo(key: "\(pack)/\(cue)", frames: int(c["frames"]), kind: c["kind"] as? String ?? "effect",
                             loudness: num(c["loudness"]), peak: num(c["peak"]))
        }
    }

    static func synth(_ spec: [String: Any], _ frames: Int) -> [Float] {
        let amp = num(spec["amp"])
        return (0..<frames).map { k in
            if spec["type"] as? String == "sine" { return Float(amp * sin((2 * Double.pi * num(spec["hz"]) * Double(k)) / rate)) }
            return k % int(spec["every"]) == 0 ? Float(amp) : 0
        }
    }

    static let takeSamples: [String: [Float]] = Dictionary(uniqueKeysWithValues: takeRows.map {
        ($0["id"] as? String ?? "", synth($0["synth"] as? [String: Any] ?? [:], int($0["frames"])))
    })
    static let cueSamples: [String: [Float]] = Dictionary(uniqueKeysWithValues: cueRows.map {
        ("\($0["pack"] as? String ?? "")/\($0["cue"] as? String ?? "")", synth($0["synth"] as? [String: Any] ?? [:], int($0["frames"])))
    })

    static func load(_ source: MixRenderer.Source) -> [Float] {
        switch source {
        case let .voice(p): return takeSamples[p.takeID] ?? []
        case let .sound(x):
            switch x.src {
            case let .take(id): return takeSamples[id] ?? []
            case let .pack(pack, cue): return cueSamples["\(pack)/\(cue)"] ?? []
            case .own: return []
            }
        }
    }
}

private func near(_ a: Double, _ b: Double, _ tol: Double = 1e-6) -> Bool { abs(a - b) <= tol }

private func checkShape(_ t: MixTimeline, _ want: [String: Any], _ name: String) {
    let g = SoundGolden.self
    let placements = want["placements"] as? [[String: Any]] ?? []
    #expect(t.totalFrames == g.int(want["totalFrames"]), "\(name): total frames")
    #expect(t.placements.map { [$0.lineID, $0.takeID, "\($0.start)", "\($0.frames)"] }
        == placements.map { [$0["lineID"] as? String ?? "", $0["takeID"] as? String ?? "", "\(g.int($0["start"]))", "\(g.int($0["frames"]))"] },
        "\(name): voice placements")
    #expect(zip(t.placements, placements).allSatisfy { near(Double($0.gain), g.num($1["gain"])) }, "\(name): voice gains")
    guard let sounds = want["sounds"] as? [[String: Any]] else {
        #expect(t.sounds.isEmpty && t.voice.isEmpty && t.left.isEmpty, "\(name): no sound lanes without sound")
        return
    }
    #expect(t.sounds.count == sounds.count, "\(name): sound count")
    for (x, w) in zip(t.sounds, sounds) {
        #expect(x.soundID == w["soundID"] as? String && x.slotID == w["slotID"] as? String && x.lane == w["lane"] as? String,
                "\(name): \(x.soundID) identity")
        #expect([x.start, x.frames, x.inFrame, x.outFrame, x.fadeIn, x.fadeOut]
            == ["start", "frames", "inFrame", "outFrame", "fadeIn", "fadeOut"].map { g.int(w[$0]) }, "\(name): \(x.soundID) frames")
        #expect(x.loop == (w["loop"] as? Bool), "\(name): \(x.soundID) loop")
        #expect(near(x.gain, g.num(w["gain"])) && near(x.duck, g.num(w["duck"])), "\(name): \(x.soundID) gain and duck")
    }
    let voice = (want["voice"] as? [[Any]] ?? []).map { VoiceSpan(start: g.int($0[0]), end: g.int($0[1])) }
    #expect(t.voice == voice, "\(name): voice activity, gaps under 1 s held")
    #expect(t.left == (want["left"] as? [String] ?? []), "\(name): sounds left out")
}

private func envelope(_ points: [DuckPoint]) -> [[Double]] { points.map { [Double($0.frame), $0.db] } }

// MARK: - The timeline

struct MixSoundTimelineTests {
    @Test func cuesPlaceAgainstTheTakesAsTheGoldenSays() throws {
        let g = SoundGolden.self, e = g.expect
        let script = try g.script
        let plain = try MixTimeline.build(script: script, production: g.production(nil))
        checkShape(plain, e["voiceOnly"] as? [String: Any] ?? [:], "voice only")
        #expect(plain.sounds.isEmpty && plain.voice.isEmpty && plain.left.isEmpty, "a play with no sound has the timeline it always had")
        checkShape(try MixTimeline.build(script: script, production: g.production(g.block(silentOnly: true))),
                   e["silentOnly"] as? [String: Any] ?? [:], "only a silent slot")
        checkShape(try MixTimeline.build(script: script, production: g.production(g.block()), resolveSound: g.resolver()),
                   e["full"] as? [String: Any] ?? [:], "full")
        let missing = e["missing"] as? [String: Any] ?? [:]
        #expect(missing["kind"] as? String == "missingSounds")
        #expect(throws: MixTimeline.Failure.missingSounds(missing["detail"] as? [String] ?? [])) {
            try MixTimeline.build(script: script, production: g.production(g.block()), resolveSound: g.resolver { $0 != "rain-steady-1" })
        }
        checkShape(try MixTimeline.build(script: script, production: g.production(g.block()),
                                         resolveSound: g.resolver { $0 != "rain-steady-1" }, withoutMissing: true),
                   e["withoutMissing"] as? [String: Any] ?? [:], "export without them")
        #expect(throws: MixTimeline.Failure.soundVersion(2)) {
            try MixTimeline.build(script: script, production: g.production(g.block(version: 2)), resolveSound: g.resolver())
        }
    }

    @Test func aPackCueWithNoResolverIsNamedNotDropped() throws {
        let g = SoundGolden.self
        #expect(throws: MixTimeline.Failure.missingSounds(["B1", "K1", "R1"])) {
            try MixTimeline.build(script: g.script, production: g.production(g.block()))
        }
    }

    @Test func theDuckIsComputedFromTheVoiceTakesAsTheGoldenSays() throws {
        let g = SoundGolden.self, e = g.expect
        let voice = ((e["full"] as? [String: Any])?["voice"] as? [[Any]] ?? []).map { VoiceSpan(start: g.int($0[0]), end: g.int($0[1])) }
        for (depth, points) in e["envelopes"] as? [String: [[Double]]] ?? [:] {
            #expect(envelope(SoundMix.duckEnvelope(voice, depthDb: Double(depth) ?? 0, sampleRate: g.rate)) == points, "breakpoints at \(depth) dB")
        }
        #expect(SoundMix.duckEnvelope(voice, depthDb: 0, sampleRate: g.rate).isEmpty, "Off has no duck")
        var worst = 0.0
        for probe in e["duckAt"] as? [[Double]] ?? [] {
            let points = SoundMix.duckEnvelope(voice, depthDb: probe[0], sampleRate: g.rate)
            let got = 20 * log10(SoundMix.duckGains(points, from: Int(probe[1]), count: 1)[0])
            worst = max(worst, abs(got - probe[2]))
        }
        #expect(worst < 1e-6, "the envelope at each probe (worst \(worst) dB)")
        let d = g.json["defaults"] as? [String: Any] ?? [:]
        #expect([g.num(d["effectsDuckDb"]), g.num(d["musicDuckDb"]), g.num(d["attackMs"]), g.num(d["releaseMs"]), g.num(d["holdMs"])]
            == [SoundMix.effectsDuckDb, SoundMix.musicDuckDb, SoundMix.attackMs, SoundMix.releaseMs, SoundMix.holdMs])
    }
}

// MARK: - The rendered samples

struct MixSoundRenderTests {
    private func int16(_ x: Float) -> Int { Int((min(1, max(-1, Double(x))) * 32767 + 0.5).rounded(.down)) }

    private func render(_ t: MixTimeline, chunk: Int) throws -> (samples: [Int], peak: Double, scalar: Double) {
        var peak = 0.0
        var from = 0
        while from < t.totalFrames {
            let n = min(chunk, t.totalFrames - from)
            for v in try MixRenderer.mixChunk(t, from: from, count: n, load: SoundGolden.load) { peak = max(peak, Double(abs(v))) }
            from += n
        }
        let scalar = try MixRenderer.scalar(for: t, chunk: chunk, load: SoundGolden.load)
        var out: [Int] = []
        try MixRenderer.finalChunks(t, chunk: chunk, scalar: scalar, load: SoundGolden.load) { out += $0.map(int16) }
        return (out, peak, scalar)
    }

    @Test func theMixWithSoundRendersTheGoldenSamplesToOneLSB() throws {
        let g = SoundGolden.self, e = g.expect
        let t = try MixTimeline.build(script: g.script, production: g.production(g.block()), resolveSound: g.resolver())
        let every = g.int(e["samplesEvery"])
        for chunk in [48_000, 17_760] {
            let r = try render(t, chunk: chunk)
            #expect(r.samples.count == t.totalFrames, "the mix is as long as its timeline (chunks of \(chunk))")
            var worst = 0
            for (i, want) in (e["samples"] as? [Int] ?? []).enumerated() { worst = max(worst, abs(r.samples[i * every] - want)) }
            for pair in e["samplesAt"] as? [[Int]] ?? [] { worst = max(worst, abs(r.samples[pair[0]] - pair[1])) }
            #expect(worst <= 1, "every golden sample within 1 LSB (chunks of \(chunk); worst \(worst))")
            #expect(near(r.peak, g.num(e["peak"])), "the peak the first pass measures (\(r.peak))")
            #expect(near(r.scalar, g.num(e["scalar"])), "the one scalar (\(r.scalar))")
            #expect(Double(r.samples.map { abs($0) }.max() ?? 0) / 32767 <= pow(10, -1.0 / 20) + 1.0 / 32767, "held at -1 dBFS")
        }
        #expect(SoundMix.mixScalar(0.5) == 1, "a quiet mix is not raised")
    }

    @Test func aVoiceOnlyMixIsTheSumOfItsTakesTimesTheirGain() throws {
        let g = SoundGolden.self
        let t = try MixTimeline.build(script: g.script, production: g.production(nil))
        let mix = try MixRenderer.mixChunk(t, from: 0, count: t.totalFrames, load: g.load)
        let first = t.placements[0]
        #expect(mix.count == t.totalFrames)
        #expect(near(Double(mix[100]), Double(g.takeSamples[first.takeID]![100]) * Double(first.gain), 1e-6))
        #expect(mix[first.frames + 100] == 0, "the gap is silent")
    }
}

// MARK: - The record

struct MixSoundRecordTests {
    @Test func oldRecordsKeepTheirFingerprintAndPerformedCuesAreKept() throws {
        let g = SoundGolden.self
        let plain = try g.production(nil)
        #expect(plain.chosenFingerprint == "L0001=t1,L0002=t2,L0004=t4,L0005=t5", "no sound, the fingerprint it always had")
        #expect(try g.production(g.block(silentOnly: true)).chosenFingerprint == plain.chosenFingerprint, "only silent slots change nothing")
        let withSound = try g.production(g.block())
        #expect(withSound.chosenFingerprint != plain.chosenFingerprint, "placing a sound makes the mix stale")
        var moved = withSound
        moved.sound?.slots[1].sounds[2].startMs = -400
        #expect(moved.chosenFingerprint != withSound.chosenFingerprint, "moving a sound makes the mix stale")
        #expect(withSound.unusedTakes.isEmpty, "a take a slot plays is not unused")
        #expect(plain.unusedTakes.map(\.id) == ["k-door"], "without the slot it is")
        var keep = withSound
        #expect(keep.deleteTake("k-door").isEmpty, "a take a slot plays is not deleted")
        #expect(keep.discardUnused().isEmpty, "nor discarded")
        #expect(keep.takes.count == 5)
        var drop = plain
        #expect(drop.discardUnused().map(\.id) == ["k-door"])
        #expect(!SoundMix.hasSound(plain.sound) && SoundMix.hasSound(withSound.sound))
    }

    @Test func productionJSONRoundTripsWithAndWithoutTheBlock() throws {
        let g = SoundGolden.self
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let plain = try g.production(nil)
        let old = try encoder.encode(plain)
        #expect((try JSONSerialization.jsonObject(with: old) as? [String: Any])?["sound"] == nil, "no sound key until a sound is placed")
        let again = try JSONDecoder().decode(Production.self, from: old)
        #expect(again == plain)
        #expect(try encoder.encode(again) == old, "an old record re-encodes unchanged")
        let withSound = try g.production(g.block())
        let data = try encoder.encode(withSound)
        let back = try JSONDecoder().decode(Production.self, from: data)
        #expect(back.sound == withSound.sound && back == withSound, "the block round-trips")
        #expect(back.sound?.slots[1].sounds[0].src == .pack(pack: "eardrama-sounds-1", cue: "knock-wood-1"))
        #expect(back.sound?.slots[1].sounds[2].src == .take("k-door"))
    }

    @Test func aLeanBlockDecodesWithDefaults() throws {
        let json = #"{"slots":[{"id":"S","line":"L1","sounds":[{"id":"C","src":{"own":"f1"},"at":"after"}]}]}"#
        let b = try JSONDecoder().decode(SoundBlock.self, from: Data(json.utf8))
        #expect(b.v == 1 && b.slots[0].sounds[0] == SoundCue(id: "C", src: .own("f1"), at: "after"))
    }

    @Test func theSoundBlockTravelsInTheDataExport() throws {
        let block = try SoundGolden.block()
        let when = Date(timeIntervalSince1970: 1_793_000_000)
        let with = DataExport.Production(id: "P", title: "Golden", created: when, takes: [], sound: block)
        let without = DataExport.Production(id: "Q", title: "Plain", created: when, takes: [])
        let export = DataExport(exportedAt: when, history: [], following: [], queue: [], takes: [with, without])
        let object = try #require(try JSONSerialization.jsonObject(with: export.json()) as? [String: Any])
        let rows = try #require(object["takes"] as? [[String: Any]])
        let sound = try #require(rows[0]["sound"] as? [String: Any])
        let back = try JSONDecoder().decode(SoundBlock.self, from: SoundGolden.data(sound))
        #expect(back == block, "the cues travel with their production")
        #expect(rows[1]["sound"] == nil, "a production with no sound has no sound key")
    }
}
