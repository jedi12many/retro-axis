---
name: commodore-engine
description: How to work on ISO64, the isometric RPG engine for Commodore machines (C64 stock / +REU / Ultimate turbo, VIC-20, C128 VDC, later Plus/4 and MEGA65). It covers hardware cheat-sheets (registers, memory maps, PAL/NTSC cycle budgets), proven tricks for squeezing these machines, and the project's conventions: shared engine/common plus a platform layer per machine, every engine matching its editor preview under the 6502 test harness, and every flavor getting an editor preview. It also gives the build, test and VICE commands, and the Windows quirks. Use it for any change to engine/*, editor/* or test/* in this repo, for planning a new platform or tier, for performance work (cycle counts, raster timing, REU/DMA, VDC, turbo), and for questions about C64, VIC-20, C128 or Ultimate 64 hardware, even if the user doesn't say "skill" or name a file.
---

# ISO64 Commodore engine

ISO64 is one turn-based isometric RPG, shipped as one engine per machine. The goal is to get the most out of each machine. The **lead target** is the fully loaded C64 Ultimate / Ultimate 64 (REU + turbo + 2 SIDs). The stock C64 and the VIC-20 keep getting the best version their hardware allows (docs/PLATFORMS.md §0). Design for the Ultimate first, then add the best version each smaller machine can manage.

## Read first, depending on the task

| Task | Read |
|---|---|
| Anything in the repo | `docs/DESIGN.md` (graphics model, formats, C64 memory map), `docs/PLATFORMS.md` (architecture, tiers, VIC-20 v1, the preview rule) |
| Choosing what to build next | `docs/research/OPPORTUNITIES.md`: a ranked backlog with gains, effort, risk, and whether VICE can verify each item |
| C64 hardware, REU, timing, tricks | [references/c64.md](references/c64.md), then `docs/research/c64.md` for sources |
| Ultimate turbo, Command Interface, SIDs | [references/ultimate.md](references/ultimate.md), then `docs/research/ultimate.md` |
| C128 / VDC | [references/c128-vdc.md](references/c128-vdc.md), then `docs/research/c128.md` |
| VIC-20 | [references/vic20.md](references/vic20.md), then `docs/research/vic20.md` |
| Build, test, VICE, Windows quirks | [references/workflow.md](references/workflow.md) |

The `docs/research/*.md` files carry confidence marks: H = documented or measured, M = community source, L = unconfirmed, 🔧 = needs real hardware. Keep the marks when you quote a claim, so nobody builds on an unconfirmed claim by accident.

## Architecture in one screen

```
editor/index.html  one editor; C64 tiles are the master art, maps are shared by all machines
editor/vic20.js    per-machine module: hardware model, tile conversion, preview, export
engine/common/     6502 code shared by every 6502 machine: zp.inc ($02-$5f), defs.inc,
                   game.s (rules: movement, blocking, bumping), view.s (visibility, dirty
                   strips, back-to-front draw order)
engine/<machine>/  platform layer: main.s, build.cmd, run-vice.cmd (+ linker cfg)
test/              cpu6502.js + one harness per machine; profile.js for per-routine cycles
build/<machine>/   ready-to-copy SD card folder (engine.prg + data files)
```

**The platform layer contract.** Each machine provides:
- `VP_C0 VP_C1 VP_R0 VP_R1`, `CENTER_COL/ROW`;
- the `COLM`/`ROWM` dirty-mask tables;
- `draw_tile` (clipped by the masks, drawn into the hidden frame);
- `plat_flash`;
- the main loop (load, `render_full`, `render_scroll`, flip, sprites, input).

The common code calls these. A platform's own zero page starts at `$60`.

**Rendering idea shared by all machines:**
- Tile edges fall on cell boundaries: a 2:1 diamond is 4×2 cells, one height level is 1 cell row. So drawing only copies or masks whole bytes and never shifts bits.
- Each step scrolls by whole cells: copy the old frame shifted, redraw only the exposed strip, flip below the viewport.
- A clipped render is exactly a window of the unclipped world. That is why the REU tier can pre-render the whole world once and DMA a window per frame.

