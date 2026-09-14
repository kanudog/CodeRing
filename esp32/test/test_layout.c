// Ported from FanLayoutTests and TopArcLayoutTests, re-expressed in panel
// pixels. The rules are Sebastian's, and every one of them exists because
// something went wrong on the wrist first:
//   • a bubble whose rim runs off the edge is a leaf that cannot be hit
//   • bubbles that touch make hover flap, which reads as "it logged nothing"
//   • a label is WIDER than its button, so label width sets the spacing
//   • an exit pad drawn under a puck makes ✕ re-open the menu it should close
//
// The old bloom-around-the-anchor cascade (RadialLayoutTests) is deliberately
// NOT here — see test/deferred_swift_tests.txt.

#include <math.h>
#include <string.h>

#include "cr_layout.h"
#include "cr_test.h"

static float distance(cr_pt_t a, cr_pt_t b)
{
    return sqrtf((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));
}

static bool rects_intersect(float ax1, float ay1, float ax2, float ay2,
                            float bx1, float by1, float bx2, float by2)
{
    return ax1 < bx2 && bx1 < ax2 && ay1 < by2 && by1 < ay2;
}

// FanLayoutTests.testSeededFansStillMatchTheTopArc
static void test_seeded_fans_still_match_the_top_arc(void)
{
    // A fan still on its seed must reproduce exactly what the arc computes.
    // Placing one by hand drops it out of this check, but never out of the
    // geometry checks below.
    for (size_t i = 0; i < cr_fan_count; i++) {
        const cr_fan_t *fan = &cr_fans[i];
        if (fan->placed) continue;
        cr_pt_t arc[CR_MAX_SLOTS];
        size_t n = cr_arc_positions(fan->seed_count, arc, CR_MAX_SLOTS);
        CHECK_I(n, fan->seed_count);
        cr_slot_t slots[CR_MAX_SLOTS];
        size_t got = cr_fan_slots(fan->key, fan->seed_count, slots, CR_MAX_SLOTS);
        CHECK_I(got, n);
        for (size_t s = 0; s < n; s++) {
            cr_pt_t want = cr_clamp_bubble(arc[s]);
            CHECK_NEAR(slots[s].center.x, want.x, 0.01);
            CHECK_NEAR(slots[s].center.y, want.y, 0.01);
        }
    }
}

// FanLayoutTests.testLabelsSitFourPointsUnderTheirButton
static void test_labels_sit_four_points_under_their_button(void)
{
    // 4 pt on the watch → 8.28 px here, measured from the button's EDGE so
    // the rule survives a change of button size.
    for (size_t i = 0; i < cr_fan_count; i++) {
        const cr_fan_t *fan = &cr_fans[i];
        if (fan->placed) continue;
        cr_slot_t slots[CR_MAX_SLOTS];
        size_t n = cr_fan_slots(fan->key, fan->seed_count, slots, CR_MAX_SLOTS);
        for (size_t s = 0; s < n; s++) {
            CHECK_NEAR(slots[s].label.x, slots[s].center.x, 0.01);
            float button_bottom = slots[s].center.y + slots[s].diameter / 2;
            float label_top = slots[s].label.y - cr_arc.label_box_height / 2;
            CHECK_NEAR(label_top - button_bottom, cr_arc.label_gap, 0.01);
        }
    }
}

// FanLayoutTests.testEveryButtonIsTheSameSize
static void test_every_button_is_the_same_size(void)
{
    // Ø44/25 pt on the watch → Ø91/52 px. Bubbles, ✕ and Back alike.
    for (size_t i = 0; i < cr_fan_count; i++) {
        for (uint8_t s = 0; s < cr_fans[i].slot_count; s++) {
            CHECK_NEAR(cr_fans[i].slots[s].diameter, 44 * CR_LAYOUT_SCALE, 0.01);
            CHECK_NEAR(cr_fans[i].slots[s].glyph, 25 * CR_LAYOUT_SCALE, 0.01);
        }
    }
    CHECK_NEAR(cr_screen.pads.cancel.diameter, 44 * CR_LAYOUT_SCALE, 0.01);
    CHECK_NEAR(cr_screen.pads.back.diameter, 44 * CR_LAYOUT_SCALE, 0.01);
    CHECK_NEAR(cr_screen.pads.cancel.glyph, 25 * CR_LAYOUT_SCALE, 0.01);
    CHECK_NEAR(cr_screen.pads.back.glyph, 25 * CR_LAYOUT_SCALE, 0.01);
}

