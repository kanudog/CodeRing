// Port-only tests: things the watch got for free from Swift and Foundation
// and this build has to guarantee itself — fixed memory, UTF-8 safety, and
// the permanence of the stable ids.

#include <stdio.h>
#include <string.h>

#include "cr_test.h"
#include "cr_text.h"
#include "test_helpers.h"

#define START CR_SEC(1000000)
#define T(sec) (START + CR_SEC(sec))

static cr_engine_t engine;

// Port.stableIdsArePermanentAndUnique — invariant 1. spec_coverage.sh also
// diffs these against Defaults.swift on every run.
static void test_stable_ids_are_permanent_and_unique(void)
{
    const char *ids[] = {
        CR_ID_PALS_SET, CR_ID_EPI, CR_ID_AMIO, CR_ID_ATROPINE, CR_ID_ADENOSINE,
        CR_ID_DEFIB, CR_ID_LIDOCAINE, CR_ID_FLUIDS, CR_ID_DEXTROSE, CR_ID_CALCIUM,
        CR_ID_BICARB, CR_ID_MAGNESIUM, CR_ID_NALOXONE, CR_ID_EXAMPLITOL,
    };
    size_t n = sizeof ids / sizeof ids[0];
    for (size_t i = 0; i < n; i++) {
        CHECK_I(strlen(ids[i]), 36);
        CHECK(strncmp(ids[i], "C0DE0000-", 9) == 0);
        for (size_t j = i + 1; j < n; j++) CHECK(strcmp(ids[i], ids[j]) != 0);
    }
    CHECK_STR(cr_drug_epinephrine.id, CR_ID_EPI);
    CHECK_STR(cr_pals_drug_set.id, CR_ID_PALS_SET);
}

// Port.defaultsInventoryMatchesTheWatch — a drug or event quietly dropped in
// translation would be a silently missing button.
static void test_defaults_inventory_matches_the_watch(void)
{
    CHECK_I(cr_pals_drug_set.drug_count, 12);
    CHECK_I(cr_builtin_event_count, 16);
    CHECK_I(cr_protocol_choice_count, 14);
    CHECK_I(cr_protocol_top_count, 5);

    // Every drug in the set resolves, and every drug-interval timer points
    // at a drug that actually exists.
    for (uint8_t i = 0; i < cr_pals_drug_set.drug_count; i++) {
        const cr_drug_t *drug = cr_pals_drug_set.drugs[i];
        CHECK(drug != NULL);
        if (drug == NULL) continue;
        CHECK(cr_drug_set_find(&cr_pals_drug_set, drug->id) == drug);
        CHECK(drug->step_count > 0 && drug->step_count <= CR_MAX_DOSE_STEPS);
    }
    for (size_t p = 0; p < cr_protocol_choice_count; p++) {
        const cr_protocol_t *proto = cr_protocol_choices[p];
        CHECK(cr_protocol_cycle_spec(proto) != NULL);
        CHECK(cr_protocol_vitals_spec(proto) != NULL);
        for (uint8_t t = 0; t < proto->timer_count; t++) {
            if (proto->timers[t].role != CR_TIMER_DRUG_INTERVAL) continue;
            CHECK(cr_drug_set_find(&cr_pals_drug_set, proto->timers[t].linked_drug_id) != NULL);
        }
        for (uint8_t ev = 0; ev < proto->event_id_count; ev++) {
            CHECK(cr_builtin_event(proto->event_ids[ev]) != NULL);
        }
    }
}

// Port.logFullRefusesDrugsButNeverBlocksAPulseCheck — the clinical state
// machine has to keep working when the paper trail runs out, and the
// overflow has to be visible rather than silent.
static void test_log_full_refuses_drugs_but_never_blocks_a_pulse_check(void)
{
    test_make_engine(&engine, START);
    cr_engine_t *e = &engine;
    cr_engine_start_cpr(e, START);

    while (e->session.event_count < CR_MAX_EVENTS) {
        cr_engine_log_event(e, "Filler", NULL, CR_CAT_CUSTOM, "filler", CR_COLOR_NONE, T(1));
    }
    CHECK(!e->overflow);

    // A dose that cannot be recorded is refused outright — and must not have
    // restarted the timer that says when the next one is due.
    CHECK(!cr_engine_log_drug(e, &cr_drug_epinephrine, -1, T(2)));
    CHECK(e->overflow);
    CHECK(!cr_engine_interval_is_running(e, cr_protocol_interval_spec(&e->protocol, 0)));
    CHECK_I(e->session.event_count, CR_MAX_EVENTS);

    // The pulse check still runs: the cycle must close even unrecorded.
    CHECK(cr_engine_begin_pulse_check(e, T(3)));
    CHECK(e->in_pulse_check);
    CHECK_I(e->session.pause_count, 1);
    CHECK(cr_engine_complete_pulse_check(e, false, T(13)));
    CHECK_I(cr_engine_cycle_index(e), 1);
    CHECK_I(cr_pause_ms(&e->session.pauses[0], T(999)), CR_SEC(10));
}

