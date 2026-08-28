<# M365 User Session Revocation Script
# Requires Microsoft Graph PowerShell SDK


.SYNOPSIS
    Revokes all M365 Sessions

.NOTES
    Use Case - Suspected compromise within your environment 
    Pair this script with my Local AD repo, Log off all AD users (if you are in a hybrid situation) and for added "fun" Toss in the bulk password reset script


#>
# Connect to Microsoft Graph with required permissions
Connect-MgGraph -Scopes "User.ReadWrite.All", "Directory.ReadWrite.All"

# Get all users
$users = Get-MgUser -All

$count = 0
$errors = @()

foreach ($user in $users) {
    try {
        # Revoke all refresh tokens for the user
        Revoke-MgUserSignInSession -UserId $user.Id
        Write-Host "Revoked sessions for: $($user.UserPrincipalName)" -ForegroundColor Green
        $count++
    }
    catch {
        Write-Host "Failed to revoke sessions for: $($user.UserPrincipalName)" -ForegroundColor Red
        $errors += [PSCustomObject]@{
            User  = $user.UserPrincipalName
            Error = $_.Exception.Message
        }
    }
}

Write-Host "Completed. Revoked sessions for $count users." -ForegroundColor Cyan

if ($errors.Count -gt 0) {
    Write-Host "Errors encountered: $($errors.Count)" -ForegroundColor Yellow
    $errors | Format-Table -AutoSize
}

# Disconnect when done
Disconnect-MgGraph