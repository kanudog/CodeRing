# CLAUDE.md — CodeRing

Demo pediatric code timer (watchOS + iOS + shared `CodeCore` package). NOT a medical device — the demo badge and disclaimers are permanent features, not placeholders.

Full context: `BUILD_MANUAL.md`. Section 13 ("FOR AI MAINTAINERS") is your constitution for this repo — read it before editing anything.

## Commands

```bash
# Logic tests (run before AND after any CodeCore change — must stay green)
cd CodeCore && swift test

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
3. Demo badge on every top-level screen + PDF footer. Never remove or gate.
4. `SessionEngine` owns no Timers — anchor dates only, `now` injected by views.
5. All colors from `CRTheme` or stored `colorHex`. No literal hex in views.
6. Persistence only through `CodeStore`. No UserDefaults, no stray file writes.
7. CPR cycle freezes during pause; drug-interval timers run through pauses. Intentional; tests enforce it.

## Style

SwiftUI + Observation, zero third-party dependencies, explicit `public` in CodeCore, comments explain *why*. Watch files → Watch target only; iOS files → iOS target only; wrong target membership is the #1 build-error source.

## Sharp edges

- `RadialMenu`: anchor's LongPress→Drag sequence owns the touch; overlay hit-tests only in tap mode. Do not reorder that ZStack or force `allowsHitTesting(true)`.
- `ToneMetronome`: documented benign race on `envelope` between main and render thread. Leave it.
- `DrugEditorView`: force-unwrapped bindings behind an `if drug != nil` guard. Keep the guard.
