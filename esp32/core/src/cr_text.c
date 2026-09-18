#include "cr_text.h"

#include <inttypes.h>
#include <math.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>

static char ascii_lower(char c) { return (c >= 'A' && c <= 'Z') ? (char)(c + 32) : c; }
static char ascii_upper(char c) { return (c >= 'a' && c <= 'z') ? (char)(c - 32) : c; }

/// True for a UTF-8 continuation byte (10xxxxxx) — the middle of a character.
static bool is_continuation(char c) { return ((unsigned char)c & 0xC0) == 0x80; }

/// Copies at most `n` bytes of `src`, backing off so the cut never lands
/// inside a character.
static size_t copy_utf8_n(char *dst, size_t cap, const char *src, size_t n)
{
    if (cap == 0) return 0;
    if (n > cap - 1) n = cap - 1;
    while (n > 0 && is_continuation(src[n])) n--;
    if (n > 0) memcpy(dst, src, n);
    dst[n] = '\0';
    return n;
}

size_t cr_copy_utf8(char *dst, size_t cap, const char *src)
{
    if (cap == 0) return 0;
    if (src == NULL) { dst[0] = '\0'; return 0; }
    return copy_utf8_n(dst, cap, src, strlen(src));
}

void cr_format_clock(char *buf, size_t cap, cr_ms_t interval)
{
    int64_t t = interval < 0 ? 0 : interval / 1000;
    snprintf(buf, cap, "%" PRId64 ":%02d", t / 60, (int)(t % 60));
}

void cr_format_clock_signed(char *buf, size_t cap, cr_ms_t interval)
{
    // C division truncates toward zero, which is what Swift's
    // .rounded(.towardZero) does — "-0:59" then "-1:00", never "-1:01" early.
    int64_t t = interval / 1000;
    int64_t mag = t < 0 ? -t : t;
    snprintf(buf, cap, "%s%" PRId64 ":%02d", t < 0 ? "-" : "", mag / 60, (int)(mag % 60));
}

void cr_format_offset(char *buf, size_t cap, int32_t seconds)
{
    int t = seconds < 0 ? 0 : (int)seconds;
    snprintf(buf, cap, "+%d:%02d", t / 60, t % 60);
}

void cr_format_trim(char *buf, size_t cap, double value)
{
    if (cap == 0) return;
    if (!isfinite(value)) { cr_copy_utf8(buf, cap, "—"); return; }
    if (value == round(value) && fabs(value) >= 1) {
        snprintf(buf, cap, "%.0f", value);
        return;
    }
    snprintf(buf, cap, "%.2f", value);
    size_t n = strlen(buf);
    while (n > 0 && buf[n - 1] == '0') buf[--n] = '\0';
    if (n > 0 && buf[n - 1] == '.') buf[--n] = '\0';
}

void cr_format_percent(char *buf, size_t cap, double fraction)
{
    if (cap == 0) return;
    if (!isfinite(fraction)) { cr_copy_utf8(buf, cap, "—"); return; }
    // Swift's String(format:) is this same printf, so "%.0f" rounds
    // identically — including 0.5 to even, which is why it is not rewritten
    // as an integer cast here.
    snprintf(buf, cap, "%.0f%%", fraction * 100.0);
}

/// Number of UTF-8 characters in the first `len` bytes.
static size_t utf8_count(const char *s, size_t len)
{
    size_t count = 0;
    for (size_t i = 0; i < len; i++) if (!is_continuation(s[i])) count++;
    return count;
}

/// Byte length of the first `chars` UTF-8 characters.
static size_t utf8_prefix_bytes(const char *s, size_t len, size_t chars)
{
    size_t seen = 0, i = 0;
    while (i < len) {
        if (!is_continuation(s[i])) {
            if (seen == chars) return i;
            seen++;
        }
        i++;
    }
    return len;
}

void cr_chip_abbreviation(char *buf, size_t cap, const char *title)
{
    if (cap == 0) return;
    const char *all = title ? title : "";

    // Swift's split(separator: " ") drops empty pieces, so leading spaces
    // are skipped; a title with no word at all is used whole.
    const char *word = all;
    while (*word == ' ') word++;
    size_t len = strcspn(word, " ");
    if (len == 0) { word = all; len = strlen(all); }

    // Known clinical shorthand, keyed on the leading word.
    static const struct { const char *word; const char *abbr; } known[] = {
        { "epinephrine", "EPI" },   { "atropine", "ATRO" },  { "adenosine", "ADEN" },
        { "amiodarone", "AMIO" },   { "lidocaine", "LIDO" }, { "dextrose", "DEX" },
        { "calcium", "CA" },        { "sodium", "BICARB" },  { "bicarb", "BICARB" },
        { "magnesium", "MAG" },     { "naloxone", "NAL" },   { "fluid", "IVF" },
        { "fluids", "IVF" },        { "blood", "BLOOD" },    { "defibrillation", "DEFIB" },
        { "cardioversion", "CVERT" },
    };
    char lower[32];
    if (len < sizeof lower) {
        for (size_t i = 0; i < len; i++) lower[i] = ascii_lower(word[i]);
        lower[len] = '\0';
        for (size_t i = 0; i < sizeof known / sizeof known[0]; i++) {
            if (strcmp(lower, known[i].word) == 0) {
                cr_copy_utf8(buf, cap, known[i].abbr);
                return;
            }
        }
    }

    // Unknown: a short word is said whole, a long one cut to three letters.
    size_t take = len;
    if (utf8_count(word, len) > 5) take = utf8_prefix_bytes(word, len, 3);
    size_t n = copy_utf8_n(buf, cap, word, take);
    for (size_t i = 0; i < n; i++) buf[i] = ascii_upper(buf[i]);
}
