# ISO64 platform plan

**Goal:** one game, the same maps and editor, on every major retro platform. Each machine gets an engine that makes the most of its hardware. All of them read the same map files and play by the same rules.

This document is the spec for how that's organised. It also specifies two concrete targets: C64 capability tiers (stock, REU, Ultimate turbo) and the VIC-20.

## 0. Strategy (decided 2026-10-21)

Period games targeted the minimum configuration to reach the most buyers. ISO64 does the opposite.

- **Lead target:** the **C64 Ultimate / Ultimate 64**, fully loaded: REU (up to 16 MB), turbo CPU and two SIDs. New features are designed for it first.
- **Stock builds keep developing.** The stock C64 and the VIC-20 (24K or more) get each feature in whatever form their hardware allows. They are not frozen.
- **Rule:** design a feature for the Ultimate, then add the best version each smaller machine can manage, so every build stays fully playable.

| Feature | Stock C64 | C64 + REU | C64 Ultimate (REU + turbo + 2 SIDs) | VIC-20 |
|---|---|---|---|---|
| Walking | Cell steps, about 175 ms | **Smooth 50 fps scrolling** | Smooth scrolling | Cell steps |
| Figures behind walls and trees | Sprite priority per cell (approximate) | Same | **Exact software masking** | Exact (soft sprites are already composited) |
| Animated tiles (water, torches) | A few cells per step | Re-render cells into the REU world | Every frame | A few cells per step |
| Combat AI | Turn-based pathfinding, small radius | Same | Larger radius, line of sight, fog of war | Like stock |
| Music and effects | 1 SID | 1 SID | **2 SIDs, stereo** | VIC voices |
| World size | 32×32 maps, linked | Larger maps held in the REU | Larger maps | 32×32 maps |

**Work order for the lead target:**
1. **Smooth scrolling** on the REU tier. Every REU owner benefits, and it's verifiable in VICE.
2. **Figure depth:** figures drawn behind walls, trees and buildings.
3. **Turbo detection and use.** It needs real hardware or Ultimate documentation for the control register; VICE can't emulate it.
4. **Dual-SID music player.**
5. **Animated tiles.**
6. **Larger maps** (map format v2).

## 1. Architecture

```
editor/            one editor for all machines
  index.html         maps, entities, C64 tiles (the master art)
  vic20.js           VIC-20 model: tile conversion, preview, export
  <platform>.js      one module per further platform, same shape
engine/
  common/            6502 code shared by every 6502 machine
    zp.inc             zero-page layout
    game.s             map access, movement, blocking, bumping, key mapping
    view.s             isometric visibility: which map cells touch the screen,
                       dirty strips for scrolling, back-to-front draw order
  c64/               C64 platform layer (bitmap, double buffer, sprites)
  vic20/             VIC-20 platform layer (dynamic character set, soft sprites)
  <platform>/        one folder per machine
test/              6502 emulator + per-platform harnesses that diff each engine's
                   screen against the editor's preview, frame by frame
build/<platform>/  ready-to-copy files for each machine
```

### What is shared, and what isn't

| Layer | Shared? | Notes |
|---|---|---|
| Map format (`mapxx.prg`) | Shared by every platform | Terrain, heights, objects, entities and start position. The header also holds per-platform colour choices (§3). |
| Game rules | Shared source per CPU family | Movement, blocking, bumping, and later combat, AI and map links. 6502 machines `.include` `engine/common`. |
| Visibility / draw order | Shared per CPU family | The same projection maths. Each platform supplies its viewport size and centre. |
| Tile art | Per platform, derived from the C64 master | Each platform module converts the C64 tiles automatically. Any tile can be hand-edited per platform, as the VIC-20 version already can. |
| Rendering, input, sound, loading | Per platform | The platform layer. |

### The platform layer contract (6502)

Each platform folder provides these routines and constants, and the common code calls them:

