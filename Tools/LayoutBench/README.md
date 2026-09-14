# Layout Bench

A single-file, drag-and-drop editor for CodeRing's watch layout: the four
live-screen states (Before CPR / CPR running / Meds given / Post-ROSC) and all
fourteen radial submenus. Open `index.html` in any browser — no build step.

Drag to move, handles resize, Shift-click to multi-select and align, ⌘Z undo,
`[` `]` draw order, SF Symbol picker. **Generate** exports Swift for the fans
and a change list + JSON for the screens.

## Read this before trusting what it shows

- **The Swift files are the source of truth, not this page.**
  `CodeCore/Sources/CodeCore/UI/WatchLayout.swift` (live screen) and
  `CodeCore/Sources/CodeCore/UI/FanLayout.swift` (fans) hold the shipping
  numbers. The Bench opens on its built-in seeds; the final hand placement of
  2026-08-29 lives in FanLayout.swift, not in these defaults.
- Edits save to the browser's `localStorage`, which is per-origin. A copy
  opened from disk does not see edits made in the hosted version, and vice
  versa.
- Geometry is 45 mm Apple Watch Series 9: 198 × 242 pt. The fans are edited in
  screen points and exported in FAN space (194 × 191, inset 2, 51), because
  that is what FanLayout.swift stores.
- The `ICONS` table near the top of the script is a hand-drawn 24 × 24 SVG
  version of every SF Symbol the app uses. Off Apple platforms, where SF
  Symbols do not exist, that table is the starting icon set.

## Known rough edges

- `arcSeed()` still reads `ARC.labelDrop`, which was removed when labels moved
  to the 4 pt-under-the-button rule. The label values it produces are unused,
  so nothing visible breaks.
- The fan backdrop here is a flat dark scrim; the app now blurs the layers
  behind the fan instead.
