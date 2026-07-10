// Theme.swift — Midnight Neon, extended from Block Ward's tokens.js discipline.
// Every color in the app comes from here. Never hardcode hex in views.

import SwiftUI

public extension Color {
    /// Init from "#RRGGBB" or "RRGGBB".
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

/// Central design tokens. Category accents mirror event severity coding.
public enum CRTheme {
    // Base
    public static let bgHex = "0A0F1E"          // midnight
    public static let surfaceHex = "131A2E"
    public static let surfaceHiHex = "1B2440"
    public static let ringTrackHex = "1E2742"
    public static let textHex = "F2F5FF"
    public static let textDimHex = "8A93B0"

    // Category accents
    public static let medHex = "FF3B5C"          // medications — hot red
    public static let shockHex = "FFB020"        // defib/cardioversion — amber
    public static let airwayHex = "22D3EE"       // airway — cyan
    public static let accessHex = "34D399"       // IV/IO — green
    public static let cprHex = "A78BFA"          // CPR cycle — violet
    public static let roscHex = "4ADE80"         // outcome — bright green
    public static let rhythmHex = "60A5FA"       // rhythm checks — blue
    public static let careHex = "2DD4BF"         // supportive care (temp, fluids) — teal
    public static let customHex = "F0ABFC"       // user-defined — pink
    public static let demoHex = "FFB020"         // demo badge — amber

    public static var bg: Color { Color(hex: bgHex) }
    public static var surface: Color { Color(hex: surfaceHex) }
    public static var surfaceHi: Color { Color(hex: surfaceHiHex) }
    public static var ringTrack: Color { Color(hex: ringTrackHex) }
    public static var text: Color { Color(hex: textHex) }
    public static var textDim: Color { Color(hex: textDimHex) }
    public static var med: Color { Color(hex: medHex) }
    public static var shock: Color { Color(hex: shockHex) }
    public static var airway: Color { Color(hex: airwayHex) }
    public static var access: Color { Color(hex: accessHex) }
    public static var cpr: Color { Color(hex: cprHex) }
    public static var rosc: Color { Color(hex: roscHex) }
    public static var rhythm: Color { Color(hex: rhythmHex) }
    public static var care: Color { Color(hex: careHex) }
    public static var custom: Color { Color(hex: customHex) }
    public static var demo: Color { Color(hex: demoHex) }
}

/// mm:ss formatting used on every timer surface.
public func crClock(_ interval: TimeInterval) -> String {
    let t = max(0, Int(interval.rounded(.down)))
    return String(format: "%d:%02d", t / 60, t % 60)
}

/// +mm:ss offset stamps for the event log and report.
public func crOffset(_ seconds: Int) -> String {
    let t = max(0, seconds)
    return String(format: "+%d:%02d", t / 60, t % 60)
}

/// Signed mm:ss — negatives keep their minus so overdue timers can count up
/// past zero (e.g. "-0:23" = 23 s past the pulse-check deadline).
public func crClockSigned(_ interval: TimeInterval) -> String {
    let t = Int(interval.rounded(.towardZero))
    let mag = abs(t)
    let body = String(format: "%d:%02d", mag / 60, mag % 60)
    return t < 0 ? "-\(body)" : body
}
