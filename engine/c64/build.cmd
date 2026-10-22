@echo off
rem Builds the C64 engine (BASIC SYS stub at $0801) with cc65 -> build\c64\engine.prg
cd /d %~dp0
cl65 -g -t c64 -C c64-asm.cfg -u __EXEHDR__ -l engine.lst -Ln engine.lbl -o engine.prg main.s || exit /b 1
if not exist ..\..\build\c64 mkdir ..\..\build\c64
copy /y engine.prg ..\..\build\c64\engine.prg >nul
