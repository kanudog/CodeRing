// HistoryViews.swift — session review on the phone.
// List → detail (patient header, stat grid, med totals, full timeline)
// → Share exports the PDF report through the system share sheet.

import SwiftUI
import CodeCore

struct HistoryListView: View {
    private let store = CodeStore.shared

    var body: some View {
        NavigationStack {
            Group {
                if store.sessions.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.largeTitle)
                            .foregroundStyle(CRTheme.textDim)
                        Text("No codes yet")
                            .font(.headline)
                        Text("Sessions sync here from the watch when they end.")
                            .font(.footnote)
                            .foregroundStyle(CRTheme.textDim)
                    }
                } else {
                    List {
                        ForEach(store.sessions) { session in
                            NavigationLink {
                                SessionDetailView(session: session)
                            } label: {
                                row(session)
                            }
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { store.sessions[$0].id }
                            ids.forEach { store.delete(sessionID: $0) }
                        }
                    }
                }
            }
            .navigationTitle("History")
        }
    }

    private func row(_ session: CodeSession) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(session.startDate.formatted(date: .abbreviated, time: .shortened))
                .font(.body.weight(.semibold))
            HStack(spacing: 8) {
                Text(session.protocolName)
                Text(crClock(session.stats.totalSeconds)).monospacedDigit()
                if session.roscDate != nil {
                    Text("ROSC")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(CRTheme.rosc)
                }
            }
            .font(.caption)
            .foregroundStyle(CRTheme.textDim)
        }
    }
}

// MARK: - Detail

private struct PDFDoc: Identifiable {
    let url: URL
    var id: String { url.path }
}

struct SessionDetailView: View {
    let session: CodeSession
    @State private var pdfDoc: PDFDoc?
    @State private var showWallTimes = false   // timeline: +offset ↔ local time

    private var stats: SessionStats { session.stats }

    private static let wallClock: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "H:mm:ss"
        return df
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                patientCard

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3),
                          spacing: 8) {
                    StatTile(label: "Duration", value: crClock(stats.totalSeconds))
                    StatTile(label: "CPR", value: stats.cprFractionPercent, color: CRTheme.cpr)
                    StatTile(label: "Pauses", value: "\(stats.pauseCount)")
                    StatTile(label: "Epi", value: "×\(stats.epiCount)", color: CRTheme.med)
                    StatTile(label: "Shocks", value: "×\(stats.shockCount)", color: CRTheme.shock)
                    StatTile(label: "Rhythm ✓", value: "×\(stats.rhythmCheckCount)", color: CRTheme.rhythm)
                    if let t = stats.secondsToFirstEpi {
                        StatTile(label: "First epi", value: crOffset(t), color: CRTheme.med)
                    }
                    if let t = stats.secondsToROSC {
                        StatTile(label: "ROSC", value: crOffset(t), color: CRTheme.rosc)
                    }
                }

                if !stats.medEvents.isEmpty {
                    card {
                        VStack(alignment: .leading, spacing: 6) {
                            sectionLabel("MEDICATIONS")
                            ForEach(stats.medEvents.sorted(by: { $0.key < $1.key }),
                                    id: \.key) { name, count in
                                HStack {
                                    Text(name).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text("×\(count)")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(CRTheme.textDim)
                                }
                            }
                        }
                    }
                }

                card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            sectionLabel("TIMELINE — \(showWallTimes ? "LOCAL TIME" : "TIME INTO CODE")")
                            Spacer()
                            Button {
                                withAnimation { showWallTimes.toggle() }
                            } label: {
                                Image(systemName: showWallTimes ? "clock.fill" : "stopwatch.fill")
                                    .font(.caption)
                                    .foregroundStyle(CRTheme.cpr)
                            }
                            .accessibilityLabel("Toggle time display")
                        }
                        ForEach(session.events) { event in
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(event.category.color)
                                    .frame(width: 3, height: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(event.title)
                                        .font(.subheadline.weight(.semibold))
                                    if let detail = event.detail {
                                        Text(detail)
                                            .font(.caption)
                                            .foregroundStyle(CRTheme.textDim)
                                    }
                                }
                                Spacer()
                                Text(showWallTimes ? Self.wallClock.string(from: event.date)
                                                   : event.stamp)
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(CRTheme.textDim)
                            }
                        }
                    }
                }

                DemoBadge()
            }
            .padding()
        }
        .background(CRTheme.bg)
        .navigationTitle(session.startDate.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                if let url = ReportGenerator.makePDF(for: session) {
                    pdfDoc = PDFDoc(url: url)
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .sheet(item: $pdfDoc) { doc in
            ShareSheet(items: [doc.url])
        }
    }

    private var patientCard: some View {
        card {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    sectionLabel(session.protocolName.uppercased())
                    Spacer()
                    if session.roscDate != nil {
                        Text("ROSC")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(CRTheme.rosc)
                    }
                }
                Text("\(session.patient.weightLabel) · \(session.patient.sourceDetail)")
                    .font(.title3.weight(.bold))
                HStack(spacing: 14) {
                    Text("Age \(session.patient.ageLabel)")
                    Text("Sex \(session.patient.sex.label)")
                    if !session.deviceName.isEmpty { Text(session.deviceName) }
                }
                .font(.caption)
                .foregroundStyle(CRTheme.textDim)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.heavy))
            .tracking(1.2)
            .foregroundStyle(CRTheme.textDim)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(CRTheme.surface))
    }
}
