#include "cr_archive.h"

#include <string.h>

#include "cr_text.h"

static const uint8_t k_magic[4] = { 'C', 'R', 'S', 'N' };

/// A cursor that refuses to run off either end. Every put/get goes through
/// it, so a truncated file cannot walk into memory it does not own — the one
/// failure mode a fixed-capacity decoder has to be immune to.
typedef struct {
    uint8_t *buf;
    const uint8_t *src;
    size_t cap, at;
    bool overflow;
} cursor_t;

static void put(cursor_t *c, const void *bytes, size_t n)
{
    if (c->at + n > c->cap) { c->overflow = true; c->at += n; return; }
    if (c->buf != NULL) memcpy(c->buf + c->at, bytes, n);
    c->at += n;
}

static bool get(cursor_t *c, void *out, size_t n)
{
    if (c->at + n > c->cap) { c->overflow = true; return false; }
    memcpy(out, c->src + c->at, n);
    c->at += n;
    return true;
}

// Little-endian on the wire regardless of the host, so a file written on the
// board reads on a laptop and vice versa.
static void put_u16(cursor_t *c, uint16_t v)
{
    const uint8_t b[2] = { (uint8_t)v, (uint8_t)(v >> 8) };
    put(c, b, 2);
}
static void put_u32(cursor_t *c, uint32_t v)
{
    const uint8_t b[4] = { (uint8_t)v, (uint8_t)(v >> 8), (uint8_t)(v >> 16), (uint8_t)(v >> 24) };
    put(c, b, 4);
}
static void put_i64(cursor_t *c, int64_t v)
{
    uint8_t b[8];
    const uint64_t u = (uint64_t)v;
    for (size_t i = 0; i < 8; i++) b[i] = (uint8_t)(u >> (i * 8));
    put(c, b, 8);
}
/// Doubles go as their IEEE-754 bits. Both ends are ESP32/ARM/x86, all of
/// which agree; a text encoding would round the weight, and the weight is
/// what every dose was computed from.
static void put_f64(cursor_t *c, double v)
{
    uint64_t bits;
    memcpy(&bits, &v, sizeof bits);
    put_i64(c, (int64_t)bits);
}
/// Strings carry their length, so a field that grows later still parses.
static void put_str(cursor_t *c, const char *s, size_t field)
{
    size_t n = strnlen(s, field);
    put_u16(c, (uint16_t)n);
    put(c, s, n);
}

static bool get_u16(cursor_t *c, uint16_t *v)
{
    uint8_t b[2];
    if (!get(c, b, 2)) return false;
    *v = (uint16_t)(b[0] | (b[1] << 8));
    return true;
}
static bool get_u32(cursor_t *c, uint32_t *v)
{
    uint8_t b[4];
    if (!get(c, b, 4)) return false;
    *v = (uint32_t)b[0] | ((uint32_t)b[1] << 8) | ((uint32_t)b[2] << 16) | ((uint32_t)b[3] << 24);
    return true;
}
static bool get_i64(cursor_t *c, int64_t *v)
{
    uint8_t b[8];
    if (!get(c, b, 8)) return false;
    uint64_t u = 0;
    for (size_t i = 0; i < 8; i++) u |= (uint64_t)b[i] << (i * 8);
    *v = (int64_t)u;
    return true;
}
static bool get_f64(cursor_t *c, double *v)
{
    int64_t bits;
    if (!get_i64(c, &bits)) return false;
    const uint64_t u = (uint64_t)bits;
    memcpy(v, &u, sizeof *v);
    return true;
}
static bool get_str(cursor_t *c, char *out, size_t field)
{
    uint16_t n = 0;
    if (!get_u16(c, &n)) return false;
    if (c->at + n > c->cap) { c->overflow = true; return false; }
    // Truncate rather than refuse: a longer string from a future build is a
    // cosmetic loss, not a corrupt record. UTF-8 safe, so a cut never lands
    // mid-character.
    char tmp[CR_DETAIL_MAX * 2];
    const size_t take = n < sizeof tmp - 1 ? n : sizeof tmp - 1;
    memcpy(tmp, c->src + c->at, take);
    tmp[take] = '\0';
    c->at += n;
    cr_copy_utf8(out, field, tmp);
    return true;
}

