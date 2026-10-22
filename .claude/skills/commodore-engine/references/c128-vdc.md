# C128 / VDC cheat-sheet

Sources are in `docs/research/c128.md` (C128 Programmer's Reference Guide). The C128 VDC engine is in progress on its own branch.

## CPU and modes

- **8502:** an NMOS 6502. Stable illegal opcodes work as on the 6510.
- **2 MHz** via `$d030` bit 0. It garbles the 40-column VIC-II, so blank the VIC-II (`$d011` bit 4 = 0) and stay at 2 MHz for the 80-column engine.
- CIA timers stay at 1 MHz.
- **In C64 mode,** `$d030` still works (it reads `$fc`/`$fd`, while a C64 reads `$ff`). Use 2 MHz only outside the display lines. Keep 1 MHz for REU DMA and KERNAL I/O.

## VDC access

- `$d600`: write the register number; read the status (bit 7 ready, bit 5 vertical blank).
- `$d601`: data.

```
wreg: stx $d600
:     bit $d600
      bpl :-
      sta $d601
```

**Registers:**

| Reg | Use |
|---|---|
| R12/R13 | Display start (page flip / coarse scroll) |
| R18/R19 | Update address |
| R20/R21 | Attribute start |
| R24 | Bit 7 copy (1) / fill (0), bits 0–4 vertical fine scroll |
| R25 | Bit 7 bitmap, bit 6 attributes, bits 0–3 horizontal fine scroll |
| R26 | Colours |
| R27 | Row address increment (virtual width) |
| R28 | Bit 4 = 64 KB DRAM layout |
| R30 | Count: writing it starts the fill or copy (1–255) |
| R31 | Data, auto-increments the address |
| R32/R33 | Copy source |
| R9 | Scan lines per row − 1 (attribute cell height) |

**64 KB check** (VICE ✓): set R28 bit 4, write `$00` at `$0000` and `$55` at `$8000`, read back `$0000`. It reads `$00` on a 64 KB VDC.

## Measured speeds (VICE x128, PAL)

| Operation | Speed |
|---|---|
| CPU write through R31 with ready polling | **31 µs per byte at 1 MHz, 22 µs at 2 MHz** |
| CPU read through R31 | 31 µs per byte |
| **Block fill** | **0.85 µs per byte** |
| **Block copy** | **1.47 µs per byte** |

🔧 Real hardware is unmeasured, so trust the ratio, not the absolute numbers.

**Design rules that follow:**
- Keep tiles in VDC RAM and **draw with block copy/fill**.
- Avoid CPU read-modify-write on VDC memory (masking). Compose masked cells in main RAM at 2 MHz instead.
- **Double buffer:** two 16 KB bitmaps + attributes in 64 KB, flipped by R12/R13 (+R20/R21) during vertical blank.
- **Hardware scroll:** R12/R13 + R27 pan a virtual bitmap wider than the display; R24/R25 do the fine scroll.
- **Denser colour:** R9 = 3 or 1 gives 8×4 or 8×2 attribute cells. The editor's `c128.js` must model whichever choice is made.

## MMU and KERNAL

| Item | Use |
|---|---|
| `$ff00` | Configuration (RAM bank 0/1, ROM/I/O) |
| `$d505` | Mode (bit 6 = C64 mode) |
| `$d506` | Common RAM |
| `$d507`–`$d50a` | **Zero page and stack relocation** |
| `$ff68` SETBNK | Data bank and filename bank, before `LOAD` |
| `$ff6e` JSRFAR / `$ff74` INDFET / `$ff77` INDSTA | Cross-bank calls and accesses |

- `LOAD` uses 1571/1581 burst automatically. sd2iec probably doesn't support burst (unconfirmed).
- 128 KB of RAM: keep code and the zero page in bank 0, tile and map data in bank 1.
