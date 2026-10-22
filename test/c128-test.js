// Headless check for the C128 80-column engine: runs engine/c128/engine.prg on a 6502
// core with a model of the VDC (8563/8568 with 64 KB RAM) and the editor's exported
// CTILES/CSPRITES/MAP01. After every move it decodes the frame the VDC shows (display
// start R12/R13, attribute start R20/R21) and compares all 80x25 cells, bitmap and
// attribute, with the editor's C128 preview (editor/c128.js). It also checks that
// nothing is ever written into the frame on show and that flips happen in vertical blank.
// Usage: node test/c128-test.js
const fs = require('fs'), path = require('path'), vm = require('vm'), zlib = require('zlib');
const makeCPU = require('./cpu6502');
const root = path.join(__dirname, '..');

// --- editor model: core + VIC-20 and C128 modules + exporters -------------------
const html = fs.readFileSync(path.join(root, 'editor/index.html'), 'utf8');
const js = html.slice(html.indexOf('<script>') + 8, html.lastIndexOf('</script>'));
const core = js.slice(0, js.indexOf('//  State'));
const exporters = js.slice(js.indexOf('function exportTiles'), js.indexOf('function download'));
const mod = n => fs.readFileSync(path.join(root, 'editor', n), 'utf8');
const ctx = {};
vm.createContext(ctx);
vm.runInContext(core + mod('vic20.js') + mod('c128.js') + exporters + `
  var P = newProject(); let encCache = null;
  function enc(){ if(!encCache) encCache = P.tiles.map(t => t ? encodeTile(t) : null); return encCache; }
  this.api = { P, c128ToImage, exportMap, vicAutoColours, c128Settings, c128ExportTiles, c128ExportSprites, c128Render, C128, MW };`, ctx);
const E = ctx.api, m = E.P.maps[0];

// same test map as test/engine-test.js
for (let y = 10; y < 16; y++) for (let x = 18; x < 24; x++) m.hgt[y * 32 + x] = x > 20 ? 2 : 1;
for (let y = 4; y < 9; y++) for (let x = 4; x < 12; x++) m.terr[y * 32 + x] = 4;
for (let x = 12; x < 20; x++) m.terr[17 * 32 + x] = 3;
[[14, 13], [15, 10], [12, 12], [19, 19]].forEach(([x, y]) => m.obj[y * 32 + x] = 8);
[[10, 18], [11, 18], [12, 18]].forEach(([x, y]) => m.obj[y * 32 + x] = 7);
m.obj[11 * 32 + 19] = 11; m.obj[20 * 32 + 14] = 10; m.obj[15 * 32 + 13] = 9;
m.hgt[16 * 32 + 15] |= 0x80;
for (let x = 0; x < 3; x++) m.terr[0 * 32 + x] = 0;
m.ents.push({ type: 1, sprite: 1, color: 5, hp: 2, atk: 1, def: 0, x: 18, y: 16 },
            { type: 2, sprite: 2, color: 14, hp: 9, atk: 0, def: 0, x: 14, y: 17 },
            { type: 3, sprite: 3, color: 2, hp: 1, atk: 0, def: 0, x: 17, y: 13 },
            { type: 4, sprite: 0, color: 1, hp: 0, atk: 0, def: 0, x: 15, y: 15 });
m.vic = E.vicAutoColours(E.P.tiles, m);
const g = E.c128Settings(m);
g.border = 6;   // not the default, so the header bytes are really used

const files = { CTILES: E.c128ExportTiles(E.P.tiles, m.bg), CSPRITES: E.c128ExportSprites(), MAP01: E.exportMap(m) };
fs.mkdirSync(path.join(root, 'build/c128'), { recursive: true });
for (const [n, d] of Object.entries(files)) fs.writeFileSync(path.join(root, 'build/c128', n.toLowerCase() + '.prg'), d);

