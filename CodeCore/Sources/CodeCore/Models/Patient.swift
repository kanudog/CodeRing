// Patient.swift — patient context + the three weight-entry paths:
// manual kg (primary), Broselow color (primary), age estimate (fallback).
// DEMO values only. Estimation formulas are the published APLS approximations.

import Foundation

public enum Sex: String, Codable, CaseIterable, Identifiable, Sendable {
    case unspecified, female, male
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .unspecified: return "—"
        case .female: return "Female"
        case .male: return "Male"
        }
    }
}

public enum WeightSource: String, Codable, Sendable {
    case manual, broselow, ageEstimate
    public var label: String {
        switch self {
        case .manual: return "Manual kg"
        case .broselow: return "Broselow"
        case .ageEstimate: return "Age estimate"
        }
    }
}

/// Standard Broselow zones. midKg drives dosing when a color is chosen.
public struct BroselowZone: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let colorHex: String
    public let minKg: Double
    public let maxKg: Double
    public var midKg: Double { ((minKg + maxKg) / 2 * 10).rounded() / 10 }
    /// Short "6–7" style label the watch wheel prints on each wedge.
    public var rangeLabel: String { "\(Int(minKg))–\(Int(maxKg))" }

    public init(id: String, name: String, colorHex: String, minKg: Double, maxKg: Double) {
        self.id = id; self.name = name; self.colorHex = colorHex
        self.minKg = minKg; self.maxKg = maxKg
    }

    public static let zones: [BroselowZone] = [
        BroselowZone(id: "grey",   name: "Grey",   colorHex: "9CA3AF", minKg: 3,  maxKg: 5),
        BroselowZone(id: "pink",   name: "Pink",   colorHex: "F472B6", minKg: 6,  maxKg: 7),
        BroselowZone(id: "red",    name: "Red",    colorHex: "EF4444", minKg: 8,  maxKg: 9),
        BroselowZone(id: "purple", name: "Purple", colorHex: "A855F7", minKg: 10, maxKg: 11),
        BroselowZone(id: "yellow", name: "Yellow", colorHex: "FACC15", minKg: 12, maxKg: 14),
        BroselowZone(id: "white",  name: "White",  colorHex: "E5E7EB", minKg: 15, maxKg: 18),
        BroselowZone(id: "blue",   name: "Blue",   colorHex: "3B82F6", minKg: 19, maxKg: 23),
        BroselowZone(id: "orange", name: "Orange", colorHex: "F97316", minKg: 24, maxKg: 29),
        BroselowZone(id: "green",  name: "Green",  colorHex: "22C55E", minKg: 30, maxKg: 36)
    ]
}

public struct PatientContext: Codable, Sendable, Equatable {
    public var weightKg: Double
    public var weightSource: WeightSource
    public var broselowZoneID: String?
    public var ageMonths: Int?
    public var sex: Sex

    public init(weightKg: Double,
                weightSource: WeightSource,
                broselowZoneID: String? = nil,
                ageMonths: Int? = nil,
                sex: Sex = .unspecified) {
        self.weightKg = weightKg
        self.weightSource = weightSource
        self.broselowZoneID = broselowZoneID
        self.ageMonths = ageMonths
        self.sex = sex
    }

    public var weightLabel: String {
        String(format: "%.1f kg", weightKg)
    }

    public var ageLabel: String {
        guard let m = ageMonths else { return "—" }
        if m < 24 { return "\(m) mo" }
        return "\(m / 12) yr"
    }

    public var sourceDetail: String {
        switch weightSource {
        case .manual: return "entered manually"
        case .broselow:
            let name = BroselowZone.zones.first { $0.id == broselowZoneID }?.name ?? "?"
            return "Broselow \(name)"
        case .ageEstimate: return "estimated from age"
        }
    }
}

/// APLS approximations. Fallback path only; capped at 50 kg for the peds scope.
public enum WeightEstimator {
    public static func weightKg(forAgeMonths months: Int) -> Double {
        let m = Double(max(0, months))
        let kg: Double
        if months <= 12 {
            kg = 0.5 * m + 4                    // infants: (0.5 × months) + 4
        } else {
            kg = (m / 12.0 + 4.0) * 2.0         // 1–10 yr: (years + 4) × 2
        }
        return min((kg * 10).rounded() / 10, 50)
    }
}
