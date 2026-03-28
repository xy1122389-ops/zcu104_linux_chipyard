param(
  [string]$OpenOcdExe = "C:\Users\24242\AppData\Local\Microsoft\WinGet\Packages\xpack-dev-tools.openocd-xpack_Microsoft.Winget.Source_8wekyb3d8bbwe\xpack-openocd-0.12.0-7\bin\openocd.exe",
  [string]$OpenOcdScripts = "C:\Users\24242\AppData\Local\Microsoft\WinGet\Packages\xpack-dev-tools.openocd-xpack_Microsoft.Winget.Source_8wekyb3d8bbwe\xpack-openocd-0.12.0-7\openocd\scripts",
  [string]$RepoRoot = "\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga",
  [string]$OutDir = "$env:TEMP\ft4232_openocd_verify"
)

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$cfgs = @(
  @{Name="custom";       Path=(Join-Path $RepoRoot "scripts\openocd_zcu104_win_custom.cfg")},
  @{Name="custom_serial";Path=(Join-Path $RepoRoot "scripts\openocd_zcu104_win_custom_serial.cfg")},
  @{Name="hs2";          Path=(Join-Path $RepoRoot "scripts\openocd_zcu104_win_hs2.cfg")},
  @{Name="hs3";          Path=(Join-Path $RepoRoot "scripts\openocd_zcu104_win_hs3.cfg")},
  @{Name="smt2_nc";      Path=(Join-Path $RepoRoot "scripts\openocd_zcu104_native_try.cfg")}
)

taskkill /F /IM hw_server.exe > (Join-Path $OutDir "taskkill_hw_server.txt") 2>&1

$summary = @()
foreach ($cfg in $cfgs) {
  $log = Join-Path $OutDir ($cfg.Name + ".log")
  & $OpenOcdExe -s $OpenOcdScripts -f $cfg.Path *> $log

  $content = Get-Content $log -Raw
  $classification =
    if ($content -match "libusb_open\(\) failed") { "B_open_device_failed" }
    elseif ($content -match "unable to open ftdi device") { "B_open_device_failed" }
    elseif ($content -match "JTAG scan chain" -or $content -match "tap/device found") { "C_jtag_scan_progressed" }
    elseif ($content -match "Hardware thread awareness created" -or $content -match "Listening on port 3333 for gdb connections") { "C_target_progressed" }
    else { "UNKNOWN" }

  $summary += [pscustomobject]@{
    Name           = $cfg.Name
    Config         = $cfg.Path
    Classification = $classification
    Log            = $log
  }
}

$summary | ConvertTo-Json -Depth 4 | Out-File -FilePath (Join-Path $OutDir "summary.json") -Encoding utf8
$summary | Format-Table -AutoSize | Out-File -FilePath (Join-Path $OutDir "summary.txt") -Encoding utf8

Write-Output "OUTDIR=$OutDir"
Get-Content (Join-Path $OutDir "summary.txt")
