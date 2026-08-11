<#
.SYNOPSIS
    Exports all Active Directory users and the date/time their password
    was last changed to a CSV file.

.DESCRIPTION
    Queries Active Directory for every user account, retrieves the
    PasswordLastSet attribute, and writes the results to a CSV.
    Accounts that have never had a password set are reported as "Never".

.NOTES
    Requires the ActiveDirectory module (part of RSAT, or present on
    a Domain Controller). Run from an account with read access to AD.
#>

# --- Configuration ---------------------------------------------------------
$OutputPath = "C:\Temp\UserPasswordLastSet.csv"   # change as needed
# ---------------------------------------------------------------------------

# Make sure the AD module is available
Import-Module ActiveDirectory -ErrorAction Stop

# Ensure the output folder exists
$OutputFolder = Split-Path -Path $OutputPath -Parent
if (-not (Test-Path -Path $OutputFolder)) {
    New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
}

# Gather users. -Filter * returns all users; pull only the properties we need.
Get-ADUser -Filter * -Properties SamAccountName, Name, PasswordLastSet, Enabled |
    Select-Object `
        @{ Name = 'Username';        Expression = { $_.SamAccountName } },
        @{ Name = 'DisplayName';     Expression = { $_.Name } },
        @{ Name = 'Enabled';         Expression = { $_.Enabled } },
        @{ Name = 'PasswordLastSet'; Expression = {
                if ($_.PasswordLastSet) { $_.PasswordLastSet }
                else                    { 'Never' }
            }
        } |
    Sort-Object Username |
    Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

Write-Host "Export complete: $OutputPath" -ForegroundColor Green