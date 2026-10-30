import Foundation
import Testing

// WEB-DESIGN §6.4c's golden cases, the same as js/api.test.js "home and browse: ...".

struct HomeBrowseRulesTests {
    private struct Row {
        let id: String, date: String?, title: String, series: String
    }

    private let rows = [
        Row(id: "a|1944-10-29", date: "1944-10-29", title: "Beloved Enemy", series: "a"),
        Row(id: "a2|1944-10-29", date: "1944-10-29", title: "Beloved  enemy!", series: "a"),
        Row(id: "b|1944-10-29", date: "1944-10-29", title: "On Train", series: "b"),
        Row(id: "c|1944-10-29", date: "1944-10-29", title: "Odd One", series: "c"),
        Row(id: "d|1938-10-29", date: "1938-10-29", title: "Early", series: "d"),
        Row(id: "e|", date: nil, title: "No date", series: "d"),
    ]
    private let series: [String: (genre: String, episodes: Int)] = [
        "a": ("drama", 40), "b": ("comedy", 9), "c": ("", 2), "d": ("drama", 6),
    ]

    @Test func theShowLineIsFiveEpisodes() {
        #expect(ShowLine.isShow(5), "five episodes is a show")
        #expect(!ShowLine.isShow(4), "control: four is a single recording")
        #expect(!ShowLine.isShow(nil), "control: no count is not a show")
    }

    @Test func aDayByYearStacksByGenre() {
        let dy = ShowLine.dayYears(rows, date: { $0.date }, genre: { series[$0.series]?.genre })
        #expect(dy.years.map { [$0.year, $0.total] } == [[1938, 1], [1944, 4]], "an undated row is left off the strip")
        #expect(dy.peak == 1944)
        #expect(dy.count == 5)
        #expect(dy.years[1].genres == ["drama": 2, "comedy": 1, "": 1], "no genre stacks under the empty key")
        #expect(dy.genres == ["drama", "comedy"], "the legend is the genres seen, in the fixed order, never the empty one")
        let tie = ShowLine.dayYears([Row(id: "x", date: "1940-01-01", title: "x", series: "d"),
                                     Row(id: "y", date: "1941-01-01", title: "y", series: "d")],
                                    date: { $0.date }, genre: { _ in nil })
        #expect(tie.peak == 1940, "control: a tie goes to the earlier year")
    }

    @Test func aNightIsItsShowsAndACountOfSingles() {
        let night = ShowLine.nightShows(rows.filter { ($0.date ?? "").hasPrefix("1944") },
                                        title: { $0.title }, episodes: { series[$0.series]?.episodes })
        #expect(night.shows.map(\.id) == ["a|1944-10-29", "b|1944-10-29"],
                "a copy under the same title folds once; a single is not a show")
        #expect(night.singles == 1)
    }

    @Test func theDecadeFieldCountsShowsPerGenreAndDecade() {
        let f = ShowLine.decadeField([("drama", "1944-01-01"), ("drama", "1949"), ("comedy", "1951"),
                                      ("", "1950"), ("news", nil)])
        #expect(f.decades == [1940, 1950])
        #expect(f.count("drama", 1940) == 2)
        #expect(f.none == 2, "no genre and no first year are counted, not drawn")
        #expect(f.genres == ["drama", "comedy"], "rows only for genres that have a cell")
        #expect(ShowLine.fieldSide(98, max: 98) == 32)
        #expect(ShowLine.fieldSide(1, max: 98) == 6, "a one-show cell keeps the floor")
        #expect(ShowLine.fieldSide(0, max: 98) == 0, "control: an empty cell draws nothing")
        #expect(ShowLine.fieldSide(49, max: 98) == 23, "area carries the count (the square root)")
    }
}

struct BrowseLayoutTests {
    private func plan(_ width: CGFloat, decades: Int = 6) -> BrowseLayout.Plan {
        BrowseLayout.plan(width: width, decades: decades, tileMin: 160)
    }

    @Test func theFieldSitsBesideTheGridOnlyWhenTheGridKeepsThreeColumns() {
        let wide = plan(1590)
        #expect(wide.sideBySide && wide.fieldWidth == 312 && wide.gridWidth == 1254 && wide.columns == 7, "1590: \(wide)")
        let ipad = plan(1180)
        #expect(ipad.sideBySide && ipad.gridWidth == 844 && ipad.columns == 4, "1180: \(ipad)")
        let split = plan(820)
        #expect(!split.sideBySide && split.gridWidth == 820 && split.columns == 4, "820: \(split)")
        let phone = plan(390)
        #expect(!phone.sideBySide && phone.columns == 2, "390: \(phone)")
        let small = plan(320)
        #expect(!small.sideBySide && small.columns == 1, "320: \(small)")
    }

    @Test func everyPlanFitsItsWidth() {
        for w: CGFloat in [1590, 1180, 820, 390, 320] {
            let p = plan(w)
            let used = p.sideBySide ? p.fieldWidth + BrowseLayout.sideGap + p.gridWidth : p.gridWidth
            #expect(used <= w, "the field and the grid together are at most \(w) wide, got \(used)")
            let row = CGFloat(p.columns) * p.tileWidth + BrowseLayout.gap * CGFloat(p.columns - 1)
            #expect(row <= p.gridWidth + 0.001, "a row of \(p.columns) tiles fits \(p.gridWidth)")
        }
    }

    @Test func noDecadesNeverMakesAField() {
        #expect(!plan(1590, decades: 0).sideBySide)
    }
}
