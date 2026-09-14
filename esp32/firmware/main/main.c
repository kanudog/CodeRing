// main.c — M2: first light.
//
// Deliberately plain. The job of this milestone is to prove three things
// work TOGETHER — the panel, the touch digitiser, and the engine from
// esp32/core — because debugging all three at once behind a finished layout
// is how a port stalls. M3 replaces this screen with the real hand-placed
// radial UI, on this same foundation.
//
// Nothing here knows any clinical rules. Every number on screen comes from
// the engine, and every button is one engine call.

#include <stdio.h>
#include <string.h>

#include "bsp/esp32_s3_touch_amoled_2_06.h"
#include "esp_attr.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "lvgl.h"

#include "cr_defaults.h"
#include "cr_engine.h"
#include "cr_text.h"
#include "cr_theme.h"
#include "fonts/cr_fonts.h"
#include "ui_probe.h"

static const char *TAG = "codering";

// 96 kB of session lives in PSRAM, leaving internal RAM for LVGL and (at
// M5) the WiFi stack.
EXT_RAM_BSS_ATTR static cr_engine_t engine;

static lv_obj_t *lbl_hint;
static lv_obj_t *lbl_cycle;
static lv_obj_t *lbl_elapsed;
static lv_obj_t *lbl_epi;
static lv_obj_t *lbl_toast;
static lv_obj_t *btn_pulse_label;

/// The engine reads no clock of its own (invariant 4); this is the only
/// place the time comes from. M5 swaps this for an RTC-anchored epoch so a
/// reboot mid-code can resume against the same anchors.
static cr_ms_t now_ms(void)
{
    return (cr_ms_t)(esp_timer_get_time() / 1000);
}

static void toast_hide_cb(lv_timer_t *timer)
{
    lv_obj_add_flag(lbl_toast, LV_OBJ_FLAG_HIDDEN);
    lv_timer_delete(timer);
}

/// Confirmation has to be visible, because this board has no motor to tap
/// the wrist. Exactly 2 s, as on the watch.
static void toast(const char *text, uint32_t color)
{
    lv_label_set_text(lbl_toast, text);
    lv_obj_set_style_text_color(lbl_toast, lv_color_hex(color), 0);
    lv_obj_clear_flag(lbl_toast, LV_OBJ_FLAG_HIDDEN);
    lv_timer_t *timer = lv_timer_create(toast_hide_cb, 2000, NULL);
    lv_timer_set_repeat_count(timer, 1);
}

/// Silence after a deliberate action is this app's worst failure mode, so
/// every refusal says so out loud.
static void report(bool changed, const char *what)
{
    if (changed) {
        const cr_session_t *s = &engine.session;
        if (s->event_count > 0) {
            const cr_event_t *last = &s->events[s->event_count - 1];
            char line[CR_TITLE_MAX + CR_DETAIL_MAX + 16];
            snprintf(line, sizeof line, "%s%s%s", last->title,
                     last->detail[0] ? " — " : "", last->detail);
            toast(line, CR_THEME_ROSC);
            return;
        }
        toast(what, CR_THEME_ROSC);
    } else {
        char line[CR_TITLE_MAX + CR_DETAIL_MAX + 16];
        snprintf(line, sizeof line, "NOTHING LOGGED — %s", what);
        toast(line, CR_THEME_MED);
    }
}

static void on_start_cpr(lv_event_t *event)
{
    (void)event;
    report(cr_engine_start_cpr(&engine, now_ms()), "start CPR");
}

static void on_epi(lv_event_t *event)
{
    (void)event;
    report(cr_engine_log_drug(&engine, &cr_drug_epinephrine, -1, now_ms()), "epinephrine");
}

/// One button for the whole hands-off flow: start the check, then end it.
static void on_pulse(lv_event_t *event)
{
    (void)event;
    if (engine.in_pulse_check) {
        report(cr_engine_complete_pulse_check(&engine, false, now_ms()), "end pulse check");
    } else {
        report(cr_engine_begin_pulse_check(&engine, now_ms()), "pulse check");
    }
}

