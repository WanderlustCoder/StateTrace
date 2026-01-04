<#
.SYNOPSIS
Measures UI responsiveness for key actions and emits telemetry.

.DESCRIPTION
ST-O-003: Instruments UI actions (tab switches, search/filter apply, Compare diff load)
to emit duration metrics. Provides thresholds for smoke test integration.

.PARAMETER Action
The UI action to measure. Valid values: TabSwitch, SearchApply, FilterApply, CompareDiffLoad, SpanRefresh, TemplateLoad.

.PARAMETER ActionScript
Script block to execute and measure.

.PARAMETER TargetLatencyMs
Maximum acceptable latency in milliseconds. Default varies by action type.

.PARAMETER OutputPath
Optional path to write JSON results.

.PARAMETER RepositoryRoot
Repository root path. Defaults to parent of script directory.

.PARAMETER PassThru
Return result object.

.EXAMPLE
.\Measure-UiResponsiveness.ps1 -Action TabSwitch -ActionScript { Set-ActiveTab 'Interfaces' } -PassThru

.EXAMPLE
.\Measure-UiResponsiveness.ps1 -Action SearchApply -ActionScript { Invoke-SearchFilter -Pattern 'trunk' }
#>
param(
    [Parameter(Mandatory)]
    [ValidateSet('TabSwitch', 'SearchApply', 'FilterApply', 'CompareDiffLoad', 'SpanRefresh', 'TemplateLoad', 'InterfacesLoad', 'AlertsRefresh', 'Custom')]
    [string]$Action,

    [Parameter(Mandatory)]
    [scriptblock]$ActionScript,

    [double]$TargetLatencyMs,

    [string]$OutputPath,

    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,

    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Default thresholds per action type
$defaultThresholds = @{
    TabSwitch       = 200.0
    SearchApply     = 500.0
    FilterApply     = 300.0
    CompareDiffLoad = 1000.0
    SpanRefresh     = 800.0
    TemplateLoad    = 300.0
    InterfacesLoad  = 2000.0
    AlertsRefresh   = 500.0
    Custom          = 1000.0
}

if (-not $TargetLatencyMs) {
    $TargetLatencyMs = $defaultThresholds[$Action]
}

Write-Host "Measuring UI responsiveness: $Action" -ForegroundColor Cyan
Write-Host ("  Target latency: {0:N0} ms" -f $TargetLatencyMs) -ForegroundColor Cyan

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$startTime = Get-Date

# Execute the action with timing
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$error.Clear()
$actionError = $null
$actionOutput = $null

try {
    $actionOutput = & $ActionScript
}
catch {
    $actionError = $_.Exception.Message
}

$stopwatch.Stop()
$durationMs = $stopwatch.Elapsed.TotalMilliseconds

# Determine status
$status = 'Pass'
if ($actionError) {
    $status = 'Error'
}
elseif ($durationMs -gt $TargetLatencyMs) {
    $status = 'Slow'
}

# Build result
$result = [pscustomobject]@{
    Timestamp        = Get-Date -Format 'o'
    Action           = $Action
    DurationMs       = [math]::Round($durationMs, 2)
    TargetLatencyMs  = $TargetLatencyMs
    Status           = $status
    ExceededBy       = if ($durationMs -gt $TargetLatencyMs) { [math]::Round($durationMs - $TargetLatencyMs, 2) } else { 0 }
    PercentOfTarget  = [math]::Round(($durationMs / $TargetLatencyMs) * 100, 1)
    Error            = $actionError
}

# Display result
$statusColor = switch ($status) {
    'Pass'  { 'Green' }
    'Slow'  { 'Yellow' }
    'Error' { 'Red' }
}

Write-Host "`nResult:" -ForegroundColor Cyan
Write-Host ("  Duration: {0:N2} ms" -f $result.DurationMs) -ForegroundColor $statusColor
Write-Host ("  Status: {0}" -f $result.Status) -ForegroundColor $statusColor
if ($result.Status -eq 'Slow') {
    Write-Host ("  Exceeded target by: {0:N2} ms ({1:N1}% of target)" -f $result.ExceededBy, $result.PercentOfTarget) -ForegroundColor Yellow
}
if ($result.Error) {
    Write-Host ("  Error: {0}" -f $result.Error) -ForegroundColor Red
}

# Output to file if requested
if ($OutputPath) {
    $outputDir = Split-Path -Path $OutputPath -Parent
    if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    $result | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    Write-Host ("`nResults written to: {0}" -f $OutputPath) -ForegroundColor Green
}

if ($PassThru) {
    return $result
}
