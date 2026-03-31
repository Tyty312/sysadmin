<#
This script must be setup in task scheduler to run as often as you would like
in its current state. Everytime the script is run, it will check the current 
members of the group you want to monitor and compare it to the list of members
the previous time it was run. If there is a difference in the two, it will email
all recipients. YOU WILL RECEIVE AN EMAIL THE FIRST TIME THE SCRIPT IS RUN.

I use this to ensure nobody receives access to our admin level groups who
do not need access to said groups.
#>

Import-Module ActiveDirectory

# --- CONFIGURATION ---
$GroupName   = ""        # Name of the group you want to monitor
$BaselineFile = "C:\Temp\GroupMembers.txt"  # File to store last known members
$SmtpServer  = ""    # Your SMTP server
$From        = ""  # From address
$To          = ""   # Recipient(s) - can be comma-separated

# --- GET CURRENT MEMBERS ---
$CurrentMembers = Get-ADGroupMember -Identity $GroupName -Recursive |
                  Select-Object -ExpandProperty SamAccountName |
                  Sort-Object

# --- LOAD BASELINE ---
if (Test-Path $BaselineFile) {
    $OldMembers = Get-Content $BaselineFile
} else {
    $OldMembers = @()
}

# --- COMPARE ---
$NewMembers = $CurrentMembers | Where-Object {$_ -notin $OldMembers}
$RemovedMembers = $OldMembers | Where-Object {$_ -notin $CurrentMembers}

# --- ALERT IF CHANGES ---
if ($NewMembers -or $RemovedMembers) {
    $Body = "Changes detected in group '$GroupName':`n"

    if ($NewMembers) {
        $Body += "`nNew Members:`n$($NewMembers -join "`n")"
    }
    if ($RemovedMembers) {
        $Body += "`nRemoved Members:`n$($RemovedMembers -join "`n")"
    }

    Send-MailMessage -From $From -To $To -Subject "Group $GroupName membership change detected" -Body $Body -SmtpServer $SmtpServer
}

# --- UPDATE BASELINE ---
$CurrentMembers | Out-File $BaselineFile
