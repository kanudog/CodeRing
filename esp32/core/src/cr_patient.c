#include "cr_patient.h"

#include <math.h>

const char *cr_weight_source_key(cr_weight_source_t source)
{
    switch (source) {
    case CR_WEIGHT_MANUAL:       return "manual";
    case CR_WEIGHT_BROSELOW:     return "broselow";
    case CR_WEIGHT_AGE_ESTIMATE: return "ageEstimate";
    }
    return "manual";
}

// Standard Broselow zones. These hexes are tape colours, i.e. data — they
// are deliberately not theme tokens.
const cr_broselow_zone_t cr_broselow_zones[] = {
    { .id = "grey",   .name = "Grey",   .color = 0x9CA3AF, .min_kg = 3,  .max_kg = 5  },
    { .id = "pink",   .name = "Pink",   .color = 0xF472B6, .min_kg = 6,  .max_kg = 7  },
    { .id = "red",    .name = "Red",    .color = 0xEF4444, .min_kg = 8,  .max_kg = 9  },
    { .id = "purple", .name = "Purple", .color = 0xA855F7, .min_kg = 10, .max_kg = 11 },
    { .id = "yellow", .name = "Yellow", .color = 0xFACC15, .min_kg = 12, .max_kg = 14 },
    { .id = "white",  .name = "White",  .color = 0xE5E7EB, .min_kg = 15, .max_kg = 18 },
    { .id = "blue",   .name = "Blue",   .color = 0x3B82F6, .min_kg = 19, .max_kg = 23 },
    { .id = "orange", .name = "Orange", .color = 0xF97316, .min_kg = 24, .max_kg = 29 },
    { .id = "green",  .name = "Green",  .color = 0x22C55E, .min_kg = 30, .max_kg = 36 },
};
const size_t cr_broselow_zone_count = sizeof cr_broselow_zones / sizeof cr_broselow_zones[0];

double cr_broselow_mid_kg(const cr_broselow_zone_t *zone)
{
    if (zone == NULL) return 0;
    return round((zone->min_kg + zone->max_kg) / 2 * 10) / 10;
}

double cr_weight_for_age_months(int months)
{
    double m = months < 0 ? 0 : (double)months;
    double kg = (months <= 12) ? (0.5 * m + 4)        // infants: (0.5 × months) + 4
                               : ((m / 12.0 + 4.0) * 2.0);   // 1–10 yr: (years + 4) × 2
    kg = round(kg * 10) / 10;
    return kg > 50 ? 50 : kg;   // paediatric scope — this is a fallback path
}
