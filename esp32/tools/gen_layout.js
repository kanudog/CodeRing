// gen_layout.js — turn the watch's hand-placed layout into C.
//
//   node esp32/tools/gen_layout.js   (from the repo root; run by make layout)
//
// Reads CodeCore/Sources/CodeCore/UI/{WatchLayout,FanLayout,RadialLayout}.swift
// and writes esp32/core/src/cr_layout_data.c in panel pixels.
//
// Generated rather than retyped because these are Sebastian's hand-placed
// coordinates: 14 fans, ~50 slots, each with a label position he nudged by
// eye. Retyping them once would be error-prone; keeping them in sync by hand
// after every Bench session would be hopeless. Re-run this instead.

const fs = require('fs');
const path = require('path');

const repo = path.resolve(__dirname, '..', '..');
const ui = path.join(repo, 'CodeCore/Sources/CodeCore/UI');
const watchSrc = fs.readFileSync(path.join(ui, 'WatchLayout.swift'), 'utf8');
const fanSrc = fs.readFileSync(path.join(ui, 'FanLayout.swift'), 'utf8');
const radialSrc = fs.readFileSync(path.join(ui, 'RadialLayout.swift'), 'utf8');

const SCALE = 2.071;
// The fan layer's inset inside the watch screen. Collapsing the two spaces
// into one is the whole point (see cr_layout.h).
const INSET = { x: 2, y: 51 };

const px = (pt) => +(pt * SCALE).toFixed(3);
const screenPt = (x, y) => ({ x: px(x), y: px(y) });
const fanPt = (x, y) => ({ x: px(x + INSET.x), y: px(y + INSET.y) });
const f = (v) => `${v.toFixed(3)}f`;
const pt = (p) => `{ ${f(p.x)}, ${f(p.y)} }`;
const snake = (s) => s.replace(/([a-z0-9])([A-Z])/g, '$1_$2').toLowerCase();

/** Pulls `public static let <name> = <Kind>(args…)` out of a Swift file. */
function constructor(src, name) {
    const re = new RegExp(`static let ${name}\\s*=\\s*(\\w+)\\(([^)]*(?:\\([^)]*\\))?[^)]*)\\)`);
    const m = src.match(re);
    if (!m) throw new Error(`could not find ${name}`);
    return { kind: m[1], args: m[2] };
}

/** Parses "99, 121, d: 94, stroke: 8" into [99, 121] + {d: 94, stroke: 8}. */
function args(text, resolve = {}) {
    const positional = [];
    const named = {};
    // Split on commas that are not inside parentheses.
    const parts = text.split(/,(?![^(]*\))/).map((s) => s.trim()).filter(Boolean);
    for (const part of parts) {
        const m = part.match(/^(\w+):\s*(.+)$/);
        const raw = m ? m[2] : part;
        const value = number(raw, resolve);
        if (m) named[m[1]] = value; else positional.push(value);
    }
    return { positional, named };
}

/** A literal, or a reference like `cprRing.center.x` to something already parsed. */
function number(raw, resolve) {
    const text = raw.trim();
    if (/^-?[\d.]+$/.test(text)) return parseFloat(text);
    const ref = text.match(/^(\w+)\.center\.([xy])$/);
    if (ref && resolve[ref[1]]) return resolve[ref[1]].raw[ref[2] === 'x' ? 0 : 1];
    const cg = text.match(/CGPoint\(x:\s*([-\d.]+),\s*y:\s*([-\d.]+)\)/);
    if (cg) return { x: parseFloat(cg[1]), y: parseFloat(cg[2]) };
    if (text === 'true') return true;
    if (text === 'false') return false;
    if (text === 'nil') return null;
    throw new Error(`cannot read value: ${text}`);
}

// ---------------------------------------------------------------- screen

const DISCS = ['logButton', 'timersButton', 'pauseButton', 'muteButton', 'flagButton',
               'medsPuck', 'eventsPuck', 'fluidsPuck', 'shockPuck', 'tapGlyph', 'roscHeart'];
