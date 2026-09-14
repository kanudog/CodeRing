#include "cr_defaults.h"

#include <string.h>

#include "cr_theme.h"

// MARK: - Drugs (key meds only — rare items arrive later from the phone)

const cr_drug_t cr_drug_epinephrine = {
    .id = CR_ID_EPI,
    .name = "Epinephrine",
    .subtitle = "0.1 mg/mL (1:10,000)",
    .unit = CR_UNIT_MG_PER_KG,
    .steps = { { .label = "IV/IO", .per_kg = 0.01, .has_max = true, .max_absolute = 1.0 } },
    .step_count = 1,
    .concentration_mg_per_ml = 0.1,
    .color = CR_THEME_MED,
    .symbol = "syringe.fill",
    .resets_interval = true,
    .notes = "Repeat q3–5 min. Demo values.",
};

// The rhythm/code meds all wear the group's RED so their timers read as one
// family; the chip abbreviation, not the hue, tells them apart.
const cr_drug_t cr_drug_atropine = {
    .id = CR_ID_ATROPINE,
    .name = "Atropine",
    .subtitle = "0.1 mg/mL",
    .unit = CR_UNIT_MG_PER_KG,
    .steps = { { .label = "IV/IO", .per_kg = 0.02, .has_max = true, .max_absolute = 0.5 } },
    .step_count = 1,
    .concentration_mg_per_ml = 0.1,
    .color = CR_THEME_MED,
    .symbol = "hare.fill",
    .notes = "Bradycardia (vagal / AV block). 0.02 mg/kg, may repeat once. Demo values.",
};

const cr_drug_t cr_drug_adenosine = {
    .id = CR_ID_ADENOSINE,
    .name = "Adenosine",
    .subtitle = "3 mg/mL — rapid push",
    .unit = CR_UNIT_MG_PER_KG,
    .steps = {
        { .label = "1st", .per_kg = 0.1, .has_max = true, .max_absolute = 6 },
        { .label = "2nd", .per_kg = 0.2, .has_max = true, .max_absolute = 12 },
    },
    .step_count = 2,
    .concentration_mg_per_ml = 3,
    .color = CR_THEME_MED,
    .symbol = "pause.circle.fill",
    .notes = "SVT. 0.1 then 0.2 mg/kg, rapid flush. Demo values.",
};

const cr_drug_t cr_drug_amiodarone = {
    .id = CR_ID_AMIO,
    .name = "Amiodarone",
    .subtitle = "50 mg/mL",
    .unit = CR_UNIT_MG_PER_KG,
    .steps = { { .label = "Bolus", .per_kg = 5.0, .has_max = true, .max_absolute = 300 } },
    .step_count = 1,
    .concentration_mg_per_ml = 50,
    .color = CR_THEME_MED,
    .symbol = "tortoise.fill",
    .notes = "VF/pVT. 5 mg/kg, may repeat ×2 (max 15 mg/kg/day). Demo values.",
};

const cr_drug_t cr_drug_lidocaine = {
    .id = CR_ID_LIDOCAINE,
    .name = "Lidocaine",
    .subtitle = "20 mg/mL (2%)",
    .unit = CR_UNIT_MG_PER_KG,
    .steps = { { .label = "Bolus", .per_kg = 1.0, .has_max = true, .max_absolute = 100 } },
    .step_count = 1,
    .concentration_mg_per_ml = 20,
    .color = CR_THEME_MED,
    .symbol = "waveform.slash",
    .notes = "VF/pVT alternative to amiodarone. 1 mg/kg. Demo values.",
};

const cr_drug_t cr_drug_defibrillation = {
    .id = CR_ID_DEFIB,
    .name = "Defibrillation",
    .subtitle = "Biphasic",
    .unit = CR_UNIT_J_PER_KG,
    .steps = {
        { .label = "1st",        .per_kg = 2,  .has_max = true, .max_absolute = 200 },
        { .label = "Subsequent", .per_kg = 4,  .has_max = true, .max_absolute = 200 },
        { .label = "Max",        .per_kg = 10, .has_max = true, .max_absolute = 200 },
    },
    .step_count = 3,
    .color = CR_THEME_SHOCK,
    .symbol = "bolt.fill",
    .notes = "2 J/kg, then 4 J/kg, up to 10 J/kg. Demo values.",
};

// MARK: - Volume / support meds (blue group)

const cr_drug_t cr_drug_fluids = {
    .id = CR_ID_FLUIDS,
    .name = "Fluid bolus",
    .subtitle = "Isotonic crystalloid",
    .unit = CR_UNIT_ML_PER_KG,
    .steps = {
        { .label = "10 mL/kg", .per_kg = 10 },
        { .label = "20 mL/kg", .per_kg = 20, .has_max = true, .max_absolute = 2000 },
    },
    .step_count = 2,
    .color = CR_THEME_VOLUME,
    .symbol = "drop.fill",
    .notes = "10–20 mL/kg; reassess after each. Demo values.",
};

