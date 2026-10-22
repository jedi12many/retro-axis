@echo off
rem Builds the C128 80-column (VDC) engine (BASIC SYS stub at $1c01) -> build\c128\engine.prg
cd /d %~dp0
cl65 -g -t c128 -C c128.cfg -u __EXEHDR__ -l engine.lst -Ln engine.lbl -o engine.prg main.s || exit /b 1
if not exist ..\..\build\c128 mkdir ..\..\build\c128
copy /y engine.prg ..\..\build\c128\engine.prg >nul
