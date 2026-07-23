// TimersView.swift — every running clock on one screen, mid-code.
// A timer starts when its event is first logged and counts from the LATEST
// occurrence (last epi, last pulse check, last compressor swap, …).
// Total code time deliberately absent — the live header always shows it.

import SwiftUI
import CodeCore

/// One red list row that removes the latest user-logged entry. Shared by the
/// Timers and Log sheets — the two places a mis-tap gets noticed mid-code.
/// Hidden when nothing is undoable; structural records (CPR, pulse checks,
/// ROSC, weight) are never offered — the engine skips past them.
struct UndoLastRow: View {
    let engine: SessionEngine

    var body: some View {
        if let target = engine.lastUndoableEvent, !engine.isEnded {
            Button {
                if engine.undoLastEntry() != nil { WatchHaptics.play(.failure) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(CRTheme.med)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("UNDO LAST")
                            .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                            .tracking(0.5)
                            .foregroundStyle(CRTheme.med)
                        Text(target.title)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(CRTheme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 0)
                }
            }
            .listRowBackground(RoundedRectangle(cornerRadius: 8)
                .fill(CRTheme.med.opacity(0.18)))
            .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
        }
    }
}

struct TimersView: View {
    let engine: SessionEngine

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            // One line per timer, tight rows: label left, clock right,
            // so the whole picture needs as little scrolling as possible.
            List {
                UndoLastRow(engine: engine)
                ForEach(engine.session.runningTimers(at: ctx.date).filter { $0.id != "total" }) { timer in
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
            }
            .environment(\.defaultMinListRowHeight, 26)
        }
        .navigationTitle("Timers")
    }
}
