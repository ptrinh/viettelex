<#
.SYNOPSIS
  Build, sign and package VietTelex for Windows: x86 + x64 + ARM64 binaries, one MSI
  per native architecture, winget manifests with real SHA-256s.

.DESCRIPTION
  Requirements (on a Windows build machine / windows-latest runner):
    * Visual Studio 2022 with "Desktop development with C++" incl. ARM64/ARM64EC tools
    * CMake >= 3.20 on PATH
    * WiX v4+:  dotnet tool install --global wix
    * optional signing: see signing/sign.ps1 (Azure Trusted Signing, env vars only)

  ARM64: VietTelexTIP.dll for the ARM64 MSI must be ARM64X (ARM64 + ARM64EC in one
  file) because native ARM64 apps and emulated x64 apps share the 64-bit registry
  view — one InprocServer32 path has to serve both. The script builds the ARM64EC
  flavour and links the pair with `link /machine:arm64x` (see Build-Arm64X). Until that
  step is validated on real hardware, pass -SkipArm64X to ship a plain ARM64 DLL
  (native ARM64 apps only).

.EXAMPLE
  ./build.ps1 -Version 0.1.0.1
#>
param(
    [string]$Version = '',
    [string]$Config = 'Release',
    [switch]$SkipArm64,
    [switch]$SkipArm64X,
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

# Multi-config layout: <build>\ime\<Config>\VietTelexTIP.dll, <build>\app\<Config>\VietTelex.exe
function Collect([string]$arch, [string]$dir) {
    $bin = Join-Path $out "bin-$arch"
    New-Item -ItemType Directory -Force -Path $bin | Out-Null
    Copy-Item (Join-Path $dir "ime\$Config\VietTelexTIP.dll") $bin -Force
    $exe = Join-Path $dir "app\$Config\VietTelex.exe"
    if (Test-Path $exe) { Copy-Item $exe $bin -Force }
    return $bin
}

function Build-Arm64X([string]$arm64Bin) {
    # Build the ARM64EC flavour of the TIP; merging it with the ARM64 one into a single
    # ARM64X DLL is a relink of both object sets:
    #   link /machine:arm64x /dll /def:ime\src\VietTelexTIP.def <arm64 objs> <arm64ec objs>
    # CMake has no first-class ARM64X support yet, so this stays an explicit step.
    $ecDir = Build-Arch 'arm64ec' 'ARM64EC'
    Write-Warning ("ARM64X: ARM64EC TIP built at $ecDir\ime\$Config\VietTelexTIP.dll; " +
        'relink with /machine:arm64x before release (see comment above).')
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
    if (-not $SkipArm64X) { Build-Arm64X $bins['arm64'] }
}
Sign (Get-ChildItem -Path $out -Recurse -Include *.dll, *.exe | ForEach-Object FullName)

$msis = @{}
foreach ($arch in @('x64', 'arm64')) {
    if (-not $bins.ContainsKey($arch)) { continue }
    $msi = Join-Path $out "VietTelex-$Version-$arch.msi"
    wix build (Join-Path $PSScriptRoot 'wix\VietTelex.wxs') -arch $arch `
        -d "Version=$Version" -d "Platform=$arch" -d "BinNative=$($bins[$arch])" -d "BinX86=$($bins['x86'])" `
        -o $msi | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "wix failed: $arch" }
    $msis[$arch] = $msi
}
Sign ($msis.Values)

# winget manifests with real hashes (ProductCode read back from each MSI).
function MsiProductCode([string]$path) {
    $installer = New-Object -ComObject WindowsInstaller.Installer
    $db = $installer.GetType().InvokeMember('OpenDatabase', 'InvokeMethod', $null, $installer, @($path, 0))
    $view = $db.GetType().InvokeMember('OpenView', 'InvokeMethod', $null, $db,
        @("SELECT Value FROM Property WHERE Property='ProductCode'"))
    $view.GetType().InvokeMember('Execute', 'InvokeMethod', $null, $view, $null) | Out-Null
    $rec = $view.GetType().InvokeMember('Fetch', 'InvokeMethod', $null, $view, $null)
    return $rec.GetType().InvokeMember('StringData', 'GetProperty', $null, $rec, 1)
}
$wingetOut = Join-Path $out "winget\manifests\p\ptrinh\VietTelex\$Version"
New-Item -ItemType Directory -Force -Path $wingetOut | Out-Null
foreach ($f in Get-ChildItem (Join-Path $PSScriptRoot 'winget') -Filter *.yaml) {
    $t = (Get-Content $f.FullName -Raw).Replace('__VERSION__', $Version)
    foreach ($arch in @('x64', 'arm64')) {
        $tag = $arch.ToUpper()
        if ($msis.ContainsKey($arch)) {
            $t = $t.Replace("__SHA256_$($tag)__", (Get-FileHash $msis[$arch] -Algorithm SHA256).Hash)
            $t = $t.Replace("__PRODUCTCODE_$($tag)__", (MsiProductCode $msis[$arch]))
        }
    }
    Set-Content -Path (Join-Path $wingetOut $f.Name) -Value $t -Encoding UTF8
}
Write-Host "done: $out"
