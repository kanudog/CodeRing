#include "session_store.h"

#include <dirent.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "esp_attr.h"
#include "esp_log.h"
#include "esp_spiffs.h"

static const char *TAG = "store";

#define MOUNT   "/codes"
#define LABEL   "storage"

static bool mounted;

/// The worst case is every event and pause slot in use — ~94 kB, which has no
/// business on a stack. A real code is a couple of kB, but the buffer has to
/// hold the one that is not.
EXT_RAM_BSS_ATTR static uint8_t scratch[CR_ARCHIVE_MAX_BYTES];

esp_err_t store_init(void)
{
    esp_vfs_spiffs_conf_t conf = {
        .base_path = MOUNT,
        .partition_label = LABEL,
        .max_files = 4,
        // A partition that will not mount is formatted rather than leaving the
        // device unable to remember anything. Losing old codes is bad; being
        // permanently unable to save new ones is worse.
        .format_if_mount_failed = true,
    };
    esp_err_t err = esp_vfs_spiffs_register(&conf);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "mount failed: %s — codes will not be saved", esp_err_to_name(err));
        return err;
    }
    size_t total = 0, used = 0;
    if (esp_spiffs_info(LABEL, &total, &used) == ESP_OK) {
        ESP_LOGI(TAG, "mounted %s — %u kB used of %u kB",
                 MOUNT, (unsigned)(used / 1024), (unsigned)(total / 1024));
    }
    mounted = true;
    return ESP_OK;
}

bool store_ready(void) { return mounted; }

/// Named for the START of the code, in seconds. Zero-padded so that sorting
/// the names sorts by time — the whole reason there is no index file.
static void name_for(char *buf, size_t cap, cr_ms_t start)
{
    snprintf(buf, cap, "c%012lld.crs", (long long)(start / 1000));
}

/// Deletes the oldest until only STORE_KEEP remain.
static void prune(void)
{
    for (;;) {
        DIR *dir = opendir(MOUNT);
        if (dir == NULL) return;
        char oldest[32] = "";
        size_t count = 0;
        struct dirent *entry;
        while ((entry = readdir(dir)) != NULL) {
            // A name too long to be one of ours is not one of ours: every file
            // this code writes is "c<12 digits>.crs". Checking the length here
            // is also what keeps the copy below provably in bounds.
            const size_t len = strlen(entry->d_name);
            if (len >= sizeof oldest) continue;
            if (strstr(entry->d_name, ".crs") == NULL) continue;
            count++;
            if (oldest[0] == '\0' || strcmp(entry->d_name, oldest) < 0) {
                memcpy(oldest, entry->d_name, len + 1);
            }
        }
        closedir(dir);
        if (count <= STORE_KEEP || oldest[0] == '\0') return;

        char path[64];
        snprintf(path, sizeof path, MOUNT "/%s", oldest);
        ESP_LOGI(TAG, "pruning %s", oldest);
        if (unlink(path) != 0) return;      // stop rather than spin
    }
}

bool store_save(const cr_session_t *session)
{
    if (!mounted || session == NULL) return false;

    const size_t n = cr_archive_encode(session, scratch, sizeof scratch);
    if (n == 0 || n > sizeof scratch) {
        ESP_LOGE(TAG, "encode needs %u bytes", (unsigned)n);
        return false;
    }

    // Temp name, then rename. A power loss halfway through a write then
    // leaves the previous listing intact instead of a truncated file that
    // looks like a real code until something tries to read it.
    char name[32], path[64], tmp[64];
    name_for(name, sizeof name, session->start);
    snprintf(path, sizeof path, MOUNT "/%s", name);
    snprintf(tmp, sizeof tmp, MOUNT "/_writing.crs");

    FILE *f = fopen(tmp, "wb");
    if (f == NULL) { ESP_LOGE(TAG, "cannot open %s", tmp); return false; }
    const size_t wrote = fwrite(scratch, 1, n, f);
    const int flushed = fflush(f);
    fclose(f);
    if (wrote != n || flushed != 0) {
        ESP_LOGE(TAG, "short write (%u of %u)", (unsigned)wrote, (unsigned)n);
        unlink(tmp);
        return false;
    }
    unlink(path);                   // SPIFFS rename will not overwrite
    if (rename(tmp, path) != 0) {
        ESP_LOGE(TAG, "rename failed");
        unlink(tmp);
        return false;
    }

    ESP_LOGI(TAG, "saved %s — %u bytes, %d events",
             name, (unsigned)n, (int)session->event_count);
    prune();
    return true;
}

