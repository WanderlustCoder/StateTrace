[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MetricsPath,

    [string]$OutputPath,

    [switch]$InPlace,

    [switch]$Force
)

<#
.SYNOPSIS
Synthesizes PortBatchReady events from InterfacePortDispatchMetrics telemetry.

.DESCRIPTION
Some incremental-loading runs (especially harness-driven sweeps) only emit
InterfacePortDispatchMetrics/InterfacePortQueueMetrics events. The existing
performance analyzers expect PortBatchReady entries, so this helper inspects
the source telemetry and materialises PortBatchReady rows per batch using all
available dispatch/queue metadata. When PortBatchReady already exists the
script exits unless -Force is supplied.

.EXAMPLE
pwsh Tools\Add-PortBatchReadyTelemetry.ps1 `
    -MetricsPath Logs\IngestionMetrics\2025-11-14.json `
    -InPlace
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $MetricsPath)) {
    throw "Metrics file '$MetricsPath' does not exist."
}

$sourcePath = (Resolve-Path -LiteralPath $MetricsPath).Path
$destinationPath = $null
$backupPath = $null

if ($InPlace.IsPresent -and $OutputPath) {
    throw 'Specify either -InPlace or -OutputPath, not both.'
}

if ($InPlace.IsPresent -or -not $OutputPath) {
    $destinationPath = $sourcePath
    $backupPath = "$($sourcePath).bak"
    Copy-Item -LiteralPath $sourcePath -Destination $backupPath -Force
}
else {
    $destinationPath = $OutputPath
    $destDir = Split-Path -Path $destinationPath -Parent
    if ($destDir -and -not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
    Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
}

$rawLines = Get-Content -LiteralPath $sourcePath
$streamEvents = New-Object System.Collections.Generic.List[pscustomobject]
$queueEvents = @{}
$dispatchEvents = @{}
$hasPortBatchReady = $false

foreach ($line in $rawLines) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    try {
        $obj = $line | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Warning ("Skipping malformed JSON: {0}" -f $_.Exception.Message)
        continue
    }
    $eventName = '' + $obj.EventName
    switch ($eventName) {
        'PortBatchReady' {
            $hasPortBatchReady = $true
        }
        'InterfacePortStreamMetrics' {
            if ($obj.BatchId) {
                $streamEvents.Add($obj) | Out-Null
            }
        }
        'InterfacePortQueueMetrics' {
            if ($obj.BatchId) {
                $queueEvents[$obj.BatchId] = $obj
            }
        }
        'InterfacePortDispatchMetrics' {
            if ($obj.BatchId) {
                $dispatchEvents[$obj.BatchId] = $obj
            }
        }
        default { }
    }
}

if ($hasPortBatchReady -and -not $Force) {
    Write-Host 'PortBatchReady telemetry already present; no synthesis required.' -ForegroundColor Yellow
    if ($backupPath) { Remove-Item -LiteralPath $backupPath -Force }
    return
}

if ($streamEvents.Count -eq 0) {
    if ($queueEvents.Count -gt 0) {
        # Fall back to queue metrics when stream metrics are absent (e.g., dispatcher harness-only runs)
        foreach ($qe in $queueEvents.Values) {
            $runDateValue = $null
            $runDateProp = $qe.PSObject.Properties.Match('RunDate')
            if ($runDateProp -and $runDateProp.Count -gt 0 -and $runDateProp[0].Value) {
                $runDateValue = '' + $runDateProp[0].Value
            }
            $timestampValue = $null
            $tsProp = $qe.PSObject.Properties.Match('Timestamp')
            if ($tsProp -and $tsProp.Count -gt 0 -and $tsProp[0].Value) {
                $timestampValue = $tsProp[0].Value
            }
            $syntheticStream = [pscustomobject]@{
                EventName    = 'InterfacePortStreamMetrics'
                BatchId      = '' + $qe.BatchId
                Hostname     = '' + $qe.Hostname
                RowsReceived = if ($qe.ChunkSize -gt 0) { [int]$qe.ChunkSize } elseif ($qe.TotalPorts -gt 0) { [int]$qe.TotalPorts } else { 0 }
                RunDate      = if ($runDateValue) { $runDateValue } elseif ($timestampValue) { ([datetime]$timestampValue).ToString('yyyy-MM-dd HH:mm:ss') } else { '' }
                Timestamp    = $timestampValue
            }
            $streamEvents.Add($syntheticStream) | Out-Null
        }
    } else {
        throw "No InterfacePortStreamMetrics events found in '$MetricsPath'; cannot synthesize PortBatchReady."
    }
}

