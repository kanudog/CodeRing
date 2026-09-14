// ui_flow.c — home, and the setup that precedes a code.
//
// The order is Sebastian's, and deliberate (watch, 2026-08-22): setup starts
// at WEIGHT, not at a protocol picker. You rarely know the rhythm at t=0,
// one scenario spans several types, and nothing about the timers depends on
// which one is chosen — so the protocol is a label you set when you actually
// know it, and the weight is the thing every dose needs.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "esp_log.h"
#include "lvgl.h"

#include "cr_defaults.h"
#include "cr_engine.h"
#include "cr_layout.h"
#include "cr_patient.h"
#include "cr_theme.h"
#include "fonts/cr_fonts.h"
#include "icons/cr_icons.h"
#include "ui_flow.h"
#include "ui_probe.h"
#include "ui_screen.h"

static cr_engine_t *engine;
static cr_ms_t (*clock_ms)(void);

static lv_obj_t *home_screen;
static lv_obj_t *weight_screen;
static lv_obj_t *weight_readout;
static lv_obj_t *weight_source_label;

/// What the setup is building. Starts where the watch's dial starts.
static double weight_kg = 10.0;
static cr_weight_source_t weight_source = CR_WEIGHT_MANUAL;
static char weight_zone[8];
/// Digits typed since the last clear; empty means the dial value stands.
static char typed[8];

