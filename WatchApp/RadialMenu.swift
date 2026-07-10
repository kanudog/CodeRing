// RadialMenu.swift — the signature interaction of CodeRing.
//
// Anchor pucks sit on the screen perimeter. Two ways in:
//   HOLD (0.15s) → arc of items blooms. Slide finger through — hovering reads
//   the item name in the top chip — release ON a leaf to select it. Nothing
//   else ever logs: parents only expand (dwell 0.3s), and lifting anywhere
//   that isn't a leaf cancels. Dragging back to the ✕ pad at the origin is
//   the explicit bail-out (Sebastian: accidental "Access attempt" logged).
//   TAP → same arc opens in tap mode; items become buttons; tap outside closes.
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

    var isOpen = false
    var tapMode = false
    var anchor: CGPoint = .zero
    var arcStart: Double = -160        // degrees; 0 = right, -90 = up
    var arcEnd: Double = -20
    var radius: CGFloat = 64
    var hoveredID: String? = nil
    var hoveringCancel = false         // finger back over the origin ✕ pad
    var breadcrumb: String? = nil      // parent title while in a sub-arc

    private(set) var items: [RadialItem] = []
    private var pendingParent: RadialItem? = nil
    private var hoverStart: Date = .distantPast
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
        self.pendingParent = nil
        self.isOpen = true
        WatchHaptics.play(.start)
    }

    func close() {
        isOpen = false
        items = []
        hoveredID = nil
        hoveringCancel = false
        breadcrumb = nil
        pendingParent = nil
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

    // MARK: - Hold-drag flow

    func updateDrag(_ location: CGPoint) {
        guard isOpen, !tapMode else { return }

        // Finger back over the origin pad = armed to cancel.
        let fromAnchor = hypot(location.x - anchor.x, location.y - anchor.y)
        guard fromAnchor > 28 else {
            if !hoveringCancel {
                hoveringCancel = true
                WatchHaptics.play(.click)
            }
            if hoveredID != nil { hoveredID = nil }
            return
        }
        hoveringCancel = false

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
            hoverStart = Date()
            if newID != nil { WatchHaptics.play(.click) }
        } else if let item = nearest?.item,
                  let children = item.children, !children.isEmpty,
                  Date().timeIntervalSince(hoverStart) > 0.30 {
            expand(item, children: children)
        }
    }

    private func expand(_ parent: RadialItem, children: [RadialItem]) {
        pendingParent = parent
        breadcrumb = parent.title
        items = children
        hoveredID = nil
        hoverStart = Date()
        WatchHaptics.play(.directionUp)
    }

    /// Finger lifted. ONLY a hovered LEAF fires — parents just expand, and
    /// lifting on dead space, the ✕ pad, or a parent records nothing. An
    /// accidental hover must never become a logged clinical event.
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
            pendingParent = item
            breadcrumb = item.title
            items = children
            WatchHaptics.play(.directionUp)
        } else {
            fire(item)
            close()
        }
    }

    /// In tap mode, tapping the anchor pops one level, or closes at root.
    func tapAnchor() {
        guard tapMode else { return }
        close()
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
            overlayContent(width: geo.size.width)
        }
    }

    private func overlayContent(width: CGFloat) -> some View {
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

                // Name tag riding the hovered bubble — what your finger is on,
                // right where you're looking (the top readout stays too).
                if !model.tapMode,
                   let i = model.items.firstIndex(where: { $0.id == model.hoveredID }) {
                    let p = model.position(forIndex: i, count: model.items.count)
                    Text(model.items[i].title)
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(CRTheme.text)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(CRTheme.surfaceHi))
                        .position(x: min(max(p.x, 40), width - 40), y: max(12, p.y - 36))
                        .allowsHitTesting(false)
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
                .onTapGesture { model.tapAnchor() }

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
        return model.items.first { $0.id == model.hoveredID }?.title
            ?? (model.tapMode ? "Tap to log" : "Slide + release on an item")
    }

    private var hoveredColor: Color {
        if model.hoveringCancel { return CRTheme.textDim }
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
