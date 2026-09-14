// CodeCoreTests — run with `swift test` inside CodeCore/ on the Mac,
// or ⌘U in Xcode. These lock in the math a lesser model must never break.

import XCTest
@testable import CodeCore

final class DoseCalculatorTests: XCTestCase {

    func testEpi8kg() {
        let doses = DoseCalculator.doses(for: Defaults.epinephrine, weightKg: 8)
        XCTAssertEqual(doses.count, 1)
        XCTAssertEqual(doses[0].amount, 0.08, accuracy: 0.0001)     // mg
        XCTAssertEqual(doses[0].volumeMl ?? 0, 0.8, accuracy: 0.0001) // mL of 0.1 mg/mL
        XCTAssertFalse(doses[0].capped)
    }

    func testEpiCapAtOneMg() {
        let doses = DoseCalculator.doses(for: Defaults.epinephrine, weightKg: 150)
        XCTAssertEqual(doses[0].amount, 1.0, accuracy: 0.0001)
        XCTAssertEqual(doses[0].volumeMl ?? 0, 10.0, accuracy: 0.0001)
        XCTAssertTrue(doses[0].capped)
    }

    func testAdenosineLadder() {
        let doses = DoseCalculator.doses(for: Defaults.adenosine, weightKg: 20)
        XCTAssertEqual(doses[0].amount, 2.0, accuracy: 0.0001)   // 0.1 × 20
        XCTAssertEqual(doses[1].amount, 4.0, accuracy: 0.0001)   // 0.2 × 20
        // Ladder advances with prior count, then holds the last rung.
        XCTAssertEqual(DoseCalculator.primaryDose(for: Defaults.adenosine, weightKg: 20, priorCount: 0)?.stepLabel, "1st")
        XCTAssertEqual(DoseCalculator.primaryDose(for: Defaults.adenosine, weightKg: 20, priorCount: 1)?.stepLabel, "2nd")
        XCTAssertEqual(DoseCalculator.primaryDose(for: Defaults.adenosine, weightKg: 20, priorCount: 5)?.stepLabel, "2nd")
    }

    func testDefibEnergies() {
        let doses = DoseCalculator.doses(for: Defaults.defibrillation, weightKg: 12)
        XCTAssertEqual(doses[0].amount, 24, accuracy: 0.0001)    // 2 J/kg
        XCTAssertEqual(doses[1].amount, 48, accuracy: 0.0001)    // 4 J/kg
        XCTAssertNil(doses[0].volumeMl)                          // energy has no mL
    }

    func testVolumeFloor() {
        // Tiny volumes never render as 0.0 mL.
        XCTAssertEqual(DoseCalculator.roundedVolume(0.031), 0.1, accuracy: 0.0001)
    }

    func testTrimFormatting() {
        XCTAssertEqual(DoseCalculator.trim(0.80), "0.8")
        XCTAssertEqual(DoseCalculator.trim(16.0), "16")
        XCTAssertEqual(DoseCalculator.trim(0.08), "0.08")
    }

    func testChipAbbreviations() {
        // Known clinical shorthand, keyed on the leading word.
        XCTAssertEqual(crChipAbbreviation(key: "x", title: "Fluid bolus"), "IVF")
        XCTAssertEqual(crChipAbbreviation(key: "x", title: "Blood given"), "BLOOD")
        XCTAssertEqual(crChipAbbreviation(key: "x", title: "Epinephrine"), "EPI")
        XCTAssertEqual(crChipAbbreviation(key: "x", title: "Amiodarone"), "AMIO")
        XCTAssertEqual(crChipAbbreviation(key: "x", title: "Calcium"), "CA")
        XCTAssertEqual(crChipAbbreviation(key: "x", title: "Dextrose"), "DEX")
        XCTAssertEqual(crChipAbbreviation(key: "x", title: "Bicarb"), "BICARB")
        // Unknown short word → said whole; unknown long word → first 3.
        XCTAssertEqual(crChipAbbreviation(key: "x", title: "Zeta"), "ZETA")
        XCTAssertEqual(crChipAbbreviation(key: "x", title: "Zetatropine"), "ZET")
    }

    func testMlPerKgDosing() {
        // Fluids: 20 mL/kg × 12 kg = 240 mL, featured as mL, no mg tail.
        let doses = DoseCalculator.doses(for: Defaults.fluids, weightKg: 12)
        XCTAssertEqual(doses[0].volumeMl ?? 0, 120, accuracy: 0.01)   // 10 mL/kg
        XCTAssertEqual(doses[1].volumeMl ?? 0, 240, accuracy: 0.01)   // 20 mL/kg
        XCTAssertEqual(doses[1].volumeText, "240 mL")
        XCTAssertEqual(doses[1].summary, "240 mL")                    // no "(… mg)"
        // 20 mL/kg caps at 2000 mL for a large patient.
        let big = DoseCalculator.doses(for: Defaults.fluids, weightKg: 150)
        XCTAssertEqual(big[1].volumeMl ?? 0, 2000, accuracy: 0.01)
        XCTAssertTrue(big[1].capped)
    }
}

final class WeightEstimatorTests: XCTestCase {

    func testInfantFormula() {
        XCTAssertEqual(WeightEstimator.weightKg(forAgeMonths: 6), 7.0, accuracy: 0.001)   // 0.5×6+4
    }

    func testChildFormula() {
        XCTAssertEqual(WeightEstimator.weightKg(forAgeMonths: 48), 16.0, accuracy: 0.001) // (4+4)×2
    }

    func testCap() {
        XCTAssertLessThanOrEqual(WeightEstimator.weightKg(forAgeMonths: 300), 50)
    }
}

final class RadialLayoutTests: XCTestCase {

    private let bounds = CGSize(width: 198, height: 191)   // 45 mm live screen

    private func assertOnScreen(_ layout: RadialLayout, count: Int,
                                file: StaticString = #filePath, line: UInt = #line) {
        for i in 0..<count {
            let p = layout.position(forIndex: i, count: count)
            XCTAssertGreaterThanOrEqual(p.x, 19, "bubble \(i) off left", file: file, line: line)
            XCTAssertLessThanOrEqual(p.x, bounds.width - 19, "bubble \(i) off right", file: file, line: line)
            XCTAssertGreaterThanOrEqual(p.y, 13, "bubble \(i) off top", file: file, line: line)
            XCTAssertLessThanOrEqual(p.y, bounds.height - 15, "bubble \(i) off bottom", file: file, line: line)
        }
    }

