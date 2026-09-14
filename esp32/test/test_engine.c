// Ported from SessionEngineTests — the clinical rules. Every anchor is
// injected, so these run in zero time and never touch a real clock.

#include <string.h>

#include "cr_test.h"
#include "test_helpers.h"

#define START CR_SEC(1000000)
#define T(sec) (START + CR_SEC(sec))

// 100 kB of session: static, never on the stack.
static cr_engine_t engine;

static cr_engine_t *fresh(void)
{
    test_make_engine(&engine, START);
    return &engine;
}

/// The epi interval, taken from the defaults exactly as the Swift tests do —
/// which also proves anchors are keyed by timer id, not by array index.
static const cr_timer_spec_t *epi_spec(void)
{
    return cr_protocol_interval_spec(&cr_protocol_pals_arrest, 0);
}

// SessionEngineTests.testCycleCountdownGoesOverdueUntilPulseCheck
static void test_cycle_countdown_goes_overdue_until_pulse_check(void)
{
    // Cycles no longer wrap on the wall clock: the countdown runs negative
    // until a pulse check completes, which is what closes the cycle.
    cr_engine_t *e = fresh();
    cr_engine_start_cpr(e, START);
    CHECK_I(cr_engine_cycle_remaining(e, START), CR_SEC(120));
    CHECK_I(cr_engine_cycle_remaining(e, T(30)), CR_SEC(90));
    CHECK_I(cr_engine_cycle_remaining(e, T(125)), CR_SEC(-5));
    CHECK_I(cr_engine_cycle_index(e), 0);                    // still cycle 1

    cr_engine_begin_pulse_check(e, T(130));
    // Frozen mid-check, and the check clock runs on its own.
    CHECK_I(cr_engine_cycle_remaining(e, T(137)), CR_SEC(-10));
    CHECK_I(cr_engine_pulse_check_elapsed(e, T(137)), CR_SEC(7));

    cr_engine_complete_pulse_check(e, false, T(140));
    CHECK_I(cr_engine_cycle_index(e), 1);
    CHECK_I(cr_engine_cycle_remaining(e, T(140)), CR_SEC(120));
    // The 10 s hands-off interval counts against the CPR fraction…
    CHECK_I(e->session.pause_count, 1);
    CHECK_I(cr_pause_ms(&e->session.pauses[0], T(999)), CR_SEC(10));
    // …and both bookends land in the log.
    CHECK(test_has_event(e, "pulse.check"));
    CHECK(test_has_event(e, "pulse.resume"));
}

// SessionEngineTests.testPulseFoundFlowsIntoROSC
static void test_pulse_found_flows_into_rosc(void)
{
    cr_engine_t *e = fresh();
    cr_engine_start_cpr(e, START);
    cr_engine_begin_pulse_check(e, T(120));
    cr_engine_complete_pulse_check(e, true, T(128));
    CHECK(e->rosc_achieved);
    CHECK(!e->in_pulse_check);
    CHECK(e->session.pauses[0].end != CR_TIME_NONE);
    CHECK(test_has_event(e, "pulse.found"));
}

// SessionEngineTests.testDrugIntervalRunsThroughPulseCheck
static void test_drug_interval_runs_through_pulse_check(void)
{
    // Same clinical rule as pauses: hands-off never freezes drug timers.
    cr_engine_t *e = fresh();
    cr_engine_start_cpr(e, START);
    cr_engine_log_drug(e, &cr_drug_epinephrine, -1, START);   // interval starts at first dose
    cr_engine_begin_pulse_check(e, T(100));
    cr_engine_complete_pulse_check(e, false, T(115));
    CHECK_I(cr_engine_interval_remaining(e, epi_spec(), T(115)), CR_SEC(65));   // 180 − 115
}

// SessionEngineTests.testRunningTimersListTotalAndSinceLast
static void test_running_timers_list_total_and_since_last(void)
{
    cr_engine_t *e = fresh();
    cr_engine_log_drug(e, &cr_drug_epinephrine, -1, T(60));
    cr_engine_log_drug(e, &cr_drug_epinephrine, -1, T(240));

    cr_running_timer_t timers[CR_MAX_RUNNING_TIMERS];
    size_t n = cr_session_running_timers(&e->session, timers, CR_MAX_RUNNING_TIMERS);
    CHECK_STR(timers[0].id, "total");
    CHECK_I(cr_running_timer_elapsed(&timers[0], T(300)), CR_SEC(300));

    // Only the LATEST epi drives its since-last timer.
    const cr_running_timer_t *epi = test_find_timer(timers, n, CR_ID_EPI);
    CHECK(epi != NULL);
    if (epi != NULL) CHECK_I(cr_running_timer_elapsed(epi, T(300)), CR_SEC(60));
}

