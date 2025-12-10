Set-StrictMode -Version Latest

function Invoke-RegexTableParser {
    [CmdletBinding()]
    param(
        [Parameter()][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory)][string]$HeaderPattern,
        [Parameter(Mandatory)][string]$RowPattern,
        [Parameter(Mandatory)][hashtable]$PropertyMap,
        [string]$TerminatorPattern = '^\s*$',
        [switch]$AllowMultipleSections,
        [scriptblock]$PostProcess
    )

    if (-not $Lines) {
        return [System.Collections.Generic.List[object]]::new()
    }

    $headerRegex = [regex]::new($HeaderPattern)
    $rowRegex    = [regex]::new($RowPattern)
    $terminatorRegex = $null
    if ($TerminatorPattern -and $TerminatorPattern -ne '') {
        $terminatorRegex = [regex]::new($TerminatorPattern)
    }

    $results = [System.Collections.Generic.List[object]]::new()
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

function Get-HostnameFromPrompt {
    [CmdletBinding()]
    param(
        [Parameter()][AllowEmptyString()][string[]]$Lines,
        [string]$RunningConfigPattern
    )

    if (-not $Lines) { return $null }

    $promptRegex = [regex]'^(?:SSH@)?(?<host>[^(#>\s]+)(?:\([^)]*\))?[#>]'
    foreach ($line in $Lines) {
        $text = if ($null -ne $line) { [string]$line } else { '' }
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $m = $promptRegex.Match($text)
        if ($m.Success) {
            $value = $m.Groups['host'].Value
            if (-not [string]::IsNullOrWhiteSpace($value)) { return $value.Trim() }
        }
    }

    if ($RunningConfigPattern) {
        $configRegex = [regex]$RunningConfigPattern
        foreach ($line in $Lines) {
            $text = if ($null -ne $line) { [string]$line } else { '' }
            if ([string]::IsNullOrWhiteSpace($text)) { continue }
            $m = $configRegex.Match($text)
            if ($m.Success -and $m.Groups.Count -ge 2) {
                $value = $m.Groups[1].Value
                if (-not [string]::IsNullOrWhiteSpace($value)) { return $value.Trim() }
            }
        }
    }

    return $null
}

function ConvertTo-ShortPortName {
    [CmdletBinding()]
    param([string]$Port)

    if ([string]::IsNullOrWhiteSpace($Port)) { return $Port }
    $normalized = $Port.Trim()
    $normalized = $normalized -replace '\s+', ''

    switch -Regex ($normalized) {
        '^(GigabitEthernet)(.+)$'        { return 'Gi' + $matches[2] }
        '^(FastEthernet)(.+)$'           { return 'Fa' + $matches[2] }
        '^(TenGigabitEthernet)(.+)$'     { return 'Te' + $matches[2] }
        '^(HundredGigabitEthernet)(.+)$' { return 'Hu' + $matches[2] }
        '^(Ethernet)(.+)$'               { return 'Et' + $matches[2] }
        Default                          { return $normalized }
    }
}

function Get-UptimeFromLines {
    [CmdletBinding()]
    param(
        [Parameter()][AllowEmptyString()][string[]]$Lines,
        [string[]]$Patterns = @('(?i)uptime\s+is\s+(.+)$', '(?i)uptime:\s*(.+)$')
    )

    if (-not $Lines) { return $null }
    if (-not $Patterns -or $Patterns.Count -eq 0) { return $null }

    $regexes = @()
    foreach ($p in $Patterns) {
        try { $regexes += [regex]::new($p) } catch { }
    }
    if ($regexes.Count -eq 0) { return $null }

    foreach ($line in $Lines) {
        $text = if ($null -ne $line) { [string]$line } else { '' }
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        foreach ($re in $regexes) {
            $m = $re.Match($text)
            if ($m.Success -and $m.Groups.Count -ge 2) {
                $value = $m.Groups[1].Value
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    return $value.Trim()
                }
            }
        }
    }

    return $null
}

function ConvertFrom-MacTableRegex {
    [CmdletBinding()]
    param(
        [Parameter()][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory)][string]$HeaderPattern,
        [Parameter(Mandatory)][string]$RowPattern,
        [Parameter(Mandatory)][int]$VlanGroup,
        [Parameter(Mandatory)][int]$MacGroup,
        [Parameter(Mandatory)][int]$PortGroup,
        [scriptblock]$PortTransform
    )

    $propertyMap = [ordered]@{
        VLAN = $VlanGroup
        MAC  = $MacGroup
        Port = $PortGroup
    }
    $postProcess = $null
    if ($PortTransform) {
        $postProcess = {
            param($obj, $match)
            $obj.Port = & $PortTransform $obj.Port
            return $obj
        }
    }
    $parsed = Invoke-RegexTableParser -Lines $Lines -HeaderPattern $HeaderPattern -RowPattern $RowPattern -PropertyMap $propertyMap -PostProcess $postProcess
    # Normalize any longer Ethernet prefix down to Et when users omit a custom transform.
    foreach ($row in $parsed) {
        if ($row.Port -and -not $PortTransform) {
            $row.Port = ConvertTo-ShortPortName -Port $row.Port
        }
    }
    return $parsed
}

# Backwards compatibility wrapper to ease migration off the unapproved verb.
function Parse-MacTableFromRegex {
    [CmdletBinding()]
    param(
        [Parameter()][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory)][string]$HeaderPattern,
        [Parameter(Mandatory)][string]$RowPattern,
        [Parameter(Mandatory)][int]$VlanGroup,
        [Parameter(Mandatory)][int]$MacGroup,
        [Parameter(Mandatory)][int]$PortGroup,
        [scriptblock]$PortTransform
    )

    return ConvertFrom-MacTableRegex @PSBoundParameters
}

Export-ModuleMember -Function Invoke-RegexTableParser, Get-HostnameFromPrompt, ConvertTo-ShortPortName, Get-UptimeFromLines, ConvertFrom-MacTableRegex
