#include "cr_engine.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

#include "cr_text.h"
#include "cr_theme.h"

// MARK: - Internals

static bool id_eq(const char *a, const char *b)
{
    return a != NULL && b != NULL && strcmp(a, b) == 0;
}

/// Appends one record. Returns false when the log is full: the caller must
/// decide whether that cancels the action (a drug log) or merely loses the
/// paper trail (a pulse check, which still has to work). Either way
/// `overflow` latches, so the UI can say so instead of going quiet.
static bool append(cr_engine_t *e, const char *title, const char *detail,
                   cr_category_t category, const char *definition_id,
                   uint32_t color, cr_ms_t now)
{
    cr_session_t *s = &e->session;
    if (s->event_count >= CR_MAX_EVENTS) {
        e->overflow = true;
        return false;
    }
    cr_event_t *ev = &s->events[s->event_count];
    memset(ev, 0, sizeof *ev);
    ev->seq = e->next_seq++;
    ev->date = now;
    ev->offset_s = (int32_t)(cr_engine_elapsed(e, now) / 1000);
    cr_copy_utf8(ev->title, sizeof ev->title, title);
    cr_copy_utf8(ev->detail, sizeof ev->detail, detail);
    ev->category = category;
    cr_copy_utf8(ev->definition_id, sizeof ev->definition_id, definition_id);
    ev->color = color;
    s->event_count++;
    e->log_rev++;
    return true;
}

static void open_pause(cr_engine_t *e, cr_ms_t now)
{
    cr_session_t *s = &e->session;
    if (s->pause_count >= CR_MAX_PAUSES) {
        e->overflow = true;   // the clock still runs; only the record is lost
        return;
    }
    s->pauses[s->pause_count].start = now;
    s->pauses[s->pause_count].end = CR_TIME_NONE;
    s->pause_count++;
}

static void close_open_pause(cr_engine_t *e, cr_ms_t now)
{
    cr_session_t *s = &e->session;
    for (int i = (int)s->pause_count - 1; i >= 0; i--) {
        if (s->pauses[i].end == CR_TIME_NONE) {
            s->pauses[i].end = now;
            return;
        }
    }
}

/// Shared teardown: closes the check's pause, counts the cycle, and
/// re-anchors so the next cycle starts now. Safe to call when idle.
static void close_pulse_check(cr_engine_t *e, cr_ms_t now)
{
    if (!e->in_pulse_check) return;
    close_open_pause(e, now);
    e->pulse_check_started_at = CR_TIME_NONE;
    e->in_pulse_check = false;
    e->completed_cycles++;
    e->cycle_anchor = now;
}

static int timer_index(const cr_protocol_t *p, const char *timer_id)
{
    for (uint8_t i = 0; i < p->timer_count; i++) {
        if (id_eq(p->timers[i].id, timer_id)) return i;
    }
    return -1;
}

// MARK: - Life cycle

void cr_engine_init(cr_engine_t *e,
                    const cr_protocol_t *protocol,
                    const cr_drug_set_t *drug_set,
                    const cr_event_def_t *event_defs, size_t event_def_count,
                    const cr_patient_t *patient,
                    cr_ms_t start,
                    const char *session_id,
                    const char *device_name)
{
    memset(e, 0, sizeof *e);
    e->protocol = *protocol;
    e->drug_set = drug_set;
    e->event_defs = event_defs;
    e->event_def_count = event_def_count;

    cr_session_t *s = &e->session;
    cr_copy_utf8(s->id, sizeof s->id, session_id);
    cr_copy_utf8(s->protocol_id, sizeof s->protocol_id, protocol->id);
    cr_copy_utf8(s->protocol_name, sizeof s->protocol_name, protocol->name);
    cr_copy_utf8(s->device_name, sizeof s->device_name, device_name);
    s->start = start;
    s->end = CR_TIME_NONE;
    s->rosc = CR_TIME_NONE;
    if (patient != NULL) s->patient = *patient;

    e->cycle_anchor = start;
    e->pause_started_at = CR_TIME_NONE;
    e->pulse_check_started_at = CR_TIME_NONE;
    e->last_rosc_at = CR_TIME_NONE;
    e->vitals_anchor = CR_TIME_NONE;
    // Drug-interval timers stay IDLE until the first dose — a countdown for
    // a med nobody has given yet reads as a false order.
    for (size_t i = 0; i < CR_MAX_TIMERS; i++) e->interval_anchors[i] = CR_TIME_NONE;
    e->next_seq = 1;
}

