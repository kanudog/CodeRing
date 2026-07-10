// SessionEngine.swift — the beating heart. Owns the live session.
// Design rules:
//   • The engine holds anchor DATES and computes remaining time from `now`
//     passed in by the UI (TimelineView tick). No internal Timer, no drift,
//     fully unit-testable.
//   • CPR cycle freezes during pause (anchor slides forward on resume).
//   • Drug interval timers (epi) keep running through pauses — intentional.
//   • Every action is one method; views never mutate the session directly.

import Foundation
import Observation

@MainActor
@Observable
public final class SessionEngine {

    public private(set) var session: CodeSession
    public let protocolDef: CodeProtocolDefinition
    public let drugSet: DrugProfileSet
    public let eventDefs: [EventDefinition]

    public private(set) var isPaused = false
    public private(set) var isEnded = false
    /// GO starts the code clock; compressions start when the team says so.
    /// Until then the cycle ring sits full behind a "Start CPR" button.
    public private(set) var cprStarted = false
    /// A pulse check is a deliberate hands-off interval: it records pause time
    /// for the CPR fraction and, on completion, closes the CPR cycle.
    public private(set) var isInPulseCheck = false
    /// Live ROSC state — stored, not derived from roscDate, because a
    /// re-arrest drops back into CPR while the first ROSC time stays on record.
    public private(set) var roscAchieved = false

    private var cycleAnchor: Date
    private var pauseStartedAt: Date?
    private var pulseCheckStartedAt: Date?
    /// Latest ROSC (re-arrests can produce several); drives the post-ROSC clock.
    private var lastROSCAt: Date?
    /// Post-ROSC reassessment cadence anchor (ROSC or last confirmed vitals).
    private var vitalsAnchor: Date?
    /// Cycles only complete through a pulse check — the countdown runs
    /// negative until the team confirms one, so overdue time stays visible.
    private var completedCycles = 0
    /// timer spec id → date of last reset (start of code, or last linked drug given)
    private var intervalAnchors: [String: Date] = [:]

    public init(protocolDef: CodeProtocolDefinition,
                drugSet: DrugProfileSet,
                eventDefs: [EventDefinition],
                patient: PatientContext,
                startDate: Date = Date(),
                deviceName: String = "") {
        self.protocolDef = protocolDef
        self.drugSet = drugSet
        self.eventDefs = eventDefs
        self.session = CodeSession(protocolID: protocolDef.id,
                                   protocolName: protocolDef.name,
                                   startDate: startDate,
                                   patient: patient,
                                   deviceName: deviceName)
        self.cycleAnchor = startDate
        // Drug-interval timers stay IDLE until the first dose — a countdown
        // for a med nobody has given yet reads as a false order.
    }

    // MARK: - Clock

