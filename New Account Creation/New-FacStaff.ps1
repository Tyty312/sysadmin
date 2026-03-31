# ================================
# New-FacStaff (updated 11/17/2025)
# - Hides the console window
# - Robust phone normalization (strips non-digits, accepts leading +1)
# - Fixed OU loading order (no references before variable exists)
# - No use of 'exit' (safe for GUI event handlers)
# ================================

<#
    New-FacStaff.ps1
    Clean, STA-safe WinForms launcher for creating Faculty/Staff AD accounts.
    - Hidden console (when launched with -WindowStyle Hidden)
    - STA guaranteed (relaunches itself if needed)
    - ACL warm-up + retry logic
    - Single modal form loop via ShowDialog()
#>
# New-FacStaff.ps1 (cleaned version)
# Preserves GUI & AD logic; removes ACL/temp/type-data fixes that broke launcher runs.
Import-Module ActiveDirectory
Import-Module Microsoft.PowerShell.Security -UseWindowsPowerShell

$modules = @(
    "Microsoft.PowerShell.Security",
    "Microsoft.PowerShell.Management",
    "Microsoft.PowerShell.Utility"
    #"ActiveDirectory"
)

foreach ($m in $modules) {
    Try { Import-Module $m -ErrorAction Stop } catch {}
}



# ========== Config ==========
$rootOU = ""     # set appropriately
$companyName = ""    # set appropriately
$EnableLogging = $false  
$LogPath = "C:\Temp\New-FacStaff.log"
# ============================

function Log {
    param($msg)
    if ($EnableLogging) {
        $t = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -Path $LogPath -Value "$t - $msg"
    }
}

if ($EnableLogging) {
    if (-not (Test-Path (Split-Path $LogPath))) { New-Item -ItemType Directory -Path (Split-Path $LogPath) -Force | Out-Null }
    Log "Script started (PID $PID)."
}

# -------------------------
# Ensure STA (required for WinForms)
# -------------------------
try {
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne "STA") {
        # Relaunch in STA & hidden. This preserves $PSCommandPath when using -File.
        $psPath = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
        $arguments = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-STA",
            "-File", "`"$PSCommandPath`""
        )
        Log "Not STA - relaunching via $psPath $($arguments -join ' ')"
        Start-Process -FilePath $psPath -WindowStyle Hidden -ArgumentList $arguments
        exit
    }
} catch {
    Log "STA relaunch attempt failed: $($_.Exception.Message)"
}

# -------------------------
# Load WinForms + Drawing
# -------------------------
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# -------------------------
# Console hide helper (best-effort, silent)
# -------------------------
try {
    $csharp = @'
using System;
using System.Runtime.InteropServices;
public static class HiddenConsole {
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
'@
    Add-Type -TypeDefinition $csharp -Language CSharp -ErrorAction Stop
    $hwnd = [HiddenConsole]::GetConsoleWindow()
    if ($hwnd -ne [IntPtr]::Zero) {
        [HiddenConsole]::ShowWindow($hwnd, 0) | Out-Null
        Log "Console hidden (hwnd $hwnd)."
    }
} catch {
    Log "Console hide not available: $($_.Exception.Message)"
}

# -------------------------
# Load AD module early (so failures show as message box)
# -------------------------
# Note: we intentionally don't import Microsoft.PowerShell.Security at top-level to avoid
# type-data / temp-file problems when launched from the wrapper.  AD module stays loaded where needed.
try {
    # Attempt to load AD module early so OU dropdown can be populated
    Import-Module ActiveDirectory -ErrorAction Stop
    Log "ActiveDirectory module loaded."
} catch {
    [System.Windows.Forms.MessageBox]::Show("Failed to import ActiveDirectory module:`n$($_.Exception.Message)","Module Error",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)
    Log "Failed to import AD module: $($_.Exception.Message)"
    throw
}

