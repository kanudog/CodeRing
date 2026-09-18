// Dates, which nothing else in this suite covers because until now the board
// had no clock — the wall time was stamped in at build time. A saved code is
// only useful if it can say WHEN, so this is the arithmetic a list of recent
// codes rests on. There is no Swift counterpart: the watch gets dates from
// Foundation.

#include "cr_clock.h"
#include "cr_test.h"

static void check_roundtrip(int32_t y, uint8_t mo, uint8_t d, uint8_t h, uint8_t mi, uint8_t s)
{
    const cr_civil_t in = { y, mo, d, h, mi, s };
    const cr_civil_t out = cr_civil_from_epoch_s(cr_civil_to_epoch_s(&in));
    CHECK_I(out.year, in.year);
    CHECK_I(out.month, in.month);
    CHECK_I(out.day, in.day);
    CHECK_I(out.hour, in.hour);
    CHECK_I(out.minute, in.minute);
    CHECK_I(out.second, in.second);
}

// Port.civilDatesRoundTrip
static void test_civil_dates_round_trip(void)
{
    // The anchor everything else is measured from.
    const cr_civil_t epoch = { 1970, 1, 1, 0, 0, 0 };
    CHECK_I(cr_civil_to_epoch_s(&epoch), 0);

    // A date read off this project: the day the port reached the ROSC screen.
    const cr_civil_t known = { 2026, 9, 18, 2, 20, 0 };
    const cr_civil_t back = cr_civil_from_epoch_s(cr_civil_to_epoch_s(&known));
    CHECK_I(back.year, 2026);
    CHECK_I(back.month, 9);
    CHECK_I(back.day, 18);
    CHECK_I(back.hour, 2);
    CHECK_I(back.minute, 20);

    // The boundaries that break naive date maths.
    check_roundtrip(2024, 2, 29, 12, 0, 0);    // leap day
    check_roundtrip(2000, 2, 29, 23, 59, 59);  // century that IS a leap year
    check_roundtrip(2100, 3, 1, 0, 0, 0);      // century that is NOT
    check_roundtrip(2026, 12, 31, 23, 59, 59); // year end
    check_roundtrip(2027, 1, 1, 0, 0, 0);      // year start
    check_roundtrip(2026, 3, 1, 0, 0, 0);      // the month the algorithm pivots on
    check_roundtrip(1999, 12, 31, 23, 59, 59);
    check_roundtrip(2038, 1, 19, 3, 14, 7);    // where a 32-bit time_t would stop

    // Every day of a leap year and the year after it, in one sweep: a
    // conversion that is wrong for exactly one day in February is the whole
    // reason this test exists.
    for (int32_t year = 2024; year <= 2025; year++) {
        for (uint8_t month = 1; month <= 12; month++) {
            for (uint8_t day = 1; day <= 28; day++) {
                check_roundtrip(year, month, day, 13, 45, 30);
            }
        }
    }
}

// Port.civilDatesRejectImpossibleOnes — a clock that quietly invents a date
// is worse than one that admits it is unset.
static void test_civil_dates_reject_impossible_ones(void)
{
    const cr_civil_t good = { 2026, 9, 18, 2, 20, 0 };
    CHECK(cr_civil_valid(&good));

    const cr_civil_t feb30 = { 2026, 2, 30, 0, 0, 0 };
    CHECK(!cr_civil_valid(&feb30));
    const cr_civil_t feb29_common = { 2026, 2, 29, 0, 0, 0 };   // 2026 is not a leap year
    CHECK(!cr_civil_valid(&feb29_common));
    const cr_civil_t feb29_leap = { 2024, 2, 29, 0, 0, 0 };
    CHECK(cr_civil_valid(&feb29_leap));
    const cr_civil_t month0 = { 2026, 0, 1, 0, 0, 0 };
    CHECK(!cr_civil_valid(&month0));
    const cr_civil_t month13 = { 2026, 13, 1, 0, 0, 0 };
    CHECK(!cr_civil_valid(&month13));
    const cr_civil_t hour24 = { 2026, 9, 18, 24, 0, 0 };
    CHECK(!cr_civil_valid(&hour24));
    const cr_civil_t day0 = { 2026, 9, 0, 0, 0, 0 };
    CHECK(!cr_civil_valid(&day0));
    CHECK(!cr_civil_valid(NULL));
}

// Port.recentCodeNamesItself — what the Recents list prints.
static void test_recent_code_names_itself(void)
{
    char buf[32];
    const cr_civil_t c = { 2026, 9, 18, 2, 5, 0 };
    CHECK_STR(cr_format_time_of_day(buf, sizeof buf, &c), "2:05");
    CHECK_STR(cr_format_stamp(buf, sizeof buf, &c), "18 Sep 2:05");

    const cr_civil_t afternoon = { 2026, 12, 1, 14, 32, 9 };
    CHECK_STR(cr_format_time_of_day(buf, sizeof buf, &afternoon), "14:32");
    CHECK_STR(cr_format_stamp(buf, sizeof buf, &afternoon), "1 Dec 14:32");
}

const cr_test_case_t cr_clock_tests[] = {
    { "Port.civilDatesRoundTrip", test_civil_dates_round_trip },
    { "Port.civilDatesRejectImpossibleOnes", test_civil_dates_reject_impossible_ones },
    { "Port.recentCodeNamesItself", test_recent_code_names_itself },
};
const size_t cr_clock_test_count = sizeof cr_clock_tests / sizeof cr_clock_tests[0];
