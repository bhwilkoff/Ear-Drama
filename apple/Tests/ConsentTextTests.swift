import Foundation
import Testing

// The CC0 consent as structure (F3): the Worker's real words, read from
// worker/src/plays.js, become one lead and four items with no word changed;
// text without "- " lines is paragraphs.

nonisolated private let workerSource = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("worker/src/plays.js")

private func servedConsent() throws -> String {
    let source = try String(contentsOf: workerSource, encoding: .utf8)
    let start = try #require(source.range(of: "CONSENT_TEXT = `"))
    let rest = source[start.upperBound...]
    let end = try #require(rest.firstIndex(of: "`"))
    return String(rest[..<end])
}

@Suite struct ConsentTextTests {
    @Test func theServedWordsBecomeALeadAndFourItems() throws {
        let text = try servedConsent()
        let blocks = ConsentText.blocks(text)
        #expect(blocks.filter { $0.kind == .lead }.count == 1)
        #expect(blocks.filter { $0.kind == .item }.count == 4)
        #expect(blocks.first?.kind == .lead)
        let rebuilt = blocks.map { ($0.kind == .item ? "- " : "") + $0.text }.joined(separator: "\n")
        #expect(rebuilt == text)
    }

    @Test func textWithoutListLinesIsParagraphs() {
        #expect(ConsentText.blocks("One thing.\nAnother thing.").map(\.kind) == [.paragraph, .paragraph])
        #expect(ConsentText.blocks("").isEmpty)
    }
}
