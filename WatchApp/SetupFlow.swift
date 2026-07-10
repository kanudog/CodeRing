// SetupFlow.swift — code type → weight → confirm → GO.
// Weight has three toggleable modes: manual kg (Digital Crown), Broselow
// color wheel (tap a wedge), age estimate (crown, APLS formula).
// GO constructs the SessionEngine with the effective protocol (user timer
// overrides applied) and the active drug set.

import SwiftUI
import CodeCore

struct SetupFlowView: View {

    let onLaunch: (SessionEngine) -> Void

    private enum Step { case protocolPick, weight, confirm }

    private let store = CodeStore.shared
    @State private var step: Step = .protocolPick
    @State private var protocolDef: CodeProtocolDefinition = Defaults.palsArrest
    @State private var weightMode: WeightSource = .manual
    @State private var manualKg: Double = 10
    @State private var broselowZone: BroselowZone?
    @State private var ageMonths: Double = 24
    @State private var showKeypad = false
    @State private var showInputHelp = false
    /// Optional age set on the confirm screen (age-mode weight fills it in).
    @State private var confirmAgeMonths: Int?
    @State private var showAgePad = false
    /// Protocol chip on confirm jumps to the picker; picking returns HERE,
    /// not back through the weight flow.
    @State private var returnToConfirm = false

    var body: some View {
        Group {
            switch step {
            case .protocolPick: protocolPage
            case .weight: weightPage
            case .confirm: confirmPage
            }
        }
        .background(CRTheme.bg)
        .navigationBarBackButtonHidden(step != .protocolPick)
        // The system title bar ate vertical space and overlapped the weight
        // chips — everything past the first step draws its own compact header.
        .toolbar(step == .protocolPick ? .visible : .hidden, for: .navigationBar)
    }

    // MARK: - Step 1: code type

