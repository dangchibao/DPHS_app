param([ValidateSet('preview','staging')][string]$Channel = 'preview')
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$webRoot = Join-Path $repoRoot 'app/build/web'
$versionLine = Get-Content -LiteralPath (Join-Path $repoRoot 'app/pubspec.yaml') | Where-Object { $_ -match '^version: ' }
if ($versionLine -notmatch '^version: ([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$') { throw 'Version không hợp lệ.' }
$previewVersion, $buildNumber = $Matches[1], $Matches[2]
$built = Get-Content -LiteralPath (Join-Path $webRoot 'version.json') -Raw | ConvertFrom-Json
if ($built.version -ne $previewVersion -or [string]$built.build_number -ne $buildNumber) { throw 'Web build khác version source.' }
$releaseRoot = Join-Path $repoRoot 'artifacts/releases'
$staging = Join-Path $releaseRoot ('web-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $staging -Force | Out-Null
Get-ChildItem -LiteralPath $webRoot | Copy-Item -Destination $staging -Recurse
Copy-Item -LiteralPath (Join-Path $repoRoot 'docs/operations/release-and-cloud-setup.md') -Destination (Join-Path $staging 'RELEASE-INFO.md')
if ($Channel -eq 'staging') {
  Copy-Item -LiteralPath (Join-Path $repoRoot 'docs/operations/staging-access.md') -Destination (Join-Path $staging 'STAGING-ACCESS.md')
}
$manifest = @(Get-ChildItem -LiteralPath $staging -File -Recurse | ForEach-Object {
  [ordered]@{ path = [IO.Path]::GetRelativePath($staging,$_.FullName).Replace('\','/'); bytes = $_.Length; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
})
[IO.File]::WriteAllText((Join-Path $staging 'release-files.sha256.json'), (ConvertTo-Json -InputObject $manifest -Depth 3))
$destination = Join-Path $releaseRoot "ngoc-thanh-web-$previewVersion-$Channel.zip"
Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $destination -CompressionLevel Optimal -Force
$hash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText("$destination.sha256", "$hash  $([IO.Path]::GetFileName($destination))`n")
$archive = [IO.Compression.ZipFile]::OpenRead($destination)
try {
  $entries = @{}
  foreach ($entry in $archive.Entries) { if (!$entry.FullName.EndsWith('/')) { $entries[$entry.FullName.Replace('\','/')] = $entry } }
  if ($entries.Count -ne $manifest.Count + 1) { throw 'ZIP Web thừa/thiếu file.' }
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    foreach ($record in $manifest) {
      $entry = $entries[$record.path]
      if (!$entry -or $entry.Length -ne $record.bytes) { throw 'ZIP Web không khớp manifest.' }
      $stream = $entry.Open()
      try { if ([Convert]::ToHexString($sha.ComputeHash($stream)).ToLowerInvariant() -ne $record.sha256) { throw 'ZIP Web sai checksum file.' } } finally { $stream.Dispose() }
    }
  } finally { $sha.Dispose() }
} finally { $archive.Dispose() }
Write-Output "Đã tạo và xác minh Web ZIP: $destination ($($manifest.Count) file manifest)."
