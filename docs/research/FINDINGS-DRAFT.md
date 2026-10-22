# Commodore research: interim findings (draft)

Status: research in progress, cut short by the usage limit. Still to do: the per-system research files (c64.md, ultimate.md, c128.md, vic20.md, plus4-mega65.md), OPPORTUNITIES.md, `.claude/skills/commodore-engine/`, and the `.gitignore` change.

Confidence: **H** = official docs or measured, **M** = secondary source, **L** = recollection or needs checking. 🔧 = needs real hardware to confirm.

## Measured in VICE 3.10 (sources in `vice-tests/`)

**REU on x64sc PAL, 512 KB** (`reu-timing.s`, 1000 bytes, CIA2-timed, 27-cycle overhead already subtracted) — H for VICE:

| Operation | Cycles |
|---|---|
| Stash | 1003 |
| Fetch | 1003 |
| Fetch with the C64 address fixed (fill) | 1003 |
| Fetch with the REU address fixed (fill) | 1003 |
| Verify (equal) | 1003 |
| Swap | 2003 |

- So stash, fetch and verify cost 1 cycle per byte plus about 3 cycles of setup, and swap costs 2 cycles per byte.
- With the screen on, starting at line 60: 1087 cycles. Badlines stall the DMA.
- With the screen on plus 8 sprites: 1508 cycles. Sprite DMA stalls it too.
- REU status after verify was $50: end of block, size bit set, no fault.

**VDC on x128 PAL** (`vdc-timing.s`, 1000 bytes, µs, 53 µs overhead already subtracted) — VICE only 🔧:

| Operation | Time |
|---|---|
| CPU write through register 31, 1 MHz | 31.2 µs/byte |
| CPU write through register 31, 2 MHz | 22.0 µs/byte |
| CPU read through register 31, 1 MHz | 31.2 µs/byte |
| Block fill (register 30) | 0.85 µs/byte |
| Block copy (registers 32/33 → 18/19) | 1.47 µs/byte |

- The 64 KB check works: set register 28 bit 4, write $00 at $0000 and $55 at $8000, then read $0000 back. It reads 1 under `-VDC64KB` and 0 under `-VDC16KB`.
- **Implication for the C128 engine:** CPU byte writes are 20–35× slower than VDC block copy and fill.
  - Keep tile and world data inside VDC RAM, and draw with block copies and fills.
  - Avoid CPU read-modify-write masking on VDC memory.
  - There is no published real-hardware figure for CPU write speed. A Hacker News post estimates about 14 µs/byte at 2 MHz 🔧.
- `detect.s` (what $D030, $D031, $DF00 and $DF1D read on the C64 and on the C128 in C64 mode) was written, but its run did not finish.

## Ultimate 64 / C64 Ultimate (official docs, H)

Source: https://1541u-documentation.readthedocs.io/en/latest/config/turbo_mode.html

**Turbo modes** (firmware ≥ 1.33):
- The menu's Turbo Control setting must be "U64 Turbo Registers" or "TurboEnable Bit". Otherwise the registers below read $FF.
- **$D031:** bits 0–3 are the speed index; bit 7 = 1 disables badline timing.
  - U64 speeds by index: 1, 2, 3, 4, 5, 6, 8, 10, 12, 14, 16, 20, 24, 32, 40, 48 MHz.
  - U64E2 speeds by index: 1, 2, 3, 4, 6, 8, 10, 12, 14, 16, 20, 24, 32, 40, 48, 64 MHz.
- **$D030:** only in TurboEnable mode. Writing bit 0 = 0 gives 1 MHz with badlines; bit 0 = 1 uses the menu speed. This matches the C128's $D030 bit 0.
- **$D07A/$D07B:** SuperCPU-compatible normal/turbo switches.
- **Detection:** $D031 ≠ $FF means turbo registers are enabled (M).
- I/O and external bus accesses always run at 1 MHz.
- The VIC still steals its slots. With badlines disabled, the CPU keeps running during BA=0, but only on internal RAM.
- Turn turbo off around KERNAL LOAD and any cycle-counted code (L 🔧).

