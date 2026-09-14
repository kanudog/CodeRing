#include "cr_layout.h"

#include <math.h>
#include <string.h>

const cr_fan_t *cr_fan_find(const char *key, size_t count)
{
    if (key == NULL) return NULL;
    for (size_t i = 0; i < cr_fan_count; i++) {
        if (strcmp(cr_fans[i].key, key) != 0) continue;
        const cr_fan_t *fan = &cr_fans[i];
        size_t have = fan->placed ? fan->slot_count : fan->seed_count;
        // Count-exact on purpose: the defib ladder and the events fan are
        // built at runtime, and stretching a 6-slot placement over 7 items
        // would drop the last one somewhere undefined.
        return have == count ? fan : NULL;
    }
    return NULL;
}

uint8_t cr_arc_top_row_count(uint8_t count)
{
    if (count <= cr_arc.max_per_row) return count;
    return (uint8_t)((count + 1) / 2);   // ceil(count / 2) — 6 → 3+3, 5 → 3+2
}

/// One row of bubbles: fixed pitch, centred — NOT stretched to the full
/// width, so a 2-item fan and a 4-item fan share the same slot spacing and
/// muscle memory survives across fans.
static size_t arc_row(uint8_t n, float row_y, cr_pt_t *out, size_t cap, size_t written)
{
    if (n == 0) return written;
    const float width = cr_screen.fan_width;
    const float center_x = cr_screen.fan_origin.x + width / 2.0f;
    float half_span = width / 2.0f - cr_arc.side_inset;
    if (half_span < 1.0f) half_span = 1.0f;

    float pitch = cr_arc.slot_pitch;
    if (n > 1) {
        const float fit = (width - 2.0f * cr_arc.side_inset) / (float)(n - 1);
        if (fit < pitch) pitch = fit;
    }
    const float start_x = center_x - pitch * (float)(n - 1) / 2.0f;

    for (uint8_t i = 0; i < n && written < cap; i++) {
        const float x = start_x + pitch * (float)i;
        const float t = (x - center_x) / half_span;      // −1…1 across the row
        out[written].x = x;
        out[written].y = row_y + cr_arc.arc_drop * t * t;  // the slight curve
        written++;
    }
    return written;
}

size_t cr_arc_positions(uint8_t count, cr_pt_t *out, size_t cap)
{
    if (count == 0 || out == NULL) return 0;
    const uint8_t top = cr_arc_top_row_count(count);
    size_t written = arc_row(top, cr_arc.apex_y, out, cap, 0);
    return arc_row((uint8_t)(count - top), cr_arc.apex_y + cr_arc.row_gap, out, cap, written);
}

cr_pt_t cr_arc_label_position(cr_pt_t bubble, float diameter, float label_height)
{
    // Measured from the bubble's EDGE, not its centre: the gap is the
    // visible whitespace, which is what should stay constant if a button
    // ever changes size.
    cr_pt_t p = { bubble.x, bubble.y + diameter / 2.0f + cr_arc.label_gap + label_height / 2.0f };
    return p;
}

static float clampf(float v, float lo, float hi)
{
    return v < lo ? lo : (v > hi ? hi : v);
}

cr_pt_t cr_clamp_bubble(cr_pt_t p)
{
    const float inset = 18.0f * CR_LAYOUT_SCALE;
    const float top = 16.0f * CR_LAYOUT_SCALE;
    cr_pt_t out = {
        clampf(p.x, cr_screen.fan_origin.x + inset,
               cr_screen.fan_origin.x + cr_screen.fan_width - inset),
        clampf(p.y, cr_screen.fan_origin.y + top,
               cr_screen.fan_origin.y + cr_screen.fan_height - top),
    };
    return out;
}

cr_pt_t cr_clamp_label(cr_pt_t p)
{
    // Narrower than the bubble clamp, because a label is wider than the
    // bubble it belongs to.
    const float inset = 32.0f * CR_LAYOUT_SCALE;
    cr_pt_t out = {
        clampf(p.x, cr_screen.fan_origin.x + inset,
               cr_screen.fan_origin.x + cr_screen.fan_width - inset),
        p.y < cr_screen.fan_origin.y + 10.0f * CR_LAYOUT_SCALE
            ? cr_screen.fan_origin.y + 10.0f * CR_LAYOUT_SCALE
            : p.y,
    };
    return out;
}

size_t cr_fan_slots(const char *key, uint8_t count, cr_slot_t *out, size_t cap)
{
    if (out == NULL || cap == 0) return 0;

    // Hand-placed geometry first; otherwise every fan falls back to the SAME
    // computed arrangement — fixed rows near the top that the wearer can
    // learn, clear of the lower-right quadrant their own finger covers.
    const cr_fan_t *fan = cr_fan_find(key, count);
    if (fan != NULL && fan->placed && fan->slots != NULL) {
        size_t n = fan->slot_count < cap ? fan->slot_count : cap;
        memcpy(out, fan->slots, n * sizeof(cr_slot_t));
        return n;
    }

    cr_pt_t points[CR_MAX_SLOTS];
    size_t n = cr_arc_positions(count, points, CR_MAX_SLOTS);
    if (n > cap) n = cap;
    for (size_t i = 0; i < n; i++) {
        const cr_pt_t bubble = cr_clamp_bubble(points[i]);
        out[i].center = bubble;
        out[i].diameter = cr_arc.bubble_diameter;
        out[i].glyph = cr_arc.glyph;
        out[i].label = cr_clamp_label(
            cr_arc_label_position(bubble, cr_arc.bubble_diameter, cr_arc.label_box_height));
        out[i].label_font = cr_arc.label_font;
        out[i].label_width = cr_arc.label_width;
        out[i].z = (int)i;
    }
    return n;
}
