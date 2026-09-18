// ui_flow.c — home, the setup that precedes a code, and the debrief after it.
//
// The order is Sebastian's, and deliberate (watch, 2026-08-22): setup starts
// at WEIGHT, not at a protocol picker. You rarely know the rhythm at t=0,
// one scenario spans several types, and nothing about the timers depends on
// which one is chosen — so the protocol is a label you set when you actually
// know it, and the weight is the thing every dose needs.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "esp_heap_caps.h"
#include "esp_log.h"
#include "lvgl.h"

#include "cr_defaults.h"
#include "cr_engine.h"
#include "cr_rtc.h"
#include "cr_layout.h"
#include "cr_clock.h"
#include "cr_patient.h"
#include "cr_session.h"
#include "cr_settings.h"
#include "cr_text.h"
#include "cr_theme.h"
#include "fonts/cr_fonts.h"
#include "icons/cr_icons.h"
#include "cr_audio.h"
#include "session_store.h"
#include "settings_store.h"
#include "wifi_link.h"
#include "ui_flow.h"
#include "ui_probe.h"
#include "ui_screen.h"

static cr_engine_t *engine;
static cr_ms_t (*clock_ms)(void);

static lv_obj_t *home_screen;
static lv_obj_t *weight_screen;
static lv_obj_t *weight_readout;
static lv_obj_t *weight_source_label;
static lv_obj_t *confirm_screen;
static lv_obj_t *protocol_screen;
static lv_obj_t *age_screen;
static lv_obj_t *age_readout;
static lv_obj_t *age_estimate_label;
static lv_obj_t *summary_screen;
static lv_obj_t *summary_banner, *summary_banner_label, *summary_list, *summary_when;
static lv_obj_t *summary_done_label;
static lv_obj_t *recents_screen, *recents_list, *recents_empty;
static lv_obj_t *settings_screen, *settings_list;

/// The live settings. Loaded once at boot, written back on every change —
/// there is no Save button, because a settings screen you can leave without
/// committing is a settings screen that lies about what the device will do.
static cr_settings_t settings;

/// Which session the summary is showing. The live one when a code has just
/// ended, or a copy loaded from flash when browsing Recents — the watch does
/// exactly this, reusing SummaryView for both.
static const cr_session_t *summary_session;
/// Where DONE goes back to: home after a code, the list when browsing.
static bool summary_from_recents;
/// A loaded code lives here rather than on a stack: it is ~96 kB.
EXT_RAM_BSS_ATTR static cr_session_t loaded_session;

static void show_recents(void);
static void on_summary_done(lv_event_t *event);

/// The clear-everything confirmation, on the Recents screen. Saved codes are
/// the only copy — nothing syncs them anywhere — so this asks, for the same
/// reason ending a code does.
static lv_obj_t *wipe_confirm;
static lv_obj_t *chip_protocol_value;
static lv_obj_t *chip_weight_value;
static lv_obj_t *chip_age_value;

/// Optional, and never blocks GO: the record can carry an age, and the APLS
/// estimate is there when nobody knows the weight.
static int age_months = -1;
/// Months for infants, years for everyone else — typing "5" should be able
/// to mean either.
static bool age_in_years;
/// A label, not a mode: nothing about the timers depends on which protocol
/// is chosen, so it can be set once the rhythm is actually known.
static const cr_protocol_t *chosen_protocol = &cr_protocol_pals_arrest;

/// What the setup is building. Starts where the watch's dial starts.
static double weight_kg = 10.0;
static cr_weight_source_t weight_source = CR_WEIGHT_MANUAL;
static char weight_zone[8];
/// Digits typed since the last clear; empty means the starting value stands.
static char typed[8];
static bool typing_age;

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
/// screen looks dead. The input device has to be made to forget that object.
///
/// It must be lv_indev_reset, NOT lv_indev_wait_release. wait_release is for a
/// finger that is still DOWN, and LV_EVENT_CLICKED fires on RELEASE — so it
/// always latched, and LVGL spends the whole of the next press clearing the
/// flag:
///
///     if (indev->wait_until_release) { act_obj = NULL; wait_until_release = 0; }
///     indev_obj_act = indev->pointer.act_obj;    // NULL — that press does nothing
///
/// Every button on every screen therefore needed two taps, and only the first
/// tap after boot worked, because nothing had swapped a screen yet. Measured on
/// the wrist: the touch log showed a DOWN/UP landing on the right coordinates
/// and no handler firing, then an identical one that worked.
/// What is left to draw with. The display's SPI transfers need DMA-capable
/// INTERNAL memory, and when that runs out the panel does not crash — it
/// simply stops flushing, leaving bands of the previous screen on the glass.
/// That failure is invisible from the outside, so every screen change says
/// where memory stands.
static void log_heap(const char *where)
{
    ESP_LOGI(TAG, "%s — internal %d kB, DMA-capable %d kB, PSRAM %d kB",
             where,
             (int)(heap_caps_get_free_size(MALLOC_CAP_INTERNAL) / 1024),
             (int)(heap_caps_get_free_size(MALLOC_CAP_DMA) / 1024),
             (int)(heap_caps_get_free_size(MALLOC_CAP_SPIRAM) / 1024));
}

