# CodeRing → Waveshare ESP32-S3-Touch-AMOLED-2.06: port handoff

Written 2026-09-14, at the end of the watchOS work (Watch v8). Read this first
when starting the ESP32 port. It is the portable summary of what the Apple
Watch build learned; the code itself will not carry over, but almost all of
the decisions should.

## The short version

1. **The Swift does not port. The behaviour does.** The engine rules, the dose
   maths, the menu tree and the hand-placed layout are the specification, and
   the 45 tests in `CodeCore/Tests` are an executable copy of it. Port against
   the tests, not against the SwiftUI.
2. **The layout ports almost for free.** The two screens have the same aspect
   ratio — 198 × 242 pt (0.8182) versus 410 × 502 px (0.8167). One uniform
   factor of **×2.071** maps every watchOS point to a panel pixel and lands the
   bottom edge less than 1 px off. Every number in `WatchLayout.swift` and
   `FanLayout.swift` becomes a pixel coordinate by multiplication.
3. **There is no vibration motor on this board.** The watch app leans on
   haptics for every confirmation and alert (see "Feedback" below). That is
   the largest behavioural gap, and it needs a decision early.
4. **SF Symbols do not exist there.** `Tools/LayoutBench/index.html` has a
   24 × 24 SVG redraw of every icon the app uses (the `ICONS` table). That is
   the starting asset set — rasterise it.

## The target board (verified against Waveshare's docs, 2026-09-14)

| | |
|---|---|
| MCU | ESP32-S3R8 — 32 MB flash, 8 MB PSRAM |
| Display | 2.06" AMOLED, **410 × 502**, CO5300 driver over QSPI |
| Touch | FT3168 capacitive, I²C (address 0x38) |
| Power | AXP2101 PMU, 3.7 V Li-ion on MX1.25 |
| Motion | QMI8658C 6-axis IMU |
| Clock | PCF85063ATL RTC |
| Audio | ES8311 codec, ES7210 mic ADC (dual mics), NS4150B amp on GPIO46 |
| Storage | TF card over SPI |
| Buttons | BOOT and PWR (configurable) |
| Haptics | **none listed** |
| Frameworks | Arduino and ESP-IDF; versions not pinned in the docs — take them from Waveshare's example repo |

