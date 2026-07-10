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
            startMetronomeIfNeeded()
        }
        .onDisappear { metronome.stop() }
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
        let epiRem = epiSpec.map { engine.intervalRemaining($0, at: now) } ?? 0
        let epiOverdue = epiSpec != nil && epiRem <= 0 && !engine.roscAchieved

        return VStack(spacing: 2) {
            header(now: now)

            if engine.roscAchieved {
                roscBlock(now: now)
            } else {
                ringStack(cycleRem: cycleRem, cycleLen: cycleLen, idx: idx,
                          epiRem: epiRem, epiLen: epiLen, epiOverdue: epiOverdue,
                          epiTitle: epiSpec?.title ?? "EPI")
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .leading) { cycleTag(idx) }
            }

            Spacer(minLength: 48)   // anchor zone
        }
        .padding(.horizontal, 6)
        .padding(.top, 26)   // just under the corner clock's baseline
        // Top-anchored: a centered column overflows both ends on the small
        // watch — empty band up top, anchors clipped below.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: idx) { old, new in
            if new > old, !engine.isPaused, !engine.roscAchieved {
                WatchHaptics.play(.notification)
            }
        }
        .onChange(of: cycleRem <= 0) { old, due in
            if due, !old, !engine.roscAchieved { WatchHaptics.play(.retry) }
        }
        .onChange(of: epiOverdue) { old, new in
            if new, !old { WatchHaptics.play(.retry) }
        }
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
                Text("\(engine.protocolDef.shortName) · \(engine.session.patient.weightLabel)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(CRTheme.textDim)
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
                           epiOverdue: Bool, epiTitle: String) -> some View {
        let checkOverdue = cycleRem <= 0
        let checkDue = cycleRem <= 15 && !engine.isPaused && !engine.roscAchieved
        return ZStack {
            RingGauge(progress: max(0, cycleRem) / max(1, cycleLen),
                      color: CRTheme.cpr, lineWidth: 8, overdue: checkOverdue)
                .frame(width: 112, height: 112)

            RingGauge(progress: max(0, epiRem) / max(1, epiLen),
                      color: CRTheme.med, lineWidth: 5, overdue: epiOverdue)
                .frame(width: 86, height: 86)

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
                    Text(epiOverdue ? "\(epiTitle) DUE" : "\(epiTitle) \(crClock(max(0, epiRem)))")
                        .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(epiOverdue ? CRTheme.med : CRTheme.textDim)
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

                    Button {
                        engine.completePulseCheck(pulseFound: false)
                        WatchHaptics.play(.success)
                    } label: {
                        Text("RESUME CPR")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(CRTheme.bg)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(Capsule().fill(CRTheme.cpr))
                    }
                    .buttonStyle(.plain)

                    Button {
                        engine.completePulseCheck(pulseFound: true)
                        WatchHaptics.play(.success)
                    } label: {
                        Text("PULSE FOUND")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(CRTheme.bg)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(Capsule().fill(CRTheme.rosc))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .onChange(of: over) { _, o in
                    if o { WatchHaptics.play(.retry) }
                }
            }
        }
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

    private func shockItems() -> [RadialItem] {
        guard let defib else { return [] }
        let doses = DoseCalculator.doses(for: defib, weightKg: engine.session.patient.weightKg)
        return doses.enumerated().map { i, d in
            RadialItem(id: "shock.\(i)",
                       title: "\(d.stepLabel) · \(d.amountText)",
                       symbol: "bolt.fill",
                       color: CRTheme.shock)
        }
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

        for id in engine.protocolDef.eventIDs {
            guard let def = engine.eventDefs.first(where: { $0.id == id }) else { continue }
            if id == "access.iv" {
                // Group IV + IO under one skippable "Access" parent.
                var children: [RadialItem] = []
                if let iv = engine.eventDefs.first(where: { $0.id == "access.iv" }) {
                    children.append(item(for: iv))
                }
                if let io = engine.eventDefs.first(where: { $0.id == "access.io" }) {
                    children.append(item(for: io))
                }
                items.append(RadialItem(id: "access.group", title: "Access",
                                        symbol: "cross.circle.fill",
                                        color: CRTheme.access, children: children))
            } else if id == "access.io" {
                continue
            } else {
                items.append(item(for: def))
            }
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
        guard let defib else { return }
        let stepIndex = Int(item.id.split(separator: ".").last.map(String.init) ?? "")
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
        guard !engine.isPaused, !engine.isInPulseCheck,
              !engine.roscAchieved, !engine.isEnded else { return }
        metronome.start(bpm: store.settings.metronomeBPM,
                        soundOn: store.settings.metronomeSoundOn)
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