    private var protocolPage: some View {
        ScrollView {
            VStack(spacing: 8) {
                eyebrow("CODE TYPE")
                ForEach(Defaults.protocols) { proto in
                    Button {
                        protocolDef = proto
                        WatchHaptics.play(.click)
                        // Last-minute protocol change from Confirm goes
                        // straight back — never back through weight entry.
                        step = returnToConfirm ? .confirm : .weight
                        returnToConfirm = false
                    } label: {
                        HStack {
                            Image(systemName: proto.symbol)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(CRTheme.med)
                                .frame(width: 24)
                            Text(proto.name)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(CRTheme.text)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(CRTheme.textDim)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 52)
                        .background(RoundedRectangle(cornerRadius: 14).fill(CRTheme.surface))
                    }
                    .buttonStyle(.plain)
                }
                DemoBadge(compact: true)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("New Code")
    }

    // MARK: - Step 2: weight

    private var weightPage: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                backChevron { step = .protocolPick }
                modeChip("kg", .manual)
                modeChip("Broselow", .broselow)
                modeChip("Age", .ageEstimate)
            }

            switch weightMode {
            case .manual: manualEntry
            case .broselow: BroselowWheel(selected: $broselowZone)
            case .ageEstimate: ageEntry
            }

            Button {
                WatchHaptics.play(.click)
                step = .confirm
            } label: {
                Text("Next")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(CRTheme.bg)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(Capsule().fill(nextEnabled ? CRTheme.cpr : CRTheme.surfaceHi))
            }
            .buttonStyle(.plain)
            .disabled(!nextEnabled)
        }
        .padding(.horizontal, 4)
        .padding(.top, 24)   // clear of the always-on system clock
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $showKeypad) {
            if weightMode == .ageEstimate {
                NumberPadSheet(unit: "mo", allowsDecimal: false, range: 0...216) {
                    ageMonths = $0
                }
            } else {
                NumberPadSheet(unit: "kg", allowsDecimal: true, range: 1...150) {
                    manualKg = $0
                }
            }
        }
        .sheet(isPresented: $showInputHelp) { InputHelpSheet() }
    }

    /// The input-methods hint line with its ⓘ — tap for the full explainer.
    private func inputMethodsHint(_ text: String) -> some View {
        HStack(spacing: 3) {
            Button { showInputHelp = true } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CRTheme.airway)
            }
            .buttonStyle(.plain)
            Text(text)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(CRTheme.textDim)
        }
    }

    private var nextEnabled: Bool {
        weightMode != .broselow || broselowZone != nil
    }

    private var manualEntry: some View {
        HStack(spacing: 6) {
            VStack(spacing: 2) {
                Spacer(minLength: 4)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(String(format: "%.1f", manualKg))
                        .font(.system(size: 46, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(CRTheme.text)
                    Text("kg")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(CRTheme.textDim)
                }
                inputMethodsHint("crown · edge strip · tap to type")
                Spacer(minLength: 4)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { showKeypad = true }

            EdgeAdjustStrip(value: $manualKg, range: 1...150,
                            step: 0.1, coarseRatePerPoint: 0.45)
        }
        .focusable()
        .digitalCrownRotation($manualKg, from: 1, through: 150, by: 0.5,
                              sensitivity: .medium, isContinuous: false,
                              isHapticFeedbackEnabled: true)
    }

    private var ageEntry: some View {
        HStack(spacing: 6) {
            VStack(spacing: 2) {
                Spacer(minLength: 4)
                Text(ageLabel)
                    .font(.system(size: 34, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(CRTheme.text)
                Text("≈ \(String(format: "%.1f", WeightEstimator.weightKg(forAgeMonths: Int(ageMonths)))) kg")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(CRTheme.airway)
                inputMethodsHint("APLS · crown · strip · tap")
                Spacer(minLength: 4)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { showKeypad = true }

            EdgeAdjustStrip(value: $ageMonths, range: 0...216,
                            step: 1, coarseRatePerPoint: 1.2)
        }
        .focusable()
        .digitalCrownRotation($ageMonths, from: 0, through: 216, by: 1,
                              sensitivity: .medium, isContinuous: false,
                              isHapticFeedbackEnabled: true)
    }

    private var ageLabel: String {
        let m = Int(ageMonths)
        return m < 24 ? "\(m) mo" : "\(m / 12) yr \(m % 12) mo"
    }

    // MARK: - Step 3: confirm + GO
    // One screen, nothing scrolls: GO is the bullseye, the three editable
    // facts orbit it as tappable chips. Protocol returns straight here;
    // age is optional (auto-filled when weight came from age).

    private var confirmPage: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2 + 2)
            let orbit = min(geo.size.width, geo.size.height) * 0.37

            ZStack {
                VStack {
                    HStack(spacing: 4) {
                        backChevron { step = .weight }
                        eyebrow("CONFIRM")
                        Spacer()
                    }
                    Spacer()
                    DemoBadge(compact: true)
                }
                .padding(.horizontal, 4)

                confirmChip("PROTOCOL", protocolDef.shortName, CRTheme.med) {
                    returnToConfirm = true
                    step = .protocolPick
                }
                .position(orbitPoint(center, orbit, angleDeg: -135))

                confirmChip("WEIGHT", String(format: "%.1f kg", resolvedKg), CRTheme.airway) {
                    step = .weight
                }
                .position(orbitPoint(center, orbit, angleDeg: -45))

                // Optional: italic "tap" until set, so the record can carry
                // an age without ever blocking the GO.
                confirmChip("AGE", resolvedAgeLabel, CRTheme.access,
                            italicValue: resolvedAgeMonths == nil) {
                    showAgePad = true
                }
                // tucked between GO and the demo badge — the badge is a
                // permanent fixture and never gets covered
                .position(orbitPoint(center, orbit * 0.88, angleDeg: 96))

                Button(action: launch) {
                    ZStack {
                        Circle().fill(CRTheme.rosc)
                        Text("GO")
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .tracking(2)
                            .foregroundStyle(CRTheme.bg)
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 78, height: 78)
                .position(center)
            }
        }
        .sheet(isPresented: $showAgePad) {
            NumberPadSheet(unit: "mo", allowsDecimal: false, range: 0...216) {
                confirmAgeMonths = Int($0)
            }
        }
    }

    /// Age shown on the confirm chip: explicit entry wins, then age-mode's
    /// estimate; nil = not provided (chip shows the italic "tap" prompt).
    private var resolvedAgeMonths: Int? {
        confirmAgeMonths ?? (weightMode == .ageEstimate ? Int(ageMonths) : nil)
    }

    private var resolvedAgeLabel: String {
        guard let m = resolvedAgeMonths else { return "tap" }
        return m < 24 ? "\(m) mo" : "\(m / 12) yr \(m % 12) mo"
    }

    private func orbitPoint(_ center: CGPoint, _ radius: CGFloat, angleDeg: Double) -> CGPoint {
        let a = angleDeg * .pi / 180
        return CGPoint(x: center.x + radius * CGFloat(cos(a)),
                       y: center.y + radius * CGFloat(sin(a)))
    }

    private func confirmChip(_ label: String, _ value: String, _ tint: Color,
                             italicValue: Bool = false,
                             action: @escaping () -> Void) -> some View {
        Button {
            action()
            WatchHaptics.play(.click)
        } label: {
            VStack(spacing: 1) {
                Text(label)
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(tint)
                Text(value)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .italic(italicValue)
                    .foregroundStyle(italicValue ? CRTheme.textDim : CRTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(CRTheme.surface))
            .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var resolvedKg: Double {
        switch weightMode {
        case .manual: return manualKg
        case .broselow: return broselowZone?.midKg ?? manualKg
        case .ageEstimate: return WeightEstimator.weightKg(forAgeMonths: Int(ageMonths))
        }
    }

    private func launch() {
        let proto = store.effectiveProtocol(protocolDef)
        let drugs = store.activeDrugSet(for: proto)
        let patient = PatientContext(weightKg: resolvedKg,
                                     weightSource: weightMode,
                                     broselowZoneID: broselowZone?.id,
                                     ageMonths: resolvedAgeMonths,
                                     sex: .unspecified)
        let engine = SessionEngine(protocolDef: proto,
                                   drugSet: drugs,
                                   eventDefs: store.allEventDefs,
                                   patient: patient,
                                   deviceName: "Apple Watch")
        WatchHaptics.play(.success)
        onLaunch(engine)
    }

    // MARK: - Bits

    private func modeChip(_ title: String, _ mode: WeightSource) -> some View {
        Button {
            weightMode = mode
            WatchHaptics.play(.click)
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(weightMode == mode ? CRTheme.bg : CRTheme.textDim)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(Capsule().fill(weightMode == mode ? CRTheme.cpr : CRTheme.surface))
        }
        .buttonStyle(.plain)
    }

    private func backChevron(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(CRTheme.textDim)
                .frame(width: 24, height: 24)
                .background(Circle().fill(CRTheme.surface))
        }
        .buttonStyle(.plain)
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .tracking(1.2)
            .foregroundStyle(CRTheme.textDim)
    }

}

// MARK: - Input help

/// The ⓘ explainer for the three weight/age input methods — mostly here to
/// teach the edge strip's distance-based sensitivity.
private struct InputHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                helpRow(symbol: "digitalcrown.horizontal.press",
                        title: "Crown",
                        text: "Turn the Digital Crown for steady, stepped changes.")
                helpRow(symbol: "hand.draw.fill",
                        title: "Edge strip",
                        text: "Swipe up or down on the bar at the right edge. On the bar, moves are big and fast. Keep swiping while sliding your finger LEFT, away from the bar — the further from the edge, the finer the adjustment.")
                helpRow(symbol: "hand.tap.fill",
                        title: "Tap to type",
                        text: "Tap the big number to type an exact value on the keypad.")

                Button { dismiss() } label: {
                    Text("Close")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(CRTheme.bg)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(Capsule().fill(CRTheme.cpr))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.horizontal, 6)
        }
        .background(CRTheme.bg)
        .navigationTitle("Adjusting values")
    }

    private func helpRow(symbol: String, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(CRTheme.airway)
            Text(text)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(CRTheme.text)
        }
    }
}