const cr_drug_t cr_drug_dextrose = {
    .id = CR_ID_DEXTROSE,
    .name = "Dextrose",
    .subtitle = "D25 (250 mg/mL)",
    .unit = CR_UNIT_ML_PER_KG,
    .steps = { { .label = "D25", .per_kg = 2, .has_max = true, .max_absolute = 100 } },
    .step_count = 1,
    .color = CR_THEME_VOLUME,
    .symbol = "cube.fill",
    .notes = "Hypoglycemia: 0.5 g/kg = 2 mL/kg of D25. Demo values.",
};

const cr_drug_t cr_drug_calcium = {
    .id = CR_ID_CALCIUM,
    .name = "Calcium",
    .subtitle = "CaCl₂ 100 mg/mL",
    .unit = CR_UNIT_MG_PER_KG,
    .steps = { { .label = "CaCl₂", .per_kg = 20, .has_max = true, .max_absolute = 1000 } },
    .step_count = 1,
    .concentration_mg_per_ml = 100,
    .color = CR_THEME_VOLUME,
    .symbol = "diamond.fill",
    .notes = "20 mg/kg calcium chloride (hyperK, hypoCa, CCB). Demo values.",
};

const cr_drug_t cr_drug_bicarb = {
    .id = CR_ID_BICARB,
    .name = "Bicarb",
    .subtitle = "8.4% (1 mEq/mL)",
    .unit = CR_UNIT_ML_PER_KG,
    .steps = { { .label = "1 mEq/kg", .per_kg = 1, .has_max = true, .max_absolute = 50 } },
    .step_count = 1,
    .color = CR_THEME_VOLUME,
    .symbol = "bubbles.and.sparkles.fill",
    .notes = "1 mEq/kg = 1 mL/kg of 8.4%. Demo values.",
};

const cr_drug_t cr_drug_magnesium = {
    .id = CR_ID_MAGNESIUM,
    .name = "Magnesium",
    .subtitle = "500 mg/mL",
    .unit = CR_UNIT_MG_PER_KG,
    .steps = { { .label = "Sulfate", .per_kg = 50, .has_max = true, .max_absolute = 2000 } },
    .step_count = 1,
    .concentration_mg_per_ml = 500,
    .color = CR_THEME_VOLUME,
    .symbol = "hexagon.fill",
    .notes = "Torsades / hypoMg: 25–50 mg/kg (max 2 g). Demo values.",
};

const cr_drug_t cr_drug_naloxone = {
    .id = CR_ID_NALOXONE,
    .name = "Naloxone",
    .subtitle = "0.4 mg/mL",
    .unit = CR_UNIT_MG_PER_KG,
    .steps = { { .label = "IV/IO", .per_kg = 0.1, .has_max = true, .max_absolute = 2 } },
    .step_count = 1,
    .concentration_mg_per_ml = 0.4,
    .color = CR_THEME_VOLUME,
    .symbol = "nose.fill",
    .notes = "Opioid reversal: 0.1 mg/kg (max 2 mg). Demo values.",
};

const cr_drug_t cr_drug_examplitol = {
    .id = CR_ID_EXAMPLITOL,
    .name = "Examplitol",
    .subtitle = "2 mg/mL — fictional",
    .unit = CR_UNIT_MG_PER_KG,
    .steps = { { .label = "Sample", .per_kg = 0.5, .has_max = true, .max_absolute = 20 } },
    .step_count = 1,
    .concentration_mg_per_ml = 2,
    .color = CR_THEME_CARE,
    .symbol = "testtube.2",
    .notes = "Not a real medication. Duplicate me to build your own.",
};

static const cr_drug_t *const pals_drugs[] = {
    // Rhythm/code (red)
    &cr_drug_epinephrine, &cr_drug_atropine, &cr_drug_adenosine,
    &cr_drug_amiodarone, &cr_drug_lidocaine,
    // Shock (amber)
    &cr_drug_defibrillation,
    // Volume/support (blue)
    &cr_drug_fluids, &cr_drug_dextrose, &cr_drug_calcium,
    &cr_drug_bicarb, &cr_drug_magnesium, &cr_drug_naloxone,
};

const cr_drug_set_t cr_pals_drug_set = {
    .id = CR_ID_PALS_SET,
    .name = "PALS Default (Demo)",
    .drugs = pals_drugs,
    .drug_count = sizeof pals_drugs / sizeof pals_drugs[0],
    .is_built_in = true,
};

// MARK: - Events

