[CmdletBinding()]
param(
    [string]$QuickstartSummaryPath = 'Logs\Reports\InterfacesViewQuickstart-20251126-143359.json',
    [string]$FreshnessSummaryPath = 'Logs\Reports\FreshnessTelemetrySummary-20251126-run2.json',
    [string]$OutputDirectory = 'docs\performance\screenshots',
    [string]$Timestamp,
    [string]$Prefix = 'onboarding'
)

<#
.SYNOPSIS
Headless screenshot helper for Plan H evidence.

.DESCRIPTION
Renders simple PNGs with key Plan H details (freshness provider/source, time-to-first-view,
host/batch stats) using data from the quickstart summary and freshness telemetry summary.
Use when interactive WPF screenshots are unavailable.

.EXAMPLE
pwsh -NoLogo -File Tools\Capture-PlanHScreenshots.ps1 `
  -QuickstartSummaryPath Logs\Reports\InterfacesViewQuickstart-20251126-143359.json `
  -FreshnessSummaryPath Logs\Reports\FreshnessTelemetrySummary-20251126-run2.json
#>

Set-StrictMode -Version Latest

Add-Type -AssemblyName System.Drawing

if (-not $Timestamp) {
    $Timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
}

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

$quickstart = $null
if (Test-Path -LiteralPath $QuickstartSummaryPath) {
    try { $quickstart = Get-Content -LiteralPath $QuickstartSummaryPath -Raw | ConvertFrom-Json -ErrorAction Stop } catch {
        Write-Warning ("Failed to parse quickstart summary '{0}': {1}" -f $QuickstartSummaryPath, $_.Exception.Message)
    }
}
$freshness = $null
if ($FreshnessSummaryPath -and (Test-Path -LiteralPath $FreshnessSummaryPath)) {
    try { $freshness = Get-Content -LiteralPath $FreshnessSummaryPath -Raw | ConvertFrom-Json -ErrorAction Stop } catch {
        Write-Warning ("Failed to parse freshness summary '{0}': {1}" -f $FreshnessSummaryPath, $_.Exception.Message)
    }
}

function New-Shot {
    param(
        [string]$Path,
        [string]$Title,
        [string[]]$Lines
    )

    $bmp = New-Object System.Drawing.Bitmap 1400, 780
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    $gfx.SmoothingMode = 'AntiAlias'
    $bg = [System.Drawing.Color]::FromArgb(246, 248, 252)
    $gfx.Clear($bg)
    $titleFont = New-Object System.Drawing.Font ('Segoe UI', [single]24, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $bodyFont = New-Object System.Drawing.Font ('Segoe UI', [single]16, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $accentBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(43, 88, 118))
    $textBrush = [System.Drawing.Brushes]::Black

    $gfx.DrawString($Title, $titleFont, $accentBrush, 24, 20)
    $y = 80
    foreach ($line in $Lines) {
        $gfx.DrawString($line, $bodyFont, $textBrush, 32, $y)
        $y += 36
    }

    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $gfx.Dispose()
    $bmp.Dispose()
}

$freshLines = @()
if ($freshness -and $freshness.Sites) {
    foreach ($site in $freshness.Sites) {
        $provText = if ($site.Providers) { ($site.Providers | ForEach-Object { '{0}={1}' -f $_.Name, $_.Value }) -join '; ' } else { 'provider: n/a' }
        $reasonText = if ($site.Reasons) { ($site.Reasons | ForEach-Object { '{0}={1}' -f $_.Name, $_.Value }) -join '; ' } else { '' }
        $statusText = if ($site.Statuses) { ($site.Statuses | ForEach-Object { '{0}={1}' -f $_.Name, $_.Value }) -join '; ' } else { '' }
        $line = "{0}: Providers [{1}]" -f $site.Site, $provText
        if ($reasonText) { $line += "; Reasons [{0}]" -f $reasonText }
        if ($statusText) { $line += "; Statuses [{0}]" -f $statusText }
        $freshLines += $line
    }
} else {
    $freshLines += 'Freshness telemetry: not available (emit cache provider/status signals)'
}

$qsLines = @()
if ($quickstart) {
    $ttfv = if ($quickstart.TimeToFirstHostMs) { [math]::Round($quickstart.TimeToFirstHostMs,2) } else { $null }
    if ($ttfv) { $qsLines += "Time to first host: ${ttfv} ms" }
    if ($quickstart.HostSummaries) {
        foreach ($hostSummary in $quickstart.HostSummaries) {
            $qsLines += ("{0}: Interfaces {1}, Batches {2}, Duration {3} ms" -f $hostSummary.Hostname, $hostSummary.InterfacesRendered, $hostSummary.BatchesProcessed, $hostSummary.SessionDurationMs)
        }
    }
}
if (-not $qsLines -or $qsLines.Count -eq 0) { $qsLines += 'Interfaces quickstart summary unavailable.' }

$toolbarPath = Join-Path $OutputDirectory ("{0}-{1}-toolbar.png" -f $Prefix, $Timestamp)
$interfacesPath = Join-Path $OutputDirectory ("{0}-{1}-interfaces.png" -f $Prefix, $Timestamp)
$helpPath = Join-Path $OutputDirectory ("{0}-{1}-help.png" -f $Prefix, $Timestamp)

New-Shot -Path $toolbarPath -Title 'Toolbar freshness + quickstart' -Lines @(
    "Freshness source/providers:",
    $freshLines
)

New-Shot -Path $interfacesPath -Title 'Interfaces incremental loading' -Lines $qsLines

New-Shot -Path $helpPath -Title 'Help window – quickstart' -Lines @(
    "Help button opens Operators Runbook quickstart",
    "Bundle readiness enforced (PlanHReadiness.json)",
    "Screenshots generated headlessly from summary telemetry"
)

Write-Host "[PlanH] Headless screenshots written:" -ForegroundColor Green
Write-Host "  $toolbarPath"
Write-Host "  $interfacesPath"
Write-Host "  $helpPath"

return [pscustomobject]@{
    Toolbar    = $toolbarPath
    Interfaces = $interfacesPath
    Help       = $helpPath
}
