$ErrorActionPreference = 'Stop'

# Bumped by windows/installer/chocolatey/update.sh - keep these three lines in this form.
$version       = '1.3.26'
$checksumX64   = '040B8C3F0A364F94D4F804DDD597EEEDB33B3DE1936983F0A4CF0C7D4A06347B'
$checksumArm64 = 'AEFC4FB17A77BBAAA3B429F4979EC0F02CD5A226A4470370E51986C0257F352C'

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
