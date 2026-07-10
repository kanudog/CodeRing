// LiveSessionView.swift — the team lead's instrument.
// Layout: elapsed header → nested rings (CPR cycle outer, EPI inner) →
// hint line → three radial anchors along the bottom:
//   SHOCK (left, amber)  — TAP logs the next energy step instantly;
//                          HOLD blooms the explicit 2 J/kg / 4 J/kg arc.
//   EVENTS (center, violet) — hold/tap bloom: pause-resume, rhythm, access
//                          (nested sites, skippable), airway, ROSC, customs.
//   MEDS (right, red)    — bloom of the drug set; release logs with the
//                          computed dose snapshot (mL featured).
// TimelineView drives the clock; the engine holds anchor dates (no drift).

import SwiftUI
import CodeCore

struct LiveSessionView: View {

    let engine: SessionEngine
    let onEnded: (CodeSession) -> Void

    private let store = CodeStore.shared
    @State private var menu = RadialMenuModel()
    @State private var metronome = ToneMetronome()
    @State private var showEndConfirm = false
    @State private var showLog = false
    @State private var showTimers = false
    @State private var showHandoff = false
    @State private var showQuickEdit = false
    @State private var lastLogged: String?

    /// 24 h wall clock (H:mm:ss) — codes are documented in clock time.
    private static let wallClock: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "H:mm:ss"
        return df
    }()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CRTheme.bg.ignoresSafeArea()

                TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                    mainContent(now: ctx.date)
                }
                // Reclaim the enormous top inset: only the corner clock lives
                // up there, and the header row stays left/center of it.
                .ignoresSafeArea(edges: .top)

                anchors(size: geo.size)

                if let msg = lastLogged {
                    Text(msg)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(CRTheme.rosc)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(CRTheme.surfaceHi))
                        .position(x: geo.size.width / 2, y: geo.size.height - 76)
                        .transition(.opacity)
                }

                RadialMenuOverlay(model: menu)

                // Modal by design: hands-off time owns the whole screen.
                if engine.isInPulseCheck {
                    pulseCheckOverlay
                }
            }
            .coordinateSpace(name: "live")
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            WatchHaptics.enabled = store.settings.hapticsEnabled
            // Keep-screen-awake: extended runtime session + Always-On support
            // (see ScreenAwake.swift for the full mechanism).
            if store.settings.keepScreenOn { ScreenAwakeManager.shared.begin() }
            startMetronomeIfNeeded()
        }
        .onDisappear {
            metronome.stop()
            ScreenAwakeManager.shared.end()
        }
        .onChange(of: engine.isPaused) { _, paused in
            if paused { metronome.stop() } else { startMetronomeIfNeeded() }
        }
        .onChange(of: engine.isInPulseCheck) { _, checking in
            if checking { metronome.stop() } else { startMetronomeIfNeeded() }
        }
        .onChange(of: engine.roscAchieved) { _, rosc in
            if rosc { metronome.stop() } else { startMetronomeIfNeeded() }   // re-arrest
        }
        .sheet(isPresented: $showLog) {
            EventLogView(events: engine.session.events)
        }
        .sheet(isPresented: $showTimers) {
            TimersView(engine: engine)
        }
        .sheet(isPresented: $showHandoff) {
            HandoffView(engine: engine)
        }
        .sheet(isPresented: $showQuickEdit) {
            QuickEditSheet(engine: engine) { flashLast() }
        }
        .confirmationDialog("End code?", isPresented: $showEndConfirm) {
            Button("End & review", role: .destructive) {
                metronome.stop()
                let finished = engine.end()
                onEnded(finished)
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    // MARK: - Main column

    private func mainContent(now: Date) -> some View {
        let cycleLen = engine.protocolDef.cycleSpec?.seconds ?? 120
        let cycleRem = engine.cycleRemaining(at: now)
        let idx = engine.cycleIndex(at: now)
        let epiSpec = engine.protocolDef.intervalSpecs.first
        let epiLen = epiSpec?.seconds ?? 180
        let epiRunning = epiSpec.map { engine.intervalIsRunning($0) } ?? false
        let epiRem = epiSpec.map { engine.intervalRemaining($0, at: now) } ?? 0
        let epiOverdue = epiSpec.map { engine.intervalIsOverdue($0, at: now) } ?? false
            && !engine.roscAchieved

        return VStack(spacing: 2) {
            header(now: now)

            if engine.roscAchieved {
                roscBlock(now: now)
            } else if !engine.cprStarted {
                startCPRBlock
            } else {
                ringStack(cycleRem: cycleRem, cycleLen: cycleLen, idx: idx,
                          epiRem: epiRem, epiLen: epiLen, epiRunning: epiRunning,
                          epiOverdue: epiOverdue, epiSpec: epiSpec)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .leading) { cycleTag(idx) }
                    .overlay(alignment: .trailing) { medChips(now: now) }
            }

            Spacer(minLength: 48)   // anchor zone
        }
        .padding(.horizontal, 6)
        .padding(.top, 26)   // just under the corner clock's baseline
        // Top-anchored: a centered column overflows both ends on the small
        // watch — empty band up top, anchors clipped below.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: idx) { old, new in
            // Cycle closed = the swap-compressors moment.
            if new > old, !engine.isPaused, !engine.roscAchieved {
                WatchHaptics.play(store.settings.hapticCycleComplete)
            }
        }
        .onChange(of: cycleRem <= 0) { old, due in
            if due, !old, engine.cprStarted, !engine.roscAchieved {
                WatchHaptics.play(store.settings.hapticPulseCheckDue)
            }
        }
        .onChange(of: epiOverdue) { old, new in
            if new, !old { WatchHaptics.play(store.settings.hapticMedDue) }
        }
    }

    /// Pre-compression state: the ring sits full behind one giant button.
    /// The code clock is already running (GO); this starts the CPR cycle.
    private var startCPRBlock: some View {
        ZStack {
            RingGauge(progress: 1, color: CRTheme.cpr, lineWidth: 8, overdue: false)
                .frame(width: 112, height: 112)
            Button {
                engine.startCPR()
                WatchHaptics.play(.start)
                startMetronomeIfNeeded()
                flashLast()
            } label: {
                VStack(spacing: 1) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CRTheme.cpr)
                    Text("START CPR")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(CRTheme.text)
                    Text("when compressions begin")
                        .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(CRTheme.textDim)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 92)
            }
            .buttonStyle(.plain)
        }
    }

    /// Repeatable meds ride the right gutter: abbreviation + time since the
    /// last dose, colored like the drug. Newest three, most recent on top.
    private func medChips(now: Date) -> some View {
        var latest: [String: CodeEvent] = [:]
        for e in engine.session.events where e.category == .medication {
            guard let key = e.definitionID else { continue }
            if let seen = latest[key], seen.date > e.date { continue }
            latest[key] = e
        }
        let rows = latest.values.sorted { $0.date > $1.date }.prefix(3)
        return VStack(alignment: .trailing, spacing: 5) {
            ForEach(Array(rows), id: \.id) { event in
                let drug = engine.drugSet.drugs.first { $0.id.uuidString == event.definitionID }
                let tint = drug.map { Color(hex: $0.colorHex) } ?? CRTheme.med
                VStack(alignment: .trailing, spacing: 0) {
                    Text(String((drug?.name ?? event.title).prefix(4)).uppercased())
                        .font(.system(size: 7, weight: .heavy, design: .rounded))
                        .tracking(0.4)
                        .foregroundStyle(tint)
                    Text(crClock(now.timeIntervalSince(event.date)))
                        .font(.system(size: 10, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(CRTheme.text)
                }
            }
        }
        .padding(.trailing, 1)
    }

    private func header(now: Date) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 4) {
                headerButton("list.bullet", tint: CRTheme.textDim) { showLog = true }
                headerButton("timer", tint: CRTheme.textDim) { showTimers = true }

                Spacer(minLength: 2)

                // Wall clock up top (documentation time), code clock labeled under it.
                VStack(spacing: 0) {
                    Text(Self.wallClock.string(from: now))
                        .font(.system(size: 14, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(CRTheme.text)
                    HStack(spacing: 3) {
                        Text("TOTAL CODE")
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .tracking(0.5)
                            .foregroundStyle(CRTheme.textDim)
                        Text(crClock(engine.elapsed(at: now)))
                            .font(.system(size: 10, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(CRTheme.cpr)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }

                Spacer(minLength: 2)

                headerButton(store.settings.metronomeSoundOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                             tint: store.settings.metronomeSoundOn ? CRTheme.cpr : CRTheme.textDim) {
                    toggleMetronomeSound()
                }
                headerButton("flag.fill", tint: CRTheme.med) { showEndConfirm = true }
            }

            HStack(spacing: 5) {
                DemoBadge(compact: true)
                // Tappable: mid-code weight (and protocol, once more exist)
                // corrections without leaving the timer screen.
                Button { showQuickEdit = true } label: {
                    HStack(spacing: 3) {
                        Text("\(engine.protocolDef.shortName) · \(engine.session.patient.weightLabel)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(CRTheme.textDim)
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(CRTheme.textDim.opacity(0.7))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func headerButton(_ symbol: String, tint: Color,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(Circle().fill(CRTheme.surface))
        }
        .buttonStyle(.plain)
    }

    /// Cycle counter lives beside the ring so the center text can breathe.
    private func cycleTag(_ idx: Int) -> some View {
        VStack(spacing: 0) {
            Text("CYCLE")
                .font(.system(size: 7, weight: .heavy, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(CRTheme.textDim)
            Text("\(idx + 1)")
                .font(.system(size: 20, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(CRTheme.cpr)
        }
        .padding(.leading, 2)
    }

    private func ringStack(cycleRem: TimeInterval, cycleLen: TimeInterval, idx: Int,
                           epiRem: TimeInterval, epiLen: TimeInterval,
                           epiRunning: Bool, epiOverdue: Bool,
                           epiSpec: TimerSpec?) -> some View {
        let checkOverdue = cycleRem <= 0
        let checkDue = cycleRem <= 15 && !engine.isPaused && !engine.roscAchieved
        let epiTitle = epiSpec?.title ?? "EPI"
        // Inner ring wears the linked DRUG's color (phone-editable), so the
        // ring, its countdown text, and the med chips all match.
        let epiDrug = engine.drugSet.drugs.first { $0.id == epiSpec?.linkedDrugID }
        let epiColor = epiDrug.map { Color(hex: $0.colorHex) }
            ?? epiSpec.map { Color(hex: $0.colorHex) } ?? CRTheme.med

        return ZStack {
            RingGauge(progress: max(0, cycleRem) / max(1, cycleLen),
                      color: CRTheme.cpr, lineWidth: 8, overdue: checkOverdue)
                .frame(width: 112, height: 112)

            // No countdown for a med nobody has given: the inner ring only
            // appears once the first dose starts its clock.
            if epiRunning {
                RingGauge(progress: max(0, epiRem) / max(1, epiLen),
                          color: epiColor, lineWidth: 5, overdue: epiOverdue)
                    .frame(width: 86, height: 86)
            }

            // The ring's center doubles as the pulse-check button once a
            // check is due — a huge target well clear of the anchors' touch
            // zones at the bottom (their gesture owns anything down there).
            Button {
                guard checkDue else { return }
                engine.beginPulseCheck()
                WatchHaptics.play(.notification)
            } label: {
                VStack(spacing: 0) {
                    Text("NEXT PULSE CHECK")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(checkOverdue ? CRTheme.med : CRTheme.cpr)
                    Text(crClockSigned(cycleRem))
                        .font(.system(size: 25, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(checkOverdue ? CRTheme.med
                                         : (engine.isPaused ? CRTheme.textDim : CRTheme.text))
                    if epiRunning {
                        Text(epiOverdue ? "\(epiTitle) DUE" : "\(epiTitle) \(crClock(max(0, epiRem)))")
                            .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(epiOverdue ? CRTheme.med : epiColor)
                    } else {
                        Text("\(epiTitle) —")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(CRTheme.textDim.opacity(0.6))
                    }
                    if checkDue {
                        Text("TAP — PULSE CHECK")
                            .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                            .tracking(0.4)
                            .foregroundStyle(CRTheme.bg)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(checkOverdue ? CRTheme.med : CRTheme.cpr))
                            .padding(.top, 2)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 92)
            }
            .buttonStyle(.plain)
            // no .disabled here — it grays the countdown; the action guards
            .opacity(engine.isPaused ? 0.45 : 1)

            if engine.isPaused {
                Text("PAUSED")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(CRTheme.bg)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(CRTheme.shock))
            }
        }
        .opacity(engine.isPaused ? 0.85 : 1)
    }

    /// Full-screen hands-off mode: a fresh check clock that goes red past the
    /// 10-second target, and the only two exits a pulse check has.
    private var pulseCheckOverlay: some View {
        ZStack {
            CRTheme.bg.ignoresSafeArea()   // fully opaque — nothing competes
            TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                let t = engine.pulseCheckElapsed(at: ctx.date)
                let over = t >= 10
                VStack(spacing: 4) {
                    Text("PULSE CHECK")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(CRTheme.cpr)
                    Text(crClock(t))
                        .font(.system(size: 34, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(over ? CRTheme.med : CRTheme.text)
                    Text(over ? "over 10 s — resume compressions" : "hands off — check pulse & rhythm")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(over ? CRTheme.med : CRTheme.textDim)

                    // Two big circular targets, side by side — tappable
                    // without looking, icons under the words.
                    HStack(spacing: 16) {
                        checkExitButton(title: "RESUME CPR", color: CRTheme.cpr) {
                            Image(systemName: "figure.mixed.cardio")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(CRTheme.bg)
                        } action: {
                            engine.completePulseCheck(pulseFound: false)
                            WatchHaptics.play(.success)
                        }

                        checkExitButton(title: "PULSE FOUND", color: CRTheme.rosc) {
                            ZStack {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(CRTheme.bg)
                                Image(systemName: "waveform.path.ecg")
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundStyle(CRTheme.rosc)
                            }
                        } action: {
                            engine.completePulseCheck(pulseFound: true)
                            WatchHaptics.play(.success)
                        }
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 10)
                .onChange(of: over) { _, o in
                    if o { WatchHaptics.play(.retry) }
                }
            }
        }
    }

    /// One circular pulse-check exit: colored disc with the icon, label under.
    private func checkExitButton<Icon: View>(title: String, color: Color,
                                             @ViewBuilder icon: () -> Icon,
                                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack {
                    Circle().fill(color)
                    icon()
                }
                .frame(width: 62, height: 62)
                Text(title)
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(0.4)
                    .foregroundStyle(color)
            }
        }
        .buttonStyle(.plain)
    }

    // Post-ROSC block: RE-ARREST is the escape hatch back into the CPR flow,
    // HANDOFF is the phone-call card, and the ring carries the vitals cadence.
    private func roscBlock(now: Date) -> some View {
        let vitalsRem = engine.vitalsRemaining(at: now)
        let vitalsLen = engine.protocolDef.vitalsSpec?.seconds ?? 300
        let overdue = (vitalsRem ?? 1) <= 0
        let due = (vitalsRem ?? 1) <= 15

        return VStack(spacing: 3) {
            HStack(spacing: 5) {
                Button {
                    engine.reArrest()
                    WatchHaptics.play(.retry)
                    flashLast()
                } label: {
                    Text("RE-ARREST")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(CRTheme.bg)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background(Capsule().fill(CRTheme.med))
                }
                .buttonStyle(.plain)

                Button { showHandoff = true } label: {
                    Text("HANDOFF")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(CRTheme.rosc)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Capsule().fill(CRTheme.surfaceHi))
                }
                .buttonStyle(.plain)
            }

            ZStack {
                RingGauge(progress: max(0, vitalsRem ?? 0) / max(1, vitalsLen),
                          color: CRTheme.rosc, lineWidth: 8, overdue: overdue)
                    .frame(width: 92, height: 92)

                Button {
                    guard due else { return }
                    engine.confirmVitals()
                    WatchHaptics.play(.success)
                    flashLast()
                } label: {
                    VStack(spacing: 0) {
                        Text("ROSC \(crClock(engine.roscElapsed(at: now)))")
                            .font(.system(size: 9, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(CRTheme.rosc)
                        if let rem = vitalsRem {
                            Text("NEXT VITALS")
                                .font(.system(size: 7.5, weight: .heavy, design: .rounded))
                                .tracking(0.5)
                                .foregroundStyle(overdue ? CRTheme.med : CRTheme.textDim)
                            Text(crClockSigned(rem))
                                .font(.system(size: 21, weight: .heavy, design: .rounded).monospacedDigit())
                                .foregroundStyle(overdue ? CRTheme.med : CRTheme.text)
                            if due {
                                Text("TAP — VITALS")
                                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                                    .foregroundStyle(CRTheme.bg)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(overdue ? CRTheme.med : CRTheme.rosc))
                                    .padding(.top, 2)
                            }
                        } else {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(CRTheme.rosc)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(width: 78)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Anchors

    private func anchors(size: CGSize) -> some View {
        let y = size.height - 36   // high enough that labels never clip the bezel
        return ZStack {
            RadialAnchor(id: "shock",
                         center: CGPoint(x: size.width * 0.16, y: y),
                         symbol: "bolt.fill", label: "Shock", color: CRTheme.shock,
                         items: shockItems,
                         arcStart: -78, arcEnd: -14, radius: 62,
                         tapAction: quickShock,
                         model: menu, onSelect: selectShock)

            RadialAnchor(id: "events",
                         center: CGPoint(x: size.width * 0.5, y: y),
                         symbol: "square.grid.2x2.fill", label: "Events", color: CRTheme.cpr,
                         items: eventsItems,
                         arcStart: -168, arcEnd: -12, radius: 74,
                         model: menu, onSelect: selectEvent)

            RadialAnchor(id: "meds",
                         center: CGPoint(x: size.width * 0.84, y: y),
                         symbol: "syringe.fill", label: "Meds", color: CRTheme.med,
                         items: medItems,
                         arcStart: -176, arcEnd: -82, radius: 84,
                         model: menu, onSelect: selectMed)
        }
    }

    // MARK: - Item builders

    private var defib: DrugProfile? {
        engine.drugSet.drugs.first { $0.unit == .joulesPerKg }
    }

    /// SHOCK bloom hierarchy per Sebastian: Defib (weight-based joule ladder
    /// as children), then sync cardioversion and pacing as sibling leaves.
    private func shockItems() -> [RadialItem] {
        var items: [RadialItem] = []
        if let defib {
            let doses = DoseCalculator.doses(for: defib, weightKg: engine.session.patient.weightKg)
            let steps = doses.enumerated().map { i, d in
                RadialItem(id: "shock.\(i)",
                           title: "\(d.stepLabel) · \(d.amountText)",
                           symbol: "bolt.fill",
                           color: CRTheme.shock)
            }
            items.append(RadialItem(id: "shock.defib", title: "Defib",
                                    symbol: "bolt.fill", color: CRTheme.shock,
                                    children: steps))
        }
        if let sync = engine.eventDefs.first(where: { $0.id == "shock.sync" }) {
            items.append(item(for: sync))
        }
        if let pace = engine.eventDefs.first(where: { $0.id == "shock.pace" }) {
            items.append(item(for: pace))
        }
        return items
    }

    private func medItems() -> [RadialItem] {
        var items = engine.drugSet.drugs
            .filter { $0.unit == .mgPerKg }
            .map { d in
                RadialItem(id: d.id.uuidString, title: d.name,
                           symbol: d.symbol, color: Color(hex: d.colorHex))
            }
        if items.count > 5 {
            let rest = Array(items.dropFirst(4))
            items = Array(items.prefix(4))
            items.append(RadialItem(id: "more.meds", title: "More",
                                    symbol: "ellipsis", color: CRTheme.textDim,
                                    children: rest))
        }
        return items
    }

    private func item(for def: EventDefinition) -> RadialItem {
        let children: [RadialItem]? = def.subOptions.isEmpty ? nil :
            def.subOptions.map {
                RadialItem(id: "\(def.id)|\($0)", title: $0,
                           symbol: def.symbol, color: def.category.color)
            }
        return RadialItem(id: def.id, title: def.title, symbol: def.symbol,
                          color: def.category.color, children: children)
    }

    /// In ROSC the bloom swaps to the post-resuscitation care set
    /// ("rosc."-prefixed built-ins) plus rhythm checks and customs.
    private func roscEventsItems() -> [RadialItem] {
        var items: [RadialItem] = []
        if let rc = engine.eventDefs.first(where: { $0.id == "rhythm.check" }) {
            items.append(item(for: rc))
        }
        items.append(contentsOf: engine.eventDefs
            .filter { $0.id.hasPrefix("rosc.") }
            .map(item(for:)))
        // Blood and temperature management stay reachable after ROSC too.
        for id in ["med.blood", "temp.mgmt"] {
            if let def = engine.eventDefs.first(where: { $0.id == id }) {
                items.append(item(for: def))
            }
        }
        items.append(contentsOf: engine.eventDefs
            .filter { $0.category == .custom }
            .map(item(for:)))
        if items.count > 6 {
            let rest = Array(items.dropFirst(5))
            items = Array(items.prefix(5))
            items.append(RadialItem(id: "more.events", title: "More",
                                    symbol: "ellipsis", color: CRTheme.textDim,
                                    children: rest))
        }
        return items
    }

    private func eventsItems() -> [RadialItem] {
        if engine.roscAchieved { return roscEventsItems() }

        var items: [RadialItem] = [
            RadialItem(id: "cpr.toggle",
                       title: engine.isPaused ? "Resume CPR" : "Pause CPR",
                       symbol: engine.isPaused ? "play.fill" : "pause.fill",
                       color: CRTheme.cpr)
        ]

        // Every def renders itself — subOptions (access limbs, temp devices)
        // become the child arc automatically.
        for id in engine.protocolDef.eventIDs {
            guard let def = engine.eventDefs.first(where: { $0.id == id }) else { continue }
            items.append(item(for: def))
        }

        let customs = engine.eventDefs.filter { $0.category == .custom }
        items.append(contentsOf: customs.map(item(for:)))

        if items.count > 6 {
            let rest = Array(items.dropFirst(5))
            items = Array(items.prefix(5))
            items.append(RadialItem(id: "more.events", title: "More",
                                    symbol: "ellipsis", color: CRTheme.textDim,
                                    children: rest))
        }
        return items
    }

    // MARK: - Selection handlers

    private func selectMed(_ item: RadialItem) {
        if item.id == "more.meds" { return }
        guard let drug = engine.drugSet.drugs.first(where: { $0.id.uuidString == item.id })
        else { return }
        engine.logDrug(drug)
        flashLast()
    }

    private func quickShock() {
        guard let defib else { return }
        engine.logDrug(defib)
        WatchHaptics.play(.success)
        flashLast()
    }

    private func selectShock(_ item: RadialItem) {
        // Sync cardioversion / pacing are event leaves, not defib doses.
        if item.id == "shock.sync" || item.id == "shock.pace" {
            guard let def = engine.eventDefs.first(where: { $0.id == item.id }) else { return }
            engine.logEvent(def)
            flashLast()
            return
        }
        guard let defib,
              let stepIndex = Int(item.id.split(separator: ".").last.map(String.init) ?? "")
        else { return }
        engine.logDrug(defib, forcedStepIndex: stepIndex)
        flashLast()
    }

    private func selectEvent(_ item: RadialItem) {
        if item.id == "more.events" { return }

        if item.id == "cpr.toggle" {
            engine.togglePause()
            flashLast()
            return
        }
        // Parents ("access.group", "more.*") never fire anymore — the menu
        // only selects leaves — so no generic-access fallback exists.
        if item.id.contains("|") {
            let parts = item.id.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let def = engine.eventDefs.first(where: { $0.id == parts[0] })
            else { return }
            engine.logEvent(def, subOption: parts[1])
            flashLast()
            return
        }
        guard let def = engine.eventDefs.first(where: { $0.id == item.id }) else { return }
        engine.logEvent(def)
        flashLast()
    }

    // MARK: - Helpers

    private func flashLast() {
        let text = engine.session.events.last.map { ev in
            ev.detail.map { "\(ev.title) — \($0)" } ?? ev.title
        } ?? "Logged"
        withAnimation { lastLogged = text }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation { if lastLogged == text { lastLogged = nil } }
        }
    }

    private func startMetronomeIfNeeded() {
        // No beat before compressions start — the metronome IS the CPR rate.
        guard engine.cprStarted, !engine.isPaused, !engine.isInPulseCheck,
              !engine.roscAchieved, !engine.isEnded else { return }
        metronome.start(bpm: store.settings.metronomeBPM,
                        soundOn: store.settings.metronomeSoundOn,
                        pitch: store.settings.metronomePitch)
    }

    private func toggleMetronomeSound() {
        var s = store.settings
        s.metronomeSoundOn.toggle()
        store.updateSettings(s)
        metronome.stop()
        startMetronomeIfNeeded()
        WatchHaptics.play(.click)
    }
}

// MARK: - Mid-code quick edit

/// Weight (and someday protocol) corrections without leaving the timer.
/// Weight changes recompute every dose-derived number instantly and land
/// in the timeline; the protocol list is ready for future algorithms.
private struct QuickEditSheet: View {
    let engine: SessionEngine
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showWeightPad = false

    var body: some View {
        List {
            Button { showWeightPad = true } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("WEIGHT")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .tracking(0.6)
                            .foregroundStyle(CRTheme.airway)
                        Text(engine.session.patient.weightLabel)
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(CRTheme.text)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(CRTheme.textDim)
                }
            }
            .listRowBackground(RoundedRectangle(cornerRadius: 10).fill(CRTheme.surface))

            Section {
                ForEach(Defaults.protocols) { proto in
                    HStack {
                        Text(proto.name)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(CRTheme.text)
                        Spacer()
                        if proto.id == engine.protocolDef.id {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(CRTheme.rosc)
                        }
                    }
                    .listRowBackground(RoundedRectangle(cornerRadius: 10).fill(CRTheme.surface))
                }
            } header: {
                Text("PROTOCOL")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(CRTheme.med)
            } footer: {
                Text("Doses and shock energies follow the weight instantly. More algorithms coming — switching mid-code will land here.")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(CRTheme.textDim)
            }
        }
        .navigationTitle("Adjust")
        .sheet(isPresented: $showWeightPad) {
            NumberPadSheet(unit: "kg", allowsDecimal: true, range: 1...150) { kg in
                engine.updateWeight(kg)
                onChanged()
                dismiss()
            }
        }
    }
}
