// RadialMenu.swift — the signature interaction of CodeRing.
//
// Anchor pucks sit on the screen perimeter. Two ways in:
//   HOLD (0.15s) → fan of items blooms, every bubble labeled. Slide through —
//   release ON a leaf to select it. Nothing else ever logs: parents only
//   expand, and lifting anywhere that isn't a leaf cancels.
//   Hovering a parent ~1 s expands it, with a haptic RAMP (light pulse →
//   firmer pulse → pop). Expansion CASCADES: the tapped item's position
//   becomes the center of the next fan, so the finger never lifts and every
//   deeper option stays within easy reach (geometry: CodeCore/RadialLayout,
//   unit-tested).
//   A chevron pad marks the previous fan's center — drag back onto it to pop
//   one level. The ✕ at the origin puck bails out entirely.
//   TAP → same fans in tap mode; items become buttons; tap outside closes.
//
// One RadialMenuModel per screen; every anchor drives the same overlay.

import SwiftUI
import WatchKit
import CodeCore

struct RadialItem: Identifiable, Equatable {
    let id: String
    let title: String
    /// SF Symbol name, or "text:XX" to render the string itself as the icon
    /// (element abbreviations like Ca / Mg / HCO₃).
    let symbol: String
    let colorHex: String
    /// Overrides the ICON's color only (e.g. blood: blue bubble, red drop).
    var iconColorHex: String? = nil
    var children: [RadialItem]? = nil

    var color: Color { Color(hex: colorHex) }

    init(id: String, title: String, symbol: String, colorHex: String,
         iconColorHex: String? = nil, children: [RadialItem]? = nil) {
        self.id = id; self.title = title; self.symbol = symbol
        self.colorHex = colorHex; self.iconColorHex = iconColorHex
        self.children = children
    }

    static func == (a: RadialItem, b: RadialItem) -> Bool { a.id == b.id }
}

@MainActor
@Observable
final class RadialMenuModel {

    /// One expanded menu level, so Back can restore it — items, geometry,
    /// and the focus center that level was fanned around.
    private struct Level {
        let items: [RadialItem]
        let breadcrumb: String?
        let levelTitle: String
        let layout: RadialLayout
        let fixedPos: [Int: CGPoint]
        /// Hand-placed geometry for THAT level, or nil if it was on the
        /// computed arc. Popping has to restore sizes and label positions,
        /// not just centres.
        let fan: FanLayout.Fan?
    }

    var isOpen = false
    var tapMode = false
    /// When the menu opened — the anchor's TapGesture fires on release of
    /// the very hold that opened a tap-mode fan, and must not dismiss it.
    private var openedAt = Date.distantPast
    /// The ORIGINAL puck (cancel home at the root level).
    private(set) var rootAnchor: CGPoint = .zero
    var hoveredID: String? = nil
    var hoveringCancel = false         // finger over the ✕ pad
    var hoveringBack = false           // finger over the back chevron pad
    var breadcrumb: String? = nil      // the fan we came FROM, small line
    /// This fan's own name, the chip's big line: "MEDS" at the root, the
    /// parent item's title once nested ("EVENTS" over "Temp").
    private(set) var levelTitle: String = ""
    /// The two exit pads, in FAN space, converted from the shared screen
    /// constants. Computed rather than stored: they are the same two points
    /// for every fan at every depth, so there was nothing to remember.
    /// Back appears only when there IS a level to pop back to.
    var cancelPos: CGPoint { WatchLayout.toLive(FanLayout.Pads.cancel.center) }
    var backPos: CGPoint? {
        stack.isEmpty ? nil : WatchLayout.toLive(FanLayout.Pads.back.center)
    }
    /// Drives whether the chrome layer draws the Back pad at all.
    var canGoBack: Bool { !stack.isEmpty }

