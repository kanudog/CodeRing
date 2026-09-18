// Ported from AppSettingsCodableTests, re-expressed against the JSON this
// board reads and writes. Same keys as the Swift Codable, so the phone's
// settings.json loads here unchanged.

#include <string.h>

#include "cr_settings.h"
#include "cr_test.h"

// AppSettingsCodableTests.testMissingFieldsDecodeToDefaults
static void test_missing_fields_decode_to_defaults(void)
{
    // Settings written by older builds (fields missing from the JSON) must
    // load with defaults instead of failing — menuTapOnly ships after 1.0.
    cr_settings_t settings;
    CHECK(cr_settings_from_json("{}", &settings));
    cr_settings_t defaults = cr_settings_default();
    CHECK(cr_settings_equal(&settings, &defaults));
    CHECK(!settings.menu_tap_only);
}

// AppSettingsCodableTests.testMenuTapOnlyRoundTrips
static void test_menu_tap_only_round_trips(void)
{
    cr_settings_t settings = cr_settings_default();
    settings.menu_tap_only = true;

    char json[512];
    size_t needed = cr_settings_to_json(&settings, json, sizeof json);
    CHECK(needed < sizeof json);

    cr_settings_t decoded;
    CHECK(cr_settings_from_json(json, &decoded));
    CHECK(decoded.menu_tap_only);
}

// Port.settingsRoundTripEveryField
static void test_settings_round_trip_every_field(void)
{
    cr_settings_t settings = cr_settings_default();
    settings.cues_enabled = false;
    settings.metronome_sound_on = true;
    settings.metronome_bpm = 100;
    settings.metronome_pitch = CR_PITCH_HIGH;
    settings.keep_screen_on = true;
    settings.menu_tap_only = true;
    settings.cycle_override_ms = CR_SEC(90);
    settings.interval_override_ms = CR_SEC(240);
    strcpy(settings.default_drug_set_id, "C0DE0000-0000-4000-8000-000000000001");
    settings.pulse_check_due = CR_CUE_SINGLE;
    settings.med_due = CR_CUE_LONG;
    settings.hands_off_overshoot = CR_CUE_DOUBLE;
    settings.tv_link_on = true;

    char json[512];
    CHECK(cr_settings_to_json(&settings, json, sizeof json) < sizeof json);
    CHECK_HAS(json, "\"cycleSecondsOverride\":90");
    CHECK_HAS(json, "\"epiSecondsOverride\":240");

    cr_settings_t decoded;
    CHECK(cr_settings_from_json(json, &decoded));
    CHECK(cr_settings_equal(&settings, &decoded));
}

// Port.settingsOmitUnsetOverrides — nil stays nil, so the protocol default
// keeps winning instead of being frozen into the file.
static void test_settings_omit_unset_overrides(void)
{
    cr_settings_t settings = cr_settings_default();
    char json[512];
    cr_settings_to_json(&settings, json, sizeof json);
    CHECK(strstr(json, "cycleSecondsOverride") == NULL);
    CHECK(strstr(json, "epiSecondsOverride") == NULL);
    CHECK(strstr(json, "defaultDrugSetID") == NULL);

    cr_settings_t decoded;
    CHECK(cr_settings_from_json(json, &decoded));
    CHECK_I(decoded.cycle_override_ms, CR_TIME_NONE);
    CHECK_I(decoded.interval_override_ms, CR_TIME_NONE);
}

// Port.settingsRejectBadFilesWholesale — a corrupt file falls back to
// defaults rather than half-loading, which is what CodeStore does today.
static void test_settings_reject_bad_files_wholesale(void)
{
    cr_settings_t s;
    cr_settings_t defaults = cr_settings_default();

    CHECK(!cr_settings_from_json("{\"menuTapOnly\":\"yes\"}", &s));   // wrong type
    CHECK(cr_settings_equal(&s, &defaults));
    CHECK(!cr_settings_from_json("{\"metronomeBPM\":110.5}", &s));    // not an Int
    CHECK(!cr_settings_from_json("{\"metronomePitch\":\"loud\"}", &s));
    CHECK(!cr_settings_from_json("{\"defaultDrugSetID\":\"nope\"}", &s));
    CHECK(!cr_settings_from_json("{\"menuTapOnly\":true", &s));       // truncated
    CHECK(!cr_settings_from_json("{} trailing", &s));
    CHECK(!cr_settings_from_json("[]", &s));
    CHECK(!cr_settings_from_json(NULL, &s));
}

// Port.settingsIgnoreUnknownKeys — a newer phone build must not brick this
// device's settings.
static void test_settings_ignore_unknown_keys(void)
{
    cr_settings_t s;
    CHECK(cr_settings_from_json(
        "{\"futureThing\":{\"a\":[1,2,{\"b\":null}]},\"metronomeBPM\":100,\"menuTapOnly\":null}", &s));
    CHECK_I(s.metronome_bpm, 100);
    CHECK(!s.menu_tap_only);   // null means "absent", so the default stands
}

// Port.settingsReportTruncation
static void test_settings_report_truncation(void)
{
    cr_settings_t settings = cr_settings_default();
    char small[16];
    size_t needed = cr_settings_to_json(&settings, small, sizeof small);
    CHECK(needed > sizeof small);
    CHECK_I(strlen(small), sizeof small - 1);   // still NUL-terminated

    char big[512];
    CHECK_I(cr_settings_to_json(&settings, big, sizeof big), needed);
}

const cr_test_case_t cr_settings_tests[] = {
    { "AppSettingsCodableTests.testMissingFieldsDecodeToDefaults",
      test_missing_fields_decode_to_defaults },
    { "AppSettingsCodableTests.testMenuTapOnlyRoundTrips", test_menu_tap_only_round_trips },
    { "Port.settingsRoundTripEveryField", test_settings_round_trip_every_field },
    { "Port.settingsOmitUnsetOverrides", test_settings_omit_unset_overrides },
    { "Port.settingsRejectBadFilesWholesale", test_settings_reject_bad_files_wholesale },
    { "Port.settingsIgnoreUnknownKeys", test_settings_ignore_unknown_keys },
    { "Port.settingsReportTruncation", test_settings_report_truncation },
};
const size_t cr_settings_test_count = sizeof cr_settings_tests / sizeof cr_settings_tests[0];
