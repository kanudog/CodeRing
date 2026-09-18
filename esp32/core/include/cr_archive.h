// cr_archive.h — a finished code, as bytes.
//
// The session struct is ~96 kB because its arrays are fixed at 512 events and
// 256 pauses; a real code uses twenty of them. This writes only what is USED,
// which makes a saved code a couple of kB instead of ninety-six — the
// difference between a save you notice and one you do not, on flash that is
// slow to write.
//
// Explicit little-endian fields rather than a memcpy of the struct. Verbatim
// would be shorter, and would silently misread every previously saved code
// the first time a field is added to cr_session_t. A record you cannot read
// back is not a record.
//
// Pure: no allocation, no file system, no ESP-IDF. The firmware decides where
// the bytes live; `make test` proves they survive the round trip.

#ifndef CR_ARCHIVE_H
#define CR_ARCHIVE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "cr_session.h"

/// Bumped only when the layout below changes. A file from a newer version is
/// refused rather than guessed at.
#define CR_ARCHIVE_VERSION 1

/// Worst case: every event and pause slot in use. A typical code is ~2 kB.
#define CR_ARCHIVE_MAX_BYTES (64 + CR_MAX_EVENTS * 176 + CR_MAX_PAUSES * 16)

/// Writes `s` into `buf`. Returns the number of bytes the encoding NEEDS,
/// which is > cap when it did not fit (nothing is written in that case).
size_t cr_archive_encode(const cr_session_t *s, uint8_t *buf, size_t cap);

/// Reads one back. False — and `out` left untouched — when the magic, the
/// version or the length does not check out, so a truncated write or a file
/// from another build is refused loudly instead of producing a plausible
/// wrong record.
bool cr_archive_decode(const uint8_t *buf, size_t len, cr_session_t *out);

/// The header alone: enough to list recent codes without reading every file
/// in full. False when the bytes are not a CodeRing archive.
typedef struct {
    cr_ms_t start;
    cr_ms_t end;          // CR_TIME_NONE if the code was never ended
    cr_ms_t rosc;         // CR_TIME_NONE if there was none
    uint16_t event_count;
    double weight_kg;
    char protocol_name[40];
} cr_archive_head_t;

bool cr_archive_peek(const uint8_t *buf, size_t len, cr_archive_head_t *out);

#endif