    private(set) var items: [RadialItem] = []
    /// Stamped when a fan closes without firing a leaf. Silence after a
    /// deliberate selection gesture is this app's most dangerous failure
    /// mode — the wearer believes an intervention was logged when it wasn't
    /// — so the live screen watches this and says so out loud.
    private(set) var missedAt: Date? = nil
    /// Hand-placed positions — beat the fitted arc.
    private var fixedPos: [Int: CGPoint] = [:]
    /// The CURRENT level's entry in `FanLayout.table`, when one exists for
    /// this key at this item count. nil ⇒ everything falls back to the
    /// computed top arc, which is what every fan did before the table.
    private(set) var fan: FanLayout.Fan? = nil
    /// Geometry for the CURRENT level. Its anchor is the "focus center":
    /// the root puck at level 0, then the tapped item's position at every
    /// deeper level — so the fan always grows around the finger.
    private var layout = RadialLayout(anchor: .zero, bounds: .zero)
    private var stack: [Level] = []
    private var lastLocation: CGPoint? = nil
    private var backHoverStart: Date = .distantPast
    /// Time-driven expansion: drag events stop for a motionless finger, so
    /// dwell must run on a clock, not on the next touch delta.
    private var dwellTask: Task<Void, Never>? = nil
    private var onSelect: ((RadialItem) -> Void)? = nil

    // MARK: - Lifecycle

    func open(anchor: CGPoint, radius: CGFloat, bounds: CGSize,
              items: [RadialItem], tapMode: Bool, key: String? = nil,
              onSelect: @escaping (RadialItem) -> Void) {
        self.rootAnchor = anchor
        self.layout = RadialLayout(anchor: anchor, bounds: bounds)
        self.layout.fit(count: items.count, preferredCenter: nil, startRadius: radius)
        self.items = items
        self.tapMode = tapMode
        self.onSelect = onSelect
        self.hoveredID = nil
        self.breadcrumb = nil
        self.levelTitle = key.flatMap { FanLayout.fanTitle[$0] } ?? ""
        self.stack = []
        self.lastLocation = nil
        // Hand-placed geometry first (FanLayout, keyed by the anchor id);
        // otherwise every fan blooms into the SAME top arc — fixed slots the
        // wearer can learn, clear of the occluded lower-right quadrant.
        self.fan = key.flatMap { FanLayout.fan($0, count: items.count) }
        self.fixedPos = slotCentres(count: items.count, bounds: bounds)
        self.openedAt = Date()
        self.isOpen = true
        WatchHaptics.play(.start)
    }

    /// Anchor tapped while a menu is open: dismiss — unless the menu opened
    /// under this very touch (in tap-only mode, releasing the hold that
    /// opened the fan also lands here as a tap).
    func closeUnlessJustOpened() {
        guard Date().timeIntervalSince(openedAt) > 0.6 else { return }
        close()
    }

    func close() {
        dwellTask?.cancel()
        dwellTask = nil
        isOpen = false
        items = []
        hoveredID = nil
        hoveringCancel = false
        hoveringBack = false
        breadcrumb = nil
        levelTitle = ""
        stack = []
        lastLocation = nil
        fixedPos = [:]
        fan = nil
        onSelect = nil
    }

    // MARK: - Geometry (delegated to CodeCore's unit-tested RadialLayout)

    /// Bubble centres for the level being opened: the hand-placed table when
    /// it has an entry at this exact count, the computed arc otherwise.
    private func slotCentres(count: Int, bounds: CGSize) -> [Int: CGPoint] {
        var out: [Int: CGPoint] = [:]
        if let fan {
            for (i, s) in fan.slots.enumerated() { out[i] = s.center }
            return out
        }
        for (i, p) in TopArcLayout.positions(count: count, bounds: bounds).enumerated() {
            out[i] = clampToScreen(p)
        }
        return out
    }

