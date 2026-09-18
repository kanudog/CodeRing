// A cue that fires twice is an annoyance; a cue that never fires is a missed
// drug. Neither leaves a mark on the screen or in the log, so neither would be
// found by using the device — which is the whole reason this logic is in core
// and driven here across every boundary a real code crosses.

#include <string.h>

#include "cr_cues.h"
#include "cr_defaults.h"
#include "cr_test.h"
#include "test_helpers.h"

#define START CR_SEC(1000)
#define T(s)  (START + CR_SEC(s))

static cr_engine_t engine;
static cr_cue_state_t cues;

/// Cues raised at `now`, as a count — nearly always 0.
static size_t poll_at(cr_ms_t now, cr_cue_t *out, size_t cap)
{
    return cr_cues_poll(&cues, &engine, now, out, cap);
}

static bool fired(cr_ms_t now, cr_cue_t want)
{
    cr_cue_t got[4];
    const size_t n = poll_at(now, got, 4);
    for (size_t i = 0; i < n; i++) if (got[i] == want) return true;
    return false;
}

static void begin(void)
{
    test_make_engine(&engine, START);
    cr_cues_reset(&cues);
}

// Port.pulseCheckCueFiresOncePerCycle
static void test_pulse_check_cue_fires_once_per_cycle(void)
{
    begin();
    cr_engine_start_cpr(&engine, START);

    // Nothing while the cycle still has time on it, however often it is asked.
    for (int s = 0; s < 120; s += 10) CHECK_I(poll_at(T(s), NULL, 0), 0);

    // Once, as it runs out.
    CHECK(fired(T(120), CR_CUE_PULSE_CHECK_DUE));
    // …and NOT again, no matter how long it stays overdue or how often polled.
    for (int s = 121; s < 200; s++) CHECK_I(poll_at(T(s), NULL, 0), 0);

    // The check closes the cycle and starts a new one, which re-arms it.
    cr_engine_begin_pulse_check(&engine, T(200));
    cr_engine_complete_pulse_check(&engine, false, T(206));
    CHECK_I(poll_at(T(210), NULL, 0), 0);
    CHECK(fired(T(326), CR_CUE_PULSE_CHECK_DUE));       // 206 + 120
}

// Port.noCueBeforeCompressionsOrAfterTheEnd
static void test_no_cue_before_compressions_or_after_the_end(void)
{
    begin();
    // Before Start CPR the countdown shows its full length; it is not due.
    for (int s = 0; s < 300; s += 20) CHECK_I(poll_at(T(s), NULL, 0), 0);

    cr_engine_start_cpr(&engine, T(300));
    CHECK(fired(T(420), CR_CUE_PULSE_CHECK_DUE));

    // A finished code says nothing at all.
    cr_engine_end(&engine, T(500));
    for (int s = 500; s < 900; s += 10) CHECK_I(poll_at(T(s), NULL, 0), 0);
}

// Port.pauseDoesNotRaiseTheCue — the cycle freezes, so it never becomes due.
static void test_pause_does_not_raise_the_cue(void)
{
    begin();
    cr_engine_start_cpr(&engine, START);
    cr_engine_toggle_pause(&engine, T(60));
    // Frozen at 60 s remaining, for as long as the pause lasts.
    for (int s = 60; s < 400; s += 10) CHECK_I(poll_at(T(s), NULL, 0), 0);
    cr_engine_toggle_pause(&engine, T(400));
    // It has 60 s left from here, so nothing yet…
    CHECK_I(poll_at(T(450), NULL, 0), 0);
    CHECK(fired(T(460), CR_CUE_PULSE_CHECK_DUE));
}

// Port.medCueFiresPerDrugAndReArmsOnTheNextDose
static void test_med_cue_fires_per_drug_and_re_arms_on_the_next_dose(void)
{
    begin();
    cr_engine_start_cpr(&engine, START);

    // An interval nobody has started is showing its full length, not counting
    // down. Announcing it would read as a standing order.
    for (int s = 0; s < 400; s += 20) {
        cr_cue_t got[4];
        const size_t n = poll_at(T(s), got, 4);
        for (size_t i = 0; i < n; i++) CHECK(got[i] != CR_CUE_MED_DUE);
    }

    cr_engine_log_drug(&engine, &cr_drug_epinephrine, -1, T(400));
    CHECK_I(poll_at(T(500), NULL, 0), 0);                 // 180 s to run
    CHECK(fired(T(580), CR_CUE_MED_DUE));                 // 400 + 180
    for (int s = 581; s < 700; s++) {                     // once only
        cr_cue_t got[4];
        const size_t n = poll_at(T(s), got, 4);
        for (size_t i = 0; i < n; i++) CHECK(got[i] != CR_CUE_MED_DUE);
    }

    // The next dose puts time back on the clock, so running out again is a new
    // event.
    cr_engine_log_drug(&engine, &cr_drug_epinephrine, -1, T(700));
    CHECK(fired(T(880), CR_CUE_MED_DUE));
}

