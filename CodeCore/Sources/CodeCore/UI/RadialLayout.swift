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

// MARK: - Canonical top-arc fan layout (Sebastian, 2026-08-22)

/// EVERY fan — root or nested — blooms into the same shallow arc across the
/// top of the live screen. Fixed geometry is the whole point: the wearer
/// builds muscle memory for "second slot from the left" no matter which
/// anchor they held, and nothing ever opens under the finger. (Left wrist,
/// right index finger ⇒ the lower-right quadrant is permanently occluded,
/// which is where the old per-fan hand-placed layouts kept putting leaves.)
///
/// Replaces `FanLayoutOverrides` as the live layout source. That table is
/// kept only as the record of the 2026-07 hand placement.
public enum TopArcLayout {

    /// Bubble Ø44 + air. Buttons are not what sets this — LABELS are. A
    /// centre label like "SUBSEQUENT · 40 J" is far wider than its own
    /// button and reaches into the ones either side, so the pitch has to
    /// clear the widest caption, not the widest button. 44 → 56 → 60.
    public static let slotPitch: CGFloat = 60
    /// First row's center y, in fan space (the live GeometryReader).
    public static let apexY: CGFloat = 24
    /// Second row clears the first row's LABELS, not just its buttons.
    ///
    /// The floor is d/2 + labelGap + labelHeight + d/2 = 22 + 4 + 13.5 + 22 =
    /// 61.5 at Ø44 — but `rowGap` is centre-to-centre BEFORE the arc drop,
    /// and the drop is not equal on both rows. On a 3 + 2 fan the outer top
    /// slot falls 6.1 pt while the row below it falls only 1.5, so the real
    /// vertical gap is ~4.6 pt tighter than this number. 66 cleared by 0.1 pt
    /// — arithmetically "fine", visually touching. 72 clears by ~6.
    ///
    /// It was 52 (sized for Ø38 with the label tucked closer), which put
    /// "INTUBATION" straight through the top of the button below it.
    public static let rowGap: CGFloat = 66
    /// The arc's ends drop this far below its center — the "slight curve".
    /// Was 13. At Ø44 the drop is charged twice: it pushes the outer buttons
    /// down AND drags their labels with them, which is what made a 3 + 2 fan
    /// collide no matter how far the rows were pushed apart. 6 keeps a
    /// visible curve while giving the vertical budget back.
    public static let arcDrop: CGFloat = 6
    /// Bubble centers never come closer than this to a side edge.
    public static let sideInset: CGFloat = 24
    /// Above this count a fan needs a second row.
    ///
    /// Three, not four, since the Ø44 buttons: four across at a 50 pt pitch
    /// spans 150 + 44 = 194 pt, which is the fan box EXACTLY — no margin at
    /// either end. Four-item fans now open 2 + 2.
    public static let maxPerRow = 3
    /// Gap from the bubble's bottom EDGE to the top of the label box
    /// (Sebastian, 2026-08-29). Superseded the old fixed centre-to-centre
    /// drop, which drifted as soon as buttons changed size.
    public static let labelGap: CGFloat = 4
    /// A one-line label at 8.5 pt: 10.5 pt of glyphs + 1.5 pt padding each
    /// side, measured off the running app. Wrapped labels are taller, so the
    /// Bench measures the real node and only the seed uses this.
    public static let labelBoxHeight: CGFloat = 13.5

    /// How many items ride the top row: balanced across two rows so neither
    /// looks stranded (6 → 3+3, 5 → 3+2).
    public static func topRowCount(_ count: Int) -> Int {
        count <= maxPerRow ? count : Int(ceil(Double(count) / 2))
    }

    /// Bubble centers for `count` items, in fan-space points, index order
    /// left-to-right then top-to-bottom.
    public static func positions(count: Int, bounds: CGSize) -> [CGPoint] {
        guard count > 0 else { return [] }
        let centerX = bounds.width / 2
        let halfSpan = max(1, bounds.width / 2 - sideInset)

        func row(_ n: Int, y: CGFloat) -> [CGPoint] {
            guard n > 0 else { return [] }
            // Fixed pitch, centered — NOT stretched to the full width, so a
            // 2-item fan and a 4-item fan share the same slot spacing.
            let pitch = min(slotPitch, (bounds.width - 2 * sideInset) / CGFloat(max(1, n - 1)))
            let startX = centerX - pitch * CGFloat(n - 1) / 2
            return (0..<n).map { i in
                let x = startX + pitch * CGFloat(i)
                let t = (x - centerX) / halfSpan          // −1…1
                return CGPoint(x: x, y: y + arcDrop * t * t)
            }
        }

        let top = topRowCount(count)
        return row(top, y: apexY) + row(count - top, y: apexY + rowGap)
    }

    /// Label centre for a bubble — always straight below it and sharing its
    /// x, so a label can never cover a neighbour and always reads as
    /// belonging to its own button.
    ///
    /// Measured from the bubble's EDGE, not its centre: `labelGap` is the
    /// visible whitespace, which is what stays constant when a button is
    /// resized.
    public static func labelPosition(for p: CGPoint,
                                     diameter: CGFloat = 44,
                                     labelHeight: CGFloat = labelBoxHeight) -> CGPoint {
        CGPoint(x: p.x, y: p.y + diameter / 2 + labelGap + labelHeight / 2)
    }

    // The three anchor pucks sit along the bottom at roughly x = 0.15w,
    // 0.5w and 0.85w. The exit pads drop into the GAPS between them rather
    // than on top of one — stacking ✕ over the meds puck made the two read
    // as one control.
    // Exit pads flank the arc on the SIDE band. The bottom is unusable: the
    // three Ø42 anchor pucks leave only ~34 pt of gap between them, which is
    // not enough for a Ø34 pad — ✕ drawn there lands on the meds puck, and
    // the two read as one control. The side band at y ≈ h−77 is the only
    // place clear of both the pucks below and the arc's second row above.
    // RETIRED 2026-08-29. The pads no longer live in fan space at all —
    // Sebastian put Back in the screen's top-left corner, which is ABOVE this
    // box entirely (fan y −19). They are now shared screen-point constants on
    // `FanLayout.Pads`, drawn in the chrome layer. See the note there.
}