    public func elapsed(at now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(session.startDate))
    }

    /// Seconds until the pulse check that ends this CPR cycle. Runs NEGATIVE
    /// once overdue — the cycle only closes when a pulse check completes, so
    /// the team always sees how far past the deadline they are. Frozen while
    /// paused or mid-check.
    public func cycleRemaining(at now: Date) -> TimeInterval {
        guard let spec = protocolDef.cycleSpec else { return 0 }
        guard cprStarted else { return spec.seconds }   // full ring, waiting on Start CPR
        let effectiveNow = pauseStartedAt ?? pulseCheckStartedAt ?? now
        let elapsedInCycle = max(0, effectiveNow.timeIntervalSince(cycleAnchor))
        return spec.seconds - elapsedInCycle
    }

    /// Completed-cycle count (0-based). Increments when a pulse check
    /// completes, not on a wall-clock wrap. Views watch this for the haptic.
    public func cycleIndex(at now: Date) -> Int {
        completedCycles
    }

    /// Seconds spent in the current pulse check (0 when not checking).
    /// The UI turns this red past the 10-second hands-off target.
    public func pulseCheckElapsed(at now: Date) -> TimeInterval {
        guard let started = pulseCheckStartedAt else { return 0 }
        return max(0, now.timeIntervalSince(started))
    }

    /// Time since the LATEST ROSC (re-arrests reset this, roscDate doesn't).
    public func roscElapsed(at now: Date) -> TimeInterval {
        guard let rosc = lastROSCAt ?? session.roscDate else { return 0 }
        return max(0, now.timeIntervalSince(rosc))
    }

    /// Countdown to the next post-ROSC vitals reassessment. Negative =
    /// overdue, same convention as the pulse check. Nil when not in ROSC
    /// or the protocol has no vitals cadence.
    public func vitalsRemaining(at now: Date) -> TimeInterval? {
        guard roscAchieved, let anchor = vitalsAnchor,
              let spec = protocolDef.vitalsSpec else { return nil }
        return spec.seconds - now.timeIntervalSince(anchor)
    }

    /// Remaining seconds for a drug-interval timer. Negative = overdue.
    /// Idle (drug never given) reports the full length — pair with
    /// `intervalIsRunning` before drawing a countdown.
    public func intervalRemaining(_ spec: TimerSpec, at now: Date) -> TimeInterval {
        guard let anchor = intervalAnchors[spec.id] else { return spec.seconds }
        return spec.seconds - now.timeIntervalSince(anchor)
    }

    /// False until the linked drug's first dose starts the countdown.
    public func intervalIsRunning(_ spec: TimerSpec) -> Bool {
        intervalAnchors[spec.id] != nil
    }

    public func intervalIsOverdue(_ spec: TimerSpec, at now: Date) -> Bool {
        intervalIsRunning(spec) && intervalRemaining(spec, at: now) <= 0
    }

    // MARK: - Guidance

    public func hint(at now: Date) -> String {
        if isEnded { return "Code ended" }
        if roscAchieved {
            if let v = vitalsRemaining(at: now), v <= 0 { return "Vitals check overdue" }
            return "ROSC — post-resuscitation care"
        }
        if isInPulseCheck { return "Hands off — checking pulse" }
        if !cprStarted { return "Tap Start CPR when compressions begin" }
        if isPaused { return "CPR PAUSED — resume compressions" }
        if cycleRemaining(at: now) <= 0 { return "Pulse check overdue" }
        for spec in protocolDef.intervalSpecs where intervalIsOverdue(spec, at: now) {
            return "\(spec.title) due now"
        }
        if cycleRemaining(at: now) <= 15 { return "Pulse check at cycle end" }
        return "Continue high-quality CPR"
    }

    // MARK: - Actions

    /// Logs a drug with a computed dose snapshot; advances its dose ladder
    /// by prior count; resets its interval timer if flagged.
    public func logDrug(_ drug: DrugProfile, forcedStepIndex: Int? = nil, at now: Date = Date()) {
        let prior = session.events.filter { $0.definitionID == drug.id.uuidString }.count
        let all = DoseCalculator.doses(for: drug, weightKg: session.patient.weightKg)
        let index = min(forcedStepIndex ?? prior, max(0, all.count - 1))
        let dose: DoseResult? = all.isEmpty ? nil : all[index]
        let detail = dose.map { d -> String in
            drug.steps.count > 1 ? "\(d.stepLabel): \(d.summary)" : d.summary
        }
        let category: EventCategory = drug.unit == .joulesPerKg ? .defibrillation : .medication
        append(title: drug.name, detail: detail, category: category,
               definitionID: drug.id.uuidString, at: now)

        if drug.resetsInterval {
            for spec in protocolDef.intervalSpecs where spec.linkedDrugID == drug.id {
                intervalAnchors[spec.id] = now
            }
        }
    }

    /// Logs a defined event, optionally with a chosen sub-option (site, etc).
    public func logEvent(_ def: EventDefinition, subOption: String? = nil, at now: Date = Date()) {
        if def.id == "outcome.rosc" { markROSC(at: now); return }
        append(title: def.title, detail: subOption, category: def.category,
               definitionID: def.id, at: now)
    }

    public func logNote(_ text: String, at now: Date = Date()) {
        append(title: "Note", detail: text, category: .custom, definitionID: nil, at: now)
    }

    /// Compressions begin: anchor the first CPR cycle here. The code clock
    /// (GO) and the compression clock are different moments on purpose.
    public func startCPR(at now: Date = Date()) {
        guard !cprStarted, !isEnded, !roscAchieved else { return }
        cprStarted = true
        cycleAnchor = now
        append(title: "CPR started", detail: nil,
               category: .cpr, definitionID: "cpr.start", at: now)
    }

    /// Mid-code weight correction. Everything dose-derived (mg, mL, joules)
    /// recomputes from the session's weight at log time, so future doses and
    /// the shock menu update instantly. The change itself goes on the record.
    public func updateWeight(_ kg: Double, at now: Date = Date()) {
        guard !isEnded, kg > 0 else { return }
        let old = session.patient.weightKg
        guard abs(old - kg) > 0.049 else { return }
        session.patient.weightKg = kg
        append(title: "Weight changed",
               detail: String(format: "%.1f → %.1f kg", old, kg),
               category: .custom, definitionID: "patient.weight", at: now)
    }

    /// Start the hands-off pulse check that closes the current CPR cycle.
    /// Opens a PauseInterval (it IS interrupted CPR) and freezes the cycle
    /// clock at whatever it showed — usually zero or negative.
    public func beginPulseCheck(at now: Date = Date()) {
        guard cprStarted, !isEnded, !roscAchieved, !isInPulseCheck, !isPaused else { return }
        pulseCheckStartedAt = now
        isInPulseCheck = true
        session.pauses.append(PauseInterval(start: now))
        append(title: "Pulse check", detail: "cycle \(completedCycles + 1)",
               category: .rhythm, definitionID: "pulse.check", at: now)
    }

    /// Finish the pulse check: close its pause interval, count the cycle,
    /// and start a fresh one. A found pulse flows straight into ROSC.
    public func completePulseCheck(pulseFound: Bool, at now: Date = Date()) {
        guard isInPulseCheck else { return }
        closePulseCheck(at: now)
        if pulseFound {
            append(title: "Pulse found", detail: nil,
                   category: .outcome, definitionID: "pulse.found", at: now)
            markROSC(at: now)
        } else {
            append(title: "CPR resumed", detail: "no pulse",
                   category: .cpr, definitionID: "pulse.resume", at: now)
        }
    }

    /// Pause/resume CPR. Pausing opens a PauseInterval and freezes the cycle;
    /// resuming closes it and slides the cycle anchor forward by the gap.
    public func togglePause(at now: Date = Date()) {
        guard !isEnded, !roscAchieved, !isInPulseCheck else { return }
        if isPaused {
            if let started = pauseStartedAt {
                cycleAnchor.addTimeInterval(now.timeIntervalSince(started))
                if let idx = session.pauses.lastIndex(where: { $0.end == nil }) {
                    session.pauses[idx].end = now
                }
            }
            pauseStartedAt = nil
            isPaused = false
            append(title: "CPR resumed", detail: nil, category: .cpr,
                   definitionID: "cpr.toggle", at: now)
        } else {
            pauseStartedAt = now
            session.pauses.append(PauseInterval(start: now))
            isPaused = true
            append(title: "CPR paused", detail: nil, category: .cpr,
                   definitionID: "cpr.toggle", at: now)
        }
    }

    public func markROSC(at now: Date = Date()) {
        guard !roscAchieved, !isEnded else { return }
        closePulseCheck(at: now)               // ROSC mid-check counts the cycle
        if isPaused { togglePause(at: now) }   // close any open pause first
        if session.roscDate == nil {           // stats keep the FIRST ROSC
            session.roscDate = now
        }
        lastROSCAt = now
        vitalsAnchor = now                     // reassessment cadence starts now
        roscAchieved = true
        append(title: "ROSC", detail: "Return of spontaneous circulation",
               category: .outcome, definitionID: "outcome.rosc", at: now)
    }

    /// Pulses lost after ROSC: drop straight back into the CPR flow with a
    /// fresh cycle. Drug-interval anchors are deliberately untouched — time
    /// since the last epi is still the number that matters.
    public func reArrest(at now: Date = Date()) {
        guard roscAchieved, !isEnded else { return }
        roscAchieved = false
        vitalsAnchor = nil
        cprStarted = true      // compressions resume immediately on re-arrest
        cycleAnchor = now
        append(title: "Re-arrest", detail: "CPR resumed",
               category: .cpr, definitionID: "outcome.rearrest", at: now)
    }

    /// Post-ROSC reassessment confirmed — log it and restart the cadence.
    public func confirmVitals(at now: Date = Date()) {
        guard roscAchieved, !isEnded else { return }
        vitalsAnchor = now
        append(title: "Vitals reassessed", detail: nil,
               category: .rhythm, definitionID: "rosc.vitals", at: now)
    }

    @discardableResult
    public func end(at now: Date = Date()) -> CodeSession {
        guard !isEnded else { return session }
        closePulseCheck(at: now)
        if isPaused { togglePause(at: now) }
        session.endDate = now
        isEnded = true
        return session
    }

    // MARK: - Internals

    /// Shared teardown: closes the check's pause interval, counts the cycle,
    /// and re-anchors so the next cycle starts now. Safe to call when idle.
    private func closePulseCheck(at now: Date) {
        guard isInPulseCheck else { return }
        if let idx = session.pauses.lastIndex(where: { $0.end == nil }) {
            session.pauses[idx].end = now
        }
        pulseCheckStartedAt = nil
        isInPulseCheck = false
        completedCycles += 1
        cycleAnchor = now
    }

    private func append(title: String, detail: String?, category: EventCategory,
                        definitionID: String?, at now: Date) {
        let offset = Int(elapsed(at: now))
        session.events.append(CodeEvent(date: now, offsetSeconds: offset, title: title,
                                        detail: detail, category: category,
                                        definitionID: definitionID))
    }
}
