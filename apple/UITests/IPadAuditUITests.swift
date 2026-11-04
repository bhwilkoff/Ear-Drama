import XCTest

/// The iPad audit: every screen in landscape and portrait, light and dark, each page attached and read.
/// One test per orientation and appearance; each visits the screens and a spread of shows.
final class IPadAuditUITests: DeviceTestCase {
    private func configure(_ o: UIDeviceOrientation, _ a: XCUIDevice.Appearance) {
        // Always set: however the iPad stands on the bench, a "landscape" frame must be one
        // (2026-11-04: the stand had moved and every land- frame came back portrait).
        XCUIDevice.shared.orientation = o
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

    /// The screens a person judges the iPad by, one or two frames each: quick enough to run per change.
    private func frames(_ tag: String) {
        sweep(tab("home"), "\(tag)-home", pages: 4)
        sweep(tab("stations"), "\(tag)-stations", pages: 1)
        sweep(tab("browse"), "\(tag)-browse", pages: 1)
        for (name, item) in [("rich", "gunsmoke"), ("sparse", "tarzan")] {
            sweep(tab("browse", ["APP_START_ITEM": item]), "\(tag)-series-\(name)", pages: 1)
        }
        shot(tab("browse", ["APP_START_ITEM": "gunsmoke|1952-04-26"]), "\(tag)-episode-p00")
        let person = tab("browse")
        person.buttons["Voices"].tap(); sleep(3)
        shot(person, "\(tag)-voices-p00")
        let face = person.buttons.matching(identifier: "voice-face").firstMatch
        if face.waitForExistence(timeout: 20) { face.tap(); sleep(5); sweep(person, "\(tag)-person", pages: 1) }
    }

    func testFramesLandscapeDark() { configure(.landscapeRight, .dark); frames("land-dark") }
    func testFramesLandscapeLight() { configure(.landscapeRight, .light); frames("land-light") }
    func testFramesPortraitDark() { configure(.portrait, .dark); frames("port-dark") }
    func testFramesPortraitLight() { configure(.portrait, .light); frames("port-light") }

    func testLandscapeDark() { configure(.landscapeRight, .dark); visit("land-dark") }
    func testLandscapeLight() { configure(.landscapeRight, .light); visit("land-light") }
    func testPortraitDark() { configure(.portrait, .dark); visit("port-dark") }
    func testPortraitLight() { configure(.portrait, .light); visit("port-light") }
}
