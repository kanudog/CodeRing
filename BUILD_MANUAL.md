# CodeRing — Build Manual

**DEMO PROJECT. NOT A MEDICAL DEVICE. NEVER FOR CLINICAL USE.**
Every dose value ships as an editable placeholder. The demo badge in both apps is permanent by design.

This manual gets the code from this folder onto your Watch Series 9 + iPhone 17 Pro Max using Xcode on the Mac Mini and a free Apple developer account. It also contains a maintenance constitution for AI assistants working on this codebase later — read that section before changing anything.

---

## 1. What's in the folder

```
CodeRing/
├── CodeCore/                  Swift package — all logic, models, storage, sync
│   ├── Package.swift
│   ├── Sources/CodeCore/
│   │   ├── Theme.swift            Midnight Neon tokens, crClock/crOffset
│   │   ├── Models/
│   │   │   ├── Patient.swift      PatientContext, Broselow zones, APLS estimator
│   │   │   ├── Drugs.swift        DrugProfile, dose ladder, DoseCalculator (mL-forward)
│   │   │   ├── Events.swift       EventDefinition, CodeEvent, categories
│   │   │   ├── ProtocolDefinition.swift   Data-driven protocols + TimerSpec
│   │   │   └── Session.swift      CodeSession, PauseInterval, SessionStats
│   │   ├── Engine/SessionEngine.swift     Live-code engine (anchor dates, no Timers)
│   │   ├── Defaults/Defaults.swift        PALS defaults, Examplitol, STABLE UUIDs
│   │   ├── Storage/Store.swift            CodeStore — JSON persistence + settings
│   │   ├── Sync/Connectivity.swift        WCSession envelope sync
│   │   └── UI/SharedUI.swift              DemoBadge, RingGauge, StatTile
│   └── Tests/CodeCoreTests/CodeCoreTests.swift
├── WatchApp/                  Sources for the watchOS app target
│   ├── CodeRingWatchApp.swift     @main + inbound sync merge
│   ├── WatchRootView.swift        Home / recent / settings / flow owner
│   ├── SetupFlow.swift            Protocol → weight (crown / Broselow wheel / age) → GO
│   ├── LiveSessionView.swift      Rings, hints, the three radial anchors
│   ├── RadialMenu.swift           Signature hold-slide-release bloom menus
│   ├── EventLogView.swift
│   ├── SummaryView.swift
│   └── WatchHaptics.swift         Haptic router + 110 bpm metronome
├── iOSApp/                    Sources for the iOS app target
│   ├── CodeRingApp.swift          @main, tabs, dashboard, settings
│   ├── DrugLibraryViews.swift     Sets → editor with live mL-forward preview
│   ├── CustomEventViews.swift
│   ├── ProtocolSettingsView.swift Cycle/epi overrides
│   ├── HistoryViews.swift         Sessions → detail → share
│   ├── ReportGenerator.swift      Paginated PDF
│   └── ShareSheet.swift
├── Widget/CodeRingComplication.swift   OPTIONAL watch-face launcher
├── BUILD_MANUAL.md            This file
└── README.md
```

## 2. Prerequisites

- Mac Mini with Xcode 15.2 or newer (16.x fine). `xcode-select --install` if prompted.
- Free Apple ID signed into Xcode (Settings → Accounts → +).
- iPhone with **Developer Mode on** (Settings → Privacy & Security → Developer Mode → restart) and the Watch paired to it.
- This `CodeRing/` folder somewhere stable, e.g. `~/dev/CodeRing`. Xcode references the package by path — moving the folder later breaks the reference (fix: re-add the package).

## 3. Create the Xcode project

1. Xcode → **File → New → Project → iOS → App**.
   - Product Name: `CodeRing` · Interface: SwiftUI · Language: Swift · Storage: None · uncheck tests.
   - Save it **inside** the `CodeRing/` folder (sibling to `CodeCore/`).
