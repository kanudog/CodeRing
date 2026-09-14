#include "cr_snapshot.h"

#include <string.h>

#include "cr_json.h"
#include "cr_text.h"

static void write_time_or_null(cr_jw_t *w, cr_ms_t t)
{
    if (t == CR_TIME_NONE) cr_jw_raw(w, "null");
    else cr_jw_i64(w, t);
}

size_t cr_snapshot_json(const cr_engine_t *e, cr_ms_t now, uint16_t first_event,
                        char *buf, size_t cap)
{
    cr_jw_t w;
    cr_jw_init(&w, buf, cap);
    const cr_session_t *s = &e->session;

    cr_jw_raw(&w, "{\"v\":1,\"nowMs\":");
    cr_jw_i64(&w, now);

    cr_jw_raw(&w, ",\"session\":{\"id\":");      cr_jw_str(&w, s->id);
    cr_jw_raw(&w, ",\"protocolId\":");           cr_jw_str(&w, s->protocol_id);
    cr_jw_raw(&w, ",\"protocolName\":");         cr_jw_str(&w, s->protocol_name);
    cr_jw_raw(&w, ",\"protocolShort\":");        cr_jw_str(&w, e->protocol.short_name);
    cr_jw_raw(&w, ",\"device\":");               cr_jw_str(&w, s->device_name);
    cr_jw_raw(&w, ",\"startMs\":");              cr_jw_i64(&w, s->start);
    cr_jw_raw(&w, ",\"endMs\":");                write_time_or_null(&w, s->end);
    cr_jw_raw(&w, ",\"roscMs\":");               write_time_or_null(&w, s->rosc);
    cr_jw_raw(&w, "}");

    cr_jw_raw(&w, ",\"state\":{\"cprStarted\":"); cr_jw_bool(&w, e->cpr_started);
    cr_jw_raw(&w, ",\"paused\":");                cr_jw_bool(&w, e->paused);
    cr_jw_raw(&w, ",\"pulseCheck\":");            cr_jw_bool(&w, e->in_pulse_check);
    cr_jw_raw(&w, ",\"rosc\":");                  cr_jw_bool(&w, e->rosc_achieved);
    cr_jw_raw(&w, ",\"ended\":");                 cr_jw_bool(&w, e->ended);
    // The TV shows this too: a log that stopped recording must be visible in
    // the room, not just on the wrist.
    cr_jw_raw(&w, ",\"overflow\":");              cr_jw_bool(&w, e->overflow);
    cr_jw_raw(&w, "}");

    cr_jw_raw(&w, ",\"patient\":{\"weightKg\":"); cr_jw_num(&w, s->patient.weight_kg);
    cr_jw_raw(&w, ",\"source\":");                cr_jw_str(&w, cr_weight_source_key(s->patient.source));
    cr_jw_raw(&w, ",\"broselow\":");              cr_jw_str_or_null(&w, s->patient.broselow_zone_id);
    cr_jw_raw(&w, ",\"ageMonths\":");
    if (s->patient.has_age) cr_jw_i64(&w, s->patient.age_months);
    else cr_jw_raw(&w, "null");
    cr_jw_raw(&w, "}");

    char hint[64];
    cr_engine_hint(e, now, hint, sizeof hint);
    cr_jw_raw(&w, ",\"hint\":");                  cr_jw_str(&w, hint);

    const cr_timer_spec_t *cycle = cr_protocol_cycle_spec(&e->protocol);
    cr_jw_raw(&w, ",\"clock\":{\"elapsedMs\":");  cr_jw_i64(&w, cr_engine_elapsed(e, now));
    cr_jw_raw(&w, ",\"cycleMs\":");
    if (cycle != NULL) cr_jw_i64(&w, cycle->duration_ms); else cr_jw_raw(&w, "null");
    cr_jw_raw(&w, ",\"cycleRemainingMs\":");      cr_jw_i64(&w, cr_engine_cycle_remaining(e, now));
    cr_jw_raw(&w, ",\"cycleIndex\":");            cr_jw_i64(&w, cr_engine_cycle_index(e));
    cr_jw_raw(&w, ",\"pulseCheckElapsedMs\":");   cr_jw_i64(&w, cr_engine_pulse_check_elapsed(e, now));
    cr_jw_raw(&w, ",\"roscElapsedMs\":");         cr_jw_i64(&w, cr_engine_rosc_elapsed(e, now));
    cr_jw_raw(&w, ",\"vitalsRemainingMs\":");
    {
        cr_ms_t vitals;
        if (cr_engine_vitals_remaining(e, now, &vitals)) cr_jw_i64(&w, vitals);
        else cr_jw_raw(&w, "null");
    }
    cr_jw_raw(&w, "}");

    cr_jw_raw(&w, ",\"intervals\":[");
    size_t interval_count = cr_protocol_interval_count(&e->protocol);
    for (size_t i = 0; i < interval_count; i++) {
        const cr_timer_spec_t *spec = cr_protocol_interval_spec(&e->protocol, i);
        if (i > 0) cr_jw_raw(&w, ",");
        cr_jw_raw(&w, "{\"id\":");          cr_jw_str(&w, spec->id);
        cr_jw_raw(&w, ",\"title\":");       cr_jw_str(&w, spec->title);
        cr_jw_raw(&w, ",\"durationMs\":");  cr_jw_i64(&w, spec->duration_ms);
        cr_jw_raw(&w, ",\"running\":");     cr_jw_bool(&w, cr_engine_interval_is_running(e, spec));
        cr_jw_raw(&w, ",\"remainingMs\":"); cr_jw_i64(&w, cr_engine_interval_remaining(e, spec, now));
        cr_jw_raw(&w, ",\"overdue\":");     cr_jw_bool(&w, cr_engine_interval_is_overdue(e, spec, now));
        cr_jw_raw(&w, ",\"color\":");       cr_jw_color(&w, spec->color);
        cr_jw_raw(&w, "}");
    }
    cr_jw_raw(&w, "]");

    cr_running_timer_t timers[CR_MAX_RUNNING_TIMERS];
    size_t timer_count = cr_session_running_timers(s, timers, CR_MAX_RUNNING_TIMERS);
    cr_jw_raw(&w, ",\"timers\":[");
    for (size_t i = 0; i < timer_count; i++) {
        if (i > 0) cr_jw_raw(&w, ",");
        cr_jw_raw(&w, "{\"id\":");        cr_jw_str(&w, timers[i].id);
        cr_jw_raw(&w, ",\"title\":");     cr_jw_str(&w, timers[i].title);
        cr_jw_raw(&w, ",\"elapsedMs\":"); cr_jw_i64(&w, cr_running_timer_elapsed(&timers[i], now));
        cr_jw_raw(&w, ",\"color\":");     cr_jw_color(&w, timers[i].color);
        cr_jw_raw(&w, "}");
    }
    cr_jw_raw(&w, "]");

    // rev + count let a client tell an append from an undo: same rev means
    // nothing changed, a smaller count means something was removed.
    cr_jw_raw(&w, ",\"log\":{\"rev\":");  cr_jw_i64(&w, e->log_rev);
    cr_jw_raw(&w, ",\"count\":");         cr_jw_i64(&w, s->event_count);
    cr_jw_raw(&w, ",\"from\":");          cr_jw_i64(&w, first_event);
    cr_jw_raw(&w, ",\"events\":[");
    for (uint16_t i = first_event; i < s->event_count; i++) {
        const cr_event_t *ev = &s->events[i];
        char stamp[16];
        cr_format_offset(stamp, sizeof stamp, ev->offset_s);
        if (i > first_event) cr_jw_raw(&w, ",");
        cr_jw_raw(&w, "{\"seq\":");      cr_jw_i64(&w, ev->seq);
        cr_jw_raw(&w, ",\"atMs\":");     cr_jw_i64(&w, ev->date);
        cr_jw_raw(&w, ",\"offsetS\":");  cr_jw_i64(&w, ev->offset_s);
        cr_jw_raw(&w, ",\"stamp\":");    cr_jw_str(&w, stamp);
        cr_jw_raw(&w, ",\"title\":");    cr_jw_str(&w, ev->title);
        cr_jw_raw(&w, ",\"detail\":");   cr_jw_str_or_null(&w, ev->detail);
        cr_jw_raw(&w, ",\"category\":"); cr_jw_str(&w, cr_category_key(ev->category));
        cr_jw_raw(&w, ",\"defId\":");    cr_jw_str_or_null(&w, ev->definition_id);
        cr_jw_raw(&w, ",\"color\":");    cr_jw_color(&w, cr_event_tint(ev));
        cr_jw_raw(&w, "}");
    }
    cr_jw_raw(&w, "]}");

    cr_stats_t stats;
    cr_session_stats(s, now, &stats);
    cr_jw_raw(&w, ",\"stats\":{\"totalMs\":");   cr_jw_i64(&w, stats.total_ms);
    cr_jw_raw(&w, ",\"pausedMs\":");             cr_jw_i64(&w, stats.paused_ms);
    cr_jw_raw(&w, ",\"cprFraction\":");          cr_jw_num(&w, stats.cpr_fraction);
    cr_jw_raw(&w, ",\"pauseCount\":");           cr_jw_i64(&w, stats.pause_count);
    cr_jw_raw(&w, ",\"epiCount\":");             cr_jw_i64(&w, stats.epi_count);
    cr_jw_raw(&w, ",\"shockCount\":");           cr_jw_i64(&w, stats.shock_count);
    cr_jw_raw(&w, ",\"rhythmCheckCount\":");     cr_jw_i64(&w, stats.rhythm_check_count);
    cr_jw_raw(&w, ",\"secondsToFirstEpi\":");
    if (stats.has_first_epi) cr_jw_i64(&w, stats.seconds_to_first_epi); else cr_jw_raw(&w, "null");
    cr_jw_raw(&w, ",\"secondsToRosc\":");
    if (stats.has_rosc) cr_jw_i64(&w, stats.seconds_to_rosc); else cr_jw_raw(&w, "null");
    cr_jw_raw(&w, ",\"meds\":[");
    for (uint8_t i = 0; i < stats.med_count; i++) {
        if (i > 0) cr_jw_raw(&w, ",");
        cr_jw_raw(&w, "{\"title\":");  cr_jw_str(&w, stats.meds[i].title);
        cr_jw_raw(&w, ",\"count\":");  cr_jw_i64(&w, stats.meds[i].count);
        cr_jw_raw(&w, "}");
    }
    cr_jw_raw(&w, "]}");

    cr_jw_raw(&w, "}");
    return w.len;
}
