# PETSCII cheat-sheet

The sources, the games survey and the tools are in `docs/research/petscii.md`. The codes below were measured from VICE's `C64/chargen-901225-01.bin` with `docs/research/vice-tests/petscii-glyphs.js` [H].

## Basics

- **Machines:** PETSCII is in the ROM of the PET, VIC-20, C64, C16/Plus/4, C128 (40-col; the VDC loads it into its RAM) and CBM-II.
- **Screen RAM holds screen codes,** not PETSCII codes: 0–127 are the glyphs, and +128 is the same glyph reversed.
- **Two sets:** uppercase + graphics (the one used here) and lowercase + uppercase. Switch on the C64 with `$d018` bit 1; in BASIC with CHR$(14) / CHR$(142).
- **Colour:** one foreground colour per character (colour RAM, or the VDC attribute, or TED colour + luminance) on a global background.
  - The PET has no colour.
  - Don't use multicolour character mode with ROM glyphs: it doubles the pixel width.
  - ECM only allows codes 0–63, which excludes the block glyphs.

## Quarter blocks: an exact 2× semigraphics mode

Screen codes, with bits UL=8, UR=4, LL=2, LR=1:

| Bits | Code | Bits | Code | Bits | Code | Bits | Code |
|---|---|---|---|---|---|---|---|
| 0 | `$20` | 4 UR | `$7c` | 8 UL | `$7e` | 12 top | `$e2` |
| 1 LR | `$6c` | 5 right | `$e1` | 9 UL+LR | `$7f` | 13 ¬LL | `$fb` |
| 2 LL | `$7b` | 6 UR+LL | `$ff` | 10 left | `$61` | 14 ¬LR | `$ec` |
| 3 bottom | `$62` | 7 ¬UL | `$fe` | 11 ¬UR | `$fc` | 15 full | `$a0` |

That's a 16-byte lookup table: `semi_to_code`. The resulting resolution per screen:

| Screen | Semigraphics |
|---|---|
| C64 40×25 | 80×50 |
| VIC-20 22×23 | 44×46 |
| C128 VDC 80×25 | 160×50 |
| PET 80-col | 160×50 |

**Other glyphs:**
- Triangles: ◤ `$69`, ◥ `$5f`, ◢ `$e9`, ◣ `$df`. The reversed pair differs on the diagonal line.
- Eighth-steps (bars) from the bottom: 1/8 `$64`, 2/8 `$6f`, 3/8 `$79`, 4/8 `$62`, 5/8 `$f8`, 6/8 `$f7`, 7/8 `$e3`.
- There are **no 2:1 diagonals.**

## The ISO64 diamond in PETSCII

At semigraphics resolution, the ISO64 2:1 floor diamond is **8×4 quarter-pixels = 4×2 characters**, the same cell grid as every other flavor. The quarter-pixel rows cover x 3–4, 1–6, 1–6, 3–4:

```
row 0:  $6c $fe $fc $7b      ▗▟▙▖
row 1:  $7c $fb $ec $7e      ▝▜▛▘
```

Verified: at ISO64's tile offsets of (2 cells, 1 row), the diamonds tile the plane with no overlaps and no holes. A height level is 1 character row, as everywhere else.

**Composing a frame:**
1. Keep the frame as a quarter-pixel buffer, one nibble per character. Store a colour per character beside it.
2. Draw tiles back to front by OR-ing each tile's quarter masks, under the same painter's order as `common/view.s`.
3. A tile that sets any quarter in a character also sets that character's colour; the last writer wins. This is the same rule as the VIC-20's per-cell colour, so the editor's clash counter applies.
4. Convert each nibble through `semi_to_code` into screen RAM.

**Costs:**
- A full C64 screen redraw with unrolled code is about 16–20k cycles: one PAL frame.
- No character-set memory is needed, and tile art is just 4-bit masks plus colours.

**When this flavor makes sense:**
- the PET (no custom character set possible);
- the unexpanded VIC-20;
- a "fast mode" on any machine;
- an authentic PETSCII look as a deliberate style.

Every flavor still needs its own editor preview (the project rule).

## PETSCII for UI on every flavor

Panels, combat log, menus and the title screen can all use ROM glyphs: box drawing, reverse-video bars, and the eighth-step bars for HP and XP meters. The C128 VDC branch already draws its side panel this way.

On the bitmap C64, either:
- raster-split to character mode under the viewport (OPPORTUNITIES UI-1); or
- blit the 8 bytes of each glyph from the character ROM into the bitmap. Read the ROM via `$01` = `$33` with interrupts off.

## Tools

| Tool | Use |
|---|---|
| **Petmate** / **petmate9** | petmate9 covers C64, C128 and VDC, VIC-20, PET and Plus/4. It converts images to PETSCII and talks to an Ultimate 64. Its files are `.petmate` JSON, so stamps can be imported into the ISO64 editor |
| **ventti/petscii** | A headless CLI with plugins, for build pipelines |
| **Playscii** | A general character-art tool and engine with Commodore sets |

## Lessons from shipped games

**Attack of the PETSCII Robots:**
- one design shipped on the PET, VIC-20 and C64, with one map file for all three;
- 3×3-character tiles;
- a 64-slot unit table: robots, weapons fire, doors, hidden items;
- its portable port split the logic behind a platform interface, the same structure as ISO64.

**Others:**
- **PETSCII Bros:** an action game on the 80×50 quarter-block display.
- **Delve! The Goblin's Grotto:** a C64 PETSCII dungeon crawler.
- **PETSCII Dungeons & Droids:** C64, Plus/4 and PET from one game.