// MARK: - Clock

cr_ms_t cr_engine_elapsed(const cr_engine_t *e, cr_ms_t now)
{
    cr_ms_t span = now - e->session.start;
    return span < 0 ? 0 : span;
}

cr_ms_t cr_engine_cycle_remaining(const cr_engine_t *e, cr_ms_t now)
{
    const cr_timer_spec_t *spec = cr_protocol_cycle_spec(&e->protocol);
    if (spec == NULL) return 0;
    if (!e->cpr_started) return spec->duration_ms;   // full ring, waiting on Start CPR

    cr_ms_t effective_now = now;
    if (e->pause_started_at != CR_TIME_NONE) effective_now = e->pause_started_at;
    else if (e->pulse_check_started_at != CR_TIME_NONE) effective_now = e->pulse_check_started_at;

    cr_ms_t in_cycle = effective_now - e->cycle_anchor;
    if (in_cycle < 0) in_cycle = 0;
    return spec->duration_ms - in_cycle;
}

int32_t cr_engine_cycle_index(const cr_engine_t *e)
{
    return e->completed_cycles;
}

cr_ms_t cr_engine_pulse_check_elapsed(const cr_engine_t *e, cr_ms_t now)
{
    if (e->pulse_check_started_at == CR_TIME_NONE) return 0;
    cr_ms_t span = now - e->pulse_check_started_at;
    return span < 0 ? 0 : span;
}

cr_ms_t cr_engine_rosc_elapsed(const cr_engine_t *e, cr_ms_t now)
{
    cr_ms_t rosc = (e->last_rosc_at != CR_TIME_NONE) ? e->last_rosc_at : e->session.rosc;
    if (rosc == CR_TIME_NONE) return 0;
    cr_ms_t span = now - rosc;
    return span < 0 ? 0 : span;
}

bool cr_engine_vitals_remaining(const cr_engine_t *e, cr_ms_t now, cr_ms_t *out)
{
    const cr_timer_spec_t *spec = cr_protocol_vitals_spec(&e->protocol);
    if (!e->rosc_achieved || e->vitals_anchor == CR_TIME_NONE || spec == NULL) return false;
    if (out != NULL) *out = spec->duration_ms - (now - e->vitals_anchor);
    return true;
}

cr_ms_t cr_engine_interval_remaining(const cr_engine_t *e, const cr_timer_spec_t *spec, cr_ms_t now)
{
    if (spec == NULL) return 0;
    int idx = timer_index(&e->protocol, spec->id);
    if (idx < 0 || e->interval_anchors[idx] == CR_TIME_NONE) return spec->duration_ms;
    return spec->duration_ms - (now - e->interval_anchors[idx]);
}

bool cr_engine_interval_is_running(const cr_engine_t *e, const cr_timer_spec_t *spec)
{
    if (spec == NULL) return false;
    int idx = timer_index(&e->protocol, spec->id);
    return idx >= 0 && e->interval_anchors[idx] != CR_TIME_NONE;
}

bool cr_engine_interval_is_overdue(const cr_engine_t *e, const cr_timer_spec_t *spec, cr_ms_t now)
{
    return cr_engine_interval_is_running(e, spec) &&
           cr_engine_interval_remaining(e, spec, now) <= 0;
}

// MARK: - Guidance

