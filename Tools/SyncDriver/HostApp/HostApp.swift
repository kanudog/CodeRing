// HostApp.swift — empty host for the phone UI-test runner.
// The tests drive the INSTALLED CodeRing iOS app by bundle id; this app
// exists only because XCUITest bundles need a host target.

import SwiftUI

@main
struct HostApp: App {
    var body: some Scene {
        WindowGroup {
            Text("SyncDriver phone host")
        }
    }
}
