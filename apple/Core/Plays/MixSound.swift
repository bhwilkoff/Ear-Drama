import Foundation

/// Sound in the mix (B32 §3.3, §4.2, §5.1), a line-for-line port of the "Sound in the mix" section of
/// js/plays-core.js. The duck is computed from where voice takes sit, never detected from audio, so every device
/// computes the same envelope (catalog/tests/golden/mix_sound.json).

/// Where a cue's samples come from: a pack cue, one of the person's own files, or a take performed in a slot.
nonisolated enum SoundSource: Codable, Equatable, Hashable, Sendable {
    case pack(pack: String, cue: String)
    /// The id, and the person's own name for it, so another device can say which sound it lacks (B32 §3.4 item 2).
    case own(String, name: String? = nil)
    case take(String)

    private enum Keys: String, CodingKey { case pack, cue, own, take, name }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        if let take = try c.decodeIfPresent(String.self, forKey: .take) {
            self = .take(take)
        } else if let own = try c.decodeIfPresent(String.self, forKey: .own) {
            self = .own(own, name: try? c.decodeIfPresent(String.self, forKey: .name))
        } else {
            self = .pack(pack: try c.decode(String.self, forKey: .pack), cue: try c.decode(String.self, forKey: .cue))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case let .pack(pack, cue):
            try c.encode(pack, forKey: .pack)
            try c.encode(cue, forKey: .cue)
        case let .own(id, name):
            try c.encode(id, forKey: .own)
            try c.encodeIfPresent(name, forKey: .name)
        case let .take(id): try c.encode(id, forKey: .take)
        }
    }
}

/// One sound a slot places, as stored (§5.1). Every field but the id, source and placement reads leniently.
nonisolated struct SoundCue: Codable, Equatable, Sendable {
    var id: String
    var src: SoundSource
    var at: String
    var until: String?
    var startMs: Double
    var gainDb: Double
    var fadeInMs: Double
    var fadeOutMs: Double
    var loop: Bool
    var duckDb: Double?

    init(id: String, src: SoundSource, at: String, until: String? = nil, startMs: Double = 0, gainDb: Double = 0,
         fadeInMs: Double = 0, fadeOutMs: Double = 0, loop: Bool = false, duckDb: Double? = nil) {
        self.id = id
        self.src = src
        self.at = at
        self.until = until
        self.startMs = startMs
        self.gainDb = gainDb
        self.fadeInMs = fadeInMs
        self.fadeOutMs = fadeOutMs
        self.loop = loop
        self.duckDb = duckDb
    }

    private enum Keys: String, CodingKey { case id, src, at, until, startMs, gainDb, fadeInMs, fadeOutMs, loop, duckDb }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id)
        src = try c.decode(SoundSource.self, forKey: .src)
        at = try c.decode(String.self, forKey: .at)
        until = try? c.decodeIfPresent(String.self, forKey: .until)
        startMs = (try? c.decodeIfPresent(Double.self, forKey: .startMs)) ?? 0
        gainDb = (try? c.decodeIfPresent(Double.self, forKey: .gainDb)) ?? 0
        fadeInMs = (try? c.decodeIfPresent(Double.self, forKey: .fadeInMs)) ?? 0
        fadeOutMs = (try? c.decodeIfPresent(Double.self, forKey: .fadeOutMs)) ?? 0
        loop = (try? c.decodeIfPresent(Bool.self, forKey: .loop)) ?? false
        duckDb = try? c.decodeIfPresent(Double.self, forKey: .duckDb)
    }
}

nonisolated struct SoundSlot: Codable, Equatable, Sendable {
    var id: String
    var line: String
    var piece: Int?
    var added: Bool
    var silent: Bool
    var sounds: [SoundCue]

    init(id: String, line: String, piece: Int? = nil, added: Bool = false, silent: Bool = false, sounds: [SoundCue] = []) {
        self.id = id
        self.line = line
        self.piece = piece
        self.added = added
        self.silent = silent
        self.sounds = sounds
    }

    private enum Keys: String, CodingKey { case id, line, piece, added, silent, sounds }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id)
        line = try c.decode(String.self, forKey: .line)
        piece = try? c.decodeIfPresent(Int.self, forKey: .piece)
        added = (try? c.decodeIfPresent(Bool.self, forKey: .added)) ?? false
        silent = (try? c.decodeIfPresent(Bool.self, forKey: .silent)) ?? false
        sounds = (try? c.decodeIfPresent([SoundCue].self, forKey: .sounds)) ?? []
    }
}

