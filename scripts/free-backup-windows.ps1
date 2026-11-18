param(
  [ValidateSet('Run','Verify','Install','Status')][string]$Mode = 'Run',
  [string]$PythonExecutable,
  [string]$ConfigPath = (Join-Path $PSScriptRoot '../api/wrangler.staging.local.jsonc')
)
$ErrorActionPreference = 'Stop'
$taskName = 'NgocThanhPOS-Free-D1-Backup-Staging'
$deploymentRoot = Join-Path $env:LOCALAPPDATA 'NgocThanhPOSDeployment'
$reportPath = Join-Path $deploymentRoot 'free-d1-backup-status.json'
if ($Mode -eq 'Status') {
  $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
  $info = if ($task) { Get-ScheduledTaskInfo -TaskName $taskName }
  $report = if (Test-Path -LiteralPath $reportPath) { Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json }
  [pscustomobject]@{
    TaskName = $taskName
    TaskState = if ($task) { [string]$task.State } else { 'NotInstalled' }
    LastRunTime = $info.LastRunTime
    NextRunTime = $info.NextRunTime
    LastTaskResult = $info.LastTaskResult
    Backup = $report
  } | ConvertTo-Json -Depth 4
  return
}
if (!$PythonExecutable -or !(Test-Path -LiteralPath $PythonExecutable -PathType Leaf)) {
  throw 'Can duong dan Python 3.12+ thuc, khong dung Windows Store alias.'
}
$resolvedConfig = (Resolve-Path -LiteralPath $ConfigPath).Path
$config = Get-Content -LiteralPath $resolvedConfig -Raw | ConvertFrom-Json
if ($config.name -ne 'ngoc-thanh-pos-staging') { throw 'Lich nay chi danh cho staging da duoc phep.' }
if ($Mode -eq 'Install') {
  if (!(Test-Path -LiteralPath $reportPath)) { throw 'Can chay Run va kiem tra backup thanh cong truoc.' }
  $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
  $targetId = @($config.d1_databases | Where-Object binding -eq 'DB')[0].database_id
  if ($report.status -ne 'success' -or $report.mode -ne 'local_encrypted_no_r2' -or $report.database_id -ne $targetId) {
    throw 'Chua co backup thanh cong dung database; khong cai lich.'
  }
  $drill = Get-Content -LiteralPath (Join-Path $deploymentRoot 'free-d1-backup-restore-drill.json') -Raw | ConvertFrom-Json
  if ($drill.status -ne 'success' -or $drill.database_id -ne $targetId -or $drill.ciphertext_sha256 -ne $report.ciphertext_sha256) {
    throw 'Can dien tap giai ma/restore dung ban backup truoc khi cai lich.'
  }
  if ((Get-FileHash -LiteralPath $report.encrypted_file -Algorithm SHA256).Hash -ine $report.ciphertext_sha256) {
    throw 'Checksum ban backup khong con khop; khong cai lich.'
  }
  $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
  foreach ($path in @($PSCommandPath,$PythonExecutable,$resolvedConfig)) {
    if ($path.Contains('"')) { throw 'Duong dan khong hop le.' }
  }
  $shellPath = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
  $arguments = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Mode Run -PythonExecutable "{1}" -ConfigPath "{2}"' -f $PSCommandPath,$PythonExecutable,$resolvedConfig
  $action = New-ScheduledTaskAction -Execute $shellPath -Argument $arguments -WorkingDirectory (Split-Path $PSScriptRoot -Parent)
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
  if ($existing) {
    if ($existing.Actions.Count -ne 1 -or $existing.Actions[0].Execute -ne $shellPath -or
        !$existing.Actions[0].Arguments.Contains('"' + $PSCommandPath + '"') -or
        $existing.Description -notlike 'Ngoc Thanh staging: encrypted backup*' -or
        [string]$existing.Principal.RunLevel -ne 'Limited' -or [string]$existing.State -eq 'Running') {
      throw 'Task khong khop hoac dang chay; khong thay cau hinh.'
    }
    Set-ScheduledTask -TaskName $taskName -Action $action | Select-Object TaskName,State
    return
  }
  $principal = New-ScheduledTaskPrincipal -UserId $identity -LogonType Interactive -RunLevel Limited
  $triggers = @((New-ScheduledTaskTrigger -Daily -At '02:30'), (New-ScheduledTaskTrigger -AtLogOn -User $identity))
  $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
  Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Trigger $triggers -Settings $settings -Description 'Ngoc Thanh staging: encrypted backup to this Windows PC. No R2, no subscription. Requires logged-in Windows user and network.' | Select-Object TaskName,State
  return
}
$publicKey = Join-Path $deploymentRoot 'cloud-backup-public.asc'
$keyInfo = Get-Content -LiteralPath (Join-Path $deploymentRoot 'cloud-backup-key-info.json') -Raw | ConvertFrom-Json
$oldPath = $env:PATH
$oldMetrics = $env:WRANGLER_SEND_METRICS
$oldCi = $env:CI
$oldPassphrase = $env:NT_BACKUP_KEY_PASSPHRASE
try {
  $gitTools = Join-Path $env:ProgramFiles 'Git/usr/bin'
  if (Test-Path -LiteralPath $gitTools) { $env:PATH = $gitTools + ';' + $oldPath }
  $env:WRANGLER_SEND_METRICS = 'false'
  $env:CI = 'true'
  if ($Mode -eq 'Verify') {
    $credential = Import-Clixml (Join-Path $deploymentRoot 'backup-gpg-passphrase.credential.xml')
    $env:NT_BACKUP_KEY_PASSPHRASE = $credential.GetNetworkCredential().Password
    & $PythonExecutable (Join-Path $PSScriptRoot 'verify_free_backup.py') --report $reportPath --private-key (Join-Path $deploymentRoot 'cloud-backup-private.asc') --proof (Join-Path $deploymentRoot 'free-d1-backup-restore-drill.json')
    if ($LASTEXITCODE -ne 0) { throw 'Dien tap chua dat; khong cong nhan bang chung moi.' }
    return
  }
  & $PythonExecutable (Join-Path $PSScriptRoot 'free_d1_backup.py') --config $resolvedConfig --destination (Join-Path $deploymentRoot 'free-d1-backups') --public-key $publicKey --fingerprint $keyInfo.fingerprint --execute-cloud --report $reportPath
  if ($LASTEXITCODE -ne 0) { throw 'Backup chua thanh cong. Ban cu duoc giu nguyen; xem status report.' }
} finally {
  $env:PATH = $oldPath
  $env:WRANGLER_SEND_METRICS = $oldMetrics
  $env:CI = $oldCi
  $env:NT_BACKUP_KEY_PASSPHRASE = $oldPassphrase
}
