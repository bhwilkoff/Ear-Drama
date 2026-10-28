import Foundation

/// archive.org's automatic transcript of an episode (DECISIONS 058, contract
/// §3.1): shown only where `has_transcript = 1`, fetched from its own URL when
/// the listener opens it, never bundled or stored.
nonisolated enum Transcript {
    /// The one label on every platform: what it is, and that no person wrote it.
    static let label = "Automatic transcript"
    /// The words a search looks for in a transcript: three letters or more,
    /// folded as FTS5's unicode61 folds them (contract §3.4).
    static func searchWords(_ query: String) -> [String] {
        var seen = Set<String>()
        return tokens(query).filter { $0.count >= 3 && seen.insert($0).inserted }
    }

    static func tokens(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// The line where a search word is first said, verbatim, cut to about
    /// `max` characters around it with an ellipsis at a cut; nil when no line
    /// says one. The same rule on every platform
    /// (catalog/tests/golden/search_text.json).
    static func snippet(_ text: String, words: [String], max: Int = 120) -> String? {
        guard !words.isEmpty,
              let line = lines(text).first(where: { l in
                  tokens(l).contains { t in words.contains { t.hasPrefix($0) } }
              }) else { return nil }
        let chars = Array(line)
        if chars.count <= max { return line }
        let lower = Array(line.lowercased())
        var at = chars.count
        if lower.count == chars.count {
            for w in words.map(Array.init) where w.count <= lower.count {
                for i in 0...(lower.count - w.count)
                where Array(lower[i..<(i + w.count)]) == w && (i == 0 || !(lower[i - 1].isLetter || lower[i - 1].isNumber)) {
                    at = min(at, i)
                    break
                }
            }
        }
        if at == chars.count { at = 0 }
        var start = Swift.max(0, at - 40)
        if start > 0 {
            if let sp = chars[start...].firstIndex(of: " "), sp < at { start = sp + 1 } else { start = at }
        }
        var end = min(chars.count, start + max)
        if end < chars.count, let sp = chars[...end].lastIndex(of: " "), sp > at { end = sp }
        let body = String(chars[start..<end]).trimmingCharacters(in: .whitespaces)
        return (start > 0 ? "…" : "") + body + (end < chars.count ? "…" : "")
    }

    /// The snippet of an episode's shown transcript, fetched from its own URL.
    static func snippet(from url: URL, words: [String]) async -> String? {
        guard let text = try? await load(url) else { return nil }
        return snippet(text, words: words)
    }

    /// The text as archive.org serves it (a sentence a line), with blank
    /// lines and stray whitespace dropped.
    static func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Lines grouped into paragraphs of `size`: the TV's focus stops, so the
    /// remote moves through the text a few sentences at a time.
    static func paragraphs(_ text: String, size: Int = 4) -> [String] {
        let all = lines(text)
        return stride(from: 0, to: all.count, by: max(size, 1)).map {
            all[$0..<min($0 + max(size, 1), all.count)].joined(separator: " ")
        }
    }

    static func load(_ url: URL) async throws -> String {
        try await APIClient.shared.text(from: url)
    }
}
