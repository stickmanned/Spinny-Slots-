$ErrorActionPreference = 'Stop'
$verifyScript = Join-Path $PSScriptRoot 'verify.ps1'
& $verifyScript -Export
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
