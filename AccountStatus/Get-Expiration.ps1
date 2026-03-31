param([string]$Username)

if (-not $Username) {
    $Username = Read-Host "Enter username"
}

Write-Host "SCRIPT STARTED, Username = $Username"
Start-Sleep -Seconds 2

# Ensure username was passed from launcher
if ([string]::IsNullOrWhiteSpace($Username)) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        "No username was provided by the launcher.","Error","OK","Error"
    )
    exit
}

# ------------------------------
# Fetch AD user data
# ------------------------------
try {
    $user = Get-ADUser -Identity $Username -Properties DisplayName, Enabled, PasswordLastSet, AccountExpires
}
catch {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        "User '$Username' not found.","Error","OK","Error"
    )
    exit
}

# ------------------------------
# Build expiration data
# ------------------------------
$maxPasswordAge = (Get-ADDefaultDomainPasswordPolicy).MaxPasswordAge.Days
$passwordExpires = $user.PasswordLastSet.AddDays($maxPasswordAge)

if ($user.AccountExpires -eq 0 -or $user.AccountExpires -eq 9223372036854775807) {
    $accountExpires = "N/A"
}
else {
    $accountExpires = [datetime]::FromFileTime($user.AccountExpires)
}

# ------------------------------
# Build report text
# ------------------------------
$report = @"
Report for: $Username
--------------------------------------------
   Name:              $($user.DisplayName)
   Enabled:           $($user.Enabled)
   Account Expires:   $accountExpires

   Password Set:      $($user.PasswordLastSet)
   Password Expires:  $passwordExpires
   Max Password Age:  $maxPasswordAge days
--------------------------------------------
"@

# ------------------------------
# Safe storage for GUI input
# ------------------------------
$reportDir = "C:\Temp\ADReports"
if (-not (Test-Path $reportDir)) {
    New-Item -Path $reportDir -ItemType Directory -Force | Out-Null
}

$tempFile = Join-Path $reportDir ("ADReport_{0}_{1}.txt" -f $Username, (Get-Date -Format "MM-dd-yyyy"))
Set-Content -Path $tempFile -Value $report

# ------------------------------
# GUI Viewer (clean, no highlight)
# ------------------------------
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = "AD Expiration Report"
$form.Size = New-Object System.Drawing.Size(360,200)
$form.StartPosition = "CenterScreen"
$form.TopMost = $true

$tb = New-Object System.Windows.Forms.TextBox
$tb.Multiline = $true
$tb.ReadOnly  = $true
$tb.ScrollBars = "Vertical"
$tb.Dock = "Fill"
$tb.Font = New-Object System.Drawing.Font("Consolas",10)
$tb.Text = (Get-Content $tempFile -Raw)

# Remove highlight on load
$form.Add_Shown({
    $tb.DeselectAll()
    $tb.SelectionStart = 0
    $tb.SelectionLength = 0
    $tb.HideSelection = $true

    # set focus to a hidden button (safe)
    $dummyBtn = New-Object System.Windows.Forms.Button
    $dummyBtn.Size = [System.Drawing.Size]::new(0,0)
    $dummyBtn.Location = [System.Drawing.Point]::new(0,0)
    $form.Controls.Add($dummyBtn)
    $form.ActiveControl = $dummyBtn
})


$form.Controls.Add($tb)
$form.ShowDialog()

exit
