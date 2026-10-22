# ISO64 opportunity backlog (ranked)

These are concrete improvements per platform flavor, ranked by value to the strategy in PLATFORMS.md §0: lead with the fully loaded Ultimate, and keep the stock C64 and the VIC-20 improving. Hardware facts and sources are in [c64.md](c64.md), [ultimate.md](ultimate.md), [c128.md](c128.md), [vic20.md](vic20.md) and [plus4-mega65.md](plus4-mega65.md).

**Baseline** (measured, PLATFORMS.md §4 and §6; DESIGN.md):

| Flavor | Step | Per frame |
|---|---|---|
| C64 stock | avg 174,461 cycles (137k–216k); strip drawing ≈ 57%, bitmap copy ≈ 14%, flip ≈ 10% | — |
| C64 + REU | 19,610 cycles, ~8k of real work | Smooth walk: 12.6k work + ≤ 2.2k flip ≈ 15.6k of the 19,656 PAL frame, plus ~1.7k VIC stealing, so **≈ 2k spare** |
| VIC-20 (24K+) | avg 229k cycles (130k–290k); `draw_tile` ≈ 35%, emit ≈ 25%, scroll copy ≈ 11% | — |
| C128 VDC | engine in progress on `claude/c128-vdc-*`, no numbers yet | — |

**Rules every item inherits:**
- **Editor preview:** a feature counts as done only when its flavor's editor preview shows it (PLATFORMS.md "Every flavor gets a preview"). Every item below therefore also touches the editor: `editor/index.html` for the C64 tiers, `editor/vic20.js`, or `editor/c128.js`.
- **Harness:** each item must keep `node test/engine-test.js` / `node test/vic20-test.js` passing frame by frame. Where an item changes the picture, the editor model changes first, and the harness compares against it.

**Column key:**
- **Effort:** S < 1 day, M a few days, L a week or more.
- **Risk:** the chance it fails, or breaks compatibility.
- **VICE:** ✓ = verifiable in VICE; ½ = correctness yes, timing or hardware no; ✗ = real hardware only.

---

## Top 10 (all flavors)