    /// Bounds-checked because `items` and `fan.slots` are matched on count at
    /// lookup time but the view re-renders during the close animation, when
    /// one has already emptied and the other has not.
    private func slot(_ i: Int) -> FanLayout.Slot? {
        guard let fan, fan.slots.indices.contains(i) else { return nil }
        return fan.slots[i]
    }

    /// Per-slot appearance. All five fall back to the values the overlay used
    /// to hard-code, so an unplaced fan renders exactly as it always did.
    func slotDiameter(_ i: Int) -> CGFloat { slot(i)?.diameter ?? 38 }
    func slotGlyph(_ i: Int) -> CGFloat { slot(i)?.glyph ?? 15 }
    func labelFont(_ i: Int) -> CGFloat { slot(i)?.labelFont ?? 8.5 }
    func labelWidth(_ i: Int) -> CGFloat { slot(i)?.labelWidth ?? 74 }
    func slotZ(_ i: Int) -> Int { slot(i)?.z ?? i }

    /// A seeded fan keeps the old rule — the chip dodges to the side away
    /// from the puck that opened the fan. A hand-placed one pins its x.
    /// The readout chip's slot in SCREEN points, or nil when this fan has no
    /// chip. A seeded fan still follows the old rule (dodge to the side away
    /// from the puck that opened it); a placed one is pinned.
    var readout: FanLayout.Readout? {
        guard let fan else {
            return FanLayout.Readout(rootAnchor.x < 100 ? 112 : 92,
                                     FanLayout.bounds.height - 16 + WatchLayout.liveInset.y)
        }
        guard let r = fan.readout else { return nil }
        guard r.followAnchor else { return r }
        return FanLayout.Readout(rootAnchor.x < 100 ? 112 : 92, r.center.y,
                                 font: r.font, crumbFont: r.crumbFont)
    }
    /// The chip's big line. The FAN's name by default — never "Tap to log"
    /// again — but the hovered item's name while a finger is actually on one.
    /// That readout is the only confirmation of what a hold-drag is about to
    /// fire, and silently firing the wrong thing is this app's worst failure.
    var hoveredReadoutTitle: String {
        if hoveringCancel { return "Release to cancel" }
        if hoveringBack { return "Back" }
        return items.first { $0.id == hoveredID }?.title ?? levelTitle
    }
    var hoveredReadoutColorHex: String? {
        if hoveringCancel || hoveringBack { return nil }
        return items.first { $0.id == hoveredID }?.colorHex
    }

    func angle(forIndex i: Int, count: Int) -> Double {
        layout.angle(forIndex: i, count: count)
    }

    func position(forIndex i: Int, count: Int) -> CGPoint {
        fixedPos[i] ?? layout.position(forIndex: i, count: count)
    }

    func labelPosition(forIndex i: Int, count: Int) -> CGPoint {
        // Hand-placed labels are absolute — the whole point is being able to
        // pull one out from under a crowded neighbour. Otherwise: fixed arc
        // ⇒ fixed labels, straight below the bubble. The old outward/stacked
        // search existed to dodge neighbours in a FITTED arc; slots here are
        // pitched wide enough that it can't happen.
        if let s = slot(i) { return s.label }
        return TopArcLayout.labelPosition(for: position(forIndex: i, count: count))
    }

    // MARK: - Hold-drag flow

