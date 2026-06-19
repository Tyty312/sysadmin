<#
This script launches a GUI in Windows PowerShell that can be used to launch applications
that are typically used at work with an admin account, with only requiring logging into
the admin account once. This accelerates the work flow and enhances productivity. This
GUI can also be used to run commonly used scripts with the admin account.

FOR THE LAUNCHER TO WORK, YOUR APPLICATIONS AND SCRIPTS MUST BE IN THE SAME
DIRECTORY PATH AS THIS SCRIPT SAYS. THIS CAN BE EASILY ADJUSTED WITHIN THIS SCRIPT.

6/19/2026 - Various fixes across multiple parts of the script to ensure everything is working.
Added a disable option for the "Reset-RiskyUser" option
#>

param([switch]$Elevated)

# -------------------------
# Temp Credential File
# -------------------------
$CredPath = "C:\Temp\AdminLauncher_creds.xml"
$CredDir = Split-Path $CredPath
if (-not (Test-Path $CredDir)) { New-Item -ItemType Directory -Path $CredDir -Force | Out-Null }

# -------------------------
# Auto-Elevation
# -------------------------
if (-not $Elevated) {
    Write-Host "`nEnter your IT account credentials..." -ForegroundColor Yellow
    $DefaultDomain = "DOMAIN" #Replace with your domain
    $cred = Get-Credential -Message "Enter your Admin Account username"

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
        -LoadUserProfile `
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
#$Credential = Import-Clixml -Path $CredPath
Remove-Item $CredPath -Force

# -------------------------
# FIX BROKEN ENVIRONMENT
# -------------------------
#$UsernameOnly = $Credential.UserName.Split('\')[-1]

$env:USERPROFILE = "C:"
$env:TEMP = "C:\Temp"
$env:TMP  = "C:\Temp"

# Ensure temp exists
if (-not (Test-Path $env:TEMP)) {
    New-Item -ItemType Directory -Force -Path $env:TEMP | Out-Null
}

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
    Write-Host "║  [6] DNS Management                  ║  [16] Count-ADUsers                  ║" -ForegroundColor White
    Write-Host "║  [7] DFS Management                  ║  [17] Remove-FakeApp                 ║" -ForegroundColor White
    Write-Host "║  [8] Explorer++                      ║  [18] Reset-RiskyUser                ║" -ForegroundColor White
    Write-Host "║  [9] PowerShell 7                    ║                                      ║" -ForegroundColor White
    Write-Host "╚══════════════════════════════════════╩══════════════════════════════════════╝" -ForegroundColor White
    Write-Host "╔══════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║  [Q] Quit                            ║" -ForegroundColor Red
    Write-Host "╚══════════════════════════════════════╝" -ForegroundColor Red
}


<#$command = {
    if (Get-Module -ListAvailable ActiveDirectory) {
        Import-Module ActiveDirectory
    }
    Clear-Host
}.ToString()#>


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
        '9'  { Start-Process "C:\Program Files\PowerShell\7\pwsh.exe" -ArgumentList '-NoExit', '-Command "Clear-Host"' -WorkingDirectory $env:USERPROFILE }

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

        '16' {
            Start-Process -FilePath "C:\Program Files\PowerShell\7\pwsh.exe" `
            -ArgumentList "-ExecutionPolicy Bypass -File `"C:\Scripts\Count Users\CountAllUsers.ps1`""
            # Parralel processing for speed
        }
        
        "17" {
    		$InputUsernames = @()

            Write-Host "Paste usernames one per line." -ForegroundColor Cyan
            Write-Host "Press ENTER on a blank line when done.`n" -ForegroundColor Yellow

            while ($true) {
                $line = Read-Host

                if ([string]::IsNullOrWhiteSpace($line)) {
                    break
                }

                $InputUsernames += $line.Trim()
            }

            $Usernames = $InputUsernames | Where-Object { $_ -ne "" }
	
            $ProtectedGroups = @(
				"Student - Enrolled",
				"SailPoint-Student Enrolled",
                "Ty Test Group"
			)
		
					foreach ($Username in $Usernames) {
		
				try {
		
					Write-Host "`nChecking user: $Username" -ForegroundColor Cyan
		
					$user = Get-ADUser -Identity $Username -Properties MemberOf -ErrorAction Stop
		
					$UserGroups = foreach ($GroupDN in $user.MemberOf) {
						(Get-ADGroup -Identity $GroupDN).Name
					}
		
					$BlockedGroups = $UserGroups | Where-Object { $_ -in $ProtectedGroups }
		
					if ($BlockedGroups) {
		
						Write-Host "User $Username is in protected group(s):" -ForegroundColor Red
		
						$BlockedGroups | ForEach-Object {
							Write-Host " - $_" -ForegroundColor Red
						}
		
						Write-Host "Deletion BLOCKED for $Username." -ForegroundColor Red
		
						Start-Sleep -Milliseconds 500
		
						continue
					}
		
					Write-Host "`nWARNING: You are about to delete $Username" -ForegroundColor Yellow
		
					$confirm = Read-Host "Type YES to confirm deletion of $Username"
		
					if ($confirm -eq "YES") {
		
						Remove-ADUser -Identity $user.DistinguishedName -Confirm:$false
		
						Write-Host "User $Username deleted successfully." -ForegroundColor Green
					}
					else {
		
						Write-Host "Deletion cancelled for $Username." -ForegroundColor Cyan
					}
				}
				catch {
		
					Write-Host "Error deleting user ${Username}: $($_.Exception.Message)" -ForegroundColor Red
		
					Start-Sleep -Milliseconds 500
				}
			}
		
			break
		}

        '18' {
			$Username = Read-Host "Enter username to reset password"
		
			try {
				$user = Get-ADUser -Identity $Username -ErrorAction Stop
		
				# Generate random password
				Add-Type -AssemblyName System.Web
				$plainPassword = [System.Web.Security.Membership]::GeneratePassword(12,3)
				$securePassword = New-Object System.Security.SecureString
                $plainPassword.ToCharArray() | ForEach-Object {
                    $securePassword.AppendChar($_)
                }
		
				# Reset password
				Set-ADAccountPassword -Identity $user `
					-Reset `
					-NewPassword $securePassword
		
				# Force change at next logon
				Set-ADUser -Identity $user -ChangePasswordAtLogon $true
		
                # Prompt to disable account or not
                $doDisable = Read-Host "Should this account be disabled? ('y' or 'yes')"

                $doDisable = $doDisable.ToLower()

                if ($doDisable -eq "y" -or $doDisable -eq "yes")
                {
                    Disable-ADAccount -Identity $User
                    Write-Host "Account has been disabled" -ForegroundColor Blue
                    Start-Sleep -Milliseconds 500
                }

                else
                {
                    Write-Host "Account is left enabled" -ForegroundColor Blue
                    Start-Sleep -Milliseconds 500
                }

				Write-Host "Password reset for $Username" -ForegroundColor Green
				#Write-Host "Temporary Password: $plainPassword" -ForegroundColor Cyan    #Un-comment if you want to be given their termporary password
			}
			catch {
				Write-Host "Error resetting password for ${Username}: $_" -ForegroundColor Red
			}
		}

        'Q'  { Write-Host "`nGoodbye!" -ForegroundColor Blue; break }
        default { Write-Host "`nInvalid selection." -ForegroundColor Red }
    }

    Start-Sleep -Milliseconds 500

} while ($choice.ToUpper() -ne 'Q')
