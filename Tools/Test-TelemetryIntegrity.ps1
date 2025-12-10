<#
.SYNOPSIS
Validates ingestion telemetry files for JSON integrity and required event coverage.

.DESCRIPTION
Reads a telemetry file (newline-delimited JSON) and fails when any line is not valid JSON.
Optionally enforces the presence of queue delay metrics and InterfaceSyncTiming events to
catch polluted or incomplete telemetry before analyzers run.

.PARAMETER Path
Telemetry file path (e.g., Logs\IngestionMetrics\<date>.json).

.PARAMETER RequireQueueSummary
Fail when no queue-related events are present (looks for QueueDelay/InterfacePortQueue metrics).

.PARAMETER RequireInterfaceSync
Fail when no InterfaceSyncTiming events are present.

.PARAMETER PassThru
Return a summary object instead of only writing to the host/throwing.

.EXAMPLE
pwsh -File Tools\Test-TelemetryIntegrity.ps1 -Path Logs\IngestionMetrics\2025-12-01.json -RequireQueueSummary -RequireInterfaceSync
#>
param(
    [Parameter(Mandatory)][string]$Path,
    [switch]$RequireQueueSummary,
    [switch]$RequireInterfaceSync,
    [switch]$PassThru
)

Set-StrictMode -Version Latest

if (-not (Test-Path -LiteralPath $Path)) {
    throw ("Telemetry file not found: {0}" -f $Path)
}

$errors = [System.Collections.Generic.List[psobject]]::new()
$queueFound = $false
$syncFound = $false
$totalLines = 0
$parsedLines = 0

function Test-EventMatch {
    param($Object, [string[]]$Needle)

    foreach ($name in $Needle) {
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        # EventName property
        if ($Object.PSObject.Properties.Name -contains 'EventName' -and ($Object.EventName -match $name)) { return $true }

        # Top-level property
        if ($Object.PSObject.Properties.Name -contains $name) { return $true }

        # Fallback: string search
        $lineText = ($Object | ConvertTo-Json -Depth 5 -Compress)
        if ($lineText -match $name) { return $true }
    }
    return $false
}

Get-Content -LiteralPath $Path | ForEach-Object {
    $line = $_
    if ([string]::IsNullOrWhiteSpace($line)) { return }

    $totalLines++
    try {
        $obj = $line | ConvertFrom-Json -ErrorAction Stop
        $parsedLines++

        if (-not $queueFound) {
            $queueFound = Test-EventMatch -Object $obj -Needle @('QueueDelay', 'InterfacePortQueueMetrics', 'QueueDelaySummary')
        }
        if (-not $syncFound) {
            $syncFound = Test-EventMatch -Object $obj -Needle @('InterfaceSyncTiming')
        }
    } catch {
        $errors.Add([pscustomobject]@{
                LineNumber = $totalLines
                Message    = $_.Exception.Message
                Content    = $line
            }) | Out-Null
    }
}

$summary = [pscustomobject]@{
    Path               = (Resolve-Path -LiteralPath $Path).Path
    TotalLines         = $totalLines
    ParsedLines        = $parsedLines
    ErrorCount         = $errors.Count
    QueueEventsFound   = $queueFound
    InterfaceSyncFound = $syncFound
}

if ($errors.Count -gt 0) {
    $preview = $errors | Select-Object -First 3
    $errorText = $preview | Format-Table LineNumber, Message -AutoSize | Out-String
    throw ("Telemetry integrity failed: {0} invalid lines found.`n{1}" -f $errors.Count, $errorText)
}

if ($RequireQueueSummary -and -not $queueFound) {
    throw "Telemetry integrity failed: queue summary/metrics not found (enable dispatcher/queue instrumentation before parsing)."
}

if ($RequireInterfaceSync -and -not $syncFound) {
    throw "Telemetry integrity failed: InterfaceSyncTiming events not found."
}

Write-Host ("Telemetry integrity passed for {0} (Lines={1}, QueueFound={2}, InterfaceSyncFound={3})" -f $summary.Path, $summary.TotalLines, $summary.QueueEventsFound, $summary.InterfaceSyncFound) -ForegroundColor Green

if ($PassThru) { return $summary }