// MARK: - Broselow wheel

/// Donut of the 9 Broselow zones. Tap a wedge; center shows the pick.
/// Each wedge carries its kg range so the color alone never has to be recalled.
struct BroselowWheel: View {
    @Binding var selected: BroselowZone?

    private let zones = BroselowZone.zones
    private let size: CGFloat = 148

    var body: some View {
        ZStack {
            ForEach(Array(zones.enumerated()), id: \.element.id) { i, zone in
                let start = Angle.degrees(-90 + Double(i) * 40 + 1)
                let end = Angle.degrees(-90 + Double(i + 1) * 40 - 1)
                let isSel = selected?.id == zone.id
                SectorShape(startAngle: start, endAngle: end, innerRatio: 0.58)
                    .fill(Color(hex: zone.colorHex).opacity(isSel ? 1.0 : 0.75))
                    .overlay(
                        SectorShape(startAngle: start, endAngle: end, innerRatio: 0.58)
                            .stroke(isSel ? Color.white : Color.clear, lineWidth: 2)
                    )
                    .contentShape(SectorShape(startAngle: start, endAngle: end, innerRatio: 0.58))
                    .onTapGesture {
                        selected = zone
                        WatchHaptics.play(.click)
                    }
            }

            // kg-range labels ride the middle of each wedge's band.
            ForEach(Array(zones.enumerated()), id: \.element.id) { i, zone in
                let mid = (-90 + (Double(i) + 0.5) * 40) * .pi / 180
                Text(zone.rangeLabel)
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .foregroundStyle(labelColor(onHex: zone.colorHex))
                    .position(x: size / 2 + CGFloat(cos(mid)) * size * 0.395,
                              y: size / 2 + CGFloat(sin(mid)) * size * 0.395)
                    .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                Text(selected?.name ?? "Tap a")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(CRTheme.text)
                Text(selected.map { String(format: "%.1f kg", $0.midKg) } ?? "color")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(CRTheme.textDim)
            }
        }
        .frame(width: size, height: size)
        .frame(maxWidth: .infinity)
    }

    /// Dark ink on bright zones (yellow/white), light ink on dark ones —
    /// both ends pulled from the theme, not literals.
    private func labelColor(onHex hex: String) -> Color {
        var v: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF), g = Double((v >> 8) & 0xFF), b = Double(v & 0xFF)
        let luma = (0.299 * r + 0.587 * g + 0.114 * b) / 255
        return luma > 0.6 ? Color(hex: CRTheme.bgHex) : Color(hex: CRTheme.textHex)
    }
}

struct SectorShape: Shape {
    let startAngle: Angle
    let endAngle: Angle
    let innerRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let rOut = min(rect.width, rect.height) / 2
        let rIn = rOut * innerRatio
        var p = Path()
        p.addArc(center: center, radius: rOut,
                 startAngle: startAngle, endAngle: endAngle, clockwise: false)
        p.addArc(center: center, radius: rIn,
                 startAngle: endAngle, endAngle: startAngle, clockwise: true)
        p.closeSubpath()
        return p
    }
}