// FanLayoutTests.testEveryBubbleIsFullyOnScreen
static void test_every_bubble_is_fully_on_screen(void)
{
    for (size_t i = 0; i < cr_fan_count; i++) {
        const cr_fan_t *fan = &cr_fans[i];
        for (uint8_t s = 0; s < fan->slot_count; s++) {
            const cr_slot_t *slot = &fan->slots[s];
            float r = slot->diameter / 2;
            CHECK(slot->center.x - r >= cr_screen.fan_origin.x - 0.01f);
            CHECK(slot->center.x + r <= cr_screen.fan_origin.x + cr_screen.fan_width + 0.01f);
            CHECK(slot->center.y - r >= cr_screen.fan_origin.y - 0.01f);
            CHECK(slot->center.y + r <= cr_screen.fan_origin.y + cr_screen.fan_height + 0.01f);
        }
    }
}

// FanLayoutTests.testBubblesNeverOverlap
static void test_bubbles_never_overlap(void)
{
    for (size_t i = 0; i < cr_fan_count; i++) {
        const cr_fan_t *fan = &cr_fans[i];
        for (uint8_t a = 0; a < fan->slot_count; a++) {
            for (uint8_t b = (uint8_t)(a + 1); b < fan->slot_count; b++) {
                float gap = distance(fan->slots[a].center, fan->slots[b].center);
                float need = (fan->slots[a].diameter + fan->slots[b].diameter) / 2;
                CHECK(gap >= need - 0.01f);
            }
        }
    }
}

// FanLayoutTests.testExitPadOverlapsAreExactlyTheDeliberateOnes
static void test_exit_pad_overlaps_are_exactly_the_deliberate_ones(void)
{
    // Pads MAY overlap what is beneath them — but only what was meant. ✕
    // sits deliberately in the gap between the Events and Shock pucks, which
    // at Ø91 clips both; Back sits on the Log button for the same reason.
    // Pinning the exact set means a NEW overlap fails loudly instead of
    // quietly becoming a dead control.
    const struct { const char *name; cr_disc_t disc; } controls[] = {
        { "meds puck", cr_screen.meds_puck },   { "events puck", cr_screen.events_puck },
        { "fluids puck", cr_screen.fluids_puck }, { "shock puck", cr_screen.shock_puck },
        { "log", cr_screen.log_button },        { "timers", cr_screen.timers_button },
        { "mute", cr_screen.mute_button },      { "flag", cr_screen.flag_button },
    };
    const struct { cr_disc_t pad; const char *expect[3]; } pads[] = {
        { cr_screen.pads.cancel, { "events puck", "shock puck", NULL } },
        { cr_screen.pads.back,   { "log", NULL, NULL } },
    };

    for (size_t p = 0; p < 2; p++) {
        for (size_t c = 0; c < sizeof controls / sizeof controls[0]; c++) {
            bool overlaps = distance(pads[p].pad.center, controls[c].disc.center) <
                            (pads[p].pad.diameter + controls[c].disc.diameter) / 2;
            bool expected = false;
            for (size_t e = 0; e < 3 && pads[p].expect[e] != NULL; e++) {
                if (strcmp(pads[p].expect[e], controls[c].name) == 0) expected = true;
            }
            CHECK(overlaps == expected);
        }
    }
}

// FanLayoutTests.testExitPadsClearEveryBubble
static void test_exit_pads_clear_every_bubble(void)
{
    const cr_disc_t pads[] = { cr_screen.pads.cancel, cr_screen.pads.back };
    for (size_t i = 0; i < cr_fan_count; i++) {
        const cr_fan_t *fan = &cr_fans[i];
        for (size_t p = 0; p < 2; p++) {
            for (uint8_t s = 0; s < fan->slot_count; s++) {
                float gap = distance(pads[p].center, fan->slots[s].center);
                CHECK(gap > (pads[p].diameter + fan->slots[s].diameter) / 2);
            }
        }
    }
}

// FanLayoutTests.testExitPadsAreOnScreen
static void test_exit_pads_are_on_screen(void)
{
    const cr_disc_t pads[] = { cr_screen.pads.cancel, cr_screen.pads.back };
    for (size_t p = 0; p < 2; p++) {
        float r = pads[p].diameter / 2;
        CHECK(pads[p].center.x - r >= 0);
        CHECK(pads[p].center.y - r >= 0);
        CHECK(pads[p].center.x + r <= cr_screen.width);
        CHECK(pads[p].center.y + r <= cr_screen.height);
    }
}

