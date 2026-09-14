// FanLayout.swift — hand-placeable geometry for the radial submenus.
//
// `WatchLayout` does this job for the live SCREEN; this file does it for the
// fans that bloom out of the anchor pucks. Same bargain: the Layout Bench
// exports literal numbers, this table holds them, and the views read the
// table instead of computing an arrangement.
//
// Coordinates are in FAN space — the 194 × 191 GeometryReader the radial
// layer lives in, inset (2, 51) from the screen. That is deliberately NOT
// the screen space `WatchLayout` uses; converting between them is
// `WatchLayout.toLive(_:)`. Keep them apart, or every fan moves.
//
// A fan that has not been hand-placed is written `.arc(n)`: the canonical
// `TopArcLayout` arrangement for n items, built at load. So an untouched
// table produces byte-identical geometry to the top-arc code it replaced —
// `FanLayoutTests.testSeededFansStillMatchTheTopArc` asserts exactly that. Placing a fan by hand swaps its
// `.arc(n)` for a literal `Fan(...)` and nothing else in the app changes.

import Foundation
import CoreGraphics

public enum FanLayout {

    /// The radial layer's box on the 45 mm Series 9, probe-measured.
    /// Every coordinate below is relative to this, not to the screen.
    public static let bounds = CGSize(width: 194, height: 191)

    // Baseline verified against the running app on 2026-08-29 by
    // `testWQ_dumpFanFrames` (Tools/SyncDriver), which opens ten fans across
    // all three depths and prints the accessibility frames. Every bubble,
    // label and pad matched the values `arc(_:)` computes here to within
    // XCUITest's 0.5 pt frame rounding. Two details that only a dump shows:
    //   • Bubbles are Ø38 and pads Ø44 — the pads really are the bigger
    //     target, and the Back pad exists only at depth ≥ 2.
    //   • At four per row the outer bubbles sit at x 31 / 163 but their
    //     labels render at x 32 / 162, because the overlay clamps labels to
    //     a narrower band than bubbles. `clampLabel` reproduces that.

    // MARK: - Pieces

    /// One item bubble plus the label that hangs off it. The label carries an
    /// ABSOLUTE centre rather than an offset so it can be dragged out from
    /// under a crowded neighbour without dragging the bubble with it.
    public struct Slot: Sendable, Equatable {
        public let center: CGPoint
        public let diameter: CGFloat
        /// Point size of the SF Symbol (or the `text:` abbreviation) inside.
        public let glyph: CGFloat
        public let label: CGPoint
        public let labelFont: CGFloat
        /// Wrap width for the label; it wraps to two lines rather than shrink.
        public let labelWidth: CGFloat
        /// Draw order within the fan, low to high. Ties keep index order.
        public let z: Int

        public init(_ x: CGFloat, _ y: CGFloat,
                    d: CGFloat = 44, glyph: CGFloat = 25,
                    label: CGPoint, labelFont: CGFloat = 8.5,
                    labelWidth: CGFloat = 74, z: Int = 0) {
            self.center = CGPoint(x: x, y: y); self.diameter = d; self.glyph = glyph
            self.label = label; self.labelFont = labelFont
            self.labelWidth = labelWidth; self.z = z
        }
    }

    /// Back / ✕. Sized separately from the item bubbles because they are
    /// reached blind — muscle memory, not aim — so they run larger.
    public struct Pad: Sendable, Equatable {
        /// SCREEN points — see `Pads`. The one piece of fan chrome that is
        /// deliberately NOT in fan space.
        public let center: CGPoint
        public let diameter: CGFloat
        public let glyph: CGFloat
        public init(_ x: CGFloat, _ y: CGFloat, d: CGFloat = 44, glyph: CGFloat = 25) {
            self.center = CGPoint(x: x, y: y); self.diameter = d; self.glyph = glyph
        }
    }

