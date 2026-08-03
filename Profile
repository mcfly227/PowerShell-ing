#Requires -Version 7.0

<#
.SYNOPSIS
    Cross-Platform PowerShell Profile - Nerd Edition
.DESCRIPTION
    A feature-rich, stats-heavy PowerShell profile with enhanced history,
    system monitoring, command suggestions, and nerdy goodness.
.NOTES
    Author: David McFall
    Compatible: PowerShell 7+ on Windows, Linux, and macOS
#>

#region *Global Variables*
$Global:ProfileLoadTime = Get-Date
$Global:CommandCount = 0
$Global:SessionStats = @{
    CommandsExecuted = 0
    ErrorsEncountered = 0
    StartTime = Get-Date
}
#endregion

#region Platform Detection
$IsWindowsOS = $IsWindows -or ($PSVersionTable.PSVersion.Major -lt 6)
$IsLinuxOS = $IsLinux
$IsMacOS = $IsMacOS
#endregion

#region PSReadLine Configuration (Enhanced History & Editing)
if (Get-Module -ListAvailable -Name PSReadLine) {
    Import-Module PSReadLine
    
    # Set history search behavior
    Set-PSReadLineOption -PredictionSource HistoryAndPlugin
    Set-PSReadLineOption -PredictionViewStyle ListView
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    Set-PSReadLineOption -ShowToolTips
    Set-PSReadLineOption -BellStyle Visual
    
    # Enhanced colors
    Set-PSReadLineOption -Colors @{
        Command            = 'Cyan'
        Parameter          = 'DarkGray'
        Operator           = 'DarkMagenta'
        Variable           = 'Green'
        String             = 'Yellow'
        Number             = 'DarkCyan'
        Type               = 'DarkYellow'
        Comment            = 'DarkGreen'
        InlinePrediction   = 'DarkGray'
        ListPrediction     = 'Yellow'
        ListPredictionSelected = 'DarkBlue'
    }
    
    # Key bindings
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    Set-PSReadLineKeyHandler -Key Ctrl+d -Function DeleteChar
    Set-PSReadLineKeyHandler -Key Ctrl+w -Function BackwardDeleteWord
    
    # History configuration
    Set-PSReadLineOption -MaximumHistoryCount 10000
    Set-PSReadLineOption -HistoryNoDuplicates
    Set-PSReadLineOption -HistorySaveStyle SaveIncrementally
    
    # Command validation and suggestions
    Set-PSReadLineOption -CommandValidationHandler {
        param([System.Management.Automation.Language.CommandAst]$CommandAst)
        
        # Track command execution
        $Global:SessionStats.CommandsExecuted++
        
        # Check if command exists
        $commandName = $CommandAst.GetCommandName()
        if ($commandName) {
            $command = Get-Command $commandName -ErrorAction SilentlyContinue
            if (-not $command) {
                # Find similar commands
                $allCommands = Get-Command | Select-Object -ExpandProperty Name
                $suggestions = $allCommands | Where-Object {
                    $similarity = Compare-String $_ $commandName
                    $similarity -gt 0.6
                } | Select-Object -First 3
                
                if ($suggestions) {
                    Write-Host "`n💡 Command not found. Did you mean:" -ForegroundColor Yellow
                    $suggestions | ForEach-Object {
                        Write-Host "   • $_" -ForegroundColor Cyan
                    }
                }
            }
        }
    }
}

# Fuzzy string comparison function
function Compare-String {
    param(
        [string]$String1,
        [string]$String2
    )
    
    $len1 = $String1.Length
    $len2 = $String2.Length
    $maxLen = [Math]::Max($len1, $len2)
    
    if ($maxLen -eq 0) { return 1.0 }
    
    $distance = Get-LevenshteinDistance $String1 $String2
    return 1.0 - ($distance / $maxLen)
}

function Get-LevenshteinDistance {
    param(
        [string]$String1,
        [string]$String2
    )
    
    $len1 = $String1.Length
    $len2 = $String2.Length
    $matrix = New-Object 'int[,]' ($len1 + 1), ($len2 + 1)
    
    for ($i = 0; $i -le $len1; $i++) { $matrix[$i, 0] = $i }
    for ($j = 0; $j -le $len2; $j++) { $matrix[0, $j] = $j }
    
    for ($i = 1; $i -le $len1; $i++) {
        for ($j = 1; $j -le $len2; $j++) {
            $cost = if ($String1[$i - 1] -eq $String2[$j - 1]) { 0 } else { 1 }
            $matrix[$i, $j] = [Math]::Min(
                [Math]::Min($matrix[$i - 1, $j] + 1, $matrix[$i, $j - 1] + 1),
                $matrix[$i - 1, $j - 1] + $cost
            )
        }
    }
    
    return $matrix[$len1, $len2]
}
#endregion