// SessionEngineTests.testRunningTimersOnlyTrackRepeatables
static void test_running_timers_only_track_repeatables(void)
{
    cr_engine_t *e = fresh();
    cr_engine_start_cpr(e, START);
    cr_engine_log_drug(e, &cr_drug_epinephrine, -1, T(60));
    cr_engine_log_event_def(e, cr_builtin_event("access.iv"), "R arm", T(70));
    cr_engine_log_event_def(e, cr_builtin_event("airway.ett"), NULL, T(80));
    cr_engine_log_event_def(e, cr_builtin_event("cpr.swap"), NULL, T(90));

    cr_running_timer_t timers[CR_MAX_RUNNING_TIMERS];
    size_t n = cr_session_running_timers(&e->session, timers, CR_MAX_RUNNING_TIMERS);
    CHECK(test_find_timer(timers, n, "total") != NULL);
    CHECK(test_find_timer(timers, n, CR_ID_EPI) != NULL);      // med — repeatable
    CHECK(test_find_timer(timers, n, "cpr.swap") != NULL);     // swap — repeatable
    CHECK(test_find_timer(timers, n, "access.iv") == NULL);    // one-shots: no timer
    CHECK(test_find_timer(timers, n, "airway.ett") == NULL);
    CHECK(test_find_timer(timers, n, "cpr.start") == NULL);
}

// SessionEngineTests.testPauseFreezesCycleAndRecordsInterval
static void test_pause_freezes_cycle_and_records_interval(void)
{
    cr_engine_t *e = fresh();
    cr_engine_start_cpr(e, START);
    cr_engine_toggle_pause(e, T(40));                          // pause at t+40
    CHECK_I(cr_engine_cycle_remaining(e, T(70)), CR_SEC(80));  // still shows 80 s left
    cr_engine_toggle_pause(e, T(70));                          // resume after a 30 s gap
    CHECK_I(cr_engine_cycle_remaining(e, T(70)), CR_SEC(80));
    CHECK_I(e->session.pause_count, 1);
    CHECK_I(cr_pause_ms(&e->session.pauses[0], T(999)), CR_SEC(30));
}

// SessionEngineTests.testEpiIntervalIdleUntilFirstDoseThenResets
static void test_epi_interval_idle_until_first_dose_then_resets(void)
{
    cr_engine_t *e = fresh();
    const cr_timer_spec_t *spec = epi_spec();
    // Idle before any dose: no countdown, never overdue.
    CHECK(!cr_engine_interval_is_running(e, spec));
    CHECK(!cr_engine_interval_is_overdue(e, spec, T(999)));
    CHECK_I(cr_engine_interval_remaining(e, spec, T(100)), CR_SEC(180));   // full length while idle

    cr_engine_log_drug(e, &cr_drug_epinephrine, -1, T(100));
    CHECK(cr_engine_interval_is_running(e, spec));
    CHECK_I(cr_engine_interval_remaining(e, spec, T(160)), CR_SEC(120));   // from the dose, not GO

    // A second dose resets the countdown.
    cr_engine_log_drug(e, &cr_drug_epinephrine, -1, T(220));
    CHECK_I(cr_engine_interval_remaining(e, spec, T(220)), CR_SEC(180));
    CHECK_I(test_count_category(e, CR_CAT_MEDICATION), 2);
}

// SessionEngineTests.testStartCPRGatesCycleAndPulseCheck
static void test_start_cpr_gates_cycle_and_pulse_check(void)
{
    cr_engine_t *e = fresh();
    // Before Start CPR: the ring stays full and pulse checks refuse to
    // begin, but the code clock (GO) is already running.
    CHECK_I(cr_engine_cycle_remaining(e, T(500)), CR_SEC(120));
    CHECK(!cr_engine_begin_pulse_check(e, T(10)));
    CHECK(!e->in_pulse_check);
    CHECK_I(cr_engine_elapsed(e, T(500)), CR_SEC(500));

    cr_engine_start_cpr(e, T(45));
    CHECK_I(cr_engine_cycle_remaining(e, T(65)), CR_SEC(100));
    CHECK(test_has_event(e, "cpr.start"));
}

