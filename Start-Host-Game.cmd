@echo off
setlocal
rem The host connects directly; remote friends continue using the ngrok URL.
set "WANDERVILLE_API_URL=http://127.0.0.1:8000"
set "WANDERVILLE_MULTIPLAYER_TRANSPORT=legacy"
set "GODOT_ENET_GAMEPLAY="
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0code\server\scripts\start_local_game.ps1"
endlocal
