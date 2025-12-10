# .SYNOPSIS

Set-StrictMode -Version Latest

try {
    if (-not (ViewStateService\Import-ViewStateServiceModule)) {
        Write-Verbose "[InterfaceModule] ViewStateService not available"
    }
} catch {
    Write-Verbose "[InterfaceModule] Failed to import ViewStateService: $($_.Exception.Message)"
}

try { TelemetryModule\Import-InterfaceCommon | Out-Null } catch { }

$script:lastTemplateVendor = 'default'
$script:TemplateThemeHandlerRegistered = $false

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

if (-not ('StateTrace.Models.InterfacePortRecord' -as [type])) {
    Add-Type -TypeDefinition @"
namespace StateTrace.Models
{
    public sealed class InterfacePortRecord
    {
        public string Hostname { get; set; }
        public string Port { get; set; }
        public string PortSort { get; set; }
        public string Name { get; set; }
        public string Status { get; set; }
        public string VLAN { get; set; }
        public string Duplex { get; set; }
        public string Speed { get; set; }
        public string Type { get; set; }
        public string LearnedMACs { get; set; }
        public string AuthState { get; set; }
        public string AuthMode { get; set; }
        public string AuthClientMAC { get; set; }
        public string Site { get; set; }
        public string Building { get; set; }
        public string Room { get; set; }
        public string Zone { get; set; }
        public string AuthTemplate { get; set; }
        public string Config { get; set; }
        public string ConfigStatus { get; set; }
        public string PortColor { get; set; }
        public string ToolTip { get; set; }
        public string CacheSignature { get; set; }
        public bool IsSelected { get; set; }
    }

    public sealed class InterfaceTemplateHint
    {
        public string PortColor { get; set; }
        public string ConfigStatus { get; set; }
        public bool HasTemplate { get; set; }
    }
}
"@ -Language CSharp
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


# Ensure that the debounce timer variable exists in script scope.  Under
if (-not (Get-Variable -Name InterfacesFilterTimer -Scope Script -ErrorAction SilentlyContinue)) {
    $script:InterfacesFilterTimer = $null
}

# Helper: Gather selected or checked interface rows using typed lists.  This function
function Get-SelectedInterfaceRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Controls.DataGrid]$Grid
    )
    # Collect rows explicitly selected in the grid
    $selected = [System.Collections.Generic.List[object]]::new()
    foreach ($r in @($Grid.SelectedItems)) {
        [void]$selected.Add($r)
    }
    # Collect rows that have the IsSelected checkbox set
    $checked = [System.Collections.Generic.List[object]]::new()
    if ($Grid.ItemsSource -is [System.Collections.IEnumerable]) {
        foreach ($it in $Grid.ItemsSource) {
            $prop = $it.PSObject.Properties['IsSelected']
            if ($prop -and $prop.Value) {
                [void]$checked.Add($it)
            }
        }
    }
    # Prefer checked rows when present
    if ($checked.Count -gt 0) { return $checked }
    return $selected
}

# Define a default path to the Interfaces view XAML.  This allows the
$script:InterfacesViewXamlDefault = Join-Path $PSScriptRoot '..\Views\InterfacesView.xaml'


if (-not (Get-Variable -Name InterfaceDataDir -Scope Script -ErrorAction SilentlyContinue)) {
    try {
        $parentDir = Split-Path -Parent $PSScriptRoot
        $script:InterfaceDataDir = [System.IO.Path]::GetFullPath((Join-Path $parentDir 'Data'))
    } catch {
        $script:InterfaceDataDir = Join-Path $PSScriptRoot '..\Data'
    }
}

function Get-InterfaceSiteCode {
    param([string]$Hostname)
    if (-not $Hostname) { return 'Unknown' }
    if ($Hostname -match '^(?<site>[^-]+)-') { return $matches['site'] }
    return $Hostname
}

function Resolve-InterfaceDatabasePath {
    param([Parameter()][AllowEmptyString()][string]$Hostname)
    $site = Get-InterfaceSiteCode $Hostname
    try {
        return DeviceRepositoryModule\Get-DbPathForSite -Site $site
    } catch {
        return (Join-Path $script:InterfaceDataDir ("{0}.accdb" -f $site))
    }
}

function Ensure-DatabaseModule {
    [CmdletBinding()]
    param()
    try {
        if (-not (Get-Module -Name DatabaseModule)) {
            $dbModulePath = Join-Path $PSScriptRoot 'DatabaseModule.psm1'
            if (Test-Path $dbModulePath) {
                Import-Module $dbModulePath -Force -Global -ErrorAction SilentlyContinue | Out-Null
            }
        }
    } catch {
        # Swallow import errors; callers handle missing cmdlets gracefully.
    }
}