const char *cr_engine_hint(const cr_engine_t *e, cr_ms_t now, char *buf, size_t cap)
{
    if (cap == 0) return buf;
    const char *fixed = NULL;

    if (e->ended) {
        fixed = "Code ended";
    } else if (e->rosc_achieved) {
        cr_ms_t vitals;
        fixed = (cr_engine_vitals_remaining(e, now, &vitals) && vitals <= 0)
                    ? "Vitals check overdue"
                    : "ROSC — post-resuscitation care";
    } else if (e->in_pulse_check) {
        fixed = "Hands off — checking pulse";
    } else if (!e->cpr_started) {
        fixed = "Tap Start CPR when compressions begin";
    } else if (e->paused) {
        fixed = "CPR PAUSED — resume compressions";
    } else if (cr_engine_cycle_remaining(e, now) <= 0) {
        fixed = "Pulse check overdue";
    } else {
        size_t intervals = cr_protocol_interval_count(&e->protocol);
        for (size_t i = 0; i < intervals; i++) {
            const cr_timer_spec_t *spec = cr_protocol_interval_spec(&e->protocol, i);
            if (cr_engine_interval_is_overdue(e, spec, now)) {
                snprintf(buf, cap, "%s due now", spec->title);
                return buf;
            }
        }
        fixed = (cr_engine_cycle_remaining(e, now) <= CR_SEC(15))
                    ? "Pulse check at cycle end"
                    : "Continue high-quality CPR";
    }

    cr_copy_utf8(buf, cap, fixed);
    return buf;
}

// MARK: - Actions

bool cr_engine_log_drug(cr_engine_t *e, const cr_drug_t *drug, int forced_step, cr_ms_t now)
{
    if (drug == NULL) return false;

    int prior = 0;
    for (uint16_t i = 0; i < e->session.event_count; i++) {
        if (strcmp(e->session.events[i].definition_id, drug->id) == 0) prior++;
    }

    cr_dose_t doses[CR_MAX_DOSE_STEPS];
    size_t count = cr_doses(drug, e->session.patient.weight_kg, doses, CR_MAX_DOSE_STEPS);
    if (count > CR_MAX_DOSE_STEPS) count = CR_MAX_DOSE_STEPS;

    char detail[CR_DETAIL_MAX] = "";
    if (count > 0) {
        int idx = (forced_step >= 0) ? forced_step : prior;
        if (idx > (int)count - 1) idx = (int)count - 1;
        if (idx < 0) idx = 0;
        // Bounded well under CR_DETAIL_MAX so "<label>: <summary>" always
        // fits whole; the longest real summary is ~23 bytes
        // ("10 mL  (1 mg) · capped").
        char summary[48];
        cr_dose_summary(&doses[idx], summary, sizeof summary);
        if (drug->step_count > 1) {
            snprintf(detail, sizeof detail, "%s: %s", doses[idx].step_label, summary);
        } else {
            cr_copy_utf8(detail, sizeof detail, summary);
        }
    }

    cr_category_t category = (drug->unit == CR_UNIT_J_PER_KG) ? CR_CAT_DEFIBRILLATION
                                                             : CR_CAT_MEDICATION;
    // A dose that cannot be recorded must not silently restart the timer
    // that says when the next one is due.
    if (!append(e, drug->name, detail, category, drug->id, drug->color, now)) return false;

    if (drug->resets_interval) {
        for (uint8_t i = 0; i < e->protocol.timer_count; i++) {
            const cr_timer_spec_t *spec = &e->protocol.timers[i];
            if (spec->role == CR_TIMER_DRUG_INTERVAL && id_eq(spec->linked_drug_id, drug->id)) {
                e->interval_anchors[i] = now;
            }
        }
    }
    return true;
}

bool cr_engine_log_event_def(cr_engine_t *e, const cr_event_def_t *def,
                             const char *sub_option, cr_ms_t now)
{
    if (def == NULL) return false;
    if (id_eq(def->id, "outcome.rosc")) return cr_engine_mark_rosc(e, now);
    return append(e, def->title, sub_option, def->category, def->id,
                  cr_category_color(def->category), now);
}

bool cr_engine_log_event(cr_engine_t *e, const char *title, const char *detail,
                         cr_category_t category, const char *definition_id,
                         uint32_t color, cr_ms_t now)
{
    return append(e, title, detail, category, definition_id, color, now);
}

