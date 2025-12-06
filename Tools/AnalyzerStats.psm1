Set-StrictMode -Version Latest

function Get-PercentileValue {
    [CmdletBinding()]
    param(
        [double[]]$Values,
        [double]$Percentile
    )

    $normalized = @($Values | Where-Object { $_ -ne $null })
    if (-not $normalized -or $normalized.Count -eq 0) { return $null }
    $sorted = @($normalized | Sort-Object)
    $position = ($Percentile / 100.0) * ($sorted.Count - 1)
    $lowerIndex = [math]::Floor($position)
    $upperIndex = [math]::Ceiling($position)
    if ($lowerIndex -eq $upperIndex) { return $sorted[$lowerIndex] }
    $weight = $position - $lowerIndex
    return $sorted[$lowerIndex] + ($weight * ($sorted[$upperIndex] - $sorted[$lowerIndex]))
}

function New-StatsSummary {
    [CmdletBinding()]
    param(
        [double[]]$Values,
        [string]$Name,
        [double[]]$Percentiles = @(50, 95, 99)
    )

    $normalized = @($Values | Where-Object { $_ -ne $null })
    if (-not $normalized -or $normalized.Count -eq 0) {
        return [pscustomobject]@{
            Name    = $Name
            Count   = 0
            Average = $null
            Min     = $null
            Max     = $null
            P50     = $null
            P95     = $null
            P99     = $null
        }
    }

    $sorted = @($normalized | Sort-Object)
    $avg = ($sorted | Measure-Object -Average).Average
    $summary = [pscustomobject]@{
        Name    = $Name
        Count   = $sorted.Count
        Average = [math]::Round($avg, 6)
        Min     = [math]::Round(($sorted | Measure-Object -Minimum).Minimum, 6)
        Max     = [math]::Round($sorted[-1], 6)
        P50     = $null
        P95     = $null
        P99     = $null
    }

    foreach ($pct in $Percentiles) {
        $prop = "P$($pct)"
        $value = Get-PercentileValue -Values $sorted -Percentile $pct
        $summary | Add-Member -NotePropertyName $prop -NotePropertyValue ([math]::Round(($value), 6)) -Force
    }

    return $summary
}

Export-ModuleMember -Function Get-PercentileValue, New-StatsSummary