$synthesized = New-Object System.Collections.Generic.List[string]

foreach ($stream in $streamEvents | Sort-Object { [datetime]$_.Timestamp }) {
    $batchId = if ($stream.BatchId) { '' + $stream.BatchId } else { [guid]::NewGuid().ToString() }
    $queue = $null
    if ($batchId -and $queueEvents.ContainsKey($batchId)) {
        $queue = $queueEvents[$batchId]
    }
    $dispatch = $null
    if ($batchId -and $dispatchEvents.ContainsKey($batchId)) {
        $dispatch = $dispatchEvents[$batchId]
    }

    $chunkSize = 0
    if ($queue -and $queue.PSObject.Properties.Name -contains 'ChunkSize' -and $queue.ChunkSize -gt 0) {
        $chunkSize = [int]$queue.ChunkSize
    } elseif ($stream.PSObject.Properties.Name -contains 'RowsReceived' -and $stream.RowsReceived -gt 0) {
        $chunkSize = [int]$stream.RowsReceived
    } elseif ($dispatch -and $dispatch.PSObject.Properties.Name -contains 'BatchSize' -and $dispatch.BatchSize -gt 0) {
        $chunkSize = [int]$dispatch.BatchSize
    }

    $estimatedBatchCount = 0
    if ($queue -and $queue.PSObject.Properties.Name -contains 'BatchCount' -and $queue.BatchCount -gt 0) {
        $estimatedBatchCount = [int]$queue.BatchCount
    } elseif ($dispatch -and $dispatch.PSObject.Properties.Name -contains 'BatchCount' -and $dispatch.BatchCount -gt 0) {
        $estimatedBatchCount = [int]$dispatch.BatchCount
    }

    $rowsReceived = 0
    if ($stream.PSObject.Properties.Name -contains 'RowsReceived' -and $stream.RowsReceived -gt 0) {
        $rowsReceived = [int]$stream.RowsReceived
    } elseif ($dispatch -and $dispatch.PSObject.Properties.Name -contains 'TotalPorts' -and $dispatch.TotalPorts -gt 0) {
        $rowsReceived = [int]$dispatch.TotalPorts
    } elseif ($queue -and $queue.PSObject.Properties.Name -contains 'TotalPorts' -and $queue.TotalPorts -gt 0) {
        $rowsReceived = [int]$queue.TotalPorts
    }

    $runDate = ''
    if ($stream.PSObject.Properties.Name -contains 'RunDate' -and $stream.RunDate) {
        $runDate = '' + $stream.RunDate
    } elseif ($queue -and $queue.PSObject.Properties.Name -contains 'RunDate' -and $queue.RunDate) {
        $runDate = '' + $queue.RunDate
    } else {
        $runDate = ([datetime]$stream.Timestamp).ToString('yyyy-MM-dd HH:mm:ss')
    }

    $timestamp = ([datetime]$stream.Timestamp).ToString('o')
    $eventPayload = [ordered]@{
        EventName            = 'PortBatchReady'
        Timestamp            = $timestamp
        Hostname             = '' + $stream.Hostname
        BatchId              = $batchId
        RunDate              = $runDate
        PortsCommitted       = $rowsReceived
        ChunkSize            = $chunkSize
        EstimatedBatchCount  = $estimatedBatchCount
        Synthesized          = $true
        SourceEvent          = 'InterfacePortStreamMetrics'
    }
    $synthesized.Add( ($eventPayload | ConvertTo-Json -Depth 4 -Compress) ) | Out-Null
}

if ($synthesized.Count -eq 0) {
    throw "Failed to synthesize PortBatchReady events from '$MetricsPath'."
}

$linesToAppend = $synthesized
Add-Content -LiteralPath $destinationPath -Value $linesToAppend

Write-Host ("Appended {0} synthesized PortBatchReady events to {1}" -f $synthesized.Count, $destinationPath) -ForegroundColor Green
if ($backupPath) {
    Write-Host ("Original telemetry preserved at {0}" -f $backupPath) -ForegroundColor DarkGray
}
