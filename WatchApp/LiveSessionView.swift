// LiveSessionView.swift — the team lead's instrument.
// Layout: elapsed header → nested rings (CPR cycle outer, drug-interval
// inner) → four radial buttons, color-coded by role:
//   RHYTHM/CODE (red, bottom-left)   — epi, atropine, adenosine, amio, lido.
//   EVENTS (violet, bottom-center)   — rhythm, access→site, airway, comms,
//                                      temp, ROSC (nested, leaf-only logging).
//   VOLUME/SUPPORT (blue, bottom-right) — fluids, dextrose, calcium, bicarb,
//                                      magnesium, naloxone, blood, drip.
//   SHOCK (amber, right of the ring) — tap = next defib energy; hold =
//                                      Defib ladder / Cardiovert.
// Every logged item freezes its own color, so its timer (gutter chip, inner
// ring, timers sheet) reads in the same hue as its button.
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

            // Chips ride EVERY phase — a med given before Start CPR (or
            // after ROSC) keeps its timer visible the moment it's logged.
            Group {
                if engine.roscAchieved {
                    roscBlock(now: now)
                } else if !engine.cprStarted {
                    startCPRBlock
                } else {
                    ringStack(cycleRem: cycleRem, cycleLen: cycleLen, idx: idx,
                              epiRem: epiRem, epiLen: epiLen, epiRunning: epiRunning,
                              epiOverdue: epiOverdue, epiSpec: epiSpec)
                }
            }
            .frame(maxWidth: .infinity)
            // Left column pins to the TOP (clear of the Rhythm/Code puck);
            // the right column tucks into the band between the shock label
            // and the volume anchor — or mirrors the left below RE-ARREST
            // once ROSC hides the shock button (3 + 3).
            .overlay(alignment: .topLeading) {
                medChipColumn(now: now, side: 0)
                    .padding(.top, engine.roscAchieved ? 32 : 2)
            }
            .overlay(alignment: .topTrailing) {
                medChipColumn(now: now, side: 1)
                    .padding(.top, engine.roscAchieved ? 32 : 2)
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

    /// Since-given chips for meds / fluids / shocks, each in ITS OWN color
    /// (red rhythm meds, blue volume, red blood, amber defib) with a ×N dose
    /// count pill between the name and the clock. Slots are assigned in
    /// first-given order and never move: the left gutter takes four, the
    /// next three sit BOTTOM-right — below the shock button, never under it.
    /// A repeat dose bumps its count and resets its clock in place.
    private func medChipColumn(now: Date, side: Int) -> some View {
        let chipCats: Set<EventCategory> = [.medication, .defibrillation, .volume]
        var firstSeen: [String] = []
        var latest: [String: CodeEvent] = [:]
        var counts: [String: Int] = [:]
        for e in engine.session.events where chipCats.contains(e.category) {
            guard let key = e.definitionID else { continue }
            if !firstSeen.contains(key) { firstSeen.append(key) }
            counts[key, default: 0] += 1
            if let seen = latest[key], seen.date > e.date { continue }
            latest[key] = e
        }
        // Six chips max on the main screen. Past that, the STALEST timer
        // (oldest last dose) drops off — epinephrine never does. Everything
        // stays in the Timers sheet regardless.
        var keys = firstSeen
        let epiKey = Defaults.epiID.uuidString
        while keys.count > 6 {
            guard let victim = keys.filter({ $0 != epiKey }).min(by: {
                (latest[$0]?.date ?? .distantPast) < (latest[$1]?.date ?? .distantPast)
            }) else { break }
            keys.removeAll { $0 == victim }
        }
        let leftCount = engine.roscAchieved ? 3 : 4
        var slots = side == 0 ? Array(keys.prefix(leftCount))
                              : Array(keys.dropFirst(leftCount))
        // Right column (with the shock button up top) fills BOTTOM-UP on the
        // same row grid as the left: the 5th chip lines up with the 4th, the
        // 6th with the 3rd — never under the shock bolt or the volume puck.
        var leadingBlanks = 0
        if side == 1, !engine.roscAchieved {
            slots = slots.reversed()
            leadingBlanks = max(0, leftCount - slots.count)
        }
        let align: Alignment = side == 0 ? .leading : .trailing

        return VStack(spacing: 0) {
            ForEach(0..<leadingBlanks, id: \.self) { _ in
                Color.clear.frame(height: 27)
            }
            ForEach(slots, id: \.self) { key in
                if let event = latest[key] {
                    VStack(spacing: 0.5) {
                        HStack(spacing: 2) {
                            Text(crChipAbbreviation(key: key, title: event.title))
                                .font(.system(size: 7, weight: .heavy, design: .rounded))
                                .tracking(0.4)
                                .foregroundStyle(Color(hex: event.tintHex))
                            Text("×\(counts[key] ?? 1)")
                                .font(.system(size: 6.5, weight: .heavy, design: .rounded).monospacedDigit())
                                .foregroundStyle(CRTheme.text)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 0.5)
                                .background(RoundedRectangle(cornerRadius: 3.5).fill(CRTheme.surfaceHi))
                        }
                        Text(crClock(now.timeIntervalSince(event.date)))
                            .font(.system(size: 9.5, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(CRTheme.text)
                    }
                    .frame(maxWidth: .infinity, alignment: align)
                    .frame(height: 27, alignment: .top)   // fixed row grid
                }
            }
        }
        .frame(width: 52)
        .padding(.horizontal, 1)
    }


    private func header(now: Date) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 3) {
                headerButton("list.bullet", tint: CRTheme.textDim) { showLog = true }
                headerButton("timer", tint: CRTheme.textDim) { showTimers = true }
                // Manual pause/resume lives here now — filled violet so it
                // reads as a primary control, green while paused (= resume).
                if engine.cprStarted, !engine.roscAchieved {
                    Button {
                        engine.togglePause(); flashLast()
                    } label: {
                        Image(systemName: engine.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(CRTheme.bg)
                            .frame(width: 19, height: 19)
                            .background(Circle().fill(engine.isPaused ? CRTheme.rosc : CRTheme.cpr))
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 2)

                // Wall clock up top (documentation time), code clock labeled
                // under it. fixedSize keeps both on one line now the pause
                // button shares the top row.
                VStack(spacing: 0) {
                    Text(Self.wallClock.string(from: now))
                        .font(.system(size: 13, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(CRTheme.text)
                    HStack(spacing: 3) {
                        Text("TOTAL")
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .tracking(0.5)
                            .foregroundStyle(CRTheme.textDim)
                        Text(crClock(engine.elapsed(at: now)))
                            .font(.system(size: 10, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(CRTheme.cpr)
                    }
                }
                .lineLimit(1)
                .fixedSize()

                Spacer(minLength: 2)

                headerButton(store.settings.metronomeSoundOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                             tint: store.settings.metronomeSoundOn ? CRTheme.cpr : CRTheme.textDim) {
                    toggleMetronomeSound()
                }
                headerButton("flag.fill", tint: CRTheme.med) { showEndConfirm = true }
            }

            HStack(spacing: 5) {
                // Demo badge pulled from THIS screen at Sebastian's request
                // ("for now", 2026-07-10) — every other screen and the PDF
                // keep it. Cycle count took its slot.
                Text("CYCLE \(engine.cycleIndex(at: now) + 1)")
                    .font(.system(size: 9, weight: .heavy, design: .rounded).monospacedDigit())
                    .tracking(0.5)
                    .foregroundStyle(CRTheme.bg)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(CRTheme.cpr))
                // Tappable: mid-code weight (and protocol, once more exist)
                // corrections without leaving the timer screen.
                Button { showQuickEdit = true } label: {
                    HStack(spacing: 3) {
                        Text(patientLine)
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
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 19, height: 19)
                .background(Circle().fill(CRTheme.surface))
        }
        .buttonStyle(.plain)
    }

    /// Protocol · weight · age — everything the quick-edit sheet can touch.
    private var patientLine: String {
        var line = "\(engine.protocolDef.shortName) · \(engine.session.patient.weightLabel)"
        if let m = engine.session.patient.ageMonths {
            line += m < 24 ? " · \(m)mo" : " · \(m / 12)y"
        }
        return line
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
                    // Two short lines so the label never crosses the rings.
                    Text("NEXT PULSE CHECK")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .tracking(0.5)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(width: 64)
                        .foregroundStyle(checkOverdue ? CRTheme.med : CRTheme.cpr)
                    Text(crClockSigned(cycleRem))
                        .font(.system(size: 25, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(checkOverdue ? CRTheme.med
                                         : (engine.isPaused ? CRTheme.textDim : CRTheme.text))
                    // Nothing epi-related shows until the first dose is real.
                    if epiRunning {
                        Text(epiOverdue ? "\(epiTitle) DUE" : "\(epiTitle) \(crClock(max(0, epiRem)))")
                            .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(epiOverdue ? CRTheme.med : epiColor)
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
                // Bias the block upward: centered-in-safe-area reads LOW on
                // the round-cornered face (big top inset, elements kissing
                // the bottom edge).
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: -14)
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
        // Side anchors ride higher: their two-line labels need clearance
        // from the bottom bezel; the arcs lay themselves out (RadialMenu
        // fits spacing/radius to the screen automatically).
        let sideY = size.height - 46
        let centerY = size.height - 36
        return ZStack {
            // Rhythm / Code — RED, bottom-left. Antiarrhythmics + code meds.
            RadialAnchor(id: "code",
                         center: CGPoint(x: size.width * 0.15, y: sideY),
                         symbol: "syringe.fill", label: "Rhythm/Code",
                         color: CRTheme.med,
                         items: rhythmCodeItems,
                         radius: 84, bounds: size,
                         model: menu, onSelect: select)

            // Events — VIOLET, bottom-center.
            RadialAnchor(id: "events",
                         center: CGPoint(x: size.width * 0.5, y: centerY),
                         symbol: "square.grid.2x2.fill", label: "Events",
                         color: CRTheme.cpr,
                         items: eventsItems,
                         radius: 76, bounds: size,
                         model: menu, onSelect: select)

            // Volume / Support — BLUE, bottom-right.
            RadialAnchor(id: "support",
                         center: CGPoint(x: size.width * 0.85, y: sideY),
                         symbol: "drop.fill", label: "Volume/Support",
                         color: CRTheme.volume,
                         items: supportItems,
                         radius: 84, bounds: size,
                         model: menu, onSelect: select)

            // Shock — YELLOW, upper-right with clear air between it and the
            // ring. Tap = next defib energy; hold = Defib ladder / Cardiovert.
            if engine.cprStarted, !engine.roscAchieved {
                RadialAnchor(id: "shock",
                             center: CGPoint(x: size.width - 23, y: size.height * 0.24),
                             symbol: "bolt.fill", label: "",
                             color: CRTheme.shock,
                             items: shockItems,
                             radius: 62, bounds: size,
                             tapAction: quickShock,
                             model: menu, onSelect: select)
            }
        }
    }

    // MARK: - Menu trees
    // Leaf ids encode the action so ONE selector handles every menu:
    //   drug:<uuid>[#step]  → log that drug (auto ladder or forced rung)
    //   evt:<base>[|detail] → log a catalog event with an optional path
    //   rosc / pause        → engine control
    //   grp:*               → parent, never fires (only expands)

    private func drug(_ id: UUID) -> DrugProfile? {
        engine.drugSet.drugs.first { $0.id == id }
    }
    private var defib: DrugProfile? { drug(Defaults.defibID) }

    private func drugItem(_ id: UUID) -> RadialItem? {
        guard let d = drug(id) else { return nil }
        return RadialItem(id: "drug:\(id.uuidString)", title: d.name,
                          symbol: d.symbol, colorHex: d.colorHex)
    }

    /// Rhythm/Code — 12 o'clock clockwise: epi, atropine, adenosine, amio, lido.
    private func rhythmCodeItems() -> [RadialItem] {
        [Defaults.epiID, Defaults.atropineID, Defaults.adenosineID,
         Defaults.amioID, Defaults.lidocaineID].compactMap(drugItem)
    }

    /// Shock — Defib (weight-based joule ladder) + Cardiovert.
    private func shockItems() -> [RadialItem] {
        var items: [RadialItem] = []
        if let defib {
            let doses = DoseCalculator.doses(for: defib, weightKg: engine.session.patient.weightKg)
            let steps = doses.enumerated().map { i, d in
                RadialItem(id: "drug:\(defib.id.uuidString)#\(i)",
                           title: "\(d.stepLabel) · \(d.amountText)",
                           symbol: "bolt.fill", colorHex: CRTheme.shockHex)
            }
            items.append(RadialItem(id: "grp:defib", title: "Defib", symbol: "bolt.fill",
                                    colorHex: CRTheme.shockHex, children: steps))
        }
        items.append(RadialItem(id: "evt:cardiovert", title: "Cardiovert",
                                symbol: "bolt.heart.fill", colorHex: CRTheme.shockHex))
        return items
    }

    /// Volume/Support — 12 o'clock counter-clockwise: fluids, dextrose,
    /// calcium, bicarb, more. The array is REVERSED because arcs assign
    /// index 0 to their lowest angle; for the right-side anchor the last
    /// element lands at 12 o'clock and earlier ones sweep counter-clockwise.
    private func supportItems() -> [RadialItem] {
        let blue = CRTheme.volumeHex
        var fluidKids: [RadialItem] = [
            RadialItem(id: "evt:blood", title: "Blood",
                       symbol: "drop.fill", colorHex: blue,
                       iconColorHex: CRTheme.medHex)
        ]
        if let f = drug(Defaults.fluidsID) {
            for (i, d) in DoseCalculator.doses(for: f, weightKg: engine.session.patient.weightKg).enumerated() {
                fluidKids.append(RadialItem(id: "drug:\(f.id.uuidString)#\(i)",
                                            title: d.stepLabel, symbol: "drop.fill", colorHex: blue))
            }
        }
        var more: [RadialItem] = [
            RadialItem(id: "evt:drip", title: "Drip", symbol: "ivfluid.bag", colorHex: blue)
        ]
        more.append(contentsOf: [Defaults.magnesiumID, Defaults.naloxoneID].compactMap(drugItem))

        var items: [RadialItem] = [
            RadialItem(id: "grp:fluids", title: "Fluids", symbol: "drop.fill",
                       colorHex: blue, children: fluidKids)
        ]
        items.append(contentsOf: [Defaults.dextroseID, Defaults.calciumID, Defaults.bicarbID].compactMap(drugItem))
        items.append(RadialItem(id: "grp:more", title: "More", symbol: "ellipsis",
                                colorHex: blue, children: more))
        return items.reversed()
    }

    private let commsServices = ["Surgery", "Anesthesia", "ECMO", "Consult"]

    private func tempParent() -> RadialItem {
        let teal = CRTheme.careHex
        let devices = ["Bair Hugger", "Arctic Sun", "Warm blankets"]
        let syms = ["wind", "snowflake", "square.stack.3d.up.fill"]
        let kids = zip(devices, syms).map { name, sym in
            RadialItem(id: "evt:temp|\(name)", title: name, symbol: sym, colorHex: teal)
        }
        return RadialItem(id: "grp:temp", title: "Temp", symbol: "thermometer.medium",
                          colorHex: teal, children: kids)
    }

    /// Events — left to right: Rhythm, Access, Airway, Comms, Temp, ROSC.
    private func eventsItems() -> [RadialItem] {
        if engine.roscAchieved { return roscEventsItems() }
        let access = CRTheme.accessHex, airway = CRTheme.airwayHex, comms = CRTheme.commsHex
        var items: [RadialItem] = []

        items.append(RadialItem(id: "evt:rhythm", title: "Rhythm",
                                symbol: "waveform.path.ecg", colorHex: CRTheme.rhythmHex))

        // Access → IV / IO / Art line, logged as-is: the site lives in the
        // chart, not the watch (Sebastian: no need to track limbs here).
        items.append(RadialItem(id: "grp:access", title: "Access",
                                symbol: "cross.circle.fill", colorHex: access, children: [
            RadialItem(id: "evt:access.iv", title: "IV", symbol: "cross.vial.fill", colorHex: access),
            RadialItem(id: "evt:access.io", title: "IO", symbol: "target", colorHex: access),
            RadialItem(id: "evt:access.art", title: "Art line", symbol: "waveform.path", colorHex: access)
        ]))

        // Airway → intubation / bag / mask / trach
        items.append(RadialItem(id: "grp:airway", title: "Airway",
                                symbol: "lungs.fill", colorHex: airway, children: [
            RadialItem(id: "evt:airway.ett", title: "Intubation", symbol: "lungs.fill", colorHex: airway),
            RadialItem(id: "evt:airway.bag", title: "Bag", symbol: "text:BVM", colorHex: airway),
            RadialItem(id: "evt:airway.mask", title: "Mask", symbol: "facemask.fill", colorHex: airway),
            RadialItem(id: "evt:airway.trach", title: "Trach", symbol: "text:TRACH", colorHex: airway)
        ]))

        // Comms → Call / Arrival → service (two levels deep)
        func services(_ base: String, _ sym: String) -> [RadialItem] {
            commsServices.map { RadialItem(id: "evt:\(base)|\($0)", title: $0, symbol: sym, colorHex: comms) }
        }
        items.append(RadialItem(id: "grp:comms", title: "Comms",
                                symbol: "person.2.wave.2.fill", colorHex: comms, children: [
            RadialItem(id: "grp:call", title: "Call", symbol: "phone.fill", colorHex: comms, children: services("comms.call", "phone.fill")),
            RadialItem(id: "grp:arrival", title: "Arrival", symbol: "figure.walk.arrival", colorHex: comms, children: services("comms.arrival", "figure.walk"))
        ]))

        items.append(tempParent())
        items.append(RadialItem(id: "rosc", title: "ROSC", symbol: "heart.fill", colorHex: CRTheme.roscHex))

        // Custom events (phone-built) ride along at the end.
        items.append(contentsOf: engine.eventDefs.filter { $0.category == .custom }.map {
            RadialItem(id: "evt:\($0.id)", title: $0.title, symbol: $0.symbol, colorHex: $0.category.colorHex)
        })
        return items
    }

    /// Post-ROSC bloom: reassessment-oriented set.
    private func roscEventsItems() -> [RadialItem] {
        let blue = CRTheme.volumeHex
        return [
            RadialItem(id: "evt:rhythm", title: "Rhythm", symbol: "waveform.path.ecg", colorHex: CRTheme.rhythmHex),
            RadialItem(id: "evt:12lead", title: "12-lead", symbol: "waveform.path.ecg.rectangle", colorHex: CRTheme.rhythmHex),
            RadialItem(id: "evt:drip", title: "Drip", symbol: "ivfluid.bag", colorHex: blue),
            RadialItem(id: "evt:blood", title: "Blood", symbol: "drop.fill", colorHex: blue,
                       iconColorHex: CRTheme.medHex),
            tempParent()
        ]
    }

    // MARK: - Catalog + unified selection

    private struct EvtMeta { let title: String; let category: EventCategory; let colorHex: String }

    /// Maps an event base id → what to log. Detail (limb, service, device)
    /// rides in the leaf id after "|".
    private var eventCatalog: [String: EvtMeta] {
        [
            "rhythm":         .init(title: "Rhythm check", category: .rhythm, colorHex: CRTheme.rhythmHex),
            "12lead":         .init(title: "12-lead ECG", category: .rhythm, colorHex: CRTheme.rhythmHex),
            "access.iv":      .init(title: "IV access", category: .access, colorHex: CRTheme.accessHex),
            "access.io":      .init(title: "IO access", category: .access, colorHex: CRTheme.accessHex),
            "access.art":     .init(title: "Arterial line", category: .access, colorHex: CRTheme.accessHex),
            "airway.ett":     .init(title: "Intubation", category: .airway, colorHex: CRTheme.airwayHex),
            "airway.bag":     .init(title: "Bag-mask", category: .airway, colorHex: CRTheme.airwayHex),
            "airway.mask":    .init(title: "Mask", category: .airway, colorHex: CRTheme.airwayHex),
            "airway.trach":   .init(title: "Trach", category: .airway, colorHex: CRTheme.airwayHex),
            "comms.call":     .init(title: "Call", category: .comms, colorHex: CRTheme.commsHex),
            "comms.arrival":  .init(title: "Arrival", category: .comms, colorHex: CRTheme.commsHex),
            "temp":           .init(title: "Temp mgmt", category: .care, colorHex: CRTheme.careHex),
            "blood":          .init(title: "Blood given", category: .volume, colorHex: CRTheme.medHex),
            "drip":           .init(title: "Drip started", category: .volume, colorHex: CRTheme.volumeHex),
            "cardiovert":     .init(title: "Cardioversion", category: .defibrillation, colorHex: CRTheme.shockHex)
        ]
    }

    private func quickShock() {
        guard let defib else { return }
        engine.logDrug(defib)
        WatchHaptics.play(.success)
        flashLast()
    }

    /// The one handler every anchor uses.
    private func select(_ item: RadialItem) {
        let id = item.id
        if id == "pause" { engine.togglePause(); flashLast(); return }
        if id == "rosc" { engine.markROSC(); flashLast(); return }

        if id.hasPrefix("drug:") {
            let body = id.dropFirst(5)
            let parts = body.split(separator: "#", maxSplits: 1)
            guard let uuid = UUID(uuidString: String(parts[0])), let d = drug(uuid) else { return }
            let step = parts.count > 1 ? Int(parts[1]) : nil
            engine.logDrug(d, forcedStepIndex: step)
            flashLast()
            return
        }

        if id.hasPrefix("evt:") {
            let segs = id.dropFirst(4).split(separator: "|", maxSplits: 1).map(String.init)
            let base = segs[0]
            let detail = segs.count > 1 ? segs[1] : nil
            if let meta = eventCatalog[base] {
                engine.logEvent(title: meta.title, detail: detail, category: meta.category,
                                definitionID: base, colorHex: meta.colorHex)
            } else if let def = engine.eventDefs.first(where: { $0.id == base }) {
                engine.logEvent(title: def.title, detail: detail, category: def.category,
                                definitionID: def.id, colorHex: def.category.colorHex)
            }
            flashLast()
            return
        }
        // grp:* parents only expand — nothing to fire.
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
