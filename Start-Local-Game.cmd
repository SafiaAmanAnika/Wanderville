@echo off
set "WANDERVILLE_API_URL=http://127.0.0.1:8000"
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "code\server\scripts\start_local_game.ps1"
if errorlevel 1 pause
