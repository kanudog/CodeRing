// scenario.c — the C half of the parity harness. Prints a canonical trace
// of one long code. Its Swift twin (SwiftParity/Sources/parity/main.swift)
// prints the same lines from CodeCore; `make parity` diffs them.
//
// Keep the two files line-for-line parallel.

#include <inttypes.h>
#include <stdio.h>
#include <string.h>

#include "cr_defaults.h"
#include "cr_engine.h"
#include "cr_text.h"

#define START CR_SEC(1000000)
#define T(sec) (START + CR_SEC(sec))

static cr_engine_t engine;

static void print_log(const cr_engine_t *e)
{
    for (uint16_t i = 0; i < e->session.event_count; i++) {
        const cr_event_t *ev = &e->session.events[i];
        char stamp[16];
        cr_format_offset(stamp, sizeof stamp, ev->offset_s);
        printf("EVENT %s | %s | %s | %s | %06X\n",
               stamp, ev->title, ev->detail[0] ? ev->detail : "-",
               cr_category_key(ev->category), (unsigned)(cr_event_tint(ev) & 0xFFFFFFu));
    }
}

static void print_clock(const cr_engine_t *e, int64_t at)
{
    cr_ms_t now = T(at);
    char hint[64];
    cr_ms_t vitals = 0;
    bool has_vitals = cr_engine_vitals_remaining(e, now, &vitals);
    printf("CLOCK t=%" PRId64 " elapsed=%" PRId64 " cycleRem=%" PRId64 " idx=%d pc=%" PRId64
           " rosc=%" PRId64 " vitals=",
           at, cr_engine_elapsed(e, now), cr_engine_cycle_remaining(e, now),
           (int)cr_engine_cycle_index(e), cr_engine_pulse_check_elapsed(e, now),
           cr_engine_rosc_elapsed(e, now));
    if (has_vitals) printf("%" PRId64, vitals); else printf("-");
    printf(" | %s\n", cr_engine_hint(e, now, hint, sizeof hint));

    size_t intervals = cr_protocol_interval_count(&e->protocol);
    for (size_t i = 0; i < intervals; i++) {
        const cr_timer_spec_t *spec = cr_protocol_interval_spec(&e->protocol, i);
        printf("INTERVAL t=%" PRId64 " %s run=%d rem=%" PRId64 " overdue=%d\n",
               at, spec->id, cr_engine_interval_is_running(e, spec) ? 1 : 0,
               cr_engine_interval_remaining(e, spec, now),
               cr_engine_interval_is_overdue(e, spec, now) ? 1 : 0);
    }
}

static void print_timers(const cr_engine_t *e, int64_t at)
{
    cr_running_timer_t timers[CR_MAX_RUNNING_TIMERS];
    size_t n = cr_session_running_timers(&e->session, timers, CR_MAX_RUNNING_TIMERS);
    for (size_t i = 0; i < n; i++) {
        printf("TIMER %s | %s | %" PRId64 " | %06X\n",
               timers[i].id, timers[i].title,
               cr_running_timer_elapsed(&timers[i], T(at)),
               (unsigned)(timers[i].color & 0xFFFFFFu));
    }
}

static void print_stats(const cr_engine_t *e, int64_t at)
{
    cr_stats_t s;
    cr_session_stats(&e->session, T(at), &s);
    printf("STATS total=%" PRId64 " paused=%" PRId64 " frac=%.3f pauses=%d epi=%d shocks=%d rhythm=%d",
           s.total_ms, s.paused_ms, s.cpr_fraction, (int)s.pause_count,
           (int)s.epi_count, (int)s.shock_count, (int)s.rhythm_check_count);
    if (s.has_first_epi) printf(" firstEpi=%d", (int)s.seconds_to_first_epi); else printf(" firstEpi=-");
    if (s.has_rosc) printf(" rosc=%d\n", (int)s.seconds_to_rosc); else printf(" rosc=-\n");
    // Sorted by name: Swift tallies into a dictionary, which has no order.
    for (uint8_t i = 0; i < s.med_count; i++) {
        uint8_t best = i;
        for (uint8_t j = i + 1; j < s.med_count; j++) {
            if (strcmp(s.meds[j].title, s.meds[best].title) < 0) best = j;
        }
        cr_med_tally_t swap = s.meds[i];
        s.meds[i] = s.meds[best];
        s.meds[best] = swap;
        printf("MED %s = %d\n", s.meds[i].title, (int)s.meds[i].count);
    }
}

int main(void)
{
    cr_patient_t patient;
    memset(&patient, 0, sizeof patient);
    patient.weight_kg = 10;
    patient.source = CR_WEIGHT_MANUAL;
    cr_engine_init(&engine, &cr_protocol_pals_arrest, &cr_pals_drug_set,
                   cr_builtin_events, cr_builtin_event_count,
                   &patient, START, "PARITY", "parity");
    cr_engine_t *e = &engine;

    print_clock(e, 0);
    cr_engine_start_cpr(e, T(5));
    print_clock(e, 20);

    cr_engine_log_drug(e, &cr_drug_epinephrine, -1, T(30));
    cr_engine_log_event_def(e, cr_builtin_event("access.iv"), "R leg", T(41));
    print_clock(e, 60);

    cr_engine_toggle_pause(e, T(70));
    print_clock(e, 85);
    cr_engine_toggle_pause(e, T(90));
    print_clock(e, 95);

    cr_engine_log_drug(e, &cr_drug_defibrillation, 1, T(101));   // forced rung: "Subsequent"
    cr_engine_log_drug(e, &cr_drug_adenosine, -1, T(112));       // ladder rung 1
    cr_engine_log_drug(e, &cr_drug_adenosine, -1, T(123));       // ladder rung 2
    cr_engine_log_drug(e, &cr_drug_fluids, 1, T(134));           // 20 mL/kg
    print_clock(e, 140);

    cr_engine_begin_pulse_check(e, T(150));
    print_clock(e, 158);
    cr_engine_complete_pulse_check(e, false, T(162));
    print_clock(e, 170);

    cr_engine_update_weight(e, 24, T(181));
    cr_engine_log_drug(e, &cr_drug_epinephrine, -1, T(192));     // recomputed from 24 kg
    cr_engine_log_event_def(e, cr_builtin_event("airway.ett"), NULL, T(203));
    cr_engine_log_event(e, "Cardioversion", "50 J", CR_CAT_DEFIBRILLATION,
                        "shock.sync", CR_THEME_SHOCK, T(214));
    print_clock(e, 220);
    print_timers(e, 220);

    cr_event_t removed;
    if (cr_engine_undo_last(e, &removed)) printf("UNDO %s\n", removed.title);

    cr_engine_begin_pulse_check(e, T(230));
    cr_engine_complete_pulse_check(e, true, T(238));             // pulse found → ROSC
    print_clock(e, 250);

    cr_engine_confirm_vitals(e, T(300));
    print_clock(e, 400);
    cr_engine_re_arrest(e, T(500));
    print_clock(e, 520);
    cr_engine_log_drug(e, &cr_drug_amiodarone, -1, T(531));
    cr_engine_mark_rosc(e, T(560));
    print_clock(e, 580);

    cr_engine_end(e, T(600));
    print_clock(e, 610);
    print_timers(e, 610);
    print_log(e);
    print_stats(e, 610);
    return 0;
}
