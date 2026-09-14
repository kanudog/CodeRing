// cr_patient.h — patient context and the three weight paths
// (CodeCore/Models/Patient.swift): manual kg, Broselow colour, age estimate.
// DEMO values only; the estimate is the published APLS approximation.

#ifndef CR_PATIENT_H
#define CR_PATIENT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef enum { CR_SEX_UNSPECIFIED, CR_SEX_FEMALE, CR_SEX_MALE } cr_sex_t;

typedef enum {
    CR_WEIGHT_MANUAL,
    CR_WEIGHT_BROSELOW,
    CR_WEIGHT_AGE_ESTIMATE,
} cr_weight_source_t;

/// Swift raw value ("manual", "broselow", "ageEstimate") — the JSON key.
const char *cr_weight_source_key(cr_weight_source_t source);

typedef struct {
    const char *id;          // "grey" … "green"
    const char *name;
    uint32_t color;          // Broselow tape colour — data, not theme
    double min_kg;
    double max_kg;
} cr_broselow_zone_t;

extern const cr_broselow_zone_t cr_broselow_zones[];
extern const size_t cr_broselow_zone_count;

/// Midpoint to 0.1 kg — what dosing uses when a colour is chosen.
double cr_broselow_mid_kg(const cr_broselow_zone_t *zone);

/// Zero-initialised = 0 kg, manual, no zone, no age, sex unspecified.
/// Strings are copied in, not pointed at, so a session can be persisted.
typedef struct {
    double weight_kg;
    cr_weight_source_t source;
    char broselow_zone_id[8];   // "" = none
    bool has_age;
    int16_t age_months;
    cr_sex_t sex;
} cr_patient_t;

/// APLS: infants (≤12 mo) 0.5 × months + 4; older (years + 4) × 2.
/// Rounded to 0.1 kg and capped at 50 kg for the paediatric scope.
double cr_weight_for_age_months(int months);

#endif
