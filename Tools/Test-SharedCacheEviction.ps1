<#
.SYNOPSIS
Validates shared cache snapshot size, host count, and eviction rate.

.DESCRIPTION
ST-Q-003: Analyzes shared cache snapshots to detect:
- Unexpected cache shrinkage (host/row count decrease)
- Size budget violations (exceeding max limits)
- High eviction rates from telemetry

Fails harness if cache shrinks unexpectedly or exceeds size budget.

.PARAMETER CurrentSnapshotPath
Path to current shared cache snapshot (clixml).

.PARAMETER BaselineSnapshotPath
Optional path to baseline snapshot for comparison.

.PARAMETER TelemetryPath
Path to ingestion metrics JSON for eviction rate analysis.

.PARAMETER MaxSizeBytes
Maximum allowed snapshot file size in bytes. Default 50MB.

.PARAMETER MaxHostCount
Maximum allowed host count. Default 500.

.PARAMETER MaxRowCount
Maximum allowed total row count. Default 50000.

.PARAMETER MaxEvictionRatePercent
Maximum allowed eviction rate (Remove events / total operations). Default 10.

.PARAMETER AllowShrinkagePercent
Allowed shrinkage percentage vs baseline before failing. Default 5.

.PARAMETER RepositoryRoot
Repository root path. Defaults to parent of script directory.

.PARAMETER OutputPath
Optional JSON output path for the analysis report.

.PARAMETER FailOnViolation
Exit with error code if any violation is detected.

.PARAMETER PassThru
Return the analysis result as an object.
#>
param(
    [string]$CurrentSnapshotPath,
    [string]$BaselineSnapshotPath,
    [string]$TelemetryPath,
    [int64]$MaxSizeBytes = 50MB,
    [int]$MaxHostCount = 500,
    [int]$MaxRowCount = 50000,
    [double]$MaxEvictionRatePercent = 10.0,
    [double]$AllowShrinkagePercent = 5.0,
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$OutputPath,
    [switch]$FailOnViolation,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path

Write-Host "Analyzing shared cache eviction/size metrics..." -ForegroundColor Cyan

# Auto-discover current snapshot if not provided
if (-not $CurrentSnapshotPath) {
    $snapshotDir = Join-Path $repoRoot 'Logs\SharedCacheSnapshot'
    if (Test-Path -LiteralPath $snapshotDir) {
        $latest = Get-ChildItem -LiteralPath $snapshotDir -Filter 'SharedCacheSnapshot-*.clixml' -File |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latest) { $CurrentSnapshotPath = $latest.FullName }
    }
}

# Auto-discover telemetry if not provided
if (-not $TelemetryPath) {
    $metricsDir = Join-Path $repoRoot 'Logs\IngestionMetrics'
    if (Test-Path -LiteralPath $metricsDir) {
        $latest = Get-ChildItem -LiteralPath $metricsDir -Filter '*.json' -File |
            Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}\.json$' } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latest) { $TelemetryPath = $latest.FullName }
    }
}

$violations = [System.Collections.Generic.List[pscustomobject]]::new()
$metrics = [pscustomobject]@{
    CurrentSnapshot = $null
    BaselineSnapshot = $null
    Eviction = $null
    SizeCheck = $null
}

function Get-SnapshotMetrics {
    param([string]$Path)

    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $fileInfo = Get-Item -LiteralPath $Path
    $entries = Import-Clixml -LiteralPath $Path

    $siteCount = 0
    $hostCount = 0
    $rowCount = 0

    foreach ($entry in @($entries)) {
        if (-not $entry) { continue }
        $siteCount++

        $entryValue = $entry
        if ($entry.PSObject.Properties.Name -contains 'Entry') { $entryValue = $entry.Entry }

        if ($entryValue -and $entryValue.PSObject.Properties.Name -contains 'HostMap') {
            $hostMap = $entryValue.HostMap
            if ($hostMap -is [System.Collections.IDictionary]) {
                $hostCount += $hostMap.Count
                foreach ($hostKey in @($hostMap.Keys)) {
                    $ports = $hostMap[$hostKey]
                    if ($ports -is [System.Collections.ICollection]) {
                        $rowCount += $ports.Count
                    } elseif ($ports -is [System.Collections.IEnumerable] -and -not ($ports -is [string])) {
                        $rowCount += @($ports).Count
                    } else {
                        $rowCount++
                    }
                }
            }
        }
    }

    return [pscustomobject]@{
        Path      = $Path
        FileName  = $fileInfo.Name
        SizeBytes = $fileInfo.Length
        SiteCount = $siteCount
        HostCount = $hostCount
        RowCount  = $rowCount
        LastModified = $fileInfo.LastWriteTime
    }
}