    private func minPairDistance(_ layout: RadialLayout, count: Int) -> CGFloat {
        var best = CGFloat.infinity
        for i in 0..<count {
            for j in (i + 1)..<count {
                let a = layout.position(forIndex: i, count: count)
                let b = layout.position(forIndex: j, count: count)
                best = min(best, hypot(a.x - b.x, a.y - b.y))
            }
        }
        return best
    }

    /// Walk the deepest real path: events root (6) → Access (2) → IV (4
    /// limbs), each level re-centered on the tapped item like the watch does.
    func testCascadeAccessIVLimbsStaysOnScreenAndSpaced() {
        var root = RadialLayout(anchor: CGPoint(x: 99, y: 155), bounds: bounds)
        root.fit(count: 6, preferredCenter: nil, startRadius: 76)
        assertOnScreen(root, count: 6)
        XCTAssertGreaterThanOrEqual(minPairDistance(root, count: 6), 40)

        let access = root.position(forIndex: 1, count: 6)
        var lvl1 = RadialLayout(anchor: access, bounds: bounds)
        lvl1.fit(count: 2,
                 preferredCenter: RadialLayout.openSpaceDirection(from: access, bounds: bounds),
                 startRadius: 56, radiusCap: 72)
        assertOnScreen(lvl1, count: 2)
        XCTAssertGreaterThanOrEqual(minPairDistance(lvl1, count: 2), 40)
        // Uniform finger reach: children never fly across the screen.
        for i in 0..<2 {
            let p = lvl1.position(forIndex: i, count: 2)
            XCTAssertLessThanOrEqual(hypot(p.x - access.x, p.y - access.y), 76)
        }

        let iv = lvl1.position(forIndex: 0, count: 2)
        var lvl2 = RadialLayout(anchor: iv, bounds: bounds)
        lvl2.fit(count: 4,
                 preferredCenter: RadialLayout.openSpaceDirection(from: iv, bounds: bounds),
                 startRadius: 56, radiusCap: 72)
        assertOnScreen(lvl2, count: 4)
        XCTAssertGreaterThanOrEqual(minPairDistance(lvl2, count: 4), 34)
    }

    /// Every parent in the ACTUAL four menu trees must lay out its children
    /// on screen, at every depth, exactly as the watch cascades them.
    func testEveryParentExpandsOnScreen() {
        // node = (childCount, grandchild counts per child); mirrors the trees.
        struct Node { let children: Int; let grand: [Int] }
        // (anchor, root count, parents by root index)
        let menus: [(CGPoint, Int, [Int: Node])] = [
            (CGPoint(x: 29.7, y: 145), 5, [:]),                      // rhythm/code: all leaves
            (CGPoint(x: 99, y: 155), 6, [                            // events
                1: Node(children: 3, grand: []),                     // access → IV/IO/art (leaves)
                2: Node(children: 4, grand: []),                     // airway
                3: Node(children: 2, grand: [4, 4]),                 // comms → call/arrival → services
                4: Node(children: 3, grand: [])                      // temp devices
            ]),
            (CGPoint(x: 168.3, y: 145), 5, [                         // volume (reversed order)
                0: Node(children: 3, grand: []),                     // more
                4: Node(children: 3, grand: [])                      // fluids
            ]),
            (CGPoint(x: 175, y: 45.8), 2, [                          // shock
                0: Node(children: 3, grand: [])                      // defib rungs
            ])
        ]
        for (anchor, count, parents) in menus {
            var root = RadialLayout(anchor: anchor, bounds: bounds)
            root.fit(count: count, preferredCenter: nil, startRadius: 74)
            assertOnScreen(root, count: count)
            for (idx, node) in parents {
                let parent = root.position(forIndex: idx, count: count)
                var lvl1 = RadialLayout(anchor: parent, bounds: bounds)
                lvl1.fit(count: node.children,
                         preferredCenter: RadialLayout.openSpaceDirection(from: parent, bounds: bounds),
                         startRadius: 56, radiusCap: 72)
                assertOnScreen(lvl1, count: node.children)
                XCTAssertGreaterThanOrEqual(minPairDistance(lvl1, count: node.children), 30,
                    "children of \(anchor) idx \(idx) crowded")
                for (ci, gcount) in node.grand.enumerated() where gcount > 0 {
                    let cpos = lvl1.position(forIndex: ci, count: node.children)
                    var lvl2 = RadialLayout(anchor: cpos, bounds: bounds)
                    lvl2.fit(count: gcount,
                             preferredCenter: RadialLayout.openSpaceDirection(from: cpos, bounds: bounds),
                             startRadius: 56, radiusCap: 72)
                    assertOnScreen(lvl2, count: gcount)
                    XCTAssertGreaterThanOrEqual(minPairDistance(lvl2, count: gcount), 30,
                        "grandchildren of \(anchor) idx \(idx).\(ci) crowded")
                }
            }
        }
    }

