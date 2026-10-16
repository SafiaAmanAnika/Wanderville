@echo off
setlocal
rem Starts the headless Godot multiplayer server against a running backend.
rem
rem Required before launching (Start-Local-Server.cmd):
rem   MULTIPLAYER_BRIDGE_SECRET  must match the backend's value
rem
rem Optional:
rem   GODOT_MULTIPLAYER_PORT     UDP port, default 24567
rem   GODOT_MULTIPLAYER_BIND     interface to bind, default 0.0.0.0
rem   MULTIPLAYER_BRIDGE_URL     backend base url, default http://127.0.0.1:8000

set "GODOT_EXE=%GODOT_EXE%"
if not defined GODOT_EXE (
    if exist "%~dp0code\server\.local-postgres\godot-path.txt" (
        set /p GODOT_EXE=<"%~dp0code\server\.local-postgres\godot-path.txt"
    )
)

if not defined MULTIPLAYER_BRIDGE_SECRET (
    echo [Start-Local-Multiplayer-Server] MULTIPLAYER_BRIDGE_SECRET is not set.
    echo The server cannot authenticate anybody without it, so it will refuse to start.
    echo Set it to the same value the backend is using.
    exit /b 2
)

if not defined GODOT_EXE (
    echo [Start-Local-Multiplayer-Server] Godot executable not found.
    echo Set GODOT_EXE to your Godot 4.6 executable.
    exit /b 2
)

echo [Start-Local-Multiplayer-Server] Godot:  %GODOT_EXE%
echo [Start-Local-Multiplayer-Server] Port:   %GODOT_MULTIPLAYER_PORT% (default 24567)
echo [Start-Local-Multiplayer-Server] Bridge: %MULTIPLAYER_BRIDGE_URL% (default http://127.0.0.1:8000)
echo [Start-Local-Multiplayer-Server] Ready file: %GODOT_MULTIPLAYER_READY_FILE%
echo.

cd /d "%~dp0code\client"
"%GODOT_EXE%" --headless --path . res://Scenes/network/DedicatedServer.tscn %*
endlocal