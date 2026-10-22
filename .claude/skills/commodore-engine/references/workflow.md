# Build, test, VICE and Windows quirks

## Build (cc65 on PATH; `cl65` V2.19)

| Machine | Command | Output |
|---|---|---|
| C64 | `engine/c64/build.cmd` | `build/c64/engine.prg`: BASIC SYS stub at `$0801`, uses `c64-asm.cfg` + `-u __EXEHDR__` |
| VIC-20 | `engine/vic20/build.cmd` | `build/vic20/engine.prg`: load address `$11ff`, stub at `$1201`, code at `$2000` (`vic20.cfg`; the MAIN segment size is fixed by the labels above it) |

The `.cmd` files are cmd.exe batch files. From Git Bash, run them with `cmd //c "engine\\c64\\build.cmd"`. In PowerShell, run them directly. Each also writes `engine.lst` and `engine.lbl` next to `main.s`, which give label addresses for VICE breakpoints.

New probes or tools: build them with `cl65 -g -t <c64|c128|vic20> -C <target>-asm.cfg -u __EXEHDR__ -Ln x.lbl`. The `-g` flag is needed so local labels appear in the `.lbl` file.

## Tests (Node, no dependencies)

| Command | What it does |
|---|---|
| `node test/engine-test.js` | C64: the full move script, run twice: stock (`$de00+` reads open bus) and with a 512 KB REU model. Every frame is compared with the editor preview, and the REU walk on every animation frame at `ssh` 1 and 0. Also writes the demo set into `build/c64/` |
| `node test/vic20-test.js` | VIC-20: 40 key moves + 10 joystick moves. Screen codes, colour RAM and character use are checked against `editor/vic20.js` |
| `node test/profile.js upright` | C64 per-routine cycles for one step |
| `node test/profile.js vic20 d` | VIC-20 profile of one step |

Environment variables:
- `ISO64_REU=0|1`: run one C64 tier only.
- `ISO64_SSH=0|1`: REU walk speed.
- `ISO64_KEYS=wasd...`: replay these keys and dump the shown frame to `test/out/emu.png`.

The harness counts cycles, page-cross penalties included. It does **not** model VIC-II cycle stealing (badlines ~1.1k per frame over the viewport, sprites up to ~0.6k), so add that by hand when budgeting.

The editor's renderer is the reference. The harness loads `editor/index.html` / `editor/vic20.js` logic, so when the picture changes, the editor changes first.

## VICE 3.10

Location: `%USERPROFILE%\Downloads\GTK3VICE-3.10-win64\GTK3VICE-3.10-win64\bin\`, which contains `x64sc.exe`, `x128.exe`, `xvic.exe`, `xplus4.exe` and `xscpu64.exe`. The manual is `..\doc\vice.pdf`; `pdftotext` is available.

Running the engines:
- `engine/c64/run-vice.cmd`: stock C64. `run-vice.cmd reu` adds `-reu -reusize 512`. Drive 8 = `build/c64` as a directory device (`-drive8type 0 -busdevice8 -fs8 build\c64`). Joystick port 2 = numeric keypad.
- `engine/vic20/run-vice.cmd`: `xvic -pal -memory 24k +drive8truedrive -trapdevice8 -fs8 build\vic20`.

Useful options:

| Option | Effect |
|---|---|
| `-default` | Ignore saved settings (reproducible runs) |
| `-warp +sound` | Fast, silent |
| `-pal` / `-ntsc` | Video standard |
| `-reu -reusize 128…16384` | REU |
| `-georam -georamsize` | GeoRAM |
| `-cartcrt x.crt` | EasyFlash and other CRTs |
| `-sidextra 1 -sid2address 0xd420` | Second SID |
| `x128 -80col -VDC64KB` / `-VDC16KB` | C128 with 64 KB or 16 KB VDC RAM |
| `x128 -go64` | C128 in C64 mode |
| `xvic -memory 24k` / `all` / `3,5` | VIC-20 RAM blocks |
| `-cartfe` | Final Expansion 3 |
| `-limitcycles N` | Stop after N cycles |
| `-exitscreenshot out.png` | Screenshot on exit |
| `-moncommands file` | Run monitor commands at start |
| `-remotemonitor` | Text monitor on TCP 6510, for scripted drivers |

**Headless measurement pattern** (used by `docs/research/vice-tests/`):
- The program stores its results and then loops at a `done:` label.
- The monitor command file contains:
  ```
  break <done address from the .lbl>
  command 1 "bsave \"out.bin\" 0 c000 c07f"
  ```
- Run with a `timeout` wrapper and read `out.bin` with `od -A x -t x1`.
- Run VICE with its working directory set to where `out.bin` should land. Relative paths avoid quoting Windows backslashes inside monitor strings.

Time with CIA2 timer A (`$dd04/5`, free-running, `$dd0e = $11`). It counts PHI2, so it measures real 1 MHz cycles even when a C128 runs at 2 MHz (and on the Ultimate in turbo).

What VICE can't show:
- Ultimate turbo (`$d030/$d031`), the Command Interface, UltiSID addressing;
- the VSP crash;
- real VDC access timing (VICE's model may differ).

Mark these 🔧 and ask the user for a hardware check.

## Windows quirks on this machine

- **Shells:** the primary shell is PowerShell, and the Bash tool is Git Bash. Use POSIX syntax in Bash (`/dev/null`, `$VAR`) and run `.cmd` files through `cmd //c`. The `start ""` in the run scripts returns immediately, so VICE keeps running detached.
- **Python:** the console code page isn't UTF-8. Printing `✓`, `→` or box characters can raise `UnicodeEncodeError`. Use `python -X utf8 script.py` or set `PYTHONUTF8=1`, and open files with `encoding="utf-8"`.
- **Long paths:**
  - Worktrees live under `C:\Users\dilla\retro-axis\.claude\worktrees\<name>\`, which is already ~60 characters before repo paths.
  - Windows' 260-character `MAX_PATH` can break tools on deep paths (`test/out/...`, node modules, scratch directories).
  - Keep generated paths short; `git config core.longpaths true` helps git itself.
  - Scratch output can go in the session scratchpad or `%TEMP%`.
- **Line endings:** git warns "LF will be replaced by CRLF". That's harmless; the assembler and Node accept both.
- **The network filter** redirects `codebase64.org` to a warning page. Use the mirror https://codebase.c64.org/ instead.

## Git conventions

- Each session works on its own branch or worktree. Don't touch other platforms' files.
- Commit in logical steps.
- Use `gh` for PRs (repo `jedi12many/retro-axis`, main branch `main`).
- `.gitignore` ignores `.claude/*` except `.claude/skills/`, so this skill is versioned with the repo.