function Get-PropertyStringValue {
    param(
        [Parameter(Mandatory)][object]$InputObject,
        [Parameter(Mandatory)][string[]]$PropertyNames
    )

    try {
        if (Get-Command -Name 'InterfaceCommon\Get-StringPropertyValue' -ErrorAction SilentlyContinue) {
            return InterfaceCommon\Get-StringPropertyValue @PSBoundParameters
        }
    } catch { }

    foreach ($name in $PropertyNames) {
        try {
            $prop = $InputObject.PSObject.Properties[$name]
            if ($prop -and $null -ne $prop.Value) {
                $val = '' + $prop.Value
                if (-not [string]::IsNullOrWhiteSpace($val)) {
                    return $val
                }
            }
        } catch {
            continue
        }
    }

    return ''
}
function Set-TemplateDropdownBrush {
    param([string]$Vendor)
    if ([string]::IsNullOrWhiteSpace($Vendor)) { $Vendor = 'default' }
    $key = 'Theme.Text.Primary'
    switch ($Vendor.ToLowerInvariant()) {
        'cisco'   { $key = 'Theme.Vendor.Cisco' }
        'brocade' { $key = 'Theme.Vendor.Brocade' }
        'arista'  { $key = 'Theme.Vendor.Arista' }
        default     { $key = 'Theme.Text.Primary' }
    }
    $brush = $null
    try {
        $brush = Get-ThemeBrush -Key $key
    } catch {
        Write-Verbose "[Interfaces] Failed to resolve theme brush: $($_.Exception.Message)"
    }
    if (-not $brush) { $brush = [System.Windows.Media.Brushes]::Black }
    if ($global:templateDropdown) {
        try { $global:templateDropdown.Foreground = $brush } catch {}
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

function Get-InterfaceHostnames {
    # .SYNOPSIS

    [CmdletBinding()]
    param()
    return DeviceCatalogModule\Get-InterfaceHostnames @PSBoundParameters
}

function New-InterfaceObjectsFromDbRow {
    [CmdletBinding()]
    param(
        # Accept a null or empty Data argument.  When $Data is null due to missing
        # interface records in the log or database, return an empty list rather
        # than throwing a binding error.  Previously this parameter was
        # mandatory, which caused an error when logs contained no interface
        # information.  Making it optional allows the function to be called
        # safely in those situations.
        [object]$Data = $null,
        [Parameter(Mandatory)][string]$Hostname,
        [string]$TemplatesPath = (Join-Path $PSScriptRoot '..\Templates')
    )
    Ensure-DatabaseModule
    # Resolve the per-site database path for this host.  This allows the
    # module to query the correct database when multiple site databases
    # exist.  Do not rely on a global database path.
    $dbPath = Resolve-InterfaceDatabasePath $Hostname
    # Escape the hostname once for reuse in SQL queries.  Doubling single quotes
    $escHost = $Hostname -replace "'", "''"

    # Determine vendor (Cisco vs Brocade) and global auth block using any joined
    # If no data was provided, return an empty array immediately.  This
    # prevents downstream logic from attempting to access properties on a
    # null reference and avoids binding errors at the caller.
    if (-not $Data) { return @() }

    $vendor = 'Cisco'
    $authBlockLines = @()
    $firstRow = $null
    # Try to extract a representative row from the provided data
    try {
        $rows = DatabaseModule\ConvertTo-DbRowList -Data $Data
        if ($rows.Count -gt 0) { $firstRow = $rows[0] }
    } catch {}
    # Attempt to determine vendor from joined Make column
    try {
        # Check if the first row exposes a 'Make' property.  Avoid specifying
        if ($firstRow -and ($firstRow | Get-Member -Name 'Make' -ErrorAction SilentlyContinue)) {
            $mk = '' + $firstRow.Make
            if ($mk -match '(?i)brocade') { $vendor = 'Brocade' }
        }
    } catch {}
    # Fallback to query DeviceSummary if vendor still Cisco
    if ($vendor -eq 'Cisco') {
        try {
            $mkDt = Invoke-DbQuery -DatabasePath $dbPath -Sql "SELECT Make FROM DeviceSummary WHERE Hostname = '$escHost'"
            if ($mkDt) {
                $mkRows = DatabaseModule\ConvertTo-DbRowList -Data $mkDt
                if ($mkRows.Count -gt 0) {
                    $mk = '' + $mkRows[0].Make
                    if ($mk -match '(?i)brocade') { $vendor = 'Brocade' }
                }
            }
        } catch {}
    }
    # For Brocade devices, try to fetch the AuthBlock from the joined column; fallback to DB
    if ($vendor -eq 'Brocade') {
        $abText = $null
        try {
            # Check if the first row exposes an 'AuthBlock' property without constraining MemberType
        if ($firstRow -and ($firstRow | Get-Member -Name 'AuthBlock' -ErrorAction SilentlyContinue)) {
            $abText = '' + $firstRow.AuthBlock
        }
    } catch {}
    if (-not $abText) {
        try {
            $abDt = Invoke-DbQuery -DatabasePath $dbPath -Sql "SELECT AuthBlock FROM DeviceSummary WHERE Hostname = '$escHost'"
            if ($abDt) {
                $abRows = DatabaseModule\ConvertTo-DbRowList -Data $abDt
                if ($abRows.Count -gt 0) {
                    try { $abText = '' + $abRows[0].AuthBlock } catch { }
                }
            }
        } catch {}
    }
        if ($abText) {
            # Split into non-empty trimmed lines.  Use a typed list instead of ForEach-Object to
            # avoid pipeline overhead when processing large authentication blocks.
            $__tmpLines = $abText -split "`r?`n"
            $__list = [System.Collections.Generic.List[string]]::new()
            foreach ($ln in $__tmpLines) {
                $s = ('' + $ln).Trim()
                if ($s -ne '') { [void]$__list.Add($s) }
            }
            $authBlockLines = $__list.ToArray()
        }
    }
    # Retrieve compliance templates for this vendor.  Avoid repeatedly reading
    # Retrieve templates via TemplatesModule so caching stays centralized and per-vendor lookups stay consistent.
    # The module caches and normalizes names/aliases for downstream dictionary access.
    $templates = @()
    $templatesByName = $null
    try {
        $templateData = TemplatesModule\Get-ConfigurationTemplateData -Vendor $vendor -TemplatesPath $TemplatesPath
        if ($templateData) {
            $templates = $templateData.Templates
            $templatesByName = $templateData.Lookup
        }
    } catch {
        $templates = @()
        $templatesByName = $null
    }
    # Normalise $Data into an enumerable collection of rows.  Support DataTable,
    $rows = DatabaseModule\ConvertTo-DbRowList -Data $Data
    if (-not $rows -or $rows.Count -eq 0) { return @() }
    # Use a strongly typed List[object] instead of a PowerShell array.  Using
    $resultList = [System.Collections.Generic.List[object]]::new()

    # Precompute a lookup table for compliance templates when available.  When
    $templateLookup = if ($templatesByName) {
        $templatesByName
    } else {
        New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
    }
    $templateHintCache = New-Object 'System.Collections.Generic.Dictionary[string,StateTrace.Models.InterfaceTemplateHint]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $rows) {
        if (-not $row) { continue }
        # Safely extract fields; some properties may not exist on all row types.
        $authTemplate = $null
        if ($row.PSObject.Properties['AuthTemplate']) { $authTemplate = '' + $row.AuthTemplate }
        $cfg          = $null
        if ($row.PSObject.Properties['Config'])       { $cfg = '' + $row.Config }
        $existingTip  = ''
        if ($row.PSObject.Properties['ToolTip'] -and $row.ToolTip) {
            $existingTip = ('' + $row.ToolTip).TrimEnd()
        }
        # Determine the base tooltip: use existing tooltip when present; otherwise synthesise from AuthTemplate and Config.
        $toolTipCore = $existingTip
        if (-not $toolTipCore) {
            if ($cfg -and $cfg.Trim() -ne '') {
                $toolTipCore = "AuthTemplate: $authTemplate`r`n`r`n$cfg"
            } elseif ($authTemplate) {
                $toolTipCore = "AuthTemplate: $authTemplate"
            } else {
                $toolTipCore = ''
            }
        }
        # Determine PortColor and ConfigStatus by combining row values with template defaults.
        $portColorVal = $null
        $cfgStatusVal = $null
        $hasPortColor = $false
        $hasConfigStatus = $false
        if ($row.PSObject.Properties['PortColor'] -and $row.PortColor) {
            $portColorVal = '' + $row.PortColor
            if (-not [string]::IsNullOrWhiteSpace($portColorVal)) {
                $hasPortColor = $true
            }
        }
        if ($row.PSObject.Properties['ConfigStatus'] -and $row.ConfigStatus) {
            $cfgStatusVal = '' + $row.ConfigStatus
            if (-not [string]::IsNullOrWhiteSpace($cfgStatusVal)) {
                $hasConfigStatus = $true
            }
        }
        # If no explicit values were provided, look up the template colour and status.
        if (-not $hasPortColor -or -not $hasConfigStatus) {
            if ([string]::IsNullOrWhiteSpace($authTemplate)) {
                if (-not $hasPortColor) { $portColorVal = 'Gray' }
                if (-not $hasConfigStatus) { $cfgStatusVal = 'Unknown' }
            } else {
                $hint = $null
                if (-not $templateHintCache.TryGetValue($authTemplate, [ref]$hint)) {
                    $hint = [StateTrace.Models.InterfaceTemplateHint]::new()
                    $match = $null
                    if ($templateLookup -and $templateLookup.TryGetValue($authTemplate, [ref]$match)) {
                        $colorFromTemplate = 'Gray'
                        if ($match) {
                            try {
                                $colorProp = $match.PSObject.Properties['color']
                                if ($colorProp -and $colorProp.Value) { $colorFromTemplate = '' + $colorProp.Value }
                            } catch {
                                $colorFromTemplate = 'Gray'
                            }
                        }
                        $hint.PortColor = $colorFromTemplate
                        $hint.ConfigStatus = 'Match'
                        $hint.HasTemplate = $true
                    } else {
                        $hint.PortColor = 'Gray'
                        $hint.ConfigStatus = 'Mismatch'
                        $hint.HasTemplate = $false
                    }
                    $templateHintCache[$authTemplate] = $hint
                }
                if (-not $hasPortColor) { $portColorVal = $hint.PortColor }
                if (-not $hasConfigStatus) { $cfgStatusVal = $hint.ConfigStatus }
            }
        }
        # Append global authentication block lines to the tooltip for Brocade devices.
        $finalTip = $toolTipCore
        if ($vendor -eq 'Brocade' -and $authBlockLines.Count -gt 0 -and ($finalTip -notmatch '(?i)GLOBAL AUTH BLOCK')) {
            if ($finalTip -and $finalTip.Trim() -ne '') {
                $finalTip = $finalTip.TrimEnd() + "`r`n`r`n! GLOBAL AUTH BLOCK`r`n" + ($authBlockLines -join "`r`n")
            } else {
                $finalTip = "! GLOBAL AUTH BLOCK`r`n" + ($authBlockLines -join "`r`n")
            }
        }
        # Build the PSCustomObject for this interface.  Use the provided Hostname for all entries.
        $portValue = if ($row.PSObject.Properties['Port']) { '' + $row.Port } else { $null }
        $portSortKey = if ($portValue) { Get-PortSortKey -Port $portValue } else { $script:PortSortFallbackKey }

        $record = [StateTrace.Models.InterfacePortRecord]::new()
        $record.Hostname = $Hostname
        $record.Port = $portValue
        $record.PortSort = $portSortKey
        $record.Name = Get-PropertyStringValue -InputObject $row -PropertyNames @('Name')
        $record.Status = Get-PropertyStringValue -InputObject $row -PropertyNames @('Status')
        $record.VLAN = Get-PropertyStringValue -InputObject $row -PropertyNames @('VLAN')
        $record.Duplex = Get-PropertyStringValue -InputObject $row -PropertyNames @('Duplex')
        $record.Speed = Get-PropertyStringValue -InputObject $row -PropertyNames @('Speed')
        $record.Type = Get-PropertyStringValue -InputObject $row -PropertyNames @('Type')
        $record.LearnedMACs = Get-PropertyStringValue -InputObject $row -PropertyNames @('LearnedMACs')
        $record.AuthState = Get-PropertyStringValue -InputObject $row -PropertyNames @('AuthState')
        $record.AuthMode = Get-PropertyStringValue -InputObject $row -PropertyNames @('AuthMode')
        $record.AuthClientMAC = Get-PropertyStringValue -InputObject $row -PropertyNames @('AuthClientMAC')
        $record.Site = Get-PropertyStringValue -InputObject $row -PropertyNames @('Site')
        $record.Building = Get-PropertyStringValue -InputObject $row -PropertyNames @('Building')
        $record.Room = Get-PropertyStringValue -InputObject $row -PropertyNames @('Room')
        $record.Zone = Get-PropertyStringValue -InputObject $row -PropertyNames @('Zone')
        $record.AuthTemplate = $authTemplate
        $record.Config = $cfg
        $record.ConfigStatus = $cfgStatusVal
        $record.PortColor = $portColorVal
        $record.ToolTip = $finalTip
        $record.IsSelected = $false
        [void]$resultList.Add($record)
    }
    $comparison = [System.Comparison[object]]{
        param($a, $b)
        $keyA = if ($a -and $a.PSObject.Properties['PortSort']) { '' + $a.PortSort } else { $script:PortSortFallbackKey }
        $keyB = if ($b -and $b.PSObject.Properties['PortSort']) { '' + $b.PortSort } else { $script:PortSortFallbackKey }
        return [System.StringComparer]::Ordinal.Compare($keyA, $keyB)
    }
    try { $resultList.Sort($comparison) } catch {}
    return $resultList
}

function Get-InterfaceInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [string]$TemplatesPath = (Join-Path $PSScriptRoot '..\Templates')
    )
    DeviceRepositoryModule\Get-InterfaceInfo @PSBoundParameters
}

