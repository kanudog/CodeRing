// extract_icons.js — pull the icon set out of the Layout Bench.
//
// Tools/LayoutBench/index.html holds a 24×24 SVG redraw of every icon the
// watch app uses (SF Symbols themselves are Apple's and cannot come along).
// That table is the single source of truth, so this reads it rather than
// keeping a second copy here that could drift from it.
//
// Usage: node extract_icons.js <index.html> <out-dir>
// Writes one .svg per icon and prints "<file>\t<symbol>" for the table
// generator.

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const [, , htmlPath, outDir] = process.argv;
if (!htmlPath || !outDir) {
    console.error('usage: node extract_icons.js <index.html> <out-dir>');
    process.exit(1);
}

const html = fs.readFileSync(htmlPath, 'utf8');
// `S` holds the shared stroke attributes the icon strings interpolate, so
// both definitions have to be evaluated together.
const start = html.indexOf('const S=');
const iconsAt = html.indexOf('const ICONS={', start);
const end = html.indexOf('\n};', iconsAt);
if (start < 0 || iconsAt < 0 || end < 0) {
    console.error('could not find the ICONS table — has the Bench been restructured?');
    process.exit(1);
}

const sandbox = {};
vm.createContext(sandbox);
vm.runInContext(html.slice(start, end + 3) + '\n__icons = ICONS;', sandbox);
const icons = sandbox.__icons;

fs.mkdirSync(outDir, { recursive: true });
let count = 0;
for (const [symbol, inner] of Object.entries(icons)) {
    // The Bench draws with currentColor; rasterise as white on transparent
    // and let LVGL tint the alpha mask at runtime.
    const svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" ' +
                'width="24" height="24" style="color:#ffffff">' + inner + '</svg>';
    const file = symbol.replace(/[^a-zA-Z0-9]/g, '_');
    fs.writeFileSync(path.join(outDir, file + '.svg'), svg);
    console.log(file + '\t' + symbol);
    count++;
}
console.error(`extracted ${count} icons`);
