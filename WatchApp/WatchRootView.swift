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
        ScrollView {
            VStack(spacing: 10) {
                Button(action: startAction) {
                    VStack(spacing: 4) {
                        Image(systemName: "bolt.heart.fill")
                            .font(.system(size: 30, weight: .bold))
                        Text("START CODE")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .tracking(1.0)
                    }
                    .foregroundStyle(CRTheme.bg)
                    .frame(maxWidth: .infinity)
                    .frame(height: 86)
                    .background(RoundedRectangle(cornerRadius: 18).fill(CRTheme.cpr))
                }
                .buttonStyle(.plain)

                NavigationLink {
                    WatchSessionsList()
                } label: {
                    rowLabel(symbol: "clock.arrow.circlepath",
                             title: "Recent",
                             detail: "\(store.sessions.count)")
                }
                .buttonStyle(.plain)

                NavigationLink {
                    WatchSettingsView()
                } label: {
                    rowLabel(symbol: "gearshape.fill", title: "Settings", detail: "")
                }
                .buttonStyle(.plain)

                DemoBadge()
                    .padding(.top, 2)
            }
            .padding(.horizontal, 4)
        }
        .background(CRTheme.bg)
        .navigationTitle("CodeRing")
    }

    private func rowLabel(symbol: String, title: String, detail: String) -> some View {
        HStack {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CRTheme.textDim)
                .frame(width: 22)
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(CRTheme.text)
            Spacer()
            Text(detail)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(CRTheme.textDim)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 12).fill(CRTheme.surface))
    }
}

// MARK: - Recent sessions

struct WatchSessionsList: View {
    private let store = CodeStore.shared

    var body: some View {
        Group {
            if store.sessions.isEmpty {
                Text("No codes yet")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(CRTheme.textDim)
            } else {
                List(store.sessions) { session in
                    NavigationLink {
                        SummaryView(session: session, onDone: nil)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.startDate, style: .date)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                            HStack(spacing: 6) {
                                Text(crClock(session.duration(at: session.endDate ?? session.startDate)))
                                    .font(.system(size: 11, design: .rounded).monospacedDigit())
                                    .foregroundStyle(CRTheme.textDim)
                                if session.roscDate != nil {
                                    Text("ROSC")
                                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                                        .foregroundStyle(CRTheme.rosc)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Recent")
    }
}

// MARK: - Settings

struct WatchSettingsView: View {
    private let store = CodeStore.shared

    private var haptics: Binding<Bool> {
        Binding(get: { store.settings.hapticsEnabled },
                set: { on in
                    var s = store.settings
                    s.hapticsEnabled = on
                    store.updateSettings(s)
                    WatchHaptics.enabled = on
                })
    }

    private var metronomeSound: Binding<Bool> {
        Binding(get: { store.settings.metronomeSoundOn },
                set: { on in
                    var s = store.settings
                    s.metronomeSoundOn = on
                    store.updateSettings(s)
                })
    }

    var body: some View {
        Form {
            Toggle("Haptics", isOn: haptics)
            Toggle("Metronome sound", isOn: metronomeSound)
            Section {
                Text("Metronome: \(store.settings.metronomeBPM) bpm. Edit drugs, events, and timer lengths in the iPhone app.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(CRTheme.textDim)
            }
        }
        .navigationTitle("Settings")
    }
}
