// cr_theme.h — Midnight Neon, ported from CodeCore/Theme.swift.
//
// Every colour on this device comes from here or from a stored item colour
// (invariant 5). Values are 0xRRGGBB and byte-identical to the Swift hexes,
// so the watch, the phone, this board and the TV all show one hue per item.

#ifndef CR_THEME_H
#define CR_THEME_H

#include <stdint.h>

/// Swift's `colorHex: String?` = nil. Real colours only use the low 24 bits.
#define CR_COLOR_NONE UINT32_C(0xFFFFFFFF)

// Base
#define CR_THEME_BG          UINT32_C(0x0A0F1E)   // midnight
#define CR_THEME_SURFACE     UINT32_C(0x131A2E)
#define CR_THEME_SURFACE_HI  UINT32_C(0x1B2440)
#define CR_THEME_RING_TRACK  UINT32_C(0x1E2742)
#define CR_THEME_TEXT        UINT32_C(0xF2F5FF)
#define CR_THEME_TEXT_DIM    UINT32_C(0x8A93B0)

// Category accents
#define CR_THEME_MED         UINT32_C(0xFF3B5C)   // medications — hot red
#define CR_THEME_SHOCK       UINT32_C(0xFFB020)   // defib/cardioversion — amber
#define CR_THEME_AIRWAY      UINT32_C(0x22D3EE)   // airway — cyan
#define CR_THEME_ACCESS      UINT32_C(0x34D399)   // IV/IO — green
#define CR_THEME_CPR         UINT32_C(0xA78BFA)   // CPR cycle — violet
#define CR_THEME_ROSC        UINT32_C(0x4ADE80)   // outcome — bright green
#define CR_THEME_RHYTHM      UINT32_C(0x60A5FA)   // rhythm checks — blue
#define CR_THEME_CARE        UINT32_C(0x2DD4BF)   // supportive care (temp) — teal
#define CR_THEME_VOLUME      UINT32_C(0x3B82F6)   // volume/support meds & fluids — blue
#define CR_THEME_COMMS       UINT32_C(0x818CF8)   // team comms — indigo
#define CR_THEME_CUSTOM      UINT32_C(0xF0ABFC)   // user-defined — pink
#define CR_THEME_DEMO        UINT32_C(0xFFB020)   // PDF/CSV demo footer only (invariant 3)
#define CR_THEME_PAUSE       UINT32_C(0xFBCB89)   // pause control — warm sand

// Exit pads (✕ and back) invert on purpose: pale fill, dark red glyph, so
// they read as "not an option" against every fan's dark bubbles.
#define CR_THEME_PAD_FILL    UINT32_C(0xD9DCE3)
#define CR_THEME_PAD_ICON    UINT32_C(0xB51737)

/// Wash over the backdrop while a fan is open — lifts it off pure black so
/// dark bubbles still read.
#define CR_THEME_SCRIM_TINT  UINT32_C(0x8FA0C8)

#endif
