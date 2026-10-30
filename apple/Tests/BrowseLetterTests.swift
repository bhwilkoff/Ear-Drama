import Foundation
import Testing

// The same golden cases as js/api.test.js "browse and rows: A to Z letters, the histogram strip,
// the bare undated row".

struct BrowseLetterTests {
    @Test func lettersFoldAndNumbersGoUnderHash() {
        #expect(Grammar.azLetter("The Shadow") == "T")
        #expect(Grammar.azLetter("\u{00C9}clair") == "E", "an accent folds")
        #expect(Grammar.azLetter("2000 Plus") == "#")
        #expect(Grammar.azLetter("\"Quoted\"") == "#")
        #expect(Grammar.azLetters(["Zero", "10 Days", "Adam", "Alan"]) == ["#", "A", "Z"])
        #expect(Grammar.azLetters(["Adam"]) == ["A"], "control: no # when no number")
    }

    @Test func theHistogramDrawsRealYears() throws {
        let bars = try #require(Grammar.runBars(years: [1938, 1, 0, 4]))
        #expect(bars.count == 2, "a year with no episode draws nothing")
        #expect(bars[0].height == 0.25)
        #expect(bars[1].height == 1)
        #expect(abs(bars[1].from - 10.0 / 33.0) < 1e-9)
        #expect(Grammar.runBars(years: nil) == nil, "control: no histogram, the span draws")
        #expect(Grammar.runBars(years: [1940, 0, 0]) == nil, "control: all zero")
        #expect(Grammar.parseYearCounts("1932,3,12,0,4") == [1932, 3, 12, 0, 4])
        #expect(Grammar.parseYearCounts("1932") == nil, "control: a year alone is no histogram")
        #expect(Grammar.parseYearCounts(nil) == nil)
    }

    @Test func aBareUndatedRowLeadsWithTheWindow() {
        #expect(Grammar.undatedBare(date: nil, number: nil))
        #expect(!Grammar.undatedBare(date: nil, number: 7), "control: a number keeps its block")
        #expect(!Grammar.undatedBare(date: "1943-05-25", number: nil), "control: a date keeps its block")
    }
}
