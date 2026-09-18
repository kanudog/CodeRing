// settings_store.h — user settings that survive a reboot.
//
// Settings go in NVS, not on the storage partition: they are a handful of
// small values that change rarely and must never be lost, which is precisely
// what NVS's wear-levelled key/value store is for. Saved codes go on SPIFFS
// because they are large and many. Two shapes of data, two stores.
//
// The value is the SAME JSON the phone writes (cr_settings_to_json), so a
// settings.json copied between devices still means the same thing — that
// compatibility is why the C model keeps the Swift field names.

#pragma once

#include <stdbool.h>

#include "cr_settings.h"
#include "esp_err.h"

esp_err_t settings_store_init(void);

/// The stored settings, or the defaults when nothing has been saved yet or
/// what was saved no longer parses. Never fails: a device with unreadable
/// settings is still a usable code timer.
cr_settings_t settings_store_load(void);

bool settings_store_save(const cr_settings_t *settings);
