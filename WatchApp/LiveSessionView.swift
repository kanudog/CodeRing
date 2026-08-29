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
    /// Tints the toast red instead of green — a miss must not read as a win.
    @State private var loggedWasMiss = false

    /// 24 h wall clock (H:mm:ss) — codes are documented in clock time.
    private static let wallClock: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "H:mm:ss"
        return df
    }()

    var body: some View {
        GeometryReader { full in
            ZStack(alignment: .topLeading) {
                CRTheme.bg

                // Hand-placed chrome, in raw screen points.
                TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                    chrome(now: ctx.date)
                }

                // The radial layer keeps the INSET space its top-arc fans
                // were tuned in (194 × 191 at 2, 51). Folding it into the
                // chrome's screen space would move every fan.
                GeometryReader { live in
                    ZStack {
                        anchors(size: live.size)
                        RadialMenuOverlay(model: menu)
                            .onChange(of: menu.missedAt) { _, new in
                                guard new != nil else { return }
                                flashMessage("Nothing logged", isMiss: true)
                            }
                    }
                    .coordinateSpace(name: "live")
                }
                .padding(.horizontal, WatchLayout.liveInset.x)
                .padding(.top, WatchLayout.liveInset.y)

                if let msg = lastLogged {
                    Text(msg)
                        .font(.system(size: WatchLayout.toast.font, weight: .bold, design: .rounded))
                        .foregroundStyle(loggedWasMiss ? CRTheme.med : CRTheme.rosc)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(CRTheme.surfaceHi))
                        .position(WatchLayout.toast.center)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                // Modal by design: hands-off time owns the whole screen.
                if engine.isInPulseCheck {
                    pulseCheckOverlay
                }
            }
            .frame(width: full.size.width, height: full.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
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
            EventLogView(events: engine.session.events, engine: engine)
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

    // MARK: - Hand-placed chrome
    //
    // The live screen is positioned from `WatchLayout` in SCREEN points
    // rather than stacked. Stacking was the root of a whole family of bugs:
    // a sibling appearing (the pause button, the drug countdown line) resized
    // its container and silently re-centred everything around it. Sebastian
    // placed every element by hand in the Layout Bench on 2026-08-24; these
    // are his coordinates, and nothing may re-flow them.

    private func chrome(now: Date) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear.allowsHitTesting(false)
            if engine.roscAchieved { roscStack(now: now) }
            else { centreStack(now: now) }
            // Chips ride EVERY phase — a med given before Start CPR or after
            // ROSC keeps its timer visible the moment it is logged.
            chipsLayer(now: now)
            headerLayer(now: now)
        }
        .frame(width: WatchLayout.screen.width,
               height: WatchLayout.screen.height, alignment: .topLeading)
    }

    // MARK: Placement helpers

    /// Text inside a fixed box: it scales down to fit rather than pushing
    /// neighbours around, which is what keeps hand-placed positions honest.
    private func placed(_ spec: WatchLayout.Label, _ text: String,
                        weight: Font.Weight = .heavy, mono: Bool = false,
                        color: Color, lines: Int = 1) -> some View {
        let base = Font.system(size: spec.font, weight: weight, design: .rounded)
        return Text(text)
            .font(mono ? base.monospacedDigit() : base)
            .tracking(0.3)
            .foregroundStyle(color)
            .lineLimit(lines)
            .minimumScaleFactor(0.5)
            .multilineTextAlignment(.center)
            .frame(width: spec.size.width, height: spec.size.height)
            .position(spec.center)
            // Decoration must never absorb a touch. The tap glyph sitting on
            // top of the ring button is exactly how START CPR stopped working.
            .allowsHitTesting(false)
    }

    private func ringView(_ spec: WatchLayout.Ring, progress: Double,
                          color: Color, overdue: Bool) -> some View {
        RingGauge(progress: progress, color: color,
                  lineWidth: spec.stroke, overdue: overdue)
            .frame(width: spec.diameter, height: spec.diameter)
            .position(spec.center)
            .allowsHitTesting(false)
    }

    private func discButton(_ spec: WatchLayout.Disc, symbol: String,
                            fill: Color, tint: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(fill)
                Image(systemName: symbol)
                    .font(.system(size: spec.glyph * 0.62, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: spec.diameter, height: spec.diameter)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .position(spec.center)
    }

    // MARK: Centre stack

    @ViewBuilder
    private func centreStack(now: Date) -> some View {
        let cycleLen = engine.protocolDef.cycleSpec?.seconds ?? 120
        let cycleRem = engine.cycleRemaining(at: now)
        let epiSpec = engine.protocolDef.intervalSpecs.first
        let epiLen = epiSpec?.seconds ?? 180
        let epiRunning = epiSpec.map { engine.intervalIsRunning($0) } ?? false
        let epiRem = epiSpec.map { engine.intervalRemaining($0, at: now) } ?? 0
        let epiOverdue = (epiSpec.map { engine.intervalIsOverdue($0, at: now) } ?? false)
        let epiTitle = epiSpec?.title ?? "EPI"
        let epiDrug = engine.drugSet.drugs.first { $0.id == epiSpec?.linkedDrugID }
        let epiColor = epiDrug.map { Color(hex: $0.colorHex) }
            ?? epiSpec.map { Color(hex: $0.colorHex) } ?? CRTheme.med
        let overdue = cycleRem <= 0
        let due = cycleRem <= 15 && !engine.isPaused

        ringView(WatchLayout.cprRing,
                 progress: max(0, cycleRem) / max(1, cycleLen),
                 color: CRTheme.cpr, overdue: overdue)

        if epiRunning {
            ringView(WatchLayout.drugRing,
                     progress: max(0, epiRem) / max(1, epiLen),
                     color: epiColor, overdue: epiOverdue)
        }

        // One target filling the ring. Before compressions it starts CPR;
        // once running it is the pulse-check button (guarded, so an early
        // tap does nothing rather than skipping the cycle).
        Button {
            if engine.cprStarted {
                guard due || overdue else { return }
                engine.beginPulseCheck()
                WatchHaptics.play(.notification)
            } else {
                engine.startCPR()
                WatchHaptics.play(.start)
                startMetronomeIfNeeded()
                flashLast()
            }
        } label: {
            Circle().fill(Color.clear).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: WatchLayout.cprRing.diameter, height: WatchLayout.cprRing.diameter)
        .position(WatchLayout.cprRing.center)

        if engine.cprStarted {
            placed(WatchLayout.pulseLabel, "NEXT PULSE CHECK",
                   color: overdue ? CRTheme.med : CRTheme.cpr)
            placed(WatchLayout.countdown, crClockSigned(cycleRem), mono: true,
                   color: overdue ? CRTheme.med
                                  : (engine.isPaused ? CRTheme.textDim : CRTheme.text))
            if epiRunning {
                placed(WatchLayout.drugLine,
                       epiOverdue ? "\(epiTitle) DUE" : "\(epiTitle) \(crClock(max(0, epiRem)))",
                       weight: .bold, mono: true,
                       color: epiOverdue ? CRTheme.med : epiColor)
            }
            if engine.isPaused {
                // Dead centre of the ring (Sebastian, 2026-08-24) — it used
                // to sit wherever the stack happened to put it.
                Text("PAUSED")
                    .font(.system(size: WatchLayout.pausedText.font, weight: .heavy, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(CRTheme.bg)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(CRTheme.shock))
                    .position(WatchLayout.pausedText.center)
                    .allowsHitTesting(false)
            }
        } else {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: WatchLayout.tapGlyph.glyph, weight: .bold))
                .foregroundStyle(CRTheme.cpr)
                .position(WatchLayout.tapGlyph.center)
                .allowsHitTesting(false)
            placed(WatchLayout.startText, "START CPR", color: CRTheme.text)
        }
    }

    // MARK: Med timer chips

    /// Drugs/fluids/shocks that have been given, newest-first per key, capped
    /// at the number of hand-placed chip slots. The STALEST timer drops off
    /// when there are more; epinephrine never does. Everything stays in the
    /// Timers sheet regardless.
    private func chipSlots() -> [(key: String, event: CodeEvent, count: Int)] {
        let cats: Set<EventCategory> = [.medication, .defibrillation, .volume]
        var firstSeen: [String] = []
        var latest: [String: CodeEvent] = [:]
        var counts: [String: Int] = [:]
        for e in engine.session.events where cats.contains(e.category) {
            guard let key = e.definitionID else { continue }
            if !firstSeen.contains(key) { firstSeen.append(key) }
            counts[key, default: 0] += 1
            if let seen = latest[key], seen.date > e.date { continue }
            latest[key] = e
        }
        var keys = firstSeen
        let epiKey = Defaults.epiID.uuidString
        while keys.count > WatchLayout.chips.count {
            guard let victim = keys.filter({ $0 != epiKey }).min(by: {
                (latest[$0]?.date ?? .distantPast) < (latest[$1]?.date ?? .distantPast)
            }) else { break }
            keys.removeAll { $0 == victim }
        }
        return keys.compactMap { k in
            latest[k].map { (key: k, event: $0, count: counts[k] ?? 1) }
        }
    }

    private func chipsLayer(now: Date) -> some View {
        let slots = chipSlots()
        return ForEach(Array(slots.enumerated()), id: \.element.key) { i, slot in
            if i < WatchLayout.chips.count {
                chipView(WatchLayout.chips[i], slot: slot, now: now)
            }
        }
    }

    private func chipView(_ spec: WatchLayout.Chip,
                          slot: (key: String, event: CodeEvent, count: Int),
                          now: Date) -> some View {
        VStack(alignment: spec.trailing ? .trailing : .leading, spacing: 0.5) {
            HStack(spacing: 2) {
                Text(crChipAbbreviation(key: slot.key, title: slot.event.title))
                    .font(.system(size: spec.nameFont, weight: .heavy, design: .rounded))
                    .tracking(0.4)
                    .foregroundStyle(Color(hex: slot.event.tintHex))
                Text("×\(slot.count)")
                    .font(.system(size: WatchLayout.chipCountFont, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(CRTheme.text)
                    .padding(.horizontal, 3).padding(.vertical, 0.5)
                    .background(RoundedRectangle(cornerRadius: 3.5).fill(CRTheme.surfaceHi))
            }
            Text(crClock(now.timeIntervalSince(slot.event.date)))
                .font(.system(size: WatchLayout.chipTimerFont, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(CRTheme.text)
        }
        .frame(width: spec.size.width, height: spec.size.height,
               alignment: spec.trailing ? .topTrailing : .topLeading)
        .position(x: spec.origin.x + spec.size.width / 2,
                  y: spec.origin.y + spec.size.height / 2)
        .allowsHitTesting(false)
    }

    // MARK: Header controls and clocks

    @ViewBuilder
    private func headerLayer(now: Date) -> some View {
        discButton(WatchLayout.logButton, symbol: "list.bullet",
                   fill: CRTheme.surface, tint: CRTheme.textDim) { showLog = true }
        discButton(WatchLayout.timersButton, symbol: "timer",
                   fill: CRTheme.surface, tint: CRTheme.textDim) { showTimers = true }
        discButton(WatchLayout.muteButton,
                   symbol: store.settings.metronomeSoundOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                   fill: CRTheme.surface,
                   tint: store.settings.metronomeSoundOn ? CRTheme.cpr : CRTheme.textDim) {
            toggleMetronomeSound()
        }
        discButton(WatchLayout.flagButton, symbol: "flag.fill",
                   fill: CRTheme.surface, tint: CRTheme.med) { showEndConfirm = true }

        if engine.cprStarted, !engine.roscAchieved {
            discButton(WatchLayout.pauseButton,
                       symbol: engine.isPaused ? "play.fill" : "pause.fill",
                       fill: engine.isPaused ? CRTheme.rosc : CRTheme.pause,
                       tint: CRTheme.bg) { engine.togglePause(); flashLast() }
        }

        placed(WatchLayout.totalLabel, "TOTAL", color: CRTheme.textDim)
        placed(WatchLayout.codeClock, crClock(engine.elapsed(at: now)),
               mono: true, color: CRTheme.cpr)

        if !engine.roscAchieved {
            Text("CYCLE \(engine.cycleIndex(at: now) + 1)")
                .font(.system(size: WatchLayout.cycleChip.font, weight: .heavy, design: .rounded).monospacedDigit())
                .tracking(0.5)
                .foregroundStyle(CRTheme.bg)
                .padding(.horizontal, 6).padding(.vertical, 1.5)
                .background(Capsule().fill(CRTheme.cpr))
                .position(WatchLayout.cycleChip.center)
                .allowsHitTesting(false)
        }

        // Patient strip. Text and pencil are ONE centred row: placing the
        // pencil at a fixed x made it drift away from text of a different
        // width (a 3-digit weight, an age suffix).
        Button { showQuickEdit = true } label: {
            HStack(spacing: 4) {
                Text(patientLine)
                    .font(.system(size: WatchLayout.patient.font, weight: .bold, design: .rounded))
                    .foregroundStyle(CRTheme.textDim)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: WatchLayout.editPencilGlyph, weight: .semibold))
                    .foregroundStyle(CRTheme.textDim.opacity(0.7))
            }
            .frame(width: WatchLayout.patient.size.width,
                   height: WatchLayout.patient.size.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .position(WatchLayout.patient.center)
    }

    /// Protocol · weight · age — everything the quick-edit sheet can touch.
    private var patientLine: String {
        var line = "\(engine.protocolDef.shortName) · \(engine.session.patient.weightLabel)"
        if let m = engine.session.patient.ageMonths {
            line += " · \(m < 24 ? "\(m) mo" : "\(m / 12) y")"
        }
        return line
    }

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

    // MARK: - Post-ROSC
    //
    // Hand-placed like every other state (WatchLayout). Shared chrome — the
    // header, patient strip, clocks, pucks and med chips — is drawn by the
    // same code paths at the same coordinates, so nothing shifts when the
    // outcome changes. Only the centre stack differs, plus RE-ARREST and
    // HANDOFF, which take the slots the pause button and shock bolt vacate.

    @ViewBuilder
    private func roscStack(now: Date) -> some View {
        let vitalsRem = engine.vitalsRemaining(at: now)
        let vitalsLen = engine.protocolDef.vitalsSpec?.seconds ?? 300
        let overdue = (vitalsRem ?? 1) <= 0
        let due = (vitalsRem ?? 1) <= 15

        ringView(WatchLayout.vitalsRing,
                 progress: max(0, vitalsRem ?? 0) / max(1, vitalsLen),
                 color: CRTheme.rosc, overdue: overdue)

        // The ring doubles as the vitals-confirmed target, exactly as the CPR
        // ring is the pulse-check target.
        Button {
            guard due else { return }
            engine.confirmVitals()
            WatchHaptics.play(.success)
            flashLast()
        } label: {
            Circle().fill(Color.clear).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: WatchLayout.vitalsRing.diameter, height: WatchLayout.vitalsRing.diameter)
        .position(WatchLayout.vitalsRing.center)

        placed(WatchLayout.roscElapsed, "ROSC \(crClock(engine.roscElapsed(at: now)))",
               mono: true, color: CRTheme.rosc)

        if let rem = vitalsRem {
            placed(WatchLayout.vitalsLabel, "NEXT VITALS",
                   color: overdue ? CRTheme.med : CRTheme.textDim)
            placed(WatchLayout.vitalsCount, crClockSigned(rem), mono: true,
                   color: overdue ? CRTheme.med : CRTheme.text)
            if due {
                Text("TAP — VITALS")
                    .font(.system(size: WatchLayout.vitalsPrompt.font, weight: .heavy, design: .rounded))
                    .foregroundStyle(CRTheme.bg)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(overdue ? CRTheme.med : CRTheme.rosc))
                    .position(WatchLayout.vitalsPrompt.center)
                    .allowsHitTesting(false)
            }
        } else {
            Image(systemName: "heart.fill")
                .font(.system(size: WatchLayout.roscHeart.glyph, weight: .bold))
                .foregroundStyle(CRTheme.rosc)
                .position(WatchLayout.roscHeart.center)
                .allowsHitTesting(false)
        }

        capsuleButton(WatchLayout.reArrest, "RE-ARREST",
                      fill: CRTheme.med, tint: CRTheme.bg) {
            engine.reArrest(); WatchHaptics.play(.retry); flashLast()
        }
        capsuleButton(WatchLayout.handoff, "HANDOFF",
                      fill: CRTheme.surfaceHi, tint: CRTheme.rosc) {
            showHandoff = true
        }
    }

    /// A pill-shaped control placed by its centre, like `discButton`.
    private func capsuleButton(_ spec: WatchLayout.Label, _ title: String,
                               fill: Color, tint: Color,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: spec.font, weight: .heavy, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: spec.size.width, height: spec.size.height)
                .background(Capsule().fill(fill))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .position(spec.center)
    }

    // MARK: - Anchors

    private func anchors(size: CGSize) -> some View {
        // Icon-only pucks (captions retired, Sebastian 2026-07-23) ride low —
        // the freed band above them is what lets four chip rows fit. Side
        // pucks stay a touch higher than the center one for the display's
        // corner curve; the arcs lay themselves out (RadialMenu fits
        // spacing/radius to the screen automatically).
        // Puck centres are hand-placed (WatchLayout, screen points) and
        // converted into this inset layer. `size` is no longer consulted —
        // these are absolute positions Sebastian chose, not proportions.
        let meds   = WatchLayout.toLive(WatchLayout.medsPuck.center)
        let events = WatchLayout.toLive(WatchLayout.eventsPuck.center)
        let fluids = WatchLayout.toLive(WatchLayout.fluidsPuck.center)
        let shock  = WatchLayout.toLive(WatchLayout.shockPuck.center)
        let tapOnly = store.settings.menuTapOnly
        return ZStack {
            // Rhythm / Code — RED, bottom-left. Antiarrhythmics + code meds.
            RadialAnchor(id: "code",
                         center: meds,
                         symbol: "syringe.fill",
                         color: CRTheme.med,
                         items: rhythmCodeItems,
                         radius: 84, bounds: size, tapOnly: tapOnly,
                         model: menu, onSelect: select)

            // Events — VIOLET, bottom-center.
            RadialAnchor(id: "events",
                         center: events,
                         symbol: "square.grid.2x2.fill",
                         color: CRTheme.cpr,
                         items: eventsItems,
                         radius: 76, bounds: size, tapOnly: tapOnly,
                         model: menu, onSelect: select)

            // Volume / Support — BLUE, bottom-right.
            RadialAnchor(id: "support",
                         center: fluids,
                         symbol: "drop.fill",
                         color: CRTheme.volume,
                         items: supportItems,
                         radius: 84, bounds: size, tapOnly: tapOnly,
                         model: menu, onSelect: select)

            // Shock — AMBER. Tap = next defib energy; hold = Defib ladder /
            // Cardiovert. (Tap-only mode turns the tap into the menu too.)
            //
            // Present in EVERY state, including before compressions and after
            // ROSC (Sebastian, 2026-08-28). Defibrillation can precede CPR,
            // and `quickShock` only logs an event — no dependency on the
            // cycle having started. Post-ROSC it is kept mainly so the bottom
            // row of anchors stays visually even; re-arrest is the realistic
            // path back to shocking.
            Group {
                RadialAnchor(id: "shock",
                             center: shock,
                             symbol: "bolt.fill",
                             color: CRTheme.shock,
                             items: shockItems,
                             radius: 62, bounds: size, tapOnly: tapOnly,
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
        flashMessage(text, isMiss: false)
    }

    /// One confirmation path for every outcome: what landed in the timeline,
    /// or that nothing did. 2 s — long enough to read mid-code without
    /// covering the chips for the next action.
    private func flashMessage(_ text: String, isMiss: Bool) {
        loggedWasMiss = isMiss
        withAnimation { lastLogged = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
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
                // Every choosable variant, not just the five families — this
                // is now the primary place the code type gets set, so the
                // refinements have to be reachable here.
                ForEach(Defaults.allProtocolChoices) { proto in
                    Button {
                        engine.changeProtocol(proto)
                        WatchHaptics.play(.click)
                        onChanged()
                    } label: {
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
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(RoundedRectangle(cornerRadius: 10).fill(CRTheme.surface))
                }
            } header: {
                Text("PROTOCOL")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(CRTheme.med)
            } footer: {
                Text("Sets the label on this code and in History. Doses and shock energies follow the weight instantly; every PALS variant shares one timer set, so switching mid-code disturbs nothing.")
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