static void encode_body(cursor_t *c, const cr_session_t *s)
{
    put(c, k_magic, sizeof k_magic);
    put_u16(c, CR_ARCHIVE_VERSION);
    put_u16(c, 0);                                  // flags, reserved

    put_i64(c, s->start);
    put_i64(c, s->end);
    put_i64(c, s->rosc);
    put_str(c, s->id, CR_ID_MAX);
    put_str(c, s->protocol_id, sizeof s->protocol_id);
    put_str(c, s->protocol_name, sizeof s->protocol_name);
    put_str(c, s->device_name, sizeof s->device_name);

    put_f64(c, s->patient.weight_kg);
    put_u16(c, (uint16_t)s->patient.source);
    put_str(c, s->patient.broselow_zone_id, sizeof s->patient.broselow_zone_id);
    put_u16(c, (uint16_t)(s->patient.has_age ? 1 : 0));
    put_u16(c, (uint16_t)s->patient.age_months);
    put_u16(c, (uint16_t)s->patient.sex);

    put_u16(c, s->event_count);
    for (uint16_t i = 0; i < s->event_count; i++) {
        const cr_event_t *e = &s->events[i];
        put_u32(c, e->seq);
        put_i64(c, e->date);
        put_u32(c, (uint32_t)e->offset_s);
        put_str(c, e->title, CR_TITLE_MAX);
        put_str(c, e->detail, CR_DETAIL_MAX);
        put_u16(c, (uint16_t)e->category);
        put_str(c, e->definition_id, CR_DEF_ID_MAX);
        put_u32(c, e->color);
    }

    put_u16(c, s->pause_count);
    for (uint16_t i = 0; i < s->pause_count; i++) {
        put_i64(c, s->pauses[i].start);
        put_i64(c, s->pauses[i].end);
    }
}

size_t cr_archive_encode(const cr_session_t *s, uint8_t *buf, size_t cap)
{
    if (s == NULL) return 0;
    // Measure first, so a caller that passed too small a buffer is told the
    // real size instead of being handed a half-written record.
    cursor_t measure = { NULL, NULL, (size_t)-1, 0, false };
    encode_body(&measure, s);
    if (buf == NULL || measure.at > cap) return measure.at;

    cursor_t write = { buf, NULL, cap, 0, false };
    encode_body(&write, s);
    return write.overflow ? 0 : write.at;
}

/// Everything up to the event array, which is all a listing needs.
///
/// It fills the CALLER'S session rather than a local one. That is not style:
/// cr_session_t is ~96 kB, and a copy of it on the stack overflowed the UI
/// task the first time Recents was opened on the board — a white screen and a
/// reboot. Nothing in this file may put a session on the stack.
static bool decode_head(cursor_t *c, cr_session_t *s)
{
    uint8_t magic[4];
    uint16_t version = 0, flags = 0;
    if (!get(c, magic, sizeof magic)) return false;
    if (memcmp(magic, k_magic, sizeof k_magic) != 0) return false;
    if (!get_u16(c, &version) || !get_u16(c, &flags)) return false;
    if (version != CR_ARCHIVE_VERSION) return false;

    uint16_t source = 0, has_age = 0, age = 0, sex = 0;
    if (!get_i64(c, &s->start) || !get_i64(c, &s->end) || !get_i64(c, &s->rosc)) return false;
    if (!get_str(c, s->id, CR_ID_MAX)) return false;
    if (!get_str(c, s->protocol_id, sizeof s->protocol_id)) return false;
    if (!get_str(c, s->protocol_name, sizeof s->protocol_name)) return false;
    if (!get_str(c, s->device_name, sizeof s->device_name)) return false;
    if (!get_f64(c, &s->patient.weight_kg)) return false;
    if (!get_u16(c, &source)) return false;
    if (!get_str(c, s->patient.broselow_zone_id, sizeof s->patient.broselow_zone_id)) return false;
    if (!get_u16(c, &has_age) || !get_u16(c, &age) || !get_u16(c, &sex)) return false;
    s->patient.source = (cr_weight_source_t)source;
    s->patient.has_age = has_age != 0;
    s->patient.age_months = (int16_t)age;
    s->patient.sex = (cr_sex_t)sex;
    return true;
}