const RINGS = ['cprRing', 'drugRing', 'vitalsRing'];
const TEXTS = ['totalLabel', 'codeClock', 'cycleChip', 'patient', 'startText',
               'pulseLabel', 'countdown', 'drugLine', 'toast', 'pausedText',
               'vitalsLabel', 'vitalsCount', 'roscElapsed', 'vitalsPrompt',
               'reArrest', 'handoff'];

const parsed = {};
const members = [];

for (const name of DISCS) {
    const { args: raw } = constructor(watchSrc, name);
    const a = args(raw, parsed);
    parsed[name] = { raw: a.positional };
    const c = screenPt(a.positional[0], a.positional[1]);
    members.push(`    .${snake(name)} = { ${pt(c)}, ${f(px(a.named.d))}, ${f(px(a.named.glyph))} },`);
}
for (const name of RINGS) {
    const a = args(constructor(watchSrc, name).args, parsed);
    parsed[name] = { raw: a.positional };
    const c = screenPt(a.positional[0], a.positional[1]);
    members.push(`    .${snake(name)} = { ${pt(c)}, ${f(px(a.named.d))}, ${f(px(a.named.stroke))} },`);
}
for (const name of TEXTS) {
    const a = args(constructor(watchSrc, name).args, parsed);
    parsed[name] = { raw: a.positional };
    const c = screenPt(a.positional[0], a.positional[1]);
    members.push(`    .${snake(name)} = { ${pt(c)}, ${f(px(a.named.w))}, ${f(px(a.named.h))}, ` +
                 `${f(px(a.named.font))} },`);
}

// Med timer chips: a literal array of Chip(...).
const chipBlock = watchSrc.match(/static let chips: \[Chip\] = \[([\s\S]*?)\]/)[1];
const chips = [...chipBlock.matchAll(/Chip\(([^)]*)\)/g)].map((m) => {
    const a = args(m[1]);
    const o = screenPt(a.positional[0], a.positional[1]);
    const w = px(a.named.w ?? 52), h = px(a.named.h ?? 27);
    return `        { ${pt(o)}, ${f(w)}, ${f(h)}, ${a.named.trailing ? 'true' : 'false'}, ` +
           `${f(px(a.named.nameFont ?? 7))} },`;
});

const pads = {
    cancel: args(constructor(fanSrc, 'cancel').args).positional,
    back: args(constructor(fanSrc, 'back').args).positional,
    hover: parseFloat(fanSrc.match(/static let hoverRadius: CGFloat = ([\d.]+)/)[1]),
};
const padDiameter = parseFloat(fanSrc.match(/public struct Pad[\s\S]*?diameter: CGFloat = ([\d.]+)/)?.[1] ?? 44);
const padGlyph = parseFloat(fanSrc.match(/public struct Pad[\s\S]*?glyph: CGFloat = ([\d.]+)/)?.[1] ?? 25);

const fanBounds = fanSrc.match(/static let bounds = CGSize\(width: ([\d.]+), height: ([\d.]+)\)/);
const screenSize = watchSrc.match(/static let screen = CGSize\(width: ([\d.]+), height: ([\d.]+)\)/);

// ------------------------------------------------------------------ fans

const tableBlock = fanSrc.match(/static let table: \[String: Fan\] = \[([\s\S]*?)\n    \]/)[1];
const titlesBlock = fanSrc.match(/static let titles: \[String: \[String\]\] = \[([\s\S]*?)\n    \]/)[1];

const fanTitles = {};
for (const m of fanSrc.match(/static let fanTitle: \[String: String\] = \[([\s\S]*?)\]/)[1]
        .matchAll(/"([\w:.]+)":\s*"([^"]*)"/g)) {
    fanTitles[m[1]] = m[2];
}

const titles = {};
for (const m of titlesBlock.matchAll(/"([\w:.]+)":\s*\[([^\]]*)\]/g)) {
    titles[m[1]] = [...m[2].matchAll(/"([^"]*)"/g)].map((t) => t[1]);
}

