[CmdletBinding()]
param(
    [ValidateRange(1, 30)]
    [int]$Days = 1,

    [switch]$IncludePerSite = $true,
    [switch]$IncludeSiteCache = $true,

    [string]$MetricsDirectory,
    [string]$OutputDirectory,

    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path $PSScriptRoot -Parent

Write-Verbose ("Invoke-DailyRollupScheduled: repoRoot={0}" -f $repoRoot)

if (-not $MetricsDirectory) {
    $MetricsDirectory = Join-Path -Path $repoRoot -ChildPath 'Logs\IngestionMetrics'
}
if (-not $OutputDirectory) {
    $OutputDirectory = $MetricsDirectory
}

if (-not (Test-Path -LiteralPath $MetricsDirectory)) {
    New-Item -ItemType Directory -Path $MetricsDirectory -Force | Out-Null
}
if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

$resolvedMetricsDir = Resolve-Path -LiteralPath $MetricsDirectory -ErrorAction Stop
$resolvedOutputDir = Resolve-Path -LiteralPath $OutputDirectory -ErrorAction Stop

$rollupScript = Join-Path -Path $repoRoot -ChildPath 'Tools\Invoke-DailyMetricRollup.ps1'
if (-not (Test-Path -LiteralPath $rollupScript)) {
    throw "Unable to locate Invoke-DailyMetricRollup.ps1 at '$rollupScript'."
}

Write-Verbose ("Invoke-DailyRollupScheduled: Days={0} MetricsDirectory={1} OutputDirectory={2}" -f $Days, $resolvedMetricsDir.Path, $resolvedOutputDir.Path)

$arguments = @{
    Days             = $Days
    MetricsDirectory = $resolvedMetricsDir.Path
    OutputDirectory  = $resolvedOutputDir.Path
}
if ($IncludePerSite) { $arguments.IncludePerSite = $true }
if ($IncludeSiteCache) { $arguments.IncludeSiteCache = $true }
if ($PassThru) { $arguments.PassThru = $true }

Write-Verbose ("Invoke-DailyRollupScheduled: Forwarding {0}" -f (($arguments.GetEnumerator() | ForEach-Object { "-$($_.Key) $($_.Value)" }) -join ' '))

$result = & $rollupScript @arguments

if ($PassThru) {
    return $result
}
