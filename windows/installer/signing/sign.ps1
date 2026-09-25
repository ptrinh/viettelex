<#
.SYNOPSIS
  Authenticode-sign files with Azure Trusted Signing (spec §10, decision #5).

.DESCRIPTION
  No secrets live in this repository. Everything comes from the environment (CI
  secrets / a developer's own shell):

    VTX_SIGN_ENDPOINT      e.g. https://weu.codesigning.azure.net
    VTX_SIGN_ACCOUNT       Trusted Signing account name
    VTX_SIGN_PROFILE       certificate profile name
    VTX_SIGN_DLIB          path to Azure.CodeSigning.Dlib.dll
                           (NuGet package Microsoft.Trusted.Signing.Client)
    VTX_SIGNTOOL           optional path to signtool.exe (default: from the Windows SDK)
    Authentication: DefaultAzureCredential — AZURE_TENANT_ID / AZURE_CLIENT_ID /
    AZURE_CLIENT_SECRET for a service principal in CI, or `az login` locally.

  Without these variables the script exits with code 2 and signs nothing, so unsigned
  local builds keep working.

.EXAMPLE
  ./sign.ps1 build-x64/Release/VietTelexTIP.dll build-x64/Release/VietTelex.exe
#>
param([Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)][string[]]$Files)

$ErrorActionPreference = 'Stop'
foreach ($v in 'VTX_SIGN_ENDPOINT', 'VTX_SIGN_ACCOUNT', 'VTX_SIGN_PROFILE', 'VTX_SIGN_DLIB') {
    if (-not [Environment]::GetEnvironmentVariable($v)) {
        Write-Warning "sign.ps1: $v not set — skipping signing (unsigned build)."
        exit 2
    }
}

$signtool = $env:VTX_SIGNTOOL
if (-not $signtool) {
    $kits = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    $signtool = Get-ChildItem -Path $kits -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\x64\\' } | Sort-Object FullName -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $signtool -or -not (Test-Path $signtool)) { throw 'signtool.exe not found (install the Windows SDK)' }

# metadata.json is generated per run from the environment (template: metadata.template.json).
$metadata = Join-Path ([IO.Path]::GetTempPath()) "vtx-sign-$PID.json"
@{
    Endpoint               = $env:VTX_SIGN_ENDPOINT
    CodeSigningAccountName = $env:VTX_SIGN_ACCOUNT
    CertificateProfileName = $env:VTX_SIGN_PROFILE
} | ConvertTo-Json | Set-Content -Path $metadata -Encoding UTF8

try {
    & $signtool sign /v /fd SHA256 /tr 'http://timestamp.acs.microsoft.com' /td SHA256 `
        /dlib $env:VTX_SIGN_DLIB /dmdf $metadata @Files
    if ($LASTEXITCODE -ne 0) { throw "signtool failed ($LASTEXITCODE)" }
    & $signtool verify /pa /v @Files
    if ($LASTEXITCODE -ne 0) { throw "signature verification failed ($LASTEXITCODE)" }
} finally {
    Remove-Item -Force $metadata -ErrorAction SilentlyContinue
}