// Port.pauseLogFullStillTracksTheClock
static void test_pause_log_full_still_tracks_the_clock(void)
{
    test_make_engine(&engine, START);
    cr_engine_t *e = &engine;
    cr_engine_start_cpr(e, START);

    // Fill the pause table with completed pauses. Two log lines per pause
    // means the log runs out on the way, which is the real worst case.
    int64_t at = 1;
    while (e->session.pause_count < CR_MAX_PAUSES) {
        cr_engine_toggle_pause(e, START + CR_SEC(at));
        cr_engine_toggle_pause(e, START + CR_SEC(at + 1));
        at += 2;
    }
    CHECK_I(e->session.pause_count, CR_MAX_PAUSES);
    CHECK(e->overflow);                                  // and it says so

    // With both tables full the records are gone, but the clock is not: a
    // pause still freezes the cycle and a resume still slides it forward.
    cr_ms_t pause_at = START + CR_SEC(at);
    cr_ms_t at_pause = cr_engine_cycle_remaining(e, pause_at);
    CHECK(cr_engine_toggle_pause(e, pause_at));
    CHECK(e->paused);
    CHECK_I(cr_engine_cycle_remaining(e, pause_at + CR_SEC(30)), at_pause);   // frozen
    CHECK(cr_engine_toggle_pause(e, pause_at + CR_SEC(30)));
    CHECK(!e->paused);
    // Resuming slides the anchor by the gap, so the countdown picks up
    // exactly where it froze instead of losing 30 s.
    CHECK_I(cr_engine_cycle_remaining(e, pause_at + CR_SEC(30)), at_pause);
}

// Port.runningTimersNeverOverrunTheirBuffer
static void test_running_timers_never_overrun_their_buffer(void)
{
    test_make_engine(&engine, START);
    cr_engine_t *e = &engine;
    for (int i = 0; i < CR_MAX_RUNNING_TIMERS + 10; i++) {
        char id[32];
        snprintf(id, sizeof id, "custom.%d", i);
        cr_engine_log_event(e, "Custom", NULL, CR_CAT_CUSTOM, id, CR_COLOR_NONE, T(i + 1));
    }
    cr_running_timer_t timers[CR_MAX_RUNNING_TIMERS];
    size_t n = cr_session_running_timers(&e->session, timers, CR_MAX_RUNNING_TIMERS);
    CHECK_I(n, CR_MAX_RUNNING_TIMERS);
    CHECK_STR(timers[0].id, "total");
    // Everything after row 0 is stalest-first.
    for (size_t i = 2; i < n; i++) CHECK(timers[i - 1].since <= timers[i].since);
}

// Port.longTextTruncatesOnACharacterBoundary — a custom name from the phone
// can be longer than the fixed buffers, and must never leave half a
// character behind (the log, the TV and the CSV all re-read these bytes).
static void test_long_text_truncates_on_a_character_boundary(void)
{
    char buf[8];
    size_t n = cr_copy_utf8(buf, sizeof buf, "CaCl₂ 100 mg/mL");
    CHECK(n < sizeof buf);
    CHECK_STR(buf, "CaCl₂");           // the subscript survives whole
    cr_copy_utf8(buf, sizeof buf, "ααααααααα");
    CHECK_STR(buf, "ααα");             // 2-byte chars, never split
    cr_copy_utf8(buf, sizeof buf, NULL);
    CHECK_STR(buf, "");

    test_make_engine(&engine, START);
    cr_engine_log_event(&engine, "Épinéphrine à très long nom de médicament",
                        NULL, CR_CAT_MEDICATION, "custom.long", CR_COLOR_NONE, T(1));
    const cr_event_t *ev = test_first_event(&engine, "custom.long");
    CHECK(ev != NULL);
    if (ev == NULL) return;
    CHECK(strlen(ev->title) < CR_TITLE_MAX);
    // A clean truncation means the last byte is never a stray continuation.
    CHECK((ev->title[strlen(ev->title) - 1] & 0xC0) != 0x80);
}

// Port.clockFormattingMatchesTheWatch
static void test_clock_formatting_matches_the_watch(void)
{
    char buf[16];
    cr_format_clock(buf, sizeof buf, CR_SEC(125));   CHECK_STR(buf, "2:05");
    cr_format_clock(buf, sizeof buf, CR_SEC(-5));    CHECK_STR(buf, "0:00");
    cr_format_clock(buf, sizeof buf, 1999);          CHECK_STR(buf, "0:01");   // floors
    cr_format_clock_signed(buf, sizeof buf, CR_SEC(-65));  CHECK_STR(buf, "-1:05");
    cr_format_clock_signed(buf, sizeof buf, CR_SEC(65));   CHECK_STR(buf, "1:05");
    cr_format_offset(buf, sizeof buf, 83);           CHECK_STR(buf, "+1:23");
    cr_format_offset(buf, sizeof buf, -3);           CHECK_STR(buf, "+0:00");
}

