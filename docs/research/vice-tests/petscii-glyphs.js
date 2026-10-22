// Classify the block/line/diagonal glyphs of the C64 character ROM (uppercase/graphics set)
// by their actual pixels. Usage: node petscii-glyphs.js <chargen.bin>
const rom = require('fs').readFileSync(process.argv[2]);
const px = (c, x, y) => (rom[c * 8 + y] >> (7 - x)) & 1;           // set 1 = first 2 KB
const grid = c => [...Array(8)].map((_, y) => [...Array(8)].map((_, x) => px(c, x, y)));
const same = (c, f) => grid(c).every((r, y) => r.every((v, x) => v === (f(x, y) ? 1 : 0)));
const shapes = {
  'blank': () => 0, 'full': () => 1,
  'left half': x => x < 4, 'right half': x => x >= 4, 'top half': (x, y) => y < 4, 'bottom half': (x, y) => y >= 4,
  'quarter upper-left': (x, y) => x < 4 && y < 4, 'quarter upper-right': (x, y) => x >= 4 && y < 4,
  'quarter lower-left': (x, y) => x < 4 && y >= 4, 'quarter lower-right': (x, y) => x >= 4 && y >= 4,
  'quarters UL+LR': (x, y) => (x < 4) === (y < 4), 'quarters UR+LL': (x, y) => (x < 4) !== (y < 4),
  'three quarters (no LR)': (x, y) => !(x >= 4 && y >= 4), 'three quarters (no LL)': (x, y) => !(x < 4 && y >= 4),
  'three quarters (no UR)': (x, y) => !(x >= 4 && y < 4), 'three quarters (no UL)': (x, y) => !(x < 4 && y < 4),
  'triangle upper-left ◤': (x, y) => x + y < 8, 'triangle upper-right ◥': (x, y) => x >= y,
  'triangle lower-left ◣': (x, y) => x <= y, 'triangle lower-right ◢': (x, y) => x + y >= 7,
  'checkerboard 1px': (x, y) => (x + y) & 1, 'checkerboard 1px alt': (x, y) => !((x + y) & 1),
  'left half checker': (x, y) => x < 4 && ((x + y) & 1), 'bottom half checker': (x, y) => y >= 4 && ((x + y) & 1),
};
for (let k = 1; k <= 7; k++) {
  shapes[`bottom ${k}/8 block`] = (x, y) => y >= 8 - k; shapes[`top ${k}/8 block`] = (x, y) => y < k;
  shapes[`left ${k}/8 block`] = x => x < k; shapes[`right ${k}/8 block`] = x => x >= 8 - k;
}
for (let r = 0; r < 8; r++) { shapes[`horizontal line row ${r}`] = (x, y) => y === r; shapes[`vertical line col ${r}`] = x => x === r; }
for (let r = 0; r < 7; r++) { shapes[`horizontal 2px line rows ${r}-${r + 1}`] = (x, y) => y === r || y === r + 1; shapes[`vertical 2px line cols ${r}-${r + 1}`] = x => x === r || x === r + 1; }
const found = {};
for (let c = 0; c < 256; c++) for (const [n, f] of Object.entries(shapes)) if (same(c, f)) (found[n] = found[n] || []).push(c);
for (const [n, cs] of Object.entries(found)) console.log(n.padEnd(34), cs.map(c => '$' + c.toString(16).padStart(2, '0')).join(' '));
