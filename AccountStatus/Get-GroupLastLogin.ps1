param(
    [Parameter(Mandatory=$true)]
    [string]$GroupName
)

# Get all users in the group
$users = Get-ADGroupMember -Identity $GroupName -Recursive | Where-Object {
    $_.objectClass -eq 'user'
}

# Get last logon info
$result = foreach ($user in $users) {
    $adUser = Get-ADUser $user.SamAccountName -Properties lastLogonDate, pwdLastSet, displayName

    [PSCustomObject]@{
        Name            = $adUser.displayName
        SamAccountName  = $adUser.SamAccountName
        LastLogonDate   = $adUser.lastLogonDate
        PasswordLastSet = if ($adUser.pwdLastSet -ne 0) {
        [DateTime]::FromFileTime($adUser.pwdLastSet)
    }
}
}

# Output nicely
$result | Sort-Object LastLogonDate | Format-Table -AutoSize
