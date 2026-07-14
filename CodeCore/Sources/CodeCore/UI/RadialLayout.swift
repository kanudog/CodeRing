// RadialLayout.swift — pure geometry for the watch's radial menus.
// Lives in CodeCore (no SwiftUI/WatchKit) so the layout rules are unit-
// testable: every level must keep its bubbles fully on screen with a
// minimum chord between neighbors, and cascaded levels re-center on the
// item that opened them (the finger's position), fanning outward.

import Foundation
import CoreGraphics

public struct RadialLayout: Sendable, Equatable {

    public var anchor: CGPoint            // center of THIS level's arc
    public var bounds: CGSize
    public private(set) var arcStart: Double = -160   // degrees; 0 = right, -90 = up
    public private(set) var arcEnd: Double = -20
    public private(set) var radius: CGFloat = 64

    /// Bubble Ø38 + breathing room — below this, neighbors overlap and
    /// hover flaps between them.
    public static let minChord: CGFloat = 47
    public static let maxRadius: CGFloat = 118

    public init(anchor: CGPoint, bounds: CGSize) {
        self.anchor = anchor
        self.bounds = bounds
    }

    // MARK: - Fitting

    /// All contiguous runs of degrees whose bubbles land fully on screen.
    /// Samples the FULL circle (−270…90 covers every direction) — cascaded
    /// fans near the top edge legitimately open downward.
    private func validRuns(radius r: CGFloat) -> [(lo: Double, hi: Double)] {
        var runs: [(lo: Double, hi: Double)] = []
        var runStart: Double? = nil
        var deg = -270.0
        while deg <= 90 {
            let a = deg * .pi / 180
            let p = CGPoint(x: anchor.x + r * cos(a), y: anchor.y + r * sin(a))
            let ok = p.x >= 22 && p.x <= bounds.width - 22 &&
                     p.y >= 16 && p.y <= bounds.height - 18
            if ok, runStart == nil { runStart = deg }
            if !ok, let s = runStart { runs.append((s, deg - 3)); runStart = nil }
            deg += 3
        }
        if let s = runStart { runs.append((s, 90)) }
        return runs
    }

    /// Choose arcStart/arcEnd/radius for `count` bubbles: enough angular
    /// spacing for the minimum chord, centered on the preferred direction.
    /// Direction (degrees) from a point toward the roomiest part of the
    /// screen — cascaded fans open here so children never pile into an edge.
    public static func openSpaceDirection(from p: CGPoint, bounds: CGSize) -> Double {
        let target = CGPoint(x: bounds.width / 2, y: bounds.height * 0.48)
        let dx = Double(target.x - p.x), dy = Double(target.y - p.y)
        // Finger already at the middle → any direction works; prefer up.
        if (dx * dx + dy * dy).squareRoot() < 24 { return -90 }
        return atan2(dy, dx) * 180 / .pi
    }

    /// Prefers the nearest window that actually FITS the whole span (a tiny
    /// sliver next to the preferred direction must never beat a roomy window
    /// further away); radius grows until one fits, then the widest window
    /// takes the squeeze.
    public mutating func fit(count: Int, preferredCenter: Double?, startRadius: CGFloat,
                             radiusCap: CGFloat = RadialLayout.maxRadius) {
        var want = preferredCenter ?? -90
        if want > 90 { want -= 360 }   // sampling domain is −270…90

        func place(_ run: (lo: Double, hi: Double), span: Double, r: CGFloat) {
            let half = min(span, run.hi - run.lo) / 2
            let center = min(max(want, run.lo + half), run.hi - half)
            radius = r
            arcStart = center - half
            arcEnd = center + half
        }

        // Radii to try: grow from the start ring (up to the cap), then
        // shrink below it. A tight cap keeps cascaded fans a uniform
        // finger-reach from the touch point.
        var candidates: [CGFloat] = []
        var g = startRadius
        while g <= radiusCap { candidates.append(g); g += 12 }
        var s = startRadius - 12
        while s >= 40 { candidates.append(s); s -= 12 }

        var bestSqueeze: (chord: CGFloat, r: CGFloat, run: (lo: Double, hi: Double), span: Double)? = nil
        for r in candidates {
            let runs = validRuns(radius: r)
            guard !runs.isEmpty else { continue }
            let spacing = Double(2 * asin(min(1, Self.minChord / (2 * r)))) * 180 / .pi
            let span = spacing * Double(max(0, count - 1))
            let fitting = runs.filter { $0.hi - $0.lo >= span }
            if let run = fitting.min(by: {
                abs(want - ($0.lo + $0.hi) / 2) < abs(want - ($1.lo + $1.hi) / 2)
            }) {
                place(run, span: span, r: r)
                return
            }
            // No run fits at this radius — remember the least-bad squeeze
            // (the radius+window whose forced spacing gives the widest chord).
            if count > 1, let widest = runs.max(by: { ($0.hi - $0.lo) < ($1.hi - $1.lo) }) {
                let forced = min(spacing, (widest.hi - widest.lo) / Double(count - 1))
                let chord = 2 * r * sin(CGFloat(forced / 2 * .pi / 180))
                if bestSqueeze == nil || chord > bestSqueeze!.chord {
                    bestSqueeze = (chord, r, widest, forced * Double(count - 1))
                }
            }
        }
        if let b = bestSqueeze {
            place(b.run, span: b.span, r: b.r)
        } else {
            radius = startRadius; arcStart = -160; arcEnd = -20
        }
    }

