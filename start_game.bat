@echo off
rem ============================================
rem  Crystal Cavern Gunner launcher
rem  Double-click to start the game.
rem ============================================
setlocal
set "GODOT=D:\godot\Godot_v4.7.2-stable_win64.exe"
set "GAME_DIR=D:\game1"

if not exist "%GODOT%" (
    echo [ERROR] Godot engine not found:
    echo   %GODOT%
    echo Please edit start_game.bat and fix the GODOT path.
    pause
    exit /b 1
)

if not exist "%GAME_DIR%\project.godot" (
    echo [ERROR] Game project not found:
    echo   %GAME_DIR%
    echo Please edit start_game.bat and fix the GAME_DIR path.
    pause
    exit /b 1
)

start "" "%GODOT%" --path "%GAME_DIR%"
endlocal