// Port.statsTallyEveryMedByName
static void test_stats_tally_every_med_by_name(void)
{
    test_make_engine(&engine, START);
    cr_engine_t *e = &engine;
    cr_engine_start_cpr(e, START);
    cr_engine_log_drug(e, &cr_drug_epinephrine, -1, T(60));
    cr_engine_log_drug(e, &cr_drug_epinephrine, -1, T(240));
    cr_engine_log_drug(e, &cr_drug_amiodarone, -1, T(300));
    cr_engine_log_drug(e, &cr_drug_defibrillation, -1, T(310));
    cr_engine_log_event_def(e, cr_builtin_event("rhythm.check"), NULL, T(320));
    cr_engine_end(e, T(400));

    cr_stats_t stats;
    cr_session_stats(&e->session, T(400), &stats);
    CHECK_I(stats.epi_count, 2);
    CHECK_I(stats.shock_count, 1);
    CHECK_I(stats.rhythm_check_count, 1);
    CHECK_I(stats.seconds_to_first_epi, 60);
    CHECK(stats.has_first_epi);
    CHECK_I(stats.med_count, 2);                 // epinephrine and amiodarone
    CHECK_STR(stats.meds[0].title, "Epinephrine");
    CHECK_I(stats.meds[0].count, 2);
    CHECK_I(stats.total_ms, CR_SEC(400));
    CHECK(!stats.has_rosc);
}

// Port.medChipsKeepEpiAndDropTheStalest — six slots around the ring, and
// the one the protocol is timed around never loses its place.
static void test_med_chips_keep_epi_and_drop_the_stalest(void)
{
    test_make_engine(&engine, START);
    cr_engine_t *e = &engine;
    cr_engine_start_cpr(e, START);

    cr_engine_log_drug(e, &cr_drug_epinephrine, -1, T(10));     // first, and stalest
    cr_engine_log_drug(e, &cr_drug_atropine, -1, T(20));
    cr_engine_log_drug(e, &cr_drug_adenosine, -1, T(30));
    cr_engine_log_drug(e, &cr_drug_amiodarone, -1, T(40));
    cr_engine_log_drug(e, &cr_drug_lidocaine, -1, T(50));
    cr_engine_log_drug(e, &cr_drug_calcium, -1, T(60));

    cr_med_chip_t chips[6];
    size_t n = cr_session_med_chips(&e->session, CR_ID_EPI, chips, 6);
    CHECK_I(n, 6);
    CHECK_STR(chips[0].key, CR_ID_EPI);                          // first-seen order
    CHECK_I(chips[0].count, 1);

    // A seventh item pushes the stalest NON-epi out — epi stays.
    cr_engine_log_drug(e, &cr_drug_bicarb, -1, T(70));
    n = cr_session_med_chips(&e->session, CR_ID_EPI, chips, 6);
    CHECK_I(n, 6);
    CHECK_STR(chips[0].key, CR_ID_EPI);
    bool has_atropine = false;
    for (size_t i = 0; i < n; i++) {
        if (strcmp(chips[i].key, CR_ID_ATROPINE) == 0) has_atropine = true;
    }
    CHECK(!has_atropine);                                        // it was the stalest

    // A repeat updates the count and the clock, not the slot.
    cr_engine_log_drug(e, &cr_drug_epinephrine, -1, T(200));
    n = cr_session_med_chips(&e->session, CR_ID_EPI, chips, 6);
    CHECK_STR(chips[0].key, CR_ID_EPI);
    CHECK_I(chips[0].count, 2);
    CHECK_I(chips[0].since, T(200));
}

const cr_test_case_t cr_port_tests[] = {
    { "Port.medChipsKeepEpiAndDropTheStalest", test_med_chips_keep_epi_and_drop_the_stalest },
    { "Port.stableIdsArePermanentAndUnique", test_stable_ids_are_permanent_and_unique },
    { "Port.defaultsInventoryMatchesTheWatch", test_defaults_inventory_matches_the_watch },
    { "Port.logFullRefusesDrugsButNeverBlocksAPulseCheck",
      test_log_full_refuses_drugs_but_never_blocks_a_pulse_check },
    { "Port.pauseLogFullStillTracksTheClock", test_pause_log_full_still_tracks_the_clock },
    { "Port.runningTimersNeverOverrunTheirBuffer", test_running_timers_never_overrun_their_buffer },
    { "Port.longTextTruncatesOnACharacterBoundary", test_long_text_truncates_on_a_character_boundary },
    { "Port.clockFormattingMatchesTheWatch", test_clock_formatting_matches_the_watch },
    { "Port.statsTallyEveryMedByName", test_stats_tally_every_med_by_name },
};
const size_t cr_port_test_count = sizeof cr_port_tests / sizeof cr_port_tests[0];
