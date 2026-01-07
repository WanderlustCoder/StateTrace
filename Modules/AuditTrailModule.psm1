# AuditTrailModule.psm1
# Configuration audit trail logging for compliance

Set-StrictMode -Version Latest

$script:AuditLogPath = $null
$script:AuditBuffer = [System.Collections.Generic.List[object]]::new()
$script:BufferFlushThreshold = 10
$script:CurrentUser = $null

function Initialize-AuditTrail {
    <#
    .SYNOPSIS
    Initializes the audit trail system.
    .PARAMETER LogPath
    Base path for audit logs. Default: Logs/Audit/
    #>
    [CmdletBinding()]
    param(
        [string]$LogPath
    )

    if (-not $LogPath) {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $LogPath = Join-Path $projectRoot 'Logs\Audit'
    }

    if (-not (Test-Path $LogPath)) {
        New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
    }

    $script:AuditLogPath = $LogPath
    $script:CurrentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    Write-Verbose "[AuditTrail] Initialized at $LogPath"
}

function Write-AuditEvent {
    <#
    .SYNOPSIS
    Writes an audit event to the trail.
    .PARAMETER EventType
    Type of event: ConfigChange, AccessAttempt, DataExport, SystemAction, ComplianceCheck
    .PARAMETER Category
    Category: Device, Interface, Alert, User, System, Compliance
    .PARAMETER Action
    Action performed: Create, Read, Update, Delete, Export, Execute
    .PARAMETER Target
    Target of the action (e.g., device hostname, file path)
    .PARAMETER Details
    Additional details about the event
    .PARAMETER Result
    Outcome: Success, Failure, Denied
    .PARAMETER Severity
    Severity level: Info, Warning, Critical
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('ConfigChange', 'AccessAttempt', 'DataExport', 'SystemAction', 'ComplianceCheck')]
        [string]$EventType,

        [Parameter(Mandatory)]
        [ValidateSet('Device', 'Interface', 'Alert', 'User', 'System', 'Compliance', 'Database', 'API')]
        [string]$Category,

        [Parameter(Mandatory)]
        [ValidateSet('Create', 'Read', 'Update', 'Delete', 'Export', 'Execute', 'Login', 'Logout', 'Validate')]
        [string]$Action,

        [string]$Target,
        [string]$Details,

        [ValidateSet('Success', 'Failure', 'Denied')]
        [string]$Result = 'Success',

        [ValidateSet('Info', 'Warning', 'Critical')]
        [string]$Severity = 'Info'
    )

    if (-not $script:AuditLogPath) {
        Initialize-AuditTrail
    }

    $event = [PSCustomObject]@{
        Id = [guid]::NewGuid().ToString('N').Substring(0, 12)
        Timestamp = [datetime]::UtcNow.ToString('o')
        TimestampLocal = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        EventType = $EventType
        Category = $Category
        Action = $Action
        Target = $Target
        Details = $Details
        Result = $Result
        Severity = $Severity
        User = $script:CurrentUser
        Machine = $env:COMPUTERNAME
        ProcessId = $PID
        SessionId = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
    }

    # Add to buffer
    [void]$script:AuditBuffer.Add($event)

    # Flush if threshold reached or critical event
    if ($script:AuditBuffer.Count -ge $script:BufferFlushThreshold -or $Severity -eq 'Critical') {
        Flush-AuditBuffer
    }

    # Return event for caller reference
    return $event
}

function Flush-AuditBuffer {
    <#
    .SYNOPSIS
    Flushes the audit buffer to disk.
    #>
    [CmdletBinding()]
    param()

    if ($script:AuditBuffer.Count -eq 0) { return }

    $today = (Get-Date).ToString('yyyy-MM-dd')
    $logFile = Join-Path $script:AuditLogPath "AuditTrail-$today.jsonl"

    try {
        $lines = $script:AuditBuffer | ForEach-Object {
            $_ | ConvertTo-Json -Compress -Depth 5
        }

        $lines -join "`n" | Add-Content -Path $logFile -Encoding UTF8

        $script:AuditBuffer.Clear()

    } catch {
        Write-Warning "[AuditTrail] Failed to flush buffer: $_"
    }
}

