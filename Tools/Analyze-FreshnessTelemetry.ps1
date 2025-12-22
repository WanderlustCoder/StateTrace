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

function Read-TelemetryEvents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string[]]$EventNames,
        [string]$Label = 'Telemetry'
    )

    $parsed = New-Object System.Collections.Generic.List[object]
    $parseErrors = 0
    $parsedLines = 0
    $lineAttempts = 0
    $maxLineAttempts = 10

    foreach ($line in (Get-Content -LiteralPath $Path -ReadCount 1 -ErrorAction Stop)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $lineAttempts++
        try {
            $obj = $line | ConvertFrom-Json -ErrorAction Stop
            $parsedLines++
            if (-not $EventNames -or ($EventNames -contains $obj.EventName)) {
                $null = $parsed.Add($obj)
            }
        } catch {
            $parseErrors++
            if ($parseErrors -le 3) {
                Write-Verbose ("[{0}] Skipping invalid JSON line: {1}" -f $Label, $_.Exception.Message)
            }
        }
        if ($parsedLines -eq 0 -and $lineAttempts -ge $maxLineAttempts) {
            break
        }
    }

    if ($parsedLines -gt 0) {
        if ($parseErrors -gt 0) {
            Write-Warning ("[{0}] Skipped {1} invalid JSON line(s) in {2}" -f $Label, $parseErrors, $Path)
        }
        return $parsed.ToArray()
    }

    $rawJson = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    $events = $rawJson | ConvertFrom-Json -ErrorAction Stop
    if (-not $events) {
        throw "Failed to parse telemetry at $Path."
    }
    if ($EventNames) {
        $events = @($events | Where-Object { $EventNames -contains $_.EventName })
    }
    return $events
}

if (-not $Path) { $Path = Get-LatestTelemetryPath }
if (-not $Path) { throw "No telemetry file found. Provide -Path or ensure Logs\IngestionMetrics exists." }
if (-not (Test-Path -LiteralPath $Path)) { throw "Telemetry file not found: $Path" }

$targetEventNames = @('InterfaceSiteCacheMetrics','InterfaceSiteCacheRunspaceState','InterfaceSyncTiming','DatabaseWriteBreakdown')
$targetEvents = Read-TelemetryEvents -Path $Path -EventNames $targetEventNames -Label 'Freshness'

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
