// cr_audio.h — the speaker, and the only thing that makes noise.
//
// This board has no vibration motor (the I2C scan found nothing at 0x5A; the
// tick felt on a tap is the panel). So every cue the watch delivers to the
// wrist has to arrive through the ES8311 at 0x18 instead, which is what M4 is
// about.
//
// Sound is produced on its OWN task, fed by a queue. Writing to the codec
// blocks for as long as the sound lasts, and the caller is almost always the
// LVGL task — a blocking write there stutters the screen during compressions,
// which is the last moment to be dropping frames.

#pragma once

#include <stdbool.h>

#include "cr_settings.h"
#include "esp_err.h"

/// Brings up I2S and the codec. Safe to call once, after the display and the
/// I2C bus. A failure is not fatal: the timer still runs, it just cannot make
/// a sound, and the UI says so rather than pretending.
esp_err_t cr_audio_init(void);

bool cr_audio_ready(void);

/// Queues one tone. Returns immediately. `hz` is the pitch, `ms` the length;
/// a dropped queue entry is silently ignored, because a missed tick is better
/// than a stalled UI.
void cr_audio_tone(double hz, int ms);

/// Plays one of the four cue rhythms at `hz`. The rhythms exist so three
/// different alerts can be told apart without looking — which is the whole
/// job, on a device worn by someone whose eyes are on a patient.
void cr_audio_cue(cr_cue_pattern_t pattern, double hz);

/// Master mute, honoured by everything above. The BSP has no audio deinit, so
/// this stops the board EMITTING rather than releasing the peripheral.
void cr_audio_set_muted(bool muted);
bool cr_audio_muted(void);
