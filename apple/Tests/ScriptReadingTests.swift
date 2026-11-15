import Foundation
import Testing

// The script reader's rules (Decision 076 S0 + S1), held to the web's: the golden section cases every stack runs,
// the contents fixtures of js/reader.test.js case for case, search, runs, the reader's arithmetic, the published
// library, and the pagination over real scripts picked from the data (never a pinned title). A built library is
// read from catalog/out/plays-library, or from the folder TEST_RUNNER_ED_PLAY_LIBRARY names (xcodebuild passes the
// TEST_RUNNER_ prefix on); the bundled scripts are always read.

nonisolated private let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

nonisolated private func bundled() throws -> [PlayScript] {
    let data = try Data(contentsOf: root.appendingPathComponent("catalog/plays/castable-scripts.json"))
    return try JSONDecoder().decode(CastableLibrary.self, from: data).scripts
}

nonisolated private func libraryFolder() -> URL? {
    let env = ProcessInfo.processInfo.environment["ED_PLAY_LIBRARY"]
    let folder = env.map { URL(fileURLWithPath: $0) } ?? root.appendingPathComponent("catalog/out/plays-library")
    return FileManager.default.fileExists(atPath: folder.appendingPathComponent("index.json").path) ? folder : nil
}

nonisolated private func libraryRows() -> [PlayRow] {
    guard let folder = libraryFolder(), let data = try? Data(contentsOf: folder.appendingPathComponent("index.json")),
          let index = try? JSONDecoder().decode(PlayRowIndex.self, from: data) else { return [] }
    return index.plays
}

/// Up to `n` built-library scripts that exist on disk, spread across the index, so no test names a play.
nonisolated private func libraryScripts(_ n: Int) -> [PlayScript] {
    guard let folder = libraryFolder() else { return [] }
    let rows = libraryRows()
    let step = max(1, rows.count / (n * 3))
    var out: [PlayScript] = []
    for row in stride(from: 0, to: rows.count, by: step) where out.count < n {
        guard let path = rows[row].path, let data = try? Data(contentsOf: folder.appendingPathComponent(path)),
              let found = PlaysLibrary.pick(rows[row].id, from: data) else { continue }
        out.append(found)
    }
    return out
}

nonisolated private func speech(_ id: String, _ role: String = "A", say: String = "x") -> ScriptLine {
    ScriptLine(id: id, kind: .speech, role: role, parts: [.say(say)])
}

nonisolated private func block(_ id: String, _ source: String, kind: ScriptLine.Kind = .direction) -> ScriptLine {
    ScriptLine(id: id, kind: kind, source: source)
}

nonisolated private func script(_ id: String = "t", lines: [ScriptLine], sections: [ScriptSection]? = nil,
                                roles: [PlayScript.Role] = []) -> PlayScript {
    PlayScript(id: id, revision: "r", kind: "stage", title: "T", authors: [], source: .init(name: "S", url: "https://example.org"),
               rights: .init(bucket: "script_source_cleared", evidence: []), roles: roles, lines: lines, sections: sections)
}

struct ScriptReadingTests {
    // MARK: Sections

