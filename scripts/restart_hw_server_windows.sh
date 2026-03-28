#!/usr/bin/env bash
set -euo pipefail

powershell.exe -NoLogo -NoProfile -Command '
  $p = Get-CimInstance Win32_Process | Where-Object Name -eq "hw_server.exe"
  if ($p) {
    $p | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
  }
  Start-Process -FilePath "E:\PRO_APP\xilinx\Vivado\2021.2\bin\unwrapped\win64.o\hw_server.exe" -ArgumentList "-D","-I20","-s","TCP:127.0.0.1:3121"
  Start-Sleep -Seconds 2
  Get-CimInstance Win32_Process | Where-Object Name -eq "hw_server.exe" | Select-Object ProcessId,Name,CommandLine | Format-Table -AutoSize
'

