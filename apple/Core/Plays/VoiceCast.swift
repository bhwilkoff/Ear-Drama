import Foundation
import AVFoundation

// The device voices' cast (PLAYS-DESIGN §2.8, Decision 076 S2): which voice reads which part, one
// assignment for every player on this device (the recorder's cues, the listen-through, the reader's
// Hear the cast), kept in UserDefaults on this device only and never synced (Q8). Mirrors
// js/voice-cast.js; VoiceCastTests mirrors js/voice-cast.test.js.
//
// A part's casting is { engine, voice, name, rate, pitch }: voice is the engine's identifier
// (`AVSpeechSynthesisVoice.identifier`, or a Kokoro voice id such as `af_heart` for the downloaded voices,
// S6e: KokoroEngine.swift), never a language. Auto-cast casts system voices only, so downloading voices never
// recasts a play; a Kokoro voice is a person's choice in the picker. Auto-cast reads only the voices (their
// quality, the person's language, and the gender the VOICE reports); it never reads a part's name
// or the script (§2.8 rule 4).

nonisolated enum VoiceEngine: String, Sendable, Codable {
    case system, kokoro, none
}

nonisolated enum VoiceGender: String, Sendable {
    case male, female
}

/// One castable voice, best first in `VoiceCasting.sorted`.
nonisolated struct CastVoice: Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let language: String
    /// Premium 2, Enhanced 1, Default 0.
    let tier: Int
    let gender: VoiceGender?
    var engine: VoiceEngine = .system

    /// "Ava (Premium)": the name with its quality, once.
    var displayName: String {
        if name.localizedCaseInsensitiveContains("(premium)") || name.localizedCaseInsensitiveContains("(enhanced)") { return name }
        switch tier {
        case 2: return "\(name) (Premium)"
        case 1: return "\(name) (Enhanced)"
        default: return name
        }
    }
}

nonisolated struct VoiceCastEntry: Equatable, Codable, Sendable {
    var engine: VoiceEngine
    var voice: String?
    var name: String?
    var rate: Double = 1
    var pitch: Double = 1

    static let notRead = VoiceCastEntry(engine: .none, voice: nil, name: nil, rate: 1, pitch: 1)
}

/// How a part is read now: not at all (Not read, or no voice on this device), or with `voice`, `rate`,
/// `pitch`; `missing` names a cast voice this device lacks, and `voice` is then the part's auto-cast voice.
nonisolated struct ResolvedVoice: Equatable, Sendable {
    var read: Bool
    var entry: VoiceCastEntry
    var voice: CastVoice?
    var rate: Double
    var pitch: Double
    var missing: String?
    /// The device has no castable voice at all.
    var none: Bool

    static func notRead(_ entry: VoiceCastEntry = .notRead, none: Bool = false) -> ResolvedVoice {
        ResolvedVoice(read: false, entry: entry, voice: nil, rate: 1, pitch: 1, missing: nil, none: none)
    }
}

