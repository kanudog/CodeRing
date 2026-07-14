// SharedUI.swift — small SwiftUI pieces both apps use.
// DemoBadge appears on every top-level screen. Non-negotiable.

import SwiftUI

/// Renders an item symbol: an SF Symbol name, or "text:XX" for typographic
/// icons (element abbreviations like Ca / Mg / HCO₃) in the same weight
/// family so they read as siblings of the glyphs.
public struct CRIconView: View {
    let symbol: String
    let size: CGFloat

    public init(symbol: String, size: CGFloat = 15) {
        self.symbol = symbol
        self.size = size
    }

    public var body: some View {
        if symbol.hasPrefix("text:") {
            Text(symbol.dropFirst(5))
                .font(.system(size: size * 0.8, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        } else {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
        }
    }
}

public struct DemoBadge: View {
    var compact: Bool

    public init(compact: Bool = false) {
        self.compact = compact
    }

    public var body: some View {
        Text(compact ? "DEMO" : "DEMO · NOT FOR CLINICAL USE")
            .font(.system(size: compact ? 9 : 11, weight: .heavy, design: .rounded))
            .tracking(1.0)
            .foregroundStyle(CRTheme.demo)
            .padding(.horizontal, compact ? 6 : 10)
            .padding(.vertical, compact ? 2 : 4)
            .background(
                Capsule().strokeBorder(CRTheme.demo.opacity(0.55), lineWidth: 1)
            )
            .accessibilityLabel("Demo. Not for clinical use.")
    }
}

/// Circular countdown gauge. progress = fraction REMAINING (1 → full ring).
public struct RingGauge: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat
    var overdue: Bool

    public init(progress: Double, color: Color, lineWidth: CGFloat = 8, overdue: Bool = false) {
        self.progress = progress
        self.color = color
        self.lineWidth = lineWidth
        self.overdue = overdue
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(CRTheme.ringTrack, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.003, min(1, progress)))
                .stroke(overdue ? CRTheme.med : color,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: progress)
        }
    }
}

/// Label-over-value tile used by summary/detail screens.
public struct StatTile: View {
    var label: String
    var value: String
    var color: Color

    public init(label: String, value: String, color: Color = CRTheme.text) {
        self.label = label; self.value = value; self.color = color
    }

    public var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(CRTheme.textDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(CRTheme.surface))
    }
}