# Analyze current snapshot
if ($CurrentSnapshotPath) {
    Write-Host ("  Analyzing: {0}" -f (Split-Path -Leaf $CurrentSnapshotPath)) -ForegroundColor Cyan
    $metrics.CurrentSnapshot = Get-SnapshotMetrics -Path $CurrentSnapshotPath

    if ($metrics.CurrentSnapshot) {
        # Size checks
        $sizeCheck = [pscustomobject]@{
            SizeBytes      = $metrics.CurrentSnapshot.SizeBytes
            MaxSizeBytes   = $MaxSizeBytes
            SizeOk         = $metrics.CurrentSnapshot.SizeBytes -le $MaxSizeBytes
            HostCount      = $metrics.CurrentSnapshot.HostCount
            MaxHostCount   = $MaxHostCount
            HostCountOk    = $metrics.CurrentSnapshot.HostCount -le $MaxHostCount
            RowCount       = $metrics.CurrentSnapshot.RowCount
            MaxRowCount    = $MaxRowCount
            RowCountOk     = $metrics.CurrentSnapshot.RowCount -le $MaxRowCount
        }
        $metrics.SizeCheck = $sizeCheck

        if (-not $sizeCheck.SizeOk) {
            $violations.Add([pscustomobject]@{
                Type    = 'SizeBudgetExceeded'
                Message = ("Snapshot size {0:N0} bytes exceeds max {1:N0} bytes" -f $sizeCheck.SizeBytes, $sizeCheck.MaxSizeBytes)
                Current = $sizeCheck.SizeBytes
                Limit   = $sizeCheck.MaxSizeBytes
            })
        }

        if (-not $sizeCheck.HostCountOk) {
            $violations.Add([pscustomobject]@{
                Type    = 'HostCountExceeded'
                Message = ("Host count {0} exceeds max {1}" -f $sizeCheck.HostCount, $sizeCheck.MaxHostCount)
                Current = $sizeCheck.HostCount
                Limit   = $sizeCheck.MaxHostCount
            })
        }

        if (-not $sizeCheck.RowCountOk) {
            $violations.Add([pscustomobject]@{
                Type    = 'RowCountExceeded'
                Message = ("Row count {0} exceeds max {1}" -f $sizeCheck.RowCount, $sizeCheck.MaxRowCount)
                Current = $sizeCheck.RowCount
                Limit   = $sizeCheck.MaxRowCount
            })
        }
    }
} else {
    Write-Warning "No current snapshot found"
}

# Analyze baseline comparison
if ($BaselineSnapshotPath -and (Test-Path -LiteralPath $BaselineSnapshotPath)) {
    Write-Host ("  Comparing to baseline: {0}" -f (Split-Path -Leaf $BaselineSnapshotPath)) -ForegroundColor Cyan
    $metrics.BaselineSnapshot = Get-SnapshotMetrics -Path $BaselineSnapshotPath

    if ($metrics.CurrentSnapshot -and $metrics.BaselineSnapshot) {
        $baselineHosts = $metrics.BaselineSnapshot.HostCount
        $currentHosts = $metrics.CurrentSnapshot.HostCount

        if ($baselineHosts -gt 0) {
            $shrinkagePercent = (($baselineHosts - $currentHosts) / $baselineHosts) * 100
            if ($shrinkagePercent -gt $AllowShrinkagePercent) {
                $violations.Add([pscustomobject]@{
                    Type    = 'UnexpectedShrinkage'
                    Message = ("Host count shrunk by {0:N1}% (from {1} to {2}), exceeds allowed {3}%" -f $shrinkagePercent, $baselineHosts, $currentHosts, $AllowShrinkagePercent)
                    Current = $currentHosts
                    Baseline = $baselineHosts
                    ShrinkagePercent = $shrinkagePercent
                })
            }
        }
    }
}

