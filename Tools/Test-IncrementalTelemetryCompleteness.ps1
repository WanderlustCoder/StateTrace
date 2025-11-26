[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MetricsPath,

    [switch]$RequirePortBatchReady,
    [switch]$RequireInterfaceSync,
    [switch]$RequireSchedulerLaunch,
    [switch]$ThrowOnMissing
)

<#
.SYNOPSIS
Validates that incremental-loading telemetry contains the expected event types.

.DESCRIPTION
Scans a newline-delimited telemetry JSON file (typically `Logs\IngestionMetrics\<date>.json`)
and counts critical events: `PortBatchReady`, `InterfacePortStreamMetrics`,
`InterfaceSyncTiming`, and `ParserSchedulerLaunch`. The script reports which
signals are missing and optionally fails when required event types are absent.

.EXAMPLE
pwsh Tools\Test-IncrementalTelemetryCompleteness.ps1 `
    -MetricsPath Logs\IngestionMetrics\2025-11-14.json `
    -RequirePortBatchReady -RequireInterfaceSync -RequireSchedulerLaunch -ThrowOnMissing
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $MetricsPath)) {
    throw "Telemetry file '$MetricsPath' does not exist."
}

$counts = @{
    PortBatchReady             = 0
    InterfacePortStreamMetrics = 0
    InterfaceSyncTiming        = 0
    ParserSchedulerLaunch      = 0
}

Get-Content -LiteralPath $MetricsPath -ReadCount 500 | ForEach-Object {
    foreach ($line in $_) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $evt = $null
        try {
            $evt = $line | ConvertFrom-Json -ErrorAction Stop
        } catch {
            continue
        }
        switch ($evt.EventName) {
            'PortBatchReady'             { $counts.PortBatchReady++ }
            'InterfacePortStreamMetrics' { $counts.InterfacePortStreamMetrics++ }
            'InterfaceSyncTiming'        { $counts.InterfaceSyncTiming++ }
            'ParserSchedulerLaunch'      { $counts.ParserSchedulerLaunch++ }
        }
    }
}

$missing = New-Object System.Collections.Generic.List[string]
if ($RequirePortBatchReady -and $counts.PortBatchReady -le 0) {
    $missing.Add('PortBatchReady') | Out-Null
}
if ($RequireInterfaceSync -and $counts.InterfaceSyncTiming -le 0) {
    $missing.Add('InterfaceSyncTiming') | Out-Null
}
if ($RequireSchedulerLaunch -and $counts.ParserSchedulerLaunch -le 0) {
    $missing.Add('ParserSchedulerLaunch') | Out-Null
}

$result = [pscustomobject]@{
    MetricsPath                 = (Resolve-Path -LiteralPath $MetricsPath).Path
    PortBatchReadyCount         = $counts.PortBatchReady
    InterfacePortStreamCount    = $counts.InterfacePortStreamMetrics
    InterfaceSyncTimingCount    = $counts.InterfaceSyncTiming
    ParserSchedulerLaunchCount  = $counts.ParserSchedulerLaunch
    MissingSignals              = $missing.ToArray()
    Pass                        = ($missing.Count -eq 0)
}

if ($missing.Count -gt 0) {
    $missingList = $missing -join ', '
    $message = "Telemetry file '$($result.MetricsPath)' is missing required events: $missingList."
    if ($ThrowOnMissing) {
        throw $message
    } else {
        Write-Warning $message
    }
}

return $result
