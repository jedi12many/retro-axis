// Cycle profile of one engine step: wraps cpu.step to charge each instruction's
// cycles to the nearest preceding label in engine.lbl.
// Usage: node test/profile.js [move]          C64 (move = joystick direction, default "right")
//        node test/profile.js vic20 [key]     VIC-20 (key as in test/vic20-test.js, default "d")
const path = require('path'), fs = require('fs');
const vic = process.argv[2] === 'vic20';
const [lblFile, lo, hi] = vic ? ['../engine/vic20/engine.lbl', 0x2000, 0x3800] : ['../engine/c64/engine.lbl', 0x801, 0x3e00];
const lbl = fs.readFileSync(path.join(__dirname, lblFile), 'utf8').split('\n')
  .map(l => l.match(/al ([0-9A-F]+) \.(\w+)/i)).filter(m => m && !m[2].startsWith('__'))
  .map(m => [parseInt(m[1], 16), m[2]]).filter(([a]) => a >= lo && a < hi).sort((a, b) => a[0] - b[0]);
const owner = new Array(65536).fill('?');
for (let i = 0; i < lbl.length; i++) for (let a = lbl[i][0]; a < (lbl[i + 1] ? lbl[i + 1][0] : hi); a++) owner[a] = lbl[i][1];
const entry = {}; for (const [a] of lbl) entry[a] = true;
global.__profile = { owner, entry, prof: {}, calls: {}, on: false };
process.env.ISO64_PROFILE = process.argv[vic ? 3 : 2] || (vic ? 'd' : 'right');
require(vic ? './vic20-test.js' : './engine-test.js');
