<#
.SYNOPSIS
    Creates a Microsoft Planner board for (insert variable here).
    This is an example for an environment that I work in you can adjust the names rules and buckets as you see fit
    This is simply to be used as a template/guide
    Reach out if you have questions or need assistance
    

.DESCRIPTION
    This script uses Microsoft Graph API to create a Planner plan with buckets 
    and tasks based on the Defender Firewall Policy Project Plan document.

.NOTES
    Prerequisites:
    1. Install Microsoft.Graph module: Install-Module Microsoft.Graph -Scope CurrentUser
    2. You need permissions: Tasks.ReadWrite, Group.ReadWrite.All
    3. Update the $existingGroupName variable to match your Microsoft 365 Group name

    Author: David R. McFall
    Date: January 2026
#>

#region Setup and Connection

Import-Module Microsoft.Graph.Groups
Import-Module Microsoft.Graph.Planner

# Connect to Microsoft Graph
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes "Group.ReadWrite.All", "Tasks.ReadWrite"

# Verify permissions
Write-Host "Verifying permissions..." -ForegroundColor Cyan
$context = Get-MgContext
Write-Host "Connected as: $($context.Account)" -ForegroundColor Gray
Write-Host "Scopes granted: $($context.Scopes -join ', ')" -ForegroundColor Gray
Write-Host "Note: You must be the owner of the Group or have Planner admin rights" -ForegroundColor Yellow

#endregion Setup and Connection

#region Configuration - UPDATE THESE VALUES!
$existingGroupName = "Use your own group name"
$planTitle = "(use your own This is an example of a CIS crontrol)Disable Merging of Local Defender Firewall Rules (Public Profile)"
#endregion Configuration

#region Find Group

Write-Host "Finding existing Microsoft 365 Group..." -ForegroundColor Cyan
$group = Get-MgGroup -Filter "displayName eq '$existingGroupName'"

if (-not $group) {
    Write-Host "Error: Could not find group '$existingGroupName'" -ForegroundColor Red
    Write-Host "Available Microsoft 365 Groups:" -ForegroundColor Yellow
    Get-MgGroup -Filter "groupTypes/any(c:c eq 'Unified')" -All | Select-Object DisplayName, Id, Mail | Format-Table -AutoSize
    throw "Group not found. Please update the `$existingGroupName variable with a valid group name from the list above."
}

# Verify it's a Microsoft 365 Group (unified group)
if ($group.GroupTypes -notcontains "Unified") {
    Write-Host "Error: '$existingGroupName' is not a Microsoft 365 Group (unified group)." -ForegroundColor Red
    Write-Host "Planner only works with Microsoft 365 Groups." -ForegroundColor Red
    Write-Host "Available Microsoft 365 Groups:" -ForegroundColor Yellow
    Get-MgGroup -Filter "groupTypes/any(c:c eq 'Unified')" -All | Select-Object DisplayName, Id, Mail | Format-Table -AutoSize
    throw "Invalid group type. Please use a Microsoft 365 Group."
}

Write-Host "Using group: $($group.DisplayName) ($($group.Id))" -ForegroundColor Green

#endregion Find Group

#region Functions

function New-PlannerPlan {
    param(
        [string]$GroupId,
        [string]$Title
    )
    
    Write-Host "Creating Planner plan: $Title" -ForegroundColor Cyan
    
    $planBody = @{
        owner = $GroupId
        title = $Title
    }
    
    try {
        $plan = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/planner/plans" -Body ($planBody | ConvertTo-Json)
        Write-Host "Plan created successfully. Plan ID: $($plan.id)" -ForegroundColor Green
        return $plan
    }
    catch {
        throw "Failed to create plan: $_"
    }
}

function New-PlannerBucket {
    param(
        [string]$PlanId,
        [string]$Name
    )
    
    Write-Host "  Creating bucket: $Name" -ForegroundColor Yellow
    
    # Don't specify orderHint - let Planner assign it automatically
    $bucketBody = @{
        name   = $Name
        planId = $PlanId
    }
    
    try {
        $bucket = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/planner/buckets" -Body ($bucketBody | ConvertTo-Json)
        Start-Sleep -Milliseconds 500  # Rate limiting
        return $bucket
    }
    catch {
        throw "Failed to create bucket '$Name': $_"
    }
}

function New-PlannerTask {
    param(
        [string]$PlanId,
        [string]$BucketId,
        [string]$Title,
        [int]$PercentComplete = 0,
        [string]$Priority = "Medium",
        [hashtable]$Checklist = @{}
    )
    
    Write-Host "    Creating task: $Title" -ForegroundColor Gray
    
    # Map priority to Planner values (1=Urgent, 3=Important, 5=Medium, 9=Low)
    $priorityMap = @{
        "Urgent"    = 1
        "Important" = 3
        "Medium"    = 5
        "Low"       = 9
    }
    
    # Don't specify orderHint - let Planner assign it automatically
    $taskBody = @{
        planId          = $PlanId
        bucketId        = $BucketId
        title           = $Title
        percentComplete = $PercentComplete
        priority        = $priorityMap[$Priority]
    }
    
    try {
        $task = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/planner/tasks" -Body ($taskBody | ConvertTo-Json)
        
        # Add checklist items if provided
        if ($Checklist.Count -gt 0) {
            Add-TaskChecklist -TaskId $task.id -ChecklistItems $Checklist
        }
        
        Start-Sleep -Milliseconds 500  # Rate limiting
        return $task
    }
    catch {
        throw "Failed to create task '$Title': $_"
    }
}

