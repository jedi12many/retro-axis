@echo off
rem Runs build\c64\engine.prg in VICE with build\c64\ as drive 8 (like the sd2iec folder).
rem Joystick port 2 = numeric keypad (8/2/4/6, diagonals 7/9/1/3, fire 0).
rem "run-vice.cmd reu" adds a 512 KB REU: the REU tier (pre-rendered world, smooth scrolling).
rem Set VICE to your x64sc.exe if it lives somewhere else.
cd /d %~dp0..\..
if "%VICE%"=="" set VICE=%USERPROFILE%\Downloads\GTK3VICE-3.10-win64\GTK3VICE-3.10-win64\bin\x64sc.exe
set REUOPT=
if /i "%1"=="reu" set REUOPT=-reu -reusize 512
start "" "%VICE%" %REUOPT% -drive8type 0 -busdevice8 -fs8 build\c64 -joydev2 1 -autostartprgmode 1 -autostart build\c64\engine.prg