    /// Sebastian's hand-placed layouts (FanLayoutOverrides) must reproduce
    /// EXACTLY what he drew in the layout editor: parents resolved through
    /// the same fit chain the watch runs must sit where the editor showed
    /// them, and no offset position may be displaced by the screen clamp.
    /// Two coordinate spaces on purpose: the EDITOR previewed root fits at
    /// 198×191, but the live GeometryReader is 194×191 (2 pt side insets,
    /// probe-measured on the 45 mm sim) — offsets were derived in editor
    /// space and must survive the clamp at the live parents.
    func testFanLayoutOverridesMatchEditorExport() {
        // Roots exactly as LiveSessionView opens them (anchor, count, radius).
        var events = RadialLayout(anchor: CGPoint(x: 99, y: 155), bounds: bounds)
        events.fit(count: 6, preferredCenter: nil, startRadius: 76)
        var volume = RadialLayout(anchor: CGPoint(x: 168.3, y: 145), bounds: bounds)
        volume.fit(count: 5, preferredCenter: nil, startRadius: 84)

        // Level-3 parents (Call/Arrival) live inside the overridden comms fan.
        let comms = events.position(forIndex: 3, count: 6)
        guard let commsOv = FanLayoutOverrides.table["comms"],
              let callOff = commsOv.items[0], let arrivalOff = commsOv.items[1],
              let shockOv = FanLayoutOverrides.table["shockRoot"],
              let defibFixed = shockOv.items[0] else {
            return XCTFail("comms/shockRoot overrides missing from table")
        }

        // (key, parent via live fit chain, parent per the editor export)
        let parents: [(String, CGPoint, CGPoint)] = [
            ("access",  events.position(forIndex: 1, count: 6), CGPoint(x: 37, y: 110)),
            ("airway",  events.position(forIndex: 2, count: 6), CGPoint(x: 76, y: 83)),
            ("comms",   comms,                                  CGPoint(x: 123, y: 83)),
            ("call",    CGPoint(x: comms.x + callOff.x, y: comms.y + callOff.y),
                        CGPoint(x: 87, y: 43)),
            ("arrival", CGPoint(x: comms.x + arrivalOff.x, y: comms.y + arrivalOff.y),
                        CGPoint(x: 69, y: 96)),
            ("temp",    events.position(forIndex: 4, count: 6), CGPoint(x: 161, y: 110)),
            ("moreVol", volume.position(forIndex: 0, count: 5), CGPoint(x: 61, y: 159)),
            ("fluids",  volume.position(forIndex: 4, count: 5), CGPoint(x: 174, y: 37)),
            ("defib",   defibFixed,                             CGPoint(x: 116, y: 38))
        ]

        for (key, live, editor) in parents {
            // Offsets were authored against the editor's parent; if the live
            // fit drifts, everything Sebastian placed lands somewhere else.
            XCTAssertEqual(live.x, editor.x, accuracy: 1.5, "\(key) parent x drifted from editor")
            XCTAssertEqual(live.y, editor.y, accuracy: 1.5, "\(key) parent y drifted from editor")
            guard let ov = FanLayoutOverrides.table[key] else {
                XCTFail("override \(key) missing from table"); continue
            }
            var pts = ov.items.values.map { CGPoint(x: live.x + $0.x, y: live.y + $0.y) }
            if let b = ov.back { pts.append(CGPoint(x: live.x + b.x, y: live.y + b.y)) }
            if let c = ov.cancel { pts.append(CGPoint(x: live.x + c.x, y: live.y + c.y)) }
            for p in pts {
                // Watch clamp: x∈[18, W−18], y∈[16, H−16]. ≤3 pt of slack for
                // pads placed right on the editor's slightly looser margin.
                XCTAssertEqual(p.x, min(max(p.x, 18), bounds.width - 18), accuracy: 3,
                               "\(key) point clamped away from where it was drawn")
                XCTAssertEqual(p.y, min(max(p.y, 16), bounds.height - 16), accuracy: 3,
                               "\(key) point clamped away from where it was drawn")
            }
        }

        // shockRoot absolutes stay on screen as-is.
        for p in shockOv.items.values {
            XCTAssertEqual(p.x, min(max(p.x, 18), bounds.width - 18), accuracy: 0.01)
            XCTAssertEqual(p.y, min(max(p.y, 16), bounds.height - 16), accuracy: 0.01)
        }

        // LIVE space (194 wide): re-resolve every parent with the real
        // runtime bounds and require the clamp to move nothing by more than
        // a few points — the drawn arrangement survives on the actual watch.
        let live = CGSize(width: 194, height: 191)
        var liveEvents = RadialLayout(anchor: CGPoint(x: 97, y: 155), bounds: live)
        liveEvents.fit(count: 6, preferredCenter: nil, startRadius: 76)
        var liveVolume = RadialLayout(anchor: CGPoint(x: 194 * 0.85, y: 145), bounds: live)
        liveVolume.fit(count: 5, preferredCenter: nil, startRadius: 84)
        let liveComms = liveEvents.position(forIndex: 3, count: 6)
        let liveParents: [(String, CGPoint)] = [
            ("access",  liveEvents.position(forIndex: 1, count: 6)),
            ("airway",  liveEvents.position(forIndex: 2, count: 6)),
            ("comms",   liveComms),
            ("call",    CGPoint(x: liveComms.x + callOff.x, y: liveComms.y + callOff.y)),
            ("arrival", CGPoint(x: liveComms.x + arrivalOff.x, y: liveComms.y + arrivalOff.y)),
            ("temp",    liveEvents.position(forIndex: 4, count: 6)),
            ("moreVol", liveVolume.position(forIndex: 0, count: 5)),
            ("fluids",  liveVolume.position(forIndex: 4, count: 5)),
            ("defib",   defibFixed)
        ]
        for (key, parent) in liveParents {
            guard let ov = FanLayoutOverrides.table[key] else { continue }
            var pts = ov.items.values.map { CGPoint(x: parent.x + $0.x, y: parent.y + $0.y) }
            if let b = ov.back { pts.append(CGPoint(x: parent.x + b.x, y: parent.y + b.y)) }
            if let c = ov.cancel { pts.append(CGPoint(x: parent.x + c.x, y: parent.y + c.y)) }
            for p in pts {
                XCTAssertEqual(p.x, min(max(p.x, 18), live.width - 18), accuracy: 6,
                               "\(key) clamps >6 pt on the live watch")
                XCTAssertEqual(p.y, min(max(p.y, 16), live.height - 16), accuracy: 6,
                               "\(key) clamps >6 pt on the live watch")
            }
        }

        // Key routing: shock root only, and every grp:* parent that was edited.
        XCTAssertEqual(FanLayoutOverrides.key(forRootAnchor: "shock"), "shockRoot")
        XCTAssertNil(FanLayoutOverrides.key(forRootAnchor: "events"))
        let mapping = [("grp:access", "access"), ("grp:airway", "airway"),
                       ("grp:comms", "comms"), ("grp:call", "call"),
                       ("grp:arrival", "arrival"), ("grp:temp", "temp"),
                       ("grp:fluids", "fluids"), ("grp:more", "moreVol"),
                       ("grp:defib", "defib")]
        for (gid, key) in mapping {
            XCTAssertEqual(FanLayoutOverrides.key(forParentItem: gid), key)
            XCTAssertNotNil(FanLayoutOverrides.table[FanLayoutOverrides.key(forParentItem: gid)!])
        }
    }
}

