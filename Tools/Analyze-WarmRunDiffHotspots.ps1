[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TelemetryPath,
    [int]$Top = 20,
    [double]$MinDiffComparisonMs = 0,
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $TelemetryPath)) {
    throw "Telemetry file not found at '$TelemetryPath'."
}

Write-Host ("Reading telemetry from '{0}'..." -f (Resolve-Path -LiteralPath $TelemetryPath)) -ForegroundColor Cyan

$rawContent = Get-Content -LiteralPath $TelemetryPath -Raw
if ([string]::IsNullOrWhiteSpace($rawContent)) {
    throw "Telemetry file '$TelemetryPath' was empty."
}

$allEvents = $rawContent | ConvertFrom-Json
$warmEvents = @($allEvents | Where-Object { $_.PassLabel -eq 'WarmPass' -and $_.Site })
if (-not $warmEvents -or $warmEvents.Count -eq 0) {
    Write-Warning 'No WarmPass entries were found in the telemetry file.'
    return
}

$hotPaths = $warmEvents | Where-Object {
    $_.PSObject.Properties.Name -contains 'DiffComparisonDurationMs' -and
    $_.DiffComparisonDurationMs -ne $null -and
    [double]$_.DiffComparisonDurationMs -ge $MinDiffComparisonMs
}

if (-not $hotPaths -or $hotPaths.Count -eq 0) {
    Write-Warning ("No WarmPass entries met the diff comparison threshold (>= {0} ms)." -f $MinDiffComparisonMs)
    return
}

$sorted = $hotPaths | Sort-Object {
    -1 * [double]($_.DiffComparisonDurationMs)
}

$topEntries = if ($Top -gt 0) { $sorted | Select-Object -First $Top } else { $sorted }

$result = $topEntries | Select-Object `
    @{ Name = 'Site'; Expression = { $_.Site } },
    @{ Name = 'Hostname'; Expression = { $_.Hostname } },
    @{ Name = 'DiffComparisonMs'; Expression = { [math]::Round([double]($_.DiffComparisonDurationMs), 3) } },
    @{ Name = 'DiffDurationMs'; Expression = {
            if ($_ -and $_.PSObject.Properties.Name -contains 'DiffDurationMs' -and $null -ne $_.DiffDurationMs) {
                [math]::Round([double]$_.DiffDurationMs, 3)
            } else { $null }
        }
    },
    @{ Name = 'LoadExistingMs'; Expression = {
            if ($_ -and $_.PSObject.Properties.Name -contains 'LoadExistingDurationMs' -and $null -ne $_.LoadExistingDurationMs) {
                [math]::Round([double]$_.LoadExistingDurationMs, 3)
            } else { $null }
        }
    },
    @{ Name = 'RowSetCount'; Expression = {
            if ($_ -and $_.PSObject.Properties.Name -contains 'LoadExistingRowSetCount') {
                [int]$_.LoadExistingRowSetCount
            } else { $null }
        }
    },
    @{ Name = 'Provider'; Expression = { $_.Provider } },
    @{ Name = 'ProviderReason'; Expression = { $_.SiteCacheProviderReason } }

Write-Host ''
Write-Host ("Top {0} WarmPass hosts by DiffComparisonDurationMs:" -f $topEntries.Count) -ForegroundColor Yellow
$result | Format-Table -AutoSize

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
    $result | Export-Csv -LiteralPath $resolvedOutput -NoTypeInformation
    Write-Host ("Wrote diff hotspot table to '{0}'." -f $resolvedOutput) -ForegroundColor Green
}

$siteAggregates = $hotPaths | Group-Object -Property Site | ForEach-Object {
    $totalDiff = ($_.Group | Measure-Object -Property DiffComparisonDurationMs -Sum).Sum
    $totalRows = ($_.Group | Measure-Object -Property LoadExistingRowSetCount -Sum).Sum
    [pscustomobject]@{
        Site                  = $_.Name
        HostCount             = $_.Count
        TotalDiffComparisonMs = [math]::Round([double]$totalDiff, 3)
        TotalRowSetCount      = [int]$totalRows
        AvgDiffComparisonMs   = [math]::Round([double]($totalDiff / [math]::Max($_.Count, 1)), 3)
    }
} | Sort-Object -Property TotalDiffComparisonMs -Descending

Write-Host ''
Write-Host 'Per-site diff comparison totals:' -ForegroundColor Yellow
$siteAggregates | Format-Table -AutoSize
