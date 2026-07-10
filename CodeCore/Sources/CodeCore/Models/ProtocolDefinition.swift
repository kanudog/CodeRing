// ProtocolDefinition.swift — the "add protocols later" promise.
// A protocol is DATA: its timers, its event set, its drug set.
// "Cardiac Arrest (PALS)" ships as the first definition (see Defaults.swift).
// RSI or status epilepticus later = a new definition, zero engine changes.
//
// TimerRole tells the engine which minimal semantics apply:
//   .cprCycle        — repeating countdown, freezes while CPR is paused
//   .drugInterval    — counts down from the last administration of linkedDrugID
//                      (keeps running through pauses; that's intentional)
//   .postROSCVitals  — reassessment cadence that only runs while in ROSC;
//                      anchored at ROSC / the last confirmed vitals check

import Foundation

public enum TimerRole: String, Codable, Sendable {
    case cprCycle
    case drugInterval
    case postROSCVitals
}

public struct TimerSpec: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var role: TimerRole
    public var title: String              // "CPR", "EPI"
    public var seconds: TimeInterval      // 120, 180
    public var windowSeconds: TimeInterval?  // e.g. epi outer window 300 ("q3–5 min")
    public var linkedDrugID: UUID?        // drugInterval only
    public var colorHex: String

    public init(id: String, role: TimerRole, title: String, seconds: TimeInterval,
                windowSeconds: TimeInterval? = nil, linkedDrugID: UUID? = nil,
                colorHex: String) {
        self.id = id; self.role = role; self.title = title; self.seconds = seconds
        self.windowSeconds = windowSeconds; self.linkedDrugID = linkedDrugID
        self.colorHex = colorHex
    }
}

public struct CodeProtocolDefinition: Identifiable, Codable, Sendable, Equatable {
    public var id: String                 // "pals.arrest"
    public var name: String               // "Cardiac Arrest"
    public var shortName: String          // "ARREST"
    public var symbol: String
    public var timers: [TimerSpec]
    public var eventIDs: [String]         // ordered IDs for the Events bloom
    public var drugSetID: UUID

    public init(id: String, name: String, shortName: String, symbol: String,
                timers: [TimerSpec], eventIDs: [String], drugSetID: UUID) {
        self.id = id; self.name = name; self.shortName = shortName; self.symbol = symbol
        self.timers = timers; self.eventIDs = eventIDs; self.drugSetID = drugSetID
    }

    public var cycleSpec: TimerSpec? { timers.first { $0.role == .cprCycle } }
    public var intervalSpecs: [TimerSpec] { timers.filter { $0.role == .drugInterval } }
    public var vitalsSpec: TimerSpec? { timers.first { $0.role == .postROSCVitals } }

    /// Returns a copy with user-adjusted timer lengths (from AppSettings) applied.
    public func applying(cycleSeconds: TimeInterval?, epiSeconds: TimeInterval?) -> CodeProtocolDefinition {
        var copy = self
        copy.timers = timers.map { spec in
            var s = spec
            if spec.role == .cprCycle, let c = cycleSeconds { s.seconds = c }
            if spec.role == .drugInterval, let e = epiSeconds { s.seconds = e }
            return s
        }
        return copy
    }
}
