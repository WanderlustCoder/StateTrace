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
Synthesizes `InterfaceSyncTiming` events (and normalizes existing ones) when UI telemetry is unavailable.

.DESCRIPTION
Rewrites the specified telemetry file, emitting a synthetic `InterfaceSyncTiming`
record immediately after each `InterfacePortStreamMetrics` entry. Populated fields
use available stream metrics (clone duration, state update, etc.). Existing
`InterfaceSyncTiming` events gain a `SiteCacheUpdateDurationMs` property when missing
so downstream analyzers remain functional.

.EXAMPLE
pwsh Tools\Synthesize-InterfaceSyncTelemetry.ps1 `
    -MetricsPath Logs\IngestionMetrics\2025-11-14.json `
    -InPlace
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $MetricsPath)) {
    throw "Metrics file '$MetricsPath' does not exist."
}

$resolvedMetrics = (Resolve-Path -LiteralPath $MetricsPath).Path
$finalOutput = if ($OutputPath) { [System.IO.Path]::GetFullPath($OutputPath) } elseif ($InPlace) { $resolvedMetrics } else { "$resolvedMetrics.synthetic" }
$tempOutput = if ($InPlace) { "$resolvedMetrics.synthetic.tmp" } else { $finalOutput }

$inputStream = [System.IO.File]::OpenRead($resolvedMetrics)
$reader = New-Object System.IO.StreamReader($inputStream)
$outputStream = [System.IO.File]::Open($tempOutput, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
$writer = New-Object System.IO.StreamWriter($outputStream, [System.Text.Encoding]::UTF8)
$synthesizedCount = 0

try {
    while (-not $reader.EndOfStream) {
        $line = $reader.ReadLine()
        if ([string]::IsNullOrWhiteSpace($line)) {
            $writer.WriteLine($line)
            continue
        }

        $evt = $null
        try { $evt = $line | ConvertFrom-Json -ErrorAction Stop } catch {
            $writer.WriteLine($line)
            continue
        }

        $handled = $false
        if ($evt.EventName -eq 'InterfaceSyncTiming') {
            if (-not ($evt.PSObject.Properties.Name -contains 'SiteCacheUpdateDurationMs')) {
                $evt | Add-Member -MemberType NoteProperty -Name 'SiteCacheUpdateDurationMs' -Value 0
            }
            $writer.WriteLine(($evt | ConvertTo-Json -Depth 4 -Compress))
            $handled = $true
        }

        if (-not $handled) {
            $writer.WriteLine($line)
        }

        if ($evt.EventName -ne 'InterfacePortStreamMetrics') { continue }

        $timestamp = $null
        if ($evt.PSObject.Properties.Name -contains 'Timestamp') {
            try { $timestamp = [datetime]$evt.Timestamp } catch { $timestamp = $null }
        }
        if (-not $timestamp -and $evt.PSObject.Properties.Name -contains 'RunDate') {
            try { $timestamp = [datetime]$evt.RunDate } catch { $timestamp = $null }
        }
        if (-not $timestamp) { $timestamp = Get-Date }

        $hostname = '' + $evt.Hostname
        $site = $hostname
        if (-not [string]::IsNullOrWhiteSpace($hostname)) {
            $dashIndex = $hostname.IndexOf('-')
            if ($dashIndex -gt 0) { $site = $hostname.Substring(0, $dashIndex) }
        } else {
            $site = 'Unknown'
        }

        $uiClone = if ($evt.PSObject.Properties.Name -contains 'StreamCloneDurationMs') { [double]$evt.StreamCloneDurationMs } else { 0.0 }
        $streamDispatch = if ($evt.PSObject.Properties.Name -contains 'StreamStateUpdateDurationMs') { [double]$evt.StreamStateUpdateDurationMs } else { 0.0 }
        $diffDuration = if ($evt.PSObject.Properties.Name -contains 'StreamCloneDurationMs') { [double]$evt.StreamCloneDurationMs / 2.0 } else { 0.0 }

        $syncEvent = [ordered]@{
            EventName                 = 'InterfaceSyncTiming'
            Timestamp                 = $timestamp.ToString('o')
            Hostname                  = $hostname
            Site                      = $site
            UiCloneDurationMs         = [math]::Round($uiClone, 3)
            StreamDispatchDurationMs  = [math]::Round($streamDispatch, 3)
            DiffDurationMs            = [math]::Round($diffDuration, 3)
            SiteCacheUpdateDurationMs = 0
            Synthesized               = $true
        }
        $writer.WriteLine(($syncEvent | ConvertTo-Json -Depth 4 -Compress))
        $synthesizedCount++
    }
} finally {
    $writer.Flush()
    $writer.Dispose()
    $reader.Dispose()
}

if ($InPlace) {
    if (-not $Force) {
        $backupPath = "$resolvedMetrics.bak"
        if (-not (Test-Path -LiteralPath $backupPath)) {
            Copy-Item -LiteralPath $resolvedMetrics -Destination $backupPath
        }
    }
    Move-Item -LiteralPath $tempOutput -Destination $resolvedMetrics -Force
    $finalOutput = $resolvedMetrics
}

if ($synthesizedCount -eq 0) {
    Write-Warning ("No InterfacePortStreamMetrics events were found in '{0}'. No InterfaceSyncTiming entries were synthesized." -f $MetricsPath)
} else {
    Write-Host ("Synthesized {0} InterfaceSyncTiming event(s) into '{1}'." -f $synthesizedCount, $finalOutput) -ForegroundColor Green
}

[pscustomobject]@{
    MetricsPath       = $finalOutput
    EventsSynthesized = $synthesizedCount
}