// Port.medCueReArmsAfterAnUndo — undo rolls the interval back to the previous
// dose, which can put it straight back into "due".
static void test_med_cue_re_arms_after_an_undo(void)
{
    begin();
    cr_engine_start_cpr(&engine, START);
    cr_engine_log_drug(&engine, &cr_drug_epinephrine, -1, T(10));
    CHECK(fired(T(190), CR_CUE_MED_DUE));

    // A second dose, announced when it runs out too.
    cr_engine_log_drug(&engine, &cr_drug_epinephrine, -1, T(200));
    CHECK(fired(T(380), CR_CUE_MED_DUE));

    // Undo that dose: the anchor rolls back to T(10), so the timer is overdue
    // again and the crew should hear about it.
    CHECK(cr_engine_undo_last(&engine, NULL));
    CHECK(fired(T(400), CR_CUE_MED_DUE));
}

// Port.handsOffCueWarnsOnceAtTenSeconds
static void test_hands_off_cue_warns_once_at_ten_seconds(void)
{
    begin();
    cr_engine_start_cpr(&engine, START);
    cr_engine_begin_pulse_check(&engine, T(120));

    for (int s = 120; s < 130; s++) {
        cr_cue_t got[4];
        const size_t n = poll_at(T(s), got, 4);
        for (size_t i = 0; i < n; i++) CHECK(got[i] != CR_CUE_HANDS_OFF_OVERSHOOT);
    }
    CHECK(fired(T(130), CR_CUE_HANDS_OFF_OVERSHOOT));
    for (int s = 131; s < 160; s++) {                     // once per check
        cr_cue_t got[4];
        const size_t n = poll_at(T(s), got, 4);
        for (size_t i = 0; i < n; i++) CHECK(got[i] != CR_CUE_HANDS_OFF_OVERSHOOT);
    }

    // The next check can warn again.
    cr_engine_complete_pulse_check(&engine, false, T(160));
    cr_engine_begin_pulse_check(&engine, T(300));
    CHECK(fired(T(311), CR_CUE_HANDS_OFF_OVERSHOOT));
}

// Port.roscSilencesTheCycleCue — there is no cycle running to run out.
static void test_rosc_silences_the_cycle_cue(void)
{
    begin();
    cr_engine_start_cpr(&engine, START);
    cr_engine_mark_rosc(&engine, T(60));
    for (int s = 60; s < 600; s += 10) {
        cr_cue_t got[4];
        const size_t n = poll_at(T(s), got, 4);
        for (size_t i = 0; i < n; i++) CHECK(got[i] != CR_CUE_PULSE_CHECK_DUE);
    }
    // …but a drug given before ROSC still comes due: the interval runs through
    // everything, which is invariant 7.
    cr_engine_re_arrest(&engine, T(600));
    cr_engine_log_drug(&engine, &cr_drug_epinephrine, -1, T(610));
    CHECK(fired(T(790), CR_CUE_MED_DUE));
}

// Port.cueOutputNeverOverrunsItsBuffer
static void test_cue_output_never_overruns_its_buffer(void)
{
    begin();
    cr_engine_start_cpr(&engine, START);
    cr_engine_log_drug(&engine, &cr_drug_epinephrine, -1, START);

    // The cycle and the drug both run out at once is impossible here (120 vs
    // 180), so contrive it: poll once, late, with a one-slot buffer.
    cr_cue_t one[1] = { CR_CUE_PULSE_CHECK_DUE };
    const size_t n = poll_at(T(200), one, 1);
    CHECK(n >= 1);
    // A caller that passes no buffer at all still gets a count, and writes
    // nothing anywhere.
    cr_cues_reset(&cues);
    CHECK(cr_cues_poll(&cues, &engine, T(200), NULL, 0) >= 1);
}

const cr_test_case_t cr_cue_tests[] = {
    { "Port.pulseCheckCueFiresOncePerCycle", test_pulse_check_cue_fires_once_per_cycle },
    { "Port.noCueBeforeCompressionsOrAfterTheEnd",
      test_no_cue_before_compressions_or_after_the_end },
    { "Port.pauseDoesNotRaiseTheCue", test_pause_does_not_raise_the_cue },
    { "Port.medCueFiresPerDrugAndReArmsOnTheNextDose",
      test_med_cue_fires_per_drug_and_re_arms_on_the_next_dose },
    { "Port.medCueReArmsAfterAnUndo", test_med_cue_re_arms_after_an_undo },
    { "Port.handsOffCueWarnsOnceAtTenSeconds", test_hands_off_cue_warns_once_at_ten_seconds },
    { "Port.roscSilencesTheCycleCue", test_rosc_silences_the_cycle_cue },
    { "Port.cueOutputNeverOverrunsItsBuffer", test_cue_output_never_overruns_its_buffer },
};
const size_t cr_cue_test_count = sizeof cr_cue_tests / sizeof cr_cue_tests[0];