function Get-AuditEvents {
    <#
    .SYNOPSIS
    Retrieves audit events with optional filtering.
    .PARAMETER StartDate
    Filter events from this date.
    .PARAMETER EndDate
    Filter events to this date.
    .PARAMETER EventType
    Filter by event type.
    .PARAMETER Category
    Filter by category.
    .PARAMETER User
    Filter by user.
    .PARAMETER Last
    Get last N events.
    #>
    [CmdletBinding()]
    param(
        [datetime]$StartDate,
        [datetime]$EndDate,
        [string]$EventType,
        [string]$Category,
        [string]$User,
        [string]$Target,
        [string]$Result,
        [int]$Last = 1000
    )

    if (-not $script:AuditLogPath) {
        Initialize-AuditTrail
    }

    # Flush buffer first
    Flush-AuditBuffer

    # Collect events from log files
    $events = [System.Collections.Generic.List[object]]::new()

    $logFiles = Get-ChildItem -Path $script:AuditLogPath -Filter 'AuditTrail-*.jsonl' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending

    foreach ($file in $logFiles) {
        # Check date range from filename
        if ($file.Name -match 'AuditTrail-(\d{4}-\d{2}-\d{2})\.jsonl') {
            $fileDate = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd', $null)
            if ($StartDate -and $fileDate -lt $StartDate.Date) { continue }
            if ($EndDate -and $fileDate -gt $EndDate.Date) { continue }
        }

        $lines = Get-Content -Path $file.FullName -ErrorAction SilentlyContinue
        foreach ($line in $lines) {
            if (-not $line.Trim()) { continue }
            try {
                $event = $line | ConvertFrom-Json
                $events.Add($event)
            } catch {
                # Skip malformed lines
            }
        }

        if ($events.Count -ge $Last * 2) { break }
    }

    # Apply filters
    $filtered = $events

    if ($EventType) {
        $filtered = $filtered | Where-Object { $_.EventType -eq $EventType }
    }
    if ($Category) {
        $filtered = $filtered | Where-Object { $_.Category -eq $Category }
    }
    if ($User) {
        $filtered = $filtered | Where-Object { $_.User -like "*$User*" }
    }
    if ($Target) {
        $filtered = $filtered | Where-Object { $_.Target -like "*$Target*" }
    }
    if ($Result) {
        $filtered = $filtered | Where-Object { $_.Result -eq $Result }
    }
    if ($StartDate) {
        $filtered = $filtered | Where-Object { [datetime]$_.Timestamp -ge $StartDate }
    }
    if ($EndDate) {
        $filtered = $filtered | Where-Object { [datetime]$_.Timestamp -le $EndDate }
    }

    # Sort and limit
    return $filtered | Sort-Object Timestamp -Descending | Select-Object -First $Last
}

