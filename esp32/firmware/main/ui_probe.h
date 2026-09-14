// ui_probe.h — measure, don't eyeball.
//
// The watch build was verified by dumping real frame coordinates from the
// running app and diffing them against the layout table; a 3 pt shift is
// invisible in a screenshot. This is the equivalent for LVGL: it prints
// where every object ACTUALLY landed, and where the panel reports each
// touch. M3's hand-placed layout gets checked against these numbers rather
// than against how it looks in a photo.

#pragma once

#include "lvgl.h"

/// Tags an object so the dump can name it. The string must outlive the
/// object (a literal).
void cr_probe_name(lv_obj_t *obj, const char *name);

/// Records where the layout table says this object's CENTRE should be. The
/// dump then prints the difference between intent and reality and flags
/// anything that drifted, so the layout is checked by measurement rather
/// than by looking at a photo — a 3 pt shift is invisible in a screenshot.
void cr_probe_expect(lv_obj_t *obj, float x, float y);

/// Prints the object tree with absolute screen coordinates, plus the
/// display resolution it was measured against. Returns the number of
/// controls that landed more than a pixel from where the table put them.
int cr_probe_dump(lv_obj_t *root, const char *title);

/// Logs every touch press and release with its coordinates, so touch and
/// display can be proven to share one coordinate space — the trap the
/// CO5300's 22-column panel gap sets.
void cr_probe_watch_touches(lv_indev_t *indev);
