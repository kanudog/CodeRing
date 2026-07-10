// Defaults.swift — everything that ships in the box.
// DEMO VALUES. Per-kg doses use widely published PALS reference numbers so the
// math previews realistically, but this app is a demo and these are placeholders
// until Sebastian loads his facility's own calculations via the iPhone editor.
//
// UUIDs are HARDCODED (stable) so watch and phone always agree on identity
// across installs and sync. Never regenerate these.

import Foundation

public enum Defaults {

    // MARK: - Stable identities

    public static let palsSetID = UUID(uuidString: "C0DE0000-0000-4000-8000-000000000001")!
    public static let epiID     = UUID(uuidString: "C0DE0000-0000-4000-8000-0000000000A1")!
    public static let amioID    = UUID(uuidString: "C0DE0000-0000-4000-8000-0000000000A2")!
    public static let atropineID = UUID(uuidString: "C0DE0000-0000-4000-8000-0000000000A3")!
    public static let adenosineID = UUID(uuidString: "C0DE0000-0000-4000-8000-0000000000A4")!
    public static let defibID   = UUID(uuidString: "C0DE0000-0000-4000-8000-0000000000A5")!
    public static let examplitolID = UUID(uuidString: "C0DE0000-0000-4000-8000-0000000000AF")!

    // MARK: - Drugs (key meds only — rare items get added later via the editor)

    public static var epinephrine: DrugProfile {
        DrugProfile(id: epiID,
                    name: "Epinephrine",
                    subtitle: "0.1 mg/mL (1:10,000)",
                    unit: .mgPerKg,
                    steps: [DoseStep(label: "IV/IO", perKg: 0.01, maxAbsolute: 1.0)],
                    concentrationMgPerMl: 0.1,
                    colorHex: "FF3B5C",
                    symbol: "syringe.fill",
                    resetsInterval: true,
                    notes: "Repeat q3–5 min. Demo values.")
    }

    public static var amiodarone: DrugProfile {
        DrugProfile(id: amioID,
                    name: "Amiodarone",
                    subtitle: "50 mg/mL",
                    unit: .mgPerKg,
                    steps: [DoseStep(label: "Bolus", perKg: 5.0, maxAbsolute: 300)],
                    concentrationMgPerMl: 50,
                    colorHex: "F472B6",
                    symbol: "cross.vial.fill",
                    notes: "VF/pVT. May repeat ×2. Demo values.")
    }

    public static var atropine: DrugProfile {
        DrugProfile(id: atropineID,
                    name: "Atropine",
                    subtitle: "0.1 mg/mL",
                    unit: .mgPerKg,
                    steps: [DoseStep(label: "IV/IO", perKg: 0.02, maxAbsolute: 0.5)],
                    concentrationMgPerMl: 0.1,
                    colorHex: "FB923C",
                    symbol: "heart.circle.fill",
                    notes: "Bradycardia w/ increased vagal tone. Demo values.")
    }

    public static var adenosine: DrugProfile {
        DrugProfile(id: adenosineID,
                    name: "Adenosine",
                    subtitle: "3 mg/mL — rapid push",
                    unit: .mgPerKg,
                    steps: [
                        DoseStep(label: "1st", perKg: 0.1, maxAbsolute: 6),
                        DoseStep(label: "2nd", perKg: 0.2, maxAbsolute: 12)
                    ],
                    concentrationMgPerMl: 3,
                    colorHex: "38BDF8",
                    symbol: "bolt.heart.fill",
                    notes: "SVT. Rapid flush. Demo values.")
    }

    public static var defibrillation: DrugProfile {
        DrugProfile(id: defibID,
                    name: "Defibrillation",
                    subtitle: "Biphasic",
                    unit: .joulesPerKg,
                    steps: [
                        DoseStep(label: "1st", perKg: 2, maxAbsolute: 200),
                        DoseStep(label: "Subsequent", perKg: 4, maxAbsolute: 200)
                    ],
                    colorHex: CRTheme.shockHex,
                    symbol: "bolt.fill",
                    notes: "2 J/kg then 4 J/kg. Demo values.")
    }

