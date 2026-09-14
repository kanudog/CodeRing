// Ported from DoseCalculatorTests — the maths a lesser model must never break.

#include "cr_defaults.h"
#include "cr_drugs.h"
#include "cr_test.h"
#include "cr_text.h"

// DoseCalculatorTests.testEpi8kg
static void test_epi_8kg(void)
{
    cr_dose_t doses[CR_MAX_DOSE_STEPS];
    size_t n = cr_doses(&cr_drug_epinephrine, 8, doses, CR_MAX_DOSE_STEPS);
    CHECK_I(n, 1);
    CHECK_NEAR(doses[0].amount, 0.08, 0.0001);            // mg
    CHECK(doses[0].has_volume);
    CHECK_NEAR(doses[0].volume_ml, 0.8, 0.0001);          // mL of 0.1 mg/mL
    CHECK(!doses[0].capped);
}

// DoseCalculatorTests.testEpiCapAtOneMg
static void test_epi_cap_at_one_mg(void)
{
    cr_dose_t doses[CR_MAX_DOSE_STEPS];
    cr_doses(&cr_drug_epinephrine, 150, doses, CR_MAX_DOSE_STEPS);
    CHECK_NEAR(doses[0].amount, 1.0, 0.0001);
    CHECK_NEAR(doses[0].volume_ml, 10.0, 0.0001);
    CHECK(doses[0].capped);
}

// DoseCalculatorTests.testAdenosineLadder
static void test_adenosine_ladder(void)
{
    cr_dose_t doses[CR_MAX_DOSE_STEPS];
    cr_doses(&cr_drug_adenosine, 20, doses, CR_MAX_DOSE_STEPS);
    CHECK_NEAR(doses[0].amount, 2.0, 0.0001);   // 0.1 × 20
    CHECK_NEAR(doses[1].amount, 4.0, 0.0001);   // 0.2 × 20

    // The ladder advances with the prior count, then holds the last rung.
    cr_dose_t dose;
    CHECK(cr_primary_dose(&cr_drug_adenosine, 20, 0, &dose));
    CHECK_STR(dose.step_label, "1st");
    CHECK(cr_primary_dose(&cr_drug_adenosine, 20, 1, &dose));
    CHECK_STR(dose.step_label, "2nd");
    CHECK(cr_primary_dose(&cr_drug_adenosine, 20, 5, &dose));
    CHECK_STR(dose.step_label, "2nd");
}

// DoseCalculatorTests.testDefibEnergies
static void test_defib_energies(void)
{
    cr_dose_t doses[CR_MAX_DOSE_STEPS];
    cr_doses(&cr_drug_defibrillation, 12, doses, CR_MAX_DOSE_STEPS);
    CHECK_NEAR(doses[0].amount, 24, 0.0001);   // 2 J/kg
    CHECK_NEAR(doses[1].amount, 48, 0.0001);   // 4 J/kg
    CHECK(!doses[0].has_volume);               // energy has no mL
}

// DoseCalculatorTests.testVolumeFloor
static void test_volume_floor(void)
{
    // Tiny volumes never render as 0.0 mL.
    CHECK_NEAR(cr_rounded_volume(0.031), 0.1, 0.0001);
}

// DoseCalculatorTests.testTrimFormatting
static void test_trim_formatting(void)
{
    char buf[24];
    cr_format_trim(buf, sizeof buf, 0.80); CHECK_STR(buf, "0.8");
    cr_format_trim(buf, sizeof buf, 16.0); CHECK_STR(buf, "16");
    cr_format_trim(buf, sizeof buf, 0.08); CHECK_STR(buf, "0.08");
}

// DoseCalculatorTests.testChipAbbreviations
static void test_chip_abbreviations(void)
{
    char buf[16];
    cr_chip_abbreviation(buf, sizeof buf, "Fluid bolus");  CHECK_STR(buf, "IVF");
    cr_chip_abbreviation(buf, sizeof buf, "Blood given");  CHECK_STR(buf, "BLOOD");
    cr_chip_abbreviation(buf, sizeof buf, "Epinephrine");  CHECK_STR(buf, "EPI");
    cr_chip_abbreviation(buf, sizeof buf, "Amiodarone");   CHECK_STR(buf, "AMIO");
    cr_chip_abbreviation(buf, sizeof buf, "Calcium");      CHECK_STR(buf, "CA");
    cr_chip_abbreviation(buf, sizeof buf, "Dextrose");     CHECK_STR(buf, "DEX");
    cr_chip_abbreviation(buf, sizeof buf, "Bicarb");       CHECK_STR(buf, "BICARB");
    // Unknown short word → said whole; unknown long word → first 3.
    cr_chip_abbreviation(buf, sizeof buf, "Zeta");         CHECK_STR(buf, "ZETA");
    cr_chip_abbreviation(buf, sizeof buf, "Zetatropine");  CHECK_STR(buf, "ZET");
}