## Non-negotiable project rules (and why)

1. **Every engine matches its editor preview, frame by frame.** The harness (`test/engine-test.js`, `test/vic20-test.js`) runs the real `engine.prg` on a JS 6502 core and diffs screen memory against the editor's renderer after every scripted move. The REU walk is checked on every animation frame.
   - This is what lets the project optimise aggressively without breaking anything.
   - A change that alters the picture changes the **editor model first**, then the engine.
   - Never "fix" a failing diff by loosening the test.
2. **Every platform flavor gets an editor preview** (PLATFORMS.md, "Every flavor gets a preview"):
   - the flavors are C64 stock, C64 + REU (smooth walking), C64 Ultimate (REU + Ultimate-only features), VIC-20 and C128 VDC;
   - a feature counts as done only when its flavor's preview shows it **and** the harness passes;
   - the Machine toggle is planned to become a flavor list once the C128 branch merges.
3. **The shared map format** (`mapxx.prg`, `$e00` bytes, 32×32) is identical on every machine. Per-platform settings go in free header bytes (`$0b-$0f`); a v2 tagged block is planned for more. Don't fork the map format per machine.
4. **Same picture on every C64 tier.** Stock, REU and turbo differ only in speed and smoothness, unless the feature is explicitly flavor-only and has its own preview.
5. **Load files through KERNAL `LOAD`, by wildcard, with lowercase host names.**
   - The engines ask for `TILES*`, `SPRITES*`, `MAP01*`, `VTILES*`, `VSPRITES*`.
   - The editor exports lowercase files (`tiles.prg`), which show up as normal names on sd2iec and on VICE's directory device.
   - KERNAL `LOAD` keeps sd2iec, Kung Fu Flash (it hooks the KERNAL vectors, so custom fast loaders break) and the Ultimate working.
6. **Raster safety.** On the C64, never write `$d011` during lines `$30–$f7` with a YSCROLL that could create a badline mid-line: that is VSP, which crashes some C64s. The REU walk flips at line 250 for this reason.
7. **Stay in your lane on shared branches.** Other sessions own other platforms. A platform change touches `engine/<that machine>/`, its harness and its editor module. A change to `engine/common/` must keep **every** platform's harness passing.

## Measured baselines (update them when you improve something)

| Flavor | Number |
|---|---|
| C64 stock | Step avg **174,461 cycles** (137k–216k). Strip drawing ≈ 57%, bitmap copy ≈ 14%, flip ≈ 10% |
| C64 + REU | Step **19,610** (~8k real work). Smooth walk: **~15.6k of 19,656 cycles per PAL frame** + ~1.7k VIC stealing, so **~2k spare**. Boot 6.19M cycles (world build) |
| VIC-20 (PAL, 24K+) | Step avg **229k** (130k–290k). `draw_tile` ≈ 35%, emit ≈ 25%, scroll copy ≈ 11%. Character budget 112 per frame. **~26 bytes of code space left** below `$34e8` |

These numbers decide what's affordable. For example, a 3k-cycle music player does **not** fit the REU walk at 1 MHz without savings elsewhere, and the walk is ~1% over budget on **NTSC** (17,095 cycles per frame).

## How to approach a performance or feature task

1. **Measure:** `node test/profile.js <move>` (C64) or `node test/profile.js vic20 <key>`; `ISO64_REU=1` for the REU tier.
2. **Check the budget** against the frame (PAL C64 19,656; NTSC 17,095; VIC-20 PAL 22,152) and the cost tables in the references.
3. **Prefer techniques already proven here:** double buffering, cell-aligned blits, dirty masks, REU autoload rows, unrolled per-buffer routines, labels and hashing on the VIC-20.
4. **Change the editor model, then the engine.** Run the harness and the profile, then look at it in VICE (`run-vice.cmd`, `run-vice.cmd reu`).
5. **Update `docs/PLATFORMS.md`** with the new measured numbers, and say in the commit what the harness covered.
6. **Flag 🔧 anything VICE can't show:** Ultimate turbo, the Command Interface, real VDC speed, VSP crash behaviour.
