[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SweepPath,

    [string]$OutputPath
)

<#
.SYNOPSIS
Summarises dispatcher harness sweep order (host/site sequencing).

.DESCRIPTION
Reads a routing sweep JSON (as produced by `Tools\Invoke-RoutingQueueSweep.ps1`) and reports:
  * Execution order (with timestamp, site, queue delay, duration)
  * Per-site counts / percentage of runs
  * Longest consecutive streak per site (to detect biases)
Use this to prove when sweeps execute all WLLS hosts before BOYO, contributing to scheduler starvation.

.EXAMPLE
pwsh Tools\Analyze-DispatchHarnessSweep.ps1 `
    -SweepPath Logs/DispatchHarness/RoutingQueueSweep-20251113.json `
    -OutputPath docs/performance/DispatchHarnessSweepOrder-20251113.md
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$toolingJsonPath = Join-Path -Path $PSScriptRoot -ChildPath 'ToolingJson.psm1'
if (Test-Path -LiteralPath $toolingJsonPath) {
    Import-Module -Name $toolingJsonPath -Force
} else {
    throw "ToolingJson module not found at '$toolingJsonPath'."
}

function Get-SiteFromHostname {
    param([string]$Hostname)
    if ([string]::IsNullOrWhiteSpace($Hostname)) { return '(unknown)' }
    $parts = $Hostname.Split('-', 2, [System.StringSplitOptions]::RemoveEmptyEntries)
    if ($parts.Count -gt 0) { return $parts[0] }
    return $Hostname
}

if (-not (Test-Path -LiteralPath $SweepPath)) {
    throw "Sweep file '$SweepPath' not found."
}

$entries = Read-ToolingJson -Path $SweepPath -Label 'Dispatch sweep'
if (-not $entries -or $entries.Count -eq 0) {
    throw "Sweep file '$SweepPath' does not contain any entries."
}

$ordered = for ($i = 0; $i -lt $entries.Count; $i++) {
    $entry = $entries[$i]
    [pscustomobject]@{
        Order        = $i + 1
        Hostname     = $entry.Hostname
        Site         = Get-SiteFromHostname -Hostname $entry.Hostname
        QueueDelayMs = $entry.QueueDelayMs
        DurationMs   = $entry.DurationMs
        LogPath      = $entry.LogPath
        ExitCode     = $entry.ExitCode
    }
}

$siteCounts = $ordered | Group-Object Site | ForEach-Object {
    [pscustomobject]@{
        Site        = $_.Name
        Count       = $_.Count
        Percent     = [math]::Round(($_.Count / $ordered.Count) * 100, 2)
    }
} | Sort-Object Count -Descending

# Compute longest streak per site
$streaks = [System.Collections.Generic.List[pscustomobject]]::new()
$currentSite = $null
$currentCount = 0
$currentStart = 0
for ($i = 0; $i -lt $ordered.Count; $i++) {
    $entry = $ordered[$i]
    if ($entry.Site -eq $currentSite) {
        $currentCount++
    }
    else {
        if ($currentSite) {
            $streaks.Add([pscustomobject]@{
                Site    = $currentSite
                Count   = $currentCount
                StartAt = $currentStart + 1
                EndAt   = $i
            })
        }
        $currentSite = $entry.Site
        $currentCount = 1
        $currentStart = $i
    }
}
if ($currentSite) {
    $streaks.Add([pscustomobject]@{
        Site    = $currentSite
        Count   = $currentCount
        StartAt = $currentStart + 1
        EndAt   = $ordered.Count
    })
}

$longestPerSite = $streaks | Sort-Object Count -Descending | Group-Object Site | ForEach-Object {
    $_.Group | Sort-Object Count -Descending | Select-Object -First 1
} | Sort-Object Count -Descending

$builder = New-Object System.Collections.Generic.List[string]
$builder.Add('# Dispatch harness sweep order')
$builder.Add('')
$resolvedSweep = (Resolve-Path -LiteralPath $SweepPath).Path
$builder.Add(('> Sweep file: `{0}`' -f $resolvedSweep))
$generated = Get-Date -Format 'yyyy-MM-dd HH:mm:ss K'
$builder.Add('> Generated ' + $generated)
$builder.Add('')
$builder.Add('## Execution order')
$builder.Add('')
$builder.Add('| # | Host | Site | Queue delay (ms) | Duration (ms) | Log path |')
$builder.Add('|---|---|---|---|---|---|')
foreach ($row in $ordered) {
    $queue = if ($row.QueueDelayMs -ne $null) { [math]::Round($row.QueueDelayMs, 3) } else { '' }
    $duration = if ($row.DurationMs -ne $null) { [math]::Round($row.DurationMs, 3) } else { '' }
    $logLeaf = Split-Path -Path $row.LogPath -Leaf
    $builder.Add( ("| {0} | {1} | {2} | {3} | {4} | `{5}` |" -f @(
        $row.Order,
        $row.Hostname,
        $row.Site,
        $queue,
        $duration,
        $logLeaf)) )
}
$builder.Add("")
$builder.Add("## Site distribution")
$builder.Add("")
$builder.Add("| Site | Count | Percent | Longest streak | Streak range |")
$builder.Add("|---|---|---|---|---|")

foreach ($site in $siteCounts) {
    $streak = $longestPerSite | Where-Object { $_.Site -eq $site.Site } | Select-Object -First 1
    $streakText = if ($streak) { $streak.Count } else { 0 }
    $rangeText = if ($streak) { "$($streak.StartAt)-$($streak.EndAt)" } else { "-" }
    $builder.Add("| $($site.Site) | $($site.Count) | $($site.Percent)% | $streakText | $rangeText |")
}
$builder.Add("")

if ($OutputPath) {
    $outDir = Split-Path -Path $OutputPath -Parent
    if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }
    Set-Content -LiteralPath $OutputPath -Value ($builder -join [Environment]::NewLine) -Encoding utf8
    Write-Host ("Dispatch sweep report written to {0}" -f (Resolve-Path -LiteralPath $OutputPath)) -ForegroundColor DarkCyan
}
else {
    $builder -join [Environment]::NewLine | Write-Host
}

