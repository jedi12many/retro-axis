@echo off
rem Runs build\vic20\engine.prg in VICE (xvic): PAL VIC-20, 24K in blocks 1-3,
rem build\vic20\ as drive 8 (like the sd2iec folder). Keys and joystick as on the C64.
rem Set XVIC to your xvic.exe if it lives somewhere else.
cd /d %~dp0..\..
if "%XVIC%"=="" set XVIC=%USERPROFILE%\Downloads\GTK3VICE-3.10-win64\GTK3VICE-3.10-win64\bin\xvic.exe
start "" "%XVIC%" -pal -memory 24k +drive8truedrive -trapdevice8 -fs8 "%CD%\build\vic20" -autostartprgmode 1 -autostart "%CD%\build\vic20\engine.prg"
