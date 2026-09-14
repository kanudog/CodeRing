#include "cr_menu.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cr_defaults.h"
#include "cr_text.h"
#include "cr_theme.h"

static cr_menu_item_t *push(cr_menu_item_t *out, size_t cap, size_t *n)
{
    if (*n >= cap) return NULL;
    cr_menu_item_t *item = &out[*n];
    memset(item, 0, sizeof *item);
    item->icon_color = CR_COLOR_NONE;
    (*n)++;
    return item;
}

static void set(cr_menu_item_t *item, const char *id, const char *title,
                const char *symbol, uint32_t color)
{
    cr_copy_utf8(item->id, sizeof item->id, id);
    cr_copy_utf8(item->title, sizeof item->title, title);
    item->symbol = symbol;
    item->color = color;
}

static void group(cr_menu_item_t *item, const char *key, const char *title,
                  const char *symbol, uint32_t color)
{
    set(item, key, title, symbol, color);
    item->is_group = true;
    item->child_key = key;
}

static void add_drug(cr_menu_item_t *out, size_t cap, size_t *n, const cr_drug_t *drug)
{
    if (drug == NULL) return;
    cr_menu_item_t *item = push(out, cap, n);
    if (item == NULL) return;
    char id[CR_MENU_ID_MAX];
    snprintf(id, sizeof id, "drug:%s", drug->id);
    set(item, id, drug->name, drug->symbol, drug->color);
}

const char *cr_menu_key(const cr_engine_t *e, const char *anchor)
{
    if (anchor == NULL) return CR_ANCHOR_EVENTS;
    // Same puck, different set: once there is a rhythm, the fan becomes the
    // post-resuscitation one.
    if (strcmp(anchor, CR_ANCHOR_EVENTS) == 0 && e != NULL && e->rosc_achieved) {
        return "events.rosc";
    }
    return anchor;
}

/// Rhythm/code meds, left to right.
static size_t meds_items(const cr_engine_t *e, cr_menu_item_t *out, size_t cap)
{
    size_t n = 0;
    const char *ids[] = { CR_ID_EPI, CR_ID_ATROPINE, CR_ID_ADENOSINE, CR_ID_AMIO, CR_ID_LIDOCAINE };
    for (size_t i = 0; i < sizeof ids / sizeof ids[0]; i++) {
        add_drug(out, cap, &n, cr_drug_set_find(e->drug_set, ids[i]));
    }
    return n;
}

static size_t shock_items(const cr_engine_t *e, cr_menu_item_t *out, size_t cap)
{
    size_t n = 0;
    cr_menu_item_t *item = push(out, cap, &n);
    if (item != NULL) group(item, "grp:defib", "Defib", "bolt.fill", CR_THEME_SHOCK);
    item = push(out, cap, &n);
    if (item != NULL) set(item, "evt:cardiovert", "Cardiovert", "bolt.heart.fill", CR_THEME_SHOCK);
    (void)e;
    return n;
}

/// The defib ladder at this patient's weight.
static size_t defib_items(const cr_engine_t *e, cr_menu_item_t *out, size_t cap)
{
    size_t n = 0;
    const cr_drug_t *defib = cr_drug_set_find(e->drug_set, CR_ID_DEFIB);
    if (defib == NULL) return 0;
    cr_dose_t doses[CR_MAX_DOSE_STEPS];
    size_t steps = cr_doses(defib, e->session.patient.weight_kg, doses, CR_MAX_DOSE_STEPS);
    for (size_t i = 0; i < steps && i < CR_MAX_DOSE_STEPS; i++) {
        cr_menu_item_t *item = push(out, cap, &n);
        if (item == NULL) break;
        char id[CR_MENU_ID_MAX], title[CR_MENU_TITLE_MAX], amount[12];   // "200 J" at most
        snprintf(id, sizeof id, "drug:%s#%d", defib->id, (int)i);
        cr_dose_amount_text(&doses[i], amount, sizeof amount);
        // "Subsequent · 40 J" renders wider than the slot pitch and reached
        // into the buttons either side, so the rung is shortened for DISPLAY
        // only — the id, the dose and everything logged are untouched.
        const char *rung = strcmp(doses[i].step_label, "Subsequent") == 0 ? "Next"
                                                                         : doses[i].step_label;
        snprintf(title, sizeof title, "%s %s", rung, amount);
        set(item, id, title, "bolt.fill", CR_THEME_SHOCK);
    }
    return n;
}

