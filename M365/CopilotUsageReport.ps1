###############################################################
# Microsoft 365 Copilot Usage Report
# Author: David R. McFall
# Purpose:
#   Download Copilot Usage Report
#   Generate executive metrics
#   Produce Power BI-ready CSVs
###############################################################

#-------------------------------------------------------------
# CONFIGURATION
#-------------------------------------------------------------

$ReportPath = "C:\Reports\Copilot"

if (!(Test-Path $ReportPath)) {
    New-Item -Path $ReportPath -ItemType Directory -Force | Out-Null
}

$Today = Get-Date -Format "yyyy-MM-dd"

$RawCsv      = "$ReportPath\CopilotUsage-$Today.csv"
$SummaryCsv  = "$ReportPath\CopilotSummary-$Today.csv"
$InactiveCsv = "$ReportPath\CopilotInactiveUsers-$Today.csv"
$TopUsersCsv = "$ReportPath\CopilotTopUsers-$Today.csv"

# Reporting Period Options: D7, D30, D90, D180
$ReportingPeriod = "D30"

#-------------------------------------------------------------
# CONNECT TO GRAPH
# NOTE: Only import Authentication module - importing the full
# Microsoft.Graph module loads 100+ submodules and is what was
# making this slow. We don't need anything else for this task.
#-------------------------------------------------------------

Write-Host ""
Write-Host "Connecting to Microsoft Graph..."
Write-Host ""

Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

Connect-MgGraph -Scopes "Reports.Read.All", "Directory.Read.All" -NoWelcome

#-------------------------------------------------------------
# DOWNLOAD COPILOT USAGE REPORT
#-------------------------------------------------------------

Write-Host ""
Write-Host "Downloading Copilot Usage Report..."
Write-Host ""

$Uri = "https://graph.microsoft.com/beta/reports/getMicrosoft365CopilotUsageUserDetail(period='$ReportingPeriod')"

# Delete any existing file with this name first. Invoke-MgGraphRequest can
# leave stale/duplicated content behind if a same-named file already exists
# from an earlier run today, which causes "member already present" errors
# when the CSV is imported below.
if (Test-Path $RawCsv) {
    Remove-Item $RawCsv -Force
}

try {
    Invoke-MgGraphRequest -Method GET -Uri $Uri -OutputFilePath $RawCsv
    Write-Host "Report Saved:"
    Write-Host $RawCsv
}
catch {
    Write-Host "Unable to download report"
    Write-Host $_.Exception.Message
    break
}

#-------------------------------------------------------------
# IMPORT REPORT
#-------------------------------------------------------------

Write-Host ""
Write-Host "Processing Report..."
Write-Host ""

# Import-Csv fails outright if the header row has duplicate column names
# (the beta Copilot report has occasionally returned a duplicate
# "...LastActivityDate" column). Work around this by de-duplicating the
# header ourselves, rather than letting Import-Csv build the objects.
$RawLines = Get-Content -Path $RawCsv

if (!$RawLines -or $RawLines.Count -lt 2) {
    Write-Host "No data returned."
    break
}

$HeaderFields = ($RawLines[0]) -split ','
$SeenHeaders  = @{}
$UniqueHeaders = foreach ($Field in $HeaderFields) {
    $Clean = $Field.Trim('"')
    if ($SeenHeaders.ContainsKey($Clean)) {
        $SeenHeaders[$Clean]++
        "$Clean`_dup$($SeenHeaders[$Clean])"
    }
    else {
        $SeenHeaders[$Clean] = 0
        $Clean
    }
}

$DuplicateCount = ($SeenHeaders.Values | Where-Object { $_ -gt 0 }).Count
if ($DuplicateCount -gt 0) {
    Write-Host "Warning: $DuplicateCount duplicate column name(s) found in the raw CSV header and renamed to avoid import errors."
}

$Data = $RawLines | Select-Object -Skip 1 | ConvertFrom-Csv -Header $UniqueHeaders

if (!$Data) {
    Write-Host "No data returned."
    break
}

# If names/UPNs come back as "User_xxxx" instead of real values, your
# tenant has "Reports display concealed user, group, and site names"
# turned ON. Turn it off in the M365 admin center:
# Settings > Org settings > Reports, or via:
# Update-MgAdminReportSetting -DisplayConcealedNames:$false

