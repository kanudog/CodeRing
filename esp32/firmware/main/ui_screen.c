#include "ui_screen.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

#include "esp_log.h"
#include "lvgl.h"

#include "cr_defaults.h"
#include "cr_layout.h"
#include "cr_menu.h"
#include "cr_text.h"
#include "cr_theme.h"
#include "fonts/cr_fonts.h"
#include "icons/cr_icons.h"
#include "ui_flow.h"
#include "ui_probe.h"

static const char *TAG = "ui";

/// The three generated font sizes, as pixel heights, so `font_for` picks the
/// one that was asked for.
static const float cr_font_16_px = 16.0f;

#define MAX_DEPTH 3

/// Stamped in by the build (firmware/main/CMakeLists.txt). Zero when it is
/// not, which shows a clock counting from midnight rather than a wrong one.
#ifndef CR_BUILD_LOCAL_EPOCH
#define CR_BUILD_LOCAL_EPOCH 0
#endif

/// The bottom of this panel is not fully visible the way the watch face was
/// — the anchor pucks and the clock row sat slightly cut off. Everything in
/// the bottom band is lifted by this much. A device quirk, not a layout
/// change: the table still holds Sebastian's coordinates.
#define BOTTOM_LIFT 12.0f

/// The panel is a ROUNDED rectangle, so the four corners are not there to
/// draw in. Anything whose box would poke past the arc is nudged back along
/// the diagonal. Tune this if a corner control still clips: it is the one
/// number that decides how much of each corner is unusable.
#define CORNER_RADIUS 110.0f

static cr_pt_t corner_safe(cr_pt_t c, float w, float h)
{
    const float hw = w / 2 + 2, hh = h / 2 + 2;     // +2 so it never kisses the edge
    const float cx = (c.x < cr_screen.width / 2) ? CORNER_RADIUS
                                                 : cr_screen.width - CORNER_RADIUS;
    const float cy = (c.y < cr_screen.height / 2) ? CORNER_RADIUS
                                                  : cr_screen.height - CORNER_RADIUS;
    // Only the corner quadrants are curved; the straight edges are fine.
    const bool in_corner_x = c.x < CORNER_RADIUS || c.x > cr_screen.width - CORNER_RADIUS;
    const bool in_corner_y = c.y < CORNER_RADIUS || c.y > cr_screen.height - CORNER_RADIUS;
    if (!in_corner_x || !in_corner_y) return c;

    // The far corner of the control's box is what actually touches the arc.
    const float dx = c.x - cx, dy = c.y - cy;
    const float reach = sqrtf(hw * hw + hh * hh);
    const float d = sqrtf(dx * dx + dy * dy);
    const float max = CORNER_RADIUS - reach;
    if (d <= max || d == 0) return c;
    cr_pt_t out = { cx + dx * max / d, cy + dy * max / d };
    return out;
}

static cr_pt_t lifted(cr_pt_t p)
{
    cr_pt_t out = { p.x, p.y - BOTTOM_LIFT };
    return out;
}

/// Labels are centred on a point, but their width changes with their text
/// ("0:59" → "-10:05"), so the centre has to be re-applied, not just set once.
#define MAX_CENTRED 40
static struct { lv_obj_t *obj; cr_pt_t center; } centred[MAX_CENTRED];
static size_t centred_count;

static cr_engine_t *engine;
static cr_ms_t (*clock_ms)(void);

static struct {
    lv_obj_t *root;
    lv_obj_t *cpr_ring, *drug_ring;
    lv_obj_t *countdown, *cycle_chip, *drug_line;
    lv_obj_t *code_clock, *total_label, *patient, *toast;
    lv_obj_t *start_text, *paused_text;
    lv_obj_t *pause_button;
    lv_obj_t *wall_clock;
    lv_obj_t *pulse_button;
    lv_obj_t *check_title, *check_clock, *check_hint, *check_resume, *check_found;
    // Post-ROSC. Shared chrome — header, patient strip, clocks, pucks, chips —
    // is drawn by the same code at the same coordinates, so nothing shifts
    // when the outcome changes; only the centre stack differs, plus the two
    // capsules down the right edge.
    lv_obj_t *vitals_ring;
    lv_obj_t *vitals_label, *vitals_count, *rosc_elapsed, *vitals_prompt;
    lv_obj_t *rosc_heart;
    lv_obj_t *re_arrest, *handoff;
    lv_obj_t *pucks[4];
    struct { lv_obj_t *root, *name, *clock; } chips[6];
} live;

/// The end-of-code confirmation. Hidden until the flag is tapped.
static struct {
    lv_obj_t *root;
} confirm;

static struct {
    lv_obj_t *root;            // the whole overlay, hidden when closed
    lv_obj_t *scrim;
    lv_obj_t *title_chip;
    lv_obj_t *back_pad;
    lv_obj_t *slots[CR_MAX_SLOTS];
    lv_obj_t *labels[CR_MAX_SLOTS];
    cr_menu_item_t items[CR_MAX_SLOTS];
    size_t item_count;
    const char *stack[MAX_DEPTH];   // fan keys, root first
    size_t depth;
    bool open;
} fan;

// MARK: - Placement helpers (the table holds CENTRES; LVGL wants top-left)

static void place(lv_obj_t *obj, cr_pt_t center, float w, float h)
{
    lv_obj_set_size(obj, (int32_t)(w + 0.5f), (int32_t)(h + 0.5f));
    lv_obj_set_pos(obj, (int32_t)(center.x - w / 2 + 0.5f), (int32_t)(center.y - h / 2 + 0.5f));
    // Record the intent so the probe can prove what actually landed.
    cr_probe_expect(obj, center.x, center.y);
}

static void place_disc(lv_obj_t *obj, const cr_disc_t *disc)
{
    place(obj, corner_safe(disc->center, disc->diameter, disc->diameter),
          disc->diameter, disc->diameter);
}

/// Sizes a label to its own text and centres it on `center`, keeping it
/// clear of the rounded corners. The table's boxes are watchOS point sizes;
/// the nearest rasterised font is often taller, which silently clipped
/// "TOTAL" and pushed a negative countdown onto two lines.
static void recentre(lv_obj_t *obj, cr_pt_t center);

