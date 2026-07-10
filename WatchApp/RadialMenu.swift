// RadialMenu.swift — the signature interaction of CodeRing.
//
// Anchor pucks sit on the screen perimeter. Two ways in:
//   HOLD (0.15s) → arc of items blooms, every bubble labeled so the whole
//   menu reads at a glance. Slide finger through — release ON a leaf to
//   select it. Nothing else ever logs: parents only expand (dwell 0.3s),
//   and lifting anywhere that isn't a leaf cancels.
//   Inside a sub-arc, a chevron pad marks where the parent bubble was —
//   dragging back onto it pops one level. The ✕ pad at the origin is the
//   full bail-out (Sebastian: accidental "Access attempt" logged, twice).
//   TAP → same arc in tap mode; items become buttons; the origin pad pops
//   a level; tap outside closes.
//
// One RadialMenuModel per screen; every anchor drives the same overlay.

import SwiftUI
import WatchKit
import CodeCore

struct RadialItem: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
    let color: Color
    var children: [RadialItem]? = nil

    static func == (a: RadialItem, b: RadialItem) -> Bool { a.id == b.id }
}

@MainActor
@Observable
final class RadialMenuModel {

    /// One expanded menu level, so Back can restore it exactly.
    private struct Level {
        let items: [RadialItem]
        let backPos: CGPoint?
        let breadcrumb: String?
    }

    var isOpen = false
    var tapMode = false
    var anchor: CGPoint = .zero
    var arcStart: Double = -160        // degrees; 0 = right, -90 = up
    var arcEnd: Double = -20
    var radius: CGFloat = 64
    var hoveredID: String? = nil
    var hoveringCancel = false         // finger over the origin ✕ pad
    var hoveringBack = false           // finger over the sub-arc's chevron pad
    var breadcrumb: String? = nil      // parent title while in a sub-arc
    /// Where the parent bubble sat before it expanded — the Back target.
    private(set) var backPos: CGPoint? = nil

    private(set) var items: [RadialItem] = []
    private var stack: [Level] = []
    private var backHoverStart: Date = .distantPast
    /// Time-driven expansion: drag events stop for a motionless finger, so
    /// dwell must run on a clock, not on the next touch delta.
    private var dwellTask: Task<Void, Never>? = nil
    private var onSelect: ((RadialItem) -> Void)? = nil

    // MARK: - Lifecycle

    func open(anchor: CGPoint, arcStart: Double, arcEnd: Double, radius: CGFloat,
              items: [RadialItem], tapMode: Bool,
              onSelect: @escaping (RadialItem) -> Void) {
        self.anchor = anchor
        self.arcStart = arcStart
        self.arcEnd = arcEnd
        self.radius = radius
        self.items = items
        self.tapMode = tapMode
        self.onSelect = onSelect
        self.hoveredID = nil
        self.breadcrumb = nil
        self.backPos = nil
        self.stack = []
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
        onSelect = nil
    }

    // MARK: - Geometry

    func angle(forIndex i: Int, count: Int) -> Double {
        guard count > 1 else { return (arcStart + arcEnd) / 2 }
        return arcStart + (arcEnd - arcStart) * Double(i) / Double(count - 1)
    }

    func position(forIndex i: Int, count: Int) -> CGPoint {
        let a = angle(forIndex: i, count: count) * .pi / 180
        return CGPoint(x: anchor.x + radius * cos(a),
                       y: anchor.y + radius * sin(a))
    }

    /// Labels sit radially outward from their bubble so no label ever covers
    /// an adjacent bubble — EXCEPT at the shallow ends of the arc, where
    /// "outward" is sideways and lands on the neighbor: those go UNDER their
    /// bubble instead (Sebastian: Pause/More labels overlapped bubbles).
    func labelPosition(forIndex i: Int, count: Int) -> CGPoint {
        let deg = angle(forIndex: i, count: count)
        let a = deg * .pi / 180
        if abs(sin(a)) < 0.45 {
            let bubble = position(forIndex: i, count: count)
            return CGPoint(x: bubble.x, y: bubble.y + 27)
        }
        let r = radius + 30
        return CGPoint(x: anchor.x + r * cos(a),
                       y: anchor.y + r * sin(a))
    }

