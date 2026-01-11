[CmdletBinding()]
param(
    [string]$VerificationDirectory,
    [string]$WarmRunSummaryPath,
    [string]$SharedCacheDirectory,
    [string]$TelemetryBundlePath,
    [string]$RollupCsvPath,
    [string]$OutputPath,
    [switch]$PassThru,
    [switch]$IncludeGateDetails
)

<#
.SYNOPSIS
Displays a consolidated release readiness dashboard combining verification, warm-run, cache, and telemetry gate metrics.

.DESCRIPTION
ST-G-005: Combines metrics from rollups + verification runs into a readiness view showing:
- Warm-run improvement percentage and cache-hit ratio
- Shared cache coverage (sites, hosts, rows)
- Telemetry gate status (from gate enforcement tests)
- Verification summary status
- Telemetry bundle readiness

Use this script before release sign-off to get a consolidated view of all readiness indicators.

.PARAMETER VerificationDirectory
Directory containing verification summaries (defaults to Logs/Verification).

.PARAMETER WarmRunSummaryPath
Path to WarmRunTelemetry-*-summary.json (defaults to latest).

.PARAMETER SharedCacheDirectory
Directory containing shared cache snapshots (defaults to Logs/SharedCacheSnapshot).

.PARAMETER TelemetryBundlePath
Optional path to a telemetry bundle to check for readiness.

.PARAMETER RollupCsvPath
Optional path to rollup CSV for gate evaluation.

.PARAMETER OutputPath
If specified, writes the dashboard to a JSON file.

.PARAMETER PassThru
Returns the dashboard data as an object.

.PARAMETER IncludeGateDetails
Include detailed gate status per threshold.

.EXAMPLE
pwsh Tools\Show-ReleaseReadiness.ps1

.EXAMPLE
pwsh Tools\Show-ReleaseReadiness.ps1 -TelemetryBundlePath Logs\TelemetryBundles\Release-2026-01-04 -PassThru
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent

$toolingJsonPath = Join-Path -Path $PSScriptRoot -ChildPath 'ToolingJson.psm1'
if (Test-Path -LiteralPath $toolingJsonPath) {
    Import-Module -Name $toolingJsonPath -Force
}

# Resolve default paths
if ([string]::IsNullOrWhiteSpace($VerificationDirectory)) {
    $VerificationDirectory = Join-Path -Path $repositoryRoot -ChildPath 'Logs\Verification'
}

if ([string]::IsNullOrWhiteSpace($SharedCacheDirectory)) {
    $SharedCacheDirectory = Join-Path -Path $repositoryRoot -ChildPath 'Logs\SharedCacheSnapshot'
}

if ([string]::IsNullOrWhiteSpace($WarmRunSummaryPath)) {
    $metricsDir = Join-Path -Path $repositoryRoot -ChildPath 'Logs\IngestionMetrics'
    $latestWarmRun = Join-Path -Path $metricsDir -ChildPath 'WarmRunTelemetry-latest-summary.json'
    if (Test-Path -LiteralPath $latestWarmRun) {
        $WarmRunSummaryPath = $latestWarmRun
    }
}

# Initialize dashboard object
$dashboard = [pscustomobject]@{
    GeneratedAtUtc           = (Get-Date).ToUniversalTime().ToString('o')
    OverallStatus            = 'Unknown'
    WarmRunStatus            = [pscustomobject]@{
        Available            = $false
        ImprovementPercent   = $null
        CacheHitRatioPercent = $null
        MeetsThreshold       = $false
        Message              = ''
    }
    SharedCacheStatus        = [pscustomobject]@{
        Available            = $false
        SiteCount            = 0
        HostCount            = 0
        TotalRows            = 0
        MeetsThreshold       = $false
        Message              = ''
    }
    VerificationStatus       = [pscustomobject]@{
        Available            = $false
        LatestTimestamp      = $null
        Status               = 'Unknown'
        ErrorMessage         = $null
    }
    TelemetryBundleStatus    = [pscustomobject]@{
        Available            = $false
        BundlePath           = $null
        ReadinessChecked     = $false
        Message              = ''
    }
    GateStatus               = [pscustomobject]@{
        Evaluated            = $false
        AllPassed            = $false
        Gates                = @()
    }
    Recommendations          = @()
}

# Gate thresholds from docs/telemetry/Automation_Gates.md
$gateThresholds = @{
    WarmRunImprovementMin       = 60    # percent
    WarmRunCacheHitRatioMin     = 99    # percent
    SharedCacheMinSites         = 2
    SharedCacheMinHosts         = 37
    SharedCacheMinRows          = 1200
}