const cr_event_def_t cr_builtin_events[] = {
    { .id = "rhythm.check", .title = "Rhythm check", .category = CR_CAT_RHYTHM,
      .symbol = "waveform.path.ecg", .is_built_in = true },
    // Access is one parent with four limbs, no IV/IO split. The id keeps its
    // historical "access.iv" key — stable ids outlive names.
    { .id = "access.iv", .title = "Access", .category = CR_CAT_ACCESS,
      .symbol = "cross.circle.fill",
      .sub_options = { "R leg", "R arm", "L arm", "L leg" }, .sub_option_count = 4,
      .is_built_in = true },
    { .id = "airway.ett", .title = "Intubation", .category = CR_CAT_AIRWAY,
      .symbol = "lungs.fill", .is_built_in = true },
    { .id = "cpr.swap", .title = "Compressor swap", .category = CR_CAT_CPR,
      .symbol = "arrow.triangle.2.circlepath", .is_built_in = true },
    { .id = "med.blood", .title = "Blood given", .category = CR_CAT_MEDICATION,
      .symbol = "drop.circle.fill", .is_built_in = true },
    { .id = "temp.mgmt", .title = "Temp mgmt", .category = CR_CAT_CARE,
      .symbol = "thermometer.variable.and.figure",
      .sub_options = { "Fluid warmer", "Bair Hugger", "Arctic Sun", "Warmed blankets" },
      .sub_option_count = 4, .is_built_in = true },
    { .id = "outcome.rosc", .title = "ROSC", .category = CR_CAT_OUTCOME,
      .symbol = "heart.fill", .is_built_in = true },

    // Non-defib shock modalities — leaves of the SHOCK fan.
    { .id = "shock.sync", .title = "Cardioversion", .category = CR_CAT_DEFIBRILLATION,
      .symbol = "bolt.circle.fill", .is_built_in = true },
    { .id = "shock.pace", .title = "Pacing started", .category = CR_CAT_DEFIBRILLATION,
      .symbol = "waveform.circle.fill", .is_built_in = true },

    // Post-ROSC care set — only offered while in ROSC (the "rosc." prefix is
    // how the events fan swaps over).
    { .id = "rosc.infusion", .title = "Pressor infusion", .category = CR_CAT_MEDICATION,
      .symbol = "ivfluid.bag", .is_built_in = true },
    { .id = "rosc.bolus", .title = "Fluid bolus", .category = CR_CAT_MEDICATION,
      .symbol = "drop.fill", .is_built_in = true },
    { .id = "rosc.vent", .title = "Vent change", .category = CR_CAT_AIRWAY,
      .symbol = "lungs.fill", .is_built_in = true },
    { .id = "rosc.temp", .title = "Temperature", .category = CR_CAT_RHYTHM,
      .symbol = "thermometer.medium", .is_built_in = true },
    { .id = "rosc.glucose", .title = "Glucose", .category = CR_CAT_RHYTHM,
      .symbol = "testtube.2", .is_built_in = true },
    { .id = "rosc.sedation", .title = "Sedation", .category = CR_CAT_MEDICATION,
      .symbol = "moon.zzz.fill", .is_built_in = true },
    { .id = "rosc.ecg", .title = "12-lead ECG", .category = CR_CAT_RHYTHM,
      .symbol = "waveform.path.ecg.rectangle", .is_built_in = true },
};
const size_t cr_builtin_event_count = sizeof cr_builtin_events / sizeof cr_builtin_events[0];

const cr_event_def_t *cr_builtin_event(const char *id)
{
    if (id == NULL) return NULL;
    for (size_t i = 0; i < cr_builtin_event_count; i++) {
        if (strcmp(cr_builtin_events[i].id, id) == 0) return &cr_builtin_events[i];
    }
    return NULL;
}

// MARK: - Protocols

// Every PALS variant currently shares the arrest scaffolding: same timers,
// same drugs, same events. The variant carries identity only, so the picker,
// the header and the record read correctly. Algorithm-specific flows come
// later — that is a demo simplification, and adding one is a data change.
#define CR_ARREST_SCAFFOLD                                                          \
    .timers = {                                                                     \
        { .id = "timer.cpr", .role = CR_TIMER_CPR_CYCLE, .title = "CPR",            \
          .duration_ms = CR_SEC(120), .color = CR_THEME_CPR },                      \
        { .id = "timer.epi", .role = CR_TIMER_DRUG_INTERVAL, .title = "EPI",        \
          .duration_ms = CR_SEC(180), .window_ms = CR_SEC(300),                     \
          .linked_drug_id = CR_ID_EPI, .color = CR_THEME_MED },                     \
        { .id = "timer.vitals", .role = CR_TIMER_POST_ROSC_VITALS, .title = "VITALS", \
          .duration_ms = CR_SEC(300), .color = CR_THEME_ROSC },                     \
    },                                                                              \
    .timer_count = 3,                                                               \
    .event_ids = { "rhythm.check", "access.iv", "outcome.rosc", "cpr.swap",         \
                   "airway.ett", "rosc.bolus", "med.blood", "temp.mgmt" },           \
    .event_id_count = 8,                                                            \
    .drug_set_id = CR_ID_PALS_SET

