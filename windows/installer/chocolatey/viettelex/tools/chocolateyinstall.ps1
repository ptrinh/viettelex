$ErrorActionPreference = 'Stop'

# Bumped by windows/installer/chocolatey/update.sh - keep these three lines in this form.
$version       = '1.3.18'
$checksumX64   = '2DE2264003B24A501022E7D2A384657CEA8A7797508BE58E15637CACDE4C1B90'
$checksumArm64 = 'B4FA21894C2846677C2830A0602DDC05B32F07B32EDE93CCF8BFCBBAF15AC5E5'

$base = "https://github.com/ptrinh/viettelex/releases/download/windows-v$version"

# Install-ChocolateyPackage only knows 32/64-bit, and there is no 32-bit VietTelex.
# On Windows on ARM choco.exe may run emulated (x64), where PROCESSOR_ARCHITECTURE
# reads AMD64, so take the NATIVE architecture from the machine environment key
# (not WOW-redirected). The ARM64 MSI is required there: it carries the ARM64X
# forwarder that serves both native ARM64 and emulated x64 apps.
$nativeArch = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -Name PROCESSOR_ARCHITECTURE).PROCESSOR_ARCHITECTURE
if ($nativeArch -eq 'ARM64') {
  $url64 = "$base/VietTelex-$version-arm64.msi"; $checksum64 = $checksumArm64
} else {
  $url64 = "$base/VietTelex-$version-x64.msi";   $checksum64 = $checksumX64
}

$packageArgs = @{
  packageName    = $env:ChocolateyPackageName
  fileType       = 'msi'
  url64bit       = $url64
  checksum64     = $checksum64
  checksumType64 = 'sha256'
  softwareName   = 'VietTelex*'
  silentArgs     = "/qn /norestart /l*v `"$($env:TEMP)\$($env:ChocolateyPackageName).$($env:ChocolateyPackageVersion).MsiInstall.log`""
  validExitCodes = @(0, 3010, 1641)
}

Install-ChocolateyPackage @packageArgs
