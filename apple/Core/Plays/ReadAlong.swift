import Foundation

/// The read-along's follow logic (PLAYS-DESIGN §2.11), shared by the phone, tablet, Mac and TV. The line heard
/// comes from the listen plan; a rendered mix finds its line by its timeline; the word heard comes from the voice's
/// own timing (rule 3), mapped onto the printed words.
nonisolated enum ReadAlong {
    /// The line the plan's entry `index` speaks; nil past either end.
    static func line(_ plan: [ListenEntry], at index: Int) -> String? {
        plan.indices.contains(index) ? plan[index].lineID : nil
    }

    /// The line a finished drama's file `index` speaks; nil past either end. The file playing is the line heard.
    static func line(files: [FinishedLine], at index: Int) -> String? {
        files.indices.contains(index) ? files[index].lineID : nil
    }

    struct Span: Equatable, Sendable {
        let lineID: String
        let start: Int
        let frames: Int
    }

    /// The line a mix is speaking at `seconds`: the last span begun, nil once the last has ended; a gap keeps the
    /// line before it.
    static func line(_ spans: [Span], rate: Double, seconds: Double) -> String? {
        let frame = seconds * rate
        guard let at = spans.last(where: { Double($0.start) <= frame }) else { return nil }
        if at == spans.last, frame >= Double(at.start + at.frames) { return nil }
        return at.lineID
    }

    /// Whether the reader turns itself to the line heard. A touch (`away`) stops it and offers Back to the Line
    /// while something plays; `back` returns the line now heard and follows again.
    struct Follow: Equatable, Sendable {
        struct Step: Equatable, Sendable {
            var turn: Bool
            var back: Bool
        }

        private(set) var following = true
        private(set) var now: String?

        mutating func line(_ id: String?) -> Step {
            now = id
            return Step(turn: following && id != nil, back: !following && id != nil)
        }

        mutating func away() { following = false }

        mutating func back() -> String? {
            following = true
            return now
        }
    }

    /// The TV panel's three lines: before, the one heard, after (nil at an end).
    static func panel(_ lines: [ScriptLine], around id: String) -> (before: ScriptLine?, current: ScriptLine?, after: ScriptLine?) {
        guard let i = lines.firstIndex(where: { $0.id == id }) else { return (nil, nil, nil) }
        return (i > 0 ? lines[i - 1] : nil, lines[i], i + 1 < lines.count ? lines[i + 1] : nil)
    }

    // MARK: The word heard (rule 3)

    /// A word on the page: UTF-16 offsets into the line's printed words (`ScriptReading.lineText`), end exclusive.
    struct Word: Equatable, Hashable, Sendable {
        let start: Int
        let end: Int
    }

    /// The words a voice is given for a line (`said`: exactly `DeviceVoices.said(line.spokenText)`) and, for each
    /// UTF-16 unit of it, the UTF-16 offset in the line's printed words it came from.
    struct Spoken: Equatable, Sendable {
        let said: String
        let toLine: [Int]
    }

    /// The spoken string of `line` with its map back to the printed words: a speech's said parts (joined by one space,
    /// as `spokenText`), a direction's or a cue's whole block; printed italic marks dropped and the ends trimmed, as
    /// `DeviceVoices.said` does.
    static func spoken(_ line: ScriptLine) -> Spoken {
        var chars: [(Character, Int)] = []
        if line.kind == .speech {
            var at = 0
            var first = true
            for part in line.parts ?? [] {
                if part.isSaid {
                    if !first { chars.append((" ", max(0, at - 1))) }
                    first = false
                    var o = at
                    for ch in part.text {
                        chars.append((ch, o))
                        o += ch.utf16.count
                    }
                }
                at += part.text.utf16.count + 1
            }
        } else {
            var o = 0
            for ch in line.source ?? "" {
                chars.append((ch, o))
                o += ch.utf16.count
            }
        }
        chars.removeAll { $0.0 == "_" }
        while let f = chars.first, f.0.isWhitespace || f.0.isNewline { chars.removeFirst() }
        while let l = chars.last, l.0.isWhitespace || l.0.isNewline { chars.removeLast() }
        var said = ""
        var map: [Int] = []
        for (ch, o) in chars {
            said.append(ch)
            for k in 0..<ch.utf16.count { map.append(o + k) }
        }
        return Spoken(said: said, toLine: map)
    }

    /// The printed word a voice's range of `spoken.said` (UTF-16 location and length) is; nil when it falls outside.
    static func word(_ spoken: Spoken, location: Int, length: Int) -> Word? {
        guard location >= 0, length > 0, location + length <= spoken.toLine.count else { return nil }
        return Word(start: spoken.toLine[location], end: spoken.toLine[location + length - 1] + 1)
    }

    /// The printed words of a spoken string, as UTF-16 ranges of it: runs split at white space and dashes (an em or
    /// en dash, or two hyphens), each holding a letter or a digit, trimmed to its first and last letter or digit.
    static func textWords(_ said: String) -> [Word] {
        let chars = Array(said)
        var offsets: [Int] = []
        var o = 0
        for ch in chars {
            offsets.append(o)
            o += ch.utf16.count
        }
        func separates(_ i: Int) -> Bool {
            let c = chars[i]
            if c.isWhitespace || c == "\u{2014}" || c == "\u{2013}" { return true }
            if c == "-" { return (i + 1 < chars.count && chars[i + 1] == "-") || (i > 0 && chars[i - 1] == "-") }
            return false
        }
        var out: [Word] = []
        var first: Int?
        var last: Int?
        func close() {
            if let f = first, let l = last { out.append(Word(start: offsets[f], end: offsets[l] + chars[l].utf16.count)) }
            first = nil
            last = nil
        }
        for i in chars.indices {
            if separates(i) { close(); continue }
            if chars[i].isLetter || chars[i].isNumber {
                if first == nil { first = i }
                last = i
            }
        }
        close()
        return out
    }

    /// Kokoro's punctuation symbols: a phoneme run made only of these is not a word.
    static let phonemePunctuation: Set<Character> = [";", ":", ",", ".", "!", "?", "\u{2014}", "\u{2026}", "\"", "(", ")",
                                                     "\u{201C}", "\u{201D}", "\u{00AB}", "\u{00BB}", "\u{00A1}", "\u{00BF}",
                                                     "-", "\u{2013}", "'", "\u{2019}"]

    /// One rendered piece: the phoneme symbols that became tokens, in order, and the duration model's frames for each
    /// token, the padding token at both ends included (`symbols.count + 2` values).
    struct KokoroPiece: Equatable, Sendable {
        let symbols: [Character]
        let frames: [Int]
    }

    /// A word heard at a sample of the line's audio (24 kHz before the pitch's playback rate), as a range of `said`.
    struct TimedWord: Equatable, Sendable {
        let sample: Int
        let word: Word
    }

    /// Where each word of a Kokoro line begins in its audio, measured from the duration model (rule 3): each phoneme
    /// word starts at the frames of every token before its first sounding symbol. Phoneme words pair with the printed
    /// words in order only when the two counts agree; otherwise nil (the line stays lit with no word mark).
    static func kokoroWords(said: String, pieces: [KokoroPiece], samplesPerFrame: Int = Kokoro.samplesPerFrame) -> [TimedWord]? {
        guard let starts = phonemeWordStarts(pieces, samplesPerFrame: samplesPerFrame) else { return nil }
        let words = textWords(said)
        guard !words.isEmpty, words.count == starts.count else { return nil }
        return zip(starts, words).map { TimedWord(sample: $0, word: $1) }
    }

    /// The first sample of each phoneme word of the pieces, in order; nil when a piece's frames do not fit its symbols.
    static func phonemeWordStarts(_ pieces: [KokoroPiece], samplesPerFrame: Int = Kokoro.samplesPerFrame) -> [Int]? {
        var starts: [Int] = []
        var base = 0
        for piece in pieces {
            guard piece.frames.count == piece.symbols.count + 2 else { return nil }
            var frame = piece.frames[0]
            var runHasWord = false
            for (i, s) in piece.symbols.enumerated() {
                if s.isWhitespace {
                    runHasWord = false
                } else if !runHasWord, !phonemePunctuation.contains(s) {
                    runHasWord = true
                    starts.append(base + frame * samplesPerFrame)
                }
                frame += piece.frames[i + 1]
            }
            base += piece.frames.reduce(0, +) * samplesPerFrame
        }
        return starts
    }

    /// How many phoneme words a line's whole phoneme string holds (decided before the first piece plays).
    static func phonemeWordCount(_ symbols: String) -> Int {
        phonemeWordStarts([KokoroPiece(symbols: Array(symbols), frames: Array(repeating: 0, count: symbols.count + 2))])?.count ?? 0
    }

    /// The word heard at `sample`: the last one begun, nil before the first.
    static func word(_ timed: [TimedWord], at sample: Int) -> Word? {
        timed.last { $0.sample <= sample }?.word
    }

    // MARK: Speed (rule 7)

    /// The transport's speeds: 0.5x to 2x in quarter steps, a multiplier on each part's own speed.
    static let speeds: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]
    static let speedKey = "ed.along.speed"

    /// The nearest step to `x` (a stored value from another version, or none).
    static func speed(_ x: Double?) -> Double {
        guard let x, x.isFinite else { return 1 }
        return speeds.min { abs($0 - x) < abs($1 - x) } ?? 1
    }

    /// "1.25×": the speed as the transport names it.
    static func speedLabel(_ x: Double) -> String {
        var s = String(format: "%.2f", speed(x))
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s + "\u{00D7}"
    }

    static func savedSpeed(_ defaults: UserDefaults = .standard) -> Double {
        speed(defaults.object(forKey: speedKey) as? Double)
    }

    static func saveSpeed(_ x: Double, _ defaults: UserDefaults = .standard) { defaults.set(speed(x), forKey: speedKey) }
}
