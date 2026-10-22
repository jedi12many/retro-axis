# VIC-20 cheat-sheet

Sources are in `docs/research/vic20.md`. The engine is described in PLATFORMS.md §6.

## Timing

- **PAL 6561:** 1,108,405 Hz, 71 cycles per line × 312 lines = **22,152 cycles per frame**.
- **NTSC 6560:** 65 × 261 = 16,965 cycles per frame.
- **The VIC steals no CPU cycles**, so cycle counts are exact.
- **There is no raster IRQ.** Poll `$9004` (raster ÷ 2) or sync a VIA timer once. The ISO64 flip polls for `$9004` = 114.

## Memory

| Range | Use |
|---|---|
| `$0000-$03ff` | VIC-visible internal RAM. The KERNAL uses `$0200-$03ff` |
| `$0400-$0fff` | 3K expansion (not VIC-visible) |
| **`$1000-$1fff`** | **VIC-visible**: screens, character set, hot tables |
| `$2000-$7fff` | BLK1–3 (24K expansion) |
| `$8000` | Character ROM |
| `$9000` | VIC |
| `$9110` / `$9120` | VIAs |
| `$9400` / `$9600` | Colour RAM halves |
| `$9c00-$9fff` | I/O3 (cartridge registers) |
| `$a000-$bfff` | BLK5 |

**ISO64 VIC-20 layout:**

| Range | Use |
|---|---|
| `$1000` / `$1200` | Screens A/B, with colour RAM `$9400`/`$9600` (flip = `$9002` bit 7) |
| `$1400-$1bff` | Characters: 0–111 frame A, 112–223 frame B, 224–255 text |
| `$1c00-$1fff` | Masks and hashes |
| `$2000-$34e7` | Code (**~26 bytes free**) |
| `$4000` | Map |
| `$5000-$6beb` | Compose buffers |
| `$7000` | `VTILES` |

## VIC registers

| Reg | Use |
|---|---|
| `$9000` | Bit 7 interlace, bits 0–6 horizontal origin |
| `$9001` | Vertical origin |
| `$9002` | Bit 7 screen/colour half, bits 0–6 columns |
| `$9003` | Bits 1–6 rows, bit 0 = 8×16 characters, bit 7 raster bit 0 |
| `$9005` | Screen base (high nibble) / character base (low nibble). Values 8–15 → RAM `$0000-$1c00`, 0–7 → ROM |
| `$900a-$900d` | Voices + noise |
| `$900e` | Bits 0–3 volume, **bits 4–7 aux colour** (digis must keep them) |
| `$900f` | Screen colour (high), bit 3 inverted mode, border (bits 0–2) |

**Multicolour pixel pairs:** `00` screen, `01` border (0–7), `10` cell colour (colour RAM bits 0–2, bit 3 = multicolour), `11` aux.

## Tricks worth knowing

- **Dynamic character set** (in use): labels + hash. Budget 112 codes per frame.
- **Text from character ROM via a `$9005` split below the viewport:** frees codes 224–255, so the budget becomes 144 (OPPORTUNITIES V-1).
- **8×16 characters:** a true 160×192 bitmap, but no room for double buffering. Not recommended.
- **Raster colour split** for the UI rows (aux/screen colours).
- **`$9000`/`$9001` origin shifts:** move the whole picture in 4-pixel / 2-line steps (a camera ease).

## Big-RAM cartridges (a VIC-20 "big RAM" flavor)

**Final Expansion 3:**
- `$9c02` REG1: mode bits 7–5 (`$a0` = SUPER_RAM), bank bits 0–3 (32 KB banks).
- `$9c03` REG2: bits 0–4 hide blocks, bit 7 hides the registers.
- VICE: `-cartfe`.

**UltiMem:**
- `$9ff0` control, `$9ff1/2` modes, `$9ff3` ID.
- 16-bit bank numbers at `$9ff8` (BLK1), `$9ffa` (BLK2), `$9ffc` (BLK3), `$9ffe` (BLK5).

**Use:** a pre-rendered compose world (~93 KB + 12 KB of colours) could replace `draw_tile` and the scroll copy. Estimated step 229k → ~155k.
