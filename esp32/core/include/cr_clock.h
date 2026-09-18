// cr_clock.h — civil date ⇄ epoch, and how a code is stamped.
//
// The engine's clock is integer milliseconds that never jump backwards
// (cr_time.h). That is all the engine needs, but a SAVED code needs one more
// thing: a date a human recognises, so a list of recent codes can say which
// one is which. This is that conversion, and it lives in core rather than in
// the firmware because date arithmetic is where off-by-ones hide — a leap
// year, a month boundary — and here `make test` can prove it.
//
// LOCAL TIME, not UTC. The board carries no timezone database and no way to
// ask for one; the RTC is set to wall-clock time and read back as wall-clock
// time, so what the screen shows is what the clock on the wall shows. The
// cost is that a code recorded either side of a DST change reads an hour out
// — on a device that is also not a medical device, that is the right trade
// against shipping a tzdata.

#ifndef CR_CLOCK_H
#define CR_CLOCK_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "cr_time.h"

/// A wall-clock moment. Fields are the ones a person reads, in the ranges a
/// person expects: month 1-12, day 1-31, hour 0-23.
typedef struct {
    int32_t year;      // full year, e.g. 2026
    uint8_t month;     // 1-12
    uint8_t day;       // 1-31
    uint8_t hour;      // 0-23
    uint8_t minute;    // 0-59
    uint8_t second;    // 0-59
} cr_civil_t;

/// True when every field is in range AND the day exists in that month —
/// 31 February is rejected rather than silently normalised, because a clock
/// that quietly invents a date is worse than one that says it is unset.
bool cr_civil_valid(const cr_civil_t *c);

/// Days since 1970-01-01. Valid across the whole range the RTC can hold.
/// (Howard Hinnant's days_from_civil; the era arithmetic is what makes it
/// exact without a lookup table.)
int64_t cr_days_from_civil(int32_t year, uint8_t month, uint8_t day);

/// Seconds since the epoch, in the same local frame the civil time is in.
int64_t cr_civil_to_epoch_s(const cr_civil_t *c);

/// The inverse. Negative seconds (before 1970) round the right way.
cr_civil_t cr_civil_from_epoch_s(int64_t seconds);

/// "14:32" and "18 Sep 14:32" — how a recent code names itself in a list.
/// Both write into `buf` and return it.
const char *cr_format_time_of_day(char *buf, size_t cap, const cr_civil_t *c);
const char *cr_format_stamp(char *buf, size_t cap, const cr_civil_t *c);

#endif
