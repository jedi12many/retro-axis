// Headless check: runs engine/c64/engine.prg on a 6502 core with the editor's exported
// TILES/SPRITES/MAP01 data, then compares bitmap, screen RAM, colour RAM and sprite
// registers against the editor's own renderer after a series of joystick moves.
// The whole run is done twice: on a stock C64 and with an REU (the engine's REU tier).
// Usage: node test/engine-test.js          (ISO64_REU=0 or 1: only that tier)
const fs = require('fs'), path = require('path'), vm = require('vm');
const makeCPU = require('./cpu6502');
const root = path.join(__dirname, '..');

// --- pull the pure (DOM-free) parts out of the editor -------------------------
const html = fs.readFileSync(path.join(root, 'editor/index.html'), 'utf8');
const js = html.slice(html.indexOf('<script>') + 8, html.lastIndexOf('</script>'));
const cut = (a, b) => js.slice(js.indexOf(a), js.indexOf(b));
const core = js.slice(0, js.indexOf('//  State'));
const exporters = cut('function exportTiles', 'function download');
const ctx = {};
vm.createContext(ctx);
vm.runInContext(core + exporters + `
  var P = newProject(); let encCache = null;
  function enc(){ if(!encCache) encCache = P.tiles.map(t => t ? encodeTile(t) : null); return encCache; }
  this.api = { P, enc, exportTiles, exportMap, exportSprites, renderMap, newFB, project, MW, CENTER_COL, CENTER_ROW, VP };`, ctx);
const E = ctx.api, m = E.P.maps[0];

// same demo map the editor seeds on first run, plus extra cases
for (let y = 10; y < 16; y++) for (let x = 18; x < 24; x++) m.hgt[y * 32 + x] = x > 20 ? 2 : 1;
for (let y = 4; y < 9; y++) for (let x = 4; x < 12; x++) m.terr[y * 32 + x] = 4;
for (let x = 12; x < 20; x++) m.terr[17 * 32 + x] = 3;
[[14, 13], [15, 10], [12, 12], [19, 19]].forEach(([x, y]) => m.obj[y * 32 + x] = 8);
[[10, 18], [11, 18], [12, 18]].forEach(([x, y]) => m.obj[y * 32 + x] = 7);
m.obj[11 * 32 + 19] = 11; m.obj[20 * 32 + 14] = 10; m.obj[15 * 32 + 13] = 9;
m.hgt[16 * 32 + 15] |= 0x80;                       // a flagged blocked cell
for (let x = 0; x < 3; x++) m.terr[0 * 32 + x] = 0;  // void cells at the corner
m.ents.push({ type: 1, sprite: 1, color: 5, hp: 2, atk: 1, def: 0, x: 18, y: 16 },
            { type: 2, sprite: 2, color: 14, hp: 9, atk: 0, def: 0, x: 14, y: 17 },
            { type: 3, sprite: 3, color: 2, hp: 1, atk: 0, def: 0, x: 17, y: 13 },
            { type: 4, sprite: 0, color: 1, hp: 0, atk: 0, def: 0, x: 15, y: 15 });

const files = { TILES: E.exportTiles(), SPRITES: E.exportSprites(), MAP01: E.exportMap(m) };