bool cr_archive_decode(const uint8_t *buf, size_t len, cr_session_t *out)
{
    if (buf == NULL || out == NULL) return false;
    // Decoded straight into `out`, never through a local copy — see
    // decode_head. The cost is that a FAILED decode leaves `out` partially
    // written, so a caller must check the return value before reading it;
    // that is cheaper than 96 kB of stack in a UI callback.
    cr_session_t *s = out;
    memset(s, 0, sizeof *s);
    cursor_t c = { NULL, buf, len, 0, false };
    if (!decode_head(&c, s)) return false;

    uint16_t events = 0;
    if (!get_u16(&c, &events)) return false;
    if (events > CR_MAX_EVENTS) return false;          // a count this build cannot hold
    for (uint16_t i = 0; i < events; i++) {
        cr_event_t *e = &s->events[i];
        uint16_t category = 0;
        uint32_t offset = 0;
        if (!get_u32(&c, &e->seq) || !get_i64(&c, &e->date) || !get_u32(&c, &offset)) return false;
        e->offset_s = (int32_t)offset;
        if (!get_str(&c, e->title, CR_TITLE_MAX)) return false;
        if (!get_str(&c, e->detail, CR_DETAIL_MAX)) return false;
        if (!get_u16(&c, &category)) return false;
        e->category = (cr_category_t)category;
        if (!get_str(&c, e->definition_id, CR_DEF_ID_MAX)) return false;
        if (!get_u32(&c, &e->color)) return false;
    }
    s->event_count = events;

    uint16_t pauses = 0;
    if (!get_u16(&c, &pauses)) return false;
    if (pauses > CR_MAX_PAUSES) return false;
    for (uint16_t i = 0; i < pauses; i++) {
        if (!get_i64(&c, &s->pauses[i].start) || !get_i64(&c, &s->pauses[i].end)) return false;
    }
    s->pause_count = pauses;

    return !c.overflow;
}

bool cr_archive_peek(const uint8_t *buf, size_t len, cr_archive_head_t *out)
{
    if (buf == NULL || out == NULL) return false;
    // Parses the same prefix as decode_head but into a few hundred bytes of
    // locals instead of a session. A listing calls this once per saved code,
    // from the UI task; it cannot afford a session each time.
    uint8_t magic[4];
    uint16_t version = 0, flags = 0, source = 0, has_age = 0, age = 0, sex = 0, events = 0;
    char scratch[CR_DEF_ID_MAX];
    cursor_t c = { NULL, buf, len, 0, false };

    if (!get(&c, magic, sizeof magic)) return false;
    if (memcmp(magic, k_magic, sizeof k_magic) != 0) return false;
    if (!get_u16(&c, &version) || !get_u16(&c, &flags)) return false;
    if (version != CR_ARCHIVE_VERSION) return false;
    if (!get_i64(&c, &out->start) || !get_i64(&c, &out->end) || !get_i64(&c, &out->rosc)) {
        return false;
    }
    if (!get_str(&c, scratch, sizeof scratch)) return false;                 // id
    if (!get_str(&c, scratch, sizeof scratch)) return false;                 // protocol id
    if (!get_str(&c, out->protocol_name, sizeof out->protocol_name)) return false;
    if (!get_str(&c, scratch, sizeof scratch)) return false;                 // device name
    if (!get_f64(&c, &out->weight_kg)) return false;
    if (!get_u16(&c, &source)) return false;
    if (!get_str(&c, scratch, sizeof scratch)) return false;                 // broselow zone
    if (!get_u16(&c, &has_age) || !get_u16(&c, &age) || !get_u16(&c, &sex)) return false;
    if (!get_u16(&c, &events)) return false;
    out->event_count = events;
    return !c.overflow;
}
