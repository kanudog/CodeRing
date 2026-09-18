// cr_cues.h — when the board should make a noise.
//
// This is the whole of the alerting logic, and it lives in core rather than in
// the firmware for one reason: a cue that fires twice is an annoyance, and a
// cue that never fires is a missed drug. Neither leaves a trace on the screen
// or in the log, so neither would be found by using the device — only by a
// test that drives a whole code past every boundary.
//
// It decides only WHICH cue; the firmware owns the sound (cr_audio) and the
// user's choice of rhythm (cr_settings). And like the engine, it reads no
// clock: the caller passes `now`.
//
// ONE ALERT PER EVENT, then silence (Sebastian, 2026-09-18). The countdown is
// already red and counting negative on the screen, so the screen carries the
// urgency; a speaker that nags during a resuscitation becomes a sound people
// learn to ignore.

#ifndef CR_CUES_H
#define CR_CUES_H

#include <stdbool.h>
#include <stddef.h>

#include "cr_engine.h"

typedef enum {
    /// The CPR cycle countdown reached zero: stop and check a pulse.
    CR_CUE_PULSE_CHECK_DUE,
    /// A drug's interval reached zero.
    CR_CUE_MED_DUE,
    /// A pulse check has run past the 10 s hands-off target: back on the
    /// chest. The one alert the watch app itself raises automatically.
    CR_CUE_HANDS_OFF_OVERSHOOT,
} cr_cue_t;

/// The hands-off target, matching the live screen's red threshold.
#define CR_HANDS_OFF_LIMIT_MS CR_SEC(10)

/// What has already been announced, remembered as the ANCHOR each cue belonged
/// to rather than as a flag.
///
/// Flags were the first attempt and were wrong: re-arming meant observing the
/// timer with time left on it, so whether a cue fired depended on whether a
/// poll happened to land in that window. At 10 Hz on the board it would always
/// have worked, and the flaw would have sat there invisibly. An anchor is
/// identity — a new one is a new event, however often or seldom it is asked —
/// and it makes undo work for free, because rolling an interval back to the
/// previous dose changes the anchor too.
typedef struct {
    cr_ms_t cycle;                        // CR_TIME_NONE = nothing announced yet
    cr_ms_t interval[CR_MAX_TIMERS];
    cr_ms_t check;
} cr_cue_state_t;

void cr_cues_reset(cr_cue_state_t *state);

/// The cues that became due since the last call. Writes at most `cap` and
/// returns how many — normally zero. Call it as often as you like: the state
/// is what stops an alert repeating, so polling faster does not make it louder.
size_t cr_cues_poll(cr_cue_state_t *state, const cr_engine_t *engine, cr_ms_t now,
                    cr_cue_t *out, size_t cap);

#endif
