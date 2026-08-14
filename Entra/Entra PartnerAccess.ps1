#Have you ever wanted to see who your B2B collaborators are? the below script will give you details on each org. Including compliance
#Requires -Modules Microsoft.Graph.Identity.DirectoryManagement, Microsoft.Graph.Users, Microsoft.Graph.Groups

# Connect to Microsoft Graph with required scopes
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow
Connect-MgGraph -Scopes "Organization.Read.All", "User.Read.All", "Directory.Read.All", "RoleManagement.Read.Directory", "Group.Read.All"

Write-Host "Retrieving partner organization data..." -ForegroundColor Yellow

try {
    # Get all partner organizations (crossTenantAccessPolicy)
    Write-Host "Getting cross-tenant access policies..." -ForegroundColor Yellow
    $crossTenantPolicy = Get-MgPolicyCrossTenantAccessPolicyPartner -All

    # Get all directory roles for later reference
    Write-Host "Getting directory roles..." -ForegroundColor Yellow
    $directoryRoles = Get-MgDirectoryRole -All

    # Get all guest users to identify partner domains
    Write-Host "Getting guest users to identify partner domains..." -ForegroundColor Yellow
    $guestUsers = Get-MgUser -Filter "userType eq 'Guest'" -All -Property "Id,DisplayName,Mail,UserPrincipalName,CreatedDateTime,CompanyName"

    $report = @()

    # Process cross-tenant access policies
    foreach ($partner in $crossTenantPolicy) {
        Write-Host "Processing partner: $($partner.TenantId)" -ForegroundColor Gray
        
        try {
            # Get organization info for the partner
            $partnerOrg = $null
            try {
                $partnerOrg = Get-MgOrganization -OrganizationId $partner.TenantId -ErrorAction SilentlyContinue
            } catch {
                Write-Host "Could not retrieve org info for $($partner.TenantId)" -ForegroundColor Yellow
            }

            # Get users from this partner domain
            $partnerDomain = if ($partnerOrg) { $partnerOrg.VerifiedDomains | Where-Object IsDefault | Select-Object -ExpandProperty Name } else { "Unknown" }
            $partnerUsers = $guestUsers | Where-Object { 
                $_.UserPrincipalName -like "*$($partner.TenantId)*" -or 
                ($partnerDomain -ne "Unknown" -and $_.Mail -like "*@$partnerDomain")
            }

            # Analyze access settings
            $inboundSettings = $partner.InboundTrust
            $b2bSettings = $partner.B2BCollaborationInbound
            $b2cSettings = $partner.B2BCollaborationOutbound

            $accessLevel = @()
            
            # Determine access levels based on settings
            if ($inboundSettings.IsMfaAccepted -eq $true) { $accessLevel += "MFA Trust" }
            if ($inboundSettings.IsCompliantDeviceAccepted -eq $true) { $accessLevel += "Compliant Device Trust" }
            if ($inboundSettings.IsHybridAzureADJoinedDeviceAccepted -eq $true) { $accessLevel += "Hybrid Join Trust" }
            
            if ($b2bSettings.Applications.AccessType -eq "allowed") { $accessLevel += "B2B Collaboration Allowed" }
            if ($b2bSettings.Applications.AccessType -eq "blocked") { $accessLevel += "B2B Collaboration Blocked" }
            
            $accessLevelString = if ($accessLevel.Count -gt 0) { $accessLevel -join ", " } else { "Default Policy" }

            $reportItem = [PSCustomObject]@{
                PartnerTenantId = $partner.TenantId
                PartnerName = if ($partnerOrg) { $partnerOrg.DisplayName } else { "Unknown Organization" }
                PartnerDomain = $partnerDomain
                ActiveGuestUsers = $partnerUsers.Count
                AccessLevel = $accessLevelString
                MfaTrusted = $inboundSettings.IsMfaAccepted
                CompliantDeviceTrusted = $inboundSettings.IsCompliantDeviceAccepted
                HybridJoinTrusted = $inboundSettings.IsHybridAzureADJoinedDeviceAccepted
                B2BCollaborationInbound = $b2bSettings.Applications.AccessType
                B2BCollaborationOutbound = $b2cSettings.Applications.AccessType
                AutoRedemption = $partner.AutomaticUserConsentSettings.InboundAllowed
                LastModified = $partner.LastModifiedDateTime
            }

            $report += $reportItem

        } catch {
            Write-Host "Error processing partner $($partner.TenantId): $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # Also check for partner domains not in cross-tenant policy but with guest users
    Write-Host "Checking for additional partner domains from guest users..." -ForegroundColor Yellow
    
    $guestDomains = $guestUsers | Where-Object { $_.Mail } | ForEach-Object {
        if ($_.Mail -match "@(.+)$") {
            $matches[1].ToLower()
        }
    } | Group-Object | Sort-Object Count -Descending

    foreach ($domainGroup in $guestDomains) {
        $domain = $domainGroup.Name
        $userCount = $domainGroup.Count
        
        # Skip if we already have this in our report
        if (-not ($report | Where-Object { $_.PartnerDomain -eq $domain })) {
            $reportItem = [PSCustomObject]@{
                PartnerTenantId = "Unknown"
                PartnerName = "Unknown Organization"
                PartnerDomain = $domain
                ActiveGuestUsers = $userCount
                AccessLevel = "Default Policy (No Explicit Configuration)"
                MfaTrusted = "Default"
                CompliantDeviceTrusted = "Default"
                HybridJoinTrusted = "Default"
                B2BCollaborationInbound = "Default"
                B2BCollaborationOutbound = "Default"
                AutoRedemption = "Default"
                LastModified = ""
            }
            $report += $reportItem
        }
    }

    # Sort by number of active guest users (descending)
    $sortedReport = $report | Sort-Object ActiveGuestUsers -Descending

    # Create timestamped filename
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $exportPath = "c:\temp\PartnerAccess_$timestamp.csv"
    
    # Export to CSV
    $sortedReport | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8
    
    # Display summary
    Write-Host "`nPartner Access Summary:" -ForegroundColor Cyan
    Write-Host "======================" -ForegroundColor Cyan
    Write-Host "Total partner organizations: $($report.Count)" -ForegroundColor Green
    Write-Host "Partners with explicit policies: $(($report | Where-Object { $_.PartnerTenantId -ne 'Unknown' }).Count)" -ForegroundColor Green
    Write-Host "Partners with MFA trust: $(($report | Where-Object { $_.MfaTrusted -eq $true }).Count)" -ForegroundColor Yellow
    Write-Host "Partners with device trust: $(($report | Where-Object { $_.CompliantDeviceTrusted -eq $true }).Count)" -ForegroundColor Yellow
    Write-Host "`nCSV exported to: $exportPath" -ForegroundColor Green
    
    # Show preview of top partners by guest user count
    Write-Host "`nTop 10 partners by guest user count:" -ForegroundColor Cyan
    $sortedReport | Select-Object -First 10 | Format-Table -Property PartnerName, PartnerDomain, ActiveGuestUsers, AccessLevel -AutoSize

} catch {
    Write-Error "Error retrieving partner data: $($_.Exception.Message)"
} finally {
    # Disconnect from Graph
    Disconnect-MgGraph
    Write-Host "Disconnected from Microsoft Graph" -ForegroundColor Yellow
}