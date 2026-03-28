param(
  [string]$OutDir = "$env:TEMP\ft4232_driver_state"
)

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Save-Text {
  param([string]$Path, [string]$Text)
  $Text | Out-File -FilePath $Path -Encoding utf8
}

function Get-DeviceProps {
  param([string]$InstanceId)
  $keys = @(
    "DEVPKEY_Device_HardwareIds",
    "DEVPKEY_Device_CompatibleIds",
    "DEVPKEY_Device_Parent",
    "DEVPKEY_Device_Children",
    "DEVPKEY_Device_Service",
    "DEVPKEY_Device_DriverInfPath",
    "DEVPKEY_Device_Class",
    "DEVPKEY_Device_ClassGuid",
    "DEVPKEY_Device_Manufacturer",
    "DEVPKEY_Device_BusReportedDeviceDesc"
  )

  $result = [ordered]@{}
  foreach ($k in $keys) {
    try {
      $p = Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName $k -ErrorAction Stop
      $result[$k] = $p.Data
    } catch {
      $result[$k] = $null
    }
  }
  return [pscustomobject]$result
}

$patterns = @("VID_0403&PID_6011", "FTDIBUS\VID_0403+PID_6011", "07198")

$allDevices = Get-PnpDevice -PresentOnly
$matched = foreach ($d in $allDevices) {
  foreach ($pat in $patterns) {
    if ($d.InstanceId -like "*$pat*") {
      $props = Get-DeviceProps -InstanceId $d.InstanceId
      $signed = Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceID -eq $d.InstanceId } | Select-Object -First 1
      [pscustomobject]@{
        Status          = $d.Status
        Class           = $d.Class
        FriendlyName    = $d.FriendlyName
        InstanceId      = $d.InstanceId
        DriverProvider  = $signed.DriverProviderName
        DriverVersion   = $signed.DriverVersion
        InfName         = $signed.InfName
        Service         = $signed.Service
        Parent          = $props.DEVPKEY_Device_Parent
        Children        = $props.DEVPKEY_Device_Children
        HardwareIds     = $props.DEVPKEY_Device_HardwareIds
        CompatibleIds   = $props.DEVPKEY_Device_CompatibleIds
        Manufacturer    = $props.DEVPKEY_Device_Manufacturer
        BusDesc         = $props.DEVPKEY_Device_BusReportedDeviceDesc
      }
      break
    }
  }
}

$matched | Sort-Object InstanceId | ConvertTo-Json -Depth 6 | Out-File -FilePath (Join-Path $OutDir "ft4232_devices.json") -Encoding utf8
$matched | Sort-Object InstanceId | Format-List * | Out-File -FilePath (Join-Path $OutDir "ft4232_devices.txt") -Encoding utf8

pnputil /enum-devices /connected > (Join-Path $OutDir "pnputil_enum_connected.txt") 2>&1
pnputil /enum-drivers > (Join-Path $OutDir "pnputil_enum_drivers.txt") 2>&1
tasklist /FI "IMAGENAME eq hw_server.exe" > (Join-Path $OutDir "tasklist_hw_server.txt") 2>&1

Write-Output "OUTDIR=$OutDir"
Write-Output "FILES:"
Get-ChildItem $OutDir | Select-Object Name,Length,LastWriteTime | Format-Table -AutoSize
