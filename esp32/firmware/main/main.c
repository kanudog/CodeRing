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

#include "cr_clock.h"
#include "cr_defaults.h"
#include "cr_engine.h"
#include "cr_rtc.h"
#include "session_store.h"
#include "ui_flow.h"
#include "ui_probe.h"
#include "ui_screen.h"

static const char *TAG = "codering";

// 96 kB of session in PSRAM, leaving internal RAM for LVGL and (at M5) WiFi.
EXT_RAM_BSS_ATTR static cr_engine_t engine;

#ifndef CR_BUILD_LOCAL_EPOCH
#define CR_BUILD_LOCAL_EPOCH 0
#endif

/// Local epoch ms at the instant esp_timer read zero. Set once, at boot, from
/// the RTC — and then never touched, which is the whole point: the engine's
/// clock must never jump backwards (cr_time.h), so the RTC ANCHORS it rather
/// than driving it. esp_timer does the counting; a second RTC read that came
/// back a tick earlier would rewind every anchor in a running code.
static int64_t epoch_at_boot_ms;

/// The engine reads no clock of its own (invariant 4); this is the only place
/// time comes from. Now RTC-anchored epoch ms, so timestamps survive a reboot
/// and a saved code can say when it happened.
static cr_ms_t now_ms(void)
{
    return (cr_ms_t)(epoch_at_boot_ms + esp_timer_get_time() / 1000);
}

/// Reads the clock, and seeds it from the build stamp the first time — a
/// board fresh off the bench has never had its RTC set, and one that has
/// simply keeps time across reboots and reflashes.
static void start_clock(void)
{
    if (cr_rtc_init() != ESP_OK) {
        ESP_LOGW(TAG, "no RTC — falling back to the build stamp");
        epoch_at_boot_ms = (int64_t)CR_BUILD_LOCAL_EPOCH * 1000;
        return;
    }

    int64_t seconds = 0;
    if (!cr_rtc_read(&seconds)) {
        ESP_LOGW(TAG, "RTC unset — seeding it from the build stamp, once");
        cr_rtc_write((int64_t)CR_BUILD_LOCAL_EPOCH);
        if (!cr_rtc_read(&seconds)) seconds = (int64_t)CR_BUILD_LOCAL_EPOCH;
    }
    // Subtract what esp_timer has already counted during boot, so the two
    // clocks agree about this instant rather than about app_main's start.
    epoch_at_boot_ms = seconds * 1000 - esp_timer_get_time() / 1000;

    const cr_civil_t c = cr_civil_from_epoch_s(seconds);
    ESP_LOGI(TAG, "clock: %04d-%02d-%02d %02d:%02d:%02d (local)",
             (int)c.year, (int)c.month, (int)c.day,
             (int)c.hour, (int)c.minute, (int)c.second);
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

    lv_display_t *display = bsp_display_start();
    if (display == NULL) {
        ESP_LOGE(TAG, "display failed to start");
        return;
    }
    bsp_display_brightness_set(80);

    // After the display comes up: the BSP powers the rails and starts the
    // bus as part of that, so scanning earlier found nothing at all.
    scan_i2c();

    // The bus is up, so the clock can be. Everything timestamped after this
    // point — every event, every saved code — is dated from the RTC, so the
    // clock has to be anchored BEFORE the engine is built.
    start_clock();

    // A placeholder engine so the live screen has something to draw before a
    // code exists. The real one is built when START CODE is tapped: the code
    // clock starts at GO, and a session begun at boot would already be
    // minutes old by the time anyone touched it.
    cr_patient_t patient;
    memset(&patient, 0, sizeof patient);
    patient.weight_kg = 10;
    patient.source = CR_WEIGHT_MANUAL;
    cr_engine_init(&engine, &cr_protocol_pals_arrest, &cr_pals_drug_set,
                   cr_builtin_events, cr_builtin_event_count,
                   &patient, now_ms(), "DEVICE-0001", "codering-esp32");

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

    // Storage mounts AFTER the screens exist, and deliberately so: the first
    // mount of a blank partition formats it, and LVGL runs on the BSP's own
    // task — so the home screen is already drawn and responsive while this
    // happens rather than the device looking dead. Not fatal either way: a
    // code still runs, it just cannot be kept.
    store_init();

    ESP_LOGI(TAG, "screens built — internal %d kB free, PSRAM %d kB free",
             (int)(heap_caps_get_free_size(MALLOC_CAP_INTERNAL) / 1024),
             (int)(heap_caps_get_free_size(MALLOC_CAP_SPIRAM) / 1024));
    ESP_LOGI(TAG, "up — %s", engine.protocol.name);
}