const fans = [];
const entryRe = /"([\w:.]+)":\s*(Fan\(|\.arc\()/g;
let match;
while ((match = entryRe.exec(tableBlock)) !== null) {
    const key = match[1];
    if (match[2] === '.arc(') {
        const n = parseInt(tableBlock.slice(entryRe.lastIndex), 10);
        fans.push({ key, placed: false, seed: n, slots: [], readout: null });
        continue;
    }
    // Walk to the matching close paren of Fan( so nested calls are safe.
    let depth = 1, i = entryRe.lastIndex;
    while (depth > 0 && i < tableBlock.length) {
        if (tableBlock[i] === '(') depth++;
        else if (tableBlock[i] === ')') depth--;
        i++;
    }
    const body = tableBlock.slice(entryRe.lastIndex, i - 1);

    const slots = [...body.matchAll(/Slot\(([^)]*\)[^)]*?)\)(?=,?\s*(?:\/\/|\n))/g)].map((s, index) => {
        const a = args(s[1]);
        const c = fanPt(a.positional[0], a.positional[1]);
        const label = a.named.label;
        const l = fanPt(label.x, label.y);
        return { c, l, d: px(a.named.d ?? 44), glyph: px(a.named.glyph ?? 25),
                 labelFont: px(a.named.labelFont ?? 8.5), labelWidth: px(a.named.labelWidth ?? 74),
                 z: a.named.z ?? index };
    });

    const readoutMatch = body.match(/readout:\s*(nil|Readout\(([^)]*)\))/);
    let readout = null;
    if (readoutMatch && readoutMatch[1] !== 'nil') {
        const a = args(readoutMatch[2]);
        readout = { c: screenPt(a.positional[0], a.positional[1]),
                    font: px(a.named.font ?? 16), crumb: px(a.named.crumbFont ?? 9),
                    follow: a.named.followAnchor === true };
    }
    const placed = !/placed:\s*false/.test(body);
    fans.push({ key, placed, seed: slots.length, slots, readout });
}

// --------------------------------------------------------------- the arc

const arcNum = (name) => parseFloat(radialSrc.match(new RegExp(`static let ${name}: CGFloat = ([\\d.]+)`))[1]);
const arc = {
    slotPitch: arcNum('slotPitch'), apexY: arcNum('apexY'), rowGap: arcNum('rowGap'),
    arcDrop: arcNum('arcDrop'), sideInset: arcNum('sideInset'),
    labelGap: arcNum('labelGap'), labelBoxHeight: arcNum('labelBoxHeight'),
    maxPerRow: parseInt(radialSrc.match(/static let maxPerRow = (\d+)/)[1], 10),
};

// ------------------------------------------------------------------ emit

const out = [];
out.push('// Generated by esp32/tools/gen_layout.js — do not edit.');
out.push('// Source: CodeCore/Sources/CodeCore/UI/{WatchLayout,FanLayout,RadialLayout}.swift');
out.push(`// Sebastian's hand-placed geometry, scaled by ${SCALE} into panel pixels`);
out.push('// and collapsed from the watch\'s two coordinate spaces into one.');
out.push('');
out.push('#include "cr_layout.h"');
out.push('');

for (const fan of fans) {
    if (!fan.placed || fan.slots.length === 0) continue;
    out.push(`static const cr_slot_t slots_${fan.key.replace(/[^\w]/g, '_')}[] = {`);
    for (const s of fan.slots) {
        out.push(`    { ${pt(s.c)}, ${f(s.d)}, ${f(s.glyph)}, ${pt(s.l)}, ` +
                 `${f(s.labelFont)}, ${f(s.labelWidth)}, ${s.z} },`);
    }
    out.push('};');
}
out.push('');

for (const key of Object.keys(titles)) {
    out.push(`static const char *const titles_${key.replace(/[^\w]/g, '_')}[] = {` +
             titles[key].map((t) => ` "${t}"`).join(',') + ' };');
}
out.push('');

