// The Swift half of the parity harness — the twin of scenario.c.
// Keep the two files line-for-line parallel.

import CodeCore
import Foundation

let start = Date(timeIntervalSince1970: 1_000_000)
func T(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }
func ms(_ interval: TimeInterval) -> Int { Int((interval * 1000).rounded()) }

@MainActor
func printLog(_ engine: SessionEngine) {
    for event in engine.session.events {
        print("EVENT \(crOffset(event.offsetSeconds)) | \(event.title) | "
              + "\(event.detail ?? "-") | \(event.category.rawValue) | \(event.tintHex)")
    }
}

@MainActor
func printClock(_ engine: SessionEngine, _ at: TimeInterval) {
    let now = T(at)
    let vitals = engine.vitalsRemaining(at: now).map { String(ms($0)) } ?? "-"
    print("CLOCK t=\(Int(at)) elapsed=\(ms(engine.elapsed(at: now)))"
          + " cycleRem=\(ms(engine.cycleRemaining(at: now)))"
          + " idx=\(engine.cycleIndex(at: now))"
          + " pc=\(ms(engine.pulseCheckElapsed(at: now)))"
          + " rosc=\(ms(engine.roscElapsed(at: now)))"
          + " vitals=\(vitals) | \(engine.hint(at: now))")

    for spec in engine.protocolDef.intervalSpecs {
        print("INTERVAL t=\(Int(at)) \(spec.id)"
              + " run=\(engine.intervalIsRunning(spec) ? 1 : 0)"
              + " rem=\(ms(engine.intervalRemaining(spec, at: now)))"
              + " overdue=\(engine.intervalIsOverdue(spec, at: now) ? 1 : 0)")
    }
}

@MainActor
func printTimers(_ engine: SessionEngine, _ at: TimeInterval) {
    for timer in engine.session.runningTimers(at: T(at)) {
        print("TIMER \(timer.id) | \(timer.title) | \(ms(timer.elapsed(at: T(at)))) | \(timer.colorHex)")
    }
}

@MainActor
func printStats(_ engine: SessionEngine) {
    let s = engine.session.stats
    let firstEpi = s.secondsToFirstEpi.map(String.init) ?? "-"
    let rosc = s.secondsToROSC.map(String.init) ?? "-"
    print("STATS total=\(ms(s.totalSeconds)) paused=\(ms(s.pausedSeconds))"
          + " frac=\(String(format: "%.3f", s.cprFraction)) pauses=\(s.pauseCount)"
          + " epi=\(s.epiCount) shocks=\(s.shockCount) rhythm=\(s.rhythmCheckCount)"
          + " firstEpi=\(firstEpi) rosc=\(rosc)")
    // Sorted by name: the tally is a dictionary, which has no order.
    for name in s.medEvents.keys.sorted() {
        print("MED \(name) = \(s.medEvents[name] ?? 0)")
    }
}

@MainActor
func run() {
    let engine = SessionEngine(protocolDef: Defaults.palsArrest,
                               drugSet: Defaults.palsDrugSet,
                               eventDefs: Defaults.builtInEvents,
                               patient: PatientContext(weightKg: 10, weightSource: .manual),
                               startDate: start,
                               deviceName: "parity")
    let access = Defaults.builtInEvents.first { $0.id == "access.iv" }!
    let ett = Defaults.builtInEvents.first { $0.id == "airway.ett" }!

    printClock(engine, 0)
    engine.startCPR(at: T(5))
    printClock(engine, 20)

    engine.logDrug(Defaults.epinephrine, at: T(30))
    engine.logEvent(access, subOption: "R leg", at: T(41))
    printClock(engine, 60)

    engine.togglePause(at: T(70))
    printClock(engine, 85)
    engine.togglePause(at: T(90))
    printClock(engine, 95)

    engine.logDrug(Defaults.defibrillation, forcedStepIndex: 1, at: T(101))   // "Subsequent"
    engine.logDrug(Defaults.adenosine, at: T(112))                            // ladder rung 1
    engine.logDrug(Defaults.adenosine, at: T(123))                            // ladder rung 2
    engine.logDrug(Defaults.fluids, forcedStepIndex: 1, at: T(134))           // 20 mL/kg
    printClock(engine, 140)

    engine.beginPulseCheck(at: T(150))
    printClock(engine, 158)
    engine.completePulseCheck(pulseFound: false, at: T(162))
    printClock(engine, 170)

    engine.updateWeight(24, at: T(181))
    engine.logDrug(Defaults.epinephrine, at: T(192))                          // recomputed from 24 kg
    engine.logEvent(ett, at: T(203))
    engine.logEvent(title: "Cardioversion", detail: "50 J", category: .defibrillation,
                    definitionID: "shock.sync", colorHex: CRTheme.shockHex, at: T(214))
    printClock(engine, 220)
    printTimers(engine, 220)

    if let removed = engine.undoLastEntry() { print("UNDO \(removed.title)") }

    engine.beginPulseCheck(at: T(230))
    engine.completePulseCheck(pulseFound: true, at: T(238))                   // pulse found → ROSC
    printClock(engine, 250)

    engine.confirmVitals(at: T(300))
    printClock(engine, 400)
    engine.reArrest(at: T(500))
    printClock(engine, 520)
    engine.logDrug(Defaults.amiodarone, at: T(531))
    engine.markROSC(at: T(560))
    printClock(engine, 580)

    _ = engine.end(at: T(600))
    printClock(engine, 610)
    printTimers(engine, 610)
    printLog(engine)
    printStats(engine)
}

MainActor.assumeIsolated { run() }
