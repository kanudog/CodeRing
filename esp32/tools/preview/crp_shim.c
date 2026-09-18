// crp_shim.c — a thin bridge so a browser page on the Mac can drive the
// REAL engine. Nothing here ships to the watch; it exists so the clinical
// rules can be watched running long before there are pixels on the panel.
//
// The shim keeps the engine's discipline intact: every entry point takes
// `now_ms` from the caller, so the engine still reads no clock of its own
// (invariant 4). The page is therefore exercising exactly what the firmware
// will exercise.

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "cr_defaults.h"
#include "cr_engine.h"
#include "cr_json.h"
#include "cr_menu.h"
#include "cr_snapshot.h"

static cr_engine_t engine;
static bool ready;

void crp_reset(int64_t now_ms, double weight_kg);
int crp_command(const char *name, const char *arg1, const char *arg2, double value, int64_t now_ms);
int crp_snapshot(int64_t now_ms, int first_event, char *buf, int cap);
int crp_catalog(char *buf, int cap);

void crp_reset(int64_t now_ms, double weight_kg)
{
    cr_patient_t patient;
    memset(&patient, 0, sizeof patient);
    patient.weight_kg = weight_kg > 0 ? weight_kg : 10;
    patient.source = CR_WEIGHT_MANUAL;
    cr_engine_init(&engine, &cr_protocol_pals_arrest, &cr_pals_drug_set,
                   cr_builtin_events, cr_builtin_event_count,
                   &patient, now_ms, "PREVIEW", "mac-preview");
    ready = true;
}

static bool is(const char *a, const char *b) { return strcmp(a, b) == 0; }

/// Returns 1 when the action changed something, 0 when the engine refused
/// it — which is exactly what the UI needs in order to say "nothing logged"
/// instead of going quiet.
int crp_command(const char *name, const char *arg1, const char *arg2, double value, int64_t now_ms)
{
    if (!ready) crp_reset(now_ms, 10);
    if (name == NULL) return 0;
    if (arg1 == NULL) arg1 = "";
    if (arg2 == NULL) arg2 = "";

    if (is(name, "reset"))        { crp_reset(now_ms, value); return 1; }
    if (is(name, "start_cpr"))    return cr_engine_start_cpr(&engine, now_ms) ? 1 : 0;
    if (is(name, "pause"))        return cr_engine_toggle_pause(&engine, now_ms) ? 1 : 0;
    if (is(name, "pulse_begin"))  return cr_engine_begin_pulse_check(&engine, now_ms) ? 1 : 0;
    if (is(name, "pulse_none"))   return cr_engine_complete_pulse_check(&engine, false, now_ms) ? 1 : 0;
    if (is(name, "pulse_found"))  return cr_engine_complete_pulse_check(&engine, true, now_ms) ? 1 : 0;
    if (is(name, "rosc"))         return cr_engine_mark_rosc(&engine, now_ms) ? 1 : 0;
    if (is(name, "rearrest"))     return cr_engine_re_arrest(&engine, now_ms) ? 1 : 0;
    if (is(name, "vitals"))       return cr_engine_confirm_vitals(&engine, now_ms) ? 1 : 0;
    if (is(name, "undo"))         return cr_engine_undo_last(&engine, NULL) ? 1 : 0;
    if (is(name, "end"))          return cr_engine_end(&engine, now_ms) ? 1 : 0;
    if (is(name, "weight"))       return cr_engine_update_weight(&engine, value, now_ms) ? 1 : 0;

    if (is(name, "drug")) {
        const cr_drug_t *drug = cr_drug_set_find(&cr_pals_drug_set, arg1);
        int step = (value >= 0) ? (int)value : -1;   // the shock fan forces a rung
        return cr_engine_log_drug(&engine, drug, step, now_ms) ? 1 : 0;
    }
    if (is(name, "event")) {
        const cr_event_def_t *def = cr_builtin_event(arg1);
        const char *sub = arg2[0] ? arg2 : NULL;
        return cr_engine_log_event_def(&engine, def, sub, now_ms) ? 1 : 0;
    }
    // Anything reachable from the watch's menu tree, by fan key + item id.
    // Not everything on the wrist is a built-in event definition — the comms
    // services (Surgery, Anesthesia, ECMO, Consult) and the temperature
    // devices are ad-hoc leaves the menu itself carries, so "event" cannot
    // reach them. This drives the real cr_menu_select path, which is the
    // same one a finger on the panel takes.
    if (is(name, "menu")) {
        cr_menu_item_t items[CR_MAX_SLOTS];
        size_t n = cr_menu_items(&engine, arg1, items, CR_MAX_SLOTS);
        for (size_t i = 0; i < n; i++) {
            if (strcmp(items[i].id, arg2) != 0) continue;
            return cr_menu_select(&engine, &items[i], now_ms) ? 1 : 0;
        }
        return 0;
    }
    return 0;
}

int crp_snapshot(int64_t now_ms, int first_event, char *buf, int cap)
{
    if (!ready) crp_reset(now_ms, 10);
    if (first_event < 0) first_event = 0;
    return (int)cr_snapshot_json(&engine, now_ms, (uint16_t)first_event, buf, (size_t)cap);
}

/// The drug and event catalogue, so the page builds its buttons from the
/// same defaults the watch ships with rather than a hand-copied list.
int crp_catalog(char *buf, int cap)
{
    cr_jw_t w;
    cr_jw_init(&w, buf, (size_t)cap);
    cr_jw_raw(&w, "{\"drugs\":[");
    for (uint8_t i = 0; i < cr_pals_drug_set.drug_count; i++) {
        const cr_drug_t *drug = cr_pals_drug_set.drugs[i];
        if (i > 0) cr_jw_raw(&w, ",");
        cr_jw_raw(&w, "{\"id\":");        cr_jw_str(&w, drug->id);
        cr_jw_raw(&w, ",\"name\":");      cr_jw_str(&w, drug->name);
        cr_jw_raw(&w, ",\"subtitle\":");  cr_jw_str(&w, drug->subtitle);
        cr_jw_raw(&w, ",\"color\":");     cr_jw_color(&w, drug->color);
        cr_jw_raw(&w, ",\"steps\":[");
        for (uint8_t s = 0; s < drug->step_count; s++) {
            if (s > 0) cr_jw_raw(&w, ",");
            cr_jw_str(&w, drug->steps[s].label);
        }
        cr_jw_raw(&w, "]}");
    }
    cr_jw_raw(&w, "],\"events\":[");
    for (size_t i = 0; i < cr_builtin_event_count; i++) {
        const cr_event_def_t *def = &cr_builtin_events[i];
        if (i > 0) cr_jw_raw(&w, ",");
        cr_jw_raw(&w, "{\"id\":");      cr_jw_str(&w, def->id);
        cr_jw_raw(&w, ",\"title\":");   cr_jw_str(&w, def->title);
        cr_jw_raw(&w, ",\"color\":");   cr_jw_color(&w, cr_category_color(def->category));
        cr_jw_raw(&w, ",\"subOptions\":[");
        for (uint8_t s = 0; s < def->sub_option_count; s++) {
            if (s > 0) cr_jw_raw(&w, ",");
            cr_jw_str(&w, def->sub_options[s]);
        }
        cr_jw_raw(&w, "]}");
    }
    cr_jw_raw(&w, "]}");
    return (int)w.len;
}
