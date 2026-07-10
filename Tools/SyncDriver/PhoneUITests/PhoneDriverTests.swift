// Drives the installed CodeRing iPhone app by bundle id.
// Each test is one verification step; run them individually with -only-testing.
import XCTest

final class PhoneDriverTests: XCTestCase {

    let ring = XCUIApplication(bundleIdentifier: "com.sebastianheredia.CodeRing")

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Step A: create a distinctive marker (PALS Copy), flip a setting, send library to watch.
    func testA_duplicateSetToggleSoundAndSend() throws {
        ring.activate()
        XCTAssertTrue(ring.wait(for: .runningForeground, timeout: 10))

        // Drugs tab → "+" menu → Duplicate PALS Default (skip if already there)
        ring.tabBars.buttons["Drugs"].tap()
        if !ring.staticTexts["PALS Copy"].waitForExistence(timeout: 2) {
            let add = ring.navigationBars.buttons["Add"].firstMatch
            XCTAssertTrue(add.waitForExistence(timeout: 5), "Add button not found")
            add.tap()
            let dup = ring.buttons["Duplicate PALS Default"]
            XCTAssertTrue(dup.waitForExistence(timeout: 5), "menu did not open")
            dup.tap()
            XCTAssertTrue(ring.staticTexts["PALS Copy"].waitForExistence(timeout: 5),
                          "duplicated set not visible")
        }

        // Settings tab → Metronome sound ON
        ring.tabBars.buttons["Settings"].tap()
        let row = ring.switches["Metronome sound"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        if row.switches.firstMatch.exists {
            row.switches.firstMatch.tap()
        } else {
            row.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        XCTAssertEqual(row.value as? String, "1", "toggle did not flip on")

        // Home tab → Send library to Watch
        ring.tabBars.buttons["Home"].tap()
        let send = ring.buttons["Send library to Watch"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        send.tap()
        XCTAssertTrue(ring.buttons["Sent to Watch"].waitForExistence(timeout: 5),
                      "send button never showed its sent state")
        sleep(4)   // give WCSession time to deliver
    }

    /// Step C: after the watch ran a code, the session must appear on the phone.
    func testC_assertSessionArrivedFromWatch() throws {
        ring.activate()
        XCTAssertTrue(ring.wait(for: .runningForeground, timeout: 10))
        ring.tabBars.buttons["Home"].tap()
        XCTAssertTrue(ring.staticTexts["LAST CODE"].waitForExistence(timeout: 15),
                      "LAST CODE card never appeared — session did not arrive")
        ring.tabBars.buttons["History"].tap()
        sleep(2)   // settle for the screenshot taken right after
    }

    /// Step D (probe): resend the library — receiver must replace, not append.
    func testD_resendLibrary() throws {
        ring.activate()
        XCTAssertTrue(ring.wait(for: .runningForeground, timeout: 10))
        ring.tabBars.buttons["Home"].tap()
        let send = ring.buttons["Send library to Watch"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        send.tap()
        XCTAssertTrue(ring.buttons["Sent to Watch"].waitForExistence(timeout: 5))
        sleep(4)
    }

    /// History timeline: open the latest session and flip the time-display
    /// toggle (offset-into-code ↔ local wall time).
    func testF_historyTimeToggle() throws {
        ring.activate()
        XCTAssertTrue(ring.wait(for: .runningForeground, timeout: 10))
        ring.tabBars.buttons["History"].tap()
        let first = ring.cells.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 8), "no sessions in history")
        first.tap()

        let toggle = ring.buttons["Toggle time display"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 8), "time toggle not found")
        sleep(2)   // screenshot window: offset stamps
        toggle.tap()
        XCTAssertTrue(ring.staticTexts["TIMELINE — LOCAL TIME"].waitForExistence(timeout: 5),
                      "header did not flip to local time")
        sleep(3)   // screenshot window: wall-clock stamps
    }

    /// Step E (probe): bump the metronome bpm and send settings while the
    /// watch app is dead — exercises the queued transferUserInfo fallback.
    func testE_bumpBpmAndSendSettings() throws {
        ring.activate()
        XCTAssertTrue(ring.wait(for: .runningForeground, timeout: 10))
        ring.tabBars.buttons["Settings"].tap()

        let stepper = ring.steppers.firstMatch
        let inc = stepper.exists ? stepper.buttons["Increment"]
                                 : ring.buttons["Increment"].firstMatch
        XCTAssertTrue(inc.waitForExistence(timeout: 5), "stepper increment not found")
        inc.tap()
        XCTAssertTrue(ring.staticTexts["Metronome: 115 bpm"].waitForExistence(timeout: 5),
                      "bpm did not change to 115")

        ring.buttons["Send settings to Watch"].tap()
        sleep(4)
    }
}
