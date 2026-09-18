// A saved code has to come back exactly as it went in, and a damaged file has
// to be REFUSED rather than half-read. Those are the two things this covers,
// because a clinical record that decodes into a plausible wrong answer is
// worse than one that fails.
//
// No Swift counterpart: the watch persists through CodeStore and Codable.

#include <string.h>

#include "cr_archive.h"
#include "cr_defaults.h"
#include "cr_test.h"
#include "test_helpers.h"

#define START CR_SEC(1000)
#define T(s)  (START + CR_SEC(s))

static cr_engine_t engine;
static uint8_t buffer[CR_ARCHIVE_MAX_BYTES];

/// A code with something of everything in it: drugs, a shock, an event with a
/// sub-option, a pause, a pulse check and ROSC.
static void drive_a_code(cr_engine_t *e)
{
    test_make_engine(e, START);
    cr_engine_start_cpr(e, START);
    cr_engine_log_event_def(e, cr_builtin_event("access.iv"), "IO", T(8));
    cr_engine_log_drug(e, &cr_drug_epinephrine, -1, T(22));
    cr_engine_log_drug(e, &cr_drug_defibrillation, -1, T(59));
    cr_engine_toggle_pause(e, T(70));
    cr_engine_toggle_pause(e, T(90));
    cr_engine_log_drug(e, &cr_drug_amiodarone, -1, T(154));
    cr_engine_begin_pulse_check(e, T(180));
    cr_engine_complete_pulse_check(e, true, T(188));      // ROSC
    cr_engine_end(e, T(400));
}

// Port.savedCodeComesBackExactly
static void test_saved_code_comes_back_exactly(void)
{
    drive_a_code(&engine);
    const cr_session_t *original = &engine.session;

    const size_t n = cr_archive_encode(original, buffer, sizeof buffer);
    CHECK(n > 0);
    CHECK(n < sizeof buffer);
    // The whole point of encoding only what is used: a real code is a couple
    // of kB, not the 96 kB the struct occupies in RAM.
    CHECK(n < sizeof(cr_session_t) / 8);

    cr_session_t back;
    memset(&back, 0xAA, sizeof back);                    // poison, so gaps show
    CHECK(cr_archive_decode(buffer, n, &back));

    CHECK_I(back.start, original->start);
    CHECK_I(back.end, original->end);
    CHECK_I(back.rosc, original->rosc);
    CHECK_STR(back.id, original->id);
    CHECK_STR(back.protocol_name, original->protocol_name);
    CHECK_STR(back.device_name, original->device_name);
    CHECK(back.patient.weight_kg == original->patient.weight_kg);
    CHECK_I(back.patient.source, original->patient.source);

    CHECK_I(back.event_count, original->event_count);
    CHECK(back.event_count > 5);
    for (uint16_t i = 0; i < original->event_count; i++) {
        const cr_event_t *a = &original->events[i], *b = &back.events[i];
        CHECK_I(b->seq, a->seq);
        CHECK_I(b->date, a->date);
        CHECK_I(b->offset_s, a->offset_s);
        CHECK_STR(b->title, a->title);
        CHECK_STR(b->detail, a->detail);
        CHECK_I(b->category, a->category);
        CHECK_STR(b->definition_id, a->definition_id);
        CHECK_I(b->color, a->color);
    }

    CHECK_I(back.pause_count, original->pause_count);
    for (uint16_t i = 0; i < original->pause_count; i++) {
        CHECK_I(back.pauses[i].start, original->pauses[i].start);
        CHECK_I(back.pauses[i].end, original->pauses[i].end);
    }

    // And the numbers derived from it agree, which is what the summary screen
    // will actually show months later.
    cr_stats_t was, now;
    cr_session_stats(original, T(400), &was);
    cr_session_stats(&back, T(400), &now);
    CHECK_I(now.total_ms, was.total_ms);
    CHECK_I(now.epi_count, was.epi_count);
    CHECK_I(now.shock_count, was.shock_count);
    CHECK_I(now.pause_count, was.pause_count);
    CHECK(now.cpr_fraction == was.cpr_fraction);
    CHECK_I(now.seconds_to_rosc, was.seconds_to_rosc);
}