Write-Host "`n=== StateTrace Release Readiness Dashboard ===" -ForegroundColor Cyan
Write-Host ("Generated: {0}" -f $dashboard.GeneratedAtUtc) -ForegroundColor DarkGray
Write-Host ""

# 1. Warm-Run Status
Write-Host "--- Warm-Run Performance ---" -ForegroundColor Yellow
if ($WarmRunSummaryPath -and (Test-Path -LiteralPath $WarmRunSummaryPath)) {
    try {
        $warmRunData = Get-Content -Raw -LiteralPath $WarmRunSummaryPath | ConvertFrom-Json
        $dashboard.WarmRunStatus.Available = $true
        $dashboard.WarmRunStatus.ImprovementPercent = $warmRunData.ImprovementPercent
        $dashboard.WarmRunStatus.CacheHitRatioPercent = $warmRunData.WarmCacheHitRatioPercent

        $improvementPass = $warmRunData.ImprovementPercent -ge $gateThresholds.WarmRunImprovementMin
        $cacheHitPass = $warmRunData.WarmCacheHitRatioPercent -ge $gateThresholds.WarmRunCacheHitRatioMin
        $dashboard.WarmRunStatus.MeetsThreshold = $improvementPass -and $cacheHitPass

        $improvementColor = if ($improvementPass) { 'Green' } else { 'Red' }
        $cacheHitColor = if ($cacheHitPass) { 'Green' } else { 'Red' }

        Write-Host ("  Improvement: {0:N1}% (threshold: >= {1}%)" -f $warmRunData.ImprovementPercent, $gateThresholds.WarmRunImprovementMin) -ForegroundColor $improvementColor
        Write-Host ("  Cache Hit Ratio: {0:N1}% (threshold: >= {1}%)" -f $warmRunData.WarmCacheHitRatioPercent, $gateThresholds.WarmRunCacheHitRatioMin) -ForegroundColor $cacheHitColor
        $cacheCount = if ($warmRunData.WarmProviderCounts.PSObject.Properties['Cache']) { $warmRunData.WarmProviderCounts.Cache } else { 0 }
        $sharedCacheCount = if ($warmRunData.WarmProviderCounts.PSObject.Properties['SharedCache']) { $warmRunData.WarmProviderCounts.SharedCache } else { 0 }
        Write-Host ("  Provider Counts: Cache={0}, SharedCache={1}" -f $cacheCount, $sharedCacheCount) -ForegroundColor DarkGray

        if (-not $improvementPass) {
            $dashboard.Recommendations += "Warm-run improvement ({0:N1}%) below threshold ({1}%)" -f $warmRunData.ImprovementPercent, $gateThresholds.WarmRunImprovementMin
        }
        if (-not $cacheHitPass) {
            $dashboard.Recommendations += "Cache hit ratio ({0:N1}%) below threshold ({1}%)" -f $warmRunData.WarmCacheHitRatioPercent, $gateThresholds.WarmRunCacheHitRatioMin
        }

        $dashboard.WarmRunStatus.Message = if ($dashboard.WarmRunStatus.MeetsThreshold) { 'Pass' } else { 'Fail' }
    } catch {
        $dashboard.WarmRunStatus.Message = "Error reading warm-run summary: $($_.Exception.Message)"
        Write-Host "  Error: $($dashboard.WarmRunStatus.Message)" -ForegroundColor Red
    }
} else {
    $dashboard.WarmRunStatus.Message = 'No warm-run summary available'
    Write-Host "  No warm-run summary found" -ForegroundColor DarkGray
    $dashboard.Recommendations += "Run warm-run regression to generate performance baseline"
}
Write-Host ""

