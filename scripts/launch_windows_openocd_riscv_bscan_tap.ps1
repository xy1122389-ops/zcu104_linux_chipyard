param(
  [string]$Cfg = "\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga\scripts\openocd_zcu104_win_riscv_bscan_tap.cfg",
  [string]$OutDir = "$env:TEMP\openocd_riscv_bscan_tap"
)

& "\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga\scripts\launch_windows_openocd_server.ps1" -Cfg $Cfg -OutDir $OutDir