@MainActor
final class SessionEngineTests: XCTestCase {

    private func makeEngine(start: Date) -> SessionEngine {
        SessionEngine(protocolDef: Defaults.palsArrest,
                      drugSet: Defaults.palsDrugSet,
                      eventDefs: Defaults.builtInEvents,
                      patient: PatientContext(weightKg: 10, weightSource: .manual),
                      startDate: start)
    }

    func testCycleCountdownGoesOverdueUntilPulseCheck() {
        // Cycles no longer wrap on the wall clock: the countdown runs negative
        // until a pulse check completes, which is what closes the cycle.
        let start = Date(timeIntervalSince1970: 1_000_000)
        let engine = makeEngine(start: start)
        engine.startCPR(at: start)
        XCTAssertEqual(engine.cycleRemaining(at: start), 120, accuracy: 0.01)
        XCTAssertEqual(engine.cycleRemaining(at: start.addingTimeInterval(30)), 90, accuracy: 0.01)
        XCTAssertEqual(engine.cycleRemaining(at: start.addingTimeInterval(125)), -5, accuracy: 0.01)
        XCTAssertEqual(engine.cycleIndex(at: start.addingTimeInterval(125)), 0)   // still cycle 1

        engine.beginPulseCheck(at: start.addingTimeInterval(130))
        // Frozen mid-check, and the check clock runs on its own.
        XCTAssertEqual(engine.cycleRemaining(at: start.addingTimeInterval(137)), -10, accuracy: 0.01)
        XCTAssertEqual(engine.pulseCheckElapsed(at: start.addingTimeInterval(137)), 7, accuracy: 0.01)

        engine.completePulseCheck(pulseFound: false, at: start.addingTimeInterval(140))
        XCTAssertEqual(engine.cycleIndex(at: start.addingTimeInterval(140)), 1)
        XCTAssertEqual(engine.cycleRemaining(at: start.addingTimeInterval(140)), 120, accuracy: 0.01)
        // The 10 s hands-off interval counts against the CPR fraction…
        XCTAssertEqual(engine.session.pauses.count, 1)
        XCTAssertEqual(engine.session.pauses[0].seconds(clampedTo: start.addingTimeInterval(999)),
                       10, accuracy: 0.01)
        // …and both bookends land in the log.
        XCTAssertTrue(engine.session.events.contains { $0.definitionID == "pulse.check" })
        XCTAssertTrue(engine.session.events.contains { $0.definitionID == "pulse.resume" })
    }

