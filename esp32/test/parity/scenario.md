# The parity harness

The ported unit tests prove the C engine satisfies the same assertions as
the Swift one. This proves something stronger and much harder to fake: run
**one long scenario** through both engines and diff the traces, byte for
byte. Event order, dose strings, every clock at every sampled moment, the
running-timer rows and the final stats all have to agree.

It exists because "the behaviour ports" is the whole premise of this port.
A translated assertion can be translated wrongly in the same direction
twice; a byte-identical trace cannot.

```
make parity        # from esp32/ — builds both, runs both, diffs
```

Needs Swift (it builds a tiny SwiftPM executable against `../../CodeCore`).
It is not part of `make test`, which stays dependency-free and instant.

Two deliberate rules for anyone extending `scenario.c` / `main.swift`:

1. **Keep the two files line-for-line parallel.** They are meant to be read
   side by side.
2. **No two log entries or timer rows may share a timestamp.** Swift's
   `runningTimers` sorts a dictionary, so ties come out in an undefined
   order — a tie would make the diff flap for a reason that is not a bug.
