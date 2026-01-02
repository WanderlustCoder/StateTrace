[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SchedulerReportPath,

    [Parameter(Mandatory)]
    [string]$PortDiversityReportPath,

    [string]$OutputPath,

    [string]$MarkdownPath
)

<#
.SYNOPSIS
Correlates parser scheduler launch streaks with PortBatchReady site streaks.

.DESCRIPTION
Reads `ParserSchedulerLaunch-*.json` and `PortBatchSiteDiversity-*.json` outputs and
generates a combined summary showing, per site, the maximum scheduler streak vs. the
longest consecutive PortBatchReady run. Highlights sites where the UI replay still
shows longer streaks than the parser scheduler emits and optionally writes both JSON
and markdown artifacts.

.EXAMPLE
pwsh Tools\Compare-SchedulerAndPortDiversity.ps1 `
    -SchedulerReportPath Logs\Reports\ParserSchedulerLaunch-2025-11-14.json `
    -PortDiversityReportPath Logs\Reports\PortBatchSiteDiversity-20251114.json `
    -OutputPath Logs\Reports\SchedulerVsPortDiversity-2025-11-14.json `
    -MarkdownPath docs\performance\SchedulerVsPortDiversity-20251114.md
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$toolingJsonPath = Join-Path -Path $PSScriptRoot -ChildPath 'ToolingJson.psm1'
if (Test-Path -LiteralPath $toolingJsonPath) {
    Import-Module -Name $toolingJsonPath -Force
} else {
    throw "ToolingJson module not found at '$toolingJsonPath'."
}

function Resolve-ExistingFile {
    param([string]$PathValue, [string]$Name)
    if (-not (Test-Path -LiteralPath $PathValue)) {
        throw "'$Name' file '$PathValue' was not found."
    }
    return (Resolve-Path -LiteralPath $PathValue).Path
}

$schedulerPath = Resolve-ExistingFile -PathValue $SchedulerReportPath -Name 'Scheduler report'
$portPath = Resolve-ExistingFile -PathValue $PortDiversityReportPath -Name 'Port diversity report'

try {
    $scheduler = Read-ToolingJson -Path $schedulerPath -Label 'Scheduler report'
} catch {
    throw "Failed to parse scheduler report '$schedulerPath': $($_.Exception.Message)"
}
try {
    $port = Read-ToolingJson -Path $portPath -Label 'Port diversity report'
} catch {
    throw "Failed to parse port diversity report '$portPath': $($_.Exception.Message)"
}

if (-not $scheduler.SiteSummaries) {
    throw "Scheduler report '$schedulerPath' does not contain SiteSummaries."   
}
if (-not ($port -and $port.PSObject.Properties.Name -contains 'SiteStreaks')) { 
    throw "Port diversity report '$portPath' does not contain SiteStreaks."     
}

# LANDMARK: Scheduler vs port diversity metadata - track synthesis and input alignment
$portUsedSynthesized = $false
if ($port -and ($port.PSObject.Properties.Name -contains 'UsedSynthesizedEvents')) {
    try { $portUsedSynthesized = [bool]$port.UsedSynthesizedEvents } catch { $portUsedSynthesized = $false }
}
$comparisonMode = if ($portUsedSynthesized) { 'SynthesizedPortBatchReady' } else { 'ObservedPortBatchReady' }

$portMetricsFile = $null
if ($port -and ($port.PSObject.Properties.Name -contains 'MetricsFile') -and $port.MetricsFile) {
    $portMetricsFile = $port.MetricsFile
}
$schedulerMetricsFiles = @()
if ($scheduler -and ($scheduler.PSObject.Properties.Name -contains 'FilesAnalyzed') -and $scheduler.FilesAnalyzed) {
    if ($scheduler.FilesAnalyzed -is [System.Array]) {
        $schedulerMetricsFiles = @($scheduler.FilesAnalyzed)
    } else {
        $schedulerMetricsFiles = @($scheduler.FilesAnalyzed)
    }
}

