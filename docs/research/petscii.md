# PETSCII games and character-mode engines

What PETSCII games do, the tools behind them, and what that means for ISO64. Confidence marks are as in the rest of `docs/research`:
- **H:** documented, or measured here;
- **M:** a community or secondary source;
- **L:** unconfirmed;
- 🔧 needs real hardware.

## 1. The character set

- **Where it lives.** PETSCII is the built-in character set of 8-bit Commodore machines. It started on the PET and carried over to the VIC-20, C64, CBM-II, Plus/4, C16, C116, C128 and the Commander X16. [H, [C64-Wiki][wiki]]
- **Size.** It has 192 PETSCII values, against ASCII's 127. Codes 192–223 duplicate 96–127, and 224–254 duplicate 160–190. [H, [C64-Wiki][wiki]]
- **Two sets.** One is uppercase plus graphics, the other lowercase plus uppercase. CHR$(14) and CHR$(142) switch between them. [H, [C64-Wiki][wiki]]
  - On the C64 the switch is bit 1 of `$d018`, since the two sets are the two 2 KB halves of the character ROM. [M]
- **Screen codes are not PETSCII codes.** Screen RAM holds *screen codes*: 0–127 are the glyphs, and 128–255 are the same glyphs in reverse video. [M; the reverse halves are confirmed in the ROM measurement below]
- **A creative platform.** The academic treatment is Reunanen, Heikkinen and Carlsson, *PETSCII – A Character Set and a Creative Platform*, Replay 5(1), 2019, pp. 27–47. It argues that the fixed symbol set limits what can be drawn, but invites experimentation and gives rise to recognisable styles. [H, [Aalto Research][paper]]

### Glyph inventory: measured from VICE's C64 character ROM

Classified pixel by pixel from `C64/chargen-901225-01.bin` (uppercase/graphics set, screen codes) with `petscii-glyphs.js`. [H, measured]

**All 16 combinations of 2×2 quarter blocks exist.** So any PETSCII screen is an exact **semigraphics** display at 2× the text resolution in each direction:

| Screen | Semigraphics |
|---|---|
| C64 40×25 | **80×50** |
| VIC-20 22×23 | 44×46 |
| C128 VDC 80×25 | 160×50 |

PETSCII Bros on the PET uses the same principle. [M, [setsideb][bros]]

| Quarters set (UL UR LL LR) | Screen code | | Quarters set | Screen code |
|---|---|---|---|---|
| none | `$20` | | UL+UR (top half) | `$e2` |
| UL | `$7e` | | LL+LR (bottom half) | `$62` |
| UR | `$7c` | | UL+LL (left half) | `$61` |
| LL | `$7b` | | UR+LR (right half) | `$e1` |
| LR | `$6c` | | UL+LR | `$7f` |
| all but UL | `$fe` | | UR+LL | `$ff` |
| all but UR | `$fc` | | all (full) | `$a0` |
| all but LL | `$fb` | | | |
| all but LR | `$ec` | | | |

**Other useful glyphs:**
- **Half-cell triangles:** ◤ `$69` and ◥ `$5f`. Their reverse forms ◢ `$e9` and ◣ `$df` differ by the diagonal pixel line.
- **Eighth-steps:** solid bars of 1/8 to 7/8 from each edge, for example bottom 1/8 `$64`, 2/8 `$6f`, 3/8 `$79`, half `$62`, 5/8 `$f8`, 6/8 `$f7`, 7/8 `$e3`. They give 8-step resolution along one axis.
- **1-pixel lines** at row 0 and row 7, and **2-pixel lines** through the centre (`$40`, `$42`).

There are **no 2:1 diagonals.** Isometric edges have to be built from quarter blocks (§4) or eighth-steps.

## 2. Notable PETSCII games, and what each teaches

