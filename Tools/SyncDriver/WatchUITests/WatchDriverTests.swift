// Drives the installed CodeRing watch app by bundle id.
import XCTest

/// Anchor-puck centres in SCREEN points, mirroring
/// `CodeCore/UI/WatchLayout.swift`. This project cannot import CodeCore, so
/// the values are copied — **when a puck moves in WatchLayout, move it here.**
///
/// They stopped being proportional on 2026-08-24, when the live screen went
/// to absolute placement and a fourth puck (Shock) split the bottom row. The
/// old `f.width * 0.5, f.height − 40` for Events now lands 26 pt from the
/// Events puck and 26 pt from the Shock puck — in the gap, hitting neither,
/// which reads exactly like "the menu is broken" when it is the test that is.
enum Pucks {
    static let meds   = CGPoint(x: 30,  y: 210)
    static let events = CGPoint(x: 74,  y: 196)
    static let shock  = CGPoint(x: 124, y: 196)
    static let fluids = CGPoint(x: 170, y: 210)
    /// Ø42 — a tap has to land within 21 pt of a centre.
    static let diameter: CGFloat = 42
}

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
        // 2026-08-22: START now lands straight on WEIGHT — the code-type
        // picker moved off the startup path (Confirm/Adjust reach it). Older
        // recordings still expect the picker, so tolerate either.
        let arrest = ring.buttons["Cardiac Arrest"]
        if arrest.waitForExistence(timeout: 3) { arrest.tap() }
        XCTAssertTrue(ring.buttons["Next"].waitForExistence(timeout: 10), "weight page not shown")
    }

    /// v13: five auto-created timers (Sebastian's atropine/amio/blood/IVF/
    /// defib report, 2026-07-22) — every chip must be FULLY visible, never
    /// under the anchor pucks (bottom) or the shock bolt (right edge).
    /// Frame assertions run LAST so the screenshot burst captures the state
    /// either way. Run on the 45 mm Series 9 sim ONLY (editor-geo targets).
    func testV13_fiveChipsClearOfAnchors() throws {
        ring.terminate(); sleep(1); ring.launch()
        _ = ring.wait(for: .runningForeground, timeout: 15)
        ring.buttons.matching(NSPredicate(format: "label CONTAINS 'START'")).firstMatch.tap()
        let skip = ring.buttons["SKIP"]
        XCTAssertTrue(skip.waitForExistence(timeout: 8)); skip.tap()
        let startCPR = ring.buttons.matching(
            NSPredicate(format: "label CONTAINS 'START CPR'")).firstMatch
        XCTAssertTrue(startCPR.waitForExistence(timeout: 8)); startCPR.tap()
        sleep(1)

        let f = ring.frame
        func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            ring.coordinate(withNormalizedOffset: CGVector(dx: x / f.width, dy: y / f.height))
        }
        /// Press an anchor, drag to a target, hold, release (leaf logs).
        func give(fromX ax: CGFloat, fromY ay: CGFloat,
                  toX tx: CGFloat, toY ty: CGFloat, seconds: Double = 0.6) {
            at(ax, ay).press(forDuration: 0.5, thenDragTo: at(tx, ty),
                             withVelocity: .slow, thenHoldForDuration: seconds)
            usleep(600_000)
        }
        let sideY = f.height - 36          // side pucks (caption-less, lowered)
        let cx = f.width * 0.15, vx = f.width * 0.85
        // Anchors are placed in GeometryReader space (194×191, top inset
        // dy below the window top) — convert like testV12 does.
        let dy = f.height - 191
        let shockX = f.width - 23, shockY = 40.1 + dy   // bolt at 0.21 × geo

        // Five ROOT leaves only: a motionless synthetic hold stops sending
        // drag events, so sub-fan leaves (blood, fluid rungs, defib rungs)
        // can't be re-hovered after a dwell-expand — the chip GRID doesn't
        // care which items fill it, only the count and order. Cardiovert is
        // the shock-category stand-in for a defib rung.
        give(fromX: cx, fromY: sideY, toX: cx + 38.5, toY: sideY - 101)   // atropine
        give(fromX: cx, fromY: sideY, toX: cx + 102, toY: sideY - 35)     // amiodarone
        give(fromX: vx, fromY: sideY, toX: vx - 38.5, toY: sideY - 101)   // dextrose
        give(fromX: vx, fromY: sideY, toX: vx - 78, toY: sideY - 75)      // calcium
        give(fromX: shockX, fromY: shockY, toX: 142, toY: 147)            // cardiovert

        for chip in ["ATRO", "AMIO", "DEX", "CA", "CVERT"] {
            XCTAssertTrue(ring.staticTexts[chip].waitForExistence(timeout: 6),
                          "\(chip) chip missing")
        }
        sleep(6)   // shot: all five chips, clocks running

        // 6th item fits the 4+2 grid; the 7th (epi, protected) evicts the
        // stalest chip (atropine).
        give(fromX: vx, fromY: sideY, toX: vx - 102, toY: sideY - 35)
        XCTAssertTrue(ring.staticTexts["BICARB"].waitForExistence(timeout: 6),
                      "BICARB chip missing")
        XCTAssertTrue(ring.staticTexts["ATRO"].exists, "sixth chip should not evict")
        sleep(4)   // shot: six chips (4 + 2)
        give(fromX: cx, fromY: sideY, toX: cx - 8, toY: sideY - 108)
        XCTAssertTrue(ring.staticTexts["EPI"].waitForExistence(timeout: 6), "EPI chip missing")
        XCTAssertFalse(ring.staticTexts["ATRO"].exists, "stalest chip was not evicted")
        sleep(8)   // shot: post-eviction six chips, epi ring live

        // Geometry: every chip row (abbrev text + the clock line under it)
        // must clear the anchor pucks below and the shock bolt at top-right.
        let puckTop = sideY - 22          // caption-less puck circle top, 1 pt margin
        let boltBottom = shockY + 23      // bolt circle bottom edge
        for chip in ["EPI", "AMIO", "DEX", "CA", "CVERT", "BICARB"] {
            let fr = ring.staticTexts[chip].frame
            XCTAssertLessThanOrEqual(fr.maxY + 13, puckTop,
                                     "\(chip) chip row reaches into the anchor pucks")
            if fr.midX > f.width / 2 {
                XCTAssertGreaterThanOrEqual(fr.minY, boltBottom,
                                            "\(chip) chip sits under the shock bolt")
            }
        }
        sleep(2)
    }

    /// v14: tap-only menus (Settings → Menus). A HOLD on an anchor opens the
    /// fan in TAP mode and releasing keeps it open; bubbles are real buttons
    /// that log on tap. Restores the toggle afterward so hold-drag tests
    /// keep working.
    func testV14_tapOnlyMenus() throws {
        func setTapOnly(_ on: Bool) {
            ring.terminate(); sleep(1); ring.launch()
            _ = ring.wait(for: .runningForeground, timeout: 15)
            let settingsBtn = ring.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] 'settings'")).firstMatch
            XCTAssertTrue(settingsBtn.waitForExistence(timeout: 10), "settings orbit missing")
            settingsBtn.tap()
            sleep(1)
            // Form rows lazy-load: scroll until the toggle exists. It may
            // surface as a switch or a generic labeled element.
            let byLabel = NSPredicate(format: "label CONTAINS 'Tap-only'")
            func findToggle() -> XCUIElement? {
                let el = ring.descendants(matching: .any).matching(byLabel).firstMatch
                return el.exists ? el : nil
            }
            // Full swipes overshoot the short Menus section and its rows get
            // recycled out of the tree — creep down in half-screen drags,
            // querying between each.
            func nudgeUp() {
                let a = ring.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
                let b = ring.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
                a.press(forDuration: 0.05, thenDragTo: b, withVelocity: .slow,
                        thenHoldForDuration: 0.25)
            }
            var toggle = findToggle()
            var tries = 0
            while toggle == nil, tries < 8 {
                nudgeUp(); usleep(400_000)
                toggle = findToggle(); tries += 1
            }
            guard let toggle else {
                print("SETTINGS-HIERARCHY >>> \(ring.debugDescription)")
                XCTFail("tap-only toggle missing"); return
            }
            // The row surfaces as a Cell with no value — the embedded Switch
            // carries the real state. Verify every flip: a silent no-op here
            // leaves the sim in the wrong mode for every hold-drag test.
            func readIsOn(_ el: XCUIElement) -> Bool? {
                let sw = el.switches.firstMatch
                let raw = ((sw.exists ? sw.value : el.value) as? String)?.lowercased()
                return raw.map { $0 == "1" || $0 == "on" || $0 == "true" }
            }
            guard let isOn = readIsOn(toggle) else {
                XCTFail("tap-only toggle value unreadable"); return
            }
            if isOn != on {
                toggle.tap(); sleep(1)
                XCTAssertEqual(readIsOn(toggle), on, "toggle did not flip")
            }
        }
        setTapOnly(true)

        ring.terminate(); sleep(1); ring.launch()   // reload proves persistence
        _ = ring.wait(for: .runningForeground, timeout: 15)
        ring.buttons.matching(NSPredicate(format: "label CONTAINS 'START'")).firstMatch.tap()
        let skip = ring.buttons["SKIP"]
        XCTAssertTrue(skip.waitForExistence(timeout: 8)); skip.tap()
        let startCPR = ring.buttons.matching(
            NSPredicate(format: "label CONTAINS 'START CPR'")).firstMatch
        XCTAssertTrue(startCPR.waitForExistence(timeout: 8)); startCPR.tap()
        sleep(1)

        let f = ring.frame
        func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            ring.coordinate(withNormalizedOffset: CGVector(dx: x / f.width, dy: y / f.height))
        }
        let sideY = f.height - 36
        let cx = f.width * 0.15
        let dy = f.height - 191
        let shockX = f.width - 23, shockY = 40.1 + dy   // bolt at 0.21 × geo

        // Hold the rhythm anchor and RELEASE in place: the fan must open in
        // tap mode and survive the release (the readout hint proves it).
        at(cx, sideY).press(forDuration: 0.8)
        XCTAssertTrue(ring.staticTexts["Tap to log"].waitForExistence(timeout: 4),
                      "tap-mode fan did not open (or closed on release)")
        sleep(2)   // shot: tap fan open, finger up
        at(cx - 8, sideY - 108).tap()   // epi bubble is a real Button now
        XCTAssertTrue(ring.staticTexts["EPI"].waitForExistence(timeout: 6),
                      "tap on epi bubble did not log")
        XCTAssertFalse(ring.staticTexts["Tap to log"].exists,
                       "fan should close after a leaf tap")

        // Shock anchor: in tap-only the fan opens instead of quick-logging;
        // Cardiovert (fixed at geo 142,96) logs by tap.
        at(shockX, shockY).press(forDuration: 0.8)
        XCTAssertTrue(ring.staticTexts["Tap to log"].waitForExistence(timeout: 4),
                      "shock fan did not open in tap mode")
        at(142, 96 + dy).tap()
        XCTAssertTrue(ring.staticTexts["CVERT"].waitForExistence(timeout: 6),
                      "tap on cardiovert bubble did not log")
        sleep(2)   // shot: EPI + CVERT chips via taps only

        setTapOnly(false)
    }

    /// v15: undo-last-entry from BOTH mid-code sheets. Undoing a med drops
    /// its chip and timer immediately; the row hides once only structural
    /// records (CPR start etc.) remain.
    func testV15_undoLastEntry() throws {
        ring.terminate(); sleep(1); ring.launch()
        _ = ring.wait(for: .runningForeground, timeout: 15)
        ring.buttons.matching(NSPredicate(format: "label CONTAINS 'START'")).firstMatch.tap()
        let skip = ring.buttons["SKIP"]
        XCTAssertTrue(skip.waitForExistence(timeout: 8)); skip.tap()
        let startCPR = ring.buttons.matching(
            NSPredicate(format: "label CONTAINS 'START CPR'")).firstMatch
        XCTAssertTrue(startCPR.waitForExistence(timeout: 8)); startCPR.tap()
        sleep(1)

        let f = ring.frame
        func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            ring.coordinate(withNormalizedOffset: CGVector(dx: x / f.width, dy: y / f.height))
        }
        let sideY = f.height - 36
        let cx = f.width * 0.15
        func give(toX tx: CGFloat, toY ty: CGFloat) {
            at(cx, sideY).press(forDuration: 0.5, thenDragTo: at(tx, ty),
                                withVelocity: .slow, thenHoldForDuration: 0.6)
            usleep(600_000)
        }
        give(toX: cx + 38.5, toY: sideY - 101)   // atropine
        give(toX: cx + 102, toY: sideY - 35)     // amiodarone
        XCTAssertTrue(ring.staticTexts["ATRO"].waitForExistence(timeout: 6))
        XCTAssertTrue(ring.staticTexts["AMIO"].exists)

        func headerButtons() -> [XCUIElement] {
            ring.buttons.allElementsBoundByIndex.filter {
                $0.frame.minY >= 0 && $0.frame.midY < 40 && $0.isHittable
            }.sorted { $0.frame.minX < $1.frame.minX }
        }
        let undoBtn = ring.buttons.matching(
            NSPredicate(format: "label CONTAINS 'UNDO LAST'")).firstMatch

        // Timers sheet (2nd header button): undo the amio.
        let hdr = headerButtons()
        XCTAssertGreaterThanOrEqual(hdr.count, 2, "header buttons missing")
        hdr[1].tap()
        XCTAssertTrue(undoBtn.waitForExistence(timeout: 8), "undo row missing in Timers")
        sleep(2)   // shot: undo row above the timer list
        undoBtn.tap()
        sleep(1)
        ring.buttons.matching(identifier: "Close").firstMatch.tap()
        XCTAssertFalse(ring.staticTexts["AMIO"].waitForExistence(timeout: 2),
                       "amio chip should be gone after undo")
        XCTAssertTrue(ring.staticTexts["ATRO"].exists, "atropine must remain")

        // Log sheet (1st header button): undo the atropine there.
        sleep(1)
        headerButtons().first?.tap()
        XCTAssertTrue(undoBtn.waitForExistence(timeout: 8), "undo row missing in Log")
        undoBtn.tap()
        sleep(1)
        XCTAssertFalse(undoBtn.exists,
                       "row must hide once only structural records remain")
        ring.buttons.matching(identifier: "Close").firstMatch.tap()
        XCTAssertFalse(ring.staticTexts["ATRO"].waitForExistence(timeout: 2),
                       "atropine chip should be gone after undo")
        sleep(2)
    }

    /// v12: Sebastian's hand-placed fan layouts (FanLayoutOverrides).
    /// Holds each overridden fan open ~3 s for the screenshot burst.
    /// Coordinates: editor geo (198×191) → test ≈ same x, y + (frame.height
    /// − 191). The live GeometryReader is really 194×191 (2 pt side insets),
    /// so drag targets land ≤5 pt off live parents — well inside the 40 pt
    /// hit radius. Run on the 45 mm Series 9 sim ONLY.
    func testV12_fixedLayouts() throws {
        ring.terminate(); sleep(1); ring.launch()
        _ = ring.wait(for: .runningForeground, timeout: 15)
        ring.buttons.matching(NSPredicate(format: "label CONTAINS 'START'")).firstMatch.tap()
        let skip = ring.buttons["SKIP"]
        XCTAssertTrue(skip.waitForExistence(timeout: 8)); skip.tap()
        let startCPR = ring.buttons.matching(
            NSPredicate(format: "label CONTAINS 'START CPR'")).firstMatch
        XCTAssertTrue(startCPR.waitForExistence(timeout: 8)); startCPR.tap()
        sleep(1)

        let f = ring.frame
        let dy = f.height - 191          // geo-y → test-y
        func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            ring.coordinate(withNormalizedOffset: CGVector(dx: x / f.width, dy: y / f.height))
        }
        /// Press an anchor, drag to a geo-space target, hold there.
        func hold(fromX ax: CGFloat, fromY ay: CGFloat,
                  toGeoX gx: CGFloat, toGeoY gy: CGFloat, seconds: Double) {
            at(ax, ay).press(forDuration: 0.5, thenDragTo: at(gx, gy + dy),
                             withVelocity: .slow, thenHoldForDuration: seconds)
            usleep(700_000)
        }
        let shockX = f.width * 0.885, shockY = 45.8 + dy   // shock anchor
        let eventsX = Pucks.events.x, eventsY = Pucks.events.y   // see Pucks
        let volX = f.width * 0.85, volY = f.height - 46

        // 1 · shock root fan: Defib top-center (116,38), Cardiovert (142,96).
        // Held at empty geo (90,130) — >40 pt from both, so nothing fires.
        hold(fromX: shockX, fromY: shockY, toGeoX: 90, toGeoY: 130, seconds: 3.0)

        // 2 · defib rungs fan off the FIXED Defib bubble (dwell 1 s → expand).
        hold(fromX: shockX, fromY: shockY, toGeoX: 116, toGeoY: 38, seconds: 3.6)

        // 3–6 · events sub-fans at their editor parents.
        hold(fromX: eventsX, fromY: eventsY, toGeoX: 37, toGeoY: 110, seconds: 3.6)  // access
        hold(fromX: eventsX, fromY: eventsY, toGeoX: 76, toGeoY: 83, seconds: 3.6)   // airway
        hold(fromX: eventsX, fromY: eventsY, toGeoX: 123, toGeoY: 83, seconds: 3.6)  // comms
        hold(fromX: eventsX, fromY: eventsY, toGeoX: 161, toGeoY: 110, seconds: 3.6) // temp pads

        // 7–8 · volume sub-fans.
        hold(fromX: volX, fromY: volY, toGeoX: 174, toGeoY: 37, seconds: 3.6)        // fluids
        hold(fromX: volX, fromY: volY, toGeoX: 61, toGeoY: 159, seconds: 3.6)        // more

        // Nothing may have logged: every hold released over a parent or gap.
        XCTAssertFalse(ring.staticTexts["CARD"].exists, "cardiovert fired accidentally")
        sleep(2)
    }

    /// v11: chip cap + epi-protected eviction, collision-free columns,
    /// opposite back/✕ pads, art-line access branch, ROSC 3+3 chips.
    func testV11_chipCapAndRosc() throws {
        ring.terminate(); sleep(1); ring.launch()
        _ = ring.wait(for: .runningForeground, timeout: 15)
        ring.buttons.matching(NSPredicate(format: "label CONTAINS 'START'")).firstMatch.tap()
        let skip = ring.buttons["SKIP"]
        XCTAssertTrue(skip.waitForExistence(timeout: 8)); skip.tap()
        let startCPR = ring.buttons.matching(
            NSPredicate(format: "label CONTAINS 'START CPR'")).firstMatch
        XCTAssertTrue(startCPR.waitForExistence(timeout: 8)); startCPR.tap()
        sleep(1)

        let f = ring.frame
        func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            ring.coordinate(withNormalizedOffset: CGVector(dx: x / f.width, dy: y / f.height))
        }
        let sideY = f.height - 46, centerY = Pucks.events.y      // see Pucks
        let cx = f.width * 0.15, vx = f.width * 0.85

        // Seven distinct items: 5 rhythm/code meds + dextrose + calcium.
        // Eviction must drop ATROPINE (stalest after protected epi).
        let targets: [(CGFloat, CGFloat, CGFloat)] = [
            (cx, cx - 8, -108),    // epi
            (cx, cx + 38.5, -101), // atropine
            (cx, cx + 78, -75),    // adenosine
            (cx, cx + 102, -35),   // amiodarone
            (cx, cx + 107, 12),    // lidocaine
            (vx, vx - 38.5, -101), // dextrose
            (vx, vx - 78, -75)     // calcium
        ]
        for (ax, tx, dy) in targets {
            at(ax, sideY).press(forDuration: 0.5, thenDragTo: at(tx, sideY + dy),
                                withVelocity: .slow, thenHoldForDuration: 0.6)
            usleep(400_000)
        }
        XCTAssertTrue(ring.staticTexts["CA"].waitForExistence(timeout: 6), "CA chip missing")
        XCTAssertTrue(ring.staticTexts["EPI"].exists, "protected EPI chip missing")
        XCTAssertFalse(ring.staticTexts["ATRO"].exists, "stalest chip was not evicted")
        sleep(3)   // shot: 4 left + 2 right, clear of SHOCK

        // Access → art line fan (opposite back/✕ pads for the burst).
        at(f.width * 0.5, centerY).press(forDuration: 0.5,
                                         thenDragTo: at(f.width * 0.5 - 61.5, centerY - 44.7),
                                         withVelocity: .slow, thenHoldForDuration: 3.2)
        sleep(1)

        // ROSC via pulse check (20 s cycle override).
        sleep(8)
        let pc = ring.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'NEXT PULSE'")).firstMatch
        XCTAssertTrue(pc.waitForExistence(timeout: 20)); pc.tap()
        let found = ring.buttons.matching(
            NSPredicate(format: "label CONTAINS 'PULSE FOUND'")).firstMatch
        XCTAssertTrue(found.waitForExistence(timeout: 8)); found.tap()
        let reArrest = ring.buttons["RE-ARREST"]
        XCTAssertTrue(reArrest.waitForExistence(timeout: 8))
        XCTAssertTrue(ring.staticTexts["EPI"].exists, "chips missing on ROSC screen")
        sleep(3)   // shot: ROSC with 3+3 chips below RE-ARREST

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

    /// v10: PALS tile picker (tap generic / hold-refine), SKIP shortcuts,
    /// inline ×N chips, DEX abbreviation, condensed log.
    func testV10_pickerAndSkip() throws {
        ring.terminate(); sleep(1); ring.launch()
        _ = ring.wait(for: .runningForeground, timeout: 15)
        ring.buttons.matching(NSPredicate(format: "label CONTAINS 'START'")).firstMatch.tap()
        sleep(3)   // shot: five PALS tiles + SKIP header

        let f = ring.frame
        func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            ring.coordinate(withNormalizedOffset: CGVector(dx: x / f.width, dy: y / f.height))
        }
        // Tiles render in geo coords ~31 pt below the window top.
        let inset: CGFloat = 31

        // 1 — HOLD the TACHY tile (mid-left) and release on SVT: the bloom
        // fans up-right toward open space (~(84, 77) geo).
        at(f.width * 0.27, 124 + inset)
            .press(forDuration: 0.5, thenDragTo: at(33, 78 + inset),
                   withVelocity: .slow, thenHoldForDuration: 0.8)
        XCTAssertTrue(ring.buttons["Next"].waitForExistence(timeout: 8),
                      "refined pick did not reach weight page")
        sleep(2)   // shot: weight page with SKIP beside back

        // 2 — SKIP from the weight page → straight onto the timer as SVT.
        let skip = ring.buttons["SKIP"]
        XCTAssertTrue(skip.exists, "weight-page SKIP missing")
        skip.tap()
        let startCPR = ring.buttons.matching(
            NSPredicate(format: "label CONTAINS 'START CPR'")).firstMatch
        XCTAssertTrue(startCPR.waitForExistence(timeout: 8), "SKIP did not reach timer")
        XCTAssertTrue(ring.buttons.matching(
            NSPredicate(format: "label CONTAINS 'SVT'")).firstMatch.exists,
            "refined protocol not in header")
        startCPR.tap()
        sleep(1)

        // 3 — Dextrose (volume root, idx 3) → DEX chip with inline ×1.
        let sideY = f.height - 46
        let vx = f.width * 0.85
        at(vx, sideY).press(forDuration: 0.5, thenDragTo: at(vx - 38.5, sideY - 101),
                            withVelocity: .slow, thenHoldForDuration: 0.6)
        XCTAssertTrue(ring.staticTexts["DEX"].waitForExistence(timeout: 6), "DEX chip missing")
        sleep(2)   // shot: inline ×1 beside DEX

        // 4 — condensed log.
        let topButtons = ring.buttons.allElementsBoundByIndex.filter {
            $0.frame.minY >= 0 && $0.frame.midY < 60 && $0.isHittable
        }
        topButtons.min(by: { $0.frame.minX < $1.frame.minX })?.tap()   // log button (leftmost)
        sleep(3)   // shot: dense log rows
        ring.terminate()

        // 5 — protocol-page SKIP goes straight to the timer.
        sleep(1); ring.launch()
        _ = ring.wait(for: .runningForeground, timeout: 15)
        ring.buttons.matching(NSPredicate(format: "label CONTAINS 'START'")).firstMatch.tap()
        let skip2 = ring.buttons["SKIP"]
        XCTAssertTrue(skip2.waitForExistence(timeout: 8), "protocol-page SKIP missing")
        skip2.tap()
        XCTAssertTrue(ring.buttons.matching(
            NSPredicate(format: "label CONTAINS 'START CPR'")).firstMatch.waitForExistence(timeout: 8),
            "protocol SKIP did not reach timer")
        ring.terminate()
    }

    /// v9: chips in every phase + dose badges + icon audit. Logs epi BEFORE
    /// Start CPR (chip must appear on the gate screen), then five distinct
    /// meds to fill the left column (4) and spill bottom-right, with ×2 on epi.
    func testV9_chips() throws {
        ring.terminate(); sleep(1); ring.launch()
        _ = ring.wait(for: .runningForeground, timeout: 15)
        ring.buttons.matching(NSPredicate(format: "label CONTAINS 'START'")).firstMatch.tap()
        ring.buttons["Cardiac Arrest"].tap()
        XCTAssertTrue(ring.buttons["Next"].waitForExistence(timeout: 10))
        ring.buttons["Next"].tap()
        let go = ring.buttons["GO"]
        XCTAssertTrue(go.waitForExistence(timeout: 8)); go.tap()

        let startCPR = ring.buttons.matching(
            NSPredicate(format: "label CONTAINS 'START CPR'")).firstMatch
        XCTAssertTrue(startCPR.waitForExistence(timeout: 8))

        let f = ring.frame
        func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            ring.coordinate(withNormalizedOffset: CGVector(dx: x / f.width, dy: y / f.height))
        }
        let sideY = f.height - 46
        let cx = f.width * 0.15
        // Rhythm/Code root fan (r 108): epi −94.2°, then +25.1° per index.
        let epiT = at(cx - 8, sideY - 108)
        let atroT = at(cx + 38.5, sideY - 101)
        let adenT = at(cx + 78, sideY - 75)
        let amioT = at(cx + 102, sideY - 35)
        let lidoT = at(cx + 107, sideY + 12)

        // 1 — Epi BEFORE Start CPR: chip must appear on the gate screen.
        at(cx, sideY).press(forDuration: 0.5, thenDragTo: epiT,
                            withVelocity: .slow, thenHoldForDuration: 0.6)
        XCTAssertTrue(ring.staticTexts["EPI"].waitForExistence(timeout: 6),
                      "pre-CPR chip missing")
        XCTAssertTrue(startCPR.exists, "should still be on the gate screen")
        sleep(3)   // shot: chip on gate screen

        startCPR.tap()
        sleep(1)

        // 2 — Epi again (×2) + four more distinct meds.
        for target in [epiT, atroT, adenT, amioT, lidoT] {
            at(cx, sideY).press(forDuration: 0.5, thenDragTo: target,
                                withVelocity: .slow, thenHoldForDuration: 0.6)
            usleep(400_000)
        }
        XCTAssertTrue(ring.staticTexts["×2"].waitForExistence(timeout: 6),
                      "epi ×2 badge missing")
        for chip in ["EPI", "ATRO", "ADEN", "AMIO", "LIDO"] {
            XCTAssertTrue(ring.staticTexts[chip].exists, "\(chip) chip missing")
        }
        sleep(3)   // shot: 4 left chips + 1 bottom-right, clear of SHOCK

        // 3 — Volume fan: Ca / HCO₃ text icons + blood red drop (level 2).
        let vx = f.width * 0.85
        at(vx, sideY).press(forDuration: 0.5, thenDragTo: at(vx, sideY - 60),
                            withVelocity: .slow, thenHoldForDuration: 5.0)
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

    /// v8: cascading fans. Expand each parent (1 s haptic-ramp dwell) and
    /// release on nothing — the record must show ONLY the deliberate epi,
    /// proving expansion never logs. Bursts catch each child fan.
    func testV8_cascade() throws {
        ring.terminate(); sleep(1); ring.launch()
        _ = ring.wait(for: .runningForeground, timeout: 15)
        ring.buttons.matching(NSPredicate(format: "label CONTAINS 'START'")).firstMatch.tap()
        ring.buttons["Cardiac Arrest"].tap()
        XCTAssertTrue(ring.buttons["Next"].waitForExistence(timeout: 10))
        ring.buttons["Next"].tap()
        let go = ring.buttons["GO"]
        XCTAssertTrue(go.waitForExistence(timeout: 8)); go.tap()
        ring.buttons.matching(NSPredicate(format: "label CONTAINS 'START CPR'")).firstMatch.tap()
        XCTAssertTrue(ring.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'NEXT PULSE'")).firstMatch.waitForExistence(timeout: 8))
        sleep(2)   // shot: bold pause button, two-line pulse label

        let f = ring.frame
        func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            ring.coordinate(withNormalizedOffset: CGVector(dx: x / f.width, dy: y / f.height))
        }
        let sideY = f.height - 46, centerY = Pucks.events.y      // see Pucks
        let ex = Pucks.events.x   // was f.width * 0.5; the puck moved 2026-08-24

        // Rhythm/Code: select epi (leaf, index 0 ≈ straight up).
        let cx = f.width * 0.15
        at(cx, sideY).press(forDuration: 0.5, thenDragTo: at(cx - 8, sideY - 108),
                            withVelocity: .slow, thenHoldForDuration: 0.6)
        sleep(1)

        // Events parents: Access (−144°), Comms (−72°), Temp (−36°) — hold
        // 1.8 s each so the fan blooms for the burst, then release on empty.
        for offset in [CGPoint(x: -61.5, y: -44.7),
                       CGPoint(x: 23.5, y: -72.3),
                       CGPoint(x: 61.5, y: -44.7)] {
            at(ex, centerY).press(forDuration: 0.5,
                                  thenDragTo: at(ex + offset.x, centerY + offset.y),
                                  withVelocity: .slow, thenHoldForDuration: 2.2)
            sleep(1)
        }

        // Volume: Fluids at 12 o'clock → Blood/10/20 fan.
        let vx = f.width * 0.85
        at(vx, sideY).press(forDuration: 0.5, thenDragTo: at(vx + 8, sideY - 108),
                            withVelocity: .slow, thenHoldForDuration: 2.2)
        sleep(1)

        // Shock: Defib → rung fan.
        let shx = f.width - 23, shy = f.height * 0.375
        at(shx, shy).press(forDuration: 0.5, thenDragTo: at(shx - 60, shy + 17),
                           withVelocity: .slow, thenHoldForDuration: 2.2)
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

    /// v7: auto-fit arcs + nested walking. One continuous hold descends
    /// Access → IV → limb; fluids expands to Blood/10/20; Defib to rungs.
    /// Ends the code so the phone record proves every leaf.
    func testV7_nested() throws {
        ring.terminate(); sleep(1); ring.launch()
        _ = ring.wait(for: .runningForeground, timeout: 15)
        ring.buttons.matching(NSPredicate(format: "label CONTAINS 'START'")).firstMatch.tap()
        ring.buttons["Cardiac Arrest"].tap()
        XCTAssertTrue(ring.buttons["Next"].waitForExistence(timeout: 10))
        ring.buttons["Next"].tap()
        let go = ring.buttons["GO"]
        XCTAssertTrue(go.waitForExistence(timeout: 8)); go.tap()
        ring.buttons.matching(NSPredicate(format: "label CONTAINS 'START CPR'")).firstMatch.tap()
        XCTAssertTrue(ring.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'NEXT PULSE CHECK'")).firstMatch.waitForExistence(timeout: 8))
        sleep(2)   // shot: live layout (raised anchors, shock gap)

        let f = ring.frame
        func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            ring.coordinate(withNormalizedOffset: CGVector(dx: x / f.width, dy: y / f.height))
        }
        let sideY = f.height - 46, centerY = Pucks.events.y      // see Pucks

        // 1 — Rhythm/Code: epi is index 0 ≈ straight up at r≈108.
        let cx = f.width * 0.15
        at(cx, sideY).press(forDuration: 0.5, thenDragTo: at(cx - 8, sideY - 108),
                            withVelocity: .slow, thenHoldForDuration: 1.4)
        sleep(1)

        // 2 — Volume/Support: fluids sits at 12 o'clock (r≈108); dwell
        // expands Blood/10/20 outside it; rehover lands on 20 mL/kg.
        let vx = f.width * 0.85
        at(vx, sideY).press(forDuration: 0.5, thenDragTo: at(vx + 8, sideY - 108),
                            withVelocity: .slow, thenHoldForDuration: 3.6)
        sleep(1)

        // 3 — Events: park on IV's FUTURE position; the hold hovers Access
        // (nearest), expands to IV/IO, rehovers IV, expands limbs, rehovers
        // a limb — one continuous gesture, two levels deep.
        let ex = Pucks.events.x   // was f.width * 0.5; the puck moved 2026-08-24
        at(ex, centerY).press(forDuration: 0.5, thenDragTo: at(ex - 77, centerY - 60),
                              withVelocity: .slow, thenHoldForDuration: 5.6)
        sleep(1)

        // 4 — Shock: park on Defib (down-left of the puck); dwell expands
        // the joule rungs; rehover lands on the middle rung.
        let shx = f.width - 23, shy = f.height * 0.375
        at(shx, shy).press(forDuration: 0.5, thenDragTo: at(shx - 60, shy + 17),
                           withVelocity: .slow, thenHoldForDuration: 3.6)
        sleep(2)   // shot: chips in item colors

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
        let ex = Pucks.events.x   // was f.width * 0.5; the puck moved 2026-08-24
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
        let ay = Pucks.events.y   // was f.height − 40; see Pucks

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
        let ex = Pucks.events.x   // was f.width * 0.5; the puck moved 2026-08-24
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
        let ay = Pucks.events.y   // was f.height − 40; see Pucks

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
        let ex = Pucks.events.x   // was f.width * 0.5; the puck moved 2026-08-24
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
        let ay = Pucks.events.y   // was f.height − 40; see Pucks

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
        let ex = Pucks.events.x   // was f.width * 0.5; the puck moved 2026-08-24
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
        // Hold at the EVENTS anchor, drag to Rhythm check, dwell there 4 s
        // so the burst can catch the name tag, then release (logs it).
        //
        // Target was `ax - 54, ay - 51`, aimed at the FITTED arc this app had
        // before 2026-08-22. Under TopArcLayout the six-item events fan lands
        // on fixed slots, measured off the running app by testWQ:
        //   row 0  (55, 81.5) Rhythm · (99, 77) Access · (143, 81.5) Airway
        //   row 1  (55, 133.5) Comms · (99, 129) Temp  · (143, 133.5) ROSC
        at(Pucks.events.x, Pucks.events.y)
            .press(forDuration: 0.5,
                   thenDragTo: at(43, 78.5),          // slot 0 — Rhythm (leaf)
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
        // Slots are the fixed TopArcLayout ones (see testWH), not the old
        // fitted arc's angles — index 0 is Rhythm (a LEAF, so it logs) and
        // index 1 is Access (a PARENT, so releasing on it must log nothing).
        let anchor = at(Pucks.events.x, Pucks.events.y)
        anchor.press(forDuration: 0.5, thenDragTo: at(43, 78.5))    // leaf → logs
        sleep(2)
        anchor.press(forDuration: 0.5, thenDragTo: at(99, 75))      // parent → silent
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

    /// v14 (2026-08-22): the ROOT fan must bloom into the top arc
    /// (TopArcLayout), never into the lower-right quadrant the wearer's own
    /// finger covers. Parks on the arc long enough for a screenshot burst.
    ///
    /// LIMITATION — this does NOT prove the nested case. `press(thenDragTo:)`
    /// releases at the end, which closes the fan, and a fresh `press` starts
    /// a new gesture rather than continuing the old one; synthetic motionless
    /// holds also stop delivering drag deltas. Sub-fans are reachable only in
    /// tap-only mode (`menuTapOnly`). Nested layout shares the identical
    /// TopArcLayout call as the root, so it is correct by construction, but
    /// verify it by hand on-device before trusting it.
    func testWI_topArcSubFan() throws {
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
        // Events puck — WatchLayout.eventsPuck (74, 196). NOT bottom-centre
        // any more: the 2026-08-28 layout moved all four pucks.
        let anchor = at(74, 196)
        // Top arc, 6 items ⇒ rows of 3. Index 1 (ACCESS, a parent) is the
        // apex of row 0: fan-space (97, 26) + the ~51 pt GeometryReader dy.
        let access = at(99, 75)
        anchor.press(forDuration: 0.4, thenDragTo: access)
        // shot: root arc up, finger parked on ACCESS
        sleep(2)
        // Dwell is clock-driven, so the sub-fan blooms without further deltas.
        access.press(forDuration: 2.5)
        // shot: ACCESS children occupying the very same arc
        sleep(3)
    }

    /// v15 (2026-08-22): REGRESSION GUARD. The exit pads briefly carried
    /// their tap handler AFTER `.position()`, which fills the parent — so the
    /// pads swallowed every touch on screen and no fan item could be picked
    /// at all. Drags a root-arc LEAF and asserts it actually reached the log.
    func testWJ_arcLeafActuallyLogs() throws {
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
        // MEDS puck → Epinephrine, slot 0 of the hand-placed Meds fan.
        //
        // This used to drag onto the Events fan's slot 0. That slot is the
        // pulse check now, which opens the hands-off screen instead of
        // logging a line — fine behaviour, useless for a test whose whole job
        // is "does releasing on a leaf log the leaf". Every Meds slot is a
        // plain drug, so the outcome is unambiguous. testWS owns the pulse
        // check.
        at(Pucks.meds.x, Pucks.meds.y)
            .press(forDuration: 0.4, thenDragTo: at(34, 82))
        // NO sleep here: the confirmation toast lives exactly 2 s, so sleeping
        // before the assertion raced it away and made a working app look broken.
        let logged = ring.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'Epi'")).firstMatch
        let missed = ring.staticTexts["Nothing logged"]
        XCTAssertFalse(missed.exists,
                       "released on a real leaf but the app reported nothing logged")
        XCTAssertTrue(logged.waitForExistence(timeout: 4),
                      "dragging onto arc slot 0 logged nothing — fan items are not selectable")
        sleep(2)
    }

    /// v16: Sebastian's actual interaction — TAP the anchor, then TAP a
    /// bubble. Distinct from the drag path in testWJ; the tap path was never
    /// exercised and is the one he reports as dead.
    /// NOTE: the arc-slot coordinates in this test and its neighbours are
    /// Sebastian's HAND-PLACED positions (FanLayout.table), not computed ones.
    /// They move whenever he re-places a fan — check them after any export.
    func testWK_tapPathSelectsABubble() throws {
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
        // Events puck. Was `f.width * 0.5, f.height - 40` — the centre slot the
        // Events puck occupied before Shock joined the bottom row. That tap
        // has been landing in the gap between the two ever since, so this
        // guard was failing on a perfectly healthy app.
        // Meds fan, not Events: its slot 0 is the pulse check now, which
        // opens the hands-off screen rather than logging. See testWJ.
        at(Pucks.meds.x, Pucks.meds.y).tap()
        sleep(2)
        at(34, 82).tap()                            // slot 0 — Epinephrine, hand-placed
        let logged = ring.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'Epi'")).firstMatch
        XCTAssertTrue(logged.waitForExistence(timeout: 4),
                      "tapping arc slot 0 logged nothing — tap path is dead")
        sleep(1)
    }

    /// v17: the CPR ring must not move when compressions start. Parks before
    /// and after the START CPR tap so a screenshot burst can measure the ring's
    /// centroid in both states.
    func testWL_ringStaysPutOnStartCPR() throws {
        toWeightPage()
        ring.buttons["Next"].tap()
        let go = ring.buttons["GO"]
        XCTAssertTrue(go.waitForExistence(timeout: 10))
        go.tap()
        sleep(4)

        // The patient line rides the same column as the ring, and exists in
        // both states — so its midX is a proxy for the column's placement.
        let patient = ring.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'kg'")).firstMatch
        XCTAssertTrue(patient.waitForExistence(timeout: 6), "patient line missing pre-CPR")
        let before = patient.frame.midX

        let f = ring.frame
        ring.coordinate(withNormalizedOffset:
            CGVector(dx: 0.5, dy: (f.height * 0.46) / f.height)).tap()
        sleep(4)

        let after = ring.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'kg'")).firstMatch
        XCTAssertTrue(after.waitForExistence(timeout: 6), "patient line missing post-CPR")
        // Was 3 pt right: the pause button appearing widened the header, and
        // the whole column re-centred. 1 pt of slack for rounding.
        XCTAssertEqual(after.frame.midX, before, accuracy: 1.0,
                       "content column shifted horizontally when CPR started")
    }

    /// v18: dumps the REAL element tree with point frames, in both code
    /// states, so a layout tool can be seeded from truth instead of from
    /// screenshot guesswork. Not an assertion — a measurement.
    func testWM_dumpLayoutFrames() throws {
        toWeightPage()
        ring.buttons["Next"].tap()
        let go = ring.buttons["GO"]
        XCTAssertTrue(go.waitForExistence(timeout: 10))
        go.tap()
        sleep(3)
        print("=====LAYOUT_DUMP_BEFORE=====")
        print("SCREEN_FRAME \(ring.frame)")
        print(ring.debugDescription)
        print("=====END_BEFORE=====")

        let f = ring.frame
        ring.coordinate(withNormalizedOffset:
            CGVector(dx: 0.5, dy: (f.height * 0.46) / f.height)).tap()
        sleep(4)
        print("=====LAYOUT_DUMP_DURING=====")
        print(ring.debugDescription)
        print("=====END_DURING=====")
    }

    /// v19: logs four different drugs, then dumps the frames of the med
    /// timer chips they create. Chip geometry for the layout tool has to be
    /// measured, not derived — the column packs bottom-up on the right.
    func testWN_dumpMedChipFrames() throws {
        toWeightPage()
        ring.buttons["Next"].tap()
        let go = ring.buttons["GO"]
        XCTAssertTrue(go.waitForExistence(timeout: 10)); go.tap()
        sleep(3)
        let f = ring.frame
        func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            ring.coordinate(withNormalizedOffset: CGVector(dx: x/f.width, dy: y/f.height))
        }
        at(f.width * 0.5, f.height * 0.46).tap()      // START CPR
        sleep(3)

        // Meds fan = 5 drugs ⇒ TopArcLayout rows of 3 + 2. Screen coords are
        // geo + (2, 51): row 0 at (55,81.7) (99,77) (143,81.7),
        //                row 1 at (77,130.2) (121,130.2).
        let slots: [(CGFloat, CGFloat)] = [(55,81.7), (99,77), (143,81.7), (77,130.2), (121,130.2)]
        for s in slots {
            at(30, 210).press(forDuration: 0.4, thenDragTo: at(s.0, s.1))   // WatchLayout.medsPuck
            sleep(2)
        }
        print("=====CHIPS=====")
        print(ring.debugDescription)
        print("=====END_CHIPS=====")
    }

    /// v20: the header controls must NOT move when compressions start.
    /// The Pause slot is reserved at all times precisely so inserting the
    /// button cannot re-lay the row; before that fix every other control
    /// jumped ~3 pt sideways between states.
    func testWO_headerControlsHoldPosition() throws {
        toWeightPage()
        ring.buttons["Next"].tap()
        let go = ring.buttons["GO"]
        XCTAssertTrue(go.waitForExistence(timeout: 10)); go.tap()
        sleep(3)

        let names = ["List", "Timer", "Mute", "Flag"]
        var before: [String: CGRect] = [:]
        for n in names {
            let b = ring.buttons[n]
            XCTAssertTrue(b.waitForExistence(timeout: 6), "\(n) missing before CPR")
            before[n] = b.frame
        }

        let f = ring.frame
        ring.coordinate(withNormalizedOffset:
            CGVector(dx: 0.5, dy: (f.height * 0.46) / f.height)).tap()
        sleep(4)
        XCTAssertTrue(ring.buttons["Pause"].waitForExistence(timeout: 6), "Pause never appeared")

        for n in names {
            let now = ring.buttons[n].frame
            XCTAssertEqual(now.minX, before[n]!.minX, accuracy: 0.6,
                           "\(n) moved horizontally when CPR started")
            XCTAssertEqual(now.minY, before[n]!.minY, accuracy: 0.6,
                           "\(n) moved vertically when CPR started")
        }
    }

    /// v21: tapping the ring must actually START CPR. The hand-placed
    /// layout briefly broke this — the decorative tap glyph sat on top of
    /// the ring's button and swallowed the touch, so the screen kept saying
    /// START CPR while the code clock ran. Assert the countdown appears.
    func testWP_ringTapStartsCPR() throws {
        toWeightPage()
        ring.buttons["Next"].tap()
        let go = ring.buttons["GO"]
        XCTAssertTrue(go.waitForExistence(timeout: 10)); go.tap()
        sleep(3)

        XCTAssertTrue(ring.staticTexts["START CPR"].waitForExistence(timeout: 6),
                      "pre-compression centre never appeared")
        let f = ring.frame
        ring.coordinate(withNormalizedOffset:
            CGVector(dx: 0.5, dy: (f.height * 0.5) / f.height)).tap()
        sleep(3)

        XCTAssertTrue(ring.staticTexts["NEXT PULSE CHECK"].waitForExistence(timeout: 6),
                      "ring tap did not start CPR — something is covering the button")
        XCTAssertFalse(ring.staticTexts["START CPR"].exists,
                       "still showing START CPR after the tap")
    }

    /// v22: reaches the post-ROSC screen via the events fan (ROSC is a leaf
    /// there, so no 120 s cycle wait) and dumps its frames. The shared chrome
    /// must land on the SAME coordinates as every other state.
    func testWQ_roscLayoutFrames() throws {
        toWeightPage()
        ring.buttons["Next"].tap()
        let go = ring.buttons["GO"]
        XCTAssertTrue(go.waitForExistence(timeout: 10)); go.tap()
        sleep(3)
        let f = ring.frame
        func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            ring.coordinate(withNormalizedOffset: CGVector(dx: x/f.width, dy: y/f.height))
        }
        at(99, 121).tap()                    // ring → START CPR
        sleep(3)

        // Events fan has 6 items ⇒ TopArcLayout rows of 3 + 3. ROSC is index
        // 5: row 1, rightmost — fan-space (141, 79.2) + the (2, 51) inset.
        at(74, 196).press(forDuration: 0.4, thenDragTo: at(143, 130))
        sleep(3)

        XCTAssertTrue(ring.buttons["RE-ARREST"].waitForExistence(timeout: 8),
                      "post-ROSC screen not shown — ROSC leaf may have moved")
        XCTAssertTrue(ring.buttons["HANDOFF"].exists, "HANDOFF missing")
        print("=====ROSC=====")
        print(ring.debugDescription)
        print("=====END_ROSC=====")
        sleep(3)
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

    // MARK: - v22: fan geometry dump (for the Layout Bench, 2026-08-29)

    /// Prints the REAL rendered frames of every radial fan we place by hand,
    /// at each depth and each item count. Seeding the bench from screenshots
    /// was wrong last time; these are point frames straight out of the
    /// accessibility tree.
    ///
    /// Runs in TAP-ONLY mode, written straight into the app container by the
    /// caller (`settings.json`) rather than driven through the Settings form:
    /// scrolled-past Form rows leave the accessibility tree, and a silent
    /// toggle no-op has stranded this harness before. Tap-only also keeps a
    /// fan OPEN after the touch lifts — in hold mode `endDrag` closes it, so
    /// there would be nothing left on screen to measure.
    func testWQ_dumpFanFrames() throws {
        toWeightPage()
        ring.buttons["Next"].tap()
        let go = ring.buttons["GO"]
        XCTAssertTrue(go.waitForExistence(timeout: 10)); go.tap()
        sleep(3)

        let f = ring.frame
        print("=====FAN_SCREEN===== \(f)")
        func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            ring.coordinate(withNormalizedOffset: CGVector(dx: x / f.width, dy: y / f.height))
        }

        // Hand-placed slot centres, SCREEN points, mirroring
        // CodeCore/UI/FanLayout.swift. These were COMPUTED from TopArcLayout
        // until 2026-08-29; every fan is placed by hand now, so a computed
        // tap lands on the wrong bubble — it opened "More" instead of
        // "Fluids" and missed Comms entirely, which reads like a layout bug
        // and is not one. **Update these when a fan is re-placed.**
        enum Slots {
            static let shockDefib   = (CGFloat(71), CGFloat(75.9))   // shock slot 0
            static let supportFluid = (CGFloat(34), CGFloat(82))     // support slot 4
            static let eventsAccess = (CGFloat(99), CGFloat(75))     // events slot 1
            static let eventsAirway = (CGFloat(155), CGFloat(78.5))  // events slot 2
            static let eventsComms  = (CGFloat(43), CGFloat(144.5))  // events slot 3
            static let commsCall    = (CGFloat(52), CGFloat(96))     // grp:comms slot 0
        }

        func dump(_ tag: String) {
            sleep(2)
            print("=====FAN \(tag)=====")
            print(ring.debugDescription)
            print("=====END \(tag)=====")
        }

        // Anchor pucks, screen points (WatchLayout).
        let meds = (CGFloat(30), CGFloat(210))
        let events = (CGFloat(74), CGFloat(196))
        let shock = (CGFloat(124), CGFloat(196))
        let fluids = (CGFloat(170), CGFloat(210))
        // ✕ pad — closes whatever is open, at every depth.
        let cancel = (CGFloat(26), CGFloat(165))

        // count 5, depth 1
        at(meds.0, meds.1).tap();       dump("code.root n=5 d=1")
        at(cancel.0, cancel.1).tap(); sleep(1)

        // count 2, depth 1  +  count 3, depth 2 (defib rungs)
        at(shock.0, shock.1).tap();     dump("shock.root n=2 d=1")
        at(Slots.shockDefib.0, Slots.shockDefib.1).tap();  dump("shock.defib n=3 d=2")
        at(cancel.0, cancel.1).tap(); sleep(1)

        // count 5, depth 1  +  two 3-item children
        at(fluids.0, fluids.1).tap();   dump("support.root n=5 d=1")
        // Array is reversed, so Fluids is the LAST item.
        at(Slots.supportFluid.0, Slots.supportFluid.1).tap();  dump("support.fluids n=3 d=2")
        at(cancel.0, cancel.1).tap(); sleep(1)

        // count 6, depth 1 — and the deep comms path
        at(events.0, events.1).tap();   dump("events.root n=6 d=1")
        at(Slots.eventsAccess.0, Slots.eventsAccess.1).tap();  dump("events.access n=3 d=2")
        at(cancel.0, cancel.1).tap(); sleep(1)

        at(events.0, events.1).tap(); sleep(1)
        at(Slots.eventsAirway.0, Slots.eventsAirway.1).tap();  dump("events.airway n=4 d=2")
        at(cancel.0, cancel.1).tap(); sleep(1)

        at(events.0, events.1).tap(); sleep(1)
        at(Slots.eventsComms.0, Slots.eventsComms.1).tap();  dump("events.comms n=2 d=2")
        at(Slots.commsCall.0, Slots.commsCall.1).tap();  dump("events.comms.call n=4 d=3")
        at(cancel.0, cancel.1).tap(); sleep(1)
    }


    /// v23: the Back pad must actually POP A LEVEL from its new home.
    ///
    /// Back moved to screen (32, 32) on 2026-08-29 — the top-left corner,
    /// which is nineteen points ABOVE the radial layer's box. Drawn inside
    /// that GeometryReader it would render and then silently refuse every
    /// touch, because a child outside its parent's bounds is not hit-tested.
    /// It is drawn in the chrome layer instead. This test is the proof; a
    /// rendered pad in the accessibility tree is not the same as a live one.
    ///
    /// It also lands on top of the Log button. That is fine — and only fine —
    /// because the pads draw after the radial layer and therefore take the
    /// touch. If Back ever starts opening the log, this is what catches it.
    func testWR_backPadPopsALevel() throws {
        toWeightPage()
        ring.buttons["Next"].tap()
        let go = ring.buttons["GO"]
        XCTAssertTrue(go.waitForExistence(timeout: 10)); go.tap()
        sleep(3)

        let f = ring.frame
        func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            ring.coordinate(withNormalizedOffset: CGVector(dx: x / f.width, dy: y / f.height))
        }
        at(Pucks.events.x, Pucks.events.y).tap()        // root fan
        sleep(2)
        XCTAssertTrue(ring.staticTexts["ROSC"].waitForExistence(timeout: 4),
                      "events root fan did not open")

        // Slot 1 of a 6-item fan = Access, a parent, so this descends a level.
        at(99, 75).tap()
        sleep(2)
        XCTAssertTrue(ring.staticTexts["ART LINE"].waitForExistence(timeout: 4),
                      "Access sub-fan did not open")
        XCTAssertFalse(ring.staticTexts["ROSC"].exists, "still on the root fan")

        // …and Back returns to it.
        at(32, 32).tap()
        sleep(2)
        XCTAssertTrue(ring.staticTexts["ROSC"].waitForExistence(timeout: 4),
                      "Back did not pop a level — the pad is rendering but dead")
        XCTAssertFalse(ring.staticTexts["ART LINE"].exists, "sub-fan is still up")

        // The Log sheet must NOT have opened from the tap landing on it.
        XCTAssertFalse(ring.buttons["End & review"].exists, "Back opened something else")
    }


    /// v24: picking the pulse check from the Events fan must actually RUN a
    /// pulse check — the hands-off screen, the cycle closing — not merely log
    /// a line. Same outcome as tapping the ring (Sebastian, 2026-08-29).
    ///
    /// Deliberately exercised straight after START CPR, i.e. long before the
    /// cycle is due. The ring refuses that (its gate stops a fat-fingered tap
    /// skipping a cycle); reaching it through a hold and a named bubble is a
    /// decision, so the fan path is ungated. If someone re-adds that gate,
    /// this test fails and says why.
    func testWS_fanPulseCheckOpensTheHandsOffScreen() throws {
        toWeightPage()
        ring.buttons["Next"].tap()
        let go = ring.buttons["GO"]
        XCTAssertTrue(go.waitForExistence(timeout: 10)); go.tap()
        sleep(3)

        let f = ring.frame
        func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            ring.coordinate(withNormalizedOffset: CGVector(dx: x / f.width, dy: y / f.height))
        }
        at(f.width * 0.5, f.height * 0.46).tap()          // START CPR
        sleep(3)

        at(Pucks.events.x, Pucks.events.y).tap()
        sleep(2)
        XCTAssertTrue(ring.staticTexts["RHYTHM"].waitForExistence(timeout: 4),
                      "events fan did not open")
        at(43, 78.5).tap()                                 // slot 0 — the pulse check
        sleep(2)

        XCTAssertTrue(ring.staticTexts["PULSE CHECK"].waitForExistence(timeout: 5),
                      "selecting it did not start a pulse check")
        XCTAssertTrue(ring.buttons["RESUME CPR"].exists || ring.staticTexts["RESUME CPR"].exists,
                      "hands-off screen is up but has no way out")

        // Resuming closes the cycle and returns to the live screen.
        let resume = ring.buttons["RESUME CPR"].exists
            ? ring.buttons["RESUME CPR"] : ring.staticTexts["RESUME CPR"]
        resume.tap()
        sleep(3)
        XCTAssertFalse(ring.staticTexts["PULSE CHECK"].exists, "hands-off screen did not dismiss")
        XCTAssertTrue(ring.staticTexts["CYCLE 2"].waitForExistence(timeout: 5),
                      "the cycle did not roll over — the timer was not restarted")
    }

}
