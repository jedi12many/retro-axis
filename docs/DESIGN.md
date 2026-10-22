# ISO64: C64 isometric RPG engine design

A solo, turn-based isometric RPG engine for a stock C64 (PAL). Content is made in a browser editor on a PC and copied to an SD card as `.PRG` files. Kung Fu Flash 2 and sd2iec handle storage. Load times are treated as free, so the world is split into many small map files instead of being streamed.

## Layout

```
editor/index.html     Browser editor: tiles, maps, entities, C64-accurate preview, PRG export
editor/vic20.js       VIC-20 model: tile conversion, preview, export
engine/common/        Shared 6502 code: zp.inc, defs.inc, game.s (rules), view.s (visibility)
engine/c64/           C64 platform layer. build.cmd assembles it, run-vice.cmd runs it
engine/vic20/         VIC-20 platform layer (docs/PLATFORMS.md section 6)
test/engine-test.js   Runs the C64 engine on a 6502 core and diffs its screen against the editor
test/vic20-test.js    Same for the VIC-20 engine
test/profile.js       Cycle profile of one C64 step, per routine
build/<platform>/     engine.prg + data files, ready for the SD card
```

This document describes the C64 engine and the shared design. The other machines are covered in [PLATFORMS.md](PLATFORMS.md).

## Graphics model

- **Mode:** multicolor bitmap, 160×200 double-wide pixels. Each 4×8 cell has 4 colors: `00` = global background (`$d021`), `01` = screen RAM high nibble, `10` = screen RAM low nibble, `11` = color RAM.
- **Tile grid:** a floor diamond is 16×16 multicolor pixels (32×16 on screen, 2:1 isometric). That is 4 cells wide and 2 cells tall.
- **Why it's fast:** neighbouring tiles are offset by exactly 2 cell columns and 1 cell row, and one height level is 8 pixels (1 cell row). Every tile edge falls on a cell boundary, so the blitter only copies or masks whole bytes and never shifts bits.
- **Tiles are bottom-aligned:** the last two cell rows are the floor footprint. Taller tiles (walls, trees, towers) extend upwards, 1–8 cell rows in total.
- **Raised terrain:** a cell at height *h* draws the map's *slab* tile *h* times (one cliff layer per level) and then the terrain top. By convention the slab sides use only color `11` + background, and every terrain tile uses the same `11` color (brown by default). That way cliffs never clash with what sits on top of them.
- **Slab top faces:** the top face of a slab is always covered by the level above. The default slab therefore leaves it transparent, and the engine never draws that cell row.
- **Cell types**, which control color clash per cell:
  - 0 empty
  - 1 opaque (plain copy)
  - 2 masked, writes its colors
  - 3 masked, keeps the colors underneath
  The editor picks 2 or 3 automatically (2 when ≥50% of the cell is opaque), and you can override it per cell.
- **Draw order:** row-major over the map (y outer, x inner) is correct back-to-front order for this projection.
- **Which map cells are drawn:** exactly those whose tiles can touch the viewport. With dx, dy relative to the player: dx−dy in −6…6 and dx+dy in −8…19 (the row range allows for 8-row tiles on height 3). The editor preview uses the same rule.
- **Characters:** hardware sprites, multicolor. `$d025` is the black outline, `$d026` is skin, and each entity has its own sprite color. Sprite 0 is the hero; sprites 1–7 are the visible entities.

### Screen layout (cells)

| Area | Columns | Rows |
|---|---|---|
| Viewport | 8–31 | 1–18 |
| Free for UI (party/inventory panels as in the reference, icon bar below) | 0–7, 32–39 | 19–24 |

The player's tile is always drawn at column 18, row 8 (minus its height). The camera re-centres on every step.

Projection, for a map cell (x, y) seen from the player (px, py):

```
col = 18 + 2*((x-px) - (y-py))
row =  8 +    (x-px) + (y-py)  - height
```

## Rendering: double buffer + scroll

Two complete frames exist, one per VIC bank, and both use `$d018 = $08` (screen at +$0000, bitmap at +$2000). Flipping is a single write to `$dd00`.

1. **First frame** (map load): every viewport cell is drawn into the hidden buffer.
2. **Each step** moves the view by whole cells: (±4, 0) or (0, ±2) for the straight keys, and (±2, ±1) for the diagonal keys.
   - `scroll_copy` copies the shown frame into the hidden one, shifted: bitmap, screen RAM, and colour RAM into a colour shadow. It uses three 18-row copy routines whose addresses are patched per step, so each loop pass copies the same byte of every row.
   - The exposed strip (2–4 columns and/or 1–2 rows) is cleared. Only the map cells whose tiles can touch it are drawn, clipped by per-column and per-row dirty masks (`COLM`/`ROWM`).
   - Because every viewport cell of the previous frame already held the exact composition of the tiles covering it, the result is identical to a full redraw. The test proves this for every frame.