    func testPulseFoundFlowsIntoROSC() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let engine = makeEngine(start: start)
        engine.startCPR(at: start)
        engine.beginPulseCheck(at: start.addingTimeInterval(120))
        engine.completePulseCheck(pulseFound: true, at: start.addingTimeInterval(128))
        XCTAssertTrue(engine.roscAchieved)
        XCTAssertFalse(engine.isInPulseCheck)
        XCTAssertNotNil(engine.session.pauses[0].end)
        XCTAssertTrue(engine.session.events.contains { $0.definitionID == "pulse.found" })
    }

    func testDrugIntervalRunsThroughPulseCheck() {
        // Same clinical rule as pauses: hands-off never freezes drug timers.
        let start = Date(timeIntervalSince1970: 1_000_000)
        let engine = makeEngine(start: start)
        let epiSpec = Defaults.palsArrest.intervalSpecs[0]
        engine.startCPR(at: start)
        engine.logDrug(Defaults.epinephrine, at: start)   // interval starts at first dose
        engine.beginPulseCheck(at: start.addingTimeInterval(100))
        engine.completePulseCheck(pulseFound: false, at: start.addingTimeInterval(115))
        XCTAssertEqual(engine.intervalRemaining(epiSpec, at: start.addingTimeInterval(115)),
                       65, accuracy: 0.01)   // 180 − 115, untouched by the check
    }

    func testRunningTimersListTotalAndSinceLast() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let engine = makeEngine(start: start)
        engine.logDrug(Defaults.epinephrine, at: start.addingTimeInterval(60))
        engine.logDrug(Defaults.epinephrine, at: start.addingTimeInterval(240))
        let now = start.addingTimeInterval(300)
        let timers = engine.session.runningTimers(at: now)
        XCTAssertEqual(timers.first?.id, "total")
        XCTAssertEqual(timers.first?.elapsed(at: now) ?? 0, 300, accuracy: 0.01)
        // Only the LATEST epi drives its since-last timer.
        let epi = timers.first { $0.id == Defaults.epiID.uuidString }
        XCTAssertEqual(epi?.elapsed(at: now) ?? 0, 60, accuracy: 0.01)
    }

    func testRunningTimersOnlyTrackRepeatables() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let engine = makeEngine(start: start)
        engine.startCPR(at: start)
        engine.logDrug(Defaults.epinephrine, at: start.addingTimeInterval(60))
        let access = Defaults.builtInEvents.first { $0.id == "access.iv" }!
        engine.logEvent(access, subOption: "R arm", at: start.addingTimeInterval(70))
        let tube = Defaults.builtInEvents.first { $0.id == "airway.ett" }!
        engine.logEvent(tube, at: start.addingTimeInterval(80))
        let swap = Defaults.builtInEvents.first { $0.id == "cpr.swap" }!
        engine.logEvent(swap, at: start.addingTimeInterval(90))

        let ids = Set(engine.session.runningTimers(at: start.addingTimeInterval(100)).map(\.id))
        XCTAssertTrue(ids.contains("total"))
        XCTAssertTrue(ids.contains(Defaults.epiID.uuidString))   // med — repeatable
        XCTAssertTrue(ids.contains("cpr.swap"))                  // swap — repeatable
        XCTAssertFalse(ids.contains("access.iv"))                // one-shots: no timer
        XCTAssertFalse(ids.contains("airway.ett"))
        XCTAssertFalse(ids.contains("cpr.start"))
    }

    func testPauseFreezesCycleAndRecordsInterval() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let engine = makeEngine(start: start)
        engine.startCPR(at: start)
        engine.togglePause(at: start.addingTimeInterval(40))          // pause at t+40
        let frozen = engine.cycleRemaining(at: start.addingTimeInterval(70))
        XCTAssertEqual(frozen, 80, accuracy: 0.01)                    // still shows 80s left
        engine.togglePause(at: start.addingTimeInterval(70))          // resume after 30s gap
        XCTAssertEqual(engine.cycleRemaining(at: start.addingTimeInterval(70)), 80, accuracy: 0.01)
        XCTAssertEqual(engine.session.pauses.count, 1)
        XCTAssertEqual(engine.session.pauses[0].seconds(clampedTo: start.addingTimeInterval(999)),
                       30, accuracy: 0.01)
    }

    func testEpiIntervalIdleUntilFirstDoseThenResets() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let engine = makeEngine(start: start)
        let epiSpec = Defaults.palsArrest.intervalSpecs[0]
        // Idle before any dose: no countdown, never overdue.
        XCTAssertFalse(engine.intervalIsRunning(epiSpec))
        XCTAssertFalse(engine.intervalIsOverdue(epiSpec, at: start.addingTimeInterval(999)))
        XCTAssertEqual(engine.intervalRemaining(epiSpec, at: start.addingTimeInterval(100)),
                       180, accuracy: 0.01)   // reports full length while idle

        engine.logDrug(Defaults.epinephrine, at: start.addingTimeInterval(100))
        XCTAssertTrue(engine.intervalIsRunning(epiSpec))
        XCTAssertEqual(engine.intervalRemaining(epiSpec, at: start.addingTimeInterval(160)),
                       120, accuracy: 0.01)   // counting from the dose, not GO
        // Second dose resets the countdown.
        engine.logDrug(Defaults.epinephrine, at: start.addingTimeInterval(220))
        XCTAssertEqual(engine.intervalRemaining(epiSpec, at: start.addingTimeInterval(220)),
                       180, accuracy: 0.01)
        XCTAssertEqual(engine.session.events.filter { $0.category == .medication }.count, 2)
    }

    func testStartCPRGatesCycleAndPulseCheck() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let engine = makeEngine(start: start)
        // Before Start CPR: ring stays full, pulse checks refuse to begin,
        // but the code clock (GO) is already running.
        XCTAssertEqual(engine.cycleRemaining(at: start.addingTimeInterval(500)), 120, accuracy: 0.01)
        engine.beginPulseCheck(at: start.addingTimeInterval(10))
        XCTAssertFalse(engine.isInPulseCheck)
        XCTAssertEqual(engine.elapsed(at: start.addingTimeInterval(500)), 500, accuracy: 0.01)

        engine.startCPR(at: start.addingTimeInterval(45))
        XCTAssertEqual(engine.cycleRemaining(at: start.addingTimeInterval(65)), 100, accuracy: 0.01)
        XCTAssertTrue(engine.session.events.contains { $0.definitionID == "cpr.start" })
    }

    func testLoggedEventCarriesItemColor() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let engine = makeEngine(start: start)
        engine.startCPR(at: start)
        // A volume/support drug's timer must show BLUE, not the red med category.
        engine.logDrug(Defaults.calcium, at: start.addingTimeInterval(30))
        let ca = engine.session.events.last { $0.category == .medication }
        XCTAssertEqual(ca?.tintHex, CRTheme.volumeHex)
        let timer = engine.session.runningTimers(at: start.addingTimeInterval(60))
            .first { $0.id == Defaults.calciumID.uuidString }
        XCTAssertEqual(timer?.colorHex, CRTheme.volumeHex)
    }

    func testWeightChangeUpdatesDosesAndLogs() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let engine = makeEngine(start: start)
        engine.updateWeight(20, at: start.addingTimeInterval(30))
        // The change is on the record…
        let change = engine.session.events.first { $0.definitionID == "patient.weight" }
        XCTAssertEqual(change?.detail, "10.0 → 20.0 kg")
        // …and the next dose computes from the NEW weight (0.01 mg/kg × 20).
        engine.logDrug(Defaults.epinephrine, at: start.addingTimeInterval(60))
        let epi = engine.session.events.last { $0.category == .medication }
        XCTAssertTrue(epi?.detail?.contains("0.2 mg") ?? false,
                      "dose detail was \(epi?.detail ?? "nil")")
    }

    func testRoscClosesPauseAndStopsFurtherPauses() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let engine = makeEngine(start: start)
        engine.togglePause(at: start.addingTimeInterval(10))
        engine.markROSC(at: start.addingTimeInterval(20))
        XCTAssertTrue(engine.roscAchieved)
        XCTAssertNotNil(engine.session.pauses[0].end)
        engine.togglePause(at: start.addingTimeInterval(30))          // ignored post-ROSC
        XCTAssertFalse(engine.isPaused)
    }

    func testReArrestReturnsToCPRAndKeepsFirstROSC() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let engine = makeEngine(start: start)
        engine.markROSC(at: start.addingTimeInterval(100))
        XCTAssertTrue(engine.roscAchieved)

        engine.reArrest(at: start.addingTimeInterval(200))
        XCTAssertFalse(engine.roscAchieved)
        // Fresh cycle from the re-arrest moment; pauses work again.
        XCTAssertEqual(engine.cycleRemaining(at: start.addingTimeInterval(230)), 90, accuracy: 0.01)
        engine.togglePause(at: start.addingTimeInterval(240))
        XCTAssertTrue(engine.isPaused)
        engine.togglePause(at: start.addingTimeInterval(250))

        // Second ROSC: live state flips back, roscDate still records the FIRST.
        engine.markROSC(at: start.addingTimeInterval(300))
        XCTAssertTrue(engine.roscAchieved)
        XCTAssertEqual(engine.session.roscDate, start.addingTimeInterval(100))
        XCTAssertEqual(engine.roscElapsed(at: start.addingTimeInterval(360)), 60, accuracy: 0.01)
        XCTAssertTrue(engine.session.events.contains { $0.definitionID == "outcome.rearrest" })
        XCTAssertEqual(engine.session.events.filter { $0.definitionID == "outcome.rosc" }.count, 2)
    }

    func testVitalsCadenceRunsOnlyInROSC() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let engine = makeEngine(start: start)
        XCTAssertNil(engine.vitalsRemaining(at: start.addingTimeInterval(10)))

        engine.markROSC(at: start.addingTimeInterval(100))
        XCTAssertEqual(engine.vitalsRemaining(at: start.addingTimeInterval(200)) ?? 0,
                       200, accuracy: 0.01)   // 300 s cadence, 100 s in
        // Overdue goes negative, same convention as the pulse check.
        XCTAssertEqual(engine.vitalsRemaining(at: start.addingTimeInterval(450)) ?? 0,
                       -50, accuracy: 0.01)

        engine.confirmVitals(at: start.addingTimeInterval(450))
        XCTAssertEqual(engine.vitalsRemaining(at: start.addingTimeInterval(500)) ?? 0,
                       250, accuracy: 0.01)
        XCTAssertTrue(engine.session.events.contains { $0.definitionID == "rosc.vitals" })

        engine.reArrest(at: start.addingTimeInterval(600))
        XCTAssertNil(engine.vitalsRemaining(at: start.addingTimeInterval(610)))
    }

    func testStatsCprFraction() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let engine = makeEngine(start: start)
        engine.togglePause(at: start.addingTimeInterval(30))
        engine.togglePause(at: start.addingTimeInterval(60))          // 30s paused
        engine.end(at: start.addingTimeInterval(120))                 // 120s total
        let stats = engine.session.stats
        XCTAssertEqual(stats.cprFraction, 0.75, accuracy: 0.01)       // 90/120
        XCTAssertEqual(stats.pauseCount, 1)
    }
}

