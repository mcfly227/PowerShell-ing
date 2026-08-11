<#
.SYNOPSIS
    Resets passwords for a list of Active Directory users from a CSV, then
    exports the resulting username/password pairs to a CSV.

.DESCRIPTION
    Reads an input CSV containing one column of usernames (default column:
    SamAccountName), generates a cryptographically random, complex password
    for each user, resets the AD account password, and writes the results
    (username, password, status, timestamp) to an output CSV.

    Supports -WhatIf for a safe dry run.

.PARAMETER InputCsv
    Path to the source CSV. Must contain the column named by -UserColumn.

.PARAMETER OutputCsv
    Path for the results CSV. Defaults to a timestamped file in the current dir.

.PARAMETER UserColumn
    Name of the column in the input CSV that holds the username.
    Default: SamAccountName.

.PARAMETER PasswordLength
    Length of generated passwords (minimum 8). Default: 16.

.PARAMETER ForceChangeAtLogon
    If set, forces each user to change their password at next sign-in
    (recommended).

.EXAMPLE
    .\Reset-UserPasswords.ps1 -InputCsv .\users.csv -ForceChangeAtLogon -WhatIf
    Dry run — shows what would happen without changing anything.

.EXAMPLE
    .\Reset-UserPasswords.ps1 -InputCsv .\users.csv -OutputCsv .\results.csv -ForceChangeAtLogon

.NOTES
    The output CSV contains PLAINTEXT passwords. Treat it as a secret:
    restrict access, distribute securely, and delete it once passwords
    have been handed out.
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [string]$InputCsv,

    [string]$OutputCsv = ".\PasswordReset_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv",

    [string]$UserColumn = 'SamAccountName',

    [ValidateRange(8, 128)]
    [int]$PasswordLength = 16,

    [switch]$ForceChangeAtLogon
)

function New-RandomPassword {
    <#
        Generates a cryptographically secure password guaranteed to contain
        at least one upper, lower, digit, and special character. Ambiguous
        characters (0/O, 1/l/I) are excluded for readability.
    #>
    [CmdletBinding()]
    param([int]$Length = 16)

    if ($Length -lt 4) { $Length = 4 }

    $sets = @(
        'ABCDEFGHJKLMNPQRSTUVWXYZ',   # upper (no I, O)
        'abcdefghijkmnpqrstuvwxyz',   # lower (no l, o)
        '23456789',                   # digits (no 0, 1)
        '!@#$%^&*()-_=+'              # special
    )
    $all = -join $sets

    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $randIndex = {
            param([int]$max)
            $bytes = [byte[]]::new(4)
            $rng.GetBytes($bytes)
            [int]([System.BitConverter]::ToUInt32($bytes, 0) % $max)
        }

        # One guaranteed character from each set
        $chars = foreach ($set in $sets) { $set[(& $randIndex $set.Length)] }

        # Fill the rest from the full pool
        for ($i = $chars.Count; $i -lt $Length; $i++) {
            $chars += $all[(& $randIndex $all.Length)]
        }

        # Fisher-Yates shuffle so the guaranteed chars aren't always up front
        for ($i = $chars.Count - 1; $i -gt 0; $i--) {
            $j = & $randIndex ($i + 1)
            $tmp = $chars[$i]; $chars[$i] = $chars[$j]; $chars[$j] = $tmp
        }

        -join $chars
    }
    finally {
        $rng.Dispose()
    }
}

# --- Pre-flight checks -------------------------------------------------------

if (-not (Test-Path -LiteralPath $InputCsv)) {
    throw "Input CSV not found: $InputCsv"
}

try {
    Import-Module ActiveDirectory -ErrorAction Stop
}
catch {
    throw "Could not load the ActiveDirectory module. Run this on a machine with RSAT / AD tools installed. ($($_.Exception.Message))"
}

$users = Import-Csv -Path $InputCsv
if (-not ($users | Get-Member -Name $UserColumn -MemberType NoteProperty)) {
    throw "Input CSV has no column named '$UserColumn'. Use -UserColumn to specify the correct one."
}

# --- Process users -----------------------------------------------------------

$results = foreach ($row in $users) {
    $sam = ($row.$UserColumn).Trim()
    if ([string]::IsNullOrWhiteSpace($sam)) { continue }

    $record = [pscustomobject]@{
        SamAccountName = $sam
        Password       = ''
        Status         = ''
        TimeStamp      = (Get-Date).ToString('s')
    }

    try {
        $adUser   = Get-ADUser -Identity $sam -ErrorAction Stop
        $plainPw  = New-RandomPassword -Length $PasswordLength
        $securePw = ConvertTo-SecureString -String $plainPw -AsPlainText -Force

        if ($PSCmdlet.ShouldProcess($sam, 'Reset password')) {
            Set-ADAccountPassword -Identity $adUser -Reset -NewPassword $securePw -ErrorAction Stop

            if ($ForceChangeAtLogon) {
                Set-ADUser -Identity $adUser -ChangePasswordAtLogon $true -ErrorAction Stop
            }

            $record.Password = $plainPw
            $record.Status   = 'Success'
        }
        else {
            $record.Status = 'Skipped (WhatIf)'
        }
    }
    catch {
        $record.Status = "Failed: $($_.Exception.Message)"
    }

    $record
}

# --- Output ------------------------------------------------------------------

$results | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8

$success = @($results | Where-Object Status -eq 'Success').Count
$failed  = @($results | Where-Object Status -like 'Failed*').Count

Write-Host ""
Write-Host "Done. $success reset, $failed failed." -ForegroundColor Cyan
Write-Host "Results written to: $OutputCsv" -ForegroundColor Cyan
Write-Host "Reminder: that file contains plaintext passwords - secure or delete it after use." -ForegroundColor Yellow