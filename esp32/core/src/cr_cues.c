#include "cr_cues.h"

#include <string.h>

void cr_cues_reset(cr_cue_state_t *state)
{
    if (state == NULL) return;
    state->cycle = CR_TIME_NONE;
    state->check = CR_TIME_NONE;
    for (size_t i = 0; i < CR_MAX_TIMERS; i++) state->interval[i] = CR_TIME_NONE;
}

static void emit(cr_cue_t cue, cr_cue_t *out, size_t cap, size_t *n)
{
    if (out != NULL && *n < cap) out[*n] = cue;
    (*n)++;
}

size_t cr_cues_poll(cr_cue_state_t *state, const cr_engine_t *e, cr_ms_t now,
                    cr_cue_t *out, size_t cap)
{
    size_t n = 0;
    if (state == NULL || e == NULL) return 0;

    // A finished code says nothing at all, and neither does one that has not
    // started compressions: a countdown showing its full length is not due.
    if (e->ended) return 0;

    // MARK: hands off too long
    //
    // Only while a check is actually running. It re-arms when the check ends,
    // so the next one can warn again.
    if (e->in_pulse_check && state->check != e->pulse_check_started_at &&
        cr_engine_pulse_check_elapsed(e, now) >= CR_HANDS_OFF_LIMIT_MS) {
        state->check = e->pulse_check_started_at;
        emit(CR_CUE_HANDS_OFF_OVERSHOOT, out, cap, &n);
    }

    // MARK: the pulse check is due
    //
    // Not while paused: the cycle is frozen, so it did not become due — it was
    // already due, or it is not yet. Not during the check itself, which IS the
    // answer to this cue. Not post-ROSC, where there is no cycle to run out.
    const bool cycle_runs = e->cpr_started && !e->paused && !e->in_pulse_check &&
                            !e->rosc_achieved;
    if (cycle_runs && state->cycle != e->cycle_anchor &&
        cr_engine_cycle_remaining(e, now) <= 0) {
        state->cycle = e->cycle_anchor;
        emit(CR_CUE_PULSE_CHECK_DUE, out, cap, &n);
    }

    // MARK: a drug is due
    //
    // Per timer, and only once it is RUNNING: an interval that has never been
    // started is showing its full length, not counting down, and announcing it
    // would read as a standing order for a drug nobody has given.
    for (uint8_t i = 0; i < e->protocol.timer_count && i < CR_MAX_TIMERS; i++) {
        const cr_timer_spec_t *spec = &e->protocol.timers[i];
        if (spec->role != CR_TIMER_DRUG_INTERVAL) continue;

        if (!cr_engine_interval_is_running(e, spec)) continue;
        // A fresh dose moves the anchor, so running out again is a new event.
        // So does an undo, which rolls the anchor back to the dose before —
        // and that timer may already be overdue, which the crew should hear.
        if (state->interval[i] != e->interval_anchors[i] &&
            cr_engine_interval_remaining(e, spec, now) <= 0) {
            state->interval[i] = e->interval_anchors[i];
            emit(CR_CUE_MED_DUE, out, cap, &n);
        }
    }

    return n;
}
