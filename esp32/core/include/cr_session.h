// cr_session.h — one complete code, from GO to end
// (CodeCore/Models/Session.swift). Owns the event log, the pause intervals
// and the patient snapshot, and derives the numbers the summary needs.
//
// Fixed capacities, zero allocation: the whole session is one struct the
// firmware can place in PSRAM and write to flash verbatim. Everything a
// logged record needs is COPIED in, so no pointer here outlives a reboot.

#ifndef CR_SESSION_H
#define CR_SESSION_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "cr_events.h"
#include "cr_patient.h"
#include "cr_theme.h"
#include "cr_time.h"

#define CR_TITLE_MAX   40
#define CR_DETAIL_MAX  64
#define CR_DEF_ID_MAX  48   // "custom.<uuid>" is 43
#define CR_ID_MAX      40   // a UUID string is 36

/// ~100 kB of session at these sizes. A long code logs well under 512
/// entries; the engine refuses a new one rather than overwrite history, and
/// says so loudly (cr_engine_t.overflow) instead of dropping it in silence.
#define CR_MAX_EVENTS  512
#define CR_MAX_PAUSES  256

typedef struct {
    cr_ms_t start;
    cr_ms_t end;        // CR_TIME_NONE while the pause is still open
} cr_pause_t;

/// Hands-off seconds, clamping an open interval to `limit`.
cr_ms_t cr_pause_ms(const cr_pause_t *pause, cr_ms_t limit);

typedef struct {
    uint32_t seq;                       // stable per session; the TV diffs on it
    cr_ms_t date;
    int32_t offset_s;                   // seconds since GO, frozen at log time
    char title[CR_TITLE_MAX];
    char detail[CR_DETAIL_MAX];         // "" = none
    cr_category_t category;
    char definition_id[CR_DEF_ID_MAX];  // "" = none; drug UUID or event key
    uint32_t color;                     // CR_COLOR_NONE → the category colour
} cr_event_t;

/// The item's own hue, frozen at log time, else its category's.
uint32_t cr_event_tint(const cr_event_t *event);

typedef struct {
    char id[CR_ID_MAX];
    char protocol_id[40];
    char protocol_name[40];
    cr_ms_t start;
    cr_ms_t end;         // CR_TIME_NONE until the code ends
    cr_ms_t rosc;        // the FIRST ROSC; re-arrest never rewrites it
    cr_patient_t patient;
    cr_event_t events[CR_MAX_EVENTS];
    uint16_t event_count;
    cr_pause_t pauses[CR_MAX_PAUSES];
    uint16_t pause_count;
    char device_name[32];
} cr_session_t;

cr_ms_t cr_session_duration(const cr_session_t *s, cr_ms_t now);
cr_ms_t cr_session_paused_ms(const cr_session_t *s, cr_ms_t now);

/// One live "time since X" row.
typedef struct {
    const char *id;      // points into the session's event storage, or "total"
    const char *title;
    cr_ms_t since;
    uint32_t color;
} cr_running_timer_t;

#define CR_MAX_RUNNING_TIMERS 32

cr_ms_t cr_running_timer_elapsed(const cr_running_timer_t *timer, cr_ms_t now);

/// Total code time plus a since-last row for things the algorithm REPEATS —
/// meds, shocks, rhythm/pulse checks, compressor swaps, vitals, customs.
/// One-shots (access, intubation, CPR started) answer no clinical question
/// mid-code and get no row. Total is row 0; the rest are stalest-first.
/// Pointers stay valid until the next engine mutation.
size_t cr_session_running_timers(const cr_session_t *s, cr_running_timer_t *out, size_t cap);

#define CR_MAX_MED_TALLY 16

typedef struct {
    char title[CR_TITLE_MAX];
    uint16_t count;
} cr_med_tally_t;

typedef struct {
    cr_ms_t total_ms;
    cr_ms_t paused_ms;
    double cpr_fraction;        // 0…1 of the pre-ROSC span with compressions running
    uint16_t pause_count;
    uint16_t epi_count;
    uint16_t shock_count;
    uint16_t rhythm_check_count;
    cr_med_tally_t meds[CR_MAX_MED_TALLY];
    uint8_t med_count;          // distinct drugs beyond the 16th are not tallied
    bool has_first_epi;
    int32_t seconds_to_first_epi;
    bool has_rosc;
    int32_t seconds_to_rosc;
} cr_stats_t;

void cr_session_stats(const cr_session_t *s, cr_ms_t now, cr_stats_t *out);

/// One med-timer chip: the drugs, shocks and fluids already given, each with
/// how many times and how long since the last one. These ride around the
/// ring on the live screen.
typedef struct {
    const char *key;      // definition id, pointing into the session's storage
    const char *title;
    uint32_t color;       // the item's own hue, frozen when it was logged
    uint16_t count;
    cr_ms_t since;
} cr_med_chip_t;

/// Newest-per-key in FIRST-SEEN order, capped at `cap`. When there are more
/// than fit, the STALEST drops off — except `keep_key` (epinephrine on the
/// watch), which never does. Everything stays in the timers list regardless.
size_t cr_session_med_chips(const cr_session_t *s, const char *keep_key,
                            cr_med_chip_t *out, size_t cap);

#endif