// SessionEngineTests.testLoggedEventCarriesItemColor
static void test_logged_event_carries_item_color(void)
{
    cr_engine_t *e = fresh();
    cr_engine_start_cpr(e, START);
    // A volume/support drug's timer must show BLUE, not the red med category.
    cr_engine_log_drug(e, &cr_drug_calcium, -1, T(30));
    const cr_event_t *calcium = test_last_in_category(e, CR_CAT_MEDICATION);
    CHECK(calcium != NULL);
    if (calcium != NULL) CHECK_I(cr_event_tint(calcium), CR_THEME_VOLUME);

    cr_running_timer_t timers[CR_MAX_RUNNING_TIMERS];
    size_t n = cr_session_running_timers(&e->session, timers, CR_MAX_RUNNING_TIMERS);
    const cr_running_timer_t *row = test_find_timer(timers, n, CR_ID_CALCIUM);
    CHECK(row != NULL);
    if (row != NULL) CHECK_I(row->color, CR_THEME_VOLUME);
}

// SessionEngineTests.testWeightChangeUpdatesDosesAndLogs
static void test_weight_change_updates_doses_and_logs(void)
{
    cr_engine_t *e = fresh();
    cr_engine_update_weight(e, 20, T(30));
    // The change is on the record…
    const cr_event_t *change = test_first_event(e, "patient.weight");
    CHECK(change != NULL);
    if (change != NULL) CHECK_STR(change->detail, "10.0 → 20.0 kg");
    // …and the next dose computes from the NEW weight (0.01 mg/kg × 20).
    cr_engine_log_drug(e, &cr_drug_epinephrine, -1, T(60));
    const cr_event_t *epi = test_last_in_category(e, CR_CAT_MEDICATION);
    CHECK(epi != NULL);
    if (epi != NULL) CHECK_HAS(epi->detail, "0.2 mg");
}

// SessionEngineTests.testRoscClosesPauseAndStopsFurtherPauses
static void test_rosc_closes_pause_and_stops_further_pauses(void)
{
    cr_engine_t *e = fresh();
    cr_engine_toggle_pause(e, T(10));
    cr_engine_mark_rosc(e, T(20));
    CHECK(e->rosc_achieved);
    CHECK(e->session.pauses[0].end != CR_TIME_NONE);
    CHECK(!cr_engine_toggle_pause(e, T(30)));   // ignored post-ROSC
    CHECK(!e->paused);
}

// SessionEngineTests.testReArrestReturnsToCPRAndKeepsFirstROSC
static void test_re_arrest_returns_to_cpr_and_keeps_first_rosc(void)
{
    cr_engine_t *e = fresh();
    cr_engine_mark_rosc(e, T(100));
    CHECK(e->rosc_achieved);

    cr_engine_re_arrest(e, T(200));
    CHECK(!e->rosc_achieved);
    // Fresh cycle from the re-arrest moment; pauses work again.
    CHECK_I(cr_engine_cycle_remaining(e, T(230)), CR_SEC(90));
    cr_engine_toggle_pause(e, T(240));
    CHECK(e->paused);
    cr_engine_toggle_pause(e, T(250));

    // Second ROSC: live state flips back, session.rosc still records the FIRST.
    cr_engine_mark_rosc(e, T(300));
    CHECK(e->rosc_achieved);
    CHECK_I(e->session.rosc, T(100));
    CHECK_I(cr_engine_rosc_elapsed(e, T(360)), CR_SEC(60));
    CHECK(test_has_event(e, "outcome.rearrest"));
    CHECK_I(test_count_events(e, "outcome.rosc"), 2);
}

// SessionEngineTests.testVitalsCadenceRunsOnlyInROSC
static void test_vitals_cadence_runs_only_in_rosc(void)
{
    cr_engine_t *e = fresh();
    cr_ms_t vitals = 0;
    CHECK(!cr_engine_vitals_remaining(e, T(10), &vitals));

    cr_engine_mark_rosc(e, T(100));
    CHECK(cr_engine_vitals_remaining(e, T(200), &vitals));
    CHECK_I(vitals, CR_SEC(200));                       // 300 s cadence, 100 s in
    // Overdue goes negative, same convention as the pulse check.
    CHECK(cr_engine_vitals_remaining(e, T(450), &vitals));
    CHECK_I(vitals, CR_SEC(-50));

    cr_engine_confirm_vitals(e, T(450));
    CHECK(cr_engine_vitals_remaining(e, T(500), &vitals));
    CHECK_I(vitals, CR_SEC(250));
    CHECK(test_has_event(e, "rosc.vitals"));

    cr_engine_re_arrest(e, T(600));
    CHECK(!cr_engine_vitals_remaining(e, T(610), &vitals));
}