static void load_screen(lv_obj_t *screen)
{
    lv_indev_t *indev = lv_indev_active();
    if (indev != NULL) lv_indev_reset(indev, NULL);
    lv_screen_load(screen);
    const char *name = lv_obj_get_user_data(screen);
    log_heap(name != NULL ? name : "screen");
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

static void refresh_age(void);

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

    if (typing_age) {
        const int entered = typed[0] == '\0' ? -1 : (int)strtol(typed, NULL, 10);
        age_months = entered < 0 ? -1 : (age_in_years ? entered * 12 : entered);
        if (age_months > 216) {                       // 18 years, the paediatric scope
            age_months = 216;
            snprintf(typed, sizeof typed, age_in_years ? "18" : "216");
        }
        refresh_age();
        return;
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

    if (age_months >= 0) {
        patient.has_age = true;
        patient.age_months = (int16_t)age_months;
    }

    // The user's timer overrides apply to the code about to start, which is
    // the whole point of having them.
    const cr_protocol_t configured = cr_protocol_applying(
        chosen_protocol, settings.cycle_override_ms, settings.interval_override_ms);
    cr_engine_init(engine, &configured, &cr_pals_drug_set,
                   cr_builtin_events, cr_builtin_event_count,
                   &patient, clock_ms(), "DEVICE-0001", "codering-esp32");
    ui_code_started();
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

/// A labelled value the wearer can tap to change — PROTOCOL, WEIGHT, AGE.
#define CHIP_W 180
#define CHIP_H 92

static lv_obj_t *confirm_chip(lv_obj_t *parent, const char *eyebrow, uint32_t color,
                              int32_t cx, int32_t cy, lv_event_cb_t handler, const char *probe)
{
    lv_obj_t *chip = button_at(parent, cx - CHIP_W / 2, cy - CHIP_H / 2,
                               CHIP_W, CHIP_H, color, handler, NULL, probe);
    lv_obj_set_style_radius(chip, CHIP_H / 2, 0);     // fully rounded
    lv_obj_set_style_pad_all(chip, 6, 0);

    // Two lines with real spacing. They used to be aligned to the chip's own
    // edges, which put them on top of each other once the font's line height
    // was taken into account.
    lv_obj_t *label = lv_label_create(chip);
    lv_label_set_text(label, eyebrow);
    lv_obj_set_style_text_color(label, lv_color_hex(color), 0);
    lv_obj_set_style_text_font(label, &cr_font_16, 0);
    lv_obj_align(label, LV_ALIGN_CENTER, 0, -20);

    lv_obj_t *value = lv_label_create(chip);
    lv_label_set_text(value, "—");
    lv_obj_set_style_text_color(value, lv_color_hex(CR_THEME_TEXT), 0);
    lv_obj_set_style_text_font(value, &cr_font_28, 0);
    lv_obj_align(value, LV_ALIGN_CENTER, 0, 16);
    return value;
}

static void refresh_confirm(void)
{
    lv_label_set_text(chip_protocol_value, chosen_protocol->short_name);

    char text[24];
    snprintf(text, sizeof text, "%.1f kg", weight_kg);
    lv_label_set_text(chip_weight_value, text);

    // Italic-equivalent: dim "tap" until it is set, so an unknown age reads
    // as optional rather than missing.
    if (age_months < 0) {
        lv_label_set_text(chip_age_value, "tap");
        lv_obj_set_style_text_color(chip_age_value, lv_color_hex(CR_THEME_TEXT_DIM), 0);
    } else {
        if (age_months < 24) snprintf(text, sizeof text, "%d mo", age_months);
        else snprintf(text, sizeof text, "%d yr", age_months / 12);
        lv_label_set_text(chip_age_value, text);
        lv_obj_set_style_text_color(chip_age_value, lv_color_hex(CR_THEME_TEXT), 0);
    }
}

static lv_obj_t *age_unit_buttons[2];

static void refresh_age(void)
{
    char text[40];
    // The chosen unit reads as selected; the other is just available.
    for (size_t i = 0; i < 2; i++) {
        if (age_unit_buttons[i] == NULL) continue;
        const bool on = (i == 1) == age_in_years;
        lv_obj_set_style_border_color(age_unit_buttons[i],
                                      lv_color_hex(on ? CR_THEME_ACCESS : CR_THEME_SURFACE_HI), 0);
        lv_obj_set_style_bg_color(age_unit_buttons[i],
                                  lv_color_hex(on ? CR_THEME_SURFACE_HI : CR_THEME_SURFACE), 0);
    }

    if (age_months < 0) {
        lv_label_set_text(age_readout, "—");
        lv_label_set_text(age_estimate_label, "");
        return;
    }
    if (age_months < 24) snprintf(text, sizeof text, "%d mo", age_months);
    else snprintf(text, sizeof text, "%d yr %d mo", age_months / 12, age_months % 12);
    lv_label_set_text(age_readout, text);
    snprintf(text, sizeof text, "APLS estimate: %.1f kg", cr_weight_for_age_months(age_months));
    lv_label_set_text(age_estimate_label, text);
}

static void on_show_confirm(lv_event_t *event)
{
    (void)event;
    refresh_confirm();
    load_screen(confirm_screen);
}

static void on_show_weight(lv_event_t *event)
{
    (void)event;
    typing_age = false;
    typed[0] = '\0';
    refresh_weight();
    load_screen(weight_screen);
}

static void on_show_protocols(lv_event_t *event)
{
    (void)event;
    load_screen(protocol_screen);
}

static void on_pick_protocol(lv_event_t *event)
{
    chosen_protocol = lv_event_get_user_data(event);
    ESP_LOGI(TAG, "protocol %s", chosen_protocol->name);
    refresh_confirm();
    load_screen(confirm_screen);
}

static void on_age_unit(lv_event_t *event)
{
    age_in_years = lv_event_get_user_data(event) != NULL;
    // Re-read what was typed in the new unit rather than silently keeping a
    // number that now means something different.
    const int entered = typed[0] == '\0' ? -1 : (int)strtol(typed, NULL, 10);
    age_months = entered < 0 ? -1 : (age_in_years ? entered * 12 : entered);
    if (age_months > 216) age_months = 216;
    refresh_age();
}

static void on_show_age(lv_event_t *event)
{
    (void)event;
    typing_age = true;
    typed[0] = '\0';
    refresh_age();
    load_screen(age_screen);
}

/// The fallback path: no scale, no tape, but somebody knows roughly how old
/// the child is.
static void on_use_estimate(lv_event_t *event)
{
    (void)event;
    if (age_months >= 0) {
        weight_kg = cr_weight_for_age_months(age_months);
        weight_source = CR_WEIGHT_AGE_ESTIMATE;
        weight_zone[0] = '\0';
        refresh_weight();
    }
    refresh_confirm();
    load_screen(confirm_screen);
}

/// The numeric keypad, shared by the weight and age screens.
static void build_keypad(lv_obj_t *screen, int32_t top)
{
    static const char *const keys[12] = { "1", "2", "3", "4", "5", "6",
                                          "7", "8", "9", ".", "0", "<" };
    for (size_t i = 0; i < 12; i++) {
        int32_t col = (int32_t)(i % 3), row = (int32_t)(i / 3);
        lv_obj_t *key = button_at(screen, 44 + col * 110, top + row * 56, 96, 50,
                                  CR_THEME_SURFACE_HI, on_key, (void *)keys[i], NULL);
        lv_obj_t *label = lv_label_create(key);
        // LV_SYMBOL_* lives in LVGL's built-in font, which ours replaced, so
        // a symbol here renders as an empty box. Plain text instead.
        lv_label_set_text(label, strcmp(keys[i], "<") == 0 ? "DEL" : keys[i]);
        lv_obj_set_style_text_color(label, lv_color_hex(CR_THEME_TEXT), 0);
        lv_obj_set_style_text_font(label, &cr_font_28, 0);
        lv_obj_center(label);
    }
}

static void build_confirm(void)
{
    confirm_screen = lv_obj_create(NULL);
    lv_obj_set_style_bg_color(confirm_screen, lv_color_hex(CR_THEME_BG), 0);
    lv_obj_remove_flag(confirm_screen, LV_OBJ_FLAG_SCROLLABLE);
    cr_probe_name(confirm_screen, "setup.confirm");

    lv_obj_t *back = button_at(confirm_screen, 40, 56, 88, 56, CR_THEME_TEXT_DIM,
                               on_show_weight, NULL, "confirm.back");
    lv_obj_t *back_label = lv_label_create(back);
    lv_label_set_text(back_label, "BACK");
    lv_obj_set_style_text_color(back_label, lv_color_hex(CR_THEME_TEXT), 0);
    lv_obj_set_style_text_font(back_label, &cr_font_16, 0);
    lv_obj_center(back_label);

    lv_obj_t *title = label_at(confirm_screen, "CONFIRM", CR_THEME_TEXT_DIM,
                              &cr_font_16, 0, 70, 370);
    lv_obj_set_style_text_align(title, LV_TEXT_ALIGN_RIGHT, 0);

    // Three chips orbiting GO, as on the watch: protocol upper-left, weight
    // upper-right, age below.
    chip_protocol_value = confirm_chip(confirm_screen, "PROTOCOL", CR_THEME_MED,
                                       112, 186, on_show_protocols, "chip.protocol");
    chip_weight_value = confirm_chip(confirm_screen, "WEIGHT", CR_THEME_AIRWAY,
                                     298, 186, on_show_weight, "chip.weight");
    chip_age_value = confirm_chip(confirm_screen, "AGE", CR_THEME_ACCESS,
                                  205, 438, on_show_age, "chip.age");

    // GO sits in the gap between them — 232 to 384, with ~40 px of air on
    // each side, so it never lands on a chip.
    lv_obj_t *go = lv_button_create(confirm_screen);
    lv_obj_set_size(go, 152, 152);
    lv_obj_set_pos(go, 129, 232);
    lv_obj_set_style_radius(go, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_bg_color(go, lv_color_hex(CR_THEME_ROSC), 0);
    lv_obj_set_style_shadow_width(go, 0, 0);
    lv_obj_add_event_cb(go, on_start_code, LV_EVENT_CLICKED, NULL);
    cr_probe_name(go, "confirm.go");
    lv_obj_t *go_label = lv_label_create(go);
    lv_label_set_text(go_label, "GO");
    lv_obj_set_style_text_color(go_label, lv_color_hex(CR_THEME_BG), 0);
    lv_obj_set_style_text_font(go_label, &cr_font_48, 0);
    lv_obj_center(go_label);
}

static void build_protocols(void)
{
    protocol_screen = lv_obj_create(NULL);
    lv_obj_set_style_bg_color(protocol_screen, lv_color_hex(CR_THEME_BG), 0);
    lv_obj_remove_flag(protocol_screen, LV_OBJ_FLAG_SCROLLABLE);
    cr_probe_name(protocol_screen, "setup.protocols");

    label_at(protocol_screen, "PROTOCOL", CR_THEME_TEXT_DIM, &cr_font_16, 0, 44, 410);

    // The five top-level choices. Nothing about the timers depends on this —
    // it is the label the record carries.
    for (size_t i = 0; i < cr_protocol_top_count && i < 5; i++) {
        const cr_protocol_t *proto = cr_protocol_tops[i];
        lv_obj_t *tile = button_at(protocol_screen, 45, 80 + (int32_t)i * 76, 320, 64,
                                   CR_THEME_MED, on_pick_protocol, (void *)proto, NULL);
        lv_obj_t *name = lv_label_create(tile);
        lv_label_set_text(name, proto->name);
        lv_obj_set_style_text_color(name, lv_color_hex(CR_THEME_TEXT), 0);
        lv_obj_set_style_text_font(name, &cr_font_28, 0);
        lv_obj_align(name, LV_ALIGN_LEFT_MID, 12, 0);

        lv_obj_t *short_name = lv_label_create(tile);
        lv_label_set_text(short_name, proto->short_name);
        lv_obj_set_style_text_color(short_name, lv_color_hex(CR_THEME_TEXT_DIM), 0);
        lv_obj_set_style_text_font(short_name, &cr_font_16, 0);
        lv_obj_align(short_name, LV_ALIGN_RIGHT_MID, -12, 0);
    }

    lv_obj_t *back = button_at(protocol_screen, 125, 456, 160, 40, CR_THEME_TEXT_DIM,
                               on_show_confirm, NULL, "protocols.back");
    lv_obj_t *back_label = lv_label_create(back);
    lv_label_set_text(back_label, "BACK");
    lv_obj_set_style_text_color(back_label, lv_color_hex(CR_THEME_TEXT), 0);
    lv_obj_set_style_text_font(back_label, &cr_font_16, 0);
    lv_obj_center(back_label);
}

static void build_age(void)
{
    age_screen = lv_obj_create(NULL);
    lv_obj_set_style_bg_color(age_screen, lv_color_hex(CR_THEME_BG), 0);
    lv_obj_remove_flag(age_screen, LV_OBJ_FLAG_SCROLLABLE);
    cr_probe_name(age_screen, "setup.age");

    lv_obj_t *title = label_at(age_screen, "AGE IN MONTHS", CR_THEME_TEXT_DIM,
                               &cr_font_16, 0, 44, 370);
    lv_obj_set_style_text_align(title, LV_TEXT_ALIGN_RIGHT, 0);
    age_readout = label_at(age_screen, "—", CR_THEME_TEXT, &cr_font_48, 0, 64, 370);
    lv_obj_set_style_text_align(age_readout, LV_TEXT_ALIGN_RIGHT, 0);
    age_estimate_label = label_at(age_screen, "", CR_THEME_ACCESS, &cr_font_16, 0, 122, 370);
    lv_obj_set_style_text_align(age_estimate_label, LV_TEXT_ALIGN_RIGHT, 0);

    lv_obj_t *back = button_at(age_screen, 40, 56, 88, 56, CR_THEME_TEXT_DIM,
                               on_show_confirm, NULL, "age.back");
    lv_obj_t *back_label = lv_label_create(back);
    lv_label_set_text(back_label, "BACK");
    lv_obj_set_style_text_color(back_label, lv_color_hex(CR_THEME_TEXT), 0);
    lv_obj_set_style_text_font(back_label, &cr_font_16, 0);
    lv_obj_center(back_label);

    // MONTHS / YEARS.
    const char *units[2] = { "MONTHS", "YEARS" };
    for (size_t i = 0; i < 2; i++) {
        age_unit_buttons[i] = button_at(age_screen, 45 + (int32_t)i * 165, 150, 155, 46,
                                        CR_THEME_SURFACE_HI, on_age_unit,
                                        i == 1 ? (void *)units : NULL, NULL);
        lv_obj_set_style_radius(age_unit_buttons[i], 23, 0);
        lv_obj_t *label = lv_label_create(age_unit_buttons[i]);
        lv_label_set_text(label, units[i]);
        lv_obj_set_style_text_color(label, lv_color_hex(CR_THEME_TEXT), 0);
        lv_obj_set_style_text_font(label, &cr_font_16, 0);
        lv_obj_center(label);
    }

    build_keypad(age_screen, 206);

    lv_obj_t *use = button_at(age_screen, 45, 438, 320, 48, CR_THEME_ACCESS,
                              on_use_estimate, NULL, "age.use");
    lv_obj_t *use_label = lv_label_create(use);
    lv_label_set_text(use_label, "USE ESTIMATE AS WEIGHT");
    lv_obj_set_style_text_color(use_label, lv_color_hex(CR_THEME_ACCESS), 0);
    lv_obj_set_style_text_font(use_label, &cr_font_16, 0);
    lv_obj_center(use_label);
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

    // A known weight is two taps.
    build_keypad(weight_screen, 192);

    // NEXT goes to confirm; SKIP launches with what is already set, because
    // a code does not wait for a form to be filled in.
    lv_obj_t *skip = button_at(weight_screen, 45, 424, 120, 50, CR_THEME_TEXT_DIM,
                               on_start_code, NULL, "setup.skip");
    lv_obj_t *skip_label = lv_label_create(skip);
    lv_label_set_text(skip_label, "SKIP");
    lv_obj_set_style_text_color(skip_label, lv_color_hex(CR_THEME_TEXT_DIM), 0);
    lv_obj_set_style_text_font(skip_label, &cr_font_16, 0);
    lv_obj_center(skip_label);

    lv_obj_t *start = button_at(weight_screen, 180, 424, 185, 50, CR_THEME_ROSC,
                                on_show_confirm, NULL, "setup.next");
    lv_obj_t *start_label = lv_label_create(start);
    lv_label_set_text(start_label, "NEXT");
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

// MARK: - Summary
//
// The debrief after End, and the counterpart of SummaryView: the numbers a
// code is reviewed by, then every drug with its count, then the whole log.
// It is built once and filled from the session each time it is shown — a
// finished code cannot change, so unlike the live screen it does not tick.

/// A label and a value on one line, the shape SummaryView's StatTile has.
static void summary_stat(const char *label, const char *value, uint32_t color)
{
    lv_obj_t *row = lv_obj_create(summary_list);
    lv_obj_set_size(row, 330, 46);
    lv_obj_set_style_bg_color(row, lv_color_hex(CR_THEME_SURFACE), 0);
    lv_obj_set_style_bg_opa(row, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(row, 0, 0);
    lv_obj_set_style_radius(row, 10, 0);
    lv_obj_set_style_pad_all(row, 0, 0);
    lv_obj_remove_flag(row, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_remove_flag(row, LV_OBJ_FLAG_CLICKABLE);

    lv_obj_t *caption = lv_label_create(row);
    lv_label_set_text(caption, label);
    lv_obj_set_style_text_color(caption, lv_color_hex(CR_THEME_TEXT_DIM), 0);
    lv_obj_set_style_text_font(caption, &cr_font_16, 0);
    lv_obj_align(caption, LV_ALIGN_LEFT_MID, 14, 0);

    lv_obj_t *text = lv_label_create(row);
    lv_label_set_text(text, value);
    lv_obj_set_style_text_color(text, lv_color_hex(color), 0);
    lv_obj_set_style_text_font(text, &cr_font_28, 0);
    lv_obj_align(text, LV_ALIGN_RIGHT_MID, -14, 0);
}

/// A plain line, for the med tally and the log.
static void summary_line(const char *text, uint32_t color, const lv_font_t *font)
{
    lv_obj_t *label = lv_label_create(summary_list);
    lv_label_set_text(label, text);
    lv_obj_set_style_text_color(label, lv_color_hex(color), 0);
    lv_obj_set_style_text_font(label, font, 0);
    lv_obj_set_style_text_align(label, LV_TEXT_ALIGN_LEFT, 0);
    lv_obj_set_width(label, 330);
    lv_label_set_long_mode(label, LV_LABEL_LONG_WRAP);
}

static void refresh_summary(void)
{
    const cr_session_t *s = summary_session != NULL ? summary_session : &engine->session;
    // A finished code is measured at its own end, not at now — otherwise a
    // code reopened a week later would report a week-long duration.
    const cr_ms_t as_of = (s->end != CR_TIME_NONE) ? s->end : clock_ms();
    cr_stats_t stats;
    cr_session_stats(s, as_of, &stats);

    // When it happened, which is the whole point of the Recents list.
    char when[40];
    const cr_civil_t c = cr_civil_from_epoch_s(s->start / 1000);
    cr_format_stamp(when, sizeof when, &c);
    lv_label_set_text(summary_when, when);
    lv_label_set_text(summary_done_label, summary_from_recents ? "BACK" : "DONE");

    const bool rosc = s->rosc != CR_TIME_NONE;
    lv_label_set_text(summary_banner_label, rosc ? "ROSC ACHIEVED" : "CODE ENDED");
    lv_obj_set_style_text_color(summary_banner_label,
                               lv_color_hex(rosc ? CR_THEME_BG : CR_THEME_TEXT), 0);
    lv_obj_set_style_bg_color(summary_banner,
                              lv_color_hex(rosc ? CR_THEME_ROSC : CR_THEME_SURFACE_HI), 0);

    lv_obj_clean(summary_list);
    char value[48], line[CR_TITLE_MAX + CR_DETAIL_MAX + 24];

    cr_format_clock(value, sizeof value, stats.total_ms);
    summary_stat("Duration", value, CR_THEME_TEXT);
    cr_format_percent(value, sizeof value, stats.cpr_fraction);
    summary_stat("CPR", value, CR_THEME_CPR);
    snprintf(value, sizeof value, "×%d", (int)stats.epi_count);
    summary_stat("Epi", value, CR_THEME_MED);
    snprintf(value, sizeof value, "×%d", (int)stats.shock_count);
    summary_stat("Shocks", value, CR_THEME_SHOCK);
    snprintf(value, sizeof value, "×%d", (int)stats.rhythm_check_count);
    summary_stat("Rhythm ✓", value, CR_THEME_RHYTHM);
    snprintf(value, sizeof value, "%d", (int)stats.pause_count);
    summary_stat("Pauses", value, CR_THEME_TEXT);
    // Both are "how long into the code", so they read as offsets (+m:ss), not
    // durations — the same distinction the watch draws with crOffset.
    if (stats.has_first_epi) {
        cr_format_offset(value, sizeof value, stats.seconds_to_first_epi);
        summary_stat("First epi", value, CR_THEME_MED);
    }
    if (stats.has_rosc) {
        cr_format_offset(value, sizeof value, stats.seconds_to_rosc);
        summary_stat("ROSC", value, CR_THEME_ROSC);
    }

    if (stats.med_count > 0) {
        summary_line("MEDS GIVEN", CR_THEME_TEXT_DIM, &cr_font_16);
        for (uint8_t i = 0; i < stats.med_count; i++) {
            snprintf(line, sizeof line, "%s  ×%d", stats.meds[i].title,
                     (int)stats.meds[i].count);
            summary_line(line, CR_THEME_TEXT, &cr_font_28);
        }
    }

    // The log, oldest first: a debrief is read forwards, unlike the live log
    // where you are checking what just happened.
    snprintf(line, sizeof line, "EVENT LOG · %d", (int)s->event_count);
    summary_line(line, CR_THEME_TEXT_DIM, &cr_font_16);
    for (uint16_t i = 0; i < s->event_count; i++) {
        const cr_event_t *ev = &s->events[i];
        char stamp[16];
        cr_format_offset(stamp, sizeof stamp, ev->offset_s);
        snprintf(line, sizeof line, "%s  %s%s%s", stamp, ev->title,
                 ev->detail[0] ? " — " : "", ev->detail);
        summary_line(line, cr_event_tint(ev), &cr_font_16);
    }

    if (engine->overflow) {
        summary_line("LOG FULL — later events were not recorded", CR_THEME_MED, &cr_font_16);
    }
    summary_line("Demo — not a medical device. Full timeline + PDF on iPhone.",
                 CR_THEME_TEXT_DIM, &cr_font_16);
}

static void build_summary(void)
{
    summary_screen = lv_obj_create(NULL);
    lv_obj_set_style_bg_color(summary_screen, lv_color_hex(CR_THEME_BG), 0);
    lv_obj_remove_flag(summary_screen, LV_OBJ_FLAG_SCROLLABLE);
    cr_probe_name(summary_screen, "summary");

    summary_banner = lv_obj_create(summary_screen);
    lv_obj_set_size(summary_banner, 300, 62);
    lv_obj_set_pos(summary_banner, 55, 50);
    lv_obj_set_style_radius(summary_banner, 20, 0);
    lv_obj_set_style_border_width(summary_banner, 0, 0);
    lv_obj_set_style_pad_all(summary_banner, 0, 0);
    lv_obj_remove_flag(summary_banner, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_remove_flag(summary_banner, LV_OBJ_FLAG_CLICKABLE);
    cr_probe_name(summary_banner, "summary.banner");
    summary_banner_label = lv_label_create(summary_banner);
    lv_obj_set_style_text_font(summary_banner_label, &cr_font_28, 0);
    lv_label_set_text(summary_banner_label, "CODE ENDED");
    lv_obj_center(summary_banner_label);

    summary_when = label_at(summary_screen, "", CR_THEME_TEXT_DIM, &cr_font_16, 0, 114, 410);

    // Narrower than the glass because the corners are curved, and scrolling:
    // a long code's log does not fit and must not be truncated.
    summary_list = lv_obj_create(summary_screen);
    lv_obj_set_size(summary_list, 340, 262);
    lv_obj_set_pos(summary_list, 35, 144);
    lv_obj_set_style_bg_opa(summary_list, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(summary_list, 0, 0);
    lv_obj_set_style_pad_all(summary_list, 0, 0);
    lv_obj_set_style_pad_row(summary_list, 6, 0);
    lv_obj_set_flex_flow(summary_list, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_scroll_dir(summary_list, LV_DIR_VER);
    cr_probe_name(summary_list, "summary.list");

    // Lifted clear of the bottom band, which this panel does not show in full
    // (the same reason the live screen's BOTTOM_LIFT exists).
    lv_obj_t *done = button_at(summary_screen, 105, 414, 200, 56, CR_THEME_CPR,
                               on_summary_done, NULL, "summary.done");
    summary_done_label = lv_label_create(done);
    lv_label_set_text(summary_done_label, "DONE");
    lv_obj_set_style_text_color(summary_done_label, lv_color_hex(CR_THEME_CPR), 0);
    lv_obj_set_style_text_font(summary_done_label, &cr_font_28, 0);
    lv_obj_center(summary_done_label);
}

static void on_summary_done(lv_event_t *event)
{
    (void)event;
    if (summary_from_recents) { show_recents(); return; }
    load_screen(home_screen);
}

void ui_flow_show_summary(void)
{
    // Persist FIRST, then draw. If the save is going to fail, the moment to
    // find out is while the screen still says what just happened — not when
    // the list turns out to be empty tomorrow.
    if (!store_save(&engine->session)) {
        ESP_LOGW(TAG, "this code was NOT saved");
    }
    summary_session = &engine->session;
    summary_from_recents = false;
    refresh_summary();
    load_screen(summary_screen);
    // The live screen's controls were proven at boot; these were not, and the
    // list is built from the session rather than from the table. Dump it once
    // so the debrief is measured too.
    static bool dumped;
    if (!dumped) {
        dumped = true;
        cr_probe_dump(summary_screen, "summary layout");
    }
}

// MARK: - Settings
//
// Every row writes through immediately. The protocol timer overrides are the
// ones that actually change behaviour mid-code, so they are shown as the
// SECONDS they are, not as a preference with a hidden unit.

static void refresh_settings(void);

/// Applies a changed setting to a running code as well as to the next one —
/// the timer lengths are the only ones that can matter while compressions are
/// happening, and a user who lengthens the cycle expects THIS cycle to follow.
static void settings_changed(void)
{
    settings_store_save(&settings);
    ui_settings_changed(&settings);
    if (engine != NULL) {
        const cr_protocol_t updated = cr_protocol_applying(
            &cr_protocol_pals_arrest, settings.cycle_override_ms, settings.interval_override_ms);
        cr_engine_change_protocol(engine, &updated);
    }
    refresh_settings();
}

static void on_toggle_cues(lv_event_t *e)
{
    (void)e; settings.cues_enabled = !settings.cues_enabled; settings_changed();
}
static void on_toggle_sound(lv_event_t *e)
{
    (void)e; settings.metronome_sound_on = !settings.metronome_sound_on; settings_changed();
}
static void on_toggle_screen(lv_event_t *e)
{
    (void)e; settings.keep_screen_on = !settings.keep_screen_on; settings_changed();
}
/// Cycles through the lengths a person would actually pick, then back to the
/// protocol's own. A stepper beats a dial here: there are four sensible
/// answers and no reason to let someone set 137 seconds.
static void on_cycle_length(lv_event_t *e)
{
    (void)e;
    static const cr_ms_t choices[] = { CR_TIME_NONE, CR_SEC(60), CR_SEC(90), CR_SEC(120),
                                       CR_SEC(180), CR_SEC(240) };
    size_t at = 0;
    for (size_t i = 0; i < sizeof choices / sizeof choices[0]; i++) {
        if (settings.cycle_override_ms == choices[i]) { at = i; break; }
    }
    settings.cycle_override_ms = choices[(at + 1) % (sizeof choices / sizeof choices[0])];
    settings_changed();
}

static void on_interval_length(lv_event_t *e)
{
    (void)e;
    static const cr_ms_t choices[] = { CR_TIME_NONE, CR_SEC(180), CR_SEC(240), CR_SEC(300) };
    size_t at = 0;
    for (size_t i = 0; i < sizeof choices / sizeof choices[0]; i++) {
        if (settings.interval_override_ms == choices[i]) { at = i; break; }
    }
    settings.interval_override_ms = choices[(at + 1) % (sizeof choices / sizeof choices[0])];
    settings_changed();
}

/// The TV link is OFF by default and toggled here. A SoftAP plus this AMOLED
/// is the most expensive thing this board can do to its battery, so it runs
/// when a display is actually wanted rather than all the time.
static void on_toggle_tv(lv_event_t *event)
{
    (void)event;
    if (wifi_link_running()) wifi_link_stop();
    else wifi_link_start(engine, clock_ms);
    // Remembered, so a permanently-installed display keeps working across a
    // reboot or a flat battery. Stored as what actually happened rather than
    // as what was asked for: if the radio refused to start, the setting should
    // not claim it is on.
    settings.tv_link_on = wifi_link_running();
    settings_store_save(&settings);
    refresh_settings();
}

/// Proves the speaker works, with one tap and no code running. C5, the middle
/// of the three metronome pitches.
static void on_test_tone(lv_event_t *event)
{
    (void)event;
    cr_audio_tone(cr_metronome_pitch_hz(CR_PITCH_MEDIUM), 120);
}

/// Nudges the clock. The RTC keeps time by itself, but nothing on this device
/// can tell it the RIGHT time — there is no network in the trauma bay and no
/// phone pairing yet — so minutes are adjustable by hand.
static void on_clock_nudge(lv_event_t *event)
{
    const int minutes = (int)(intptr_t)lv_event_get_user_data(event);
    cr_rtc_adjust_seconds(minutes * 60);
    refresh_settings();
}

static void settings_row(const char *label, const char *value, uint32_t colour,
                         lv_event_cb_t handler, void *data, const char *probe)
{
    lv_obj_t *row = lv_button_create(settings_list);
    lv_obj_set_size(row, 336, 66);
    lv_obj_set_style_radius(row, 14, 0);
    lv_obj_set_style_bg_color(row, lv_color_hex(CR_THEME_SURFACE), 0);
    lv_obj_set_style_shadow_width(row, 0, 0);
    lv_obj_set_style_pad_all(row, 0, 0);
    if (handler != NULL) lv_obj_add_event_cb(row, handler, LV_EVENT_CLICKED, data);
    if (probe != NULL) cr_probe_name(row, probe);

    lv_obj_t *name = lv_label_create(row);
    lv_label_set_text(name, label);
    lv_obj_set_style_text_color(name, lv_color_hex(CR_THEME_TEXT), 0);
    lv_obj_set_style_text_font(name, &cr_font_16, 0);
    lv_obj_align(name, LV_ALIGN_LEFT_MID, 16, 0);

    lv_obj_t *val = lv_label_create(row);
    lv_label_set_text(val, value);
    lv_obj_set_style_text_color(val, lv_color_hex(colour), 0);
    lv_obj_set_style_text_font(val, &cr_font_28, 0);
    lv_obj_align(val, LV_ALIGN_RIGHT_MID, -16, 0);
}

static void seconds_label(char *buf, size_t cap, cr_ms_t override, int fallback)
{
    if (override == CR_TIME_NONE) snprintf(buf, cap, "%d s", fallback);
    else snprintf(buf, cap, "%d s", (int)(override / 1000));
}

static void refresh_settings(void)
{
    // Every tap rebuilds the list, which resets the scroll — so a row below the
    // fold threw the screen back to the top the moment you touched it, and the
    // clock nudge was unusable. Keep the position across the rebuild.
    const int32_t scroll = lv_obj_get_scroll_y(settings_list);
    lv_obj_clean(settings_list);
    char value[24];

    // The TV link first: it is the row anyone comes to this screen looking for,
    // and it was buried below the fold on a list that gives no hint it scrolls.
    if (wifi_link_running()) {
        const int n = wifi_link_clients();
        if (n > 0) snprintf(value, sizeof value, "ON · %d", n);
        else snprintf(value, sizeof value, "ON · waiting");
    } else {
        snprintf(value, sizeof value, "OFF");
    }
    settings_row("TV link", value,
                 wifi_link_running() ? CR_THEME_ROSC : CR_THEME_TEXT_DIM,
                 on_toggle_tv, NULL, "set.tv");
    if (wifi_link_running()) {
        settings_row("   join", "codering-tv", CR_THEME_TEXT_DIM, NULL, NULL, NULL);
        settings_row("   then open", "192.168.4.1", CR_THEME_TEXT_DIM, NULL, NULL, NULL);
    }

    settings_row("Alert tones", settings.cues_enabled ? "ON" : "OFF",
                 settings.cues_enabled ? CR_THEME_ROSC : CR_THEME_TEXT_DIM,
                 on_toggle_cues, NULL, "set.cues");
    settings_row("Metronome", settings.metronome_sound_on ? "ON" : "OFF",
                 settings.metronome_sound_on ? CR_THEME_ROSC : CR_THEME_TEXT_DIM,
                 on_toggle_sound, NULL, "set.sound");
    settings_row("Keep screen on", settings.keep_screen_on ? "ON" : "OFF",
                 settings.keep_screen_on ? CR_THEME_ROSC : CR_THEME_TEXT_DIM,
                 on_toggle_screen, NULL, "set.screen");

    // The protocol's own lengths when nothing is overridden, so the row always
    // says what the device will actually do rather than "default".
    seconds_label(value, sizeof value, settings.cycle_override_ms, 120);
    settings_row("CPR cycle", value,
                 settings.cycle_override_ms == CR_TIME_NONE ? CR_THEME_TEXT_DIM : CR_THEME_CPR,
                 on_cycle_length, NULL, "set.cycle");
    seconds_label(value, sizeof value, settings.interval_override_ms, 180);
    settings_row("Drug interval", value,
                 settings.interval_override_ms == CR_TIME_NONE ? CR_THEME_TEXT_DIM : CR_THEME_MED,
                 on_interval_length, NULL, "set.interval");

    settings_row("Test tone", cr_audio_ready() ? "TAP" : "NO CODEC",
                 cr_audio_ready() ? CR_THEME_CPR : CR_THEME_MED,
                 cr_audio_ready() ? on_test_tone : NULL, NULL, "set.testtone");

    const cr_civil_t c = cr_civil_from_epoch_s(clock_ms() / 1000);
    cr_format_stamp(value, sizeof value, &c);
    settings_row("Clock", value, CR_THEME_TEXT_DIM, NULL, NULL, "set.clock");
    // ASCII hyphen, not U+2212 MINUS SIGN: the generated fonts carry the dashes
    // the watch's own strings need and not that one, and a missing glyph draws
    // as a filled box — which is exactly what it did here.
    settings_row("   clock  -1 min", "-1", CR_THEME_TEXT_DIM,
                 on_clock_nudge, (void *)(intptr_t)-1, "set.clockdown");
    settings_row("   clock  +1 min", "+1", CR_THEME_TEXT_DIM,
                 on_clock_nudge, (void *)(intptr_t)1, "set.clockup");

    lv_obj_scroll_to_y(settings_list, scroll, LV_ANIM_OFF);
}

static void on_open_settings(lv_event_t *event)
{
    (void)event;
    refresh_settings();
    load_screen(settings_screen);
}

static void build_settings(void)
{
    settings_screen = lv_obj_create(NULL);
    lv_obj_set_style_bg_color(settings_screen, lv_color_hex(CR_THEME_BG), 0);
    lv_obj_remove_flag(settings_screen, LV_OBJ_FLAG_SCROLLABLE);
    cr_probe_name(settings_screen, "settings");

    label_at(settings_screen, "SETTINGS", CR_THEME_TEXT_DIM, &cr_font_16, 0, 56, 410);

    settings_list = lv_obj_create(settings_screen);
    lv_obj_set_size(settings_list, 340, 322);
    lv_obj_set_pos(settings_list, 35, 88);
    lv_obj_set_style_bg_opa(settings_list, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(settings_list, 0, 0);
    lv_obj_set_style_pad_all(settings_list, 0, 0);
    lv_obj_set_style_pad_row(settings_list, 8, 0);
    lv_obj_set_flex_flow(settings_list, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_scroll_dir(settings_list, LV_DIR_VER);
    cr_probe_name(settings_list, "settings.list");

    lv_obj_t *back = button_at(settings_screen, 105, 414, 200, 56, CR_THEME_TEXT_DIM,
                               on_home, NULL, "settings.back");
    lv_obj_t *back_label = lv_label_create(back);
    lv_label_set_text(back_label, "BACK");
    lv_obj_set_style_text_color(back_label, lv_color_hex(CR_THEME_TEXT), 0);
    lv_obj_set_style_text_font(back_label, &cr_font_28, 0);
    lv_obj_center(back_label);
}

// MARK: - Recents
//
// The last STORE_KEEP codes, newest first, each naming itself by when it
// happened — which is the entire reason the RTC came first. Tapping one opens
// the same summary screen a code ends on, exactly as the watch reuses
// SummaryView for browsing.

static store_entry_t recents[STORE_KEEP];
static size_t recents_count;

static void on_recent_row(lv_event_t *event)
{
    const size_t index = (size_t)(uintptr_t)lv_event_get_user_data(event);
    if (index >= recents_count) return;
    if (!store_load(recents[index].name, &loaded_session)) {
        ESP_LOGE(TAG, "could not open %s", recents[index].name);
        return;
    }
    summary_session = &loaded_session;
    summary_from_recents = true;
    refresh_summary();
    load_screen(summary_screen);
}

static void refresh_recents(void)
{
    lv_obj_clean(recents_list);
    recents_count = store_list(recents, STORE_KEEP);

    if (recents_count == 0) {
        lv_obj_remove_flag(recents_empty, LV_OBJ_FLAG_HIDDEN);
        lv_label_set_text(recents_empty, store_ready()
            ? "No codes saved yet.\nThey are kept here when a code ends."
            : "Storage did not mount —\ncodes cannot be saved.");
        return;
    }
    lv_obj_add_flag(recents_empty, LV_OBJ_FLAG_HIDDEN);

    for (size_t i = 0; i < recents_count; i++) {
        const cr_archive_head_t *h = &recents[i].head;

        lv_obj_t *row = lv_button_create(recents_list);
        lv_obj_set_size(row, 336, 76);
        lv_obj_set_style_radius(row, 16, 0);
        lv_obj_set_style_bg_color(row, lv_color_hex(CR_THEME_SURFACE), 0);
        lv_obj_set_style_shadow_width(row, 0, 0);
        lv_obj_set_style_pad_all(row, 0, 0);
        lv_obj_add_event_cb(row, on_recent_row, LV_EVENT_CLICKED, (void *)(uintptr_t)i);

        // ROSC or not is the first thing anyone wants from this list, so it is
        // the colour of the whole row's marker rather than a word to read.
        const bool rosc = h->rosc != CR_TIME_NONE;
        lv_obj_t *bar = lv_obj_create(row);
        lv_obj_set_size(bar, 6, 52);
        lv_obj_set_pos(bar, 10, 12);
        lv_obj_set_style_bg_color(bar, lv_color_hex(rosc ? CR_THEME_ROSC : CR_THEME_TEXT_DIM), 0);
        lv_obj_set_style_border_width(bar, 0, 0);
        lv_obj_set_style_radius(bar, 3, 0);
        lv_obj_remove_flag(bar, LV_OBJ_FLAG_CLICKABLE);

        char when[40];
        const cr_civil_t c = cr_civil_from_epoch_s(h->start / 1000);
        cr_format_stamp(when, sizeof when, &c);
        lv_obj_t *stamp = lv_label_create(row);
        lv_label_set_text(stamp, when);
        lv_obj_set_style_text_color(stamp, lv_color_hex(CR_THEME_TEXT), 0);
        lv_obj_set_style_text_font(stamp, &cr_font_28, 0);
        lv_obj_set_pos(stamp, 26, 8);

        char detail[64], length[16];
        const cr_ms_t ran = (h->end != CR_TIME_NONE) ? h->end - h->start : 0;
        cr_format_clock(length, sizeof length, ran);
        snprintf(detail, sizeof detail, "%s · %.1f kg · %d events",
                 length, h->weight_kg, (int)h->event_count);
        lv_obj_t *sub = lv_label_create(row);
        lv_label_set_text(sub, detail);
        lv_obj_set_style_text_color(sub, lv_color_hex(CR_THEME_TEXT_DIM), 0);
        lv_obj_set_style_text_font(sub, &cr_font_16, 0);
        lv_obj_set_pos(sub, 26, 44);
    }
}

static void on_wipe_ask(lv_event_t *event)
{
    (void)event;
    lv_obj_remove_flag(wipe_confirm, LV_OBJ_FLAG_HIDDEN);
    lv_obj_move_foreground(wipe_confirm);
}

static void on_wipe_cancel(lv_event_t *event)
{
    (void)event;
    lv_obj_add_flag(wipe_confirm, LV_OBJ_FLAG_HIDDEN);
}

static void on_wipe_confirm(lv_event_t *event)
{
    (void)event;
    const size_t gone = store_clear();
    ESP_LOGW(TAG, "recents cleared by the user (%u)", (unsigned)gone);
    lv_obj_add_flag(wipe_confirm, LV_OBJ_FLAG_HIDDEN);
    refresh_recents();
}

static void show_recents(void)
{
    refresh_recents();
    lv_obj_add_flag(wipe_confirm, LV_OBJ_FLAG_HIDDEN);   // never open on arrival
    load_screen(recents_screen);
}

static void on_open_recents(lv_event_t *event)
{
    (void)event;
    show_recents();
}

static void build_recents(void)
{
    recents_screen = lv_obj_create(NULL);
    lv_obj_set_style_bg_color(recents_screen, lv_color_hex(CR_THEME_BG), 0);
    lv_obj_remove_flag(recents_screen, LV_OBJ_FLAG_SCROLLABLE);
    cr_probe_name(recents_screen, "recents");

    label_at(recents_screen, "RECENT CODES", CR_THEME_TEXT_DIM, &cr_font_16, 0, 56, 410);

    recents_list = lv_obj_create(recents_screen);
    lv_obj_set_size(recents_list, 340, 322);
    lv_obj_set_pos(recents_list, 35, 88);
    lv_obj_set_style_bg_opa(recents_list, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(recents_list, 0, 0);
    lv_obj_set_style_pad_all(recents_list, 0, 0);
    lv_obj_set_style_pad_row(recents_list, 8, 0);
    lv_obj_set_flex_flow(recents_list, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_scroll_dir(recents_list, LV_DIR_VER);
    cr_probe_name(recents_list, "recents.list");

    recents_empty = label_at(recents_screen, "", CR_THEME_TEXT_DIM, &cr_font_16, 0, 200, 410);
    lv_obj_add_flag(recents_empty, LV_OBJ_FLAG_HIDDEN);

    lv_obj_t *back = button_at(recents_screen, 30, 414, 178, 56, CR_THEME_TEXT_DIM,
                               on_home, NULL, "recents.back");
    lv_obj_t *back_label = lv_label_create(back);
    lv_label_set_text(back_label, "BACK");
    lv_obj_set_style_text_color(back_label, lv_color_hex(CR_THEME_TEXT), 0);
    lv_obj_set_style_text_font(back_label, &cr_font_28, 0);
    lv_obj_center(back_label);

    // Deliberately the smaller of the two, and the dark-red of the exit pads
    // rather than a menu colour: it must not read as the obvious thing to
    // press on the way out.
    lv_obj_t *wipe = button_at(recents_screen, 222, 414, 158, 56, CR_THEME_MED,
                               on_wipe_ask, NULL, "recents.clear");
    lv_obj_t *wipe_label = lv_label_create(wipe);
    lv_label_set_text(wipe_label, "CLEAR");
    lv_obj_set_style_text_color(wipe_label, lv_color_hex(CR_THEME_MED), 0);
    lv_obj_set_style_text_font(wipe_label, &cr_font_16, 0);
    lv_obj_center(wipe_label);

    // The confirmation, built once and hidden.
    wipe_confirm = lv_obj_create(recents_screen);
    lv_obj_set_size(wipe_confirm, 410, 501);
    lv_obj_set_pos(wipe_confirm, 0, 0);
    lv_obj_set_style_bg_color(wipe_confirm, lv_color_hex(CR_THEME_BG), 0);
    lv_obj_set_style_bg_opa(wipe_confirm, LV_OPA_90, 0);
    lv_obj_set_style_border_width(wipe_confirm, 0, 0);
    lv_obj_set_style_radius(wipe_confirm, 0, 0);
    lv_obj_remove_flag(wipe_confirm, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_flag(wipe_confirm, LV_OBJ_FLAG_HIDDEN);
    cr_probe_name(wipe_confirm, "recents.wipe");

    label_at(wipe_confirm, "DELETE ALL CODES?", CR_THEME_TEXT, &cr_font_28, 0, 150, 410);
    label_at(wipe_confirm, "this is the only copy —\nnothing syncs them anywhere",
             CR_THEME_TEXT_DIM, &cr_font_16, 0, 196, 410);

    lv_obj_t *yes = button_at(wipe_confirm, 55, 268, 300, 70, CR_THEME_MED,
                              on_wipe_confirm, NULL, "wipe.yes");
    lv_obj_set_style_bg_color(yes, lv_color_hex(CR_THEME_MED), 0);
    lv_obj_t *yes_label = lv_label_create(yes);
    lv_label_set_text(yes_label, "DELETE ALL");
    lv_obj_set_style_text_color(yes_label, lv_color_hex(CR_THEME_BG), 0);
    lv_obj_set_style_text_font(yes_label, &cr_font_28, 0);
    lv_obj_center(yes_label);

    lv_obj_t *no = button_at(wipe_confirm, 85, 360, 240, 62, CR_THEME_TEXT_DIM,
                             on_wipe_cancel, NULL, "wipe.no");
    lv_obj_t *no_label = lv_label_create(no);
    lv_label_set_text(no_label, "KEEP THEM");
    lv_obj_set_style_text_color(no_label, lv_color_hex(CR_THEME_TEXT), 0);
    lv_obj_set_style_text_font(no_label, &cr_font_28, 0);
    lv_obj_center(no_label);
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
    const struct { const char *symbol; const char *title; int32_t x; lv_event_cb_t handler; } orbit[] = {
        { "clock.arrow.circlepath", "Recent", 42, on_open_recents },
        { "gearshape.fill", "Settings", 246, on_open_settings },
    };
    for (size_t i = 0; i < 2; i++) {
        lv_obj_t *button = lv_button_create(home_screen);
        if (orbit[i].handler != NULL) {
            lv_obj_add_event_cb(button, orbit[i].handler, LV_EVENT_CLICKED, NULL);
        }
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
    settings = settings_store_load();
    ui_settings_changed(&settings);
    // Bring the radio back up if it was left on. After the UI exists, so a
    // slow start cannot delay the screen appearing.
    if (settings.tv_link_on) wifi_link_start(e, clock);
    build_home();
    build_summary();
    build_recents();
    build_settings();
    build_weight();
    build_confirm();
    build_protocols();
    build_age();
    refresh_weight();
    refresh_confirm();
}

void ui_flow_show_home(void)
{
    lv_screen_load(home_screen);   // at boot; no touch is in flight yet
}