#region Custom Prompt
function prompt {
    $lastCommandSuccess = $?
    $currentPath = Get-Location
    
    # Track errors
    if (-not $lastCommandSuccess) {
        $Global:SessionStats.ErrorsEncountered++
    }
    
    # Get last command execution time
    $lastCommand = Get-History -Count 1
    $executionTime = ""
    if ($lastCommand) {
        $duration = $lastCommand.Duration
        if ($duration.TotalSeconds -gt 1) {
            $executionTime = " $([char]0x1B)[90m⏱ {0:N2}s$([char]0x1B)[0m" -f $duration.TotalSeconds
        } elseif ($duration.TotalMilliseconds -gt 0) {
            $executionTime = " $([char]0x1B)[90m⏱ {0:N0}ms$([char]0x1B)[0m" -f $duration.TotalMilliseconds
        }
    }
    
    # Get current memory usage
    $process = Get-Process -Id $PID
    $memoryMB = [math]::Round($process.WorkingSet64 / 1MB, 1)
    $memoryIndicator = "$([char]0x1B)[90m💾 ${memoryMB}MB$([char]0x1B)[0m"
    
    # Shorten path for readability
    $displayPath = $currentPath.Path
    if ($IsWindowsOS) {
        $displayPath = $displayPath -replace [regex]::Escape($HOME), "~"
    } else {
        $displayPath = $displayPath -replace [regex]::Escape($HOME), "~"
    }
    
    # Get git branch if in a git repo
    $gitBranch = ""
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $gitStatus = git rev-parse --abbrev-ref HEAD 2>$null
        if ($gitStatus) {
            # Check for uncommitted changes
            $gitDirty = git status --porcelain 2>$null
            $dirtyIndicator = if ($gitDirty) { "$([char]0x1B)[31m*$([char]0x1B)[0m" } else { "" }
            $gitBranch = " $([char]0x1B)[33m[$([char]0x1B)[36m$gitStatus$dirtyIndicator$([char]0x1B)[33m]$([char]0x1B)[0m"
        }
    }
    
    # Status indicator (green checkmark or red X)
    $statusSymbol = if ($lastCommandSuccess) {
        "$([char]0x1B)[32m✓$([char]0x1B)[0m"
    } else {
        "$([char]0x1B)[31m✗$([char]0x1B)[0m"
    }
    
    # Timestamp
    $timestamp = Get-Date -Format "HH:mm:ss"
    
    # Command counter
    $commandNum = (Get-History).Count
    $commandCounter = "$([char]0x1B)[90m#$commandNum$([char]0x1B)[0m"
    
    # Build prompt
    Write-Host ""
    Write-Host "$([char]0x1B)[90m[$timestamp]$([char]0x1B)[0m " -NoNewline
    Write-Host "$commandCounter " -NoNewline
    Write-Host "$statusSymbol " -NoNewline
    Write-Host "$([char]0x1B)[35m$env:USERNAME$([char]0x1B)[0m" -NoNewline
    Write-Host " $([char]0x1B)[90m@$([char]0x1B)[0m " -NoNewline
    Write-Host "$([char]0x1B)[34m$displayPath$([char]0x1B)[0m" -NoNewline
    Write-Host "$gitBranch" -NoNewline
    Write-Host "$executionTime" -NoNewline
    Write-Host " $memoryIndicator"
    Write-Host "$([char]0x1B)[32m❯$([char]0x1B)[0m " -NoNewline
    
    return " "
}
#endregion

#region Utility Functions

# ============================================================
# Session Statistics
# ============================================================

