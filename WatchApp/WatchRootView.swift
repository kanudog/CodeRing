// WatchRootView.swift — owns the top-level flow:
// Home → Setup → Live → Summary → back Home.
// The live engine replaces the whole hierarchy (no accidental back-swipe
// out of a running code). Ending merges + syncs the session to the phone.

import SwiftUI
import CodeCore

struct WatchRootView: View {

    private let store = CodeStore.shared
    @State private var liveEngine: SessionEngine?
    @State private var showSetup = false

    var body: some View {
        Group {
            if let engine = liveEngine {
                if engine.isEnded {
                    SummaryView(session: engine.session) {
                        liveEngine = nil
                    }
                } else {
                    LiveSessionView(engine: engine) { finished in
                        store.merge(session: finished)
                        ConnectivityManager.shared.send(.session, finished)
                    }
                }
            } else {
                NavigationStack {
                    HomeView(startAction: { showSetup = true })
                        .navigationDestination(isPresented: $showSetup) {
                            SetupFlowView { engine in
                                showSetup = false
                                liveEngine = engine
                            }
                        }
                }
            }
        }
        .onAppear { WatchHaptics.enabled = store.settings.hapticsEnabled }
        .onOpenURL { url in
            // codering://new — complication tap goes straight to setup
            guard liveEngine == nil else { return }
            if url.absoluteString.contains("new") { showSetup = true }
        }
    }
}

// MARK: - Home

struct HomeView: View {
    let startAction: () -> Void
    private let store = CodeStore.shared

    var body: some View {
        ZStack {
            // Full-bleed backdrop — without this the navy stops at the safe
            // area and the rounded display shows black bars down the sides.
            CRTheme.bg.ignoresSafeArea()

            ScrollView {
            VStack(spacing: 6) {
                // Bullseye cluster: START CODE front and center, Recent and
                // Settings tucked under its lower corners (drawn first, so
                // the big button overlaps them slightly).
                ZStack {
                    // ±42 keeps the labels clear of the display's corner
                    // curve; y 50 gives the big button real breathing room.
                    orbitButton(symbol: "clock.arrow.circlepath", title: "Recent") {
                        WatchSessionsList()
                    }
                    .offset(x: -42, y: 50)

                    orbitButton(symbol: "gearshape.fill", title: "Settings") {
                        WatchSettingsView()
                    }
                    .offset(x: 42, y: 50)

                    Button(action: startAction) {
                        ZStack {
                            Circle().fill(CRTheme.cpr)
                            Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1.5)
                            VStack(spacing: 2) {
                                Image(systemName: "bolt.heart.fill")
                                    .font(.system(size: 24, weight: .bold))
                                Text("START")
                                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                                    .tracking(1.2)
                                Text("CODE")
                                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                                    .tracking(1.2)
                            }
                            .foregroundStyle(CRTheme.bg)
                        }
                        .frame(width: 100, height: 100)
                    }
                    .buttonStyle(.plain)
                    .offset(y: -20)
                }
                .frame(height: 172)

                DemoBadge()
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
            }
        }
        .navigationTitle("CodeRing")
    }