/// Volume/support. Built Fluids-first and then REVERSED, so it reads
/// More → Fluids left to right.
static size_t support_items(const cr_engine_t *e, cr_menu_item_t *out, size_t cap)
{
    size_t n = 0;
    cr_menu_item_t *item = push(out, cap, &n);
    if (item != NULL) group(item, "grp:fluids", "Fluids", "drop.fill", CR_THEME_VOLUME);
    add_drug(out, cap, &n, cr_drug_set_find(e->drug_set, CR_ID_DEXTROSE));
    add_drug(out, cap, &n, cr_drug_set_find(e->drug_set, CR_ID_CALCIUM));
    add_drug(out, cap, &n, cr_drug_set_find(e->drug_set, CR_ID_BICARB));
    item = push(out, cap, &n);
    if (item != NULL) group(item, "grp:more", "More", "ellipsis", CR_THEME_VOLUME);

    for (size_t i = 0; i < n / 2; i++) {
        cr_menu_item_t swap = out[i];
        out[i] = out[n - 1 - i];
        out[n - 1 - i] = swap;
    }
    return n;
}

static size_t fluids_items(const cr_engine_t *e, cr_menu_item_t *out, size_t cap)
{
    size_t n = 0;
    cr_menu_item_t *item = push(out, cap, &n);
    if (item != NULL) {
        set(item, "evt:blood", "Blood", "drop.fill", CR_THEME_VOLUME);
        item->icon_color = CR_THEME_MED;   // blue bubble, red drop
    }
    const cr_drug_t *fluids = cr_drug_set_find(e->drug_set, CR_ID_FLUIDS);
    if (fluids == NULL) return n;
    cr_dose_t doses[CR_MAX_DOSE_STEPS];
    size_t steps = cr_doses(fluids, e->session.patient.weight_kg, doses, CR_MAX_DOSE_STEPS);
    for (size_t i = 0; i < steps && i < CR_MAX_DOSE_STEPS; i++) {
        item = push(out, cap, &n);
        if (item == NULL) break;
        char id[CR_MENU_ID_MAX];
        snprintf(id, sizeof id, "drug:%s#%d", fluids->id, (int)i);
        // Half-full for the 10 mL/kg rung, full for 20 — they used to share
        // a glyph and were tellable apart only by their labels.
        set(item, id, doses[i].step_label, i == 0 ? "drop.halffull" : "drop.fill", CR_THEME_VOLUME);
    }
    return n;
}

static size_t more_items(const cr_engine_t *e, cr_menu_item_t *out, size_t cap)
{
    size_t n = 0;
    cr_menu_item_t *item = push(out, cap, &n);
    if (item != NULL) set(item, "evt:drip", "Drip", "ivfluid.bag", CR_THEME_VOLUME);
    add_drug(out, cap, &n, cr_drug_set_find(e->drug_set, CR_ID_MAGNESIUM));
    add_drug(out, cap, &n, cr_drug_set_find(e->drug_set, CR_ID_NALOXONE));
    return n;
}

/// Each service carries its OWN icon. They used to inherit one symbol from
/// the branch — four identical bubbles in a row, tellable apart only by
/// their labels. Anesthesia has no laryngoscope in SF Symbols, so the watch
/// uses the honest generic for "the people who put them to sleep"; drawing
/// our own icons here means that one could be improved.
static const struct { const char *name; const char *symbol; } k_services[] = {
    { "Surgery", "scissors" },
    { "Anesthesia", "moon.zzz.fill" },
    { "ECMO", "arrow.triangle.2.circlepath" },
    { "Consult", "stethoscope" },
};

