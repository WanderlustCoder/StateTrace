<#
.SYNOPSIS
Real-time connectivity monitor for network devices.

.DESCRIPTION
Polls devices via ICMP (ping) and optionally SSH/SNMP to monitor reachability.
Integrates with AlertRuleModule to fire alerts on state changes.

.PARAMETER Hosts
Array of hostnames or IP addresses to monitor.

.PARAMETER HostFile
Path to file containing hosts (one per line).

.PARAMETER IntervalSeconds
Polling interval in seconds. Default 60.

.PARAMETER TimeoutMs
Ping timeout in milliseconds. Default 2000.

.PARAMETER RetryCount
Number of retries before marking host as down. Default 2.

.PARAMETER Duration
How long to run in minutes. 0 = indefinitely. Default 0.

.PARAMETER EnableAlerts
Enable alert rule evaluation. Default $true.

.PARAMETER LogPath
Path to write monitoring log.

.EXAMPLE
.\Start-ConnectivityMonitor.ps1 -Hosts '10.0.0.1','10.0.0.2' -IntervalSeconds 30

.EXAMPLE
.\Start-ConnectivityMonitor.ps1 -HostFile '.\Data\RoutingHosts.txt' -Duration 60
#>

[CmdletBinding()]
param(
    [string[]]$Hosts,
    [string]$HostFile,
    [int]$IntervalSeconds = 60,
    [int]$TimeoutMs = 2000,
    [int]$RetryCount = 2,
    [int]$Duration = 0,
    [switch]$EnableAlerts = $true,
    [string]$LogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$projectRoot = Split-Path -Parent $PSScriptRoot

# Import required modules
Import-Module (Join-Path $projectRoot 'Modules\AlertRuleModule.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $projectRoot 'Modules\TelemetryModule.psm1') -Force -DisableNameChecking -ErrorAction SilentlyContinue

# State tracking
$script:HostStates = @{}
$script:StartTime = [datetime]::UtcNow
$script:PollCount = 0

function Get-MonitorHosts {
    $allHosts = [System.Collections.Generic.List[string]]::new()

    if ($Hosts) {
        foreach ($h in $Hosts) {
            if ($h -and $h.Trim()) {
                [void]$allHosts.Add($h.Trim())
            }
        }
    }

    if ($HostFile -and (Test-Path $HostFile)) {
        $fileHosts = Get-Content $HostFile | Where-Object { $_ -and $_.Trim() -and -not $_.StartsWith('#') }
        foreach ($h in $fileHosts) {
            if ($h.Trim() -and -not $allHosts.Contains($h.Trim())) {
                [void]$allHosts.Add($h.Trim())
            }
        }
    }

    return $allHosts.ToArray()
}

function Test-HostConnectivity {
    param(
        [string]$Host,
        [int]$Timeout = 2000,
        [int]$Retries = 2
    )

    $result = [PSCustomObject]@{
        Host = $Host
        Reachable = $false
        ResponseTime = -1
        Attempts = 0
        Timestamp = [datetime]::UtcNow
        Error = $null
    }

    for ($i = 0; $i -le $Retries; $i++) {
        $result.Attempts++
        try {
            $ping = Test-Connection -ComputerName $Host -Count 1 -TimeoutSeconds ([Math]::Ceiling($Timeout / 1000)) -ErrorAction Stop

            if ($ping) {
                $result.Reachable = $true
                $result.ResponseTime = if ($ping.ResponseTime) { $ping.ResponseTime } else { 0 }
                break
            }
        } catch {
            $result.Error = $_.Exception.Message
            Start-Sleep -Milliseconds 500
        }
    }

    return $result
}

function Update-HostState {
    param(
        [PSCustomObject]$PingResult
    )

    $host = $PingResult.Host
    $wasReachable = $true
    $stateChanged = $false

    if ($script:HostStates.ContainsKey($host)) {
        $wasReachable = $script:HostStates[$host].Reachable
        $stateChanged = $wasReachable -ne $PingResult.Reachable
    } else {
        $stateChanged = $true
    }

    $state = [PSCustomObject]@{
        Host = $host
        Reachable = $PingResult.Reachable
        LastSeen = if ($PingResult.Reachable) { $PingResult.Timestamp } elseif ($script:HostStates.ContainsKey($host)) { $script:HostStates[$host].LastSeen } else { $null }
        LastCheck = $PingResult.Timestamp
        ResponseTime = $PingResult.ResponseTime
        ConsecutiveFailures = if ($PingResult.Reachable) { 0 } elseif ($script:HostStates.ContainsKey($host)) { $script:HostStates[$host].ConsecutiveFailures + 1 } else { 1 }
        StateChanged = $stateChanged
        PreviousState = if ($script:HostStates.ContainsKey($host)) { $script:HostStates[$host].Reachable } else { $null }
    }

    $script:HostStates[$host] = $state

    return $state
}

function Write-MonitorLog {
    param(
        [string]$Message,
        [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logLine = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        'Error' { Write-Host $logLine -ForegroundColor Red }
        'Warning' { Write-Host $logLine -ForegroundColor Yellow }
        'Success' { Write-Host $logLine -ForegroundColor Green }
        default { Write-Host $logLine }
    }

    if ($LogPath) {
        Add-Content -Path $LogPath -Value $logLine -ErrorAction SilentlyContinue
    }
}

function Format-ResponseTime {
    param([int]$Ms)
    if ($Ms -lt 0) { return 'N/A' }
    if ($Ms -lt 1) { return '<1ms' }
    return "${Ms}ms"
}

# Main execution
Write-Host @"

╔═══════════════════════════════════════════════════════════════╗
║           StateTrace Connectivity Monitor                      ║
╚═══════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

$targetHosts = Get-MonitorHosts

if ($targetHosts.Count -eq 0) {
    Write-Error "No hosts specified. Use -Hosts or -HostFile parameter."
    exit 1
}

Write-MonitorLog "Starting connectivity monitor for $($targetHosts.Count) host(s)"
Write-MonitorLog "Interval: ${IntervalSeconds}s | Timeout: ${TimeoutMs}ms | Retries: $RetryCount"

if ($EnableAlerts.IsPresent) {
    Initialize-DefaultAlertRules
    Write-MonitorLog "Alert rules enabled"
}

$endTime = if ($Duration -gt 0) { $script:StartTime.AddMinutes($Duration) } else { $null }

try {
    while ($true) {
        $script:PollCount++
        $pollStart = [datetime]::UtcNow

        if ($endTime -and [datetime]::UtcNow -ge $endTime) {
            Write-MonitorLog "Duration limit reached. Stopping monitor."
            break
        }

        Write-Host "`n--- Poll #$($script:PollCount) at $(Get-Date -Format 'HH:mm:ss') ---" -ForegroundColor Gray

        $reachableCount = 0
        $unreachableCount = 0

        foreach ($host in $targetHosts) {
            $pingResult = Test-HostConnectivity -Host $host -Timeout $TimeoutMs -Retries $RetryCount
            $state = Update-HostState -PingResult $pingResult

            $statusIcon = if ($state.Reachable) { '[OK]' } else { '[DOWN]' }
            $statusColor = if ($state.Reachable) { 'Green' } else { 'Red' }
            $rtDisplay = Format-ResponseTime -Ms $state.ResponseTime

            if ($state.StateChanged) {
                $changeType = if ($state.Reachable) { 'UP' } else { 'DOWN' }
                Write-Host "  $statusIcon $host - $rtDisplay [STATE CHANGE: $changeType]" -ForegroundColor $statusColor
                Write-MonitorLog "$host changed state to $changeType" -Level $(if ($state.Reachable) { 'Success' } else { 'Warning' })
            } else {
                Write-Host "  $statusIcon $host - $rtDisplay" -ForegroundColor $statusColor
            }

            if ($state.Reachable) {
                $reachableCount++
            } else {
                $unreachableCount++
            }

            # Evaluate alerts
            if ($EnableAlerts.IsPresent) {
                $alertContext = @{
                    Host = $host
                    PingStatus = if ($state.Reachable) { 'Success' } else { 'Failed' }
                    ResponseTime = $state.ResponseTime
                    ConsecutiveFailures = $state.ConsecutiveFailures
                    StateChanged = $state.StateChanged
                }

                $alerts = Invoke-AlertEvaluation -Context $alertContext -Source $host
                foreach ($alert in $alerts) {
                    Write-MonitorLog "ALERT: $($alert.RuleName) - $host" -Level 'Warning'
                }
            }
        }

        # Summary
        $totalHosts = $targetHosts.Count
        $upPercent = [Math]::Round(($reachableCount / $totalHosts) * 100, 1)
        Write-Host "`n  Summary: $reachableCount/$totalHosts reachable ($upPercent%)" -ForegroundColor $(if ($unreachableCount -eq 0) { 'Green' } else { 'Yellow' })

        # Publish telemetry
        try {
            if (Get-Command 'Publish-TelemetryEvent' -ErrorAction SilentlyContinue) {
                Publish-TelemetryEvent -EventType 'ConnectivityPoll' -Data @{
                    PollNumber = $script:PollCount
                    TotalHosts = $totalHosts
                    Reachable = $reachableCount
                    Unreachable = $unreachableCount
                    UpPercent = $upPercent
                }
            }
        } catch { }

        # Wait for next interval
        $elapsed = ([datetime]::UtcNow - $pollStart).TotalSeconds
        $sleepTime = [Math]::Max(1, $IntervalSeconds - $elapsed)
        Write-Host "  Next poll in $([Math]::Round($sleepTime))s (Ctrl+C to stop)" -ForegroundColor Gray
        Start-Sleep -Seconds $sleepTime
    }
} finally {
    Write-Host "`n" -NoNewline
    Write-MonitorLog "Monitor stopped after $($script:PollCount) polls"

    # Final summary
    $summary = Get-AlertSummary
    if ($summary.TotalActive -gt 0) {
        Write-MonitorLog "Active alerts: $($summary.TotalActive) (Critical: $($summary.Critical), High: $($summary.High))" -Level 'Warning'
    }
}
