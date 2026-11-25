import XCTest

/// Adding a script and casting an episode by ear (iOS-DESIGN §4.21, §4.22), pressed on a real device. Every launch keeps
/// its scripts and productions in scratch (APP_SCRATCH), so nothing of the owner's is read or changed, and is muted.
final class OwnScriptUITests: DeviceTestCase {
    private static let text = """
    ANNA: Who is there?
    BEN: Only me.

    Somebody knocks twice.

    ANNA: Come in, then. (She opens the door.) Mind the step.
    BEN: Thank you. I have walked all the way.
    """

    private func start(_ env: [String: String]) -> XCUIApplication {
        launch(["APP_SCRATCH": "1", "APP_DOOR_SECONDS": "600"].merging(env) { $1 })
    }

    private func button(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Record's +, the title and the words typed, Next, every step of the parts page, Done, the script's page, Edit, and
    /// Delete through the platform's own confirmation.
    func testAddAScript() throws {
        let app = start(["APP_START_TAB": "record"])
        let add = button(app, "add-script")
        XCTAssertTrue(add.waitForExistence(timeout: 30), "Add a Script in Record's bar")
        shot(app, "own-1-record")
        add.tap()
        let title = app.textFields["own-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "the title field")
        title.tap()
        title.typeText("A Little Play")
        let text = app.textViews["own-text"]
        text.tap()
        text.typeText(Self.text)
        let next = button(app, "own-next")
        XCTAssertTrue(wait(next, "isEnabled == true", timeout: 10, "Next"))
        XCTAssertTrue(self.text(app, matching: "2 parts . 5 lines").waitForExistence(timeout: 5), "the count as it is typed")
        XCTAssertTrue(self.text(app, matching: "Kept on this device").waitForExistence(timeout: 5), "and that it is kept")
        shot(app, "own-2-add")
        next.tap()

        let open = button(app, "own-open")
        XCTAssertTrue(open.waitForExistence(timeout: 10), "the strip")
        XCTAssertEqual(open.label, "1 line has no part")
        shot(app, "own-3-parts")
        button(app, "own-next-open").tap()
        app.buttons["Direction"].firstMatch.tap()
        XCTAssertTrue(wait(open, "exists == false", timeout: 5, "the strip gone when every line has a part"))
        button(app, "own-undo").tap()
        XCTAssertTrue(open.waitForExistence(timeout: 5), "Undo brings it back")
        app.buttons["Direction"].firstMatch.tap()

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'BEN. Thank you'")).firstMatch.tap()
        let cut = button(app, "own-cut")
        XCTAssertTrue(cut.waitForExistence(timeout: 5), "the line's sheet")
        let split = button(app, "own-split")
        XCTAssertFalse(split.isEnabled, "no cut placed, nothing to split")
        cut.coordinate(withNormalizedOffset: CGVector(dx: 0.36, dy: 0.3)).tap()
        XCTAssertTrue(wait(split, "isEnabled == true", timeout: 5, "Split Here"))
        shot(app, "own-4-line")
        split.tap()
        XCTAssertTrue(self.text(app, matching: "2 parts . 6 lines").waitForExistence(timeout: 5), "one line more")

        button(app, "own-done").tap()
        XCTAssertTrue(self.text(app, matching: "(?i)your script").waitForExistence(timeout: 10), "the script's own page")
        XCTAssertTrue(app.buttons["Record This"].firstMatch.exists, "Record This")
        XCTAssertFalse(app.buttons["Read Together"].exists, "no Read Together")
        shot(app, "own-5-page")
        let edit = button(app, "own-edit")
        reveal(edit, in: app)
        XCTAssertTrue(self.text(app, matching: "be published").exists, "the refusal stands on the page")
        shot(app, "own-6-page-foot")
        edit.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'ANNA. Who is there'")).firstMatch.waitForExistence(timeout: 10))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'ANNA. Who is there'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Edit Words"].waitForExistence(timeout: 5))
        app.buttons["Edit Words"].tap()
        let words = app.textViews["own-words"]
        XCTAssertTrue(words.waitForExistence(timeout: 5))
        words.tap()
        words.typeText(" Speak up.")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'ANNA. ' AND label CONTAINS 'Speak up'")).firstMatch.waitForExistence(timeout: 5), "the words typed")
        button(app, "own-done").tap()

        XCTAssertTrue(self.text(app, matching: "(?i)your script").waitForExistence(timeout: 10), "back on its page")
        // The Duo's strip holds Back: it is in no navigation bar there.
        let back = app.buttons.matching(NSPredicate(format: "identifier == 'BackButton' OR label == 'Back'")).allElementsBoundByIndex.last { $0.isHittable }
        (back ?? app.navigationBars.buttons.element(boundBy: 0)).tap()
        XCTAssertTrue(button(app, "add-script").waitForExistence(timeout: 10), "Record")
        XCTAssertTrue(self.text(app, matching: "Your Scripts").waitForExistence(timeout: 10), "listed under Your Scripts")
        XCTAssertTrue(self.text(app, matching: "2 parts . 6 lines").exists)
        shot(app, "own-7-your-scripts")
        button(app, "own-row").tap()
        let gone = button(app, "own-delete")
        XCTAssertTrue(gone.waitForExistence(timeout: 10))
        reveal(gone, in: app)
        gone.tap()
        XCTAssertTrue(self.text(app, matching: "Delete A Little Play").waitForExistence(timeout: 5), "asks first")
        shot(app, "own-8-delete")
        app.buttons.matching(NSPredicate(format: "label == 'Delete'")).allElementsBoundByIndex.last?.tap()
        XCTAssertTrue(button(app, "add-script").waitForExistence(timeout: 10))
        XCTAssertFalse(self.text(app, matching: "Your Scripts").exists, "the section is gone with its last script")
    }

