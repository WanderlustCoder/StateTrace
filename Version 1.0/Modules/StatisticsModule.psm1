Set-StrictMode -Version Latest

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

    if (-not $Values -or $Values.Length -eq 0) {
        return $null
    }

    if ($Percentile -lt 0) { $Percentile = 0 }
    if ($Percentile -gt 100) { $Percentile = 100 }

    $sorted = @($Values | Sort-Object)
    $count = $sorted.Count
    if ($count -eq 0) {
        return $null
    }
    if ($count -eq 1) {
        return [double]$sorted[0]
    }

    $position = ($Percentile / 100.0) * ($count - 1)
    $lowerIndex = [math]::Floor($position)
    $upperIndex = [math]::Ceiling($position)

    if ($lowerIndex -lt 0) { $lowerIndex = 0 }
    if ($upperIndex -ge $count) { $upperIndex = $count - 1 }

    if ($lowerIndex -eq $upperIndex) {
        return [double]$sorted[$lowerIndex]
    }

    $lowerValue = [double]$sorted[$lowerIndex]
    $upperValue = [double]$sorted[$upperIndex]
    $fraction = $position - $lowerIndex
    return $lowerValue + (($upperValue - $lowerValue) * $fraction)
}

Export-ModuleMember -Function Get-PercentileValue

