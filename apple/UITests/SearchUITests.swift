import XCTest

/// Search by air date (2026-10-27): a date narrows by the other words, and the
/// "Aired" section lists what aired then.
final class SearchUITests: DeviceTestCase {
    func testDateFindsWhatAired() throws {
        let app = launch(["APP_DOOR_SECONDS": "60"])
        sleep(3)
        // The search link (DEEP_LINKS.md) reaches the same screen as typing.
        app.open(URL(string: "eardrama://search?q=gangbusters+august+1954")!)
        let aired = text(app, matching: "Aired")
        XCTAssertTrue(aired.waitForExistence(timeout: 15), "an Aired section")
        XCTAssertTrue(text(app, matching: "Kewpie Doll").waitForExistence(timeout: 10),
                      "Gang Busters 1954-08-02 in it")
        shot(app, "search-date")
    }

    /// A word said in a shown automatic transcript (Decision 058) lists the
    /// episode under "Automatic transcript" with the line where it is said.
    /// "zeppelin" is in four live transcripts and in none of their titles or
    /// series names (search/said/ze.json, 2026-10-28), so a label carrying it
    /// can only be the quoted line, read from the transcript's own URL.
    func testTranscriptWordListsTheLineSaid() throws {
        let app = launch(["APP_DOOR_SECONDS": "90"])
        sleep(3)
        app.open(URL(string: "eardrama://search?q=zeppelin")!)
        let section = text(app, matching: "Automatic transcript")
        XCTAssertTrue(section.waitForExistence(timeout: 20), "an Automatic transcript section")
        let quote = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'zeppelin'")).firstMatch
        XCTAssertTrue(quote.waitForExistence(timeout: 20), "a row quoting the line that says it")
        shot(app, "search-transcript")
    }

    /// A title typed into the Search tab's field. Typing failed on the device
    /// once (a keyboard-focus error that XCTest cannot catch), so the test taps
    /// the field, types only if a keyboard came up, and otherwise opens the
    /// search link; the shot name says which path ran.
    func testTypedTitleFindsTheEpisode() throws {
        let app = launch(["APP_START_TAB": "search", "APP_DOOR_SECONDS": "90"])
        let query = "Andy Clyde"
        var path = "link"
        let field = app.searchFields.firstMatch
        if field.waitForExistence(timeout: 20) {
            field.tap()
            if app.keyboards.firstMatch.waitForExistence(timeout: 4) {
                field.typeText(query)
                path = "typed"
            }
        }
        if path == "link" {
            app.open(URL(string: "eardrama://search?q=" + query.replacingOccurrences(of: " ", with: "+"))!)
        }
        let row = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", Fixture.shortTitle)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "\(Fixture.shortTitle) in the results (\(path))")
        shot(app, "search-title-\(path)")
    }
}
