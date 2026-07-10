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
                List(events.reversed()) { event in
                    HStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(event.category.color)
                            .frame(width: 3, height: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.title)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(CRTheme.text)
                                .lineLimit(1)
                            if let detail = event.detail {
                                Text(detail)
                                    .font(.system(size: 10, design: .rounded))
                                    .foregroundStyle(CRTheme.textDim)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(event.stamp)
                                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(CRTheme.textDim)
                            Text(Self.wallClock.string(from: event.date))
                                .font(.system(size: 8, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(CRTheme.textDim.opacity(0.7))
                        }
                    }
                    .listRowBackground(RoundedRectangle(cornerRadius: 10).fill(CRTheme.surface))
                }
            }
        }
        .navigationTitle("Log")
    }
}
