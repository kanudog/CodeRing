# CLAUDE.md — CodeRing

Demo pediatric code timer (watchOS + iOS + shared `CodeCore` package). NOT a medical device. Personal tool for Sebastian; the PDF disclaimer stays, on-screen badges are gone (see invariant 3).

Full context: `BUILD_MANUAL.md`. Section 13 ("FOR AI MAINTAINERS") is your constitution for this repo — read it before editing anything.

Porting to the Waveshare ESP32-S3 AMOLED watch? Start with `docs/ESP32_PORT_HANDOFF.md`.

## Commands

```bash
# Logic tests (run before AND after any CodeCore change — must stay green)
cd CodeCore && swift test

# ESP32 port (esp32/, portable C99 — no board or ESP-IDF needed)
cd esp32 && make test      # also: make parity (diffs the C engine against Swift)

# Simulator builds once the Xcode project exists (manual §3–8)
xcodebuild -scheme "CodeRing Watch App" \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 9 (45mm)' build
xcodebuild -scheme "CodeRing" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build
```

Fix compile errors by editing sources, never by weakening the invariants below.

## Hard invariants

1. Stable UUIDs in `Defaults.swift` (`C0DE0000-…`) are permanent. Never regenerate.
2. mL is always the featured dose number; mg secondary (`DoseResult.volumeText` first).
3. PDF export keeps its demo footer. On-screen demo badges were REMOVED at
   Sebastian's request (2026-08-22) — personal use only, and they cost scarce
   watch screen space. `DemoBadge` still exists in `SharedUI.swift`; do not
   re-add it to any screen without asking.
4. `SessionEngine` owns no Timers — anchor dates only, `now` injected by views.
5. All colors from `CRTheme` or stored `colorHex`. No literal hex in views.
6. Persistence only through `CodeStore`. No UserDefaults, no stray file writes.
7. CPR cycle freezes during pause; drug-interval timers run through pauses. Intentional; tests enforce it.

## Style

SwiftUI + Observation, zero third-party dependencies, explicit `public` in CodeCore, comments explain *why*. Watch files → Watch target only; iOS files → iOS target only; wrong target membership is the #1 build-error source.

## Layout is hand-placed, in two files

- `CodeCore/UI/WatchLayout.swift` — the live SCREEN, in screen points (198×242).
- `CodeCore/UI/FanLayout.swift` — the radial submenus, in FAN space (194×191,
  inset 2,51). Keyed by anchor id at the root and by parent item id (`grp:*`)
  below it. Lookup is **count-exact** and falls back to `TopArcLayout` on any
  mismatch, because several fans are sized at runtime. Fans still on their
  `.arc(n)` seed are byte-identical to the old computed arc; a test enforces it.
- Both are exported from the Layout Bench. Never convert between the two spaces
  by hand — use `WatchLayout.toLive(_:)`.

## Sharp edges

- `RadialMenu`: anchor's LongPress→Drag sequence owns the touch; overlay hit-tests only in tap mode. Do not reorder that ZStack or force `allowsHitTesting(true)`.
- `Tools/SyncDriver` hardcodes anchor coordinates and cannot import CodeCore. The
  `Pucks` enum at the top of `WatchDriverTests.swift` mirrors `WatchLayout` —
  **update it whenever a puck moves**, or tests fail on a healthy app.
- `ToneMetronome`: documented benign race on `envelope` between main and render thread. Leave it.
- `DrugEditorView`: force-unwrapped bindings behind an `if drug != nil` guard. Keep the guard.
