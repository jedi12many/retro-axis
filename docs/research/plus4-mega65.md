# Future flavors: Plus/4 / C16 (TED) and MEGA65

These are short notes for planning. Neither machine is being built yet. Confidence marks are as in [c64.md](c64.md).

## Commodore Plus/4 and C16 (TED 7360/8360)

**References:**
- https://www.c64-wiki.com/wiki/TED
- Plus/4 World: https://plus4world.powweb.com/
- VICE `xplus4` manual section

**Hardware:**

| Item | Facts | Conf. |
|---|---|---|
| CPU | 7501/8501 (6502-compatible), **1.77 MHz PAL / 1.79 MHz NTSC in "double clock"** while TED isn't fetching (borders, or the screen blanked through `$ff06` bit 4); single clock (~0.89 MHz) during display fetches. `$ff13` bit 1 forces single clock | M |
| RAM | Plus/4: 64 KB; C16/116: 16 KB (64 KB with expansion). ROM banked by writes to `$ff3e` (ROM on) and `$ff3f` (RAM on) | H |
| Colours | **121**: 16 hues × 8 luminances (black has no luminance steps) | H |
| Modes | 40×25 text, multicolour text, extended colour, **320×200 hires bitmap, 160×200 multicolour bitmap** | H |
| Multicolour bitmap colours | Per 4×8 cell: `00` = background `$ff15`, `11` = `$ff16`, `01`/`10` from the cell's attribute and video-matrix bytes. **2 per-cell + 2 global** (the C64 has 3 per-cell + 1 global) | M |
| Sprites | **None.** Figures must be soft sprites, like ISO64's VIC-20 renderer | H |
| Scrolling | Fine X/Y scroll (`$ff07` / `$ff06` bits 0–2), 38/24 modes, raster IRQ, hardware cursor | H |
| Memory for video | Video matrix + attributes (2 KB) and bitmap anywhere on 1 K / 8 K boundaries, so **double buffering is easy** (`$ff14` / `$ff12`); there is no fixed colour RAM | M |
| Sound | 2 voices (square, or noise on voice 2), 4-bit volume `$ff11` (digis possible) | H |
| Storage | 1541 or 1551 (parallel, fast). sd2iec works over the serial bus | M |

**ISO64 fit:**
- **The C64 bitmap renderer ports almost directly:** multicolour bitmap, cell-aligned tiles, double buffer. The differences:
  1. one fewer per-cell colour, so the editor's `plus4.js` converts tiles with 2 globals + 2 per cell;
  2. no sprites, so composite figures into the bitmap (a software masked blit per figure cell);
  3. no colour RAM copy at flip: both attribute planes switch with the base registers.
- **The faster CPU in the border** (~1.3–1.5× the C64 on average, M) helps the soft sprites.
- VICE `xplus4` can verify, and a 6502 harness works as-is (no special CPU).
- **Target the Plus/4 or a 64 KB C16. A stock 16 KB C16 is too small.**

## MEGA65

**References:**
- MEGA65 Book (complete compendium): https://files.mega65.org/manuals-upload/mega65-book.pdf
- Developer site: https://dev.mega65.org/

| Item | Facts | Conf. |
|---|---|---|
| CPU | **45GS02 at 40.5 MHz** (also 1, 2 and 3.5 MHz compatibility speeds). A 4510 superset with 32-bit "quad" instructions and flat 28-bit addressing via `[zp],z` | H |
| **Illegal opcodes** | **Not available in native mode.** The NMOS illegal opcode slots are 4510 instructions. A C64-mode core (MiSTer-derived "C64 core for MEGA65") exists separately and runs C64 software including illegals | H (native), M (core) |
| RAM | 384 KB chip RAM; 8 MB "attic" HyperRAM on most boards | H |
| Video (VIC-IV) | VIC-II/VIC-III compatible plus **Full-Colour Mode (FCM)**: 8×8 characters with one byte per pixel (64 bytes per char), 256-colour palette with 8-bit RGB. 80×50 / 40×25 text, 640×400 | H |
| **Raster Rewrite Buffer (RRB)** | Character rows can contain **GOTOX tokens**, placing following characters at any X and *overlaying* earlier ones: layered characters with transparency, used as "sprites" made of characters | H |
| Sprites | 8 VIC-II-style sprites, plus 16-colour / wider variants | H |
| DMA (F018B "DMAgic") | Copy, fill, swap, mix; DMA lists in memory; tens of MB/s | H (feature), M (speed) |
| Sound | 4 SIDs, plus digital audio DMA channels | H |
| Storage | SD card, internal FDC (1581 format), D81 images | H |

**ISO64 fit:**
- **A "native" engine, not a port.**
  - FCM tiles: 256 colours, so the C64 tile art upgrades with no colour clash.
  - RRB layering: each map cell's tile parts become overlaid character runs per row, and the hardware composites the back-to-front draw order.
  - Figures as RRB characters behind or in front of walls: **exact depth for free**.
- **DMAgic** replaces the REU walk: a smooth 50 fps scroll at 40 MHz is trivial.
- **What carries over:** maps, game rules (`engine/common`, assembled for 45GS02 with care: no illegals) and the editor model. The rendering is new.
- **Verification:** the 6502 harness would need a 45GS02 core. Xemu (https://github.com/lgblgblgb/xemu) is the reference emulator. VICE does not emulate the MEGA65.
- Priority: after the Commodore 8-bits are done. Very high visual ceiling, but a small user base.