# -------------------------
# Build main form
# -------------------------
[System.Windows.Forms.Application]::EnableVisualStyles()
$form = New-Object System.Windows.Forms.Form
$form.Text = "Create New AD User"
$form.Size = New-Object System.Drawing.Size(420, 700)
$form.StartPosition = "CenterScreen"
$form.TopMost = $true
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox = $false
$form.MinimizeBox = $false

# Fields
$labels = @("Username", "First Name", "Last Name", "Title", "Manager Username", "Office Location", "Phone Number")
$inputs = @{}
$y = 20

foreach ($labelText in $labels) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $labelText
    $label.Location = New-Object System.Drawing.Point(10, $y)
    $label.Size = New-Object System.Drawing.Size(130, 20)
    $form.Controls.Add($label)

    $textbox = New-Object System.Windows.Forms.TextBox
    $textbox.Location = New-Object System.Drawing.Point(150, $y)
    $textbox.Size = New-Object System.Drawing.Size(240, 20)
    $form.Controls.Add($textbox)

    $inputs[$labelText] = $textbox
    $y += 40
}

# Role dropdown
$roleLabel = New-Object System.Windows.Forms.Label
$roleLabel.Text = "Faculty or Staff"
$roleLabel.Location = New-Object System.Drawing.Point(10, $y)
$roleLabel.Size = New-Object System.Drawing.Size(130, 20)
$form.Controls.Add($roleLabel)

$roleDropdown = New-Object System.Windows.Forms.ComboBox
$roleDropdown.Location = New-Object System.Drawing.Point(150, $y)
$roleDropdown.Size = New-Object System.Drawing.Size(240, 20)
$roleDropdown.DropDownStyle = 'DropDownList'
$roleDropdown.Items.AddRange(@("Faculty","Staff"))
$form.Controls.Add($roleDropdown)
$y += 40

# Department dropdown
$deptLabel = New-Object System.Windows.Forms.Label
$deptLabel.Text = "Department"
$deptLabel.Location = New-Object System.Drawing.Point(10, $y)
$deptLabel.Size = New-Object System.Drawing.Size(130, 20)
$form.Controls.Add($deptLabel)

$deptDropdown = New-Object System.Windows.Forms.ComboBox
$deptDropdown.Location = New-Object System.Drawing.Point(150, $y)
$deptDropdown.Size = New-Object System.Drawing.Size(240, 20)
$deptDropdown.DropDownStyle = 'DropDownList'
$form.Controls.Add($deptDropdown)
$y += 50

# OU map populate
$ouMap = @{}
try {
    $departmentOUMap = Get-ADOrganizationalUnit -Filter * -SearchBase $rootOU -SearchScope OneLevel -ErrorAction Stop
} catch {
    [System.Windows.Forms.MessageBox]::Show("Unable to query AD for departments:`n$($_.Exception.Message)","AD Query Error",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)
    $departmentOUMap = $null
}

if ($departmentOUMap -and $departmentOUMap.Count -gt 0) {
    foreach ($ou in $departmentOUMap | Sort-Object Name) {
        if ($ou.Name) {
            $null = $deptDropdown.Items.Add($ou.Name)
            $ouMap[$ou.Name] = $ou.DistinguishedName
        }
    }
} else {
    [System.Windows.Forms.MessageBox]::Show("No departments found under $rootOU. Check OU path or AD permissions.","No Departments",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning)
}

# Submit button & result label
$submit = New-Object System.Windows.Forms.Button
$submit.Text = "Create User"
$submit.Location = New-Object System.Drawing.Point(150, $y)
$submit.Size = New-Object System.Drawing.Size(120, 30)
$form.Controls.Add($submit)

$result = New-Object System.Windows.Forms.Label
$result.Location = New-Object System.Drawing.Point(10, ($y + 40))
$result.Size = New-Object System.Drawing.Size(390, 120)
$result.AutoSize = $false
$result.BorderStyle = 'Fixed3D'
$form.Controls.Add($result)

