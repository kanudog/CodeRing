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
    let colorHex: String
    var children: [RadialItem]? = nil

    var color: Color { Color(hex: colorHex) }

    init(id: String, title: String, symbol: String, colorHex: String,
         children: [RadialItem]? = nil) {
        self.id = id; self.title = title; self.symbol = symbol
        self.colorHex = colorHex; self.children = children
    }

    static func == (a: RadialItem, b: RadialItem) -> Bool { a.id == b.id }
}

@MainActor
@Observable
final class RadialMenuModel {

    /// One expanded menu level, so Back can restore it — including the arc
    /// geometry that level was laid out with.
    private struct Level {
        let items: [RadialItem]
        let backPos: CGPoint?
        let breadcrumb: String?
        let arcStart: Double
        let arcEnd: Double
        let radius: CGFloat
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
    private var bounds: CGSize = .zero
    private var baseRadius: CGFloat = 74
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
        self.anchor = anchor
        self.bounds = bounds
        self.baseRadius = radius
        self.items = items
        self.tapMode = tapMode
        self.onSelect = onSelect
        self.hoveredID = nil
        self.breadcrumb = nil
        self.backPos = nil
        self.stack = []
        self.lastLocation = nil
        fitArc(count: items.count, preferredCenter: nil, startRadius: radius)
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

    // MARK: - Geometry
    // The arc LAYS ITSELF OUT: every level keeps a minimum chord between
    // bubbles (no overlap, no hover flapping between neighbors) and only
    // uses angles whose bubbles land fully on screen — growing the radius
    // when a level needs more room than the current ring offers.

    private let minChord: CGFloat = 47        // bubble Ø38 + breathing room
    private let maxRadius: CGFloat = 118

    /// Degrees at which bubbles remain fully on screen for a given radius —
    /// the contiguous run nearest `preferredCenter` (or straight up).
    private func validWindow(radius r: CGFloat, preferredCenter: Double) -> ClosedRange<Double>? {
        var runs: [(lo: Double, hi: Double)] = []
        var runStart: Double? = nil
        var deg = -260.0
        while deg <= 30 {
            let a = deg * .pi / 180
            let p = CGPoint(x: anchor.x + r * cos(a), y: anchor.y + r * sin(a))
            let ok = p.x >= 22 && p.x <= bounds.width - 22 &&
                     p.y >= 16 && p.y <= bounds.height - 18
            if ok, runStart == nil { runStart = deg }
            if !ok, let s = runStart { runs.append((s, deg - 3)); runStart = nil }
            deg += 3
        }
        if let s = runStart { runs.append((s, 30)) }
        guard !runs.isEmpty else { return nil }
        let best = runs.min { a, b in
            let da = abs(preferredCenter - (a.lo + a.hi) / 2)
            let db = abs(preferredCenter - (b.lo + b.hi) / 2)
            return da < db
        }!
        return best.lo...best.hi
    }

    /// Choose arcStart/arcEnd/radius for `count` bubbles: enough angular
    /// spacing for the minimum chord, centered on the parent's direction,
    /// clamped to the on-screen window; radius grows until the span fits.
    private func fitArc(count: Int, preferredCenter: Double?, startRadius: CGFloat) {
        let want = preferredCenter ?? -90
        var r = startRadius
        while true {
            guard let window = validWindow(radius: r, preferredCenter: want) else {
                r -= 12
                if r < 40 { radius = startRadius; arcStart = -160; arcEnd = -20; return }
                continue
            }
            let spacing = Double(2 * asin(min(1, minChord / (2 * r)))) * 180 / .pi
            let span = spacing * Double(max(0, count - 1))
            let available = window.upperBound - window.lowerBound
            if span <= available || r >= maxRadius {
                let usable = min(span, available)
                let half = usable / 2
                let center = min(max(want, window.lowerBound + half), window.upperBound - half)
                radius = r
                arcStart = center - half
                arcEnd = center + half
                return
            }
            r += 12
        }
    }

    func angle(forIndex i: Int, count: Int) -> Double {
        guard count > 1 else { return (arcStart + arcEnd) / 2 }
        return arcStart + (arcEnd - arcStart) * Double(i) / Double(count - 1)
    }

    func position(forIndex i: Int, count: Int) -> CGPoint {
        let a = angle(forIndex: i, count: count) * .pi / 180
        return CGPoint(x: anchor.x + radius * cos(a),
                       y: anchor.y + radius * sin(a))
    }

