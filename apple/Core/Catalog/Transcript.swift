import Foundation

/// archive.org's automatic transcript of an episode (DECISIONS 058, contract
/// §3.1): shown only where `has_transcript = 1`, fetched from its own URL when
/// the listener opens it, never bundled or stored.
nonisolated enum Transcript {
    /// The one label on every platform: what it is, and that no person wrote it.
    static let label = "Automatic transcript"
    /// A search row found only by words in its transcript.
    static let searchNote = "In the transcript"

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
