// Headless check for the VIC-20 engine: runs engine/vic20/engine.prg on a 6502
// core with the editor's exported VTILES/VSPRITES/MAP01, then decodes the shown
// screen (screen codes -> character set, colour RAM) after every move and
// compares each viewport cell with the editor's VIC-20 preview (editor/vic20.js).
// Usage: node test/vic20-test.js
const fs = require('fs'), path = require('path'), vm = require('vm');
const makeCPU = require('./cpu6502');
const root = path.join(__dirname, '..');

// --- editor model: core + exporters + VIC-20 module ---------------------------
const html = fs.readFileSync(path.join(root, 'editor/index.html'), 'utf8');
const js = html.slice(html.indexOf('<script>') + 8, html.lastIndexOf('</script>'));
const core = js.slice(0, js.indexOf('//  State'));
const exporters = js.slice(js.indexOf('function exportTiles'), js.indexOf('function download'));
const vicjs = fs.readFileSync(path.join(root, 'editor/vic20.js'), 'utf8');
const ctx = {};
vm.createContext(ctx);
vm.runInContext(core + vicjs + exporters + `
  var P = newProject(); let encCache = null;
  function enc(){ if(!encCache) encCache = P.tiles.map(t => t ? encodeTile(t) : null); return encCache; }
  this.api = { P, exportMap, vicAutoColours, vicExportTiles, vicExportSprites, vicRender, VIC, MW };`, ctx);
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

const files = { VTILES: E.vicExportTiles(E.P.tiles, m.vic, m.bg), VSPRITES: E.vicExportSprites(), MAP01: E.exportMap(m) };
fs.mkdirSync(path.join(root, 'build/vic20'), { recursive: true });
for (const [n, d] of Object.entries(files)) fs.writeFileSync(path.join(root, 'build/vic20', n.toLowerCase() + '.prg'), d);