    // MARK: - Positions

    public func angle(forIndex i: Int, count: Int) -> Double {
        guard count > 1 else { return (arcStart + arcEnd) / 2 }
        return arcStart + (arcEnd - arcStart) * Double(i) / Double(count - 1)
    }

    public func position(forIndex i: Int, count: Int) -> CGPoint {
        let a = angle(forIndex: i, count: count) * .pi / 180
        return CGPoint(x: anchor.x + radius * cos(a),
                       y: anchor.y + radius * sin(a))
    }

    /// Labels sit radially OUTSIDE their bubble so no label ever covers an
    /// adjacent bubble. Where outward would clip the screen or run sideways
    /// into a neighbor, the label tries above, then below, then beside its
    /// own bubble — whichever spot is actually CLEAR of the other bubbles.
    public func labelPosition(forIndex i: Int, count: Int) -> CGPoint {
        let bubble = position(forIndex: i, count: count)
        let others = (0..<count).filter { $0 != i }
            .map { position(forIndex: $0, count: count) }
        return labelPosition(around: anchor, bubble: bubble, others: others)
    }

    /// Point-based variant — hand-placed (override) bubbles use the same
    /// label rules, with the outward direction taken from center → bubble.
    public func labelPosition(around center: CGPoint, bubble: CGPoint,
                              others: [CGPoint]) -> CGPoint {
        let a = atan2(Double(bubble.y - center.y), Double(bubble.x - center.x))
        func clear(_ p: CGPoint) -> Bool {
            p.y >= 8 && p.y <= bounds.height - 10 &&
            others.allSatisfy { hypot($0.x - p.x, $0.y - p.y) > 32 }
        }
        func stacked() -> CGPoint {
            let above = CGPoint(x: bubble.x, y: bubble.y - 27)
            if clear(above) { return above }
            let below = CGPoint(x: bubble.x, y: bubble.y + 27)
            if clear(below) { return below }
            return CGPoint(x: bubble.x + (cos(a) >= 0 ? 36 : -36), y: bubble.y)
        }
        // Shallow arc ends: "outward" is sideways — stack instead.
        if abs(sin(a)) < 0.45 { return stacked() }
        let r = CGFloat(hypot(Double(bubble.x - center.x), Double(bubble.y - center.y))) + 30
        let p = CGPoint(x: center.x + r * CGFloat(cos(a)), y: center.y + r * CGFloat(sin(a)))
        // Off the top edge → fall back to stacking.
        if p.y < 14 { return stacked() }
        return p
    }
}

// MARK: - Hand-placed fan layouts (Sebastian, layout-editor export 2026-07-14)

/// A fixed arrangement for one fan. Sub-fan values are OFFSETS from the
/// parent bubble (the finger point) so the whole arrangement rides along if
/// the parent ever moves; `absolute` marks root fans placed in screen points.
public struct FanOverride: Sendable {
    public let items: [Int: CGPoint]     // item index → offset (or absolute)
    public let back: CGPoint?
    public let cancel: CGPoint?
    public let absolute: Bool

    public init(items: [Int: CGPoint], back: CGPoint? = nil,
                cancel: CGPoint? = nil, absolute: Bool = false) {
        self.items = items; self.back = back; self.cancel = cancel
        self.absolute = absolute
    }
}

public enum FanLayoutOverrides {

