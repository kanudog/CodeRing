// cr_menu.h — the menu tree (WatchApp/LiveSessionView.swift "Menu trees").
//
// Item ids encode the action, so ONE selector handles every menu:
//   drug:<uuid>[#step]  → log that drug (auto ladder, or a forced rung)
//   evt:<base>[|detail] → log a catalog event, detail after the bar
//   rosc / pause        → engine control
//   grp:*               → a parent; it only expands, and never logs
//
// Fans are built at RUNTIME, not stored, because some titles depend on the
// patient: the defib ladder reads "1st 20 J / Next 40 J / Max 100 J" at
// 10 kg and different numbers at 30. A group's children live under its own
// key, which is the same key the layout table uses — so the menu and the
// geometry cannot drift apart.

#ifndef CR_MENU_H
#define CR_MENU_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "cr_engine.h"
#include "cr_layout.h"

#define CR_MENU_TITLE_MAX 24
#define CR_MENU_ID_MAX    48

typedef struct {
    char id[CR_MENU_ID_MAX];
    char title[CR_MENU_TITLE_MAX];
    const char *symbol;      // SF Symbol name; resolved to an icon by the UI
    uint32_t color;
    /// Usually the same as `color`. Blood is the exception Sebastian drew: a
    /// blue bubble with a RED drop, because it sits among the fluids but is
    /// not one.
    uint32_t icon_color;
    bool is_group;           // expands only — releasing here logs nothing
    const char *child_key;   // the fan key holding its children
} cr_menu_item_t;

/// The anchor pucks and the fan each one opens.
#define CR_ANCHOR_MEDS   "code"
#define CR_ANCHOR_SHOCK  "shock"
#define CR_ANCHOR_FLUIDS "support"
#define CR_ANCHOR_EVENTS "events"

/// The events fan swaps wholesale after ROSC — same puck, different set,
/// reassessment-oriented. Resolves an anchor id to the key that is actually
/// open right now, which is also the key the layout table is asked for.
const char *cr_menu_key(const cr_engine_t *e, const char *anchor);

/// Fills `out` with one fan's items, in slot order. Returns how many.
size_t cr_menu_items(const cr_engine_t *e, const char *key,
                     cr_menu_item_t *out, size_t cap);

/// What a leaf does when it fires. Groups return false — and the caller must
/// SAY so ("Nothing logged"), because silence after a deliberate gesture is
/// this app's worst failure mode.
bool cr_menu_select(cr_engine_t *e, const cr_menu_item_t *item, cr_ms_t now);

#endif