final class AppSettingsCodableTests: XCTestCase {

    /// Settings written by older builds (fields missing from the JSON) must
    /// load with defaults instead of failing — menuTapOnly ships after 1.0.
    func testMissingFieldsDecodeToDefaults() throws {
        let settings = try JSONDecoder().decode(AppSettings.self,
                                                from: Data("{}".utf8))
        XCTAssertEqual(settings, AppSettings())
        XCTAssertFalse(settings.menuTapOnly)
    }

    func testMenuTapOnlyRoundTrips() throws {
        var settings = AppSettings()
        settings.menuTapOnly = true
        let decoded = try JSONDecoder().decode(AppSettings.self,
                                               from: JSONEncoder().encode(settings))
        XCTAssertTrue(decoded.menuTapOnly)
    }
}

@MainActor
final class UndoLastEntryTests: XCTestCase {

    private func makeEngine(start: Date) -> SessionEngine {
        SessionEngine(protocolDef: Defaults.palsArrest,
                      drugSet: Defaults.palsDrugSet,
                      eventDefs: Defaults.builtInEvents,
                      patient: PatientContext(weightKg: 10, weightSource: .manual),
                      startDate: start)
    }

    func testUndoRevertsIntervalAnchorAndLadder() throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let engine = makeEngine(start: start)
        engine.startCPR(at: start)
        let epi = try XCTUnwrap(Defaults.palsDrugSet.drugs.first { $0.id == Defaults.epiID })
        let spec = try XCTUnwrap(engine.protocolDef.intervalSpecs.first)

        engine.logDrug(epi, at: start.addingTimeInterval(10))
        engine.logDrug(epi, at: start.addingTimeInterval(70))
        XCTAssertEqual(engine.intervalRemaining(spec, at: start.addingTimeInterval(70)),
                       spec.seconds, accuracy: 0.01)

        let removed = engine.undoLastEntry()
        XCTAssertEqual(removed?.definitionID, epi.id.uuidString)
        // Anchor rolled back to the surviving first dose (t+10).
        XCTAssertEqual(engine.intervalRemaining(spec, at: start.addingTimeInterval(70)),
                       spec.seconds - 60, accuracy: 0.01)
        XCTAssertEqual(engine.session.events.filter { $0.definitionID == epi.id.uuidString }.count, 1)

        _ = engine.undoLastEntry()
        XCTAssertFalse(engine.intervalIsRunning(spec), "no doses left — timer must go idle")
    }

    func testUndoSkipsStructuralEventsAndStopsWhenNoneLeft() throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let engine = makeEngine(start: start)
        engine.startCPR(at: start)
        let amio = try XCTUnwrap(Defaults.palsDrugSet.drugs.first { $0.id == Defaults.amioID })

        engine.logDrug(amio, at: start.addingTimeInterval(5))
        engine.beginPulseCheck(at: start.addingTimeInterval(20))   // structural, sits on top

        let removed = engine.undoLastEntry()
        XCTAssertEqual(removed?.definitionID, amio.id.uuidString,
                       "undo must reach past the pulse-check record")
        XCTAssertTrue(engine.session.events.contains { $0.definitionID == "pulse.check" })
        XCTAssertTrue(engine.session.events.contains { $0.definitionID == "cpr.start" })
        XCTAssertNil(engine.undoLastEntry(), "only structural records remain")
    }
}

/// The exit pads (✕ / back) used to be drawn on top of the bottom anchor
/// pucks — ✕ landed squarely on the meds puck, so the two read as one
/// control and a tap on ✕ re-opened the meds fan instead of closing.
/// Geometry, not hit-testing, is what keeps them distinguishable.
final class TopArcLayoutTests: XCTestCase {

    /// Live GeometryReader on the 45 mm Series 9 (probe-measured 2026-07-23).
    private let bounds = CGSize(width: 194, height: 191)

    // The two exit-pad tests that lived here moved to `FanLayoutTests` when
    // the pads left fan space for shared SCREEN constants on 2026-08-29.
    // `TopArcLayout` no longer knows anything about them.

    /// Fixed slots are the whole point — a 2-item fan and a 4-item fan must
    /// share pitch and row height so muscle memory survives across fans.
    func testArcSlotsAreFixedPitchAndOnScreen() {
        for count in 1...6 {
            let pts = TopArcLayout.positions(count: count, bounds: bounds)
            XCTAssertEqual(pts.count, count)
            for p in pts {
                XCTAssertGreaterThanOrEqual(p.x, 18, "count \(count): slot off the left edge")
                XCTAssertLessThanOrEqual(p.x, bounds.width - 18, "count \(count): slot off the right edge")
                XCTAssertGreaterThanOrEqual(p.y, 16, "count \(count): slot off the top edge")
            }
            // Neighbours within a row never come closer than a bubble width.
            let top = TopArcLayout.topRowCount(count)
            for i in 1..<max(1, top) {
                XCTAssertGreaterThanOrEqual(hypot(pts[i].x - pts[i-1].x, pts[i].y - pts[i-1].y), 40,
                                            "count \(count): row-0 slots \(i-1)/\(i) too close")
            }
        }
    }
}

