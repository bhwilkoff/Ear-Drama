import XCTest

/// The iPad audit: every screen in landscape and portrait, light and dark, each page attached and read.
/// One test per orientation and appearance; each visits the screens and a spread of shows.
final class IPadAuditUITests: DeviceTestCase {
    private func configure(_ o: UIDeviceOrientation, _ a: XCUIDevice.Appearance) {
        // The iPad stands in landscape; XCUITest only rotates it for the portrait runs.
        if o != .landscapeRight { XCUIDevice.shared.orientation = o }
        XCUIDevice.shared.appearance = a
        sleep(2)
    }

    private func visit(_ tag: String) {
        sweep(tab("home"), "\(tag)-home", pages: 2)
        sweep(tab("stations"), "\(tag)-stations", pages: 2)
        sweep(tab("surprise"), "\(tag)-surprise", pages: 1)
        sweep(tab("library"), "\(tag)-library", pages: 2)
        sweep(tab("browse"), "\(tag)-browse", pages: 8)
        let search = tab("search")
        var field = search.searchFields.firstMatch
        if !field.waitForExistence(timeout: 3) {
            let open = search.buttons.matching(identifier: "Search").allElementsBoundByIndex.last(where: { $0.frame.minY < 200 })
            open?.tap()
            field = search.searchFields.firstMatch
        }
        if field.waitForExistence(timeout: 5) { field.tap(); field.typeText("Gunsmoke\n") }
        sleep(4)
        sweep(search, "\(tag)-search", pages: 3)
        for (name, item) in [("rich", "gunsmoke"), ("dragnet", "dragnet"), ("long", "librivox2469"), ("tarzan", "tarzan")] {
            sweep(tab("browse", ["APP_START_ITEM": item]), "\(tag)-series-\(name)", pages: 3)
        }
        let person = tab("browse")
        person.buttons["Voices"].tap(); sleep(3)
        let face = person.buttons.matching(identifier: "voice-face").firstMatch
        if face.waitForExistence(timeout: 20) { face.tap(); sleep(4); sweep(person, "\(tag)-person", pages: 4) }
        let mini = launch(["APP_START_ITEM": Fixture.short, "APP_AUTOPLAY": "1", "APP_DOOR_SECONDS": "300"])
        sleep(8)
        shot(mini, "\(tag)-nowplaying")
        let close = mini.buttons["Close player"]
        if close.waitForExistence(timeout: 5) { close.tap(); sleep(2) }
        for t in ["Home", "Library", "Browse"] {
            openTab(mini, t); sleep(3)
            sweep(mini, "\(tag)-mini-\(t.lowercased())", pages: 9)
        }
    }

    func testLandscapeDark() { configure(.landscapeRight, .dark); visit("land-dark") }
    func testLandscapeLight() { configure(.landscapeRight, .light); visit("land-light") }
    func testPortraitDark() { configure(.portrait, .dark); visit("port-dark") }
    func testPortraitLight() { configure(.portrait, .light); visit("port-light") }
}
