import Foundation

/// The relay (PLAYS-DESIGN §2.3-2.5): pure functions of the script and the
/// production, so every platform can prove the same order.
///
/// C7 (owner 2026-10-23): any open part, in any order, while no other part is
/// being recorded (one microphone). The largest open part is suggested, never
/// forced. Sound effects and stage directions may be left silent; a speaking
/// part may not (C6, below).
nonisolated enum Relay {
    enum Refusal: Error, Equatable {
        case anotherPartIsRecording(PartID)
        case notOpen
        case linesMissing([String])
        case speakingPartCannotBeSilent
    }

    static func order(_ script: PlayScript) -> [PartID] { script.castParts.map(\.id) }

    /// The part being recorded now, if any.
    static func current(_ production: Production, _ script: PlayScript) -> PartID? {
        order(script).first { production.state(of: $0).status == .recording }
    }

    /// The suggested part: the first open part in the order, or nil while a
    /// part is recording or when every part is through.
    static func next(_ production: Production, _ script: PlayScript) -> PartID? {
        guard current(production, script) == nil else { return nil }
        return order(script).first { production.state(of: $0).status == .open }
    }

    static func take(_ part: PartID, performer: String?, in production: Production,
                     script: PlayScript) throws(Refusal) -> Production {
        if let current = current(production, script) { throw .anotherPartIsRecording(current) }
        guard production.state(of: part).status == .open else { throw .notOpen }
        var p = production
        let name = performer?.trimmingCharacters(in: .whitespacesAndNewlines)
        p.parts[part] = PartState(status: .recording, performer: (name?.isEmpty ?? true) ? nil : name)
        return p
    }

    /// Lines of the part with no chosen take, or whose chosen take the bleed
    /// check flagged: that line needs a re-take with headphones.
    static func missingLines(_ part: PartID, in production: Production, script: PlayScript) -> [String] {
        script.lines(for: part).map(\.id).filter { production.usableTake(for: $0) == nil }
    }

    /// "Done with this part" (§2.5). A speaking part is done only when every one
    /// of its lines has a take, because a play cannot be finished with a stand-in
    /// in it (§5 rule 4). A sound or directions part may leave lines silent.
    static func finish(_ part: PartID, in production: Production, script: PlayScript) throws(Refusal) -> Production {
        guard production.state(of: part).status == .recording else { throw .notOpen }
        if part.isSpeaking {
            let missing = missingLines(part, in: production, script: script)
            if !missing.isEmpty { throw .linesMissing(missing) }
        }
        var p = production
        p.parts[part, default: PartState()].status = .done
        return p
    }

    /// C6: nobody takes a part. Only sound effects and stage
    /// directions may be left silent; a speaking part nobody takes leaves the play
    /// unfinished, and it never gets a stored synthetic voice.
    static func leaveSilent(_ part: PartID, in production: Production, script: PlayScript) throws(Refusal) -> Production {
        guard !part.isSpeaking else { throw .speakingPartCannotBeSilent }
        guard [.open, .recording].contains(production.state(of: part).status) else { throw .notOpen }
        var p = production
        p.parts[part, default: PartState()].status = .silent
        return p
    }

    /// Back to a part that is through, to re-take a line. Still one part at a time.
    static func reopen(_ part: PartID, in production: Production, script: PlayScript) throws(Refusal) -> Production {
        if let current = current(production, script) { throw .anotherPartIsRecording(current) }
        guard [.done, .silent].contains(production.state(of: part).status) else { throw .notOpen }
        var p = production
        p.parts[part, default: PartState()].status = .recording
        return p
    }

    /// Speaking lines with no unflagged human take.
    static func missingSpeech(_ production: Production, _ script: PlayScript) -> [String] {
        script.speechLineIDs.filter { production.usableTake(for: $0) == nil }
    }

    /// Lines of any kind whose chosen take the bleed check flagged.
    static func needsRetake(_ production: Production, _ script: PlayScript) -> [String] {
        script.lines.map(\.id).filter { production.chosenTake(for: $0)?.bleed == true }
    }

    /// Every speaking line has an unflagged human take and no chosen take is
    /// flagged: only then can the play be mixed.
    static func isComplete(_ production: Production, _ script: PlayScript) -> Bool {
        missingSpeech(production, script).isEmpty && needsRetake(production, script).isEmpty
    }

    /// The lines that cue a performer's line (§2.4): the previous line where
    /// another part speaks it, or, for a run-up, the two lines before it.
    static func cueLines(before lineID: String, in script: PlayScript, runUp: Bool) -> [ScriptLine] {
        guard let index = script.lines.firstIndex(where: { $0.id == lineID }) else { return [] }
        let me = script.lines[index].part
        let before = script.lines[..<index].filter { $0.kind == .speech }
        if runUp { return Array(before.suffix(2)) }
        guard let last = before.last, last.part != me else { return [] }
        return [last]
    }
}