| Game | Machines | What it shows |
|---|---|---|
| **Attack of the PETSCII Robots** (The 8-Bit Guy, 2021) | PET, C64, VIC-20; later ports to Apple II, Atari 8-bit, Amiga and others [H, [Giant Bomb][gb]] | One 6502 game shipped on many Commodores from a single design. Details below the table. |
| **PETSCII Bros** | PET | The 16 quarter-block characters used as an 80×50 pixel display for an action game [M, [setsideb][bros]] |
| **Escape From PETSCII Castle** | PET | A Wolfenstein-style first-person shooter in PETSCII [M, [itch.io][castle]] |
| **Digiloi** (Dr. TerrorZ, 2018) | C64 | A PETSCII action platformer praised for its art direction [M, [IndieRetroNews][digiloi]] |
| **Delve! The Goblin's Grotto** | C64 | A PETSCII dungeon crawler, the closest genre match to ISO64 [M, [IndieRetroNews][irn]] |
| **PETSCII Dungeons & Droids** (Ko-Ko, work in progress) | C64, Plus/4, PET | A roguelike deck-builder in full PETSCII across three Commodores [M, [itch.io][dd]] |
| **PETSCII Lumberjack** (2024) | C64 | A demo-party game compo entry (QB Party 2024, 4th) [M, [CSDb][lumber]] |

**PETSCII Robots in detail:**
- **Tiles and map:** the playfield is 11×7 tiles of 24×24 pixels, i.e. 3×3 characters per tile [M, forum]. The map is probably 128×64 tiles, inferred from the editor's search-range parameters C 0–127 and D 0–63 [M, [editor guide][mapedit]].
- **Units:** a fixed unit table of 64 slots: player, robots 1–27, weapons fire 28–31, doors 32–47, hidden items 48–63. Each unit has a type, parameters A–D and health [H, [editor guide][mapedit]].
- **One map file for every machine:** the level editor runs only on the PET, but its maps run unchanged on the C64 and VIC-20 versions [H, [editor guide][mapedit]].
- **Ports:** the portable SDL port moved the logic line by line from the 6502 sources behind a `Platform` interface [H, [Aminet readme][sdl]]. That's the same split as ISO64's `engine/common` plus platform layers.

**The scene.** PETSCII art and game entries appear regularly in demo-party "mixed" and PETSCII competitions (Edison 2023, Xenium 2024, QB Party 2024) [M, [CSDb][csdb]]. No dedicated yearly PETSCII *game* jam was found.

## 3. Tools

| Tool | What it does | Notes |
|---|---|---|
| **Petmate** (Nurpax) | The standard C64 PETSCII editor | v0.8.3 (2021) on [CSDb][petmate]. Its `.petmate` files are JSON |
| **petmate9** (a fork) | Multi-platform: C64, C128, **C128 VDC 80-col**, VIC-20, PET 40/80, C16/Plus/4 | Converts images to PETSCII (Petsciiator, IMG2PETSCII, Pet9scii). Can send to and reset Ultimate 64 hardware, and exports D64 [M, [Oasis BBS][pm9]] |
| **ventti/petscii** | A PETSCII editor with a headless CLI and plugins | Built for pipelines: game and demo asset builds [M, [GitHub][ventti]] |
| **Playscii** | A general ASCII/PETSCII art tool and game engine (MIT) | Includes Commodore character sets, plus image conversion [M, [GamingOnLinux][playscii]] |

## 4. Character-mode engine techniques

