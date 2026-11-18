param(
  [switch]$CreateSigningKey,
  [string]$FlutterPath = 'D:/development/flutter/bin/flutter.bat',
  [string]$JavaDirectory = 'D:/jdk21',
  [string]$AndroidSdk = 'C:/Android/Sdk'
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$managedRoot = Join-Path $env:LOCALAPPDATA 'NgocThanhPOSDeployment/android-release'
$keyFile = Join-Path $managedRoot 'ngoc-thanh-release.p12'
$credentialFile = Join-Path $managedRoot 'signing-password.credential.xml'
$keyNames = @('ANDROID_KEYSTORE_PATH','ANDROID_KEYSTORE_PASSWORD','ANDROID_KEY_ALIAS','ANDROID_KEY_PASSWORD')
$saved = @{}
foreach ($name in ($keyNames + @('JAVA_HOME','ANDROID_HOME','ANDROID_REQUIRE_RELEASE_SIGNING'))) { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }
try {
  $present = @($keyNames | Where-Object { ![string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($_)) })
  if ($present.Count -gt 0 -and $present.Count -ne 4) { throw 'Cần đủ bốn biến ký Android; không thay bằng khóa khác.' }
  if ($present.Count -eq 0) {
    if (!(Test-Path -LiteralPath $keyFile)) {
      if (!$CreateSigningKey) { throw 'Chưa có khóa ký. Chỉ dùng -CreateSigningKey khi tạo khóa phát hành đầu tiên trên máy chủ sở hữu.' }
      New-Item -ItemType Directory -Path $managedRoot -Force | Out-Null
      if (!(Test-Path -LiteralPath $credentialFile)) {
        $password = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
        [Management.Automation.PSCredential]::new('ngoc-thanh-release',(ConvertTo-SecureString $password -AsPlainText -Force)) | Export-Clixml -LiteralPath $credentialFile
        $password = $null
      }
      $signing = Import-Clixml -LiteralPath $credentialFile
      $env:ANDROID_KEYSTORE_PASSWORD = $signing.GetNetworkCredential().Password
      $env:ANDROID_KEY_PASSWORD = $env:ANDROID_KEYSTORE_PASSWORD
      & (Join-Path $JavaDirectory 'bin/keytool.exe') -genkeypair -alias ngoc-thanh-release -keyalg RSA -keysize 3072 -validity 10000 -storetype PKCS12 -keystore $keyFile -storepass:env ANDROID_KEYSTORE_PASSWORD -keypass:env ANDROID_KEY_PASSWORD -dname 'CN=Ngoc Thanh POS, O=Ngoc Thanh, C=VN' -noprompt
      if ($LASTEXITCODE -ne 0) { throw 'Không tạo được khóa; giữ nguyên tệp để kiểm tra, không tự ghi đè.' }
    }
    if (!(Test-Path -LiteralPath $credentialFile)) { throw 'Khóa đã có nhưng thiếu mật khẩu được bảo vệ. Không tự tạo lại khóa.' }
    $signing = Import-Clixml -LiteralPath $credentialFile
    $env:ANDROID_KEYSTORE_PATH = $keyFile
    $env:ANDROID_KEYSTORE_PASSWORD = $signing.GetNetworkCredential().Password
    $env:ANDROID_KEY_ALIAS = $signing.UserName
    $env:ANDROID_KEY_PASSWORD = $env:ANDROID_KEYSTORE_PASSWORD
  }
  $env:JAVA_HOME = $JavaDirectory
  $env:ANDROID_HOME = $AndroidSdk
  $env:ANDROID_REQUIRE_RELEASE_SIGNING = '1'
  Push-Location (Join-Path $repoRoot 'app')
  try {
    & $FlutterPath build apk --release
    if ($LASTEXITCODE -ne 0) { throw 'Android build ký phát hành thất bại.' }
  } finally { Pop-Location }
  $tools = Get-ChildItem -LiteralPath (Join-Path $AndroidSdk 'build-tools') -Directory | Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
  $built = Join-Path $repoRoot 'app/build/app/outputs/flutter-apk/app-release.apk'
  $certificateInfo = & (Join-Path $tools.FullName 'apksigner.bat') verify --verbose --print-certs $built
  if ($LASTEXITCODE -ne 0) { throw 'Không xác minh được chữ ký APK.' }
  $details = $certificateInfo | Out-String
  if ($details -match '(?i)CN=Android Debug' -or $details -notmatch 'Verified using v2 scheme.*true') { throw 'APK không có chữ ký release v2 như yêu cầu.' }
  $versionLine = Get-Content -LiteralPath (Join-Path $repoRoot 'app/pubspec.yaml') | Where-Object { $_ -match '^version: ' }
  if ($versionLine -notmatch '^version: (\d+\.\d+\.\d+)\+(\d+)$') { throw 'Version source không hợp lệ.' }
  $version = $Matches[1]
  $releaseRoot = Join-Path $repoRoot 'artifacts/releases'
  New-Item -ItemType Directory -Path $releaseRoot -Force | Out-Null
  $destination = Join-Path $releaseRoot "ngoc-thanh-android-$version-release.apk"
  Copy-Item -LiteralPath $built -Destination $destination -Force
  $hash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
  [IO.File]::WriteAllText("$destination.sha256", "$hash  $([IO.Path]::GetFileName($destination))`n")
  $fingerprint = [regex]::Match($details,'Signer #1 certificate SHA-256 digest: ([a-fA-F0-9]+)').Groups[1].Value.ToLowerInvariant()
  if ($fingerprint.Length -ne 64) { throw 'Không đọc được fingerprint chứng thư ký.' }
  [IO.File]::WriteAllText("$destination.signing.json",(ConvertTo-Json @{ version=$version;certificate_sha256=$fingerprint;debug=$false;apk_sha256=$hash } -Compress))
  Write-Output "Đã build và kiểm chữ ký release: $destination"
  Write-Output 'Giữ an toàn keystore và sao lưu mật khẩu riêng trước khi phân phối. DPAPI chỉ giải mã được bằng tài khoản Windows hiện tại.'
} finally {
  foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name,$saved[$name],'Process') }
}
