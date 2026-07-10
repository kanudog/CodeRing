// ProtocolSettingsView.swift — user-adjustable timer lengths.
// Overrides live in AppSettings (nil = protocol default) and are applied at
// engine construction via CodeStore.effectiveProtocol(_:). Sync to the watch
// so both devices build identical engines.

import SwiftUI
import CodeCore

struct ProtocolSettingsView: View {

    private let store = CodeStore.shared
    @State private var sentTick = false

    private var cycleSeconds: Binding<TimeInterval> {
        Binding(get: { store.settings.cycleSecondsOverride ?? 120 },
                set: { value in
                    var s = store.settings
                    s.cycleSecondsOverride = value == 120 ? nil : value
                    store.updateSettings(s)
                })
    }

    private var epiSeconds: Binding<TimeInterval> {
        Binding(get: { store.settings.epiSecondsOverride ?? 180 },
                set: { value in
                    var s = store.settings
                    s.epiSecondsOverride = value == 180 ? nil : value
                    store.updateSettings(s)
                })
    }

    var body: some View {
        Form {
            Section {
                Stepper(value: cycleSeconds, in: 60...240, step: 15) {
                    HStack {
                        Text("Cycle length")
                        Spacer()
                        Text(crClock(cycleSeconds.wrappedValue))
                            .monospacedDigit()
                            .foregroundStyle(CRTheme.textDim)
                    }
                }
            } header: {
                Text("CPR cycle")
            } footer: {
                Text("Default 2:00. The violet ring counts down each cycle; rhythm check lands at the end.")
            }

            Section {
                Stepper(value: epiSeconds, in: 120...300, step: 30) {
                    HStack {
                        Text("Epi interval")
                        Spacer()
                        Text(crClock(epiSeconds.wrappedValue))
                            .monospacedDigit()
                            .foregroundStyle(CRTheme.textDim)
                    }
                }
            } header: {
                Text("Epinephrine")
            } footer: {
                Text("Default 3:00 (q3–5 min window). Giving epi restarts this timer; it runs through CPR pauses.")
            }

            Section {
                Button("Reset to defaults") {
                    var s = store.settings
                    s.cycleSecondsOverride = nil
                    s.epiSecondsOverride = nil
                    store.updateSettings(s)
                }
                Button(sentTick ? "Sent ✓" : "Send settings to Watch") {
                    ConnectivityManager.shared.send(.settings, store.settings)
                    sentTick = true
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        sentTick = false
                    }
                }
            } footer: {
                Text("Overrides apply to new codes. Sync so the watch builds the same timers.")
            }
        }
        .navigationTitle("Timers")
    }
}
