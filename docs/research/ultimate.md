# C64 Ultimate / Ultimate 64 / Ultimate II+: research for ISO64

**The machines, by Gideon Zweijtzer:**
- the **Ultimate 64** (U64) and **Ultimate 64 Elite-II** (U64E2): FPGA C64 boards;
- the **Commodore 64 Ultimate** (C64U, 2025): a complete machine built on the same Elite-II design;
- the **Ultimate II+ / II+L** cartridges, which provide the REU, drive emulation and Command Interface on a real C64.

ISO64's lead target is the fully loaded C64U / U64: REU + turbo + 2 SIDs (PLATFORMS.md §0).

Confidence marks are as in [c64.md](c64.md): H / M / L, 🔧 = real hardware needed, VICE ✓. **VICE emulates none of the Ultimate-specific features**: no turbo, no Command Interface, no UltiSID addressing beyond normal dual-SID. Every turbo claim below needs hardware.

**Primary sources:**
- Ultimate documentation (readthedocs): https://1541u-documentation.readthedocs.io/en/latest/index.html
  - Turbo: https://1541u-documentation.readthedocs.io/en/latest/config/turbo_mode.html
  - Command Interface: https://1541u-documentation.readthedocs.io/en/latest/uci/core_uci_architecture.html, plus `uci/ultimate_dos_target.html` and `uci/control_target.html`
  - U64 manual (older): https://1541u-documentation.readthedocs.io/en/master/_sources/ultimate64-manual.rst.txt
  - MultiSID: https://1541u-documentation.readthedocs.io/en/latest/config/multi_sid.html
- Firmware repository: https://github.com/GideonZ/1541ultimate. The REU-at-turbo measurement is issue #839 (https://github.com/GideonZ/1541ultimate/issues/839); the 2021 developer comment is issue #204.
- C64U specs (community wiki): https://c64u.org/dokuwiki/technical_specifications

---

## 1. Hardware summary

| | Ultimate 64 (Elite) | U64 Elite-II / C64 Ultimate | Ultimate II+ cartridge |
|---|---|---|---|
| CPU | FPGA 6510, turbo to 48 MHz (H) | FPGA 6510, turbo to 64 MHz (H for the U64E2; the C64U is assumed identical, M) | the host C64's 6510 |
| REU | 1750/1764-compatible, up to 16 MB (H) | same; the C64U wiki lists a 16 MB REU (M) | up to 16 MB |
| SIDs | 2 sockets + 2 UltiSID (8 voices of FPGA SID engine, "octal-core" on the C64U) | same | UltiSID in the cartridge |
| Video | HDMI 576p50 / VGA-ish analogue; the C64U does 1080p50/60 (M) | | host VIC-II |
| Storage | USB, SD on the C64U, network | same | USB |

## 2. Turbo modes: how software selects them (H, official docs)

**The menu has to allow it first.** "Turbo Control" in the U64 configuration has four settings:

| Setting | Behaviour |
|---|---|
| Off | Turbo off |
| Manual | Uses the menu speed; registers can't change it |
| **U64 Turbo Registers** | Uses the menu speed; registers *can* change it |
| **TurboEnable Bit** | As above, plus `$d030` bit 0 switches turbo on and off |

**Registers** (U64 firmware ≥ 1.33):

| Address | Name | Available in | Meaning |
|---|---|---|---|
| `$d031` (53297) | U64 Turbo Control | "U64 Turbo Registers" or "TurboEnable Bit"; otherwise reads `$ff` | Bits 0–3: speed index. **Bit 7: 1 = badline timing disabled** (0 = enabled) |
| `$d030` (53296) | Turbo Enable | "TurboEnable Bit" only; otherwise reads `$ff` | Write bit 0: 0 = **1 MHz with badlines**, 1 = use the configured speed. Read bit 0: current state. *The same bit as the C128's 2 MHz switch* |
| `$d07a` / `$d07b` | SuperCPU-compatible | same modes as `$d031`, write-only | `$d07a` = normal speed, `$d07b` = turbo |
| `$d0bc` | SuperCPU detect | read-only, only when separately enabled | |

**Speed index → MHz:**

| Index | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| U64 | 1 | 2 | 3 | 4 | 5 | 6 | 8 | 10 | 12 | 14 | 16 | 20 | 24 | 32 | 40 | 48 |
| U64E2 | 1 | 2 | 3 | 4 | 6 | 8 | 10 | 12 | 14 | 16 | 20 | 24 | 32 | 40 | 48 | 64 |

**What turbo speeds up, and what it doesn't** (H, official docs):
- The U64 has 48 time slots per 1 MHz cycle (the U64E2 has 64). The turbo setting decides how many the CPU gets.
- **Only internal RAM accesses are accelerated.** I/O (`$d000-$dfff`), ROM (KERNAL/BASIC/cartridge) and the external cartridge bus always run at **1 MHz PHI2** and only when BA is high.
  - Every `lda $d012` or `sta $df01` therefore costs a full microsecond.
  - Code that runs from cartridge ROM is not accelerated: the developer confirmed in issue #204 that EasyFlash code at 48 MHz runs at 1 MHz speed.
  - **Copy cartridge code to RAM before running it.**