// --- the REU tier's world image, built from the editor ---------------------------
// Screen cell (c,r) of camera px,py is world cell (c-8+2(px-py)+62, r+px+py). The editor
// renders the same 35 viewport windows the engine's world_build does (cameras may be off
// the map), so this is an independent model of the whole 148x82 image.
const WW = 148, WH = 82, world = { bmp: new Uint8Array(WW * WH * 8), scr: new Uint8Array(WW * WH), col: new Uint8Array(WW * WH) };
for (const d of [-31, -19, -7, 5, 17, 29, 31]) for (const s of [-1, 17, 35, 53, 63]) {
  const px = (s + d) / 2, py = (s - d) / 2, fb = E.newFB();
  E.renderMap(fb, m, E.enc(), px, py);
  for (let r = E.VP.r0; r <= E.VP.r1; r++) for (let c = E.VP.c0; c <= E.VP.c1; c++) {
    const w = (r + px + py) * WW + c - 8 + 2 * (px - py) + 62;
    world.scr[w] = fb.scr[r * 40 + c]; world.col[w] = fb.col[r * 40 + c];
    for (let i = 0; i < 8; i++) world.bmp[w * 8 + i] = fb.bmp[r * 320 + c * 8 + i];
  }
}
// zero-page equates of the C64 layer (not in the label file)
const ZP = {};
for (const l of fs.readFileSync(path.join(root, 'engine/c64/main.s'), 'utf8').split('\n')) {
  const mm = l.match(/^(\w+)\s*=\s*\$([0-9a-f]{2})\b/i); if (mm) ZP[mm[1]] = parseInt(mm[2], 16);
}
const FRAME = 312 * 63;   // PAL cycles per frame
fs.mkdirSync(path.join(root, 'build/c64'), { recursive: true });
for (const [n, d] of Object.entries(files)) fs.writeFileSync(path.join(root, 'build/c64', n.toLowerCase() + '.prg'), d);