    /// Small circular satellite of the START CODE button.
    private func orbitButton<Destination: View>(symbol: String, title: String,
                                                @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink { destination() } label: {
            VStack(spacing: 2) {
                ZStack {
                    Circle().fill(CRTheme.surfaceHi)
                    Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1)
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(CRTheme.text)
                }
                .frame(width: 54, height: 54)
                Text(title.uppercased())
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(CRTheme.textDim)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recent sessions

struct WatchSessionsList: View {
    private let store = CodeStore.shared
    @State private var confirmClear = false

    var body: some View {
        Group {
            if store.sessions.isEmpty {
                Text("No codes yet")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(CRTheme.textDim)
            } else {
                List {
                    ForEach(store.sessions) { session in
                        NavigationLink {
                            SummaryView(session: session, onDone: nil)
                        } label: {
                            tile(session)
                        }
                    }

                    // Clear lives at the very bottom, destructive and
                    // double-confirmed — codes are the whole record.
                    Button(role: .destructive) {
                        confirmClear = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Clear all codes", systemImage: "trash.fill")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                            Spacer()
                        }
                    }
                    .listRowBackground(RoundedRectangle(cornerRadius: 10)
                        .fill(CRTheme.med.opacity(0.18)))
                }
            }
        }
        .navigationTitle("Recent")
        .confirmationDialog("Delete all saved codes?", isPresented: $confirmClear) {
            Button("Delete everything", role: .destructive) {
                store.clearAllSessions()
                WatchHaptics.play(.failure)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently removes every saved code from this watch. Codes already synced to the phone stay there.")
        }
    }

    /// Code type · weight · length · outcome — the tile answers "which code
    /// was this" without opening it.
    private func tile(_ session: CodeSession) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(session.protocolName)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(CRTheme.text)
                Spacer()
                if session.roscDate != nil {
                    Text("ROSC")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(CRTheme.rosc)
                } else {
                    Text("NO ROSC")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(CRTheme.textDim)
                }
            }
            Text("\(session.patient.weightLabel) · \(session.startDate.formatted(date: .abbreviated, time: .shortened))")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(CRTheme.textDim)
            Text("Code length: \(crClock(session.duration(at: session.endDate ?? session.startDate)))")
                .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(CRTheme.cpr)
        }
        .padding(.vertical, 1)
    }
}

// MARK: - Settings

struct WatchSettingsView: View {
    private let store = CodeStore.shared

    /// One binding per settings field, all funneled through CodeStore.
    private func setting<T>(_ get: @escaping (AppSettings) -> T,
                            _ set: @escaping (inout AppSettings, T) -> Void) -> Binding<T> {
        Binding(get: { get(store.settings) },
                set: { value in
                    var s = store.settings
                    set(&s, value)
                    store.updateSettings(s)
                })
    }

    var body: some View {
        Form {
            Section("Display") {
                Toggle("Keep screen awake", isOn: setting({ $0.keepScreenOn },
                                                          { $0.keepScreenOn = $1 }))
                Text("Keeps the app running and frontmost for the whole code, and shows the timers dimmed instead of a blank screen on wrist-down (Always-On models). Wake behavior also depends on the watch's Display settings.")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(CRTheme.textDim)
            }

            Section("Metronome") {
                Toggle("Sound", isOn: setting({ $0.metronomeSoundOn },
                                              { $0.metronomeSoundOn = $1 }))
                Picker("Pitch", selection: setting({ $0.metronomePitch },
                                                   { $0.metronomePitch = $1 })) {
                    ForEach(MetronomePitch.allCases, id: \.self) { p in
                        Text(p.label).tag(p)
                    }
                }
                Text("\(store.settings.metronomeBPM) bpm · audio only, no vibration")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(CRTheme.textDim)
            }

            Section("Haptics") {
                Toggle("Haptics", isOn: setting({ $0.hapticsEnabled },
                                                { $0.hapticsEnabled = $1 })
                    .onChange { WatchHaptics.enabled = $0 })

                hapticRow("Pulse check due", \.hapticPulseCheckDue) { $0.hapticPulseCheckDue = $1 }
                hapticRow("Med due", \.hapticMedDue) { $0.hapticMedDue = $1 }
                hapticRow("Cycle done · swap", \.hapticCycleComplete) { $0.hapticCycleComplete = $1 }
                Text("Pick a rhythm per cue — tap a row's pattern to feel it.")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(CRTheme.textDim)
            }

            Section {
                Text("Edit drugs, colors, events, and timer lengths in the iPhone app.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(CRTheme.textDim)
            }
        }
        .navigationTitle("Settings")
    }

    private func hapticRow(_ title: String,
                           _ keyPath: KeyPath<AppSettings, HapticPattern>,
                           _ set: @escaping (inout AppSettings, HapticPattern) -> Void) -> some View {
        Picker(title, selection: setting({ $0[keyPath: keyPath] }, set)
            .onChange { WatchHaptics.play($0) }) {   // preview on select
            ForEach(HapticPattern.allCases, id: \.self) { p in
                Text(p.label).tag(p)
            }
        }
    }
}

private extension Binding {
    /// Runs a side effect after each write — settings rows use it to apply
    /// or preview the new value immediately.
    func onChange(_ action: @escaping (Value) -> Void) -> Binding<Value> {
        Binding(get: { wrappedValue },
                set: { wrappedValue = $0; action($0) })
    }
}