// --- machine: RAM bank 0 + VDC ---------------------------------------------------
const mem = new Uint8Array(65536);
const prg = fs.readFileSync(path.join(root, 'engine/c128/engine.prg'));
mem.set(prg.subarray(2), prg[0] | prg[1] << 8);
mem[0xba] = 8; mem[0xdc00] = 0xff;
const labels = {};
for (const l of fs.readFileSync(path.join(root, 'engine/c128/engine.lbl'), 'utf8').split('\n')) {
  const mm = l.match(/al ([0-9A-F]+) \.(\w+)/i); if (mm) labels[mm[2]] = parseInt(mm[1], 16);
}
const cpu = makeCPU(mem);
const FRAME = 40000, VBLANK = Math.round(FRAME * 200 / 312);   // 2 MHz cycles per PAL frame; lines 200-311 blank
const inVblank = () => cpu.cyc % FRAME >= VBLANK;

// VDC: register file, 64 KB RAM, update address with auto-increment, block copy / fill
const V = { reg: new Uint8Array(64), ram: new Uint8Array(65536), sel: 0, ua: 0, latch: 0, armed: false, bad: [], flips: 0, late: 0, bytes: 0, copied: 0 };
V.reg[24] = 0x20; V.reg[25] = 0x47; V.reg[28] = 0x2f;   // KERNAL 80-column text set-up
const shownBM = () => V.reg[12] << 8 | V.reg[13], shownAT = () => V.reg[20] << 8 | V.reg[21];
function vput(a, v) {
  a &= 0xffff;
  if (V.armed) {
    const b = (a - shownBM() + 65536) & 0xffff, t = (a - shownAT() + 65536) & 0xffff;
    if ((b < 16000 || t < 2000) && V.bad.length < 5) V.bad.push(`write to $${a.toString(16)} in the frame on show (pc $${cpu.pc.toString(16)})`);
  }
  V.ram[a] = v;
}
cpu.ioLo = 0xd600; cpu.ioHi = 0xd602;
cpu.io = a => {
  if (a === 0xd600) return 0x80 | (inVblank() ? 0x20 : 0);   // always ready
  if (V.sel === 31) { const v = V.ram[V.ua]; V.ua = V.ua + 1 & 0xffff; return V.latch = v; }
  return V.reg[V.sel];
};
cpu.iow = (a, v) => {
  if (a === 0xd600) { V.sel = v & 63; return true; }
  const r = V.sel; V.reg[r] = v;
  switch (r) {
    case 18: V.ua = v << 8 | V.ua & 255; break;
    case 19: V.ua = V.ua & 0xff00 | v; break;
    case 31: vput(V.ua, v); V.latch = v; V.ua = V.ua + 1 & 0xffff; V.bytes++; break;
    case 30: {
      const n = v || 256, copy = V.reg[24] & 0x80;
      let src = V.reg[32] << 8 | V.reg[33];
      for (let i = 0; i < n; i++) {
        const b = copy ? V.ram[src] : V.latch;
        if (copy) src = src + 1 & 0xffff;
        vput(V.ua, b); V.ua = V.ua + 1 & 0xffff;
      }
      if (copy) { V.reg[32] = src >> 8; V.reg[33] = src & 255; V.copied += n; }
      break;
    }
    case 12: case 13: case 20: case 21:
      if (V.armed) { if (!inVblank()) V.late++; if (r === 12) V.flips++; }
      break;
  }
  V.reg[18] = V.ua >> 8; V.reg[19] = V.ua & 255;
  return true;
};
cpu.pc = labels.start; cpu.sp = 0xff;

