<#
This script launches a GUI in Windows PowerShell that can be used to launch applications
that are typically used at work with an admin account, with only requiring logging into
the admin account once. This accelerates the work flow and enhances productivity. This
GUI can also be used to run commonly used scripts with the admin account.

FOR THE LAUNCHER TO WORK, YOUR APPLICATIONS AND SCRIPTS MUST BE IN THE SAME
DIRECTORY PATH AS THIS SCRIPT SAYS. THIS CAN BE EASILY ADJUSTED WITHIN THIS SCRIPT.
#>

param([switch]$Elevated)

# -------------------------
# Temp Credential File
# -------------------------
$CredPath = "C:\Temp\Admin-Launcher_creds.xml"
$CredDir = Split-Path $CredPath
if (-not (Test-Path $CredDir)) { New-Item -ItemType Directory -Path $CredDir -Force | Out-Null }

# -------------------------
# Auto-Elevation
# -------------------------
if (-not $Elevated) {
    Write-Host "`nEnter your Admin account credentials..." -ForegroundColor Yellow
    $DefaultDomain = "DOMAIN"
    $cred = Get-Credential -Message "Enter your Admin Account Username"

    # Optional: prepend domain if missing
    if ($cred.UserName -notmatch "\\") {
        $cred = New-Object System.Management.Automation.PSCredential(
            "$DefaultDomain\$($cred.UserName)", $cred.Password
        )
    }

    # Save temporary credentials
    $cred | Export-Clixml -Path $CredPath

    # Relaunch Windows PowerShell as that user
    $script = $MyInvocation.MyCommand.Definition
    Write-Host "`nLaunching elevated Windows PowerShell..." -ForegroundColor Blue
    Start-Process "powershell.exe" `
        -Credential $cred `
        -ArgumentList "-NoExit", "-File `"$script`" -Elevated"

    exit
}

# -------------------------
# Elevated session: load creds
# -------------------------
if (-not (Test-Path $CredPath)) {
    Write-Host "Credential file missing. Exiting." -ForegroundColor Red
    exit 1
}
$Credential = Import-Clixml -Path $CredPath
Remove-Item $CredPath -Force

# -------------------------
# Tool Launcher
# -------------------------
function Start-Tool {
    param([string]$Name, [string]$Executable, [string]$Arguments)
    Write-Host "`nLaunching $Name..." -ForegroundColor Green
    try {
        if ($Arguments) {
            Start-Process -FilePath $Executable -ArgumentList $Arguments
        } else {
            Start-Process -FilePath $Executable
        }
    }
    catch {
        Write-Host ("Failed to launch " + $Name + ": " + $_.Exception.Message) -ForegroundColor Red
    }
}


# -------------------------
# GUI-ISH MENU
# -------------------------
function Show-Menu {
    Clear-Host                  # Unicode characters for copy/paste - ╚ ║ ╔ ═ ╗ ╝ ╦ ╩ ╬ 
    Write-Host ""
    Write-Host "╔═════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Blue
    Write-Host "║                             ADMIN TOOL LAUNCHER                             ║" -ForegroundColor Blue
    Write-Host "╚═════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Blue
    Write-Host "╔══════════════════════════════════════╦══════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║             SYSTEM TOOLS             ║               SCRIPTS                ║" -ForegroundColor Yellow
    Write-Host "╚══════════════════════════════════════╩══════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host "╔══════════════════════════════════════╦══════════════════════════════════════╗" -ForegroundColor White
    Write-Host "║  [1] ADUC                            ║  [11] Get-Expiration                 ║" -ForegroundColor White
    Write-Host "║  [2] ADAC                            ║  [12] New-FacStaff                   ║" -ForegroundColor White
    Write-Host "║  [3] Group Policy Management         ║  [13] New-DCProctor                  ║" -ForegroundColor White
    Write-Host "║  [4] Event Viewer                    ║  [14] New-Acadeum                    ║" -ForegroundColor White
    Write-Host "║  [5] DHCP Management                 ║  [15] Name Change Prep               ║" -ForegroundColor White
    Write-Host "║  [6] DNS Management                  ║  [16] Count-ADUsers - NOT WORKING    ║" -ForegroundColor White
    Write-Host "║  [7] DFS Management                  ║                                      ║" -ForegroundColor White
    Write-Host "║  [8] Explorer++                      ║                                      ║" -ForegroundColor White
    Write-Host "║  [9] PowerShell 7 - Buggy            ║                                      ║" -ForegroundColor White
    Write-Host "╚══════════════════════════════════════╩══════════════════════════════════════╝" -ForegroundColor White
    Write-Host "╔══════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║  [Q] Quit                            ║" -ForegroundColor Red
    Write-Host "╚══════════════════════════════════════╝" -ForegroundColor Red
}

