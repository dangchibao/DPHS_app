param([ValidateSet('windows','chrome','web-server','android')][string]$Target = 'windows', [string]$DeviceId)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$envPath = Join-Path $repoRoot '.env'
if (Test-Path -LiteralPath $envPath) {
  foreach ($line in Get-Content -LiteralPath $envPath) {
    if ($line -match '^([A-Z_]+)=(.*)$') { [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process') }
  }
}
$flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
$flutterPath = if ($flutterCommand) { $flutterCommand.Source } elseif (Test-Path 'D:\development\flutter\bin\flutter.bat') { 'D:\development\flutter\bin\flutter.bat' } else { throw 'Chưa tìm thấy Flutter. Thêm Flutter SDK vào PATH.' }
Push-Location (Join-Path $repoRoot 'api')
try {
  if (!(Test-Path 'node_modules')) { & npm.cmd ci; if ($LASTEXITCODE) { throw 'npm ci thất bại' } }
  & npm.cmd run migrate:local
  if ($LASTEXITCODE) { throw 'Migration API thất bại' }
  if ($env:BOOTSTRAP_PASSWORD) {
    [System.IO.File]::WriteAllText((Join-Path $repoRoot 'api\.dev.vars'), "BOOTSTRAP_PASSWORD=$($env:BOOTSTRAP_PASSWORD)`n")
  }
  $apiProcess = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c npm.cmd run dev' -WorkingDirectory (Join-Path $repoRoot 'api') -WindowStyle Hidden -PassThru
} finally { Pop-Location }
Push-Location (Join-Path $repoRoot 'app')
try {
  & $flutterPath pub get
  if ($LASTEXITCODE) { throw 'flutter pub get thất bại' }
  $deviceTarget = if ($DeviceId) { $DeviceId } else { $Target }
  if ($Target -eq 'android' -and !$DeviceId) {
    $availableDevices = & $flutterPath devices --machine | ConvertFrom-Json
    if ($LASTEXITCODE) { throw 'Không đọc được thiết bị Flutter.' }
    $androidDevices = @($availableDevices | Where-Object { $_.targetPlatform -like 'android*' })
    if ($androidDevices.Count -ne 1) { throw 'Cần kết nối đúng một máy Android hoặc truyền -DeviceId theo flutter devices.' }
    $deviceTarget = $androidDevices[0].id
  }
  $runArguments = @('run','-d',$deviceTarget)
  if ($Target -in @('chrome','web-server')) { $runArguments += @('--web-port','8080') }
  & $flutterPath @runArguments
  if ($LASTEXITCODE) { throw 'Không chạy được Flutter.' }
} finally {
  Pop-Location
  if ($apiProcess -and !$apiProcess.HasExited) { & taskkill /PID $apiProcess.Id /T /F 2>$null | Out-Null }
}
