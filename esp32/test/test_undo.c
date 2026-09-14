// Ported from UndoLastEntryTests. Mis-taps happen mid-code; the rule is
// that undo removes the newest USER entry and steps past the records that
// anchor clock state.

#include "cr_test.h"
#include "test_helpers.h"

#define START CR_SEC(1000000)
#define T(sec) (START + CR_SEC(sec))

static cr_engine_t engine;

static cr_engine_t *fresh(void)
{
    test_make_engine(&engine, START);
    return &engine;
}

// UndoLastEntryTests.testUndoRevertsIntervalAnchorAndLadder
static void test_undo_reverts_interval_anchor_and_ladder(void)
{
    cr_engine_t *e = fresh();
    cr_engine_start_cpr(e, START);
    const cr_drug_t *epi = cr_drug_set_find(&cr_pals_drug_set, CR_ID_EPI);
    CHECK(epi != NULL);
    if (epi == NULL) return;
    const cr_timer_spec_t *spec = cr_protocol_interval_spec(&e->protocol, 0);
    CHECK(spec != NULL);
    if (spec == NULL) return;

    cr_engine_log_drug(e, epi, -1, T(10));
    cr_engine_log_drug(e, epi, -1, T(70));
    CHECK_I(cr_engine_interval_remaining(e, spec, T(70)), spec->duration_ms);

    cr_event_t removed;
    CHECK(cr_engine_undo_last(e, &removed));
    CHECK_STR(removed.definition_id, epi->id);
    // The anchor rolled back to the surviving first dose (t+10).
    CHECK_I(cr_engine_interval_remaining(e, spec, T(70)), spec->duration_ms - CR_SEC(60));
    CHECK_I(test_count_events(e, epi->id), 1);

    CHECK(cr_engine_undo_last(e, NULL));
    CHECK(!cr_engine_interval_is_running(e, spec));   // no doses left — the timer goes idle
}

// UndoLastEntryTests.testUndoSkipsStructuralEventsAndStopsWhenNoneLeft
static void test_undo_skips_structural_events_and_stops_when_none_left(void)
{
    cr_engine_t *e = fresh();
    cr_engine_start_cpr(e, START);
    const cr_drug_t *amio = cr_drug_set_find(&cr_pals_drug_set, CR_ID_AMIO);
    CHECK(amio != NULL);
    if (amio == NULL) return;

    cr_engine_log_drug(e, amio, -1, T(5));
    cr_engine_begin_pulse_check(e, T(20));   // structural, sits on top

    cr_event_t removed;
    CHECK(cr_engine_undo_last(e, &removed));
    CHECK_STR(removed.definition_id, amio->id);   // undo reaches past the pulse-check record
    CHECK(test_has_event(e, "pulse.check"));
    CHECK(test_has_event(e, "cpr.start"));
    CHECK(!cr_engine_undo_last(e, NULL));         // only structural records remain
}

// Port.undoCannotRemoveAWeightChange — every later dose derives from it and
// there is no way back, so it is deliberately not undoable.
static void test_undo_cannot_remove_a_weight_change(void)
{
    cr_engine_t *e = fresh();
    cr_engine_start_cpr(e, START);
    cr_engine_update_weight(e, 22, T(10));
    CHECK(cr_engine_last_undoable(e) == NULL);
    CHECK(!cr_engine_undo_last(e, NULL));
    CHECK(test_has_event(e, "patient.weight"));
    CHECK_NEAR(e->session.patient.weight_kg, 22, 0.001);
}

// Port.undoNamesWhatItWouldRemove — the button is labelled with the entry,
// so the wearer sees what is about to disappear.
static void test_undo_names_what_it_would_remove(void)
{
    cr_engine_t *e = fresh();
    cr_engine_start_cpr(e, START);
    cr_engine_log_event_def(e, cr_builtin_event("access.iv"), "L arm", T(10));

    const cr_event_t *next = cr_engine_last_undoable(e);
    CHECK(next != NULL);
    if (next == NULL) return;
    CHECK_STR(next->title, "Access");
    CHECK_STR(next->detail, "L arm");

    uint32_t rev_before = e->log_rev;
    CHECK(cr_engine_undo_last(e, NULL));
    CHECK(e->log_rev != rev_before);   // the TV has to notice the removal
    CHECK(cr_engine_last_undoable(e) == NULL);
}

const cr_test_case_t cr_undo_tests[] = {
    { "UndoLastEntryTests.testUndoRevertsIntervalAnchorAndLadder",
      test_undo_reverts_interval_anchor_and_ladder },
    { "UndoLastEntryTests.testUndoSkipsStructuralEventsAndStopsWhenNoneLeft",
      test_undo_skips_structural_events_and_stops_when_none_left },
    { "Port.undoCannotRemoveAWeightChange", test_undo_cannot_remove_a_weight_change },
    { "Port.undoNamesWhatItWouldRemove", test_undo_names_what_it_would_remove },
};
const size_t cr_undo_test_count = sizeof cr_undo_tests / sizeof cr_undo_tests[0];