3. **`flip`** waits for raster line 210, just below the viewport. It switches the bank, then copies the colour shadow into `$d800` before the beam gets back to the top of the viewport, so there's no tearing.
4. Blocked moves don't redraw anything, and bumps only update sprites.

While drawing, IRQs are off and the KERNAL is switched out (`$01=$35`), so buffer B under `$e000` reads back as RAM. `flip` restores `$01=$36` and turns IRQs back on for keyboard scanning. The NMI vector at `$fffa` points to an `rti`.

Any UI drawn outside the viewport (panels, icon bar) must be written into both buffers, because only the viewport is copied between them.

## Memory map

| Range | Use |
|---|---|
| `$0801-$3dff` | engine code (≈3.6 KB so far) |
| `$3e00-$3fff` | `COLM` / `ROWM` dirty masks (256 bytes each) |
| `$4000-$43ff` | screen A (VIC bank 1), sprite pointers at `$43f8` |
| `$4400-$47ff` | sprite shapes (`SPRITES`), 16 slots, pointer value `$10` |
| `$4800-$4bff` | free |
| `$4c00-$59ff` | current map (`MAPxx`) |
| `$5a00-$5fff` | free (combat state, scripts) |
| `$6000-$7f3f` | bitmap A |
| `$8000-$bfff` | tileset (`TILES`), 16 KB, BASIC ROM switched out |
| `$c000-$c3ff` | screen B (VIC bank 3) |
| `$c400-$c7ff` | copy of the sprite shapes for bank 3 (same pointer values) |
| `$c800-$cbe7` | colour shadow: the colour RAM image of the frame being drawn |
| `$cc00-$cfff` | free |
| `$e000-$ff3f` | bitmap B, in RAM under the KERNAL |

## File formats

All files are standard PRGs (2-byte load address first), saved with lowercase host names (`tiles.prg`). The engine asks for `TILES*`, which matches both sd2iec (extension hidden) and VICE's folder device (extension shown).

### TILES → `$8000`

```
+0          n            tile count (ids 1..n, max 127)
+1          ptr[0..n]    little-endian absolute addresses; ptr[0] unused
records:    h            height in cell rows (1-8)
            flags        bit0 = blocks movement
            cellptr[h*4] absolute address of each cell, row-major; 0 = empty cell
            cell data, each:
              type        1 opaque | 2 masked+colors | 3 masked keep colors
              scr byte (c01<<4 | c10), colram byte (c11), 8 bitmap bytes
              (type 2/3)  8 mask bytes (1-bits keep the pixel underneath)
```

The pointer table lets the blitter jump straight to the cells that are on screen and dirty, without decoding the ones before them.

### MAPxx → `$4c00` (`$e00` bytes, fixed 32×32)

| Offset | Content |
|---|---|
| `$000` | `"IM"`, version 1, width 32 |
| `$004` | start x, start y, entity count, background, border, slab tile id, hero color |
| `$010` | name, 16 bytes |
| `$100` | terrain ids, 1024 bytes (0 = void, not walkable) |
| `$500` | height bytes: bits 0-1 height 0-3, bit 7 blocked |
| `$900` | object ids, 1024 bytes (0 = none) |
| `$d00` | 32 entities × 8 bytes: type, x, y, sprite, color, hp, atk, def |

Entity types: 1 monster, 2 NPC, 3 item, 4 trigger (invisible, walk-through).

### SPRITES → `$4400`

64 bytes per shape, standard multicolor sprite data. The editor ships 4 shapes: hero, goblin, robed NPC, potion. The engine copies them to `$c400` for bank 3.

## Movement rules (implemented)

- Keyboard, one step per key press (read with KERNAL `GETIN`, so it works on a real C64 and in VICE):
  - `W`/`S`/`A`/`D` or the cursor keys move straight up, down, left or right on screen (two map axes at once).
  - `Q`/`E`/`Z`/`C` move diagonally on screen, along one map axis.
  - Keys that pile up during a redraw are dropped, so holding a key doesn't overshoot.
- Joystick port 2, one step per push.
  - Up = y-1, down = y+1, left = x-1, right = x+1. Each moves diagonally on screen.
  - Diagonals combine two of these, giving straight up/down/left/right on screen.
- **Blocked:** void terrain, height-byte bit 7, a terrain or object tile with flag bit 0, or a climb of more than one level.
- **Bumping an entity:** a monster loses 1 hp per bump and disappears at 0; an item is picked up; an NPC just blocks. This is a placeholder for the combat system below.

## Measured performance

These numbers come from `test/engine-test.js`, which runs the real `engine.prg` and counts 6502 cycles, page-cross penalties included. A step is timed from the key press until the new frame is on screen; PAL runs at 985 kHz.

