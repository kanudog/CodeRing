// Store.swift — single source of truth for persisted data on each device.
// Plain Codable JSON files in Application Support/CodeRing/ — transparent,
// diffable, no database. Watch and phone each run their own store; the
// ConnectivityManager merges between them.

import Foundation
import Observation

public struct AppSettings: Codable, Sendable, Equatable {
    public var hapticsEnabled: Bool = true
    public var metronomeSoundOn: Bool = false     // haptic-only by default
    public var metronomeBPM: Int = 110
    public var cycleSecondsOverride: TimeInterval? = nil   // nil = protocol default (120)
    public var epiSecondsOverride: TimeInterval? = nil     // nil = protocol default (180)
    public var defaultDrugSetID: UUID? = nil

    public init() {}
}

@MainActor
@Observable
public final class CodeStore {

    public static let shared = CodeStore()

    public var drugSets: [DrugProfileSet] = []
    public var customEvents: [EventDefinition] = []
    public var sessions: [CodeSession] = []
    public var settings = AppSettings()

    private let fm = FileManager.default

    private var dir: URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("CodeRing", isDirectory: true)
        if !fm.fileExists(atPath: d.path) {
            try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        }
        return d
    }

    private init() {
        load()
    }

    // MARK: - Resolution helpers

    public var allEventDefs: [EventDefinition] { Defaults.builtInEvents + customEvents }

    public func drugSet(id: UUID) -> DrugProfileSet? {
        drugSets.first { $0.id == id }
    }

    /// The set a new session uses: user default → protocol's set → first available.
    public func activeDrugSet(for protocolDef: CodeProtocolDefinition) -> DrugProfileSet {
        if let id = settings.defaultDrugSetID, let s = drugSet(id: id) { return s }
        if let s = drugSet(id: protocolDef.drugSetID) { return s }
        return drugSets.first ?? Defaults.palsDrugSet
    }

    public func effectiveProtocol(_ base: CodeProtocolDefinition) -> CodeProtocolDefinition {
        base.applying(cycleSeconds: settings.cycleSecondsOverride,
                      epiSeconds: settings.epiSecondsOverride)
    }

    // MARK: - Mutations

    public func merge(session: CodeSession) {
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        } else {
            sessions.append(session)
        }
        sessions.sort { $0.startDate > $1.startDate }
        persistSessions()
    }

    public func delete(sessionID: UUID) {
        sessions.removeAll { $0.id == sessionID }
        persistSessions()
    }

    public func upsert(set: DrugProfileSet) {
        if let idx = drugSets.firstIndex(where: { $0.id == set.id }) {
            drugSets[idx] = set
        } else {
            drugSets.append(set)
        }
        persistDrugSets()
    }

    public func delete(setID: UUID) {
        drugSets.removeAll { $0.id == setID && !$0.isBuiltIn }
        persistDrugSets()
    }

    public func replaceDrugSets(_ sets: [DrugProfileSet]) {
        drugSets = sets
        persistDrugSets()
    }

    public func upsert(event: EventDefinition) {
        if let idx = customEvents.firstIndex(where: { $0.id == event.id }) {
            customEvents[idx] = event
        } else {
            customEvents.append(event)
        }
        persistEvents()
    }

    public func delete(eventID: String) {
        customEvents.removeAll { $0.id == eventID }
        persistEvents()
    }

    public func replaceCustomEvents(_ events: [EventDefinition]) {
        customEvents = events
        persistEvents()
    }

    public func updateSettings(_ new: AppSettings) {
        settings = new
        persistSettings()
    }

    public func resetAllData() {
        sessions = []
        customEvents = []
        drugSets = [Defaults.palsDrugSet]
        settings = AppSettings()
        persistAll()
    }

    // MARK: - Persistence

    private func url(_ name: String) -> URL { dir.appendingPathComponent(name) }

    private func save<T: Encodable>(_ value: T, to name: String) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(value) {
            try? data.write(to: url(name), options: .atomic)
        }
    }

    private func read<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(type, from: data)
    }

    public func persistDrugSets() { save(drugSets, to: "drugSets.json") }
    public func persistEvents() { save(customEvents, to: "customEvents.json") }
    public func persistSessions() { save(sessions, to: "sessions.json") }
    public func persistSettings() { save(settings, to: "settings.json") }
    public func persistAll() {
        persistDrugSets(); persistEvents(); persistSessions(); persistSettings()
    }

    private func load() {
        drugSets = read([DrugProfileSet].self, from: "drugSets.json") ?? [Defaults.palsDrugSet]
        if drugSets.isEmpty { drugSets = [Defaults.palsDrugSet] }
        customEvents = read([EventDefinition].self, from: "customEvents.json") ?? []
        sessions = read([CodeSession].self, from: "sessions.json") ?? []
        settings = read(AppSettings.self, from: "settings.json") ?? AppSettings()
    }
}