| # | Item | Flavor | Expected gain | Effort | Risk | VICE | Touches |
|---|---|---|---|---|---|---|---|
| 1 | **U-1 Turbo tier** | Ultimate | Smooth-walk frame from ~15.6k µs to ~2 ms of DMA + 0.15 ms of CPU, so **~17 ms per frame free**. World build 5.6 s → ~0.1 s | M | M | ✗ (½: the 1 MHz fallback path stays harness-tested) | `engine/c64/main.s`: `start` (detection), `load_file` (1 MHz around KERNAL), `reu_walk` / `sflip` (turbo while composing) |
| 2 | **X-1 Music IRQ restructure + 1-SID player** | C64 all tiers | Music and SFX at all; today IRQs are off while drawing. Costs ~1.5–3k cycles per frame (see below) | M | M | ✓ | `engine/c64/main.s`: `start`, `flip`, `sflip`, `get_move` (keyboard without the KERNAL IRQ), new `irq` |
| 3 | **U-2 Exact figure masking** | Ultimate (needs U-1) | Figures correctly behind walls and trees, pixel-exact | L | M | ½ (the harness checks pixels; VICE drops frames at 1 MHz) | `reu_walk` / `sframe` (composite figures into the back buffer after the window fetch), new figure-mask data from the editor |
| 4 | **S-1 Stock inner-loop speed-ups** | C64 stock (VIC-20 too, as V-2) | Est. **−20–30% per step** (175k → ~125–140k) | M | L | ✓ | `draw_tile` (self-modifying absolute operands: 23 → ~17–19 cycles per masked byte), `scroll_copy` (skip rows that are cleared), coverage skip |
| 5 | **C-1 Cartridge world tier (EasyFlash / KFF)** | C64 + EasyFlash/KFF/Ultimate cart | Step ~**38k cycles (≈ 4.5× stock)**, instant loads | L | M | ✓ (`x64sc -cartcrt`) | Editor (CRT export with pre-rendered worlds from `renderMap`), `engine/c64/main.s` new tier (memory-map change: tiles no longer at `$8000`) |
| 6 | **A-1 Sprite multiplexer** | C64 stock / REU (Ultimate: U-2 makes it optional) | Visible figures 7 → ~16–24 | L | M | ✓ | `place_sprites`, `ssprites`, raster IRQ chain inside lines 59–202 (needs X-1's IRQ framework) |
| 7 | **R-1 NTSC budget for the smooth walk** | C64 + REU on NTSC | Without it: likely dropped frames (≈ 17.3k needed vs 17,095 available). With it: a full-rate walk on NTSC | S–M | L | ✓ (`x64sc -ntsc`) | `reu_walk` (detect NTSC, use `ssh=0` pacing or trim the colour fetch), harness NTSC timing in `test/engine-test.js` |
| 8 | **V-1 Text from character ROM via a raster split** | VIC-20 | Character budget **112 → 144** per frame for ~0 cycles; fewer overflow fallbacks; allows a bigger viewport | S–M | L | ✓ | `engine/vic20/main.s` (`flip`, a `$9005` split polled below the viewport, `CODES`/`TEXT_CH`), `editor/vic20.js` budget |
| 9 | **A-2 Sprite priority behind walls (`$d01b`)** | C64 stock / REU | Approximate "behind walls" on every C64 tier for ~0 cycles | S (code) + M (art) | L | ✓ | `place_sprites` / `ssprites` (priority bit per figure from its cell), tile art convention (occluders use pixel pairs 10/11), editor preview shows the priority |
| 10 | **U-3 Dual-SID stereo** | Ultimate (and any C64 with 2 SIDs) | 6-voice stereo music | S (on top of X-1) | L | ✓ (`-sidextra 1 -sid2address 0xd420`) | Music player config, SID probe in `start` |

**Top 5 summary:** turbo tier (1), music IRQ (2), exact masking on the Ultimate (3), stock inner loops (4), cartridge world tier (5).

---

## C64 + Ultimate (lead target)

### U-1 Turbo detection and use

**What it is:**
- Detect `$d031 != $ff` (turbo registers enabled) and the UCI ID (`$df1d == $c9`).
- Select the speed index (e.g. 15 = 48/64 MHz) and set bit 7 (badline timing off) while composing.
- Drop to index 0 around KERNAL `LOAD`, then restore.
- Firmware ≥ 3.15 is needed (it fixes stale REU data in turbo).

**Gain:**
- **REU walk:** about 6.5k bytes of DMA per frame at ~3.5 B/µs ≈ 1.9 ms, plus ~6k CPU cycles at 48 MHz ≈ 0.13 ms. That leaves ~17 ms of the 20 ms frame for U-2, animated tiles (A-3), AI and multi-figure animation.
- **World build:** 5.5M cycles → ~0.12 s.

**Risks:**
- KERNAL serial `LOAD` under turbo is unverified, hence the 1 MHz wrap.
- I/O accesses stay at 1 µs each, so register-heavy loops (REU setup per row) don't speed up. Batch them.
- 4 MHz is a bad point: REU fetch is slower there than at 3 MHz. Use ≥ 8 MHz.

**Verify:** VICE can't (no turbo). The harness keeps verifying the picture at 1 MHz. Hardware checklist in ultimate.md §7.

**Preview:** the "C64 Ultimate" flavor = the REU preview plus Ultimate-only features (unchanged until U-2 or A-3 land).

### U-2 Exact figure depth (software masking)

**What it is:** after `reu_walk` fetches the window, draw each figure into the back buffer with a per-pixel mask clipped by occluders in front of it.
- The occluders are the tile cells drawn later in back-to-front order: the figure's map cell, plus cells with a larger x+y.
- Practical approach: re-draw the occluding tile cells over the figure, using `draw_cell` restricted to the figure's screen box. The existing clipped renderer already composes correctly; only the box changes.

**Cost:**
- Per figure, ~4×3 cells × (figure masked blit + 2–4 occluder cells) ≈ 12 × 4 × 8 bytes × ~20 cycles ≈ 8k cycles.
- 8 figures ≈ 64k cycles: **turbo only** (~1.3 ms at 48 MHz).
- Hardware sprites are then free for UI, cursor and effects.

**Verify:** the harness's per-frame picture check already compares full VIC output with the editor's world image. The editor's Ultimate preview must render figures into the image with the same rule. Correctness ✓, timing ✗.

### U-3 Stereo SIDs

Probe `$d420`, `$d500`, `$de00` (skip `$df00` while the REU is present). Use a GoatTracker 2 Stereo player. Needs X-1.

### U-4 Fast data via the Ultimate Command Interface

- DOS target `$01`: `OPEN_FILE` + `READ_DATA` at ~100 KB/s (CPU reading `$df1e`), replacing KERNAL `LOAD` on the Ultimate.
- `LOAD_REU` (`$01 $21`) loads an editor-made world straight into the REU, only useful with turbo off.

Effort M, risk L, VICE ✗. Touches `load_file`.

### U-5 Per-map palette (optional)

UCI control `$04 $52` + 48 RGB bytes. It changes the look, so it needs its own flavor preview and a map header field (v2 tagged block, PLATFORMS.md §3). Effort S–M, risk L, VICE ✗.

## C64 + REU

### X-1 Music (applies to stock and Ultimate too)

**Problem:** `sei` while drawing, and the KERNAL is out (`$01=$35`), so there's no IRQ during a ~175 ms stock step.

**Fix:**
- An own IRQ handler via `$fffe` that is valid with the KERNAL out and saves `$01`.
- Keep IRQs **on** while drawing.
- Scan the keyboard with a CIA routine (or keep `GETIN` only in `main_loop` with the KERNAL in).
- One raster IRQ at ~line 205–215 calls the player; the flip at 210 (stock) or 250 (walk) needs re-checking.

**Budget:**
- **Stock:** +1.5–3k per frame, so a step slows ~8–15% (fine).
- **REU walk:** only ~2k is spare per frame. A full player (~3k) would drop frames at `ssh=1`. Options:
  - a light player (~1.5k);
  - recover ~1k (e.g. skip `cm_a`/`cm_b` on frames where `xs` = 0, unroll `zlines`);
  - on the Ultimate, turbo (U-1) removes the issue.
- Measure with `test/profile.js`.

Effort M, risk M, VICE ✓.

### R-1 NTSC

Smooth-walk frames need ≈ 17.3k cycles against 17,095 per NTSC frame. Run the harness with NTSC frame timing and `x64sc -ntsc`. Then either trim (colour fetch only on window moves already; split the colour fetch across two frames) or pace NTSC at `ssh=0` with 2 video frames per animation frame. Effort S–M.

### A-3 Animated tiles (water, torches)

- **REU tier at 1 MHz:** patch animated cells into the back buffer after the window fetch: ~8 bytes + colour per cell ≈ 120 cycles. With ~2k spare, about 10–15 cells per frame.
- **Turbo:** every animated cell, every frame.
- **Stock:** redraw a few cells per step (inside the strip-redraw budget).
- Needs an animation table in the tile format (editor + `TILES`) and a world-image "base frame". Effort M–L, risk M, VICE ✓.

### W-1 Larger maps (map format v2)

- A 64×64 map makes the world image ~276×146 cells ≈ 400 KB, so it needs a ≥ 512 KB REU. Ultimate REUs (16 MB) are fine.
- On a 128 KB 1700, fall back to 32×32 or to sections.
- Touches the map header (v2 tagged block), `world_build`, `reu_win`, `engine/common/view.s` (32×32 assumptions), and the editor. Effort L, risk M, VICE ✓ (`-reusize 512+`).

## C64 stock

### S-1 Inner loops

From DESIGN.md's list, now with estimates:
1. **Self-modifying absolute addressing** in the `draw_tile` masked path: 23 → ~19 cycles per byte (or ~17 with interleaved mask/data). Strip drawing is ~57% of the step, so about **−10–15%**.
2. **Skip the bitmap copy for rows that are cleared anyway** (diagonal moves): copy is ~14%, rows are 1–2 of 18, so about −1–2% on those moves.
3. **Coverage skip:** don't draw a tile cell that a later opaque cell fully covers. Helps walls and buildings: −5–15% on built-up maps.
4. **Flip from a raster IRQ** so input handling starts during the wait: hides up to 1 frame (~10% of the measured step).

Effort M, risk L, VICE ✓. Touches `draw_tile`, `scroll_copy`, `flip`, `engine/common/view.s` (`draw_all` order data for coverage).

### C-1 Cartridge world (EasyFlash / KFF)

- The editor writes a CRT: engine + tiles + sprites + maps + a pre-rendered world per map, made with its exact `renderMap`.
- A step copies 18×(192+24+24) bytes from ROM ≈ 4.3 KB × ~8–9 cycles ≈ **38k cycles**.
- Smooth walking from ROM (~6 KB per frame ≈ 50k cycles) doesn't fit 50 fps. A 2–3 frame-per-fine-step walk (~17–25 fps) is possible.
- Flash size: 1 MB, so ~7 maps at 121 KB, or more with per-map cropping.
- Savegames via EAPI.
- KFF users can't also have an REU (one port).
- Effort L, risk M, VICE ✓.

### S-7 AGSP smooth scrolling (research grade)

- VSP + line crunch scroll the bitmap with no copying. Then draw only the exposed strip, spread over the step's frames (≈ 100k ÷ 8 ≈ 12.5k per frame).
- **Blockers:**
  - VSP crashes some C64s ("safe VSP" layout required);
  - cycle-exact top-of-screen code;
  - the side UI panels share the viewport's lines and would scroll with it.
- Effort L+, risk H, VICE ✓ (VICE does not reproduce the VSP crash).

### K-1 2 MHz in the border on a C128 (C64 mode)

Detect `$d030` = `$fc`/`$fd` (VICE ✓). A raster IRQ pair sets 2 MHz outside the display window (~36% of lines): **~1.3× on stock steps** (est.). Keep 1 MHz for REU DMA and KERNAL I/O. Effort S–M (after X-1), risk M, VICE ✓ (x128 `-go64`).

### UI-1 Hires text area by raster split

- At ~line 203, switch rows 19–24 to hires character mode (`$d011` / `$d016` / `$d018`), with a font in both VIC banks.
- Text then costs 1 byte per character instead of 8 bitmap bytes: crisp 40-column text for the combat log and status.
- **Constraint:** `$d011` writes during `$30–$f7` risk VSP. Change only the mode bits, with YSCROLL unchanged, which is safe (no badline condition change).
- Effort M, risk L–M, VICE ✓. Touches `flip`, `sflip`, a new IRQ, and the editor preview of the UI rows.

## VIC-20

| ID | Item | Gain | Effort | Risk | VICE | Touches |
|---|---|---|---|---|---|---|
| V-1 | Text from character ROM via a `$9005` split | Budget 112 → 144 codes; fewer overflow paths; room for a wider viewport | S–M | L | ✓ | `flip`, init, `CODES`/`TEXT_CH`, `editor/vic20.js` |
| V-2 | `draw_tile` inner loops (self-modifying absolute operands, coverage skip) | `draw_tile` ≈ 35%, so ~−8–12% per step | M | L | ✓ | `draw_tile` in `engine/vic20/main.s`. **Code space: 26 bytes left below `$34e8`**, so the memory map must change first |
| V-3 | Big-RAM flavor (UltiMem / FE3): pre-rendered compose world in banked RAM (~93 KB + 12 KB) | Step ~229k → ~155k (−30%; the copy replaces `draw_tile` + scroll copy) | L | M | ✓ (FE3 / UltiMem cartridge images) | New tier in `engine/vic20/main.s`, editor (world export or build on the machine), `vic20.cfg` |
| V-4 | Raster colour split for the UI (different aux/screen colour for rows 18–22) | Map palette choice no longer constrained by text legibility | S | L | ✓ | `flip`/main loop polling, editor auto-pick colours |
| V-5 | IRQ music player (VIC voices) | Music | M | L | ✓ | New VIA-timer IRQ, `$900e` writes keep the aux colour bits |
| V-6 | End-of-step camera ease via `$9000`/`$9001` | Perceived smoothness (2–3 frames) | S–M | M (margins) | ✓ | `flip`, border margins |

## C128 VDC (advice for the in-progress branch)

| ID | Item | Gain | Effort | Risk | VICE | Touches |
|---|---|---|---|---|---|---|
| D-1 | **Draw with VDC block copy/fill, not CPU writes through R31** | VICE: copy 1.47 µs/B and fill 0.85 µs/B vs CPU write 22–31 µs/B, i.e. **15–35× per byte** | M | L | ✓ (ratio); ✗ (absolute) | VDC `draw_tile` / tile storage in VDC RAM (64 KB) |
| D-2 | **Hardware scroll**: R12/R13 start address + R27 row stride over a wider virtual bitmap, R24/R25 fine scroll | Steps draw only the exposed strip; smooth panning possible | M–L | M | ✓ | VDC platform layer, `c128.js` preview |
| D-3 | Denser attributes (R9 = 3 or 1: 8×4 or 8×2 colour cells) | Much better colour fidelity for the converted C64 tiles | M | M (8563 vs 8568 differences) | ✓ (verify on hardware) | VDC init, tile conversion in `editor/c128.js` |
| D-4 | 2 MHz always, VIC-II blanked | ~2× CPU | S | L | ✓ | VDC `start` |
| D-5 | Zero-page relocation via MMU `$d507` | No KERNAL ZP conflicts; cheap context switch | S | L | ✓ | VDC `start` |

## Future flavors

- **Plus/4 (64 KB):** port the C64 bitmap renderer, with the 2+2 colour conversion and soft sprites. VICE `xplus4` ✓.
- **MEGA65:** native engine using FCM + RRB for exact depth. Needs a 45GS02 harness core and Xemu.

See [plus4-mega65.md](plus4-mega65.md).

## PETSCII

Research: [petscii.md](petscii.md). Glyph codes and the diamond recipe: `.claude/skills/commodore-engine/references/petscii.md`.

| # | Item | Flavor | Expected gain | Effort | Risk | VICE | Touches |
|---|---|---|---|---|---|---|---|
| P-1 | **PETSCII flavor (semigraphics)** | New flavor on C64, VIC-20, C128, and a PET port | No character set or tile art in RAM, so it runs on the PET and on lightly expanded VIC-20s. Full redraw ≈ 1 PAL frame on the C64. An authentic PETSCII look. | M | L | ✓ (`xpet`, `x64sc`, `xvic`) | new `engine/petscii/` (or a C64 build switch), `editor/petscii.js` (preview, clash counter, quarter-mask tiles), new harness |
| P-2 | **PETSCII UI kit** | All flavors | Panels, HP/XP bars (eighth-step glyphs), combat log and menus with no art and the same text code everywhere | S–M | L | ✓ | `engine/common` (a text/panel module + platform `put_char`), UI-1 raster split on the C64 bitmap |
| P-3 | **Petmate import** | Editor | Hand-drawn PETSCII stamps per tile (as in PETSCII Robots), from Petmate/petmate9 `.petmate` JSON | S | L | n/a | `editor/petscii.js` |
| P-4 | **PET port** | PET (40 or 80 columns, monochrome) | One more Commodore. PETSCII Robots shows that one map file can run on the PET, VIC-20 and C64 | M (after P-1) | M (no colour, so tiles are told apart by pattern) | ✓ `xpet` | `engine/pet/`, PET KERNAL loading |

The **diamond recipe is verified**: 8×4 quarter-pixels per floor diamond, which is 4×2 characters, the same grid as every flavor. At ISO64's tile offsets the diamonds tile the plane exactly.

## Needs real hardware (summary)

- **Ultimate:**
  - turbo register behaviour per menu mode;
  - KERNAL `LOAD` under turbo;
  - REU rate at turbo on PAL (only one NTSC device measured);
  - UCI ID and model string on the C64U;
  - stable illegal opcodes on the FPGA 6510;
  - the Ultimate Audio sampler's register map (not found).
- **C128:**
  - VDC CPU access speed (VICE: 22–31 µs per byte, real hardware unknown);
  - block copy/fill speeds;
  - attribute density with R9 on the 8563 vs the 8568;
  - 2 MHz-in-border in C64 mode.
- **VIC-20:** UltiMem register defaults, FE3 SUPER_RAM on a real cartridge, the exact line for a `$9005` split.
- **C64:**
  - the "safe VSP" layout (only if S-7 is attempted);
  - sd2iec's lack of 1571 burst (C128).