    /// Record This on an episode with a transcript, two voices named, a carry, Undo, Leave Out, Back, a line's sheet, Done,
    /// and the casting taken up again.
    func testCastByEar() throws {
        let app = start(["APP_START_TAB": "home", "APP_START_ITEM": Fixture.spoken])
        let door = button(app, "ear-door")
        XCTAssertTrue(door.waitForExistence(timeout: 60), "Record This on \(Fixture.spoken)")
        reveal(door, in: app)
        shot(app, "ear-1-episode")
        door.tap()
        let play = button(app, "ear-play")
        XCTAssertTrue(play.waitForExistence(timeout: 30), "the page")
        XCTAssertTrue(text(app, matching: "Automatic transcript").exists)
        shot(app, "ear-2-page")
        addPart(app, "One")
        play.tap()
        XCTAssertTrue(wait(play, "label == 'Pause'", timeout: 40, "playing"))
        sleep(25)
        let one = app.buttons["ONE"].firstMatch
        one.tap()
        sleep(12)
        shot(app, "ear-3-carried")
        addPart(app, "Two")
        XCTAssertTrue(app.buttons["TWO"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(wait(play, "label == 'Pause'", timeout: 20, "the episode goes on when the sheet closes"))
        sleep(8)
        shot(app, "ear-4-two")
        let before = cast(app)
        XCTAssertGreaterThan(before, 1, "a tap gives its line and those after")
        button(app, "ear-leave-out").tap()
        sleep(1)
        button(app, "ear-undo").tap()
        button(app, "ear-back").tap()
        sleep(2)
        if play.label == "Pause" { play.tap() }
        XCTAssertTrue(wait(play, "label == 'Play'", timeout: 10, "paused"))
        let ones = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'ONE. '")).allElementsBoundByIndex
        (ones.first { $0.frame.minY > 140 && $0.frame.maxY < app.frame.height - 160 && $0.isHittable } ?? ones[ones.count - 1]).tap()
        XCTAssertTrue(app.buttons["Hear It"].waitForExistence(timeout: 5), "the line's sheet")
        shot(app, "ear-5-line")
        app.buttons["Close"].tap()
        XCTAssertTrue(wait(button(app, "ear-done"), "isHittable == true", timeout: 10, "the sheet closed"))
        let counted = cast(app)
        button(app, "ear-done").tap()
        XCTAssertTrue(text(app, matching: "(?i)your script").waitForExistence(timeout: 15), "what was cast is a script")
        XCTAssertFalse(app.buttons["Read Together"].exists)
        let go = app.buttons["Cast by Ear"].firstMatch
        reveal(go, in: app)
        shot(app, "ear-6-page")
        go.tap()
        XCTAssertTrue(play.waitForExistence(timeout: 20), "casting taken up again")
        XCTAssertEqual(cast(app), counted, "where it was left")
        XCTAssertTrue(app.buttons["TWO"].firstMatch.exists, "its parts kept")
        shot(app, "ear-7-resumed")
    }

    private func addPart(_ app: XCUIApplication, _ name: String) {
        button(app, "ear-new-part").tap()
        let field = app.textFields["own-name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the name field")
        field.tap()
        // Return, not the button: typing without the glass hides the keyboard, the sheet settles lower, and a tap
        // aimed before that lands where the button was.
        field.typeText(name + "\n")
        XCTAssertTrue(wait(field, "exists == false", timeout: 10, "the sheet closed"))
    }

    /// The 37 of "37 of 149 lines cast".
    private func cast(_ app: XCUIApplication) -> Int {
        let label = text(app, matching: "[0-9,]+ of [0-9,]+ lines cast").label
        guard let r = label.range(of: "[0-9,]+ of ", options: .regularExpression) else { return -1 }
        return Int(label[r].filter(\.isNumber)) ?? -1
    }
}