function Get-SessionStats {
    <#
    .SYNOPSIS
        Display comprehensive session statistics
    #>
    $uptime = (Get-Date) - $Global:SessionStats.StartTime
    $historyCount = (Get-History).Count
    $successRate = if ($historyCount -gt 0) {
        [math]::Round((($historyCount - $Global:SessionStats.ErrorsEncountered) / $historyCount) * 100, 2)
    } else { 100 }
    
    Write-Host "`n╔═══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║              SESSION STATISTICS                       ║" -ForegroundColor Cyan
    Write-Host "╠═══════════════════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "║  Session Uptime:      " -ForegroundColor Cyan -NoNewline
    Write-Host "$($uptime.ToString('hh\:mm\:ss'))".PadRight(32) -ForegroundColor Yellow -NoNewline
    Write-Host "║" -ForegroundColor Cyan
    Write-Host "║  Commands Executed:   " -ForegroundColor Cyan -NoNewline
    Write-Host "$historyCount".PadRight(32) -ForegroundColor Yellow -NoNewline
    Write-Host "║" -ForegroundColor Cyan
    Write-Host "║  Errors Encountered:  " -ForegroundColor Cyan -NoNewline
    Write-Host "$($Global:SessionStats.ErrorsEncountered)".PadRight(32) -ForegroundColor Red -NoNewline
    Write-Host "║" -ForegroundColor Cyan
    Write-Host "║  Success Rate:        " -ForegroundColor Cyan -NoNewline
    Write-Host "$successRate%".PadRight(32) -ForegroundColor Green -NoNewline
    Write-Host "║" -ForegroundColor Cyan
    Write-Host "║  Memory Usage:        " -ForegroundColor Cyan -NoNewline
    $memMB = [math]::Round((Get-Process -Id $PID).WorkingSet64 / 1MB, 2)
    Write-Host "$memMB MB".PadRight(32) -ForegroundColor Yellow -NoNewline
    Write-Host "║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}
Set-Alias -Name stats -Value Get-SessionStats

function Get-SystemInfo {
    <#
    .SYNOPSIS
        Display detailed system information with nerdy stats
    #>
    $os = if ($IsWindowsOS) { 
        Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    } else { 
        $null 
    }
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                    SYSTEM INFORMATION                          ║" -ForegroundColor Cyan
    Write-Host "╠════════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
    
    # OS Information
    Write-Host "║  🖥️  OPERATING SYSTEM" -ForegroundColor Green -NoNewline
    Write-Host "                                     ║" -ForegroundColor Cyan
    Write-Host "║  ─────────────────────────────────────────────────────────  ║" -ForegroundColor DarkGray
    
    if ($IsWindowsOS -and $os) {
        Write-Host "║  OS:              " -ForegroundColor Cyan -NoNewline
        Write-Host "$($os.Caption)".PadRight(44) -ForegroundColor White -NoNewline
        Write-Host "║" -ForegroundColor Cyan
        Write-Host "║  Version:         " -ForegroundColor Cyan -NoNewline
        Write-Host "$($os.Version)".PadRight(44) -ForegroundColor White -NoNewline
        Write-Host "║" -ForegroundColor Cyan
        Write-Host "║  Architecture:    " -ForegroundColor Cyan -NoNewline
        Write-Host "$($os.OSArchitecture)".PadRight(44) -ForegroundColor White -NoNewline
        Write-Host "║" -ForegroundColor Cyan
        
        # Uptime
        $bootTime = $os.LastBootUpTime
        $uptime = (Get-Date) - $bootTime
        Write-Host "║  Uptime:          " -ForegroundColor Cyan -NoNewline
        Write-Host "$($uptime.Days)d $($uptime.Hours)h $($uptime.Minutes)m".PadRight(44) -ForegroundColor Yellow -NoNewline
        Write-Host "║" -ForegroundColor Cyan
    } else {
        Write-Host "║  OS:              " -ForegroundColor Cyan -NoNewline
        $osName = if ($IsLinuxOS) { "Linux" } elseif ($IsMacOS) { "macOS" } else { "Unknown" }
        Write-Host "$osName".PadRight(44) -ForegroundColor White -NoNewline
        Write-Host "║" -ForegroundColor Cyan
    }
    
    # CPU Information
    Write-Host "║" -ForegroundColor Cyan
    Write-Host "║  🔥 PROCESSOR" -ForegroundColor Green -NoNewline
    Write-Host "                                              ║" -ForegroundColor Cyan
    Write-Host "║  ─────────────────────────────────────────────────────────  ║" -ForegroundColor DarkGray
    
    if ($IsWindowsOS) {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cpu) {
            Write-Host "║  Name:            " -ForegroundColor Cyan -NoNewline
            Write-Host "$($cpu.Name.Trim())".Substring(0, [Math]::Min(44, $cpu.Name.Length)).PadRight(44) -ForegroundColor White -NoNewline
            Write-Host "║" -ForegroundColor Cyan
            Write-Host "║  Cores:           " -ForegroundColor Cyan -NoNewline
            Write-Host "$($cpu.NumberOfCores) cores / $($cpu.NumberOfLogicalProcessors) threads".PadRight(44) -ForegroundColor Yellow -NoNewline
            Write-Host "║" -ForegroundColor Cyan
            Write-Host "║  Max Speed:       " -ForegroundColor Cyan -NoNewline
            Write-Host "$($cpu.MaxClockSpeed) MHz".PadRight(44) -ForegroundColor Yellow -NoNewline
            Write-Host "║" -ForegroundColor Cyan
        }
    } else {
        Write-Host "║  Cores:           " -ForegroundColor Cyan -NoNewline
        $cores = (Get-CimInstance -ClassName CIM_Processor -ErrorAction SilentlyContinue).NumberOfCores
        if (-not $cores) { $cores = $env:NUMBER_OF_PROCESSORS }
        Write-Host "$cores".PadRight(44) -ForegroundColor Yellow -NoNewline
        Write-Host "║" -ForegroundColor Cyan
    }
    
    # Memory Information
    Write-Host "║" -ForegroundColor Cyan
    Write-Host "║  💾 MEMORY" -ForegroundColor Green -NoNewline
    Write-Host "                                                 ║" -ForegroundColor Cyan
    Write-Host "║  ─────────────────────────────────────────────────────────  ║" -ForegroundColor DarkGray
    
    if ($IsWindowsOS -and $os) {
        $totalRAM = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        $freeRAM = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        $usedRAM = $totalRAM - $freeRAM
        $percentUsed = [math]::Round(($usedRAM / $totalRAM) * 100, 1)
        
        Write-Host "║  Total:           " -ForegroundColor Cyan -NoNewline
        Write-Host "$totalRAM GB".PadRight(44) -ForegroundColor White -NoNewline
        Write-Host "║" -ForegroundColor Cyan
        Write-Host "║  Used:            " -ForegroundColor Cyan -NoNewline
        Write-Host "$usedRAM GB ($percentUsed%)".PadRight(44) -ForegroundColor Yellow -NoNewline
        Write-Host "║" -ForegroundColor Cyan
        Write-Host "║  Free:            " -ForegroundColor Cyan -NoNewline
        Write-Host "$freeRAM GB".PadRight(44) -ForegroundColor Green -NoNewline
        Write-Host "║" -ForegroundColor Cyan
        
        # Memory bar
        $barWidth = 40
        $usedBars = [math]::Round(($percentUsed / 100) * $barWidth)
        $freeBars = $barWidth - $usedBars
        Write-Host "║  Usage:           " -ForegroundColor Cyan -NoNewline
        Write-Host ("[" + ("█" * $usedBars) + ("░" * $freeBars) + "]").PadRight(44) -ForegroundColor Yellow -NoNewline
        Write-Host "║" -ForegroundColor Cyan
    }
    
    # PowerShell Information
    Write-Host "║" -ForegroundColor Cyan
    Write-Host "║  ⚡ POWERSHELL" -ForegroundColor Green -NoNewline
    Write-Host "                                            ║" -ForegroundColor Cyan
    Write-Host "║  ─────────────────────────────────────────────────────────  ║" -ForegroundColor DarkGray
    Write-Host "║  Version:         " -ForegroundColor Cyan -NoNewline
    Write-Host "$($PSVersionTable.PSVersion)".PadRight(44) -ForegroundColor White -NoNewline
    Write-Host "║" -ForegroundColor Cyan
    Write-Host "║  Edition:         " -ForegroundColor Cyan -NoNewline
    Write-Host "$($PSVersionTable.PSEdition)".PadRight(44) -ForegroundColor White -NoNewline
    Write-Host "║" -ForegroundColor Cyan
    Write-Host "║  PID:             " -ForegroundColor Cyan -NoNewline
    Write-Host "$PID".PadRight(44) -ForegroundColor White -NoNewline
    Write-Host "║" -ForegroundColor Cyan
    
    # Network Information
    if ($IsWindowsOS) {
        Write-Host "║" -ForegroundColor Cyan
        Write-Host "║  🌐 NETWORK" -ForegroundColor Green -NoNewline
        Write-Host "                                                ║" -ForegroundColor Cyan
        Write-Host "║  ─────────────────────────────────────────────────────────  ║" -ForegroundColor DarkGray
        
        $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up'
        if ($adapters) {
            $adapter = $adapters | Select-Object -First 1
            Write-Host "║  Adapter:         " -ForegroundColor Cyan -NoNewline
            Write-Host "$($adapter.Name)".Substring(0, [Math]::Min(44, $adapter.Name.Length)).PadRight(44) -ForegroundColor White -NoNewline
            Write-Host "║" -ForegroundColor Cyan
            Write-Host "║  Speed:           " -ForegroundColor Cyan -NoNewline
            Write-Host "$($adapter.LinkSpeed)".PadRight(44) -ForegroundColor Yellow -NoNewline
            Write-Host "║" -ForegroundColor Cyan
        }
    }
    
    Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}
