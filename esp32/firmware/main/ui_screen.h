// ui_screen.h — the live session screen and its fans.
//
// Draws Sebastian's hand-placed layout (cr_layout) and nothing else: every
// position comes from the table, so "measure, don't eyeball" stays possible
// — ui_probe dumps what actually landed and it can be diffed against the
// same numbers the tests check.

#pragma once

#include "cr_engine.h"
#include "cr_settings.h"

#include "lvgl.h"

/// `clock` is the only source of time; the engine still reads none itself.
void ui_create(cr_engine_t *engine, cr_ms_t (*clock)(void));

/// The live session's screen, so the setup flow can hand over to it.
lv_obj_t *ui_live_screen(void);

/// Repaints from engine state, and drives the beat and the cues off the same
/// `now`. Rendering decides nothing; cr_cues decides when a sound happens.
void ui_tick(void);

/// The live settings, handed over whenever they change.
void ui_settings_changed(const cr_settings_t *settings);

/// A new code: forget what was already announced, so the first cycle of this
/// one is not silenced by the last one's.
void ui_code_started(void);
