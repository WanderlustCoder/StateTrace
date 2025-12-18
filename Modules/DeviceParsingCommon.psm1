Set-StrictMode -Version Latest

if (-not (Get-Variable -Name DeviceParsingRegexCache -Scope Script -ErrorAction SilentlyContinue)) {
    $script:DeviceParsingRegexCache = [System.Collections.Concurrent.ConcurrentDictionary[string,System.Text.RegularExpressions.Regex]]::new([System.StringComparer]::Ordinal)
}
if (-not (Get-Variable -Name RegexCacheKeySeparator -Scope Script -ErrorAction SilentlyContinue)) {
    $script:RegexCacheKeySeparator = [char]0x1F
}

function script:Get-CachedRegex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Pattern,
        [System.Text.RegularExpressions.RegexOptions]$Options = [System.Text.RegularExpressions.RegexOptions]::Compiled
    )

    $key = "$([int]$Options)$($script:RegexCacheKeySeparator)$Pattern"
    $cached = $null
    if ($script:DeviceParsingRegexCache.TryGetValue($key, [ref]$cached)) {
        return $cached
    }

    $regex = [regex]::new($Pattern, $Options)
    $script:DeviceParsingRegexCache[$key] = $regex
    return $regex
}

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

    $headerRegex = script:Get-CachedRegex -Pattern $HeaderPattern
    $rowRegex    = script:Get-CachedRegex -Pattern $RowPattern
    $terminatorRegex = $null
    if ($TerminatorPattern -and $TerminatorPattern -ne '') {
        $terminatorRegex = script:Get-CachedRegex -Pattern $TerminatorPattern
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

    $promptRegex = script:Get-CachedRegex -Pattern '^(?:SSH@)?(?<host>[^(#>\s]+)(?:\([^)]*\))?[#>]'
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
        $configRegex = script:Get-CachedRegex -Pattern $RunningConfigPattern
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

    $regexes = [System.Collections.Generic.List[regex]]::new()
    foreach ($p in $Patterns) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        try {
            $re = script:Get-CachedRegex -Pattern $p
            if ($re) { [void]$regexes.Add($re) }
        } catch { }
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

function Get-InterfaceConfigBlocks {
    [CmdletBinding()]
    param(
        [Parameter()][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory)][string]$InterfacePattern,
        [string[]]$StopPatterns = @('^interface', '^!'),
        [switch]$StopOnBlankLine
    )

    if (-not $Lines) { return ,@() }

    $interfaceRegex = $null
    try {
        $interfaceRegex = script:Get-CachedRegex -Pattern $InterfacePattern -Options ([System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Compiled)
    } catch {
        return ,@()
    }

    $stopRegexes = [System.Collections.Generic.List[regex]]::new()
    foreach ($p in $StopPatterns) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        try {
            $re = script:Get-CachedRegex -Pattern $p -Options ([System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Compiled)
            if ($re) { [void]$stopRegexes.Add($re) }
        } catch { }
    }

    $blocks = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        $text = if ($null -ne $line) { [string]$line } else { '' }
        if ([string]::IsNullOrWhiteSpace($text)) { continue }

        $match = $interfaceRegex.Match($text)
        if (-not $match.Success -or $match.Groups.Count -lt 2) { continue }

        $name = ('' + $match.Groups[1].Value).Trim()
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $blockLines = [System.Collections.Generic.List[string]]::new()
        [void]$blockLines.Add($text)

        $j = $i + 1
        while ($j -lt $Lines.Count) {
            $nextLine = $Lines[$j]
            $nextText = if ($null -ne $nextLine) { [string]$nextLine } else { '' }

            if ($StopOnBlankLine -and [string]::IsNullOrWhiteSpace($nextText)) {
                break
            }

            $shouldStop = $false
            foreach ($re in $stopRegexes) {
                if ($re.IsMatch($nextText)) {
                    $shouldStop = $true
                    break
                }
            }
            if ($shouldStop) { break }

            [void]$blockLines.Add($nextText)
            $j++
        }

        [void]$blocks.Add([PSCustomObject]@{
            Name  = $name
            Lines = $blockLines.ToArray()
        })
        $i = $j - 1
    }

    return ,$blocks.ToArray()
}

Export-ModuleMember -Function Invoke-RegexTableParser, Get-HostnameFromPrompt, ConvertTo-ShortPortName, Get-UptimeFromLines, ConvertFrom-MacTableRegex, Get-InterfaceConfigBlocks
