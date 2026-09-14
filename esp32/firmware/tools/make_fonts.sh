#!/bin/sh
# make_fonts.sh — generate the app's LVGL fonts.
#
# LVGL's built-in fonts cover plain ASCII only, so "Hands off — checking
# pulse" renders with a box where the dash should be. The strings are NOT
# the thing to change: they have to stay byte-identical to the watch app, or
# the parity trace breaks and the wrist, the phone, the TV and the CSV start
# disagreeing with each other. So the font gets the characters instead.
#
# Regenerate after adding any new character to a user-visible string:
#   cd esp32/firmware && sh tools/make_fonts.sh
#
# Needs node (for npx lv_font_conv). Output is committed, so a normal build
# never needs this.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
firmware=$(dirname "$here")
ttf="$firmware/managed_components/lvgl__lvgl/scripts/built_in_font/Montserrat-Medium.ttf"
out="$firmware/main/fonts"

[ -f "$ttf" ] || { echo "Montserrat not found — run a build first so the LVGL component is fetched"; exit 1; }
mkdir -p "$out"

# ASCII plus every non-ASCII character the app actually prints:
#   —  em dash      hints, drug subtitles, the toast separator
#   –  en dash      dose notes ("10–20 mL/kg", "q3–5 min")
#   ·  middot       " · capped"
#   →  arrow        "10.0 → 20.0 kg"
#   ₂  subscript 2  "CaCl₂"
#   ×  times        "may repeat ×2"
#   …  ellipsis     placeholder text
#   ✕  exit pad glyph, ≤ ≥ ° • for headroom
#
# Given as code points, not as literal characters: npm refuses an argument
# that begins with an em dash, and silently drops it.
EXTRA='0x2014,0x2013,0x00B7,0x2022,0x00D7,0x2192,0x2026,0x2264,0x2265,0x00B0,0x2082'

for size in 16 28 48; do
    echo "  font ${size}px"
    npx --yes lv_font_conv@1.5.3 \
        --font "$ttf" \
        --size "$size" \
        --bpp 4 \
        --format lvgl \
        --no-compress \
        --lv-include lvgl.h \
        --lv-font-name "cr_font_$size" \
        -r 0x20-0x7F \
        -r "$EXTRA" \
        -o "$out/cr_font_$size.c"

    # lv_font_conv stamps its full command line into the file, absolute
    # paths and all. This repo is public, so rewrite them to repo-relative
    # form — no home directories, no usernames.
    sed "s|$firmware/||g" "$out/cr_font_$size.c" > "$out/cr_font_$size.c.tmp"
    mv "$out/cr_font_$size.c.tmp" "$out/cr_font_$size.c"
done

if grep -l "/Users/\|/home/" "$out"/cr_font_*.c 2>/dev/null; then
    echo "FAILED — a local path survived in the generated fonts (see above)"
    exit 1
fi

# Prove the characters are really in there. A font that silently lacks a
# glyph draws a box, and a box is easy to miss on a 2" screen. LVGL stores
# scattered characters as OFFSETS from a range start, so this has to decode
# the cmap rather than grep for the number.
python3 - "$out/cr_font_28.c" <<'PY'
import re, sys

src = open(sys.argv[1]).read()
lists = {name: [int(x, 0) for x in re.findall(r'0x[0-9a-fA-F]+|\d+', body)]
         for name, body in re.findall(r'static const uint16_t (unicode_list_\d+)\[\] = \{(.*?)\};', src, re.S)}

covered = set()
for m in re.finditer(r'\.range_start = (\d+), \.range_length = (\d+), \.glyph_id_start = \d+,\s*\.unicode_list = (\w+)', src):
    start, length, name = int(m.group(1)), int(m.group(2)), m.group(3)
    if name == 'NULL':
        covered.update(range(start, start + length))
    else:
        covered.update(start + off for off in lists.get(name, []))

need = {0x2014: 'em dash', 0x2013: 'en dash', 0x00B7: 'middot',
        0x00D7: 'times', 0x2192: 'arrow', 0x2082: 'subscript 2'}
missing = [f"U+{cp:04X} ({label})" for cp, label in need.items() if cp not in covered]
if missing:
    sys.exit("FAILED — missing from the font: " + ", ".join(missing))
print(f"verified: {len(covered)} code points, including " + ", ".join(need.values()))
PY

echo "done — $(ls -la "$out" | awk 'NR>3 {printf "%s (%d kB)  ", $9, $5/1024}')"
