import Foundation

/// The mix as plain data (PLAYS-DESIGN §4.2): lines in script order, each a
/// chosen human take with its in and out points, a gap before it, and a stored
/// gain. Placement is relative, so a longer re-take ripples every later line.
/// A partial play has no timeline at all: it is never mixed into a file (§5
/// rule 3), and nothing but a take can be placed, so a stand-in cannot be.
nonisolated struct MixTimeline: Equatable, Sendable {
    struct Placement: Equatable, Sendable {
        let lineID: String
        let takeID: String
        let file: String
        let start: Int
        let inFrame: Int
        let outFrame: Int
        let gain: Float
        var bleed = false
        var frames: Int { outFrame - inFrame }
    }

    enum Failure: Error, Equatable {
        case incomplete(missing: [String])
        case bleed(lines: [String])
        case sampleRate(String)
        case missingSounds([String])
        case soundVersion(Int)
    }

    let sampleRate: Double
    let placements: [Placement]
    let totalFrames: Int
    /// Empty when the production places no sound; `voice` and `left` are then empty too.
    var sounds: [SoundPlacement] = []
    var voice: [VoiceSpan] = []
    var left: [String] = []

    static let target: Double = -16
    static let peakCeiling: Double = -1
    static let defaultGap = 0.4

    /// `resolveSound` names what a pack or own cue needs (nil when it is not on this device); a slot take is read from
    /// the production itself. A sound that cannot be placed fails as `missingSounds`, or is listed in `left` with
    /// `withoutMissing`.
    static func build(script: PlayScript, production: Production, sampleRate: Double = 48_000,
                      gap: Double = defaultGap, resolveSound: ((SoundSource, SoundCue) -> SoundInfo?)? = nil,
                      withoutMissing: Bool = false) throws(Failure) -> MixTimeline {
        let script = script.scoped(for: production)
        let missing = Relay.missingSpeech(production, script)
        guard missing.isEmpty else { throw .incomplete(missing: missing) }
        let flagged = Relay.needsRetake(production, script)
        guard flagged.isEmpty else { throw .bleed(lines: flagged) }
        let sound: (lanes: SoundLanes, slots: [SoundSlot])?
        do {
            let read = try SoundMix.readSound(production.sound)
            if let read, script.scope != nil {
                let here = Set(script.lines.map(\.id))
                let slots = read.slots.filter { here.contains($0.line) }
                sound = slots.isEmpty ? nil : (read.lanes, slots)
            } else {
                sound = read
            }
        } catch {
            switch error { case let .soundVersion(v): throw .soundVersion(v) }
        }

        struct Entry {
            let slot: SoundSlot
            let s: SoundCue
            let info: SoundInfo
            let order: Int
        }
        var entries: [Entry] = []
        var left: [String] = []
        if let sound {
            for slot in sound.slots {
                for s in slot.sounds {
                    guard SoundMix.placements.contains(s.at) else { continue }
                    var info: SoundInfo?
                    if case let .take(id) = s.src {
                        if let t = production.take(id) {
                            if t.bleed { throw .bleed(lines: [slot.line]) }
                            guard t.sampleRate == sampleRate else { throw .sampleRate(t.id) }
                            info = SoundInfo(key: t.id, frames: t.frames, kind: "effect", loudness: t.loudness,
                                             peak: Double(t.peak), file: t.file)
                        }
                    } else if let resolveSound {
                        info = resolveSound(s.src, s)
                    }
                    guard let info, info.frames > 0 else {
                        left.append(s.id)
                        continue
                    }
                    entries.append(Entry(slot: slot, s: s, info: info, order: entries.count + left.count))
                }
            }
            if !left.isEmpty, !withoutMissing { throw .missingSounds(left) }
        }
        var byLine: [String: [Entry]] = [:]
        for e in entries { byLine[e.slot.line, default: []].append(e) }

        var placements: [Placement] = []
        var voice: [VoiceSpan] = []
        var out: [Int: SoundPlacement] = [:]
        var anchors: [String: (Int, Int)] = [:]
        var endAt: [String: Int] = [:]
        var cursor = 0
        var placed = false
        var lastVoiceEnd = 0
        let gapFrames = Int(gap * sampleRate)
        func nominal() -> Int { placed ? cursor + gapFrames : 0 }
        func startOf(_ e: Entry) -> Int {
            SoundMix.msFrames(SoundMix.clamp(e.s.startMs, SoundMix.startMinMs, 600_000, 0), sampleRate)
        }
        func lane(_ e: Entry) -> String { e.s.at == "bed" || e.info.kind == "music" ? "music" : "effects" }
        func place(_ e: Entry, _ start: Int, _ frames: Int) {
            let ln = lane(e)
            let laneDb = ln == "music" ? sound?.lanes.music?.duckDb : sound?.lanes.effects?.duckDb
            let duck = e.s.duckDb ?? laneDb ?? (ln == "music" ? SoundMix.musicDuckDb : SoundMix.effectsDuckDb)
            let level = gain(loudness: e.info.loudness, peak: e.info.peak, target: ln == "music" ? SoundMix.musicLufs : SoundMix.effectsLufs)
                * pow(10, SoundMix.clamp(e.s.gainDb, SoundMix.gainMinDb, SoundMix.gainMaxDb, 0) / 20)
            let loop = (e.s.at == "under" || e.s.at == "bed") && e.s.loop
            out[e.order] = SoundPlacement(
                slotID: e.slot.id, soundID: e.s.id, lineID: e.slot.line, at: e.s.at, src: e.s.src, file: e.info.file,
                lane: ln, start: start, frames: frames, inFrame: 0, outFrame: e.info.frames, loop: loop, gain: level,
                fadeIn: SoundMix.msFrames(SoundMix.clamp(e.s.fadeInMs, 0, 600_000, 0), sampleRate),
                fadeOut: SoundMix.msFrames(SoundMix.clamp(e.s.fadeOutMs, 0, 600_000, 0), sampleRate),
                duck: min(0, max(-60, duck)))
        }

        for line in script.lines {
            let mine = byLine[line.id] ?? []
            for e in mine where e.s.at == "before" {
                let s = max(0, nominal() + startOf(e))
                place(e, s, e.info.frames)
                cursor = max(cursor, s + e.info.frames)
                placed = true
            }
            let anchor: (Int, Int)
            if let take = production.chosenTake(for: line.id) {
                guard take.sampleRate == sampleRate else { throw .sampleRate(take.id) }
                let start = nominal()
                placements.append(Placement(lineID: line.id, takeID: take.id, file: take.file, start: start,
                                            inFrame: 0, outFrame: take.frames,
                                            gain: gain(loudness: take.loudness, peak: take.peak), bleed: take.bleed))
                cursor = start + take.frames
                placed = true
                lastVoiceEnd = cursor
                if line.part != .sound { voice.append(VoiceSpan(start: start, end: cursor)) }
                anchor = (start, cursor)
            } else {
                let at = nominal()
                anchor = (at, at)
            }
            anchors[line.id] = anchor
            endAt[line.id] = lastVoiceEnd
            for e in mine where e.s.at == "after" {
                let s = max(0, nominal() + startOf(e))
                place(e, s, e.info.frames)
                cursor = max(cursor, s + e.info.frames)
                placed = true
            }
        }
        for e in entries where e.s.at == "under" || e.s.at == "bed" {
            guard let anchor = anchors[e.slot.line] else { continue }
            let s = max(0, anchor.0 + startOf(e))
            var frames: Int
            if e.s.at == "under" {
                frames = e.s.loop ? anchor.1 - s : e.info.frames
            } else {
                let until = e.s.until.flatMap { endAt[$0] } ?? anchor.1
                frames = until + SoundMix.msFrames(SoundMix.clamp(e.s.fadeOutMs, 0, 600_000, 0), sampleRate) - s
                if !e.s.loop { frames = min(frames, e.info.frames) }
            }
            if frames <= 0 { frames = e.info.frames }
            place(e, s, frames)
        }
        guard sound != nil else { return MixTimeline(sampleRate: sampleRate, placements: placements, totalFrames: cursor) }
        let sounds = out.keys.sorted().compactMap { out[$0] }
        var merged: [VoiceSpan] = []
        let hold = SoundMix.msFrames(SoundMix.holdMs, sampleRate)
        for v in voice {
            if let last = merged.last, v.start - last.end < hold {
                merged[merged.count - 1].end = max(last.end, v.end)
            } else {
                merged.append(v)
            }
        }
        let total = sounds.reduce(cursor) { max($0, $1.start + $1.frames) }
        return MixTimeline(sampleRate: sampleRate, placements: placements, totalFrames: total, sounds: sounds,
                           voice: merged, left: left)
    }

    /// The linear gain that brings a take to -16 LUFS, held so its peak stays at
    /// or below -1 dBFS (sample peak stands in for true peak) and within +-24 dB.
    /// An unmeasured or silent take plays at unity.
    static func gain(loudness: Double?, peak: Float) -> Float {
        guard let loudness, loudness.isFinite else { return 1 }
        var db = target - loudness
        if peak > 0 { db = min(db, peakCeiling - 20 * log10(Double(peak))) }
        db = min(max(db, -24), 24)
        return Float(pow(10, db / 20))
    }
}

nonisolated extension MixTimeline {
    /// The gain for a cue's lane, in Double: to `target` LUFS, peak held at -1 dBFS, within +-24 dB.
    fileprivate static func gain(loudness: Double?, peak: Double, target: Double) -> Double {
        guard let loudness, loudness.isFinite else { return 1 }
        var db = target - loudness
        if peak > 0 { db = min(db, peakCeiling - 20 * log10(peak)) }
        db = min(max(db, -24), 24)
        return pow(10, db / 20)
    }
}