    /// Labels sit radially OUTSIDE their bubble so no label ever covers an
    /// adjacent bubble. Where outward would clip the screen or run sideways
    /// into a neighbor, the label tries below, then above, then beside its
    /// own bubble — whichever spot is actually CLEAR of the other bubbles.
    func labelPosition(forIndex i: Int, count: Int) -> CGPoint {
        let deg = angle(forIndex: i, count: count)
        let a = deg * .pi / 180
        let bubble = position(forIndex: i, count: count)
        let others = (0..<count).filter { $0 != i }
            .map { position(forIndex: $0, count: count) }
        func clear(_ p: CGPoint) -> Bool {
            p.y >= 12 && p.y <= bounds.height - 10 &&
            others.allSatisfy { hypot($0.x - p.x, $0.y - p.y) > 32 }
        }
        func stacked() -> CGPoint {
            let below = CGPoint(x: bubble.x, y: bubble.y + 27)
            if clear(below) { return below }
            let above = CGPoint(x: bubble.x, y: bubble.y - 27)
            if clear(above) { return above }
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

    // MARK: - Hold-drag flow

    func updateDrag(_ location: CGPoint) {
        guard isOpen, !tapMode else { return }
        lastLocation = location

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

    /// Back target sits beside the ✕ pad at the origin, on whichever side
    /// keeps it CLEAR of the child bubbles — a back pad inside the bloom
    /// swallows hovers meant for items (bit the shock menu, whose arc and
    /// "toward screen center" were the same direction).
    private func backPadPosition() -> CGPoint {
        let towardCenter: CGFloat = anchor.x < bounds.width / 2 ? 38 : -38
        let candidates = [
            CGPoint(x: anchor.x + towardCenter, y: anchor.y),
            CGPoint(x: anchor.x - towardCenter, y: anchor.y),
            CGPoint(x: anchor.x, y: anchor.y + 38),
            CGPoint(x: anchor.x, y: anchor.y - 38)
        ]
        let bubbles = (0..<items.count).map { position(forIndex: $0, count: items.count) }
        func clearance(_ p: CGPoint) -> CGFloat {
            guard p.x >= 20, p.x <= bounds.width - 20,
                  p.y >= 16, p.y <= bounds.height - 16 else { return -1 }
            return bubbles.map { hypot($0.x - p.x, $0.y - p.y) }.min() ?? 999
        }
        return candidates.max { clearance($0) < clearance($1) } ?? candidates[0]
    }

    private func expand(_ parent: RadialItem, children: [RadialItem]) {
        dwellTask?.cancel()
        dwellTask = nil
        // Parent's direction BEFORE the arc mutates — the child arc centers on it.
        let parentAngle = items.firstIndex(of: parent).map { angle(forIndex: $0, count: items.count) }
        stack.append(Level(items: items, backPos: backPos, breadcrumb: breadcrumb,
                           arcStart: arcStart, arcEnd: arcEnd, radius: radius))
        breadcrumb = parent.title
        items = children
        hoveredID = nil
        // Children ring OUTSIDE the parent level, re-spaced for their count;
        // the back pad picks its spot AFTER layout so it dodges the bubbles.
        fitArc(count: children.count, preferredCenter: parentAngle,
               startRadius: min(radius + 22, maxRadius))
        backPos = backPadPosition()
        WatchHaptics.play(.directionUp)
        // A motionless finger gets no new drag events, so re-evaluate hover
        // at the last known spot — that's what lets a continuous hold walk
        // DOWN through nested levels (access → IV → limb).
        if !tapMode, let loc = lastLocation { updateDrag(loc) }
    }

    /// Back one level — restores the parent arc exactly as it was.
    private func pop() {
        guard let level = stack.popLast() else { return }
        dwellTask?.cancel()
        dwellTask = nil
        items = level.items
        backPos = level.backPos
        breadcrumb = level.breadcrumb
        arcStart = level.arcStart
        arcEnd = level.arcEnd
        radius = level.radius
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
            let parentAngle = items.firstIndex(of: item).map { angle(forIndex: $0, count: items.count) }
            stack.append(Level(items: items, backPos: backPos, breadcrumb: breadcrumb,
                               arcStart: arcStart, arcEnd: arcEnd, radius: radius))
            breadcrumb = item.title
            items = children
            fitArc(count: children.count, preferredCenter: parentAngle,
                   startRadius: min(radius + 22, maxRadius))
            backPos = backPadPosition()
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
                // The chip dodges the arc: top by default, bottom whenever
                // bubbles climb high enough that it would sit on their labels.
                .position(x: model.anchor.x < 100 ? 110 : 90,
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
