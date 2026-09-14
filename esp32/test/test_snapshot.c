// The TV seam. These are port-only tests: the watch had no equivalent,
// because on the watch the screen WAS the only consumer of engine state.

#include <stdio.h>
#include <string.h>

#include "cr_json.h"
#include "cr_snapshot.h"
#include "cr_test.h"
#include "test_helpers.h"

#define START CR_SEC(1000000)
#define T(sec) (START + CR_SEC(sec))

static cr_engine_t engine;
static char json[16384];

/// A code in progress: compressions, one epi, one access, one overdue cycle.
static cr_engine_t *scenario(void)
{
    test_make_engine(&engine, START);
    cr_engine_t *e = &engine;
    cr_engine_start_cpr(e, START);
    cr_engine_log_drug(e, &cr_drug_epinephrine, -1, T(30));
    cr_engine_log_event_def(e, cr_builtin_event("access.iv"), "R leg", T(45));
    return e;
}

// Port.snapshotIsValidJson
static void test_snapshot_is_valid_json(void)
{
    cr_engine_t *e = scenario();
    size_t needed = cr_snapshot_json(e, T(125), 0, json, sizeof json);
    CHECK(needed < sizeof json);
    CHECK(cr_json_validate(json));
}

// Port.snapshotCarriesTheClinicalState — what the room needs to see without
// looking at the wrist.
static void test_snapshot_carries_the_clinical_state(void)
{
    cr_engine_t *e = scenario();
    cr_snapshot_json(e, T(125), 0, json, sizeof json);

    CHECK_HAS(json, "\"cycleRemainingMs\":-5000");          // overdue runs negative
    CHECK_HAS(json, "\"hint\":\"Pulse check overdue\"");
    CHECK_HAS(json, "\"cprStarted\":true");
    CHECK_HAS(json, "\"weightKg\":10");
    CHECK_HAS(json, "\"source\":\"manual\"");
    CHECK_HAS(json, "\"protocolShort\":\"ARREST\"");
    // The epi interval, its colour, and the dose as it was logged.
    CHECK_HAS(json, "\"id\":\"timer.epi\"");
    CHECK_HAS(json, "\"remainingMs\":85000");               // 180 − 95
    CHECK_HAS(json, "\"color\":\"FF3B5C\"");
    CHECK_HAS(json, "\"detail\":\"1 mL  (0.1 mg)\"");
    CHECK_HAS(json, "\"stamp\":\"+0:30\"");
    CHECK_HAS(json, "\"detail\":\"R leg\"");
    // Running timers and the log bookkeeping the TV diffs on.
    CHECK_HAS(json, "\"id\":\"total\"");
    CHECK_HAS(json, "\"count\":3");
    CHECK_HAS(json, "\"overflow\":false");
}

// Port.snapshotTracksRoscAndVitals
static void test_snapshot_tracks_rosc_and_vitals(void)
{
    cr_engine_t *e = scenario();
    cr_engine_mark_rosc(e, T(200));
    cr_snapshot_json(e, T(260), 0, json, sizeof json);
    CHECK(cr_json_validate(json));
    CHECK_HAS(json, "\"rosc\":true");
    CHECK_HAS(json, "\"roscElapsedMs\":60000");
    CHECK_HAS(json, "\"vitalsRemainingMs\":240000");        // 300 − 60
    CHECK_HAS(json, "\"secondsToRosc\":200");

    // Before ROSC the same fields are null, never a stale number.
    test_make_engine(&engine, START);
    cr_snapshot_json(&engine, T(10), 0, json, sizeof json);
    CHECK_HAS(json, "\"vitalsRemainingMs\":null");
    CHECK_HAS(json, "\"roscMs\":null");
    CHECK_HAS(json, "\"secondsToRosc\":null");
}

// Port.snapshotSendsOnlyRequestedEvents — the delta the TV asks for.
static void test_snapshot_sends_only_requested_events(void)
{
    cr_engine_t *e = scenario();
    cr_snapshot_json(e, T(60), 2, json, sizeof json);
    CHECK(cr_json_validate(json));
    CHECK_HAS(json, "\"from\":2");
    CHECK_HAS(json, "\"count\":3");
    CHECK_HAS(json, "\"title\":\"Access\"");
    CHECK(strstr(json, "\"title\":\"CPR started\"") == NULL);

    // Past the end is empty, not malformed.
    cr_snapshot_json(e, T(60), 99, json, sizeof json);
    CHECK(cr_json_validate(json));
    CHECK_HAS(json, "\"events\":[]");
}

// Port.snapshotEscapesUserText — a custom drug name with a quote in it must
// not produce a broken page.
static void test_snapshot_escapes_user_text(void)
{
    test_make_engine(&engine, START);
    cr_engine_log_event(&engine, "He said \"go\"\\now\n", "tab\there",
                        CR_CAT_CUSTOM, "custom.quote", CR_COLOR_NONE, T(5));
    size_t needed = cr_snapshot_json(&engine, T(10), 0, json, sizeof json);
    CHECK(needed < sizeof json);
    CHECK(cr_json_validate(json));
    CHECK_HAS(json, "\\\"go\\\"");
    CHECK_HAS(json, "\\\\now\\n");
    CHECK_HAS(json, "tab\\there");
}

// Port.snapshotReportsTruncation — a half-written snapshot must be
// detectable, never sent as if it were whole.
static void test_snapshot_reports_truncation(void)
{
    cr_engine_t *e = scenario();
    char small[64];
    size_t needed = cr_snapshot_json(e, T(60), 0, small, sizeof small);
    CHECK(needed > sizeof small);
    CHECK_I(strlen(small), sizeof small - 1);
    CHECK(!cr_json_validate(small));

    CHECK_I(cr_snapshot_json(e, T(60), 0, json, sizeof json), needed);
    CHECK(cr_json_validate(json));
}

// Port.snapshotLogRevMovesOnEveryChange
static void test_snapshot_log_rev_moves_on_every_change(void)
{
    cr_engine_t *e = scenario();
    uint32_t rev = e->log_rev;
    cr_engine_log_drug(e, &cr_drug_amiodarone, -1, T(70));
    CHECK(e->log_rev > rev);
    rev = e->log_rev;
    cr_engine_undo_last(e, NULL);
    CHECK(e->log_rev > rev);

    cr_snapshot_json(e, T(80), 0, json, sizeof json);
    CHECK(cr_json_validate(json));
    char expected[32];
    snprintf(expected, sizeof expected, "\"rev\":%u", (unsigned)e->log_rev);
    CHECK_HAS(json, expected);
}

const cr_test_case_t cr_snapshot_tests[] = {
    { "Port.snapshotIsValidJson", test_snapshot_is_valid_json },
    { "Port.snapshotCarriesTheClinicalState", test_snapshot_carries_the_clinical_state },
    { "Port.snapshotTracksRoscAndVitals", test_snapshot_tracks_rosc_and_vitals },
    { "Port.snapshotSendsOnlyRequestedEvents", test_snapshot_sends_only_requested_events },
    { "Port.snapshotEscapesUserText", test_snapshot_escapes_user_text },
    { "Port.snapshotReportsTruncation", test_snapshot_reports_truncation },
    { "Port.snapshotLogRevMovesOnEveryChange", test_snapshot_log_rev_moves_on_every_change },
};
const size_t cr_snapshot_test_count = sizeof cr_snapshot_tests / sizeof cr_snapshot_tests[0];