    func updateDrag(_ location: CGPoint) {
        guard isOpen, !tapMode else { return }
        lastLocation = location

        // Finger over the ✕ pad = armed to cancel everything.
        if distance(location, cancelPos) <= FanLayout.Pads.hoverRadius {
            if !hoveringCancel {
                hoveringCancel = true
                WatchHaptics.play(.click)
            }
            hoveringBack = false
            if hoveredID != nil { hoveredID = nil }
            return
        }
        hoveringCancel = false

        // Sub-arc: dragging onto the parent's old spot pops one level.
        if let back = backPos {
            let d = hypot(location.x - back.x, location.y - back.y)
            if d < 24 {
                if !hoveringBack {
                    hoveringBack = true
                    backHoverStart = Date()
                    WatchHaptics.play(.click)
                } else if Date().timeIntervalSince(backHoverStart) > 0.15 {
                    pop()
                }
                if hoveredID != nil { hoveredID = nil }
                return
            }
        }
        hoveringBack = false

        var nearest: (item: RadialItem, dist: CGFloat)? = nil
        for (i, item) in items.enumerated() {
            let p = position(forIndex: i, count: items.count)
            let d = hypot(location.x - p.x, location.y - p.y)
            if d < 40, d < (nearest?.dist ?? .infinity) {
                nearest = (item, d)
            }
        }

        let newID = nearest?.item.id
        if newID != hoveredID {
            hoveredID = newID
            if newID != nil { WatchHaptics.play(.click) }
            scheduleDwell(for: nearest?.item)
        }
    }

    /// Hold an expandable item ~1 s to open its sub-fan, with a haptic ramp
    /// so the wait is FELT: light pulse → firmer pulse → pop on expansion
    /// (Sebastian: tactile feedback while press-and-holding).
    private func scheduleDwell(for item: RadialItem?) {
        dwellTask?.cancel()
        dwellTask = nil
        guard let item, let children = item.children, !children.isEmpty else { return }
        dwellTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self, !Task.isCancelled, self.hoveredID == item.id else { return }
            WatchHaptics.play(.click)                       // ramp: light
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, self.hoveredID == item.id else { return }
            WatchHaptics.play(.directionUp)                 // ramp: firmer
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, self.isOpen, !self.tapMode,
                  self.hoveredID == item.id else { return }
            self.expand(item, children: children)           // pop lives in expand()
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint?) -> CGFloat {
        guard let b else { return .infinity }
        return hypot(a.x - b.x, a.y - b.y)
    }

    private func clampToScreen(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 18), layout.bounds.width - 18),
                y: min(max(p.y, 16), layout.bounds.height - 16))
    }

    /// The cascade: the tapped item's position becomes the CENTER of the
    /// next fan — options radiate outward from wherever the finger is, so
    /// navigating deep never means reaching back across the screen.
    /// Back and ✕ sit DIRECTLY OPPOSITE the fan from the finger (the one
    /// direction guaranteed empty), back nearer, ✕ beyond it.
    private func expand(_ parent: RadialItem, children: [RadialItem]) {
        dwellTask?.cancel()
        dwellTask = nil
        guard let idx = items.firstIndex(of: parent) else { return }
        let parentPos = position(forIndex: idx, count: items.count)   // fixed-aware
        // Fan toward the roomiest part of the screen, one finger-reach out —
        // children never pile into an edge or under other elements.
        let open = RadialLayout.openSpaceDirection(from: parentPos, bounds: layout.bounds)

        stack.append(Level(items: items, breadcrumb: breadcrumb, levelTitle: levelTitle,
                           layout: layout, fixedPos: fixedPos, fan: fan))
        // The trail reads previous-over-current: EVENTS above Temp, then
        // COMMS above Call one level deeper.
        breadcrumb = levelTitle
        levelTitle = FanLayout.fanTitle[parent.id] ?? parent.title
        items = children
        hoveredID = nil
        layout.anchor = parentPos
        // Uniform standard: children sit ~56 pt (a finger-width) from the
        // touch point; the cap keeps them within easy reach even squeezed.
        layout.fit(count: children.count, preferredCenter: open,
                   startRadius: 56, radiusCap: 72)

        // A nested fan is keyed by the PARENT item's id ("grp:airway", …),
        // so each sub-menu can be placed independently of the fan it came
        // from. Unplaced, children take over the very same arc the parent
        // occupied and the two exit pads never move — depth changes the
        // CONTENTS of the arc, never its geometry.
        fan = FanLayout.fan(parent.id, count: children.count)
        fixedPos = slotCentres(count: children.count, bounds: layout.bounds)
        WatchHaptics.play(.success)        // the "pop" that ends the dwell ramp
    }

    /// Back one level — restores the parent fan exactly as it was.
    private func pop() {
        guard let level = stack.popLast() else { return }
        dwellTask?.cancel()
        dwellTask = nil
        items = level.items
        breadcrumb = level.breadcrumb
        levelTitle = level.levelTitle
        layout = level.layout
        fixedPos = level.fixedPos
        fan = level.fan
        hoveredID = nil
        hoveringBack = false
        WatchHaptics.play(.directionDown)
    }

    /// Finger lifted. ONLY a hovered LEAF fires — parents just expand, and
    /// lifting on dead space, the ✕ pad, the back pad, or a parent records
    /// nothing. An accidental hover must never become a logged clinical event.
    func endDrag() {
        guard isOpen, !tapMode else { return }
        if let item = items.first(where: { $0.id == hoveredID }),
           item.children?.isEmpty ?? true {
            fire(item)
        } else if !hoveringCancel, !hoveringBack {
            // Released on dead space or on a parent: nothing was recorded,
            // and the wearer has no other way to tell.
            missedAt = Date()
        }
        close()
    }

    // MARK: - Tap flow

    func tapSelect(_ item: RadialItem) {
        guard isOpen else { return }
        if let children = item.children, !children.isEmpty {
            expand(item, children: children)   // same cascade as hold mode
        } else {
            fire(item)
            close()
        }
    }

    /// Tap mode: the ✕ always closes; the chevron pad pops one level.
    // No tapMode guard: the exit pads are now hit-testable in BOTH modes, so
    // these must actually run in hold mode too. Both are idempotent and log
    // nothing — the reason they, alone, are exempt from the tap-mode gate.
    func tapClose() {
        guard isOpen else { return }
        close()
    }

    func tapBack() {
        guard isOpen else { return }
        pop()
    }

    private func fire(_ item: RadialItem) {
        WatchHaptics.play(.success)
        onSelect?(item)
    }
}

