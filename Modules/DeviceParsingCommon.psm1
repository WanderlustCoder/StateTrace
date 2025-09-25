Set-StrictMode -Version Latest

function Invoke-RegexTableParser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory)][string]$HeaderPattern,
        [Parameter(Mandatory)][string]$RowPattern,
        [Parameter(Mandatory)][hashtable]$PropertyMap,
        [string]$TerminatorPattern = '^\s*$',
        [switch]$AllowMultipleSections,
        [scriptblock]$PostProcess
    )

    if (-not $Lines) {
        return (New-Object 'System.Collections.Generic.List[object]')
    }

    $headerRegex = [regex]::new($HeaderPattern)
    $rowRegex    = [regex]::new($RowPattern)
    $terminatorRegex = $null
    if ($TerminatorPattern -and $TerminatorPattern -ne '') {
        $terminatorRegex = [regex]::new($TerminatorPattern)
    }

    $results = New-Object 'System.Collections.Generic.List[object]'
    $parsing = $false

    foreach ($line in $Lines) {
        $text = if ($null -ne $line) { [string]$line } else { '' }
        if (-not $parsing) {
            if ($headerRegex.IsMatch($text)) {
                $parsing = $true
                continue
            }
            else {
                continue
            }
        }

        if ($terminatorRegex -and $terminatorRegex.IsMatch($text)) {
            if ($AllowMultipleSections) {
                $parsing = $false
                continue
            }
            break
        }

        if ([string]::IsNullOrWhiteSpace($text)) {
            continue
        }

        $match = $rowRegex.Match($text)
        if (-not $match.Success) {
            continue
        }

        $ordered = [ordered]@{}
        foreach ($entry in $PropertyMap.GetEnumerator()) {
            $propName = [string]$entry.Key
            $mapValue = $entry.Value
            $value = $null

            if ($mapValue -is [scriptblock]) {
                $value = & $mapValue $match
            }
            elseif ($mapValue -is [int]) {
                if ($mapValue -ge 0 -and $mapValue -lt $match.Groups.Count) {
                    $group = $match.Groups[$mapValue]
                    if ($group.Success) { $value = $group.Value }
                }
            }
            elseif ($mapValue -is [string]) {
                $group = $match.Groups[$mapValue]
                if ($group -and $group.Success) { $value = $group.Value }
            }
            else {
                $value = $mapValue
            }

            if ($value -is [string]) {
                $value = $value.Trim()
            }

            $ordered[$propName] = $value
        }

        $obj = [PSCustomObject]$ordered
        if ($PostProcess) {
            $processed = & $PostProcess $obj $match
            if ($null -eq $processed) { continue }
            $obj = $processed
        }

        [void]$results.Add($obj)
    }

    return $results
}

Export-ModuleMember -Function Invoke-RegexTableParser