| Technique | Detail |
|---|---|
| **Full-screen redraw is cheap** | 1,000 screen bytes plus 1,000 colour bytes. With unrolled `lda abs,x / sta abs,x` that's about 16–20k cycles on a C64, about one PAL frame (19,656). A whole-screen update every frame is affordable, unlike bitmap mode. [M, from cycle counts] |
| **Double buffering** | Switch the screen pointer: C64 `$d018` upper nibble; VIC-20 `$9005` plus `$9002` bit 7, as ISO64 does. Copy colour RAM in the border. [H, the ISO64 engines do this] |
| **Smooth scrolling** | Character mode plus `$d016`/`$d011` fine scroll, with a coarse shift every 8 pixels. This is the classic scrolling technique, and much cheaper in character mode than in bitmap mode. [M] |
| **Colour** | One foreground colour per character (colour RAM) on a global background. Reverse glyphs swap which side is drawn. [H] |
| **ECM (C64)** | Four background colours, but only screen codes 0–63. That excludes the quarter blocks, so ECM is no use for semigraphics. [M] |
| **Multicolour character mode** | Doubles pixel width, so ROM glyphs lose their look. Avoid it for PETSCII. [M] |
| **C128 VDC** | Each character's attribute holds colour, reverse, underline, blink, and an **alternate character set** select. Character mode is far cheaper than VDC bitmap mode: 2,000 + 2,000 bytes. [M; see `c128.md` for the VDC speeds] |
| **TED (Plus/4)** | PETSCII with 121 colours (16 hues × 8 luminances) per character. [M] |
| **PET** | Monochrome, 40 or 80 columns, screen at `$8000`. PETSCII-only. [M] |

## 5. Implications for ISO64

1. **A "PETSCII flavor" fits the architecture.** Render the map to a **semigraphics buffer** (80×50 on the C64), then map each 2×2 block to one of the 16 quarter-block codes above. Colour is one per character.
   - **Same grid:** at this resolution a 2:1 isometric diamond is exactly **8×4 quarter-pixels = 4×2 characters**, the same cell grid as every other ISO64 flavor. So `engine/common` and the map format work unchanged. The quarter-block recipe is in the skill's `references/petscii.md`.
   - **No custom character set:** it needs no tile graphics in RAM beyond small quarter masks per tile, and no character-set memory.
   - **Any Commodore:** it runs on every Commodore with PETSCII, so a **PET** port and an unexpanded or lightly expanded **VIC-20** become feasible.
   - **Cost:** composing an 80×50 buffer and converting it costs far less than the bitmap path, because full redraws are cheap.
2. **PETSCII UI on every flavor.** The side panel, combat log and menus can use the ROM characters directly: no art, no extra memory, and the same text code on every machine (the C128 VDC branch already draws its panel this way).
3. **Tooling.** PETSCII tile stamps (hand-drawn per tile, like PETSCII Robots' 3×3 tiles) could be imported from **Petmate** `.petmate` JSON. petmate9 covers every ISO64 machine, including the VDC.
4. **Shared-map precedent.** PETSCII Robots proves the one-map, many-machines model ISO64 already uses: its maps run unchanged on the PET, VIC-20 and C64.

The backlog items are in [OPPORTUNITIES.md](OPPORTUNITIES.md), section "PETSCII".

[wiki]: https://www.c64-wiki.com/wiki/PETSCII
[paper]: https://research.aalto.fi/en/publications/petscii-a-character-set-and-a-creative-platform/
[bros]: https://setsideb.com/?p=4673
[gb]: https://www.giantbomb.com/attack-of-the-petscii-robots/3030-82368/
[castle]: https://jimbo.itch.io/escape-from-petscii-castle
[digiloi]: https://indieretronews.com/2018/12/digiloi-petscii-game-for-c64-looks.html
[irn]: https://www.indieretronews.com/search/label/PETSCII?m=1
[dd]: https://ko-ko74.itch.io/petscii-dungeons-droids-c64
[lumber]: https://csdb.dk/release/?id=246166
[csdb]: https://csdb.dk/release/?id=245130
[mapedit]: https://www.the8bitguy.com/pr-mapedit
[sdl]: https://morphos.aminet.net/game/misc/PETSCIIRobots-SDL.readme
[petmate]: https://csdb.dk/release/?id=201164
[pm9]: https://theoasisbbs.com/petmate9-petscii-editor-0-9-20-released-for-windows-macos-and-linux/
[ventti]: https://github.com/ventti/petscii
[playscii]: https://www.gamingonlinux.com/2020/01/if-you-want-to-make-some-ascii-art-animations-and-games-check-out-playscii
