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

    /// V8: a page's own-span strip shows at least twelve years, so three seasons are three bars, not three slabs.
    @Test func theOwnSpanAxisShowsAtLeastTwelveYears() throws {
        let short = try #require(Grammar.ownSpanAxis(Grammar.runBars(years: [1955, 30, 60, 20])))
        #expect(abs((short.hi - short.lo) * 33 - 12) < 1e-9)
        #expect(abs(short.lo - 25.0 / 33.0) < 1e-9, "the axis starts at the first year")
        let long = try #require(Grammar.ownSpanAxis(Grammar.runBars(years: [1940] + Array(repeating: 5, count: 20))))
        #expect(abs((long.hi - long.lo) * 33 - 20) < 1e-9, "control: a long run keeps its own span")
    }

    @Test func aBareUndatedRowLeadsWithTheWindow() {
        #expect(Grammar.undatedBare(date: nil, number: nil))
        #expect(!Grammar.undatedBare(date: nil, number: 7), "control: a number keeps its block")
        #expect(!Grammar.undatedBare(date: "1943-05-25", number: nil), "control: a date keeps its block")
    }
}