2. **File → New → Target → watchOS → App**. Choose **"Watch App for Existing iOS App"** if offered; otherwise "App" and confirm it embeds in CodeRing.
   - Product Name: `CodeRing Watch App` · Interface: SwiftUI · uncheck tests. Activate the scheme when asked.

## 4. Add the CodeCore package

3. **File → Add Package Dependencies… → Add Local…** → select the `CodeCore` folder → Add Package.
   - When asked which target gets the `CodeCore` library, pick the **iOS target**.
4. Link it to the watch too: select the project → **CodeRing Watch App** target → **General → Frameworks, Libraries, and Embedded Content → +** → `CodeCore`.

## 5. Drop in the sources

5. Delete the template files Xcode generated in **both** targets: the template `CodeRingApp.swift`, `ContentView.swift`, and the watch equivalents (`CodeRing_Watch_AppApp.swift`, `ContentView.swift`). Move to Trash.
6. Drag the provided source files in from Finder:
   - Everything in `iOSApp/` → into the iOS group. In the add dialog: **Copy items if needed OFF is fine (already in folder)**, Target membership: **CodeRing only**.
   - Everything in `WatchApp/` → into the watch group. Target membership: **CodeRing Watch App only**.
   - Wrong membership is the #1 source of "cannot find X in scope" errors. Verify in the File Inspector (right panel) if anything fails to build.

## 6. Watch target configuration

7. Select the **CodeRing Watch App** target:
   - **General**: check **"Supports Running Without iOS App Installation"** (independence).
   - **Info** tab → **URL Types → +** → URL Schemes: `codering`. (Powers the `codering://new` complication deep link.)

## 7. Signing

8. For **every** target (iOS, Watch App, and the widget if you add it): **Signing & Capabilities → Team →** your Personal Team. Automatic signing on. Xcode assigns bundle IDs like `com.yourname.CodeRing` / `.watchkitapp` — accept them and **never change them afterward** (free accounts cap at 10 unique App IDs per 7 days; reusing IDs avoids the cap).

## 8. Optional — watch-face complication (5 min)

- **File → New → Target → watchOS → Widget Extension**, name `CodeRingWidget`, embed in the Watch App, **uncheck** "Include Configuration App Intent".
- Delete the template widget source file; drag in `Widget/CodeRingComplication.swift` with membership **CodeRingWidget only**.
- Sign the new target (step 8). After install: long-press the watch face → Edit → add the CodeRing complication. Tap → straight into setup.

## 9. Run it

1. Plug the iPhone into the Mac (first run — cable is more reliable than Wi-Fi). Trust the computer.
2. Scheme: **CodeRing Watch App → [your Apple Watch via iPhone]** → Run. First install takes a few minutes.
3. If the watch app won't launch: on the **iPhone**, Settings → General → VPN & Device Management → trust your developer certificate. Launch again.
4. Switch scheme to **CodeRing → iPhone** → Run. Open both apps once so WCSession handshakes; then Dashboard → **Send library to Watch**.

Simulator alternative: any watch simulator paired with an iPhone simulator runs everything except real haptics.

## 10. The 7-day routine (free account)

Free-account provisioning profiles expire weekly. Symptom: the app icon dims or the app refuses to launch, usually ~7 days after the last install.

Fix, ~2 minutes: connect the iPhone → open the project → Run each scheme once. Done. Nothing is lost — sessions, drug sets, and settings persist on-device.

## 11. Running the tests

- Terminal: `cd CodeRing/CodeCore && swift test`
- Or in Xcode: select the `CodeCore` scheme → ⌘U.

The suite locks in dose math (epi 8 kg → 0.08 mg / 0.8 mL, caps, ladders, defib energies), the APLS estimator, pause-freeze cycle math, epi timer resets, and CPR-fraction stats. Green tests before and after any CodeCore change.

## 12. Troubleshooting FAQ