// MARK: - Anchor puck

struct RadialAnchor: View {
    let id: String
    let center: CGPoint
    let symbol: String
    /// Caption under the puck. The LIVE screen's anchors go icon-only
    /// (captions retired there 2026-07-23); the setup tiles still use it.
    var label: String = ""
    let color: Color
    let items: () -> [RadialItem]
    let radius: CGFloat                    // base ring; the model grows it to fit
    let bounds: CGSize                     // screen box the arc must stay inside
    var tapOnly: Bool = false              // settings: every entry opens a TAP fan
    var tapAction: (() -> Void)? = nil     // set → tap runs this instead of opening
    let model: RadialMenuModel
    let onSelect: (RadialItem) -> Void

    private var isActive: Bool { model.isOpen }

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(CRTheme.bg)
                .frame(width: 42, height: 42)
                .background(Circle().fill(color))
                .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1))
            // "Post-ROSC" → two stacked lines; empty label = icon only.
            if !label.isEmpty {
                Text(label.uppercased().replacingOccurrences(of: "/", with: "\n"))
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundStyle(CRTheme.textDim)
            }
        }
        .opacity(isActive ? 0.35 : 1)
        .position(center)
        .gesture(holdDragGesture)
        .simultaneousGesture(TapGesture().onEnded { handleTap() })
    }

    private var holdDragGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.15)
            .sequenced(before: DragGesture(minimumDistance: 0,
                                           coordinateSpace: .named("live")))
            .onChanged { value in
                switch value {
                case .first(true):
                    // Tap-only: the hold opens the SAME tap fan a tap would —
                    // updateDrag/endDrag no-op in tap mode, so releasing
                    // leaves the fan up for tapping.
                    // An anchor with nothing to bloom must not open an empty
                    // fan — holding it is a no-op, not a one-item echo.
                    let blooms = items()
                    guard !blooms.isEmpty else { break }
                    model.open(anchor: center, radius: radius, bounds: bounds,
                               items: blooms, tapMode: tapOnly, key: id,
                               onSelect: onSelect)
                case .second(true, let drag):
                    if let drag { model.updateDrag(drag.location) }
                default:
                    break
                }
            }
            .onEnded { value in
                if case .second = value { model.endDrag() }
            }
    }

    private func handleTap() {
        if model.isOpen { model.closeUnlessJustOpened(); return }
        if let tapAction, !tapOnly {
            tapAction()
        } else {
            // Tap-only also reroutes the shock bolt's quick-log tap into its
            // menu — the instant defib log is exactly the accidental-touch
            // hazard that mode exists to remove.
            model.open(anchor: center, radius: radius, bounds: bounds,
                       items: items(), tapMode: true, key: id,
                       onSelect: onSelect)
        }
    }
}

