// Drives the installed CodeRing watch app by bundle id.
import XCTest

final class WatchDriverTests: XCTestCase {

    let ring = XCUIApplication(bundleIdentifier: "com.sebastianheredia.CodeRing.watchkitapp")

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Fresh launch → Home → START CODE → Cardiac Arrest → weight page.
    private func toWeightPage() {
        ring.terminate()
        sleep(1)
        ring.launch()
        _ = ring.wait(for: .runningForeground, timeout: 15)
        let start = ring.buttons.matching(
            NSPredicate(format: "label CONTAINS 'START'")).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 15), "home not shown")
        start.tap()
        let arrest = ring.buttons["Cardiac Arrest"]
        XCTAssertTrue(arrest.waitForExistence(timeout: 10), "protocol page not shown")
        arrest.tap()
        XCTAssertTrue(ring.buttons["Next"].waitForExistence(timeout: 10), "weight page not shown")
    }

    /// Focused: open the Shock-by-ring bloom FIRST so the sim's always-on
    /// hasn't dimmed, and hold it open for the external capture.
    func testV6_shock() throws {
        ring.terminate(); sleep(1); ring.launch()
        _ = ring.wait(for: .runningForeground, timeout: 15)
        ring.buttons.matching(NSPredicate(format: "label CONTAINS 'START'")).firstMatch.tap()
        ring.buttons["Cardiac Arrest"].tap()
        XCTAssertTrue(ring.buttons["Next"].waitForExistence(timeout: 10))
        ring.buttons["Next"].tap()
        let go = ring.buttons["GO"]
        XCTAssertTrue(go.waitForExistence(timeout: 8)); go.tap()
        ring.buttons.matching(NSPredicate(format: "label CONTAINS 'START CPR'")).firstMatch.tap()
        XCTAssertTrue(ring.buttons.matching(NSPredicate(format: "label BEGINSWITH 'NEXT PULSE CHECK'")).firstMatch.waitForExistence(timeout: 8))

        let f = ring.frame
        func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            ring.coordinate(withNormalizedOffset: CGVector(dx: x / f.width, dy: y / f.height))
        }
        // Shock anchor at (0.9w, 0.40h); bloom opens up-left. Hold 4s so the
        // external burst (0.25 s) catches Defib/Cardiovert before dimming.
        at(f.width * 0.82, f.height * 0.45)
            .press(forDuration: 0.5, thenDragTo: at(f.width * 0.82 - 44, f.height * 0.45 - 24),
                   withVelocity: .slow, thenHoldForDuration: 4.0)
        ring.terminate()
    }

    /// v6 tour: full-bleed home → the four color-coded menus (Rhythm/Code,
    /// Events w/ deep nesting, Volume/Support, Shock-by-ring) → colored chips.
    func testV6_menus() throws {
        ring.terminate(); sleep(1); ring.launch()
        _ = ring.wait(for: .runningForeground, timeout: 15)
        sleep(2)   // shot: home
        ring.buttons.matching(NSPredicate(format: "label CONTAINS 'START'")).firstMatch.tap()
        ring.buttons["Cardiac Arrest"].tap()
        XCTAssertTrue(ring.buttons["Next"].waitForExistence(timeout: 10))
        ring.buttons["Next"].tap()
        let go = ring.buttons["GO"]
        XCTAssertTrue(go.waitForExistence(timeout: 8)); go.tap()
        ring.buttons.matching(NSPredicate(format: "label CONTAINS 'START CPR'")).firstMatch.tap()
        let pc = ring.buttons.matching(NSPredicate(format: "label BEGINSWITH 'NEXT PULSE CHECK'")).firstMatch
        XCTAssertTrue(pc.waitForExistence(timeout: 8))
        sleep(2)   // shot: live w/ shock button by the ring

        let f = ring.frame
        func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            ring.coordinate(withNormalizedOffset: CGVector(dx: x / f.width, dy: y / f.height))
        }
        let ay = f.height - 36

        // 1 — Rhythm/Code (left): hold to bloom the 5 red meds, drag onto Epi
        // (index 0, arc -96°, r 74 → offset (-7.7, -73.6)) and release.
        let cx = f.width * 0.16
        at(cx, ay).press(forDuration: 0.5, thenDragTo: at(cx - 8, ay - 74),
                         withVelocity: .slow, thenHoldForDuration: 1.2)
        sleep(2)   // shot: EPI chip (red) on the left gutter

        // 2 — Volume/Support (right): hold to bloom, dwell 2.2s on Fluids
        // (index 0, arc -90°, r 84 → straight up, offset (0, -84)) to expand
        // Blood/10/20, then release on 20 mL/kg.
        let sx = f.width * 0.84
        at(sx, ay).press(forDuration: 0.5, thenDragTo: at(sx, ay - 84),
                         withVelocity: .slow, thenHoldForDuration: 3.4)
        sleep(2)   // shot: fluids expanded

        // 3 — Events (center): hold, dwell on Access (index 1 of 6, arc
        // -168+31.2= -136.8°, r 74 → offset (-54.1, -50.5)) to expand IV/IO.
        let ex = f.width * 0.5
        at(ex, ay).press(forDuration: 0.5, thenDragTo: at(ex - 54, ay - 50),
                         withVelocity: .slow, thenHoldForDuration: 3.4)
        sleep(2)   // shot: access → IV/IO

        // 4 — Shock (right of ring): hold to bloom Defib/Cardiovert.
        let shx = f.width * 0.9, shy = f.height * 0.40
        at(shx, shy).press(forDuration: 0.5, thenDragTo: at(shx - 40, shy - 20),
                           withVelocity: .slow, thenHoldForDuration: 2.5)
        sleep(2)   // shot: shock bloom

        ring.terminate()
    }

    /// v5 feedback tour: spaced home trio → IVF/BLOOD chips via tap-mode
    /// More submenu → uniform caps radial labels → compact timers sheet.
    func testV5_feedback() throws {
        ring.terminate()
        sleep(1)
        ring.launch()
        _ = ring.wait(for: .runningForeground, timeout: 15)
        sleep(3)   // shot: home with spaced satellites

        let start = ring.buttons.matching(
            NSPredicate(format: "label CONTAINS 'START'")).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()
        ring.buttons["Cardiac Arrest"].tap()
        XCTAssertTrue(ring.buttons["Next"].waitForExistence(timeout: 10))
        ring.buttons["Next"].tap()
        let go = ring.buttons["GO"]
        XCTAssertTrue(go.waitForExistence(timeout: 8))
        go.tap()
        let startCPR = ring.buttons.matching(
            NSPredicate(format: "label CONTAINS 'START CPR'")).firstMatch
        XCTAssertTrue(startCPR.waitForExistence(timeout: 8))
        startCPR.tap()
        sleep(1)

        let f = ring.frame
        func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            ring.coordinate(withNormalizedOffset: CGVector(dx: x / f.width, dy: y / f.height))
        }
        let ay = f.height - 40

        // Epi via hold-drag on MEDS.
        let mx = f.width * 0.84
        at(mx, ay).press(forDuration: 0.5,
                         thenDragTo: at(mx - 84, ay - 6),
                         withVelocity: .slow,
                         thenHoldForDuration: 1.5)
        sleep(1)

        // Chip abbreviations (IVF/BLOOD) are unit-tested in CodeCore —
        // synthetic taps can't open tap mode, so no UI path here.
        // EVENTS bloom labels: hold on dead space for the burst.
        let ex = f.width * 0.5
        at(ex, ay).press(forDuration: 0.5,
                         thenDragTo: at(ex + 55, ay - 50),
                         withVelocity: .slow,
                         thenHoldForDuration: 3.0)
        sleep(1)

        // SHOCK bloom labels (CARDIOVERSION rename) — hold shy of the arc.
        let sx = f.width * 0.16
        at(sx, ay).press(forDuration: 0.5,
                         thenDragTo: at(sx + 25, ay - 30),
                         withVelocity: .slow,
                         thenHoldForDuration: 2.5)
        sleep(1)

        // Timers sheet: second header button from the left.
        let headerButtons = ring.buttons.allElementsBoundByIndex.filter {
            $0.frame.minY >= 0 && $0.frame.midY < 60 && $0.isHittable
        }.sorted { $0.frame.minX < $1.frame.minX }
        XCTAssertTrue(headerButtons.count >= 2, "header buttons missing")
        headerButtons[1].tap()
        XCTAssertTrue(ring.staticTexts["EPINEPHRINE"].waitForExistence(timeout: 8),
                      "timers sheet missing epi row")
        // The live header behind the sheet also says TOTAL CODE — the
        // timers LIST must not add a second one.
        XCTAssertLessThanOrEqual(ring.staticTexts.matching(identifier: "TOTAL CODE").count, 1,
                                 "timers list should not repeat total code")
        sleep(3)   // shot: compact timers
        ring.buttons.matching(identifier: "Close").firstMatch.tap()
        sleep(1)

        // End & sync.
        let topButtons = ring.buttons.allElementsBoundByIndex.filter {
            $0.frame.minY >= 0 && $0.frame.midY < 60 && $0.isHittable
        }
        topButtons.max(by: { $0.frame.maxX < $1.frame.maxX })?.tap()
        let end = ring.buttons["End & review"]
        XCTAssertTrue(end.waitForExistence(timeout: 10))
        end.tap()
        sleep(4)
    }

    /// v4 feedback tour: home trio → centered AGE + yr toggle → live header
    /// (CYCLE chip, no demo, no idle EPI) → left med chips → Access expand
    /// with back-beside-✕ → wide shock arc → raised pulse overlay.
    func testV4_feedback() throws {
        ring.terminate()
        sleep(1)
        ring.launch()
        _ = ring.wait(for: .runningForeground, timeout: 15)
        sleep(3)   // shot: home trio

        let start = ring.buttons.matching(
            NSPredicate(format: "label CONTAINS 'START'")).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()
        let arrest = ring.buttons["Cardiac Arrest"]
        XCTAssertTrue(arrest.waitForExistence(timeout: 10))
        arrest.tap()
        XCTAssertTrue(ring.buttons["Next"].waitForExistence(timeout: 10))
        ring.buttons["Next"].tap()

        let go = ring.buttons["GO"]
        XCTAssertTrue(go.waitForExistence(timeout: 8))
        sleep(3)   // shot: AGE centered under GO

        // Age pad in YEARS: 3 yr → 36 mo.
        ring.buttons.matching(NSPredicate(format: "label CONTAINS 'AGE'")).firstMatch.tap()
        XCTAssertTrue(ring.buttons["Done"].waitForExistence(timeout: 8))
        ring.buttons["yr"].tap()
        ring.buttons["3"].tap()
        sleep(2)   // shot: pad with yr selected
        ring.buttons["Done"].tap()
        XCTAssertTrue(go.waitForExistence(timeout: 8))
        go.tap()

        let startCPR = ring.buttons.matching(
            NSPredicate(format: "label CONTAINS 'START CPR'")).firstMatch
        XCTAssertTrue(startCPR.waitForExistence(timeout: 8))
        startCPR.tap()
        let pc = ring.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'NEXT PULSE CHECK'")).firstMatch
        XCTAssertTrue(pc.waitForExistence(timeout: 8))
        sleep(3)   // shot: CYCLE chip header, age in patient line, no EPI text

        let f = ring.frame
        func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            ring.coordinate(withNormalizedOffset: CGVector(dx: x / f.width, dy: y / f.height))
        }
        let ay = f.height - 40

        // Epi → chip lands on the LEFT gutter.
        let mx = f.width * 0.84
        at(mx, ay).press(forDuration: 0.5,
                         thenDragTo: at(mx - 84, ay - 6),
                         withVelocity: .slow,
                         thenHoldForDuration: 2.0)
        sleep(2)   // shot: left EPI chip
        XCTAssertTrue(ring.staticTexts["EPI"].waitForExistence(timeout: 6),
                      "left med chip missing")

        // EVENTS → hold on Access ~3 s: 2 s dwell expands the limbs, back
        // pad appears NEXT TO the ✕. Release there logs nothing.
        let ex = f.width * 0.5
        // Access = index 2 of 6 (−105.6°, r 74) → offset (−19.9, −71.3).
        at(ex, ay).press(forDuration: 0.5,
                         thenDragTo: at(ex - 20, ay - 71),
                         withVelocity: .slow,
                         thenHoldForDuration: 4.6)
        sleep(1)

        // SHOCK → hold 1.2 s on Defib: expands NOTHING at <2 s; the burst
        // catches the wide three-bubble arc.
        let sx = f.width * 0.16
        // Defib = index 0 of 3 (−100°, r 72) → offset (−12.5, −70.9).
        at(sx, ay).press(forDuration: 0.5,
                         thenDragTo: at(sx - 12, ay - 71),
                         withVelocity: .slow,
                         thenHoldForDuration: 1.2)
        sleep(1)

        // Pulse check (20 s override) → raised overlay.
        sleep(10)
        XCTAssertTrue(pc.waitForExistence(timeout: 20))
        pc.tap()
        let resume = ring.buttons.matching(
            NSPredicate(format: "label CONTAINS 'RESUME CPR'")).firstMatch
        XCTAssertTrue(resume.waitForExistence(timeout: 8))
        sleep(3)   // shot: centered overlay
        resume.tap()

        // End & sync.
        let topButtons = ring.buttons.allElementsBoundByIndex.filter {
            $0.frame.minY >= 0 && $0.frame.midY < 60 && $0.isHittable
        }
        topButtons.max(by: { $0.frame.maxX < $1.frame.maxX })?.tap()
        let end = ring.buttons["End & review"]
        XCTAssertTrue(end.waitForExistence(timeout: 10))
        end.tap()
        sleep(4)
    }

    /// v3 setup tour: weight ⓘ help sheet → confirm with AGE chip → age pad.
    func testV3A_setupTour() throws {
        toWeightPage()
        sleep(2)   // shot: weight page with ⓘ

        let info = ring.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Info' OR label CONTAINS 'info'")).firstMatch
        XCTAssertTrue(info.waitForExistence(timeout: 8), "info button missing")
        info.tap()
        let close = ring.buttons.matching(identifier: "Close").firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 8), "help sheet missing")
        sleep(3)   // shot: help sheet
        ring.swipeUp()
        sleep(2)   // shot: help sheet bottom + Close
        close.tap()

        ring.buttons["Next"].tap()
        let go = ring.buttons["GO"]
        XCTAssertTrue(go.waitForExistence(timeout: 8))
        sleep(3)   // shot: confirm with AGE(tap) chip

        let age = ring.buttons.matching(
            NSPredicate(format: "label CONTAINS 'AGE'")).firstMatch
        XCTAssertTrue(age.exists, "age chip missing")
        age.tap()
        XCTAssertTrue(ring.buttons["Done"].waitForExistence(timeout: 8), "age pad missing")
        ring.buttons["2"].tap()
        ring.buttons["4"].tap()
        ring.buttons["Done"].tap()
        XCTAssertTrue(go.waitForExistence(timeout: 8))
        sleep(3)   // shot: confirm with AGE = 2 yr 0 mo
        ring.terminate()
    }

    /// v3 live tour: Start CPR gate → epi ring/chip → labeled blooms →
    /// shock hierarchy → circular pulse-check exits → quick weight edit.
    func testV3B_liveTour() throws {
        toWeightPage()
        ring.buttons["Next"].tap()
        let go = ring.buttons["GO"]
        XCTAssertTrue(go.waitForExistence(timeout: 10))
        go.tap()

        // 1 — Start CPR gate: full ring, no cycle countdown yet.
        let startCPR = ring.buttons.matching(
            NSPredicate(format: "label CONTAINS 'START CPR'")).firstMatch
        XCTAssertTrue(startCPR.waitForExistence(timeout: 8), "start CPR gate missing")
        sleep(3)   // shot: gate state
        startCPR.tap()
        let pc = ring.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'NEXT PULSE CHECK'")).firstMatch
        XCTAssertTrue(pc.waitForExistence(timeout: 8), "cycle did not start")
        sleep(2)   // shot: running, EPI idle (no inner ring)

        let f = ring.frame
        func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            ring.coordinate(withNormalizedOffset: CGVector(dx: x / f.width, dy: y / f.height))
        }
        let ay = f.height - 40

        // 2 — MEDS bloom: labeled arc, release on Epinephrine (index 0,
        // arc -176°, r 84 → offset (-83.8, -5.9) from the meds anchor).
        let mx = f.width * 0.84
        at(mx, ay).press(forDuration: 0.5,
                         thenDragTo: at(mx - 84, ay - 6),
                         withVelocity: .slow,
                         thenHoldForDuration: 2.5)
        sleep(2)   // shot: epi ring + med chip
        XCTAssertTrue(ring.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'EPIN'")).firstMatch
            .waitForExistence(timeout: 6), "med chip missing")

        // 3 — EVENTS bloom: hold on dead space so the burst captures every
        // label; release there logs nothing.
        let ex = f.width * 0.5
        at(ex, ay).press(forDuration: 0.5,
                         thenDragTo: at(ex + 30, ay - 40),
                         withVelocity: .slow,
                         thenHoldForDuration: 3.5)
        sleep(1)

        // 4 — SHOCK bloom: Defib parent (arc -78°, r 62 → offset (12.9, -60.6))
        // expands to the joule ladder; holding there oscillates expand/back,
        // which shows BOTH the children and the back pad to the burst.
        let sx = f.width * 0.16
        at(sx, ay).press(forDuration: 0.5,
                         thenDragTo: at(sx + 13, ay - 61),
                         withVelocity: .slow,
                         thenHoldForDuration: 3.0)
        sleep(1)

        // 5 — pulse check (20 s override): circular exits.
        sleep(14)
        XCTAssertTrue(pc.waitForExistence(timeout: 20))
        pc.tap()
        let resume = ring.buttons.matching(
            NSPredicate(format: "label CONTAINS 'RESUME CPR'")).firstMatch
        XCTAssertTrue(resume.waitForExistence(timeout: 8), "pulse overlay missing")
        sleep(3)   // shot: circular buttons
        resume.tap()

        // 6 — quick edit: patient chip → weight 12 → header updates.
        let chip = ring.buttons.matching(
            NSPredicate(format: "label CONTAINS 'ARREST'")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 8), "patient chip missing")
        chip.tap()
        let weightRow = ring.buttons.matching(
            NSPredicate(format: "label CONTAINS 'WEIGHT'")).firstMatch
        XCTAssertTrue(weightRow.waitForExistence(timeout: 8), "quick edit missing")
        sleep(2)   // shot: quick edit sheet
        weightRow.tap()
        XCTAssertTrue(ring.buttons["Done"].waitForExistence(timeout: 8))
        ring.buttons["1"].tap()
        ring.buttons["2"].tap()
        ring.buttons["Done"].tap()
        let updated = ring.buttons.matching(
            NSPredicate(format: "label CONTAINS '12.0 kg'")).firstMatch
        XCTAssertTrue(updated.waitForExistence(timeout: 8), "weight change not reflected")
        sleep(2)   // shot: 12.0 kg header

        // 7 — end & sync.
        let topButtons = ring.buttons.allElementsBoundByIndex.filter {
            $0.frame.minY >= 0 && $0.frame.midY < 60 && $0.isHittable
        }
        XCTAssertFalse(topButtons.isEmpty)
        topButtons.max(by: { $0.frame.maxX < $1.frame.maxX })?.tap()
        let end = ring.buttons["End & review"]
        XCTAssertTrue(end.waitForExistence(timeout: 10))
        end.tap()
        sleep(5)
    }

    /// v3 home/recent/settings tour. Cancels the destructive clear.
    func testV3C_homeRecentSettings() throws {
        ring.terminate()
        sleep(1)
        ring.launch()
        _ = ring.wait(for: .runningForeground, timeout: 15)
        sleep(3)   // shot: circular START CODE home

        let recent = ring.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Recent'")).firstMatch
        XCTAssertTrue(recent.waitForExistence(timeout: 10), "recent row missing")
        recent.tap()
        sleep(3)   // shot: tiles
        ring.swipeUp()
        sleep(2)   // shot: clear button
        let clear = ring.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Clear all'")).firstMatch
        XCTAssertTrue(clear.waitForExistence(timeout: 8), "clear button missing")
        clear.tap()
        // watchOS renders the cancel role as the ✕ pad top-left.
        let deleteBtn = ring.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Delete everything'")).firstMatch
        XCTAssertTrue(deleteBtn.waitForExistence(timeout: 8), "confirm dialog missing")
        sleep(3)   // shot: destructive confirm
        ring.buttons.matching(identifier: "Close").firstMatch.tap()
        sleep(1)

        // Back to home, then Settings.
        ring.terminate()
        sleep(1)
        ring.launch()
        _ = ring.wait(for: .runningForeground, timeout: 15)
        let settings = ring.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Settings'")).firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "settings row missing")
        settings.tap()
        sleep(3)   // shot: display + metronome sections
        ring.swipeUp()
        sleep(2)   // shot: haptics section
        ring.swipeUp()
        sleep(2)   // shot: haptic pickers
    }

    /// Park on the manual weight page (strip + crown + tap hint visible).
    func testWA_weightPage() throws {
        toWeightPage()
        sleep(1)
    }

    /// Park with the number pad sheet open.
    func testWB_keypad() throws {
        toWeightPage()
        ring.staticTexts["10.0"].tap()
        XCTAssertTrue(ring.buttons["Done"].waitForExistence(timeout: 8), "keypad did not open")
        // Type 12.5 to show the display in action.
        ring.buttons["1"].tap()
        ring.buttons["2"].tap()
        ring.buttons["."].tap()
        ring.buttons["5"].tap()
        sleep(1)
    }

    /// Park on the Broselow wheel (range labels on every wedge).
    func testWC_broselow() throws {
        toWeightPage()
        ring.buttons["Broselow"].tap()
        sleep(1)
    }

    /// Park on the redesigned confirm screen (GO center, chips orbiting).
    func testWD_ready() throws {
        toWeightPage()
        ring.buttons["Next"].tap()
        XCTAssertTrue(ring.buttons["GO"].waitForExistence(timeout: 10), "confirm page not shown")
        sleep(1)
    }

    /// Full live-screen choreography — run with a 20 s cycle override so the
    /// pulse-check states arrive quickly. Screenshots are taken externally
    /// while this walks: fresh live → overdue (negative red) → pulse check
    /// overlay (past 10 s) → resume → timers sheet.
    func testWE_liveFlow() throws {
        toWeightPage()
        ring.buttons["Next"].tap()
        let go = ring.buttons["GO"]
        XCTAssertTrue(go.waitForExistence(timeout: 10))
        go.tap()
        sleep(6)    // fresh live screen

        sleep(26)   // 20 s cycle → well past due, countdown negative + red

        // The ring center becomes the pulse-check button once due.
        let pc = ring.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'NEXT PULSE CHECK'")).firstMatch
        XCTAssertTrue(pc.waitForExistence(timeout: 10), "pulse check button missing")
        pc.tap()
        sleep(14)   // overlay ticks past the 10 s hands-off target (red)

        let resume = ring.buttons["RESUME CPR"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5), "overlay missing resume")
        resume.tap()
        sleep(4)    // fresh cycle 2

        // Timers sheet (timer symbol renders with label "Timer" on watchOS).
        if ring.buttons["Timer"].waitForExistence(timeout: 3) {
            ring.buttons["Timer"].tap()
        } else {
            // fall back: second header button from the left
            let candidates = ring.buttons.allElementsBoundByIndex.filter { $0.frame.midY < 40 }
            candidates.sorted { $0.frame.minX < $1.frame.minX }.dropFirst().first?.tap()
        }
        sleep(6)    // timers sheet up
    }

    /// ROSC flow: pulse found → post-ROSC screen (vitals ring, RE-ARREST,
    /// HANDOFF) → handoff sheet → re-arrest back to CPR → end & sync.
    /// Run with the 20 s cycle override so the pulse check arrives fast.
    func testWG_roscFlow() throws {
        toWeightPage()
        ring.buttons["Next"].tap()
        let go = ring.buttons["GO"]
        XCTAssertTrue(go.waitForExistence(timeout: 10))
        go.tap()

        sleep(24)   // 20 s cycle → check due
        let pc = ring.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'NEXT PULSE CHECK'")).firstMatch
        XCTAssertTrue(pc.waitForExistence(timeout: 15), "pulse check button missing")
        pc.tap()

        let found = ring.buttons["PULSE FOUND"]
        XCTAssertTrue(found.waitForExistence(timeout: 8), "overlay missing pulse found")
        found.tap()

        // Post-ROSC screen: vitals ring + the two capsules.
        let reArrest = ring.buttons["RE-ARREST"]
        XCTAssertTrue(reArrest.waitForExistence(timeout: 8), "post-ROSC screen not shown")
        XCTAssertTrue(ring.buttons["HANDOFF"].exists)
        sleep(4)    // screenshot window: post-ROSC screen

        ring.buttons["HANDOFF"].tap()
        XCTAssertTrue(ring.staticTexts["TOTAL CODE"].waitForExistence(timeout: 8),
                      "handoff sheet not shown")
        sleep(4)    // screenshot window: handoff sheet

        // Close the sheet (system X, top-left), then re-arrest.
        let close = ring.buttons.matching(identifier: "Close").firstMatch
        if close.exists {
            close.tap()
        } else {
            ring.coordinate(withNormalizedOffset: CGVector(dx: 0.13, dy: 0.08)).tap()
        }
        XCTAssertTrue(reArrest.waitForExistence(timeout: 8))
        reArrest.tap()

        // Back in the CPR flow: pulse-check center + fresh cycle.
        XCTAssertTrue(pc.waitForExistence(timeout: 8), "re-arrest did not return to CPR")
        sleep(4)    // screenshot window: back in CPR

        // End & sync.
        let topButtons = ring.buttons.allElementsBoundByIndex.filter {
            $0.frame.minY >= 0 && $0.frame.midY < 60 && $0.isHittable
        }
        XCTAssertFalse(topButtons.isEmpty, "no header buttons found")
        topButtons.max(by: { $0.frame.maxX < $1.frame.maxX })?.tap()
        let end = ring.buttons["End & review"]
        XCTAssertTrue(end.waitForExistence(timeout: 10))
        end.tap()
        sleep(5)
    }

    /// Hover name tag: hold-drag onto a bubble and dwell — the label capsule
    /// should ride above it (captured by the external screenshot burst).
    func testWH_hoverLabel() throws {
        toWeightPage()
        ring.buttons["Next"].tap()
        let go = ring.buttons["GO"]
        XCTAssertTrue(go.waitForExistence(timeout: 10))
        go.tap()
        sleep(3)

        let f = ring.frame
        func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            ring.coordinate(withNormalizedOffset: CGVector(dx: x / f.width, dy: y / f.height))
        }
        let ax = f.width * 0.5
        let ay = f.height - 40
        // Hold at the EVENTS anchor, drag to Rhythm check, dwell there 4 s
        // so the burst can catch the name tag, then release (logs it).
        at(ax, ay).press(forDuration: 0.5,
                         thenDragTo: at(ax - 54, ay - 51),
                         withVelocity: .slow,
                         thenHoldForDuration: 4.0)
        sleep(2)
        ring.terminate()   // abandon this demo code — nothing persists
    }

    /// Radial-menu semantics: releasing on a LEAF logs it; releasing on a
    /// PARENT (Access) without picking a child logs nothing. Ends the code
    /// so the synced session on the phone is the evidence.
    func testWF_radialSemantics() throws {
        toWeightPage()
        ring.buttons["Next"].tap()
        let go = ring.buttons["GO"]
        XCTAssertTrue(go.waitForExistence(timeout: 10))
        go.tap()
        sleep(3)

        let f = ring.frame
        func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            ring.coordinate(withNormalizedOffset: CGVector(dx: x / f.width, dy: y / f.height))
        }
        let ax = f.width * 0.5
        let ay = f.height - 40
        // Bloom arc: -168°…-12°, radius 74, six items.
        // index 1 = Rhythm check (leaf) at -136.8°; index 3 = Access (parent) at -74.4°.
        let anchor = at(ax, ay)
        anchor.press(forDuration: 0.5, thenDragTo: at(ax - 54, ay - 51))
        sleep(2)
        anchor.press(forDuration: 0.5, thenDragTo: at(ax + 20, ay - 71))
        sleep(2)

        // End the code (flag → End & review) so it syncs to the phone.
        let flagByLabel = ring.buttons["Flag"]
        if flagByLabel.exists {
            flagByLabel.tap()
        } else {
            let topButtons = ring.buttons.allElementsBoundByIndex.filter {
                $0.frame.minY >= 0 && $0.frame.midY < 40 && $0.isHittable
            }
            topButtons.max(by: { $0.frame.maxX < $1.frame.maxX })?.tap()
        }
        let end = ring.buttons["End & review"]
        XCTAssertTrue(end.waitForExistence(timeout: 10), "end confirmation did not appear")
        end.tap()
        sleep(5)
    }

    /// Step B (sync verification): run a short code start→finish.
    func testB_runQuickCode() throws {
        toWeightPage()
        ring.buttons["Next"].tap()
        let go = ring.buttons["GO"]
        XCTAssertTrue(go.waitForExistence(timeout: 10))
        go.tap()
        sleep(6)

        let flagByLabel = ring.buttons["Flag"]
        if flagByLabel.exists {
            flagByLabel.tap()
        } else {
            let topButtons = ring.buttons.allElementsBoundByIndex.filter {
                $0.frame.minY >= 0 && $0.frame.midY < 60 && $0.isHittable
            }
            guard let flag = topButtons.max(by: { $0.frame.maxX < $1.frame.maxX }) else {
                XCTFail("no top-strip buttons found to end the code"); return
            }
            flag.tap()
        }

        let end = ring.buttons["End & review"]
        XCTAssertTrue(end.waitForExistence(timeout: 10), "end confirmation did not appear")
        end.tap()
        sleep(5)
    }
}