static bool read_head(const char *name, store_entry_t *out)
{
    char path[64];
    snprintf(path, sizeof path, MOUNT "/%s", name);
    FILE *f = fopen(path, "rb");
    if (f == NULL) return false;
    // The header is the first ~200 bytes; a listing never reads the events.
    uint8_t head[256];
    const size_t n = fread(head, 1, sizeof head, f);
    fclose(f);
    if (!cr_archive_peek(head, n, &out->head)) {
        ESP_LOGW(TAG, "%s is not a readable code — ignoring it", name);
        return false;
    }
    snprintf(out->name, sizeof out->name, "%s", name);
    return true;
}

size_t store_list(store_entry_t *out, size_t cap)
{
    if (!mounted || out == NULL || cap == 0) return 0;
    DIR *dir = opendir(MOUNT);
    if (dir == NULL) return 0;

    size_t n = 0;
    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL) {
        if (strlen(entry->d_name) >= sizeof out->name) continue;
        if (strstr(entry->d_name, ".crs") == NULL) continue;
        if (entry->d_name[0] == '_') continue;              // a write in flight
        store_entry_t row;
        if (!read_head(entry->d_name, &row)) continue;

        // Newest first, by insertion: a dozen entries, so the simplest sort
        // that cannot get the order wrong is the right one.
        size_t at = n;
        while (at > 0 && out[at - 1].head.start < row.head.start) at--;
        if (at >= cap) continue;
        if (n < cap) n++;
        for (size_t i = (n > cap ? cap : n) - 1; i > at; i--) out[i] = out[i - 1];
        out[at] = row;
    }
    closedir(dir);
    return n;
}

bool store_load(const char *name, cr_session_t *out)
{
    if (!mounted || name == NULL || out == NULL) return false;
    char path[64];
    snprintf(path, sizeof path, MOUNT "/%s", name);
    FILE *f = fopen(path, "rb");
    if (f == NULL) { ESP_LOGE(TAG, "cannot open %s", name); return false; }
    const size_t n = fread(scratch, 1, sizeof scratch, f);
    fclose(f);
    if (!cr_archive_decode(scratch, n, out)) {
        ESP_LOGE(TAG, "%s did not decode", name);
        return false;
    }
    return true;
}

size_t store_clear(void)
{
    if (!mounted) return 0;
    size_t removed = 0;
    // Re-opened each pass: deleting while walking a directory is not defined
    // to be safe, and this runs once, on a handful of files.
    for (;;) {
        DIR *dir = opendir(MOUNT);
        if (dir == NULL) return removed;
        char victim[32] = "";
        struct dirent *entry;
        while ((entry = readdir(dir)) != NULL) {
            const size_t len = strlen(entry->d_name);
            if (len >= sizeof victim) continue;
            if (strstr(entry->d_name, ".crs") == NULL) continue;
            memcpy(victim, entry->d_name, len + 1);
            break;
        }
        closedir(dir);
        if (victim[0] == '\0') break;

        char path[64];
        snprintf(path, sizeof path, MOUNT "/%s", victim);
        if (unlink(path) != 0) break;       // stop rather than spin
        removed++;
    }
    ESP_LOGW(TAG, "cleared %u saved codes", (unsigned)removed);
    return removed;
}
