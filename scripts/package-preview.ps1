$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$releaseRoot = Join-Path $repoRoot 'app\build\windows\x64\runner\Release'
foreach ($required in @('ngoc_thanh_pos.exe','flutter_windows.dll','data')) {
  if (!(Test-Path -LiteralPath (Join-Path $releaseRoot $required))) { throw "Thiếu $required. Chạy flutter build windows --release trước." }
}
$versionLine = Get-Content -LiteralPath (Join-Path $repoRoot 'app\pubspec.yaml') | Where-Object { $_ -match '^version: ' }
if ($versionLine -notmatch '^version: ([0-9]+\.[0-9]+\.[0-9]+)\+[0-9]+$') { throw 'Version không hợp lệ.' }
$previewVersion = $Matches[1]
$fullVersion = $versionLine -replace '^version: ', ''
$binaryVersion = (Get-Item -LiteralPath (Join-Path $releaseRoot 'ngoc_thanh_pos.exe')).VersionInfo.ProductVersion
if ($binaryVersion -ne $fullVersion) { throw "EXE $binaryVersion khác source $fullVersion. Build lại trước khi đóng gói." }
$latestMigration = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'app\assets\migrations') -Filter '*.sql' | Sort-Object Name | Select-Object -Last 1
if (!(Test-Path -LiteralPath (Join-Path $releaseRoot "data\flutter_assets\assets\migrations\$($latestMigration.Name)"))) { throw 'EXE thiếu migration hiện hành. Build lại trước khi đóng gói.' }
$artifactsRoot = Join-Path $repoRoot 'artifacts\releases'
$stagingRoot = Join-Path $artifactsRoot ('windows-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null
Get-ChildItem -LiteralPath $releaseRoot | Copy-Item -Destination $stagingRoot -Recurse
Copy-Item -LiteralPath (Join-Path $repoRoot 'docs\huong-dan-chay-thu.md') -Destination (Join-Path $stagingRoot 'HUONG-DAN.md')
Copy-Item -LiteralPath (Join-Path $repoRoot 'docs\phases\progress.md') -Destination (Join-Path $stagingRoot 'TIEN-DO.md')
$manifest = @(
  Get-ChildItem -LiteralPath $stagingRoot -File -Recurse | ForEach-Object {
    [ordered]@{ path = [IO.Path]::GetRelativePath($stagingRoot,$_.FullName); bytes = $_.Length; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
  }
)
[IO.File]::WriteAllText((Join-Path $stagingRoot 'manifest.json'), (ConvertTo-Json -InputObject $manifest -Depth 3))
$archivePath = Join-Path $artifactsRoot "ngoc-thanh-windows-$previewVersion-preview.zip"
Compress-Archive -Path (Join-Path $stagingRoot '*') -DestinationPath $archivePath -CompressionLevel Optimal -Force
$checksum = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText("$archivePath.sha256", "$checksum  $([IO.Path]::GetFileName($archivePath))`n")
Write-Output "Đã tạo: $archivePath"
