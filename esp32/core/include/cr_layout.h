// cr_layout.h — the hand-placed layout, in panel pixels.
//
// Sebastian placed every control by hand in the Layout Bench; WatchLayout
// and FanLayout hold those literals in Swift. This is the same geometry,
// generated from those files by esp32/tools/gen_layout.js — not retyped, so
// re-placing a fan in the Bench and re-running the generator is the whole
// update path.
//
// ONE COORDINATE SPACE. watchOS forced two — the screen (198 × 242 pt) and
// a fan layer inset (2, 51) — because of a SwiftUI hit-testing artefact.
// That split does not port. Everything here is already in panel pixels:
//
//     screen_pt → px   = pt × 2.071
//     fan_pt    → px   = (pt + (2, 51)) × 2.071
//
// The two screens share an aspect ratio (0.8182 vs 0.8167), so one uniform
// factor lands the bottom edge under a pixel off. Never convert by hand —
// the generator has done it.

#ifndef CR_LAYOUT_H
#define CR_LAYOUT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/// watchOS point → panel pixel. 198 × 2.071 = 410.06, 242 × 2.071 = 501.2.
#define CR_LAYOUT_SCALE 2.071f

typedef struct { float x, y; } cr_pt_t;

/// A circular control: filled disc with a centred glyph.
typedef struct {
    cr_pt_t center;
    float diameter;
    float glyph;        // icon size; the icon set is rasterised at 52 px
} cr_disc_t;

/// A text run. `w`/`h` is the box it occupies — text scales down inside it
/// rather than pushing neighbours around.
typedef struct {
    cr_pt_t center;
    float w, h;
    float font;
} cr_text_t;

typedef struct {
    cr_pt_t center;
    float diameter;
    float stroke;       // straddles the path: visual extent is ±stroke/2
} cr_ring_t;

/// A med timer chip, anchored TOP-LEFT because its column grid is top-aligned.
typedef struct {
    cr_pt_t origin;
    float w, h;
    bool trailing;
    float name_font;
} cr_chip_t;

/// One fan item: a bubble plus the label hanging under it. The label carries
/// an ABSOLUTE centre, not an offset, so it can be nudged out from under a
/// crowded neighbour without moving the bubble.
typedef struct {
    cr_pt_t center;
    float diameter;
    float glyph;
    cr_pt_t label;
    float label_font;
    float label_width;   // wraps to two lines rather than shrinking
    int z;               // draw order, low to high
} cr_slot_t;

#define CR_MAX_SLOTS 8

/// The hovered-item readout chip. nil in the fans where five buttons already
/// fill the screen and each caption says what the chip would have said.
typedef struct {
    bool present;
    cr_pt_t center;
    float font;
    float crumb_font;
    /// Seeded fans put the chip on the side away from the puck that opened
    /// them — a property of the anchor, not the fan. A hand-placed fan pins
    /// the x instead, because by then it is a decision rather than a rule.
    bool follow_anchor;
} cr_readout_t;

typedef struct {
    const char *key;
    const char *title;           // what the chip at the top of the fan says
    const cr_slot_t *slots;
    uint8_t slot_count;
    cr_readout_t readout;
    /// false = still on its top-arc seed, computed at runtime rather than
    /// stored. Only seeded fans are held to "must equal the top arc".
    bool placed;
    uint8_t seed_count;
    const char *const *titles;   // slot order; labels are sized from these
    uint8_t title_count;
} cr_fan_t;

extern const cr_fan_t cr_fans[];
extern const size_t cr_fan_count;

/// Count-exact on purpose: the defib ladder and the events fan are built at
/// runtime, and stretching a 6-slot placement over 7 items would drop the
/// last one somewhere undefined. NULL means "fall back to the top arc".
const cr_fan_t *cr_fan_find(const char *key, size_t count);

/// The shared exit pads. They never move: ✕ and Back sit in the same place
/// in every fan at every depth, so exiting is one learned reach.
typedef struct {
    cr_disc_t cancel;
    cr_disc_t back;      // depth >= 2 only
    float hover_radius;  // how close the finger must come to hover an item
} cr_pads_t;

/// The live session screen, all of it.
typedef struct {
    float width, height;
    /// The box the fans are laid out in, already in panel pixels.
    cr_pt_t fan_origin;
    float fan_width, fan_height;

    cr_disc_t log_button, timers_button, pause_button, mute_button, flag_button;
    cr_disc_t meds_puck, events_puck, fluids_puck, shock_puck;
    cr_disc_t tap_glyph, rosc_heart;

    cr_ring_t cpr_ring, drug_ring, vitals_ring;

    cr_text_t total_label, code_clock, cycle_chip, patient, start_text;
    cr_text_t pulse_label, countdown, drug_line, toast, paused_text;
    cr_text_t vitals_label, vitals_count, rosc_elapsed, vitals_prompt;
    cr_text_t re_arrest, handoff;

    cr_chip_t chips[6];
    uint8_t chip_count;
    float chip_count_font, chip_timer_font;

    cr_pads_t pads;
} cr_screen_t;

extern const cr_screen_t cr_screen;

// MARK: - The computed arrangement (TopArcLayout)

/// Fixed slots the wearer can learn: items ride one or two rows near the
/// TOP, clear of the lower-right quadrant the wearer's own finger covers.
/// (The old bloom-around-the-anchor cascade does NOT port — Sebastian
/// replaced it for exactly that reason.)
typedef struct {
    float slot_pitch;
    float apex_y;        // first row centre, in panel pixels
    float row_gap;
    float arc_drop;      // the ends fall this far below the row's centre
    float side_inset;
    float label_gap;     // bubble EDGE to the top of the label box
    float label_box_height;
    float bubble_diameter;
    float glyph;
    float label_font;
    float label_width;
    uint8_t max_per_row;
} cr_arc_spec_t;

extern const cr_arc_spec_t cr_arc;

uint8_t cr_arc_top_row_count(uint8_t count);

/// Bubble centres for `count` items, left-to-right then top-to-bottom.
/// Writes at most `cap`; returns how many it wrote.
size_t cr_arc_positions(uint8_t count, cr_pt_t *out, size_t cap);

/// Label centre for a bubble: straight below it, sharing its x, measured
/// from the bubble's EDGE so the visible gap survives a resize.
cr_pt_t cr_arc_label_position(cr_pt_t bubble, float diameter, float label_height);

/// The clamps the overlay applies before drawing, baked in so a hand-placed
/// fan and a seeded one are measured the same way.
cr_pt_t cr_clamp_bubble(cr_pt_t p);
cr_pt_t cr_clamp_label(cr_pt_t p);

/// Builds a fan's slots: the stored placement when one exists for this exact
/// count, otherwise the computed arc. Returns the number of slots.
size_t cr_fan_slots(const char *key, uint8_t count, cr_slot_t *out, size_t cap);

#endif