// DoseCalculatorTests.testMlPerKgDosing
static void test_ml_per_kg_dosing(void)
{
    // Fluids: 20 mL/kg × 12 kg = 240 mL, featured as mL, no mg tail.
    cr_dose_t doses[CR_MAX_DOSE_STEPS];
    cr_doses(&cr_drug_fluids, 12, doses, CR_MAX_DOSE_STEPS);
    CHECK_NEAR(doses[0].volume_ml, 120, 0.01);   // 10 mL/kg
    CHECK_NEAR(doses[1].volume_ml, 240, 0.01);   // 20 mL/kg

    char text[48];
    CHECK(cr_dose_volume_text(&doses[1], text, sizeof text));
    CHECK_STR(text, "240 mL");
    cr_dose_summary(&doses[1], text, sizeof text);
    CHECK_STR(text, "240 mL");                   // no "(… mg)"

    // 20 mL/kg caps at 2000 mL for a large patient.
    cr_dose_t big[CR_MAX_DOSE_STEPS];
    cr_doses(&cr_drug_fluids, 150, big, CR_MAX_DOSE_STEPS);
    CHECK_NEAR(big[1].volume_ml, 2000, 0.01);
    CHECK(big[1].capped);
}

// Port.doseSummaryFeaturesVolumeFirst — invariant 2 in the one string that
// reaches the log, the TV and the CSV.
static void test_dose_summary_features_volume_first(void)
{
    cr_dose_t dose;
    char text[64];

    CHECK(cr_primary_dose(&cr_drug_epinephrine, 10, 0, &dose));
    cr_dose_summary(&dose, text, sizeof text);
    CHECK_STR(text, "1 mL  (0.1 mg)");

    CHECK(cr_primary_dose(&cr_drug_epinephrine, 150, 0, &dose));
    cr_dose_summary(&dose, text, sizeof text);
    CHECK_STR(text, "10 mL  (1 mg) · capped");

    CHECK(cr_primary_dose(&cr_drug_defibrillation, 12, 0, &dose));
    cr_dose_summary(&dose, text, sizeof text);
    CHECK_STR(text, "24 J");
}

// Port.roundingTiersMatchTheWatch
static void test_rounding_tiers_match_the_watch(void)
{
    CHECK_NEAR(cr_rounded_amount(0.123, CR_UNIT_MG_PER_KG), 0.12, 1e-9);   // <1 → 2 dp
    CHECK_NEAR(cr_rounded_amount(5.55, CR_UNIT_MG_PER_KG), 5.6, 1e-9);     // <10 → 1 dp
    CHECK_NEAR(cr_rounded_amount(123.4, CR_UNIT_MG_PER_KG), 123, 1e-9);    // else whole
    CHECK_NEAR(cr_rounded_amount(23.6, CR_UNIT_J_PER_KG), 24, 1e-9);       // joules → whole
    CHECK_NEAR(cr_rounded_volume(0), 0, 1e-9);                             // zero stays zero
}

const cr_test_case_t cr_dose_tests[] = {
    { "DoseCalculatorTests.testEpi8kg", test_epi_8kg },
    { "DoseCalculatorTests.testEpiCapAtOneMg", test_epi_cap_at_one_mg },
    { "DoseCalculatorTests.testAdenosineLadder", test_adenosine_ladder },
    { "DoseCalculatorTests.testDefibEnergies", test_defib_energies },
    { "DoseCalculatorTests.testVolumeFloor", test_volume_floor },
    { "DoseCalculatorTests.testTrimFormatting", test_trim_formatting },
    { "DoseCalculatorTests.testChipAbbreviations", test_chip_abbreviations },
    { "DoseCalculatorTests.testMlPerKgDosing", test_ml_per_kg_dosing },
    { "Port.doseSummaryFeaturesVolumeFirst", test_dose_summary_features_volume_first },
    { "Port.roundingTiersMatchTheWatch", test_rounding_tiers_match_the_watch },
};
const size_t cr_dose_test_count = sizeof cr_dose_tests / sizeof cr_dose_tests[0];