// FanLayoutTests.testLabelsStayOnScreen
static void test_labels_stay_on_screen(void)
{
    for (size_t i = 0; i < cr_fan_count; i++) {
        const cr_fan_t *fan = &cr_fans[i];
        for (uint8_t s = 0; s < fan->slot_count; s++) {
            CHECK(fan->slots[s].label.x >= cr_screen.fan_origin.x);
            CHECK(fan->slots[s].label.x <= cr_screen.fan_origin.x + cr_screen.fan_width);
            CHECK(fan->slots[s].label.y >= cr_screen.fan_origin.y);
            CHECK(fan->slots[s].label.y <= cr_screen.fan_origin.y + cr_screen.fan_height);
        }
    }
}

// FanLayoutTests.testLabelsNeverCoverAnotherButton
static void test_labels_never_cover_another_button(void)
{
    // Labels are WIDE: a centre label on a three-slot row reaches into both
    // neighbours. Estimate the rendered width the way the overlay lays it
    // out — ~0.62 em per character, capped at the wrap width.
    for (size_t i = 0; i < cr_fan_count; i++) {
        const cr_fan_t *fan = &cr_fans[i];
        for (uint8_t a = 0; a < fan->slot_count; a++) {
            const cr_slot_t *label = &fan->slots[a];
            size_t chars = (fan->titles != NULL && a < fan->title_count)
                               ? strlen(fan->titles[a]) : 10;
            float w = (float)chars * label->label_font * 0.62f;
            if (w > label->label_width) w = label->label_width;
            w += 8 * CR_LAYOUT_SCALE;
            float h = cr_arc.label_box_height;

            for (uint8_t b = 0; b < fan->slot_count; b++) {
                if (b == a) continue;
                const cr_slot_t *other = &fan->slots[b];
                // 1 pt of slack, as in the Swift test: a real collision is
                // points, not tenths, and labels draw after bubbles so their
                // own background covers a hairline.
                float inset = 1 * CR_LAYOUT_SCALE;
                CHECK(!rects_intersect(
                    label->label.x - w / 2, label->label.y - h / 2,
                    label->label.x + w / 2, label->label.y + h / 2,
                    other->center.x - other->diameter / 2 + inset,
                    other->center.y - other->diameter / 2 + inset,
                    other->center.x + other->diameter / 2 - inset,
                    other->center.y + other->diameter / 2 - inset));
            }
        }
    }
}

// FanLayoutTests.testLookupRefusesACountMismatch
static void test_lookup_refuses_a_count_mismatch(void)
{
    CHECK(cr_fan_find("events", 6) != NULL);
    // A custom event was added — that fan must fall back to the computed arc.
    CHECK(cr_fan_find("events", 7) == NULL);
    CHECK(cr_fan_find("no.such.fan", 3) == NULL);

    // …and falling back still produces a usable fan.
    cr_slot_t slots[CR_MAX_SLOTS];
    size_t n = cr_fan_slots("events", 7, slots, CR_MAX_SLOTS);
    CHECK_I(n, 7);
    for (size_t i = 0; i < n; i++) {
        CHECK(slots[i].center.x > cr_screen.fan_origin.x);
        CHECK(slots[i].center.x < cr_screen.fan_origin.x + cr_screen.fan_width);
    }
}

// FanLayoutTests.testTableCoversEveryFanAtItsRealCount
static void test_table_covers_every_fan_at_its_real_count(void)
{
    // The inventory itself, so a menu-tree edit that changes a fan's size
    // fails here instead of silently falling back to the arc on the wrist.
    const struct { const char *key; uint8_t count; } expected[] = {
        { "code", 5 }, { "shock", 2 }, { "support", 5 }, { "events", 6 },
        { "events.rosc", 5 }, { "grp:defib", 3 }, { "grp:fluids", 3 },
        { "grp:more", 3 }, { "grp:access", 3 }, { "grp:airway", 4 },
        { "grp:comms", 2 }, { "grp:temp", 3 }, { "grp:call", 4 }, { "grp:arrival", 4 },
    };
    size_t want = sizeof expected / sizeof expected[0];
    CHECK_I(cr_fan_count, want);
    for (size_t i = 0; i < want; i++) {
        const cr_fan_t *fan = cr_fan_find(expected[i].key, expected[i].count);
        CHECK(fan != NULL);
        if (fan != NULL) CHECK_I(fan->slot_count, expected[i].count);
    }
}

