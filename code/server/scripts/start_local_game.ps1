param([string]$GodotPath = $env:GODOT_EXE)
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$env:WANDERVILLE_API_URL = 'http://127.0.0.1:8000'
try {
    $ready = Invoke-RestMethod 'http://127.0.0.1:8000/ready' -TimeoutSec 5
} catch {
    Write-Host 'Start Start-Local-Server.cmd first, then run this launcher again.'
    exit 1
}
if (-not $GodotPath) {
    $command = Get-Command godot, godot4 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { $GodotPath = $command.Source }
}
if (-not $GodotPath) {
    $savedPath = Join-Path $repoRoot 'code\server\.local-postgres\godot-path.txt'
    if (Test-Path -LiteralPath $savedPath) { $GodotPath = (Get-Content -LiteralPath $savedPath -Raw).Trim() }
}
if (-not $GodotPath -or -not (Test-Path -LiteralPath $GodotPath)) {
    Write-Host 'Set GODOT_EXE to your Godot executable path and run again.'
    exit 1
}
# This is an interactive game window explicitly requested by the launcher.
& $GodotPath --path (Join-Path $repoRoot 'code\client')
