import Foundation

/// The Worker's consent words as structure, none changed: with "- " lines the
/// first plain line leads and each "- " line is an item; without them every
/// line is a paragraph.
nonisolated struct ConsentBlock: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case lead, item, paragraph }
    var kind: Kind
    var text: String
}

nonisolated enum ConsentText {
    static func blocks(_ text: String) -> [ConsentBlock] {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let listed = lines.contains { $0.hasPrefix("- ") }
        return lines.enumerated().map { index, line in
            if listed && line.hasPrefix("- ") {
                return ConsentBlock(kind: .item, text: String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            }
            return ConsentBlock(kind: listed && index == 0 ? .lead : .paragraph, text: line)
        }
    }
}
