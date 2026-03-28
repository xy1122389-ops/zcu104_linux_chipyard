param(
  [string]$OpenOcdExe = "C:\Users\24242\AppData\Local\Microsoft\WinGet\Packages\xpack-dev-tools.openocd-xpack_Microsoft.Winget.Source_8wekyb3d8bbwe\xpack-openocd-0.12.0-7\bin\openocd.exe",
  [string]$OpenOcdScripts = "C:\Users\24242\AppData\Local\Microsoft\WinGet\Packages\xpack-dev-tools.openocd-xpack_Microsoft.Winget.Source_8wekyb3d8bbwe\xpack-openocd-0.12.0-7\openocd\scripts",
  [string]$RepoRoot = "\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga",
  [string]$OutDir = "$env:TEMP\ft4232_sticky_matrix"
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
  $PSNativeCommandUseErrorActionPreference = $false
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Resolve-OpenOcd {
  param([string]$Preferred)
  try {
    $cmd = Get-Command openocd -ErrorAction Stop
    if ($cmd -and $cmd.Source) {
      return $cmd.Source
    }
  } catch {}
  return $Preferred
}

$OpenOcdExe = Resolve-OpenOcd -Preferred $OpenOcdExe
$CmdExe = Join-Path $env:SystemRoot "System32\cmd.exe"

$cfgs = @(
  @{ Name = "custom_serial_1000"; Path = (Join-Path $RepoRoot "scripts\openocd_zcu104_win_custom_serial_1000.cfg") },
  @{ Name = "custom_serial_500";  Path = (Join-Path $RepoRoot "scripts\openocd_zcu104_win_custom_serial_500.cfg") },
  @{ Name = "custom_serial_200";  Path = (Join-Path $RepoRoot "scripts\openocd_zcu104_win_custom_serial_200.cfg") }
)

$localCfgDir = Join-Path $OutDir "cfg"
New-Item -ItemType Directory -Force -Path $localCfgDir | Out-Null

$cfgs = foreach ($cfg in $cfgs) {
  $localCfg = Join-Path $localCfgDir ($cfg.Name + ".cfg")
  Copy-Item -Force -Path $cfg.Path -Destination $localCfg
  @{
    Name = $cfg.Name
    Path = $localCfg
  }
}

$taskKillLog = Join-Path $OutDir "taskkill_hw_server.txt"
$taskKillCmd = "/c taskkill /F /IM hw_server.exe > `"$taskKillLog`" 2>&1"
$taskKillProc = Start-Process -FilePath $CmdExe -ArgumentList $taskKillCmd -NoNewWindow -PassThru -Wait
$taskKillExit = $taskKillProc.ExitCode

$summary = foreach ($cfg in $cfgs) {
  $log = Join-Path $OutDir ($cfg.Name + ".log")
  $stdoutLog = Join-Path $OutDir ($cfg.Name + ".stdout.log")
  $stderrLog = Join-Path $OutDir ($cfg.Name + ".stderr.log")

  $proc = Start-Process -FilePath $OpenOcdExe `
    -ArgumentList @("-s", $OpenOcdScripts, "-f", $cfg.Path) `
    -WorkingDirectory $OutDir `
    -NoNewWindow `
    -PassThru `
    -Wait `
    -RedirectStandardOutput $stdoutLog `
    -RedirectStandardError $stderrLog
  $exitCode = $proc.ExitCode
  @(
    if (Test-Path $stdoutLog) { Get-Content $stdoutLog -Raw }
    if (Test-Path $stderrLog) { Get-Content $stderrLog -Raw }
  ) | Out-File -FilePath $log -Encoding utf8
  $content = Get-Content $log -Raw

  $classification =
    if ($content -match "libusb_open\(\) failed" -or $content -match "unable to open ftdi device") {
      "B_open_device_failed"
    } elseif ($content -match "JTAG-DP STICKY ERROR" -or $content -match "\[uscale\.a53\.0\] Examination failed") {
      "D_a53_examination_failed"
    } elseif ($content -match "tap/device found") {
      "C_jtag_scan_progressed"
    } elseif ($content -match "Hardware thread awareness created" -or $content -match "Listening on port 3333 for gdb connections" -or $content -match "\[uscale\.axi\] Examination succeed") {
      "E_success_or_further_progress"
    } else {
      "UNKNOWN"
    }

  [pscustomobject]@{
    cfg_name = $cfg.Name
    exit_code = $exitCode
    log_path = $log
    classification = $classification
  }
}

$summary | ConvertTo-Json -Depth 4 | Out-File -FilePath (Join-Path $OutDir "summary.json") -Encoding utf8
$summary | Format-Table -AutoSize | Out-File -FilePath (Join-Path $OutDir "summary.txt") -Encoding utf8

Write-Output "OUTDIR=$OutDir"
Write-Output "TASKKILL_EXIT=$taskKillExit"
Get-Content (Join-Path $OutDir "summary.txt")
