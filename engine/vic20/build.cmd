@echo off
rem Builds the VIC-20 engine (PAL, +32K; SYS stub at $1201, code at $2000) -> build\vic20\engine.prg
cd /d %~dp0
cl65 -g -t vic20 -C vic20.cfg -l engine.lst -Ln engine.lbl -o engine.prg main.s || exit /b 1
if not exist ..\..\build\vic20 mkdir ..\..\build\vic20
copy /y engine.prg ..\..\build\vic20\engine.prg >nul
