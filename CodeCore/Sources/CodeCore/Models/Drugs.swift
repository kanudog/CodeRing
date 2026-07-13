// Drugs.swift — the editable drug system.
// A DrugProfile is pure data: dose steps, max caps, concentration, color.
// DoseCalculator turns (profile, weight) into capped mg AND mL — the UI
// features mL because that's what gets drawn up.
// Profiles group into DrugProfileSet ("PALS Default", later "UNC Facility"),
// editable on iPhone and synced to the watch. DEMO values only.

import Foundation

public enum DoseUnit: String, Codable, Sendable {
    case mgPerKg
    case joulesPerKg
    case mlPerKg        // volume-dosed (fluids, bicarb, dextrose) — mL IS the number

    public var amountSuffix: String {
        switch self {
        case .mgPerKg: return "mg"
        case .joulesPerKg: return "J"
        case .mlPerKg: return "mL"
        }
    }
    public var perKgSuffix: String {
        switch self {
        case .mgPerKg: return "mg/kg"
        case .joulesPerKg: return "J/kg"
        case .mlPerKg: return "mL/kg"
        }
    }
}

/// One rung of a dose ladder (e.g. adenosine 1st vs 2nd, defib 2 → 4 J/kg).
public struct DoseStep: Identifiable, Codable, Sendable, Equatable, Hashable {
    public var id: UUID
    public var label: String          // "1st", "Subsequent", "Bolus"
    public var perKg: Double
    public var maxAbsolute: Double?   // cap in mg or J; nil = uncapped

    public init(id: UUID = UUID(), label: String, perKg: Double, maxAbsolute: Double? = nil) {
        self.id = id; self.label = label; self.perKg = perKg; self.maxAbsolute = maxAbsolute
    }
}

public struct DrugProfile: Identifiable, Codable, Sendable, Equatable, Hashable {
    public var id: UUID
    public var name: String
    public var subtitle: String              // concentration text, e.g. "0.1 mg/mL (1:10,000)"
    public var unit: DoseUnit
    public var steps: [DoseStep]
    public var concentrationMgPerMl: Double? // enables mL math; nil for energy doses
    public var colorHex: String
    public var symbol: String                // SF Symbol name
    public var resetsInterval: Bool          // true = giving this resets its interval timer (epi)
    public var notes: String

    public init(id: UUID = UUID(),
                name: String,
                subtitle: String = "",
                unit: DoseUnit = .mgPerKg,
                steps: [DoseStep],
                concentrationMgPerMl: Double? = nil,
                colorHex: String = CRTheme.medHex,
                symbol: String = "syringe",
                resetsInterval: Bool = false,
                notes: String = "") {
        self.id = id; self.name = name; self.subtitle = subtitle; self.unit = unit
        self.steps = steps; self.concentrationMgPerMl = concentrationMgPerMl
        self.colorHex = colorHex; self.symbol = symbol
        self.resetsInterval = resetsInterval; self.notes = notes
    }
}

public struct DrugProfileSet: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var drugs: [DrugProfile]
    public var isBuiltIn: Bool

    public init(id: UUID = UUID(), name: String, drugs: [DrugProfile], isBuiltIn: Bool = false) {
        self.id = id; self.name = name; self.drugs = drugs; self.isBuiltIn = isBuiltIn
    }
}

/// A computed, capped dose for one step at one weight.
public struct DoseResult: Sendable, Equatable {
    public let stepLabel: String
    public let amount: Double        // mg or J after cap + rounding
    public let volumeMl: Double?     // rounded to 0.1 mL when concentration exists
    public let unit: DoseUnit
    public let capped: Bool

    /// "0.8 mL" — the featured, draw-it-up number.
    public var volumeText: String? {
        guard let v = volumeMl else { return nil }
        return "\(DoseCalculator.trim(v)) mL"
    }
    /// "0.08 mg" or "16 J" — the secondary number.
    public var amountText: String {
        "\(DoseCalculator.trim(amount)) \(unit.amountSuffix)"
    }
    /// One-line summary for event details / reports.
    public var summary: String {
        // mL-dosed drugs ARE their volume — no redundant "(12 mL)" tail.
        if unit == .mlPerKg { return "\(volumeText ?? amountText)\(capped ? " · capped" : "")" }
        if let v = volumeText { return "\(v)  (\(amountText))\(capped ? " · capped" : "")" }
        return "\(amountText)\(capped ? " · capped" : "")"
    }
}

public enum DoseCalculator {

    public static func doses(for drug: DrugProfile, weightKg: Double) -> [DoseResult] {
        drug.steps.map { step in
            let raw = step.perKg * weightKg
            var amount = raw
            var capped = false
            if let cap = step.maxAbsolute, raw > cap { amount = cap; capped = true }
            amount = roundedAmount(amount, unit: drug.unit)
            var ml: Double? = nil
            if drug.unit == .mgPerKg, let conc = drug.concentrationMgPerMl, conc > 0 {
                ml = roundedVolume(amount / conc)
            } else if drug.unit == .mlPerKg {
                ml = amount   // the dose already IS the volume
            }
            return DoseResult(stepLabel: step.label, amount: amount, volumeMl: ml,
                              unit: drug.unit, capped: capped)
        }
    }

    /// First (or only) step — used for one-tap logging on the watch.
    public static func primaryDose(for drug: DrugProfile, weightKg: Double, priorCount: Int = 0) -> DoseResult? {
        let all = doses(for: drug, weightKg: weightKg)
        guard !all.isEmpty else { return nil }
        // Prior administrations advance the ladder (adenosine 2nd, defib 4 J/kg),
        // then stay on the last rung.
        let index = min(priorCount, all.count - 1)
        return all[index]
    }

    /// mg rounding tiers: <1 → 2 dp, <10 → 1 dp, else whole. Joules → whole.
    static func roundedAmount(_ value: Double, unit: DoseUnit) -> Double {
        switch unit {
        case .joulesPerKg:
            return value.rounded()
        case .mgPerKg:
            if value < 1 { return (value * 100).rounded() / 100 }
            if value < 10 { return (value * 10).rounded() / 10 }
            return value.rounded()
        case .mlPerKg:
            return roundedVolume(value)   // 0.1 mL resolution
        }
    }

    /// Volumes round to 0.1 mL with a 0.1 mL floor for anything nonzero.
    static func roundedVolume(_ value: Double) -> Double {
        guard value > 0 else { return 0 }
        return max(0.1, (value * 10).rounded() / 10)
    }

    /// Trims trailing zeros: 0.80 → "0.8", 16.0 → "16".
    public static func trim(_ value: Double) -> String {
        if value == value.rounded() && abs(value) >= 1 {
            return String(format: "%.0f", value)
        }
        var s = String(format: "%.2f", value)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}
