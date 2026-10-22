# ISO64

An isometric turn-based RPG engine for retro computers. It currently runs on the Commodore 64 and the VIC-20, with one browser-based map and tile editor for all of them.
- Design and file formats: [docs/DESIGN.md](docs/DESIGN.md)
- Platform plan, covering more machines plus the C64 REU and Ultimate tiers: [docs/PLATFORMS.md](docs/PLATFORMS.md)

## Editor

Open `editor/index.html` in a browser. Opening the file directly works, as does `python -m http.server 8064 --directory editor`. Your work autosaves to the browser's local storage.

- **Map tab:** paint terrain, place objects, raise or lower ground, block cells, place entities and the player start. The preview is each engine's own algorithm, so colour clash shows up exactly as it will on the machine.
- **Machine toggle (C64 / VIC-20)**, above the preview and in the Tiles tab.
  - **In the Map tab**, the VIC-20 view renders the same map under VIC-20 limits. It counts the characters each frame needs and can highlight colour clash. **Auto-pick colours** chooses the screen, border and auxiliary colours that suit the map.
  - **In the Tiles tab**, the toggle edits a tile's VIC-20 version by hand: the pens become screen / border / cell / auxiliary, and each cell gets one of the 8 VIC-20 cell colours. **Reset to automatic** goes back to the version converted from the C64 tile.
- **Tiles tab:** draw tiles in multicolour pixels, with per-cell colours and an adjustable height.
- **Export PRGs** downloads:
  - **C64:** `tiles.prg` and `sprites.prg`
  - **VIC-20:** `vtiles.prg` and `vsprites.prg`
  - **Both:** one `mapxx.prg` per map. Map files are the same on every machine.

  Keep the names lowercase: lowercase host filenames show up as normal uppercase names under both VICE and sd2iec. The engines start in `MAP01`.

## Engines

```
engine/common/   shared 6502 code: map access, movement rules, isometric visibility
engine/c64/      C64: multicolour bitmap, double buffer, hardware sprites
engine/vic20/    VIC-20 (PAL, +32K): character set rebuilt per frame, soft sprites
```

Each platform folder has a `build.cmd` (needs cc65), which writes `build/<platform>/engine.prg`, and a `run-vice.cmd` that runs it in VICE with `build/<platform>/` as drive 8.

```bash
engine/c64/build.cmd
```

```bash
engine/vic20/build.cmd
```

The run scripts expect VICE in Downloads. Set the `VICE` (for `x64sc`) or `XVIC` environment variable if yours is elsewhere.

## Running on real hardware

Copy each machine's files into its own folder on the sd2iec card:

| Folder | Files |
|---|---|
| C64 | `engine.prg`, `tiles.prg`, `sprites.prg`, `map01.prg` |
| VIC-20 (needs 24K or more in blocks 1–3) | `engine.prg`, `vtiles.prg`, `vsprites.prg`, `map01.prg` |

Then `LOAD"ENGINE",8` and `RUN`. A flashing border means a data file wasn't found.

| Keys | Move on screen |
|---|---|
| `W` / cursor up, `S` / cursor down | up / down |
| `A` / cursor left, `D` / cursor right | left / right |
| `Q`, `E`, `Z`, `C` | diagonally: up-left, up-right, down-left, down-right (one map square along a tile edge) |

A joystick works too, in port 2 on the C64 or the VIC-20's only port. Its four main directions step along the tile edges, and the diagonals move straight along the screen.

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

Each test runs that machine's real `engine.prg` on a 6502 CPU core and plays a scripted sequence of moves (keys, plus joystick moves on the VIC-20). After every move it compares the screen with the editor's preview for that machine: the C64 bitmap, colours and sprites, or the VIC-20 characters and colour RAM. They also write a demo set into `build/<platform>/`.

To see where a step's cycles go, routine by routine, on the C64 (joystick direction) or the VIC-20 (key):

```bash
node test/profile.js upright
```

```bash
node test/profile.js vic20 d
```