static lv_obj_t *make_button(lv_obj_t *parent, const char *text, uint32_t color,
                             lv_event_cb_t handler, const char *probe_name,
                             int32_t x, int32_t y, lv_obj_t **out_label)
{
    lv_obj_t *button = lv_button_create(parent);
    lv_obj_set_size(button, 124, 76);
    lv_obj_set_pos(button, x, y);
    lv_obj_set_style_radius(button, 18, 0);
    lv_obj_set_style_bg_color(button, lv_color_hex(CR_THEME_SURFACE_HI), 0);
    lv_obj_set_style_border_color(button, lv_color_hex(color), 0);
    lv_obj_set_style_border_width(button, 2, 0);
    lv_obj_add_event_cb(button, handler, LV_EVENT_CLICKED, NULL);
    cr_probe_name(button, probe_name);

    lv_obj_t *label = lv_label_create(button);
    lv_label_set_text(label, text);
    lv_obj_set_style_text_color(label, lv_color_hex(color), 0);
    // Smaller than the inherited body font: "START CPR" at 28 px is wider
    // than the button it sits in.
    lv_obj_set_style_text_font(label, &cr_font_16, 0);
    lv_obj_center(label);
    if (out_label != NULL) *out_label = label;
    return button;
}

/// Redraws from engine state. Pure rendering: it decides nothing.
static void tick_cb(lv_timer_t *timer)
{
    (void)timer;
    cr_ms_t now = now_ms();
    char buf[64];

    char hint[64];
    lv_label_set_text(lbl_hint, cr_engine_hint(&engine, now, hint, sizeof hint));

    cr_ms_t cycle = cr_engine_cycle_remaining(&engine, now);
    cr_format_clock_signed(buf, sizeof buf, cycle);
    lv_label_set_text(lbl_cycle, buf);
    lv_obj_set_style_text_color(lbl_cycle,
                                lv_color_hex(cycle <= 0 ? CR_THEME_MED : CR_THEME_CPR), 0);

    cr_format_clock(buf, sizeof buf, cr_engine_elapsed(&engine, now));
    lv_label_set_text_fmt(lbl_elapsed, "CODE %s", buf);

    const cr_timer_spec_t *epi = cr_protocol_interval_spec(&engine.protocol, 0);
    if (epi != NULL) {
        bool running = cr_engine_interval_is_running(&engine, epi);
        cr_format_clock_signed(buf, sizeof buf, cr_engine_interval_remaining(&engine, epi, now));
        lv_label_set_text_fmt(lbl_epi, "EPI %s", buf);
        // Idle reads dim: a countdown for a med nobody has given yet would
        // look like a standing order.
        lv_obj_set_style_text_color(lbl_epi,
                                    lv_color_hex(running ? CR_THEME_MED : CR_THEME_TEXT_DIM), 0);
        lv_obj_set_style_text_opa(lbl_epi, running ? LV_OPA_COVER : LV_OPA_50, 0);
    }

    lv_label_set_text(btn_pulse_label, engine.in_pulse_check ? "NO PULSE" : "PULSE");
}

