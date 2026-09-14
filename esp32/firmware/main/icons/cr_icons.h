// cr_icons.h — the icon set, redrawn.
//
// SF Symbols are Apple's and do not exist here, so Tools/LayoutBench holds a
// 24×24 SVG redraw of every icon the watch uses, and tools/make_icons.sh
// turns those into LVGL A8 images — alpha masks that LVGL tints at runtime,
// so one file serves every colour a fan needs.
//
// Look icons up by their SF Symbol NAME ("syringe.fill"), exactly as the
// drug and event data spells them, so the data stays portable between the
// watch, the phone and this board.

#pragma once

#include <stddef.h>

#include "lvgl.h"

/// NULL when the name is unknown. make_icons.sh fails the build if any
/// symbol in cr_defaults.c has no icon, so this should not happen.
const lv_image_dsc_t *cr_icon(const char *symbol);

size_t cr_icon_count(void);
