<#
.SYNOPSIS
Builds the Opus decoder extension for the Godot client on Windows.

.DESCRIPTION
Godot has no Opus decoder of its own, so the client needs one. This builds
it from source: the official Xiph release of libopus and the official Godot
bindings, both pinned, so nothing is taken on trust from a third party build.

The libraries are written to bin/ under the names the .gdextension file
expects, one for the editor and debug exports and one for release exports.
The client never depends on them being there: it only asks the server for
Opus when the decoder actually loaded, so a build without it keeps using raw
PCM.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File build.ps1
#>
param(
    [ValidateSet("Debug", "Release", "Both")]
    [string]$Configuration = "Both",
    [int]$Jobs = 0
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$bin = Join-Path $here "bin"

function Find-CMake {
    $found = Get-Command cmake -ErrorAction SilentlyContinue
    if ($found) {
        return $found.Source
    }
    # A cmake installed with pip is just as good, and many machines already
    # have one inside a Python environment.
    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python) {
        $probe = & $python.Source -c "import cmake, os; print(os.path.join(os.path.dirname(cmake.__file__), 'data', 'bin', 'cmake.exe'))" 2>$null
        if ($probe -and (Test-Path -LiteralPath $probe)) {
            return $probe
        }
    }
    throw "cmake was not found. Install it, or run: pip install cmake ninja"
}

$cmake = Find-CMake
Write-Host "cmake: $cmake"

# Ninja is preferred, but it is not required: without it the default
# generator of the platform is used, which is slower but works.
$generator = @()
if (Get-Command ninja -ErrorAction SilentlyContinue) {
    $generator = @("-G", "Ninja")
} elseif (Test-Path -LiteralPath (Join-Path $here "..\..\..\server\.venv312\Scripts\ninja.exe")) {
    $generator = @("-G", "Ninja")
    $env:PATH = (Split-Path -Parent (Join-Path $here "..\..\..\server\.venv312\Scripts\ninja.exe")) + ";" + $env:PATH
}

if ($Jobs -le 0) {
    $Jobs = [Environment]::ProcessorCount
}

$targets = switch ($Configuration) {
    "Debug" { @("template_debug") }
    "Release" { @("template_release") }
    "Both" { @("template_debug", "template_release") }
}

New-Item -ItemType Directory -Force -Path $bin | Out-Null

foreach ($target in $targets) {
    $build = Join-Path $here "build/$target"
    Write-Host "Configuring $target in $build"
    & $cmake -S $here -B $build @generator `
        -DCMAKE_BUILD_TYPE=Release `
        -DGODOTCPP_TARGET=$target `
        -DOPUS_BUILD_TESTING=OFF `
        -DOPUS_INSTALL=OFF
    if ($LASTEXITCODE -ne 0) {
        throw "cmake failed for $target"
    }
    Write-Host "Building $target"
    & $cmake --build $build -j $Jobs
    if ($LASTEXITCODE -ne 0) {
        throw "the build failed for $target"
    }
    $source = Get-ChildItem -Path $build -Filter "libwanderville_opus.dll" -Recurse |
        Where-Object { $_.DirectoryName -eq $build } |
        Select-Object -First 1
    if (-not $source) {
        $source = Get-ChildItem -Path $build -Filter "libwanderville_opus.dll" -Recurse | Select-Object -First 1
    }
    if (-not $source) {
        throw "the build produced no library for $target"
    }
    $destination = Join-Path $bin "libwanderville_opus.windows.$target.x86_64.dll"
    Copy-Item -LiteralPath $source.FullName -Destination $destination -Force
    Write-Host "Wrote $destination"
}

Write-Host "Done. The client picks the extension up from native/opus/bin."