nonisolated enum VoiceCasting {
    /// Voices repeat on a device with few of them; pitch tells two parts on one voice apart.
    static let pitches: [Double] = [1.0, 0.86, 1.14, 0.93, 1.07]
    static let rateRange: ClosedRange<Double> = 0.5...2
    static let pitchRange: ClosedRange<Double> = 0.5...1.5

    /// The castable voices, best first: tier, the person's own language exactly, the name, the id.
    static func sorted(_ voices: [CastVoice], language: String) -> [CastVoice] {
        voices.sorted {
            if $0.tier != $1.tier { return $0.tier > $1.tier }
            let a = $0.language.lowercased() == language.lowercased()
            let b = $1.language.lowercased() == language.lowercased()
            if a != b { return a }
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.id < $1.id
        }
    }

    private static func entry(_ v: CastVoice, pitch: Double = 1) -> VoiceCastEntry {
        VoiceCastEntry(engine: v.engine, voice: v.id, name: v.displayName, rate: 1, pitch: pitch)
    }

    /// Auto-cast (§2.8 rule 4). `parts` in cast order (largest first), `voices` best first. Speaking parts
    /// take distinct voices, the best first; where voices report a gender, each next part takes the best
    /// remaining voice of the other one. When voices run out the list starts again at the next pitch.
    /// Directions and sound are Not read. Reads nothing of a part but its place in the list.
    static func autoCast(_ parts: [PartID], _ voices: [CastVoice]) -> [PartID: VoiceCastEntry] {
        var out: [PartID: VoiceCastEntry] = [:]
        var pool: [CastVoice] = []
        var round = -1
        var last: VoiceGender?
        for part in parts {
            guard part.isSpeaking else {
                out[part] = .notRead
                continue
            }
            guard !voices.isEmpty else { continue }
            if pool.isEmpty {
                pool = voices
                round += 1
            }
            var k = 0
            if let last, let j = pool.firstIndex(where: { $0.gender != nil && $0.gender != last }) { k = j }
            let v = pool.remove(at: k)
            if let g = v.gender { last = g }
            out[part] = entry(v, pitch: pitches[round % pitches.count])
        }
        return out
    }

    private static func clamp(_ x: Any?, _ r: ClosedRange<Double>, _ d: Double) -> Double {
        guard let n = (x as? NSNumber)?.doubleValue, n.isFinite else { return d }
        return (min(r.upperBound, max(r.lowerBound, n)) * 100).rounded() / 100
    }

    /// An entry as stored: an unknown engine, or a voice-reading engine with no voice, is no entry.
    static func normalize(_ raw: Any?) -> VoiceCastEntry? {
        guard let e = raw as? [String: Any], let name = e["engine"] as? String, let engine = VoiceEngine(rawValue: name) else { return nil }
        if engine == .none { return .notRead }
        guard let voice = e["voice"] as? String, !voice.isEmpty else { return nil }
        return VoiceCastEntry(engine: engine, voice: voice, name: e["name"] as? String ?? voice,
                              rate: clamp(e["rate"], rateRange, 1), pitch: clamp(e["pitch"], pitchRange, 1))
    }

    static func normalize(_ e: VoiceCastEntry) -> VoiceCastEntry? { normalize(dictionary(e)) }

    static func dictionary(_ e: VoiceCastEntry) -> [String: Any] {
        var d: [String: Any] = ["engine": e.engine.rawValue, "rate": e.rate, "pitch": e.pitch]
        if let v = e.voice { d["voice"] = v }
        if let n = e.name { d["name"] = n }
        return d
    }

    static func resolve(_ entry: VoiceCastEntry?, _ part: PartID, _ voices: [CastVoice],
                        _ auto: [PartID: VoiceCastEntry], downloaded: [CastVoice] = []) -> ResolvedVoice {
        guard let e = entry.flatMap(normalize) ?? auto[part], e.engine != .none else {
            return .notRead(entry.flatMap(normalize) ?? auto[part] ?? .notRead, none: voices.isEmpty)
        }
        if voices.isEmpty { return .notRead(e, none: true) }
        let found: CastVoice? = switch e.engine {
        case .system: voices.first { $0.id == e.voice }
        case .kokoro: downloaded.first { $0.engine == .kokoro && $0.id == e.voice }
        case .none: nil
        }
        if let found {
            return ResolvedVoice(read: true, entry: e, voice: found, rate: e.rate, pitch: e.pitch, missing: nil, none: false)
        }
        let fallback = auto[part].flatMap { a in voices.first { $0.id == a.voice } } ?? voices[0]
        let pitch = auto[part]?.pitch ?? 1
        return ResolvedVoice(read: true, entry: e, voice: fallback, rate: e.rate, pitch: pitch,
                             missing: e.name ?? e.voice, none: false)
    }
}

// MARK: - Storage: this device only, newest 80 casts

nonisolated struct CastStorage: Sendable {
    let read: @Sendable () -> Data?
    let write: @Sendable (Data) -> Void

    static let defaultsKey = "ed.cast"

    static func defaults(_ defaults: UserDefaults = .standard) -> CastStorage {
        nonisolated(unsafe) let store = defaults
        return CastStorage(read: { store.data(forKey: defaultsKey) }, write: { store.set($0, forKey: defaultsKey) })
    }

    /// A store that lives and dies with the process, for tests.
    static func memory() -> CastStorage {
        let box = MemoryBox()
        return CastStorage(read: { box.get() }, write: { box.set($0) })
    }

    private final class MemoryBox: @unchecked Sendable {
        private let lock = NSLock()
        private var data: Data?
        func get() -> Data? { lock.lock(); defer { lock.unlock() }; return data }
        func set(_ d: Data) { lock.lock(); data = d; lock.unlock() }
    }
}