    /// Seen to fail: breaking SECTION_ACT's `\b` made "ACT FOURTH." read as no section and this case list failed.
    @Test func sectionHeadingsMatchTheGoldenCasesEveryStackRuns() throws {
        let data = try Data(contentsOf: root.appendingPathComponent("catalog/tests/golden/script_sections.json"))
        struct Golden: Decodable {
            struct Case: Decodable { let text: String; let level: String?; let title: String?; let act: String? }
            let cases: [Case]
        }
        let golden = try JSONDecoder().decode(Golden.self, from: data)
        #expect(golden.cases.count > 20)
        for c in golden.cases {
            #expect(ScriptReading.sectionLevel(c.text)?.rawValue == c.level, "level of \(c.text.debugDescription)")
            if let title = c.title { #expect(ScriptReading.sectionTitle(c.text) == title, "title of \(c.text.debugDescription)") }
            if let act = c.act { #expect(ScriptReading.actKey(c.text) == act, "act of \(c.text.debugDescription)") }
        }
    }

    @Test func anActHeadingThatRepeatsTheActIsItsSceneAndAnEpilogueStandsAlone() {
        let s = script(lines: [
            speech("L0001", say: "Before anything."),
            block("L0002", "SCENE I. A road."),
            speech("L0003", say: "One."), speech("L0004", say: "Two."),
            block("L0005", "ACT I. SCENE II. The same."),
            speech("L0006", say: "Three."), speech("L0007", say: "Four."),
            block("L0008", "_Enter_ B."),
            speech("L0009", say: "Five."),
        ], sections: [ScriptSection(line: "L0004", source: "ACT I."), ScriptSection(line: "L0007", source: "ACT II."),
                      ScriptSection(line: "L0009", source: "EPILOGUE")])
        let secs = ScriptReading.sectionsOf(s)
        #expect(secs.map(\.line) == ["L0002", "L0004", "L0005", "L0007", "L0009"])
        #expect(secs.map(\.level) == [.scene, .act, .scene, .act, .part])
        #expect(secs.map(\.isLine) == [true, false, true, false, false], "set-aside headings marked")
        let toc = ScriptReading.contentsOf(s)
        #expect(toc.map(\.heading.title) == ["SCENE I. A road.", "ACT I.", "ACT II.", "EPILOGUE"])
        #expect(toc.map { $0.scenes.map(\.title) } == [[], ["ACT I. SCENE II. The same."], [], []])
        let place = ScriptReading.placeOf(toc, lineIndex: 4)
        #expect(place.act?.title == "ACT I." && place.scene?.title == "ACT I. SCENE II. The same.")
        #expect(ScriptReading.placeOf(toc, lineIndex: 0).act == nil, "before the first heading, no place")
        #expect(ScriptReading.contentsOf(script("none", lines: [speech("L0001")])).isEmpty)
    }

    @Test func aPrintedListOfTheActsBeforeThePlayIsLeftOut() {
        let s = script("list", lines: [
            block("L0001", "ACT I.\u{2014}\u{201C}Shot in the back.\u{201D}"), block("L0002", "ACT II.\u{2014}\u{201C}After Taps.\u{201D}"),
            block("L0003", "ACT III.\u{2014}\u{201C}Home Again.\u{201D}"), block("L0004", "SCENE.\u{2014}A room."),
            speech("L0005", say: "Hello."), speech("L0006", say: "Goodbye."),
        ], sections: [ScriptSection(line: "L0004", source: "ACT I.")])
        #expect(ScriptReading.contentsOf(s).map(\.heading.title) == ["ACT I."], "only the act the play opens with")
        #expect(ScriptReading.sectionsOf(script("empty-end", lines: [speech("L0001"), block("L0002", "ACT II.")])).isEmpty,
                "a heading with nothing after it")
    }

    @Test func sectionsOverRealScriptsLandOnLinesInOrderAndScenesSitInsideTheirActs() throws {
        let picked = try bundled() + libraryScripts(60)
        #expect(picked.count >= 15)
        var withContents = 0
        for s in picked {
            let ids = Set(s.lines.map(\.id))
            let secs = ScriptReading.sectionsOf(s)
            for (i, x) in secs.enumerated() {
                #expect(ids.contains(x.line), "\(s.id): section at a line that exists")
                #expect(s.lines[x.index].id == x.line, "\(s.id): index matches")
                #expect(!x.isLine || s.lines[x.index].kind != .speech, "\(s.id): a heading line is never a speech")
                #expect(!x.title.isEmpty && !x.title.contains("\n") && !x.title.contains("_"), "\(s.id): a one-line title")
                if i > 0 { #expect(secs[i - 1].index <= x.index, "\(s.id): in reading order") }
            }
            let toc = ScriptReading.contentsOf(s)
            if !toc.isEmpty { withContents += 1 }
            for (k, top) in toc.enumerated() {
                let next = k + 1 < toc.count ? toc[k + 1].heading.index : Int.max
                for sc in top.scenes { #expect(sc.index >= top.heading.index && sc.index <= next, "\(s.id): \(sc.title) inside \(top.heading.title)") }
            }
            #expect(toc.reduce(0) { $0 + 1 + $1.scenes.count } == secs.count, "\(s.id): every section in the contents once")
        }
        #expect(withContents > 0)
    }

    // MARK: Search

    @Test func searchFoldsCaseAccentsQuotesAndLineBreaksAndReturnsTheWordsAround() throws {
        let s = script(lines: [
            ScriptLine(id: "L0001", kind: .speech, role: "ANNE",
                       parts: [.say("I don\u{2019}t know the CAF\u{00C9}"), .direction("aside"), .say("on the\ncorner.")]),
            block("L0002", "_Enter_ the waiter."),
            ScriptLine(id: "L0003", kind: .speech, role: "BEN", parts: [.say("The cafe is shut. Don't go.")]),
        ])
        let quotes = ScriptReading.searchScript(s, "don't")
        #expect(quotes.total == 2)
        #expect(quotes.hits.map(\.line) == ["L0001", "L0003"] && quotes.hits.map(\.role) == ["ANNE", "BEN"])
        #expect(quotes.hits.map(\.match) == ["don\u{2019}t", "Don't"], "quotes fold")
        #expect(ScriptReading.searchScript(s, "caf\u{00E9}").hits.map(\.line) == ["L0001", "L0003"], "accents fold")
        #expect(ScriptReading.searchScript(s, "the corner").hits.map(\.match) == ["the corner"], "a line break is a space")
        #expect(ScriptReading.searchScript(s, "w").total == 0, "one letter finds nothing")
        #expect(ScriptReading.searchScript(s, "the", limit: 1).hits.count == 1)
        #expect(ScriptReading.searchScript(s, "the", limit: 1).total == 3, "the total counts past the limit")
        let h = try #require(ScriptReading.searchScript(s, "shut").hits.first)
        #expect(h.before + h.match + h.after == "The cafe is shut. Don't go.", "the words around the match")
        let real = try #require(try bundled().first)
        let word = try #require(ScriptReading.lineText(real.lines.first { $0.kind == .speech }!)
            .split(separator: " ").map(String.init).first { $0.count > 4 })
        #expect(ScriptReading.searchScript(real, word).total >= 1, "a word from a real script is found (\(word))")
    }

    @Test func aPartsNextAndPreviousLineAndTheOpenSpeakingParts() {
        let s = script(lines: [speech("L1", "A"), speech("L2", "B"), block("L3", "x"), speech("L4", "A"), block("L5", "BELL", kind: .sound)])
        #expect(ScriptReading.nextLine(of: .role("A"), after: -1, in: s) == 0)
        #expect(ScriptReading.nextLine(of: .role("A"), after: 0, in: s) == 3)
        #expect(ScriptReading.nextLine(of: .role("A"), after: 3, in: s) == nil)
        #expect(ScriptReading.nextLine(of: .role("A"), after: 3, direction: -1, in: s) == 0)
        #expect(ScriptReading.nextLine(of: .role("A"), after: 0, direction: -1, in: s) == nil)
        var p = Production(id: "P", script: s)
        #expect(ScriptReading.openSpeakingParts(p, script: s) == [.role("A"), .role("B")], "sound and directions are never open parts")
        p.parts[.role("A")]?.status = .done
        #expect(ScriptReading.openSpeakingParts(p, script: s) == [.role("B")], "a done part is not open")
        var bare = p
        bare.parts = [.directions: PartState(), .sound: PartState()]
        #expect(ScriptReading.openSpeakingParts(bare).isEmpty, "without the script, by the record")
        let rec = SharedRecord(id: "x", scriptID: "t", scriptRevision: "r", title: "T",
                               parts: ["role:A": .init(status: .done), "role:B": .init(status: .open), "sound": .init(status: .open)])
        #expect(ScriptReading.openSpeakingParts(rec, script: s) == [.role("B")])
        #expect(ScriptReading.openSpeakingParts(rec) == [.role("B")])
    }

    // MARK: The library's rows

    @Test func anIndexRowAndItsFullScriptCountTheSameVoicesMinutesAndCast() throws {
        let json = #"{"id":"gut-1","revision":"r","title":"T","voices":4,"minutes":12,"cast":[9,5,1],"authors":["Ann Author"],"roles":3}"#
        let row = try JSONDecoder().decode(PlayRow.self, from: Data(json.utf8))
        #expect(row.voices == 4 && row.minutes == 12 && row.castLines == [9, 5, 1] && row.partCount == 3 && row.authorLine == "Ann Author")
        let old = try JSONDecoder().decode(PlayRow.self, from: Data(#"{"id":"gut-2","title":"T","voices":3,"roles":7,"minutes":9}"#.utf8))
        #expect(old.castLines.isEmpty && old.partCount == 7, "a row published before `cast` draws no cast and does not throw")
        let one = try #require(try bundled().first)
        #expect(one.castLines == one.castParts.filter { $0.id.isSpeaking }.map(\.lineCount), "a full script counts its lines")
        let byID = Dictionary(libraryRows().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        guard !byID.isEmpty else { return }
        for b in try bundled() {
            let r = try #require(byID[b.id], "\(b.id) in the library")
            #expect(b.voices == r.voices, "\(b.id): voices")
            if r.castIndex != nil { #expect(b.castLines == r.castLines, "\(b.id): cast") }
        }
    }

    @Test func aBundledScriptAsARowCarriesTheNumbersTheIndexWould() throws {
        for s in try bundled() {
            let row = PlayRow(script: s)
            #expect(row.voices == s.voices && row.minutes == s.minutes && row.castLines == s.castLines && row.lineCount == s.lines.count)
        }
    }

    // MARK: ReaderMath

    @Test func settingsDefaultToPagesAndUnknownValuesFallBack() {
        #expect(ReaderPrefs.normalized(nil) == ReaderPrefs())
        #expect(ReaderPrefs().layout == .pages && ReaderPrefs().size == ReaderMath.defaultSize && ReaderPrefs().spacing == .normal)
        #expect(ReaderPrefs.normalized(["layout": "scroll", "size": 6, "spacing": "loose"]) == ReaderPrefs(layout: .scroll, size: 6, spacing: .loose))
        #expect(ReaderPrefs.normalized(["layout": "curl", "size": 99, "spacing": "huge"]) == ReaderPrefs(), "refused")
        #expect(ReaderMath.sizes[ReaderMath.defaultSize] == 1, "the default size is the body size")
        #expect(ReaderPrefs.decode(ReaderPrefs(layout: .scroll, size: 4, spacing: .tight).json) == ReaderPrefs(layout: .scroll, size: 4, spacing: .tight))
        #expect(ReaderPrefs.decode("not json") == ReaderPrefs())
    }

    @Test func theLineAMeasuredPageShowsFirstIsTheOneCarriedOver() {
        let starts = [0, 0, 1, 2], ends = [0, 1, 1, 4]
        let carried: [Int] = (0...4).map { ReaderMath.lineAtPage(starts: starts, ends: ends, page: $0) }
        #expect(carried == [0, 1, 3, 3, 3])
        #expect(ReaderMath.lineAtPage(starts: [], ends: [], page: 0) == -1)
    }

    @Test func turnsSpreadsSwipesTapsAndKeys() {
        let per: [Int] = [ReaderMath.perSpread(834), ReaderMath.perSpread(859), ReaderMath.perSpread(860), ReaderMath.perSpread(951), ReaderMath.perSpread(1440)]
        #expect(per == [1, 1, 2, 2, 2], "two pages from 860 pt: the open Duo (867 to 951) spreads, an 11-inch iPad in portrait does not")
        let single: [Int] = [ReaderMath.turn(0, delta: -1, per: 1, count: 10), ReaderMath.turn(0, delta: 1, per: 1, count: 10),
                             ReaderMath.turn(9, delta: 1, per: 1, count: 10)]
        #expect(single == [0, 1, 9], "one page, clamped")
        let double: [Int] = [ReaderMath.turn(0, delta: 1, per: 2, count: 9), ReaderMath.turn(3, delta: 1, per: 2, count: 9),
                             ReaderMath.turn(7, delta: 1, per: 2, count: 9), ReaderMath.turn(8, delta: 1, per: 2, count: 9)]
        #expect(double == [2, 4, 8, 8], "spreads start on even pages")
        let swipes: [Int] = [ReaderMath.swipeTurn(dx: -90, ms: 400, width: 375), ReaderMath.swipeTurn(dx: 90, ms: 400, width: 375),
                             ReaderMath.swipeTurn(dx: -40, ms: 60, width: 375), ReaderMath.swipeTurn(dx: -40, ms: 400, width: 375),
                             ReaderMath.swipeTurn(dx: -10, ms: 5, width: 375)]
        #expect(swipes == [1, -1, 1, 0, 0], "swipe past a fifth, or flick")
        let zones: [ReaderMath.Zone] = [ReaderMath.tapZone(x: 10, width: 375), ReaderMath.tapZone(x: 200, width: 375), ReaderMath.tapZone(x: 320, width: 375)]
        #expect(zones == [.prev, .middle, .next], "outer fifths turn")
        let keys: [(String, Bool, ReaderMath.KeyTurn)] = [("ArrowRight", false, .by(1)), ("PageUp", false, .by(-1)), (" ", false, .by(1)),
                                                          (" ", true, .by(-1)), ("ArrowDown", false, .by(1)), ("Home", false, .first),
                                                          ("End", false, .last), ("a", false, .none)]
        for (key, shift, want) in keys { #expect(ReaderMath.keyTurn(key, shift: shift) == want, "key \(key.debugDescription) shift \(shift)") }
        let labels: [String] = [ReaderMath.pageLabel(page: 0, per: 1, count: 140), ReaderMath.pageLabel(page: 10, per: 2, count: 140),
                                ReaderMath.pageLabel(page: 138, per: 2, count: 139)]
        #expect(labels == ["1 of 140", "11\u{2013}12 of 140", "139 of 139"])
    }

    @Test func theReadingPositionSurvivesAReLayoutTextSizeUpThenDown() {
        let a = (starts: [0, 0, 1, 1, 2, 2], ends: [0, 0, 1, 1, 2, 2])
        let b = (starts: [0, 1, 2, 3, 5, 6], ends: [0, 1, 2, 4, 5, 6])
        let at = ReaderMath.lineAtPage(starts: a.starts, ends: a.ends, page: 1)
        #expect(at == 2, "the top of page 2 in A")
        let pageB = b.starts[at]
        #expect(b.starts[at] <= pageB && pageB <= b.ends[at], "B turns to the page holding that line")
        #expect(ReaderMath.lineAtPage(starts: b.starts, ends: b.ends, page: pageB) == at)
        #expect(a.starts[ReaderMath.lineAtPage(starts: b.starts, ends: b.ends, page: pageB)] == 1, "back in A, the same page")
        let spread = ReaderMath.spreadStart(b.starts[3], per: 2)
        #expect(spread <= b.starts[3] && b.starts[3] < spread + 2, "a spread holds the line too")
    }

    @Test func rememberedPositionsNewestFirstCapped() {
        var store: [ReaderPosition] = []
        for i in 0..<70 { store = ReaderMath.remember(store, ReaderPosition(id: "s\(i)", line: "L0001")) }
        #expect(store.count == 60 && store[0].id == "s69")
        store = ReaderMath.remember(store, ReaderPosition(id: "s10", part: "role:A"))
        #expect(store[0].id == "s10" && store[0].line == "L0001" && store[0].part == "role:A", "an update keeps the line")
    }

    // MARK: Runs

    @Test func everyPrintedRunMapsBackToItsLinesWords() throws {
        var n = 0
        for s in try bundled() + libraryScripts(40) {
            for line in s.lines {
                let text = ScriptReading.lineText(line) as NSString
                for r in ScriptReading.runsOf(line) {
                    n += 1
                    #expect(text.substring(with: NSRange(location: r.at, length: r.text.utf16.count)) == r.text, "\(s.id) \(line.id)")
                }
            }
        }
        #expect(n > 1000)
        let dir = ScriptReading.runsOf(block("x", "_Enter_ BEN, _slowly_."))
        #expect(dir.map(\.text) == ["Enter", " BEN, ", "slowly", "."] && dir.map(\.at) == [1, 7, 14, 21])
        #expect(dir.map(\.kind) == [.em, .plain, .em, .plain], "italic marks are drawn, not kept")
        let mixed = ScriptReading.runsOf(ScriptLine(id: "m", kind: .speech, role: "A",
                                                     parts: [.say("Hello"), .direction("Looks at_ POLLY"), .say(". Go.")]))
        #expect(mixed.map(\.text) == ["Hello", "Looks at", " POLLY", ". Go."] && mixed.map(\.at) == [0, 6, 15, 22])
        #expect(mixed.map(\.said) == [true, false, false, true], "a name inside an aside turns roman; the said words stay said")
        #expect(ScriptReading.spaceBetween("born.", "laughing") && !ScriptReading.spaceBetween("laughing", ". Same")
                && !ScriptReading.spaceBetween("(", "x") && !ScriptReading.spaceBetween("a", ", b"))
    }

    // MARK: Pagination

    @Test func paginatingARealScriptAtTwoSizesKeepsEveryLineAndTheLineAtThePageTop() throws {
        let pick = try #require((try bundled() + libraryScripts(8)).first { $0.lines.count > 150 })
        let structure = ScriptStructure(pick)
        let size = CGSize(width: 330, height: 560)
        func layout(_ scale: Double) throws -> ReaderLayout {
            try ReaderLayout.build(pick, structure: structure, style: ReaderStyle(base: 17, scale: scale, leading: 1.55), pageSize: size)
        }
        let a = try layout(1), b = try layout(1.5)
        #expect(b.pageCount > a.pageCount, "larger text takes more pages")
        for l in [a, b] {
            #expect(l.starts.count == pick.lines.count && l.ends.count == pick.lines.count)
            for i in pick.lines.indices {
                #expect(l.starts[i] <= l.ends[i], "\(pick.id) line \(i): starts <= ends")
                if i > 0 { #expect(l.starts[i] >= l.starts[i - 1] && l.ends[i] >= l.ends[i - 1], "lines in page order") }
            }
            var next = 0
            for r in l.pages {
                #expect(r.location == next, "pages are contiguous")
                next = r.location + r.length
            }
            #expect(next == l.string.length, "the pages hold the whole script")
        }
        // The top of page N at size A is on its page at size B, and back again (the web's re-layout case on real text).
        for page in stride(from: 0, to: a.pageCount, by: max(1, a.pageCount / 12)) {
            let line = ReaderMath.lineAtPage(starts: a.starts, ends: a.ends, page: page)
            #expect(b.starts[line] <= b.ends[line])
            let atB = ReaderMath.lineAtPage(starts: b.starts, ends: b.ends, page: b.starts[line])
            #expect(atB == line || b.ends[atB] >= b.starts[line], "the kept line reads back at B")
            let back = a.starts[line]
            #expect(back <= page && ReaderMath.lineAtPage(starts: a.starts, ends: a.ends, page: back) <= line, "and is back on its page at A")
        }
    }

    @Test func aLinesPrintedTextIsTheStringThePagesHold() throws {
        let pick = try #require(try bundled().first)
        let structure = ScriptStructure(pick)
        let l = try ReaderLayout.build(pick, structure: structure, style: ReaderStyle(base: 17, scale: 1, leading: 1.55),
                                       pageSize: CGSize(width: 330, height: 560))
        let text = l.string.string as NSString
        let roles = pick.roles.map(\.name)
        func collapsed(_ s: String) -> String { s.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        for i in stride(from: 0, to: pick.lines.count, by: 7) where pick.lines[i].kind == .speech && structure.setAside[i] == nil {
            guard PlayPage.layoutOf(pick.lines[i], roles: roles).speeches.count == 1 else { continue }
            let range = l.lineRanges[i]
            let drawn = collapsed(text.substring(with: range))
            for part in pick.lines[i].parts ?? [] where part.isSaid {
                let said = collapsed(part.text.replacingOccurrences(of: "_", with: ""))
                #expect(drawn.contains(said) || said.isEmpty, "\(pick.id) \(pick.lines[i].id): the said words are on the page as printed")
            }
        }
    }

    // MARK: The Ear Drama page (js/reader.test.js, case for case)

    private func page(_ role: String, _ parts: [LinePart]) -> ScriptLine { ScriptLine(id: "L", kind: .speech, role: role, parts: parts) }

    @Test func versePageKeepsItsLinesAndATranscribersWrappingIsReflowed() {
        #expect(PlayPage.isVerse(["When shall we three meet again?\nIn thunder, lightning, or in rain?"]), "a couplet is verse")
        #expect(PlayPage.isVerse(["This is the sergeant\nWho, like a good and hardy soldier, fought\n\u{2019}Gainst my captivity."]), "a capital after a quote")
        #expect(!PlayPage.isVerse(["I attribute it to the superior quality of the wine, sir. I have often\nobserved that in married households"]), "a lowercase turnover is prose")
        #expect(!PlayPage.isVerse(["Why is it that at a bachelor\u{2019}s establishment the servants invariably\nDrink the champagne? I ask merely for information, and nothing more than\nThat, sir, as anyone would."]), "rows as long as a wrapped line are prose")
        #expect(!PlayPage.isVerse(["Who is there?"]), "no break, nothing to keep")
    }

    @Test func aSpeechRunIntoAnotherIsAttributedToItsSpeakerAndCuesGetTheSoundLane() throws {
        let roles = ["CHARTERIS", "GRACE"]
        let lay = PlayPage.layoutOf(page("CHARTERIS", [.say("Of course. Why not?\nGRACE"), .direction("reflecting"), .say(". Never mind why.")]), roles: roles)
        #expect(lay.speeches.map(\.role) == ["CHARTERIS", "GRACE"], "two speakers")
        #expect(lay.speeches[1].name?.text == "GRACE" && lay.speeches[1].name?.at == 20, "the printed name, at its offset")
        #expect(lay.speeches[1].rows[0].runs.map { [$0.text, "\($0.said)"] } == [["reflecting", "false"], ["Never mind why.", "true"]], "the label period is not drawn")
        #expect(!lay.verse, "a run-in break is not verse")
        let radio = PlayPage.layoutOf(page("HANCOCK", [.direction("sound of gavel"), .say("Order!"), .sound("knock"), .say("Come in.")]), roles: ["HANCOCK"])
        #expect(radio.speeches[0].rows.map(\.cue) == [true, false, true, false], "a sound piece and a sound-of aside are cue rows")
        let duo = PlayPage.layoutOf(ScriptLine(id: "L4a", kind: .direction, source: "JOE _comes down. His clothes are of\n     the familiar kind one sees at street\n     corners; MARY notes his\n     air of dejection._"), roles: ["JOE", "MARY"])
        let duoDrawn = duo.rows[0].runs.map { PlayPage.drawn($0.text) }.joined()
        #expect(!duoDrawn.contains("  "), "a transcriber's wrapped direction is drawn with single spaces, never a gap")
        #expect(duoDrawn.contains("of the familiar") && duoDrawn.contains("street corners") && duoDrawn.contains("his air of"), "no words are lost")
        let blk = PlayPage.layoutOf(ScriptLine(id: "L3", kind: .direction, source: "[_Exeunt._]"), roles: [])
        #expect(blk.rows[0].runs.map(\.text) == ["Exeunt."] && blk.rows[0].runs.map(\.kind) == [.plain], "brackets left undrawn; a wholly italic direction stays italic")
        #expect(PlayPage.layoutOf(ScriptLine(id: "L4", kind: .direction, source: "[Enter Lane."), roles: []).rows[0].runs.map(\.text) == ["Enter Lane."], "an unclosed bracket")
        let stress = PlayPage.layoutOf(page("A", [.say("It is the first in which"), .direction("I"), .say("have been serious."), .direction("Sits."), .say("Well.")]), roles: ["A"])
        #expect(stress.speeches[0].rows[0].runs.map { [$0.text, "\($0.said)"] }
                == [["It is the first in which", "true"], ["I", "true"], ["have been serious.", "true"], ["Sits.", "false"], ["Well.", "true"]],
                "an italic word between lowercase said words is emphasis; a sentence direction stays a direction")
        let em = PlayPage.layoutOf(ScriptLine(id: "L5", kind: .speech, role: "A", parts: [.say("I said"), .say("never,"), .say("not ever.")], em: [1]), roles: ["A"])
        #expect(em.speeches[0].rows[0].runs.map(\.kind) == [.say, .em, .say], "the parser's em part is drawn in italic")
        #expect(em.speeches[0].rows[0].runs.allSatisfy { $0.said })
        let decoded = try JSONDecoder().decode(ScriptLine.self, from: Data(#"{"id":"L6","kind":"speech","role":"A","parts":[{"say":"a"},{"say":"b"}],"em":[1]}"#.utf8))
        #expect(decoded.em == [1], "the catalog's em indexes decode")
        #expect(PlayPage.cueTail("I could love anybody. Any pretty woman, that is.") == 22, "the cue is the last sentence")
        #expect(PlayPage.cueTail("Who is there?") == 0, "one sentence is all cue")
    }

    @Test func verseRowsKeepPrintedLinesAndAHalfLineIsIndented() {
        let lay = PlayPage.layoutOf(page("A", [.say("What bloody man is that?\nHe can report,\n    As seemeth by his plight.")]), roles: ["A"])
        #expect(lay.verse)
        #expect(lay.speeches[0].rows.map { $0.runs.map(\.text).joined() } == ["What bloody man is that?", "He can report,", "As seemeth by his plight."])
        #expect(lay.speeches[0].rows.map(\.indent) == [false, false, true])
    }

    @Test func everyDrawnPieceMapsBackToItsLinesText() throws {
        var n = 0, split = 0
        for s in try bundled() + libraryScripts(40) {
            let roles = s.roles.map(\.name)
            for line in s.lines {
                let text = ScriptReading.lineText(line).replacingOccurrences(of: "\n", with: " ") as NSString
                let lay = PlayPage.layoutOf(line, roles: roles)
                var runs: [PageRun] = lay.rows.flatMap(\.runs)
                for sp in lay.speeches {
                    if let name = sp.name { runs.append(name) }
                    runs += sp.rows.flatMap(\.runs)
                }
                if lay.speeches.count > 1 { split += 1 }
                for r in runs {
                    n += 1
                    let want = r.text.replacingOccurrences(of: "\n", with: " ")
                    #expect(r.at >= 0 && r.at + want.utf16.count <= text.length
                            && text.substring(with: NSRange(location: r.at, length: want.utf16.count)) == want,
                            "\(s.id) \(line.id): run at \(r.at) is not \(want.debugDescription)")
                }
            }
        }
        #expect(n > 1000)
        // No floor on split: the parser now splits run-in speeches itself (2026-11-15); a fixture test covers the page's own split.
    }

    @Test func aRealScriptsPagesNeverEndOnANameAndOpenOnAHeadedSpeech() throws {
        let pick = try #require((try bundled() + libraryScripts(8)).first { $0.lines.count > 150 })
        let l = try ReaderLayout.build(pick, structure: ScriptStructure(pick), style: ReaderStyle(base: 17, scale: 1, leading: 1.55),
                                       pageSize: CGSize(width: 330, height: 560))
        #expect(!l.gutter, "a phone page sets the name over the words")
        let wide = try ReaderLayout.build(pick, structure: ScriptStructure(pick), style: ReaderStyle(base: 17, scale: 1, leading: 1.55),
                                          pageSize: CGSize(width: 560, height: 560))
        #expect(wide.gutter, "a page of 30 em or more sets it in a gutter")
        for layout in [l, wide] {
            for (p, r) in layout.pages.enumerated().dropLast().dropFirst() {
                let last = layout.string.attribute(.edInk, at: max(0, r.location + r.length - 2), effectiveRange: nil) as? Int
                #expect(last != ReaderInk.speaker.rawValue || r.length < 3, "page \(p) does not end on a speaker's name")
            }
        }
    }
}

nonisolated private enum KeyTurnNone { static let value = ReaderMath.KeyTurn.none }
