import Foundation

extension VoiceCastModel {
    /// A voice for a part, keeping its speed and pitch.
    func choose(_ part: PartID, _ voice: CastVoice) {
        set(part) {
            $0 = VoiceCastEntry(engine: voice.engine, voice: voice.id, name: voice.displayName, rate: $0.rate, pitch: $0.pitch)
        }
    }

    func chooseNotRead(_ part: PartID) { set(part) { $0 = .notRead } }
}

/// The words on the chip and the picker (iOS-DESIGN §4.12c): what the voice is, and how it is tuned.
nonisolated enum VoiceChipText {
    static func title(_ r: ResolvedVoice) -> String {
        if r.none { return "No Voice" }
        guard r.read, let voice = r.voice else { return "Not read" }
        return voice.displayName
    }

    static func rate(_ x: Double) -> String { String(format: "%.1f\u{00D7}", x) }

    /// Pitch as steps of 0.1 from the voice's own.
    static func pitchStep(_ pitch: Double) -> Int { Int(((pitch - 1) * 10).rounded()) }

    /// "0", "+1", "\u{2212}1".
    static func pitch(_ step: Int) -> String {
        step == 0 ? "0" : step > 0 ? "+\(step)" : "\u{2212}\(-step)"
    }

    /// "1.2\u{00D7}, pitch \u{2212}1" when either is not the voice's own; nil otherwise.
    static func tuning(_ r: ResolvedVoice) -> String? {
        guard r.read else { return nil }
        var bits: [String] = []
        if abs(r.rate - 1) > 0.001 { bits.append(rate(r.rate)) }
        let step = pitchStep(r.pitch)
        if step != 0 { bits.append("pitch \(pitch(step))") }
        return bits.isEmpty ? nil : bits.joined(separator: ", ")
    }

    static func accessibility(_ r: ResolvedVoice, part: PartID) -> String {
        if let missing = r.missing, let voice = r.voice {
            return "\(missing) is not on this device; \(voice.displayName) reads instead"
        }
        return "Voice for \(part.title): \(title(r))"
    }
}
