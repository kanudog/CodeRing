// cr_fonts.h — Montserrat with the characters this app actually prints.
//
// LVGL's built-in fonts are ASCII-only, so "Hands off — checking pulse"
// came out with a box where the dash belongs. Regenerate with
// tools/make_fonts.sh after adding any new character to a visible string.

#pragma once

#include "lvgl.h"

LV_FONT_DECLARE(cr_font_16);   // fine print
LV_FONT_DECLARE(cr_font_28);   // body text and labels
LV_FONT_DECLARE(cr_font_48);   // the big timer numerals
