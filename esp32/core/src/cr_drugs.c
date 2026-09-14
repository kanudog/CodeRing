#include "cr_drugs.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

#include "cr_text.h"

const char *cr_dose_unit_amount_suffix(cr_dose_unit_t unit)
{
    switch (unit) {
    case CR_UNIT_MG_PER_KG: return "mg";
    case CR_UNIT_J_PER_KG:  return "J";
    case CR_UNIT_ML_PER_KG: return "mL";
    }
    return "";
}

const char *cr_dose_unit_per_kg_suffix(cr_dose_unit_t unit)
{
    switch (unit) {
    case CR_UNIT_MG_PER_KG: return "mg/kg";
    case CR_UNIT_J_PER_KG:  return "J/kg";
    case CR_UNIT_ML_PER_KG: return "mL/kg";
    }
    return "";
}

const cr_drug_t *cr_drug_set_find(const cr_drug_set_t *set, const char *id)
{
    if (set == NULL || id == NULL) return NULL;
    for (uint8_t i = 0; i < set->drug_count; i++) {
        if (set->drugs[i] != NULL && strcmp(set->drugs[i]->id, id) == 0) return set->drugs[i];
    }
    return NULL;
}

double cr_rounded_volume(double value)
{
    if (!(value > 0)) return 0;
    double v = round(value * 10) / 10;
    return v < 0.1 ? 0.1 : v;   // a real dose never renders as 0.0 mL
}

double cr_rounded_amount(double value, cr_dose_unit_t unit)
{
    switch (unit) {
    case CR_UNIT_J_PER_KG:
        return round(value);
    case CR_UNIT_MG_PER_KG:
        if (value < 1) return round(value * 100) / 100;
        if (value < 10) return round(value * 10) / 10;
        return round(value);
    case CR_UNIT_ML_PER_KG:
        return cr_rounded_volume(value);
    }
    return value;
}

size_t cr_doses(const cr_drug_t *drug, double weight_kg, cr_dose_t *out, size_t cap)
{
    if (drug == NULL) return 0;
    size_t n = drug->step_count;
    for (size_t i = 0; i < n && i < cap; i++) {
        const cr_dose_step_t *step = &drug->steps[i];
        double raw = step->per_kg * weight_kg;
        double amount = raw;
        bool capped = false;
        if (step->has_max && raw > step->max_absolute) {
            amount = step->max_absolute;
            capped = true;
        }
        amount = cr_rounded_amount(amount, drug->unit);

        bool has_volume = false;
        double ml = 0;
        if (drug->unit == CR_UNIT_MG_PER_KG && drug->concentration_mg_per_ml > 0) {
            ml = cr_rounded_volume(amount / drug->concentration_mg_per_ml);
            has_volume = true;
        } else if (drug->unit == CR_UNIT_ML_PER_KG) {
            ml = amount;               // the dose already IS the volume
            has_volume = true;
        }

        out[i].step_label = step->label;
        out[i].amount = amount;
        out[i].has_volume = has_volume;
        out[i].volume_ml = ml;
        out[i].unit = drug->unit;
        out[i].capped = capped;
    }
    return n;
}

bool cr_primary_dose(const cr_drug_t *drug, double weight_kg, int prior_count, cr_dose_t *out)
{
    cr_dose_t all[CR_MAX_DOSE_STEPS];
    size_t n = cr_doses(drug, weight_kg, all, CR_MAX_DOSE_STEPS);
    if (n == 0) return false;
    if (n > CR_MAX_DOSE_STEPS) n = CR_MAX_DOSE_STEPS;
    // Prior administrations advance the ladder, then hold the last rung.
    int idx = prior_count < 0 ? 0 : prior_count;
    if (idx > (int)n - 1) idx = (int)n - 1;
    *out = all[idx];
    return true;
}

bool cr_dose_volume_text(const cr_dose_t *dose, char *buf, size_t cap)
{
    if (cap == 0) return false;
    buf[0] = '\0';
    if (dose == NULL || !dose->has_volume) return false;
    char num[24];
    cr_format_trim(num, sizeof num, dose->volume_ml);
    snprintf(buf, cap, "%s mL", num);
    return true;
}

void cr_dose_amount_text(const cr_dose_t *dose, char *buf, size_t cap)
{
    if (cap == 0) return;
    buf[0] = '\0';
    if (dose == NULL) return;
    char num[24];
    cr_format_trim(num, sizeof num, dose->amount);
    snprintf(buf, cap, "%s %s", num, cr_dose_unit_amount_suffix(dose->unit));
}

void cr_dose_summary(const cr_dose_t *dose, char *buf, size_t cap)
{
    if (cap == 0) return;
    buf[0] = '\0';
    if (dose == NULL) return;

    char volume[24];
    char amount[24];
    bool has_volume = cr_dose_volume_text(dose, volume, sizeof volume);
    cr_dose_amount_text(dose, amount, sizeof amount);
    const char *tail = dose->capped ? " · capped" : "";

    if (dose->unit == CR_UNIT_ML_PER_KG) {
        // A volume-dosed drug IS its volume — no redundant "(… mg)".
        snprintf(buf, cap, "%s%s", has_volume ? volume : amount, tail);
    } else if (has_volume) {
        // Two spaces: the volume is the featured number and the mg trails it.
        snprintf(buf, cap, "%s  (%s)%s", volume, amount, tail);
    } else {
        snprintf(buf, cap, "%s%s", amount, tail);
    }
}