| Provides | Purpose |
|---|---|
| `VP_C0 VP_C1 VP_R0 VP_R1` | Viewport bounds, in character cells. |
| `CENTER_COL CENTER_ROW` | Where the player's tile is drawn. |
| `COLM`, `ROWM` | 256-byte dirty-mask tables. |
| `draw_tile` | Draws one tile, clipped by the masks, into the hidden frame. |
| `plat_flash` | Hit feedback (border flash or equivalent). |
| main loop: load, init, `render_full`, `render_scroll`, `flip`, sprites, input | Glue that calls `view_full` / `view_scroll` / `draw_all` and `try_move`. |

### Verification rule

Every platform engine gets a harness that runs the real binary on the 6502 core (or a Z80 core later) and compares its screen memory with the editor's preview for that platform, after every scripted move. A platform counts as done only when this passes and a real-emulator run (VICE, Altirra, MAME, …) looks right.

## 2. Platform roadmap

Ordered by how much code carries over, and by how well the hardware suits this kind of game.

| # | Platform | CPU | Display approach | Reuse | Status |
|---|---|---|---|---|---|
| 1 | **C64** | 6502 | Multicolor bitmap, double buffer, scroll copy, hardware sprites | — | Working |
| 2 | **VIC-20** (PAL, +32K) | 6502 | Custom multicolour characters rebuilt per frame, soft sprites | common/ | Working (v1) |
| 3 | **C64 + REU / Ultimate** (lead target, §0) | 6502 | Same as C64 plus a pre-rendered world in REU (§4) | c64/ | REU tier working; smooth scrolling next |
| 4 | Commodore Plus/4, C16 (+64K) | 6502 (7501) | 121-colour TED; character mode or bitmap | common/, VIC-20 character renderer | Planned |
| 5 | C128 | 8502 | Runs the C64 build; optional 2 MHz in the border | c64/ | Free via C64 mode |
| 6 | Atari 400/800/XL/XE | 6502 | ANTIC character modes with display-list scrolling, player/missile sprites | common/ | Planned |
| 7 | BBC Micro / Master | 6502 | Mode 1/2 bitmap; tiles drawn with a shifted blitter | common/ | Planned |
| 8 | Apple II | 6502 | Hi-res, 7-pixel bytes with colour artefacts, so the art needs its own conversion | common/ | Planned |
| 9 | NES | 6502 (2A03) | Background tiles + sprites via cartridge, CHR-RAM for composed cells | common/ (minus KERNAL) | Planned |
| 10 | ZX Spectrum, Amstrad CPC, MSX | Z80 | Attribute or bitmap modes | Rules ported to Z80 (§5) | Later |
| 11 | Amiga, Atari ST | 68000 | Bitplanes; full-frame redraw is cheap | Rules ported (§5) | Later |

### Per-platform editor module

Each `editor/<platform>.js` follows the VIC-20 module's shape:
1. **Hardware model:** screen size, cell size, colour rules, palette.
2. **Auto-conversion** of C64 tiles, with per-tile hand edits stored as `tile.<platform>` in the project.
3. **Preview renderer** using the same placement and draw order, plus feasibility counters (characters used, colour clash, memory).
4. **Exporter** for that platform's tile file. Maps stay shared.

## 3. Shared map header (v1, `$e00` bytes)

The engine-neutral fields are unchanged. Free header bytes carry per-platform settings:

| Offset | Field |
|---|---|
| `$00-$0a` | (unchanged) magic, version, size, start, entity count, C64 background and border, slab tile, hero colour |
| `$0b` | VIC-20 screen colour (0–15) |
| `$0c` | VIC-20 border colour (0–7) |
| `$0d` | VIC-20 auxiliary colour (0–15) |
| `$0e-$0f` | reserved for the next platform |
| `$10-$1f` | name |

If more platforms need settings than fit here, version 2 adds a tagged extension block after `$e00`, which older engines ignore.

## 4. C64 capability tiers (spec)