// --- boot the engine (stock or with an REU) ------------------------------------
let fails = 0, t0 = 0, last = 0, reuStats;
const summary = [];
function run(reu, ssh) {
  console.log(`\n=== ${reu ? `REU tier (512 KB REU), scroll speed ${1 << ssh} fine step${ssh ? 's' : ''} per frame` : 'stock C64'} ===`);
  reuStats = { dma: 0, bytes: 0 };
  let R = null;
  const mem = new Uint8Array(65536);
  const prg = fs.readFileSync(path.join(root, 'engine/c64/engine.prg'));
  mem.set(prg.subarray(2), prg[0] | prg[1] << 8);
  mem[0xba] = 8; mem[0xdc00] = 0xff;
  const labels = {};
  for (const l of fs.readFileSync(path.join(root, 'engine/c64/engine.lbl'), 'utf8').split('\n')) {
    const mm = l.match(/al ([0-9A-F]+) \.(\w+)/i); if (mm) labels[mm[2]] = parseInt(mm[1], 16);
  }
  const cpu = makeCPU(mem);
  cpu.io = a => a === 0xd012 ? Math.floor(cpu.cyc / 63) % 312 & 255   // PAL raster
    : a >= 0xde00 && !reu ? 0xff : undefined;                          // no cartridge: open bus
  if (reu) {   // REU (1764/1750 style, 512 KB): registers live in mem[$df00-$df0a]
    R = new Uint8Array(0x80000); const step = cpu.step;
    cpu.step = () => { step(); const cmd = mem[0xdf01]; if (cmd & 0x80) reuDMA(cmd); };
    function reuDMA(cmd) {
      let c64 = mem[0xdf02] | mem[0xdf03] << 8, ra = (mem[0xdf04] | mem[0xdf05] << 8 | mem[0xdf06] << 16) & 0x7ffff;
      const len = mem[0xdf07] | mem[0xdf08] << 8 || 0x10000, fixC = mem[0xdf0a] & 0x80, fixR = mem[0xdf0a] & 0x40;
      for (let i = 0; i < len; i++) {
        switch (cmd & 3) {
          case 0: R[ra] = mem[c64]; break;                                      // stash
          case 1: mem[c64] = R[ra]; break;                                      // fetch
          case 2: { const t = R[ra]; R[ra] = mem[c64]; mem[c64] = t; break; }   // swap
          case 3: if (R[ra] !== mem[c64]) mem[0xdf00] |= 0x20; break;           // verify
        }
        if (!fixC) c64 = c64 + 1 & 0xffff;
        if (!fixR) ra = ra + 1 & 0x7ffff;
      }
      cpu.cyc += len;                       // 1 cycle per byte with the CPU halted
      reuStats.dma++; reuStats.bytes += len;
      mem[0xdf00] |= 0x40;                  // end of block
      mem[0xdf01] = cmd & 0x7f | 0x10;
      if (!(cmd & 0x20)) {                  // no autoload: registers keep the end state
        mem[0xdf02] = c64 & 255; mem[0xdf03] = c64 >> 8;
        mem[0xdf04] = ra & 255; mem[0xdf05] = ra >> 8 & 255; mem[0xdf06] = ra >> 16 | 0xf8;
        mem[0xdf07] = 1; mem[0xdf08] = 0;
      }
    }
  }
  cpu.pc = labels.start; cpu.sp = 0xff;
  mem[0x1ff] = 0; mem[0x1fe] = 0;
  let fname = '';
  const keyq = [];
  const kernal = {
    0xffbd: () => { fname = ''; const a = cpu.x | cpu.y << 8; for (let i = 0; i < cpu.a; i++) fname += String.fromCharCode(mem[a + i]); },
    0xffba: () => {},
    0xffe4: () => { cpu.a = keyq.length ? keyq.shift() : 0; cpu.z = cpu.a ? 0 : 1; cpu.n = cpu.a >> 7; cpu.cf = 0; },
    0xffd5: () => { const f = files[fname] || files[Object.keys(files).find(k => fname.endsWith('*') && k.startsWith(fname.slice(0, -1)))]; if (!f) { cpu.cf = 1; return; } mem.set(f.subarray(2), f[0] | f[1] << 8); cpu.cf = 0; },
  };
  const PROF = global.__profile;
  const hooks = {};   // pc -> function, called before that instruction runs
  function spin(n) { for (let k = 0; k < n; k++) { if (kernal[cpu.pc]) { kernal[cpu.pc](); cpu.rts(); } else cpu.step(); } }
  function runUntil(addr, limit = 5e7) {
    for (let n = 0; n < limit; n++) {
      if (kernal[cpu.pc]) { kernal[cpu.pc](); cpu.rts(); continue; }
      if (hooks[cpu.pc]) hooks[cpu.pc]();
      if (cpu.pc === addr) return n;
      if (PROF && PROF.on) { const o = PROF.owner[cpu.pc], c0 = cpu.cyc; if (PROF.entry[cpu.pc]) PROF.calls[o] = (PROF.calls[o] || 0) + 1; cpu.step(); PROF.prof[o] = (PROF.prof[o] || 0) + cpu.cyc - c0; continue; }
      cpu.step();
    }
    throw new Error('timeout, pc=$' + cpu.pc.toString(16));
  }

  // --- compare against the editor model ------------------------------------------
  const ENTS = 0x5900;
  function check(label) {
    const px = mem[2], py = mem[3];
    // the engine mutates entities (bump/kill), so mirror its table
    m.ents.forEach((e, k) => { e.type = mem[ENTS + k * 8]; e.hp = mem[ENTS + k * 8 + 5]; });
    const fb = E.newFB();
    E.renderMap(fb, m, E.enc(), px, py);
    const diff = [];
    const bankB = (mem[0xdd00] & 3) === 0, BM = bankB ? 0xe000 : 0x6000, SCR = bankB ? 0xc000 : 0x4000;
    for (let r = E.VP.r0; r <= E.VP.r1; r++) for (let c = E.VP.c0; c <= E.VP.c1; c++) {
      const o = r * 40 + c;
      if (mem[SCR + o] !== fb.scr[o]) diff.push(`scr ${c},${r}`);
      if ((mem[0xd800 + o] & 15) !== (fb.col[o] & 15)) diff.push(`col ${c},${r}`);
      for (let i = 0; i < 8; i++) if (mem[BM + r * 320 + c * 8 + i] !== fb.bmp[r * 320 + c * 8 + i]) { diff.push(`bmp ${c},${r}`); break; }
    }
    // sprites
    const exp = [];
    const h = (x, y) => m.hgt[y * 32 + x] & 3;
    exp.push([E.CENTER_COL * 8 + 28, (E.CENTER_ROW - h(px, py)) * 8 + 41]);
    for (const e of m.ents) { if (exp.length >= 8) break; if (!e.type || e.type === 4) continue;
      const p = E.project(e.x, e.y, px, py), row = p.row - h(e.x, e.y);
      if (p.col < 8 || p.col > 28 || row < 1 || row > 18) continue;
      exp.push([p.col * 8 + 28, row * 8 + 41]); }
    const en = mem[0xd015];
    if (en !== (1 << exp.length) - 1) diff.push(`sprite enable ${en.toString(2)} vs ${exp.length}`);
    exp.forEach(([x, y], i) => { if (mem[0xd000 + i * 2] !== x || mem[0xd001 + i * 2] !== y) diff.push(`sprite ${i} at ${mem[0xd000 + i * 2]},${mem[0xd001 + i * 2]} want ${x},${y}`); });
    const ok = diff.length === 0;
    if (!ok) fails++;
    console.log(`${ok ? 'PASS' : 'FAIL'} ${label.padEnd(26)} player ${px},${py}  sprites ${exp.length}  bank ${bankB ? 3 : 1}  cycles ${last}${ok ? '' : '\n   ' + diff.slice(0, 8).join('\n   ') + (diff.length > 8 ? `\n   …${diff.length} diffs` : '')}`);
  }

  // --- REU tier: every frame of the scroll animation -------------------------------
  // At each flip (sflip_done) the walk must be exactly where the animation says: one
  // fine step further per frame (2 hires pixels across, 1 line down; times 1<<ssh), in
  // consecutive video frames. Checked per frame: the camera offset, the $d016/$d011 fine
  // scroll it implies, the window fetched (it moves on whenever the fine scroll wraps a
  // cell), the picture the VIC shows (all 320x200 pixels, from bitmap, screen, colour RAM
  // and the fine scroll, against the editor's world image at that camera, with everything
  // outside the viewport plain background), and the sprites.
  const sgn = v => v > 0 ? 1 : v < 0 ? -1 : 0, s8 = v => v << 24 >> 24;
  let walk = null, frameStats = { n: 0, maxWork: 0, sumWork: 0, maxColour: 0, wraps: 0 };
  if (reu) {
    for (let i = 0; i < world.bmp.length; i++) if (R[i] !== world.bmp[i]) { fails++; console.log(`FAIL REU world bitmap differs from the editor at byte ${i}`); break; }
    for (let i = 0; i < WW * WH; i++) if (R[0x18000 + i] !== world.scr[i] || (R[0x1c000 + i] & 15) !== (world.col[i] & 15)) { fails++; console.log(`FAIL REU world screen/colour differs from the editor at cell ${i % WW},${i / WW | 0}`); break; }
    hooks[labels.sflip] = () => { if (walk) walk.enter = cpu.cyc; };
    hooks[labels.sflip_done] = () => frameCheck();
  }
  function frameCheck() {
    const w = walk, k = ++w.k, S = 1 << ssh, px = mem[2], py = mem[3], diff = [];
    const rx = w.rx0 - k * sgn(w.rx0) * 2 * S, ry = w.ry0 - k * sgn(w.ry0) * S;
    if (s8(mem[ZP.rx]) !== rx || s8(mem[ZP.ry]) !== ry) diff.push(`camera offset ${s8(mem[ZP.rx])},${s8(mem[ZP.ry])} want ${rx},${ry}`);
    const xs = rx & 7, ys = ry + 3 & 7;
    if (mem[0xd016] !== (0x18 | xs) || mem[0xd011] !== (0x38 | ys)) diff.push(`fine scroll $d016=${mem[0xd016].toString(16)} $d011=${mem[0xd011].toString(16)} want ${(0x18 | xs).toString(16)} ${(0x38 | ys).toString(16)}`);
    const wc = 2 * (px - py) + 62, wr = px + py + 1, W = wc - (rx >> 3), Rw = wr - (ry + 3 >> 3);
    const fr0 = mem[ZP.fr0];
    if (mem[ZP.wcol] !== (W - 1 & 255) || mem[ZP.wrow] !== Rw - 1 + fr0) diff.push(`window col ${mem[ZP.wcol]} row ${mem[ZP.wrow]} (from screen row ${fr0}) want ${W - 1},${Rw - 1 + fr0}`);
    if (w.win && (w.win[0] !== W || w.win[1] !== Rw)) frameStats.wraps++;
    w.win = [W, Rw];
    // picture: what the VIC shows vs the world image seen from camera pixel CX,CY
    const CX = wc * 8 - rx, CY = wr * 8 - ry, bg = mem[0x4c07], d = ys - 3;
    const bankB = (mem[0xdd00] & 3) === 0, BM = bankB ? 0xe000 : 0x6000, SCR = bankB ? 0xc000 : 0x4000;
    if (mem[(bankB ? 0xc000 : 0x4000) + 0x3fff - 0x4000 + 0x4000] !== undefined && mem[bankB ? 0xffff : 0x7fff]) diff.push('idle byte $3fff of the bank is not 0');
    const colour = (bmp, scr, col, b, bit) => { const p = bmp[b] >> 6 - bit & 3; return p === 0 ? bg : p === 1 ? scr >> 4 : p === 2 ? scr & 15 : col & 15; };
    let bad = 0, first = '';
    for (let Y = 0; Y < 200; Y++) for (let X = 0; X < 320; X += 2) {
      let want = bg, got = bg;
      if (X >= 64 && X < 256 && Y >= 8 && Y < 152) {
        const wx = CX + X - 64, wy = CY + Y - 8, cell = (wy >> 3) * WW + (wx >> 3);
        want = colour(world.bmp, world.scr[cell], world.col[cell], cell * 8 + (wy & 7), wx & 7);
      }
      const bx = X - xs, by = Y - d;
      if (bx >= 0 && by >= 0 && by < 200) { const o = (by >> 3) * 40 + (bx >> 3);
        got = colour(mem, mem[SCR + o], mem[0xd800 + o], BM + (by >> 3) * 320 + (bx & ~7) + (by & 7), bx & 7); }
      if (got !== want && !bad++) first = `pixel ${X},${Y}: colour ${got} want ${want}`;
    }
    if (bad) diff.push(`${bad} pixels differ, first ${first}`);
    // sprites: the hero stays centred (its height eases over the step), the rest move with the world
    m.ents.forEach((e, i) => { e.type = mem[ENTS + i * 8]; });
    const h = (x, y) => m.hgt[y * 32 + x] & 3, hd = h(px, py) - h(w.ox, w.oy);
    const hy8 = 64 * hd - k * hd * 64 / w.n;
    const exp = [[E.CENTER_COL * 8 + 28, (E.CENTER_ROW - h(px, py)) * 8 + 41 + Math.floor(hy8 / 8)]];
    for (const e of m.ents) { if (exp.length >= 8) break; if (!e.type || e.type === 4) continue;
      const p = E.project(e.x, e.y, px, py), x2 = 4 * p.col + 14 + (rx >> 1), y = 8 * (p.row - h(e.x, e.y)) + 41 + ry;
      if (x2 >= 46 && x2 <= 126 && y >= 49 && y <= 185) exp.push([2 * x2, y]); }
    if (mem[0xd015] !== (1 << exp.length) - 1) diff.push(`sprite enable ${mem[0xd015].toString(2)} vs ${exp.length}`);
    exp.forEach(([x, y], i) => { if (mem[0xd000 + i * 2] !== x || mem[0xd001 + i * 2] !== y) diff.push(`sprite ${i} at ${mem[0xd000 + i * 2]},${mem[0xd001 + i * 2]} want ${x},${y}`); });
    // timing: one frame per video frame; work = from the last flip to waiting for this one
    const vf = Math.floor(cpu.cyc / FRAME);
    if (w.vf !== undefined) {
      if (vf !== w.vf + 1) diff.push(`frame shown in video frame +${vf - w.vf} (dropped)`);
      const work = w.enter - w.done;
      frameStats.n++; frameStats.sumWork += work; frameStats.maxWork = Math.max(frameStats.maxWork, work);
    }
    frameStats.maxColour = Math.max(frameStats.maxColour, cpu.cyc - w.enter);
    w.vf = vf; w.done = cpu.cyc;
    if (diff.length) { fails++; w.bad = true; console.log(`FAIL   frame ${k}/${w.n} of ${w.label}: camera ${CX},${CY}\n     ${diff.slice(0, 6).join('\n     ')}`); }
  }
  function startWalk(label) {   // before a press: the animation that a step will play
    if (!reu) return;
    walk = { label, ox: mem[2], oy: mem[3], k: 0 };
  }
  function endWalk() {          // after it: the right number of frames, or none for no step
    if (!reu) return '';
    const w = walk, dx = mem[2] - w.ox, dy = mem[3] - w.oy;
    w.rx0 = 16 * (dx - dy); w.ry0 = 8 * (dx + dy);
    const n = w.rx0 ? Math.abs(w.rx0) / (2 << ssh) : Math.abs(w.ry0) / (1 << ssh);
    walk = null;
    if (w.k !== n) { fails++; console.log(`FAIL   ${w.label}: ${w.k} scroll frames, want ${n}`); }
    return n ? `  ${n} frames ok` : '';
  }

  // joystick: bits 0 up 1 down 2 left 3 right (active low)
  const J = { up: 0xfe, down: 0xfd, left: 0xfb, right: 0xf7, upright: 0xf6, upleft: 0xfa, downleft: 0xf9, downright: 0xf5 };
  t0 = cpu.cyc; runUntil(labels.get_move); last = cpu.cyc - t0; check('start'); const boot = last;
  const steps = [];
  if (PROF) {   // node test/profile.js <move>: profile a single step and stop
    spin(40); mem[0xdc00] = J[process.env.ISO64_PROFILE]; PROF.on = true;
    t0 = cpu.cyc; runUntil(labels.main_loop); const tot = cpu.cyc - t0; PROF.on = false;
    console.log(`
  ${process.env.ISO64_PROFILE}: ${tot} cycles (${(tot / 985248 * 1000).toFixed(0)} ms PAL)`);
    for (const [k, v] of Object.entries(PROF.prof).sort((a, b) => b[1] - a[1])) console.log(`  ${k.padEnd(18)} ${String(v).padStart(8)}  ${(100 * v / tot).toFixed(1).padStart(5)}%  ${PROF.calls[k] ? PROF.calls[k] + ' calls' : ''}`);
    process.exit(0);
  }
  if (process.env.ISO64_KEYS) {   // replay keys, dump the shown frame to test/out/emu.png
    const Kq = { w: 0x57, s: 0x53, a: 0x41, d: 0x44, q: 0x51, e: 0x45, z: 0x5a, c: 0x43 };
    for (const ch of process.env.ISO64_KEYS) { spin(40); keyq.push(Kq[ch]); runUntil(labels.main_loop); runUntil(labels.get_move); }
    const bankB = (mem[0xdd00] & 3) === 0, BM = bankB ? 0xe000 : 0x6000, SCR = bankB ? 0xc000 : 0x4000;
    const PALv = [0x000000,0xffffff,0x9f4e44,0x6abfc6,0xa057a3,0x5cab5e,0x50459b,0xc9d487,0xa1683c,0x6d5412,0xcb7e75,0x626262,0x898989,0x9ae29b,0x887ecb,0xadadad];
    const W = 320, H = 200, raw = Buffer.alloc((W * 3 + 1) * H);
    for (let y = 0; y < H; y++) { raw[y * (W * 3 + 1)] = 0; for (let x = 0; x < W; x++) {
      const col = x >> 3, row = y >> 3, o = row * 40 + col, b = mem[BM + row * 320 + col * 8 + (y & 7)], pair = (b >> (6 - ((x & 7) >> 1) * 2)) & 3;
      const c = PALv[[mem[0x4c07], mem[SCR + o] >> 4, mem[SCR + o] & 15, mem[0xd800 + o] & 15][pair]];
      raw.set([c >> 16, c >> 8 & 255, c & 255], y * (W * 3 + 1) + 1 + x * 3); } }
    const zlib = require('zlib'), crc = b => { let c, t = []; for (let n = 0; n < 256; n++) { c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; }
      let r = 0xffffffff; for (const x of b) r = t[(r ^ x) & 255] ^ (r >>> 8); return (r ^ 0xffffffff) >>> 0; };
    const chunk = (ty, d) => { const l = Buffer.alloc(4); l.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(ty), d]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([l, td, c]); };
    const ih = Buffer.alloc(13); ih.writeUInt32BE(W, 0); ih.writeUInt32BE(H, 4); ih[8] = 8; ih[9] = 2;
    fs.writeFileSync(path.join(root, 'test/out/emu.png'), Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]), chunk('IHDR', ih), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]));
    console.log(`after "${process.env.ISO64_KEYS}": player ${mem[2]},${mem[3]}, bank ${bankB ? 3 : 1} -> test/out/emu.png`);
    process.exit(0);
  }
  const moves = ['up', 'up', 'right', 'right', 'right', 'upright', 'upright', 'up', 'up', 'left', 'left', 'downleft', 'down', 'down', 'down', 'down',
    'down', 'down', 'down', 'down',            // bump the goblin (hp 2) until it dies, then step in
    'up', 'left', 'left', 'left', 'left', 'left', 'up', 'up', 'upleft', 'upleft', 'up', 'left', 'left', 'downleft'];
  for (const mv of moves) {
    spin(40);  // released stick: now spinning in the wait-for-press loop
    mem[0xdc00] = J[mv];
    const bx = mem[2], by = mem[3];
    t0 = cpu.cyc; runUntil(labels.main_loop); last = cpu.cyc - t0;
    mem[0xdc00] = 0xff;
    if (mem[2] !== bx || mem[3] !== by) steps.push(last);
    runUntil(labels.get_move); check(mv);
  }
  // keyboard: W/S/A/D + cursor keys = screen directions, Q/E/Z/C = map axes
  const K = { w: 0x57, s: 0x53, a: 0x41, d: 0x44, q: 0x51, e: 0x45, z: 0x5a, c: 0x43, up: 0x91, down: 0x11, left: 0x9d, right: 0x1d };
  const keyMoves = [['s', 1, 1], ['d', 1, -1], ['a', -1, 1], ['w', -1, -1], ['q', -1, 0], ['e', 0, -1], ['z', 0, 1], ['c', 1, 0],
    ['down', 1, 1], ['right', 1, -1], ['left', -1, 1], ['up', -1, -1]];
  for (const [k, dx, dy] of keyMoves) {
    const bx = mem[2], by = mem[3];
    spin(40);
    keyq.push(K[k]);
    t0 = cpu.cyc; runUntil(labels.main_loop); last = cpu.cyc - t0;
    runUntil(labels.get_move);
    const moved = mem[2] === bx + dx && mem[3] === by + dy, stayed = mem[2] === bx && mem[3] === by;
    if (moved) steps.push(last);
    if (!moved && !stayed) { fails++; console.log(`FAIL key ${k}: ${bx},${by} -> ${mem[2]},${mem[3]}`); }
    check('key ' + k + (stayed ? ' (blocked)' : ''));
  }
  const avg = steps.reduce((a, b) => a + b, 0) / steps.length;
  summary.push({ tier: reu ? 'REU' : 'stock', boot, avg, min: Math.min(...steps), max: Math.max(...steps), n: steps.length, dma: reuStats });
}
const tiers = process.env.ISO64_REU === '1' ? [true] : process.env.ISO64_REU === '0' ? [false] : [false, true];
for (const t of tiers) run(t);
console.log('\nstep cycles (press to main_loop, incl. waiting for the flip raster line):');
for (const s of summary) console.log(`  ${s.tier.padEnd(6)} boot ${String(s.boot).padStart(9)}  steps ${s.n}: avg ${s.avg.toFixed(0)}  min ${s.min}  max ${s.max}` +
  (s.dma.dma ? `  (REU: ${s.dma.dma} DMAs, ${s.dma.bytes} bytes in all)` : ''));
console.log(fails ? `\n${fails} FAILED` : '\nall frames match the editor preview');
process.exit(fails ? 1 : 0);