function Get-InterfaceList {
    [CmdletBinding()]
    param([Parameter()][AllowEmptyString()][string]$Hostname)

    $targetHost = ('' + $Hostname).Trim()
    if ([string]::IsNullOrWhiteSpace($targetHost)) { return @() }

    try {
        $viewStateModule = Get-Module -Name 'ViewStateService' -ErrorAction SilentlyContinue
        if (-not $viewStateModule) {
            $svcPath = Join-Path $PSScriptRoot 'ViewStateService.psm1'
            if (Test-Path -LiteralPath $svcPath) {
                try {
                    $viewStateModule = Import-Module -Name $svcPath -Force -Global -PassThru
                } catch {
                    Write-Verbose "[InterfaceModule] Importing ViewStateService inside Get-InterfaceList failed: $($_.Exception.Message)"
                }
            }
        }

        if ($viewStateModule) {
            $ports = [System.Collections.Generic.List[string]]::new()

            $site = $null
            $zone = $null
            $building = $null
            $room = $null
            $meta = $null

            try {
                if ($global:DeviceMetadata) {
                    if ($global:DeviceMetadata.ContainsKey($targetHost)) {
                        $meta = $global:DeviceMetadata[$targetHost]
                    } else {
                        foreach ($kv in $global:DeviceMetadata.GetEnumerator()) {
                            if ([System.StringComparer]::OrdinalIgnoreCase.Equals(('' + $kv.Key), $targetHost)) {
                                $meta = $kv.Value
                                break
                            }
                        }
                    }
                }
            } catch {
                $meta = $null
            }

            if ($meta) {
                $metaSite = Get-PropertyStringValue -InputObject $meta -PropertyNames @('Site')
                if (-not [string]::IsNullOrWhiteSpace($metaSite)) { $site = $metaSite }
                $metaZone = Get-PropertyStringValue -InputObject $meta -PropertyNames @('Zone')
                if (-not [string]::IsNullOrWhiteSpace($metaZone)) { $zone = $metaZone }
                $metaBld = Get-PropertyStringValue -InputObject $meta -PropertyNames @('Building')
                if (-not [string]::IsNullOrWhiteSpace($metaBld)) { $building = $metaBld }
                $metaRoom = Get-PropertyStringValue -InputObject $meta -PropertyNames @('Room')
                if (-not [string]::IsNullOrWhiteSpace($metaRoom)) { $room = $metaRoom }
            }

            if ([string]::IsNullOrWhiteSpace($site)) {
                try { $site = DeviceRepositoryModule\Get-SiteFromHostname -Hostname $targetHost } catch { $site = $null }
            }

            if ([string]::IsNullOrWhiteSpace($zone)) {
                try {
                    $parts = $targetHost.Split('-', [System.StringSplitOptions]::RemoveEmptyEntries)
                    if ($parts.Length -ge 2) { $zone = $parts[1] }
                } catch { $zone = $null }
            }

            $zoneSelection = if ([string]::IsNullOrWhiteSpace($zone)) { $null } else { $zone }
            $zoneToLoad = ''
            if ($zoneSelection -and $zoneSelection -ne 'All Zones') { $zoneToLoad = $zoneSelection }

            $interfaces = @()
            try {
                $interfaces = ViewStateService\Get-InterfacesForContext -Site $site -ZoneSelection $zoneSelection -ZoneToLoad $zoneToLoad -Building $building -Room $room
            } catch {
                Write-Verbose "[InterfaceModule] ViewStateService Get-InterfacesForContext failed: $($_.Exception.Message)"
                $interfaces = @()
            }

            foreach ($iface in $interfaces) {
                if (-not $iface) { continue }

                $hostValue = Get-PropertyStringValue -InputObject $iface -PropertyNames @('Hostname', 'HostName', 'Device')

                if ([string]::IsNullOrWhiteSpace($hostValue)) { continue }
                if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals($hostValue.Trim(), $targetHost)) { continue }

                $portVal = Get-PropertyStringValue -InputObject $iface -PropertyNames @('Port', 'Interface', 'IfName', 'Name')

                if (-not [string]::IsNullOrWhiteSpace($portVal)) {
                    [void]$ports.Add($portVal.Trim())
                }
            }

            if ($ports.Count -gt 0) {
                $comparison = [System.Comparison[string]]{
                    param($a, $b)
                    $keyA = Get-PortSortKey -Port $a
                    $keyB = Get-PortSortKey -Port $b
                    return [System.StringComparer]::OrdinalIgnoreCase.Compare($keyA, $keyB)
                }
                $ports.Sort($comparison)
                return $ports.ToArray()
            }
        }
    } catch {
        Write-Verbose "[InterfaceModule] ViewStateService lookup failed: $($_.Exception.Message)"
    }

    try {
        if ($global:DeviceInterfaceCache -and $global:DeviceInterfaceCache.ContainsKey($Hostname)) {
            $items = $global:DeviceInterfaceCache[$Hostname]
            if ($items) {
                $plist = [System.Collections.Generic.List[string]]::new()
                foreach ($it in $items) {
                    if (-not $it) { continue }
                    $pVal = Get-PropertyStringValue -InputObject $it -PropertyNames @('Port')
                    if (-not [string]::IsNullOrWhiteSpace($pVal)) { [void]$plist.Add($pVal) }
                }
                return $plist.ToArray()
            }
        }
    } catch {}

    if (-not $global:StateTraceDb) { return @() }
    try {
        Ensure-DatabaseModule
        $escHost = $Hostname -replace "'", "''"
        $dt = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT Port FROM Interfaces WHERE Hostname = '$escHost' ORDER BY Port"
        $portList = [System.Collections.Generic.List[string]]::new()
        foreach ($row in $dt) {
            [void]$portList.Add([string]$row.Port)
        }
        return $portList.ToArray()
    } catch {
        Write-Warning ("Failed to get interface list for {0}: {1}" -f $Hostname, $_.Exception.Message)
        return @()
    }
}