    /// Fictional sample drug — exists purely to preview the card style & editor.
    public static var examplitol: DrugProfile {
        DrugProfile(id: examplitolID,
                    name: "Examplitol",
                    subtitle: "2 mg/mL — fictional",
                    unit: .mgPerKg,
                    steps: [DoseStep(label: "Sample", perKg: 0.5, maxAbsolute: 20)],
                    concentrationMgPerMl: 2,
                    colorHex: "2DD4BF",
                    symbol: "testtube.2",
                    notes: "Not a real medication. Duplicate me to build your own.")
    }

    public static var palsDrugSet: DrugProfileSet {
        DrugProfileSet(id: palsSetID,
                       name: "PALS Default (Demo)",
                       drugs: [epinephrine, defibrillation, amiodarone,
                               atropine, adenosine, examplitol],
                       isBuiltIn: true)
    }

    // MARK: - Events

    public static var builtInEvents: [EventDefinition] {
        [
            EventDefinition(id: "rhythm.check", title: "Rhythm check",
                            category: .rhythm, symbol: "waveform.path.ecg", isBuiltIn: true),
            EventDefinition(id: "access.iv", title: "IV access",
                            category: .access, symbol: "ivfluid.bag",
                            subOptions: ["R hand", "L hand", "R AC", "L AC", "R foot", "L foot"],
                            isBuiltIn: true),
            EventDefinition(id: "access.io", title: "IO access",
                            category: .access, symbol: "target",
                            subOptions: ["R prox tibia", "L prox tibia", "R distal femur", "L distal femur"],
                            isBuiltIn: true),
            EventDefinition(id: "airway.ett", title: "Intubation",
                            category: .airway, symbol: "lungs.fill", isBuiltIn: true),
            EventDefinition(id: "cpr.swap", title: "Compressor swap",
                            category: .cpr, symbol: "arrow.triangle.2.circlepath", isBuiltIn: true),
            EventDefinition(id: "outcome.rosc", title: "ROSC",
                            category: .outcome, symbol: "heart.fill", isBuiltIn: true),

            // Post-ROSC care set — only offered while in ROSC (id prefix
            // "rosc." is how the watch swaps the events bloom).
            EventDefinition(id: "rosc.infusion", title: "Pressor infusion",
                            category: .medication, symbol: "ivfluid.bag", isBuiltIn: true),
            EventDefinition(id: "rosc.bolus", title: "Fluid bolus",
                            category: .medication, symbol: "drop.fill", isBuiltIn: true),
            EventDefinition(id: "rosc.vent", title: "Vent change",
                            category: .airway, symbol: "lungs.fill", isBuiltIn: true),
            EventDefinition(id: "rosc.temp", title: "Temperature",
                            category: .rhythm, symbol: "thermometer.medium", isBuiltIn: true),
            EventDefinition(id: "rosc.glucose", title: "Glucose",
                            category: .rhythm, symbol: "testtube.2", isBuiltIn: true),
            EventDefinition(id: "rosc.sedation", title: "Sedation",
                            category: .medication, symbol: "moon.zzz.fill", isBuiltIn: true),
            EventDefinition(id: "rosc.ecg", title: "12-lead ECG",
                            category: .rhythm, symbol: "waveform.path.ecg.rectangle", isBuiltIn: true)
        ]
    }

    // MARK: - Protocols

    public static var palsArrest: CodeProtocolDefinition {
        CodeProtocolDefinition(
            id: "pals.arrest",
            name: "Cardiac Arrest",
            shortName: "ARREST",
            symbol: "heart.slash.fill",
            timers: [
                TimerSpec(id: "timer.cpr", role: .cprCycle, title: "CPR",
                          seconds: 120, colorHex: CRTheme.cprHex),
                TimerSpec(id: "timer.epi", role: .drugInterval, title: "EPI",
                          seconds: 180, windowSeconds: 300,
                          linkedDrugID: epiID, colorHex: CRTheme.medHex),
                TimerSpec(id: "timer.vitals", role: .postROSCVitals, title: "VITALS",
                          seconds: 300, colorHex: CRTheme.roscHex)
            ],
            eventIDs: ["rhythm.check", "cpr.swap", "access.iv", "access.io", "airway.ett", "outcome.rosc"],
            drugSetID: palsSetID
        )
    }

    /// Registry read by both apps. New protocols get appended here (or loaded
    /// from JSON later) — nothing else in the codebase changes.
    public static var protocols: [CodeProtocolDefinition] { [palsArrest] }
}