    /// The two exit pads, shared by EVERY fan at every depth and fixed in
    /// SCREEN points (Sebastian, 2026-08-29: "the cancel button is always
    /// going to be in the exact same place ... back will always be in the top
    /// left corner"). One fixed reach, learned once, never re-learned.
    ///
    /// Screen space, not fan space, because Back at (32, 32) is nineteen
    /// points ABOVE the radial layer's box — in fan coordinates it would be
    /// y −19. Rendered inside that GeometryReader it would fall outside the
    /// parent's bounds and simply never receive a touch. So the pads are
    /// drawn in the chrome layer instead, over the scrim; only the hold-drag
    /// hover test converts back into fan space, via `WatchLayout.toLive`.
    public enum Pads {
        public static let cancel = Pad(99, 200)
        public static let back   = Pad(32, 32)
        /// Radius the finger has to come within for the hold-drag hover.
        public static let hoverRadius: CGFloat = 26
    }

    /// The hovered-item readout chip.
    ///
    /// SCREEN points, like the pads and for the same reason: Sebastian put it
    /// at y 25 in ten of the fourteen fans, which is fan-space y −26, above
    /// the radial layer entirely. It is drawn in the chrome layer.
    ///
    /// `followAnchor` keeps the seed honest: unplaced fans put the chip on
    /// the side away from the puck that opened them (x 110 for a left-hand
    /// puck, 90 for a right-hand one), which is a property of the ANCHOR,
    /// not of the fan — one key can be opened from either side. Placing a
    /// fan by hand pins the x instead, because at that point the position is
    /// a decision rather than a rule.
    public struct Readout: Sendable, Equatable {
        public let center: CGPoint
        public let font: CGFloat
        public let crumbFont: CGFloat
        public let followAnchor: Bool
        public init(_ x: CGFloat, _ y: CGFloat, font: CGFloat = 16,
                    crumbFont: CGFloat = 9, followAnchor: Bool = false) {
            self.center = CGPoint(x: x, y: y); self.font = font
            self.crumbFont = crumbFont; self.followAnchor = followAnchor
        }
    }

    public struct Fan: Sendable, Equatable {
        public let slots: [Slot]
        /// nil = no chip in this fan. Sebastian removed it from Meds and
        /// Fluids, where five buttons already fill the screen and the caption
        /// under each one says what the chip would have said.
        public let readout: Readout?
        /// False while the fan still sits on its `.arc(n)` seed. Only the
        /// seeded ones are held to "must equal TopArcLayout" by the tests.
        public let placed: Bool

        // The exit pads used to live here, one copy per fan. They are shared
        // constants now (`Pads`) — there was never a reason for Back to sit
        // somewhere different depending on which menu you were in, and having
        // fourteen copies meant fourteen places to keep in sync.
        public init(slots: [Slot], readout: Readout?, placed: Bool = true) {
            self.slots = slots; self.readout = readout; self.placed = placed
        }

        /// The canonical top-arc arrangement for `count` items. This is what
        /// every fan used before the table existed, so it is both the seed
        /// and the fallback — and writing it as `.arc(n)` in the table keeps
        /// an unplaced fan to one self-documenting line.
        ///
        /// The label x is clamped to the same [32, width − 32] band the
        /// overlay applies — at four per row the outer bubbles sit at x 31
        /// and 163, so their labels really do render 1 pt inboard of their
        /// own bubble. The frame dump confirms it; reproducing it here is
        /// what lets the Bench draw the truth rather than the intent.
        public static func arc(_ count: Int) -> Fan {
            let pts = TopArcLayout.positions(count: count, bounds: bounds)
            let slots = pts.enumerated().map { i, p -> Slot in
                let b = clampBubble(p)
                let l = clampLabel(TopArcLayout.labelPosition(for: b))
                return Slot(b.x, b.y, label: l, z: i)
            }
            return Fan(slots: slots, readout: readoutSeed(for: pts), placed: false)
        }
    }

    // MARK: - Geometry helpers