$resolvedPortMetrics = $null
if ($portMetricsFile) {
    try { $resolvedPortMetrics = (Resolve-Path -LiteralPath $portMetricsFile).Path } catch { $resolvedPortMetrics = $portMetricsFile }
}
$resolvedSchedulerMetrics = @()
foreach ($file in $schedulerMetricsFiles) {
    if ([string]::IsNullOrWhiteSpace($file)) { continue }
    try { $resolvedSchedulerMetrics += (Resolve-Path -LiteralPath $file).Path } catch { $resolvedSchedulerMetrics += $file }
}

$inputsAligned = $true
$inputMismatchDetail = $null
if ($resolvedPortMetrics -and $resolvedSchedulerMetrics.Count -gt 0 -and -not ($resolvedSchedulerMetrics -contains $resolvedPortMetrics)) {
    $inputsAligned = $false
    $inputMismatchDetail = "Scheduler files: $($resolvedSchedulerMetrics -join ', '); Port metrics: $resolvedPortMetrics"
}

$portStreaks = @($port.SiteStreaks)
if (-not $portStreaks -or $portStreaks.Count -eq 0) {
    Write-Warning ("Port diversity report '{0}' contains no SiteStreaks; treating PortBatchReady streaks as zero." -f $portPath)
}

$schedulerLookup = @{}
foreach ($entry in $scheduler.SiteSummaries) {
    if ($entry.Site) {
        $schedulerLookup[$entry.Site] = [int]$entry.MaxConsecutive
    }
}

$portLookup = @{}
foreach ($entry in $portStreaks) {
    if ($entry.Site) {
        $portLookup[$entry.Site] = [int]$entry.MaxCount
    }
}

$sites = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($key in $schedulerLookup.Keys) { [void]$sites.Add($key) }
foreach ($key in $portLookup.Keys) { [void]$sites.Add($key) }

$rows = @()
foreach ($site in $sites) {
    $schedulerMax = if ($schedulerLookup.ContainsKey($site)) { $schedulerLookup[$site] } else { 0 }
    $portMax = if ($portLookup.ContainsKey($site)) { $portLookup[$site] } else { 0 }
    $rows += [pscustomobject]@{
        Site             = $site
        SchedulerMax     = $schedulerMax
        PortBatchMax     = $portMax
        PortMinusScheduler = $portMax - $schedulerMax
        Mismatch         = ($portMax -gt $schedulerMax)
    }
}

$mismatches = $rows | Where-Object { $_.Mismatch }
$sortedSites = $rows | Sort-Object -Property @{Expression = 'PortMinusScheduler'; Descending = $true }, @{Expression = 'Site'; Descending = $false }

$maxPortBatchStreak = 0
if ($portStreaks -and $portStreaks.Count -gt 0) {
    try {
        $measure = $portStreaks | Measure-Object -Property MaxCount -Maximum
        if ($measure -and $measure.PSObject.Properties.Name -contains 'Maximum') {
            $maxPortBatchStreak = [int]$measure.Maximum
        }
    } catch {
        $maxPortBatchStreak = 0
    }
}

$mismatchCount = ($mismatches | Measure-Object).Count
$mismatchClassification = 'None'
if ($mismatchCount -gt 0) {
    $mismatchClassification = if ($portUsedSynthesized) { 'Informational' } else { 'Warning' }
}

$summary = [pscustomobject]@{
    SchedulerReportPath  = $schedulerPath
    PortDiversityPath    = $portPath
    GeneratedAtUtc       = (Get-Date).ToUniversalTime().ToString('o')
    Sites                = $sortedSites
    MismatchCount        = $mismatchCount
    MismatchClassification = $mismatchClassification
    MaxSchedulerStreak   = [int]($scheduler.SiteSummaries | Measure-Object -Property MaxConsecutive -Maximum).Maximum
    MaxPortBatchStreak   = $maxPortBatchStreak
    PortBatchUsedSynthesizedEvents = $portUsedSynthesized
    ComparisonMode       = $comparisonMode
    InputsAligned        = $inputsAligned
    InputMismatchDetail  = $inputMismatchDetail
}

