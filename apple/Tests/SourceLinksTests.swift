import Foundation
import SQLite3
import Testing

// The owner's 2026-11-09 asks, read from the catalog: a show's About (`series.about_text`,
// `about_source`, `about_url`) and an episode's script to read (`episodes.script_url`,
// `script_source`), each behind a column-exists guard, so a catalog without the columns opens
// and shows nothing in their place; the unclaimed rights line is never drawn; a copy of a
// broadcast is never "Recording N".

nonisolated(unsafe) private let TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private enum Columns {
    /// Runs `sql` against the fixture file; a statement that cannot apply (a column already there, or
    /// already gone) is skipped, so the test holds whichever way the served schema has moved.
    static func edit(_ url: URL, _ statements: [String], binds: [String: [String?]] = [:]) throws {
        var h: OpaquePointer?
        try #require(sqlite3_open(url.path, &h) == SQLITE_OK)
        defer { sqlite3_close(h) }
        for sql in statements {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(h, sql, -1, &stmt, nil) == SQLITE_OK else { continue }
            for (i, value) in (binds[sql] ?? []).enumerated() {
                if let value { sqlite3_bind_text(stmt, Int32(i + 1), value, -1, TRANSIENT) } else { sqlite3_bind_null(stmt, Int32(i + 1)) }
            }
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    static let addAbout = [
        "ALTER TABLE series ADD COLUMN about_text TEXT",
        "ALTER TABLE series ADD COLUMN about_source TEXT",
        "ALTER TABLE series ADD COLUMN about_url TEXT",
    ]
    static let dropAbout = [
        "ALTER TABLE series DROP COLUMN about_text",
        "ALTER TABLE series DROP COLUMN about_source",
        "ALTER TABLE series DROP COLUMN about_url",
    ]
    static let addScript = [
        "ALTER TABLE episodes ADD COLUMN script_url TEXT",
        "ALTER TABLE episodes ADD COLUMN script_source TEXT",
        "ALTER TABLE episodes ADD COLUMN script_id TEXT",
    ]
    static let dropScript = [
        "ALTER TABLE episodes DROP COLUMN script_url",
        "ALTER TABLE episodes DROP COLUMN script_source",
        "ALTER TABLE episodes DROP COLUMN script_id",
    ]
    static let setAbout = "UPDATE series SET about_text = ?, about_source = ?, about_url = ? WHERE key = ?"
    static let setScript = "UPDATE episodes SET script_url = ?, script_source = ?, script_id = ? WHERE id = ?"
}

struct SeriesAboutTests {
    static let text = "Suspense is a radio drama series broadcast on CBS Radio from 1942 through 1962.\n\n"
        + "One of the premier drama programs of the Golden Age of Radio, it was subtitled \"radio's outstanding theater of thrills\"."

    @Test func aboutIsReadWhenPublished() throws {
        let url = try Fixture.make()
        try Columns.edit(url, Columns.addAbout + [Columns.setAbout],
                         binds: [Columns.setAbout: [Self.text, "Wikipedia", "https://en.wikipedia.org/wiki/Suspense_(radio_drama)", "suspense"]])
        let db = try #require(CatalogDatabase(path: url.path))
        let about = try #require(db.seriesPage(key: "suspense")?.about)
        #expect(about.paragraphs.count == 2)
        #expect(about.paragraphs[0].hasPrefix("Suspense is a radio drama"))
        #expect(about.sourceLine == "From Wikipedia")
        #expect(about.link?.url.absoluteString == "https://en.wikipedia.org/wiki/Suspense_(radio_drama)")
        // A show the source says nothing about shows nothing: no placeholder, no written stand-in.
        #expect(db.seriesPage(key: "mrsorrowful")?.about == nil)
        // An alias resolves to the same page and its About.
        #expect(db.seriesPage(key: "suspence")?.about == about)
    }

    @Test func aCatalogWithoutTheColumnsShowsNoAbout() throws {
        let url = try Fixture.make()
        try Columns.edit(url, Columns.dropAbout)
        let db = try #require(CatalogDatabase(path: url.path))
        let page = try #require(db.seriesPage(key: "suspense"), "the page still opens")
        #expect(page.about == nil)
        #expect(!page.episodes.isEmpty)
    }

    @Test func onlyTheTextColumnIsRequired() throws {
        let url = try Fixture.make()
        try Columns.edit(url, Columns.dropAbout + ["ALTER TABLE series ADD COLUMN about_text TEXT",
                                                   "UPDATE series SET about_text = 'A show.' WHERE key = 'suspense'"])
        let db = try #require(CatalogDatabase(path: url.path))
        let about = try #require(db.seriesPage(key: "suspense")?.about)
        #expect(about.text == "A show.")
        #expect(about.sourceLine == nil && about.link == nil)
    }

    @Test func blankTextIsNoAbout() {
        #expect(SeriesAbout(text: "  \n\n ", source: "Wikipedia", url: "https://en.wikipedia.org/wiki/X") == nil)
        #expect(SeriesAbout(text: nil, source: nil, url: nil) == nil)
        let about = SeriesAbout(text: "One.\n\n\nTwo.", source: nil, url: "https://en.wikipedia.org/wiki/X")
        #expect(about?.paragraphs == ["One.", "Two."])
        #expect(about?.sourceLine == "From en.wikipedia.org", "an unnamed source is named by its address")
        #expect(SeriesAbout(text: "x", source: "Wikipedia", url: "javascript:alert(1)")?.link == nil, "only a web page is a link")
    }
}

struct ScriptLinkTests {
    @Test func scriptLinkIsReadWhenPublished() throws {
        let url = try Fixture.make()
        try Columns.edit(url, Columns.addScript + [Columns.setScript],
                         binds: [Columns.setScript: ["https://www.genericradio.com/show.php?id=1", "Generic Radio Workshop",
                                                     "grw:1", "suspense|1943-05-25"]])
        let db = try #require(CatalogDatabase(path: url.path))
        let access = try #require(db.episodeDetail(id: "suspense|1943-05-25")?.scriptAccess)
        #expect(access.scriptID == "grw:1")
        let link = try #require(access.link)
        #expect(access.reading == .external(link), "today the control opens the source's page")
        #expect(link.url.absoluteString == "https://www.genericradio.com/show.php?id=1")
        #expect(link.sourceName == "Generic Radio Workshop")
        #expect(db.episodeDetail(id: "suspense|1942-10-20")?.scriptAccess == nil, "an episode without one links none")
        // The castable script (Decision 068) is a different thing and is untouched.
        #expect(db.episodeDetail(id: "suspense|1943-05-25")?.script == "grw-A1")
    }

    @Test func anIDWithNothingToOpenIsNoControl() {
        // Until hosted text exists, an id alone has no way in: no control rather than a dead one.
        #expect(ScriptAccess(scriptID: "grw:1", url: nil, source: nil) == nil)
        #expect(ScriptAccess(scriptID: nil, url: "https://www.genericradio.com/x", source: nil)?.scriptID == nil)
    }

    @Test func aCatalogWithoutTheColumnsLinksNoScript() throws {
        let url = try Fixture.make()
        try Columns.edit(url, Columns.dropScript)
        let db = try #require(CatalogDatabase(path: url.path))
        let detail = try #require(db.episodeDetail(id: "suspense|1943-05-25"), "the episode still opens")
        #expect(detail.scriptAccess == nil)
        #expect(!detail.recordings.isEmpty)
    }

    @Test func aSourcelessLinkIsNamedByItsSite() {
        #expect(SourceLink(url: "https://www.genericradio.com/x", source: nil)?.sourceName == "genericradio.com")
        #expect(SourceLink(url: "https://www.genericradio.com/x", source: "  ")?.sourceName == "genericradio.com")
        #expect(SourceLink(url: "", source: "Generic Radio Workshop") == nil)
        #expect(SourceLink(url: "ftp://example.com/x", source: nil) == nil)
    }
}

struct RecordingLabelFallbackTests {
    private func copy(_ rank: Int, label: String? = nil, kbps: Int? = 128, length: Double? = 1790,
                      variant: String? = nil, partial: Bool = false) -> Recording {
        Recording(rank: rank, archiveID: "Suspense420617TheBurningCourt",
                  url: URL(string: "https://archive.org/download/x/a.mp3")!, format: nil,
                  kbps: kbps, lengthSeconds: length, variant: variant, partial: partial, label: label)
    }

    /// Owner, 2026-11-09: "lots of things in recordings that still are called 'Recording 2'".
    @Test func aCopyWithoutALabelIsNamedByWhatTellsItApart() {
        let cases = [copy(0), copy(1, kbps: nil), copy(2, length: nil), copy(3, kbps: nil, length: nil),
                     copy(4, variant: "AFRS", partial: true), copy(5, label: "OTRR_Suspense_Singles")]
        for (index, recording) in cases.enumerated() {
            let title = RecordingLabel.title(recording, position: index + 1)
            #expect(!title.hasPrefix("Recording"), "\(title)")
            #expect(!title.isEmpty)
        }
        #expect(RecordingLabel.title(copy(1), position: 2) == "128 kbps \u{00B7} 29:50")
        #expect(RecordingLabel.facts(copy(1), isBest: false) == "", "the title already says it")
        #expect(RecordingLabel.facts(copy(0), isBest: true) == "Best copy")
        #expect(RecordingLabel.title(copy(4, variant: "AFRS", partial: true), position: 5)
                == "Armed Forces Radio rebroadcast \u{00B7} Incomplete copy \u{00B7} 128 kbps \u{00B7} 29:50")
        #expect(RecordingLabel.title(copy(0, kbps: nil, length: nil), position: 1) == "Best copy")
        #expect(RecordingLabel.facts(copy(0, kbps: nil, length: nil), isBest: true) == "", "never said twice")
        #expect(RecordingLabel.title(copy(3, kbps: nil, length: nil), position: 4) == "Another copy")
    }

    @Test func aLabeledCopyKeepsItsFactsLine() {
        let named = copy(1, label: "Old Time Radio Researchers")
        #expect(RecordingLabel.title(named, position: 2) == "Old Time Radio Researchers")
        #expect(RecordingLabel.facts(named, isBest: true) == "Best copy \u{00B7} 128 kbps \u{00B7} 29:50")
        // An identifier-shaped label is no name: the copy is named by its facts instead.
        #expect(RecordingLabel.title(copy(1, label: "OTRR_Suspense_Singles"), position: 2) == "128 kbps \u{00B7} 29:50")
    }

    @Test func theFixturesSecondCopyIsNamed() throws {
        let db = try Fixture.open()
        let detail = try #require(db.episodeDetail(id: "suspense|1943-05-25"))
        #expect(detail.recordings.count == 2)
        for (index, recording) in detail.recordings.enumerated() {
            #expect(!RecordingLabel.title(recording, position: index + 1).hasPrefix("Recording"))
        }
    }
}

struct UnclaimedLineTests {
    /// Owner, 2026-11-09: "the 'No rights claim known. Removed on request' on each ear drama is
    /// unnecessary as that is the default for every show on the app".
    @Test func unclaimedIsNeverDrawn() throws {
        let db = try Fixture.open()
        #expect(db.episodeDetail(id: "suspense|1943-05-25")?.rightsLine == nil)
        #expect(db.episodeDetail(id: "mrsorrowful|1950-05-25")?.rightsLine == "Government recording", "control: other lines stay")
        #expect(RightsDisplay.shown(rights: "unclaimed", basis: "rec_orphan_unclaimed") == nil)
        #expect(RightsDisplay.shown(rights: "clean", basis: "rec_librivox") == "LibriVox recording")
        #expect(RightsDisplay.line(rights: "unclaimed", basis: nil) != nil, "the published words are unchanged")
    }
}
