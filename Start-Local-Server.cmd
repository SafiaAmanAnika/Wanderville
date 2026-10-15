@echo off
REM Starts the local API so another device on your network can play.
REM Pass --local-only instead if you want it reachable from this machine alone.
cd /d "%~dp0code\server"
".venv312\Scripts\python.exe" scripts\local_development.py --serve --lan
pause