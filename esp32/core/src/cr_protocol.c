#include "cr_protocol.h"

const cr_timer_spec_t *cr_protocol_cycle_spec(const cr_protocol_t *p)
{
    if (p == NULL) return NULL;
    for (uint8_t i = 0; i < p->timer_count; i++) {
        if (p->timers[i].role == CR_TIMER_CPR_CYCLE) return &p->timers[i];
    }
    return NULL;
}

const cr_timer_spec_t *cr_protocol_vitals_spec(const cr_protocol_t *p)
{
    if (p == NULL) return NULL;
    for (uint8_t i = 0; i < p->timer_count; i++) {
        if (p->timers[i].role == CR_TIMER_POST_ROSC_VITALS) return &p->timers[i];
    }
    return NULL;
}

size_t cr_protocol_interval_count(const cr_protocol_t *p)
{
    size_t n = 0;
    if (p == NULL) return 0;
    for (uint8_t i = 0; i < p->timer_count; i++) {
        if (p->timers[i].role == CR_TIMER_DRUG_INTERVAL) n++;
    }
    return n;
}

const cr_timer_spec_t *cr_protocol_interval_spec(const cr_protocol_t *p, size_t n)
{
    size_t seen = 0;
    if (p == NULL) return NULL;
    for (uint8_t i = 0; i < p->timer_count; i++) {
        if (p->timers[i].role != CR_TIMER_DRUG_INTERVAL) continue;
        if (seen == n) return &p->timers[i];
        seen++;
    }
    return NULL;
}

cr_protocol_t cr_protocol_applying(const cr_protocol_t *base, cr_ms_t cycle_ms, cr_ms_t interval_ms)
{
    cr_protocol_t copy = *base;
    for (uint8_t i = 0; i < copy.timer_count; i++) {
        if (copy.timers[i].role == CR_TIMER_CPR_CYCLE && cycle_ms != CR_TIME_NONE) {
            copy.timers[i].duration_ms = cycle_ms;
        }
        if (copy.timers[i].role == CR_TIMER_DRUG_INTERVAL && interval_ms != CR_TIME_NONE) {
            copy.timers[i].duration_ms = interval_ms;
        }
    }
    return copy;
}
