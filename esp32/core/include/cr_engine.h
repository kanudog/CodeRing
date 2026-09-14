// cr_engine.h — the beating heart (CodeCore/Engine/SessionEngine.swift).
//
// Design rules carried over from the watch, and they matter more here:
//   • The engine owns NO timers and reads NO clock (invariant 4). It stores
//     anchors and derives every countdown from the `now` the caller passes,
//     so nothing drifts while the CPU sleeps and every rule is testable.
//   • The CPR cycle freezes during a pause; drug-interval timers keep
//     running through pauses and pulse checks. Both are deliberate.
//   • A cycle only closes through a pulse check, and its countdown runs
//     NEGATIVE until then, so overdue time stays visible.
//   • Every action is one function; nothing else mutates the session.
//
// Actions return true when they changed something. Swift returns Void and
// leaves the UI to infer it; here the caller needs the answer, because a
// gesture that logs nothing MUST say so — silence after a deliberate action
// is this app's worst failure mode.

#ifndef CR_ENGINE_H
#define CR_ENGINE_H

#include <stdbool.h>
#include <stddef.h>

#include "cr_defaults.h"
#include "cr_drugs.h"
#include "cr_events.h"
#include "cr_protocol.h"
#include "cr_session.h"
#include "cr_time.h"

typedef struct {
    cr_session_t session;
    cr_protocol_t protocol;            // a copy: settings overrides edit timer lengths
    const cr_drug_set_t *drug_set;
    const cr_event_def_t *event_defs;
    size_t event_def_count;

    bool paused;
    bool ended;
    bool cpr_started;                  // GO starts the code clock; this starts compressions
    bool in_pulse_check;
    bool rosc_achieved;                // live state; session.rosc keeps the FIRST ROSC

    cr_ms_t cycle_anchor;
    cr_ms_t pause_started_at;          // CR_TIME_NONE when not paused
    cr_ms_t pulse_check_started_at;
    cr_ms_t last_rosc_at;              // latest ROSC — drives the post-ROSC clock
    cr_ms_t vitals_anchor;
    int32_t completed_cycles;
    cr_ms_t interval_anchors[CR_MAX_TIMERS];   // by timer index; NONE = idle

    uint32_t next_seq;
    uint32_t log_rev;                  // bumps on every log change; the TV diffs on it
    bool overflow;                     // a record did not fit — surface it, never hide it
} cr_engine_t;

/// `patient` and the definition tables are copied/borrowed as-is. Static
/// tables (cr_defaults) outlive the engine; a custom drug set must too.
void cr_engine_init(cr_engine_t *e,
                    const cr_protocol_t *protocol,
                    const cr_drug_set_t *drug_set,
                    const cr_event_def_t *event_defs, size_t event_def_count,
                    const cr_patient_t *patient,
                    cr_ms_t start,
                    const char *session_id,      // NULL → ""
                    const char *device_name);    // NULL → ""

// MARK: - Clock (all pure; safe to call every frame)

cr_ms_t cr_engine_elapsed(const cr_engine_t *e, cr_ms_t now);

/// Time to the pulse check that ends this cycle. NEGATIVE once overdue.
/// Frozen while paused or mid-check; full length before Start CPR.
cr_ms_t cr_engine_cycle_remaining(const cr_engine_t *e, cr_ms_t now);

/// Completed cycles (0-based). Increments when a pulse check completes, not
/// on a wall-clock wrap.
int32_t cr_engine_cycle_index(const cr_engine_t *e);

/// Seconds in the current pulse check; 0 when not checking. The UI turns
/// this red past the 10 s hands-off target.
cr_ms_t cr_engine_pulse_check_elapsed(const cr_engine_t *e, cr_ms_t now);

/// Since the LATEST ROSC (a re-arrest resets this; session.rosc does not).
cr_ms_t cr_engine_rosc_elapsed(const cr_engine_t *e, cr_ms_t now);

