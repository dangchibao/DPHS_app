param([string]$NsisCompiler = $env:NSIS_COMPILER)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$testId = [Guid]::NewGuid().ToString('N')
$testRoot = Join-Path $repoRoot "artifacts/installer-tests/$testId"
$installed = Join-Path $testRoot 'installed'
$registryPath = "Software\NgocThanh\InstallerTests\$testId"
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
function Assert([bool]$Condition,[string]$Message) { if (!$Condition) { throw $Message } }
function RunSetup([string]$Program,[string[]]$SetupArguments,[int]$ExpectedExit = 0) {
  $process = Start-Process -FilePath $Program -ArgumentList $SetupArguments -WindowStyle Hidden -PassThru
  if (!$process.WaitForExit(60000)) { $process.Kill(); throw 'Bộ cài vượt thời gian thử.' }
  Assert ($process.ExitCode -eq $ExpectedExit) "Exit $($process.ExitCode), cần ${ExpectedExit}: $Program"
}
function RegistryValue([string]$Name) {
  $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($registryPath)
  if (!$key) { return $null }
  try { return $key.GetValue($Name) } finally { $key.Dispose() }
}
function BuildTest([string]$Version) {
  & (Join-Path $PSScriptRoot 'package-windows-installer.ps1') -NsisCompiler $NsisCompiler -TestRoot $testRoot -TestVersion $Version
}
function CheckInstalled {
  $manifest = @([IO.File]::ReadAllText((Join-Path $installed 'manifest.json')) | ConvertFrom-Json)
  foreach ($record in $manifest) {
    $file = Join-Path $installed $record.path
    Assert (Test-Path -LiteralPath $file -PathType Leaf) "Thiếu tệp $($record.path)."
    Assert ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -eq $record.sha256) "Sai hash $($record.path)."
  }
  Assert ((RegistryValue 'InstallLocation') -eq $installed) 'Sai đường dẫn đăng ký.'
  Assert ((RegistryValue 'UninstallString') -eq ('"' + (Join-Path $installed 'uninstall.exe') + '"')) 'Lệnh gỡ cài không được quote đúng.'
  $shortcut = Join-Path $testRoot 'shortcuts/Đồng phục Ngọc Thanh.lnk'
  Assert (Test-Path -LiteralPath $shortcut) 'Thiếu shortcut.'
  # This host's WScript COM converts non-ASCII filenames through ACP. Inspect
  # an identical ASCII-named copy so that the test actually opens the .lnk.
  $inspectionLink = Join-Path $testRoot 'inspect.lnk'
  Copy-Item -LiteralPath $shortcut -Destination $inspectionLink -Force
  $shell = New-Object -ComObject WScript.Shell
  try { Assert ($shell.CreateShortcut($inspectionLink).TargetPath -eq (Join-Path $installed 'ngoc_thanh_pos.exe')) 'Shortcut sai EXE.' }
  finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
}
$fakeData = Join-Path $testRoot 'simulated-userdata'
New-Item -ItemType Directory -Path $fakeData -Force | Out-Null
foreach ($file in @('ngoc_thanh.sqlite','outbox.json','backup-encrypted.zip')) { [IO.File]::WriteAllText((Join-Path $fakeData $file), 'fixture-only-do-not-delete') }
$sentinels = @(Get-ChildItem -LiteralPath $fakeData -File | Get-FileHash -Algorithm SHA256)
BuildTest '0.7.0'
$setup = Join-Path $testRoot 'setup-0.7.0.exe'
$redirect = Join-Path $testRoot 'redirect-target'
New-Item -ItemType Directory -Path $redirect -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $redirect 'keep.txt'),'fixture')
New-Item -ItemType Junction -Path $installed -Target $redirect | Out-Null
RunSetup $setup @('/S') 4
Assert ((RegistryValue 'DisplayVersion') -eq $null) 'Không được đăng ký khi thư mục là junction.'
Assert ([IO.File]::ReadAllText((Join-Path $redirect 'keep.txt')) -eq 'fixture') 'Đã sửa dữ liệu qua junction.'
# Remove the junction itself, without recursion; target stays in this fixture.
Remove-Item -LiteralPath $installed -Force
RunSetup $setup @('/S',('/D=' + (Join-Path $testRoot 'wrong-target')))
Assert (!(Test-Path -LiteralPath (Join-Path $testRoot 'wrong-target'))) '/D đã đổi thư mục cài cố định.'
CheckInstalled
Assert ((RegistryValue 'DisplayVersion') -eq '0.7.0') 'Sai version cài mới.'
[IO.File]::WriteAllText((Join-Path $installed 'user-created.txt'),'keep-user-file')
RunSetup $setup @('/S')
CheckInstalled
Write-Output 'PASS cài mới, manifest/hash/shortcut/registry, sửa chữa, chặn junction và /D.'
$lock = [IO.File]::Open((Join-Path $installed 'ngoc_thanh_pos.exe'),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
try {
  RunSetup $setup @('/S') 3
  RunSetup (Join-Path $installed 'uninstall.exe') @('/S',('_?=' + $installed)) 3
} finally { $lock.Dispose() }
CheckInstalled
Write-Output 'PASS chặn cài/gỡ khi EXE bị khóa, không tự đóng tiến trình.'
BuildTest '0.7.1'
RunSetup (Join-Path $testRoot 'setup-0.7.1.exe') @('/S')
Assert ((RegistryValue 'DisplayVersion') -eq '0.7.1') 'Sai version nâng cấp thử.'
CheckInstalled
RunSetup $setup @('/S') 6
Assert ((RegistryValue 'DisplayVersion') -eq '0.7.1') 'Hạ phiên bản đã thay đổi registry.'
Write-Output 'PASS nâng cấp fixture và chặn hạ phiên bản.'
$manifest = @([IO.File]::ReadAllText((Join-Path $installed 'manifest.json')) | ConvertFrom-Json)
RunSetup (Join-Path $installed 'uninstall.exe') @('/S')
$deadline = [DateTime]::UtcNow.AddSeconds(45)
while ((RegistryValue 'DisplayVersion') -or (Test-Path -LiteralPath (Join-Path $installed 'uninstall.exe'))) {
  if ([DateTime]::UtcNow -gt $deadline) { throw 'Gỡ cài chưa hoàn tất.' }
  Start-Sleep -Milliseconds 200
}
foreach ($record in $manifest) { Assert (!(Test-Path -LiteralPath (Join-Path $installed $record.path))) "Còn tệp cài $($record.path)." }
Assert (!(Test-Path -LiteralPath (Join-Path $installed 'manifest.json'))) 'Còn manifest.'
Assert ([IO.File]::ReadAllText((Join-Path $installed 'user-created.txt')) -eq 'keep-user-file') 'Gỡ cài đã xóa tệp người dùng.'
Assert (!(Test-Path -LiteralPath (Join-Path $testRoot 'shortcuts/Đồng phục Ngọc Thanh.lnk'))) 'Còn shortcut.'
foreach ($sentinel in $sentinels) { Assert ((Get-FileHash -LiteralPath $sentinel.Path -Algorithm SHA256).Hash -eq $sentinel.Hash) 'Đã thay đổi dữ liệu/backup fixture.' }
Write-Output "PASS gỡ tệp chương trình, giữ tệp người dùng/SQLite/outbox/backup fixture. Chỉ thử trong $testRoot"
