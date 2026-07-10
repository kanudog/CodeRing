// SummaryView.swift — the debrief screen after End, also reused for
// browsing recent sessions (onDone = nil → system back instead of Done).

import SwiftUI
import CodeCore

struct SummaryView: View {
    let session: CodeSession
    let onDone: (() -> Void)?

    private var stats: SessionStats { session.stats }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                banner

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                          spacing: 6) {
                    StatTile(label: "Duration", value: crClock(stats.totalSeconds))
                    StatTile(label: "CPR", value: stats.cprFractionPercent, color: CRTheme.cpr)
                    StatTile(label: "Epi", value: "×\(stats.epiCount)", color: CRTheme.med)
                    StatTile(label: "Shocks", value: "×\(stats.shockCount)", color: CRTheme.shock)
                    StatTile(label: "Rhythm ✓", value: "×\(stats.rhythmCheckCount)", color: CRTheme.rhythm)
                    StatTile(label: "Pauses", value: "\(stats.pauseCount)")
                    if let t = stats.secondsToFirstEpi {
                        StatTile(label: "First epi", value: crOffset(t), color: CRTheme.med)
                    }
                    if let t = stats.secondsToROSC {
                        StatTile(label: "ROSC", value: crOffset(t), color: CRTheme.rosc)
                    }
                }

                if !stats.medEvents.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(stats.medEvents.sorted(by: { $0.key < $1.key }), id: \.key) { name, count in
                            HStack {
                                Text(name)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(CRTheme.text)
                                Spacer()
                                Text("×\(count)")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(CRTheme.textDim)
                            }
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(CRTheme.surface))
                }

                Text("Full timeline + PDF report on iPhone")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(CRTheme.textDim)

                if let onDone {
                    Button(action: onDone) {
                        Text("Done")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(CRTheme.bg)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(RoundedRectangle(cornerRadius: 14).fill(CRTheme.cpr))
                    }
                    .buttonStyle(.plain)
                }

                DemoBadge(compact: true)
            }
            .padding(.horizontal, 4)
        }
        .background(CRTheme.bg)
        .navigationTitle("Summary")
    }

    private var banner: some View {
        HStack(spacing: 6) {
            Image(systemName: session.roscDate != nil ? "heart.fill" : "flag.checkered")
                .font(.system(size: 14, weight: .bold))
            Text(session.roscDate != nil ? "ROSC ACHIEVED" : "CODE ENDED")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .tracking(1)
        }
        .foregroundStyle(session.roscDate != nil ? CRTheme.bg : CRTheme.text)
        .frame(maxWidth: .infinity)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(session.roscDate != nil ? CRTheme.rosc : CRTheme.surfaceHi)
        )
    }
}