// SessionEngineTests.testStatsCprFraction
static void test_stats_cpr_fraction(void)
{
    cr_engine_t *e = fresh();
    cr_engine_toggle_pause(e, T(30));
    cr_engine_toggle_pause(e, T(60));            // 30 s paused
    cr_engine_end(e, T(120));                    // 120 s total

    cr_stats_t stats;
    cr_session_stats(&e->session, T(120), &stats);
    CHECK_NEAR(stats.cpr_fraction, 0.75, 0.01);  // 90/120
    CHECK_I(stats.pause_count, 1);
}

// Port.hintNamesWhatToDoNext — the header line is the only guidance on a
// 2" screen, so each state has to produce its own sentence.
static void test_hint_names_what_to_do_next(void)
{
    cr_engine_t *e = fresh();
    char hint[64];

    CHECK_STR(cr_engine_hint(e, START, hint, sizeof hint), "Tap Start CPR when compressions begin");
    cr_engine_start_cpr(e, START);
    CHECK_STR(cr_engine_hint(e, T(10), hint, sizeof hint), "Continue high-quality CPR");
    CHECK_STR(cr_engine_hint(e, T(110), hint, sizeof hint), "Pulse check at cycle end");
    CHECK_STR(cr_engine_hint(e, T(130), hint, sizeof hint), "Pulse check overdue");

    cr_engine_toggle_pause(e, T(131));
    CHECK_STR(cr_engine_hint(e, T(132), hint, sizeof hint), "CPR PAUSED — resume compressions");
    cr_engine_toggle_pause(e, T(133));

    // An overdue drug interval names itself — but the cycle outranks it, so
    // this only shows once a pulse check has closed the cycle it was blocking.
    cr_engine_log_drug(e, &cr_drug_epinephrine, -1, T(133));
    cr_engine_begin_pulse_check(e, T(134));
    CHECK_STR(cr_engine_hint(e, T(135), hint, sizeof hint), "Hands off — checking pulse");
    cr_engine_complete_pulse_check(e, false, T(140));
    cr_engine_begin_pulse_check(e, T(250));
    cr_engine_complete_pulse_check(e, false, T(255));   // fresh cycle from here
    CHECK_STR(cr_engine_hint(e, T(320), hint, sizeof hint), "EPI due now");

    cr_engine_mark_rosc(e, T(340));
    CHECK_STR(cr_engine_hint(e, T(350), hint, sizeof hint), "ROSC — post-resuscitation care");
    CHECK_STR(cr_engine_hint(e, T(700), hint, sizeof hint), "Vitals check overdue");
    cr_engine_end(e, T(800));
    CHECK_STR(cr_engine_hint(e, T(800), hint, sizeof hint), "Code ended");
}

// Port.refusedActionsReportFalse — every gesture that changes nothing has to
// be distinguishable from one that did, or the UI cannot say "nothing logged".
static void test_refused_actions_report_false(void)
{
    cr_engine_t *e = fresh();
    CHECK(!cr_engine_begin_pulse_check(e, START));        // CPR not started
    CHECK(!cr_engine_complete_pulse_check(e, false, START));
    CHECK(!cr_engine_confirm_vitals(e, START));           // not in ROSC
    CHECK(!cr_engine_re_arrest(e, START));                // never arrested
    CHECK(!cr_engine_update_weight(e, 10.02, START));     // below the 0.049 kg threshold
    CHECK(!cr_engine_update_weight(e, 0, START));         // nonsense weight
    CHECK(!cr_engine_log_drug(e, NULL, -1, START));
    CHECK(!cr_engine_log_event_def(e, NULL, NULL, START));

    CHECK(cr_engine_start_cpr(e, START));
    CHECK(!cr_engine_start_cpr(e, T(5)));                 // already started
    CHECK(cr_engine_end(e, T(10)));
    CHECK(!cr_engine_end(e, T(20)));
    CHECK(!cr_engine_update_weight(e, 25, T(30)));        // the code is over
}

