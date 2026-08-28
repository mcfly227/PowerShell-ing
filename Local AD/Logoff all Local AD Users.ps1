#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Logs off all Active Directory domain users currently logged into the local machine.
    
.DESCRIPTION
    This script identifies all user sessions on the local computer and logs off
    users who are domain accounts (Active Directory users), while optionally
    preserving local accounts and the current session.
    
.PARAMETER ExcludeCurrentUser
    If specified, excludes the currently running user from being logged off.
    
.PARAMETER WhatIf
    Shows what would happen without actually logging anyone off.
    
.EXAMPLE
    .\LogoffADUsers.ps1
    Logs off all AD users.
    
.EXAMPLE
    .\LogoffADUsers.ps1 -ExcludeCurrentUser
    Logs off all AD users except the one running the script.
    
.EXAMPLE
    .\LogoffADUsers.ps1 -WhatIf
    Shows which users would be logged off without taking action.
#>

param(
    [switch]$ExcludeCurrentUser,
    [switch]$WhatIf
)

# Get the computer's domain
$computerSystem = Get-WmiObject -Class Win32_ComputerSystem
$machineDomain = $computerSystem.Domain
$machineName = $env:COMPUTERNAME

# Check if the machine is domain-joined
if (-not $computerSystem.PartOfDomain) {
    Write-Warning "This computer is not joined to a domain. No AD users to log off."
    exit 0
}

Write-Host "Computer: $machineName" -ForegroundColor Cyan
Write-Host "Domain: $machineDomain" -ForegroundColor Cyan
Write-Host ""

# Get current user if we need to exclude them
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

# Get all logged-on sessions using quser (query user)
try {
    $sessions = quser 2>&1
    
    if ($sessions -match "No User exists") {
        Write-Host "No users currently logged in." -ForegroundColor Yellow
        exit 0
    }
} catch {
    Write-Error "Failed to query user sessions: $_"
    exit 1
}

# Parse quser output (skip header line)
$loggedOffCount = 0
$skippedCount = 0

foreach ($line in $sessions | Select-Object -Skip 1) {
    # Parse the quser output - handle both console and RDP sessions
    if ($line -match '^\s*(\S+)\s+(\S*)\s+(\d+)\s+(\S+)\s+(\S+)\s+(.*)$' -or 
        $line -match '^\s*>?(\S+)\s+(\S*)\s+(\d+)\s+(\S+)\s+(\S+)\s+(.*)$') {
        
        $username = $matches[1].TrimStart('>')
        $sessionId = $matches[3]
        
        # Try to determine if user is a domain user
        # Get user's domain by checking their profile
        $userAccount = $null
        
        try {
            # Check if user exists in domain
            $searcher = [adsisearcher]"(&(objectCategory=person)(objectClass=user)(sAMAccountName=$username))"
            $userAccount = $searcher.FindOne()
        } catch {
            # ADSI search failed - might not have access or user is local
        }
        
        $isDomainUser = $null -ne $userAccount
        
        # Also check via Win32_LoggedOnUser for more reliable domain detection
        $loggedOnUsers = Get-WmiObject -Class Win32_LoggedOnUser | 
            Where-Object { $_.Antecedent -match "Name=`"$username`"" }
        
        foreach ($logon in $loggedOnUsers) {
            if ($logon.Antecedent -match 'Domain="([^"]+)"') {
                $userDomain = $matches[1]
                # If domain matches machine domain (not local machine name), it's a domain user
                if ($userDomain -ne $machineName -and $userDomain -ne "NT AUTHORITY") {
                    $isDomainUser = $true
                    break
                }
            }
        }
        
        $fullUsername = "$userDomain\$username"
        
        if ($isDomainUser) {
            # Check if we should exclude current user
            if ($ExcludeCurrentUser -and $currentUser -like "*\$username") {
                Write-Host "SKIPPED (current user): $fullUsername (Session $sessionId)" -ForegroundColor Yellow
                $skippedCount++
                continue
            }
            
            if ($WhatIf) {
                Write-Host "WOULD LOG OFF: $fullUsername (Session $sessionId)" -ForegroundColor Magenta
            } else {
                Write-Host "Logging off: $fullUsername (Session $sessionId)" -ForegroundColor Red
                try {
                    logoff $sessionId
                    $loggedOffCount++
                } catch {
                    Write-Warning "Failed to log off session $sessionId : $_"
                }
            }
        } else {
            Write-Host "SKIPPED (local/system): $username (Session $sessionId)" -ForegroundColor Gray
            $skippedCount++
        }
    }
}

Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
if ($WhatIf) {
    Write-Host "  Would log off: $loggedOffCount AD user(s)" -ForegroundColor Magenta
} else {
    Write-Host "  Logged off: $loggedOffCount AD user(s)" -ForegroundColor Green
}
Write-Host "  Skipped: $skippedCount session(s)" -ForegroundColor Yellow