// cr_defaults.h — everything that ships in the box (Defaults.swift).
//
// The UUIDs below are HARDCODED and PERMANENT (invariant 1). They are the
// identity the watch, the phone and this board agree on; regenerating one
// orphans every record that referenced it. They are checked against
// Defaults.swift by test/spec_coverage.sh on every `make test`.
//
// DEMO VALUES. Published PALS reference numbers so the maths previews
// realistically — placeholders until Sebastian loads his facility's own.

#ifndef CR_DEFAULTS_H
#define CR_DEFAULTS_H

#include <stddef.h>

#include "cr_drugs.h"
#include "cr_events.h"
#include "cr_protocol.h"

#define CR_ID_PALS_SET   "C0DE0000-0000-4000-8000-000000000001"
#define CR_ID_EPI        "C0DE0000-0000-4000-8000-0000000000A1"
#define CR_ID_AMIO       "C0DE0000-0000-4000-8000-0000000000A2"
#define CR_ID_ATROPINE   "C0DE0000-0000-4000-8000-0000000000A3"
#define CR_ID_ADENOSINE  "C0DE0000-0000-4000-8000-0000000000A4"
#define CR_ID_DEFIB      "C0DE0000-0000-4000-8000-0000000000A5"
#define CR_ID_LIDOCAINE  "C0DE0000-0000-4000-8000-0000000000A6"
#define CR_ID_FLUIDS     "C0DE0000-0000-4000-8000-0000000000A7"
#define CR_ID_DEXTROSE   "C0DE0000-0000-4000-8000-0000000000A8"
#define CR_ID_CALCIUM    "C0DE0000-0000-4000-8000-0000000000A9"
#define CR_ID_BICARB     "C0DE0000-0000-4000-8000-0000000000AA"
#define CR_ID_MAGNESIUM  "C0DE0000-0000-4000-8000-0000000000AB"
#define CR_ID_NALOXONE   "C0DE0000-0000-4000-8000-0000000000AC"
#define CR_ID_EXAMPLITOL "C0DE0000-0000-4000-8000-0000000000AF"

// Rhythm/code meds (red)
extern const cr_drug_t cr_drug_epinephrine;
extern const cr_drug_t cr_drug_atropine;
extern const cr_drug_t cr_drug_adenosine;
extern const cr_drug_t cr_drug_amiodarone;
extern const cr_drug_t cr_drug_lidocaine;
// Shock (amber)
extern const cr_drug_t cr_drug_defibrillation;
// Volume / support (blue)
extern const cr_drug_t cr_drug_fluids;
extern const cr_drug_t cr_drug_dextrose;
extern const cr_drug_t cr_drug_calcium;
extern const cr_drug_t cr_drug_bicarb;
extern const cr_drug_t cr_drug_magnesium;
extern const cr_drug_t cr_drug_naloxone;
/// Fictional — exists to preview the card style in the phone editor. Not in
/// the PALS set, kept so its stable id stays reserved.
extern const cr_drug_t cr_drug_examplitol;

extern const cr_drug_set_t cr_pals_drug_set;

extern const cr_event_def_t cr_builtin_events[];
extern const size_t cr_builtin_event_count;
const cr_event_def_t *cr_builtin_event(const char *id);   // NULL when unknown

extern const cr_protocol_t cr_protocol_pals_arrest;

/// Every choosable algorithm, including the hold-to-refine variants. They
/// currently share the arrest timers/drugs/events and differ only in
/// identity — that is a demo simplification, not an oversight.
extern const cr_protocol_t *const cr_protocol_choices[];
extern const size_t cr_protocol_choice_count;

/// The five top-level picker tiles.
extern const cr_protocol_t *const cr_protocol_tops[];
extern const size_t cr_protocol_top_count;

const cr_protocol_t *cr_protocol_by_id(const char *id);   // NULL when unknown

#endif
