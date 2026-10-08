$ErrorActionPreference = 'Stop'

# Uninstall by the MSI ProductCode found in Programs and Features (it changes every
# release, so it is looked up rather than hard-coded).
[array]$keys = Get-UninstallRegistryKey -SoftwareName 'VietTelex*'

if ($keys.Count -eq 1) {
  $productCode = $keys[0].PSChildName
  Uninstall-ChocolateyPackage -PackageName $env:ChocolateyPackageName -FileType 'msi' `
    -SilentArgs "$productCode /qn /norestart" -ValidExitCodes @(0, 3010, 1605, 1614, 1641) -File ''
} elseif ($keys.Count -eq 0) {
  Write-Warning "$env:ChocolateyPackageName has already been uninstalled by other means."
} else {
  Write-Warning "$($keys.Count) matches found for VietTelex; not uninstalling to be safe:"
  $keys | ForEach-Object { Write-Warning "- $($_.DisplayName) $($_.DisplayVersion) $($_.PSChildName)" }
}