nonisolated enum VoiceCastBook {
    static let keep = 80

    private static func all(_ s: CastStorage) -> [String: [String: Any]] {
        guard let data = s.read(), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return [:] }
        return obj
    }

    private static func write(_ s: CastStorage, _ all: [String: [String: Any]]) {
        var all = all
        if all.count > keep {
            let old = all.keys.sorted { (all[$0]?["at"] as? Double ?? 0) < (all[$1]?["at"] as? Double ?? 0) }
            for k in old.prefix(all.count - keep) { all[k] = nil }
        }
        if let data = try? JSONSerialization.data(withJSONObject: all) { s.write(data) }
    }

    static func load(_ key: String, _ s: CastStorage) -> [String: Any]? {
        all(s)[key]?["parts"] as? [String: Any]
    }

    static func save(_ key: String, _ parts: [PartID: VoiceCastEntry], _ s: CastStorage) {
        var book = all(s)
        book[key] = ["parts": Dictionary(uniqueKeysWithValues: parts.map { ($0.key.rawValue, VoiceCasting.dictionary($0.value)) }),
                     "at": Date().timeIntervalSince1970 * 1000]
        write(s, book)
    }

    static func forget(_ key: String, _ s: CastStorage) {
        var book = all(s)
        guard book[key] != nil else { return }
        book[key] = nil
        write(s, book)
    }

    static func productionKey(_ id: String) -> String { "p:\(id)" }
    static func scriptKey(_ id: String) -> String { "s:\(id)" }
}

// MARK: - The caster

/// The one cast for a production (or a play): every player on this device reads parts through this.
/// It holds no state of its own; the storage is the cast, so every instance agrees.
nonisolated final class VoiceCast: Sendable {
    let key: String
    let parts: [PartID]
    /// The play whose published phonemes a Kokoro voice reads (contract §4.1).
    let playID: String?
    private let seed: String?
    private let voicesNow: @Sendable () -> [CastVoice]
    private let downloadedNow: @Sendable () -> [CastVoice]
    private let storage: CastStorage

    init(key: String, seed: String? = nil, playID: String? = nil, parts: [PartID],
         voices: @escaping @Sendable () -> [CastVoice], downloaded: @escaping @Sendable () -> [CastVoice] = { [] },
         storage: CastStorage = .defaults()) {
        self.key = key
        self.seed = seed
        self.playID = playID
        self.parts = parts
        self.voicesNow = voices
        self.downloadedNow = downloaded
        self.storage = storage
    }

    /// The downloaded (Kokoro) voices on this device now: none until the model is here (never on the TV).
    static let deviceDownloaded: @Sendable () -> [CastVoice] = {
        #if os(iOS) || os(macOS)
        KokoroInstall.castable()
        #else
        []
        #endif
    }

    /// A production's cast, starting from its play's. The voices are this device's (`DeviceVoices`).
    static func production(_ id: String, script: PlayScript) -> VoiceCast {
        VoiceCast(key: VoiceCastBook.productionKey(id), seed: VoiceCastBook.scriptKey(script.id), playID: script.id,
                  parts: script.castParts.map(\.id), voices: { DeviceVoices.castable() }, downloaded: deviceDownloaded)
    }

    /// A play's own cast, the reader's (Hear the cast).
    static func script(_ script: PlayScript) -> VoiceCast {
        VoiceCast(key: VoiceCastBook.scriptKey(script.id), playID: script.id, parts: script.castParts.map(\.id),
                  voices: { DeviceVoices.castable() }, downloaded: deviceDownloaded)
    }

    func voices() -> [CastVoice] { voicesNow() }

    /// The downloaded (Kokoro) voices now: none until the model is on this device.
    func downloadedVoices() -> [CastVoice] { downloadedNow() }

    /// Fills any part without a casting by auto-cast, once there is a voice to cast; keeps every choice made.
    @discardableResult
    func ensure() -> [PartID: VoiceCastEntry] {
        let v = voicesNow()
        let have = VoiceCastBook.load(key, storage)
        let base = have ?? seed.flatMap { VoiceCastBook.load($0, storage) } ?? [:]
        var next: [PartID: VoiceCastEntry] = [:]
        for (k, raw) in base { if let e = VoiceCasting.normalize(raw) { next[PartID(rawValue: k)] = e } }
        guard !v.isEmpty else { return next }
        let auto = VoiceCasting.autoCast(parts, v)
        var changed = have == nil
        for id in parts where next[id] == nil {
            if let a = auto[id] {
                next[id] = a
                changed = true
            }
        }
        if changed { VoiceCastBook.save(key, next, storage) }
        return next
    }

    func resolve(_ part: PartID) -> ResolvedVoice {
        let v = voicesNow()
        let cast = ensure()
        return VoiceCasting.resolve(cast[part], part, v, VoiceCasting.autoCast(parts, v), downloaded: downloadedNow())
    }

    /// The system voice that reads a Kokoro part's line Kokoro cannot read (no phonemes for the play, a refused
    /// render): the part's auto-cast system voice at the part's speed (§2.8 rule 10). A system part reads as resolved.
    func systemFallback(_ part: PartID) -> ResolvedVoice {
        let r = resolve(part)
        guard r.read, let voice = r.voice, voice.engine == .kokoro else { return r }
        let v = voicesNow()
        let a = VoiceCasting.autoCast(parts, v)[part]
        guard let fb = v.first(where: { $0.id == a?.voice }) ?? v.first else { return .notRead(r.entry, none: true) }
        return ResolvedVoice(read: true, entry: r.entry, voice: fb, rate: r.rate, pitch: a?.pitch ?? 1, missing: nil, none: false)
    }

    func entry(_ part: PartID) -> VoiceCastEntry? { ensure()[part] }

    /// Merges `change` into the part's current casting and keeps it.
    func set(_ part: PartID, _ change: (inout VoiceCastEntry) -> Void) {
        var cast = ensure()
        var e = cast[part] ?? .notRead
        change(&e)
        guard let next = VoiceCasting.normalize(e) else { return }
        cast[part] = next
        VoiceCastBook.save(key, cast, storage)
    }

    /// Recast all: auto-cast again over the voices on this device now.
    func recast() {
        let v = voicesNow()
        if !v.isEmpty { VoiceCastBook.save(key, VoiceCasting.autoCast(parts, v), storage) }
    }

    /// A production deleted forgets its cast.
    static func forget(production id: String, storage: CastStorage = .defaults()) {
        VoiceCastBook.forget(VoiceCastBook.productionKey(id), storage)
    }
}

