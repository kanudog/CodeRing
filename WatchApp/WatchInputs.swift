// WatchInputs.swift — fast value entry for the setup flow:
//   • NumberPadSheet — tap the big number, type the value directly.
//   • EdgeAdjustStrip — vertical swipe strip pinned to the screen edge;
//     finger distance from the strip sets sensitivity (near = drastic,
//     drift left = fine), so one gesture covers 3 kg and 0.1 kg moves.

import SwiftUI
import CodeCore

/// Compact digit pad for typing a weight or age directly on the watch.
/// An optional alternate unit (months ↔ years) renders as tappable chips;
/// the committed value is always converted to the PRIMARY unit.
struct NumberPadSheet: View {
    let unit: String
    var altUnit: (label: String, factor: Double)? = nil   // e.g. ("yr", 12)
    let allowsDecimal: Bool
    let range: ClosedRange<Double>
    let onCommit: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var usingAlt = false

    private let rows: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]]

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(text.isEmpty ? "—" : text)
                        .font(.system(size: 24, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(CRTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let alt = altUnit {
                        unitChip(unit, selected: !usingAlt) { usingAlt = false }
                        unitChip(alt.label, selected: usingAlt) { usingAlt = true }
                    } else {
                        Text(unit)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(CRTheme.textDim)
                    }
                }
                .frame(height: 28)

                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(row, id: \.self) { key in
                            padKey(key) { tapDigit(key) }
                        }
                    }
                }
                HStack(spacing: 4) {
                    padKey(".") { tapDecimal() }
                        .opacity(allowsDecimal ? 1 : 0)
                        .disabled(!allowsDecimal)
                    padKey("0") { tapDigit("0") }
                    padKey("⌫") { if !text.isEmpty { text.removeLast() } }
                }

                Button(action: commit) {
                    Text("Done")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(CRTheme.bg)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(Capsule().fill(value == nil ? CRTheme.surfaceHi : CRTheme.rosc))
                }
                .buttonStyle(.plain)
                .disabled(value == nil)
            }
            .padding(.horizontal, 2)
        }
        .background(CRTheme.bg)
    }

    private var value: Double? {
        guard let raw = Double(text) else { return nil }
        let v = usingAlt ? raw * (altUnit?.factor ?? 1) : raw
        guard range.contains(v) else { return nil }
        return v
    }

    private func unitChip(_ label: String, selected: Bool,
                          action: @escaping () -> Void) -> some View {
        Button {
            action()
            WatchHaptics.play(.click)
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(selected ? CRTheme.bg : CRTheme.textDim)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(selected ? CRTheme.cpr : CRTheme.surface))
        }
        .buttonStyle(.plain)
    }

    private func tapDigit(_ key: String) {
        guard text.count < 5 else { return }
        text += key
        WatchHaptics.play(.click)
    }

    private func tapDecimal() {
        guard !text.contains("."), !text.isEmpty else { return }
        text += "."
        WatchHaptics.play(.click)
    }

    private func commit() {
        guard let v = value else { return }
        onCommit(v)
        WatchHaptics.play(.success)
        dismiss()
    }

    private func padKey(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(CRTheme.text)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(CRTheme.surface))
        }
        .buttonStyle(.plain)
    }
}

/// Trailing-edge swipe strip. Drag vertically to change the value; drifting
/// the finger LEFT of the strip while dragging divides the rate, so the same
/// gesture is coarse at the edge and fine mid-screen.
struct EdgeAdjustStrip: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double                 // snap quantum (0.1 kg, 1 mo)
    let coarseRatePerPoint: Double   // value change per drag point at the strip

    @State private var lastY: CGFloat?
    @State private var accumulated: Double?
    @State private var dragging = false

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(dragging ? CRTheme.cpr : CRTheme.surfaceHi)
            .frame(width: 13)
            .overlay(
                VStack {
                    Image(systemName: "chevron.up")
                    Spacer()
                    Image(systemName: "chevron.compact.up")
                    Image(systemName: "chevron.compact.down")
                    Spacer()
                    Image(systemName: "chevron.down")
                }
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(dragging ? CRTheme.bg : CRTheme.textDim)
                .padding(.vertical, 6)
            )
            .contentShape(Rectangle().inset(by: -10))
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let dy = g.location.y - (lastY ?? g.location.y)
                        lastY = g.location.y
                        // Points of leftward drift from the strip → finer rate.
                        let drift = Double(max(0, -g.location.x))
                        let rate = coarseRatePerPoint / (1.0 + drift / 26.0)
                        var acc = accumulated ?? value
                        acc -= Double(dy) * rate               // swipe up = increase
                        acc = min(max(acc, range.lowerBound), range.upperBound)
                        accumulated = acc
                        let snapped = (acc / step).rounded() * step
                        if snapped != value {
                            if Int(snapped) != Int(value) { WatchHaptics.play(.click) }
                            value = snapped
                        }
                        dragging = true
                    }
                    .onEnded { _ in
                        lastY = nil
                        accumulated = nil
                        dragging = false
                    }
            )
    }
}
