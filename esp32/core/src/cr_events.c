#include "cr_events.h"

#include "cr_theme.h"

uint32_t cr_category_color(cr_category_t category)
{
    switch (category) {
    case CR_CAT_MEDICATION:     return CR_THEME_MED;
    case CR_CAT_DEFIBRILLATION: return CR_THEME_SHOCK;
    case CR_CAT_RHYTHM:         return CR_THEME_RHYTHM;
    case CR_CAT_AIRWAY:         return CR_THEME_AIRWAY;
    case CR_CAT_ACCESS:         return CR_THEME_ACCESS;
    case CR_CAT_CPR:            return CR_THEME_CPR;
    case CR_CAT_OUTCOME:        return CR_THEME_ROSC;
    case CR_CAT_CARE:           return CR_THEME_CARE;
    case CR_CAT_VOLUME:         return CR_THEME_VOLUME;
    case CR_CAT_COMMS:          return CR_THEME_COMMS;
    case CR_CAT_CUSTOM:         return CR_THEME_CUSTOM;
    case CR_CAT__COUNT:         break;
    }
    return CR_THEME_CUSTOM;
}

const char *cr_category_label(cr_category_t category)
{
    switch (category) {
    case CR_CAT_MEDICATION:     return "Medication";
    case CR_CAT_DEFIBRILLATION: return "Defib";
    case CR_CAT_RHYTHM:         return "Rhythm";
    case CR_CAT_AIRWAY:         return "Airway";
    case CR_CAT_ACCESS:         return "Access";
    case CR_CAT_CPR:            return "CPR";
    case CR_CAT_OUTCOME:        return "Outcome";
    case CR_CAT_CARE:           return "Care";
    case CR_CAT_VOLUME:         return "Volume/Support";
    case CR_CAT_COMMS:          return "Comms";
    case CR_CAT_CUSTOM:         return "Custom";
    case CR_CAT__COUNT:         break;
    }
    return "Custom";
}

const char *cr_category_key(cr_category_t category)
{
    switch (category) {
    case CR_CAT_MEDICATION:     return "medication";
    case CR_CAT_DEFIBRILLATION: return "defibrillation";
    case CR_CAT_RHYTHM:         return "rhythm";
    case CR_CAT_AIRWAY:         return "airway";
    case CR_CAT_ACCESS:         return "access";
    case CR_CAT_CPR:            return "cpr";
    case CR_CAT_OUTCOME:        return "outcome";
    case CR_CAT_CARE:           return "care";
    case CR_CAT_VOLUME:         return "volume";
    case CR_CAT_COMMS:          return "comms";
    case CR_CAT_CUSTOM:         return "custom";
    case CR_CAT__COUNT:         break;
    }
    return "custom";
}