static lv_obj_t *label_at(lv_obj_t *parent, const char *text, uint32_t color,
                          const lv_font_t *font, int32_t x, int32_t y, int32_t w)
{
    lv_obj_t *label = lv_label_create(parent);
    lv_label_set_text(label, text);
    lv_obj_set_style_text_color(label, lv_color_hex(color), 0);
    lv_obj_set_style_text_font(label, font, 0);
    lv_obj_set_style_text_align(label, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_width(label, w);
    lv_obj_set_pos(label, x, y);
    return label;
}

static lv_obj_t *button_at(lv_obj_t *parent, int32_t x, int32_t y, int32_t w, int32_t h,
                           uint32_t border, lv_event_cb_t handler, void *data, const char *probe)
{
    lv_obj_t *button = lv_button_create(parent);
    lv_obj_set_size(button, w, h);
    lv_obj_set_pos(button, x, y);
    lv_obj_set_style_radius(button, h / 3, 0);
    lv_obj_set_style_bg_color(button, lv_color_hex(CR_THEME_SURFACE_HI), 0);
    lv_obj_set_style_border_color(button, lv_color_hex(border), 0);
    lv_obj_set_style_border_width(button, 2, 0);
    lv_obj_set_style_shadow_width(button, 0, 0);
    if (handler != NULL) lv_obj_add_event_cb(button, handler, LV_EVENT_CLICKED, data);
    if (probe != NULL) cr_probe_name(button, probe);
    return button;
}

// MARK: - Weight

static void refresh_weight(void)
{
    // LVGL's own printf is built without float support, so "%.1f" renders a
    // bare "f". Format it here instead.
    char text[24];
    snprintf(text, sizeof text, "%.1f kg", weight_kg);
    lv_label_set_text(weight_readout, text);
    switch (weight_source) {
    case CR_WEIGHT_BROSELOW: {
        char source[32];
        snprintf(source, sizeof source, "BROSELOW · %s", weight_zone);
        lv_label_set_text(weight_source_label, source);
        break;
    }
    case CR_WEIGHT_AGE_ESTIMATE:
        lv_label_set_text(weight_source_label, "ESTIMATED FROM AGE");
        break;
    default:
        lv_label_set_text(weight_source_label, "ENTERED MANUALLY");
        break;
    }
}

/// Typing replaces the value rather than nudging it: mid-code you know the
/// number you want, and a dial that has to be spun there is slower.
static const char *TAG = "flow";

/// Switching screens from inside a button's own handler leaves the input
/// device latched on the button that was pressed — it no longer belongs to
/// the visible screen, so every later touch is routed nowhere and the new
/// screen looks dead. Release the touch first, then swap.
static void load_screen(lv_obj_t *screen)
{
    lv_indev_t *indev = lv_indev_active();
    if (indev != NULL) lv_indev_wait_release(indev);
    lv_screen_load(screen);
}

static void on_screen_press(lv_event_t *event)
{
    lv_indev_t *indev = lv_indev_active();
    lv_point_t p = { 0, 0 };
    if (indev != NULL) lv_indev_get_point(indev, &p);
    lv_obj_t *target = lv_event_get_target(event);
    const char *name = lv_obj_get_user_data(target);
    ESP_LOGI(TAG, "press at (%d,%d) landed on %s", (int)p.x, (int)p.y,
             name ? name : "(unnamed)");
}

static void on_key(lv_event_t *event)
{
    const char *key = lv_event_get_user_data(event);
    ESP_LOGI(TAG, "key '%s'", key);
    size_t len = strlen(typed);

    if (strcmp(key, "<") == 0) {
        if (len > 0) typed[len - 1] = '\0';
    } else if (len + 1 < sizeof typed) {
        if (strcmp(key, ".") == 0 && strchr(typed, '.') != NULL) return;   // one point only
        typed[len] = key[0];
        typed[len + 1] = '\0';
    }

    if (typed[0] == '\0') {
        weight_kg = 10.0;
    } else {
        weight_kg = strtod(typed, NULL);
    }
    // The dosing range the watch's dial allows.
    if (weight_kg > 150.0) { weight_kg = 150.0; snprintf(typed, sizeof typed, "150"); }
    weight_source = CR_WEIGHT_MANUAL;
    weight_zone[0] = '\0';
    refresh_weight();
}

static void on_broselow(lv_event_t *event)
{
    const cr_broselow_zone_t *zone = lv_event_get_user_data(event);
    ESP_LOGI(TAG, "broselow %s", zone->name);
    weight_kg = cr_broselow_mid_kg(zone);
    weight_source = CR_WEIGHT_BROSELOW;
    snprintf(weight_zone, sizeof weight_zone, "%s", zone->name);
    typed[0] = '\0';
    refresh_weight();
}

/// GO. The code clock starts HERE, which is why the engine is built at this
/// moment rather than at boot.
static void on_start_code(lv_event_t *event)
{
    (void)event;
    cr_patient_t patient;
    memset(&patient, 0, sizeof patient);
    patient.weight_kg = weight_kg;
    patient.source = weight_source;
    snprintf(patient.broselow_zone_id, sizeof patient.broselow_zone_id, "%s", weight_zone);

    // Cardiac Arrest by default; the protocol is a label, set from Adjust
    // once the rhythm is actually known.
    cr_engine_init(engine, &cr_protocol_pals_arrest, &cr_pals_drug_set,
                   cr_builtin_events, cr_builtin_event_count,
                   &patient, clock_ms(), "DEVICE-0001", "codering-esp32");
    ui_tick();
    load_screen(ui_live_screen());
}

static void on_open_setup(lv_event_t *event)
{
    (void)event;
    typed[0] = '\0';
    refresh_weight();
    load_screen(weight_screen);
}

static void on_home(lv_event_t *event)
{
    (void)event;
    ESP_LOGI(TAG, "back to home");
    load_screen(home_screen);
}

static void build_weight(void)
{
    weight_screen = lv_obj_create(NULL);
    lv_obj_set_style_bg_color(weight_screen, lv_color_hex(CR_THEME_BG), 0);
    lv_obj_remove_flag(weight_screen, LV_OBJ_FLAG_SCROLLABLE);
    cr_probe_name(weight_screen, "setup.weight");
    // Every press on this screen is logged with where it landed — enough to
    // tell a hit-testing problem from a handler that never ran.
    lv_obj_add_event_cb(weight_screen, on_screen_press, LV_EVENT_PRESSED, NULL);

    // Right-aligned: BACK owns the top-left corner and was covering this.
    lv_obj_t *title = label_at(weight_screen, "PATIENT WEIGHT", CR_THEME_TEXT_DIM,
                               &cr_font_16, 0, 44, 370);
    lv_obj_set_style_text_align(title, LV_TEXT_ALIGN_RIGHT, 0);
    weight_readout = label_at(weight_screen, "10.0 kg", CR_THEME_TEXT, &cr_font_48, 0, 64, 370);
    lv_obj_set_style_text_align(weight_readout, LV_TEXT_ALIGN_RIGHT, 0);
    weight_source_label = label_at(weight_screen, "", CR_THEME_TEXT_DIM, &cr_font_16, 0, 122, 370);
    lv_obj_set_style_text_align(weight_source_label, LV_TEXT_ALIGN_RIGHT, 0);

    // Broselow: the fastest path when the tape is already under the patient.
    for (size_t i = 0; i < cr_broselow_zone_count; i++) {
        const cr_broselow_zone_t *zone = &cr_broselow_zones[i];
        int32_t x = 20 + (int32_t)i * 41;
        lv_obj_t *chip = button_at(weight_screen, x, 146, 36, 36, zone->color,
                                   on_broselow, (void *)zone, NULL);
        lv_obj_set_style_radius(chip, LV_RADIUS_CIRCLE, 0);
        lv_obj_set_style_bg_color(chip, lv_color_hex(zone->color), 0);
        lv_obj_set_style_bg_opa(chip, LV_OPA_70, 0);
    }

    // Keypad. Three columns, four rows — a known weight is two taps.
    static const char *const keys[12] = { "1", "2", "3", "4", "5", "6",
                                          "7", "8", "9", ".", "0", "<" };
    for (size_t i = 0; i < 12; i++) {
        int32_t col = (int32_t)(i % 3), row = (int32_t)(i / 3);
        lv_obj_t *key = button_at(weight_screen, 44 + col * 110, 192 + row * 56, 96, 50,
                                  CR_THEME_SURFACE_HI, on_key, (void *)keys[i], NULL);
        lv_obj_t *label = lv_label_create(key);
        // LV_SYMBOL_* lives in LVGL's built-in font; ours replaced it, so a
        // symbol here renders as an empty box. Plain text instead.
        lv_label_set_text(label, strcmp(keys[i], "<") == 0 ? "DEL" : keys[i]);
        lv_obj_set_style_text_color(label, lv_color_hex(CR_THEME_TEXT), 0);
        lv_obj_set_style_text_font(label, &cr_font_28, 0);
        lv_obj_center(label);
    }

    // Below the keypad (which now ends at 412) and inside the bottom corner
    // arcs. It used to sit ON the last keypad row and swallow those taps.
    lv_obj_t *start = button_at(weight_screen, 75, 424, 260, 50, CR_THEME_ROSC,
                                on_start_code, NULL, "setup.start");
    lv_obj_t *start_label = lv_label_create(start);
    lv_label_set_text(start_label, "START CODE");
    lv_obj_set_style_text_color(start_label, lv_color_hex(CR_THEME_ROSC), 0);
    lv_obj_set_style_text_font(start_label, &cr_font_16, 0);
    lv_obj_center(start_label);

    // The corner is curved, so a button tucked right into it is half off the
    // glass. Bigger, and moved inside the arc.
    lv_obj_t *back = button_at(weight_screen, 40, 56, 88, 56, CR_THEME_TEXT_DIM,
                               on_home, NULL, "setup.back");
    lv_obj_t *back_label = lv_label_create(back);
    lv_label_set_text(back_label, "BACK");
    lv_obj_set_style_text_color(back_label, lv_color_hex(CR_THEME_TEXT), 0);
    lv_obj_set_style_text_font(back_label, &cr_font_16, 0);
    lv_obj_center(back_label);
}

// MARK: - Home

static void build_home(void)
{
    home_screen = lv_obj_create(NULL);
    lv_obj_set_style_bg_color(home_screen, lv_color_hex(CR_THEME_BG), 0);
    lv_obj_remove_flag(home_screen, LV_OBJ_FLAG_SCROLLABLE);
    cr_probe_name(home_screen, "home");

    label_at(home_screen, "CODERING", CR_THEME_TEXT_DIM, &cr_font_16, 0, 70, 410);

    // The bullseye: START CODE front and centre, Recent and Settings tucked
    // under its lower corners.
    lv_obj_t *start = lv_button_create(home_screen);
    lv_obj_set_size(start, 210, 210);
    lv_obj_set_pos(start, 100, 118);
    lv_obj_set_style_radius(start, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_bg_color(start, lv_color_hex(CR_THEME_CPR), 0);
    lv_obj_set_style_shadow_width(start, 0, 0);
    lv_obj_add_event_cb(start, on_open_setup, LV_EVENT_CLICKED, NULL);
    cr_probe_name(start, "home.start");

    const lv_image_dsc_t *bolt = cr_icon("bolt.heart.fill");
    if (bolt != NULL) {
        lv_obj_t *icon = lv_image_create(start);
        lv_image_set_src(icon, bolt);
        lv_obj_set_style_image_recolor(icon, lv_color_hex(CR_THEME_BG), 0);
        lv_obj_set_style_image_recolor_opa(icon, LV_OPA_COVER, 0);
        lv_obj_align(icon, LV_ALIGN_CENTER, 0, -34);
    }
    lv_obj_t *start_label = lv_label_create(start);
    lv_label_set_text(start_label, "START\nCODE");
    lv_obj_set_style_text_align(start_label, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_style_text_color(start_label, lv_color_hex(CR_THEME_BG), 0);
    lv_obj_set_style_text_font(start_label, &cr_font_28, 0);
    lv_obj_align(start_label, LV_ALIGN_CENTER, 0, 34);

    // Recent and Settings: both need storage to be worth opening, so they
    // say so rather than opening an empty screen (M5).
    const struct { const char *symbol; const char *title; int32_t x; } orbit[] = {
        { "clock.arrow.circlepath", "Recent", 42 },
        { "gearshape.fill", "Settings", 246 },
    };
    for (size_t i = 0; i < 2; i++) {
        lv_obj_t *button = lv_button_create(home_screen);
        lv_obj_set_size(button, 122, 92);
        lv_obj_set_pos(button, orbit[i].x, 352);
        lv_obj_set_style_radius(button, 24, 0);
        lv_obj_set_style_bg_color(button, lv_color_hex(CR_THEME_SURFACE), 0);
        lv_obj_set_style_shadow_width(button, 0, 0);
        cr_probe_name(button, orbit[i].title);

        const lv_image_dsc_t *dsc = cr_icon(orbit[i].symbol);
        if (dsc != NULL) {
            lv_obj_t *icon = lv_image_create(button);
            lv_image_set_src(icon, dsc);
            lv_obj_set_style_image_recolor(icon, lv_color_hex(CR_THEME_TEXT_DIM), 0);
            lv_obj_set_style_image_recolor_opa(icon, LV_OPA_COVER, 0);
            lv_image_set_scale(icon, 160);
            lv_obj_align(icon, LV_ALIGN_CENTER, 0, -14);
        }
        lv_obj_t *label = lv_label_create(button);
        lv_label_set_text(label, orbit[i].title);
        lv_obj_set_style_text_color(label, lv_color_hex(CR_THEME_TEXT_DIM), 0);
        lv_obj_set_style_text_font(label, &cr_font_16, 0);
        lv_obj_align(label, LV_ALIGN_CENTER, 0, 24);
    }
}

void ui_flow_create(cr_engine_t *e, cr_ms_t (*clock)(void))
{
    engine = e;
    clock_ms = clock;
    build_home();
    build_weight();
    refresh_weight();
}

void ui_flow_show_home(void)
{
    lv_screen_load(home_screen);   // at boot; no touch is in flight yet
}
