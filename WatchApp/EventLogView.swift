// EventLogView.swift — reverse-chronological event log, glanceable rows.
// Each row carries both stamps: +offset from GO and the exact wall time,
// so the log doubles as quick documentation reference mid-code.

import SwiftUI
import CodeCore

struct EventLogView: View {
    let events: [CodeEvent]

    private static let wallClock: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "H:mm:ss"
        return df
    }()

    var body: some View {
        Group {
            if events.isEmpty {
                Text("Nothing logged yet")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(CRTheme.textDim)
            } else {
                // Dense rows, timers-screen style: tight insets and small
                // type so several entries read at a glance without scrolling.
                List(events.reversed()) { event in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color(hex: event.tintHex))
                            .frame(width: 3, height: 18)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(event.title)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(CRTheme.text)
                                .lineLimit(1)
                            if let detail = event.detail {
                                Text(detail)
                                    .font(.system(size: 8.5, design: .rounded))
                                    .foregroundStyle(CRTheme.textDim)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(event.stamp)
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(CRTheme.textDim)
                            Text(Self.wallClock.string(from: event.date))
                                .font(.system(size: 7.5, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(CRTheme.textDim.opacity(0.7))
                        }
                    }
                    .listRowBackground(RoundedRectangle(cornerRadius: 8).fill(CRTheme.surface))
                    .listRowInsets(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
                }
                .environment(\.defaultMinListRowHeight, 24)
            }
        }
        .navigationTitle("Log")
    }
}
