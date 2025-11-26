[CmdletBinding()]
param(
    [string]$Path,
    [string]$OutputPath
)

<#
.SYNOPSIS
Summarizes cache/freshness source telemetry per site.

.DESCRIPTION
Reads an ingestion metrics JSON file (newline-delimited JSON allowed) and
summarizes cache provider/source signals emitted by InterfaceSiteCache*
events (e.g., InterfaceSiteCacheMetrics, InterfaceSiteCacheRunspaceState,
InterfaceSyncTiming with CacheStatus).

.EXAMPLE
pwsh -NoLogo -File Tools\Analyze-FreshnessTelemetry.ps1 `
  -Path Logs\IngestionMetrics\2025-11-26.json `
  -OutputPath Logs\Reports\FreshnessTelemetrySummary-20251126.json
#>

Set-StrictMode -Version Latest

function Get-LatestTelemetryPath {
    $dir = Join-Path (Resolve-Path '.').Path 'Logs\IngestionMetrics'
    if (-not (Test-Path -LiteralPath $dir)) { return $null }
    return Get-ChildItem -LiteralPath $dir -Filter '*.json' -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 |
        ForEach-Object { $_.FullName }
}

if (-not $Path) { $Path = Get-LatestTelemetryPath }
if (-not $Path) { throw "No telemetry file found. Provide -Path or ensure Logs\IngestionMetrics exists." }
if (-not (Test-Path -LiteralPath $Path)) { throw "Telemetry file not found: $Path" }

$events = $null
try {
    $events = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -ErrorAction Stop
} catch {
    $lines = Get-Content -LiteralPath $Path -ErrorAction Stop
    $parsed = @()
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $parsed += ($line | ConvertFrom-Json -ErrorAction Stop) } catch { }
    }
    if ($parsed.Count -eq 0) { throw "Failed to parse telemetry at ${Path}" }
    $events = $parsed
}

$targetEvents = @($events | Where-Object {
        $_.EventName -in @('InterfaceSiteCacheMetrics','InterfaceSiteCacheRunspaceState','InterfaceSyncTiming','DatabaseWriteBreakdown')
    })

$siteSummary = @{}
foreach ($evt in $targetEvents) {
    $site = '' + $evt.Site
    if ([string]::IsNullOrWhiteSpace($site)) { continue }
    if (-not $siteSummary.ContainsKey($site)) {
        $siteSummary[$site] = @{
            Providers = @{}
            Reasons   = @{}
            Statuses  = @{}
            Events    = 0
        }
    }
    $summary = $siteSummary[$site]
    $provider = if ($evt.PSObject.Properties.Name -contains 'SiteCacheProvider') { ('' + $evt.SiteCacheProvider).Trim() } else { $null }
    $reason   = if ($evt.PSObject.Properties.Name -contains 'SiteCacheProviderReason') { ('' + $evt.SiteCacheProviderReason).Trim() } else { $null }
    $status   = if ($evt.PSObject.Properties.Name -contains 'CacheStatus') { ('' + $evt.CacheStatus).Trim() } else { $null }
    if ($provider) {
        if (-not $summary.Providers.ContainsKey($provider)) { $summary.Providers[$provider] = 0 }
        $summary.Providers[$provider]++
    }
    if ($reason) {
        if (-not $summary.Reasons.ContainsKey($reason)) { $summary.Reasons[$reason] = 0 }
        $summary.Reasons[$reason]++
    }
    if ($status) {
        if (-not $summary.Statuses.ContainsKey($status)) { $summary.Statuses[$status] = 0 }
        $summary.Statuses[$status]++
    }
    $summary.Events++
}

$result = [pscustomobject]@{
    SourcePath = (Resolve-Path -LiteralPath $Path).ProviderPath
    Sites      = @()
}

foreach ($key in ($siteSummary.Keys | Sort-Object)) {
    $item = $siteSummary[$key]
    $result.Sites += [pscustomobject]@{
        Site      = $key
        Events    = $item.Events
        Providers = $item.Providers.GetEnumerator() | Sort-Object Name
        Reasons   = $item.Reasons.GetEnumerator() | Sort-Object Name
        Statuses  = $item.Statuses.GetEnumerator() | Sort-Object Name
    }
}

Write-Host ("[Freshness] Source: {0}" -f $result.SourcePath) -ForegroundColor Cyan
foreach ($site in $result.Sites) {
    Write-Host ("[Freshness] {0}: events={1}" -f $site.Site, $site.Events)
    if ($site.Providers) { Write-Host ("  Providers: {0}" -f (($site.Providers | ForEach-Object { '{0}={1}' -f $_.Name, $_.Value }) -join ', ')) }
    if ($site.Reasons) { Write-Host ("  Reasons: {0}" -f (($site.Reasons | ForEach-Object { '{0}={1}' -f $_.Name, $_.Value }) -join ', ')) }
    if ($site.Statuses) { Write-Host ("  Statuses: {0}" -f (($site.Statuses | ForEach-Object { '{0}={1}' -f $_.Name, $_.Value }) -join ', ')) }
}

if ($OutputPath) {
    $dir = Split-Path -Path $OutputPath -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    $resolved = Resolve-Path -LiteralPath $OutputPath -ErrorAction SilentlyContinue
    $display = if ($resolved) { $resolved.ProviderPath } else { $OutputPath }
    Write-Host ("[Freshness] Summary written to {0}" -f $display) -ForegroundColor Green
}
