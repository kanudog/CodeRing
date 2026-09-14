// ui_flow.h — home and setup, the screens that come before a code.

#pragma once

#include "cr_engine.h"

/// Builds the home and setup screens. The engine is NOT started here: the
/// code clock begins when START CODE is tapped, not at boot.
void ui_flow_create(cr_engine_t *engine, cr_ms_t (*clock)(void));

void ui_flow_show_home(void);