- The **VIC always keeps its slots**, so the picture stays correct.
  - With badline timing **enabled**, the CPU halts while BA = 0, as on a real C64.
  - With it **disabled** (`$d031` bit 7 = 1), the CPU keeps running during BA = 0, as long as it only touches internal RAM.
- **With physical SID sockets enabled**, SID register accesses obey badline limits too.

**Detection recipe for ISO64** (M; register semantics H, procedure untested 🔧):
1. `$d031 != $ff` means turbo registers are enabled. Read the current index from bits 0–3.
2. Else, if `$d030 != $ff`: on a U64 in "TurboEnable Bit" mode bit 0 is meaningful. **But a C128 in C64 mode also answers `$d030`**: VICE ✓ reads `$fc` on a C128 (`$fd` after writing 1) and `$ff` on a C64. Tell them apart with `$d031` and the UCI ID (§4).
3. Else assume no turbo control.

**Compatibility caveats for ISO64:**
- **KERNAL serial loading under turbo:** the IEC routines contain software delay loops, so turbo may break `LOAD` (L 🔧). Rule: **drop to 1 MHz (`$d031` index 0, or `$d030`=0) around every KERNAL I/O call**, then restore.
- **Raster waits** (`lda $d012 / cmp / bne`) stay correct at any speed. ISO64's flip uses polling, which is safe. Cycle-counted delay code (stable rasters, NOP slides) is not, so the engine must not depend on it while turbo is on.
- **CIA timers** count at 1 MHz regardless of CPU speed: measured in issue #839 ("CIA#2 timer A counts PHI2 regardless of CPU speed"). M
- **Illegal opcodes:** the FPGA 6510 core is believed to implement the stable set. The unstable ones (ANE/LXA, SHx) are unverified. Use only the stable set (L 🔧).

## 3. REU / DMA behaviour at turbo (M, one device measured 🔧)

From GideonZ/1541ultimate issue #839: U64E, firmware 3.15, core 1.4F, **NTSC**, 32 KB transfers, CIA-timed:

| CPU MHz | 1 | 2 | 3 | 4 | 8 | 12 | 16 | 24 | 48 |
|---|---|---|---|---|---|---|---|---|---|
| stash B/µs | 1.02 | 2.04 | 3.06 | 3.97 | 4.08 | 4.08 | 5.09 | 4.85 | 5.14 |
| fetch B/µs | 1.02 | 2.04 | 3.04 | 2.04 | 2.73 | 3.06 | 3.24 | 3.44 | 3.52 |

