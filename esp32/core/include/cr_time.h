// cr_time.h — the engine's only notion of time.
//
// Every timestamp is integer milliseconds on ONE clock that never jumps
// backwards. The engine never reads a clock itself (invariant 4): callers
// pass `now`. On the board that clock will be RTC-anchored epoch ms, so a
// reboot mid-code can resume against the same anchors; in tests it is
// whatever the test picks. Integers, not floating seconds: the ESP32-S3 has
// no double-precision FPU, and whole milliseconds never accumulate drift.

#ifndef CR_TIME_H
#define CR_TIME_H

#include <stdint.h>

typedef int64_t cr_ms_t;

/// Swift's `Date?` = nil. INT64_MIN can never be a real anchor.
#define CR_TIME_NONE INT64_MIN

/// Whole seconds → milliseconds. A constant expression, so it works in
/// static tables (timer lengths in cr_defaults.c).
#define CR_SEC(s) ((cr_ms_t)(s) * 1000)

#endif
