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

function Read-WarmPassEvents {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

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
            if ($obj -and $obj.PassLabel -eq 'WarmPass' -and $obj.Site) {
                $null = $parsed.Add($obj)
            }
        } catch {
            $parseErrors++
            if ($parseErrors -le 3) {
                Write-Verbose ("[WarmRunDiff] Skipping invalid JSON line: {0}" -f $_.Exception.Message)
            }
        }
        if ($parsedLines -eq 0 -and $lineAttempts -ge $maxLineAttempts) {
            break
        }
    }

    if ($parsedLines -gt 0) {
        if ($parseErrors -gt 0) {
            Write-Warning ("[WarmRunDiff] Skipped {0} invalid JSON line(s) in {1}" -f $parseErrors, $Path)
        }
        return $parsed.ToArray()
    }

    $rawContent = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($rawContent)) {
        throw "Telemetry file '$Path' was empty."
    }
    $allEvents = $rawContent | ConvertFrom-Json -ErrorAction Stop
    return @($allEvents | Where-Object { $_.PassLabel -eq 'WarmPass' -and $_.Site })
}

$warmEvents = Read-WarmPassEvents -Path $TelemetryPath
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
