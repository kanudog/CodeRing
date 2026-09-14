// cr_json.h — internal JSON writer and reader (not part of the public API).
//
// Small on purpose: the settings file and the TV snapshot are the only two
// JSON shapes this device handles, and neither justifies a dependency. The
// writer never allocates and reports the length it WANTED, so a caller can
// tell a truncated buffer from a complete one.

#ifndef CR_JSON_H
#define CR_JSON_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct {
    char *buf;
    size_t cap;
    size_t len;    // bytes the full document needs, even past the end of buf
} cr_jw_t;

void cr_jw_init(cr_jw_t *w, char *buf, size_t cap);
void cr_jw_raw(cr_jw_t *w, const char *text);
void cr_jw_str(cr_jw_t *w, const char *text);          // quoted and escaped; NULL → ""
void cr_jw_str_or_null(cr_jw_t *w, const char *text);  // "" → null
void cr_jw_i64(cr_jw_t *w, int64_t value);
void cr_jw_num(cr_jw_t *w, double value);              // non-finite → null
void cr_jw_bool(cr_jw_t *w, bool value);
void cr_jw_color(cr_jw_t *w, uint32_t color);          // "FF3B5C"; CR_COLOR_NONE → null

const char *cr_json_skip_ws(const char *p);
/// Returns the position after the value, or NULL if it is malformed.
const char *cr_json_skip_value(const char *p);
/// Parses one complete document; trailing junk is malformed.
bool cr_json_validate(const char *json);

typedef enum { CR_JSON_NULL, CR_JSON_BOOL, CR_JSON_NUMBER, CR_JSON_STRING, CR_JSON_NESTED } cr_json_kind_t;

/// Reads one value. Strings are unescaped into `str` (truncated to fit);
/// objects and arrays are skipped and reported as CR_JSON_NESTED.
const char *cr_json_value(const char *p, cr_json_kind_t *kind, bool *boolean,
                          double *number, char *str, size_t str_cap);

#endif