At startup the C64 engine detects what hardware is present and picks a tier. Every tier draws exactly the same picture; only speed and smoothness differ.

| Tier | Detected by | What changes |
|---|---|---|
| Stock | default | Current engine: double buffer, scroll copy + strip redraw. About 175k cycles (≈175 ms) per step. |
| REU (Ultimate, Ultimate II+, 1700/1764/1750) | `reu_detect` writes two patterns to the REU address registers at `$df02-$df05` and reads them back; a stock C64 reads open bus there. **Implemented.** | World pre-render + DMA viewport fetch (below). About 20k cycles per step. |
| Turbo (C64 Ultimate / Ultimate 64) | Ultimate identification; turbo control register (address to confirm on real hardware). | Turbo only while drawing, with stock speed for raster-timed code. Enables smooth walking and animation. |

### REU tier: pre-rendered world

The map's tiles never change while you walk around. The hero and monsters are sprites, and they aren't part of the bitmap. So the whole map can be drawn once into REU memory and the screen just becomes a window into it.

This tier is implemented in `engine/c64/main.s` (the "REU tier" block). Without an REU the engine takes exactly the stock path.

- **World image.** The image is the set of every viewport window the camera can show, not just the map's own extent. Screen cell (c, r) seen from camera (px, py) is world column `c − 8 + 2(px−py) + 62`, world row `r + px + py`. Over px, py = 0…31 that gives **148 columns × 82 rows**. The map art itself only needs about 128 × 72, as estimated before. The padding means a step never has to clip or clear: every window is a plain rectangle inside the image.

  | REU address | Contents | Size |
  |---|---|---|
  | `$00000` | bitmap, 82 rows × 1184 bytes (148 cells × 8) | 97,088 |
  | `$18000` | screen colours, 82 × 148 | 12,136 |
  | `$1c000` | colour RAM, 82 × 148 | 12,136 |

  That's 121,360 bytes in all, so any REU of 128 KB or more is enough, including the 1700. The engine assumes at least 128 KB and does not probe the size.
- **Building it: on the C64, at map load (chosen).** `world_build` tiles the image with 7 × 5 viewport-sized windows: world columns 0, 24, …, 120, 124 and rows 0, 18, 36, 54, 64. For each window it puts the camera there, clears the back buffer and draws with the normal `draw_cell`/`draw_tile` code. It then stashes the 18 bitmap rows, 18 screen rows and 18 shadow-colour rows into the REU. The border colour counts the windows meanwhile.
  - **Why it's correct.** A clipped viewport render is exactly a window of the unclipped world. Each screen cell receives the same draw operations in the same back-to-front order, wherever the camera is. So a fetched window matches a direct render, and the harness checks this against the editor on every frame.
  - **The window cameras** often lie off the map (for example px = −16, py = 47). `draw_all` clamps its y range assuming a camera on the map, so the build uses its own small loop, `draw_world`. It applies the same k/s bounds over the whole 32 × 32 map.
  - **Why not an editor export:** the image is 121 KB. It won't fit in one C64 load, so it would have to be several files streamed through RAM and stashed. Over a stock serial bus that's minutes, against a few seconds of drawing. Building on the C64 also needs no new file format, keeps working with any map the engine can load, and is the same code path that will re-render changed tiles later (doors, walls).
  - **Cost:** about 5.5M cycles, roughly 5.6 s PAL once per map (boot 6.19M cycles against 0.73M stock).
