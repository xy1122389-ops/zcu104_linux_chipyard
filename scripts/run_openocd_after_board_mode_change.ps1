param(
  [string]$OpenOcdExe = "C:\Users\24242\AppData\Local\Microsoft\WinGet\Packages\xpack-dev-tools.openocd-xpack_Microsoft.Winget.Source_8wekyb3d8bbwe\xpack-openocd-0.12.0-7\bin\openocd.exe",
  [string]$OpenOcdScripts = "C:\Users\24242\AppData\Local\Microsoft\WinGet\Packages\xpack-dev-tools.openocd-xpack_Microsoft.Winget.Source_8wekyb3d8bbwe\xpack-openocd-0.12.0-7\openocd\scripts",
  [string]$RepoRoot = "\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga",
  [string]$OutDir = "$env:TEMP\ft4232_boardmode_check"
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

$cfgName = "custom_serial_1000"
$cfgSource = Join-Path $RepoRoot "scripts\openocd_zcu104_win_custom_serial_1000.cfg"
$localCfgDir = Join-Path $OutDir "cfg"
New-Item -ItemType Directory -Force -Path $localCfgDir | Out-Null
$cfgPath = Join-Path $localCfgDir ($cfgName + ".cfg")
Copy-Item -Force -Path $cfgSource -Destination $cfgPath

$taskKillLog = Join-Path $OutDir "taskkill_hw_server.txt"
$taskKillCmd = "/c taskkill /F /IM hw_server.exe > `"$taskKillLog`" 2>&1"
$taskKillProc = Start-Process -FilePath $CmdExe -ArgumentList $taskKillCmd -NoNewWindow -PassThru -Wait
$taskKillExit = $taskKillProc.ExitCode

$log = Join-Path $OutDir ($cfgName + ".log")
$stdoutLog = Join-Path $OutDir ($cfgName + ".stdout.log")
$stderrLog = Join-Path $OutDir ($cfgName + ".stderr.log")

$proc = Start-Process -FilePath $OpenOcdExe `
  -ArgumentList @("-s", $OpenOcdScripts, "-f", $cfgPath) `
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

$hasOpenFail = ($content -match "libusb_open\(\) failed" -or $content -match "unable to open ftdi device")
$hasTapFound = ($content -match "tap/device found")
$hasSticky = ($content -match "JTAG-DP STICKY ERROR")
$hasA53ExamFail = ($content -match "\[uscale\.a53\.0\] Examination failed")
$hasAxiExamSucceed = ($content -match "\[uscale\.axi\] Examination succeed")

$classification =
  if ($hasOpenFail) {
    "B_open_device_failed"
  } elseif ($hasSticky -or $hasA53ExamFail) {
    "D_a53_examination_failed"
  } elseif ($hasTapFound) {
    "C_jtag_scan_progressed"
  } elseif (-not $hasOpenFail -and -not $hasSticky -and -not $hasA53ExamFail) {
    "F_board_state_changed"
  } else {
    "UNKNOWN"
  }

$summaryObject = [pscustomobject]@{
  cfg_name = $cfgName
  exit_code = $exitCode
  log_path = $log
  classification = $classification
  has_jtag_dp_sticky_error = $hasSticky
  has_a53_examination_failed = $hasA53ExamFail
  has_axi_examination_succeed = $hasAxiExamSucceed
  has_tap_device_found = $hasTapFound
  has_open_device_failed = $hasOpenFail
}

$summaryObject | ConvertTo-Json -Depth 4 | Out-File -FilePath (Join-Path $OutDir "summary.json") -Encoding utf8

@(
  "OUTDIR=$OutDir"
  "TASKKILL_EXIT=$taskKillExit"
  "CFG_NAME=$cfgName"
  "EXIT_CODE=$exitCode"
  "LOG_PATH=$log"
  "CLASSIFICATION=$classification"
  "HAS_JTAG_DP_STICKY_ERROR=$hasSticky"
  "HAS_A53_EXAMINATION_FAILED=$hasA53ExamFail"
  "HAS_AXI_EXAMINATION_SUCCEED=$hasAxiExamSucceed"
  "HAS_TAP_DEVICE_FOUND=$hasTapFound"
  "HAS_OPEN_DEVICE_FAILED=$hasOpenFail"
) | Out-File -FilePath (Join-Path $OutDir "summary.txt") -Encoding utf8

Get-Content (Join-Path $OutDir "summary.txt")