function Get-AuditSummary {
    <#
    .SYNOPSIS
    Returns audit event summary statistics.
    .PARAMETER Days
    Number of days to include. Default 7.
    #>
    [CmdletBinding()]
    param(
        [int]$Days = 7
    )

    $startDate = (Get-Date).AddDays(-$Days)
    $events = Get-AuditEvents -StartDate $startDate -Last 10000

    $summary = @{
        Period = @{
            StartDate = $startDate.ToString('yyyy-MM-dd')
            EndDate = (Get-Date).ToString('yyyy-MM-dd')
            Days = $Days
        }
        TotalEvents = $events.Count
        ByEventType = @{}
        ByCategory = @{}
        ByResult = @{}
        BySeverity = @{}
        ByUser = @{}
        CriticalEvents = @()
        FailedActions = @()
    }

    foreach ($event in $events) {
        # Count by type
        if (-not $summary.ByEventType.ContainsKey($event.EventType)) {
            $summary.ByEventType[$event.EventType] = 0
        }
        $summary.ByEventType[$event.EventType]++

        # Count by category
        if (-not $summary.ByCategory.ContainsKey($event.Category)) {
            $summary.ByCategory[$event.Category] = 0
        }
        $summary.ByCategory[$event.Category]++

        # Count by result
        if (-not $summary.ByResult.ContainsKey($event.Result)) {
            $summary.ByResult[$event.Result] = 0
        }
        $summary.ByResult[$event.Result]++

        # Count by severity
        if (-not $summary.BySeverity.ContainsKey($event.Severity)) {
            $summary.BySeverity[$event.Severity] = 0
        }
        $summary.BySeverity[$event.Severity]++

        # Count by user
        $userName = if ($event.User) { $event.User.Split('\')[-1] } else { 'Unknown' }
        if (-not $summary.ByUser.ContainsKey($userName)) {
            $summary.ByUser[$userName] = 0
        }
        $summary.ByUser[$userName]++

        # Collect critical events
        if ($event.Severity -eq 'Critical') {
            $summary.CriticalEvents += $event
        }

        # Collect failed actions
        if ($event.Result -eq 'Failure' -or $event.Result -eq 'Denied') {
            $summary.FailedActions += $event
        }
    }

    return $summary
}

function Export-AuditReport {
    <#
    .SYNOPSIS
    Exports audit events to a report file.
    .PARAMETER StartDate
    Report start date.
    .PARAMETER EndDate
    Report end date.
    .PARAMETER Format
    Output format: JSON, CSV, HTML
    .PARAMETER OutputPath
    Output file path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [datetime]$StartDate,

        [datetime]$EndDate = (Get-Date),

        [ValidateSet('JSON', 'CSV', 'HTML')]
        [string]$Format = 'JSON',

        [string]$OutputPath
    )

    $events = Get-AuditEvents -StartDate $StartDate -EndDate $EndDate -Last 100000
    $summary = Get-AuditSummary -Days ([math]::Ceiling(($EndDate - $StartDate).TotalDays))

    if (-not $OutputPath) {
        $dateStr = $StartDate.ToString('yyyyMMdd') + '-' + $EndDate.ToString('yyyyMMdd')
        $ext = switch ($Format) { 'JSON' { 'json' } 'CSV' { 'csv' } 'HTML' { 'html' } }
        $OutputPath = Join-Path $script:AuditLogPath "AuditReport-$dateStr.$ext"
    }

    switch ($Format) {
        'JSON' {
            @{
                ReportGenerated = (Get-Date).ToString('o')
                Period = @{
                    Start = $StartDate.ToString('o')
                    End = $EndDate.ToString('o')
                }
                Summary = $summary
                Events = $events
            } | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding UTF8
        }

        'CSV' {
            $events | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
        }

        'HTML' {
            $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>StateTrace Audit Report</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        h1 { color: #333; border-bottom: 2px solid #0078d4; padding-bottom: 10px; }
        h2 { color: #555; margin-top: 30px; }
        table { border-collapse: collapse; width: 100%; margin: 10px 0; background: white; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background: #0078d4; color: white; }
        tr:nth-child(even) { background: #f9f9f9; }
        .summary-cards { display: flex; gap: 15px; flex-wrap: wrap; }
        .card { background: white; padding: 15px; border-radius: 5px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); min-width: 150px; }
        .card h3 { margin: 0 0 10px 0; color: #666; font-size: 12px; text-transform: uppercase; }
        .card .value { font-size: 28px; font-weight: bold; color: #0078d4; }
        .critical { background: #ff1744; color: white; }
        .warning { background: #ff6d00; color: white; }
        .success { background: #00c853; color: white; }
    </style>
</head>
<body>
    <h1>StateTrace Audit Report</h1>
    <p><strong>Period:</strong> $($StartDate.ToString('yyyy-MM-dd')) to $($EndDate.ToString('yyyy-MM-dd'))</p>
    <p><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>

    <h2>Summary</h2>
    <div class="summary-cards">
        <div class="card">
            <h3>Total Events</h3>
            <div class="value">$($summary.TotalEvents)</div>
        </div>
        <div class="card $(if ($summary.BySeverity['Critical'] -gt 0) { 'critical' })">
            <h3>Critical</h3>
            <div class="value">$($summary.BySeverity['Critical'] ?? 0)</div>
        </div>
        <div class="card $(if ($summary.ByResult['Failure'] -gt 0) { 'warning' })">
            <h3>Failures</h3>
            <div class="value">$($summary.ByResult['Failure'] ?? 0)</div>
        </div>
        <div class="card">
            <h3>Users</h3>
            <div class="value">$($summary.ByUser.Count)</div>
        </div>
    </div>

    <h2>Events by Type</h2>
    <table>
        <tr><th>Event Type</th><th>Count</th></tr>
        $($summary.ByEventType.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
            "<tr><td>$($_.Key)</td><td>$($_.Value)</td></tr>"
        })
    </table>

    <h2>Events by Category</h2>
    <table>
        <tr><th>Category</th><th>Count</th></tr>
        $($summary.ByCategory.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
            "<tr><td>$($_.Key)</td><td>$($_.Value)</td></tr>"
        })
    </table>

    <h2>Recent Events</h2>
    <table>
        <tr>
            <th>Timestamp</th>
            <th>Type</th>
            <th>Category</th>
            <th>Action</th>
            <th>Target</th>
            <th>Result</th>
            <th>User</th>
        </tr>
        $($events | Select-Object -First 100 | ForEach-Object {
            "<tr>
                <td>$($_.TimestampLocal)</td>
                <td>$($_.EventType)</td>
                <td>$($_.Category)</td>
                <td>$($_.Action)</td>
                <td>$($_.Target)</td>
                <td>$($_.Result)</td>
                <td>$($_.User.Split('\')[-1])</td>
            </tr>"
        })
    </table>
</body>
</html>
"@
            $html | Set-Content -Path $OutputPath -Encoding UTF8
        }
    }

    Write-Verbose "[AuditTrail] Report exported to $OutputPath"
    return $OutputPath
}

function Clear-AuditTrail {
    <#
    .SYNOPSIS
    Clears old audit logs (retention policy).
    .PARAMETER RetentionDays
    Keep logs newer than this many days. Default 365.
    #>
    [CmdletBinding()]
    param(
        [int]$RetentionDays = 365
    )

    if (-not $script:AuditLogPath) {
        Initialize-AuditTrail
    }

    $cutoffDate = (Get-Date).AddDays(-$RetentionDays)
    $removed = 0

    $logFiles = Get-ChildItem -Path $script:AuditLogPath -Filter 'AuditTrail-*.jsonl' -ErrorAction SilentlyContinue

    foreach ($file in $logFiles) {
        if ($file.Name -match 'AuditTrail-(\d{4}-\d{2}-\d{2})\.jsonl') {
            $fileDate = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd', $null)
            if ($fileDate -lt $cutoffDate) {
                # Archive before deletion
                $archivePath = Join-Path $script:AuditLogPath 'Archive'
                if (-not (Test-Path $archivePath)) {
                    New-Item -Path $archivePath -ItemType Directory -Force | Out-Null
                }
                Move-Item -Path $file.FullName -Destination $archivePath -Force
                $removed++
            }
        }
    }

    Write-Verbose "[AuditTrail] Archived $removed old log files"
    return $removed
}

# Initialize on module load
Initialize-AuditTrail

Export-ModuleMember -Function @(
    'Initialize-AuditTrail',
    'Write-AuditEvent',
    'Flush-AuditBuffer',
    'Get-AuditEvents',
    'Get-AuditSummary',
    'Export-AuditReport',
    'Clear-AuditTrail'
)
