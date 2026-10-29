@echo off
setlocal
rem Uses the existing .env and database; does not reset mail or worker settings.
cd /d "%~dp0code\server"
powershell.exe -NoProfile -Command "if (Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue) { exit 10 }"
if errorlevel 1 goto occupied
"C:\Program Files\PostgreSQL\18\bin\pg_ctl.exe" status -D "%CD%\.local-postgres\data" >nul 2>&1
if errorlevel 1 (
    "C:\Program Files\PostgreSQL\18\bin\pg_ctl.exe" start -D "%CD%\.local-postgres\data" -l "%CD%\.local-postgres\postgres.log" -o "-h 127.0.0.1 -p 5434" -w
    if errorlevel 1 goto failed
)
rem Live presence needs only one API worker. Keep positions in memory.
set "PRESENCE_BACKEND=memory"
".venv312\Scripts\python.exe" -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --workers 1 --no-access-log
if errorlevel 1 goto failed
endlocal
exit /b 0

:occupied
echo.
echo Port 8000 already has a server running. Stop that API before starting another.
echo In its terminal, press Ctrl+C. Do not kill PostgreSQL processes.
powershell.exe -NoProfile -Command "Get-NetTCPConnection -LocalPort 8000 -State Listen | Select-Object LocalAddress,LocalPort,OwningProcess"
pause
exit /b 1

:failed
echo.
echo Server startup failed. Read the error above.
pause
exit /b 1
