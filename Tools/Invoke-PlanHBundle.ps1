[CmdletBinding()]
param(
    [string]$BundleName = ("UI-{0}-planh" -f (Get-Date -Format 'yyyyMMdd')),
    [string]$TelemetryPath,
    [string]$UserActionSummaryPath,
    [string]$FreshnessSummaryPath,
    [string[]]$AdditionalPath,
    [string]$QuickstartSummaryPath = 'Logs\Reports\InterfacesViewQuickstart-20251126-143359.json',
    [string]$ChecklistPath = 'Logs\Reports\InterfacesViewChecklist-20251126-143359.json',
    [switch]$Force,
    [switch]$PassThru
)

<#
.SYNOPSIS
Builds a Plan H-ready UI bundle with readiness enforcement.

.DESCRIPTION
Finds (or generates) UserAction and freshness summaries, then calls
Tools\Publish-TelemetryBundle.ps1 with -VerifyPlanHReadiness so the bundle contains
UserAction coverage + FreshnessTelemetrySummary and emits PlanHReadiness.json.

.EXAMPLE
pwsh -NoLogo -File Tools\Invoke-PlanHBundle.ps1 -TelemetryPath Logs\IngestionMetrics\2025-11-26.json
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-LatestTelemetry {
    $dir = Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'Logs\IngestionMetrics'
    if (-not (Test-Path -LiteralPath $dir)) { return $null }
    return Get-ChildItem -LiteralPath $dir -Filter '*.json' -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 |
        ForEach-Object { $_.FullName }
}

$resolvedTelemetry = $TelemetryPath
if (-not $resolvedTelemetry) {
    $resolvedTelemetry = Get-LatestTelemetry
}
if (-not $resolvedTelemetry -or -not (Test-Path -LiteralPath $resolvedTelemetry)) {
    throw "Telemetry file not found. Provide -TelemetryPath or ensure Logs\IngestionMetrics exists."
}
$telemetryFull = (Resolve-Path -LiteralPath $resolvedTelemetry).ProviderPath
$telemetryStem = [System.IO.Path]::GetFileNameWithoutExtension($telemetryFull)
$reportsDir = Join-Path (Split-Path -Path $telemetryFull -Parent) '..\Reports'
if (-not (Test-Path -LiteralPath $reportsDir)) { New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null }
$reportsDir = (Resolve-Path -LiteralPath $reportsDir).ProviderPath

# Generate UserAction summary if missing
if (-not $UserActionSummaryPath) {
    $UserActionSummaryPath = Join-Path $reportsDir "UserActionSummary-$telemetryStem-planh.json"
    & (Join-Path $PSScriptRoot 'Analyze-UserActionTelemetry.ps1') -Path $telemetryFull -OutputPath $UserActionSummaryPath | Out-Null
}

# Generate freshness summary if missing
if (-not $FreshnessSummaryPath) {
    $FreshnessSummaryPath = Join-Path $reportsDir "FreshnessTelemetrySummary-$telemetryStem-planh.json"
    & (Join-Path $PSScriptRoot 'Analyze-FreshnessTelemetry.ps1') -Path $telemetryFull -OutputPath $FreshnessSummaryPath | Out-Null
}

$resolvedAdditional = @()
if ($ChecklistPath -and (Test-Path -LiteralPath $ChecklistPath)) { $resolvedAdditional += (Resolve-Path -LiteralPath $ChecklistPath).ProviderPath }
if ($QuickstartSummaryPath -and (Test-Path -LiteralPath $QuickstartSummaryPath)) { $resolvedAdditional += (Resolve-Path -LiteralPath $QuickstartSummaryPath).ProviderPath }
if ($AdditionalPath) { $resolvedAdditional += $AdditionalPath }

$publishScript = Join-Path $PSScriptRoot 'Publish-TelemetryBundle.ps1'
$publishParams = @{}
$publishParams.BundleName = $BundleName
$publishParams.AreaName = 'UI'
$publishParams.ColdTelemetryPath = $telemetryFull
$publishParams.UserActionSummaryPath = $UserActionSummaryPath
$publishParams.FreshnessSummaryPath = $FreshnessSummaryPath
if ($resolvedAdditional.Count -gt 0) { $publishParams.AdditionalPath = $resolvedAdditional }
$publishParams.PlanReferences = 'docs/plans/PlanH_UserExperience.md'
$publishParams.TaskBoardIds = @('ST-H-001','ST-H-003')
$publishParams.Notes = 'Plan H UI evidence (auto-generated summaries)'
$publishParams.VerifyPlanHReadiness = $true
if ($Force) { $publishParams.Force = $true }
if ($PassThru) { $publishParams.PassThru = $true }

$result = & $publishScript @publishParams
$bundleDir = if ($result -and $result.Path) { $result.Path } else { Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'Logs\TelemetryBundles') $BundleName }

if ($PassThru) { return $result }
Write-Host ("Plan H bundle ready: {0}" -f $bundleDir) -ForegroundColor Green