// TopArcLayoutTests.testArcSlotsAreFixedPitchAndOnScreen
static void test_arc_slots_are_fixed_pitch_and_on_screen(void)
{
    // Fixed slots are the whole point — a 2-item fan and a 4-item fan must
    // share pitch and row height so muscle memory survives across fans.
    for (uint8_t count = 1; count <= 6; count++) {
        cr_pt_t points[CR_MAX_SLOTS];
        size_t n = cr_arc_positions(count, points, CR_MAX_SLOTS);
        CHECK_I(n, count);
        for (size_t i = 0; i < n; i++) {
            CHECK(points[i].x >= cr_screen.fan_origin.x + 18 * CR_LAYOUT_SCALE - 0.01f);
            CHECK(points[i].x <= cr_screen.fan_origin.x + cr_screen.fan_width
                                     - 18 * CR_LAYOUT_SCALE + 0.01f);
            CHECK(points[i].y >= cr_screen.fan_origin.y + 16 * CR_LAYOUT_SCALE - 0.01f);
        }
        // Neighbours within a row never come closer than a bubble width.
        uint8_t top = cr_arc_top_row_count(count);
        for (uint8_t i = 1; i < top; i++) {
            CHECK(distance(points[i], points[i - 1]) >= 40 * CR_LAYOUT_SCALE);
        }
    }
}

// Port.layoutMatchesTheHandoffTable — the numbers the handoff doc promises,
// so a change of scale factor cannot slip through unnoticed.
static void test_layout_matches_the_handoff_table(void)
{
    CHECK_NEAR(cr_screen.width, 410.0f, 0.5);
    CHECK_NEAR(cr_screen.height, 502.0f, 1.0);
    CHECK_NEAR(cr_screen.pads.cancel.center.x, 205.0f, 1.0);   // ✕ at (205, 414)
    CHECK_NEAR(cr_screen.pads.cancel.center.y, 414.0f, 1.0);
    CHECK_NEAR(cr_screen.pads.back.center.x, 66.0f, 1.0);      // Back at (66, 66)
    CHECK_NEAR(cr_screen.pads.back.center.y, 66.0f, 1.0);
    CHECK_NEAR(cr_arc.bubble_diameter, 91.0f, 0.5);            // Ø91, glyph 52
    CHECK_NEAR(cr_arc.glyph, 52.0f, 0.5);
    CHECK_NEAR(cr_arc.label_gap, 8.0f, 0.5);                   // ≈8 px under the edge

    // Every fan with a readout puts its title chip at the top centre.
    for (size_t i = 0; i < cr_fan_count; i++) {
        if (!cr_fans[i].readout.present) continue;
        CHECK_NEAR(cr_fans[i].readout.center.x, 205.0f, 1.5);
        CHECK_NEAR(cr_fans[i].readout.center.y, 52.0f, 1.5);
    }
}

const cr_test_case_t cr_layout_tests[] = {
    { "FanLayoutTests.testSeededFansStillMatchTheTopArc", test_seeded_fans_still_match_the_top_arc },
    { "FanLayoutTests.testLabelsSitFourPointsUnderTheirButton",
      test_labels_sit_four_points_under_their_button },
    { "FanLayoutTests.testEveryButtonIsTheSameSize", test_every_button_is_the_same_size },
    { "FanLayoutTests.testEveryBubbleIsFullyOnScreen", test_every_bubble_is_fully_on_screen },
    { "FanLayoutTests.testBubblesNeverOverlap", test_bubbles_never_overlap },
    { "FanLayoutTests.testExitPadOverlapsAreExactlyTheDeliberateOnes",
      test_exit_pad_overlaps_are_exactly_the_deliberate_ones },
    { "FanLayoutTests.testExitPadsClearEveryBubble", test_exit_pads_clear_every_bubble },
    { "FanLayoutTests.testExitPadsAreOnScreen", test_exit_pads_are_on_screen },
    { "FanLayoutTests.testLabelsStayOnScreen", test_labels_stay_on_screen },
    { "FanLayoutTests.testLabelsNeverCoverAnotherButton", test_labels_never_cover_another_button },
    { "FanLayoutTests.testLookupRefusesACountMismatch", test_lookup_refuses_a_count_mismatch },
    { "FanLayoutTests.testTableCoversEveryFanAtItsRealCount",
      test_table_covers_every_fan_at_its_real_count },
    { "TopArcLayoutTests.testArcSlotsAreFixedPitchAndOnScreen",
      test_arc_slots_are_fixed_pitch_and_on_screen },
    { "Port.layoutMatchesTheHandoffTable", test_layout_matches_the_handoff_table },
};
const size_t cr_layout_test_count = sizeof cr_layout_tests / sizeof cr_layout_tests[0];