bool cr_engine_start_cpr(cr_engine_t *e, cr_ms_t now)
{
    if (e->cpr_started || e->ended || e->rosc_achieved) return false;
    e->cpr_started = true;
    e->cycle_anchor = now;
    append(e, "CPR started", NULL, CR_CAT_CPR, "cpr.start", CR_COLOR_NONE, now);
    return true;
}

bool cr_engine_update_weight(cr_engine_t *e, double kg, cr_ms_t now)
{
    if (e->ended || !(kg > 0)) return false;
    double old = e->session.patient.weight_kg;
    if (!(fabs(old - kg) > 0.049)) return false;

    char detail[CR_DETAIL_MAX];
    snprintf(detail, sizeof detail, "%.1f → %.1f kg", old, kg);
    e->session.patient.weight_kg = kg;
    append(e, "Weight changed", detail, CR_CAT_CUSTOM, "patient.weight", CR_COLOR_NONE, now);
    return true;
}

bool cr_engine_begin_pulse_check(cr_engine_t *e, cr_ms_t now)
{
    if (!e->cpr_started || e->ended || e->rosc_achieved || e->in_pulse_check || e->paused) {
        return false;
    }
    e->pulse_check_started_at = now;
    e->in_pulse_check = true;
    open_pause(e, now);
    char detail[24];
    snprintf(detail, sizeof detail, "cycle %d", (int)(e->completed_cycles + 1));
    append(e, "Pulse check", detail, CR_CAT_RHYTHM, "pulse.check", CR_COLOR_NONE, now);
    return true;
}

bool cr_engine_complete_pulse_check(cr_engine_t *e, bool pulse_found, cr_ms_t now)
{
    if (!e->in_pulse_check) return false;
    close_pulse_check(e, now);
    if (pulse_found) {
        append(e, "Pulse found", NULL, CR_CAT_OUTCOME, "pulse.found", CR_COLOR_NONE, now);
        cr_engine_mark_rosc(e, now);
    } else {
        append(e, "CPR resumed", "no pulse", CR_CAT_CPR, "pulse.resume", CR_COLOR_NONE, now);
    }
    return true;
}

bool cr_engine_toggle_pause(cr_engine_t *e, cr_ms_t now)
{
    if (e->ended || e->rosc_achieved || e->in_pulse_check) return false;
    if (e->paused) {
        if (e->pause_started_at != CR_TIME_NONE) {
            // Slide the cycle anchor forward by the gap: paused time does not
            // count against the cycle.
            e->cycle_anchor += now - e->pause_started_at;
            close_open_pause(e, now);
        }
        e->pause_started_at = CR_TIME_NONE;
        e->paused = false;
        append(e, "CPR resumed", NULL, CR_CAT_CPR, "cpr.toggle", CR_COLOR_NONE, now);
    } else {
        e->pause_started_at = now;
        open_pause(e, now);
        e->paused = true;
        append(e, "CPR paused", NULL, CR_CAT_CPR, "cpr.toggle", CR_COLOR_NONE, now);
    }
    return true;
}

bool cr_engine_mark_rosc(cr_engine_t *e, cr_ms_t now)
{
    if (e->rosc_achieved || e->ended) return false;
    close_pulse_check(e, now);                        // ROSC mid-check counts the cycle
    if (e->paused) cr_engine_toggle_pause(e, now);    // close any open pause first
    if (e->session.rosc == CR_TIME_NONE) e->session.rosc = now;   // stats keep the FIRST
    e->last_rosc_at = now;
    e->vitals_anchor = now;                           // reassessment cadence starts now
    e->rosc_achieved = true;
    append(e, "ROSC", "Return of spontaneous circulation", CR_CAT_OUTCOME,
           "outcome.rosc", CR_COLOR_NONE, now);
    return true;
}

bool cr_engine_re_arrest(cr_engine_t *e, cr_ms_t now)
{
    if (!e->rosc_achieved || e->ended) return false;
    e->rosc_achieved = false;
    e->vitals_anchor = CR_TIME_NONE;
    e->cpr_started = true;      // compressions resume immediately
    e->cycle_anchor = now;
    append(e, "Re-arrest", "CPR resumed", CR_CAT_CPR, "outcome.rearrest", CR_COLOR_NONE, now);
    return true;
}