// MARK: - FanLayout

/// The submenu counterpart to `WatchLayoutTests`: the hand-placeable fan
/// table has to stay on-screen, stay reachable, and — until Sebastian moves
/// something — stay byte-identical to the top arc it replaced.
final class FanLayoutTests: XCTestCase {

    private let bounds = FanLayout.bounds

    /// Anchor pucks in SCREEN points — the space the exit pads now live in.
    private var puckCentres: [CGPoint] {
        [WatchLayout.medsPuck, WatchLayout.eventsPuck,
         WatchLayout.fluidsPuck, WatchLayout.shockPuck].map(\.center)
    }

    private func toScreen(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x + WatchLayout.liveInset.x, y: p.y + WatchLayout.liveInset.y)
    }

    /// An `.arc(n)` seed must reproduce exactly what the top arc computes.
    /// Once a fan is hand-placed its `placed` flag turns true and it drops
    /// out of this check — but never out of the geometry checks below.
    func testSeededFansStillMatchTheTopArc() {
        for (key, fan) in FanLayout.table where !fan.placed {
            let n = fan.slots.count
            let arc = TopArcLayout.positions(count: n, bounds: bounds)
            XCTAssertEqual(arc.count, n, "\(key): seed count disagrees with TopArcLayout")
            for (i, p) in arc.enumerated() {
                let want = FanLayout.clampBubble(p)
                XCTAssertEqual(fan.slots[i].center.x, want.x, accuracy: 0.001,
                               "\(key) slot \(i): seeded x drifted from the top arc")
                XCTAssertEqual(fan.slots[i].center.y, want.y, accuracy: 0.001,
                               "\(key) slot \(i): seeded y drifted from the top arc")
            }
        }
    }

    /// Sebastian's rule, 2026-08-29: every label shares its button's x and
    /// leaves exactly 4 pt between the button's bottom EDGE and the top of
    /// the label box. Measured from the edge, so it survives a resize.
    func testLabelsSitFourPointsUnderTheirButton() {
        for (key, fan) in FanLayout.table where !fan.placed {
            for (i, s) in fan.slots.enumerated() {
                XCTAssertEqual(s.label.x, s.center.x, accuracy: 0.001,
                               "\(key) label \(i) is not centred on its button")
                let buttonBottom = s.center.y + s.diameter / 2
                let labelTop = s.label.y - TopArcLayout.labelBoxHeight / 2
                XCTAssertEqual(labelTop - buttonBottom, TopArcLayout.labelGap, accuracy: 0.001,
                               "\(key) label \(i): gap under the button is wrong")
            }
        }
    }

    /// Every button is Ø44 with a 25 pt glyph — bubbles, ✕ and Back alike.
    func testEveryButtonIsTheSameSize() {
        for (key, fan) in FanLayout.table {
            for (i, s) in fan.slots.enumerated() {
                XCTAssertEqual(s.diameter, 44, "\(key) slot \(i) is not Ø44")
                XCTAssertEqual(s.glyph, 25, "\(key) slot \(i) glyph is not 25 pt")
            }
        }
        for pad in [FanLayout.Pads.cancel, FanLayout.Pads.back] {
            XCTAssertEqual(pad.diameter, 44, "exit pad is not Ø44")
            XCTAssertEqual(pad.glyph, 25, "exit pad glyph is not 25 pt")
        }
    }

    /// Every bubble fully on screen. A bubble whose rim runs off the edge is
    /// a leaf that cannot be hit.
    func testEveryBubbleIsFullyOnScreen() {
        for (key, fan) in FanLayout.table {
            for (i, s) in fan.slots.enumerated() {
                let r = s.diameter / 2
                XCTAssertGreaterThanOrEqual(s.center.x - r, 0, "\(key) slot \(i) off the left edge")
                XCTAssertLessThanOrEqual(s.center.x + r, bounds.width, "\(key) slot \(i) off the right edge")
                XCTAssertGreaterThanOrEqual(s.center.y - r, 0, "\(key) slot \(i) off the top edge")
                XCTAssertLessThanOrEqual(s.center.y + r, bounds.height, "\(key) slot \(i) off the bottom edge")
            }
        }
    }

    /// Neighbouring bubbles must not overlap — hover flaps between two that
    /// touch, and on a wrist that reads as "it logged nothing".
    func testBubblesNeverOverlap() {
        for (key, fan) in FanLayout.table {
            for i in fan.slots.indices {
                for j in fan.slots.indices where j > i {
                    let a = fan.slots[i], b = fan.slots[j]
                    XCTAssertGreaterThanOrEqual(
                        hypot(a.center.x - b.center.x, a.center.y - b.center.y),
                        (a.diameter + b.diameter) / 2,
                        "\(key): bubbles \(i) and \(j) overlap")
                }
            }
        }
    }

    /// Pads MAY overlap the controls beneath them — but only the ones we
    /// meant. The 2026-08-22 ✕ bug was an overlap where the pad was drawn
    /// UNDER the puck, so cancel re-opened a fan instead of closing one.
    /// Now the pads are drawn in the chrome layer, above the radial layer and
    /// above the scrim, so wherever they overlap they take the touch.
    ///
    /// Sebastian put ✕ deliberately in the gap between the Events and Shock
    /// pucks, which at Ø44 means it clips both — fine, and it reads well on
    /// screen. Back sits on the Log button for the same reason. This test
    /// pins that exact set, so a NEW overlap (a puck moving under a pad, say)
    /// still fails loudly instead of silently becoming a dead control.
    func testExitPadOverlapsAreExactlyTheDeliberateOnes() {
        let controls: [(String, CGPoint, CGFloat)] = [
            ("meds puck", WatchLayout.medsPuck.center, WatchLayout.medsPuck.diameter),
            ("events puck", WatchLayout.eventsPuck.center, WatchLayout.eventsPuck.diameter),
            ("fluids puck", WatchLayout.fluidsPuck.center, WatchLayout.fluidsPuck.diameter),
            ("shock puck", WatchLayout.shockPuck.center, WatchLayout.shockPuck.diameter),
            ("log", WatchLayout.logButton.center, WatchLayout.logButton.diameter),
            ("timers", WatchLayout.timersButton.center, WatchLayout.timersButton.diameter),
            ("mute", WatchLayout.muteButton.center, WatchLayout.muteButton.diameter),
            ("flag", WatchLayout.flagButton.center, WatchLayout.flagButton.diameter)
        ]
        func overlaps(_ pad: FanLayout.Pad) -> Set<String> {
            Set(controls.filter { _, c, d in
                hypot(pad.center.x - c.x, pad.center.y - c.y) < (pad.diameter + d) / 2
            }.map(\.0))
        }
        XCTAssertEqual(overlaps(FanLayout.Pads.cancel), ["events puck", "shock puck"],
                       "✕ now covers a different set of controls than intended")
        XCTAssertEqual(overlaps(FanLayout.Pads.back), ["log"],
                       "Back now covers a different set of controls than intended")
    }

    /// …and never over a bubble, in any fan — the same failure one layer up.
    func testExitPadsClearEveryBubble() {
        for (key, fan) in FanLayout.table {
            for pad in [FanLayout.Pads.cancel, FanLayout.Pads.back] {
                for (i, s) in fan.slots.enumerated() {
                    let c = toScreen(s.center)
                    XCTAssertGreaterThan(
                        hypot(pad.center.x - c.x, pad.center.y - c.y),
                        (pad.diameter + s.diameter) / 2,
                        "\(key): exit pad sits on bubble \(i)")
                }
            }
        }
    }

    /// Both pads must be fully on the physical screen.
    func testExitPadsAreOnScreen() {
        for pad in [FanLayout.Pads.cancel, FanLayout.Pads.back] {
            let r = pad.diameter / 2
            XCTAssertGreaterThanOrEqual(pad.center.x - r, 0)
            XCTAssertGreaterThanOrEqual(pad.center.y - r, 0)
            XCTAssertLessThanOrEqual(pad.center.x + r, WatchLayout.screen.width)
            XCTAssertLessThanOrEqual(pad.center.y + r, WatchLayout.screen.height)
        }
    }

    /// Labels stay inside the fan box the overlay draws them in.
    func testLabelsStayOnScreen() {
        for (key, fan) in FanLayout.table {
            for (i, s) in fan.slots.enumerated() {
                XCTAssertGreaterThanOrEqual(s.label.x, 0, "\(key) label \(i) off the left edge")
                XCTAssertLessThanOrEqual(s.label.x, bounds.width, "\(key) label \(i) off the right edge")
                XCTAssertGreaterThanOrEqual(s.label.y, 0, "\(key) label \(i) off the top edge")
                XCTAssertLessThanOrEqual(s.label.y, bounds.height, "\(key) label \(i) off the bottom edge")
            }
        }
    }

    /// A label must never land on another button.
    ///
    /// The first version of this test only compared vertical bands and used a
    /// fixed x tolerance, so it passed while the Bench — which measures the
    /// real rendered text — showed "SUBSEQUENT · 40 J" clipping the buttons on
    /// either side of it. Labels are WIDE; a centre label on a three-slot row
    /// reaches into both neighbours. Estimate the width the same way the
    /// overlay lays it out: ~0.62 em per character, capped at labelWidth.
    func testLabelsNeverCoverAnotherButton() {
        for (key, fan) in FanLayout.table {
            for (i, lab) in fan.slots.enumerated() {
                let w = min(lab.labelWidth,
                            CGFloat(FanLayout.titles[key]?[i].count ?? 10) * lab.labelFont * 0.62) + 8
                let h = TopArcLayout.labelBoxHeight
                let l = CGRect(x: lab.label.x - w / 2, y: lab.label.y - h / 2, width: w, height: h)
                for (j, other) in fan.slots.enumerated() where j != i {
                    // 1 pt of slack. The Bench measures each label's REAL
                    // rendered height to apply the 4 pt rule; this test uses
                    // the app's nominal 13.5. The two disagree by a few
                    // tenths, which shows up as a hairline touch on a layout
                    // that is actually correct — five of Sebastian's slots
                    // land exactly 0.43 pt over. Labels also draw after
                    // bubbles, so their own background covers the sliver.
                    // A real collision is points, not tenths.
                    let b = CGRect(x: other.center.x - other.diameter / 2 + 1,
                                   y: other.center.y - other.diameter / 2 + 1,
                                   width: other.diameter - 2, height: other.diameter - 2)
                    XCTAssertFalse(l.intersects(b),
                                   "\(key): label \(i) overlaps button \(j)")
                }
            }
        }
    }

    /// Lookup is count-exact on purpose: the defib ladder and the events fan
    /// are both built at runtime, and stretching a 6-slot placement over a
    /// 7-item fan would drop the last item somewhere undefined.
    func testLookupRefusesACountMismatch() {
        XCTAssertNotNil(FanLayout.fan("events", count: 6))
        XCTAssertNil(FanLayout.fan("events", count: 7),
                     "a custom event was added — that fan must fall back to the computed arc")
        XCTAssertNil(FanLayout.fan("no.such.fan", count: 3))
    }

    /// The inventory itself, so a menu-tree edit that changes a fan's size
    /// fails here instead of silently falling back to the arc on the wrist.
    func testTableCoversEveryFanAtItsRealCount() {
        let expected: [String: Int] = [
            "code": 5, "shock": 2, "support": 5, "events": 6, "events.rosc": 5,
            "grp:defib": 3, "grp:fluids": 3, "grp:more": 3, "grp:access": 3,
            "grp:airway": 4, "grp:comms": 2, "grp:temp": 3,
            "grp:call": 4, "grp:arrival": 4
        ]
        XCTAssertEqual(Set(FanLayout.table.keys), Set(expected.keys),
                       "FanLayout.table and the live menu trees have diverged")
        for (key, count) in expected {
            XCTAssertEqual(FanLayout.table[key]?.slots.count, count,
                           "\(key) should render \(count) items")
        }
    }
}