#-------------------------------------------------------------
# NORMALIZE VALUES
#-------------------------------------------------------------

foreach ($User in $Data) {

    $Prompts = 0
    [int]::TryParse($User."Prompts submitted for All Apps", [ref]$Prompts) | Out-Null

    $User | Add-Member -MemberType NoteProperty -Name TotalPrompts -Value $Prompts -Force
    $User | Add-Member -MemberType NoteProperty -Name ActiveDays -Value ($User."Active Usage Days for All Apps") -Force
}

#-------------------------------------------------------------
# EXECUTIVE METRICS
#-------------------------------------------------------------

$TotalLicensedUsers = $Data.Count

$ActiveUsers = ($Data | Where-Object { $_.TotalPrompts -gt 0 }).Count

$InactiveUsers = ($Data | Where-Object { $_.TotalPrompts -eq 0 }).Count

$TotalPrompts = ($Data | Measure-Object TotalPrompts -Sum).Sum

$AveragePrompts = if ($TotalLicensedUsers -gt 0) {
    [Math]::Round(($TotalPrompts / $TotalLicensedUsers), 2)
} else { 0 }

$AdoptionRate = if ($TotalLicensedUsers -gt 0) {
    [Math]::Round((($ActiveUsers / $TotalLicensedUsers) * 100), 2)
} else { 0 }

#-------------------------------------------------------------
# FIND LOW USAGE USERS
#-------------------------------------------------------------

$LowUsageUsers = $Data | Where-Object { $_.TotalPrompts -lt 10 } | Sort-Object TotalPrompts

#-------------------------------------------------------------
# FIND NO USAGE USERS
#-------------------------------------------------------------

$InactiveList = $Data | Where-Object { $_.TotalPrompts -eq 0 }

#-------------------------------------------------------------
# TOP USERS
#-------------------------------------------------------------

$TopUsers = $Data | Sort-Object TotalPrompts -Descending | Select-Object -First 25

#-------------------------------------------------------------
# EXPORT SUPPORTING FILES
#-------------------------------------------------------------

$InactiveList |
    Select-Object DisplayName, "User Principal Name", "Last Activity Date", TotalPrompts, ActiveDays |
    Export-Csv -NoTypeInformation -Path $InactiveCsv

$TopUsers |
    Select-Object DisplayName, "User Principal Name", TotalPrompts, ActiveDays |
    Export-Csv -NoTypeInformation -Path $TopUsersCsv

#-------------------------------------------------------------
# BUILD EXECUTIVE SUMMARY
#-------------------------------------------------------------

$Summary = @(
    [PSCustomObject]@{ Metric = "Total Licensed Users";      Value = $TotalLicensedUsers }
    [PSCustomObject]@{ Metric = "Active Users";               Value = $ActiveUsers }
    [PSCustomObject]@{ Metric = "Inactive Users";             Value = $InactiveUsers }
    [PSCustomObject]@{ Metric = "Adoption Rate %";            Value = $AdoptionRate }
    [PSCustomObject]@{ Metric = "Total Prompts";              Value = $TotalPrompts }
    [PSCustomObject]@{ Metric = "Average Prompts Per User";   Value = $AveragePrompts }
)

$Summary | Export-Csv -NoTypeInformation -Path $SummaryCsv

#-------------------------------------------------------------
# OUTPUT SUMMARY
#-------------------------------------------------------------

Write-Host ""
Write-Host "========================================="
Write-Host " MICROSOFT COPILOT EXECUTIVE SUMMARY"
Write-Host "========================================="
Write-Host ""

Write-Host "Licensed Users     : $TotalLicensedUsers"
Write-Host "Active Users       : $ActiveUsers"
Write-Host "Inactive Users     : $InactiveUsers"
Write-Host "Adoption Rate      : $AdoptionRate%"
Write-Host "Total Prompts      : $TotalPrompts"
Write-Host "Avg Prompts/User   : $AveragePrompts"

Write-Host ""
Write-Host "Summary File:"
Write-Host $SummaryCsv

Write-Host ""
Write-Host "Inactive Users:"
Write-Host $InactiveCsv

Write-Host ""
Write-Host "Top Users:"
Write-Host $TopUsersCsv

Write-Host ""
Write-Host "Complete!"

Disconnect-MgGraph | Out-Null
