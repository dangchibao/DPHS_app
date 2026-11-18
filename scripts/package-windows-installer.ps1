param(
  [string]$NsisCompiler = $env:NSIS_COMPILER,
  [string]$TestRoot,
  [ValidatePattern('^\d+\.\d+\.\d+$')][string]$TestVersion
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
if (!$NsisCompiler) { $NsisCompiler = (Get-Command makensis.exe -ErrorAction SilentlyContinue).Source }
if (!$NsisCompiler -or !(Test-Path -LiteralPath $NsisCompiler)) { throw 'Đặt NSIS_COMPILER hoặc -NsisCompiler tới makensis.exe của NSIS 3.13.' }
$NsisCompiler = (Resolve-Path -LiteralPath $NsisCompiler).Path
$compilerVersion = & $NsisCompiler /VERSION
if ($LASTEXITCODE -ne 0 -or $compilerVersion.Trim() -ne 'v3.13') { throw 'Bộ cài được kiểm chứng với NSIS 3.13; cần đúng phiên bản này.' }
$sourceVersion = (Get-Content -LiteralPath (Join-Path $repoRoot 'app/pubspec.yaml') | Where-Object { $_ -match '^version: ' }) -replace '^version: ', ''
if ($sourceVersion -notmatch '^(\d+\.\d+\.\d+)\+(\d+)$') { throw 'Version source không hợp lệ.' }
$version, $buildNumber = $Matches[1], $Matches[2]
$releaseRoot = Join-Path $repoRoot 'artifacts/releases'
$sourceZip = Join-Path $releaseRoot "ngoc-thanh-windows-$version-preview.zip"
$expected = ([IO.File]::ReadAllText("$sourceZip.sha256").Trim() -split '\s+')[0]
if ((Get-FileHash -LiteralPath $sourceZip -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) { throw 'ZIP nguồn sai checksum.' }
$staging = Join-Path $releaseRoot ('installer-' + [Guid]::NewGuid().ToString('N'))
$payload = Join-Path $staging 'payload'
New-Item -ItemType Directory -Path $payload -Force | Out-Null
[IO.Compression.ZipFile]::ExtractToDirectory($sourceZip,$payload)
$manifest = @([IO.File]::ReadAllText((Join-Path $payload 'manifest.json')) | ConvertFrom-Json)
foreach ($record in $manifest) {
  $target = [IO.Path]::GetFullPath((Join-Path $payload $record.path))
  if (!$target.StartsWith($payload + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Manifest có đường dẫn ngoài payload.' }
  if (!(Test-Path -LiteralPath $target -PathType Leaf) -or (Get-Item -LiteralPath $target).Length -ne $record.bytes -or (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -ne $record.sha256) { throw 'Payload sai manifest.' }
}
if ($manifest.Count + 1 -ne @(Get-ChildItem -LiteralPath $payload -Recurse -File).Count) { throw 'Payload có tệp ngoài manifest.' }
foreach ($required in @('msvcp140.dll','vcruntime140.dll','vcruntime140_1.dll','visual-cpp-runtime.json','ngoc_thanh_pos.exe')) {
  if (!(Test-Path -LiteralPath (Join-Path $payload $required))) { throw "ZIP thiếu $required. Đóng gói lại bằng package-preview.ps1." }
}
$installRoot = '$LOCALAPPDATA\Programs\NgocThanhPOSPreview'
$shortcutRoot = '$SMPROGRAMS\Đồng phục Ngọc Thanh — Chạy thử'
$registryKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\NgocThanhPOSPreview'
$mutexName = 'NgocThanhPOSPreviewInstaller'
$output = Join-Path $releaseRoot "ngoc-thanh-windows-$version-setup-preview.exe"
if ($TestRoot) {
  $TestRoot = [IO.Path]::GetFullPath($TestRoot)
  $allowed = [IO.Path]::GetFullPath((Join-Path $repoRoot 'artifacts/installer-tests')) + [IO.Path]::DirectorySeparatorChar
  if (!$TestRoot.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or $TestRoot -match '["$\r\n]') { throw 'TestRoot phải là thư mục riêng trong artifacts/installer-tests.' }
  $testId = [IO.Path]::GetFileName($TestRoot)
  if ($testId -notmatch '^[a-f0-9]{32}$') { throw 'TestRoot cần tên GUID dạng N.' }
  $installRoot = Join-Path $TestRoot 'installed'
  $shortcutRoot = Join-Path $TestRoot 'shortcuts'
  $registryKey = "Software\NgocThanh\InstallerTests\$testId"
  $mutexName = "NgocThanhInstallerTest$testId"
  if ($TestVersion) { $version = $TestVersion }
  New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null
  $output = Join-Path $TestRoot "setup-$version.exe"
} elseif ($TestVersion) { throw 'TestVersion chỉ cho phép với TestRoot riêng.' }
function NsisLiteral([string]$value) { return $value.Replace('$','$$').Replace('"','$\"') }
function WriteUtf8([string]$path,[string[]]$lines) { [IO.File]::WriteAllLines($path,$lines,[Text.UTF8Encoding]::new($false)) }
$config = @(
  '!define VERSION "' + $version + '"'
  '!define FILE_VERSION "' + $version + '.' + $buildNumber + '"'
  '!define OUTPUT_FILE "' + (NsisLiteral $output) + '"'
  '!define INSTALL_ROOT "' + $installRoot + '"'
  '!define SHORTCUT_ROOT "' + $shortcutRoot + '"'
  '!define UNINSTALL_KEY "' + $registryKey + '"'
  '!define MUTEX_NAME "' + $mutexName + '"'
)
WriteUtf8 (Join-Path $staging 'package-config.nsh') $config
$installLines = [Collections.Generic.List[string]]::new()
$uninstallLines = [Collections.Generic.List[string]]::new()
$directories = @(Get-ChildItem -LiteralPath $payload -Directory -Recurse | ForEach-Object { [IO.Path]::GetRelativePath($payload,$_.FullName) } | Sort-Object)
$checks = @($directories | ForEach-Object { '!insertmacro CheckSafeDirectory "$INSTDIR\' + (NsisLiteral $_) + '"' })
WriteUtf8 (Join-Path $staging 'check-directories.nsh') $checks
foreach ($file in Get-ChildItem -LiteralPath $payload -File -Recurse | Sort-Object FullName) {
  $relative = [IO.Path]::GetRelativePath($payload,$file.FullName)
  if ($relative -match '[\r\n]') { throw 'Tên tệp không hợp lệ.' }
  $directory = [IO.Path]::GetDirectoryName($relative)
  $suffix = if ($directory) { '\' + (NsisLiteral $directory) } else { '' }
  $installLines.Add('SetOutPath "$INSTDIR' + $suffix + '"')
  $installLines.Add('File "' + (NsisLiteral $file.FullName) + '"')
  $uninstallLines.Add('Delete "$INSTDIR\' + (NsisLiteral $relative) + '"')
}
foreach ($directory in $directories | Sort-Object Length -Descending) { $uninstallLines.Add('RMDir "$INSTDIR\' + (NsisLiteral $directory) + '"') }
WriteUtf8 (Join-Path $staging 'install-files.nsh') $installLines.ToArray()
WriteUtf8 (Join-Path $staging 'uninstall-files.nsh') $uninstallLines.ToArray()
Copy-Item -LiteralPath (Join-Path $repoRoot 'packaging/windows/setup.nsi') -Destination (Join-Path $staging 'setup.nsi')
Push-Location $staging
try {
  & $NsisCompiler /NOCONFIG /WX /V2 setup.nsi
  if ($LASTEXITCODE -ne 0) { throw 'NSIS biên dịch thất bại.' }
} finally { Pop-Location }
$hash = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText("$output.sha256", "$hash  $([IO.Path]::GetFileName($output))`n")
Write-Output "Đã tạo bộ cài: $output"
