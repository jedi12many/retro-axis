# ISO64

An isometric turn-based RPG engine for retro computers. It currently runs on the Commodore 64, the VIC-20 and the C128's 80-column (VDC) screen, with one browser-based map and tile editor for all of them.
- Design and file formats: [docs/DESIGN.md](docs/DESIGN.md)
- Platform plan, covering more machines plus the C64 REU and Ultimate tiers: [docs/PLATFORMS.md](docs/PLATFORMS.md)

## Editor

Open `editor/index.html` in a browser. Opening the file directly works, as does `python -m http.server 8064 --directory editor`. Your work autosaves to the browser's local storage.

- **Map tab:** paint terrain, place objects, raise or lower ground, block cells, place entities and the player start. The preview is each engine's own algorithm, so colour clash shows up exactly as it will on the machine.
- **Machine toggle (C64 / VIC-20 / C128)**, above the preview and in the Tiles tab.
  - **In the Map tab**, the VIC-20 view renders the same map under VIC-20 limits. It counts the characters each frame needs and can highlight colour clash. **Auto-pick colours** chooses the screen, border and auxiliary colours that suit the map.
  - **In the Map tab**, the C128 view shows the 80-column VDC screen: a 640×200 bitmap where each 8×8 cell has two of the 16 RGBI colours, plus the side panel. Tiles are converted automatically, with the best colour pair per cell and ordered dithering. It counts colour clash and can highlight it. You can also set the empty-cell, border and panel colours.
  - **In the Tiles tab**, the toggle edits a tile's VIC-20 or C128 version by hand.
    - **VIC-20:** the pens become screen / border / cell / auxiliary, and each cell gets one of the 8 VIC-20 cell colours.
    - **C128:** the tile shows 32 hi-res pixels per line, the pens are background / foreground, and each cell gets a foreground and a background colour.
    - **Reset to automatic** goes back to the version converted from the C64 tile.
- **Tiles tab:** draw tiles in multicolour pixels, with per-cell colours and an adjustable height.
- **Export PRGs** downloads:
  - **C64:** `tiles.prg` and `sprites.prg`
  - **VIC-20:** `vtiles.prg` and `vsprites.prg`
  - **C128:** `ctiles.prg` and `csprites.prg`
  - **All:** one `mapxx.prg` per map. Map files are the same on every machine.

  Keep the names lowercase: lowercase host filenames show up as normal uppercase names under both VICE and sd2iec. The engines start in `MAP01`.

## Engines

```
engine/common/   shared 6502 code: map access, movement rules, isometric visibility
engine/c64/      C64: multicolour bitmap, double buffer, hardware sprites
engine/vic20/    VIC-20 (PAL, +32K): character set rebuilt per frame, soft sprites
engine/c128/     C128 80-column (64 KB VDC, 2 MHz): VDC bitmap, block-copy scrolling, soft sprites
```

Each platform folder has a `build.cmd` (needs cc65), which writes `build/<platform>/engine.prg`, and a `run-vice.cmd` that runs it in VICE with `build/<platform>/` as drive 8.

```bash
engine/c64/build.cmd
```

```bash
engine/vic20/build.cmd
```

```bash
engine/c128/build.cmd
```

The run scripts expect VICE in Downloads. Set the `VICE` (for `x64sc`), `XVIC` or `X128` environment variable if yours is elsewhere. `engine/c128/run-vice.cmd` starts `x128` with `-80col -VDC64KB`. The picture is in the VDC (80-column) window.

## Running on real hardware

Copy each machine's files into its own folder on the sd2iec card:

| Folder | Files |
|---|---|
| C64 | `engine.prg`, `tiles.prg`, `sprites.prg`, `map01.prg` |
| VIC-20 (needs 24K or more in blocks 1–3) | `engine.prg`, `vtiles.prg`, `vsprites.prg`, `map01.prg` |
| C128 (C128 mode, 64 KB VDC RAM as in the C128DCR, RGBI monitor) | `engine.prg`, `ctiles.prg`, `csprites.prg`, `map01.prg` |

Then `LOAD"ENGINE",8` and `RUN`. A flashing border means a data file wasn't found. On the C128, the engine switches to 2 MHz and uses the 80-column screen only.

| Keys | Move on screen |
|---|---|
| `W` / cursor up, `S` / cursor down | up / down |
| `A` / cursor left, `D` / cursor right | left / right |
| `Q`, `E`, `Z`, `C` | diagonally: up-left, up-right, down-left, down-right (one map square along a tile edge) |

A joystick works too, in port 2 on the C64 and C128 or the VIC-20's only port. Its four main directions step along the tile edges, and the diagonals move straight along the screen.

## Upgrading older exports

The double-buffered C64 engine moved the map to `$4c00` and the sprites to `$4400`, and the tile format gained a cell pointer table. PRGs exported before these changes won't load correctly. Open your project in the editor and press **Export PRGs** again.

Projects saved before the change also keep the old cliff slab, whose top face is opaque. They still work, but steps over raised ground are slower. To speed them up, open the slab in the Tiles tab and paint its top diamond face with the clear pen; that face is always covered by the level above.

## Tests

```bash
node test/engine-test.js
```

```bash
node test/vic20-test.js
```

```bash
node test/c128-test.js
```

Each test runs that machine's real `engine.prg` on a 6502 CPU core and plays a scripted sequence of moves (keys, plus joystick moves on the VIC-20 and C128). After every move it compares the screen with the editor's preview for that machine:
- **C64:** the bitmap, colours and sprites.
- **VIC-20:** the characters and colour RAM.
- **C128:** the whole 80×25-cell VDC frame on show, from a model of the VDC with its 64 KB RAM and block copy. It also checks that nothing is drawn into the frame on show.

They also write a demo set into `build/<platform>/`. The C128 test also writes the editor's frames as PNGs into `test/out/`. `node test/c128-vice-compare.js shot.png test/out/c128-editor-start.png` checks an `x128 -exitscreenshot` against one of them, pixel for pixel.

To see where a step's cycles go, routine by routine, on the C64 (joystick direction), the VIC-20 or the C128 (key):

```bash
node test/profile.js upright
```

```bash
node test/profile.js vic20 d
```

```bash
node test/profile.js c128 d
```
