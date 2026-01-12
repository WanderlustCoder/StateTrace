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
Synthesizes `ParserSchedulerLaunch` telemetry from existing parser events.

.DESCRIPTION
Reads a newline-delimited telemetry file (typically `Logs/IngestionMetrics/<date>.json`),
identifies `ParseDuration` events (which indicate the parser scheduler order), and injects
synthetic `ParserSchedulerLaunch` events immediately after each parse entry. The generated
events track the site, remaining queued jobs, and queued site count, enabling downstream
analyzers to evaluate fairness even when the live scheduler instrumentation was missing.

Use `-InPlace` to rewrite the original telemetry file; otherwise specify `-OutputPath`
to write a patched copy.

.EXAMPLE
pwsh Tools\Synthesize-ParserSchedulerTelemetry.ps1 `
    -MetricsPath Logs\IngestionMetrics\2025-11-14.json `
    -InPlace
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $MetricsPath)) {
    throw "Metrics file '$MetricsPath' does not exist."
}

$resolvedMetricsPath = (Resolve-Path -LiteralPath $MetricsPath).Path
$finalOutput = if ($OutputPath) {
    [System.IO.Path]::GetFullPath($OutputPath)
} elseif ($InPlace) {
    $resolvedMetricsPath
} else {
    "$resolvedMetricsPath.synthetic"
}

$tempOutput = if ($InPlace) {
    "$resolvedMetricsPath.synthetic.tmp"
} else {
    $finalOutput
}

$parseEvents = [System.Collections.Generic.List[psobject]]::new()
$siteRemaining = @{}

Get-Content -LiteralPath $MetricsPath -ReadCount 500 | ForEach-Object {
    foreach ($line in $_) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $evt = $null
        try {
            $evt = $line | ConvertFrom-Json -ErrorAction Stop
        } catch { continue }

        if ($evt.EventName -ne 'ParseDuration') { continue }
        $site = ''
        if ($evt.PSObject.Properties.Name -contains 'Site') {
            $site = ('' + $evt.Site).Trim()
        }
        if ([string]::IsNullOrWhiteSpace($site) -and $evt.PSObject.Properties.Name -contains 'Hostname') {
            $hostname = ('' + $evt.Hostname).Trim()
            if ($hostname) {
                $dashIndex = $hostname.IndexOf('-')
                if ($dashIndex -gt 0) { $site = $hostname.Substring(0, $dashIndex) }
            }
        }
        if ([string]::IsNullOrWhiteSpace($site)) { continue }
        $timestamp = $null
        if ($evt.PSObject.Properties.Name -contains 'Timestamp' -and $evt.Timestamp) {
            try { $timestamp = [datetime]$evt.Timestamp } catch { $timestamp = $null }
        }
        if (-not $timestamp -and $evt.PSObject.Properties.Name -contains 'StartTime' -and $evt.StartTime) {
            try { $timestamp = [datetime]$evt.StartTime } catch { $timestamp = $null }
        }
        if (-not $timestamp) { $timestamp = Get-Date }
        $record = [pscustomobject]@{
            Site      = $site
            Timestamp = $timestamp
        }
        $parseEvents.Add($record) | Out-Null
        if ($siteRemaining.ContainsKey($site)) {
            $siteRemaining[$site]++
        } else {
            $siteRemaining[$site] = 1
        }
    }
}

if ($parseEvents.Count -eq 0) {
    Write-Warning ("No ParseDuration events were found in '{0}'. No scheduler telemetry was synthesized." -f $MetricsPath)
    return
}

$queue = New-Object 'System.Collections.Generic.Queue[psobject]'
foreach ($record in $parseEvents) { $queue.Enqueue($record) }

$inputStream = [System.IO.File]::OpenRead($resolvedMetricsPath)
$reader = New-Object System.IO.StreamReader($inputStream)

$outputStream = [System.IO.File]::Open($tempOutput, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
$writer = New-Object System.IO.StreamWriter($outputStream, [System.Text.Encoding]::UTF8)

try {
    while (-not $reader.EndOfStream) {
        $line = $reader.ReadLine()
        $writer.WriteLine($line)
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $evt = $null
        try { $evt = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
        if ($evt.EventName -ne 'ParseDuration') { continue }
        if ($queue.Count -eq 0) { continue }
        $current = $queue.Dequeue()
        if ($siteRemaining.ContainsKey($current.Site)) {
            $siteRemaining[$current.Site]--
            if ($siteRemaining[$current.Site] -le 0) {
                $null = $siteRemaining.Remove($current.Site)
            }
        }
        $queuedJobs = $queue.Count
        $queuedSites = ($siteRemaining.Keys | Measure-Object).Count
        $syntheticEvent = [ordered]@{
            EventName          = 'ParserSchedulerLaunch'
            Timestamp          = $current.Timestamp.ToString('o')
            Site               = $current.Site
            ActiveWorkers      = 1
            ActiveSites        = 1
            ThreadBudget       = 1
            QueuedJobs         = $queuedJobs
            QueuedSites        = $queuedSites
            Synthesized        = $true
        }
        $writer.WriteLine(($syntheticEvent | ConvertTo-Json -Depth 3 -Compress))
    }
} finally {
    if ($writer) { try { $writer.Flush() } catch { Write-Verbose "Caught exception in Synthesize-ParserSchedulerTelemetry.ps1: $($_.Exception.Message)" } }
    if ($writer) { try { $writer.Dispose() } catch { Write-Verbose "Caught exception in Synthesize-ParserSchedulerTelemetry.ps1: $($_.Exception.Message)" } }
    if ($reader) { try { $reader.Dispose() } catch { Write-Verbose "Caught exception in Synthesize-ParserSchedulerTelemetry.ps1: $($_.Exception.Message)" } }
    if ($outputStream) { try { $outputStream.Dispose() } catch { Write-Verbose "Caught exception in Synthesize-ParserSchedulerTelemetry.ps1: $($_.Exception.Message)" } }
    if ($inputStream) { try { $inputStream.Dispose() } catch { Write-Verbose "Caught exception in Synthesize-ParserSchedulerTelemetry.ps1: $($_.Exception.Message)" } }
}

if ($InPlace) {
    if (-not $Force) {
        $backupPath = "$resolvedMetricsPath.bak"
        if (-not (Test-Path -LiteralPath $backupPath)) {
            Copy-Item -LiteralPath $resolvedMetricsPath -Destination $backupPath
        }
    }
    Move-Item -LiteralPath $tempOutput -Destination $resolvedMetricsPath -Force
    $finalOutput = $resolvedMetricsPath
} else {
    $finalOutput = $tempOutput
}

Write-Host ("Synthesized {0} ParserSchedulerLaunch event(s) into '{1}'." -f $parseEvents.Count, $finalOutput) -ForegroundColor Green

[pscustomobject]@{
    MetricsPath      = $finalOutput
    EventsSynthesized = $parseEvents.Count
}