**REU at turbo** (GideonZ/1541ultimate issue #839, measured on a U64E, firmware 3.15, NTSC — M 🔧):
- The REU tracks the CPU speed up to 3 MHz, then flattens out: stash about 5 B/µs, fetch about 3.5 B/µs at 48 MHz.
- An unrolled CPU copy at 48 MHz runs at 5.28 B/µs.
- Firmware 3.15 fixed stale REU data for transfers started while in turbo.
- **ISO64 estimate:** at 48 MHz a smooth-scroll frame is about 1.9 ms of DMA plus about 0.15 ms of CPU, leaving about 18 ms of each 20 ms frame free. That's enough for exact software figure masking and animated tiles every frame. A full stock-path viewport render (726k cycles) would take about 15 ms.

**Ultimate Command Interface** (https://1541u-documentation.readthedocs.io/en/latest/uci/core_uci_architecture.html):
- Registers $DF1B–$DF1F. It must be enabled in the menu.
- $DF1D reads $C9 as the identification value.
- Control register $DF1C bits: 0 PUSH_CMD, 1 DATA_ACC, 2 ABORT, 3 CLR_ERR.
- Status bits: 7 DATA_AV, 6 STAT_AV, 5:4 state, 3 ERROR, 0 CMD_BUSY.
- Command bytes go to $DF1D; response data is read from $DF1E and status from $DF1F.
- DOS target $01:
  - OPEN_FILE $02 (attribute 1 = read)
  - READ_DATA $04 (length lo, hi)
  - **LOAD_REU $21 (4-byte address, 4-byte length): loads the open file straight into the REU.** A pre-rendered world could load instantly.
- Control target $04: SET_PALETTE $52 (48 RGB bytes, U64 only). This would allow a per-map custom palette, an Ultimate-only visual option.

**Other Ultimate facts:**
- SIDs: each SID's address is set in the menu, mirrored every 32 bytes. Stereo players expect the second SID at $D420 or $D500. Up to 4 SIDs (2 sockets + 2 UltiSID). Software has to probe for them.
- The Ultimate Audio sampler is mapped at $DF20–$DFFF. No register map found (L).

## Other sources checked

- **Kung Fu Flash** (https://codeberg.org/KimJorgensen/KungFuFlash): disk emulation goes through KERNAL vectors, so fast loaders don't work. **ISO64 must keep using KERNAL LOAD.** It supports EasyFlash, D64/D71/D81 and PRG.
- **Final Expansion 3** (MAME `src/devices/bus/vic20/fe3.h` and `fe3.cpp`): registers $9C02 and $9C03.
  - REG1 ($9C02): bits 7–5 are the mode — START $00, FLASH $20, SUPER_ROM $40, RAM_ROM $60, RAM_1 $80, SUPER_RAM $A0, RAM_2 $C0. Bits 0–3 select one of 16 32 KB banks.
  - REG2 ($9C03): bits 0–4 hide BLK0, 1, 2, 3, 5. Bit 7 hides the registers.
- **UltiMem** (go4retro, M): registers at $9FF0–$9FFF.
  - $9FF1/$9FF2 set per-block modes; $9FF3 is the ID.
  - 16-bit bank registers: $9FF6 (IO), $9FF8 (BLK1), $9FFA (BLK2), $9FFC (BLK3), $9FFE (BLK5).
- **REU registers** (https://codebase.c64.org/doku.php?id=base:reu_programming): the codebase64.org domain is redirected by this machine's network filter, so use codebase.c64.org instead.

## Top opportunities (draft ranking)

1. **Ultimate turbo tier.** $D031 speed set around the draw, turbo off for LOADs. That's about 18 ms free per smooth-scroll frame, which enables exact figure masking and per-frame animated tiles. 🔧 This touches `engine/c64/main.s`: detection plus the `reu_walk` / `flip` path.
2. **EasyFlash/KFF "cartridge world" tier.** The editor pre-renders each world, using its exact `renderMap` already proven by the harness, into the CRT banks. A step then becomes a ROM→bitmap copy of about 4.3 KB, roughly 38k cycles against 175k stock (about 4.5×). It also gives instant loads. VICE can verify it with `-cartcrt`.
3. **Music in a raster IRQ.** The engine runs with IRQs off while drawing, so a player would stutter. Move to an own IRQ handler at $FFFE that stays on during drawing, with music at about line 210 before the line-250 flip. Then add dual-SID stereo on Ultimate with probed addresses.
4. **Sprite multiplexing.** More than 7 visible entities, using raster IRQs inside lines 59–202. Combine it with `$d01b` per-figure priority behind walls on the stock and REU tiers (tile art convention: occluders use pixel pairs 10/11).
5. **NTSC check for the REU smooth scroll.** Each frame needs about 15.6k cycles plus about 1.7k of VIC steal, against 17,095 cycles per NTSC frame, so it probably drops frames. Run the harness with NTSC timing, or lower the speed on NTSC (estimate, M).

Also noted:
- **C128 in C64 mode:** 2 MHz via $D030 in the border lines only. Estimate about 1.3× on the stock path.
- **VIC-20 with UltiMem/FE3:** a pre-rendered compose-cell world would remove `draw_tile` and the scroll copy, about 46% of a step.
- **Stock tier:** self-modifying absolute addressing in the `draw_tile` mask loop, 23 → about 17 cycles per byte.