// MARK: - Overlay

struct RadialMenuOverlay: View {
    let model: RadialMenuModel

    var body: some View {
        GeometryReader { geo in
            overlayContent(size: geo.size)
        }
    }

    private func overlayContent(size: CGSize) -> some View {
        ZStack {
            if model.isOpen {
                // The wash. The BLUR lives on the layers behind this, in
                // LiveSessionView — `.ultraThinMaterial` here made the whole
                // overlay render as nothing on watchOS (buttons still in the
                // accessibility tree, not a pixel on screen).
                //
                // Two layers on purpose: dim, then lift off black. A flat
                // black 0.62 sank the backdrop and the dark bubbles to nearly
                // the same value, which is what made the fans hard to read.
                Rectangle()
                    .fill(Color.black.opacity(FanLayout.Backdrop.dim))
                    .overlay(CRTheme.scrimTint.opacity(FanLayout.Backdrop.tint))
                    .ignoresSafeArea()
                    .onTapGesture { model.close() }
                    // The one element that MUST NOT hit-test in hold mode: it
                    // covers the whole screen, so it would capture the drag
                    // the instant a fan opened.
                    .allowsHitTesting(model.tapMode)

                // Item bubbles. zIndex is explicit so a hand-placed fan can
                // decide what covers what when two bubbles are deliberately
                // overlapped; unplaced fans get index order, as before.
                ForEach(Array(model.items.enumerated()), id: \.element.id) { i, item in
                    bubble(item, index: i)
                        .position(model.position(forIndex: i, count: model.items.count))
                        .zIndex(Double(model.slotZ(i)))
                        .transition(.scale.combined(with: .opacity))
                }

                // Every bubble carries its name — the whole arc reads at a
                // glance before the finger commits to a direction. ONE font
                // for every label on every menu: small caps-only type that
                // wraps instead of shrinking, so nothing reads bigger or
                // smaller than its neighbors.
                ForEach(Array(model.items.enumerated()), id: \.element.id) { i, item in
                    let hovered = model.hoveredID == item.id
                    let p = model.labelPosition(forIndex: i, count: model.items.count)
                    Text(item.title.uppercased())
                        .font(.system(size: model.labelFont(i), weight: .heavy, design: .rounded))
                        .tracking(0.3)
                        .foregroundStyle(hovered ? item.color : CRTheme.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(RoundedRectangle(cornerRadius: 5).fill(CRTheme.bg.opacity(0.72)))
                        // Cap wrap width AFTER the background so the fill hugs
                        // the glyphs instead of stretching to the cap.
                        .frame(maxWidth: model.labelWidth(i))
                        // A hand-placed label is already where it was put —
                        // clamping it again would quietly undo the placement.
                        // Seeded fans keep the clamp that produced their seed.
                        .position(model.fan == nil
                                  ? CGPoint(x: min(max(p.x, 32), size.width - 32), y: max(10, p.y))
                                  : p)
                        .allowsHitTesting(false)
                }

                // Readout chip — the hovered item's name, big and glanceable
                // The readout chip moved to `LiveSessionView.fanChrome` —
                // Sebastian's placement puts it at screen y 25, which is above
                // this layer's box, and it is optional per fan (removed from
                // Meds and Fluids).
            }
        }
        .animation(.spring(duration: 0.22), value: model.isOpen)
        .animation(.spring(duration: 0.18), value: model.items)
        // Open in BOTH modes now. The reason this was tap-only is that the
        // SCRIM is a full-screen touchable surface and would steal the
        // anchor's in-flight drag; that is now handled on the scrim itself
        // (below), which is the narrow fix. Everything else in here is
        // frame-sized and cannot intercept beyond its own bounds.
        .allowsHitTesting(model.isOpen)
    }

    // The exit pads used to be an `.overlay { exitPads }` right here, inside
    // the fan's GeometryReader. They are drawn by `LiveSessionView.exitPads`
    // in SCREEN space now — Back sits at (32, 32), nineteen points above this
    // layer's box, and a child positioned outside its parent's bounds never
    // receives a touch. Everything that made them work is preserved there:
    // `.offset` inside a top-leading ZStack (never `.position`, which would
    // expand to fill and swallow the screen), and hit-testing in BOTH modes.

    private var hoveredTitle: String {
        if model.hoveringCancel { return "Release to cancel" }
        if model.hoveringBack { return "Back" }
        return model.items.first { $0.id == model.hoveredID }?.title
            ?? (model.tapMode ? "Tap to log" : "Slide + release on an item")
    }

    private var hoveredColor: Color {
        if model.hoveringCancel || model.hoveringBack { return CRTheme.textDim }
        return model.items.first { $0.id == model.hoveredID }?.color ?? CRTheme.text
    }

    @ViewBuilder
    private func bubble(_ item: RadialItem, index: Int) -> some View {
        let hovered = model.hoveredID == item.id
        // Icon color: explicit override wins (blood's red drop stays red on
        // the hover fill too); otherwise item color, inverting on hover.
        let iconColor = item.iconColorHex.map { Color(hex: $0) }
            ?? (hovered ? CRTheme.bg : item.color)
        let core = ZStack {
            Circle()
                .fill(hovered ? item.color : CRTheme.surfaceHi)
            Circle()
                .strokeBorder(item.color.opacity(hovered ? 1 : 0.7),
                              lineWidth: hovered ? 2 : 1.2)
            if item.symbol.hasPrefix("text:") {
                // Element abbreviations (Ca, Mg, HCO₃) render as type — same
                // weight family as the SF icons so they read as siblings.
                // Kept a fixed 3 pt under the icon size the way it shipped.
                Text(item.symbol.dropFirst(5))
                    .font(.system(size: model.slotGlyph(index) - 3, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(width: model.slotDiameter(index) - 8)
                    .foregroundStyle(iconColor)
            } else {
                Image(systemName: item.symbol)
                    .font(.system(size: model.slotGlyph(index), weight: .bold))
                    .foregroundStyle(iconColor)
            }
            if item.children != nil {
                Circle()
                    .fill(item.color)
                    .frame(width: 6, height: 6)
                    // "has more" dot, pinned just inside the rim
                    .offset(y: model.slotDiameter(index) / 2 - 3)
            }
        }
        .frame(width: model.slotDiameter(index), height: model.slotDiameter(index))
        .scaleEffect(hovered ? 1.28 : 1.0)
        .animation(.spring(duration: 0.15), value: hovered)

        // ALWAYS a Button, in both modes. Previously tap-only, which left the
        // bubbles inert in hold mode — taps fell through the overlay onto the
        // anchor pucks behind, so nothing could be picked by tapping at all.
        // A Button's hit region is its own 38 pt frame, so this cannot swallow
        // the screen the way a .position'd .onTapGesture does.
        Button { model.tapSelect(item) } label: { core }
            .buttonStyle(.plain)
    }
}
