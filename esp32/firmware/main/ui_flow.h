// ui_flow.h — the screens around a code: home and setup before it, the
// debrief after it. Home → Setup → Live → Summary → Home, which is the flow
// WatchRootView owns on the watch.

#pragma once

#include "cr_engine.h"

/// Builds the home, setup and summary screens. The engine is NOT started
/// here: the code clock begins when START CODE is tapped, not at boot.
void ui_flow_create(cr_engine_t *engine, cr_ms_t (*clock)(void));

void ui_flow_show_home(void);

/// The debrief, after the live screen has ended the code. Terminal on
/// purpose: there is no way back into a finished code, only DONE → home,
/// where START CODE begins a new one.
void ui_flow_show_summary(void);
