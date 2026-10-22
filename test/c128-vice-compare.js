// Compares a VICE x128 screenshot (VDC window, PNG) with an editor C128 preview PNG
// written by test/c128-test.js: finds the 640x200 picture inside VICE's border and
// counts pixels that differ. Usage: node test/c128-vice-compare.js vice.png editor.png
const fs = require('fs'), zlib = require('zlib');
function readPNG(file) {
  const b = fs.readFileSync(file); let o = 8, w, h, ct, idat = [], plte = null;
  while (o < b.length) {
    const len = b.readUInt32BE(o), t = b.toString('ascii', o + 4, o + 8), d = b.subarray(o + 8, o + 8 + len);
    if (t === 'IHDR') { w = d.readUInt32BE(0); h = d.readUInt32BE(4); ct = d[9]; if (d[8] !== 8) throw new Error('8-bit PNGs only'); }
    if (t === 'PLTE') plte = d;
    if (t === 'IDAT') idat.push(d);
    o += 12 + len;
  }
  const bpp = { 2: 3, 6: 4, 3: 1 }[ct], raw = zlib.inflateSync(Buffer.concat(idat)), px = Buffer.alloc(w * h * bpp), st = w * bpp;
  for (let y = 0; y < h; y++) {
    const f = raw[y * (st + 1)], row = raw.subarray(y * (st + 1) + 1, (y + 1) * (st + 1));
    for (let x = 0; x < st; x++) {
      const a = x >= bpp ? px[y * st + x - bpp] : 0, u = y ? px[(y - 1) * st + x] : 0, c = x >= bpp && y ? px[(y - 1) * st + x - bpp] : 0;
      const p = a + u - c, pa = Math.abs(p - a), pb = Math.abs(p - u), pc = Math.abs(p - c);
      px[y * st + x] = row[x] + [0, a, u, a + u >> 1, pa <= pb && pa <= pc ? a : pb <= pc ? u : c][f] & 255;
    }
  }
  const rgb = (x, y) => { const i = (y * w + x) * bpp; return ct === 3 ? [plte[px[i] * 3], plte[px[i] * 3 + 1], plte[px[i] * 3 + 2]] : [px[i], px[i + 1], px[i + 2]]; };
  return { w, h, rgb };
}
const [vice, ed] = process.argv.slice(2).map(readPNG);
let best = null;
for (let oy = 0; oy + ed.h <= vice.h; oy++) for (let ox = 0; ox + ed.w <= vice.w; ox++) {
  let bad = 0;
  for (let y = 0; y < ed.h && bad < 50; y += 7) for (let x = 0; x < ed.w; x += 13) { const p = vice.rgb(ox + x, oy + y), q = ed.rgb(x, y); if (p[0] !== q[0] || p[1] !== q[1] || p[2] !== q[2]) bad++; }
  if (!best || bad < best.bad) best = { ox, oy, bad };
}
let diff = 0, first = '';
for (let y = 0; y < ed.h; y++) for (let x = 0; x < ed.w; x++) {
  const p = vice.rgb(best.ox + x, best.oy + y), q = ed.rgb(x, y);
  if (p[0] !== q[0] || p[1] !== q[1] || p[2] !== q[2]) { if (!diff) first = ` (first at ${x},${y}: VICE ${p} editor ${q})`; diff++; }
}
console.log(`picture at ${best.ox},${best.oy} in the ${vice.w}x${vice.h} screenshot: ${diff} of ${ed.w * ed.h} pixels differ${first}`);
process.exit(diff ? 1 : 0);
