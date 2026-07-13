// Events.swift — event tracking.
// EventDefinition = what CAN be logged (built-in + custom, custom built on iPhone).
// CodeEvent = what WAS logged, timestamped against code start.
// subOptions power the second-level radial arc (e.g. access site) — a parent
// with subOptions only expands; logging always requires releasing on a leaf.

import Foundation
import SwiftUI

public enum EventCategory: String, Codable, CaseIterable, Sendable {
    case medication, defibrillation, rhythm, airway, access, cpr, outcome, care, volume, comms, custom

    public var colorHex: String {
        switch self {
        case .medication: return CRTheme.medHex
        case .defibrillation: return CRTheme.shockHex
        case .rhythm: return CRTheme.rhythmHex
        case .airway: return CRTheme.airwayHex
        case .access: return CRTheme.accessHex
        case .cpr: return CRTheme.cprHex
        case .outcome: return CRTheme.roscHex
        case .care: return CRTheme.careHex
        case .volume: return CRTheme.volumeHex
        case .comms: return CRTheme.commsHex
        case .custom: return CRTheme.customHex
        }
    }
    public var color: Color { Color(hex: colorHex) }

    public var label: String {
        switch self {
        case .medication: return "Medication"
        case .defibrillation: return "Defib"
        case .rhythm: return "Rhythm"
        case .airway: return "Airway"
        case .access: return "Access"
        case .cpr: return "CPR"
        case .outcome: return "Outcome"
        case .care: return "Care"
        case .volume: return "Volume/Support"
        case .comms: return "Comms"
        case .custom: return "Custom"
        }
    }
}

public struct EventDefinition: Identifiable, Codable, Sendable, Equatable, Hashable {
    public var id: String              // stable key, e.g. "rhythm.check", "custom.<uuid>"
    public var title: String
    public var category: EventCategory
    public var symbol: String
    public var subOptions: [String]    // empty = no second arc
    public var isBuiltIn: Bool

    public init(id: String, title: String, category: EventCategory, symbol: String,
                subOptions: [String] = [], isBuiltIn: Bool = false) {
        self.id = id; self.title = title; self.category = category
        self.symbol = symbol; self.subOptions = subOptions; self.isBuiltIn = isBuiltIn
    }
}

public struct CodeEvent: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var date: Date
    public var offsetSeconds: Int      // seconds since code start, frozen at log time
    public var title: String
    public var detail: String?         // dose summary, site, energy, free text
    public var category: EventCategory
    public var definitionID: String?   // links back to EventDefinition / drug UUID string
    /// The item's theme color, frozen at log time, so every timer surface
    /// (gutter chip, inner ring, timers list) shows the same hue as the
    /// button it came from. Optional → old sessions decode with nil and fall
    /// back to the category color.
    public var colorHex: String?

    public init(id: UUID = UUID(), date: Date, offsetSeconds: Int, title: String,
                detail: String? = nil, category: EventCategory, definitionID: String? = nil,
                colorHex: String? = nil) {
        self.id = id; self.date = date; self.offsetSeconds = offsetSeconds
        self.title = title; self.detail = detail; self.category = category
        self.definitionID = definitionID; self.colorHex = colorHex
    }

    /// Theme color for this event — its stored hue, else its category's.
    public var tintHex: String { colorHex ?? category.colorHex }

    public var stamp: String { crOffset(offsetSeconds) }
}