# -------------------------
# Menu Loop
# -------------------------
do {
    Show-Menu
    $choice = Read-Host "Enter your selection"

    switch ($choice.ToUpper()) {
        '1'  { Start-Tool "Active Directory Users and Computers" "mmc.exe" "C:\Windows\System32\dsa.msc" }
        '2'  { Start-Tool "Active Directory Administrative Center" "dsac.exe" }
        '3'  { Start-Tool "Group Policy Management" "mmc.exe" "C:\Windows\System32\gpmc.msc" }
        '4'  { Start-Tool "Event Viewer" "eventvwr.msc" }
        '5'  { Start-Tool "DHCP Management" "mmc.exe" "C:\Windows\System32\dhcpmgmt.msc" }
        '6'  { Start-Tool "DNS Management" "mmc.exe" "C:\Windows\System32\dnsmgmt.msc" }
        '7'  { Start-Tool "DFS Management" "mmc.exe" "C:\Windows\System32\dfsmgmt.msc" }
        '8'  { Start-Tool "Explorer++" "C:\explorerpp_x64\Explorer++.exe" }
        '9'  { Start-Tool "PowerShell 7" "C:\Program Files\PowerShell\7\pwsh.exe" }

        '11' {
			$Username = Read-Host "Enter the username to check expiration for"
		
			if ([string]::IsNullOrWhiteSpace($Username)) {
				Write-Host "No username entered." -ForegroundColor Yellow
				break
			}
		
			$launchScript = "C:\Scripts\Account Status\Launch-Expiration.ps1"
		
			if (-not (Test-Path $launchScript)) {
				Write-Host "ERROR: Script not found at $launchScript" -ForegroundColor Red
				break
			}
		
			# Launch hidden PowerShell
			Start-Process powershell.exe `
				-WindowStyle Hidden `
				-ArgumentList @(
					"-NoProfile"
					"-ExecutionPolicy Bypass"
					"-File `"$launchScript`""
					"-Username `"$Username`""
				)
		
			break
		}

        '12' {
            Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
            -WindowStyle Hidden `
            -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-STA","-File","`"C:\Scripts\New-Account\Launch-FacStaff.ps1`"")
		}

        '13' { Start-Tool "New-DCProctor Tool" "powershell.exe" "-NoProfile -ExecutionPolicy Bypass -File `"C:\Scripts\New-Account\New-DCProctor.ps1`"" }

        '14' {
            Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
            -WindowStyle Hidden `
            -ArgumentList '-NoProfile -ExecutionPolicy Bypass -STA -File "C:\Scripts\New-Account\New-Acadeum.ps1"'
		}

        '15' {
            Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-ExecutionPolicy Bypass -File `"C:\Scripts\Name_Change_Prep.ps1`""
        }

        'Q'  { Write-Host "`nGoodbye!" -ForegroundColor Blue; break }
        default { Write-Host "`nInvalid selection." -ForegroundColor Red }
    }

    Start-Sleep -Milliseconds 500

} while ($choice.ToUpper() -ne 'Q')