# 2. Shared Cache Status
Write-Host "--- Shared Cache Coverage ---" -ForegroundColor Yellow
if ($SharedCacheDirectory -and (Test-Path -LiteralPath $SharedCacheDirectory)) {
    try {
        $summaryPath = Join-Path -Path $SharedCacheDirectory -ChildPath 'SharedCacheSnapshot-latest-summary.json'
        if (-not (Test-Path -LiteralPath $summaryPath)) {
            $summaryPath = Get-ChildItem -Path $SharedCacheDirectory -Filter '*-summary.json' -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1 |
                ForEach-Object { $_.FullName }
        }

        $siteCount = 0
        $hostCount = 0
        $totalRows = 0

        if ($summaryPath) {
            try {
                $data = Get-Content -Raw -LiteralPath $summaryPath | ConvertFrom-Json
                $entries = if ($null -eq $data) { @() } elseif ($data -is [System.Array]) { $data } else { @($data) }
                foreach ($entry in $entries) {
                    if ($entry.Site) {
                        $siteCount++
                        $hostValue = 0
                        if ($entry.PSObject.Properties['Hosts'] -and $null -ne $entry.Hosts) {
                            $hostValue = [int]$entry.Hosts
                        }
                        $totalRowsValue = 0
                        if ($entry.PSObject.Properties['TotalRows'] -and $null -ne $entry.TotalRows) {
                            $totalRowsValue = [int]$entry.TotalRows
                        }
                        $hostCount += $hostValue
                        $totalRows += $totalRowsValue
                    }
                }
            } catch {
                # Skip malformed summary data
            }
        }

        $dashboard.SharedCacheStatus.Available = $siteCount -gt 0
        $dashboard.SharedCacheStatus.SiteCount = $siteCount
        $dashboard.SharedCacheStatus.HostCount = $hostCount
        $dashboard.SharedCacheStatus.TotalRows = $totalRows

        $sitesPass = $siteCount -ge $gateThresholds.SharedCacheMinSites
        $hostsPass = $hostCount -ge $gateThresholds.SharedCacheMinHosts
        $rowsPass = $totalRows -ge $gateThresholds.SharedCacheMinRows
        $dashboard.SharedCacheStatus.MeetsThreshold = $sitesPass -and $hostsPass -and $rowsPass

        $sitesColor = if ($sitesPass) { 'Green' } else { 'Red' }
        $hostsColor = if ($hostsPass) { 'Green' } else { 'Red' }
        $rowsColor = if ($rowsPass) { 'Green' } else { 'Red' }

        Write-Host ("  Sites: {0} (threshold: >= {1})" -f $siteCount, $gateThresholds.SharedCacheMinSites) -ForegroundColor $sitesColor
        Write-Host ("  Hosts: {0} (threshold: >= {1})" -f $hostCount, $gateThresholds.SharedCacheMinHosts) -ForegroundColor $hostsColor
        Write-Host ("  Total Rows: {0} (threshold: >= {1})" -f $totalRows, $gateThresholds.SharedCacheMinRows) -ForegroundColor $rowsColor

        if (-not $sitesPass) { $dashboard.Recommendations += "Shared cache site count ({0}) below threshold ({1})" -f $siteCount, $gateThresholds.SharedCacheMinSites }
        if (-not $hostsPass) { $dashboard.Recommendations += "Shared cache host count ({0}) below threshold ({1})" -f $hostCount, $gateThresholds.SharedCacheMinHosts }
        if (-not $rowsPass) { $dashboard.Recommendations += "Shared cache row count ({0}) below threshold ({1})" -f $totalRows, $gateThresholds.SharedCacheMinRows }

        $dashboard.SharedCacheStatus.Message = if ($dashboard.SharedCacheStatus.MeetsThreshold) { 'Pass' } else { 'Fail' }
    } catch {
        $dashboard.SharedCacheStatus.Message = "Error reading shared cache: $($_.Exception.Message)"
        Write-Host "  Error: $($dashboard.SharedCacheStatus.Message)" -ForegroundColor Red
    }
} else {
    $dashboard.SharedCacheStatus.Message = 'No shared cache directory found'
    Write-Host "  No shared cache snapshots found" -ForegroundColor DarkGray
    $dashboard.Recommendations += "Run shared cache warmup to populate cache snapshots"
}
Write-Host ""

# 3. Verification Status
Write-Host "--- Verification Status ---" -ForegroundColor Yellow
if ($VerificationDirectory -and (Test-Path -LiteralPath $VerificationDirectory)) {
    try {
        $latestSummary = Join-Path -Path $VerificationDirectory -ChildPath 'VerificationSummary-latest.json'
        if (Test-Path -LiteralPath $latestSummary) {
            $verificationData = Get-Content -Raw -LiteralPath $latestSummary | ConvertFrom-Json
            $dashboard.VerificationStatus.Available = $true
            $dashboard.VerificationStatus.LatestTimestamp = $verificationData.Timestamp
            $dashboard.VerificationStatus.Status = $verificationData.Status

            $statusColor = if ($verificationData.Status -eq 'Pass') { 'Green' } else { 'Red' }
            Write-Host ("  Latest Run: {0}" -f $verificationData.Timestamp) -ForegroundColor DarkGray
            Write-Host ("  Status: {0}" -f $verificationData.Status) -ForegroundColor $statusColor

            if ($verificationData.Status -ne 'Pass' -and $verificationData.ErrorMessage) {
                $errorPreview = $verificationData.ErrorMessage
                if ($errorPreview.Length -gt 100) {
                    $errorPreview = $errorPreview.Substring(0, 100) + '...'
                }
                $dashboard.VerificationStatus.ErrorMessage = $verificationData.ErrorMessage
                Write-Host ("  Error: {0}" -f $errorPreview) -ForegroundColor Red
                $dashboard.Recommendations += "Fix verification failures before release"
            }
        } else {
            $dashboard.VerificationStatus.Status = 'No summary found'
            Write-Host "  No verification summary found" -ForegroundColor DarkGray
            $dashboard.Recommendations += "Run verification harness to generate status"
        }
    } catch {
        $dashboard.VerificationStatus.Status = "Error: $($_.Exception.Message)"
        Write-Host "  Error reading verification status" -ForegroundColor Red
    }
} else {
    $dashboard.VerificationStatus.Status = 'Directory not found'
    Write-Host "  Verification directory not found" -ForegroundColor DarkGray
}
Write-Host ""

