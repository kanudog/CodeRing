#include "cr_session.h"

#include <string.h>

#include "cr_text.h"

cr_ms_t cr_pause_ms(const cr_pause_t *pause, cr_ms_t limit)
{
    cr_ms_t stop = (pause->end == CR_TIME_NONE) ? limit : pause->end;
    cr_ms_t span = stop - pause->start;
    return span < 0 ? 0 : span;
}

uint32_t cr_event_tint(const cr_event_t *event)
{
    return event->color == CR_COLOR_NONE ? cr_category_color(event->category) : event->color;
}

cr_ms_t cr_session_duration(const cr_session_t *s, cr_ms_t now)
{
    cr_ms_t end = (s->end == CR_TIME_NONE) ? now : s->end;
    cr_ms_t span = end - s->start;
    return span < 0 ? 0 : span;
}

cr_ms_t cr_session_paused_ms(const cr_session_t *s, cr_ms_t now)
{
    cr_ms_t limit = (s->end == CR_TIME_NONE) ? now : s->end;
    cr_ms_t total = 0;
    for (uint16_t i = 0; i < s->pause_count; i++) total += cr_pause_ms(&s->pauses[i], limit);
    return total;
}

cr_ms_t cr_running_timer_elapsed(const cr_running_timer_t *timer, cr_ms_t now)
{
    cr_ms_t span = now - timer->since;
    return span < 0 ? 0 : span;
}

/// Things the algorithm repeats get a "time since last" row. NOTE: the
/// custom category counts, which means a mid-code weight change shows up as
/// a timer even though the Swift comment says one-shots should not. Carried
/// over deliberately so the watch, the phone and the TV agree; see the
/// port README before "fixing" it here alone.
static bool is_repeatable(const cr_event_t *event)
{
    switch (event->category) {
    case CR_CAT_MEDICATION:
    case CR_CAT_DEFIBRILLATION:
    case CR_CAT_CUSTOM:
        return true;
    default:
        break;
    }
    static const char *const repeatable_ids[] = {
        "pulse.check", "rhythm.check", "cpr.swap", "rosc.vitals",
    };
    for (size_t i = 0; i < sizeof repeatable_ids / sizeof repeatable_ids[0]; i++) {
        if (strcmp(event->definition_id, repeatable_ids[i]) == 0) return true;
    }
    return false;
}

size_t cr_session_running_timers(const cr_session_t *s, cr_running_timer_t *out, size_t cap)
{
    if (cap == 0) return 0;

    out[0].id = "total";
    out[0].title = "Total code";
    out[0].since = s->start;
    out[0].color = CR_THEME_CPR;
    size_t n = 1;

    for (uint16_t i = 0; i < s->event_count; i++) {
        const cr_event_t *ev = &s->events[i];
        if (!is_repeatable(ev)) continue;
        const char *key = ev->definition_id[0] ? ev->definition_id : ev->title;

        size_t slot;
        for (slot = 1; slot < n; slot++) {
            if (strcmp(out[slot].id, key) == 0) break;
        }
        if (slot < n) {
            if (out[slot].since > ev->date) continue;   // keep the LATEST of this item
        } else {
            if (n >= cap) continue;                     // more distinct items than room
            n++;
        }
        out[slot].id = key;
        out[slot].title = ev->title;
        out[slot].since = ev->date;
        out[slot].color = cr_event_tint(ev);
    }

    // Stalest first — the row most likely to need attention. Total stays row 0.
    for (size_t i = 2; i < n; i++) {
        cr_running_timer_t key = out[i];
        size_t j = i;
        while (j > 1 && out[j - 1].since > key.since) {
            out[j] = out[j - 1];
            j--;
        }
        out[j] = key;
    }
    return n;
}

/// ASCII substring match; every built-in drug name is ASCII.
static bool contains_ci(const char *haystack, const char *needle)
{
    size_t nlen = strlen(needle);
    if (nlen == 0) return true;
    for (const char *p = haystack; *p; p++) {
        size_t i = 0;
        while (i < nlen) {
            char a = p[i], b = needle[i];
            if (a == '\0') return false;
            if (a >= 'A' && a <= 'Z') a = (char)(a + 32);
            if (b >= 'A' && b <= 'Z') b = (char)(b + 32);
            if (a != b) break;
            i++;
        }
        if (i == nlen) return true;
    }
    return false;
}

void cr_session_stats(const cr_session_t *s, cr_ms_t now, cr_stats_t *out)
{
    memset(out, 0, sizeof *out);
    cr_ms_t end = (s->end == CR_TIME_NONE) ? now : s->end;

    out->total_ms = cr_session_duration(s, end);
    out->paused_ms = cr_session_paused_ms(s, end);
    out->pause_count = s->pause_count;

    // CPR fraction is measured against the active-compressions phase
    // (start → first ROSC, else end).
    cr_ms_t active_end = (s->rosc == CR_TIME_NONE) ? end : s->rosc;
    cr_ms_t active_span = active_end - s->start;
    if (active_span < 1000) active_span = 1000;   // Swift's max(1, …) in seconds
    cr_ms_t paused_in_active = 0;
    for (uint16_t i = 0; i < s->pause_count; i++) {
        paused_in_active += cr_pause_ms(&s->pauses[i], active_end);
    }
    double fraction = (double)(active_span - paused_in_active) / (double)active_span;
    if (fraction < 0) fraction = 0;
    if (fraction > 1) fraction = 1;
    out->cpr_fraction = fraction;

    for (uint16_t i = 0; i < s->event_count; i++) {
        const cr_event_t *ev = &s->events[i];
        switch (ev->category) {
        case CR_CAT_MEDICATION: {
            size_t slot;
            for (slot = 0; slot < out->med_count; slot++) {
                if (strcmp(out->meds[slot].title, ev->title) == 0) break;
            }
            if (slot < out->med_count) {
                out->meds[slot].count++;
            } else if (out->med_count < CR_MAX_MED_TALLY) {
                cr_copy_utf8(out->meds[slot].title, CR_TITLE_MAX, ev->title);
                out->meds[slot].count = 1;
                out->med_count++;
            }
            if (contains_ci(ev->title, "epi")) {
                out->epi_count++;
                if (!out->has_first_epi) {
                    out->has_first_epi = true;
                    out->seconds_to_first_epi = ev->offset_s;
                }
            }
            break;
        }
        case CR_CAT_DEFIBRILLATION: out->shock_count++; break;
        case CR_CAT_RHYTHM:         out->rhythm_check_count++; break;
        default: break;
        }
    }

    if (s->rosc != CR_TIME_NONE) {
        out->has_rosc = true;
        out->seconds_to_rosc = (int32_t)((s->rosc - s->start) / 1000);
    }
}
