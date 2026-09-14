// cr_snapshot.h — the whole live state as one JSON object.
//
// This is the seam the TV mirror hangs off. The screen and the trauma-bay
// display are two consumers of ONE derived snapshot, so anything the engine
// learns reaches both; scraping state back out of UI code later is how that
// goes wrong. It is also how a browser can watch a running code during
// development, long before there are pixels on the panel.
//
// Pure: it reads the engine and writes bytes. Times are integer ms so the
// page can count down locally between pushes instead of stuttering at the
// push rate.

#ifndef CR_SNAPSHOT_H
#define CR_SNAPSHOT_H

#include <stddef.h>
#include <stdint.h>

#include "cr_engine.h"
#include "cr_time.h"

/// Renders the snapshot at `now`. `first_event` is the index the log should
/// start from — send 0 for the whole log, or the count the client already
/// has for a delta (it also gets log.rev and log.count back, so it can tell
/// an append from an undo).
///
/// snprintf semantics: returns the length the JSON needs, which is >= cap
/// when it was truncated. The buffer is always NUL-terminated, but a
/// truncated buffer is NOT valid JSON — check the return value before
/// sending it.
size_t cr_snapshot_json(const cr_engine_t *e, cr_ms_t now, uint16_t first_event,
                        char *buf, size_t cap);

#endif
