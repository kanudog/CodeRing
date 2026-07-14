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
        let backPos: CGPoint?
        let cancelPos: CGPoint
        let breadcrumb: String?
        let layout: RadialLayout
    }

    var isOpen = false
    var tapMode = false
    /// The ORIGINAL puck (cancel home at the root level).
    private(set) var rootAnchor: CGPoint = .zero
    var hoveredID: String? = nil
    var hoveringCancel = false         // finger over the ✕ pad
    var hoveringBack = false           // finger over the back chevron pad
    var breadcrumb: String? = nil      // parent title while in a sub-arc
    /// Drag here to pop a level — sits opposite the fan from the finger.
    private(set) var backPos: CGPoint? = nil
    /// Drag here to bail out entirely — beyond the back pad on the same line
    /// (the root puck itself at level 0).
    private(set) var cancelPos: CGPoint = .zero

    private(set) var items: [RadialItem] = []
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
              items: [RadialItem], tapMode: Bool,
              onSelect: @escaping (RadialItem) -> Void) {
        self.rootAnchor = anchor
        self.layout = RadialLayout(anchor: anchor, bounds: bounds)
        self.layout.fit(count: items.count, preferredCenter: nil, startRadius: radius)
        self.items = items
        self.tapMode = tapMode
        self.onSelect = onSelect
        self.hoveredID = nil
        self.breadcrumb = nil
        self.backPos = nil
        self.cancelPos = anchor
        self.stack = []
        self.lastLocation = nil
        self.isOpen = true
        WatchHaptics.play(.start)
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
        backPos = nil
        stack = []
        lastLocation = nil
        onSelect = nil
    }

    // MARK: - Geometry (delegated to CodeCore's unit-tested RadialLayout)

    func angle(forIndex i: Int, count: Int) -> Double {
        layout.angle(forIndex: i, count: count)
    }

    func position(forIndex i: Int, count: Int) -> CGPoint {
        layout.position(forIndex: i, count: count)
    }

    func labelPosition(forIndex i: Int, count: Int) -> CGPoint {
        layout.labelPosition(forIndex: i, count: count)
    }

    // MARK: - Hold-drag flow

    func updateDrag(_ location: CGPoint) {
        guard isOpen, !tapMode else { return }
        lastLocation = location

        // Finger over the ✕ pad = armed to cancel everything.
        if distance(location, cancelPos) <= 26 {
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
        let parentPos = layout.position(forIndex: idx, count: items.count)
        // Fan toward the roomiest part of the screen, one finger-reach out —
        // children never pile into an edge or under other elements.
        let open = RadialLayout.openSpaceDirection(from: parentPos, bounds: layout.bounds)

        stack.append(Level(items: items, backPos: backPos, cancelPos: cancelPos,
                           breadcrumb: breadcrumb, layout: layout))
        breadcrumb = parent.title
        items = children
        hoveredID = nil
        layout.anchor = parentPos
        // Uniform standard: children sit ~56 pt (a finger-width) from the
        // touch point; the cap keeps them within easy reach even squeezed.
        layout.fit(count: children.count, preferredCenter: open,
                   startRadius: 56, radiusCap: 72)

        // Exits opposite the fitted fan's center direction.
        let opp = ((layout.arcStart + layout.arcEnd) / 2 + 180) * .pi / 180
        backPos = clampToScreen(CGPoint(x: parentPos.x + 40 * cos(opp),
                                        y: parentPos.y + 40 * sin(opp)))
        cancelPos = clampToScreen(CGPoint(x: parentPos.x + 78 * cos(opp),
                                          y: parentPos.y + 78 * sin(opp)))
        WatchHaptics.play(.success)        // the "pop" that ends the dwell ramp
    }

    /// Back one level — restores the parent fan exactly as it was.
    private func pop() {
        guard let level = stack.popLast() else { return }
        dwellTask?.cancel()
        dwellTask = nil
        items = level.items
        backPos = level.backPos
        cancelPos = level.cancelPos
        breadcrumb = level.breadcrumb
        layout = level.layout
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
        }
        close()
    }

    // MARK: - Tap flow

    func tapSelect(_ item: RadialItem) {
        guard tapMode else { return }
        if let children = item.children, !children.isEmpty {
            expand(item, children: children)   // same cascade as hold mode
        } else {
            fire(item)
            close()
        }
    }

    /// Tap mode: the ✕ always closes; the chevron pad pops one level.
    func tapClose() {
        guard tapMode else { return }
        close()
    }

    func tapBack() {
        guard tapMode else { return }
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
    let label: String
    let color: Color
    let items: () -> [RadialItem]
    let radius: CGFloat                    // base ring; the model grows it to fit
    let bounds: CGSize                     // screen box the arc must stay inside
    var tapAction: (() -> Void)? = nil     // set → tap runs this instead of opening
    let model: RadialMenuModel
    let onSelect: (RadialItem) -> Void

    private var isActive: Bool { model.isOpen }

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(CRTheme.bg)
                .frame(width: 42, height: 42)
                .background(Circle().fill(color))
                .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1))
            // "Rhythm/Code" → two stacked lines; single words stay one line.
            Text(label.uppercased().replacingOccurrences(of: "/", with: "\n"))
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .tracking(0.6)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundStyle(CRTheme.textDim)
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
                    model.open(anchor: center, radius: radius, bounds: bounds,
                               items: items(), tapMode: false, onSelect: onSelect)
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
        if model.isOpen { model.close(); return }
        if let tapAction {
            tapAction()
        } else {
            model.open(anchor: center, radius: radius, bounds: bounds,
                       items: items(), tapMode: true, onSelect: onSelect)
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
                Color.black.opacity(0.62)
                    .ignoresSafeArea()
                    .onTapGesture { if model.tapMode { model.close() } }

                // Item bubbles
                ForEach(Array(model.items.enumerated()), id: \.element.id) { i, item in
                    bubble(item)
                        .position(model.position(forIndex: i, count: model.items.count))
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
                        .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                        .tracking(0.3)
                        .foregroundStyle(hovered ? item.color : CRTheme.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(RoundedRectangle(cornerRadius: 5).fill(CRTheme.bg.opacity(0.72)))
                        // Cap wrap width AFTER the background so the fill hugs
                        // the glyphs instead of stretching to the cap.
                        .frame(maxWidth: 74)
                        .position(x: min(max(p.x, 32), size.width - 32),
                                  y: max(10, p.y))
                        .allowsHitTesting(false)
                }

                // Back pad — the parent bubble's old spot; drag onto it (or
                // tap it in tap mode) to pop one level.
                if let back = model.backPos {
                    ZStack {
                        Circle()
                            .fill(model.hoveringBack ? CRTheme.surfaceHi : CRTheme.surface.opacity(0.7))
                        Circle()
                            .strokeBorder(.white.opacity(model.hoveringBack ? 0.8 : 0.3),
                                          lineWidth: 1.5)
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(model.hoveringBack ? CRTheme.text : CRTheme.textDim)
                    }
                    .frame(width: 30, height: 30)
                    .scaleEffect(model.hoveringBack ? 1.2 : 1.0)
                    .animation(.spring(duration: 0.15), value: model.hoveringBack)
                    .position(back)
                    .onTapGesture { model.tapBack() }
                }

                // ✕ pad — the root puck at level 0, then directly opposite
                // the fan from the finger (beyond the back chevron) so it
                // never sits on top of other elements.
                ZStack {
                    Circle()
                        .fill(model.hoveringCancel ? CRTheme.surfaceHi : CRTheme.surface.opacity(0.6))
                    Circle()
                        .strokeBorder(.white.opacity(model.hoveringCancel ? 0.8 : 0.35),
                                      lineWidth: 1.5)
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(model.hoveringCancel ? CRTheme.text : CRTheme.textDim)
                }
                .frame(width: 34, height: 34)
                .scaleEffect(model.hoveringCancel ? 1.2 : 1.0)
                .animation(.spring(duration: 0.15), value: model.hoveringCancel)
                .position(model.cancelPos)
                .onTapGesture { model.tapClose() }

                // Readout chip — the hovered item's name, big and glanceable
                VStack(spacing: 1) {
                    if let crumb = model.breadcrumb {
                        Text(crumb.uppercased())
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(CRTheme.textDim)
                    }
                    Text(hoveredTitle)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(hoveredColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(CRTheme.surfaceHi))
                .frame(maxWidth: .infinity)
                // The chip dodges the arc: top by default, bottom whenever
                // bubbles climb high enough that it would sit on their labels.
                .position(x: model.rootAnchor.x < 100 ? 110 : 90,
                          y: readoutAtBottom(size) ? size.height - 16 : 24)
            }
        }
        .animation(.spring(duration: 0.22), value: model.isOpen)
        .animation(.spring(duration: 0.18), value: model.items)
        .allowsHitTesting(model.isOpen && model.tapMode)
        // In hold mode the anchor's own gesture keeps ownership of the touch,
        // so the overlay must not intercept — hence hit testing only in tap mode.
    }

    /// True when any bubble (or its outward label) reaches the top band.
    private func readoutAtBottom(_ size: CGSize) -> Bool {
        let n = model.items.count
        guard n > 0 else { return false }
        let highest = (0..<n).map { model.position(forIndex: $0, count: n).y }.min() ?? 999
        return highest < 78
    }

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
    private func bubble(_ item: RadialItem) -> some View {
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
                Text(item.symbol.dropFirst(5))
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(width: 30)
                    .foregroundStyle(iconColor)
            } else {
                Image(systemName: item.symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(iconColor)
            }
            if item.children != nil {
                Circle()
                    .fill(item.color)
                    .frame(width: 6, height: 6)
                    .offset(y: 16)   // "has more" dot
            }
        }
        .frame(width: 38, height: 38)
        .scaleEffect(hovered ? 1.28 : 1.0)
        .animation(.spring(duration: 0.15), value: hovered)

        if model.tapMode {
            Button { model.tapSelect(item) } label: { core }
                .buttonStyle(.plain)
        } else {
            core
        }
    }
}
