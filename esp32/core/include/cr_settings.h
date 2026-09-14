// cr_settings.h — user settings (AppSettings in CodeCore/Storage/Store.swift).
//
// The JSON uses the SAME keys as the Swift Codable, so a settings.json from
// the phone loads here and vice versa. Like Swift, every field is optional
// on read: settings written by an older build load intact instead of
// resetting. Unknown keys are ignored; a malformed file falls back to
// defaults whole, which is what CodeStore does today.
//
// This board has no motor, so the three cue patterns play as TONE rhythms
// rather than wrist taps. The fields keep their Swift names so the two
// devices stay file-compatible.

#ifndef CR_SETTINGS_H
#define CR_SETTINGS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "cr_session.h"
#include "cr_time.h"

typedef enum { CR_PITCH_LOW, CR_PITCH_MEDIUM, CR_PITCH_HIGH } cr_metronome_pitch_t;

/// G4 / C5 / G5 — musical on purpose, so a tick reads as an instrument
/// rather than an alarm.
double cr_metronome_pitch_hz(cr_metronome_pitch_t pitch);

/// Distinct rhythms are how cues stay tellable-apart without looking.
typedef enum {
    CR_CUE_SINGLE,
    CR_CUE_DOUBLE,
    CR_CUE_TRIPLE,
    CR_CUE_LONG,
} cr_cue_pattern_t;

typedef struct {
    bool cues_enabled;              // "hapticsEnabled" on the watch
    bool metronome_sound_on;        // OFF by default, as on the watch: opt-in
    int32_t metronome_bpm;
    cr_metronome_pitch_t metronome_pitch;
    bool keep_screen_on;
    bool menu_tap_only;             // tap to open and tap to select; no hold-and-slide
    cr_ms_t cycle_override_ms;      // CR_TIME_NONE = the protocol default (120 s)
    cr_ms_t interval_override_ms;   // CR_TIME_NONE = the protocol default (180 s)
    char default_drug_set_id[CR_ID_MAX];   // "" = none
    cr_cue_pattern_t pulse_check_due;
    cr_cue_pattern_t med_due;
    cr_cue_pattern_t cycle_complete;
} cr_settings_t;

cr_settings_t cr_settings_default(void);
bool cr_settings_equal(const cr_settings_t *a, const cr_settings_t *b);

/// snprintf semantics: returns the length the JSON needs, which is >= cap
/// when it was truncated. The buffer is always NUL-terminated.
size_t cr_settings_to_json(const cr_settings_t *s, char *buf, size_t cap);

/// Missing keys take their defaults. Returns false and writes defaults when
/// the JSON is malformed or a known key has the wrong type — same outcome
/// as the Swift decoder throwing.
bool cr_settings_from_json(const char *json, cr_settings_t *out);

#endif
