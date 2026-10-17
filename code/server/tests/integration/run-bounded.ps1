<#
  Runs a pytest selection under a hard wall-clock deadline with an external
  watchdog, so a hanging suite is killed rather than blocking the caller.

  Usage (from the repository root):

      powershell -File code/server/tests/integration/run-bounded.ps1 `
          -TimeoutSeconds 600 -PytestArgs "-q","tests/integration/test_x.py"

  Prints the pytest exit status, the watchdog verdict, and any leaked PIDs.
  Nothing outside the pytest process tree is ever signalled.
#>
param(
    [int]$TimeoutSeconds = 600,
    [string[]]$PytestArgs = @("-q", "-p", "no:randomly")
)

$ErrorActionPreference = "Stop"
$repo = Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")
$server = Join-Path $repo "code\server"
$log = Join-Path $env:TEMP ("wanderville-pytest-{0}.log" -f (Get-Date -Format "HHmmss"))

$env:WANDERVILLE_TEST_PIDFILE = Join-Path $env:TEMP "wanderville_test_pids.txt"
$env:WANDERVILLE_TEST_PROCESS_LIFETIME = "120"
$env:WANDERVILLE_TEST_READY_TIMEOUT = "90"
$env:WANDERVILLE_TEST_BACKEND_TIMEOUT = "90"

Write-Host "[bounded] log    : $log"
Write-Host "[bounded] timeout : ${TimeoutSeconds}s"
Write-Host "[bounded] args    : $($PytestArgs -join ' ')"

$python = Join-Path $server ".venv312\Scripts\python.exe"
$pytestArgs = @("-m", "pytest") + $PytestArgs
$proc = Start-Process -FilePath $python -ArgumentList $pytestArgs `
    -WorkingDirectory $server -PassThru -NoNewWindow `
    -RedirectStandardOutput $log -RedirectStandardError "$log.err"
Write-Host "[bounded] pytest pid: $($proc.Id)"

$watchdog = Start-Process -FilePath $python `
    -ArgumentList @("tests/integration/watchdog.py", "--pid", $proc.Id,
        "--timeout", "$TimeoutSeconds") `
    -WorkingDirectory $server -PassThru -NoNewWindow `
    -RedirectStandardOutput "$log.watch" -RedirectStandardError "$log.watch.err"

$sw = [System.Diagnostics.Stopwatch]::StartNew()
while (-not $proc.HasExited -and $sw.Elapsed.TotalSeconds -lt ($TimeoutSeconds + 30)) {
    Start-Sleep -Seconds 5
}

if (-not $proc.HasExited) {
    Write-Host "[bounded] pytest did not exit; terminating its tree"
    & taskkill /T /F /PID $proc.Id | Out-Null
}
$watchdog.WaitForExit(30000) | Out-Null
$status = $proc.ExitCode

Write-Host "[bounded] pytest exit : $status"
Write-Host "[bounded] elapsed     : $([int]$sw.Elapsed.TotalSeconds)s"
Write-Host "[bounded] watchdog    :"
if (Test-Path "$log.watch") { Get-Content "$log.watch" | ForEach-Object { "    $_" } }
Write-Host "[bounded] tail of pytest output:"
if (Test-Path $log) { Get-Content $log -Tail 25 | ForEach-Object { "    $_" } }
exit $status