static void build_ui(void)
{
    lv_obj_t *screen = lv_screen_active();
    cr_probe_name(screen, "screen");
    lv_obj_set_style_bg_color(screen, lv_color_hex(CR_THEME_BG), 0);
    lv_obj_set_style_pad_all(screen, 0, 0);
    lv_obj_clear_flag(screen, LV_OBJ_FLAG_SCROLLABLE);
    // Inherited by everything: the app's own font, which unlike LVGL's
    // built-ins carries the dashes, arrows and middots its strings use.
    lv_obj_set_style_text_font(screen, &cr_font_28, 0);

    lv_obj_t *title = lv_label_create(screen);
    lv_label_set_text(title, "CODERING · M2 FIRST LIGHT");
    lv_obj_set_style_text_color(title, lv_color_hex(CR_THEME_TEXT_DIM), 0);
    lv_obj_set_style_text_font(title, &cr_font_16, 0);
    lv_obj_align(title, LV_ALIGN_TOP_MID, 0, 14);
    cr_probe_name(title, "title");

    lbl_hint = lv_label_create(screen);
    lv_label_set_text(lbl_hint, "…");
    lv_obj_set_style_text_color(lbl_hint, lv_color_hex(CR_THEME_TEXT), 0);
    lv_label_set_long_mode(lbl_hint, LV_LABEL_LONG_WRAP);
    lv_obj_set_width(lbl_hint, 380);
    lv_obj_set_style_text_align(lbl_hint, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_hint, LV_ALIGN_TOP_MID, 0, 44);
    cr_probe_name(lbl_hint, "hint");

    lbl_cycle = lv_label_create(screen);
    lv_label_set_text(lbl_cycle, "2:00");
    lv_obj_set_style_text_font(lbl_cycle, &cr_font_48, 0);
    lv_obj_set_style_text_color(lbl_cycle, lv_color_hex(CR_THEME_CPR), 0);
    lv_obj_align(lbl_cycle, LV_ALIGN_TOP_MID, 0, 120);
    cr_probe_name(lbl_cycle, "cycle");

    lbl_elapsed = lv_label_create(screen);
    lv_label_set_text(lbl_elapsed, "CODE 0:00");
    lv_obj_set_style_text_color(lbl_elapsed, lv_color_hex(CR_THEME_TEXT), 0);
    lv_obj_align(lbl_elapsed, LV_ALIGN_TOP_MID, 0, 186);
    cr_probe_name(lbl_elapsed, "elapsed");

    lbl_epi = lv_label_create(screen);
    lv_label_set_text(lbl_epi, "EPI 3:00");
    lv_obj_set_style_text_color(lbl_epi, lv_color_hex(CR_THEME_MED), 0);
    lv_obj_align(lbl_epi, LV_ALIGN_TOP_MID, 0, 216);
    cr_probe_name(lbl_epi, "epi");

    // Three big targets, spaced for a gloved fingertip.
    make_button(screen, "START CPR", CR_THEME_CPR, on_start_cpr, "btn.startcpr", 18, 260, NULL);
    make_button(screen, "EPI", CR_THEME_MED, on_epi, "btn.epi", 268, 260, NULL);
    make_button(screen, "PULSE", CR_THEME_RHYTHM, on_pulse, "btn.pulse", 143, 352, &btn_pulse_label);

    lbl_toast = lv_label_create(screen);
    lv_label_set_text(lbl_toast, "");
    lv_label_set_long_mode(lbl_toast, LV_LABEL_LONG_WRAP);
    lv_obj_set_width(lbl_toast, 380);
    lv_obj_set_style_text_align(lbl_toast, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_style_bg_color(lbl_toast, lv_color_hex(CR_THEME_SURFACE), 0);
    lv_obj_set_style_bg_opa(lbl_toast, LV_OPA_COVER, 0);
    lv_obj_set_style_pad_all(lbl_toast, 8, 0);
    lv_obj_set_style_radius(lbl_toast, 10, 0);
    lv_obj_align(lbl_toast, LV_ALIGN_BOTTOM_MID, 0, -12);
    lv_obj_add_flag(lbl_toast, LV_OBJ_FLAG_HIDDEN);
    cr_probe_name(lbl_toast, "toast");
}

void app_main(void)
{
    ESP_LOGI(TAG, "CodeRing M2 — demo, not a medical device");
    ESP_LOGI(TAG, "PSRAM %d kB free, internal %d kB free",
             (int)(heap_caps_get_free_size(MALLOC_CAP_SPIRAM) / 1024),
             (int)(heap_caps_get_free_size(MALLOC_CAP_INTERNAL) / 1024));

    cr_patient_t patient;
    memset(&patient, 0, sizeof patient);
    patient.weight_kg = 10;                 // M3 brings the real setup flow
    patient.source = CR_WEIGHT_MANUAL;
    cr_engine_init(&engine, &cr_protocol_pals_arrest, &cr_pals_drug_set,
                   cr_builtin_events, cr_builtin_event_count,
                   &patient, now_ms(), "DEVICE-0001", "codering-esp32");
    ESP_LOGI(TAG, "engine ready: %s, %.1f kg, %d B of session in PSRAM",
             engine.protocol.name, engine.session.patient.weight_kg, (int)sizeof(cr_engine_t));

    lv_display_t *display = bsp_display_start();
    if (display == NULL) {
        ESP_LOGE(TAG, "display failed to start");
        return;
    }
    bsp_display_brightness_set(80);

    // Everything touching LVGL runs under its lock: the BSP drives LVGL
    // from its own task.
    bsp_display_lock(0);
    build_ui();
    lv_timer_create(tick_cb, 100, NULL);
    cr_probe_watch_touches(bsp_display_get_input_dev());
    cr_probe_dump(lv_screen_active(), "M2 first-light layout");
    bsp_display_unlock();

    ESP_LOGI(TAG, "up — tap the screen and watch the touch coordinates below");
}