    // MARK: - Hold-drag flow

    func updateDrag(_ location: CGPoint) {
        guard isOpen, !tapMode else { return }

        // Finger back over the origin pad = armed to cancel everything.
        let fromAnchor = hypot(location.x - anchor.x, location.y - anchor.y)
        guard fromAnchor > 28 else {
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

    /// Deliberate 2 s hold on an expandable item opens its sub-arc
    /// (Sebastian: expansion must never happen by accident mid-slide).
    private func scheduleDwell(for item: RadialItem?) {
        dwellTask?.cancel()
        dwellTask = nil
        guard let item, let children = item.children, !children.isEmpty else { return }
        dwellTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, !Task.isCancelled,
                  self.isOpen, !self.tapMode,
                  self.hoveredID == item.id else { return }
            self.expand(item, children: children)
        }
    }

    /// Back target sits NEXT TO the ✕ pad at the origin — one place to look
    /// for both exits, offset toward screen center so it never clips.
    private func backPadPosition() -> CGPoint {
        CGPoint(x: anchor.x + (anchor.x < 60 ? 38 : -38), y: anchor.y)
    }

    private func expand(_ parent: RadialItem, children: [RadialItem]) {
        dwellTask?.cancel()
        dwellTask = nil
        stack.append(Level(items: items, backPos: backPos, breadcrumb: breadcrumb))
        backPos = backPadPosition()
        breadcrumb = parent.title
        items = children
        hoveredID = nil
        WatchHaptics.play(.directionUp)
    }

    /// Back one level — restores the parent arc exactly as it was.
    private func pop() {
        guard let level = stack.popLast() else { return }
        dwellTask?.cancel()
        dwellTask = nil
        items = level.items
        backPos = level.backPos
        breadcrumb = level.breadcrumb
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
            stack.append(Level(items: items, backPos: backPos, breadcrumb: breadcrumb))
            backPos = backPadPosition()
            breadcrumb = item.title
            items = children
            WatchHaptics.play(.directionUp)
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
    let arcStart: Double
    let arcEnd: Double
    let radius: CGFloat
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
            Text(label.uppercased())
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .tracking(0.6)
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
                    model.open(anchor: center, arcStart: arcStart, arcEnd: arcEnd,
                               radius: radius, items: items(), tapMode: false,
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
        if model.isOpen { model.close(); return }
        if let tapAction {
            tapAction()
        } else {
            model.open(anchor: center, arcStart: arcStart, arcEnd: arcEnd,
                       radius: radius, items: items(), tapMode: true,
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
                        .font(.system(size: 7, weight: .heavy, design: .rounded))
                        .tracking(0.3)
                        .foregroundStyle(hovered ? item.color : CRTheme.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 62)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 5).fill(CRTheme.bg.opacity(0.72)))
                        .position(x: min(max(p.x, 30), size.width - 30),
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

                // ✕ pad at the origin — drag back here (or tap in tap mode)
                // to bail out without logging anything.
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
                .position(model.anchor)
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
                .position(x: model.anchor.x < 100 ? 110 : 90, y: 24)
            }
        }
        .animation(.spring(duration: 0.22), value: model.isOpen)
        .animation(.spring(duration: 0.18), value: model.items)
        .allowsHitTesting(model.isOpen && model.tapMode)
        // In hold mode the anchor's own gesture keeps ownership of the touch,
        // so the overlay must not intercept — hence hit testing only in tap mode.
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
        let core = ZStack {
            Circle()
                .fill(hovered ? item.color : CRTheme.surfaceHi)
            Circle()
                .strokeBorder(item.color.opacity(hovered ? 1 : 0.7),
                              lineWidth: hovered ? 2 : 1.2)
            Image(systemName: item.symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(hovered ? CRTheme.bg : item.color)
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