Sources: [Waveshare docs](https://docs.waveshare.com/ESP32-S3-Touch-AMOLED-2.06) ·
[product page](https://www.waveshare.com/esp32-s3-touch-amoled-2.06.htm) ·
[example code](https://github.com/waveshareteam/ESP32-S3-Touch-AMOLED-2.06)

### What maps to what

| On Apple Watch | On this board |
|---|---|
| SwiftUI views | Your UI toolkit (LVGL is the usual choice here) |
| `WatchHaptics` cues | No motor. Speaker via ES8311 + NS4150B, and/or screen flash — or add a motor |
| `ToneMetronome` (CPR rate) | ES8311 → speaker; haptic-only was the watch default, so this must be decided |
| Digital Crown for weight entry | No crown. Touch, the two buttons, or the IMU |
| WatchConnectivity sync to iPhone | No phone app yet. A standalone prototype needs no sync at all |
| Anchor `Date`s from the system clock | PCF85063 RTC for wall time, a monotonic timer for intervals |
| PDF export (iOS app) | Out of scope on-device; a CSV to the TF card is the natural stand-in |
| watchOS system clock (top-right keep-out zone) | Gone — that corner is free on this panel |

## Where the specification lives

| What | File |
|---|---|
| Session state machine | `CodeCore/Sources/CodeCore/Engine/SessionEngine.swift` |
| Drug set, doses, ladders, caps | `CodeCore/Sources/CodeCore/Models/Drugs.swift`, `Defaults/Defaults.swift` |
| Weight from age | `CodeCore/Sources/CodeCore/Models/Patient.swift` (`WeightEstimator`) |
| Live-screen geometry | `CodeCore/Sources/CodeCore/UI/WatchLayout.swift` |
| All 14 fan layouts | `CodeCore/Sources/CodeCore/UI/FanLayout.swift` |
| Colours | `CodeCore/Sources/CodeCore/Theme.swift` |
| Menu tree + what each item does | `WatchApp/LiveSessionView.swift` — "Menu trees" and `select(_:)` |
| Radial interaction model | `WatchApp/RadialMenu.swift` |
| Invariants | `CLAUDE.md`, `BUILD_MANUAL.md` §13 |
| Executable spec | `CodeCore/Tests/CodeCoreTests/CodeCoreTests.swift` |

## Engine rules that must survive the port

Each is pinned by a named test — reimplement the test first, then the rule.

- **No timers in the engine.** It stores anchor timestamps and derives every
  countdown from an injected `now`. This matters more on a microcontroller,
  where timer callbacks drift and the device sleeps.
- **The CPR cycle freezes during a pause; drug-interval timers keep running
  through it.** Deliberate. `testPauseFreezesCycleAndRecordsInterval`,
  `testDrugIntervalRunsThroughPulseCheck`.
- **A cycle only closes through a pulse check**, and its countdown runs
  negative while overdue. `testCycleCountdownGoesOverdueUntilPulseCheck`.
- A pulse check is a hands-off interval recorded as a pause. Pulse found flows
  straight into ROSC. `testPulseFoundFlowsIntoROSC`.
- Re-arrest returns to CPR and keeps the first ROSC time.
  `testReArrestReturnsToCPRAndKeepsFirstROSC`.
- CPR must be started before the cycle or pulse check exist.
  `testStartCPRGatesCycleAndPulseCheck`.
- **mL is always the big dose number; mg is secondary.** Volumes never render
  as 0.0. `testVolumeFloor`, `testMlPerKgDosing`, `testEpiCapAtOneMg`.
- Dose ladders advance with the prior count and hold the last rung.
  `testAdenosineLadder`, `testDefibEnergies`. The defib ladder is three rungs
  at every weight; the fluid ladder is two.
- **Undo removes only the newest user-logged event.** Structural records —
  `pulse.check`, `rosc.vitals`, `patient.weight`, and anything in the CPR or
  outcome categories — are skipped, because they anchor cycle, pause and
  weight state. `testUndoSkipsStructuralEventsAndStopsWhenNoneLeft`.
- Stable IDs (`C0DE0000-…`) are permanent if this device ever exchanges data
  with the iOS app.

## Layout: port by scaling

watchOS forced two coordinate spaces — the screen (198 × 242) and a fan layer
inset (2, 51). That split was a SwiftUI hit-testing artefact. **Collapse it to
one space on the ESP32:**

```
screen_pt = fan_pt + (2, 51)          // fan space → screen points
panel_px  = screen_pt × 2.071         // screen points → 410 × 502 pixels
```

| Element | watchOS (screen pt) | Panel (px) |
|---|---|---|
| Every fan button | Ø44, glyph 25 | Ø91, glyph 52 |
| Label gap under a button | 4 pt from the button's bottom edge | ≈8 px |
| Cancel ✕ (every fan) | (99, 200) | (205, 414) |
| Back (depth ≥ 2 only) | (32, 32) | (66, 66) |
| Title chip (every fan) | (99, 25) | (205, 52) |

The panel is slightly larger physically than the 45 mm watch face, so touch
targets come out at least as large as the ones that were tuned on the wrist.
Check the panel's corner radius on the real device before trusting the corner
positions — Back sits close to one.

## The menu tree

Colours are `CRTheme` hexes. ▸ marks a group that opens a deeper fan.
Root keys are anchor ids; nested keys are the parent item's id.

| Fan | Items, left to right | Icon (SF Symbol name) |
|---|---|---|
| `code` — Meds `#FF3B5C` | Epinephrine · Atropine · Adenosine · Amiodarone · Lidocaine | syringe.fill · hare.fill · pause.circle.fill · tortoise.fill · waveform.slash |
| `shock` — Shock `#FFB020` | Defib ▸ · Cardiovert | bolt.fill · bolt.heart.fill |
| `grp:defib` | 1st · Next · Max (energy from the dose ladder) | bolt.fill ×3 |
| `support` — Fluids `#3B82F6` | More ▸ · Bicarb · Calcium · Dextrose · Fluids ▸ | ellipsis · bubbles.and.sparkles.fill · diamond.fill · cube.fill · drop.fill |
| `grp:fluids` | Blood · 10 mL/kg · 20 mL/kg | drop.fill (red icon) · drop.halffull · drop.fill |
| `grp:more` | Drip · Magnesium · Naloxone | ivfluid.bag · hexagon.fill · nose.fill |
| `events` — Events | Rhythm · Access ▸ · Airway ▸ · Comms ▸ · Temp ▸ · ROSC (+ custom events) | waveform.path.ecg · cross.circle.fill · lungs.fill · person.2.wave.2.fill · thermometer.medium · heart.fill |
| `grp:access` `#34D399` | IV · IO · Art line | cross.vial.fill · target · waveform.path |
| `grp:airway` `#22D3EE` | Intubation · Bag · Mask · Trach | arrow.down.to.line.compact · balloon.fill · facemask.fill · cylinder.fill |
| `grp:comms` `#818CF8` | Call ▸ · Arrived ▸ | phone.fill · figure.walk.arrival |
| `grp:call`, `grp:arrival` | Surgery · Anesthesia · ECMO · Consult | scissors · moon.zzz.fill · arrow.triangle.2.circlepath · stethoscope |
| `grp:temp` `#2DD4BF` | Bair Hugger · Arctic Sun · Warm blankets | wind · snowflake · square.stack.3d.up.fill |
| `events.rosc` (after ROSC) | Pulse · 12-lead · Drip · Blood · Temp ▸ | waveform.path.ecg · waveform.path.ecg.rectangle · ivfluid.bag · drop.fill · thermometer.medium |

Two that surprise people: `support` is built Fluids-first and then reversed,
so it reads More → Fluids; and the Events fan grows by however many custom
events exist, which is why layout lookup is count-exact with a computed
fallback.

Anesthesia is `moon.zzz.fill` only because SF Symbols has no laryngoscope. On
the ESP32 you draw your own icons, so a real intubation blade is free.

## Interaction decisions to keep

These came from real use on the wrist and are platform-independent.

- **The wearer's own finger hides the lower-right quadrant** (watch on the
  left wrist, right index finger). Nothing that must be hit goes there. That
  is why every fan blooms across the top.
- **Only a hovered leaf fires.** Releasing on a group, a pad or empty space
  logs nothing — and must visibly say "Nothing logged". Silence after a
  deliberate gesture is this app's worst failure mode: the wearer believes an
  intervention was recorded when it was not.
- **Name the item under the finger during a hold-drag.** It is the only
  confirmation of what is about to fire. When nothing is hovered, the chip
  shows where you are: the fan's name, or the level above over the current
  group (EVENTS / Access).
- **Exit pads never move.** ✕ and Back sit in the same place in every fan at
  every depth, so exiting is one learned reach.
- **Whatever is drawn on top must be what takes the touch.** A pad drawn over
  a puck reads as one control; if the touch lands on the one underneath, it
  looks like the menu is broken.
- **Labels are wider than buttons**, so label width — not button size — sets
  the minimum spacing between buttons.
- **Choosing Rhythm from the Events fan during CPR runs a real pulse check**
  (hands-off screen, cycle closes). It is deliberately not gated on the cycle
  being due; tapping the big centre ring is, because that target is easy to
  hit by accident. It must not also log a second entry.
- The confirmation toast lives exactly 2 s.
- The backdrop behind an open fan is blurred and lifted rather than flat
  black, so the dark buttons stand out. On an ESP32 a live full-screen blur is
  expensive; snapshotting the screen once when the fan opens and blurring that
  single frame is the likely approach.

## Feedback: the haptics problem

The watch fires eight distinct haptic cues — `click` (hover and selection
ticks, the most frequent), `success`, `start`, `notification`, `failure`,
`retry`, `directionUp`, `directionDown` — plus configurable patterns for
pulse-check-due, medication-due and cycle-complete, and a haptic-only
metronome by default. With no motor, each needs an audio or visual
equivalent, or a motor has to be added. The due alerts are the ones that
cannot be dropped.

## What NOT to port

These were workarounds for watchOS specifically:

- The fan-space / screen-space split.
- SwiftUI hit-testing traps (`.position` swallowing the screen, `Color.clear`
  being touchable, `.ultraThinMaterial` rendering nothing).
- The top-right clock keep-out zone.
- The XCUITest driver harness and its hardcoded `Pucks` / `Slots` coordinates.

The underlying lesson does port: **measure, don't eyeball.** A 3 pt shift is
invisible in a screenshot. The watch build was verified by dumping real frame
coordinates from the running app and diffing them against the layout table;
do the equivalent with your UI toolkit's object coordinates.

## Tools

- `Tools/LayoutBench/index.html` — the drag-and-drop layout editor. It opens
  on seed values, not the final placement (see its README), and its exporter
  writes Swift. At the shared aspect ratio it is still a usable design surface
  for this panel; an exporter for C would be the change.

## Open items carried over

- `Tools/SyncDriver` era tests `testV3`–`testV9` fail at setup (they predate
  the protocol picker), and `testV11` has one stale fan coordinate.
- Four fans (`grp:more`, `grp:arrival`, `grp:temp`, `events.rosc`) are covered
  by unit tests but were never captured on screen.
