// Minimal 6502 core (official opcodes, no decimal mode) for headless engine tests.
// Counts real cycles (incl. page-cross and taken-branch penalties) in c.cyc.
// c.io(addr) may return a value for reads in c.ioLo..c.ioHi (default $d000-$dfff),
// e.g. the raster line. c.iow(addr, value) may take writes in the same range
// (return true to keep them out of mem), e.g. the C128's VDC ports.
module.exports = function makeCPU(mem) {
  const c = { a: 0, x: 0, y: 0, sp: 0xfd, pc: 0, n: 0, v: 0, z: 0, cf: 0, i: 1, d: 0, cycles: 0, cyc: 0, io: null, ioLo: 0xd000, ioHi: 0xe000 };
  let pen = 0;
  const rd = a => { a &= 0xffff; if (c.io && a >= c.ioLo && a < c.ioHi) { const v = c.io(a); if (v !== undefined) return v; } return mem[a]; };
  const wr = (a, v) => { a &= 0xffff; if (c.iow && a >= c.ioLo && a < c.ioHi && c.iow(a, v & 255)) return; mem[a] = v & 255; };
  const rd16 = a => rd(a) | (rd(a + 1) << 8);
  const zp16 = a => rd(a & 255) | (rd((a + 1) & 255) << 8);
  const nz = v => { v &= 255; c.n = v >> 7; c.z = v === 0 ? 1 : 0; return v; };
  const push = v => { wr(0x100 + c.sp, v); c.sp = (c.sp - 1) & 255; };
  const pop = () => { c.sp = (c.sp + 1) & 255; return rd(0x100 + c.sp); };
  const getP = () => (c.n << 7) | (c.v << 6) | 0x20 | 0x10 | (c.d << 3) | (c.i << 2) | (c.z << 1) | c.cf;
  const setP = p => { c.n = p >> 7 & 1; c.v = p >> 6 & 1; c.d = p >> 3 & 1; c.i = p >> 2 & 1; c.z = p >> 1 & 1; c.cf = p & 1; };
  const fetch = () => rd(c.pc++);
  const fetch16 = () => { const v = rd16(c.pc); c.pc += 2; return v; };
  const idx = (b, r) => { const a = (b + r) & 0xffff; pen = (a ^ b) >> 8 ? 1 : 0; return a; };
  // addressing modes -> effective address
  const AM = {
    imm: () => c.pc++, zp: () => fetch(), zpx: () => (fetch() + c.x) & 255, zpy: () => (fetch() + c.y) & 255,
    abs: () => fetch16(), abx: () => idx(fetch16(), c.x), aby: () => idx(fetch16(), c.y),
    izx: () => zp16(fetch() + c.x), izy: () => idx(zp16(fetch()), c.y),
  };
  const adc = v => { const r = c.a + v + c.cf; c.v = (~(c.a ^ v) & (c.a ^ r) & 0x80) ? 1 : 0; c.cf = r > 255 ? 1 : 0; c.a = nz(r); };
  const cmp = (r, v) => { const t = r - v; c.cf = t >= 0 ? 1 : 0; nz(t); };
  const br = cond => { const o = fetch(); if (cond) { const t = (c.pc + (o < 128 ? o : o - 256)) & 0xffff; c.cyc += (t ^ c.pc) >> 8 ? 2 : 1; c.pc = t; } };
  const rmw = (am, f) => { const a = AM[am](); wr(a, f(rd(a))); };
  const asl = v => { c.cf = v >> 7; return nz(v << 1); }, lsr = v => { c.cf = v & 1; return nz(v >> 1); };
  const rol = v => { const r = (v << 1) | c.cf; c.cf = v >> 7; return nz(r); }, ror = v => { const r = (v >> 1) | (c.cf << 7); c.cf = v & 1; return nz(r); };
  const ops = {}, cyc = {};
  const CR = { imm: 2, zp: 3, zpx: 4, zpy: 4, abs: 4, abx: 4, aby: 4, izx: 6, izy: 5 };   // reads (+1 on page cross)
  const CW = { zp: 3, zpx: 4, zpy: 4, abs: 4, abx: 5, aby: 5, izx: 6, izy: 6 };            // writes
  const CM = { zp: 5, zpx: 6, abs: 6, abx: 7 };                                             // read-modify-write
  const def = (codes, fn, kind = 'r') => { for (const [op, am] of codes) {
    cyc[op] = (kind === 'r' ? CR : kind === 'w' ? CW : CM)[am];
    ops[op] = kind === 'r' ? () => { pen = 0; fn(am); c.cyc += pen; } : () => fn(am); } };
  def([[0xa9,'imm'],[0xa5,'zp'],[0xb5,'zpx'],[0xad,'abs'],[0xbd,'abx'],[0xb9,'aby'],[0xa1,'izx'],[0xb1,'izy']], am => { c.a = nz(rd(AM[am]())); });
  def([[0xa2,'imm'],[0xa6,'zp'],[0xb6,'zpy'],[0xae,'abs'],[0xbe,'aby']], am => { c.x = nz(rd(AM[am]())); });
  def([[0xa0,'imm'],[0xa4,'zp'],[0xb4,'zpx'],[0xac,'abs'],[0xbc,'abx']], am => { c.y = nz(rd(AM[am]())); });
  def([[0x85,'zp'],[0x95,'zpx'],[0x8d,'abs'],[0x9d,'abx'],[0x99,'aby'],[0x81,'izx'],[0x91,'izy']], am => wr(AM[am](), c.a), 'w');
  def([[0x86,'zp'],[0x96,'zpy'],[0x8e,'abs']], am => wr(AM[am](), c.x), 'w');
  def([[0x84,'zp'],[0x94,'zpx'],[0x8c,'abs']], am => wr(AM[am](), c.y), 'w');
  def([[0x69,'imm'],[0x65,'zp'],[0x75,'zpx'],[0x6d,'abs'],[0x7d,'abx'],[0x79,'aby'],[0x61,'izx'],[0x71,'izy']], am => adc(rd(AM[am]())));
  def([[0xe9,'imm'],[0xe5,'zp'],[0xf5,'zpx'],[0xed,'abs'],[0xfd,'abx'],[0xf9,'aby'],[0xe1,'izx'],[0xf1,'izy']], am => adc(rd(AM[am]()) ^ 255));
  def([[0x29,'imm'],[0x25,'zp'],[0x35,'zpx'],[0x2d,'abs'],[0x3d,'abx'],[0x39,'aby'],[0x21,'izx'],[0x31,'izy']], am => { c.a = nz(c.a & rd(AM[am]())); });
  def([[0x09,'imm'],[0x05,'zp'],[0x15,'zpx'],[0x0d,'abs'],[0x1d,'abx'],[0x19,'aby'],[0x01,'izx'],[0x11,'izy']], am => { c.a = nz(c.a | rd(AM[am]())); });
  def([[0x49,'imm'],[0x45,'zp'],[0x55,'zpx'],[0x4d,'abs'],[0x5d,'abx'],[0x59,'aby'],[0x41,'izx'],[0x51,'izy']], am => { c.a = nz(c.a ^ rd(AM[am]())); });
  def([[0xc9,'imm'],[0xc5,'zp'],[0xd5,'zpx'],[0xcd,'abs'],[0xdd,'abx'],[0xd9,'aby'],[0xc1,'izx'],[0xd1,'izy']], am => cmp(c.a, rd(AM[am]())));
  def([[0xe0,'imm'],[0xe4,'zp'],[0xec,'abs']], am => cmp(c.x, rd(AM[am]())));
  def([[0xc0,'imm'],[0xc4,'zp'],[0xcc,'abs']], am => cmp(c.y, rd(AM[am]())));
  def([[0x24,'zp'],[0x2c,'abs']], am => { const v = rd(AM[am]()); c.n = v >> 7; c.v = v >> 6 & 1; c.z = (v & c.a) ? 0 : 1; });
  def([[0xe6,'zp'],[0xf6,'zpx'],[0xee,'abs'],[0xfe,'abx']], am => rmw(am, v => nz(v + 1)), 'm');
  def([[0xc6,'zp'],[0xd6,'zpx'],[0xce,'abs'],[0xde,'abx']], am => rmw(am, v => nz(v - 1)), 'm');
  def([[0x06,'zp'],[0x16,'zpx'],[0x0e,'abs'],[0x1e,'abx']], am => rmw(am, asl), 'm');
  def([[0x46,'zp'],[0x56,'zpx'],[0x4e,'abs'],[0x5e,'abx']], am => rmw(am, lsr), 'm');
  def([[0x26,'zp'],[0x36,'zpx'],[0x2e,'abs'],[0x3e,'abx']], am => rmw(am, rol), 'm');
  def([[0x66,'zp'],[0x76,'zpx'],[0x6e,'abs'],[0x7e,'abx']], am => rmw(am, ror), 'm');
  Object.assign(ops, {
    0x0a: () => { c.a = asl(c.a); }, 0x4a: () => { c.a = lsr(c.a); }, 0x2a: () => { c.a = rol(c.a); }, 0x6a: () => { c.a = ror(c.a); },
    0xe8: () => { c.x = nz(c.x + 1); }, 0xca: () => { c.x = nz(c.x - 1); }, 0xc8: () => { c.y = nz(c.y + 1); }, 0x88: () => { c.y = nz(c.y - 1); },
    0xaa: () => { c.x = nz(c.a); }, 0x8a: () => { c.a = nz(c.x); }, 0xa8: () => { c.y = nz(c.a); }, 0x98: () => { c.a = nz(c.y); },
    0xba: () => { c.x = nz(c.sp); }, 0x9a: () => { c.sp = c.x; },
    0x48: () => push(c.a), 0x68: () => { c.a = nz(pop()); }, 0x08: () => push(getP()), 0x28: () => setP(pop()),
    0x18: () => { c.cf = 0; }, 0x38: () => { c.cf = 1; }, 0x58: () => { c.i = 0; }, 0x78: () => { c.i = 1; }, 0xb8: () => { c.v = 0; }, 0xd8: () => { c.d = 0; }, 0xf8: () => { c.d = 1; },
    0x10: () => br(!c.n), 0x30: () => br(c.n), 0x50: () => br(!c.v), 0x70: () => br(c.v),
    0x90: () => br(!c.cf), 0xb0: () => br(c.cf), 0xd0: () => br(!c.z), 0xf0: () => br(c.z),
    0x4c: () => { c.pc = fetch16(); }, 0x6c: () => { const a = fetch16(); c.pc = rd(a) | (rd((a & 0xff00) | ((a + 1) & 255)) << 8); },
    0x20: () => { const t = fetch16(); const r = (c.pc - 1) & 0xffff; push(r >> 8); push(r & 255); c.pc = t; },
    0x60: () => { const lo = pop(), hi = pop(); c.pc = ((hi << 8) | lo) + 1 & 0xffff; },
    0x40: () => { setP(pop()); const lo = pop(), hi = pop(); c.pc = (hi << 8) | lo; },
    0xea: () => {},
  });
  const IMPL = { 0x48: 3, 0x08: 3, 0x68: 4, 0x28: 4, 0x4c: 3, 0x6c: 5, 0x20: 6, 0x60: 6, 0x40: 6 };
  for (const k in ops) if (cyc[k] === undefined) cyc[k] = IMPL[k] ?? 2;
  c.step = () => { const op = fetch(); const f = ops[op]; if (!f) throw new Error('bad opcode $' + op.toString(16) + ' at $' + ((c.pc - 1) & 0xffff).toString(16)); c.cyc += cyc[op]; f(); c.cycles++; };
  c.rts = () => ops[0x60]();
  return c;
};