nonisolated struct SoundLane: Codable, Equatable, Sendable {
    var duckDb: Double?

    init(duckDb: Double? = nil) { self.duckDb = duckDb }

    private enum Keys: String, CodingKey { case duckDb }

    init(from decoder: any Decoder) throws {
        duckDb = try? decoder.container(keyedBy: Keys.self).decodeIfPresent(Double.self, forKey: .duckDb)
    }
}

nonisolated struct SoundLanes: Codable, Equatable, Sendable {
    var effects: SoundLane?
    var music: SoundLane?

    init(effects: SoundLane? = nil, music: SoundLane? = nil) {
        self.effects = effects
        self.music = music
    }

    private enum Keys: String, CodingKey { case effects, music }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        effects = try? c.decodeIfPresent(SoundLane.self, forKey: .effects)
        music = try? c.decodeIfPresent(SoundLane.self, forKey: .music)
    }
}

/// The production's `sound` block (§5.1).
nonisolated struct SoundBlock: Codable, Equatable, Sendable {
    var v: Int
    var lanes: SoundLanes
    var slots: [SoundSlot]

    init(v: Int = SoundMix.version, lanes: SoundLanes = SoundLanes(), slots: [SoundSlot] = []) {
        self.v = v
        self.lanes = lanes
        self.slots = slots
    }

    private enum Keys: String, CodingKey { case v, lanes, slots }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        v = (try? c.decodeIfPresent(Int.self, forKey: .v)) ?? SoundMix.version
        lanes = (try? c.decodeIfPresent(SoundLanes.self, forKey: .lanes)) ?? SoundLanes()
        slots = (try? c.decodeIfPresent([SoundSlot].self, forKey: .slots)) ?? []
    }

    /// Takes a slot plays (a performed cue, B32 §3.1 item 6): kept like a chosen take, never in `chosen`.
    var takeIDs: Set<String> {
        var out: Set<String> = []
        for slot in slots {
            for s in slot.sounds { if case let .take(id) = s.src { out.insert(id) } }
        }
        return out
    }

    /// Canonical JSON (sorted keys), what the mix fingerprint holds.
    var canonical: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}

/// What the timeline needs from a cue's source: its length, kind and stored loudness.
nonisolated struct SoundInfo: Equatable, Sendable {
    var key: String
    var frames: Int
    var kind: String
    var loudness: Double?
    var peak: Double
    var file: String?

    init(key: String, frames: Int, kind: String, loudness: Double? = nil, peak: Double = 0, file: String? = nil) {
        self.key = key
        self.frames = frames
        self.kind = kind
        self.loudness = loudness
        self.peak = peak
        self.file = file
    }
}

/// One sound placed on the timeline, in frames.
nonisolated struct SoundPlacement: Equatable, Sendable {
    let slotID: String
    let soundID: String
    let lineID: String
    let at: String
    let src: SoundSource
    let file: String?
    let lane: String
    let start: Int
    let frames: Int
    let inFrame: Int
    let outFrame: Int
    let loop: Bool
    let gain: Double
    let fadeIn: Int
    let fadeOut: Int
    let duck: Double
}

/// A stretch of the timeline where a voice is speaking, gaps under a second held.
nonisolated struct VoiceSpan: Equatable, Sendable {
    var start: Int
    var end: Int
}

nonisolated struct DuckPoint: Equatable, Sendable {
    let frame: Int
    let db: Double
}