static void place_label(lv_obj_t *obj, cr_pt_t center)
{
    if (centred_count < MAX_CENTRED) {
        centred[centred_count].obj = obj;
        centred[centred_count].center = center;
        centred_count++;
    }
    lv_label_set_long_mode(obj, LV_LABEL_LONG_CLIP);
    lv_obj_set_size(obj, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_update_layout(obj);
    const float w = (float)lv_obj_get_width(obj);
    const float h = (float)lv_obj_get_height(obj);
    const cr_pt_t safe = corner_safe(center, w, h);
    lv_obj_set_pos(obj, (int32_t)(safe.x - w / 2 + 0.5f), (int32_t)(safe.y - h / 2 + 0.5f));
    cr_probe_expect(obj, safe.x, safe.y);
}

static void recentre(lv_obj_t *obj, cr_pt_t center)
{
    lv_obj_update_layout(obj);
    const float w = (float)lv_obj_get_width(obj);
    const float h = (float)lv_obj_get_height(obj);
    const cr_pt_t safe = corner_safe(center, w, h);
    lv_obj_set_pos(obj, (int32_t)(safe.x - w / 2 + 0.5f), (int32_t)(safe.y - h / 2 + 0.5f));
}

static void recentre_all(void)
{
    for (size_t i = 0; i < centred_count; i++) recentre(centred[i].obj, centred[i].center);
}

static void place_text(lv_obj_t *obj, const cr_text_t *text)
{
    lv_obj_set_style_text_align(obj, LV_TEXT_ALIGN_CENTER, 0);
    place_label(obj, text->center);
}

/// Picks the nearest generated font. The layout carries exact point sizes;
/// three rasterised sizes cover them without shipping a font per label.
static const lv_font_t *font_for(float px)
{
    if (px >= 38) return &cr_font_48;
    if (px >= 22) return &cr_font_28;
    return &cr_font_16;
}

static lv_obj_t *make_label(lv_obj_t *parent, const char *text, uint32_t color, float font_px)
{
    lv_obj_t *label = lv_label_create(parent);
    lv_label_set_text(label, text);
    lv_obj_set_style_text_color(label, lv_color_hex(color), 0);
    lv_obj_set_style_text_font(label, font_for(font_px), 0);
    lv_obj_set_style_text_align(label, LV_TEXT_ALIGN_CENTER, 0);
    return label;
}

static lv_obj_t *make_icon(lv_obj_t *parent, const char *symbol, uint32_t color, float size)
{
    const lv_image_dsc_t *dsc = cr_icon(symbol);
    if (dsc == NULL) {
        ESP_LOGW(TAG, "no icon for '%s'", symbol);
        return NULL;
    }
    lv_obj_t *image = lv_image_create(parent);
    lv_image_set_src(image, dsc);
    lv_obj_set_style_image_recolor(image, lv_color_hex(color), 0);
    lv_obj_set_style_image_recolor_opa(image, LV_OPA_COVER, 0);
    // The icons are rasterised at 52 px, which is the fan-bubble glyph size;
    // anything else scales from that.
    if (size < 51.0f || size > 53.0f) {
        lv_image_set_scale(image, (int32_t)(size / 52.0f * 256.0f));
    }
    lv_obj_center(image);
    return image;
}

/// A round control with a centred glyph — pucks, pads, header buttons.
static lv_obj_t *make_disc(lv_obj_t *parent, const cr_disc_t *disc, const char *symbol,
                           uint32_t fill, uint32_t tint, lv_event_cb_t handler, void *user_data,
                           const char *probe_name)
{
    lv_obj_t *button = lv_button_create(parent);
    place_disc(button, disc);
    lv_obj_set_style_radius(button, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_bg_color(button, lv_color_hex(fill), 0);
    lv_obj_set_style_shadow_width(button, 0, 0);
    lv_obj_set_style_border_width(button, 0, 0);
    if (handler != NULL) lv_obj_add_event_cb(button, handler, LV_EVENT_CLICKED, user_data);
    cr_probe_name(button, probe_name);
    make_icon(button, symbol, tint, disc->glyph);
    return button;
}

/// A progress ring. All three (CPR cycle, drug interval, post-ROSC vitals)
/// are the same widget with a different hue, so they are built here rather
/// than three times: the arc straddles its path, so the object has to be
/// grown by one stroke width or the ring is clipped by its own box.
static lv_obj_t *make_ring(lv_obj_t *parent, const cr_ring_t *ring, uint32_t color,
                           const char *probe_name)
{
    lv_obj_t *arc = lv_arc_create(parent);
    place(arc, ring->center, ring->diameter + ring->stroke, ring->diameter + ring->stroke);
    lv_arc_set_rotation(arc, 270);
    lv_arc_set_bg_angles(arc, 0, 360);
    lv_arc_set_range(arc, 0, 1000);
    lv_obj_remove_style(arc, NULL, LV_PART_KNOB);
    lv_obj_remove_flag(arc, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_style_arc_width(arc, (int32_t)ring->stroke, 0);
    lv_obj_set_style_arc_width(arc, (int32_t)ring->stroke, LV_PART_INDICATOR);
    lv_obj_set_style_arc_color(arc, lv_color_hex(CR_THEME_RING_TRACK), 0);
    lv_obj_set_style_arc_color(arc, lv_color_hex(color), LV_PART_INDICATOR);
    cr_probe_name(arc, probe_name);
    return arc;
}

/// A pill-shaped control placed by its centre, like make_disc — the watch's
/// `capsuleButton`. RE-ARREST and HANDOFF are the only two.
static lv_obj_t *make_capsule(lv_obj_t *parent, const cr_text_t *spec, const char *title,
                              uint32_t fill, uint32_t tint, lv_event_cb_t handler,
                              const char *probe_name)
{
    lv_obj_t *button = lv_button_create(parent);
    place(button, corner_safe(spec->center, spec->w, spec->h), spec->w, spec->h);
    lv_obj_set_style_radius(button, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_bg_color(button, lv_color_hex(fill), 0);
    lv_obj_set_style_shadow_width(button, 0, 0);
    lv_obj_set_style_border_width(button, 0, 0);
    lv_obj_set_style_pad_all(button, 0, 0);
    if (handler != NULL) lv_obj_add_event_cb(button, handler, LV_EVENT_CLICKED, NULL);
    cr_probe_name(button, probe_name);
    lv_obj_center(make_label(button, title, tint, spec->font));
    return button;
}

// MARK: - Toast
//
// The only confirmation this board can give: no motor to tap the wrist, so
// every action says what it did — and every refusal says it did nothing.

static void toast_hide_cb(lv_timer_t *timer)
{
    lv_obj_add_flag(live.toast, LV_OBJ_FLAG_HIDDEN);
    lv_timer_delete(timer);
}

static void toast(const char *text, uint32_t color)
{
    lv_label_set_text(live.toast, text);
    lv_obj_set_style_text_color(live.toast, lv_color_hex(color), 0);

    // A snug pill for a short line, wrapped inside the table's box for a long
    // one. The watch shrinks text to fit that box (minimumScaleFactor); LVGL
    // cannot, and unbounded the longest string this screen shows — a refusal —
    // sized itself to 613 px on a 410 px panel and hung 100 px off BOTH edges.
    // ui_probe caught it; a photo would not have.
    lv_label_set_long_mode(live.toast, LV_LABEL_LONG_CLIP);
    lv_obj_set_width(live.toast, LV_SIZE_CONTENT);
    lv_obj_update_layout(live.toast);
    if (lv_obj_get_width(live.toast) > (int32_t)cr_screen.toast.w) {
        lv_label_set_long_mode(live.toast, LV_LABEL_LONG_WRAP);
        lv_obj_set_width(live.toast, (int32_t)cr_screen.toast.w);
    }
    recentre(live.toast, cr_screen.toast.center);

    lv_obj_remove_flag(live.toast, LV_OBJ_FLAG_HIDDEN);
    lv_obj_move_foreground(live.toast);
    lv_timer_t *timer = lv_timer_create(toast_hide_cb, 2000, NULL);   // 2 s, as on the watch
    lv_timer_set_repeat_count(timer, 1);
}

static void report(bool changed, const char *what)
{
    if (!changed) {
        char line[96];
        snprintf(line, sizeof line, "NOTHING LOGGED — %s", what);
        toast(line, CR_THEME_MED);
        return;
    }
    const cr_session_t *s = &engine->session;
    if (s->event_count == 0) { toast(what, CR_THEME_ROSC); return; }
    const cr_event_t *last = &s->events[s->event_count - 1];
    char line[CR_TITLE_MAX + CR_DETAIL_MAX + 8];
    snprintf(line, sizeof line, "%s%s%s", last->title, last->detail[0] ? " — " : "", last->detail);
    toast(line, cr_event_tint(last));
}

// MARK: - Fans

static void fan_close(void)
{
    fan.open = false;
    fan.depth = 0;
    lv_obj_add_flag(fan.root, LV_OBJ_FLAG_HIDDEN);
}

static void fan_build(const char *key);

static void on_slot(lv_event_t *event)
{
    size_t index = (size_t)(uintptr_t)lv_event_get_user_data(event);
    if (index >= fan.item_count) return;
    const cr_menu_item_t *item = &fan.items[index];

    if (item->is_group) {
        if (fan.depth < MAX_DEPTH) fan.stack[fan.depth++] = item->child_key;
        fan_build(item->child_key);
        return;
    }
    // Only a leaf fires. Everything else has to say so out loud.
    report(cr_menu_select(engine, item, clock_ms()), item->title);
    fan_close();
}

static void on_cancel(lv_event_t *event)
{
    (void)event;
    fan_close();
}

static void on_back(lv_event_t *event)
{
    (void)event;
    if (fan.depth > 1) {
        fan.depth--;
        fan_build(fan.stack[fan.depth - 1]);
    } else {
        fan_close();
    }
}

/// Lays out one level: stored placement when the table has one for this
/// exact count, otherwise the computed arc.
static void fan_build(const char *key)
{
    fan.item_count = cr_menu_items(engine, key, fan.items, CR_MAX_SLOTS);

    cr_slot_t slots[CR_MAX_SLOTS];
    size_t n = cr_fan_slots(key, (uint8_t)fan.item_count, slots, CR_MAX_SLOTS);

    const cr_fan_t *table = cr_fan_find(key, fan.item_count);
    if (table != NULL && table->readout.present) {
        lv_label_set_text(fan.title_chip, table->title);
        lv_obj_remove_flag(fan.title_chip, LV_OBJ_FLAG_HIDDEN);
        place(fan.title_chip, table->readout.center, 260, table->readout.font * 1.6f);
    } else {
        lv_obj_add_flag(fan.title_chip, LV_OBJ_FLAG_HIDDEN);
    }

    for (size_t i = 0; i < CR_MAX_SLOTS; i++) {
        if (i >= n) {
            lv_obj_add_flag(fan.slots[i], LV_OBJ_FLAG_HIDDEN);
            lv_obj_add_flag(fan.labels[i], LV_OBJ_FLAG_HIDDEN);
            continue;
        }
        const cr_menu_item_t *item = &fan.items[i];
        lv_obj_t *button = fan.slots[i];
        lv_obj_remove_flag(button, LV_OBJ_FLAG_HIDDEN);
        place_disc(button, &(cr_disc_t){ slots[i].center, slots[i].diameter, slots[i].glyph });
        lv_obj_set_style_bg_color(button, lv_color_hex(CR_THEME_SURFACE), 0);
        lv_obj_set_style_border_color(button, lv_color_hex(item->color), 0);

        lv_obj_clean(button);
        uint32_t tint = item->icon_color == CR_COLOR_NONE ? item->color : item->icon_color;
        make_icon(button, item->symbol, tint, slots[i].glyph);

        lv_obj_t *label = fan.labels[i];
        lv_obj_remove_flag(label, LV_OBJ_FLAG_HIDDEN);
        lv_label_set_text(label, item->title);
        lv_obj_set_style_text_color(label, lv_color_hex(CR_THEME_TEXT), 0);
        lv_obj_set_style_text_font(label, font_for(slots[i].label_font), 0);
        lv_obj_set_width(label, (int32_t)slots[i].label_width);
        place(label, slots[i].label, slots[i].label_width, cr_arc.label_box_height * 2);
    }

    // Back exists only below the root — exiting is one learned reach either way.
    if (fan.depth > 1) lv_obj_remove_flag(fan.back_pad, LV_OBJ_FLAG_HIDDEN);
    else lv_obj_add_flag(fan.back_pad, LV_OBJ_FLAG_HIDDEN);

    fan.open = true;
    lv_obj_remove_flag(fan.root, LV_OBJ_FLAG_HIDDEN);
    lv_obj_move_foreground(fan.root);
}

static void on_puck(lv_event_t *event)
{
    const char *anchor = lv_event_get_user_data(event);
    const char *key = cr_menu_key(engine, anchor);
    fan.depth = 1;
    fan.stack[0] = key;
    fan_build(key);
}

// MARK: - Log and timers sheets
//
// The log button shows the EVENT HISTORY (it used to undo, which is a
// different thing entirely); undo lives inside it, where you can see what
// you are about to remove.

/// HANDOFF is the watch's phone-call card: the same read-only list shape as
/// the log and the timers, which is why it rides the same overlay rather than
/// being a screen of its own. (The debrief after End is a screen — it is
/// terminal, and it belongs to the flow.)
typedef enum { SHEET_LOG, SHEET_TIMERS, SHEET_HANDOFF } sheet_mode_t;

static struct {
    lv_obj_t *root, *title, *list, *undo_button, *undo_label;
    sheet_mode_t mode;
    bool open;
} sheet;

/// One labelled value: a colour bar, the label above, the value below. The
/// watch's `row` in HandoffView.
static lv_obj_t *sheet_row(lv_obj_t *parent, const char *label, const char *value,
                           uint32_t color);

/// The wall clock, the same way the live screen derives it: stamped at build
/// time and advanced by the monotonic clock. M5's RTC makes it survive a
/// reboot; until then a reflash is what sets it.
static void wall_clock_text(char *buf, size_t cap, cr_ms_t now)
{
    const int64_t wall = (int64_t)CR_BUILD_LOCAL_EPOCH + now / 1000;
    snprintf(buf, cap, "%d:%02d:%02d", (int)((wall / 3600) % 24),
             (int)((wall / 60) % 60), (int)(wall % 60));
}

/// The handoff card: everything PICU or transport asks for on the phone, in
/// the watch's order, readable line by line while the code is still live.
static void handoff_refresh(cr_ms_t now)
{
    const cr_session_t *s = &engine->session;
    cr_stats_t stats;
    cr_session_stats(s, now, &stats);
    char line[96], clock[16];

    snprintf(line, sizeof line, "%.1f kg · %s", s->patient.weight_kg,
             engine->protocol.short_name);
    sheet_row(sheet.list, "PATIENT", line, CR_THEME_CPR);

    if (stats.has_rosc) {
        cr_format_clock(clock, sizeof clock, CR_SEC(stats.seconds_to_rosc));
        sheet_row(sheet.list, "ARREST DURATION", clock, CR_THEME_MED);
    }

    cr_format_clock(clock, sizeof clock, cr_engine_elapsed(engine, now));
    sheet_row(sheet.list, "TOTAL CODE", clock, CR_THEME_CPR);

    // "×2 — last 1:40 ago". Found by NAME, as on the watch, so a custom
    // adrenaline entry counts the same way the stats tally counts it.
    const cr_event_t *last_epi = cr_session_last_med_named(s, "epi");
    if (stats.epi_count > 0 && last_epi != NULL) {
        cr_format_clock(clock, sizeof clock, now - last_epi->date);
        snprintf(line, sizeof line, "×%d — last %s ago", (int)stats.epi_count, clock);
    } else {
        snprintf(line, sizeof line, "×0");
    }
    sheet_row(sheet.list, "EPI", line, CR_THEME_MED);

    snprintf(line, sizeof line, "×%d", (int)stats.shock_count);
    sheet_row(sheet.list, "SHOCKS", line, CR_THEME_SHOCK);

    if (s->rosc != CR_TIME_NONE) {
        wall_clock_text(clock, sizeof clock, s->rosc);
        sheet_row(sheet.list, "ROSC AT", clock, CR_THEME_ROSC);
    }
    if (engine->rosc_achieved) {
        cr_format_clock(clock, sizeof clock, cr_engine_rosc_elapsed(engine, now));
        sheet_row(sheet.list, "POST-ROSC", clock, CR_THEME_ROSC);
    }

    // Every line of access, because the first question on the phone is what
    // the drugs are going through.
    for (uint16_t i = 0; i < s->event_count; i++) {
        const cr_event_t *ev = &s->events[i];
        if (ev->category != CR_CAT_ACCESS) continue;
        sheet_row(sheet.list, "ACCESS", ev->detail[0] ? ev->detail : ev->title,
                  cr_event_tint(ev));
    }
}

static void sheet_refresh(void)
{
    lv_obj_clean(sheet.list);
    char line[CR_TITLE_MAX + CR_DETAIL_MAX + 24];

    if (sheet.mode == SHEET_HANDOFF) {
        lv_label_set_text(sheet.title, "HANDOFF");
        handoff_refresh(clock_ms());
        return;
    }

    if (sheet.mode == SHEET_LOG) {
        lv_label_set_text_fmt(sheet.title, "LOG · %d", (int)engine->session.event_count);
        // Newest first: mid-code you are checking what just happened.
        for (int i = (int)engine->session.event_count - 1; i >= 0; i--) {
            const cr_event_t *ev = &engine->session.events[i];
            char stamp[16];
            cr_format_offset(stamp, sizeof stamp, ev->offset_s);
            snprintf(line, sizeof line, "%s  %s%s%s", stamp, ev->title,
                     ev->detail[0] ? " — " : "", ev->detail);
            lv_obj_t *row = make_label(sheet.list, line, cr_event_tint(ev), cr_font_16_px);
            lv_obj_set_width(row, (int32_t)(cr_screen.width - 80));
            lv_label_set_long_mode(row, LV_LABEL_LONG_WRAP);
            lv_obj_set_style_text_align(row, LV_TEXT_ALIGN_LEFT, 0);
        }
        const cr_event_t *next = cr_engine_last_undoable(engine);
        lv_label_set_text_fmt(sheet.undo_label, "UNDO %s", next ? next->title : "—");
        return;
    }

    cr_running_timer_t timers[CR_MAX_RUNNING_TIMERS];
    size_t n = cr_session_running_timers(&engine->session, timers, CR_MAX_RUNNING_TIMERS);
    lv_label_set_text(sheet.title, "TIME SINCE LAST");
    for (size_t i = 0; i < n; i++) {
        char elapsed[16];
        cr_format_clock(elapsed, sizeof elapsed, cr_running_timer_elapsed(&timers[i], clock_ms()));
        snprintf(line, sizeof line, "%-18s %s", timers[i].title, elapsed);
        lv_obj_t *row = make_label(sheet.list, line, timers[i].color, cr_font_16_px);
        lv_obj_set_width(row, (int32_t)(cr_screen.width - 80));
        lv_obj_set_style_text_align(row, LV_TEXT_ALIGN_LEFT, 0);
    }
}

static void sheet_close(lv_event_t *event)
{
    (void)event;
    sheet.open = false;
    lv_obj_add_flag(sheet.root, LV_OBJ_FLAG_HIDDEN);
}

static void sheet_open(sheet_mode_t mode)
{
    sheet.mode = mode;
    sheet.open = true;
    // Undo belongs with the history, not with the timers or the handoff card.
    if (mode == SHEET_LOG) lv_obj_remove_flag(sheet.undo_button, LV_OBJ_FLAG_HIDDEN);
    else lv_obj_add_flag(sheet.undo_button, LV_OBJ_FLAG_HIDDEN);
    sheet_refresh();
    lv_obj_remove_flag(sheet.root, LV_OBJ_FLAG_HIDDEN);
    lv_obj_move_foreground(sheet.root);
}

static void on_log(lv_event_t *event) { (void)event; sheet_open(SHEET_LOG); }
static void on_timers(lv_event_t *event) { (void)event; sheet_open(SHEET_TIMERS); }

static void on_sheet_undo(lv_event_t *event)
{
    (void)event;
    const cr_event_t *target = cr_engine_last_undoable(engine);
    char what[CR_TITLE_MAX + 8];
    snprintf(what, sizeof what, "undo %s", target != NULL ? target->title : "");
    if (cr_engine_undo_last(engine, NULL)) toast(what, CR_THEME_SHOCK);
    else toast("NOTHING LOGGED — nothing to undo", CR_THEME_MED);
    sheet_refresh();
}

static lv_obj_t *sheet_row(lv_obj_t *parent, const char *label, const char *value,
                           uint32_t color)
{
    lv_obj_t *row = lv_obj_create(parent);
    lv_obj_set_size(row, (int32_t)(cr_screen.width - 70), 72);
    lv_obj_set_style_bg_color(row, lv_color_hex(CR_THEME_SURFACE), 0);
    lv_obj_set_style_bg_opa(row, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(row, 0, 0);
    lv_obj_set_style_radius(row, 10, 0);
    lv_obj_set_style_pad_all(row, 0, 0);
    lv_obj_remove_flag(row, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_remove_flag(row, LV_OBJ_FLAG_CLICKABLE);

    // The colour bar down the left edge is the only thing that says which
    // category a number belongs to, so it is not decoration.
    lv_obj_t *bar = lv_obj_create(row);
    lv_obj_set_size(bar, 5, 52);
    lv_obj_set_pos(bar, 8, 10);
    lv_obj_set_style_bg_color(bar, lv_color_hex(color), 0);
    lv_obj_set_style_bg_opa(bar, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(bar, 0, 0);
    lv_obj_set_style_radius(bar, 2, 0);

    // 9 pt caption over a 14 pt value on the watch — the two generated sizes
    // either side of ×2.071.
    lv_obj_t *caption = make_label(row, label, CR_THEME_TEXT_DIM, cr_font_16_px);
    lv_obj_set_style_text_align(caption, LV_TEXT_ALIGN_LEFT, 0);
    lv_obj_set_pos(caption, 22, 8);
    lv_obj_t *text = make_label(row, value, CR_THEME_TEXT, 29.0f);
    lv_obj_set_style_text_align(text, LV_TEXT_ALIGN_LEFT, 0);
    lv_obj_set_pos(text, 22, 30);
    return row;
}

static void sheet_create(lv_obj_t *parent)
{
    sheet.root = lv_obj_create(parent);
    lv_obj_set_size(sheet.root, (int32_t)cr_screen.width, (int32_t)cr_screen.height);
    lv_obj_set_pos(sheet.root, 0, 0);
    lv_obj_set_style_bg_color(sheet.root, lv_color_hex(CR_THEME_BG), 0);
    lv_obj_set_style_bg_opa(sheet.root, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(sheet.root, 0, 0);
    lv_obj_set_style_radius(sheet.root, 0, 0);
    lv_obj_set_style_pad_all(sheet.root, 0, 0);
    lv_obj_remove_flag(sheet.root, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_flag(sheet.root, LV_OBJ_FLAG_HIDDEN);
    cr_probe_name(sheet.root, "sheet.root");

    sheet.title = make_label(sheet.root, "LOG", CR_THEME_TEXT_DIM, cr_font_16_px);
    place_label(sheet.title, (cr_pt_t){ cr_screen.width / 2, 74 });

    // The list scrolls; the rounded corners mean it cannot use the full width.
    sheet.list = lv_obj_create(sheet.root);
    lv_obj_set_size(sheet.list, (int32_t)(cr_screen.width - 70), 300);
    lv_obj_set_pos(sheet.list, 35, 100);
    lv_obj_set_style_bg_opa(sheet.list, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(sheet.list, 0, 0);
    lv_obj_set_style_pad_row(sheet.list, 6, 0);
    lv_obj_set_flex_flow(sheet.list, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_scroll_dir(sheet.list, LV_DIR_VER);
    cr_probe_name(sheet.list, "sheet.list");

    lv_obj_t *undo = lv_button_create(sheet.root);
    lv_obj_set_size(undo, 220, 50);
    lv_obj_set_pos(undo, (int32_t)(cr_screen.width / 2 - 110), 406);
    lv_obj_set_style_radius(undo, 25, 0);
    lv_obj_set_style_bg_color(undo, lv_color_hex(CR_THEME_SURFACE_HI), 0);
    lv_obj_set_style_border_color(undo, lv_color_hex(CR_THEME_SHOCK), 0);
    lv_obj_set_style_border_width(undo, 2, 0);
    lv_obj_set_style_shadow_width(undo, 0, 0);
    lv_obj_add_event_cb(undo, on_sheet_undo, LV_EVENT_CLICKED, NULL);
    cr_probe_name(undo, "sheet.undo");
    sheet.undo_button = undo;
    sheet.undo_label = make_label(undo, "UNDO", CR_THEME_SHOCK, cr_font_16_px);
    lv_obj_center(sheet.undo_label);

    make_disc(sheet.root, &cr_screen.pads.cancel, "xmark", CR_THEME_PAD_FILL,
              CR_THEME_PAD_ICON, sheet_close, NULL, "sheet.close");
}

// MARK: - Live screen controls

static void on_ring(lv_event_t *event)
{
    (void)event;
    // Post-ROSC the ring is the vitals-confirmed target, exactly as it is the
    // pulse-check target during the arrest. Same object, because the table
    // puts the vitals ring on the CPR ring's centre and diameter.
    if (engine->rosc_achieved) {
        cr_ms_t left = 0;
        if (cr_engine_vitals_remaining(engine, clock_ms(), &left) && left > CR_SEC(15)) {
            toast("NOTHING LOGGED — vitals not due", CR_THEME_MED);
            return;
        }
        report(cr_engine_confirm_vitals(engine, clock_ms()), "vitals reassessed");
        return;
    }
    if (!engine->cpr_started) {
        report(cr_engine_start_cpr(engine, clock_ms()), "start CPR");
        return;
    }
    if (engine->in_pulse_check) {
        report(cr_engine_complete_pulse_check(engine, false, clock_ms()), "end pulse check");
        return;
    }
    // Tapping the big centre target IS gated on the cycle being due — unlike
    // reaching Rhythm through the fan, because this one is easy to hit by
    // accident.
    if (cr_engine_cycle_remaining(engine, clock_ms()) > 0) {
        toast("NOTHING LOGGED — pulse check not due", CR_THEME_MED);
        return;
    }
    report(cr_engine_begin_pulse_check(engine, clock_ms()), "pulse check");
}

static void on_pulse_start(lv_event_t *event)
{
    (void)event;
    report(cr_engine_begin_pulse_check(engine, clock_ms()), "pulse check");
}

static void on_check_resume(lv_event_t *event)
{
    (void)event;
    report(cr_engine_complete_pulse_check(engine, false, clock_ms()), "resume CPR");
}

static void on_check_found(lv_event_t *event)
{
    (void)event;
    report(cr_engine_complete_pulse_check(engine, true, clock_ms()), "pulse found");
}

static void on_pause(lv_event_t *event)
{
    (void)event;
    report(cr_engine_toggle_pause(engine, clock_ms()), "pause");
}

/// Pulses lost. The engine deliberately leaves the drug anchors alone — time
/// since the last epi still matters on the way back down.
static void on_re_arrest(lv_event_t *event)
{
    (void)event;
    report(cr_engine_re_arrest(engine, clock_ms()), "re-arrest");
}

static void on_handoff(lv_event_t *event)
{
    (void)event;
    sheet_open(SHEET_HANDOFF);
}

/// The flag asks first. Every other control on this screen either logs
/// something undoable or changes a clock; this one is the only door out of a
/// running code, and there is no un-end.
static void on_flag(lv_event_t *event)
{
    (void)event;
    lv_obj_remove_flag(confirm.root, LV_OBJ_FLAG_HIDDEN);
    lv_obj_move_foreground(confirm.root);
}

static void on_confirm_cancel(lv_event_t *event)
{
    (void)event;
    lv_obj_add_flag(confirm.root, LV_OBJ_FLAG_HIDDEN);
}

static void on_confirm_end(lv_event_t *event)
{
    (void)event;
    lv_obj_add_flag(confirm.root, LV_OBJ_FLAG_HIDDEN);
    // Nothing from the live screen may be left open behind the debrief: a fan
    // or a sheet still showing would be the first thing on screen if a second
    // code starts.
    fan_close();
    sheet.open = false;
    lv_obj_add_flag(sheet.root, LV_OBJ_FLAG_HIDDEN);
    cr_engine_end(engine, clock_ms());
    ui_flow_show_summary();
}

void ui_create(cr_engine_t *e, cr_ms_t (*clock)(void))
{
    engine = e;
    clock_ms = clock;

    // Its own screen rather than the active one: home and setup come first,
    // and the flow switches to this when the code actually starts.
    lv_obj_t *screen = lv_obj_create(NULL);
    live.root = screen;
    cr_probe_name(screen, "screen");
    lv_obj_set_style_bg_color(screen, lv_color_hex(CR_THEME_BG), 0);
    lv_obj_set_style_pad_all(screen, 0, 0);
    lv_obj_remove_flag(screen, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_text_font(screen, &cr_font_28, 0);

    // The CPR ring, and the countdown stack inside it.
    live.cpr_ring = make_ring(screen, &cr_screen.cpr_ring, CR_THEME_CPR, "cpr.ring");

    // The inner ring is the epi interval — the watch draws it inside the CPR
    // ring so one glance covers both clocks.
    live.drug_ring = make_ring(screen, &cr_screen.drug_ring, CR_THEME_MED, "drug.ring");
    lv_obj_set_style_arc_opa(live.drug_ring, LV_OPA_20, 0);
    lv_obj_add_flag(live.drug_ring, LV_OBJ_FLAG_HIDDEN);

    // The vitals ring takes the CPR ring's exact place post-ROSC — same
    // centre, same diameter in the table — so the eye does not have to move
    // when the outcome changes.
    live.vitals_ring = make_ring(screen, &cr_screen.vitals_ring, CR_THEME_ROSC, "vitals.ring");
    lv_obj_add_flag(live.vitals_ring, LV_OBJ_FLAG_HIDDEN);

    // A transparent disc over the ring's middle takes the tap, so the target
    // is the whole centre rather than the 8 px stroke.
    cr_disc_t ring_hit = { cr_screen.cpr_ring.center, cr_screen.cpr_ring.diameter * 0.8f, 0 };
    lv_obj_t *hit = lv_button_create(screen);
    place_disc(hit, &ring_hit);
    lv_obj_set_style_radius(hit, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_bg_opa(hit, LV_OPA_TRANSP, 0);
    lv_obj_set_style_shadow_width(hit, 0, 0);
    lv_obj_add_event_cb(hit, on_ring, LV_EVENT_CLICKED, NULL);
    cr_probe_name(hit, "ring.hit");

    live.countdown = make_label(screen, "2:00", CR_THEME_TEXT, cr_screen.countdown.font);
    place_text(live.countdown, &cr_screen.countdown);
    cr_probe_name(live.countdown, "countdown");

    live.cycle_chip = make_label(screen, "CYCLE 1", CR_THEME_TEXT_DIM, cr_screen.cycle_chip.font);
    place_text(live.cycle_chip, &cr_screen.cycle_chip);
    cr_probe_name(live.cycle_chip, "cycle.chip");

    live.drug_line = make_label(screen, "", CR_THEME_MED, cr_screen.drug_line.font);
    place_text(live.drug_line, &cr_screen.drug_line);
    cr_probe_name(live.drug_line, "drug.line");

    // Centred in the ring rather than at the watch's y: at this scale the
    // label sat low enough to clip against the ring's stroke.
    live.start_text = make_label(screen, "START CPR", CR_THEME_CPR, cr_font_16_px);
    place_label(live.start_text, cr_screen.cpr_ring.center);
    cr_probe_name(live.start_text, "start.text");

    // The watch put this dead centre of the ring; here it covered the
    // countdown, so it becomes a small line in the gap above it.
    live.paused_text = make_label(screen, "PAUSED", CR_THEME_PAUSE, cr_font_16_px);
    cr_pt_t paused_at = { cr_screen.cpr_ring.center.x,
                          (cr_screen.cycle_chip.center.y + cr_screen.countdown.center.y) / 2 };
    place_label(live.paused_text, paused_at);
    lv_obj_add_flag(live.paused_text, LV_OBJ_FLAG_HIDDEN);
    cr_probe_name(live.paused_text, "paused.text");

    live.code_clock = make_label(screen, "0:00", CR_THEME_TEXT, cr_screen.code_clock.font);
    place_label(live.code_clock, lifted(cr_screen.code_clock.center));
    cr_probe_name(live.code_clock, "code.clock");

    live.total_label = make_label(screen, "TOTAL", CR_THEME_TEXT_DIM, cr_screen.total_label.font);
    place_label(live.total_label, lifted(cr_screen.total_label.center));
    cr_probe_name(live.total_label, "total.label");

    live.patient = make_label(screen, "10.0 kg", CR_THEME_TEXT_DIM, cr_screen.patient.font);
    place_text(live.patient, &cr_screen.patient);
    cr_probe_name(live.patient, "patient");

    // watchOS drew its own clock in this corner and gave no way to hide it;
    // here the corner is ours, so the clock is too.
    live.wall_clock = make_label(screen, "--:--:--", CR_THEME_TEXT_DIM, cr_font_16_px);
    // Top right, but inside the corner arc — the watch's own clock sat in a
    // keep-out zone this panel does not have.
    cr_pt_t clock_at = { cr_screen.width - 74.0f, 54.0f };
    place_label(live.wall_clock, clock_at);
    cr_probe_name(live.wall_clock, "wall.clock");

    live.toast = make_label(screen, "", CR_THEME_ROSC, cr_screen.toast.font);
    place_text(live.toast, &cr_screen.toast);
    lv_obj_set_style_bg_color(live.toast, lv_color_hex(CR_THEME_SURFACE), 0);
    lv_obj_set_style_bg_opa(live.toast, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(live.toast, 10, 0);
    lv_obj_add_flag(live.toast, LV_OBJ_FLAG_HIDDEN);
    cr_probe_name(live.toast, "toast");

    // Header controls.
    make_disc(screen, &cr_screen.log_button, "list.bullet", CR_THEME_SURFACE,
              CR_THEME_TEXT, on_log, NULL, "btn.log");
    make_disc(screen, &cr_screen.timers_button, "timer", CR_THEME_SURFACE,
              CR_THEME_TEXT, on_timers, NULL, "btn.timers");
    make_disc(screen, &cr_screen.mute_button, "speaker.slash.fill", CR_THEME_SURFACE,
              CR_THEME_TEXT_DIM, NULL, NULL, "btn.mute");
    // Red, as on the watch: the one control here that ends things.
    make_disc(screen, &cr_screen.flag_button, "flag.fill", CR_THEME_SURFACE,
              CR_THEME_MED, on_flag, NULL, "btn.flag");
    live.pause_button = make_disc(screen, &cr_screen.pause_button, "pause.fill",
                                  CR_THEME_SURFACE, CR_THEME_PAUSE, on_pause, NULL, "btn.pause");

    // The four anchor pucks. Each opens its fan; every fan blooms across the
    // TOP, clear of the lower-right quadrant a right index finger covers.
    const struct { const cr_disc_t *disc; const char *symbol; const char *anchor;
                   uint32_t color; const char *probe; } pucks[] = {
        { &cr_screen.meds_puck,   "syringe.fill",      CR_ANCHOR_MEDS,   CR_THEME_MED,    "puck.meds" },
        { &cr_screen.shock_puck,  "bolt.fill",         CR_ANCHOR_SHOCK,  CR_THEME_SHOCK,  "puck.shock" },
        { &cr_screen.events_puck, "square.grid.2x2.fill", CR_ANCHOR_EVENTS, CR_THEME_CPR,   "puck.events" },
        { &cr_screen.fluids_puck, "drop.fill",         CR_ANCHOR_FLUIDS, CR_THEME_VOLUME, "puck.fluids" },
    };
    for (size_t i = 0; i < 4; i++) {
        cr_disc_t puck = { lifted(pucks[i].disc->center), pucks[i].disc->diameter,
                           pucks[i].disc->glyph };
        live.pucks[i] = make_disc(screen, &puck, pucks[i].symbol, CR_THEME_SURFACE,
                                  pucks[i].color, on_puck, (void *)pucks[i].anchor,
                                  pucks[i].probe);
    }

    // The fan overlay: built once, re-laid-out each time one opens.
    fan.root = lv_obj_create(screen);
    lv_obj_set_size(fan.root, (int32_t)cr_screen.width, (int32_t)cr_screen.height);
    lv_obj_set_pos(fan.root, 0, 0);
    lv_obj_set_style_pad_all(fan.root, 0, 0);
    lv_obj_set_style_border_width(fan.root, 0, 0);
    lv_obj_set_style_radius(fan.root, 0, 0);
    // A lifted wash rather than flat black: the bubbles are dark, and on a
    // black scrim they sank to the same value as the background.
    lv_obj_set_style_bg_color(fan.root, lv_color_hex(CR_THEME_BG), 0);
    lv_obj_set_style_bg_opa(fan.root, LV_OPA_80, 0);
    lv_obj_remove_flag(fan.root, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_flag(fan.root, LV_OBJ_FLAG_HIDDEN);
    cr_probe_name(fan.root, "fan.root");

    fan.title_chip = make_label(fan.root, "", CR_THEME_TEXT, 16 * CR_LAYOUT_SCALE);
    cr_probe_name(fan.title_chip, "fan.title");

    for (size_t i = 0; i < CR_MAX_SLOTS; i++) {
        lv_obj_t *button = lv_button_create(fan.root);
        lv_obj_set_style_radius(button, LV_RADIUS_CIRCLE, 0);
        lv_obj_set_style_border_width(button, 2, 0);
        lv_obj_set_style_shadow_width(button, 0, 0);
        lv_obj_add_event_cb(button, on_slot, LV_EVENT_CLICKED, (void *)(uintptr_t)i);
        lv_obj_add_flag(button, LV_OBJ_FLAG_HIDDEN);
        char name[16];
        snprintf(name, sizeof name, "fan.slot%d", (int)i);
        cr_probe_name(button, name);
        fan.slots[i] = button;

        fan.labels[i] = make_label(fan.root, "", CR_THEME_TEXT, cr_arc.label_font);
        lv_label_set_long_mode(fan.labels[i], LV_LABEL_LONG_WRAP);
        lv_obj_add_flag(fan.labels[i], LV_OBJ_FLAG_HIDDEN);
        fan.slots[i] = button;
    }

    // Pulse check. The button only appears when the cycle is up, so it reads
    // as "the thing to do now" rather than another control to ignore.
    live.pulse_button = lv_button_create(screen);
    lv_obj_set_size(live.pulse_button, 190, 52);
    lv_obj_set_style_radius(live.pulse_button, 26, 0);
    lv_obj_set_style_bg_color(live.pulse_button, lv_color_hex(CR_THEME_SURFACE_HI), 0);
    lv_obj_set_style_border_color(live.pulse_button, lv_color_hex(CR_THEME_RHYTHM), 0);
    lv_obj_set_style_border_width(live.pulse_button, 2, 0);
    lv_obj_set_style_shadow_width(live.pulse_button, 0, 0);
    lv_obj_set_pos(live.pulse_button, (int32_t)(cr_screen.cpr_ring.center.x - 95), 296);
    lv_obj_add_event_cb(live.pulse_button, on_pulse_start, LV_EVENT_CLICKED, NULL);
    lv_obj_add_flag(live.pulse_button, LV_OBJ_FLAG_HIDDEN);
    cr_probe_name(live.pulse_button, "btn.pulsecheck");
    lv_obj_t *pulse_label = make_label(live.pulse_button, "PULSE CHECK", CR_THEME_RHYTHM,
                                       cr_font_16_px);
    lv_obj_center(pulse_label);

    // The hands-off screen: a count-UP clock and two big exits.
    live.check_title = make_label(screen, "PULSE CHECK", CR_THEME_CPR, cr_font_16_px);
    place_label(live.check_title, (cr_pt_t){ cr_screen.cpr_ring.center.x, 196 });
    live.check_clock = make_label(screen, "0:00", CR_THEME_TEXT, cr_screen.countdown.font);
    place_label(live.check_clock, cr_screen.cpr_ring.center);
    live.check_hint = make_label(screen, "hands off — check pulse & rhythm",
                                 CR_THEME_TEXT_DIM, cr_font_16_px);
    place_label(live.check_hint, (cr_pt_t){ cr_screen.cpr_ring.center.x, 296 });

    live.check_resume = lv_button_create(screen);
    lv_obj_set_size(live.check_resume, 150, 56);
    lv_obj_set_pos(live.check_resume, 44, 326);
    lv_obj_set_style_radius(live.check_resume, 28, 0);
    lv_obj_set_style_bg_color(live.check_resume, lv_color_hex(CR_THEME_SURFACE_HI), 0);
    lv_obj_set_style_border_color(live.check_resume, lv_color_hex(CR_THEME_CPR), 0);
    lv_obj_set_style_border_width(live.check_resume, 2, 0);
    lv_obj_set_style_shadow_width(live.check_resume, 0, 0);
    lv_obj_add_event_cb(live.check_resume, on_check_resume, LV_EVENT_CLICKED, NULL);
    cr_probe_name(live.check_resume, "btn.resumecpr");
    lv_obj_center(make_label(live.check_resume, "CONTINUE CPR", CR_THEME_CPR, cr_font_16_px));

    live.check_found = lv_button_create(screen);
    lv_obj_set_size(live.check_found, 150, 56);
    lv_obj_set_pos(live.check_found, (int32_t)(cr_screen.width - 194), 326);
    lv_obj_set_style_radius(live.check_found, 28, 0);
    lv_obj_set_style_bg_color(live.check_found, lv_color_hex(CR_THEME_SURFACE_HI), 0);
    lv_obj_set_style_border_color(live.check_found, lv_color_hex(CR_THEME_ROSC), 0);
    lv_obj_set_style_border_width(live.check_found, 2, 0);
    lv_obj_set_style_shadow_width(live.check_found, 0, 0);
    lv_obj_add_event_cb(live.check_found, on_check_found, LV_EVENT_CLICKED, NULL);
    cr_probe_name(live.check_found, "btn.pulsefound");
    lv_obj_center(make_label(live.check_found, "PULSE FOUND", CR_THEME_ROSC, cr_font_16_px));

    // MARK: Post-ROSC
    //
    // Every position is the table's own entry, even where it coincides with a
    // CPR-phase one (vitals ring = CPR ring, vitals count = countdown), so the
    // probe checks each against the number Sebastian placed rather than
    // against a neighbour that happens to share it.
    live.rosc_elapsed = make_label(screen, "ROSC 0:00", CR_THEME_ROSC,
                                   cr_screen.rosc_elapsed.font);
    place_text(live.rosc_elapsed, &cr_screen.rosc_elapsed);
    cr_probe_name(live.rosc_elapsed, "rosc.elapsed");

    live.vitals_label = make_label(screen, "NEXT VITALS", CR_THEME_TEXT_DIM,
                                   cr_screen.vitals_label.font);
    place_text(live.vitals_label, &cr_screen.vitals_label);
    cr_probe_name(live.vitals_label, "vitals.label");

    live.vitals_count = make_label(screen, "5:00", CR_THEME_TEXT, cr_screen.vitals_count.font);
    place_text(live.vitals_count, &cr_screen.vitals_count);
    cr_probe_name(live.vitals_count, "vitals.count");

    // The prompt only appears inside the last 15 s, so it reads as "now"
    // rather than as another label that is always there.
    live.vitals_prompt = make_label(screen, "TAP — VITALS", CR_THEME_BG,
                                    cr_screen.vitals_prompt.font);
    lv_obj_set_style_bg_color(live.vitals_prompt, lv_color_hex(CR_THEME_ROSC), 0);
    lv_obj_set_style_bg_opa(live.vitals_prompt, LV_OPA_COVER, 0);
    lv_obj_set_style_pad_hor(live.vitals_prompt, 14, 0);
    lv_obj_set_style_pad_ver(live.vitals_prompt, 4, 0);
    lv_obj_set_style_radius(live.vitals_prompt, LV_RADIUS_CIRCLE, 0);
    place_text(live.vitals_prompt, &cr_screen.vitals_prompt);
    cr_probe_name(live.vitals_prompt, "vitals.prompt");

    // Only reachable if a protocol ships no vitals cadence — every built-in
    // one does. It is what the table's rosc_heart entry is for.
    live.rosc_heart = lv_image_create(screen);
    {
        const lv_image_dsc_t *heart = cr_icon("heart.fill");
        if (heart != NULL) lv_image_set_src(live.rosc_heart, heart);
        lv_obj_set_style_image_recolor(live.rosc_heart, lv_color_hex(CR_THEME_ROSC), 0);
        lv_obj_set_style_image_recolor_opa(live.rosc_heart, LV_OPA_COVER, 0);
        lv_image_set_scale(live.rosc_heart,
                           (int32_t)(cr_screen.rosc_heart.glyph / 52.0f * 256.0f));
        place(live.rosc_heart, cr_screen.rosc_heart.center,
              cr_screen.rosc_heart.diameter, cr_screen.rosc_heart.diameter);
        cr_probe_name(live.rosc_heart, "rosc.heart");
    }

    live.re_arrest = make_capsule(screen, &cr_screen.re_arrest, "RE-ARREST",
                                  CR_THEME_MED, CR_THEME_BG, on_re_arrest, "btn.rearrest");
    live.handoff = make_capsule(screen, &cr_screen.handoff, "HANDOFF",
                                CR_THEME_SURFACE_HI, CR_THEME_ROSC, on_handoff, "btn.handoff");

    lv_obj_t *const rosc_parts[] = { live.rosc_elapsed, live.vitals_label, live.vitals_count,
                                     live.vitals_prompt, live.rosc_heart, live.re_arrest,
                                     live.handoff };
    for (size_t i = 0; i < sizeof rosc_parts / sizeof rosc_parts[0]; i++) {
        lv_obj_add_flag(rosc_parts[i], LV_OBJ_FLAG_HIDDEN);
    }

    // Med timer chips ride around the ring: what has been given, how many
    // times, and how long ago. Hand-placed, so the column pitch is not quite
    // uniform — that is deliberate.
    for (uint8_t i = 0; i < cr_screen.chip_count && i < 6; i++) {
        const cr_chip_t *spec = &cr_screen.chips[i];
        lv_obj_t *box = lv_obj_create(screen);
        lv_obj_set_size(box, (int32_t)spec->w, (int32_t)spec->h);
        lv_obj_set_pos(box, (int32_t)spec->origin.x, (int32_t)spec->origin.y);
        lv_obj_set_style_bg_opa(box, LV_OPA_TRANSP, 0);
        lv_obj_set_style_border_width(box, 0, 0);
        lv_obj_set_style_pad_all(box, 0, 0);
        lv_obj_remove_flag(box, LV_OBJ_FLAG_SCROLLABLE);
        lv_obj_remove_flag(box, LV_OBJ_FLAG_CLICKABLE);
        lv_obj_add_flag(box, LV_OBJ_FLAG_HIDDEN);
        char name[16];
        snprintf(name, sizeof name, "chip%d", (int)i);
        cr_probe_name(box, name);

        const lv_align_t align = spec->trailing ? LV_ALIGN_TOP_RIGHT : LV_ALIGN_TOP_LEFT;
        live.chips[i].name = make_label(box, "", CR_THEME_TEXT, cr_font_16_px);
        lv_obj_align(live.chips[i].name, align, 0, 0);
        live.chips[i].clock = make_label(box, "", CR_THEME_TEXT, cr_font_16_px);
        lv_obj_align(live.chips[i].clock, align, 0, 22);
        live.chips[i].root = box;
    }

    sheet_create(screen);

    // Exit pads: pale fill, dark red glyph. Deliberately NOT a menu colour —
    // these are the two controls that must read as "not an option".
    make_disc(fan.root, &cr_screen.pads.cancel, "xmark", CR_THEME_PAD_FILL,
              CR_THEME_PAD_ICON, on_cancel, NULL, "pad.cancel");
    fan.back_pad = make_disc(fan.root, &cr_screen.pads.back, "chevron.backward", CR_THEME_PAD_FILL,
                             CR_THEME_PAD_ICON, on_back, NULL, "pad.back");

    // MARK: End-code confirmation
    //
    // These four coordinates are the only ones on this screen that are NOT
    // from the layout table, and they cannot be: watchOS put this behind a
    // system confirmationDialog, which has no geometry to port. Centred in the
    // middle band, clear of the pucks, and topmost so nothing underneath can
    // take the touch.
    confirm.root = lv_obj_create(screen);
    lv_obj_set_size(confirm.root, (int32_t)cr_screen.width, (int32_t)cr_screen.height);
    lv_obj_set_pos(confirm.root, 0, 0);
    lv_obj_set_style_bg_color(confirm.root, lv_color_hex(CR_THEME_BG), 0);
    lv_obj_set_style_bg_opa(confirm.root, LV_OPA_90, 0);
    lv_obj_set_style_border_width(confirm.root, 0, 0);
    lv_obj_set_style_radius(confirm.root, 0, 0);
    lv_obj_set_style_pad_all(confirm.root, 0, 0);
    lv_obj_remove_flag(confirm.root, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_flag(confirm.root, LV_OBJ_FLAG_HIDDEN);
    cr_probe_name(confirm.root, "confirm.root");

    lv_obj_t *confirm_title = make_label(confirm.root, "END CODE?", CR_THEME_TEXT, 33.0f);
    place_label(confirm_title, (cr_pt_t){ cr_screen.width / 2, 168 });
    cr_probe_name(confirm_title, "confirm.title");
    lv_obj_t *confirm_note = make_label(confirm.root, "the clocks stop — the record stays",
                                        CR_THEME_TEXT_DIM, cr_font_16_px);
    place_label(confirm_note, (cr_pt_t){ cr_screen.width / 2, 214 });
    cr_probe_name(confirm_note, "confirm.note");

    const cr_text_t end_spec = { { cr_screen.width / 2, 292.0f }, 288.0f, 66.0f, 22.0f };
    const cr_text_t cancel_spec = { { cr_screen.width / 2, 376.0f }, 224.0f, 58.0f, 20.0f };
    make_capsule(confirm.root, &end_spec, "END & REVIEW", CR_THEME_MED, CR_THEME_BG,
                 on_confirm_end, "confirm.end");
    make_capsule(confirm.root, &cancel_spec, "CANCEL", CR_THEME_SURFACE_HI, CR_THEME_TEXT,
                 on_confirm_cancel, "confirm.cancel");
}

lv_obj_t *ui_live_screen(void)
{
    return live.root;
}

/// The post-ROSC centre stack. The vitals cadence counts down where the cycle
/// counted down, in the same ring and the same digits, because post-ROSC the
/// question changes but the shape of the answer does not.
static void rosc_tick(cr_ms_t now)
{
    char buf[32];
    const cr_timer_spec_t *spec = cr_protocol_vitals_spec(&engine->protocol);
    cr_ms_t left = 0;
    const bool has_cadence = cr_engine_vitals_remaining(engine, now, &left);
    const bool over = has_cadence && left <= 0;
    const bool due = has_cadence && left <= CR_SEC(15);

    cr_format_clock(buf, sizeof buf, cr_engine_rosc_elapsed(engine, now));
    lv_label_set_text_fmt(live.rosc_elapsed, "ROSC %s", buf);

    int32_t value = 0;
    if (has_cadence && spec != NULL && spec->duration_ms > 0 && left > 0) {
        value = (int32_t)(left * 1000 / spec->duration_ms);
    }
    lv_arc_set_value(live.vitals_ring, value);
    lv_obj_set_style_arc_color(live.vitals_ring,
                               lv_color_hex(over ? CR_THEME_MED : CR_THEME_ROSC),
                               LV_PART_INDICATOR);

    if (has_cadence) {
        cr_format_clock_signed(buf, sizeof buf, left);
        lv_label_set_text(live.vitals_count, buf);
        lv_obj_set_style_text_color(live.vitals_count,
                                   lv_color_hex(over ? CR_THEME_MED : CR_THEME_TEXT), 0);
        lv_obj_set_style_text_color(live.vitals_label,
                                   lv_color_hex(over ? CR_THEME_MED : CR_THEME_TEXT_DIM), 0);
        lv_obj_set_style_bg_color(live.vitals_prompt,
                                  lv_color_hex(over ? CR_THEME_MED : CR_THEME_ROSC), 0);
    }

    // With a cadence: the label, the countdown, and the prompt inside the last
    // 15 s. Without one: just the heart, because there is nothing to count.
    lv_obj_t *const counted[] = { live.vitals_label, live.vitals_count };
    for (size_t i = 0; i < sizeof counted / sizeof counted[0]; i++) {
        if (has_cadence) lv_obj_remove_flag(counted[i], LV_OBJ_FLAG_HIDDEN);
        else lv_obj_add_flag(counted[i], LV_OBJ_FLAG_HIDDEN);
    }
    if (has_cadence && due) lv_obj_remove_flag(live.vitals_prompt, LV_OBJ_FLAG_HIDDEN);
    else lv_obj_add_flag(live.vitals_prompt, LV_OBJ_FLAG_HIDDEN);
    if (has_cadence) lv_obj_add_flag(live.rosc_heart, LV_OBJ_FLAG_HIDDEN);
    else lv_obj_remove_flag(live.rosc_heart, LV_OBJ_FLAG_HIDDEN);
}

void ui_tick(void)
{
    const cr_ms_t now = clock_ms();
    char buf[64];

    // Wall clock. Stamped at build time and advanced by the monotonic clock;
    // M5 replaces this with the board's PCF85063 RTC, which survives a
    // reboot and does not need reflashing to stay right.
    wall_clock_text(buf, sizeof buf, now);
    lv_label_set_text(live.wall_clock, buf);

    const cr_ms_t cycle = cr_engine_cycle_remaining(engine, now);
    const cr_timer_spec_t *spec = cr_protocol_cycle_spec(&engine->protocol);
    const bool overdue = cycle <= 0;
    const bool rosc = engine->rosc_achieved;

    if (rosc) {
        rosc_tick(now);
    } else if (engine->cpr_started) {
        lv_obj_add_flag(live.start_text, LV_OBJ_FLAG_HIDDEN);
        lv_obj_remove_flag(live.countdown, LV_OBJ_FLAG_HIDDEN);
        cr_format_clock_signed(buf, sizeof buf, cycle);
        lv_label_set_text(live.countdown, buf);
        lv_obj_set_style_text_color(live.countdown,
                                    lv_color_hex(overdue ? CR_THEME_MED : CR_THEME_TEXT), 0);
        int32_t value = 0;
        if (spec != NULL && spec->duration_ms > 0 && cycle > 0) {
            value = (int32_t)(cycle * 1000 / spec->duration_ms);
        }
        lv_arc_set_value(live.cpr_ring, value);
        lv_obj_set_style_arc_color(live.cpr_ring,
                                   lv_color_hex(overdue ? CR_THEME_MED
                                                        : (engine->paused ? CR_THEME_PAUSE
                                                                          : CR_THEME_CPR)),
                                   LV_PART_INDICATOR);
        lv_label_set_text_fmt(live.cycle_chip, "CYCLE %d", (int)cr_engine_cycle_index(engine) + 1);
    } else {
        lv_obj_remove_flag(live.start_text, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(live.countdown, LV_OBJ_FLAG_HIDDEN);
        lv_arc_set_value(live.cpr_ring, 1000);
        lv_label_set_text(live.cycle_chip, "");
    }

    // The centre of the screen belongs to exactly one outcome, so the other
    // one's parts go away wholesale rather than being reasoned about control by
    // control — the same reason the watch made roscStack its own branch. The
    // header, the patient strip, the clocks, the pucks and the chips are NOT in
    // either list: they are drawn by the same code at the same coordinates in
    // both states, so nothing shifts when the outcome changes.
    lv_obj_t *const cpr_only[] = { live.countdown, live.cycle_chip, live.start_text };
    lv_obj_t *const rosc_only[] = { live.vitals_ring, live.rosc_elapsed,
                                    live.re_arrest, live.handoff };
    // These three set their own visibility above, every frame, so here they
    // only ever need hiding.
    for (size_t i = 0; i < sizeof cpr_only / sizeof cpr_only[0]; i++) {
        if (rosc) lv_obj_add_flag(cpr_only[i], LV_OBJ_FLAG_HIDDEN);
    }
    // The CPR ring is the exception, and it cost a re-arrest to find out: it
    // had never needed hiding before ROSC existed, so nothing restored it, and
    // a re-arrest came back to a bare countdown with no ring around it. Its
    // visibility is purely the state's, so it is set BOTH ways.
    if (rosc) lv_obj_add_flag(live.cpr_ring, LV_OBJ_FLAG_HIDDEN);
    else lv_obj_remove_flag(live.cpr_ring, LV_OBJ_FLAG_HIDDEN);
    for (size_t i = 0; i < sizeof rosc_only / sizeof rosc_only[0]; i++) {
        if (rosc) lv_obj_remove_flag(rosc_only[i], LV_OBJ_FLAG_HIDDEN);
        else lv_obj_add_flag(rosc_only[i], LV_OBJ_FLAG_HIDDEN);
    }
    if (!rosc) {
        // The four rosc_tick owns; it never runs outside ROSC to hide them.
        lv_obj_add_flag(live.vitals_label, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(live.vitals_count, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(live.vitals_prompt, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(live.rosc_heart, LV_OBJ_FLAG_HIDDEN);
    }

    cr_format_clock(buf, sizeof buf, cr_engine_elapsed(engine, now));
    lv_label_set_text(live.code_clock, buf);

    // LVGL's printf has no float support; "%.1f" would render as "f".
    char weight[24];
    snprintf(weight, sizeof weight, "%.1f kg", engine->session.patient.weight_kg);
    lv_label_set_text(live.patient, weight);

    // The epi line under the countdown: dim while idle, because a countdown
    // for a med nobody has given yet reads as a standing order.
    const cr_timer_spec_t *epi = cr_protocol_interval_spec(&engine->protocol, 0);
    if (epi != NULL && !rosc) {
        bool running = cr_engine_interval_is_running(engine, epi);
        cr_format_clock_signed(buf, sizeof buf, cr_engine_interval_remaining(engine, epi, now));
        lv_label_set_text_fmt(live.drug_line, "%s %s", epi->title, buf);
        lv_obj_set_style_text_opa(live.drug_line, running ? LV_OPA_COVER : LV_OPA_40, 0);
        lv_obj_set_style_text_color(
            live.drug_line,
            lv_color_hex(cr_engine_interval_is_overdue(engine, epi, now) ? CR_THEME_MED
                                                                        : CR_THEME_TEXT_DIM), 0);
    }

    // ROSC closes any open pause, so this is belt and braces — but a stale
    // PAUSED over the vitals countdown would be a lie about the clock.
    if (engine->paused && !rosc) lv_obj_remove_flag(live.paused_text, LV_OBJ_FLAG_HIDDEN);
    else lv_obj_add_flag(live.paused_text, LV_OBJ_FLAG_HIDDEN);

    // Pause only exists once there are compressions to pause.
    const bool can_pause = engine->cpr_started && !engine->rosc_achieved &&
                           !engine->ended && !engine->in_pulse_check;
    if (can_pause) lv_obj_remove_flag(live.pause_button, LV_OBJ_FLAG_HIDDEN);
    else lv_obj_add_flag(live.pause_button, LV_OBJ_FLAG_HIDDEN);

    // The pulse check offers itself when the cycle is up — the one thing the
    // algorithm wants next, rather than another control to ignore.
    const bool check_due = engine->cpr_started && !engine->in_pulse_check &&
                           !engine->rosc_achieved && !engine->ended && cycle <= 0;
    if (check_due) lv_obj_remove_flag(live.pulse_button, LV_OBJ_FLAG_HIDDEN);
    else lv_obj_add_flag(live.pulse_button, LV_OBJ_FLAG_HIDDEN);

    // Hands off: the middle of the screen becomes the check itself.
    lv_obj_t *const check_parts[] = { live.check_title, live.check_clock,
                                      live.check_hint, live.check_resume, live.check_found };
    for (size_t i = 0; i < sizeof check_parts / sizeof check_parts[0]; i++) {
        if (engine->in_pulse_check) lv_obj_remove_flag(check_parts[i], LV_OBJ_FLAG_HIDDEN);
        else lv_obj_add_flag(check_parts[i], LV_OBJ_FLAG_HIDDEN);
    }
    if (engine->in_pulse_check) {
        const cr_ms_t held = cr_engine_pulse_check_elapsed(engine, now);
        const bool over = held >= CR_SEC(10);   // the hands-off target
        cr_format_clock(buf, sizeof buf, held);
        lv_label_set_text(live.check_clock, buf);
        lv_obj_set_style_text_color(live.check_clock,
                                    lv_color_hex(over ? CR_THEME_MED : CR_THEME_TEXT), 0);
        lv_label_set_text(live.check_hint, over ? "over 10 s — resume compressions"
                                               : "hands off — check pulse & rhythm");
        lv_obj_set_style_text_color(live.check_hint,
                                    lv_color_hex(over ? CR_THEME_MED : CR_THEME_TEXT_DIM), 0);
        // The countdown and the drug line would show through the middle.
        lv_obj_add_flag(live.countdown, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(live.drug_line, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(live.cycle_chip, LV_OBJ_FLAG_HIDDEN);
    } else if (!rosc) {
        lv_obj_remove_flag(live.drug_line, LV_OBJ_FLAG_HIDDEN);
        lv_obj_remove_flag(live.cycle_chip, LV_OBJ_FLAG_HIDDEN);
    } else {
        lv_obj_add_flag(live.drug_line, LV_OBJ_FLAG_HIDDEN);
    }

    // The chips around the ring.
    cr_med_chip_t med_chips[6];
    size_t chip_count = cr_session_med_chips(&engine->session, CR_ID_EPI, med_chips,
                                             cr_screen.chip_count < 6 ? cr_screen.chip_count : 6);
    for (uint8_t i = 0; i < cr_screen.chip_count && i < 6; i++) {
        if (live.chips[i].root == NULL) continue;
        if (i >= chip_count) {
            lv_obj_add_flag(live.chips[i].root, LV_OBJ_FLAG_HIDDEN);
            continue;
        }
        char abbrev[16];
        cr_chip_abbreviation(abbrev, sizeof abbrev, med_chips[i].title);
        lv_label_set_text_fmt(live.chips[i].name, "%s ×%d", abbrev, (int)med_chips[i].count);
        lv_obj_set_style_text_color(live.chips[i].name, lv_color_hex(med_chips[i].color), 0);
        cr_format_clock(buf, sizeof buf, now - med_chips[i].since);
        lv_label_set_text(live.chips[i].clock, buf);
        lv_obj_remove_flag(live.chips[i].root, LV_OBJ_FLAG_HIDDEN);
    }

    // Text that changes width has to be re-centred, or "-10:05" drifts off
    // the centre "0:59" was placed on.
    recentre_all();

    // The inner ring only exists once a dose has been given: a countdown for
    // a med nobody has given yet reads as a standing order.
    if (epi != NULL && !rosc && cr_engine_interval_is_running(engine, epi)) {
        const cr_ms_t left = cr_engine_interval_remaining(engine, epi, now);
        int32_t value = 0;
        if (epi->duration_ms > 0 && left > 0) value = (int32_t)(left * 1000 / epi->duration_ms);
        lv_arc_set_value(live.drug_ring, value);
        lv_obj_set_style_arc_color(live.drug_ring, lv_color_hex(CR_THEME_MED), LV_PART_INDICATOR);
        lv_obj_remove_flag(live.drug_ring, LV_OBJ_FLAG_HIDDEN);
    } else {
        lv_obj_add_flag(live.drug_ring, LV_OBJ_FLAG_HIDDEN);
    }

    // The timers list and the handoff card show live numbers ("last epi 1:40
    // ago"), so they have to keep up — once a second, not every frame, and
    // holding the scroll position, because rebuilding the rows under a finger
    // that is scrolling snaps the list back to the top. The LOG is deliberately
    // not in here: the watch hands it a copy of the events, so it is a snapshot
    // of the moment it was opened, and undo refreshes it itself.
    static cr_ms_t sheet_refreshed_at;
    if (sheet.open && sheet.mode != SHEET_LOG && now - sheet_refreshed_at >= CR_SEC(1)) {
        sheet_refreshed_at = now;
        const int32_t scroll = lv_obj_get_scroll_y(sheet.list);
        sheet_refresh();
        lv_obj_scroll_to_y(sheet.list, scroll, LV_ANIM_OFF);
    }

    // Measure, don't eyeball. The boot dump proves where the ROSC stack WOULD
    // land, but it is hidden then; this prints what a real pulse-found actually
    // put on the glass, once, the first time it happens.
    static bool rosc_dumped;
    if (rosc && !rosc_dumped) {
        rosc_dumped = true;
        cr_probe_dump(live.root, "post-ROSC layout");
    }
}