- **One step.** `reu_view` does 18 bitmap DMA fetches of 192 bytes and 18 screen fetches of 24 bytes into the hidden buffer. This replaces `scroll_copy`, `clear_dirty` and the strip redraw. `flip` still switches VIC banks at raster line 210, then fetches the 18 colour rows straight into `$d800`. That replaces the shadow copy, so `SHADOW` is only used during the build. The registers use autoload (command `$b1` fetch / `$b0` stash), so only the two addresses and the command are rewritten per row.
- **Measured** (`node test/engine-test.js`, same 41 moves in both tiers, from key press to back in `main_loop`):

  | | Stock | REU |
  |---|---|---|
  | Average step | 174,461 cycles | 19,610 cycles |
  | Range | 137k–216k | 14.7k–27.6k |
  | Boot to first frame | 0.73M | 6.19M (includes the world build) |

  - **The REU step** is about 8k cycles of real work. Profile of one step (`ISO64_REU=1 node test/profile.js right`): `reu_bmp` 4,838 cycles and `reu_chr` 2 × 1,603 cycles, i.e. 4,320 DMA bytes plus register setup. The rest is input, sprites and mostly waiting for the flip raster line, which is up to one frame.
  - **Speed-up:** about 9× per step overall, and about 20× for the drawing itself.
- **Smooth scrolling (not done yet).** A whole viewport refresh costs about 8k cycles, well inside one PAL frame (19.7k). So pixel scrolling at 50 fps with `$d016`/`$d011` fine scroll plus a DMA refresh every 4 pixels (8 rows vertically) is feasible at stock 1 MHz. It needs per-frame sprite repositioning and masking of the viewport edges that the fine scroll exposes. It was left for a later round.
- **Map changes** such as an opened door or a destroyed wall re-render just the affected tiles into the REU image. This is not needed yet, since nothing in the game changes tiles. When it is, it can reuse `world_build`'s window render for the windows that contain the changed cell.
- **Testing.**
  - **Harness.** `test/engine-test.js` runs the whole move script twice: on a stock C64, where `$de00-$dfff` reads as open bus, and with a 512 KB REU model. The model has registers `$df00-$df0a`, stash/fetch/swap/verify, autoload, address-fixing in `$df0a`, and 1 cycle per byte with the CPU halted. Every frame of both runs must match the editor preview. `ISO64_REU=0|1` runs one tier only, also for `ISO64_KEYS` and `test/profile.js`.
  - **VICE.** `x64sc -reu -reusize 512 -drive8type 0 -busdevice8 -fs8 build/c64 …` (add `-reu -reusize 512` to `engine/c64/run-vice.cmd`). The build shows as the border cycling colours over a black screen before the first frame. After the same keys, stock and REU screenshots were pixel-identical, and the REU frame matches the harness/editor frame.

### Turbo tier: what the extra speed is for

1. **Correct figure depth.** Composite the hero and monsters as software sprites behind walls and trees, or mask hardware sprites with per-cell priority.
2. **Animated tiles,** such as water and torches.
3. **Smarter monsters:** pathfinding, line of sight and fog of war for combat.

Turbo can't be emulated in VICE, so it needs checking on real hardware.

## 5. Beyond the 6502

The rules layer is small today: movement, blocking and bumping. Combat, AI and scripts will grow it. Two options:

- **Hand-port per CPU family.** One Z80 rules file and one 68000 rules file, each mirroring `common/game.s`. Fastest code, more maintenance.
- **Write the rules once in C,** with cc65 for 6502, z88dk for Z80 and gcc for 68000, and keep only rendering in assembly. The rules aren't speed-critical in a turn-based game.

**Recommendation:** keep the rules in 6502 assembly while the 6502 family is being built out (C64, VIC-20, Plus/4, Atari, BBC, Apple II, NES). Decide on C versus hand-ports when the first Z80 machine starts. By then the rules will be big enough to judge.

## 6. VIC-20 engine v1 (this round)

**Target:** PAL VIC-20 with 32 KB expansion (blocks 1–3).

