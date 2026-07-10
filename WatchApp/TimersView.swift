// TimersView.swift — every running clock on one screen, mid-code.
// A timer starts when its event is first logged and counts from the LATEST
// occurrence (last epi, last pulse check, last compressor swap, …).
// Total code time deliberately absent — the live header always shows it.

import SwiftUI
import CodeCore

struct TimersView: View {
    let engine: SessionEngine

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            // One line per timer, tight rows: label left, clock right,
            // so the whole picture needs as little scrolling as possible.
            List(engine.session.runningTimers(at: ctx.date).filter { $0.id != "total" }) { timer in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: timer.colorHex))
                        .frame(width: 3, height: 16)
                    Text(timer.title.uppercased())
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(0.4)
                        .foregroundStyle(CRTheme.textDim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    Spacer(minLength: 4)
                    Text(crClock(timer.elapsed(at: ctx.date)))
                        .font(.system(size: 14, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(CRTheme.text)
                }
                .listRowBackground(RoundedRectangle(cornerRadius: 8).fill(CRTheme.surface))
                .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
            }
            .environment(\.defaultMinListRowHeight, 26)
        }
        .navigationTitle("Timers")
    }
}