static size_t service_items(const char *base, cr_menu_item_t *out, size_t cap)
{
    size_t n = 0;
    for (size_t i = 0; i < sizeof k_services / sizeof k_services[0]; i++) {
        cr_menu_item_t *item = push(out, cap, &n);
        if (item == NULL) break;
        char id[CR_MENU_ID_MAX];
        snprintf(id, sizeof id, "evt:%s|%s", base, k_services[i].name);
        set(item, id, k_services[i].name, k_services[i].symbol, CR_THEME_COMMS);
    }
    return n;
}

static size_t temp_items(cr_menu_item_t *out, size_t cap)
{
    static const struct { const char *name; const char *symbol; } devices[] = {
        { "Bair Hugger", "wind" },
        { "Arctic Sun", "snowflake" },
        { "Warm blankets", "square.stack.3d.up.fill" },
    };
    size_t n = 0;
    for (size_t i = 0; i < sizeof devices / sizeof devices[0]; i++) {
        cr_menu_item_t *item = push(out, cap, &n);
        if (item == NULL) break;
        char id[CR_MENU_ID_MAX];
        snprintf(id, sizeof id, "evt:temp|%s", devices[i].name);
        set(item, id, devices[i].name, devices[i].symbol, CR_THEME_CARE);
    }
    return n;
}

static size_t events_items(const cr_engine_t *e, cr_menu_item_t *out, size_t cap)
{
    size_t n = 0;
    cr_menu_item_t *item = push(out, cap, &n);
    if (item != NULL) set(item, "evt:rhythm", "Rhythm", "waveform.path.ecg", CR_THEME_RHYTHM);
    item = push(out, cap, &n);
    if (item != NULL) group(item, "grp:access", "Access", "cross.circle.fill", CR_THEME_ACCESS);
    item = push(out, cap, &n);
    if (item != NULL) group(item, "grp:airway", "Airway", "lungs.fill", CR_THEME_AIRWAY);
    item = push(out, cap, &n);
    if (item != NULL) group(item, "grp:comms", "Comms", "person.2.wave.2.fill", CR_THEME_COMMS);
    item = push(out, cap, &n);
    if (item != NULL) group(item, "grp:temp", "Temp", "thermometer.medium", CR_THEME_CARE);
    item = push(out, cap, &n);
    if (item != NULL) set(item, "rosc", "ROSC", "heart.fill", CR_THEME_ROSC);

    // Custom events (built on the phone) ride along at the end — which is
    // why the layout lookup is count-exact and falls back to the arc.
    for (size_t i = 0; i < e->event_def_count; i++) {
        if (e->event_defs[i].category != CR_CAT_CUSTOM) continue;
        item = push(out, cap, &n);
        if (item == NULL) break;
        char id[CR_MENU_ID_MAX];
        snprintf(id, sizeof id, "evt:%s", e->event_defs[i].id);
        set(item, id, e->event_defs[i].title, e->event_defs[i].symbol, CR_THEME_CUSTOM);
    }
    return n;
}

/// Post-ROSC: the question on the wrist is no longer "what rhythm" but
/// "is there still a pulse", so the same event is titled differently.
static size_t rosc_events_items(cr_menu_item_t *out, size_t cap)
{
    size_t n = 0;
    cr_menu_item_t *item = push(out, cap, &n);
    if (item != NULL) set(item, "evt:rhythm", "Pulse", "waveform.path.ecg", CR_THEME_RHYTHM);
    item = push(out, cap, &n);
    if (item != NULL) set(item, "evt:12lead", "12-lead", "waveform.path.ecg.rectangle", CR_THEME_RHYTHM);
    item = push(out, cap, &n);
    if (item != NULL) set(item, "evt:drip", "Drip", "ivfluid.bag", CR_THEME_VOLUME);
    item = push(out, cap, &n);
    if (item != NULL) {
        set(item, "evt:blood", "Blood", "drop.fill", CR_THEME_VOLUME);
        item->icon_color = CR_THEME_MED;
    }
    item = push(out, cap, &n);
    if (item != NULL) group(item, "grp:temp", "Temp", "thermometer.medium", CR_THEME_CARE);
    return n;
}