| CPU range | Use |
|---|---|
| `$1000-$11ff` | screen A, with colour RAM `$9400` |
| `$1200-$13ff` | screen B, with colour RAM `$9600` (flip = `$9002` bit 7) |
| `$1400-$1bff` | character set: codes 0–111 for frame A, 112–223 for frame B, 224–255 for text |
| `$1c00-$1eff` | `COLM`, `ROWM`, character hash table |
| `$1f00-$1fff` | `COL4` (per tile column: which of its 4 cell columns are on screen / dirty), hash of each character's pattern |
| `$1201` → `$2000` | BASIC `SYS` stub, padding, then engine code `$2000-$34e7` |
| `$34e8-$37ff` | per-cell labels of the two compose buffers (see Emit) |
| `$3800-$3c4f` | `vsprites.prg`: figures pre-shifted into 4×4 cell images, plus a C64→VIC colour table |
| `$3d00-$3fcf` | per-cell overlay table, overlay slot colours and cells |
| `$4000-$4dff` | map (the shared file, loaded relocated) |
| `$4e00-$4edf` | overlay slot cells (high bytes), depth-sorted figure list |
| `$4f00-$4fdf` | overlay slot addresses (built at start) |
| `$5000-$6beb` | two compose buffers (396 cells × 8 bytes) + their cell colours |
| `$6c00-$6f7f` | 112 overlay slots: enough for 7 figures on screen at once |
| `$6f80-$6ff3` | emit's label → code table, front buffer's label pointer |
| `$7000-$7fff` | VIC-20 tiles (`vtiles.prg`, 4 KB budget) |

**Rendering:**
1. The map is composed into an off-screen cell buffer with the same scroll copy + strip redraw as the C64.
2. **Emit:** each viewport cell's 8 bytes, with soft sprites overlaid, is looked up in a hash table. Each new pattern gets the next character code in the hidden frame's half of the set, and the screen code and cell colour go to the hidden screen.
   - Each compose buffer keeps a **label** per cell: the code its pattern got the last time that buffer was emitted. Equal labels mean equal patterns, and the labels move with the scroll copy, so an unchanged cell costs one table lookup (label → this frame's code).
   - Only the first cell with each label, the redrawn strips and the cells under figures go through the hash. The first-label cells reuse the stored hash and the old character's bytes. Codes come out in the same order as a full rehash, so the screen codes are identical to v1's.
   - Figure cells without pixels are skipped. A new overlay slot is built in one pass (cell AND mask OR figure).
3. **Flip:** toggle `$9002` bit 7 when the raster is below the viewport. The screen, colour RAM and character half all switch at once, so there's no tearing.

**Budget:** 112 characters per frame. The editor preview counts this, and the default map needs about 90.

**Input:** keyboard via KERNAL `GETIN`, with the same keys as the C64, and the joystick with the C64's mapping (up = y−1, down = y+1, left = x−1, right = x+1; diagonals combine). Up/down/left are VIA1 `$9111` bits 2–4. Right is VIA2 `$9120` bit 7, which is also a keyboard column output, so `read_joy` turns that bit into an input in `$9122` for the read, with IRQs (the KERNAL keyboard scan) held off.

**Done when:** the harness frames match the editor's VIC-20 preview and `xvic` shows the same picture.

**Status: v1 done.**
- `node test/vic20-test.js` plays 40 key moves and 10 joystick moves, including scrolling in every direction, blocked moves and bumps. Every frame matches the editor exactly, cell by cell. The character use per frame (59–104) matches the editor's count too.
- `xvic` (PAL, `-memory 24k`) shows the same picture, and `engine/vic20/run-vice.cmd` starts it.
- **Timing:** a step costs 130–290k cycles (6–13 frames), about 0.12–0.26 s at the VIC-20's 1.1 MHz. Over the test's 35 moves and bumps, the average is 229k, down from 352k in v1 (−35%). The first frame costs about 0.67 s.
  - `node test/profile.js vic20 d` shows where a step goes.
  - The biggest remaining costs are `draw_tile` (~35%: about 250 masked cell draws for a 4-column strip), emit with its lookups (~25%), and the scroll copy (~11%).
- **Joystick:** works. The harness plays 10 stick moves, including diagonals.
- **VIC-20 tiles** are converted with MAP01's shared colours. Maps with a different palette should use hand-edited VIC-20 tiles, which don't depend on the palette.
