// wifi_link.h — the watch's own access point, and the page it serves.
//
// The watch is the server and the TV is a browser. That is the topology on
// purpose: a code happens in a room, and the display must not depend on
// hospital Wi-Fi being up, reachable, or willing to let two devices talk to
// each other. A SoftAP with the display joining it works in a bay with no
// network at all.
//
// It serves exactly two things: esp32/tv/index.html, embedded in the binary,
// and cr_snapshot_json at /api/snapshot. The page is the SAME file the
// preview server hands out, so what is developed on a laptop is what ships.

#pragma once

#include <stdbool.h>

#include "cr_engine.h"
#include "esp_err.h"

/// Starts the AP and the HTTP server. `clock` is the same one the UI uses —
/// the engine still reads no clock of its own.
esp_err_t wifi_link_start(cr_engine_t *engine, cr_ms_t (*clock)(void));

void wifi_link_stop(void);

/// True while the AP is up. The UI says so, because an access point nobody
/// can see is indistinguishable from a broken one.
bool wifi_link_running(void);

/// How many displays are associated right now.
int wifi_link_clients(void);