let fname = '', sa = 0;
const keyq = [];
const kernal = {
  0xffbd: () => { fname = ''; const a = cpu.x | cpu.y << 8; for (let i = 0; i < cpu.a; i++) fname += String.fromCharCode(mem[a + i]); },
  0xffba: () => { sa = cpu.y; },
  0xff68: () => {},   // SETBNK
  0xffe4: () => { cpu.a = keyq.length ? keyq.shift() : 0; cpu.z = cpu.a ? 0 : 1; cpu.n = cpu.a >> 7; cpu.cf = 0; },
  0xffd5: () => {
    const key = Object.keys(files).find(k => fname.endsWith('*') ? k.startsWith(fname.slice(0, -1)) : k === fname);
    if (!key) { cpu.cf = 1; return; }
    const f = files[key], at = sa === 0 ? (cpu.x | cpu.y << 8) : (f[0] | f[1] << 8);
    mem.set(f.subarray(2), at); cpu.cf = 0;
  },
};
const PROF = global.__profile;
function step() {
  if (kernal[cpu.pc]) { kernal[cpu.pc](); cpu.rts(); return; }
  if (PROF && PROF.on) { const o = PROF.owner[cpu.pc], c0 = cpu.cyc; if (PROF.entry[cpu.pc]) PROF.calls[o] = (PROF.calls[o] || 0) + 1; cpu.step(); PROF.prof[o] = (PROF.prof[o] || 0) + cpu.cyc - c0; return; }
  cpu.step();
}
function runUntil(addr, limit = 5e7) {
  for (let n = 0; n < limit; n++) { if (cpu.pc === addr && !kernal[cpu.pc]) return; step(); }
  throw new Error('timeout, pc=$' + cpu.pc.toString(16));
}
const spin = n => { for (let k = 0; k < n; k++) step(); };

// --- compare -----------------------------------------------------------------------
const ENTS = 0x4c00 + 0xd00, C = E.C128;
let fails = 0, last = 0;
const steps = [], shots = {};   // editor PNG of the first frame per label (test/out/c128-editor-*.png)
function check(label) {
  const px = mem[2], py = mem[3];
  m.ents.forEach((e, k) => { e.type = mem[ENTS + k * 8]; e.hp = mem[ENTS + k * 8 + 5]; });
  const res = E.c128Render(m, E.P.tiles, px, py);
  if (!shots[label]) { shots[label] = 1; writePNG(path.join(root, `test/out/c128-editor-${label.replace(' ', '-')}.png`), res.fb); }
  const BM = shownBM(), AT = shownAT(), diff = [];
  if ((V.reg[25] & 0xc0) !== 0xc0) diff.push(`R25 ${V.reg[25].toString(16)}: not bitmap mode with attributes`);
  if (!(V.reg[28] & 0x10)) diff.push('R28: VDC RAM not in 64 KB mode');
  if ((V.reg[26] & 15) !== g.border) diff.push(`R26 border ${V.reg[26] & 15} want ${g.border}`);
  for (let r = 0; r < C.rows; r++) for (let c = 0; c < C.cols; c++) {
    const o = r * C.cols + c;
    if (V.ram[AT + r * 80 + c & 0xffff] !== res.fb.attr[o]) diff.push(`cell ${c},${r}: attribute $${V.ram[AT + r * 80 + c & 0xffff].toString(16)} want $${res.fb.attr[o].toString(16)}`);
    for (let i = 0; i < 8; i++) if (V.ram[BM + (r * 8 + i) * 80 + c & 0xffff] !== res.fb.bmp[o * 8 + i]) { diff.push(`cell ${c},${r}: pixels`); break; }
  }
  diff.push(...V.bad); V.bad = [];
  if (V.late) { diff.push(`${V.late} display register writes outside vertical blank`); V.late = 0; }
  const ok = diff.length === 0;
  if (!ok) fails++;
  console.log(`${ok ? 'PASS' : 'FAIL'} ${label.padEnd(20)} player ${px},${py}  frame ${BM === 0 ? 'A' : 'B'}  clash ${String(res.clash).padStart(3)}  cycles ${last}` +
    (ok ? '' : '\n   ' + diff.slice(0, 8).join('\n   ') + (diff.length > 8 ? `\n   …${diff.length} diffs` : '')));
}

// PNG of a 640x200 frame (for comparing with a VICE screenshot)
function writePNG(file, fb) {
  const W = 640, H = 200, img = { data: new Uint8Array(W * H * 4) };
  E.c128ToImage(fb, img);
  const raw = Buffer.alloc((W * 3 + 1) * H);
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) for (let k = 0; k < 3; k++) raw[y * (W * 3 + 1) + 1 + x * 3 + k] = img.data[(y * W + x) * 4 + k];
  const crcT = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ c >>> 1 : c >>> 1; return c >>> 0; });
  const crc = b => { let c = 0xffffffff; for (const v of b) c = crcT[(c ^ v) & 255] ^ c >>> 8; return (c ^ 0xffffffff) >>> 0; };
  const chunk = (t, d) => { const b = Buffer.concat([Buffer.from(t), d]), l = Buffer.alloc(4), c = Buffer.alloc(4); l.writeUInt32BE(d.length); c.writeUInt32BE(crc(b)); return Buffer.concat([l, b, c]); };
  const hd = Buffer.alloc(13); hd.writeUInt32BE(W, 0); hd.writeUInt32BE(H, 4); hd[8] = 8; hd[9] = 2;
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', hd), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]));
}

