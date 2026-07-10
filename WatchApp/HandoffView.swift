// HandoffView.swift — the phone-call card. Everything PICU/transport asks
// for on one screen, readable line by line while the code is still live.

import SwiftUI
import CodeCore

struct HandoffView: View {
    let engine: SessionEngine

    private static let wallClock: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "H:mm:ss"
        return df
    }()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { ctx in
            let s = engine.session
            let stats = s.stats
            List {
                row("PATIENT", "\(s.patient.weightLabel) · \(engine.protocolDef.shortName)",
                    CRTheme.cprHex)
                if let toROSC = stats.secondsToROSC {
                    row("ARREST DURATION", crClock(TimeInterval(toROSC)), CRTheme.medHex)
                }
                row("TOTAL CODE", crClock(engine.elapsed(at: ctx.date)), CRTheme.cprHex)
                row("EPI", epiLine(s, at: ctx.date), CRTheme.medHex)
                row("SHOCKS", "×\(stats.shockCount)", CRTheme.shockHex)
                if let rosc = s.roscDate {
                    row("ROSC AT", Self.wallClock.string(from: rosc), CRTheme.roscHex)
                }
                if engine.roscAchieved {
                    row("POST-ROSC", crClock(engine.roscElapsed(at: ctx.date)), CRTheme.roscHex)
                }
                ForEach(s.events.filter { $0.category == .access }) { access in
                    row("ACCESS", access.detail ?? access.title, CRTheme.accessHex)
                }
                DemoBadge(compact: true)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Handoff")
    }

    private func epiLine(_ s: CodeSession, at now: Date) -> String {
        let count = s.stats.epiCount
        guard count > 0,
              let last = s.events.last(where: {
                  $0.category == .medication && $0.title.lowercased().contains("epi")
              })
        else { return "×0" }
        return "×\(count) — last \(crClock(now.timeIntervalSince(last.date))) ago"
    }

    private func row(_ label: String, _ value: String, _ colorHex: String) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: colorHex))
                .frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(CRTheme.textDim)
                Text(value)
                    .font(.system(size: 14, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(CRTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer()
        }
        .listRowBackground(RoundedRectangle(cornerRadius: 10).fill(CRTheme.surface))
    }
}
