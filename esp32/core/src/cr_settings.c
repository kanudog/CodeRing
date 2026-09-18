#include "cr_settings.h"

#include <math.h>
#include <string.h>

#include "cr_json.h"
#include "cr_text.h"

double cr_metronome_pitch_hz(cr_metronome_pitch_t pitch)
{
    switch (pitch) {
    case CR_PITCH_LOW:    return 392.0;    // G4
    case CR_PITCH_MEDIUM: return 523.25;   // C5
    case CR_PITCH_HIGH:   return 783.99;   // G5
    }
    return 523.25;
}

static const char *pitch_key(cr_metronome_pitch_t pitch)
{
    switch (pitch) {
    case CR_PITCH_LOW:    return "low";
    case CR_PITCH_MEDIUM: return "medium";
    case CR_PITCH_HIGH:   return "high";
    }
    return "medium";
}

static bool pitch_from_key(const char *key, cr_metronome_pitch_t *out)
{
    if (strcmp(key, "low") == 0)    { *out = CR_PITCH_LOW;    return true; }
    if (strcmp(key, "medium") == 0) { *out = CR_PITCH_MEDIUM; return true; }
    if (strcmp(key, "high") == 0)   { *out = CR_PITCH_HIGH;   return true; }
    return false;
}

static const char *cue_key(cr_cue_pattern_t cue)
{
    switch (cue) {
    case CR_CUE_SINGLE: return "single";
    case CR_CUE_DOUBLE: return "double";
    case CR_CUE_TRIPLE: return "triple";
    case CR_CUE_LONG:   return "long";
    }
    return "single";
}

static bool cue_from_key(const char *key, cr_cue_pattern_t *out)
{
    if (strcmp(key, "single") == 0) { *out = CR_CUE_SINGLE; return true; }
    if (strcmp(key, "double") == 0) { *out = CR_CUE_DOUBLE; return true; }
    if (strcmp(key, "triple") == 0) { *out = CR_CUE_TRIPLE; return true; }
    if (strcmp(key, "long") == 0)   { *out = CR_CUE_LONG;   return true; }
    return false;
}

cr_settings_t cr_settings_default(void)
{
    cr_settings_t s;
    memset(&s, 0, sizeof s);
    s.cues_enabled = true;
    s.metronome_sound_on = false;   // opt-in, exactly as on the watch
    s.metronome_bpm = 110;
    s.metronome_pitch = CR_PITCH_MEDIUM;
    s.tv_link_on = false;
    s.keep_screen_on = false;
    s.menu_tap_only = false;
    s.cycle_override_ms = CR_TIME_NONE;
    s.interval_override_ms = CR_TIME_NONE;
    s.default_drug_set_id[0] = '\0';
    // Defaults keep the three due-cues distinct from one another.
    s.pulse_check_due = CR_CUE_TRIPLE;
    s.med_due = CR_CUE_DOUBLE;
    s.hands_off_overshoot = CR_CUE_LONG;
    return s;
}

bool cr_settings_equal(const cr_settings_t *a, const cr_settings_t *b)
{
    return a->cues_enabled == b->cues_enabled &&
           a->metronome_sound_on == b->metronome_sound_on &&
           a->metronome_bpm == b->metronome_bpm &&
           a->metronome_pitch == b->metronome_pitch &&
           a->keep_screen_on == b->keep_screen_on &&
           a->tv_link_on == b->tv_link_on &&
           a->menu_tap_only == b->menu_tap_only &&
           a->cycle_override_ms == b->cycle_override_ms &&
           a->interval_override_ms == b->interval_override_ms &&
           strcmp(a->default_drug_set_id, b->default_drug_set_id) == 0 &&
           a->pulse_check_due == b->pulse_check_due &&
           a->med_due == b->med_due &&
           a->hands_off_overshoot == b->hands_off_overshoot;
}

size_t cr_settings_to_json(const cr_settings_t *s, char *buf, size_t cap)
{
    cr_jw_t w;
    cr_jw_init(&w, buf, cap);
    // Keys sorted, and nil overrides omitted, so this file is byte-comparable
    // with the one the phone writes (JSONEncoder.sortedKeys + encodeIfPresent).
    cr_jw_raw(&w, "{");
    if (s->cycle_override_ms != CR_TIME_NONE) {
        cr_jw_raw(&w, "\"cycleSecondsOverride\":");
        cr_jw_num(&w, (double)s->cycle_override_ms / 1000.0);
        cr_jw_raw(&w, ",");
    }
    if (s->default_drug_set_id[0] != '\0') {
        cr_jw_raw(&w, "\"defaultDrugSetID\":");
        cr_jw_str(&w, s->default_drug_set_id);
        cr_jw_raw(&w, ",");
    }
    if (s->interval_override_ms != CR_TIME_NONE) {
        cr_jw_raw(&w, "\"epiSecondsOverride\":");
        cr_jw_num(&w, (double)s->interval_override_ms / 1000.0);
        cr_jw_raw(&w, ",");
    }
    cr_jw_raw(&w, "\"hapticCycleComplete\":");  cr_jw_str(&w, cue_key(s->hands_off_overshoot));
    cr_jw_raw(&w, ",\"hapticMedDue\":");        cr_jw_str(&w, cue_key(s->med_due));
    cr_jw_raw(&w, ",\"hapticPulseCheckDue\":"); cr_jw_str(&w, cue_key(s->pulse_check_due));
    cr_jw_raw(&w, ",\"hapticsEnabled\":");      cr_jw_bool(&w, s->cues_enabled);
    cr_jw_raw(&w, ",\"tvLinkOn\":");           cr_jw_bool(&w, s->tv_link_on);
    cr_jw_raw(&w, ",\"keepScreenOn\":");        cr_jw_bool(&w, s->keep_screen_on);
    cr_jw_raw(&w, ",\"menuTapOnly\":");         cr_jw_bool(&w, s->menu_tap_only);
    cr_jw_raw(&w, ",\"metronomeBPM\":");        cr_jw_i64(&w, s->metronome_bpm);
    cr_jw_raw(&w, ",\"metronomePitch\":");      cr_jw_str(&w, pitch_key(s->metronome_pitch));
    cr_jw_raw(&w, ",\"metronomeSoundOn\":");    cr_jw_bool(&w, s->metronome_sound_on);
    cr_jw_raw(&w, "}");
    return w.len;
}