- **The REU tracks the CPU clock up to 3 MHz, then flattens out**, and not monotonically: fetch is slower at 4 MHz than at 3.
- An unrolled CPU copy at 48 MHz manages 5.28 B/µs, **faster than an REU fetch**.
- The developer (issue #204, 2021): the REU lives in the cartridge clock domain, and "may improve (maybe up to 8 MHz or so)".
- **Firmware 3.15** fixed REU transfers started in turbo returning stale data. **Require firmware ≥ 3.15 for the turbo tier.**

**ISO64 estimates** (derived; real hardware needed):
- **Smooth-scroll frame:** about 6.5k bytes of DMA. At 48 MHz (~3.5 B/µs) that is **~1.9 ms of the 20 ms frame**. The ~6k cycles of CPU work become ~0.13 ms.
  - So **~17–18 ms per frame are free** for exact figure masking, animated tiles and AI.
  - At 4 MHz the fetch rate dips to 2 B/µs, so prefer 3 MHz or ≥ 8 MHz.
- **World build** (5.5M cycles): ~0.12 s at 48 MHz, against 5.6 s stock. Turbo alone removes the map-load wait.
- **Full re-render** of the viewport through the stock path (726k cycles): ~15 ms at 48 MHz. It fits in a frame, so the Ultimate could compose every frame from tiles: animated tiles everywhere, with figures drawn *into* the bitmap.
- With badlines enabled the CPU still halts on badlines (~1.1k µs-slots per frame), which is negligible.

## 4. Ultimate Command Interface (UCI) (H, official docs)

It must be enabled in the menu ("Command Interface"). It occupies **`$df1b-$df1f`**, which masks the last 5 REU registers. ISO64 uses `$df00-$df0a` only, so there's no conflict.

| Addr | Write | Read |
|---|---|---|
| `$df1b` | | SoftwareIEC bus ID |
| `$df1c` | Control: bit 0 PUSH_CMD, 1 DATA_ACC, 2 ABORT, 3 CLR_ERR, 5 IRQ on completion (fw ≥ 3.15), 6 DMA on `$ff00` trigger, 7 DMA immediately | Status: bit 7 DATA_AV, 6 STAT_AV, 5–4 state (00 idle, 01 busy, 10 data last, 11 data more), 3 ERROR, 2 ABORT pending, 1 DATA_ACC, 0 CMD_BUSY |
| `$df1d` | Command data (byte stream) | **Identification: `$c9`** (`$49` with IRQ enabled) |
| `$df1e` | | Response data |
| `$df1f` | | Status data (text such as `00,OK`) |

**Protocol:**
1. Write the command bytes to `$df1d`.
2. Set PUSH_CMD.
3. Poll until the state is no longer busy.
4. Read `$df1e` while DATA_AV is set, and `$df1f` while STAT_AV is set.
5. Set DATA_ACC.

Queues: command 896 B, response 896 B, status 256 B.

**Commands useful to ISO64** (target byte first):

| Bytes | Effect |
|---|---|
| `$01 $02 $01 <name>` | DOS: open a file for reading |
| `$01 $04 lo hi` | DOS: read up to 64 KB. Data streams through `$df1e` in ≤ 512-byte chunks, so ~8 cycles per byte for a CPU read loop, **~100 KB/s at 1 MHz**, far faster than IEC |
| `$01 $21 a0 a1 a2 a3 l0 l1 l2 l3` | **DOS LOAD_REU: put the open file straight into REU memory.** A pre-rendered world (121 KB) could land in the REU without passing through C64 RAM |
| `$01 $22 …` | DOS SAVE_REU |
| `$01 $11 <dir>` | Change directory |
| `$01 $26 [fmt]` | Real-time clock as text |
| `$04 $28 $00` / `$04 $28 $01` | Hardware info: model name ("ULTIMATE 64") / SID configuration. Deprecated, but useful to identify the board |
| `$04 $52 <48 RGB bytes>` | **Set the VIC palette** (U64 family only). A per-map custom palette is possible on the Ultimate tier |
| `$04 $53 i r g b` / `$04 $54` | Set one palette colour / reset the palette |

**Ultimate detection, all three together:**
- `$df1d` reads `$c9` (UCI enabled);
- `$04 $28 $00` returns the model;
- `$d031` behaves as described in §2.

## 5. SIDs and audio

- **Addressing** (H, U64 manual):
  - Each socket and each UltiSID gets an address range in the menu, mirrored every 32 bytes within its range.
  - Use exactly `$d400` for the primary SID.
  - "Many stereo SID programs expect the second SID at `$d420` or `$d500`."
  - Up to 4 SIDs / 12 voices.
  - MultiSID can split UltiSIDs on address lines A5–A8 (e.g. `$d400` / `$d420` / `$d440` …).
- **Software cannot set SID addresses.** The engine must **probe** them (c64.md §6). Try `$d420`, `$d500`, `$de00`, `$df00`; note that `$df00` collides with the REU, so skip it when an REU is present.
- **Ultimate Audio module:** sampled voices mapped at `$df20-$dfff` when enabled. Older docs say 7 voices, 8- or 16-bit, up to 48 kHz. **No register map found** (the U2+ docs point to `ultimate_audio_v0.2.pdf` in the firmware repo). L 🔧
- **Socket SIDs at turbo** obey badline limits, as above.

## 6. Video extras and caveats

- **Palette:** settable through UCI (`$04 $52`). No other new video modes are documented. The VIC-II is FPGA-exact, so FLI and the other tricks work.
- **HDMI:** 576p50 on the U64; the C64U does 1080p. Older manuals said NTSC was "not fully implemented"; newer firmware supports 60 Hz (M).
- **Interlace and flicker tricks** look worse on modern displays.
- **VSP:** the FPGA VIC/DRAM has no analogue crash mechanism, so VSP is believed safe on the U64 (L 🔧). Irrelevant while ISO64 avoids it.

## 7. What this means for ISO64

1. **Turbo tier** (OPPORTUNITIES U-1):
   - Detect via `$d031` and `$df1d`.
   - Run at 48/64 MHz with badline timing off **while composing** (internal RAM only).
   - Drop to 1 MHz around KERNAL `LOAD` and any `$d0xx` busy loop where precision matters (none currently).
   - The REU walk then has ~18 ms per frame free: draw figures *into* the window with exact masks, and animate tiles every frame.
2. **Instant world:** with turbo the build drops to ~0.1 s, so UCI `LOAD_REU` of an editor-made world is only worth it for Ultimate owners who keep turbo off.
3. **Fast data loads:** UCI file reads replace KERNAL LOAD on the Ultimate (~100 KB/s against ~1 KB/s).
4. **Stereo music:** probe the second SID; use a GoatTracker 2 Stereo player.
5. **Optional per-map palette** through UCI. This changes the look, so it has to be a flavor feature with its own preview, which the editor-preview rule requires.

**Hardware checklist for the user** (cannot be done in VICE):
- [ ] `$d031` read values in each Turbo Control mode, and whether bit 7 reads back.
- [ ] KERNAL `LOAD` from the Ultimate's IEC drive at 48 MHz: works or fails?
- [ ] REU fetch rate at 48/64 MHz on PAL, compared with issue #839's NTSC numbers.
- [ ] `$df1d` = `$c9` with UCI on; `$04 $28 $00` model string on the C64U.
- [ ] Stable illegal opcodes (LAX/SAX/DCP/SBX) give the same results as on a real 6510.
