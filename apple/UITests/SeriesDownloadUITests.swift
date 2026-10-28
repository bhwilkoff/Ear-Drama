import XCTest

/// A series' Download menu (iOS-DESIGN §4.3). Barbershop Quartet is two
/// unclaimed recordings of about two minutes each (live catalog, 2026-10-28:
/// 118.6 s and 120.8 s, a few MB together). Starts and ends with none of its
/// episodes downloaded.
final class SeriesDownloadUITests: DeviceTestCase {
    private let key = "barbershopquartet"
    private let seriesName = "Barbershop Quartet"

    private func confirm(_ app: XCUIApplication, _ label: String) {
        let sheet = app.sheets.buttons[label]
        if sheet.waitForExistence(timeout: 5) { sheet.tap(); return }
        let all = app.buttons.matching(identifier: label).allElementsBoundByIndex
        (all.last(where: { $0.isHittable }) ?? all.last ?? app.buttons[label]).tap()
    }

    func testSeriesDownloadListsInPlaceThenRemoves() throws {
        let app = launch(["APP_START_ITEM": key, "APP_DOOR_SECONDS": "600"])
        let menu = app.buttons["Download"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30), "series Download menu")

        menu.tap()
        if app.buttons["Remove Downloads"].waitForExistence(timeout: 2) {
            app.buttons["Remove Downloads"].tap()
            confirm(app, "Remove Downloads")
            sleep(1)
            app.buttons["Download"].tap()
        }
        let all = app.buttons["Download All Episodes"]
        XCTAssertTrue(all.waitForExistence(timeout: 5), "Download All Episodes")
        all.tap()
        let title = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "Download [0-9]+ episodes?\\?")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 15), "the prompt carries the count")
        XCTAssertTrue(title.label.contains("2"), "two episodes: \(title.label)")
        shot(app, "01-prompt")
        confirm(app, "Download")

        app.tabBars.buttons["Library"].tap()
        let row = app.cells.containing(NSPredicate(format: "label CONTAINS 'Downloads'")).firstMatch
        var n = 0
        while !row.waitForExistence(timeout: n == 0 ? 25 : 1) && n < 8 { app.swipeUp(); n += 1 }
        XCTAssertTrue(row.exists, "Downloads row in Library")
        row.tap()
        XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: 10), "the place opened")
        let remove = app.buttons["Remove \(seriesName) Downloads"]
        XCTAssertTrue(remove.waitForExistence(timeout: 20), "the series is listed")
        let busy = app.progressIndicators["Downloading"]
        let started = Date()
        while busy.exists, Date().timeIntervalSince(started) < 150 { sleep(2) }
        XCTAssertFalse(busy.exists, "both downloads finished")
        shot(app, "02-downloads-place")

        remove.tap()
        confirm(app, "Remove Downloads")
        XCTAssertTrue(app.staticTexts["No downloads"].waitForExistence(timeout: 10), "removed; the place is empty")
        shot(app, "03-removed")
    }
}