bool cr_engine_confirm_vitals(cr_engine_t *e, cr_ms_t now)
{
    if (!e->rosc_achieved || e->ended) return false;
    e->vitals_anchor = now;
    append(e, "Vitals reassessed", NULL, CR_CAT_RHYTHM, "rosc.vitals", CR_COLOR_NONE, now);
    return true;
}

bool cr_engine_end(cr_engine_t *e, cr_ms_t now)
{
    if (e->ended) return false;
    close_pulse_check(e, now);
    if (e->paused) cr_engine_toggle_pause(e, now);
    e->session.end = now;
    e->ended = true;
    return true;
}

void cr_engine_change_protocol(cr_engine_t *e, const cr_protocol_t *protocol)
{
    // Identity only: no anchor moves, so this is safe mid-code. Interval
    // anchors follow their timer id, not its index, in case a future
    // protocol orders its timers differently.
    cr_ms_t carried[CR_MAX_TIMERS];
    for (size_t i = 0; i < CR_MAX_TIMERS; i++) carried[i] = CR_TIME_NONE;
    for (uint8_t i = 0; i < protocol->timer_count && i < CR_MAX_TIMERS; i++) {
        int old = timer_index(&e->protocol, protocol->timers[i].id);
        if (old >= 0) carried[i] = e->interval_anchors[old];
    }
    e->protocol = *protocol;
    for (size_t i = 0; i < CR_MAX_TIMERS; i++) e->interval_anchors[i] = carried[i];
    cr_copy_utf8(e->session.protocol_id, sizeof e->session.protocol_id, protocol->id);
    cr_copy_utf8(e->session.protocol_name, sizeof e->session.protocol_name, protocol->name);
}

// MARK: - Undo

/// Structural records anchor derived state (cycles, pauses, weight), so
/// removing one would corrupt the maths. A wrong ROSC has its own escape
/// hatch: RE-ARREST.
static bool is_structural(const cr_event_t *ev)
{
    if (ev->category == CR_CAT_CPR || ev->category == CR_CAT_OUTCOME) return true;
    static const char *const ids[] = { "pulse.check", "rosc.vitals", "patient.weight" };
    for (size_t i = 0; i < sizeof ids / sizeof ids[0]; i++) {
        if (strcmp(ev->definition_id, ids[i]) == 0) return true;
    }
    return false;
}

static int last_undoable_index(const cr_engine_t *e)
{
    for (int i = (int)e->session.event_count - 1; i >= 0; i--) {
        if (!is_structural(&e->session.events[i])) return i;
    }
    return -1;
}

const cr_event_t *cr_engine_last_undoable(const cr_engine_t *e)
{
    int idx = last_undoable_index(e);
    return idx < 0 ? NULL : &e->session.events[idx];
}

bool cr_engine_undo_last(cr_engine_t *e, cr_event_t *removed_out)
{
    if (e->ended) return false;
    int idx = last_undoable_index(e);
    if (idx < 0) return false;

    cr_session_t *s = &e->session;
    cr_event_t target = s->events[idx];
    size_t tail = (size_t)(s->event_count - idx - 1);
    if (tail > 0) memmove(&s->events[idx], &s->events[idx + 1], tail * sizeof(cr_event_t));
    s->event_count--;
    e->log_rev++;

    // Roll the linked interval anchor back to the previous dose still on
    // record, or let the timer go idle when none remains.
    if (target.definition_id[0] != '\0') {
        for (uint8_t i = 0; i < e->protocol.timer_count; i++) {
            const cr_timer_spec_t *spec = &e->protocol.timers[i];
            if (spec->role != CR_TIMER_DRUG_INTERVAL ||
                !id_eq(spec->linked_drug_id, target.definition_id)) {
                continue;
            }
            e->interval_anchors[i] = CR_TIME_NONE;
            for (int j = (int)s->event_count - 1; j >= 0; j--) {
                if (strcmp(s->events[j].definition_id, target.definition_id) == 0) {
                    e->interval_anchors[i] = s->events[j].date;
                    break;
                }
            }
        }
    }

    if (removed_out != NULL) *removed_out = target;
    return true;
}
