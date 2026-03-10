param(
  [string]$CompanyCode = "U4HHP"
)

$ErrorActionPreference = "Stop"

Write-Host "SoftEgg Windows smoke packaging start" -ForegroundColor Cyan

Push-Location (Join-Path $PSScriptRoot "..")
try {
  & flutter analyze
  if ($LASTEXITCODE -ne 0) {
    throw "flutter analyze 실패"
  }

  & flutter test
  if ($LASTEXITCODE -ne 0) {
    throw "flutter test 실패"
  }

  & dart run tool/smoke_real_packaging.dart $CompanyCode
  if ($LASTEXITCODE -ne 0) {
    throw "스모크 패키징 실패"
  }

  & flutter build windows --debug
  if ($LASTEXITCODE -ne 0) {
    throw "Windows debug build 실패"
  }

  Write-Host "SoftEgg Windows smoke packaging completed" -ForegroundColor Green
}
finally {
  Pop-Location
}
