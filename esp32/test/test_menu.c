// The menu tree, and the one rule that matters most about it: a gesture
// either logs something or SAYS it did not. Port-only tests — on the watch
// this tree lives inside a SwiftUI view and has no unit tests of its own.

#include <string.h>

#include "cr_menu.h"
#include "cr_test.h"
#include "test_helpers.h"

#define START CR_SEC(1000000)
#define T(sec) (START + CR_SEC(sec))

static cr_engine_t engine;
static cr_menu_item_t items[16];

static const cr_menu_item_t *find_item(size_t n, const char *id)
{
    for (size_t i = 0; i < n; i++) {
        if (strcmp(items[i].id, id) == 0) return &items[i];
    }
    return NULL;
}

// Port.menuInventoryMatchesTheLayoutTable — every fan must produce exactly
// as many items as the hand-placed table has slots, or it silently falls
// back to the computed arc on the wrist.
static void test_menu_inventory_matches_the_layout_table(void)
{
    test_make_engine(&engine, START);
    const struct { const char *key; uint8_t count; } expected[] = {
        { "code", 5 }, { "shock", 2 }, { "grp:defib", 3 }, { "support", 5 },
        { "grp:fluids", 3 }, { "grp:more", 3 }, { "events", 6 }, { "events.rosc", 5 },
        { "grp:access", 3 }, { "grp:airway", 4 }, { "grp:comms", 2 }, { "grp:temp", 3 },
        { "grp:call", 4 }, { "grp:arrival", 4 },
    };
    for (size_t i = 0; i < sizeof expected / sizeof expected[0]; i++) {
        size_t n = cr_menu_items(&engine, expected[i].key, items, 16);
        CHECK_I(n, expected[i].count);
        CHECK(cr_fan_find(expected[i].key, n) != NULL);   // geometry agrees
        for (size_t s = 0; s < n; s++) {
            CHECK(items[s].symbol != NULL && items[s].symbol[0] != '\0');
            CHECK(items[s].title[0] != '\0');
            if (items[s].is_group) CHECK(items[s].child_key != NULL);
        }
    }
}

// Port.menuDoseRungsReadAtThisWeight — the defib ladder is the reason fans
// are built at runtime rather than stored.
static void test_menu_dose_rungs_read_at_this_weight(void)
{
    test_make_engine(&engine, START);
    size_t n = cr_menu_items(&engine, "grp:defib", items, 16);
    CHECK_I(n, 3);
    CHECK_STR(items[0].title, "1st 20 J");     // 2 J/kg × 10 kg
    CHECK_STR(items[1].title, "Next 40 J");    // "Subsequent" is too wide to draw
    CHECK_STR(items[2].title, "Max 100 J");

    cr_engine_update_weight(&engine, 30, T(10));
    cr_menu_items(&engine, "grp:defib", items, 16);
    CHECK_STR(items[0].title, "1st 60 J");
    CHECK_STR(items[1].title, "Next 120 J");

    // The ids stay stable regardless of the display text.
    CHECK(strncmp(items[0].id, "drug:" CR_ID_DEFIB "#0", CR_MENU_ID_MAX) == 0);
}

// Port.menuSupportReadsMoreToFluids — built Fluids-first then reversed.
static void test_menu_support_reads_more_to_fluids(void)
{
    test_make_engine(&engine, START);
    size_t n = cr_menu_items(&engine, "support", items, 16);
    CHECK_I(n, 5);
    CHECK_STR(items[0].title, "More");
    CHECK_STR(items[4].title, "Fluids");
    CHECK(items[0].is_group);
    CHECK(items[4].is_group);
}

// Port.menuEventsSwapAfterRosc — same puck, a reassessment-oriented set.
static void test_menu_events_swap_after_rosc(void)
{
    test_make_engine(&engine, START);
    CHECK_STR(cr_menu_key(&engine, CR_ANCHOR_EVENTS), "events");
    cr_engine_mark_rosc(&engine, T(10));
    CHECK_STR(cr_menu_key(&engine, CR_ANCHOR_EVENTS), "events.rosc");

    size_t n = cr_menu_items(&engine, cr_menu_key(&engine, CR_ANCHOR_EVENTS), items, 16);
    CHECK_I(n, 5);
    // The rhythm check is called "Pulse" here: once there is a rhythm, the
    // question is whether it still has a pulse.
    CHECK_STR(items[0].title, "Pulse");
    CHECK_STR(items[0].id, "evt:rhythm");
}