Set-Alias -Name sysinfo -Value Get-SystemInfo

function Get-CommandHistory {
    <#
    .SYNOPSIS
        Display command history with enhanced formatting and statistics
    #>
    param(
        [int]$Last = 20
    )
    
    $history = Get-History | Select-Object -Last $Last
    
    Write-Host "`n📊 Command History (Last $Last)" -ForegroundColor Cyan
    Write-Host ("─" * 80) -ForegroundColor DarkGray
    
    $history | Format-Table -AutoSize @{
        Label = "ID"
        Expression = { $_.Id }
        Width = 5
    }, @{
        Label = "Duration"
        Expression = { 
            if ($_.Duration.TotalSeconds -gt 1) {
                "{0:N2}s" -f $_.Duration.TotalSeconds
            } else {
                "{0:N0}ms" -f $_.Duration.TotalMilliseconds
            }
        }
        Width = 10
    }, @{
        Label = "Start Time"
        Expression = { $_.StartExecutionTime.ToString("HH:mm:ss") }
        Width = 10
    }, @{
        Label = "Command"
        Expression = { $_.CommandLine }
    }
    
    # Calculate some stats
    $avgDuration = ($history | Measure-Object -Property Duration -Average).Average
    Write-Host "📈 Average execution time: " -ForegroundColor Cyan -NoNewline
    Write-Host ("{0:N2}ms" -f $avgDuration.TotalMilliseconds) -ForegroundColor Yellow
    Write-Host ""
}
Set-Alias -Name hist -Value Get-CommandHistory

function Get-TopCommands {
    <#
    .SYNOPSIS
        Show most frequently used commands
    #>
    param([int]$Top = 10)
    
    $allHistory = Get-Content (Get-PSReadLineOption).HistorySavePath -ErrorAction SilentlyContinue
    
    if ($allHistory) {
        Write-Host "`n🏆 Top $Top Most Used Commands" -ForegroundColor Cyan
        Write-Host ("─" * 60) -ForegroundColor DarkGray
        
        $allHistory | 
            ForEach-Object { $_.Split(' ')[0] } |
            Group-Object |
            Sort-Object Count -Descending |
            Select-Object -First $Top |
            Format-Table @{
                Label = "Rank"
                Expression = { ($allHistory | ForEach-Object { $_.Split(' ')[0] } | Group-Object | Sort-Object Count -Descending).IndexOf($_) + 1 }
                Width = 6
            }, @{
                Label = "Command"
                Expression = { $_.Name }
                Width = 30
            }, @{
                Label = "Count"
                Expression = { $_.Count }
                Width = 10
            }, @{
                Label = "Percentage"
                Expression = { "{0:P1}" -f ($_.Count / $allHistory.Count) }
                Width = 12
            } -AutoSize
    } else {
        Write-Host "No command history found." -ForegroundColor Yellow
    }
}
Set-Alias -Name topcmds -Value Get-TopCommands

function Clear-CommandHistory {
    <#
    .SYNOPSIS
        Clear PowerShell command history
    #>
    Clear-History
    [Microsoft.PowerShell.PSConsoleReadLine]::ClearHistory()
    Write-Host "Command history cleared." -ForegroundColor Green
}

