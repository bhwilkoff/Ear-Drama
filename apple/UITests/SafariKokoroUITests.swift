import XCTest

/// The web's Kokoro voices in real Safari on the phone (owner 2026-11-27: "they either don't play at all
/// or crash the page"). Drives Safari, not the app: opens Library with the ?diag=kokoro overlay, taps
/// Download, waits for the self-test's verdict, then opens a play's reader and starts Hear the cast.
/// Muted with ?mute=1 (the gain is 0; every render still runs). Each stage is a frame.
final class SafariKokoroUITests: XCTestCase {
    let site = "https://eardrama.org/"
    let play = "gut-59770-105"

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func button(_ safari: XCUIApplication, _ format: String, _ arg: String) -> XCUIElement {
        safari.descendants(matching: .any).matching(NSPredicate(format: format, arg)).firstMatch
    }

    private func open(_ path: String) {
        XCUIDevice.shared.system.open(URL(string: site + path + "&t=\(Int(Date().timeIntervalSince1970))")!)
    }

    func testDownloadSelfTestAndHearTheCast() throws {
        continueAfterFailure = true
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        open("?view=library&diag=kokoro&mute=1")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 20), "Safari came forward")
        sleep(6)
        shot("01-library")

        // The step sheet shows once; after that the download lives in Library > Voices.
        let voices = button(safari, "label BEGINSWITH %@", "Voices")
        if voices.waitForExistence(timeout: 20) { voices.tap(); sleep(2) }
        shot("01b-voices-open")
        let download = button(safari, "label BEGINSWITH %@", "Download (")
        if download.waitForExistence(timeout: 20) {
            download.tap()
            shot("02-download-tapped")
            let done = Date().addingTimeInterval(480)
            var n = 0
            while Date() < done {
                sleep(20); n += 1
                shot(String(format: "03-wait-%02d", n))
                if safari.state != .runningForeground { shot("03-safari-left"); break }
                if button(safari, "label == %@", "Delete").exists || button(safari, "label == %@", "Try again").exists { break }
            }
            shot("04-verdict")
        } else {
            shot("02-no-download-button")
        }

        open("?read=\(play)&diag=kokoro&mute=1")
        sleep(8)
        shot("05-reader")
        let later = button(safari, "label == %@", "Not now")
        if later.waitForExistence(timeout: 8) { later.tap(); sleep(2) }
        let hear = button(safari, "label == %@", "Hear the cast")
        let along = button(safari, "label == %@", "Read along")
        if hear.waitForExistence(timeout: 10) { hear.tap() } else if along.exists { along.tap() }
        for i in 1...6 {
            sleep(6)
            shot(String(format: "06-reading-%02d", i))
        }
        XCTAssertEqual(safari.state, .runningForeground, "Safari still up (a killed tab reloads, a crashed Safari leaves)")
    }
}
