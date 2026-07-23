// CodeRingWatchApp.swift — watch entry point.
// Activates WatchConnectivity and merges anything the iPhone pushes
// (drug sets, custom events, settings) into the local store.

import SwiftUI
import CodeCore

@main
struct CodeRingWatchApp: App {

    init() {
        ConnectivityManager.shared.activate()
        ConnectivityManager.shared.onReceive = { kind, data in
            Task { @MainActor in
                let store = CodeStore.shared
                switch kind {
                case .drugSets:
                    if let sets = SyncDecoder.decode([DrugProfileSet].self, from: data) {
                        store.replaceDrugSets(sets)
                    }
                case .customEvents:
                    if let events = SyncDecoder.decode([EventDefinition].self, from: data) {
                        store.replaceCustomEvents(events)
                    }
                case .settings:
                    if var settings = SyncDecoder.decode(AppSettings.self, from: data) {
                        // menuTapOnly is a watch-local interaction preference
                        // with no phone editor — it must survive the phone's
                        // wholesale settings push.
                        settings.menuTapOnly = store.settings.menuTapOnly
                        store.updateSettings(settings)
                        WatchHaptics.enabled = settings.hapticsEnabled
                    }
                case .session:
                    if let session = SyncDecoder.decode(CodeSession.self, from: data) {
                        store.merge(session: session)
                    }
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
    }
}