size_t cr_menu_items(const cr_engine_t *e, const char *key, cr_menu_item_t *out, size_t cap)
{
    if (e == NULL || key == NULL || out == NULL) return 0;
    if (strcmp(key, "code") == 0)        return meds_items(e, out, cap);
    if (strcmp(key, "shock") == 0)       return shock_items(e, out, cap);
    if (strcmp(key, "grp:defib") == 0)   return defib_items(e, out, cap);
    if (strcmp(key, "support") == 0)     return support_items(e, out, cap);
    if (strcmp(key, "grp:fluids") == 0)  return fluids_items(e, out, cap);
    if (strcmp(key, "grp:more") == 0)    return more_items(e, out, cap);
    if (strcmp(key, "events") == 0)      return events_items(e, out, cap);
    if (strcmp(key, "events.rosc") == 0) return rosc_events_items(out, cap);
    if (strcmp(key, "grp:temp") == 0)    return temp_items(out, cap);
    if (strcmp(key, "grp:call") == 0)    return service_items("comms.call", out, cap);
    if (strcmp(key, "grp:arrival") == 0) return service_items("comms.arrival", out, cap);

    if (strcmp(key, "grp:access") == 0) {
        size_t n = 0;
        cr_menu_item_t *item = push(out, cap, &n);
        // The site lives in the chart, not on the watch: logged as-is.
        if (item != NULL) set(item, "evt:access.iv", "IV", "cross.vial.fill", CR_THEME_ACCESS);
        item = push(out, cap, &n);
        if (item != NULL) set(item, "evt:access.io", "IO", "target", CR_THEME_ACCESS);
        item = push(out, cap, &n);
        if (item != NULL) set(item, "evt:access.art", "Art line", "waveform.path", CR_THEME_ACCESS);
        return n;
    }
    if (strcmp(key, "grp:airway") == 0) {
        size_t n = 0;
        cr_menu_item_t *item = push(out, cap, &n);
        if (item != NULL) set(item, "evt:airway.ett", "Intubation", "arrow.down.to.line.compact", CR_THEME_AIRWAY);
        item = push(out, cap, &n);
        if (item != NULL) set(item, "evt:airway.bag", "Bag", "balloon.fill", CR_THEME_AIRWAY);
        item = push(out, cap, &n);
        if (item != NULL) set(item, "evt:airway.mask", "Mask", "facemask.fill", CR_THEME_AIRWAY);
        item = push(out, cap, &n);
        if (item != NULL) set(item, "evt:airway.trach", "Trach", "cylinder.fill", CR_THEME_AIRWAY);
        return n;
    }
    if (strcmp(key, "grp:comms") == 0) {
        size_t n = 0;
        cr_menu_item_t *item = push(out, cap, &n);
        if (item != NULL) group(item, "grp:call", "Call", "phone.fill", CR_THEME_COMMS);
        item = push(out, cap, &n);
        if (item != NULL) group(item, "grp:arrival", "Arrived", "figure.walk.arrival", CR_THEME_COMMS);
        return n;
    }
    return 0;
}

