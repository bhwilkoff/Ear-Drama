import Foundation
import Testing

struct GenreDisplayTests {
    /// The eight names must match the pipeline's (catalog/tools/genres.py NAMES).
    @Test func namesMatchThePipeline() throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("catalog/tools/genres.py")
        let text = try String(contentsOf: source, encoding: .utf8)
        for (key, name) in GenreDisplay.names {
            #expect(text.contains("\"\(key)\": \"\(name)\""), "genres.py has no \(key): \(name)")
        }
        #expect(GenreDisplay.names.count == 8)
        #expect(GenreDisplay.name("OTR-Comedy") == "Comedy")
    }
}
