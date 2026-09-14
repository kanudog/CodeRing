#include "cr_json.h"

#include <inttypes.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cr_theme.h"

// MARK: - Writer

static void put(cr_jw_t *w, const char *bytes, size_t n)
{
    if (w->cap > 0 && w->len + 1 < w->cap) {
        size_t room = w->cap - 1 - w->len;
        size_t k = n < room ? n : room;
        memcpy(w->buf + w->len, bytes, k);
        w->buf[w->len + k] = '\0';
    }
    w->len += n;   // keep counting past the end so the caller sees the real size
}

void cr_jw_init(cr_jw_t *w, char *buf, size_t cap)
{
    w->buf = buf;
    w->cap = cap;
    w->len = 0;
    if (cap > 0) buf[0] = '\0';
}

void cr_jw_raw(cr_jw_t *w, const char *text)
{
    put(w, text, strlen(text));
}

void cr_jw_str(cr_jw_t *w, const char *text)
{
    put(w, "\"", 1);
    for (const unsigned char *p = (const unsigned char *)(text ? text : ""); *p; p++) {
        switch (*p) {
        case '"':  put(w, "\\\"", 2); break;
        case '\\': put(w, "\\\\", 2); break;
        case '\n': put(w, "\\n", 2); break;
        case '\r': put(w, "\\r", 2); break;
        case '\t': put(w, "\\t", 2); break;
        case '\b': put(w, "\\b", 2); break;
        case '\f': put(w, "\\f", 2); break;
        default:
            if (*p < 0x20) {
                char esc[8];
                snprintf(esc, sizeof esc, "\\u%04x", (unsigned)*p);
                put(w, esc, 6);
            } else {
                put(w, (const char *)p, 1);   // UTF-8 passes through untouched
            }
            break;
        }
    }
    put(w, "\"", 1);
}

void cr_jw_str_or_null(cr_jw_t *w, const char *text)
{
    if (text == NULL || text[0] == '\0') cr_jw_raw(w, "null");
    else cr_jw_str(w, text);
}

void cr_jw_i64(cr_jw_t *w, int64_t value)
{
    char buf[24];
    int n = snprintf(buf, sizeof buf, "%" PRId64, value);
    if (n > 0) put(w, buf, (size_t)n);
}

void cr_jw_num(cr_jw_t *w, double value)
{
    if (!isfinite(value)) { cr_jw_raw(w, "null"); return; }
    char buf[32];
    int n = snprintf(buf, sizeof buf, "%.15g", value);
    if (n > 0) put(w, buf, (size_t)n);
}

void cr_jw_bool(cr_jw_t *w, bool value)
{
    cr_jw_raw(w, value ? "true" : "false");
}

void cr_jw_color(cr_jw_t *w, uint32_t color)
{
    if (color == CR_COLOR_NONE) { cr_jw_raw(w, "null"); return; }
    char buf[10];
    snprintf(buf, sizeof buf, "\"%06X\"", (unsigned)(color & 0xFFFFFFu));
    cr_jw_raw(w, buf);
}

// MARK: - Reader

const char *cr_json_skip_ws(const char *p)
{
    while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r') p++;
    return p;
}

static void out_push(char *out, size_t cap, size_t *len, const char *bytes, size_t n)
{
    if (out == NULL || cap == 0) return;
    for (size_t i = 0; i < n && *len + 1 < cap; i++) out[(*len)++] = bytes[i];
}

static bool hex4(const char *p, uint32_t *out)
{
    uint32_t v = 0;
    for (int i = 0; i < 4; i++) {
        char c = p[i];
        v <<= 4;
        if (c >= '0' && c <= '9') v |= (uint32_t)(c - '0');
        else if (c >= 'a' && c <= 'f') v |= (uint32_t)(c - 'a' + 10);
        else if (c >= 'A' && c <= 'F') v |= (uint32_t)(c - 'A' + 10);
        else return false;
    }
    *out = v;
    return true;
}

static size_t utf8_encode(uint32_t cp, char *out)
{
    if (cp < 0x80) { out[0] = (char)cp; return 1; }
    if (cp < 0x800) {
        out[0] = (char)(0xC0 | (cp >> 6));
        out[1] = (char)(0x80 | (cp & 0x3F));
        return 2;
    }
    if (cp < 0x10000) {
        out[0] = (char)(0xE0 | (cp >> 12));
        out[1] = (char)(0x80 | ((cp >> 6) & 0x3F));
        out[2] = (char)(0x80 | (cp & 0x3F));
        return 3;
    }
    out[0] = (char)(0xF0 | (cp >> 18));
    out[1] = (char)(0x80 | ((cp >> 12) & 0x3F));
    out[2] = (char)(0x80 | ((cp >> 6) & 0x3F));
    out[3] = (char)(0x80 | (cp & 0x3F));
    return 4;
}