out.push('const cr_fan_t cr_fans[] = {');
for (const fan of fans) {
    const id = fan.key.replace(/[^\w]/g, '_');
    const slots = fan.placed && fan.slots.length ? `slots_${id}` : 'NULL';
    const count = fan.placed ? fan.slots.length : 0;
    const r = fan.readout
        ? `{ true, ${pt(fan.readout.c)}, ${f(fan.readout.font)}, ${f(fan.readout.crumb)}, ${fan.readout.follow} }`
        : '{ false, { 0.0f, 0.0f }, 0.0f, 0.0f, false }';
    const t = titles[fan.key] ? `titles_${id}` : 'NULL';
    const tc = titles[fan.key] ? titles[fan.key].length : 0;
    out.push(`    { "${fan.key}", "${fanTitles[fan.key] || fan.key}", ${slots}, ${count}, ${r}, ` +
             `${fan.placed}, ${fan.seed}, ${t}, ${tc} },`);
}
out.push('};');
out.push('const size_t cr_fan_count = sizeof cr_fans / sizeof cr_fans[0];');
out.push('');

out.push('const cr_arc_spec_t cr_arc = {');
out.push(`    .slot_pitch = ${f(px(arc.slotPitch))}, .apex_y = ${f(px(arc.apexY + INSET.y))},`);
out.push(`    .row_gap = ${f(px(arc.rowGap))}, .arc_drop = ${f(px(arc.arcDrop))},`);
out.push(`    .side_inset = ${f(px(arc.sideInset))}, .label_gap = ${f(px(arc.labelGap))},`);
out.push(`    .label_box_height = ${f(px(arc.labelBoxHeight))}, .bubble_diameter = ${f(px(44))},`);
out.push(`    .glyph = ${f(px(25))}, .label_font = ${f(px(8.5))}, .label_width = ${f(px(74))},`);
out.push(`    .max_per_row = ${arc.maxPerRow},`);
out.push('};');
out.push('');

out.push('const cr_screen_t cr_screen = {');
out.push(`    .width = ${f(px(parseFloat(screenSize[1])))}, .height = ${f(px(parseFloat(screenSize[2])))},`);
out.push(`    .fan_origin = ${pt(screenPt(INSET.x, INSET.y))},`);
out.push(`    .fan_width = ${f(px(parseFloat(fanBounds[1])))}, .fan_height = ${f(px(parseFloat(fanBounds[2])))},`);
out.push(...members);
out.push('    .chips = {');
out.push(...chips);
out.push('    },');
out.push(`    .chip_count = ${chips.length},`);
out.push(`    .chip_count_font = ${f(px(parseFloat(watchSrc.match(/chipCountFont: CGFloat = ([\d.]+)/)[1])))},`);
out.push(`    .chip_timer_font = ${f(px(parseFloat(watchSrc.match(/chipTimerFont: CGFloat = ([\d.]+)/)[1])))},`);
out.push('    .pads = {');
out.push(`        .cancel = { ${pt(screenPt(pads.cancel[0], pads.cancel[1]))}, ${f(px(padDiameter))}, ${f(px(padGlyph))} },`);
out.push(`        .back   = { ${pt(screenPt(pads.back[0], pads.back[1]))}, ${f(px(padDiameter))}, ${f(px(padGlyph))} },`);
out.push(`        .hover_radius = ${f(px(pads.hover))},`);
out.push('    },');
out.push('};');
out.push('');

const dest = path.join(repo, 'esp32/core/src/cr_layout_data.c');
fs.writeFileSync(dest, out.join('\n'));

const placedCount = fans.filter((x) => x.placed).length;
const slotCount = fans.reduce((n, x) => n + x.slots.length, 0);
console.log(`wrote ${path.relative(repo, dest)} — ${fans.length} fans (${placedCount} hand-placed, ` +
            `${slotCount} slots), ${DISCS.length + RINGS.length + TEXTS.length} screen controls`);