# Analyze eviction rate from telemetry
if ($TelemetryPath -and (Test-Path -LiteralPath $TelemetryPath)) {
    Write-Host ("  Analyzing eviction rate from: {0}" -f (Split-Path -Leaf $TelemetryPath)) -ForegroundColor Cyan

    $getHit = 0
    $getMiss = 0
    $set = 0
    $remove = 0

    Get-Content -LiteralPath $TelemetryPath | ForEach-Object {
        if ([string]::IsNullOrWhiteSpace($_)) { return }
        try {
            $event = $_ | ConvertFrom-Json -ErrorAction Stop
            if ($event.EventType -eq 'InterfaceSiteCacheMetrics') {
                if ($event.Operation -eq 'GetHit') { $getHit += if ($event.Count) { $event.Count } else { 1 } }
                elseif ($event.Operation -eq 'GetMiss') { $getMiss += if ($event.Count) { $event.Count } else { 1 } }
                elseif ($event.Operation -eq 'Set') { $set += if ($event.Count) { $event.Count } else { 1 } }
                elseif ($event.Operation -eq 'Remove') { $remove += if ($event.Count) { $event.Count } else { 1 } }
            }
        } catch { }
    }

    $totalOps = $getHit + $getMiss + $set + $remove
    $evictionRate = if ($totalOps -gt 0) { ($remove / $totalOps) * 100 } else { 0 }

    $metrics.Eviction = [pscustomobject]@{
        GetHit       = $getHit
        GetMiss      = $getMiss
        Set          = $set
        Remove       = $remove
        TotalOps     = $totalOps
        EvictionRate = [math]::Round($evictionRate, 2)
        MaxRate      = $MaxEvictionRatePercent
        RateOk       = $evictionRate -le $MaxEvictionRatePercent
    }

    if (-not $metrics.Eviction.RateOk) {
        $violations.Add([pscustomobject]@{
            Type    = 'HighEvictionRate'
            Message = ("Eviction rate {0:N2}% exceeds max {1}%" -f $evictionRate, $MaxEvictionRatePercent)
            Current = $evictionRate
            Limit   = $MaxEvictionRatePercent
        })
    }
}

# Build result
$result = [pscustomobject]@{
    Timestamp  = Get-Date -Format 'o'
    Status     = if ($violations.Count -eq 0) { 'Pass' } else { 'Fail' }
    Metrics    = $metrics
    Violations = $violations
    ViolationCount = $violations.Count
}

# Output
if ($OutputPath) {
    $outputDir = Split-Path -Path $OutputPath -Parent
    if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    $result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    Write-Host ("Report written to: {0}" -f $OutputPath) -ForegroundColor Green
}

# Display summary
Write-Host "`nEviction/Size Analysis Summary:" -ForegroundColor Cyan
if ($metrics.CurrentSnapshot) {
    Write-Host ("  Snapshot: {0}" -f $metrics.CurrentSnapshot.FileName)
    Write-Host ("  Size: {0:N0} KB / {1:N0} KB max" -f ($metrics.CurrentSnapshot.SizeBytes / 1KB), ($MaxSizeBytes / 1KB))
    Write-Host ("  Hosts: {0} / {1} max" -f $metrics.CurrentSnapshot.HostCount, $MaxHostCount)
    Write-Host ("  Rows: {0} / {1} max" -f $metrics.CurrentSnapshot.RowCount, $MaxRowCount)
}

if ($metrics.Eviction) {
    Write-Host ("  Eviction rate: {0:N2}% / {1}% max" -f $metrics.Eviction.EvictionRate, $MaxEvictionRatePercent)
}

if ($violations.Count -gt 0) {
    Write-Host ("`nViolations: {0}" -f $violations.Count) -ForegroundColor Red
    foreach ($v in $violations) {
        Write-Host ("  - [{0}] {1}" -f $v.Type, $v.Message) -ForegroundColor Red
    }
} else {
    Write-Host "`nStatus: PASS - All checks within limits" -ForegroundColor Green
}

if ($FailOnViolation -and $violations.Count -gt 0) {
    Write-Error "Eviction/size guard failed with $($violations.Count) violation(s)"
    exit 2
}

if ($PassThru) {
    return $result
}