# 4. Telemetry Bundle Status
Write-Host "--- Telemetry Bundle ---" -ForegroundColor Yellow
if (-not [string]::IsNullOrWhiteSpace($TelemetryBundlePath)) {
    if (Test-Path -LiteralPath $TelemetryBundlePath) {
        $dashboard.TelemetryBundleStatus.Available = $true
        $dashboard.TelemetryBundleStatus.BundlePath = $TelemetryBundlePath

        $verificationSummaryPath = Join-Path -Path $TelemetryBundlePath -ChildPath 'VerificationSummary.json'
        if (Test-Path -LiteralPath $verificationSummaryPath) {
            $dashboard.TelemetryBundleStatus.ReadinessChecked = $true
            $dashboard.TelemetryBundleStatus.Message = 'Bundle verified'
            Write-Host ("  Bundle Path: {0}" -f $TelemetryBundlePath) -ForegroundColor DarkGray
            Write-Host "  Readiness: Verified" -ForegroundColor Green
        } else {
            $dashboard.TelemetryBundleStatus.Message = 'Bundle exists but not verified'
            Write-Host ("  Bundle Path: {0}" -f $TelemetryBundlePath) -ForegroundColor DarkGray
            Write-Host "  Readiness: Not verified" -ForegroundColor Yellow
            $dashboard.Recommendations += "Run Test-TelemetryBundleReadiness.ps1 on the bundle"
        }
    } else {
        $dashboard.TelemetryBundleStatus.Message = 'Bundle path not found'
        Write-Host "  Bundle path not found: $TelemetryBundlePath" -ForegroundColor Red
    }
} else {
    $dashboard.TelemetryBundleStatus.Message = 'No bundle specified'
    Write-Host "  No telemetry bundle specified (use -TelemetryBundlePath)" -ForegroundColor DarkGray
}
Write-Host ""

# 5. Calculate Overall Status
$passCount = 0
$totalChecks = 0

if ($dashboard.WarmRunStatus.Available) {
    $totalChecks++
    if ($dashboard.WarmRunStatus.MeetsThreshold) { $passCount++ }
}

if ($dashboard.SharedCacheStatus.Available) {
    $totalChecks++
    if ($dashboard.SharedCacheStatus.MeetsThreshold) { $passCount++ }
}

if ($dashboard.VerificationStatus.Available) {
    $totalChecks++
    if ($dashboard.VerificationStatus.Status -eq 'Pass') { $passCount++ }
}

if ($dashboard.TelemetryBundleStatus.Available) {
    $totalChecks++
    if ($dashboard.TelemetryBundleStatus.ReadinessChecked) { $passCount++ }
}

if ($totalChecks -eq 0) {
    $dashboard.OverallStatus = 'No Data'
} elseif ($passCount -eq $totalChecks) {
    $dashboard.OverallStatus = 'Ready'
} elseif ($passCount -gt 0) {
    $dashboard.OverallStatus = 'Partial'
} else {
    $dashboard.OverallStatus = 'Not Ready'
}

# Summary
Write-Host "=== Summary ===" -ForegroundColor Cyan
$overallColor = switch ($dashboard.OverallStatus) {
    'Ready' { 'Green' }
    'Partial' { 'Yellow' }
    'Not Ready' { 'Red' }
    default { 'DarkGray' }
}
Write-Host ("Overall Status: {0} ({1}/{2} checks passed)" -f $dashboard.OverallStatus, $passCount, $totalChecks) -ForegroundColor $overallColor

if ($dashboard.Recommendations.Count -gt 0) {
    Write-Host "`nRecommendations:" -ForegroundColor Yellow
    foreach ($rec in $dashboard.Recommendations) {
        Write-Host "  - $rec" -ForegroundColor DarkYellow
    }
}
Write-Host ""

# Output
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    try {
        $outputDir = Split-Path -Path $OutputPath -Parent
        if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }
        $dashboard | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding utf8
        Write-Host "Dashboard saved to: $OutputPath" -ForegroundColor DarkCyan
    } catch {
        Write-Warning "Failed to save dashboard: $($_.Exception.Message)"
    }
}

if ($PassThru.IsPresent) {
    return $dashboard
}