/// Countdown to the next post-ROSC reassessment; negative = overdue.
/// False when not in ROSC or the protocol has no vitals cadence.
bool cr_engine_vitals_remaining(const cr_engine_t *e, cr_ms_t now, cr_ms_t *out);

/// Remaining time on a drug-interval timer; negative = overdue. An idle
/// timer (drug never given) reports its full length — check
/// cr_engine_interval_is_running before drawing a countdown.
cr_ms_t cr_engine_interval_remaining(const cr_engine_t *e, const cr_timer_spec_t *spec, cr_ms_t now);
bool cr_engine_interval_is_running(const cr_engine_t *e, const cr_timer_spec_t *spec);
bool cr_engine_interval_is_overdue(const cr_engine_t *e, const cr_timer_spec_t *spec, cr_ms_t now);

/// One line of guidance for the header. Writes into `buf` and returns it.
const char *cr_engine_hint(const cr_engine_t *e, cr_ms_t now, char *buf, size_t cap);

// MARK: - Actions

/// Logs a drug with a computed dose snapshot and advances its ladder by the
/// prior count. `forced_step` < 0 uses that count (the shock fan passes an
/// explicit rung). False = nothing logged: tell the user.
bool cr_engine_log_drug(cr_engine_t *e, const cr_drug_t *drug, int forced_step, cr_ms_t now);

/// Logs a defined event, optionally with a chosen sub-option (limb, device).
/// "outcome.rosc" routes to cr_engine_mark_rosc, exactly as on the watch.
bool cr_engine_log_event_def(cr_engine_t *e, const cr_event_def_t *def,
                             const char *sub_option, cr_ms_t now);

/// Logs an ad-hoc leaf straight from the menu tree, which carries its own
/// title/category/colour rather than a definition.
bool cr_engine_log_event(cr_engine_t *e, const char *title, const char *detail,
                         cr_category_t category, const char *definition_id,
                         uint32_t color, cr_ms_t now);

/// Compressions begin: anchors the first cycle. GO and this are different
/// moments on purpose.
bool cr_engine_start_cpr(cr_engine_t *e, cr_ms_t now);

/// Mid-code weight correction; every later dose recomputes from it. The
/// change goes on the record and undo deliberately cannot remove it.
bool cr_engine_update_weight(cr_engine_t *e, double kg, cr_ms_t now);

/// The hands-off check that closes the cycle. It IS interrupted CPR, so it
/// opens a pause interval and counts against the CPR fraction.
bool cr_engine_begin_pulse_check(cr_engine_t *e, cr_ms_t now);
bool cr_engine_complete_pulse_check(cr_engine_t *e, bool pulse_found, cr_ms_t now);

bool cr_engine_toggle_pause(cr_engine_t *e, cr_ms_t now);
bool cr_engine_mark_rosc(cr_engine_t *e, cr_ms_t now);
/// Pulses lost after ROSC: back to CPR with a fresh cycle. Drug anchors are
/// deliberately untouched — time since the last epi still matters.
bool cr_engine_re_arrest(cr_engine_t *e, cr_ms_t now);
bool cr_engine_confirm_vitals(cr_engine_t *e, cr_ms_t now);
bool cr_engine_end(cr_engine_t *e, cr_ms_t now);

/// Re-label a running code (identity only; no anchor moves).
void cr_engine_change_protocol(cr_engine_t *e, const cr_protocol_t *protocol);

// MARK: - Undo

/// The entry cr_engine_undo_last would remove; NULL when there is none.
/// Structural records — CPR and outcome categories, pulse.check,
/// rosc.vitals, patient.weight — anchor cycle, pause and weight state, so
/// undo steps past them. A wrong ROSC has its own escape hatch: re-arrest.
const cr_event_t *cr_engine_last_undoable(const cr_engine_t *e);

/// Removes the newest user-logged entry (mis-taps happen mid-code). Ladders
/// and chip counts re-derive from the log; the linked interval anchor rolls
/// back to the previous dose still on record, or goes idle.
bool cr_engine_undo_last(cr_engine_t *e, cr_event_t *removed_out);

#endif