function Add-TaskChecklist {
    param(
        [string]$TaskId,
        [hashtable]$ChecklistItems
    )
    
    try {
        # Get current task details to get etag
        $taskDetails = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/planner/tasks/$TaskId/details"
        $etag = $taskDetails.'@odata.etag'
        
        $checklistBody = @{
            checklist = $ChecklistItems
        }
        
        $headers = @{
            "If-Match" = $etag
        }
        
        Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/planner/tasks/$TaskId/details" -Body ($checklistBody | ConvertTo-Json -Depth 10) -Headers $headers
    }
    catch {
        Write-Warning "Failed to add checklist to task: $_"
    }
}

function New-ChecklistItem {
    param(
        [string]$Title,
        [bool]$IsChecked = $false
    )
    
    return @{
        "@odata.type" = "#microsoft.graph.plannerChecklistItem"
        title         = $Title
        isChecked     = $IsChecked
    }
}

#endregion Functions

#region Main Script

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "(again this is dynamic for your situation)Defender Firewall Policy Planner Board Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Create the plan
$plan = New-PlannerPlan -GroupId $group.Id -Title $planTitle
$planId = $plan.id

Write-Host "Creating buckets and tasks..." -ForegroundColor Cyan

# Define buckets in order (will be created in reverse order so they appear correctly in Planner)
$bucketNames = @(
    "Backout Plan"
    "Phase 4 - Closeout"
    "Phase 3 - Rollout"
    "Phase 2 - Testing"
    "Phase 1 - Assessment & Early Pilot"
)

# Create buckets and store their IDs
$buckets = @{}
foreach ($bucketName in $bucketNames) {
    $bucket = New-PlannerBucket -PlanId $planId -Name $bucketName
    $buckets[$bucketName] = $bucket.id
}

