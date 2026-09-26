<#
.SYNOPSIS
  MSVC build of VietTelex on Windows: x86 + x64 + ARM64 (with ARM64X forwarder)
  binaries for local testing. Release MSIs come from windows/scripts/release.sh (macOS).

.DESCRIPTION
  Requirements (on a Windows build machine / windows-latest runner):
    * Visual Studio 2022 with "Desktop development with C++" incl. ARM64/ARM64EC tools
    * CMake >= 3.20 on PATH
    * optional signing: see signing/sign.ps1 (Azure Trusted Signing, env vars only)

  ARM64 (v1): the ARM64 MSI ships an ARM64X pure-forwarder VietTelexTIP.dll plus the two
  real DLLs it forwards to — VietTelexTIP_arm64.dll (native ARM64 apps) and
  VietTelexTIP_x64.dll (emulated x64 apps, = the x64 build renamed). The forwarder is
  linked automatically by CMake in the ARM64 tree (/MACHINE:ARM64X, see
  ime/CMakeLists.txt); this script only gathers the files and checks the machine types.

.EXAMPLE
  ./build.ps1 -Version 0.1.0.1
#>
param(
    [string]$Version = '',
    [string]$Config = 'Release',
    [switch]$SkipArm64,
    [switch]$NoSign
)

$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')        # windows/
$out = Join-Path $root 'dist'
New-Item -ItemType Directory -Force -Path $out | Out-Null

if (-not $Version) {
    $h = Get-Content (Join-Path $root 'ime\version.h') -Raw
    $Version = [regex]::Match($h, 'VTX_VER_STRING "([0-9.]+)"').Groups[1].Value
}
Write-Host "VietTelex $Version"

function Build-Arch([string]$arch, [string]$cmakeArch) {
    $dir = Join-Path $root "..\build-$arch"
    cmake -S $root -B $dir -A $cmakeArch -DVTX_BUILD_TESTS=OFF -DVTX_IME_TESTS=OFF | Out-Host
    cmake --build $dir --config $Config --parallel | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "build failed: $arch" }
    return $dir
}

# Multi-config layout: <build>\ime\<Config>\*.dll, <build>\app\<Config>\VietTelex.exe
function Collect([string]$arch, [string]$dir) {
    $bin = Join-Path $out "bin-$arch"
    New-Item -ItemType Directory -Force -Path $bin | Out-Null
    Get-ChildItem (Join-Path $dir "ime\$Config") -Filter 'VietTelexTIP*.dll' | Copy-Item -Destination $bin -Force
    $exe = Join-Path $dir "app\$Config\VietTelex.exe"
    if (Test-Path $exe) { Copy-Item $exe $bin -Force }
    return $bin
}

# `dumpbin /headers` machine line, e.g. "AA64 machine (ARM64) (ARM64X)".
function Machine([string]$file) {
    $dumpbin = Get-Command dumpbin.exe -ErrorAction SilentlyContinue
    if (-not $dumpbin) { return $null }
    return (& $dumpbin.Source /nologo /headers $file | Select-String 'machine \(' | Select-Object -First 1).Line
}

function Complete-Arm64([string]$arm64Bin, [string]$x64Bin) {
    # Emulated-x64 half of the forwarder = the x64 TIP, renamed.
    Copy-Item (Join-Path $x64Bin 'VietTelexTIP.dll') (Join-Path $arm64Bin 'VietTelexTIP_x64.dll') -Force
    foreach ($f in 'VietTelexTIP.dll', 'VietTelexTIP_arm64.dll', 'VietTelexTIP_x64.dll', 'VietTelex.exe') {
        if (-not (Test-Path (Join-Path $arm64Bin $f))) { throw "ARM64 package incomplete: $f missing" }
    }
    $m = Machine (Join-Path $arm64Bin 'VietTelexTIP.dll')
    if ($m -and $m -notmatch 'ARM64X') { throw "VietTelexTIP.dll is not ARM64X: $m" }
    if ($m) { Write-Host "ARM64 forwarder: $m" }
}

function Sign([string[]]$files) {
    if ($NoSign) { return }
    & (Join-Path $PSScriptRoot 'signing\sign.ps1') @files
    if ($LASTEXITCODE -eq 2) { Write-Warning 'unsigned build' }
}

$bins = @{}
$bins['x86'] = Collect 'x86' (Build-Arch 'x86' 'Win32')
$bins['x64'] = Collect 'x64' (Build-Arch 'x64' 'x64')
if (-not $SkipArm64) {
    $bins['arm64'] = Collect 'arm64' (Build-Arch 'arm64' 'ARM64')
    Complete-Arm64 $bins['arm64'] $bins['x64']
}
Sign (Get-ChildItem -Path $out -Recurse -Include *.dll, *.exe | ForEach-Object FullName)

# MSIs are built on macOS by windows/scripts/release.sh (wixl, registry-table
# registration generated from ime/core/registration.h, jsign signing). This script only
# produces MSVC-built, optionally signed binaries in dist/bin-<arch> for local testing.
Write-Host "done: $out (binaries only; MSIs: windows/scripts/release.sh)"
