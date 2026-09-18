// session_store.h — finished codes, on flash.
//
// One file per code on the 8 MB `storage` partition, named for the moment the
// code STARTED. A flat filesystem with the time in the filename means the
// listing is sorted by sorting the names: there is no index file that can
// disagree with the directory, and nothing to repair after a power loss.
//
// The encoding is cr_archive (core, and tested there). This file only decides
// where the bytes live and which ones to throw away.

#pragma once

#include <stdbool.h>
#include <stddef.h>

#include "cr_archive.h"
#include "cr_session.h"
#include "esp_err.h"

/// How many codes are kept. Older ones are deleted as new ones are saved —
/// at a couple of kB each this is nowhere near the partition's limit; it is a
/// list a person can actually scan.
#define STORE_KEEP 12

typedef struct {
    char name[32];              // the file, for store_load
    cr_archive_head_t head;     // enough to draw a row without a full read
} store_entry_t;

/// Mounts the partition. Safe to call once, at boot; a failure here is not
/// fatal — the code timer still works, it just cannot remember.
esp_err_t store_init(void);

/// True once the partition is mounted and writable.
bool store_ready(void);

/// Writes a finished code, then prunes to STORE_KEEP. Written to a temporary
/// name and renamed into place, so a power loss mid-write leaves the old
/// listing intact rather than a half-file that looks real.
bool store_save(const cr_session_t *session);

/// Newest first. Returns how many entries were written.
size_t store_list(store_entry_t *out, size_t cap);

bool store_load(const char *name, cr_session_t *out);

/// Deletes every saved code. Irreversible and unsynced — nothing else holds a
/// copy — so the caller must have asked first. Returns how many it removed.
size_t store_clear(void);