// --- boot ------------------------------------------------------------------------
const mem = new Uint8Array(65536);
const prg = fs.readFileSync(path.join(root, 'engine/vic20/engine.prg'));
mem.set(prg.subarray(2), prg[0] | prg[1] << 8);
mem[0xba] = 8;
mem[0x9111] = mem[0x9120] = 0xff;   // joystick released (VIA ports, active low)
const labels = {};
for (const l of fs.readFileSync(path.join(root, 'engine/vic20/engine.lbl'), 'utf8').split('\n')) {
  const mm = l.match(/al ([0-9A-F]+) \.(\w+)/i); if (mm) labels[mm[2]] = parseInt(mm[1], 16);
}
const cpu = makeCPU(mem);
cpu.ioLo = 0x9000; cpu.ioHi = 0x9010;
cpu.io = a => a === 0x9004 ? (Math.floor(cpu.cyc / 71) % 312) >> 1 : undefined;   // PAL raster / 2
cpu.pc = labels.start; cpu.sp = 0xff;
let fname = '', sa = 0;
const keyq = [];
const kernal = {
  0xffbd: () => { fname = ''; const a = cpu.x | cpu.y << 8; for (let i = 0; i < cpu.a; i++) fname += String.fromCharCode(mem[a + i]); },
  0xffba: () => { sa = cpu.y; },
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
const ENTS = 0x4d00, V = E.VIC;
let fails = 0, last = 0;
function check(label) {
  const px = mem[2], py = mem[3];
  m.ents.forEach((e, k) => { e.type = mem[ENTS + k * 8]; e.hp = mem[ENTS + k * 8 + 5]; });
  const res = E.vicRender(m, E.P.tiles, px, py);
  const B = (mem[0x9002] & 0x80) !== 0, SCR = B ? 0x1200 : 0x1000, COL = B ? 0x9600 : 0x9400;
  const diff = [], codes = new Set();
  for (let r = V.vp.r0; r <= V.vp.r1; r++) for (let c = V.vp.c0; c <= V.vp.c1; c++) {
    const o = r * V.cols + c, code = mem[SCR + o], col = mem[COL + o];
    codes.add(code);
    if (B ? code < 112 || code >= 224 : code >= 112) { diff.push(`cell ${c},${r}: code ${code} from the wrong half`); continue; }
    for (let i = 0; i < 8; i++) if (mem[0x1400 + code * 8 + i] !== res.fb.bmp[o * 8 + i]) { diff.push(`cell ${c},${r}: pixels`); break; }
    if ((col & 7) !== res.fb.fg[o] || !(col & 8)) diff.push(`cell ${c},${r}: colour ${col} want ${res.fb.fg[o] | 8}`);
  }
  const ok = diff.length === 0;
  if (!ok) fails++;
  console.log(`${ok ? 'PASS' : 'FAIL'} ${label.padEnd(20)} player ${px},${py}  screen ${B ? 'B' : 'A'}  chars ${codes.size} (editor ${res.chars})  cycles ${last}` +
    (ok ? '' : '\n   ' + diff.slice(0, 8).join('\n   ') + (diff.length > 8 ? `\n   …${diff.length} diffs` : '')));
}

let t0 = cpu.cyc; runUntil(labels.get_move); last = cpu.cyc - t0; check('start');
const K = { w: 0x57, s: 0x53, a: 0x41, d: 0x44, q: 0x51, e: 0x45, z: 0x5a, c: 0x43, up: 0x91, down: 0x11, left: 0x9d, right: 0x1d };
if (PROF) {   // test/profile.js vic20 [key]: profile one step from the start position
  const k = process.env.ISO64_PROFILE;
  spin(60); keyq.push(K[k]); PROF.on = true;
  t0 = cpu.cyc; runUntil(labels.main_loop); const tot = cpu.cyc - t0; PROF.on = false;
  console.log(`
key ${k}: ${tot} cycles (${(tot / 1108405 * 1000).toFixed(0)} ms PAL)`);
  for (const [n, v] of Object.entries(PROF.prof).sort((a, b) => b[1] - a[1])) console.log(`  ${n.padEnd(18)} ${String(v).padStart(8)}  ${(100 * v / tot).toFixed(1).padStart(5)}%  ${PROF.calls[n] ? PROF.calls[n] + ' calls' : ''}`);
  process.exit(0);
}
const moves = ['w', 'w', 'q', 'e', 'd', 'd', 'e', 'e', 'w', 'a', 'a', 'z', 's', 's', 'c', 'c', 'c', 'c', 'c',
  'a', 'a', 'q', 'q', 'up', 'left', 'down', 'right', 'z', 'z', 's', 's', 's', 'd', 'w', 'w', 'w', 'w', 'w', 'w', 'w'];
for (const k of moves) {
  spin(60); keyq.push(K[k]);
  t0 = cpu.cyc; runUntil(labels.main_loop); last = cpu.cyc - t0;
  runUntil(labels.get_move); check('key ' + k);
}
// joystick: up/down/left on $9111 bits 2-4, right on $9120 bit 7 (map axes)
const JOY = { up: [0x04, 0], down: [0x08, 0], left: [0x10, 0], right: [0, 0x80] };
for (const j of ['up', 'up', 'left', 'up+left', 'right', 'down+right', 'down', 'down', 'up+right', 'left']) {
  spin(60);
  let a = 0, b = 0; for (const d of j.split('+')) { a |= JOY[d][0]; b |= JOY[d][1]; }
  mem[0x9111] = 0xff ^ a; mem[0x9120] = 0xff ^ b;
  t0 = cpu.cyc; runUntil(labels.main_loop); last = cpu.cyc - t0;
  mem[0x9111] = mem[0x9120] = 0xff;
  runUntil(labels.get_move); check('joy ' + j);
}
console.log(fails ? `\n${fails} FAILED` : '\nall frames match the editor VIC-20 preview');
process.exit(fails ? 1 : 0);
