# CodeRing on the Waveshare ESP32-S3-Touch-AMOLED-2.06

The port of CodeRing from Apple Watch to a 410 × 502 AMOLED dev watch.
**Nothing in `WatchApp/`, `iOSApp/` or `CodeCore/` is touched by anything in
this folder.** The Swift does not port; the behaviour does, and the Swift
tests are the specification (see `docs/ESP32_PORT_HANDOFF.md`).

Still a demo. Not a medical device.

## Run the tests

```bash
cd esp32 && make test
```

No board, no ESP-IDF, no network — just a C compiler. It builds with the
address and undefined-behaviour sanitizers on, runs in milliseconds, and
also checks that every Swift test is either ported or listed in
`test/deferred_swift_tests.txt` with a reason.

```bash
make test NAME=pulse   # only tests whose name contains "pulse"
make parity            # run one scenario through BOTH engines and diff (needs Swift)
make target-check      # compile the core for the ESP32-S3 (needs . ~/esp/esp-idf/export.sh)
```

`make parity` is the one that matters most: it drives a 10-minute code
through the real Swift `SessionEngine` and through this C engine, then
diffs 72 lines of trace — every event, every dose string, every clock at
every sampled moment, the running timers and the final stats. A translated
assertion can be wrong twice in the same direction; a byte-identical trace
cannot.

## What is here (M1)

`core/` is portable C99 with **no ESP-IDF dependency and no heap**. That is
deliberate: the clinical rules are testable on a laptop in milliseconds, and
a fixed-size engine cannot fragment memory or fail an allocation mid-code.

| File | What it owns |
|---|---|
| `cr_engine.*` | the session state machine — cycles, pauses, pulse checks, ROSC, undo |
| `cr_session.*` | the event log, pause intervals, running timers, stats |
| `cr_drugs.*` | dose ladders, caps, mg ↔ mL |
| `cr_patient.*` | weight: manual, Broselow, APLS age estimate |
| `cr_defaults.*` | the ship-in-the-box drugs, events and protocols (+ the stable UUIDs) |
| `cr_protocol.*`, `cr_events.*` | protocol and event definitions |
| `cr_settings.*` | user settings, same JSON keys as the phone's `settings.json` |
| `cr_snapshot.*` | the whole live state as one JSON object — **the TV seam** |
| `cr_text.*`, `cr_theme.h`, `cr_time.h` | formatting, colours, the clock type |

Size on the target: **30 KB of code**, one 96 KB session struct (512 events,
256 pauses) that will live in PSRAM.

### Decisions worth knowing before editing

- **Time is `int64_t` milliseconds** on one clock that never jumps back. The
  engine never reads a clock — callers pass `now` (invariant 4). On the
  board that will be RTC-anchored epoch ms, so a reboot mid-code can resume
  against the same anchors.
- **Actions return `bool`** — true when something actually happened. Swift
  returns Void and lets the UI infer it. Here the caller needs the answer,
  because a gesture that logs nothing must SAY so; silence after a
  deliberate action is this app's worst failure mode.
- **Overflow is loud, and never blocks the clinical clock.** A drug that
  cannot be recorded is refused outright (and does not restart its interval
  timer). A pulse check or pause whose record does not fit still runs, the
  cycle still closes, and `overflow` latches so the screen and the TV can
  say the log stopped recording.
- **Strings are copied, never pointed at**, so a session can be written to
  flash verbatim. Truncation is UTF-8 safe (a cut never lands mid-character).
- **`cr_snapshot_json` is the TV seam.** The panel and the trauma-bay display
  are two consumers of one derived snapshot. Anything the engine learns
  reaches both; scraping state out of UI code later is how that goes wrong.

## Run it on the watch

```bash
. ~/esp/esp-idf/export.sh          # once per terminal window
cd esp32/firmware && idf.py -p /dev/cu.usbmodem101 flash monitor
```

`firmware/` is an ESP-IDF project; `core/` is pulled in as a component, so
the firmware and the host tests compile the **same** engine sources.

Two tools worth knowing:

- **`main/ui_probe.c`** prints where every object actually landed, and the
  coordinates of every touch. The watch build was verified by dumping real
  frame coordinates rather than by looking at screenshots; M3's layout gets
  checked the same way. (It must call `lv_obj_update_layout()` first —
  without it LVGL reports every object as 0×0.)
- **`tools/make_fonts.sh`** regenerates the app's fonts. LVGL's built-ins
  are ASCII-only, so "Hands off — checking pulse" drew a box where the dash
  belongs. Changing the strings was not an option — they must stay
  byte-identical to the watch — so the font carries `— – · → × ₂` instead.
  The script verifies the glyphs are present, because a missing one fails
  silently as an empty box.

## Watch the engine in a browser

```bash
cd esp32 && make preview          # then open http://localhost:8765
```

Real compiled C behind a local page — the same `cr_snapshot_json` feed the
trauma-bay TV will consume. Useful for exercising clinical flows quickly,
and for seeing "Nothing logged" fire when the engine refuses an action.

## Verified on the real board (2026-09-14)

Read off the unit itself with esptool, not from the datasheet:

- ESP32-S3 rev v0.2, **32 MB flash** (the handoff's 16-vs-32 MB conflict is
  settled), 8 MB PSRAM, USB-Serial/JTAG at `/dev/cu.usbmodem101`.
- Secure boot and flash encryption **off** — freely reflashable.
- Shipped with Waveshare's ESP-Brookesia phone demo (`phone_s3_box_3`, built
  on IDF v5.5.1) plus the XiaoZhi voice assistant in `ota_0`.
- Full-flash backup taken and verified against the chip before anything else.
- Official BSP: `waveshare/esp32_s3_touch_amoled_2_06` 2.0.0 (IDF ≥ 5.3,
  LVGL 8–9). It sets **`esp_lcd_panel_set_gap(panel, 0x16, 0)` — 22 columns**,
  not the 6 an ESPHome bug report claims. Measure it on the panel anyway.
- Toolchain here: ESP-IDF v5.5.5 in `~/esp/esp-idf`, LVGL 9 at M2.

## Milestones

- **M1 — the engine, done.** 59 tests / 669 checks green, byte-identical to
  the Swift engine on the parity scenario, compiles clean for the ESP32-S3.
- **M2 — first light, done** (verified on the real watch, 2026-09-14).
  `firmware/` boots in ~1.1 s to a deliberately plain screen driven by the
  engine: panel, touch and clinical rules proven to work together before any
  layout is built on top. Confirmed on hardware: the cycle freezes during a
  pulse check while the epi timer keeps running — invariant 7, on the wrist.
- **M3** — the radial fans and the interaction rules; the 16 deferred layout
  tests come back here, re-expressed in pixels.
- **M4** — audio: the metronome (already audio-only on the watch) and the
  cue model that replaces haptics.
- **M5** — persistence (NVS + RTC), CSV to the TF card, and the TV link.

## Two Swift quirks carried over on purpose

Both are faithfully reproduced so the watch, the phone, this board and the
TV agree. Both are worth a decision before M5 — fixing either one here alone
would make the numbers disagree between devices.

1. **A weight change shows up as a running timer.** `runningTimers` treats
   the whole `custom` category as repeatable, and a weight change is
   `custom`, even though the comment beside it says one-shots get no row.
2. **Pauses after a re-arrest count against the pre-ROSC CPR fraction.**
   `SessionStats` measures the fraction over start → FIRST ROSC, but a
   closed pause that starts after that moment still contributes its full
   length, which can drag the fraction down.