| | Before | Now |
|---|---|---|
| Step, average | 746k cycles (≈760 ms) | ≈170k cycles (≈170 ms) |
| Straight up / down | — | 137–157k (140–160 ms) |
| Straight left/right, diagonals | — | 157–177k (160–180 ms) |
| Worst step in the test (plateau, both strips) | 885k | 216k (220 ms) |
| Blocked move | full redraw | 1.5k |
| Drawing visible on screen | yes | no (double buffered) |
| First frame after loading a map | — | 726k (≈0.74 s, once) |

Totals snap to whole frames (19,656 cycles), because the flip waits for raster line 210.

Where a step's time goes now (`node test/profile.js upright`):
- **≈57%** drawing tile cells into the strip. Each screen cell sits under 2–4 overlapping tile cells: 2 for flat ground, more for slabs and objects.
- **≈14%** the shifted bitmap copy.
- **≈10%** the flip, mostly waiting for the raster.

Further options, roughly in order of payoff:
1. **Skip the bitmap copy for rows that are cleared anyway.** These are the 1–2 dirty rows on diagonal moves.
2. **Coverage tracking.** Skip a tile cell when a later fully opaque cell will overwrite it. This mostly helps walls and buildings.
3. **Self-modifying absolute addressing in the mask loop.** About 17 instead of 23 cycles per byte.
4. **Draw the strip during the raster wait**, or flip from a raster IRQ so the CPU can start reading input sooner.

## VIC-20 target (preview stage)

Target hardware: a PAL VIC-20 with 32 KB RAM expansion. The map format has no machine-specific data in it, so a VIC-20 engine can read the same `mapxx.prg` files. Only the tile graphics differ. `editor/vic20.js` models how a character-mode VIC-20 engine would draw a map.

- **Screen:** 22×23 characters on PAL. The viewport is columns 0–21 and rows 0–17, leaving rows 18–22 for text. The player's tile is drawn at column 9, row 7. Placement, draw order and the "can touch the viewport" rule are the same as on the C64.
- **Characters:** a custom set of 8×8 multicolour characters. Pixel values: `00` screen colour, `01` border colour (0–7), `10` the cell's own colour (colour RAM, 0–7), `11` auxiliary colour.
- **Tiles:** converted from the C64 tiles. The C64's three per-cell colours collapse to the VIC-20's 3 shared colours plus 1 per cell. For each cell, the converter picks the cell colour that minimises the colour error, using a perceptual "redmean" distance, and maps each C64 pixel value to the nearest of the four.
- **Hand-edited tiles:** a tile can carry a hand-edited VIC-20 version (`tile.vic` in the project file): one VIC-20 pixel value per pixel, plus a cell colour and owner setting per cell. It shares the C64 tile's height and blocking flag. Height changes are applied to both versions, bottom-aligned. Once a tile is hand-edited, changes to its C64 version no longer carry over; **Reset to automatic** drops the hand edits.
- **Shared colours:** chosen per map by testing every screen/border/auxiliary combination (16×8×16) against the tiles the map uses, weighted by how often each tile appears.
- **Figures:** there are no hardware sprites, so the hero and entities are composited into the characters. Outline pixels use the screen colour, body pixels the cell colour, and skin pixels the border colour. Cells touched by a figure take its colour.
- **Character budget:** every distinct 8×8 pattern on screen needs its own character, so the engine would build the character set per frame. The preview counts the patterns against 224, keeping 32 characters for text. The default map needs about 90.
- **Memory:** the VIC chip can only read internal RAM, so the screen and character set must sit in the internal `$1000-$1fff` area. The engine, tiles and map would go in expansion RAM.

The engine is built. Its layout, tests and status are in [PLATFORMS.md](PLATFORMS.md) section 6.

## Roadmap

1. **Combat (turn-based).** Enter combat when a monster is adjacent or bumped. Turn order is player, then each awake monster. Actions: attack, item, move, flee. Monsters use simple chase/attack AI on the same grid. Damage = atk − def + d4. A text log goes in the bottom rows.
2. **UI layer.** A bitmap text renderer (2-colour font expanded to multicolor), side panels for inventory slots, a status bar (gold, HP, turn), and an icon bar like the reference. Panels are drawn into both buffers.
3. **Map links.** Trigger entities carry a target map number and an entry point. The engine LOADs `MAPxx` and keeps a small persistent state block (killed monsters, opened chests) per map in `$5a00`.
4. **Editor additions.** Sprite editor (exporting more shapes), trigger/script properties, map links, import of existing PNG tiles with colour reduction to 4-per-cell.
5. **Storage.** Optionally build an EasyFlash `.crt` from all PRGs for Kung Fu Flash 2, which gives instant loads.