function Get-DiskSpace {
    <#
    .SYNOPSIS
        Display disk space information with detailed stats and visual bars
    #>
    Write-Host "`n💽 Disk Space Usage" -ForegroundColor Cyan
    Write-Host ("─" * 90) -ForegroundColor DarkGray
    
    if ($IsWindowsOS) {
        $drives = Get-PSDrive -PSProvider FileSystem | 
            Where-Object { $_.Used -ne $null } |
            Select-Object @{
                Name = "Drive"
                Expression = { $_.Name + ":" }
            }, @{
                Name = "Used(GB)"
                Expression = { [math]::Round($_.Used/1GB, 2) }
            }, @{
                Name = "Free(GB)"
                Expression = { [math]::Round($_.Free/1GB, 2) }
            }, @{
                Name = "Total(GB)"
                Expression = { [math]::Round(($_.Used + $_.Free)/1GB, 2) }
            }, @{
                Name = "Free%"
                Expression = { [math]::Round($_.Free/($_.Used + $_.Free)*100, 1) }
            }, @{
                Name = "Usage"
                Expression = {
                    $percentUsed = [math]::Round($_.Used/($_.Used + $_.Free)*100, 0)
                    $barWidth = 20
                    $usedBars = [math]::Round(($percentUsed / 100) * $barWidth)
                    $freeBars = $barWidth - $usedBars
                    "[" + ("█" * $usedBars) + ("░" * $freeBars) + "] $percentUsed%"
                }
            }
        
        $drives | Format-Table -AutoSize
        
        # Total statistics
        $totalUsed = ($drives | Measure-Object -Property 'Used(GB)' -Sum).Sum
        $totalFree = ($drives | Measure-Object -Property 'Free(GB)' -Sum).Sum
        $totalSpace = $totalUsed + $totalFree
        
        Write-Host "📊 Total: " -ForegroundColor Cyan -NoNewline
        Write-Host "$([math]::Round($totalSpace, 2)) GB total, " -ForegroundColor White -NoNewline
        Write-Host "$([math]::Round($totalUsed, 2)) GB used, " -ForegroundColor Yellow -NoNewline
        Write-Host "$([math]::Round($totalFree, 2)) GB free" -ForegroundColor Green
        Write-Host ""
    } else {
        Get-PSDrive -PSProvider FileSystem | Format-Table -AutoSize
    }
}
Set-Alias -Name df -Value Get-DiskSpace

function Get-ProcessTop {
    <#
    .SYNOPSIS
        Display top processes with detailed resource usage
    #>
    param(
        [Parameter()]
        [ValidateSet('CPU', 'Memory', 'Both')]
        [string]$SortBy = 'CPU',
        
        [Parameter()]
        [int]$Count = 10
    )
    
    Write-Host "`n🔥 Top $Count Processes by $SortBy" -ForegroundColor Cyan
    Write-Host ("─" * 100) -ForegroundColor DarkGray
    
    if ($SortBy -eq 'CPU') {
        Get-Process | 
            Sort-Object CPU -Descending | 
            Select-Object -First $Count | 
            Format-Table -AutoSize @{
                Label = "PID"
                Expression = { $_.Id }
                Width = 8
            }, @{
                Label = "Name"
                Expression = { $_.Name }
                Width = 25
            }, @{
                Label = "CPU(s)"
                Expression = { "{0:N2}" -f $_.CPU }
                Width = 10
            }, @{
                Label = "Memory(MB)"
                Expression = { [math]::Round($_.WorkingSet/1MB, 2) }
                Width = 12
            }, @{
                Label = "Threads"
                Expression = { $_.Threads.Count }
                Width = 8
            }, @{
                Label = "Handles"
                Expression = { $_.HandleCount }
                Width = 8
            }
    } elseif ($SortBy -eq 'Memory') {
        Get-Process | 
            Sort-Object WorkingSet -Descending | 
            Select-Object -First $Count |
            Format-Table -AutoSize @{
                Label = "PID"
                Expression = { $_.Id }
                Width = 8
            }, @{
                Label = "Name"
                Expression = { $_.Name }
                Width = 25
            }, @{
                Label = "Memory(MB)"
                Expression = { [math]::Round($_.WorkingSet/1MB, 2) }
                Width = 12
            }, @{
                Label = "CPU(s)"
                Expression = { "{0:N2}" -f $_.CPU }
                Width = 10
            }, @{
                Label = "Threads"
                Expression = { $_.Threads.Count }
                Width = 8
            }, @{
                Label = "Handles"
                Expression = { $_.HandleCount }
                Width = 8
            }
    } else {
        Write-Host "By CPU:" -ForegroundColor Yellow
        Get-ProcessTop -SortBy CPU -Count ($Count / 2)
        Write-Host "`nBy Memory:" -ForegroundColor Yellow
        Get-ProcessTop -SortBy Memory -Count ($Count / 2)
        return
    }
    
    # Show total resource usage
    $allProcesses = Get-Process
    $totalMemoryMB = [math]::Round(($allProcesses | Measure-Object -Property WorkingSet -Sum).Sum / 1MB, 2)
    $totalCPU = [math]::Round(($allProcesses | Measure-Object -Property CPU -Sum).Sum, 2)
    
    Write-Host "`n📊 System Total: " -ForegroundColor Cyan -NoNewline
    Write-Host "$($allProcesses.Count) processes, " -ForegroundColor White -NoNewline
    Write-Host "${totalMemoryMB} MB memory, " -ForegroundColor Yellow -NoNewline
    Write-Host "${totalCPU}s CPU time" -ForegroundColor Green
    Write-Host ""
}
Set-Alias -Name top -Value Get-ProcessTop

