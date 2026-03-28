param(
  [string]$ParentId = 'USB\VID_0403&PID_6011\07198',
  [string]$DriverInf = 'C:\Windows\INF\oem63.inf'
)

$ErrorActionPreference = 'Stop'

$jsonPath = "$env:TEMP\ft4232_driver_state\ft4232_devices.json"
if (-not (Test-Path $jsonPath)) {
  throw "Missing driver state cache: $jsonPath. Run collect_ft4232_driver_state.ps1 first."
}

$devices = Get-Content -Raw $jsonPath | ConvertFrom-Json
$dev = $devices | Where-Object {
  $_.InstanceId -like '*VID_0403&PID_6011&MI_00*' -and $_.Parent -eq $ParentId
} | Select-Object -First 1

if (-not $dev) {
  throw "Could not locate MI_00 under parent $ParentId"
}

$iid = '@' + $dev.InstanceId
Write-Output "INSTANCE=$iid"
Write-Output "TARGET_INF=$DriverInf"

& devcon.exe drivernodes $iid
& devcon.exe /r update $DriverInf $iid

Write-Output "EXIT=$LASTEXITCODE"
