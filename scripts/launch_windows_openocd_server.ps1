param(
  [string]$OpenOcdExe = "C:\Users\24242\AppData\Local\Microsoft\WinGet\Packages\xpack-dev-tools.openocd-xpack_Microsoft.Winget.Source_8wekyb3d8bbwe\xpack-openocd-0.12.0-7\bin\openocd.exe",
  [string]$OpenOcdScripts = "C:\Users\24242\AppData\Local\Microsoft\WinGet\Packages\xpack-dev-tools.openocd-xpack_Microsoft.Winget.Source_8wekyb3d8bbwe\xpack-openocd-0.12.0-7\openocd\scripts",
  [string]$Cfg = "\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga\scripts\openocd_zcu104_win_custom_serial_1000_server_min.cfg",
  [string]$OutDir = "$env:TEMP\openocd_server_min"
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$stdout = Join-Path $OutDir 'stdout.log'
$stderr = Join-Path $OutDir 'stderr.log'
$proc = Start-Process -FilePath $OpenOcdExe -ArgumentList @('-s',$OpenOcdScripts,'-f',$Cfg) -WorkingDirectory $OutDir -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
Write-Output "PID=$($proc.Id)"
Write-Output "OUTDIR=$OutDir"
Write-Output "STDOUT=$stdout"
Write-Output "STDERR=$stderr"