const cr_protocol_t cr_protocol_pals_arrest = {
    .id = "pals.arrest", .name = "Cardiac Arrest", .short_name = "ARREST",
    .symbol = "heart.slash.fill", CR_ARREST_SCAFFOLD
};

// Cardiac arrest refinements
static const cr_protocol_t pals_arrest_shockable = {
    .id = "pals.arrest.shockable", .name = "VF / pVT", .short_name = "VF/pVT",
    .symbol = "bolt.heart.fill", CR_ARREST_SCAFFOLD
};
static const cr_protocol_t pals_arrest_nonshock = {
    .id = "pals.arrest.nonshock", .name = "PEA / Asystole", .short_name = "PEA",
    .symbol = "minus.circle.fill", CR_ARREST_SCAFFOLD
};
// Bradycardia / tachycardia (with pulse)
static const cr_protocol_t pals_brady = {
    .id = "pals.brady", .name = "Bradycardia", .short_name = "BRADY",
    .symbol = "arrow.down.heart.fill", CR_ARREST_SCAFFOLD
};
static const cr_protocol_t pals_tachy = {
    .id = "pals.tachy", .name = "Tachycardia", .short_name = "TACHY",
    .symbol = "arrow.up.heart.fill", CR_ARREST_SCAFFOLD
};
static const cr_protocol_t pals_tachy_svt = {
    .id = "pals.tachy.svt", .name = "SVT (narrow QRS)", .short_name = "SVT",
    .symbol = "arrow.up.heart.fill", CR_ARREST_SCAFFOLD
};
static const cr_protocol_t pals_tachy_vt = {
    .id = "pals.tachy.vt", .name = "VT with pulse", .short_name = "VT",
    .symbol = "waveform.path.ecg", CR_ARREST_SCAFFOLD
};
// Respiratory
static const cr_protocol_t pals_resp = {
    .id = "pals.resp", .name = "Respiratory", .short_name = "RESP",
    .symbol = "lungs.fill", CR_ARREST_SCAFFOLD
};
static const cr_protocol_t pals_resp_arrest = {
    .id = "pals.resp.arrest", .name = "Resp arrest", .short_name = "RESP-A",
    .symbol = "lungs.fill", CR_ARREST_SCAFFOLD
};
static const cr_protocol_t pals_resp_distress = {
    .id = "pals.resp.distress", .name = "Resp distress", .short_name = "RESP-D",
    .symbol = "wind", CR_ARREST_SCAFFOLD
};
// Shock (hypoperfusion) states
static const cr_protocol_t pals_shock_state = {
    .id = "pals.shockstate", .name = "Shock (perfusion)", .short_name = "SHOCK",
    .symbol = "heart.circle.fill", CR_ARREST_SCAFFOLD
};
static const cr_protocol_t pals_shock_hypo = {
    .id = "pals.shockstate.hypo", .name = "Hypovolemic shock", .short_name = "HYPOVOL",
    .symbol = "drop.fill", CR_ARREST_SCAFFOLD
};
static const cr_protocol_t pals_shock_septic = {
    .id = "pals.shockstate.septic", .name = "Septic shock", .short_name = "SEPTIC",
    .symbol = "microbe.fill", CR_ARREST_SCAFFOLD
};
static const cr_protocol_t pals_shock_cardio = {
    .id = "pals.shockstate.cardio", .name = "Cardiogenic shock", .short_name = "CARDIOG",
    .symbol = "heart.fill", CR_ARREST_SCAFFOLD
};

const cr_protocol_t *const cr_protocol_choices[] = {
    &cr_protocol_pals_arrest, &pals_arrest_shockable, &pals_arrest_nonshock,
    &pals_brady,
    &pals_tachy, &pals_tachy_svt, &pals_tachy_vt,
    &pals_resp, &pals_resp_arrest, &pals_resp_distress,
    &pals_shock_state, &pals_shock_hypo, &pals_shock_septic, &pals_shock_cardio,
};
const size_t cr_protocol_choice_count = sizeof cr_protocol_choices / sizeof cr_protocol_choices[0];

const cr_protocol_t *const cr_protocol_tops[] = {
    &cr_protocol_pals_arrest, &pals_brady, &pals_tachy, &pals_resp, &pals_shock_state,
};
const size_t cr_protocol_top_count = sizeof cr_protocol_tops / sizeof cr_protocol_tops[0];

const cr_protocol_t *cr_protocol_by_id(const char *id)
{
    if (id == NULL) return NULL;
    for (size_t i = 0; i < cr_protocol_choice_count; i++) {
        if (strcmp(cr_protocol_choices[i]->id, id) == 0) return cr_protocol_choices[i];
    }
    return NULL;
}