/// What a logged event looks like for each `evt:` base — title, category and
/// the hue the button had, frozen at log time so every timer surface shows
/// the same colour as the button it came from.
static bool catalog(const char *base, const char **title, cr_category_t *category, uint32_t *color)
{
    static const struct { const char *base, *title; cr_category_t category; uint32_t color; } k[] = {
        { "rhythm",        "Rhythm check",   CR_CAT_RHYTHM,         CR_THEME_RHYTHM },
        { "12lead",        "12-lead ECG",    CR_CAT_RHYTHM,         CR_THEME_RHYTHM },
        { "access.iv",     "IV access",      CR_CAT_ACCESS,         CR_THEME_ACCESS },
        { "access.io",     "IO access",      CR_CAT_ACCESS,         CR_THEME_ACCESS },
        { "access.art",    "Art line",       CR_CAT_ACCESS,         CR_THEME_ACCESS },
        { "airway.ett",    "Intubation",     CR_CAT_AIRWAY,         CR_THEME_AIRWAY },
        { "airway.bag",    "Bag",            CR_CAT_AIRWAY,         CR_THEME_AIRWAY },
        { "airway.mask",   "Mask",           CR_CAT_AIRWAY,         CR_THEME_AIRWAY },
        { "airway.trach",  "Trach",          CR_CAT_AIRWAY,         CR_THEME_AIRWAY },
        { "comms.call",    "Call",           CR_CAT_COMMS,          CR_THEME_COMMS },
        { "comms.arrival", "Arrival",        CR_CAT_COMMS,          CR_THEME_COMMS },
        { "temp",          "Temp mgmt",      CR_CAT_CARE,           CR_THEME_CARE },
        { "blood",         "Blood given",    CR_CAT_VOLUME,         CR_THEME_MED },
        { "drip",          "Drip started",   CR_CAT_VOLUME,         CR_THEME_VOLUME },
        { "cardiovert",    "Cardioversion",  CR_CAT_DEFIBRILLATION, CR_THEME_SHOCK },
    };
    for (size_t i = 0; i < sizeof k / sizeof k[0]; i++) {
        if (strcmp(k[i].base, base) != 0) continue;
        *title = k[i].title;
        *category = k[i].category;
        *color = k[i].color;
        return true;
    }
    return false;
}

bool cr_menu_select(cr_engine_t *e, const cr_menu_item_t *item, cr_ms_t now)
{
    if (e == NULL || item == NULL) return false;
    if (item->is_group) return false;          // parents only expand

    if (strcmp(item->id, "pause") == 0) return cr_engine_toggle_pause(e, now);
    if (strcmp(item->id, "rosc") == 0)  return cr_engine_mark_rosc(e, now);

    if (strncmp(item->id, "drug:", 5) == 0) {
        char uuid[CR_MENU_ID_MAX];
        cr_copy_utf8(uuid, sizeof uuid, item->id + 5);
        int step = -1;
        char *hash = strchr(uuid, '#');
        if (hash != NULL) {
            *hash = '\0';
            step = (int)strtol(hash + 1, NULL, 10);
        }
        return cr_engine_log_drug(e, cr_drug_set_find(e->drug_set, uuid), step, now);
    }

    if (strncmp(item->id, "evt:", 4) == 0) {
        char base[CR_MENU_ID_MAX];
        cr_copy_utf8(base, sizeof base, item->id + 4);
        const char *detail = NULL;
        char *bar = strchr(base, '|');
        if (bar != NULL) {
            *bar = '\0';
            detail = bar + 1;
        }

        // Choosing Rhythm during CPR runs a REAL pulse check — hands-off
        // screen, cycle closes. Deliberately not gated on the cycle being
        // due, the way tapping the big centre ring is: that gate protects a
        // fat-fingered tap on a large target, but reaching this took a
        // deliberate slide onto a named bubble, and a rhythm change mid-cycle
        // is a real reason to check early. beginPulseCheck writes its own
        // record, so this must NOT also log the catalog event.
        if (strcmp(base, "rhythm") == 0 && e->cpr_started && !e->rosc_achieved &&
            !e->paused && !e->in_pulse_check) {
            return cr_engine_begin_pulse_check(e, now);
        }

        const char *title = NULL;
        cr_category_t category = CR_CAT_CUSTOM;
        uint32_t color = item->color;
        if (catalog(base, &title, &category, &color)) {
            return cr_engine_log_event(e, title, detail, category, base, color, now);
        }
        // A custom event from the phone: its definition carries the truth.
        for (size_t i = 0; i < e->event_def_count; i++) {
            if (strcmp(e->event_defs[i].id, base) != 0) continue;
            return cr_engine_log_event(e, e->event_defs[i].title, detail,
                                       e->event_defs[i].category, base,
                                       cr_category_color(e->event_defs[i].category), now);
        }
    }
    return false;
}