nonisolated enum SoundMix {
    static let version = 1
    static let placements = ["before", "under", "after", "bed"]

    /// UNVERIFIED depths and times (B32 §4.2 item 3): to set on a listening pass before the board ships.
    static let effectsDuckDb = -6.0
    static let musicDuckDb = -12.0
    static let attackMs = 120.0
    static let releaseMs = 600.0
    static let holdMs = 1000.0
    static let effectsLufs = -19.0
    static let musicLufs = -20.0
    static let startMinMs = -2000.0
    static let gainMinDb = -12.0
    static let gainMaxDb = 6.0

    enum Failure: Error, Equatable { case soundVersion(Int) }

    /// Frames for a time in ms, rounded half up the same way on every stack.
    static func msFrames(_ ms: Double, _ rate: Double) -> Int { Int((ms * rate / 1000 + 0.5).rounded(.down)) }

    static func clamp(_ v: Double, _ lo: Double, _ hi: Double, _ d: Double) -> Double {
        v.isFinite ? min(hi, max(lo, v)) : d
    }

    /// The slots the timeline reads, or nil when the block places nothing. A newer version is refused, never guessed.
    static func readSound(_ block: SoundBlock?) throws(Failure) -> (lanes: SoundLanes, slots: [SoundSlot])? {
        guard let block else { return nil }
        if block.v > version { throw .soundVersion(block.v) }
        let slots = block.slots.filter { !$0.silent && !$0.sounds.isEmpty }
        return slots.isEmpty ? nil : (block.lanes, slots)
    }

    static func hasSound(_ block: SoundBlock?) -> Bool {
        do { return try readSound(block) != nil } catch { return true }
    }

    /// The duck as breakpoints for one depth: full level outside voice, `depthDb` inside, ramping linearly in dB over
    /// the attack before each voice interval and the release after it. Empty for Off (0 dB).
    static func duckEnvelope(_ voice: [VoiceSpan], depthDb: Double, sampleRate: Double = 48_000) -> [DuckPoint] {
        guard depthDb < 0 else { return [] }
        let a = msFrames(attackMs, sampleRate), r = msFrames(releaseMs, sampleRate)
        var out: [DuckPoint] = []
        for v in voice {
            out.append(DuckPoint(frame: v.start - a, db: 0))
            out.append(DuckPoint(frame: v.start, db: depthDb))
            out.append(DuckPoint(frame: v.end, db: depthDb))
            out.append(DuckPoint(frame: v.end + r, db: 0))
        }
        return out
    }

    /// The envelope's linear gain for each of `count` frames from `from`.
    static func duckGains(_ points: [DuckPoint], from: Int, count: Int) -> [Double] {
        var g = [Double](repeating: 1, count: count)
        guard !points.isEmpty else { return g }
        var j = 0
        var lastDb = 0.0, lastLin = 1.0
        for i in 0..<count {
            let f = from + i
            while j < points.count, points[j].frame <= f { j += 1 }
            let db: Double
            if j == 0 || j == points.count {
                db = 0
            } else {
                let p0 = points[j - 1], p1 = points[j]
                db = p1.frame == p0.frame ? p1.db : p0.db + (p1.db - p0.db) * Double(f - p0.frame) / Double(p1.frame - p0.frame)
            }
            if db != lastDb {
                lastDb = db
                lastLin = pow(10, db / 20)
            }
            g[i] = lastLin
        }
        return g
    }

    /// One sound placement's samples over timeline frames [from, from + count), added into `into` (indexed from
    /// `from`): the source (looped when the placement loops), times its gain, the duck, and its fades (linear in
    /// amplitude).
    static func renderSound(_ x: SoundPlacement, samples: [Float], points: [DuckPoint], from: Int, count: Int,
                            into: inout [Float]) {
        let a = max(from, x.start), b = min(from + count, x.start + x.frames)
        guard a < b else { return }
        let end = min(x.outFrame, samples.count)
        let span = end - x.inFrame
        guard span > 0 else { return }
        let duck = duckGains(points, from: a, count: b - a)
        for f in a..<b {
            let k = f - x.start
            if !x.loop && k >= span { break }
            let src = x.inFrame + (x.loop ? k % span : k)
            var g = x.gain * duck[f - a]
            if x.fadeIn > 0 && k < x.fadeIn { g *= Double(k) / Double(x.fadeIn) }
            if x.fadeOut > 0 && x.frames - k < x.fadeOut { g *= Double(x.frames - k) / Double(x.fadeOut) }
            into[f - from] = Float(Double(into[f - from]) + Double(samples[src]) * g)
        }
    }

    /// The one scalar that holds a mix with sound at or below -1 dBFS sample peak (no limiter, B32 §4.3).
    static func mixScalar(_ peak: Double) -> Double {
        let ceiling = pow(10, MixTimeline.peakCeiling / 20)
        return peak > ceiling ? ceiling / peak : 1
    }
}
