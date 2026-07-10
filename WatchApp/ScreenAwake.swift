// ScreenAwake.swift — "keep the screen on during a code".
// Modern watchOS has no frontmost-timeout API; the supported combination is:
//   • WKSupportsAlwaysOnDisplay (Info.plist) — wrist-down shows the code
//     screen luminance-dimmed instead of blanking, TimelineView keeps ticking.
//   • WKExtendedRuntimeSession (physical-therapy type, WKBackgroundModes) —
//     keeps the app the frontmost, running app for the length of the code,
//     so a wrist-raise lands back on the timers instantly, never the face.
// Session lifetime is owned by LiveSessionView via the settings toggle.

import WatchKit
import OSLog

final class ScreenAwakeManager: NSObject, WKExtendedRuntimeSessionDelegate {

    static let shared = ScreenAwakeManager()

    private var session: WKExtendedRuntimeSession?
    private let log = Logger(subsystem: "com.sebastianheredia.CodeRing",
                             category: "screen-awake")

    func begin() {
        guard session == nil || session?.state == .invalid else { return }
        let s = WKExtendedRuntimeSession()
        s.delegate = self
        s.start()
        session = s
        log.info("extended runtime session requested")
    }

    func end() {
        session?.invalidate()
        session = nil
    }

    // MARK: - WKExtendedRuntimeSessionDelegate

    func extendedRuntimeSessionDidStart(_ s: WKExtendedRuntimeSession) {
        log.info("extended runtime session started")
    }

    func extendedRuntimeSessionWillExpire(_ s: WKExtendedRuntimeSession) {
        log.info("extended runtime session expiring")
    }

    func extendedRuntimeSession(_ s: WKExtendedRuntimeSession,
                                didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
                                error: Error?) {
        log.info("extended runtime session ended (\(reason.rawValue)) \(error.map { $0.localizedDescription } ?? "")")
        session = nil
    }
}