# Random password generator
function New-RandomPassword {
    param ([int]$Length = 12)
    $upper   = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $lower   = 'abcdefghijkmnopqrstuvwxyz'
    $digits  = '23456789'
    $special = '!@#$%^&*()-_=+[]{}'
    $allChars = ($upper + $lower + $digits + $special).ToCharArray()
    $rand = New-Object System.Random
    -join (1..$Length | ForEach-Object { $allChars[$rand.Next(0, $allChars.Length)] })
}

# --------------------
# Submit event
# --------------------
$submit.Add_Click({
    try {
        # Re-import AD module (safe)
        Import-Module ActiveDirectory -ErrorAction Stop

        # Force-load security module locally before ConvertTo-SecureString (best-effort)
        Try { Import-Module Microsoft.PowerShell.Security -ErrorAction SilentlyContinue } catch {}

        $username        = $inputs["Username"].Text.Trim()
        $firstname       = $inputs["First Name"].Text.Trim()
        $lastname        = $inputs["Last Name"].Text.Trim()
        $title           = $inputs["Title"].Text.Trim()
        $managerUsername = $inputs["Manager Username"].Text.Trim()
        $officeLocation  = $inputs["Office Location"].Text.Trim()
        $roleType        = $roleDropdown.SelectedItem.ToString()
        $department      = $deptDropdown.SelectedItem
        $rawTelephone    = $inputs["Phone Number"].Text.Trim()

        # BASIC VALIDATION
        if (-not $username) {
            [System.Windows.Forms.MessageBox]::Show("Username is required.","Validation",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }
        if (-not $firstname -or -not $lastname) {
            [System.Windows.Forms.MessageBox]::Show("First and Last name are required.","Validation",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }
        if (-not $department -or -not $ouMap.ContainsKey($department)) {
            [System.Windows.Forms.MessageBox]::Show("Department not selected or invalid.","Validation",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }

        # Normalize phone
        $telephone = $null
        if ($rawTelephone) {
            $digits = $rawTelephone -replace '[^\d]', ''
            if ($digits.Length -eq 11 -and $digits.StartsWith('1')) { $digits = $digits.Substring(1) }
            if ($digits.Length -eq 10) { $telephone = "{0}-{1}-{2}" -f $digits.Substring(0,3), $digits.Substring(3,3), $digits.Substring(6,4) }
            else {
                [System.Windows.Forms.MessageBox]::Show("Invalid phone number. Enter a 10-digit number (country code +1 allowed).","Invalid Input",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning)
                return
            }
        }

        $selectedOU = $ouMap[$department]
        $fullname = "$firstname $lastname"
        $userPrincipalName = "$username@"   # set appropriately
        $generatedPassword = New-RandomPassword
        $SecurePassword = New-Object System.Security.SecureString
        $generatedPassword.ToCharArray() | ForEach-Object { $SecurePassword.AppendChar($_) }



        # Resolve manager DN (if provided)
        $managerDN = $null
        if ($managerUsername) {
            try {
                $mgr = Get-ADUser -Identity $managerUsername -ErrorAction Stop
                $managerDN = $mgr.DistinguishedName
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Manager '$managerUsername' not found in AD. Proceeding without Manager set.","Manager Not Found",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning)
                $managerDN = $null
            }
        }

        # Construct New-ADUser params
        $newUserParams = @{
            Name                    = $username
            SamAccountName          = $username
            UserPrincipalName       = $userPrincipalName
            GivenName               = $firstname
            Surname                 = $lastname
            DisplayName             = $fullname
            Description             = $title
            Title                   = $title
            Department              = $department
            Office                  = $officeLocation
            Path                    = $selectedOU
            AccountPassword         = $securePassword
            ChangePasswordAtLogon   = $true
            Company                 = $companyName
            Enabled                 = $true
            EmailAddress            = "$username@"  # set appropriately
            HomeDrive               = "P:"
            HomeDirectory           = "\\"  # set appropriately
            ErrorAction             = 'Stop'
        }
        if ($telephone) { $newUserParams['OfficePhone'] = $telephone }
        if ($managerDN)   { $newUserParams['Manager'] = $managerDN }

        # Check if user already exists
        $existingUser = Get-ADUser -Filter "SamAccountName -eq '$username'" -ErrorAction SilentlyContinue

        if ($existingUser) {

            $choice = [System.Windows.Forms.MessageBox]::Show(
                "User '$username' already exists.`n`nDo you want to update this account with the new information?",
               "Account Exists",
               [System.Windows.Forms.MessageBoxButtons]::YesNo,
               [System.Windows.Forms.MessageBoxIcon]::Question
            )

            if ($choice -eq [System.Windows.Forms.DialogResult]::No) {
                $result.Text = "Account already exists. No changes made."
                return
            }

            # Update existing account
            try {

            Set-ADUser -Identity $username `
                    -GivenName $firstname `
                    -Surname $lastname `
                    -DisplayName $fullname `
                    -Title $title `
                    -Department $department `
                    -Office $officeLocation `
                    -EmailAddress "$username@"  # set appropriately

                if ($telephone) {
                    Set-ADUser -Identity $username -OfficePhone $telephone
                }

                if ($managerDN) {
                    Set-ADUser -Identity $username -Manager $managerDN
                }

                $result.Text = "Existing user '$username' updated."

            } catch {
                [System.Windows.Forms.MessageBox]::Show(
                    "Failed to update user:`n$($_.Exception.Message)",
                    "Update Error",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                )
                return
            }

        }
        else {

            # Create new AD user
            try {
                New-ADUser @newUserParams
            } catch {
                $err = $_.Exception.Message
                [System.Windows.Forms.MessageBox]::Show(
                    "Failed to create AD user:`n$err",
                    "AD Error",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                )
                $result.Text = "Error: $err"
                return
            }

        }

        Start-Sleep -Seconds 2

        # Create home directory + ACLs (retrying for identity mapping)
		$homePath = "\\"    # set appropriately
		if (!(Test-Path $homePath)) {
		
			try {
				New-Item -Path $homePath -ItemType Directory -Force | Out-Null
		
				# Build NTAccount object
				$ntAccount = New-Object System.Security.Principal.NTAccount("$env:USERDOMAIN\$username")
		
				# Build inheritance flags safely
				$inheritFlags = `
					[System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor `
					[System.Security.AccessControl.InheritanceFlags]::ObjectInherit
		
				# Build full control access rule
				$accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
					$ntAccount,
					[System.Security.AccessControl.FileSystemRights]::FullControl,
					$inheritFlags,
					[System.Security.AccessControl.PropagationFlags]::None,
					[System.Security.AccessControl.AccessControlType]::Allow
				)
		
				# Get ACL object
				$acl = Get-Acl -Path $homePath
		
				# Set owner
				$acl.SetOwner($ntAccount)
		
				# Retry ACL update until identity maps
				$aclSet = $false
				while (-not $aclSet) {
					try {
						$acl.SetAccessRule($accessRule)
						$aclSet = $true
					}
					catch [System.Security.Principal.IdentityNotMappedException] {
						Start-Sleep -Milliseconds 200
					}
				}
		
				# Apply ACL
				Set-Acl -Path $homePath -AclObject $acl
			}
			catch {
				[System.Windows.Forms.MessageBox]::Show(
					"Failed creating home directory:`n$($_.Exception.Message)",
					"File Error",
					[System.Windows.Forms.MessageBoxButtons]::OK,
					[System.Windows.Forms.MessageBoxIcon]::Error
				)
				$result.Text += "`nError creating home directory: $($_.Exception.Message)"
			}
		}



        # Add to initial groups (non-fatal)
        try { Add-ADGroupMember -Identity "ADD GROUP NAME HERE" -Members $username -ErrorAction Stop } catch { $result.Text += "`nCould not add $user to group: $($_.Exception.Message)" }
        try { Add-ADGroupMember -Identity "ADD GROUP NAME HERE" -Members $username -ErrorAction Stop } catch { $result.Text += "`nCould not add $user to group: $($_.Exception.Message)" }
        try { Add-ADGroupMember -Identity "ADD GROUP NAME HERE" -Members $username -ErrorAction Stop } catch { $result.Text += "`nCould not add $user to group: $($_.Exception.Message)" }

        # Show credentials dialog modal to main form
        $credentialsForm = New-Object System.Windows.Forms.Form
        $credentialsForm.Text = "New Account"
        $credentialsForm.Size = New-Object System.Drawing.Size(320, 160)
        $credentialsForm.StartPosition = "CenterParent"
        $credentialsForm.FormBorderStyle = "FixedDialog"
        $credentialsForm.MinimizeBox = $false
        $credentialsForm.MaximizeBox = $false

        $userLabel = New-Object System.Windows.Forms.Label
        $userLabel.Text = "Username:"
        $userLabel.Location = New-Object System.Drawing.Point(10, 10)
        $userLabel.Size = New-Object System.Drawing.Size(75, 20)
        $credentialsForm.Controls.Add($userLabel)

        $userBox = New-Object System.Windows.Forms.TextBox
        $userBox.Text = $username
        $userBox.Location = New-Object System.Drawing.Point(95, 10)
        $userBox.Size = New-Object System.Drawing.Size(200, 20)
        $userBox.ReadOnly = $true
        $credentialsForm.Controls.Add($userBox)

        $passLabel = New-Object System.Windows.Forms.Label
        $passLabel.Text = "Password:"
        $passLabel.Location = New-Object System.Drawing.Point(10, 40)
        $passLabel.Size = New-Object System.Drawing.Size(75, 20)
        $credentialsForm.Controls.Add($passLabel)

        $passBox = New-Object System.Windows.Forms.TextBox
        $passBox.Text = $generatedPassword
        $passBox.Location = New-Object System.Drawing.Point(95, 40)
        $passBox.Size = New-Object System.Drawing.Size(200, 20)
        $passBox.ReadOnly = $true
        $credentialsForm.Controls.Add($passBox)

        $okButton = New-Object System.Windows.Forms.Button
        $okButton.Text = "OK"
        $okButton.Location = New-Object System.Drawing.Point(110, 75)
        $okButton.Size = New-Object System.Drawing.Size(90, 30)
        $okButton.Add_Click({ $credentialsForm.Close() })
        $credentialsForm.Controls.Add($okButton)

        [void]$credentialsForm.ShowDialog($form)

        # Role-based group add (non-fatal)
        $roleType = $roleDropdown.SelectedItem.ToString()

        if ($roleType -eq "Faculty" -or $roleType -eq "Staff") {

            $groupName = "$roleType - $department"

            try {
                Add-ADGroupMember -Identity $groupName -Members $username -ErrorAction Stop
                $result.Text += "`nAdded to group: $groupName"
            }
            catch {
                $result.Text += "`nCould not add to group '$groupName': $($_.Exception.Message)"
            }

        }

        $result.Text = "User '$fullname' created in $department OU.`nUsername: $username"

    } catch {
        $result.Text = "Error: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show("An unexpected error occurred:`n$($_.Exception.Message)","Error",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)
        Log "Submit event exception: $($_.Exception.ToString())"
    }

    $form.Close()
    $form.Dispose()
    
})

# Auto-focus first input
$form.Add_Shown({ $inputs["Username"].Focus() })

# Show the main form as a modal dialog (single message loop)
[void]$form.ShowDialog()
Log "Form closed; script ending."
