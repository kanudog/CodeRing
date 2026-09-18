#include "cr_rtc.h"

#include <string.h>

#include "bsp/esp32_s3_touch_amoled_2_06.h"
#include "driver/i2c_master.h"
#include "esp_log.h"
#include "esp_timer.h"

#include "cr_clock.h"

static const char *TAG = "rtc";

#define PCF85063_ADDR   0x51
#define REG_CONTROL_1   0x00
#define REG_SECONDS     0x04    // …0x0A: seconds, minutes, hours, days, weekday, months, years
#define SECONDS_OS_BIT  0x80    // oscillator stopped: the time is not trustworthy
#define CONTROL1_STOP   0x20
#define CONTROL1_12_24  0x02    // 0 = 24-hour, which is what this code assumes

#define RTC_TIMEOUT_MS  100

static i2c_master_dev_handle_t rtc;

/// The chip speaks BCD. Two digits per byte, and a nibble that is not a digit
/// means a garbled read rather than a real time.
static bool from_bcd(uint8_t value, uint8_t *out)
{
    const uint8_t high = value >> 4, low = value & 0x0F;
    if (high > 9 || low > 9) return false;
    *out = (uint8_t)(high * 10 + low);
    return true;
}

static uint8_t to_bcd(uint8_t value)
{
    return (uint8_t)(((value / 10) << 4) | (value % 10));
}

esp_err_t cr_rtc_init(void)
{
    i2c_master_bus_handle_t bus = bsp_i2c_get_handle();
    if (bus == NULL) {
        ESP_LOGE(TAG, "no I2C bus — call bsp_i2c_init() first");
        return ESP_ERR_INVALID_STATE;
    }
    const i2c_device_config_t cfg = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = PCF85063_ADDR,
        .scl_speed_hz = 100000,
    };
    esp_err_t err = i2c_master_bus_add_device(bus, &cfg, &rtc);
    if (err != ESP_OK) { ESP_LOGE(TAG, "add device: %s", esp_err_to_name(err)); return err; }

    // Running, and in 24-hour mode. Both are the power-on defaults, but a
    // board that shipped running someone else's firmware may not be.
    uint8_t reg = REG_CONTROL_1, control = 0;
    if (i2c_master_transmit_receive(rtc, &reg, 1, &control, 1, RTC_TIMEOUT_MS) == ESP_OK) {
        const uint8_t want = (uint8_t)(control & ~(CONTROL1_STOP | CONTROL1_12_24));
        if (want != control) {
            const uint8_t tx[2] = { REG_CONTROL_1, want };
            i2c_master_transmit(rtc, tx, sizeof tx, RTC_TIMEOUT_MS);
            ESP_LOGI(TAG, "control_1 %02X -> %02X", control, want);
        }
    }
    return ESP_OK;
}

bool cr_rtc_read(int64_t *epoch_s)
{
    if (rtc == NULL) return false;
    uint8_t reg = REG_SECONDS, raw[7] = { 0 };
    if (i2c_master_transmit_receive(rtc, &reg, 1, raw, sizeof raw, RTC_TIMEOUT_MS) != ESP_OK) {
        ESP_LOGW(TAG, "read failed");
        return false;
    }
    if (raw[0] & SECONDS_OS_BIT) {
        ESP_LOGW(TAG, "oscillator stopped — the clock has never been set, or lost power");
        return false;
    }

    cr_civil_t c;
    uint8_t year2 = 0;
    const bool ok = from_bcd(raw[0] & 0x7F, &c.second)
                 && from_bcd(raw[1] & 0x7F, &c.minute)
                 && from_bcd(raw[2] & 0x3F, &c.hour)
                 && from_bcd(raw[3] & 0x3F, &c.day)
                 && from_bcd(raw[5] & 0x1F, &c.month)
                 && from_bcd(raw[6], &year2);
    if (!ok) { ESP_LOGW(TAG, "not BCD — garbled read"); return false; }
    c.year = 2000 + year2;                      // the chip holds 00-99

    // The chip cannot represent an impossible date, but a bad bus read can
    // produce one. Refuse it rather than stamping codes with 31 February.
    if (!cr_civil_valid(&c)) { ESP_LOGW(TAG, "implausible date from RTC"); return false; }
    if (epoch_s != NULL) *epoch_s = cr_civil_to_epoch_s(&c);
    return true;
}

bool cr_rtc_write(int64_t epoch_s)
{
    if (rtc == NULL) return false;
    const cr_civil_t c = cr_civil_from_epoch_s(epoch_s);
    if (!cr_civil_valid(&c)) return false;

    // Writing seconds with the OS bit CLEAR is what tells the chip the time
    // is trustworthy again.
    const uint8_t tx[8] = {
        REG_SECONDS,
        to_bcd(c.second), to_bcd(c.minute), to_bcd(c.hour),
        to_bcd(c.day), 0 /* weekday: unused, derivable */, to_bcd(c.month),
        to_bcd((uint8_t)(c.year - 2000)),
    };
    if (i2c_master_transmit(rtc, tx, sizeof tx, RTC_TIMEOUT_MS) != ESP_OK) {
        ESP_LOGE(TAG, "write failed");
        return false;
    }
    ESP_LOGI(TAG, "set to %04d-%02d-%02d %02d:%02d:%02d",
             (int)c.year, (int)c.month, (int)c.day,
             (int)c.hour, (int)c.minute, (int)c.second);
    return true;
}

// MARK: - The device clock

/// Local epoch ms at the instant esp_timer read zero. Set once, at boot.
static int64_t epoch_at_boot_ms;

cr_ms_t cr_rtc_now_ms(void)
{
    return (cr_ms_t)(epoch_at_boot_ms + esp_timer_get_time() / 1000);
}

void cr_rtc_start_clock(int64_t fallback_epoch_s)
{
    int64_t seconds = 0;
    if (cr_rtc_init() != ESP_OK) {
        ESP_LOGW(TAG, "no RTC — falling back to the build stamp");
        epoch_at_boot_ms = fallback_epoch_s * 1000;
        return;
    }
    if (!cr_rtc_read(&seconds)) {
        ESP_LOGW(TAG, "RTC unset — seeding it from the build stamp, once");
        cr_rtc_write(fallback_epoch_s);
        if (!cr_rtc_read(&seconds)) seconds = fallback_epoch_s;
    }
    // Subtract what esp_timer has already counted during boot, so the two
    // clocks agree about this instant rather than about app_main's start.
    epoch_at_boot_ms = seconds * 1000 - esp_timer_get_time() / 1000;

    const cr_civil_t c = cr_civil_from_epoch_s(seconds);
    ESP_LOGI(TAG, "clock: %04d-%02d-%02d %02d:%02d:%02d (local)",
             (int)c.year, (int)c.month, (int)c.day,
             (int)c.hour, (int)c.minute, (int)c.second);
}

bool cr_rtc_adjust_seconds(int delta)
{
    // Move the ANCHOR as well as the chip. Writing only the chip left the
    // screen showing the old time until the next reboot, which reads as a
    // button that does nothing.
    const int64_t target = cr_rtc_now_ms() / 1000 + delta;
    epoch_at_boot_ms += (int64_t)delta * 1000;
    return cr_rtc_write(target);
}