// Port.changeProtocolKeepsRunningAnchors — re-labelling mid-code must not
// restart the epi clock.
static void test_change_protocol_keeps_running_anchors(void)
{
    cr_engine_t *e = fresh();
    cr_engine_start_cpr(e, START);
    cr_engine_log_drug(e, &cr_drug_epinephrine, -1, T(60));

    const cr_protocol_t *vf = cr_protocol_by_id("pals.arrest.shockable");
    CHECK(vf != NULL);
    if (vf == NULL) return;
    cr_engine_change_protocol(e, vf);

    CHECK_STR(e->session.protocol_name, "VF / pVT");
    CHECK_STR(e->protocol.short_name, "VF/pVT");
    CHECK(cr_engine_interval_is_running(e, epi_spec()));
    CHECK_I(cr_engine_interval_remaining(e, epi_spec(), T(120)), CR_SEC(120));   // 180 − 60
    CHECK_I(cr_engine_cycle_remaining(e, T(60)), CR_SEC(60));                    // cycle untouched
}

// Port.settingsOverridesChangeTimerLengths — the user's own cycle/interval
// lengths have to reach a live engine.
static void test_settings_overrides_change_timer_lengths(void)
{
    cr_patient_t patient;
    memset(&patient, 0, sizeof patient);
    patient.weight_kg = 10;
    cr_protocol_t custom = cr_protocol_applying(&cr_protocol_pals_arrest, CR_SEC(90), CR_SEC(240));
    cr_engine_init(&engine, &custom, &cr_pals_drug_set, cr_builtin_events,
                   cr_builtin_event_count, &patient, START, "TEST", "test");
    cr_engine_t *e = &engine;

    cr_engine_start_cpr(e, START);
    CHECK_I(cr_engine_cycle_remaining(e, T(30)), CR_SEC(60));
    cr_engine_log_drug(e, &cr_drug_epinephrine, -1, T(30));
    CHECK_I(cr_engine_interval_remaining(e, cr_protocol_interval_spec(&e->protocol, 0), T(30)),
            CR_SEC(240));
}

const cr_test_case_t cr_engine_tests[] = {
    { "SessionEngineTests.testCycleCountdownGoesOverdueUntilPulseCheck",
      test_cycle_countdown_goes_overdue_until_pulse_check },
    { "SessionEngineTests.testPulseFoundFlowsIntoROSC", test_pulse_found_flows_into_rosc },
    { "SessionEngineTests.testDrugIntervalRunsThroughPulseCheck",
      test_drug_interval_runs_through_pulse_check },
    { "SessionEngineTests.testRunningTimersListTotalAndSinceLast",
      test_running_timers_list_total_and_since_last },
    { "SessionEngineTests.testRunningTimersOnlyTrackRepeatables",
      test_running_timers_only_track_repeatables },
    { "SessionEngineTests.testPauseFreezesCycleAndRecordsInterval",
      test_pause_freezes_cycle_and_records_interval },
    { "SessionEngineTests.testEpiIntervalIdleUntilFirstDoseThenResets",
      test_epi_interval_idle_until_first_dose_then_resets },
    { "SessionEngineTests.testStartCPRGatesCycleAndPulseCheck",
      test_start_cpr_gates_cycle_and_pulse_check },
    { "SessionEngineTests.testLoggedEventCarriesItemColor", test_logged_event_carries_item_color },
    { "SessionEngineTests.testWeightChangeUpdatesDosesAndLogs",
      test_weight_change_updates_doses_and_logs },
    { "SessionEngineTests.testRoscClosesPauseAndStopsFurtherPauses",
      test_rosc_closes_pause_and_stops_further_pauses },
    { "SessionEngineTests.testReArrestReturnsToCPRAndKeepsFirstROSC",
      test_re_arrest_returns_to_cpr_and_keeps_first_rosc },
    { "SessionEngineTests.testVitalsCadenceRunsOnlyInROSC", test_vitals_cadence_runs_only_in_rosc },
    { "SessionEngineTests.testStatsCprFraction", test_stats_cpr_fraction },
    { "Port.hintNamesWhatToDoNext", test_hint_names_what_to_do_next },
    { "Port.refusedActionsReportFalse", test_refused_actions_report_false },
    { "Port.changeProtocolKeepsRunningAnchors", test_change_protocol_keeps_running_anchors },
    { "Port.settingsOverridesChangeTimerLengths", test_settings_overrides_change_timer_lengths },
};
const size_t cr_engine_test_count = sizeof cr_engine_tests / sizeof cr_engine_tests[0];