function Test-NetworkSpeed {
    <#
    .SYNOPSIS
        Enhanced network connectivity and latency test
    #>
    param(
        [string[]]$Targets = @("8.8.8.8", "1.1.1.1", "8.8.4.4"),
        [int]$Count = 4
    )
    
    Write-Host "`n🌐 Network Performance Test" -ForegroundColor Cyan
    Write-Host ("─" * 80) -ForegroundColor DarkGray
    
    foreach ($target in $Targets) {
        Write-Host "`nTesting: " -ForegroundColor White -NoNewline
        Write-Host "$target" -ForegroundColor Yellow
        
        $results = Test-Connection -ComputerName $target -Count $Count -ErrorAction SilentlyContinue
        
        if ($results) {
            $avgLatency = [math]::Round(($results | Measure-Object -Property ResponseTime -Average).Average, 2)
            $minLatency = ($results | Measure-Object -Property ResponseTime -Minimum).Minimum
            $maxLatency = ($results | Measure-Object -Property ResponseTime -Maximum).Maximum
            $packetLoss = [math]::Round((($Count - $results.Count) / $Count) * 100, 1)
            
            Write-Host "  ├─ Packets: " -ForegroundColor Gray -NoNewline
            Write-Host "$($results.Count)/$Count sent ($packetLoss% loss)" -ForegroundColor $(if($packetLoss -eq 0){'Green'}else{'Red'})
            Write-Host "  ├─ Latency: " -ForegroundColor Gray -NoNewline
            Write-Host "min=${minLatency}ms avg=${avgLatency}ms max=${maxLatency}ms" -ForegroundColor Yellow
            Write-Host "  └─ Status: " -ForegroundColor Gray -NoNewline
            Write-Host "$(if($avgLatency -lt 50){'Excellent'}elseif($avgLatency -lt 100){'Good'}elseif($avgLatency -lt 200){'Fair'}else{'Poor'})" -ForegroundColor $(if($avgLatency -lt 50){'Green'}elseif($avgLatency -lt 100){'Yellow'}else{'Red'})
        } else {
            Write-Host "  └─ Status: " -ForegroundColor Gray -NoNewline
            Write-Host "FAILED" -ForegroundColor Red
        }
    }
    Write-Host ""
}
Set-Alias -Name speedtest -Value Test-NetworkSpeed
Set-Alias -Name nettest -Value Test-NetworkSpeed

function Get-NetworkInfo {
    <#
    .SYNOPSIS
        Display comprehensive network adapter information
    #>
    if ($IsWindowsOS) {
        Write-Host "`n🌐 Network Adapters" -ForegroundColor Cyan
        Write-Host ("─" * 100) -ForegroundColor DarkGray
        
        $adapters = Get-NetAdapter | Where-Object Status -eq 'Up'
        
        foreach ($adapter in $adapters) {
            $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            
            Write-Host "`n$($adapter.Name)" -ForegroundColor Yellow
            Write-Host "  ├─ Status: " -ForegroundColor Gray -NoNewline
            Write-Host "$($adapter.Status)" -ForegroundColor Green
            Write-Host "  ├─ Speed: " -ForegroundColor Gray -NoNewline
            Write-Host "$($adapter.LinkSpeed)" -ForegroundColor Cyan
            Write-Host "  ├─ MAC: " -ForegroundColor Gray -NoNewline
            Write-Host "$($adapter.MacAddress)" -ForegroundColor White
            if ($ipConfig) {
                Write-Host "  └─ IP: " -ForegroundColor Gray -NoNewline
                Write-Host "$($ipConfig.IPAddress)" -ForegroundColor Yellow
            }
        }
        Write-Host ""
    } else {
        Write-Host "Network info requires Windows platform" -ForegroundColor Yellow
    }
}
Set-Alias -Name netinfo -Value Get-NetworkInfo

function Measure-CommandPerformance {
    <#
    .SYNOPSIS
        Benchmark a command or script block with detailed statistics
    #>
    param(
        [Parameter(Mandatory=$true)]
        [ScriptBlock]$ScriptBlock,
        
        [int]$Iterations = 10
    )
    
    Write-Host "`n⏱️  Performance Benchmark ($Iterations iterations)" -ForegroundColor Cyan
    Write-Host ("─" * 80) -ForegroundColor DarkGray
    Write-Host "Command: " -ForegroundColor Gray -NoNewline
    Write-Host "$ScriptBlock" -ForegroundColor Yellow
    Write-Host ""
    
    $times = @()
    
    for ($i = 1; $i -le $Iterations; $i++) {
        Write-Progress -Activity "Benchmarking" -Status "Iteration $i of $Iterations" -PercentComplete (($i / $Iterations) * 100)
        $result = Measure-Command -Expression $ScriptBlock
        $times += $result.TotalMilliseconds
    }
    
    Write-Progress -Activity "Benchmarking" -Completed
    
    $average = [math]::Round(($times | Measure-Object -Average).Average, 2)
    $min = [math]::Round(($times | Measure-Object -Minimum).Minimum, 2)
    $max = [math]::Round(($times | Measure-Object -Maximum).Maximum, 2)
    $stdDev = [math]::Round([Math]::Sqrt(($times | ForEach-Object { [Math]::Pow($_ - $average, 2) } | Measure-Object -Average).Average), 2)
    
    Write-Host "Results:" -ForegroundColor Green
    Write-Host "  ├─ Average: " -ForegroundColor Gray -NoNewline
    Write-Host "${average}ms" -ForegroundColor Yellow
    Write-Host "  ├─ Minimum: " -ForegroundColor Gray -NoNewline
    Write-Host "${min}ms" -ForegroundColor Green
    Write-Host "  ├─ Maximum: " -ForegroundColor Gray -NoNewline
    Write-Host "${max}ms" -ForegroundColor Red
    Write-Host "  ├─ Std Dev: " -ForegroundColor Gray -NoNewline
    Write-Host "${stdDev}ms" -ForegroundColor Cyan
    Write-Host "  └─ Range: " -ForegroundColor Gray -NoNewline
    Write-Host "$([math]::Round($max - $min, 2))ms" -ForegroundColor Magenta
    Write-Host ""
}
Set-Alias -Name benchmark -Value Measure-CommandPerformance

