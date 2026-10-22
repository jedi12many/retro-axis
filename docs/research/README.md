# Commodore platform research

How to get the most out of each machine ISO64 targets. Each claim carries a confidence mark (H / M / L), and 🔧 marks claims that need real hardware.

| File | Covers |
|---|---|
| [OPPORTUNITIES.md](OPPORTUNITIES.md) | **Start here.** Ranked backlog per flavor: gain, effort, risk, whether VICE can verify it, files it touches |
| [c64.md](c64.md) | Stock VIC-II/SID/CIA, PAL/NTSC timing, REU as a blitter, GeoRAM, EasyFlash/KFF, sd2iec, SuperCPU |
| [ultimate.md](ultimate.md) | Ultimate 64 / C64 Ultimate: turbo registers, Ultimate Command Interface, REU at turbo, SIDs, palette |
| [c128.md](c128.md) | VDC 8563/8568 (measured copy/fill/CPU-access speeds), MMU, 2 MHz, C128 KERNAL, burst loading |
| [vic20.md](vic20.md) | 6561 VIC tricks, every RAM block, UltiMem and Final Expansion 3 banking |
| [plus4-mega65.md](plus4-mega65.md) | Short notes on future flavors |
| [vice-tests/](vice-tests/) | The VICE probes behind the "VICE ✓" numbers (REU timing, VDC timing, machine detection) |

## Re-running the VICE probes

They are built with cc65 and run headless. A monitor breakpoint at the `done` label dumps the results with `bsave`. With `B` set to VICE's `bin` folder:

```bash
cl65 -g -t c64 -C c64-asm.cfg -u __EXEHDR__ -Ln reu.lbl -o reu-timing.prg reu-timing.s
printf 'break <done address from reu.lbl>\ncommand 1 "bsave \\"reu.bin\\" 0 c000 c07f"\n' > mon.txt
"$B/x64sc.exe" -default -pal -reu -reusize 512 -warp +sound -moncommands mon.txt -autostartprgmode 1 -autostart reu-timing.prg
```

`vdc-timing.s` runs the same way: build with `-t c128 -C c128-asm.cfg`, run under `x128 -80col -VDC64KB`, and dump `$1300-$133f`. `detect.s` is built like the REU test, runs under `x64sc` and `x128 -go64`, and dumps `$c000-$c007`. Each source file's header comment explains its result layout.
