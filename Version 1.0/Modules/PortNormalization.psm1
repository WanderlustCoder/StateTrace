Set-StrictMode -Version Latest

try { TelemetryModule\Import-InterfaceCommon | Out-Null } catch { Write-Verbose "Caught exception in PortNormalization.psm1: $($_.Exception.Message)" }

if (-not (Get-Variable -Scope Script -Name PortSortKeyCache -ErrorAction SilentlyContinue)) {
    try {
        $script:PortSortKeyCache = [System.Collections.Concurrent.ConcurrentDictionary[string,string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    } catch {
        $script:PortSortKeyCache = @{}
    }
}

if (-not (Get-Variable -Scope Script -Name PortSortCacheHits -ErrorAction SilentlyContinue)) {
    $script:PortSortCacheHits = [long]0
}

if (-not (Get-Variable -Scope Script -Name PortSortCacheMisses -ErrorAction SilentlyContinue)) {
    $script:PortSortCacheMisses = [long]0
}

if (-not (Get-Variable -Scope Script -Name PortSortFallbackKey -ErrorAction SilentlyContinue)) {
    try { $script:PortSortFallbackKey = InterfaceCommon\Get-PortSortFallbackKey } catch { $script:PortSortFallbackKey = '99-UNK-99999-99999-99999-99999-99999' }
}

$regexOptionsFallback = [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
if (-not (Get-Variable -Scope Script -Name PortSortRegexOptions -ErrorAction SilentlyContinue)) {
    try {
        $script:PortSortRegexOptions = [System.Text.RegularExpressions.RegexOptions]::Compiled -bor $regexOptionsFallback
    } catch {
        $script:PortSortRegexOptions = $regexOptionsFallback
    }
}

if (-not (Get-Variable -Scope Script -Name PortSortTypeRegex -ErrorAction SilentlyContinue)) {
    try {
        $script:PortSortTypeRegex = [System.Text.RegularExpressions.Regex]::new('^(?<type>[A-Z\-]+)?\s*(?<nums>[\d/.:]+)', $script:PortSortRegexOptions)
    } catch {
        $script:PortSortTypeRegex = [regex]'^(?<type>[A-Z\-]+)?\s*(?<nums>[\d/.:]+)'
    }
}

if (-not (Get-Variable -Scope Script -Name PortSortNumberRegex -ErrorAction SilentlyContinue)) {
    try {
        $script:PortSortNumberRegex = [System.Text.RegularExpressions.Regex]::new('\d+', $script:PortSortRegexOptions)
    } catch {
        $script:PortSortNumberRegex = [regex]'\d+'
    }
}

if (-not (Get-Variable -Scope Script -Name PortSortNormalizationRules -ErrorAction SilentlyContinue)) {
    try {
        $options = $script:PortSortRegexOptions
        $script:PortSortNormalizationRules = @(
            @{ Regex = [System.Text.RegularExpressions.Regex]::new('HUNDRED\s*GIG(?:ABIT\s*ETHERNET|E)?', $options); Replacement = 'HU' },
            @{ Regex = [System.Text.RegularExpressions.Regex]::new('FOUR\s*HUNDRED\s*GIG(?:ABIT\s*ETHERNET|E)?', $options); Replacement = 'TH' },
            @{ Regex = [System.Text.RegularExpressions.Regex]::new('FORTY\s*GIG(?:ABIT\s*ETHERNET|E)?', $options); Replacement = 'FO' },
            @{ Regex = [System.Text.RegularExpressions.Regex]::new('TWENTY\s*FIVE\s*GIG(?:ABIT\s*ETHERNET|E|IGE)?', $options); Replacement = 'TW' },
            @{ Regex = [System.Text.RegularExpressions.Regex]::new('TEN\s*GIG(?:ABIT\s*ETHERNET|E)?', $options); Replacement = 'TE' },
            @{ Regex = [System.Text.RegularExpressions.Regex]::new('GIGABIT\s*ETHERNET', $options); Replacement = 'GI' },
            @{ Regex = [System.Text.RegularExpressions.Regex]::new('FAST\s*ETHERNET', $options); Replacement = 'FA' },
            @{ Regex = [System.Text.RegularExpressions.Regex]::new('ETHERNET', $options); Replacement = 'ET' },
            @{ Regex = [System.Text.RegularExpressions.Regex]::new('MANAGEMENT', $options); Replacement = 'MGMT' },
            @{ Regex = [System.Text.RegularExpressions.Regex]::new('PORT-?\s*CHANNEL', $options); Replacement = 'PO' },
            @{ Regex = [System.Text.RegularExpressions.Regex]::new('LOOPBACK', $options); Replacement = 'LO' },
            @{ Regex = [System.Text.RegularExpressions.Regex]::new('VLAN', $options); Replacement = 'VL' }
        )
    } catch {
        $script:PortSortNormalizationRules = @()
    }
}

if (-not (Get-Variable -Scope Script -Name PortSortTypeWeights -ErrorAction SilentlyContinue)) {
    try {
        $weights = [System.Collections.Generic.Dictionary[string,int]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $weights['MGMT'] = 5
        $weights['PO'] = 10
        $weights['TH'] = 22
        $weights['HU'] = 23
        $weights['FO'] = 24
        $weights['TE'] = 25
        $weights['TW'] = 26
        $weights['ET'] = 30
        $weights['GI'] = 40
        $weights['FA'] = 50
        $weights['VL'] = 97
        $weights['LO'] = 98
        $script:PortSortTypeWeights = $weights
    } catch {
        $script:PortSortTypeWeights = @{
            MGMT = 5
            PO   = 10
            TH   = 22
            HU   = 23
            FO   = 24
            TE   = 25
            TW   = 26
            ET   = 30
            GI   = 40
            FA   = 50
            VL   = 97
            LO   = 98
        }
    }
}

function Get-PortSortKey {
    param([Parameter(Mandatory)][string]$Port)
    if ([string]::IsNullOrWhiteSpace($Port)) { return $script:PortSortFallbackKey }

    $normalized = $Port.Trim()
    if ([string]::IsNullOrWhiteSpace($normalized)) { return $script:PortSortFallbackKey }
    $cacheKey = $normalized.ToUpperInvariant()

    $cacheInstance = $script:PortSortKeyCache
    if ($cacheInstance -is [System.Collections.Concurrent.ConcurrentDictionary[string,string]]) {
        $cachedValue = $null
        if ($cacheInstance.TryGetValue($cacheKey, [ref]$cachedValue)) {
            [System.Threading.Interlocked]::Increment([ref]$script:PortSortCacheHits) | Out-Null
            return $cachedValue
        }
    } elseif ($cacheInstance -is [hashtable]) {
        if ($cacheInstance.ContainsKey($cacheKey)) {
            [System.Threading.Interlocked]::Increment([ref]$script:PortSortCacheHits) | Out-Null
            return $cacheInstance[$cacheKey]
        }
    }

    $u = $cacheKey
    $normalizationRules = $script:PortSortNormalizationRules
    if ($normalizationRules -and $normalizationRules.Count -gt 0) {
        foreach ($rule in $normalizationRules) {
            try {
                $u = $rule.Regex.Replace($u, $rule.Replacement)
            } catch {
                # Leave $u unchanged if the compiled regex throws so legacy replacements still apply.
            }
        }
    } else {
        $u = $u -replace 'HUNDRED\s*GIG(?:ABIT\s*ETHERNET|E)?','HU'
        $u = $u -replace 'FOUR\s*HUNDRED\s*GIG(?:ABIT\s*ETHERNET|E)?','TH'
        $u = $u -replace 'FORTY\s*GIG(?:ABIT\s*ETHERNET|E)?','FO'
        $u = $u -replace 'TWENTY\s*FIVE\s*GIG(?:ABIT\s*ETHERNET|E|IGE)?','TW'
        $u = $u -replace 'TEN\s*GIG(?:ABIT\s*ETHERNET|E)?','TE'
        $u = $u -replace 'GIGABIT\s*ETHERNET','GI'
        $u = $u -replace 'FAST\s*ETHERNET','FA'
        $u = $u -replace 'ETHERNET','ET'
        $u = $u -replace 'MANAGEMENT','MGMT'
        $u = $u -replace 'PORT-?\s*CHANNEL','PO'
        $u = $u -replace 'LOOPBACK','LO'
        $u = $u -replace 'VLAN','VL'
    }

    $typeRegex = $script:PortSortTypeRegex
    if ($typeRegex) {
        try {
            $m = $typeRegex.Match($u)
        } catch {
            $m = [regex]::Match($u, '^(?<type>[A-Z\-]+)?\s*(?<nums>[\d/.:]+)')
        }
    } else {
        $m = [regex]::Match($u, '^(?<type>[A-Z\-]+)?\s*(?<nums>[\d/.:]+)')
    }

    if ($m.Success -and $m.Groups['type'].Value) {
        $type = $m.Groups['type'].Value
        $numsPart = $m.Groups['nums'].Value
    } else {
        $type = if ($u -match '^\d') { 'ET' } else { $u -creplace '[^A-Z]','' }
        $numsPart = $u
    }

    $w = 60
    $weights = $script:PortSortTypeWeights
    if ($weights -is [System.Collections.Generic.Dictionary[string,int]]) {
        $weightCandidate = 0
        if ($weights.TryGetValue($type, [ref]$weightCandidate)) {
            $w = $weightCandidate
        }
    } elseif ($weights -is [hashtable]) {
        if ($weights.ContainsKey($type)) {
            $w = [int]$weights[$type]
        }
    }

    $numberRegex = $script:PortSortNumberRegex
    if ($numberRegex) {
        try {
            $matchesInts = $numberRegex.Matches($numsPart)
        } catch {
            $matchesInts = [regex]::Matches($numsPart, '\d+')
        }
    } else {
        $matchesInts = [regex]::Matches($numsPart, '\d+')
    }

    $matchCount = if ($matchesInts) { $matchesInts.Count } else { 0 }
    $segmentLength = if ($matchCount -ge 4) { $matchCount } else { 4 }
    $segmentCount = if ($segmentLength -gt 6) { 6 } else { $segmentLength }
    $segments = [string[]]::new($segmentCount)
    $valuesToCopy = [Math]::Min($matchCount, $segmentCount)
    for ($i = 0; $i -lt $valuesToCopy; $i++) {
        $segments[$i] = ([long]$matchesInts[$i].Value).ToString('00000')
    }
    for ($i = $valuesToCopy; $i -lt $segmentCount; $i++) {
        $segments[$i] = '00000'
    }

    $result = ('{0:00}-{1}-{2}' -f $w, $type, ([string]::Join('-', $segments)))

    if ($cacheInstance -is [System.Collections.Concurrent.ConcurrentDictionary[string,string]]) {
        if ($cacheInstance.TryAdd($cacheKey, $result)) {
            [System.Threading.Interlocked]::Increment([ref]$script:PortSortCacheMisses) | Out-Null
            return $result
        }

        $concurrentLookup = $null
        if ($cacheInstance.TryGetValue($cacheKey, [ref]$concurrentLookup)) {
            [System.Threading.Interlocked]::Increment([ref]$script:PortSortCacheHits) | Out-Null
            return $concurrentLookup
        }
    } elseif ($cacheInstance -is [hashtable]) {
        if (-not $cacheInstance.ContainsKey($cacheKey)) {
            $cacheInstance[$cacheKey] = $result
            [System.Threading.Interlocked]::Increment([ref]$script:PortSortCacheMisses) | Out-Null
            return $result
        }
        [System.Threading.Interlocked]::Increment([ref]$script:PortSortCacheHits) | Out-Null
        return $cacheInstance[$cacheKey]
    }

    [System.Threading.Interlocked]::Increment([ref]$script:PortSortCacheMisses) | Out-Null
    return $result
}

function Get-PortSortCacheStatistics {
    [CmdletBinding()]
    param()

    $cacheInstance = $script:PortSortKeyCache
    $entryCount = 0
    $cacheType = ''
    if ($cacheInstance) {
        try { $cacheType = $cacheInstance.GetType().FullName } catch { $cacheType = '' }
        if ($cacheInstance -is [System.Collections.ICollection]) {
            try { $entryCount = [int]$cacheInstance.Count } catch { $entryCount = 0 }
        }
    }

    return [pscustomobject]@{
        Hits       = [long]$script:PortSortCacheHits
        Misses     = [long]$script:PortSortCacheMisses
        EntryCount = [long]$entryCount
        Fallback   = $script:PortSortFallbackKey
        CacheType  = $cacheType
        Count      = [long]$entryCount
    }
}

function Reset-PortSortCache {
    [CmdletBinding()]
    param()

    try {
        $script:PortSortKeyCache = [System.Collections.Concurrent.ConcurrentDictionary[string,string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    } catch {
        $script:PortSortKeyCache = @{}
    }

    $script:PortSortCacheHits = 0
    $script:PortSortCacheMisses = 0

    return Get-PortSortCacheStatistics
}

Export-ModuleMember -Function Get-PortSortKey, Get-PortSortCacheStatistics, Reset-PortSortCache
