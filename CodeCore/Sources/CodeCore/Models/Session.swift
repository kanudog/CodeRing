// Session.swift — one complete code, from GO to end.
// Owns the event log, pause intervals, and patient snapshot.
// SessionStats derives everything the summary screen and PDF need.

import Foundation

public struct PauseInterval: Codable, Sendable, Equatable {
    public var start: Date
    public var end: Date?

    public init(start: Date, end: Date? = nil) {
        self.start = start; self.end = end
    }

    public func seconds(clampedTo limit: Date) -> TimeInterval {
        let stop = end ?? limit
        return max(0, stop.timeIntervalSince(start))
    }
}

public struct CodeSession: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var protocolID: String
    public var protocolName: String
    public var startDate: Date
    public var endDate: Date?
    public var roscDate: Date?
    public var patient: PatientContext
    public var events: [CodeEvent]
    public var pauses: [PauseInterval]
    public var deviceName: String

    public init(id: UUID = UUID(), protocolID: String, protocolName: String,
                startDate: Date, endDate: Date? = nil, roscDate: Date? = nil,
                patient: PatientContext, events: [CodeEvent] = [],
                pauses: [PauseInterval] = [], deviceName: String = "") {
        self.id = id; self.protocolID = protocolID; self.protocolName = protocolName
        self.startDate = startDate; self.endDate = endDate; self.roscDate = roscDate
        self.patient = patient; self.events = events; self.pauses = pauses
        self.deviceName = deviceName
    }

    public func duration(at now: Date = Date()) -> TimeInterval {
        max(0, (endDate ?? now).timeIntervalSince(startDate))
    }

    public func pausedSeconds(at now: Date = Date()) -> TimeInterval {
        let limit = endDate ?? now
        return pauses.reduce(0) { $0 + $1.seconds(clampedTo: limit) }
    }

    public var stats: SessionStats { SessionStats(session: self) }
}

/// One live "time since X" row for the watch timers screen.
public struct RunningTimer: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let since: Date
    public let colorHex: String

    public init(id: String, title: String, since: Date, colorHex: String) {
        self.id = id; self.title = title; self.since = since; self.colorHex = colorHex
    }

    public func elapsed(at now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(since))
    }
}

public extension CodeSession {
    /// Total code time plus a since-last timer for things you'd REPEAT per
    /// the algorithm — meds, shocks, pulse/rhythm checks, compressor swaps,
    /// vitals, customs. One-shots (access, intubation, CPR started, weight
    /// changes, outcomes) aren't timers: "time since intubation" answers no
    /// clinical question mid-code.
    func runningTimers(at now: Date = Date()) -> [RunningTimer] {
        let repeatableIDs: Set<String> = ["pulse.check", "rhythm.check",
                                          "cpr.swap", "rosc.vitals"]
        func isRepeatable(_ event: CodeEvent) -> Bool {
            switch event.category {
            case .medication, .defibrillation, .custom: return true
            default: return repeatableIDs.contains(event.definitionID ?? "")
            }
        }
        var latest: [String: CodeEvent] = [:]
        for event in events where isRepeatable(event) {
            let key = event.definitionID ?? event.title
            if let seen = latest[key], seen.date > event.date { continue }
            latest[key] = event
        }
        let rows = latest.map { key, event in
            RunningTimer(id: key, title: event.title, since: event.date,
                         colorHex: event.tintHex)   // the item's own hue
        }
        let total = RunningTimer(id: "total", title: "Total code",
                                 since: startDate, colorHex: CRTheme.cprHex)
        // Stalest first — the row most likely to need attention.
        return [total] + rows.sorted { $0.since < $1.since }
    }
}

public struct SessionStats: Sendable {
    public let totalSeconds: TimeInterval
    public let pausedSeconds: TimeInterval
    public let cprFraction: Double          // 0…1 of pre-ROSC time with compressions running
    public let pauseCount: Int
    public let epiCount: Int
    public let shockCount: Int
    public let rhythmCheckCount: Int
    public let medEvents: [String: Int]     // drug name → count
    public let secondsToFirstEpi: Int?
    public let secondsToROSC: Int?

    public init(session s: CodeSession) {
        let end = s.endDate ?? Date()
        totalSeconds = s.duration(at: end)
        pausedSeconds = s.pausedSeconds(at: end)
        pauseCount = s.pauses.count

        // CPR fraction measured against the active-compressions phase (start → ROSC or end).
        let activeEnd = s.roscDate ?? end
        let activeSpan = max(1, activeEnd.timeIntervalSince(s.startDate))
        let pausedInActive = s.pauses.reduce(0.0) { $0 + $1.seconds(clampedTo: activeEnd) }
        cprFraction = max(0, min(1, (activeSpan - pausedInActive) / activeSpan))

        var meds: [String: Int] = [:]
        var epi = 0, shocks = 0, rhythm = 0
        var firstEpi: Int? = nil
        for e in s.events {
            switch e.category {
            case .medication:
                meds[e.title, default: 0] += 1
                if e.title.lowercased().contains("epi") {
                    epi += 1
                    if firstEpi == nil { firstEpi = e.offsetSeconds }
                }
            case .defibrillation: shocks += 1
            case .rhythm: rhythm += 1
            default: break
            }
        }
        medEvents = meds
        epiCount = epi
        shockCount = shocks
        rhythmCheckCount = rhythm
        secondsToFirstEpi = firstEpi
        if let rosc = s.roscDate {
            secondsToROSC = Int(rosc.timeIntervalSince(s.startDate))
        } else {
            secondsToROSC = nil
        }
    }

    public var cprFractionPercent: String {
        String(format: "%.0f%%", cprFraction * 100)
    }
}
