#include "cr_clock.h"

#include <stdio.h>

static const char *const k_months[] = {
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
};

static bool is_leap(int32_t y)
{
    return (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0);
}

static uint8_t days_in_month(int32_t year, uint8_t month)
{
    static const uint8_t k[12] = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    if (month < 1 || month > 12) return 0;
    if (month == 2 && is_leap(year)) return 29;
    return k[month - 1];
}

bool cr_civil_valid(const cr_civil_t *c)
{
    if (c == NULL) return false;
    if (c->month < 1 || c->month > 12) return false;
    if (c->day < 1 || c->day > days_in_month(c->year, c->month)) return false;
    return c->hour <= 23 && c->minute <= 59 && c->second <= 59;
}

int64_t cr_days_from_civil(int32_t year, uint8_t month, uint8_t day)
{
    // Shift the year so it starts in March: leap day then lands at the END of
    // the year, which is what removes every special case from the arithmetic.
    int64_t y = year;
    y -= month <= 2;
    const int64_t era = (y >= 0 ? y : y - 399) / 400;
    const int64_t yoe = y - era * 400;                                  // 0…399
    const int64_t doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1;
    const int64_t doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;          // 0…146096
    return era * 146097 + doe - 719468;   // 719468 = days from 0000-03-01 to 1970-01-01
}

int64_t cr_civil_to_epoch_s(const cr_civil_t *c)
{
    if (c == NULL) return 0;
    return cr_days_from_civil(c->year, c->month, c->day) * 86400
         + (int64_t)c->hour * 3600 + (int64_t)c->minute * 60 + c->second;
}

cr_civil_t cr_civil_from_epoch_s(int64_t seconds)
{
    // Floor division, so a moment before 1970 lands on the right day rather
    // than being truncated toward zero into the day after.
    int64_t days = seconds / 86400;
    int64_t rem = seconds % 86400;
    if (rem < 0) { rem += 86400; days -= 1; }

    int64_t z = days + 719468;
    const int64_t era = (z >= 0 ? z : z - 146096) / 146097;
    const int64_t doe = z - era * 146097;                               // 0…146096
    const int64_t yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    const int64_t y = yoe + era * 400;
    const int64_t doy = doe - (365 * yoe + yoe / 4 - yoe / 100);        // 0…365
    const int64_t mp = (5 * doy + 2) / 153;                             // 0…11
    const int64_t d = doy - (153 * mp + 2) / 5 + 1;
    const int64_t m = mp + (mp < 10 ? 3 : -9);

    cr_civil_t out;
    out.year = (int32_t)(y + (m <= 2));
    out.month = (uint8_t)m;
    out.day = (uint8_t)d;
    out.hour = (uint8_t)(rem / 3600);
    out.minute = (uint8_t)((rem % 3600) / 60);
    out.second = (uint8_t)(rem % 60);
    return out;
}

const char *cr_format_time_of_day(char *buf, size_t cap, const cr_civil_t *c)
{
    if (cap == 0) return buf;
    snprintf(buf, cap, "%d:%02d", (int)c->hour, (int)c->minute);
    return buf;
}

const char *cr_format_stamp(char *buf, size_t cap, const cr_civil_t *c)
{
    if (cap == 0) return buf;
    const char *month = (c->month >= 1 && c->month <= 12) ? k_months[c->month - 1] : "???";
    snprintf(buf, cap, "%d %s %d:%02d", (int)c->day, month, (int)c->hour, (int)c->minute);
    return buf;
}
