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
    private func validRuns(radius r: CGFloat) -> [(lo: Double, hi: Double)] {
        var runs: [(lo: Double, hi: Double)] = []
        var runStart: Double? = nil
        var deg = -260.0
        while deg <= 80 {
            let a = deg * .pi / 180
            let p = CGPoint(x: anchor.x + r * cos(a), y: anchor.y + r * sin(a))
            let ok = p.x >= 22 && p.x <= bounds.width - 22 &&
                     p.y >= 16 && p.y <= bounds.height - 18
            if ok, runStart == nil { runStart = deg }
            if !ok, let s = runStart { runs.append((s, deg - 3)); runStart = nil }
            deg += 3
        }
        if let s = runStart { runs.append((s, 80)) }
        return runs
    }

    /// Choose arcStart/arcEnd/radius for `count` bubbles: enough angular
    /// spacing for the minimum chord, centered on the preferred direction.
    /// Prefers the nearest window that actually FITS the whole span (a tiny
    /// sliver next to the preferred direction must never beat a roomy window
    /// further away); radius grows until one fits, then the widest window
    /// takes the squeeze.
    public mutating func fit(count: Int, preferredCenter: Double?, startRadius: CGFloat) {
        let want = preferredCenter ?? -90

        func place(_ run: (lo: Double, hi: Double), span: Double, r: CGFloat) {
            let half = min(span, run.hi - run.lo) / 2
            let center = min(max(want, run.lo + half), run.hi - half)
            radius = r
            arcStart = center - half
            arcEnd = center + half
        }

        // Radii to try: grow from the start ring, then shrink below it.
        var candidates: [CGFloat] = []
        var g = startRadius
        while g <= Self.maxRadius { candidates.append(g); g += 12 }
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
        let deg = angle(forIndex: i, count: count)
        let a = deg * .pi / 180
        let bubble = position(forIndex: i, count: count)
        let others = (0..<count).filter { $0 != i }
            .map { position(forIndex: $0, count: count) }
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
        let r = radius + 30
        let p = CGPoint(x: anchor.x + r * cos(a), y: anchor.y + r * sin(a))
        // Off the top edge → fall back to stacking.
        if p.y < 14 { return stacked() }
        return p
    }
}