// Port.menuSelectLogsWhatTheButtonSays
static void test_menu_select_logs_what_the_button_says(void)
{
    test_make_engine(&engine, START);
    cr_engine_start_cpr(&engine, START);

    size_t n = cr_menu_items(&engine, "code", items, 16);
    const cr_menu_item_t *epi = &items[0];
    CHECK_STR(epi->title, "Epinephrine");
    CHECK(cr_menu_select(&engine, epi, T(10)));
    const cr_event_t *logged = test_last_in_category(&engine, CR_CAT_MEDICATION);
    CHECK(logged != NULL);
    if (logged != NULL) {
        CHECK_STR(logged->title, "Epinephrine");
        CHECK_STR(logged->detail, "1 mL  (0.1 mg)");
    }

    // A forced rung logs that rung, not the next one up the ladder.
    n = cr_menu_items(&engine, "grp:defib", items, 16);
    CHECK(cr_menu_select(&engine, &items[2], T(20)));
    logged = test_last_in_category(&engine, CR_CAT_DEFIBRILLATION);
    CHECK(logged != NULL);
    if (logged != NULL) CHECK_HAS(logged->detail, "Max: 100 J");

    // A sub-option rides in the id after the bar and lands in the detail.
    n = cr_menu_items(&engine, "grp:temp", items, 16);
    CHECK(cr_menu_select(&engine, &items[0], T(30)));
    logged = test_last_in_category(&engine, CR_CAT_CARE);
    CHECK(logged != NULL);
    if (logged != NULL) {
        CHECK_STR(logged->title, "Temp mgmt");
        CHECK_STR(logged->detail, "Bair Hugger");
    }
    (void)n;
}

// Port.menuGroupsLogNothing — releasing on a parent must report false so the
// UI can say "Nothing logged" rather than going quiet.
static void test_menu_groups_log_nothing(void)
{
    test_make_engine(&engine, START);
    cr_engine_start_cpr(&engine, START);
    size_t n = cr_menu_items(&engine, "events", items, 16);
    const cr_menu_item_t *access = find_item(n, "grp:access");
    CHECK(access != NULL);
    if (access == NULL) return;

    uint16_t before = engine.session.event_count;
    CHECK(!cr_menu_select(&engine, access, T(10)));
    CHECK_I(engine.session.event_count, before);
}

// Port.menuRhythmRunsARealPulseCheck — picking Rhythm from the fan IS a
// pulse check (hands-off screen, cycle closes), and must not ALSO log the
// catalog event, or the log shows it twice.
static void test_menu_rhythm_runs_a_real_pulse_check(void)
{
    test_make_engine(&engine, START);
    cr_engine_start_cpr(&engine, START);
    size_t n = cr_menu_items(&engine, "events", items, 16);
    const cr_menu_item_t *rhythm = find_item(n, "evt:rhythm");
    CHECK(rhythm != NULL);
    if (rhythm == NULL) return;

    CHECK(cr_menu_select(&engine, rhythm, T(30)));
    CHECK(engine.in_pulse_check);
    CHECK_I(test_count_events(&engine, "pulse.check"), 1);
    CHECK_I(test_count_events(&engine, "rhythm"), 0);   // not logged twice

    // Post-ROSC the engine refuses the check, and it falls through to
    // logging the event instead — which is what "Pulse" should do there.
    cr_engine_complete_pulse_check(&engine, true, T(40));
    n = cr_menu_items(&engine, cr_menu_key(&engine, CR_ANCHOR_EVENTS), items, 16);
    rhythm = find_item(n, "evt:rhythm");
    CHECK(rhythm != NULL);
    if (rhythm == NULL) return;
    CHECK(cr_menu_select(&engine, rhythm, T(50)));
    CHECK_I(test_count_events(&engine, "rhythm"), 1);
}

// Port.menuBloodKeepsItsRedDrop — a blue bubble with a red icon, because it
// sits among the fluids but is not one.
static void test_menu_blood_keeps_its_red_drop(void)
{
    test_make_engine(&engine, START);
    size_t n = cr_menu_items(&engine, "grp:fluids", items, 16);
    const cr_menu_item_t *blood = find_item(n, "evt:blood");
    CHECK(blood != NULL);
    if (blood == NULL) return;
    CHECK_I(blood->color, CR_THEME_VOLUME);
    CHECK_I(blood->icon_color, CR_THEME_MED);

    // Everything else inherits its bubble colour.
    CHECK_I(items[1].icon_color, CR_COLOR_NONE);
}

const cr_test_case_t cr_menu_tests[] = {
    { "Port.menuInventoryMatchesTheLayoutTable", test_menu_inventory_matches_the_layout_table },
    { "Port.menuDoseRungsReadAtThisWeight", test_menu_dose_rungs_read_at_this_weight },
    { "Port.menuSupportReadsMoreToFluids", test_menu_support_reads_more_to_fluids },
    { "Port.menuEventsSwapAfterRosc", test_menu_events_swap_after_rosc },
    { "Port.menuSelectLogsWhatTheButtonSays", test_menu_select_logs_what_the_button_says },
    { "Port.menuGroupsLogNothing", test_menu_groups_log_nothing },
    { "Port.menuRhythmRunsARealPulseCheck", test_menu_rhythm_runs_a_real_pulse_check },
    { "Port.menuBloodKeepsItsRedDrop", test_menu_blood_keeps_its_red_drop },
};
const size_t cr_menu_test_count = sizeof cr_menu_tests / sizeof cr_menu_tests[0];
