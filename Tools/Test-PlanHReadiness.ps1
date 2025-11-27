[CmdletBinding()]
param(
    [string]$BundlePath,
    [string]$UserActionSummaryPath,
    [string]$FreshnessSummaryPath,
    [string[]]$RequiredActions = @('ScanLogs','LoadFromDb','HelpQuickstart','InterfacesView','CompareView','SpanSnapshot'),
    [switch]$PassThru
)

<#
.SYNOPSIS
Validates Plan H readiness for a telemetry bundle.

.DESCRIPTION
Checks that a telemetry bundle contains UserAction coverage (all required actions present)
and a freshness telemetry summary (cache provider/source per site). Reads the manifest in
`TelemetryBundle.json` when -BundlePath is supplied, or attempts to auto-discover the latest
bundle under Logs/TelemetryBundles when paths are omitted.

.EXAMPLE
pwsh -NoLogo -File Tools\Test-PlanHReadiness.ps1 -BundlePath Logs\TelemetryBundles\UI-20251126-useraction8
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-LatestBundlePath {
    $root = Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'Logs\TelemetryBundles'
    if (-not (Test-Path -LiteralPath $root)) { return $null }
    return Get-ChildItem -LiteralPath $root -Directory |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 |
        ForEach-Object { $_.FullName }
}

if (-not $BundlePath -and -not $UserActionSummaryPath -and -not $FreshnessSummaryPath) {
    $BundlePath = Get-LatestBundlePath
}

$manifest = $null
    if ($BundlePath) {
        $resolved = Resolve-Path -LiteralPath $BundlePath -ErrorAction Stop
        $bundleDir = $resolved.ProviderPath
        $manifestPath = Join-Path $bundleDir 'TelemetryBundle.json'
        if (-not (Test-Path -LiteralPath $manifestPath)) {
            # Manifest might be inside an area subfolder
            $areaManifest = Get-ChildItem -LiteralPath $bundleDir -Filter 'TelemetryBundle.json' -Recurse -File | Select-Object -First 1
            if ($areaManifest) { $manifestPath = $areaManifest.FullName }
        }
        if (Test-Path -LiteralPath $manifestPath) {
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            Write-Verbose ("Using manifest: {0}" -f $manifestPath)
        } else {
            Write-Warning "TelemetryBundle.json not found under $bundleDir"
        }
        if (-not $UserActionSummaryPath -and $manifest) {
            $ua = $manifest.Artifacts | Where-Object { $_.Category -eq 'UserActionSummary' } | Select-Object -First 1
            if ($ua) { $UserActionSummaryPath = Join-Path (Split-Path $manifestPath -Parent) $ua.TargetFile }
        }
        if (-not $FreshnessSummaryPath -and $manifest) {
            $fr = $manifest.Artifacts | Where-Object { $_.Category -eq 'FreshnessSummary' } | Select-Object -First 1
            if (-not $fr) {
                $fr = $manifest.Artifacts | Where-Object { $_.TargetFile -like 'FreshnessTelemetrySummary*' } | Select-Object -First 1
            }
            if ($fr) { $FreshnessSummaryPath = Join-Path (Split-Path $manifestPath -Parent) $fr.TargetFile }
        }
    }

$failures = New-Object 'System.Collections.Generic.List[string]'

$userActionCoverage = $null
if ($UserActionSummaryPath) {
    if (-not (Test-Path -LiteralPath $UserActionSummaryPath)) {
        $failures.Add("UserAction summary not found: $UserActionSummaryPath") | Out-Null
    } else {
        $uaObj = Get-Content -LiteralPath $UserActionSummaryPath -Raw | ConvertFrom-Json -ErrorAction Stop
        if ($uaObj.RequiredCoverage) {
            if (-not $uaObj.RequiredCoverage.AllActionsPresent) {
                $missing = $uaObj.RequiredCoverage.MissingActions -join ','
                $failures.Add("UserAction coverage incomplete (missing: $missing)") | Out-Null
            }
        } else {
            # Recompute coverage
            $present = @($uaObj.Actions | ForEach-Object { $_.Action })
            $missing = @($RequiredActions | Where-Object { $present -notcontains $_ })
            if ($missing.Count -gt 0) {
                $failures.Add("UserAction coverage missing: $($missing -join ',')") | Out-Null
            }
        }
        $userActionCoverage = $uaObj
    }
} else {
    $failures.Add('UserAction summary path not resolved.') | Out-Null
}

$freshnessCoverage = $null
if ($FreshnessSummaryPath) {
    if (-not (Test-Path -LiteralPath $FreshnessSummaryPath)) {
        $failures.Add("Freshness summary not found: $FreshnessSummaryPath") | Out-Null
    } else {
        $frObj = Get-Content -LiteralPath $FreshnessSummaryPath -Raw | ConvertFrom-Json -ErrorAction Stop
        $freshnessCoverage = $frObj
        if (-not $frObj.Sites -or $frObj.Sites.Count -eq 0) {
            $failures.Add('Freshness summary has no site entries.') | Out-Null
        }
    }
} else {
    $failures.Add('Freshness summary path not resolved.') | Out-Null
}

$isReady = ($failures.Count -eq 0)
if ($isReady) {
    Write-Host "[PlanH] Ready: UserAction + freshness evidence present." -ForegroundColor Green
} else {
    Write-Warning "[PlanH] Not ready:"
    foreach ($f in $failures) { Write-Warning (" - {0}" -f $f) }
}

$result = [pscustomobject]@{
    Ready                 = $isReady
    BundlePath            = $BundlePath
    UserActionSummaryPath = $UserActionSummaryPath
    FreshnessSummaryPath  = $FreshnessSummaryPath
    Failures              = $failures
}

if ($PassThru) { return $result }
