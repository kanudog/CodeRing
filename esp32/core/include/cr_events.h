// cr_events.h — what CAN be logged (CodeCore/Models/Events.swift).
// What WAS logged lives in cr_session.h as cr_event_t.

#ifndef CR_EVENTS_H
#define CR_EVENTS_H

#include <stdbool.h>
#include <stdint.h>

typedef enum {
    CR_CAT_MEDICATION,
    CR_CAT_DEFIBRILLATION,
    CR_CAT_RHYTHM,
    CR_CAT_AIRWAY,
    CR_CAT_ACCESS,
    CR_CAT_CPR,
    CR_CAT_OUTCOME,
    CR_CAT_CARE,
    CR_CAT_VOLUME,
    CR_CAT_COMMS,
    CR_CAT_CUSTOM,
    CR_CAT__COUNT
} cr_category_t;

uint32_t cr_category_color(cr_category_t category);
const char *cr_category_label(cr_category_t category);   // "Medication"
const char *cr_category_key(cr_category_t category);     // Swift raw value, "medication"

#define CR_MAX_SUB_OPTIONS 4

/// A loggable item. Sub-options power the second-level fan (access limb,
/// warming device): a parent with sub-options only expands; logging always
/// takes a release on a leaf.
typedef struct {
    const char *id;          // stable key, e.g. "rhythm.check"
    const char *title;
    cr_category_t category;
    const char *symbol;
    const char *sub_options[CR_MAX_SUB_OPTIONS];
    uint8_t sub_option_count;
    bool is_built_in;
} cr_event_def_t;

#endif
