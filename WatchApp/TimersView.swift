// TimersView.swift — every running clock on one screen, mid-code.
// A timer starts when its event is first logged and counts from the LATEST
// occurrence (last epi, last pulse check, last compressor swap, …).

import SwiftUI
import CodeCore

struct TimersView: View {
    let engine: SessionEngine

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            List(engine.session.runningTimers(at: ctx.date)) { timer in
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: timer.colorHex))
                        .frame(width: 3, height: 28)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(timer.id == "total" ? "TOTAL CODE" : "LAST \(timer.title.uppercased())")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .tracking(0.6)
                            .foregroundStyle(CRTheme.textDim)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(crClock(timer.elapsed(at: ctx.date)))
                            .font(.system(size: 17, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(CRTheme.text)
                    }
                    Spacer()
                }
                .listRowBackground(RoundedRectangle(cornerRadius: 10).fill(CRTheme.surface))
            }
        }
        .navigationTitle("Timers")
    }
}