| Symptom | Cause → Fix |
|---|---|
| `No such module 'CodeCore'` | Package not linked to that target → target → General → Frameworks → + CodeCore. |
| `'Observable' is only available in…` | Deployment target too low → iOS 17.0 / watchOS 10.0 on every target. |
| `Cannot find 'WatchHaptics' in scope` (or similar) | File has wrong target membership → File Inspector → check the right box. |
| Watch app installs but Send-to-Watch does nothing | WCSession not activated on both ends → launch both apps once; keep them foregrounded on first sync. `transferUserInfo` fallback delivers queued payloads on next launch. |
| "Maximum App ID limit reached" | Free-account cap (10/week) → wait, or reuse the existing bundle IDs (don't rename targets). |
| Complication missing from face picker | Widget target not installed/signed → run the Watch App scheme again; some faces need a watch restart to refresh the gallery. |
| Metronome silent | Sound is OFF by default (haptic-only). Watch Settings → Metronome sound. Also check the watch isn't in Silent Mode. |
| App won't launch after a week | Provisioning expiry → section 10. |
| Crown won't change the number | The focusable view lost focus → tap the big number once, then turn. |

---

## 13. FOR AI MAINTAINERS — read before touching anything

You are working on a demo pediatric code timer owned by Sebastian (pediatric rapid-response RN). He reads code. Match the existing style exactly.

### Invariants — never violate

1. **Stable UUIDs in `Defaults.swift` are permanent.** They start `C0DE0000-…`. Regenerating them severs watch↔phone identity and orphans synced data.
2. **mL stays featured.** Wherever a dose renders, volume is the big number, mg the small one. `DoseResult.volumeText` first, always.
3. **The demo badge is non-negotiable.** Every top-level screen and the PDF footer. Never remove, shrink into invisibility, or gate it.
4. **The engine owns no Timers.** `SessionEngine` stores anchor `Date`s; views pass `now` from `TimelineView`. Adding a `Timer` to the engine breaks testability and drift-correctness.
5. **All colors come from `CRTheme`** (or a stored `colorHex`). No literal hex in views.
6. **Persistence goes through `CodeStore` only.** No stray `UserDefaults`, no direct file writes.
7. **Clinical semantics:** CPR cycle freezes during pause; drug-interval timers run through pauses. Both are intentional. Tests enforce them.

### Recipes

- **Add a protocol** (e.g. RSI): new `CodeProtocolDefinition` in `Defaults.swift` + append to `Defaults.protocols`. Add any new drugs/events it references. The setup picker, engine, rings, and blooms adapt — zero view changes unless the protocol needs a new `TimerRole`.
- **Add or change a drug:** prefer the iPhone editor (it round-trips through the same models). Ship-level defaults belong in `Defaults.swift` with a new stable UUID in the `C0DE0000` block.
- **Change timer lengths:** users do this in Protocol Settings (`AppSettings` overrides). Protocol-level defaults live on the `TimerSpec`.
- **New synced data type:** add a `SyncKind` case, encode/decode via `SyncEnvelope`, merge in both apps' `onReceive`.

### Style

- SwiftUI + Observation (`@Observable`), no third-party dependencies, no storyboards.
- Small views, computed sub-views, explicit `public` in CodeCore.
- Comments explain *why*, headers explain the file's job. Keep that density.
- Any change to CodeCore logic gets a test. `swift test` green is the bar.

### Known sharp edges

- `RadialMenu` gesture handoff: the anchor's `LongPress→Drag` sequence owns the touch; the overlay hit-tests only in tap mode. Reordering that ZStack or adding `allowsHitTesting(true)` unconditionally kills the slide gesture.
- `ToneMetronome` writes `envelope` on main while the render thread reads it — an accepted benign race, documented in-file. Leave it unless replacing the whole audio path.
- `DrugEditorView` bindings force-unwrap behind an `if drug != nil` guard. Keep the guard if restructuring.
