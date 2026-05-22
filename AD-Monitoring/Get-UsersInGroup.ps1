# Change these groups to whatever groups you are needing to see the user list for
$Groups = @(
    "Group1",
    "Group2",
    "Group3"
    )


$Today = Get-Date

$Results = foreach ($Group in $Groups) {
    Get-ADGroupMember -Identity $Group -Recursive |
    Where-Object { $_.objectClass -eq "user" } |
    ForEach-Object {
        $User = Get-ADUser -Identity $_.SamAccountName -Properties DisplayName, Enabled, AccountExpirationDate

        $Status = if (-not $User.Enabled) {
            "Disabled"
        }
        elseif ($User.AccountExpirationDate -and $User.AccountExpirationDate -lt $Today) {
            "Expired"
        }
        else {
            "Enabled"
        }

        [PSCustomObject]@{
            Group           = $Group
            SamAccountName  = $User.SamAccountName
            DisplayName     = $User.DisplayName
            Status          = $Status
        }
    }
}

# Deduplicate and merge group names
$Final = $Results |
Group-Object SamAccountName |
ForEach-Object {
    [PSCustomObject]@{
        SamAccountName = $_.Name
        DisplayName    = ($_.Group | Select-Object -First 1).DisplayName
        Status         = ($_.Group | Select-Object -First 1).Status
    }
} |
Sort-Object SamAccountName

# Display
$Final | Format-Table -Wrap -AutoSize
