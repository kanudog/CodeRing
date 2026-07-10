// WatchHostApp.swift — empty host for the watch UI-test runner.
// The tests drive the INSTALLED CodeRing watch app by bundle id; this app
// exists only because XCUITest bundles need a host target.

import SwiftUI

@main
struct WatchHostApp: App {
    var body: some Scene {
        WindowGroup {
            Text("SyncDriver watch host")
        }
    }
}