function Compare-InterfaceConfigs {
    # .SYNOPSIS

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Switch1,
        [Parameter(Mandatory)][string]$Interface1,
        [Parameter(Mandatory)][string]$Switch2,
        [Parameter(Mandatory)][string]$Interface2,
        [string]$ScriptPath = (Join-Path $PSScriptRoot '..\Main\CompareConfigs.ps1')
    )
    # Prior to the refactor this function launched an external PowerShell

    throw "External compare script invocation has been removed. Please use the Compare sidebar to view diffs."
}

function Get-InterfaceConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]  $Hostname,
        [Parameter(Mandatory)][string[]]$Interfaces,
        [Parameter(Mandatory)][string]  $TemplateName,
        [hashtable]$NewNames,
        [hashtable]$NewVlans,
        [string]$TemplatesPath = (Join-Path $PSScriptRoot '..\Templates')
    )
    DeviceRepositoryModule\Get-InterfaceConfiguration @PSBoundParameters
}

function Get-SpanningTreeInfo {
    [CmdletBinding()]
    param([Parameter()][AllowEmptyString()][string]$Hostname)

    $hostTrim = ('' + $Hostname).Trim()
    if ([string]::IsNullOrWhiteSpace($hostTrim)) { return @() }

    try {
        return DeviceRepositoryModule\Get-SpanningTreeInfo -Hostname $hostTrim
    } catch {
        Write-Verbose ("[InterfaceModule] Failed to load spanning tree data for '{0}': {1}" -f $hostTrim, $_.Exception.Message)
        return @()
    }
}

