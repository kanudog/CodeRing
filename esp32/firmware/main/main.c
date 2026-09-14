// main.c — bring the board up, then hand off to the UI.
//
// Everything clinical lives in esp32/core (the same sources the host test
// suite runs); everything visual lives in ui_screen.c, driven by the
// hand-placed layout table. This file only wires them together.

#include <string.h>

#include "bsp/esp32_s3_touch_amoled_2_06.h"
#include "esp_attr.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "lvgl.h"

#include "driver/i2c_master.h"

#include "cr_defaults.h"
#include "cr_engine.h"
#include "ui_flow.h"
#include "ui_probe.h"
#include "ui_screen.h"

static const char *TAG = "codering";

// 96 kB of session in PSRAM, leaving internal RAM for LVGL and (at M5) WiFi.
EXT_RAM_BSS_ATTR static cr_engine_t engine;

/// The engine reads no clock of its own (invariant 4); this is the only
/// place time comes from. M5 swaps this for an RTC-anchored epoch, so a
/// reboot mid-code can resume against the same anchors.
static cr_ms_t now_ms(void)
{
    return (cr_ms_t)(esp_timer_get_time() / 1000);
}

static void tick_cb(lv_timer_t *timer)
{
    (void)timer;
    ui_tick();
}

/// Every chip on the board answers to an address. The docs list no
/// vibration motor, but Sebastian can feel a tick on each tap — and related
/// Waveshare boards drive a motor through a DRV2605 haptic driver at 0x5A.
/// If one is here, it will answer. Anything unexpected is worth knowing too.
static void scan_i2c(void)
{
    static const struct { uint8_t addr; const char *chip; } known[] = {
        { 0x18, "ES8311 audio codec" }, { 0x34, "AXP2101 power" },
        { 0x38, "FT3168 touch" },       { 0x40, "ES7210 mic ADC" },
        { 0x51, "PCF85063 RTC" },       { 0x5A, "DRV2605 HAPTIC DRIVER" },
        { 0x6A, "QMI8658 IMU" },        { 0x6B, "QMI8658 IMU" },
    };
    if (bsp_i2c_init() != ESP_OK) {
        ESP_LOGW(TAG, "i2c did not start; skipping the scan");
        return;
    }
    i2c_master_bus_handle_t bus = bsp_i2c_get_handle();
    if (bus == NULL) return;

    ESP_LOGI(TAG, "scanning I2C…");
    for (uint8_t addr = 0x08; addr < 0x78; addr++) {
        if (i2c_master_probe(bus, addr, 50) != ESP_OK) continue;
        const char *chip = "unknown — worth identifying";
        for (size_t i = 0; i < sizeof known / sizeof known[0]; i++) {
            if (known[i].addr == addr) chip = known[i].chip;
        }
        ESP_LOGI(TAG, "  0x%02X  %s", addr, chip);
    }
    ESP_LOGI(TAG, "scan done");
}

void app_main(void)
{
    ESP_LOGI(TAG, "CodeRing — demo, not a medical device");
    ESP_LOGI(TAG, "PSRAM %d kB free, internal %d kB free",
             (int)(heap_caps_get_free_size(MALLOC_CAP_SPIRAM) / 1024),
             (int)(heap_caps_get_free_size(MALLOC_CAP_INTERNAL) / 1024));

    // The engine is built when START CODE is tapped, not here: the code
    // clock starts at GO, and a session that began at boot would already be
    // minutes old by the time anyone touched it.
    cr_patient_t patient;
    memset(&patient, 0, sizeof patient);
    patient.weight_kg = 10;
    patient.source = CR_WEIGHT_MANUAL;
    cr_engine_init(&engine, &cr_protocol_pals_arrest, &cr_pals_drug_set,
                   cr_builtin_events, cr_builtin_event_count,
                   &patient, now_ms(), "DEVICE-0001", "codering-esp32");

    lv_display_t *display = bsp_display_start();
    if (display == NULL) {
        ESP_LOGE(TAG, "display failed to start");
        return;
    }
    bsp_display_brightness_set(80);

    // After the display comes up: the BSP powers the rails and starts the
    // bus as part of that, so scanning earlier found nothing at all.
    scan_i2c();

    // The BSP drives LVGL from its own task, so everything that touches it
    // runs under the same lock.
    bsp_display_lock(0);
    ui_create(&engine, now_ms);
    ui_flow_create(&engine, now_ms);
    ui_tick();
    ui_flow_show_home();
    lv_timer_create(tick_cb, 100, NULL);
    cr_probe_watch_touches(bsp_display_get_input_dev());
    cr_probe_dump(ui_live_screen(), "live session layout");
    bsp_display_unlock();

    ESP_LOGI(TAG, "up — %s, %.1f kg", engine.protocol.name, engine.session.patient.weight_kg);
}
