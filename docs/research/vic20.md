# VIC-20: research for ISO64

Confidence marks are as in [c64.md](c64.md): H / M / L, 🔧 = real hardware needed, VICE ✓ = checked in xvic.

**References:**
- VIC-20 Programmer's Reference Guide (Commodore, 1982)
- VIC chip page: https://www.c64-wiki.com/wiki/VIC
- Memory map: https://www.retroisle.com/commodore/vic20/Technical/Firmware/VIC_MemoryMap.php
- Denial forum (VIC-20 scene): https://sleepingelephant.com/ipw-web/bulletin/bb/
- UltiMem register summary: https://www.go4retro.com/products/ultimem/
- Final Expansion 3 registers: MAME `src/devices/bus/vic20/fe3.h` and `fe3.cpp` (https://github.com/mamedev/mame)
- VICE manual, xvic section (`-memory`, `-cartfe`, UltiMem cartridge images)

ISO64's VIC-20 engine is described in PLATFORMS.md §6:
- PAL, ≥ 24K expansion in blocks 1–3;
- a dynamic multicolour character set rebuilt per frame, 112 codes per frame;
- double buffering through `$9002` bit 7;
- soft sprites composited into the characters;
- 130–290k cycles per step (229k on average).

---

## 1. Timing

| | PAL (6561) | NTSC (6560) |
|---|---|---|
| CPU clock | 1,108,405 Hz | 1,022,727 Hz |
| Cycles per line | 71 | 65 |
| Lines per frame | 312 | 261 (non-interlaced) |
| Cycles per frame | 22,152 | 16,965 |

H (standard figures; PAL is the engine's target).

- **The VIC never steals CPU cycles.** It fetches on the other clock phase, so cycle counts are exact everywhere: no badlines, no sprite DMA. H
- **There is no raster interrupt.** Raster position comes from `$9004` (raster line ÷ 2) and `$9003` bit 7 (the line's low bit).
  - For timed effects, poll, or sync a VIA timer to the raster once and let it free-run at exactly one frame (22,152 cycles PAL).
  - ISO64 polls `$9004` for the flip (`FLIP_RAST` = 114, i.e. line 228). H
- **NTSC:** a different screen origin (`$9000`/`$9001` defaults 5/25 vs PAL 12/38), fewer visible lines and a lower clock. The engine and editor are PAL-only today. M

## 2. Memory: all RAM blocks

| Range | Block | Seen by the VIC? | Notes |
|---|---|---|---|
| `$0000-$03ff` | internal 1 KB | yes | ZP, stack, KERNAL variables. VIC-visible, but the KERNAL uses `$0200-$03ff` |
| `$0400-$0fff` | RAM1–3 ("3K expansion") | **no** | Separate cartridge. ISO64 doesn't use it (a 24K+ cart usually lacks it) |
| `$1000-$1fff` | internal 4 KB | **yes** | The only RAM where screens and character sets can live. ISO64: 2 screens + 256 characters + tables |
| `$2000-$3fff` | BLK1 | no | expansion |
| `$4000-$5fff` | BLK2 | no | expansion |
| `$6000-$7fff` | BLK3 | no | expansion |
| `$8000-$8fff` | character ROM | yes | |
| `$9000-$93ff` | I/O: VIC `$9000-$900f`, VIA1 `$9110`, VIA2 `$9120` | | |
| `$9400-$97ff` | colour RAM, 1 K × 4 bits | yes | `$9400` or `$9600` half, chosen by `$9002` bit 7. ISO64 flips between them |
| `$9800-$9bff` | I/O2 | | cartridge I/O |
| `$9c00-$9fff` | I/O3 | | FE3 registers `$9c02/$9c03`; UltiMem registers `$9ff0-$9fff` |
| `$a000-$bfff` | BLK5 | no | cartridge ROM, or RAM on FE3/UltiMem ("35K" configuration) |
| `$c000-$ffff` | BASIC + KERNAL ROM | | |

H. VICE ✓: `xvic -memory 24k` is the engine's tested configuration. `-memory all` adds BLK5 and RAM1–3.

## 3. VIC (6561) registers and tricks

| Reg | Bits |
|---|---|
| `$9000` | Bit 7 **interlace**; bits 0–6 horizontal origin (4-pixel units) |
| `$9001` | Vertical origin (2-line units on PAL) |
| `$9002` | Bit 7 = screen address bit 9 **and** colour RAM half (ISO64's flip bit); bits 0–6 = number of columns |
| `$9003` | Bit 7 raster bit 0; bits 1–6 number of rows; **bit 0 = 8×16 characters** |
| `$9004` | Raster line bits 8–1 |
| `$9005` | Bits 4–7 screen base, bits 0–3 character base (VIC address space: values 8–15 map to RAM `$0000-$1c00`, 0–7 to ROM `$8000-$9c00`) |
| `$900a-$900c` | Voices 1–3 (bit 7 on, bits 0–6 frequency), three octaves apart |
| `$900d` | Noise |
| `$900e` | Bits 0–3 volume, **bits 4–7 auxiliary colour** |
| `$900f` | Bits 4–7 screen colour, bit 3 = 0 for inverted mode, bits 0–2 border colour |

H. Multicolour per cell: colour RAM bit 3 = 1 selects 2-bit pixels. The pixel pairs are `00` screen, `01` border, `10` the cell colour (colour RAM bits 0–2, 8 colours), `11` auxiliary.

**Tricks relevant to ISO64:**

- **Dynamic character set (in use):** the VIC-20's "bitmap" is a character set rebuilt every frame. ISO64's labels-and-hash emit is the right shape. H
- **8×16 characters** (`$9003` bit 0):
  - 20×12 cells of 8×16 = 240 codes covers 160×192 pixels with a unique code per cell: a true bitmap (Super Expander / MINIGRAFIK). It needs 3,840 bytes of character data plus a 240-byte screen, which nearly fills `$1000-$1fff`, so **no double buffering**.
  - For ISO64 it would remove the 112-code budget and the hash, but double buffering would go and the 16-line cells don't match the tile grid's 8-line rows. Not recommended. M
- **Larger screen:** set the column and row counts (`$9002` / `$9003`) and centre with `$9000` / `$9001`. PAL shows up to about 26–28 columns × 30+ rows within the visible area.
  - A wider viewport (e.g. 24 columns) costs more cells per frame. The 112-code budget is the limit, not RAM. M
- **Coarse hardware scroll:** moving `$9000` / `$9001` shifts the *whole* picture (text too) in 4-pixel / 2-line units.
  - Possible use: a short "camera ease" at the end of a step (shift the new frame by ±1–2 units and slide it back over 2–3 frames). It needs border-coloured margins so the slide doesn't reveal garbage. M
- **Raster colour splits:**
  - Change `$900e` (aux colour) or `$900f` (screen/border) at chosen lines: polled, or with a VIA-timer IRQ synced once.
  - E.g. a different auxiliary colour for the text area (rows 18–22) than for the map, or a sky-colour band. It frees the map's palette choice from the UI's. M
- **Interlace** (`$9000` bit 7): flickers, no real gain. Skip.
- **Colour RAM:** 4 bits per cell, two halves for double buffering (in use).
- **Character ROM tricks:** text glyphs can come from ROM (`$8000`) while the map characters come from RAM, by raster-splitting `$9005` for the UI rows. That frees codes 224–255 (ISO64's text range) for map patterns, raising the budget to **144 codes per frame** for ~0 cycles. M; VICE can verify.

## 4. CPU techniques (VIC-20 specifics)

- **Same NMOS 6502:** stable illegal opcodes work (LAX/SAX/DCP/SBX…).
- **Exact cycle counts** (no VIC stealing), so unrolled and self-modifying code pay off predictably.
- The PLATFORMS.md §6 profile puts **`draw_tile` at ~35%**, emit at ~25% and scroll copy at ~11%. The C64 inner-loop options (self-modifying absolute operands, skipping covered cells) apply here too.
- ZP: shared `$02-$5f` plus the platform's `$60-$8f`. Code is tight: **about 26 bytes left below `CLS_A` (`$34e8`)**, so any new code needs a memory-map change.

## 5. Big-RAM expansions: UltiMem and Final Expansion 3

These make a "VIC-20 + big RAM" flavor possible: pre-render the composed world, as the C64's REU tier does, but with CPU copies.

**UltiMem** (Retro Innovations; 512 KB–1 MB RAM + 8 MB flash) (M):

| Addr | Register |
|---|---|
| `$9ff0` | Control: bit 0 LED, bits 1–2 switches (read), bit 6 soft reset keeping registers, bit 7 hide registers |
| `$9ff1` / `$9ff2` | Per-area modes, 2 bits each (off / ROM / RAM read-only / RAM read-write) for RAM123, IO, BLK1, BLK2, BLK3, BLK5 |
| `$9ff3` | ID: low nibble 1 = UltiMem, high nibble manufacturer |
| `$9ff4/5` | RAM123 bank |
| `$9ff6/7` | IO bank |
| `$9ff8/9`, `$9ffa/b`, `$9ffc/d`, `$9ffe/f` | **16-bit bank numbers for BLK1, BLK2, BLK3, BLK5** (8 KB granules) |

**Final Expansion 3** (512 KB RAM + 512 KB flash + SD) (H, MAME source):

| Addr | Register |
|---|---|
| `$9c02` (REG1) | Bits 7–5 mode: `$00` START, `$20` FLASH, `$40` SUPER_ROM, `$60` RAM_ROM, `$80` RAM_1, **`$a0` SUPER_RAM**, `$c0` RAM_2. Bits 0–3 bank (16 × 32 KB). In RAM_1/RAM_2 modes, bits 0–4 choose an alternate bank per block |
| `$9c03` (REG2) | Bits 0–4 hide BLK0/1/2/3/5; bits 5–6 swap address lines A13/A14 within the bank; bit 7 hides the registers |

In SUPER_RAM mode, BLK1–3 + BLK5 map 32 KB bank N (`bank << 15 | block << 13`).

**ISO64 use:**
- The VIC-20 world image follows the same formula as the C64's. With a 22×18 viewport and the 4×2-cell tile grid, it is about **146 × 80 compose cells × 8 bytes ≈ 93 KB, plus ~12 KB of cell colours**.
- That fits in either cartridge. A step would copy the 22×18 window (3,168 pattern bytes + 396 colours) from banked RAM at ~9 cycles per byte, ≈ **30k cycles**, replacing `draw_tile` and the scroll copy (~46% of a 229k step, ≈ 105k).
- **Estimate: a step of ~155k cycles (−30%).** Emit still costs its ~25%, and its labels would need to be stored in the world image or recomputed. M (estimate)
- VICE: `-cartfe <image>` for FE3 (needs the FE3 ROM image) and the UltiMem cartridge option. 🔧 Real cartridges for final confirmation.

## 6. Sound

- 3 square-wave voices (bass, alto, soprano: one octave apart), noise, and a 4-bit master volume.
- **Digis** via the volume nibble of `$900e`. Every write must keep the auxiliary colour in bits 4–7, or the screen flickers. M
- A simple music player costs ~1–2k cycles per frame. ISO64's VIC-20 engine keeps IRQs on (KERNAL `GETIN`), so an IRQ player wedge is possible; it needs a fixed VIA-timer rate.

## 7. Loading

- KERNAL `LOAD` from sd2iec or a 1541, with lowercase names and wildcards (`VTILES*`, `VSPRITES*`, `MAP01*`), as on the C64. H (project-verified)
- The FE3 has its own SD loader menu; the UltiMem has flash. Either could hold the data files.
- JiffyDOS-for-VIC ROMs speed up `LOAD` about 5×, transparently.

## 8. Hardware checklist

- [ ] UltiMem register behaviour, compared with the go4retro summary (defaults, bank numbering).
- [ ] FE3 SUPER_RAM mode on a real cartridge, compared with MAME/VICE.
- [ ] Character ROM for text via a `$9005` raster split: exact switch line, no tearing on real PAL VIC.
