param([Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version, [Parameter(Mandatory)][ValidateRange(1,9999)][int]$Schema, [switch]$CompareBuiltExe, [switch]$RequireRuntime, [switch]$Installer)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$releaseRoot = Join-Path $repoRoot 'artifacts/releases'
$migrationFile = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'app/assets/migrations') -Filter ('{0:D4}_*.sql' -f $Schema) | Select-Object -First 1
if (!$migrationFile) { throw 'Không tìm thấy schema cần kiểm tra.' }
$zipPath = Join-Path $releaseRoot "ngoc-thanh-windows-$Version-preview.zip"
$apkPath = Join-Path $releaseRoot "ngoc-thanh-android-$Version-preview.apk"
$releaseFiles = @($zipPath,$apkPath)
if ($Installer) {
  $setupPath = Join-Path $releaseRoot "ngoc-thanh-windows-$Version-setup-preview.exe"
  if ((Get-Item -LiteralPath $setupPath).VersionInfo.FileVersion -ne $Version) { throw 'Sai phiên bản bộ cài.' }
  $releaseFiles += $setupPath
}
foreach ($file in $releaseFiles) {
  $expected = ([IO.File]::ReadAllText("$file.sha256").Trim() -split '\s+')[0]
  if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) { throw "Checksum sai: $file" }
}
$sha = [Security.Cryptography.SHA256]::Create()
function StreamHash($entry) {
  $stream = $entry.Open()
  try { return [Convert]::ToHexString($sha.ComputeHash($stream)).ToLowerInvariant() } finally { $stream.Dispose() }
}
$archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
try {
  $entries = @{}
  foreach ($entry in $archive.Entries) { if (!$entry.FullName.EndsWith('/')) { $entries[$entry.FullName.Replace('\','/')] = $entry } }
  $reader = [IO.StreamReader]::new($entries['manifest.json'].Open())
  try { $manifest = @($reader.ReadToEnd() | ConvertFrom-Json) } finally { $reader.Dispose() }
  if ($entries.Count -ne $manifest.Count + 1) { throw 'ZIP có file thừa hoặc thiếu manifest' }
  if ($RequireRuntime) {
    foreach ($required in @('msvcp140.dll','vcruntime140.dll','vcruntime140_1.dll','visual-cpp-runtime.json','VISUAL-CPP-RUNTIME.md')) {
      if (!$entries.ContainsKey($required)) { throw "ZIP thiếu runtime: $required" }
    }
  }
  foreach ($record in $manifest) {
    $entry = $entries[$record.path.Replace('\','/')]
    if (!$entry -or $entry.Length -ne $record.bytes -or (StreamHash $entry) -ne $record.sha256) { throw "ZIP không khớp: $($record.path)" }
  }
  $migration = "data/flutter_assets/assets/migrations/$($migrationFile.Name)"
  $sourceHash = (Get-FileHash -LiteralPath $migrationFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
  if ((StreamHash $entries[$migration]) -ne $sourceHash) { throw 'Migration trong ZIP sai' }
  if ($CompareBuiltExe) {
  $builtExeHash = (Get-FileHash -LiteralPath (Join-Path $repoRoot 'app/build/windows/x64/runner/Release/ngoc_thanh_pos.exe') -Algorithm SHA256).Hash.ToLowerInvariant()
  if ((StreamHash $entries['ngoc_thanh_pos.exe']) -ne $builtExeHash) { throw 'EXE trong ZIP khác bản đã build' }
  }
  Write-Output "ZIP: $($manifest.Count) file manifest khớp hash/length; schema $Schema và EXE theo manifest đã xác minh."
} finally { $archive.Dispose() }
$archive = [IO.Compression.ZipFile]::OpenRead($apkPath)
try {
  $migration = $archive.GetEntry("assets/flutter_assets/assets/migrations/$($migrationFile.Name)")
  if (!$migration -or (StreamHash $migration) -ne $sourceHash) { throw 'Migration trong APK sai' }
  foreach ($abi in @('arm64-v8a','armeabi-v7a','x86_64')) {
    if (!$archive.GetEntry("lib/$abi/libapp.so")) { throw "APK thiếu $abi" }
  }
  Write-Output "APK: schema $Schema và 3 kiến trúc đã xác minh; checksum ZIP/APK đạt."
} finally { $archive.Dispose(); $sha.Dispose() }
