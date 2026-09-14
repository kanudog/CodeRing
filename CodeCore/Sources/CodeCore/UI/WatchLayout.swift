// WatchLayout.swift — Sebastian's hand-placed live-session layout,
// exported from the Layout Bench on 2026-08-24.
//
// Every value is in SCREEN points on the 45 mm Series 9 (198 × 242). The
// live screen is positioned absolutely from these constants rather than
// stacked: stacking is what kept re-centring the column and shifting the
// header row whenever a sibling appeared or disappeared.
//
// The radial menus keep their own space (the 194 × 191 GeometryReader inset
// by `liveInset`) so the top-arc fans are unaffected by anything here —
// convert with `toLive(_:)` when placing something in that layer.

import Foundation
import CoreGraphics

public enum WatchLayout {

    public static let screen = CGSize(width: 198, height: 242)

    /// Offset of the live GeometryReader from the screen origin,
    /// probe-measured on the 45 mm sim.
    public static let liveInset = CGPoint(x: 2, y: 51)

    /// Screen point → radial-menu (live) space.
    public static func toLive(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x - liveInset.x, y: p.y - liveInset.y)
    }

    /// A circular control: filled disc with a centred glyph.
    public struct Disc: Sendable {
        public let center: CGPoint
        public let diameter: CGFloat
        public let glyph: CGFloat
        public init(_ x: CGFloat, _ y: CGFloat, d: CGFloat, glyph: CGFloat) {
            self.center = CGPoint(x: x, y: y); self.diameter = d; self.glyph = glyph
        }
    }

    /// A text run. `size` is the box it occupies — text scales down inside it
    /// rather than pushing its neighbours around.
    public struct Label: Sendable {
        public let center: CGPoint
        public let size: CGSize
        public let font: CGFloat
        public init(_ x: CGFloat, _ y: CGFloat, w: CGFloat, h: CGFloat, font: CGFloat) {
            self.center = CGPoint(x: x, y: y); self.size = CGSize(width: w, height: h); self.font = font
        }
    }

    public struct Ring: Sendable {
        public let center: CGPoint
        public let diameter: CGFloat
        public let stroke: CGFloat
        public init(_ x: CGFloat, _ y: CGFloat, d: CGFloat, stroke: CGFloat) {
            self.center = CGPoint(x: x, y: y); self.diameter = d; self.stroke = stroke
        }
    }

    /// A med timer chip, anchored TOP-LEFT (not centred) because the column
    /// grid it came from is top-aligned.
    public struct Chip: Sendable {
        public let origin: CGPoint
        public let size: CGSize
        public let trailing: Bool
        /// Per-chip: the top and bottom rows are sized individually.
        public let nameFont: CGFloat
        public init(_ x: CGFloat, _ y: CGFloat, w: CGFloat = 52, h: CGFloat = 27,
                    trailing: Bool = false, nameFont: CGFloat = 7) {
            self.origin = CGPoint(x: x, y: y); self.size = CGSize(width: w, height: h)
            self.trailing = trailing; self.nameFont = nameFont
        }
    }

    // MARK: - Header controls

    public static let logButton    = Disc(29,  24, d: 34, glyph: 26)
    public static let timersButton = Disc(71,  23, d: 34, glyph: 26)
    public static let pauseButton  = Disc(99, 163, d: 34, glyph: 20)
    public static let muteButton   = Disc(113, 23, d: 34, glyph: 26)
    public static let flagButton   = Disc(174, 55, d: 34, glyph: 26)

    // MARK: - Clocks and patient strip

    public static let totalLabel = Label(77.5, 229, w: 59,  h: 10,   font: 12)
    public static let codeClock  = Label(120, 229, w: 56,   h: 13.5, font: 16)
    public static let cycleChip  = Label(99,  98,  w: 37.5, h: 11,   font: 9)

    /// Patient strip — centred in the band between the ring's bottom edge
    /// (175) and the events puck's top (196). The wall clock that used to
    /// sit here was removed 2026-08-28: it crowded the space and the code
    /// clock already carries the time that matters.
    public static let patient    = Label(99,  48,  w: 110, h: 14, font: 9)
    /// Drawn inline after the patient text so the pair stays centred as a
    /// unit — a fixed x would drift away from text of a different width.
    public static let editPencilGlyph: CGFloat = 9

    // MARK: - Rings and their centre stack

    /// VISUAL extent is stroke/2 larger each way than `diameter` — the
    /// stroke straddles the path. At Ø94 + 8 that is 70 → 172, so space
    /// things against ±51 from the centre, not ±47.
    /// (The 67 → 175 figure in the older notes was for the Ø100 ring this
    /// replaced; it is 4 pt too generous for the ring that actually ships.)
    public static let cprRing  = Ring(99, 121, d: 94, stroke: 8)
    public static let drugRing = Ring(99, 121, d: 80,  stroke: 5)

    /// Before compressions.
    public static let tapGlyph  = Disc(99.2, 114.5, d: 13.5, glyph: 13.5)
    public static let startText = Label(99, 131, w: 90, h: 10, font: 12)

    /// Running. Fixed in both the plain and drug-running states — the old
    /// layout re-centred this block when the drug line appeared.
    ///
    /// Sits in the band between the TOTAL row's bottom (55.7) and the ring's
    /// VISUAL top — 70 at today's Ø94, not the 74 its frame suggests:
    /// `Circle().stroke` centres the 8 pt line on the path, so the ring
    /// reaches 4 pt beyond its frame. At y 64 the label overlapped it.
    public static let pulseLabel = Label(99, 59.5, w: 138, h: 11, font: 10)
    public static let countdown  = Label(99, 121, w: 53.5, h: 30,   font: 25)
    public static let drugLine   = Label(99, 139, w: 37.5, h: 12,   font: 10)

    /// Transient confirmation / "nothing logged" toast. Inside the ring,
    /// below the drug line (ends 145) and above the bottom stroke (starts
    /// 167) — it used to sit at screen-height − 76, which put it straight
    /// across the ring's stroke once the ring moved to y 121.
    public static let toast = Label(99, 156, w: 150, h: 16, font: 11)

    /// Paused banner — dead centre of the CPR ring, per Sebastian
    /// (2026-08-24). It used to float in the middle of the stack instead.
    public static let pausedText = Label(cprRing.center.x, cprRing.center.y,
                                         w: 92, h: 24, font: 15)

    // MARK: - Post-ROSC
    //
    // Shared elements (header, patient strip, clocks, pucks, med chips) hold
    // the SAME positions here as every other state — only the centre stack
    // changes and two extra controls appear. RE-ARREST and HANDOFF take the
    // slots the pause button and shock bolt vacate after ROSC.

    /// Same slot and size as the CPR ring, so the ring never appears to jump
    /// when the outcome changes.
    public static let vitalsRing = Ring(99, 121, d: 94, stroke: 8)

    /// Mirrors `pulseLabel` — same slot, same size.
    public static let vitalsLabel = Label(99, 59.5, w: 138, h: 11, font: 10)
    /// Mirrors `countdown`.
    public static let vitalsCount = Label(99, 121, w: 53.5, h: 30, font: 25)
    /// Time since ROSC. Takes the cycle chip's slot, which is free post-ROSC.
    public static let roscElapsed = Label(99, 98, w: 76, h: 11, font: 10)
    /// "TAP — VITALS" prompt, shown only when a check is due.
    public static let vitalsPrompt = Label(99, 150, w: 76, h: 14, font: 8)
    /// Fallback when the protocol carries no vitals cadence.
    public static let roscHeart = Disc(99, 121, d: 22, glyph: 22)

    /// Stacked down the right, clear of the ring at every y they occupy.
    public static let reArrest = Label(170, 85,  w: 52, h: 22, font: 9)
    public static let handoff  = Label(170, 110, w: 52, h: 22, font: 9)

    // MARK: - Med timer chips

    /// Slots 0–3 are the primary column, 4–5 the overflow. Hand-placed, so
    /// the row pitch is no longer perfectly uniform — that is intentional.
    public static let chips: [Chip] = [
        Chip(12,  67,  nameFont: 8), Chip(6, 94), Chip(6, 121), Chip(12, 148),
        Chip(134, 148, trailing: true, nameFont: 8),
        Chip(144, 121, trailing: true, nameFont: 8)
    ]
    public static let chipCountFont: CGFloat = 6.5
    public static let chipTimerFont: CGFloat = 9.5

    // MARK: - Anchor pucks (rendered in the radial layer — use toLive)

    public static let medsPuck   = Disc(30,  210, d: 42, glyph: 26)
    public static let eventsPuck = Disc(74,  196, d: 42, glyph: 26)
    public static let fluidsPuck = Disc(170, 210, d: 42, glyph: 26)
    public static let shockPuck  = Disc(124, 196, d: 42, glyph: 26)

    /// watchOS draws its own clock here and offers no way to hide it.
    public static let systemClock = CGRect(x: 143.5, y: 17.5, width: 39.5, height: 11)
}
