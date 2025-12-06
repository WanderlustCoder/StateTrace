[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [string]$OutputPath,

    [int]$TopHosts = 10,

    [switch]$PassThru
)

<#
.SYNOPSIS
Summarises InterfaceSyncTiming telemetry (UiClone, stream dispatch, cache update) per host/site.

.DESCRIPTION
Parses newline-delimited ingestion metrics JSON and extracts `InterfaceSyncTiming` events.
Produces aggregate statistics (average/p95/max) for `UiCloneDurationMs`, `StreamDispatchDurationMs`,
`DiffDurationMs`, and `SiteCacheUpdateDurationMs`, plus per-site and top-host breakdowns. Optionally
writes the result to JSON for bundling/review.

.EXAMPLE
pwsh Tools\Analyze-InterfaceSyncTiming.ps1 `
    -Path Logs\IngestionMetrics\2025-11-13-142949.json `
    -OutputPath Logs\Reports\InterfaceSyncTiming-20251113-142949.json `
    -TopHosts 15
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-InputFiles {
    param([string]$InputPath)
    if (-not (Test-Path -LiteralPath $InputPath)) {
        throw "Path '$InputPath' does not exist."
    }
    $item = Get-Item -LiteralPath $InputPath
    if ($item -is [System.IO.DirectoryInfo]) {
        $files = Get-ChildItem -LiteralPath $item.FullName -Filter '*.json' -File
        if (-not $files) { throw "Directory '$($item.FullName)' contains no JSON files." }
        return $files.FullName
    }
    return @($item.FullName)
}

function Convert-ToStats {
    param(
        [double[]]$Values,
        [string]$Name
    )
    # Normalize to an array to keep singletons from being unrolled during Sort-Object
    $normalized = @($Values | Where-Object { $_ -ne $null })
    if (-not $normalized -or $normalized.Count -eq 0) {
        return [pscustomobject]@{ Name=$Name; Count=0; Average=$null; P50=$null; P95=$null; Max=$null }
    }
    $sorted = @($normalized | Sort-Object)
    $count = $sorted.Count
    $avg = ($sorted | Measure-Object -Average).Average
    $max = $sorted[-1]
    function Get-Pct($arr,[double]$percent) {
        $rank = ($percent/100.0)*($arr.Length-1)
        $lower=[math]::Floor($rank)
        $upper=[math]::Ceiling($rank)
        if ($lower -eq $upper) { return $arr[$lower] }
        $weight=$rank-$lower
        return $arr[$lower]+($weight*($arr[$upper]-$arr[$lower]))
    }
    return [pscustomobject]@{
        Name    = $Name
        Count   = $count
        Average = [math]::Round($avg,3)
        P50     = [math]::Round((Get-Pct $sorted 50),3)
        P95     = [math]::Round((Get-Pct $sorted 95),3)
        Max     = [math]::Round($max,3)
    }
}

$files = Resolve-InputFiles -InputPath $Path
$events = New-Object System.Collections.Generic.List[pscustomobject]

foreach ($file in $files) {
    Get-Content -LiteralPath $file -ReadCount 500 | ForEach-Object {
        foreach ($line in $_) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $obj = $line | ConvertFrom-Json -ErrorAction Stop
            }
            catch {
                Write-Warning ("Skipping malformed JSON line in '{0}': {1}" -f $file, $_.Exception.Message)
                continue
            }
            if ($obj.EventName -ne 'InterfaceSyncTiming') { continue }

            $events.Add([pscustomobject]@{
                Host         = $obj.Hostname
                Site         = $obj.Site
                UiClone      = [double]($obj.UiCloneDurationMs)
                StreamDispatch = [double]($obj.StreamDispatchDurationMs)
                DiffDuration = [double]($obj.DiffDurationMs)
                SiteCacheUpdate = if ($obj.SiteCacheUpdateDurationMs -ne $null) { [double]$obj.SiteCacheUpdateDurationMs } else { $null }
            }) | Out-Null
        }
    }
}

if ($events.Count -eq 0) {
    $warningMsg = "No InterfaceSyncTiming events found in the supplied files."
    Write-Warning $warningMsg
    $emptyResult = [pscustomobject]@{
        GeneratedAtUtc   = (Get-Date).ToUniversalTime().ToString('o')
        FilesAnalyzed    = $files
        EventCount       = 0
        GlobalStats      = [pscustomobject]@{
            UiClone         = Convert-ToStats -Values $null -Name 'UiCloneDurationMs'
            StreamDispatch  = Convert-ToStats -Values $null -Name 'StreamDispatchDurationMs'
            DiffDuration    = Convert-ToStats -Values $null -Name 'DiffDurationMs'
            SiteCacheUpdate = Convert-ToStats -Values $null -Name 'SiteCacheUpdateDurationMs'
        }
        SiteBreakdown    = @()
        HostBreakdownTop = @()
    }
    if ($OutputPath) {
        $outputDir = Split-Path -Path $OutputPath -Parent
        if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }
        $emptyResult | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding utf8
        Write-Warning ("Wrote empty InterfaceSyncTiming summary to {0}" -f (Resolve-Path -LiteralPath $OutputPath))
    }
    if ($PassThru) { return $emptyResult }
    return
}

$uiCloneValues = $events | Where-Object { $_.UiClone -ge 0 } | ForEach-Object { $_.UiClone }
$dispatchValues = $events | Where-Object { $_.StreamDispatch -ge 0 } | ForEach-Object { $_.StreamDispatch }
$diffValues = $events | Where-Object { $_.DiffDuration -ge 0 } | ForEach-Object { $_.DiffDuration }
$siteCacheValues = $events | Where-Object { $_.SiteCacheUpdate -ge 0 } | ForEach-Object { $_.SiteCacheUpdate }

$globalStats = [pscustomobject]@{
    UiClone        = Convert-ToStats -Values ([double[]]$uiCloneValues) -Name 'UiCloneDurationMs'
    StreamDispatch = Convert-ToStats -Values ([double[]]$dispatchValues) -Name 'StreamDispatchDurationMs'
    DiffDuration   = Convert-ToStats -Values ([double[]]$diffValues) -Name 'DiffDurationMs'
    SiteCacheUpdate = Convert-ToStats -Values ([double[]]$siteCacheValues) -Name 'SiteCacheUpdateDurationMs'
}

$siteGroups = $events | Group-Object Site
$siteBreakdown = foreach ($group in $siteGroups) {
    $siteUi = $group.Group | Where-Object { $_.UiClone -ge 0 } | ForEach-Object { $_.UiClone }
    $siteDispatch = $group.Group | Where-Object { $_.StreamDispatch -ge 0 } | ForEach-Object { $_.StreamDispatch }
    $siteDiff = $group.Group | Where-Object { $_.DiffDuration -ge 0 } | ForEach-Object { $_.DiffDuration }
    [pscustomobject]@{
        Site             = $group.Name
        EventCount       = $group.Count
        UiCloneP95       = (Convert-ToStats -Values ([double[]]$siteUi) -Name 'UiClone').P95
        StreamDispatchP95 = (Convert-ToStats -Values ([double[]]$siteDispatch) -Name 'StreamDispatch').P95
        DiffDurationP95  = (Convert-ToStats -Values ([double[]]$siteDiff) -Name 'DiffDuration').P95
    }
}

$hostAgg = $events | Group-Object Host | ForEach-Object {
    [pscustomobject]@{
        Host             = $_.Name
        EventCount       = $_.Count
        UiCloneP95       = (Convert-ToStats -Values ([double[]]($_.Group | ForEach-Object { $_.UiClone })) -Name 'UiClone').P95
        StreamDispatchP95 = (Convert-ToStats -Values ([double[]]($_.Group | ForEach-Object { $_.StreamDispatch })) -Name 'StreamDispatch').P95
    }
} | Sort-Object UiCloneP95 -Descending

$topHostRows = $hostAgg | Select-Object -First $TopHosts

$result = [pscustomobject]@{
    GeneratedAtUtc   = (Get-Date).ToUniversalTime().ToString('o')
    FilesAnalyzed    = $files
    EventCount       = $events.Count
    GlobalStats      = $globalStats
    SiteBreakdown    = $siteBreakdown
    HostBreakdownTop = $topHostRows
}

if ($OutputPath) {
    $outputDir = Split-Path -Path $OutputPath -Parent
    if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding utf8
    Write-Host ("InterfaceSyncTiming summary written to {0}" -f (Resolve-Path -LiteralPath $OutputPath)) -ForegroundColor DarkCyan
}

Write-Host "Global InterfaceSyncTiming stats:" -ForegroundColor Cyan
$result.GlobalStats | Format-List

Write-Host "`nSite breakdown (p95 ms):" -ForegroundColor Cyan
$result.SiteBreakdown | Sort-Object UiCloneP95 -Descending | Format-Table Site, EventCount, UiCloneP95, StreamDispatchP95, DiffDurationP95 -AutoSize

Write-Host ("`nTop {0} hosts by UiClone p95:" -f $TopHosts) -ForegroundColor Cyan
$topHostRows | Format-Table Host, EventCount, UiCloneP95, StreamDispatchP95 -AutoSize

if ($PassThru) {
    return $result
}