// Port.damagedArchiveIsRefused — every way a file can be wrong.
static void test_damaged_archive_is_refused(void)
{
    drive_a_code(&engine);
    const size_t n = cr_archive_encode(&engine.session, buffer, sizeof buffer);
    CHECK(n > 0);

    cr_session_t out;
    CHECK(cr_archive_decode(buffer, n, &out));           // the good one first

    // Truncated at every length: a half-written file must never decode.
    for (size_t cut = 0; cut < n; cut += 7) {
        CHECK(!cr_archive_decode(buffer, cut, &out));
    }

    uint8_t copy[CR_ARCHIVE_MAX_BYTES];
    memcpy(copy, buffer, n);
    copy[0] = 'X';                                       // wrong magic
    CHECK(!cr_archive_decode(copy, n, &out));

    memcpy(copy, buffer, n);
    copy[4] = CR_ARCHIVE_VERSION + 1;                    // a newer build's file
    CHECK(!cr_archive_decode(copy, n, &out));

    // An event count this build could not hold.
    memcpy(copy, buffer, n);
    for (size_t i = 0; i + 1 < n; i++) {
        if (copy[i] == (uint8_t)(engine.session.event_count) && copy[i + 1] == 0) {
            copy[i] = 0xFF; copy[i + 1] = 0xFF;
            break;
        }
    }
    CHECK(!cr_archive_decode(copy, n, &out));

    CHECK(!cr_archive_decode(NULL, n, &out));
    CHECK(!cr_archive_decode(buffer, n, NULL));
    CHECK(!cr_archive_decode(buffer, 0, &out));
}

// Port.archiveSaysItsSizeWhenItDoesNotFit
static void test_archive_says_its_size_when_it_does_not_fit(void)
{
    drive_a_code(&engine);
    const size_t needed = cr_archive_encode(&engine.session, NULL, 0);
    CHECK(needed > 0);
    // Too small: it reports what it needs and writes nothing.
    uint8_t tiny[32];
    memset(tiny, 0x5A, sizeof tiny);
    CHECK_I(cr_archive_encode(&engine.session, tiny, sizeof tiny), (int64_t)needed);
    for (size_t i = 0; i < sizeof tiny; i++) CHECK_I(tiny[i], 0x5A);
    // Exactly big enough is big enough.
    CHECK_I(cr_archive_encode(&engine.session, buffer, needed), (int64_t)needed);
}

// Port.archiveHeadListsWithoutFullRead — what the Recents list reads.
static void test_archive_head_lists_without_full_read(void)
{
    drive_a_code(&engine);
    const size_t n = cr_archive_encode(&engine.session, buffer, sizeof buffer);

    cr_archive_head_t head;
    CHECK(cr_archive_peek(buffer, n, &head));
    CHECK_I(head.start, engine.session.start);
    CHECK_I(head.end, engine.session.end);
    CHECK_I(head.rosc, engine.session.rosc);
    CHECK_I(head.event_count, engine.session.event_count);
    CHECK(head.weight_kg == engine.session.patient.weight_kg);
    CHECK_STR(head.protocol_name, engine.session.protocol_name);

    // A header read must also refuse a damaged file.
    CHECK(!cr_archive_peek(buffer, 3, &head));
}

// Port.emptyCodeSurvivesTheRoundTrip — GO, then ended, nothing logged.
static void test_empty_code_survives_the_round_trip(void)
{
    test_make_engine(&engine, START);
    cr_engine_end(&engine, T(5));
    const size_t n = cr_archive_encode(&engine.session, buffer, sizeof buffer);
    CHECK(n > 0);
    cr_session_t back;
    CHECK(cr_archive_decode(buffer, n, &back));
    CHECK_I(back.event_count, 0);
    CHECK_I(back.pause_count, 0);
    CHECK_I(back.rosc, CR_TIME_NONE);
    CHECK_I(back.end, T(5));
}

const cr_test_case_t cr_archive_tests[] = {
    { "Port.savedCodeComesBackExactly", test_saved_code_comes_back_exactly },
    { "Port.damagedArchiveIsRefused", test_damaged_archive_is_refused },
    { "Port.archiveSaysItsSizeWhenItDoesNotFit", test_archive_says_its_size_when_it_does_not_fit },
    { "Port.archiveHeadListsWithoutFullRead", test_archive_head_lists_without_full_read },
    { "Port.emptyCodeSurvivesTheRoundTrip", test_empty_code_survives_the_round_trip },
};
const size_t cr_archive_test_count = sizeof cr_archive_tests / sizeof cr_archive_tests[0];