function Find-File {
    <#
    .SYNOPSIS
        Search for files by name pattern
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Pattern,
        
        [Parameter()]
        [string]$Path = "."
    )
    
    Get-ChildItem -Path $Path -Recurse -Filter "*$Pattern*" -ErrorAction SilentlyContinue |
        Select-Object FullName, Length, LastWriteTime |
        Format-Table -AutoSize
}
Set-Alias -Name ff -Value Find-File

function Update-PowerShellProfile {
    <#
    .SYNOPSIS
        Edit the PowerShell profile
    #>
    if ($IsWindowsOS) {
        if (Get-Command code -ErrorAction SilentlyContinue) {
            code $PROFILE
        } elseif (Get-Command notepad -ErrorAction SilentlyContinue) {
            notepad $PROFILE
        }
    } else {
        if (Get-Command code -ErrorAction SilentlyContinue) {
            code $PROFILE
        } elseif (Get-Command nano -ErrorAction SilentlyContinue) {
            nano $PROFILE
        } elseif (Get-Command vim -ErrorAction SilentlyContinue) {
            vim $PROFILE
        }
    }
}
Set-Alias -Name editprofile -Value Update-PowerShellProfile

function Reload-Profile {
    <#
    .SYNOPSIS
        Reload the PowerShell profile
    #>
    . $PROFILE
    Write-Host "Profile reloaded successfully!" -ForegroundColor Green
}
Set-Alias -Name reload -Value Reload-Profile
#endregion

#region Common Aliases
# Navigation
Set-Alias -Name .. -Value Set-LocationParent -ErrorAction SilentlyContinue
function Set-LocationParent { Set-Location .. }

# Directory listing
if ($IsWindowsOS) {
    function ll { Get-ChildItem -Force | Format-Table -AutoSize }
    function la { Get-ChildItem -Force }
} else {
    Set-Alias -Name ll -Value Get-ChildItem
    Set-Alias -Name la -Value Get-ChildItem
}

# Common shortcuts
Set-Alias -Name g -Value git -ErrorAction SilentlyContinue
Set-Alias -Name c -Value Clear-Host
#endregion

#region Module Auto-Import
$modulesToImport = @(
    'Az.Accounts',
    'Microsoft.Graph',
    'Pester'
)

foreach ($module in $modulesToImport) {
    if (Get-Module -ListAvailable -Name $module) {
        # Uncomment to auto-import (may slow startup)
        # Import-Module $module -ErrorAction SilentlyContinue
    }
}
#endregion

#region Welcome Message
Clear-Host

# Calculate profile load time
$profileLoadDuration = (Get-Date) - $Global:ProfileLoadTime

# ASCII Art Header
Write-Host ""
Write-Host "    ____                        ____  __         ____" -ForegroundColor Cyan
Write-Host "   / __ \____ _      _____  ___/ ___\/ /_  ___  / / /" -ForegroundColor Cyan
Write-Host "  / /_/ / __ \ | /| / / _ \/ __\___ \/ __ \/ _ \/ / /" -ForegroundColor Blue
Write-Host " / ____/ /_/ / |/ |/ /  __/ /  ___/ / / / /  __/ / /" -ForegroundColor Blue
Write-Host "/_/    \____/|__/|__/\___/_/  /____/_/ /_/\___/_/_/" -ForegroundColor DarkBlue
Write-Host ""

# System Information Box
$osInfo = if ($IsWindowsOS) {
    if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os) { "$($os.Caption) $($os.OSArchitecture)" } else { "Windows" }
    } else { "Windows" }
} elseif ($IsLinuxOS) {
    "Linux"
} else {
    "macOS"
}

$psVersion = "$($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"
$currentDate = Get-Date -Format "dddd, MMMM dd, yyyy"
$currentTime = Get-Date -Format "HH:mm:ss"