    /// `RadialMenuModel` clamped every computed slot into the screen before
    /// drawing it; the table has to bake that in or a hand-placed fan and a
    /// seeded one would not be measured the same way.
    public static func clampBubble(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 18), bounds.width - 18),
                y: min(max(p.y, 16), bounds.height - 16))
    }

    /// The overlay's own label clamp — narrower than the bubble clamp
    /// because a label is wider than the bubble it belongs to.
    public static func clampLabel(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 32), bounds.width - 32), y: max(10, p.y))
    }

    /// Readout chip: top by default, bottom when the arc reaches up into the
    /// band it would occupy — the view's old `readoutAtBottom` rule.
    ///
    /// Under the top arc the highest bubble is always y 26–36.6, so this
    /// always resolves to the bottom; the frame dump confirms the chip at
    /// y 175 in every one of the ten fans measured. The branch is kept for
    /// the case a fan is hand-placed low on the screen.
    fileprivate static func readoutSeed(for pts: [CGPoint]) -> Readout {
        let highest = pts.map(\.y).min() ?? 999
        // SCREEN points now — the chip moved out of the fan layer with the
        // pads, because Sebastian placed it at y 25 (fan-space −26).
        let y = (highest < 78 ? bounds.height - 16 : 24) + WatchLayout.liveInset.y
        return Readout(110 + WatchLayout.liveInset.x, y, followAnchor: true)
    }

    // MARK: - Lookup

    /// Geometry for the fan `key` showing `count` items, or nil to let the
    /// caller fall back to the computed arc.
    ///
    /// The count must match EXACTLY. Several fans are built at runtime —
    /// defib rungs come off the dose ladder, and the events fan grows by
    /// however many custom events the phone has pushed — so a table entry
    /// sized for six items must not be stretched over seven. A surprise
    /// count gets the auto arc, which is guaranteed on-screen.
    public static func fan(_ key: String, count: Int) -> Fan? {
        guard let f = table[key], f.slots.count == count else { return nil }
        return f
    }

    /// The backdrop while a fan is open.
    ///
    /// `.ultraThinMaterial` was the obvious way to do this and it does NOT
    /// work on watchOS: the buttons stayed in the accessibility tree but the
    /// entire overlay — scrim, bubbles, labels — rendered as nothing. So the
    /// blur is applied to the content BEHIND instead, and the scrim is a
    /// plain two-layer wash: dim it down, then lift it off black so the dark
    /// bubbles have something to read against.
    public enum Backdrop {
        public static let blurRadius: CGFloat = 7
        public static let dim: Double = 0.38          // was a flat black 0.62
        public static let tint: Double = 0.14
    }

    /// What the readout chip calls each fan. Root fans take the anchor's own
    /// name; nested fans take the parent item's. The chip is a "where am I",
    /// not a "what am I about to do" — Sebastian, 2026-08-29.
    public static let fanTitle: [String: String] = [
        "code": "Meds", "shock": "Shock", "support": "Fluids",
        "events": "Events", "events.rosc": "Events",
        "grp:defib": "Defib", "grp:fluids": "Fluids", "grp:more": "More",
        "grp:access": "Access", "grp:airway": "Airway", "grp:comms": "Comms",
        "grp:temp": "Temp", "grp:call": "Call", "grp:arrival": "Arrived"
    ]

    /// The item titles each fan renders, in slot order. Kept beside the table
    /// because the geometry is only correct in relation to the WORDS: a label
    /// is as wide as its text, and a wide one on a middle slot reaches into
    /// the buttons either side. `testLabelsNeverCoverAnotherButton` uses these
    /// to model that; the live titles still come from LiveSessionView.
    ///
    /// Dose rungs are shown at a 10 kg patient — the widest common case for
    /// the defib ladder, which is the point of listing them here.
    public static let titles: [String: [String]] = [
        "code":        ["Epinephrine", "Atropine", "Adenosine", "Amiodarone", "Lidocaine"],
        "shock":       ["Defib", "Cardiovert"],
        "support":     ["More", "Bicarb", "Calcium", "Dextrose", "Fluids"],
        "events":      ["Rhythm", "Access", "Airway", "Comms", "Temp", "ROSC"],
        "events.rosc": ["Rhythm", "12-lead", "Drip", "Blood", "Temp"],
        "grp:defib":   ["1st 20 J", "Next 40 J", "Max 100 J"],
        "grp:fluids":  ["Blood", "10 mL/kg", "20 mL/kg"],
        "grp:more":    ["Drip", "Magnesium", "Naloxone"],
        "grp:access":  ["IV", "IO", "Art line"],
        "grp:airway":  ["Intubation", "Bag", "Mask", "Trach"],
        "grp:comms":   ["Call", "Arrival"],
        "grp:temp":    ["Bair Hugger", "Arctic Sun", "Warm blankets"],
        "grp:call":    ["Surgery", "Anesthesia", "ECMO", "Consult"],
        "grp:arrival": ["Surgery", "Anesthesia", "ECMO", "Consult"]
    ]

    /// Every fan the live screen can open, with the item count it renders at.
    /// Counts verified against `DoseCalculator` on 2026-08-29 — the defib
    /// ladder is three rungs at every weight, and the fluid ladder two.
    ///
    /// Keys: root fans use the anchor id, nested fans the parent item id.
    /// `events` and `events.rosc` are separate because the same puck opens a
    /// different set once ROSC is achieved.
    /// Sebastian's hand placement, 2026-08-29, exported from the Layout
    /// Bench. FAN-space points for the slots; the readout is SCREEN points.
    ///
    /// Nothing here is computed any more — every fan is placed, so `.arc(n)`
    /// survives only as the fallback for a count the table does not cover
    /// (a phone-authored custom event growing the Events fan, say).
    public static let table: [String: Fan] = [
        // Meds puck
        "code": Fan(
          slots: [
            Slot(32, 31, label: CGPoint(x: 32, y: 62.68)),   // Epinephrine
            Slot(97, 24, label: CGPoint(x: 97, y: 56.75)),   // Atropine
            Slot(162, 31, label: CGPoint(x: 162, y: 62.68)),   // Adenosine
            Slot(69, 91, label: CGPoint(x: 69, y: 122.68)),   // Amiodarone
            Slot(125, 91, label: CGPoint(x: 125, y: 122.68)),   // Lidocaine
          ],
          readout: Readout(99, 25)),

        // Shock bolt
        "shock": Fan(
          slots: [
            Slot(69, 24.88, label: CGPoint(x: 69, y: 57.63)),   // Defib
            Slot(125, 24.88, label: CGPoint(x: 125, y: 57.63)),   // Cardiovert
          ],
          readout: Readout(99, 25)),

        // Shock ▸ Defib
        "grp:defib": Fan(
          slots: [
            Slot(35, 67, label: CGPoint(x: 35, y: 98.68)),   // 1st 20 J
            Slot(97, 35, label: CGPoint(x: 97, y: 71.45)),   // Next 40 J
            Slot(161, 67, label: CGPoint(x: 161, y: 103.45)),   // Max 100 J
          ],
          readout: Readout(99, 25)),

        // Fluids puck — built Fluids-first then reversed
        "support": Fan(
          slots: [
            Slot(125, 91, label: CGPoint(x: 125, y: 122.68)),   // More
            Slot(97, 24, label: CGPoint(x: 97, y: 56.75)),   // Bicarb
            Slot(162, 31, label: CGPoint(x: 162, y: 62.68)),   // Calcium
            Slot(69, 91, label: CGPoint(x: 69, y: 122.68)),   // Dextrose
            Slot(32, 31, label: CGPoint(x: 32, y: 62.68)),   // Fluids
          ],
          readout: Readout(99, 25)),

        // Fluids ▸ Fluids
        "grp:fluids": Fan(
          slots: [
            Slot(35, 67, label: CGPoint(x: 35, y: 98.68)),   // Blood
            Slot(97, 35, label: CGPoint(x: 97, y: 66.68)),   // 10 mL/kg
            Slot(161, 67, label: CGPoint(x: 161, y: 103.45)),   // 20 mL/kg
          ],
          readout: Readout(99, 25)),

        // Fluids ▸ More
        "grp:more": Fan(
          slots: [
            Slot(35, 67, label: CGPoint(x: 35, y: 98.68)),   // Drip
            Slot(97, 24, label: CGPoint(x: 97, y: 56.75)),   // Magnesium
            Slot(161, 67, label: CGPoint(x: 161, y: 98.68)),   // Naloxone
          ],
          readout: Readout(99, 25)),

        // Events puck
        "events": Fan(
          slots: [
            Slot(41, 27.53, label: CGPoint(x: 41, y: 60.28)),   // Rhythm
            Slot(97, 24, label: CGPoint(x: 97, y: 56.75)),   // Access
            Slot(153, 27.53, label: CGPoint(x: 153, y: 60.28)),   // Airway
            Slot(41, 93.53, label: CGPoint(x: 41, y: 126.28)),   // Comms
            Slot(97, 90, label: CGPoint(x: 97, y: 122.75)),   // Temp
            Slot(153, 93.53, label: CGPoint(x: 153, y: 126.28)),   // ROSC
          ],
          readout: Readout(99, 25)),

        // Events ▸ Access
        "grp:access": Fan(
          slots: [
            Slot(35, 67, label: CGPoint(x: 35, y: 98.68)),   // IV
            Slot(97, 35, label: CGPoint(x: 97, y: 66.68)),   // IO
            Slot(161, 67, label: CGPoint(x: 161, y: 103.45)),   // Art line
          ],
          readout: Readout(99, 25)),

        // Events ▸ Airway
        "grp:airway": Fan(
          slots: [
            Slot(69, 35, label: CGPoint(x: 69, y: 66.68)),   // Intubation
            Slot(125, 35, label: CGPoint(x: 125, y: 66.68)),   // Bag
            Slot(35, 97, label: CGPoint(x: 35, y: 128.68)),   // Mask
            Slot(159, 97, label: CGPoint(x: 159, y: 128.68)),   // Trach
          ],
          readout: Readout(99, 25)),

        // Events ▸ Comms
        "grp:comms": Fan(
          slots: [
            Slot(50, 45, label: CGPoint(x: 50, y: 76.68)),   // Call
            Slot(144, 45, label: CGPoint(x: 144, y: 76.68)),   // Arrived
          ],
          readout: Readout(99, 25)),

        // Events ▸ Comms ▸ Call
        "grp:call": Fan(
          slots: [
            Slot(66, 35, label: CGPoint(x: 66, y: 66.68)),   // Surgery
            Slot(128, 35, label: CGPoint(x: 128, y: 66.68)),   // Anesthesia
            Slot(32, 97, label: CGPoint(x: 32, y: 128.68)),   // ECMO
            Slot(159, 97, label: CGPoint(x: 159, y: 128.68)),   // Consult
          ],
          readout: Readout(99, 25)),

        // Events ▸ Comms ▸ Arrival
        "grp:arrival": Fan(
          slots: [
            Slot(66, 35, label: CGPoint(x: 66, y: 66.68)),   // Surgery
            Slot(125, 35, label: CGPoint(x: 125, y: 66.68)),   // Anesthesia
            Slot(32, 97, label: CGPoint(x: 32, y: 128.68)),   // ECMO
            Slot(159, 97, label: CGPoint(x: 159, y: 128.68)),   // Consult
          ],
          readout: Readout(99, 25)),

        // Events ▸ Temp — reached from the arrest fan AND post-ROSC
        "grp:temp": Fan(
          slots: [
            Slot(97, 35, label: CGPoint(x: 97, y: 66.68)),   // Bair Hugger
            Slot(35, 67, label: CGPoint(x: 35, y: 98.68)),   // Arctic Sun
            Slot(161, 67, label: CGPoint(x: 161, y: 103.45)),   // Warm blankets
          ],
          readout: Readout(99, 25)),

        // Events puck, post-ROSC
        "events.rosc": Fan(
          slots: [
            Slot(32, 31, label: CGPoint(x: 32, y: 62.68)),   // Pulse
            Slot(97, 24, label: CGPoint(x: 97, y: 56.75)),   // 12-lead
            Slot(162, 31, label: CGPoint(x: 162, y: 62.68)),   // Drip
            Slot(69, 91, label: CGPoint(x: 69, y: 122.68)),   // Blood
            Slot(125, 90.88, label: CGPoint(x: 125, y: 123.63)),   // Temp
          ],
          readout: Readout(99, 25)),
    ]

}
