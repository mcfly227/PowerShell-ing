# Get all guest users in your Entra Environment
#Requires -Modules Microsoft.Graph.Users
Import-Module Microsoft.graph.users
Import-Module Microsoft.Graph.authentication
# Connect to Microsoft Graph
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow
Connect-MgGraph -Scopes "User.Read.All"

Write-Host "Retrieving guest users..." -ForegroundColor Yellow

try {
    # Get all guest users with required properties
    $guestUsers = Get-MgUser -Filter "userType eq 'Guest'" -All `
        -Property "Id,DisplayName,Mail,UserPrincipalName,CreatedDateTime,UserType,ExternalUserState,ExternalUserStateChangeDateTime"
    
    Write-Host "Processing $($guestUsers.Count) guest users..." -ForegroundColor Yellow
    
    # Process the data
    $report = foreach ($user in $guestUsers) {
        # Calculate days since creation
        $daysSinceCreation = if ($user.CreatedDateTime) {
            [math]::Round((New-TimeSpan -Start $user.CreatedDateTime -End (Get-Date)).TotalDays, 0)
        } else {
            "Unknown"
        }
        
        # Extract email from UPN if Mail is empty (common for pending guests)
        $emailAddress = if ($user.Mail) {
            $user.Mail
        } elseif ($user.UserPrincipalName -match "(.+)#EXT#") {
            $matches[1] -replace "_", "@"
        } else {
            "No Email Found"
        }
        
        [PSCustomObject]@{
            DisplayName           = $user.DisplayName
            Email                 = $emailAddress
            UserPrincipalName     = $user.UserPrincipalName
            ExternalUserState     = $user.ExternalUserState
            CreatedDateTime       = if ($user.CreatedDateTime) { $user.CreatedDateTime.ToString("yyyy-MM-dd HH:mm:ss") } else { "" }
            DaysSinceCreation     = $daysSinceCreation
            StateChangeDateTime   = if ($user.ExternalUserStateChangeDateTime) { $user.ExternalUserStateChangeDateTime.ToString("yyyy-MM-dd HH:mm:ss") } else { "" }
            UserId                = $user.Id
        }
    }
    
    # Sort by days since creation (oldest first for cleanup purposes)
    $sortedReport = $report | Sort-Object DaysSinceCreation -Descending
    
    # Create timestamped filename
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $exportPath = "C:\temp\EntraGuestUsers_$timestamp.csv"
    
    # Export to CSV
    $sortedReport | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8
    
    # Display summary
    Write-Host "`nGuest User Summary:" -ForegroundColor Cyan
    Write-Host "==================" -ForegroundColor Cyan
    Write-Host "Total guest users: $($report.Count)" -ForegroundColor Green
    Write-Host "Accepted invites: $(($report | Where-Object ExternalUserState -eq 'Accepted').Count)" -ForegroundColor Green
    Write-Host "Pending invites: $(($report | Where-Object ExternalUserState -eq 'PendingAcceptance').Count)" -ForegroundColor Yellow
    Write-Host "`nCSV exported to: $exportPath" -ForegroundColor Green
    
    # Show first few rows as preview
    Write-Host "`nFirst 5 records preview:" -ForegroundColor Cyan
    $sortedReport | Select-Object -First 5 | Format-Table -Property DisplayName, Email, ExternalUserState, DaysSinceCreation -AutoSize
    
} catch {
    Write-Error "Error retrieving guest users: $($_.Exception.Message)"
} finally {
    # Disconnect from Graph
    Disconnect-MgGraph
    Write-Host "Disconnected from Microsoft Graph" -ForegroundColor Yellow
}