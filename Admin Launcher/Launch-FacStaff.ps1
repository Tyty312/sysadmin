<#
This script is used by the main Admin-Launcher to run the New-FacStaff.ps1 script. For some reason the
Admin-Launcher refused to run the New-FacStaff.ps1 as an admin directly, so this work around worked.
#>

$scriptPath = "C:\Scripts\New-Account\New-FacStaff.ps1"

$wshell = New-Object -ComObject WScript.Shell
$wshell.Run("powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$scriptPath`"", 0, $false)
