$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
$flutterPath = if ($flutterCommand) { $flutterCommand.Source } else { 'D:\development\flutter\bin\flutter.bat' }
Push-Location (Join-Path $repoRoot 'api')
try {
  & npm.cmd run lint; if ($LASTEXITCODE) { throw 'API lint lỗi' }
  & npm.cmd run typecheck; if ($LASTEXITCODE) { throw 'TypeScript lỗi' }
  & npm.cmd test; if ($LASTEXITCODE) { throw 'API test lỗi' }
} finally { Pop-Location }
Push-Location (Join-Path $repoRoot 'app')
try {
  & $flutterPath analyze; if ($LASTEXITCODE) { throw 'Flutter analyze lỗi' }
  & $flutterPath test; if ($LASTEXITCODE) { throw 'Flutter test lỗi' }
} finally { Pop-Location }