/// `p` points at the opening quote. `out` may be NULL to parse and discard.
static const char *parse_string(const char *p, char *out, size_t cap)
{
    if (*p != '"') return NULL;
    p++;
    size_t len = 0;
    for (;;) {
        unsigned char c = (unsigned char)*p;
        if (c == '\0') return NULL;
        if (c == '"') { p++; break; }
        if (c < 0x20) return NULL;   // raw control characters are not legal JSON
        if (c != '\\') { out_push(out, cap, &len, (const char *)p, 1); p++; continue; }

        p++;
        char decoded[4];
        size_t n = 1;
        switch (*p) {
        case '"':  decoded[0] = '"';  p++; break;
        case '\\': decoded[0] = '\\'; p++; break;
        case '/':  decoded[0] = '/';  p++; break;
        case 'b':  decoded[0] = '\b'; p++; break;
        case 'f':  decoded[0] = '\f'; p++; break;
        case 'n':  decoded[0] = '\n'; p++; break;
        case 'r':  decoded[0] = '\r'; p++; break;
        case 't':  decoded[0] = '\t'; p++; break;
        case 'u': {
            uint32_t cp;
            p++;
            if (!hex4(p, &cp)) return NULL;
            p += 4;
            if (cp >= 0xD800 && cp <= 0xDBFF) {          // high surrogate
                uint32_t lo;
                if (p[0] == '\\' && p[1] == 'u' && hex4(p + 2, &lo) &&
                    lo >= 0xDC00 && lo <= 0xDFFF) {
                    cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                    p += 6;
                } else {
                    cp = 0xFFFD;                          // unpaired — replacement char
                }
            } else if (cp >= 0xDC00 && cp <= 0xDFFF) {
                cp = 0xFFFD;
            }
            n = utf8_encode(cp, decoded);
            break;
        }
        default: return NULL;
        }
        out_push(out, cap, &len, decoded, n);
    }
    if (out != NULL && cap > 0) out[len] = '\0';
    return p;
}

/// Validates the JSON number grammar, then converts with strtod.
static const char *parse_number(const char *p, double *out)
{
    const char *start = p;
    if (*p == '-') p++;
    if (*p == '0') {
        p++;
    } else if (*p >= '1' && *p <= '9') {
        while (*p >= '0' && *p <= '9') p++;
    } else {
        return NULL;
    }
    if (*p == '.') {
        p++;
        if (!(*p >= '0' && *p <= '9')) return NULL;
        while (*p >= '0' && *p <= '9') p++;
    }
    if (*p == 'e' || *p == 'E') {
        p++;
        if (*p == '+' || *p == '-') p++;
        if (!(*p >= '0' && *p <= '9')) return NULL;
        while (*p >= '0' && *p <= '9') p++;
    }
    size_t n = (size_t)(p - start);
    char buf[64];
    if (n >= sizeof buf) return NULL;
    memcpy(buf, start, n);
    buf[n] = '\0';
    if (out != NULL) *out = strtod(buf, NULL);
    return p;
}

static const char *match(const char *p, const char *literal)
{
    size_t n = strlen(literal);
    return strncmp(p, literal, n) == 0 ? p + n : NULL;
}

static const char *skip_value(const char *p, int depth)
{
    if (depth > 32) return NULL;   // a deep document is a malformed document here
    p = cr_json_skip_ws(p);
    switch (*p) {
    case '"': return parse_string(p, NULL, 0);
    case 't': return match(p, "true");
    case 'f': return match(p, "false");
    case 'n': return match(p, "null");
    case '{': {
        p = cr_json_skip_ws(p + 1);
        if (*p == '}') return p + 1;
        for (;;) {
            p = cr_json_skip_ws(p);
            const char *q = parse_string(p, NULL, 0);
            if (q == NULL) return NULL;
            p = cr_json_skip_ws(q);
            if (*p != ':') return NULL;
            p = skip_value(p + 1, depth + 1);
            if (p == NULL) return NULL;
            p = cr_json_skip_ws(p);
            if (*p == ',') { p++; continue; }
            if (*p == '}') return p + 1;
            return NULL;
        }
    }
    case '[': {
        p = cr_json_skip_ws(p + 1);
        if (*p == ']') return p + 1;
        for (;;) {
            p = skip_value(p, depth + 1);
            if (p == NULL) return NULL;
            p = cr_json_skip_ws(p);
            if (*p == ',') { p++; continue; }
            if (*p == ']') return p + 1;
            return NULL;
        }
    }
    default: return parse_number(p, NULL);
    }
}

const char *cr_json_skip_value(const char *p)
{
    return skip_value(p, 0);
}

bool cr_json_validate(const char *json)
{
    if (json == NULL) return false;
    const char *p = skip_value(json, 0);
    if (p == NULL) return false;
    return *cr_json_skip_ws(p) == '\0';
}

const char *cr_json_value(const char *p, cr_json_kind_t *kind, bool *boolean,
                          double *number, char *str, size_t str_cap)
{
    p = cr_json_skip_ws(p);
    switch (*p) {
    case '"':
        *kind = CR_JSON_STRING;
        return parse_string(p, str, str_cap);
    case 't':
        *kind = CR_JSON_BOOL;
        if (boolean != NULL) *boolean = true;
        return match(p, "true");
    case 'f':
        *kind = CR_JSON_BOOL;
        if (boolean != NULL) *boolean = false;
        return match(p, "false");
    case 'n':
        *kind = CR_JSON_NULL;
        return match(p, "null");
    case '{':
    case '[':
        *kind = CR_JSON_NESTED;
        return skip_value(p, 0);
    default:
        *kind = CR_JSON_NUMBER;
        return parse_number(p, number);
    }
}