function Get-ConfigurationTemplates {
    # .SYNOPSIS

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [string]$TemplatesPath = (Join-Path $PSScriptRoot '..\Templates')
    )
    # Delegate to TemplatesModule implementation.  This wrapper calls the
    return TemplatesModule\Get-ConfigurationTemplates @PSBoundParameters
    # The legacy implementation that queried the DeviceSummary table and

}

function New-InterfacesView {
    [CmdletBinding()]
    param(
        # Parent window into which the Interfaces view will be loaded.
        [Parameter(Mandatory=$true)]
        [System.Windows.Window]$Window,
        # Optional script directory.  When provided, the view XAML will be
        [string]$ScriptDir,
        # Optional explicit path to the Interfaces view XAML.  When
        [string]$InterfacesViewXaml
    )

    # Determine the XAML path to load.  Priority order:
    $interfacesViewXamlPath = $null
    if ($PSBoundParameters.ContainsKey('InterfacesViewXaml') -and $InterfacesViewXaml) {
        $interfacesViewXamlPath = $InterfacesViewXaml
    } elseif ($ScriptDir) {
        $interfacesViewXamlPath = Join-Path $ScriptDir '..\Views\InterfacesView.xaml'
    } else {
        $interfacesViewXamlPath = $script:InterfacesViewXamlDefault
    }

    # Validate that the XAML file exists before proceeding.
    if (-not (Test-Path $interfacesViewXamlPath)) {
        Write-Warning "Missing InterfacesView.xaml at $interfacesViewXamlPath"
        return
    }
    $ifaceXaml   = Get-Content $interfacesViewXamlPath -Raw
    $ifaceReader = New-Object System.Xml.XmlTextReader (New-Object System.IO.StringReader($ifaceXaml))
    $interfacesView = [Windows.Markup.XamlReader]::Load($ifaceReader)

    # Mount view
    $interfacesHost = $Window.FindName('InterfacesHost')
    if ($interfacesHost -is [System.Windows.Controls.ContentControl]) {
        $interfacesHost.Content = $interfacesView
    } else {
        Write-Warning "Could not find ContentControl 'InterfacesHost'"
    }

    # Grab controls
    $compareButton     = $interfacesView.FindName('CompareButton')
    $interfacesGrid    = $interfacesView.FindName('InterfacesGrid')
    $configureButton   = $interfacesView.FindName('ConfigureButton')
    $templateDropdown  = $interfacesView.FindName('ConfigOptionsDropdown')
    $filterBox         = $interfacesView.FindName('FilterBox')
    $clearBtn          = $interfacesView.FindName('ClearFilterButton')
    $copyDetailsButton = $interfacesView.FindName('CopyDetailsButton')

    #
    if ($interfacesGrid)    { $global:interfacesGrid   = $interfacesGrid }
    if ($templateDropdown)  { $global:templateDropdown = $templateDropdown }
    if ($filterBox)         { $global:filterBox        = $filterBox }

    # ------------------------------
    if ($compareButton) {
        $compareButton.Add_Click({
        # Prefer globally-scoped grid if we promoted it; fall back to find by name
        $grid = $global:interfacesGrid
        if (-not $grid) { $grid = $interfacesView.FindName('InterfacesGrid') }
        if (-not $grid) {
            [System.Windows.MessageBox]::Show("Interfaces grid not found.")
            return
        }
        # Commit any pending edits before reading selections
        [void]$grid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Cell, $true)
        [void]$grid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row,  $true)
        # Gather checked or selected rows using typed-list helper
        $rows = Get-SelectedInterfaceRows -Grid $grid
        if ($rows.Count -ne 2) {
            [System.Windows.MessageBox]::Show("Select (or check) exactly two interfaces to compare.")
            return
        }
        $int1,$int2 = $rows

        # Validate we have needed fields
        foreach ($int in @($int1,$int2)) {
            foreach ($req in 'Hostname','Port') {
                if (-not $int.PSObject.Properties[$req]) {
                    [System.Windows.MessageBox]::Show("Selected items are missing '$req'.")
                    return
                }
            }
        }

        try {
            Set-CompareSelection -Switch1 $int1.Hostname -Interface1 $int1.Port `
                               -Switch2 $int2.Hostname -Interface2 $int2.Port `
                               -Row1 $int1 -Row2 $int2

            # Expand compare sidebar if collapsed
            $col = $Window.FindName('CompareColumn')
            if ($col -is [System.Windows.Controls.ColumnDefinition]) {
                # Expand the Compare sidebar to a wider width.  A 600 pixel width
                if ($col.Width.Value -eq 0) { $col.Width = [System.Windows.GridLength]::new(600) }
            }
        } catch {
            [System.Windows.MessageBox]::Show("Compare failed:`n$($_.Exception.Message)")
        }
    })

    }

    if ($interfacesGrid) {
        # With SelectionUnit="CellOrRowHeader" and a two-way checkbox binding defined in the XAML, DataGrid checkboxes
    }

    # ------------------------------
    if ($configureButton -and $interfacesGrid -and $templateDropdown) {
        $configureButton.Add_Click({
            # Use globally scoped grid and dropdown to avoid out-of-scope errors
            $grid = $global:interfacesGrid
            # Gather rows using helper; prefer checked rows
            $selectedRows = Get-SelectedInterfaceRows -Grid $grid
            if ($selectedRows.Count -eq 0) {
                [System.Windows.MessageBox]::Show("No interfaces selected.")
                return
            }
            $template = $global:templateDropdown.SelectedItem
            if (-not $template) {
                [System.Windows.MessageBox]::Show("No template selected.")
                return
            }
            $hostname = $interfacesView.FindName('HostnameBox').Text
            try {
                $namesMap = @{}
                $vlansMap = @{}
                foreach ($int in $selectedRows) {
                    if ($int.Name -and $int.Name -ne '') { $namesMap[$int.Port] = $int.Name }
                    if ($int.VLAN -and $int.VLAN -ne '') { $vlansMap[$int.Port] = $int.VLAN }
                }
                $ports = $selectedRows | ForEach-Object { $_.Port }
                $lines = Get-InterfaceConfiguration -Hostname $hostname -Interfaces $ports -TemplateName $template -NewNames $namesMap -NewVlans $vlansMap
                Set-Clipboard -Value ($lines -join "`r`n")
                [System.Windows.MessageBox]::Show(($lines -join "`n"), "Generated Config")
            } catch {
                [System.Windows.MessageBox]::Show("Failed to build config:`n$($_.Exception.Message)")
            }
        })
    }

    # ------------------------------
    if ($clearBtn -and $filterBox) {
        $clearBtn.Add_Click({
            # Access filter box via global scope to avoid missing variable errors
            $global:filterBox.Text  = ""
            $global:filterBox.Focus()
        })
    }
    if ($filterBox -and $interfacesGrid) {
        # Initialise a debounce timer for the filter box if it does not exist.  This
        if (-not $script:InterfacesFilterTimer) {
            $script:InterfacesFilterTimer = New-Object System.Windows.Threading.DispatcherTimer
            # Use a 300ms interval to match the search debounce and allow the user
            $script:InterfacesFilterTimer.Interval = [TimeSpan]::FromMilliseconds(300)
            $script:InterfacesFilterTimer.add_Tick({
                # Stop the timer so it can be restarted by the next key press
                $script:InterfacesFilterTimer.Stop()
                try {
                    # Safely coerce the filter box text to a string.  Avoid calling
                    $txt  = ('' + $global:filterBox.Text)
                    $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($global:interfacesGrid.ItemsSource)
                    if ($null -eq $view) { return }
                    $view.Filter = {
                        param($item)
                        # Coerce each field to a string to avoid calling methods on $null.  Casting
                        return (
                            (('' + $item.Port      ).IndexOf($txt, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                            (('' + $item.Name      ).IndexOf($txt, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                            (('' + $item.Status    ).IndexOf($txt, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                            (('' + $item.VLAN      ).IndexOf($txt, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                            (('' + $item.AuthState ).IndexOf($txt, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
                        )
                    }
                    $view.Refresh()
                } catch {
                    # Swallow exceptions to avoid crashing the UI on bad filter values
                }
            })
        }
        # On every key press, restart the debounce timer; the filter will
        $filterBox.Add_TextChanged({
            if ($script:InterfacesFilterTimer) {
                $script:InterfacesFilterTimer.Stop()
                $script:InterfacesFilterTimer.Start()
            }
        })
    }

    # ------------------------------
    if ($copyDetailsButton -and $interfacesGrid) {
        $copyDetailsButton.Add_Click({
            # Use global interfaces grid to read selected items
            $grid = $global:interfacesGrid
            # Gather selected or checked rows using helper
            # Retrieve selected rows.  Do not assume the result exposes a .Count property on
            # the object itself; instead wrap it as an array to ensure Count always exists.
            $rawSelected = Get-SelectedInterfaceRows -Grid $grid
            $selectedRows = @($rawSelected)
            if ($selectedRows.Count -eq 0) {
                [System.Windows.MessageBox]::Show("No interfaces selected.")
                return
            }
            $hostname = $interfacesView.FindName('HostnameBox').Text
            $header = @("Hostname: $hostname", "------------------------------", "")
            # Build output for each selected interface.  Use the array version of selectedRows
            # to iterate reliably even when only one row is selected.
            $output = foreach ($int in $selectedRows) {
                @(
                    "Port:        $($int.Port)",
                    "Name:        $($int.Name)",
                    "Status:      $($int.Status)",
                    "VLAN:        $($int.VLAN)",
                    "Duplex:      $($int.Duplex)",
                    "Speed:       $($int.Speed)",
                    "Type:        $($int.Type)",
                    "LearnedMACs: $($int.LearnedMACs)",
                    "AuthState:   $($int.AuthState)",
                    "AuthMode:    $($int.AuthMode)",
                    "Client MAC:  $($int.AuthClientMAC)",
                    "Config:",
                    "$($int.ToolTip)",
                    "------------------------------"
                ) -join "`r`n"
            }
            $final = $header + $output
            Set-Clipboard -Value ($final -join "`r`n")
            # Use the count of the array to report how many interfaces were copied
            [System.Windows.MessageBox]::Show("Copied $($selectedRows.Count) interface(s) to clipboard.")
        })
    }

    # ------------------------------


    # ------------------------------
    if ($templateDropdown) {
        if (-not $script:TemplateThemeHandlerRegistered) {
            try {
                Register-StateTraceThemeChanged -Handler ([System.Action[string]]{ param($themeName) Set-TemplateDropdownBrush -Vendor $script:lastTemplateVendor })
                $script:TemplateThemeHandlerRegistered = $true
            } catch {
                Write-Verbose "[Interfaces] Failed to register template theme handler: $($_.Exception.Message)"
            }
        }
        $templateDropdown.Add_SelectionChanged({
            $sel = $global:templateDropdown.SelectedItem
            $vendor = 'default'
            if ($sel) {
                $text = '' + $sel
                if     ($text -match '(?i)cisco')   { $vendor = 'cisco' }
                elseif ($text -match '(?i)brocade') { $vendor = 'brocade' }
                elseif ($text -match '(?i)arista')  { $vendor = 'arista' }
            }
            $script:lastTemplateVendor = $vendor
            Set-TemplateDropdownBrush -Vendor $vendor
        })
        try {
            $initialVendor = 'default'
            if ($templateDropdown.SelectedItem) {
                $text = '' + $templateDropdown.SelectedItem
                if     ($text -match '(?i)cisco')   { $initialVendor = 'cisco' }
                elseif ($text -match '(?i)brocade') { $initialVendor = 'brocade' }
                elseif ($text -match '(?i)arista')  { $initialVendor = 'arista' }
            }
            $script:lastTemplateVendor = $initialVendor
            Set-TemplateDropdownBrush -Vendor $initialVendor
        } catch {}
    }

    $global:interfacesView = $interfacesView
}

function Set-InterfaceViewData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$DeviceDetails,
        [string]$DefaultHostname
    )

    $interfacesView = $null
    try { $interfacesView = $global:interfacesView } catch { $interfacesView = $null }
    if (-not $interfacesView) {
        try {
            $interfacesHost = $global:window.FindName('InterfacesHost')
            if ($interfacesHost -is [System.Windows.Controls.ContentControl]) {
                $interfacesView = $interfacesHost.Content
            }
        } catch {
            $interfacesView = $null
        }
    }
    if (-not $interfacesView) { return }

    try { $global:interfacesView = $interfacesView } catch {}

    $fallbackHostname = ''
    if ($PSBoundParameters.ContainsKey('DefaultHostname') -and $DefaultHostname) {
        $fallbackHostname = '' + $DefaultHostname
    }

    $summary = $null
    if ($DeviceDetails -and $DeviceDetails.PSObject.Properties['Summary']) {
        $summary = $DeviceDetails.Summary
    }
    if (-not $summary) {
        $summary = [PSCustomObject]@{
            Hostname        = $fallbackHostname
            Make            = ''
            Model           = ''
            Uptime          = ''
            Ports           = ''
            AuthDefaultVLAN = ''
            Building        = ''
            Room            = ''
        }
    }

    $getValue = {
        param($obj, [string]$name, [string]$defaultValue = '')
        if (-not $obj) { return $defaultValue }
        try {
            $val = $null
            if ($obj -is [hashtable]) {
                if ($obj.ContainsKey($name)) { $val = $obj[$name] }
            } elseif ($obj.PSObject -and $obj.PSObject.Properties[$name]) {
                $val = $obj.$name
            }
            if ($null -eq $val -or $val -eq [System.DBNull]::Value) { return $defaultValue }
            $text = '' + $val
            if ([string]::IsNullOrEmpty($text)) { return $defaultValue }
            return $text
        } catch {
            return $defaultValue
        }
    }

    $setText = {
        param($view, [string]$controlName, [string]$value)
        try {
            $ctrl = $view.FindName($controlName)
            if ($ctrl) { $ctrl.Text = $value }
        } catch {}
    }

    $hostnameValue = & $getValue $summary 'Hostname' $fallbackHostname
    & $setText $interfacesView 'HostnameBox'        $hostnameValue
    & $setText $interfacesView 'MakeBox'            (& $getValue $summary 'Make')
    & $setText $interfacesView 'ModelBox'           (& $getValue $summary 'Model')
    & $setText $interfacesView 'UptimeBox'          (& $getValue $summary 'Uptime')
    & $setText $interfacesView 'PortCountBox'       (& $getValue $summary 'Ports')
    & $setText $interfacesView 'AuthDefaultVLANBox' (& $getValue $summary 'AuthDefaultVLAN')
    & $setText $interfacesView 'BuildingBox'        (& $getValue $summary 'Building')
    & $setText $interfacesView 'RoomBox'            (& $getValue $summary 'Room')

    try {
        $grid = $interfacesView.FindName('InterfacesGrid')
        if ($grid) {
            $itemsSource = $DeviceDetails.Interfaces
            if (-not $itemsSource) {
                $itemsSource = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
                $DeviceDetails.Interfaces = $itemsSource
            }
            $grid.ItemsSource = $itemsSource
            try { $global:interfacesGrid = $grid } catch {}
            try { $global:CurrentInterfaceCollection = $itemsSource } catch { $global:CurrentInterfaceCollection = $null }
        }
    } catch {}

    try {
        $combo = $interfacesView.FindName('ConfigOptionsDropdown')
        if ($combo) {
            $items = [System.Collections.Generic.List[object]]::new()
            if ($DeviceDetails.Templates) {
                foreach ($item in $DeviceDetails.Templates) {
                    if ($null -ne $item) { [void]$items.Add(('' + $item)) }
                }
            }
            FilterStateModule\Set-DropdownItems -Control $combo -Items $items.ToArray()
            try { $global:templateDropdown = $combo } catch {}
        }
    } catch {}

    $telemetryCmd = Get-Command -Name 'TelemetryModule\Write-StTelemetryEvent' -ErrorAction SilentlyContinue
    if ($telemetryCmd) {
        try {
            $siteCode = $null
            if (-not [string]::IsNullOrWhiteSpace($hostnameValue)) {
                $parts = $hostnameValue -split '-', 2
                if ($parts.Count -gt 0) { $siteCode = $parts[0] }
            }
            TelemetryModule\Write-StTelemetryEvent -Name 'UserAction' -Payload @{
                Action    = 'InterfacesView'
                Hostname  = $hostnameValue
                Site      = $siteCode
                Timestamp = (Get-Date).ToString('o')
            }
        } catch { }
    }
}

function Set-PortLoadingIndicator {
    [CmdletBinding()]
    param(
        [int]$Loaded = 0,
        [int]$Total = 0,
        [int]$BatchesRemaining = 0
    )

    $view = $null
    try { $view = $global:interfacesView } catch { $view = $null }
    if (-not $view) { return }

    $indicator = $null
    $progress = $null
    try { $indicator = $view.FindName('PortLoadingIndicator') } catch { $indicator = $null }
    try { $progress = $view.FindName('PortLoadingProgress') } catch { $progress = $null }

    if (-not $indicator) { return }

    $loadedValue = if ($Loaded -ge 0) { [int]$Loaded } else { 0 }
    $totalValue = if ($Total -ge 0) { [int]$Total } else { 0 }
    $remaining = if ($BatchesRemaining -ge 0) { [int]$BatchesRemaining } else { 0 }

    if ($totalValue -le 0 -and $remaining -le 0) {
        $indicator.Visibility = [System.Windows.Visibility]::Collapsed
        if ($progress) { $progress.Visibility = [System.Windows.Visibility]::Collapsed }
        return
    }

    $indicator.Visibility = [System.Windows.Visibility]::Visible
    $displayLoaded = [Math]::Min($loadedValue, [Math]::Max($totalValue, 0))
    if ($totalValue -le 0) {
        $indicator.Text = 'Loading ports...'
        if ($progress) { $progress.Visibility = [System.Windows.Visibility]::Collapsed }
    } else {
        $text = "Loading ports ({0} of {1})" -f $displayLoaded, $totalValue
        if ($displayLoaded -ge $totalValue -and $remaining -le 0) {
            $text = "Ports loaded ({0})" -f $totalValue
        }
        $indicator.Text = $text
        if ($progress) {
            $progress.Visibility = [System.Windows.Visibility]::Visible
            $progress.Maximum = [double][Math]::Max($totalValue, 1)
            $progress.Value = [double][Math]::Min($displayLoaded, $progress.Maximum)
        }
    }
}

function Set-HostLoadingIndicator {
    [CmdletBinding()]
    param(
        [string]$Hostname,
        [int]$CurrentIndex = 0,
        [int]$TotalHosts = 0,
        [ValidateSet('Loading','Loaded','Hidden')]
        [string]$State = 'Loading'
    )

    $view = $null
    try { $view = $global:interfacesView } catch { $view = $null }
    if (-not $view) { return }

    $indicator = $null
    try { $indicator = $view.FindName('HostLoadingIndicator') } catch { $indicator = $null }
    if (-not $indicator) { return }

    if ($State -eq 'Hidden' -or [string]::IsNullOrWhiteSpace($Hostname)) {
        $indicator.Visibility = [System.Windows.Visibility]::Collapsed
        $indicator.Text = ''
        return
    }

    $text = ''
    if ($State -eq 'Loaded') {
        $text = "Loaded host {0}" -f $Hostname
    } else {
        if ($CurrentIndex -gt 0 -and $TotalHosts -gt 0) {
            $text = "Loading host {0} ({1}/{2})..." -f $Hostname, $CurrentIndex, $TotalHosts
        } else {
            $text = "Loading host {0}..." -f $Hostname
        }
    }

    $indicator.Text = $text
    $indicator.Visibility = [System.Windows.Visibility]::Visible
}

function Hide-PortLoadingIndicator {
    [CmdletBinding()]
    param()

    $view = $null
    try { $view = $global:interfacesView } catch { $view = $null }
    if (-not $view) { return }

    try {
        $indicator = $view.FindName('PortLoadingIndicator')
        if ($indicator) { $indicator.Visibility = [System.Windows.Visibility]::Collapsed }
    } catch { }

    try {
        $progress = $view.FindName('PortLoadingProgress')
        if ($progress) { $progress.Visibility = [System.Windows.Visibility]::Collapsed }
    } catch { }
}

Export-ModuleMember -Function Get-PortSortKey,Get-PortSortCacheStatistics,Reset-PortSortCache,Get-InterfaceHostnames,Get-InterfaceInfo,Get-InterfaceList,New-InterfaceObjectsFromDbRow,Compare-InterfaceConfigs,Get-InterfaceConfiguration,Get-ConfigurationTemplates,Set-InterfaceViewData,Get-SpanningTreeInfo,New-InterfacesView,Set-PortLoadingIndicator,Hide-PortLoadingIndicator,Set-HostLoadingIndicator
