$ErrorActionPreference = 'Stop'

function Copy-WindowsRuntime([string]$Destination) {
  $repoRoot = Split-Path $PSScriptRoot -Parent
  $runtimeDirectory = $env:WINDOWS_VC_REDIST_DIR
  if (!$runtimeDirectory) {
    $cache = Join-Path $repoRoot 'app/build/windows/x64/CMakeCache.txt'
    $instance = Get-Content -LiteralPath $cache | Where-Object { $_ -match '^CMAKE_GENERATOR_INSTANCE:INTERNAL=' } | Select-Object -First 1
    if (!$instance) { throw 'Không tìm thấy Visual Studio của bản build. Đặt WINDOWS_VC_REDIST_DIR tới thư mục CRT x64 redistributable.' }
    $visualStudio = $instance.Substring($instance.IndexOf('=') + 1)
    $redist = Join-Path $visualStudio 'VC/Redist/MSVC'
    $runtimeDirectory = Get-ChildItem -LiteralPath $redist -Directory | Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } | Sort-Object { [version]$_.Name } -Descending | ForEach-Object {
      Get-ChildItem -LiteralPath (Join-Path $_.FullName 'x64') -Directory -Filter 'Microsoft.VC*.CRT' -ErrorAction SilentlyContinue
    } | Select-Object -First 1 -ExpandProperty FullName
  }
  if (!$runtimeDirectory -or $runtimeDirectory -match 'debug_nonredist|onecore') { throw 'Phải dùng Visual C++ CRT x64 redistributable, không dùng debug/onecore.' }
  $runtimeDirectory = (Resolve-Path -LiteralPath $runtimeDirectory).Path
  foreach ($required in @('msvcp140.dll','vcruntime140.dll','vcruntime140_1.dll')) {
    if (!(Test-Path -LiteralPath (Join-Path $runtimeDirectory $required))) { throw "CRT thiếu $required." }
  }
  $records = @(foreach ($file in Get-ChildItem -LiteralPath $runtimeDirectory -File -Filter '*.dll') {
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    if ($bytes.Length -lt 64 -or [BitConverter]::ToUInt16($bytes,0) -ne 0x5a4d) { throw "CRT không phải PE: $($file.Name)." }
    $pe = [BitConverter]::ToInt32($bytes,60)
    if ($pe -lt 64 -or $pe + 6 -gt $bytes.Length -or [BitConverter]::ToUInt32($bytes,$pe) -ne 0x4550 -or [BitConverter]::ToUInt16($bytes,$pe+4) -ne 0x8664) { throw "CRT không phải x64: $($file.Name)." }
    $signature = Get-AuthenticodeSignature -LiteralPath $file.FullName
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation,') { throw "CRT không có chữ ký Microsoft hợp lệ: $($file.Name)." }
    Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $Destination $file.Name)
    [ordered]@{ file = $file.Name; version = $file.VersionInfo.FileVersion; sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
  })
  if ($records.Count -lt 3) { throw 'CRT redistributable không đầy đủ.' }
  [IO.File]::WriteAllText((Join-Path $Destination 'visual-cpp-runtime.json'), (ConvertTo-Json -InputObject $records -Depth 3))
  Copy-Item -LiteralPath (Join-Path $repoRoot 'docs/operations/windows-runtime.md') -Destination (Join-Path $Destination 'VISUAL-CPP-RUNTIME.md')
  Write-Output "Đã thêm $($records.Count) DLL Visual C++ x64 có chữ ký Microsoft."
}
