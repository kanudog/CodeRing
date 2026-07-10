// CodeRingApp.swift — iPhone companion shell.
// Tabs: Home · Drugs · Events · History · Settings.
// The phone is the editing + review surface; codes run on the watch.
// Inbound sync: completed sessions from the watch merge into the store.

import SwiftUI
import CodeCore

@main
struct CodeRingApp: App {

    init() {
        ConnectivityManager.shared.activate()
        ConnectivityManager.shared.onReceive = { kind, data in
            Task { @MainActor in
                let store = CodeStore.shared
                switch kind {
                case .session:
                    if let session = SyncDecoder.decode(CodeSession.self, from: data) {
                        store.merge(session: session)
                    }
                default:
                    break   // phone is the source of truth for the rest
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .preferredColorScheme(.dark)
                .tint(CRTheme.cpr)
        }
    }
}

// MARK: - Tabs

struct RootTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Home", systemImage: "waveform.path.ecg") }
            DrugLibraryView()
                .tabItem { Label("Drugs", systemImage: "pills.fill") }
            EventsAdminView()
                .tabItem { Label("Events", systemImage: "square.grid.2x2.fill") }
            HistoryListView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            PhoneSettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    private let store = CodeStore.shared
    @State private var sentTick = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    DemoBadge()

                    lastSessionCard

                    Button(action: sendLibrary) {
                        HStack {
                            Image(systemName: sentTick ? "checkmark.circle.fill"
                                                       : "arrow.up.forward.app.fill")
                            Text(sentTick ? "Sent to Watch" : "Send library to Watch")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(RoundedRectangle(cornerRadius: 14)
                            .fill(sentTick ? CRTheme.rosc.opacity(0.25) : CRTheme.surfaceHi))
                        .foregroundStyle(sentTick ? CRTheme.rosc : CRTheme.text)
                    }

                    HStack(spacing: 10) {
                        StatTile(label: "Codes logged", value: "\(store.sessions.count)")
                        StatTile(label: "Drug sets", value: "\(store.drugSets.count)")
                        StatTile(label: "Custom events", value: "\(store.customEvents.count)")
                    }

                    Text("Drug sets, custom events, and timer settings sync to the watch. Codes run on the watch and land in History here.")
                        .font(.footnote)
                        .foregroundStyle(CRTheme.textDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .background(CRTheme.bg)
            .navigationTitle("CodeRing")
        }
    }

    @ViewBuilder
    private var lastSessionCard: some View {
        if let last = store.sessions.first {
            NavigationLink {
                SessionDetailView(session: last)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("LAST CODE")
                            .font(.caption2.weight(.heavy))
                            .tracking(1.2)
                            .foregroundStyle(CRTheme.textDim)
                        Spacer()
                        if last.roscDate != nil {
                            Text("ROSC")
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(CRTheme.rosc)
                        }
                    }
                    Text(last.startDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(CRTheme.text)
                    HStack(spacing: 14) {
                        labelValue("Duration", crClock(last.stats.totalSeconds))
                        labelValue("CPR", last.stats.cprFractionPercent)
                        labelValue("Epi", "×\(last.stats.epiCount)")
                        labelValue("Shocks", "×\(last.stats.shockCount)")
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16).fill(CRTheme.surface))
            }
            .buttonStyle(.plain)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "applewatch.radiowaves.left.and.right")
                    .font(.title)
                    .foregroundStyle(CRTheme.cpr)
                Text("No codes yet")
                    .font(.headline)
                    .foregroundStyle(CRTheme.text)
                Text("Start one on your watch — it lands here when it ends.")
                    .font(.footnote)
                    .foregroundStyle(CRTheme.textDim)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
            .background(RoundedRectangle(cornerRadius: 16).fill(CRTheme.surface))
        }
    }

    private func labelValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(CRTheme.text)
            Text(label)
                .font(.caption2)
                .foregroundStyle(CRTheme.textDim)
        }
    }

    private func sendLibrary() {
        ConnectivityManager.shared.send(.drugSets, store.drugSets)
        ConnectivityManager.shared.send(.customEvents, store.customEvents)
        ConnectivityManager.shared.send(.settings, store.settings)
        withAnimation { sentTick = true }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { sentTick = false }
        }
    }
}

// MARK: - Settings

struct PhoneSettingsView: View {
    private let store = CodeStore.shared
    @State private var showResetConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Feedback") {
                    Toggle("Haptics", isOn: binding(\.hapticsEnabled))
                    Toggle("Metronome sound", isOn: binding(\.metronomeSoundOn))
                    Stepper("Metronome: \(store.settings.metronomeBPM) bpm",
                            value: bpmBinding, in: 90...130, step: 5)
                }

                Section("Protocol timers") {
                    NavigationLink("Cycle & epi intervals") {
                        ProtocolSettingsView()
                    }
                }

                Section {
                    Button("Send settings to Watch") {
                        ConnectivityManager.shared.send(.settings, store.settings)
                    }
                }

                Section("Danger zone") {
                    Button("Reset all data", role: .destructive) {
                        showResetConfirm = true
                    }
                }

                Section("About") {
                    Text("CodeRing is a DEMONSTRATION of a pediatric code timer. It is not a medical device, has not been validated, and must never be used in real clinical care. All dose values are editable placeholders.")
                        .font(.footnote)
                        .foregroundStyle(CRTheme.textDim)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete all sessions, custom events, and edits?",
                                isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button("Reset everything", role: .destructive) {
                    store.resetAllData()
                }
            }
        }
    }

    private func binding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(get: { store.settings[keyPath: keyPath] },
                set: { newValue in
                    var s = store.settings
                    s[keyPath: keyPath] = newValue
                    store.updateSettings(s)
                })
    }

    private var bpmBinding: Binding<Int> {
        Binding(get: { store.settings.metronomeBPM },
                set: { newValue in
                    var s = store.settings
                    s.metronomeBPM = newValue
                    store.updateSettings(s)
                })
    }
}