# Get memory info
$memoryInfo = if ($IsWindowsOS -and (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($os) {
        $totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        $freeGB = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
        "${totalGB}GB total, ${freeGB}GB free"
    } else {
        "N/A"
    }
} else {
    "N/A"
}

# Get CPU info
$cpuInfo = if ($IsWindowsOS -and (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cpu) {
        "$($cpu.NumberOfCores)C/$($cpu.NumberOfLogicalProcessors)T @ $($cpu.MaxClockSpeed)MHz"
    } else {
        "N/A"
    }
} else {
    "N/A"
}

# Get uptime
$uptimeInfo = if ($IsWindowsOS -and (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($os) {
        $uptime = (Get-Date) - $os.LastBootUpTime
        "$($uptime.Days)d $($uptime.Hours)h $($uptime.Minutes)m"
    } else {
        "N/A"
    }
} else {
    "N/A"
}

Write-Host "╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                          SYSTEM INFORMATION                                ║" -ForegroundColor Cyan
Write-Host "╠════════════════════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║  👤 User:          " -ForegroundColor Cyan -NoNewline 
Write-Host "$env:USERNAME".PadRight(56) -ForegroundColor Yellow -NoNewline
Write-Host "║" -ForegroundColor Cyan
Write-Host "║  💻 Computer:      " -ForegroundColor Cyan -NoNewline
Write-Host "$env:COMPUTERNAME".PadRight(56) -ForegroundColor Yellow -NoNewline
Write-Host "║" -ForegroundColor Cyan
Write-Host "║  🖥️  OS:            " -ForegroundColor Cyan -NoNewline 
Write-Host "$osInfo".PadRight(55) -ForegroundColor White -NoNewline
Write-Host "║" -ForegroundColor Cyan
Write-Host "║  ⚡ PowerShell:    " -ForegroundColor Cyan -NoNewline
Write-Host "$psVersion".PadRight(56) -ForegroundColor White -NoNewline
Write-Host "║" -ForegroundColor Cyan
Write-Host "║  📅 Date:          " -ForegroundColor Cyan -NoNewline
Write-Host "$currentDate $currentTime".PadRight(56) -ForegroundColor White -NoNewline
Write-Host "║" -ForegroundColor Cyan
Write-Host "║  ⏰ Uptime:        " -ForegroundColor Cyan -NoNewline
Write-Host "$uptimeInfo".PadRight(56) -ForegroundColor Green -NoNewline
Write-Host "║" -ForegroundColor Cyan
Write-Host "║  🔥 CPU:           " -ForegroundColor Cyan -NoNewline
Write-Host "$cpuInfo".PadRight(56) -ForegroundColor White -NoNewline
Write-Host "║" -ForegroundColor Cyan
Write-Host "║  💾 Memory:        " -ForegroundColor Cyan -NoNewline
Write-Host "$memoryInfo".PadRight(56) -ForegroundColor White -NoNewline
Write-Host "║" -ForegroundColor Cyan
Write-Host "║  📁 Location:      " -ForegroundColor Cyan -NoNewline
Write-Host "$PWD".ToString().Substring(0, [Math]::Min(55, $PWD.ToString().Length)).PadRight(56) -ForegroundColor White -NoNewline
Write-Host "║" -ForegroundColor Cyan
Write-Host "║  ⚙️  Profile Load:  " -ForegroundColor Cyan -NoNewline
Write-Host "$([math]::Round($profileLoadDuration.TotalMilliseconds, 0))ms".PadRight(55) -ForegroundColor $(if($profileLoadDuration.TotalMilliseconds -lt 500){'Green'}elseif($profileLoadDuration.TotalMilliseconds -lt 1000){'Yellow'}else{'Red'}) -NoNewline
Write-Host "║" -ForegroundColor Cyan
Write-Host "╠════════════════════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║                         AVAILABLE COMMANDS                                 ║" -ForegroundColor Cyan
Write-Host "╠════════════════════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║  📊 Stats:         " -ForegroundColor Cyan -NoNewline
Write-Host "stats, sysinfo, topcmds, hist".PadRight(56) -ForegroundColor Green -NoNewline
Write-Host "║" -ForegroundColor Cyan
Write-Host "║  💽 Storage:       " -ForegroundColor Cyan -NoNewline
Write-Host "df, top, ff <pattern>".PadRight(56) -ForegroundColor Green -NoNewline
Write-Host "║" -ForegroundColor Cyan
Write-Host "║  🌐 Network:       " -ForegroundColor Cyan -NoNewline
Write-Host "speedtest, nettest, netinfo".PadRight(56) -ForegroundColor Green -NoNewline
Write-Host "║" -ForegroundColor Cyan
Write-Host "║  ⚙️  Utilities:     " -ForegroundColor Cyan -NoNewline
Write-Host "benchmark, editprofile, reload".PadRight(55) -ForegroundColor Green -NoNewline
Write-Host "║" -ForegroundColor Cyan
Write-Host "║  📝 Navigation:    " -ForegroundColor Cyan -NoNewline
Write-Host ".., ll, la, c (clear)".PadRight(56) -ForegroundColor Green -NoNewline
Write-Host "║" -ForegroundColor Cyan
Write-Host "║  🔐 Run me Elevated:    " -ForegroundColor Cyan -NoNewline
Write-Host "Start-Process wt -Verb RunAs".PadRight(51) -ForegroundColor Green -NoNewline
Write-Host "║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "  💡 " -ForegroundColor Yellow -NoNewline
Write-Host "Tip: Type " -ForegroundColor Gray -NoNewline
Write-Host "stats " -ForegroundColor Cyan -NoNewline
Write-Host "to see session statistics or " -ForegroundColor Gray -NoNewline
Write-Host "sysinfo " -ForegroundColor Cyan -NoNewline
Write-Host "for detailed system info" -ForegroundColor Gray
Write-Host "  🚀 " -ForegroundColor Green -NoNewline
Write-Host "Command suggestions enabled - misspell a command to see alternatives!" -ForegroundColor Gray
Write-Host "  ☕ " -ForegroundColor Green -NoNewline
Write-Host "REMEMBER - NEVER POWERSHELL UN-CAFFINATED!!!" -ForegroundColor Red
Write-Host ""
#endregion

#region Performance Optimization
# Remove any duplicate paths from environment
if ($IsWindowsOS) {
    $env:Path = ($env:Path -split ';' | Select-Object -Unique) -join ';'
}
#endregion
