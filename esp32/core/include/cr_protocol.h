// cr_protocol.h — a protocol is DATA (CodeCore/Models/ProtocolDefinition.swift).
//
// Timer roles carry the only semantics the engine needs:
//   CPR_CYCLE        — countdown to the pulse check; freezes while CPR is paused
//   DRUG_INTERVAL    — counts from the last dose of linked_drug_id; keeps
//                      running through pauses and pulse checks (intentional)
//   POST_ROSC_VITALS — reassessment cadence, only while in ROSC

#ifndef CR_PROTOCOL_H
#define CR_PROTOCOL_H

#include <stddef.h>
#include <stdint.h>

#include "cr_time.h"

typedef enum {
    CR_TIMER_CPR_CYCLE,
    CR_TIMER_DRUG_INTERVAL,
    CR_TIMER_POST_ROSC_VITALS,
} cr_timer_role_t;

typedef struct {
    const char *id;              // "timer.cpr"
    cr_timer_role_t role;
    const char *title;           // "CPR", "EPI"
    cr_ms_t duration_ms;         // 120 s, 180 s
    cr_ms_t window_ms;           // outer window ("q3–5 min" → 300 s); 0 = none
    const char *linked_drug_id;  // DRUG_INTERVAL only; NULL otherwise
    uint32_t color;
} cr_timer_spec_t;

#define CR_MAX_TIMERS 6
#define CR_MAX_PROTOCOL_EVENTS 12

typedef struct {
    const char *id;              // "pals.arrest"
    const char *name;            // "Cardiac Arrest"
    const char *short_name;      // "ARREST"
    const char *symbol;
    cr_timer_spec_t timers[CR_MAX_TIMERS];
    uint8_t timer_count;
    const char *event_ids[CR_MAX_PROTOCOL_EVENTS];   // ordered for the Events fan
    uint8_t event_id_count;
    const char *drug_set_id;
} cr_protocol_t;

const cr_timer_spec_t *cr_protocol_cycle_spec(const cr_protocol_t *p);    // NULL if none
const cr_timer_spec_t *cr_protocol_vitals_spec(const cr_protocol_t *p);   // NULL if none

/// Drug-interval specs in table order (Swift `intervalSpecs`).
size_t cr_protocol_interval_count(const cr_protocol_t *p);
const cr_timer_spec_t *cr_protocol_interval_spec(const cr_protocol_t *p, size_t n);

/// A copy with the user's timer lengths applied (AppSettings overrides).
/// CR_TIME_NONE keeps the protocol default. Like Swift, the interval
/// override applies to every DRUG_INTERVAL timer, not only epi.
cr_protocol_t cr_protocol_applying(const cr_protocol_t *base, cr_ms_t cycle_ms, cr_ms_t interval_ms);

#endif
