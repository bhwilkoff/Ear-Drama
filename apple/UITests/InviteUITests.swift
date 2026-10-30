import XCTest

/// An ear drama invite (PLAYS-DESIGN §11.7 rule 3, DEEP_LINKS.md): the link
/// lands in the inbox, Library opens on Invitation, and Not Now drops it. No
/// Worker is reached signed out, so this runs before one is deployed.
final class InviteUITests: DeviceTestCase {
    private let token = String(repeating: "A", count: 43)

    func testInviteLinkOpensTheInvitation() throws {
        let app = launch(["APP_DOOR_SECONDS": "60"])
        sleep(3)
        app.open(URL(string: "eardrama://invite#\(token)")!)
        XCTAssertTrue(text(app, matching: "^Invitation").waitForExistence(timeout: 15), "the Invitation page")
        // Signed out it shows the whole play and asks for an account only at Take Part.
        XCTAssertTrue(text(app, matching: "Take Part|Sign in to join|does not work|could not be reached|Not available yet")
            .waitForExistence(timeout: 15), "the invitation's state")
        XCTAssertFalse(text(app, matching: "^Consent|I Agree").exists, "no consent screen (Decision 072)")
        shot(app, "invite-opened")
        let notNow = app.buttons["Not Now"]
        XCTAssertTrue(notNow.waitForExistence(timeout: 5), "Not Now")
        notNow.tap()
        XCTAssertFalse(text(app, matching: "^Invitation").waitForExistence(timeout: 3), "the invitation is dropped")
    }
}
