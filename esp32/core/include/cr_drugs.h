// cr_drugs.h — drug profiles and the dose maths (CodeCore/Models/Drugs.swift).
//
// A drug profile is pure data: dose steps, caps, concentration, colour. The
// calculator turns (profile, weight) into a capped amount AND a volume. mL
// is the featured number because that is what gets drawn up (invariant 2):
// render `cr_dose_volume_text` big and `cr_dose_amount_text` small.
// DEMO values only.

#ifndef CR_DRUGS_H
#define CR_DRUGS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef enum {
    CR_UNIT_MG_PER_KG,
    CR_UNIT_J_PER_KG,
    CR_UNIT_ML_PER_KG,   // volume-dosed (fluids, bicarb, dextrose) — mL IS the number
} cr_dose_unit_t;

const char *cr_dose_unit_amount_suffix(cr_dose_unit_t unit);   // "mg" / "J" / "mL"
const char *cr_dose_unit_per_kg_suffix(cr_dose_unit_t unit);   // "mg/kg" / …

#define CR_MAX_DOSE_STEPS 4

/// One rung of a dose ladder (adenosine 1st vs 2nd, defib 2 → 4 → 10 J/kg).
typedef struct {
    const char *label;       // "1st", "Subsequent", "Bolus"
    double per_kg;
    bool has_max;            // false = uncapped (Swift maxAbsolute == nil)
    double max_absolute;     // cap in mg, J or mL
} cr_dose_step_t;

typedef struct {
    const char *id;          // stable UUID string — invariant 1
    const char *name;
    const char *subtitle;    // concentration text, e.g. "0.1 mg/mL (1:10,000)"
    cr_dose_unit_t unit;
    cr_dose_step_t steps[CR_MAX_DOSE_STEPS];
    uint8_t step_count;
    double concentration_mg_per_ml;   // 0 = none (energy and volume doses)
    uint32_t color;
    const char *symbol;      // SF Symbol name; keys the icon asset on the panel
    bool resets_interval;    // giving this restarts its interval timer (epi)
    const char *notes;
} cr_drug_t;

typedef struct {
    const char *id;
    const char *name;
    const cr_drug_t *const *drugs;
    uint8_t drug_count;
    bool is_built_in;
} cr_drug_set_t;

const cr_drug_t *cr_drug_set_find(const cr_drug_set_t *set, const char *id);

/// A computed, capped dose for one step at one weight.
typedef struct {
    const char *step_label;  // points into the drug's static step table
    double amount;           // mg, J or mL after cap + rounding
    bool has_volume;
    double volume_ml;        // rounded to 0.1 mL; floor 0.1 for anything nonzero
    cr_dose_unit_t unit;
    bool capped;
} cr_dose_t;

/// Fills `out` with every step's dose. Returns the drug's step count
/// (writes at most `cap`).
size_t cr_doses(const cr_drug_t *drug, double weight_kg, cr_dose_t *out, size_t cap);

/// The step a one-tap log uses: prior administrations advance the ladder,
/// then it holds the last rung. False when the drug has no steps.
bool cr_primary_dose(const cr_drug_t *drug, double weight_kg, int prior_count, cr_dose_t *out);

/// mg: <1 → 2 dp, <10 → 1 dp, else whole. Joules → whole. mL → 0.1 mL.
double cr_rounded_amount(double value, cr_dose_unit_t unit);

/// 0.1 mL resolution with a 0.1 mL floor, so a tiny dose never reads "0 mL".
double cr_rounded_volume(double value);

/// "0.8 mL" — the featured number. False (buf = "") when there is no volume.
bool cr_dose_volume_text(const cr_dose_t *dose, char *buf, size_t cap);

/// "0.08 mg" or "16 J" — the secondary number.
void cr_dose_amount_text(const cr_dose_t *dose, char *buf, size_t cap);

/// One-line summary for event details: "0.8 mL  (0.08 mg)", "240 mL",
/// "24 J", each with " · capped" when the cap bit.
void cr_dose_summary(const cr_dose_t *dose, char *buf, size_t cap);

#endif
