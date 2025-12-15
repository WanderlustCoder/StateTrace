Set-StrictMode -Version Latest

$statisticsModulePath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Modules\StatisticsModule.psm1'
if (-not (Test-Path -LiteralPath $statisticsModulePath)) {
    throw "StatisticsModule not found at $statisticsModulePath"
}
Import-Module -Name $statisticsModulePath -Force -ErrorAction Stop

function Get-PercentileValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [double[]]$Values,

        [Parameter(Mandatory = $true)]
        [double]$Percentile
    )

    return StatisticsModule\Get-PercentileValue -Values $Values -Percentile $Percentile
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

function New-SampleStats {
    [CmdletBinding()]
    param(
        [double[]]$Values,
        [string]$Name,
        [double[]]$Percentiles = @(50, 95, 99)
    )

    $summary = New-StatsSummary -Values $Values -Name $Name -Percentiles $Percentiles
    $count = 0
    try { $count = [int]$summary.Count } catch { $count = 0 }
    $summary | Add-Member -NotePropertyName 'SampleCount' -NotePropertyValue $count -Force
    return $summary
}

function Get-SampleCount {
    [CmdletBinding()]
    param(
        $Stats,
        $FallbackContainer
    )

    $value = 0
    if ($Stats) {
        if ($Stats.PSObject.Properties.Name -contains 'SampleCount') {
            try { $value = [int]$Stats.SampleCount } catch { $value = $value }
        } elseif ($Stats.PSObject.Properties.Name -contains 'Count') {
            try { $value = [int]$Stats.Count } catch { $value = $value }
        }
    }

    if (($value -eq 0) -and $FallbackContainer -and $FallbackContainer.PSObject.Properties.Name -contains 'Statistics') {
        $fallbackStats = $FallbackContainer.Statistics
        if ($fallbackStats -and $fallbackStats.PSObject.Properties.Name -contains 'SampleCount') {
            try { $value = [int]$fallbackStats.SampleCount } catch { $value = $value }
        }
    }

    return $value
}

Export-ModuleMember -Function Get-PercentileValue, New-StatsSummary, New-SampleStats, Get-SampleCount
