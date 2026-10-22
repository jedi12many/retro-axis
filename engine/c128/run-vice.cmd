@echo off
rem Runs build\c128\engine.prg in VICE (x128): C128 mode, 80-column (VDC) output with
rem 64 KB of VDC RAM, build\c128\ as drive 8 (like the sd2iec folder).
rem Keys as on the C64; joystick port 2 = numeric keypad.
rem Set X128 to your x128.exe if it lives somewhere else.
cd /d %~dp0..\..
if "%X128%"=="" set X128=%USERPROFILE%\Downloads\GTK3VICE-3.10-win64\GTK3VICE-3.10-win64\bin\x128.exe
start "" "%X128%" -80col -VDC64KB -drive8type 0 -busdevice8 -fs8 build\c128 -joydev2 1 -autostartprgmode 1 -autostart build\c128\engine.prg