    /// Root-anchor id → table key (only overridden roots listed).
    public static func key(forRootAnchor id: String) -> String? {
        id == "shock" ? "shockRoot" : nil
    }

    /// Parent item id ("grp:*") → table key.
    public static func key(forParentItem id: String) -> String? {
        switch id {
        case "grp:access": return "access"
        case "grp:airway": return "airway"
        case "grp:comms": return "comms"
        case "grp:call": return "call"
        case "grp:arrival": return "arrival"
        case "grp:temp": return "temp"
        case "grp:fluids": return "fluids"
        case "grp:more": return "moreVol"
        case "grp:defib": return "defib"
        default: return nil
        }
    }

    public static let table: [String: FanOverride] = [
        // Shock root — absolute: Defib rides high center-right, Cardiovert below it.
        "shockRoot": FanOverride(items: [0: CGPoint(x: 116, y: 38),
                                         1: CGPoint(x: 142, y: 96)],
                                 absolute: true),
        // Access (parent at ~(37,110)): IV → IO → Art line sweep up-right.
        "access": FanOverride(items: [0: CGPoint(x: -8, y: -71),
                                      1: CGPoint(x: 38, y: -60),
                                      2: CGPoint(x: 65, y: -24)],
                              back: CGPoint(x: 62, y: 46),
                              cancel: CGPoint(x: 1, y: 50)),
        // Airway (parent ~(76,83)): Mask/ETT up top, BVM/Trach at the sides.
        "airway": FanOverride(items: [0: CGPoint(x: 23, y: -47),
                                      1: CGPoint(x: -51, y: -6),
                                      2: CGPoint(x: -25, y: -47),
                                      3: CGPoint(x: 50, y: -6)],
                              back: CGPoint(x: 23, y: 72),
                              cancel: CGPoint(x: -46, y: 62)),
        // Comms (parent ~(123,83)).
        "comms": FanOverride(items: [0: CGPoint(x: -36, y: -40),
                                     1: CGPoint(x: -54, y: 13)],
                             back: CGPoint(x: -24, y: 72),
                             cancel: CGPoint(x: 46, y: 70)),
        // Call (parent = Comms▸Call at ~(87,43)): arc down the right side.
        "call": FanOverride(items: [0: CGPoint(x: 68, y: -18),
                                    1: CGPoint(x: 64, y: 24),
                                    2: CGPoint(x: 40, y: 60),
                                    3: CGPoint(x: -4, y: 67)],
                            back: CGPoint(x: -58, y: 39),
                            cancel: CGPoint(x: -60, y: -24)),
        // Arrival (parent ~(69,96)): arc across the top.
        "arrival": FanOverride(items: [0: CGPoint(x: -37, y: -54),
                                       1: CGPoint(x: 12, y: -52),
                                       2: CGPoint(x: 50, y: -21),
                                       3: CGPoint(x: 43, y: 26)],
                               back: CGPoint(x: -39, y: 49),
                               cancel: CGPoint(x: -49, y: 2)),
        // Temp (parent ~(161,110)): devices keep the auto-fit; pads placed.
        "temp": FanOverride(items: [:],
                            back: CGPoint(x: 16, y: 53),
                            cancel: CGPoint(x: -131, y: 34)),
        // Fluids (parent ~(174,37)): Blood/10/20 cascade down-left.
        "fluids": FanOverride(items: [0: CGPoint(x: -62, y: -10),
                                      1: CGPoint(x: -55, y: 34),
                                      2: CGPoint(x: -20, y: 63)],
                              back: CGPoint(x: 1, y: 112),
                              cancel: CGPoint(x: -144, y: 107)),
        // More/volume (parent ~(61,159)): Drip/Mag up, Naloxone right.
        "moreVol": FanOverride(items: [0: CGPoint(x: -25, y: -64),
                                       1: CGPoint(x: 26, y: -60),
                                       2: CGPoint(x: 58, y: -18)],
                               back: CGPoint(x: -45, y: 17),
                               cancel: CGPoint(x: -41, y: -138)),
        // Defib rungs (parent = fixed Defib at (116,38)): ladder down-left.
        "defib": FanOverride(items: [0: CGPoint(x: -54, y: 1),
                                     1: CGPoint(x: -33, y: 44),
                                     2: CGPoint(x: 13, y: 63)],
                             back: CGPoint(x: 59, y: -14),
                             cancel: CGPoint(x: 54, y: 122))
    ]
}
