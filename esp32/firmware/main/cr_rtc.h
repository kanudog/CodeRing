// cr_rtc.h — the PCF85063 on the I2C bus at 0x51, which is what makes a
// saved code able to say WHEN.
//
// Until now the wall clock was stamped in at build time (CR_BUILD_LOCAL_EPOCH)
// and counted up from there: right to the second when flashed, and wrong the
// moment the board was power-cycled. A list of recent codes that cannot tell
// you which one is most recent is not a list, so the clock comes first.
//
// The RTC holds LOCAL wall-clock time, not UTC — see cr_clock.h for why that
// trade is deliberate on a board with no timezone database.

#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "cr_time.h"
#include "esp_err.h"

/// Claims the device on the BSP's I2C bus. Call after bsp_i2c_init().
esp_err_t cr_rtc_init(void);

/// Local epoch SECONDS from the chip. False when the RTC has never been set
/// or lost power since it was — the PCF85063 latches an oscillator-stop flag
/// for exactly this, and a clock that reports a confidently wrong time is
/// worse than one that admits it does not know.
bool cr_rtc_read(int64_t *epoch_s);

/// Sets the clock and clears the oscillator-stop flag.
bool cr_rtc_write(int64_t epoch_s);

/// Anchors the device clock to the RTC, seeding the RTC from `fallback_epoch_s`
/// if it has never been set. Call once, after the I2C bus is up.
void cr_rtc_start_clock(int64_t fallback_epoch_s);

/// Local epoch MILLISECONDS — the only clock the engine is ever given.
/// Anchored to the RTC once and advanced by esp_timer, never re-read: the
/// engine's clock must not jump backwards (invariant 4), and an RTC read that
/// came back a tick early would rewind every anchor in a running code.
cr_ms_t cr_rtc_now_ms(void);

/// Moves the clock by `delta` seconds — both the chip and the running anchor,
/// so the change shows on screen immediately rather than after a reboot.
bool cr_rtc_adjust_seconds(int delta);
