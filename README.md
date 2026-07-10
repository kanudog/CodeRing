# CodeRing

**DEMO — NOT FOR CLINICAL USE.**

A pediatric code timer demo for Apple Watch with an iPhone companion. Built as a proof of concept by a pediatric rapid-response RN: weight-based dosing with mL featured, a CPR cycle ring, an epi interval ring, one-slide radial event logging, haptic metronome, and a PDF debrief report.

- **Watch** runs the code: setup (manual kg / Broselow wheel / age estimate) → live rings + radial blooms → summary.
- **iPhone** edits the world: drug profile sets, custom events, timer lengths, session history, PDF export.
- **CodeCore** is the shared, tested Swift package underneath both.

Start with **BUILD_MANUAL.md** — Xcode assembly, deployment to devices, the free-account 7-day routine, troubleshooting, and the maintenance constitution for AI assistants.

Architecture promise: protocols are data (`Defaults.swift`). Adding RSI or status epilepticus later means one new definition, not new engine code.

All drug values are published PALS reference numbers as placeholders, editable in-app. Examplitol is fictional and exists to demonstrate the card style.
