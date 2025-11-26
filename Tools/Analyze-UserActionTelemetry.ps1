[CmdletBinding()]
param(
    [string]$Path,
    [string]$OutputPath
)

<#
.SYNOPSIS
Summarizes UserAction telemetry (Plan H adoption signals).

.DESCRIPTION
Reads a telemetry JSON file (default: latest under Logs\IngestionMetrics) and
outputs counts by Action and Site for UserAction events emitted by the UI
(ScanLogs, LoadFromDb, HelpQuickstart, InterfacesView, CompareView, SpanSnapshot, etc.).

.EXAMPLE
pwsh -NoLogo -File Tools\Analyze-UserActionTelemetry.ps1 -Path Logs\IngestionMetrics\2025-11-27.json -OutputPath Logs\Reports\UserActionSummary-20251127.json
#>

Set-StrictMode -Version Latest

function Get-LatestTelemetryPath {
    $dir = Join-Path (Resolve-Path '.').Path 'Logs\IngestionMetrics'
    if (-not (Test-Path -LiteralPath $dir)) { return $null }
    return Get-ChildItem -LiteralPath $dir -Filter '*.json' -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | ForEach-Object { $_.FullName }
}

if (-not $Path) {
    $Path = Get-LatestTelemetryPath
}

if (-not $Path) {
    throw "No telemetry file found. Provide -Path or ensure Logs\IngestionMetrics exists."
}

if (-not (Test-Path -LiteralPath $Path)) {
    throw "Telemetry file not found: $Path"
}

$raw = Get-Content -LiteralPath $Path -Raw
$events = $null
try { $events = $raw | ConvertFrom-Json -ErrorAction Stop } catch { throw "Failed to parse telemetry at $Path: $($_.Exception.Message)" }

$userActions = @($events | Where-Object { $_.EventName -eq 'UserAction' })

$actionGroups = $userActions | Group-Object Action | Sort-Object Count -Descending | ForEach-Object {
    [pscustomobject]@{
        Action = $_.Name
        Count  = $_.Count
    }
}

$siteGroups = $userActions | Group-Object Site | Sort-Object Count -Descending | ForEach-Object {
    [pscustomobject]@{
        Site  = $_.Name
        Count = $_.Count
    }
}

$summary = [pscustomobject]@{
    SourcePath   = (Resolve-Path -LiteralPath $Path).ProviderPath
    TotalEvents  = $userActions.Count
    Actions      = $actionGroups
    Sites        = $siteGroups
}

Write-Host ("[UserAction] Source: {0}" -f $summary.SourcePath) -ForegroundColor Cyan
Write-Host ("[UserAction] Total events: {0}" -f $summary.TotalEvents)
if ($actionGroups) {
    Write-Host "[UserAction] By action:"
    foreach ($a in $actionGroups) { Write-Host ("  {0}: {1}" -f $a.Action, $a.Count) }
}
if ($siteGroups) {
    Write-Host "[UserAction] By site:"
    foreach ($s in $siteGroups) { Write-Host ("  {0}: {1}" -f $s.Site, $s.Count) }
}

if ($OutputPath) {
    $dir = Split-Path -Path $OutputPath -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding utf8
    $resolved = Resolve-Path -LiteralPath $OutputPath -ErrorAction SilentlyContinue
    $display = if ($resolved) { $resolved.ProviderPath } else { $OutputPath }
    Write-Host ("[UserAction] Summary written to {0}" -f $display) -ForegroundColor Green
}
