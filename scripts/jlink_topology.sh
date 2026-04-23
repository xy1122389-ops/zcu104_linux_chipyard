#!/usr/bin/env bash
set -euo pipefail

powershell.exe -NoProfile -Command '
$targets = @(
  "USB\VID_1366&PID_0101\000601012542",
  "USB\VID_1366&PID_0105\000601012352",
  "USB\VID_0403&PID_6011\07198"
)

Get-PnpDevice | Where-Object { $targets -contains $_.InstanceId } | ForEach-Object {
  $_ | Get-PnpDeviceProperty | Where-Object {
    $_.KeyName -in @(
      "DEVPKEY_Device_InstanceId",
      "DEVPKEY_NAME",
      "DEVPKEY_Device_IsPresent",
      "DEVPKEY_Device_Parent",
      "DEVPKEY_Device_LocationInfo",
      "DEVPKEY_Device_LocationPaths",
      "DEVPKEY_Device_LastArrivalDate",
      "DEVPKEY_Device_LastRemovalDate",
      "DEVPKEY_Device_BiosDeviceName"
    )
  } | Select-Object KeyName,Data
  ""
  "---"
  ""
} | Format-Table -AutoSize
'
