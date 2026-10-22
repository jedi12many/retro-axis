# Ultimate 64 / C64 Ultimate cheat-sheet

Sources are in `docs/research/ultimate.md` (official docs: https://1541u-documentation.readthedocs.io/). **VICE emulates none of this**, so every turbo or Command Interface result needs a real-hardware check (🔧).

## Turbo

The menu's "Turbo Control" must be set to **U64 Turbo Registers** or **TurboEnable Bit**. Otherwise the registers read `$ff`.

| Reg | Meaning |
|---|---|
| `$d031` | Bits 0–3 speed index; **bit 7 = 1 disables badline timing** |
| `$d030` | Bit 0 (TurboEnable mode only): 0 = 1 MHz with badlines, 1 = menu speed. The same bit as the C128's 2 MHz switch |
| `$d07a` / `$d07b` | SuperCPU-style normal / turbo |

**Speed index → MHz:**

| Index | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| U64 | 1 | 2 | 3 | 4 | 5 | 6 | 8 | 10 | 12 | 14 | 16 | 20 | 24 | 32 | 40 | 48 |
| U64E2 / C64U | 1 | 2 | 3 | 4 | 6 | 8 | 10 | 12 | 14 | 16 | 20 | 24 | 32 | 40 | 48 | 64 |

**Rules:**
- **Only internal RAM is accelerated.** I/O, ROM and the cartridge bus stay at 1 µs per access. Copy code out of cartridge ROM before running it.
- The VIC keeps its slots. With badline timing off, the CPU runs on during BA=0, but only on internal RAM.
- **Drop to 1 MHz around KERNAL `LOAD`**: the serial routines contain delay loops (🔧).
- `$d012` polling stays correct at any speed. Cycle-counted delays do not.
- CIA timers keep counting PHI2 (1 MHz).
- Require firmware ≥ 3.15, which fixed stale REU data for transfers started in turbo.

**Detection:**
- `$d031 != $ff` means turbo registers are on.
- `$df1d == $c9` means the Command Interface is on.
- `$d030` alone is ambiguous: a C128 in C64 mode reads `$fc`/`$fd` there (VICE ✓), a C64 reads `$ff`.

## REU at turbo (one NTSC U64E measured, issue #839)

- The REU follows the CPU clock up to 3 MHz, then flattens out:
  - ~5 B/µs stash and ~3.5 B/µs fetch at 48 MHz;
  - at 4 MHz the fetch rate is *lower* (2 B/µs).
- A CPU copy at 48 MHz runs at 5.3 B/µs.

**ISO64 at 48 MHz:**
- The walk needs ~1.9 ms of DMA + ~0.15 ms of CPU per 20 ms frame, so ~17 ms are free for exact figure masking, animated tiles and AI.
- The world build takes ~0.1 s.

## Ultimate Command Interface (`$df1b-$df1f`, enable it in the menu)

| Reg | Write | Read |
|---|---|---|
| `$df1c` | Control: bit 0 push command, 1 data accepted, 2 abort, 3 clear error | Status: bit 7 data available, 6 status available, 5–4 state (0 idle, 1 busy, 2 last, 3 more), 3 error, 0 busy |
| `$df1d` | Command bytes | ID `$c9` |
| `$df1e` | | Data |
| `$df1f` | | Status text |

**Flow:**
1. Write the bytes to `$df1d`.
2. Set `$df1c` bit 0.
3. Wait until the state is not busy.
4. Read `$df1e` while bit 7 is set, and `$df1f` while bit 6 is set.
5. Set `$df1c` bit 1.

**Commands:**

| Bytes | Command |
|---|---|
| `$01 $02 $01 name` | Open for reading |
| `$01 $04 lo hi` | Read (~100 KB/s with a CPU read loop) |
| `$01 $03` | Close |
| `$01 $21 addr32 len32` | **LOAD_REU**: open file → REU |
| `$01 $11 dir` | Change directory |
| `$04 $28 $00` | Model name |
| `$04 $52 + 48 bytes` | **Set palette** |
| `$04 $54` | Reset palette |

## SIDs

- SID addresses are set in the menu only; software must probe them.
- The usual second-SID addresses are `$d420` and `$d500`. Other candidates are `$de00`, and `$df00` (which clashes with the REU).
- Up to 2 sockets + 2 UltiSIDs. Socket SIDs obey badline limits in turbo.
- The Ultimate Audio sampler at `$df20-$dfff` exists, but no register map has been found.

## Feature plan for the "C64 Ultimate" flavor

The ranking is in OPPORTUNITIES.md:
1. turbo tier;
2. exact figure masking;
3. stereo music;
4. Command Interface fast loads;
5. optional per-map palette.

Each needs the Ultimate preview in the editor to show it.