// MARK: - What an utterance is told

/// How one player tells the synthesizer to read a part: the cast voice by identifier (never a language),
/// its pitch, and its speed times the session's. Every player builds it here, so a part sounds the same
/// in the recorder, the listen-through and the reader.
nonisolated struct SpeechSetting: Equatable, Sendable {
    let voiceID: String
    let pitch: Float
    let rate: Float

    static func of(_ r: ResolvedVoice, sessionRate: Double = 1) -> SpeechSetting? {
        guard r.read, let v = r.voice else { return nil }
        return SpeechSetting(voiceID: v.id, pitch: Float(r.pitch),
                             rate: min(AVSpeechUtteranceMaximumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * Float(r.rate * sessionRate)))
    }

    func apply(to utterance: AVSpeechUtterance) {
        if let voice = AVSpeechSynthesisVoice(identifier: voiceID) { utterance.voice = voice }
        utterance.pitchMultiplier = pitch
        utterance.rate = rate
    }
}

// MARK: - The device's voices

nonisolated enum DeviceVoices {
    /// English, local, never a Personal Voice or a novelty voice; best first.
    static func castable() -> [CastVoice] {
        let english = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix("en")
                && !$0.voiceTraits.contains(.isPersonalVoice)
                && !$0.voiceTraits.contains(.isNoveltyVoice)
        }
        return VoiceCasting.sorted(english.map(cast), language: AVSpeechSynthesisVoice.currentLanguageCode())
    }

    static func cast(_ v: AVSpeechSynthesisVoice) -> CastVoice {
        let gender: VoiceGender? = switch v.gender {
        case .male: .male
        case .female: .female
        default: nil
        }
        let tier = switch v.quality {
        case .premium: 2
        case .enhanced: 1
        default: 0
        }
        return CastVoice(id: v.identifier, name: v.name, language: v.language, tier: tier, gender: gender)
    }

    /// The synthesizer's voice for a cast voice: by identifier, never by language.
    static func avVoice(_ v: CastVoice) -> AVSpeechSynthesisVoice? { AVSpeechSynthesisVoice(identifier: v.id) }

    /// The words as spoken: printed italic marks never read.
    static func said(_ text: String) -> String {
        text.replacingOccurrences(of: "_", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