/// A UUID string as Swift writes it: 8-4-4-4-12 hex, stored uppercase.
static bool copy_uuid(char *dst, size_t cap, const char *src)
{
    size_t n = strlen(src);
    if (n != 36 || cap < 37) return false;
    for (size_t i = 0; i < 36; i++) {
        char c = src[i];
        if (i == 8 || i == 13 || i == 18 || i == 23) {
            if (c != '-') return false;
            dst[i] = c;
            continue;
        }
        if (c >= '0' && c <= '9') dst[i] = c;
        else if (c >= 'a' && c <= 'f') dst[i] = (char)(c - 32);
        else if (c >= 'A' && c <= 'F') dst[i] = c;
        else return false;
    }
    dst[36] = '\0';
    return true;
}

static bool integral_in_int32(double v)
{
    return v == floor(v) && v >= -2147483648.0 && v <= 2147483647.0;
}

bool cr_settings_from_json(const char *json, cr_settings_t *out)
{
    cr_settings_t s = cr_settings_default();
    if (json == NULL) { *out = s; return false; }

    const char *p = cr_json_skip_ws(json);
    if (*p != '{') { *out = s; return false; }
    p = cr_json_skip_ws(p + 1);
    if (*p == '}') { p++; goto done; }

    for (;;) {
        char key[64];
        cr_json_kind_t key_kind;
        p = cr_json_skip_ws(p);
        if (*p != '"') goto fail;
        p = cr_json_value(p, &key_kind, NULL, NULL, key, sizeof key);
        if (p == NULL) goto fail;
        p = cr_json_skip_ws(p);
        if (*p != ':') goto fail;

        cr_json_kind_t kind;
        bool boolean = false;
        double number = 0;
        char text[64];
        text[0] = '\0';
        p = cr_json_value(p + 1, &kind, &boolean, &number, text, sizeof text);
        if (p == NULL) goto fail;

        // null means "not present" — every field keeps its default, which is
        // how a file from an older build stays loadable.
        if (kind != CR_JSON_NULL) {
            if (strcmp(key, "hapticsEnabled") == 0) {
                if (kind != CR_JSON_BOOL) goto fail;
                s.cues_enabled = boolean;
            } else if (strcmp(key, "metronomeSoundOn") == 0) {
                if (kind != CR_JSON_BOOL) goto fail;
                s.metronome_sound_on = boolean;
            } else if (strcmp(key, "tvLinkOn") == 0) {
                if (kind != CR_JSON_BOOL) goto fail;
                s.tv_link_on = boolean;
            } else if (strcmp(key, "keepScreenOn") == 0) {
                if (kind != CR_JSON_BOOL) goto fail;
                s.keep_screen_on = boolean;
            } else if (strcmp(key, "menuTapOnly") == 0) {
                if (kind != CR_JSON_BOOL) goto fail;
                s.menu_tap_only = boolean;
            } else if (strcmp(key, "metronomeBPM") == 0) {
                if (kind != CR_JSON_NUMBER || !integral_in_int32(number)) goto fail;
                s.metronome_bpm = (int32_t)number;
            } else if (strcmp(key, "metronomePitch") == 0) {
                if (kind != CR_JSON_STRING || !pitch_from_key(text, &s.metronome_pitch)) goto fail;
            } else if (strcmp(key, "cycleSecondsOverride") == 0) {
                if (kind != CR_JSON_NUMBER) goto fail;
                s.cycle_override_ms = (cr_ms_t)llround(number * 1000.0);
            } else if (strcmp(key, "epiSecondsOverride") == 0) {
                if (kind != CR_JSON_NUMBER) goto fail;
                s.interval_override_ms = (cr_ms_t)llround(number * 1000.0);
            } else if (strcmp(key, "defaultDrugSetID") == 0) {
                if (kind != CR_JSON_STRING ||
                    !copy_uuid(s.default_drug_set_id, sizeof s.default_drug_set_id, text)) {
                    goto fail;
                }
            } else if (strcmp(key, "hapticPulseCheckDue") == 0) {
                if (kind != CR_JSON_STRING || !cue_from_key(text, &s.pulse_check_due)) goto fail;
            } else if (strcmp(key, "hapticMedDue") == 0) {
                if (kind != CR_JSON_STRING || !cue_from_key(text, &s.med_due)) goto fail;
            } else if (strcmp(key, "hapticCycleComplete") == 0) {
                if (kind != CR_JSON_STRING || !cue_from_key(text, &s.hands_off_overshoot)) goto fail;
            }
            // Unknown keys are ignored, so a newer phone build can add fields
            // without breaking this device.
        }

        p = cr_json_skip_ws(p);
        if (*p == ',') { p++; continue; }
        if (*p == '}') { p++; break; }
        goto fail;
    }

done:
    if (*cr_json_skip_ws(p) != '\0') goto fail;
    *out = s;
    return true;

fail:
    *out = cr_settings_default();
    return false;
}