Write-Host ("Scheduler max streak: {0}; PortBatchReady max streak: {1}" -f $summary.MaxSchedulerStreak, $summary.MaxPortBatchStreak) -ForegroundColor Cyan      
if (-not $summary.InputsAligned -and $summary.InputMismatchDetail) {
    Write-Warning ("Scheduler vs. port diversity inputs are misaligned: {0}" -f $summary.InputMismatchDetail)
}
if ($summary.MismatchCount -gt 0) {
    if ($summary.MismatchClassification -eq 'Informational') {
        Write-Host ("{0} site(s) show PortBatchReady streaks longer than scheduler launches; classification is informational because PortBatchReady events are synthesized. Top offenders: {1}" -f $summary.MismatchCount, (($mismatches | Select-Object -First 3 | ForEach-Object { "{0} (+{1})" -f $_.Site, $_.PortMinusScheduler }) -join ', ')) -ForegroundColor Yellow
    } else {
        Write-Warning ("{0} site(s) show PortBatchReady streaks longer than scheduler launches. Top offenders: {1}" -f $summary.MismatchCount, (($mismatches | Select-Object -First 3 | ForEach-Object { "{0} (+{1})" -f $_.Site, $_.PortMinusScheduler }) -join ', '))
    }
} else {
    Write-Host 'No scheduler vs. port streak mismatches detected.' -ForegroundColor Green
}

$jsonPath = $null
$markdownPathResolved = $null

if ($OutputPath) {
    $ext = [System.IO.Path]::GetExtension($OutputPath)
    if ([string]::Equals($ext, '.md', [System.StringComparison]::OrdinalIgnoreCase)) {
        $markdownPathResolved = $OutputPath
    } else {
        $jsonPath = $OutputPath
    }
}
if ($MarkdownPath) {
    $markdownPathResolved = $MarkdownPath
}

if ($jsonPath) {
    $jsonDir = Split-Path -Path $jsonPath -Parent
    if ($jsonDir -and -not (Test-Path -LiteralPath $jsonDir)) {
        New-Item -ItemType Directory -Path $jsonDir -Force | Out-Null
    }
    $summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding utf8
    Write-Host ("JSON summary written to {0}" -f (Resolve-Path -LiteralPath $jsonPath)) -ForegroundColor DarkCyan
}

if ($markdownPathResolved) {
    $markdownDir = Split-Path -Path $markdownPathResolved -Parent
    if ($markdownDir -and -not (Test-Path -LiteralPath $markdownDir)) {
        New-Item -ItemType Directory -Path $markdownDir -Force | Out-Null
    }
    $md = New-Object System.Collections.Generic.List[string]
    $md.Add("# Scheduler vs. PortBatchReady Streaks")
    $md.Add("")
    $md.Add([string]::Format("Generated: {0}", (Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')))
    $md.Add([string]::Format("Scheduler report: {0}", (Split-Path -Path $schedulerPath -Leaf)))
    $md.Add([string]::Format("Port diversity report: {0}", (Split-Path -Path $portPath -Leaf)))
    $md.Add([string]::Format("Comparison mode: {0}", $summary.ComparisonMode))
    $md.Add([string]::Format("Port diversity used synthesized events: {0}", $summary.PortBatchUsedSynthesizedEvents))
    $md.Add([string]::Format("Inputs aligned: {0}", $summary.InputsAligned))
    if (-not $summary.InputsAligned -and $summary.InputMismatchDetail) {
        $md.Add([string]::Format("Input mismatch detail: {0}", $summary.InputMismatchDetail))
    }
    $md.Add([string]::Format("Mismatch classification: {0}", $summary.MismatchClassification))
    $md.Add("")
    $md.Add("| Site | Scheduler Max | PortBatchReady Max | Delta |")
    $md.Add("|------|---------------|--------------------|-------|")
    foreach ($row in ($summary.Sites | Sort-Object PortBatchMax -Descending)) {
        $md.Add(("| {0} | {1} | {2} | {3:+#;-#;0} |" -f $row.Site, $row.SchedulerMax, $row.PortBatchMax, $row.PortMinusScheduler))
    }
    $md.Add("")
    $md.Add(("Mismatch count: {0}" -f $summary.MismatchCount))
    Set-Content -LiteralPath $markdownPathResolved -Value ($md -join [Environment]::NewLine) -Encoding utf8
    Write-Host ("Markdown summary written to {0}" -f (Resolve-Path -LiteralPath $markdownPathResolved)) -ForegroundColor DarkCyan
}

if (-not $OutputPath -and -not $MarkdownPath) {
    $summary
}
