// Ported from WeightEstimatorTests. The estimate is the fallback path —
// a real weight, or a Broselow colour, beats it every time.

#include "cr_patient.h"
#include "cr_test.h"

// WeightEstimatorTests.testInfantFormula
static void test_infant_formula(void)
{
    CHECK_NEAR(cr_weight_for_age_months(6), 7.0, 0.001);    // 0.5×6 + 4
}

// WeightEstimatorTests.testChildFormula
static void test_child_formula(void)
{
    CHECK_NEAR(cr_weight_for_age_months(48), 16.0, 0.001);  // (4+4)×2
}

// WeightEstimatorTests.testCap
static void test_cap(void)
{
    CHECK(cr_weight_for_age_months(300) <= 50);
}

// Port.broselowZonesCoverTheTape
static void test_broselow_zones_cover_the_tape(void)
{
    CHECK_I(cr_broselow_zone_count, 9);
    CHECK_STR(cr_broselow_zones[0].id, "grey");
    CHECK_STR(cr_broselow_zones[cr_broselow_zone_count - 1].id, "green");
    // Midpoints drive dosing, so the 0.1 kg rounding matters.
    CHECK_NEAR(cr_broselow_mid_kg(&cr_broselow_zones[4]), 13.0, 0.001);   // yellow 12–14
    CHECK_NEAR(cr_broselow_mid_kg(&cr_broselow_zones[5]), 16.5, 0.001);   // white 15–18
    for (size_t i = 0; i < cr_broselow_zone_count; i++) {
        CHECK(cr_broselow_zones[i].min_kg < cr_broselow_zones[i].max_kg);
    }
}

// Port.weightEstimateNeverGoesNegative — a nonsense age must not produce a
// nonsense dose.
static void test_weight_estimate_never_goes_negative(void)
{
    CHECK_NEAR(cr_weight_for_age_months(0), 4.0, 0.001);
    CHECK_NEAR(cr_weight_for_age_months(-5), 4.0, 0.001);
}

const cr_test_case_t cr_weight_tests[] = {
    { "WeightEstimatorTests.testInfantFormula", test_infant_formula },
    { "WeightEstimatorTests.testChildFormula", test_child_formula },
    { "WeightEstimatorTests.testCap", test_cap },
    { "Port.broselowZonesCoverTheTape", test_broselow_zones_cover_the_tape },
    { "Port.weightEstimateNeverGoesNegative", test_weight_estimate_never_goes_negative },
};
const size_t cr_weight_test_count = sizeof cr_weight_tests / sizeof cr_weight_tests[0];
