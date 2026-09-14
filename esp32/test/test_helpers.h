// test_helpers.h — the small queries the Swift tests express as one-line
// closures (`events.contains { $0.definitionID == … }`).

#ifndef CR_TEST_HELPERS_H
#define CR_TEST_HELPERS_H

#include <string.h>

#include "cr_defaults.h"
#include "cr_engine.h"

/// The suite's shared fixture: PALS arrest, the built-in drugs and events,
/// a 10 kg patient — identical to `makeEngine` in CodeCoreTests.swift.
static inline void test_make_engine(cr_engine_t *e, cr_ms_t start)
{
    cr_patient_t patient;
    memset(&patient, 0, sizeof patient);
    patient.weight_kg = 10;
    patient.source = CR_WEIGHT_MANUAL;
    cr_engine_init(e, &cr_protocol_pals_arrest, &cr_pals_drug_set,
                   cr_builtin_events, cr_builtin_event_count,
                   &patient, start, "TEST-SESSION", "test");
}

static inline int test_count_events(const cr_engine_t *e, const char *definition_id)
{
    int n = 0;
    for (uint16_t i = 0; i < e->session.event_count; i++) {
        if (strcmp(e->session.events[i].definition_id, definition_id) == 0) n++;
    }
    return n;
}

static inline bool test_has_event(const cr_engine_t *e, const char *definition_id)
{
    return test_count_events(e, definition_id) > 0;
}

static inline const cr_event_t *test_first_event(const cr_engine_t *e, const char *definition_id)
{
    for (uint16_t i = 0; i < e->session.event_count; i++) {
        if (strcmp(e->session.events[i].definition_id, definition_id) == 0) {
            return &e->session.events[i];
        }
    }
    return NULL;
}

static inline const cr_event_t *test_last_in_category(const cr_engine_t *e, cr_category_t category)
{
    for (int i = (int)e->session.event_count - 1; i >= 0; i--) {
        if (e->session.events[i].category == category) return &e->session.events[i];
    }
    return NULL;
}

static inline int test_count_category(const cr_engine_t *e, cr_category_t category)
{
    int n = 0;
    for (uint16_t i = 0; i < e->session.event_count; i++) {
        if (e->session.events[i].category == category) n++;
    }
    return n;
}

static inline const cr_running_timer_t *test_find_timer(const cr_running_timer_t *timers,
                                                        size_t count, const char *id)
{
    for (size_t i = 0; i < count; i++) {
        if (strcmp(timers[i].id, id) == 0) return &timers[i];
    }
    return NULL;
}

#endif