let t0 = cpu.cyc; runUntil(labels.main_loop); const boot = cpu.cyc - t0; last = boot;
V.armed = true;
runUntil(labels.get_move); check('start');
const K = { w: 0x57, s: 0x53, a: 0x41, d: 0x44, q: 0x51, e: 0x45, z: 0x5a, c: 0x43, up: 0x91, down: 0x11, left: 0x9d, right: 0x1d };
if (PROF) {   // test/profile.js c128 [key]: profile one step from the start position
  const k = process.env.ISO64_PROFILE;
  spin(60); keyq.push(K[k]); PROF.on = true;
  t0 = cpu.cyc; runUntil(labels.main_loop); const tot = cpu.cyc - t0; PROF.on = false;
  console.log(`\nkey ${k}: ${tot} cycles (${(tot / 2e6 * 1000).toFixed(0)} ms at 2 MHz)`);
  for (const [n, v] of Object.entries(PROF.prof).sort((a, b) => b[1] - a[1])) console.log(`  ${n.padEnd(18)} ${String(v).padStart(8)}  ${(100 * v / tot).toFixed(1).padStart(5)}%  ${PROF.calls[n] ? PROF.calls[n] + ' calls' : ''}`);
  process.exit(0);
}
const moves = ['w', 'w', 'q', 'e', 'd', 'd', 'e', 'e', 'w', 'a', 'a', 'z', 's', 's', 'c', 'c', 'c', 'c', 'c',
  'a', 'a', 'q', 'q', 'up', 'left', 'down', 'right', 'z', 'z', 's', 's', 's', 'd', 'w', 'w', 'w', 'w', 'w', 'w', 'w',
  'a', 'a', 'a', 'a', 'a', 'a', 'a', 'a', 'a', 'a', 's', 's', 's', 's', 's', 's', 's', 's', 's', 's', 's'];
for (const k of moves) {
  const bx = mem[2], by = mem[3];
  spin(60); keyq.push(K[k]);
  t0 = cpu.cyc; runUntil(labels.main_loop); last = cpu.cyc - t0;
  if (mem[2] !== bx || mem[3] !== by) steps.push(last);
  runUntil(labels.get_move); check('key ' + k);
}
// joystick port 2 ($dc00, active low): map axes as on the C64
const J = { up: 0x01, down: 0x02, left: 0x04, right: 0x08 };
for (const j of ['up', 'up', 'left', 'up+left', 'right', 'down+right', 'down', 'down', 'up+right', 'left']) {
  const bx = mem[2], by = mem[3];
  spin(60);
  let a = 0; for (const d of j.split('+')) a |= J[d];
  mem[0xdc00] = 0xff ^ a;
  t0 = cpu.cyc; runUntil(labels.main_loop); last = cpu.cyc - t0;
  mem[0xdc00] = 0xff;
  if (mem[2] !== bx || mem[3] !== by) steps.push(last);
  runUntil(labels.get_move); check('joy ' + j);
}
const avg = steps.reduce((a, b) => a + b, 0) / steps.length;
console.log(`\nboot ${boot} cycles; ${steps.length} steps: avg ${avg.toFixed(0)} (${(avg / 2000).toFixed(0)} ms at 2 MHz), min ${Math.min(...steps)}, max ${Math.max(...steps)}` +
  `\nVDC: ${V.flips} flips, ${V.bytes} bytes through R31, ${V.copied} bytes block-copied`);
console.log(fails ? `\n${fails} FAILED` : '\nall frames match the editor C128 preview');
process.exit(fails ? 1 : 0);