# Define all tasks by bucket
$allTasks = @{
    "Phase 1 - Assessment & Early Pilot" = @(
        @{
            Title    = "Document policy assessment and reason for change"
            Priority = "Important"
            Checklist = @{
                "item1" = (New-ChecklistItem -Title "Document current firewall rule merging behavior")
                "item2" = (New-ChecklistItem -Title "Document security risks of allowing local policy merge")
                "item3" = (New-ChecklistItem -Title "Document intended security improvements")
            }
        },
        @{
            Title    = "Create Intune PowerShell script for registry configuration"
            Priority = "Urgent"
            Checklist = @{
                "item1" = (New-ChecklistItem -Title "Create script to set AllowLocalPolicyMerge = 0")
                "item2" = (New-ChecklistItem -Title "Registry path: HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\PublicProfile")
                "item3" = (New-ChecklistItem -Title "Test script locally before deployment")
                "item4" = (New-ChecklistItem -Title "Upload script to Intune")
            }
        },
        @{
            Title    = "Identify early pilot group (Helpdesk team)"
            Priority = "Important"
        },
        @{
            Title    = "Apply configuration to pilot group"
            Priority = "Urgent"
        },
        @{
            Title    = "Monitor pilot group for connectivity issues"
            Priority = "Important"
            Checklist = @{
                "item1" = (New-ChecklistItem -Title "Check for application connectivity issues")
                "item2" = (New-ChecklistItem -Title "Monitor helpdesk tickets for firewall-related issues")
                "item3" = (New-ChecklistItem -Title "Verify VPN connectivity")
                "item4" = (New-ChecklistItem -Title "Test common network applications")
            }
        },
        @{
            Title    = "Document pilot results"
            Priority = "Medium"
        }
    )
    "Phase 2 - Testing" = @(
        @{
            Title    = "Expand test group to IT department"
            Priority = "Urgent"
        },
        @{
            Title    = "Apply policy to IT department"
            Priority = "Urgent"
        },
        @{
            Title    = "Monitor IT department for one week"
            Priority = "Important"
            Checklist = @{
                "item1" = (New-ChecklistItem -Title "Day 1-2: Initial monitoring for immediate issues")
                "item2" = (New-ChecklistItem -Title "Day 3-5: Monitor for application-specific issues")
                "item3" = (New-ChecklistItem -Title "Day 6-7: Final validation and issue resolution")
                "item4" = (New-ChecklistItem -Title "Document any issues encountered")
            }
        },
        @{
            Title    = "Resolve any identified issues"
            Priority = "Important"
        },
        @{
            Title    = "Document expanded testing results"
            Priority = "Medium"
        }
    )
    "Phase 3 - Rollout" = @(
        @{
            Title    = "Apply policy to Autopatch Ring 1"
            Priority = "Urgent"
        },
        @{
            Title    = "Monitor Autopatch Ring 1 for one week"
            Priority = "Important"
            Checklist = @{
                "item1" = (New-ChecklistItem -Title "Monitor for connectivity issues")
                "item2" = (New-ChecklistItem -Title "Check compliance status in Intune")
                "item3" = (New-ChecklistItem -Title "Review helpdesk tickets")
            }
        },
        @{
            Title    = "Apply policy to Autopatch Ring 2"
            Priority = "Urgent"
        },
        @{
            Title    = "Monitor Autopatch Ring 2 for one week"
            Priority = "Important"
            Checklist = @{
                "item1" = (New-ChecklistItem -Title "Monitor for connectivity issues")
                "item2" = (New-ChecklistItem -Title "Check compliance status in Intune")
                "item3" = (New-ChecklistItem -Title "Review helpdesk tickets")
            }
        },
        @{
            Title    = "Apply policy to Autopatch Ring 3"
            Priority = "Urgent"
        },
        @{
            Title    = "Monitor Autopatch Ring 3 for one week"
            Priority = "Important"
            Checklist = @{
                "item1" = (New-ChecklistItem -Title "Monitor for connectivity issues")
                "item2" = (New-ChecklistItem -Title "Check compliance status in Intune")
                "item3" = (New-ChecklistItem -Title "Review helpdesk tickets")
            }
        },
        @{
            Title    = "Verify all rings successfully deployed"
            Priority = "Medium"
        }
    )
    "Phase 4 - Closeout" = @(
        @{
            Title    = "Update firewall configuration policy documentation"
            Priority = "Important"
            Checklist = @{
                "item1" = (New-ChecklistItem -Title "Update IT security documentation")
                "item2" = (New-ChecklistItem -Title "Update firewall policy runbooks")
                "item3" = (New-ChecklistItem -Title "Document final configuration settings")
            }
        },
        @{
            Title    = "Confirm compliance reporting in Intune"
            Priority = "Important"
            Checklist = @{
                "item1" = (New-ChecklistItem -Title "Verify all devices show compliant status")
                "item2" = (New-ChecklistItem -Title "Export compliance report for records")
                "item3" = (New-ChecklistItem -Title "Address any non-compliant devices")
            }
        },
        @{
            Title    = "Confirm compliance reporting in Microsoft Defender"
            Priority = "Important"
            Checklist = @{
                "item1" = (New-ChecklistItem -Title "Verify Defender portal shows correct firewall status")
                "item2" = (New-ChecklistItem -Title "Review security recommendations")
                "item3" = (New-ChecklistItem -Title "Export Defender compliance report")
            }
        },
        @{
            Title    = "Project closeout and final documentation"
            Priority = "Medium"
        }
    )
    "Backout Plan" = @(
        @{
            Title    = "Document backout procedure"
            Priority = "Important"
            Checklist = @{
                "item1" = (New-ChecklistItem -Title "Set AllowLocalPolicyMerge = 1 (REG_DWORD)")
                "item2" = (New-ChecklistItem -Title "Registry: HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\PublicProfile")
                "item3" = (New-ChecklistItem -Title "Create backout PowerShell script")
            }
        },
        @{
            Title    = "Create backout Intune script (if needed)"
            Priority = "Medium"
            Checklist = @{
                "item1" = (New-ChecklistItem -Title "Create script to restore AllowLocalPolicyMerge = 1")
                "item2" = (New-ChecklistItem -Title "Test backout script locally")
                "item3" = (New-ChecklistItem -Title "Upload to Intune as backup")
            }
        },
        @{
            Title    = "Document group removal procedure in Intune"
            Priority = "Medium"
        }
    )
}

# Create tasks in each bucket (in display order)
$taskOrder = @(
    "Phase 1 - Assessment & Early Pilot"
    "Phase 2 - Testing"
    "Phase 3 - Rollout"
    "Phase 4 - Closeout"
    "Backout Plan"
)

foreach ($bucketName in $taskOrder) {
    $bucketId = $buckets[$bucketName]
    $tasks = $allTasks[$bucketName]
    
    Write-Host " Adding tasks to: $bucketName" -ForegroundColor Yellow
    
    foreach ($taskData in $tasks) {
        $taskParams = @{
            PlanId   = $planId
            BucketId = $bucketId
            Title    = $taskData.Title
            Priority = $taskData.Priority
        }
        
        if ($taskData.Checklist) {
            $taskParams.Checklist = $taskData.Checklist
        }
        
        New-PlannerTask @taskParams | Out-Null
    }
}

Write-Host "========================================" -ForegroundColor Green
Write-Host "Planner board created successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Plan ID: $planId" -ForegroundColor Cyan
Write-Host "Plan URL: https://tasks.office.com/Home/PlanViews/$planId" -ForegroundColor Cyan
Write-Host "Note: You may need to refresh your Planner view to see all tasks." -ForegroundColor Yellow

#endregion Main Script