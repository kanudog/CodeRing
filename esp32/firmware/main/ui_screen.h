// ui_screen.h — the live session screen and its fans.
//
// Draws Sebastian's hand-placed layout (cr_layout) and nothing else: every
// position comes from the table, so "measure, don't eyeball" stays possible
// — ui_probe dumps what actually landed and it can be diffed against the
// same numbers the tests check.

#pragma once

#include "cr_engine.h"

#include "lvgl.h"

/// `clock` is the only source of time; the engine still reads none itself.
void ui_create(cr_engine_t *engine, cr_ms_t (*clock)(void));

/// The live session's screen, so the setup flow can hand over to it.
lv_obj_t *ui_live_screen(void);

/// Repaints from engine state. Pure rendering — it decides nothing.
void ui_tick(void);
