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
$script:InterfaceStringPropertyValueCmd = $null
$script:ColumnWidthSaveTimer = $null

if (-not (Get-Variable -Scope Script -Name PortNormalizationAvailable -ErrorAction SilentlyContinue)) {
    $script:PortNormalizationAvailable = $false
}

if (-not (Get-Variable -Scope Script -Name PortNormalizationWarned -ErrorAction SilentlyContinue)) {
    $script:PortNormalizationWarned = $false
}

if (-not (Get-Variable -Scope Script -Name InterfaceModuleImportWarnings -ErrorAction SilentlyContinue)) {
    $script:InterfaceModuleImportWarnings = @{}
}

try {
    $portNormPath = Join-Path $PSScriptRoot 'PortNormalization.psm1'        
    if (Test-Path -LiteralPath $portNormPath) {
        Import-Module -Name $portNormPath -ErrorAction Stop -Prefix 'PortNorm' | Out-Null
        if (Get-Command -Name 'Get-PortNormPortSortKey' -ErrorAction SilentlyContinue) {
            $script:PortNormalizationAvailable = $true
        }
    } else {
        $script:PortNormalizationAvailable = $false
        if (-not $script:PortNormalizationWarned) {
            $script:PortNormalizationWarned = $true
            Write-Warning ("[InterfaceModule] PortNormalization module not found at '{0}'; using fallback port sort keys." -f $portNormPath)
        }
    }
} catch {
    $script:PortNormalizationAvailable = $false
    if (-not $script:PortNormalizationWarned) {
        $script:PortNormalizationWarned = $true
        Write-Warning ("[InterfaceModule] PortNormalization not loaded: {0}" -f $_.Exception.Message)
    }
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
        public bool HasChanged { get; set; }
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

function Ensure-LocalStateTraceModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ModuleName,
        [Parameter(Mandatory)][string]$ModuleFileName
    )

    if ([string]::IsNullOrWhiteSpace($ModuleName) -or [string]::IsNullOrWhiteSpace($ModuleFileName)) {
        return
    }

    try {
        if (Get-Module -Name $ModuleName -ErrorAction SilentlyContinue) { return }
    } catch { }

    $alreadyWarned = $false
    try { $alreadyWarned = $script:InterfaceModuleImportWarnings.ContainsKey($ModuleName) } catch { $alreadyWarned = $false }

    $modulePath = Join-Path $PSScriptRoot $ModuleFileName
    $modulePathExists = $false
    try { $modulePathExists = Test-Path -LiteralPath $modulePath } catch { $modulePathExists = $false }

    $lastError = $null
    if ($modulePathExists) {
        try {
            Import-Module $modulePath -Force -Global -ErrorAction Stop | Out-Null
            return
        } catch {
            $lastError = $_.Exception.Message
        }
    } else {
        $lastError = "Module path not found."
    }

    if (-not $alreadyWarned) {
        $script:InterfaceModuleImportWarnings[$ModuleName] = $true
        $detail = if ($lastError) { $lastError } else { 'Unknown import failure.' }
        Write-Warning ("[InterfaceModule] Failed to import module '{0}' from '{1}': {2}" -f $ModuleName, $modulePath, $detail)
    }
}

function Ensure-DeviceRepositoryModule {
    [CmdletBinding()]
    param()
    Ensure-LocalStateTraceModule -ModuleName 'DeviceRepositoryModule' -ModuleFileName 'DeviceRepositoryModule.psm1'
}

function Ensure-DatabaseModule {
    [CmdletBinding()]
    param()
    Ensure-LocalStateTraceModule -ModuleName 'DatabaseModule' -ModuleFileName 'DatabaseModule.psm1'
}

function Get-PropertyStringValue {
    param(
        [Parameter(Mandatory)][object]$InputObject,
        [Parameter(Mandatory)][string[]]$PropertyNames
    )

    $stringPropertyCmd = $script:InterfaceStringPropertyValueCmd
    if (-not $stringPropertyCmd) {
        try { $stringPropertyCmd = Get-Command -Name 'InterfaceCommon\Get-StringPropertyValue' -ErrorAction SilentlyContinue } catch { $stringPropertyCmd = $null }
        if (-not $stringPropertyCmd) {
            try { TelemetryModule\Import-InterfaceCommon | Out-Null } catch { }
            try { $stringPropertyCmd = Get-Command -Name 'InterfaceCommon\Get-StringPropertyValue' -ErrorAction SilentlyContinue } catch { $stringPropertyCmd = $null }
        }
        if ($stringPropertyCmd) { $script:InterfaceStringPropertyValueCmd = $stringPropertyCmd }
    }

    if ($stringPropertyCmd) {
        try { return (& $stringPropertyCmd @PSBoundParameters) } catch { }
    }

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

    if ($script:PortNormalizationAvailable) {
        return Get-PortNormPortSortKey -Port $Port
    }

    return $script:PortSortFallbackKey
}

function Get-PortSortCacheStatistics {
    [CmdletBinding()]
    param()

    if ($script:PortNormalizationAvailable) {
        return Get-PortNormPortSortCacheStatistics
    }

    return [pscustomobject]@{
        Hits       = 0L
        Misses     = 0L
        EntryCount = 0L
        Fallback   = $script:PortSortFallbackKey
        CacheType  = ''
        Count      = 0L
    }
}

function Reset-PortSortCache {
    [CmdletBinding()]
    param()

    if ($script:PortNormalizationAvailable) {
        return Reset-PortNormPortSortCache
    }

    return Get-PortSortCacheStatistics
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
            $vendor = TemplatesModule\Get-TemplateVendorKeyFromMake -Make $mk
        }
    } catch {}
    # Fallback to query DeviceSummary if vendor still Cisco
    if ($vendor -eq 'Cisco') {
        try {
            $mkDt = DatabaseModule\Invoke-DbQuery -DatabasePath $dbPath -Sql "SELECT Make FROM DeviceSummary WHERE Hostname = '$escHost'"
            if ($mkDt) {
                $mkRows = DatabaseModule\ConvertTo-DbRowList -Data $mkDt
                if ($mkRows.Count -gt 0) {
                    $mk = '' + $mkRows[0].Make
                    $vendor = TemplatesModule\Get-TemplateVendorKeyFromMake -Make $mk
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
                $abDt = DatabaseModule\Invoke-DbQuery -DatabasePath $dbPath -Sql "SELECT AuthBlock FROM DeviceSummary WHERE Hostname = '$escHost'"
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

    # OPTIMIZATION: Pre-compute which properties exist by checking the first row once
    # This avoids repeated PSObject.Properties lookups for every row
    $propExists = @{}
    $sampleRow = $rows[0]
    if ($sampleRow -and $sampleRow.PSObject) {
        $propNames = @('Port','Name','Status','VLAN','Duplex','Speed','Type','LearnedMACs',
                       'AuthState','AuthMode','AuthClientMAC','Site','Building','Room','Zone',
                       'AuthTemplate','Config','ConfigStatus','PortColor','ToolTip')
        foreach ($pn in $propNames) {
            $propExists[$pn] = ($null -ne $sampleRow.PSObject.Properties[$pn])
        }
    }

    foreach ($row in $rows) {
        if (-not $row) { continue }
        # OPTIMIZED: Use pre-computed property existence map instead of checking each time
        $authTemplate = $null
        if ($propExists['AuthTemplate']) { try { $authTemplate = '' + $row.AuthTemplate } catch { } }
        $cfg = $null
        if ($propExists['Config']) { try { $cfg = '' + $row.Config } catch { } }
        $existingTip = ''
        if ($propExists['ToolTip']) { try { if ($row.ToolTip) { $existingTip = ('' + $row.ToolTip).TrimEnd() } } catch { } }
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
        if ($propExists['PortColor']) {
            try {
                $pcVal = $row.PortColor
                if ($pcVal) {
                    $portColorVal = '' + $pcVal
                    if (-not [string]::IsNullOrWhiteSpace($portColorVal)) { $hasPortColor = $true }
                }
            } catch { }
        }
        if ($propExists['ConfigStatus']) {
            try {
                $csVal = $row.ConfigStatus
                if ($csVal) {
                    $cfgStatusVal = '' + $csVal
                    if (-not [string]::IsNullOrWhiteSpace($cfgStatusVal)) { $hasConfigStatus = $true }
                }
            } catch { }
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
        # Build the InterfacePortRecord for this interface. OPTIMIZED: Use direct property access
        # with pre-computed existence map instead of Get-PropertyStringValue function calls
        $portValue = $null
        if ($propExists['Port']) { try { $portValue = '' + $row.Port } catch { } }
        $portSortKey = if ($portValue) { Get-PortSortKey -Port $portValue } else { $script:PortSortFallbackKey }

        $record = [StateTrace.Models.InterfacePortRecord]::new()
        $record.Hostname = $Hostname
        $record.Port = $portValue
        $record.PortSort = $portSortKey
        # OPTIMIZED: Direct property access with try/catch instead of Get-PropertyStringValue
        if ($propExists['Name']) { try { $v = $row.Name; if ($v) { $record.Name = '' + $v } } catch { } }
        if ($propExists['Status']) { try { $v = $row.Status; if ($v) { $record.Status = '' + $v } } catch { } }
        if ($propExists['VLAN']) { try { $v = $row.VLAN; if ($v) { $record.VLAN = '' + $v } } catch { } }
        if ($propExists['Duplex']) { try { $v = $row.Duplex; if ($v) { $record.Duplex = '' + $v } } catch { } }
        if ($propExists['Speed']) { try { $v = $row.Speed; if ($v) { $record.Speed = '' + $v } } catch { } }
        if ($propExists['Type']) { try { $v = $row.Type; if ($v) { $record.Type = '' + $v } } catch { } }
        if ($propExists['LearnedMACs']) { try { $v = $row.LearnedMACs; if ($v) { $record.LearnedMACs = '' + $v } } catch { } }
        if ($propExists['AuthState']) { try { $v = $row.AuthState; if ($v) { $record.AuthState = '' + $v } } catch { } }
        if ($propExists['AuthMode']) { try { $v = $row.AuthMode; if ($v) { $record.AuthMode = '' + $v } } catch { } }
        if ($propExists['AuthClientMAC']) { try { $v = $row.AuthClientMAC; if ($v) { $record.AuthClientMAC = '' + $v } } catch { } }
        if ($propExists['Site']) { try { $v = $row.Site; if ($v) { $record.Site = '' + $v } } catch { } }
        if ($propExists['Building']) { try { $v = $row.Building; if ($v) { $record.Building = '' + $v } } catch { } }
        if ($propExists['Room']) { try { $v = $row.Room; if ($v) { $record.Room = '' + $v } } catch { } }
        if ($propExists['Zone']) { try { $v = $row.Zone; if ($v) { $record.Zone = '' + $v } } catch { } }
        $record.AuthTemplate = $authTemplate
        $record.Config = $cfg
        $record.ConfigStatus = $cfgStatusVal
        $record.PortColor = $portColorVal
        $record.ToolTip = $finalTip
        $record.IsSelected = $false
        [void]$resultList.Add($record)
    }
    # OPTIMIZED: Use direct PortSort property access since we know it exists on InterfacePortRecord
    $comparison = [System.Comparison[object]]{
        param($a, $b)
        $keyA = if ($a) { $a.PortSort } else { $script:PortSortFallbackKey }
        $keyB = if ($b) { $b.PortSort } else { $script:PortSortFallbackKey }
        if (-not $keyA) { $keyA = $script:PortSortFallbackKey }
        if (-not $keyB) { $keyB = $script:PortSortFallbackKey }
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
        $items = $null
        try {
            $items = DeviceRepositoryModule\Invoke-InterfaceCacheLock {
                if ($global:DeviceInterfaceCache -and $global:DeviceInterfaceCache.ContainsKey($Hostname)) {
                    return @($global:DeviceInterfaceCache[$Hostname])
                }
                return $null
            }
        } catch {
            try {
                if ($global:DeviceInterfaceCache -and $global:DeviceInterfaceCache.ContainsKey($Hostname)) {
                    $items = @($global:DeviceInterfaceCache[$Hostname])
                }
            } catch { $items = $null }
        }
        if ($items) {
            $plist = [System.Collections.Generic.List[string]]::new()
            foreach ($it in $items) {
                if (-not $it) { continue }
                $pVal = Get-PropertyStringValue -InputObject $it -PropertyNames @('Port')
                if (-not [string]::IsNullOrWhiteSpace($pVal)) { [void]$plist.Add($pVal) }
            }
            return $plist.ToArray()
        }
    } catch {}

    Ensure-DeviceRepositoryModule

    $databasePath = $null
    $stateTraceDbVar = $null
    $allowMissingPath = $false
    try { $stateTraceDbVar = Get-Variable -Name StateTraceDb -Scope Global -ErrorAction Stop } catch { $stateTraceDbVar = $null }
    if ($stateTraceDbVar -and $stateTraceDbVar.Value) {
        $databasePath = $stateTraceDbVar.Value
        # Preserve legacy behaviour for callers that pre-seed StateTraceDb even when the file is absent.
        $allowMissingPath = $true
    } else {
        try { $databasePath = DeviceRepositoryModule\Get-DbPathForHost -Hostname $Hostname } catch { $databasePath = $null }
        if (-not $databasePath -or -not (Test-Path -LiteralPath $databasePath)) {
            try {
                $siteFromHost = DeviceRepositoryModule\Get-SiteFromHostname -Hostname $Hostname
                if ($siteFromHost) {
                    $candidate = DeviceRepositoryModule\Get-DbPathForSite -Site $siteFromHost
                    if ($candidate -and (Test-Path -LiteralPath $candidate)) { $databasePath = $candidate }
                }
            } catch { $databasePath = $databasePath }
        }
        if ($databasePath -and (-not $stateTraceDbVar -or -not $stateTraceDbVar.Value)) {
            try { Set-Variable -Name StateTraceDb -Scope Global -Value $databasePath -Force } catch { }
        }
    }

    if (-not $databasePath) { return @() }
    if (-not $allowMissingPath -and -not (Test-Path -LiteralPath $databasePath)) { return @() }
    try {
        Ensure-DatabaseModule
        $escHost = $Hostname -replace "'", "''"
        $dt = DatabaseModule\Invoke-DbQuery -DatabasePath $databasePath -Sql "SELECT Port FROM Interfaces WHERE Hostname = '$escHost' ORDER BY Port"
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
    if (-not (Test-Path -LiteralPath $interfacesViewXamlPath)) {
        Write-Warning "Missing InterfacesView.xaml at $interfacesViewXamlPath"
        return
    }
    $ifaceXaml   = Get-Content -LiteralPath $interfacesViewXamlPath -Raw
    $ifaceReader = New-Object System.Xml.XmlTextReader (New-Object System.IO.StringReader($ifaceXaml))
    try {
        $interfacesView = [Windows.Markup.XamlReader]::Load($ifaceReader)
    } finally {
        if ($ifaceReader) {
            try { $ifaceReader.Dispose() } catch { }
        }
    }

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
    $reorgButton       = $interfacesView.FindName('ReorgButton')
    $filterBox         = $interfacesView.FindName('FilterBox')
    $clearBtn          = $interfacesView.FindName('ClearFilterButton')
    $copyDetailsButton = $interfacesView.FindName('CopyDetailsButton')
    $copyPortsButton   = $interfacesView.FindName('CopyPortsButton')
    $copyMacsButton    = $interfacesView.FindName('CopyMacsButton')
    $exportSelectedBtn = $interfacesView.FindName('ExportSelectedButton')
    $exportFormatDropdown = $interfacesView.FindName('ExportFormatDropdown')
    $setVlanButton     = $interfacesView.FindName('SetVlanButton')
    $setNameButton     = $interfacesView.FindName('SetNameButton')
    $selectPatternButton = $interfacesView.FindName('SelectPatternButton')
    $compareButton     = $interfacesView.FindName('CompareInterfacesButton')
    $columnsButton     = $interfacesView.FindName('ColumnsButton')
    $autoFitButton     = $interfacesView.FindName('AutoFitColumnsButton')
    $sortPresetDropdown = $interfacesView.FindName('SortPresetDropdown')
    $groupByDropdown   = $interfacesView.FindName('GroupByDropdown')
    $filterPresetsDropdown = $interfacesView.FindName('FilterPresetsDropdown')
    $savePresetButton  = $interfacesView.FindName('SavePresetButton')
    $deletePresetButton = $interfacesView.FindName('DeletePresetButton')

    #
    if ($interfacesGrid)    { $global:interfacesGrid   = $interfacesGrid }
    if ($templateDropdown)  { $global:templateDropdown = $templateDropdown }
    if ($filterBox)         { $global:filterBox        = $filterBox }

    # Load saved filter text
    if ($filterBox) {
        try {
            $settingsPath = Join-Path $PSScriptRoot '..\Data\StateTraceSettings.json'
            if (Test-Path $settingsPath) {
                $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
                if ($settings.LastInterfaceFilter) {
                    $filterBox.Text = $settings.LastInterfaceFilter
                }
            }
        } catch { }
    }

    # Cell edit validation for VLAN and Name columns
    if ($interfacesGrid) {
        $interfacesGrid.Add_CellEditEnding({
            param($sender, $e)
            if ($e.EditAction -ne 'Commit') { return }

            $column = $e.Column.Header
            $editingElement = $e.EditingElement

            if ($column -eq 'VLAN' -and $editingElement -is [System.Windows.Controls.TextBox]) {
                $text = $editingElement.Text.Trim()
                if ($text -ne '') {
                    $vlan = 0
                    if (-not [int]::TryParse($text, [ref]$vlan) -or $vlan -lt 1 -or $vlan -gt 4094) {
                        [System.Windows.MessageBox]::Show("VLAN must be a number between 1 and 4094.", 'Invalid VLAN', 'OK', 'Warning')
                        $e.Cancel = $true
                        return
                    }
                }
            }
            elseif ($column -eq 'Name' -and $editingElement -is [System.Windows.Controls.TextBox]) {
                $text = $editingElement.Text
                if ($text.Length -gt 64) {
                    [System.Windows.MessageBox]::Show("Port name cannot exceed 64 characters.", 'Name Too Long', 'OK', 'Warning')
                    $e.Cancel = $true
                    return
                }
            }
        })

        # Keyboard shortcuts for grid
        $interfacesGrid.Add_PreviewKeyDown({
            param($sender, $e)
            $grid = $sender

            # Ctrl+A - Select all
            if ($e.Key -eq 'A' -and [System.Windows.Input.Keyboard]::Modifiers -eq 'Control') {
                foreach ($row in $grid.ItemsSource) {
                    $row.IsSelected = $true
                }
                $grid.Items.Refresh()
                $e.Handled = $true
                return
            }

            # Ctrl+C - Copy selected ports
            if ($e.Key -eq 'C' -and [System.Windows.Input.Keyboard]::Modifiers -eq 'Control') {
                $selectedRows = @($grid.ItemsSource | Where-Object { $_.IsSelected -eq $true })
                if ($selectedRows.Count -gt 0) {
                    $ports = $selectedRows | ForEach-Object { $_.Port } | Where-Object { $_ }
                    Set-Clipboard -Value ($ports -join "`r`n")
                }
                $e.Handled = $true
                return
            }

            # Delete - Clear selection
            if ($e.Key -eq 'Delete') {
                foreach ($row in $grid.ItemsSource) {
                    $row.IsSelected = $false
                }
                $grid.Items.Refresh()
                $e.Handled = $true
                return
            }

            # F1 or ? - Show keyboard shortcuts overlay
            if ($e.Key -eq 'F1' -or ($e.Key -eq 'Oem2' -and [System.Windows.Input.Keyboard]::Modifiers -eq 'Shift')) {
                $shortcutsText = @"
Keyboard Shortcuts - Interfaces View

Navigation:
  Ctrl+1-9      Switch tabs
  PageUp/Down   Scroll grid
  Home/End      Jump to first/last row

Selection:
  Ctrl+A        Select all rows
  Delete        Clear selection
  Click         Toggle row selection

Clipboard:
  Ctrl+C        Copy selected port names
  Double-click  Copy cell value

Filtering:
  Type in filter box to search
  Up/Down quick filters

Grid:
  Click column header to sort
  Drag column edges to resize
"@
                [System.Windows.MessageBox]::Show($shortcutsText, "Keyboard Shortcuts", "OK", "Information")
                $e.Handled = $true
                return
            }
        })

        # Double-click to copy cell value
        $interfacesGrid.Add_MouseDoubleClick({
            param($sender, $e)
            $grid = $sender
            $cell = $grid.CurrentCell
            if ($cell -and $cell.Column -and $cell.Item) {
                $columnHeader = $cell.Column.Header
                $item = $cell.Item
                $value = $null

                # Get value based on column header
                switch ($columnHeader) {
                    'Port'          { $value = $item.Port }
                    'Name'          { $value = $item.Name }
                    'Status'        { $value = $item.Status }
                    'VLAN'          { $value = $item.VLAN }
                    'Duplex'        { $value = $item.Duplex }
                    'Speed'         { $value = $item.Speed }
                    'Type'          { $value = $item.Type }
                    'LearnedMACs'   { $value = $item.LearnedMACs }
                    'AuthState'     { $value = $item.AuthState }
                    'AuthMode'      { $value = $item.AuthMode }
                    'AuthClientMAC' { $value = $item.AuthClientMAC }
                }

                if ($value) {
                    Set-Clipboard -Value $value
                }
            }
        })

        # Load saved column widths and order
        try {
            $settingsPath = Join-Path $PSScriptRoot '..\Data\StateTraceSettings.json'
            if (Test-Path $settingsPath) {
                $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
                if ($settings.InterfaceColumnWidths) {
                    $widths = $settings.InterfaceColumnWidths
                    foreach ($col in $interfacesGrid.Columns) {
                        $header = $col.Header
                        if ($header -and $widths.$header) {
                            $col.Width = [System.Windows.Controls.DataGridLength]::new($widths.$header)
                        }
                    }
                }
                # Restore column order
                if ($settings.InterfaceColumnOrder) {
                    $order = $settings.InterfaceColumnOrder
                    foreach ($col in $interfacesGrid.Columns) {
                        $header = '' + $col.Header
                        if ($header -and $order.$header -ne $null) {
                            $col.DisplayIndex = [int]$order.$header
                        }
                    }
                }
            }
        } catch { }

        # Save column order when reordered
        $interfacesGrid.Add_ColumnReordered({
            param($sender, $e)
            try {
                $grid = $sender
                $order = @{}
                foreach ($col in $grid.Columns) {
                    $header = '' + $col.Header
                    if ($header) {
                        $order[$header] = $col.DisplayIndex
                    }
                }
                $settingsPath = Join-Path $PSScriptRoot '..\Data\StateTraceSettings.json'
                $settings = @{}
                if (Test-Path $settingsPath) {
                    $raw = Get-Content $settingsPath -Raw
                    if ($raw) {
                        $parsed = $raw | ConvertFrom-Json
                        $parsed.PSObject.Properties | ForEach-Object { $settings[$_.Name] = $_.Value }
                    }
                }
                $settings['InterfaceColumnOrder'] = $order
                $settings | ConvertTo-Json -Depth 5 | Set-Content $settingsPath -Encoding UTF8
            } catch { }
        })

        # Use a script to save widths on layout updated (debounced)
        if (-not $script:ColumnWidthSaveTimer) {
            $script:ColumnWidthSaveTimer = New-Object System.Windows.Threading.DispatcherTimer
            $script:ColumnWidthSaveTimer.Interval = [TimeSpan]::FromSeconds(2)
            $script:ColumnWidthSaveTimer.Add_Tick({
                $script:ColumnWidthSaveTimer.Stop()
                try {
                    $grid = $global:interfacesGrid
                    if (-not $grid) { return }
                    $widths = @{}
                    foreach ($col in $grid.Columns) {
                        $header = $col.Header
                        if ($header) {
                            $widths[$header] = $col.ActualWidth
                        }
                    }
                    $settingsPath = Join-Path $PSScriptRoot '..\Data\StateTraceSettings.json'
                    $settings = @{}
                    if (Test-Path $settingsPath) {
                        $raw = Get-Content $settingsPath -Raw
                        if ($raw) {
                            $parsed = $raw | ConvertFrom-Json
                            $parsed.PSObject.Properties | ForEach-Object { $settings[$_.Name] = $_.Value }
                        }
                    }
                    $settings['InterfaceColumnWidths'] = $widths
                    $settings | ConvertTo-Json -Depth 5 | Set-Content $settingsPath -Encoding UTF8
                } catch { }
            }.GetNewClosure())
        }

        $interfacesGrid.Add_LayoutUpdated({
            if ($script:ColumnWidthSaveTimer) {
                $script:ColumnWidthSaveTimer.Stop()
                $script:ColumnWidthSaveTimer.Start()
            }
        }.GetNewClosure())
    }

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
        # Retrieve selected rows. Do not assume the result exposes a .Count property on
        # the object itself; instead wrap it as an array to ensure Count always exists.
        $rows = @(Get-SelectedInterfaceRows -Grid $grid)
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

    # ------------------------------
    if ($reorgButton) {
        $reorgButton.Add_Click({
            try {
                $hostname = ''
                try { $hostname = ('' + $interfacesView.FindName('HostnameBox').Text).Trim() } catch { $hostname = '' }
                if ([string]::IsNullOrWhiteSpace($hostname)) {
                    [System.Windows.MessageBox]::Show('No hostname selected.') | Out-Null
                    return
                }

                $modPath = Join-Path -Path $PSScriptRoot -ChildPath 'PortReorgViewModule.psm1'
                try {
                    PortReorgViewModule\Show-PortReorgWindow -OwnerWindow $Window -Hostname $hostname
                } catch [System.Management.Automation.CommandNotFoundException] {
                    if (Test-Path -LiteralPath $modPath) {
                        Import-Module -Name $modPath -Force -Global -ErrorAction Stop | Out-Null
                    }
                    PortReorgViewModule\Show-PortReorgWindow -OwnerWindow $Window -Hostname $hostname
                }
            } catch {
                [System.Windows.MessageBox]::Show(("Port reorg failed:`n{0}" -f $_.Exception.Message)) | Out-Null
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
            # Retrieve selected rows. Do not assume the result exposes a .Count property on
            # the object itself; instead wrap it as an array to ensure Count always exists.
            $selectedRows = @(Get-SelectedInterfaceRows -Grid $grid)
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

    # Quick filter buttons
    $filterUpBtn = $interfacesView.FindName('FilterUpButton')
    $filterDownBtn = $interfacesView.FindName('FilterDownButton')
    if ($filterUpBtn -and $filterBox) {
        $filterUpBtn.Add_Click({
            $global:filterBox.Text = 'up'
        })
    }
    if ($filterDownBtn -and $filterBox) {
        $filterDownBtn.Add_Click({
            $global:filterBox.Text = 'down'
        })
    }

    # Scroll navigation buttons
    $scrollTopBtn = $interfacesView.FindName('ScrollTopButton')
    $scrollBottomBtn = $interfacesView.FindName('ScrollBottomButton')
    if ($scrollTopBtn -and $interfacesGrid) {
        $scrollTopBtn.Add_Click({
            $grid = $global:interfacesGrid
            if ($grid -and $grid.Items.Count -gt 0) {
                $grid.ScrollIntoView($grid.Items[0])
            }
        })
    }
    if ($scrollBottomBtn -and $interfacesGrid) {
        $scrollBottomBtn.Add_Click({
            $grid = $global:interfacesGrid
            if ($grid -and $grid.Items.Count -gt 0) {
                $grid.ScrollIntoView($grid.Items[$grid.Items.Count - 1])
            }
        })
    }

    if ($filterBox -and $interfacesGrid) {
        # Initialise a debounce timer for the filter box if it does not exist.  This
        if (-not $script:InterfacesFilterTimer) {
            $script:InterfacesFilterTimer = ViewCompositionModule\New-StDebounceTimer -DelayMs 300 -Action {
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

                    # Update filter match count indicator
                    try {
                        $filterMatchCount = $global:interfacesView.FindName('FilterMatchCount')
                        if ($filterMatchCount) {
                            $total = @($global:interfacesGrid.ItemsSource).Count
                            $visible = @($view | ForEach-Object { $_ }).Count
                            if ([string]::IsNullOrEmpty($txt)) {
                                $filterMatchCount.Text = ''
                            } else {
                                $filterMatchCount.Text = "$visible of $total"
                                $filterMatchCount.Foreground = if ($visible -eq 0) { [System.Windows.Media.Brushes]::OrangeRed } else { [System.Windows.Media.Brushes]::LimeGreen }
                            }
                        }
                    } catch { }

                    # Save filter text to settings
                    try {
                        $settingsPath = Join-Path $PSScriptRoot '..\Data\StateTraceSettings.json'
                        $settings = @{}
                        if (Test-Path $settingsPath) {
                            $raw = Get-Content $settingsPath -Raw
                            if ($raw) {
                                $parsed = $raw | ConvertFrom-Json
                                $parsed.PSObject.Properties | ForEach-Object { $settings[$_.Name] = $_.Value }
                            }
                        }
                        $settings['LastInterfaceFilter'] = $txt
                        $settings | ConvertTo-Json -Depth 5 | Set-Content $settingsPath -Encoding UTF8
                    } catch { }
                } catch {
                    # Swallow exceptions to avoid crashing the UI on bad filter values
                }
            }
        }
        # On every key press, restart the debounce timer; the filter will
        $filterBox.Add_TextChanged({
            if ($script:InterfacesFilterTimer) {
                $script:InterfacesFilterTimer.Stop()
                $script:InterfacesFilterTimer.Start()
            }
        })
        # Escape key clears filter
        $filterBox.Add_PreviewKeyDown({
            param($sender, $e)
            if ($e.Key -eq 'Escape') {
                $global:filterBox.Text = ''
                $e.Handled = $true
            }
        })
    }

    # Selection toolbar handlers
    $selectAllBtn = $interfacesView.FindName('SelectAllButton')
    $selectNoneBtn = $interfacesView.FindName('SelectNoneButton')
    $invertBtn = $interfacesView.FindName('InvertSelectionButton')
    $selectByStatusDropdown = $interfacesView.FindName('SelectByStatusDropdown')
    $selectionCountText = $interfacesView.FindName('SelectionCountText')

    $updateSelectionCount = {
        if ($selectionCountText -and $interfacesGrid) {
            $items = $interfacesGrid.ItemsSource
            if ($items) {
                $selected = @($items | Where-Object { $_.IsSelected -eq $true })
                $total = @($items).Count
                $selectionCountText.Text = "$($selected.Count) of $total selected"
            }
        }
    }.GetNewClosure()

    if ($selectAllBtn -and $interfacesGrid) {
        $selectAllBtn.Add_Click({
            $items = $interfacesGrid.ItemsSource
            if ($items) {
                foreach ($item in $items) {
                    if ($item.PSObject.Properties['IsSelected']) { $item.IsSelected = $true }
                }
                $interfacesGrid.Items.Refresh()
                & $updateSelectionCount
            }
        }.GetNewClosure())
    }

    if ($selectNoneBtn -and $interfacesGrid) {
        $selectNoneBtn.Add_Click({
            $items = $interfacesGrid.ItemsSource
            if ($items) {
                foreach ($item in $items) {
                    if ($item.PSObject.Properties['IsSelected']) { $item.IsSelected = $false }
                }
                $interfacesGrid.Items.Refresh()
                & $updateSelectionCount
            }
        }.GetNewClosure())
    }

    if ($invertBtn -and $interfacesGrid) {
        $invertBtn.Add_Click({
            $items = $interfacesGrid.ItemsSource
            if ($items) {
                foreach ($item in $items) {
                    if ($item.PSObject.Properties['IsSelected']) { $item.IsSelected = -not $item.IsSelected }
                }
                $interfacesGrid.Items.Refresh()
                & $updateSelectionCount
            }
        }.GetNewClosure())
    }

    if ($selectByStatusDropdown -and $interfacesGrid) {
        $selectByStatusDropdown.Add_SelectionChanged({
            param($sender, $e)
            $selected = $selectByStatusDropdown.SelectedItem
            if (-not $selected) { return }
            $content = if ($selected -is [System.Windows.Controls.ComboBoxItem]) { $selected.Content } else { $selected }
            $items = $interfacesGrid.ItemsSource
            if (-not $items) { return }

            switch ($content) {
                'All Up' {
                    foreach ($item in $items) {
                        if ($item.PSObject.Properties['IsSelected']) {
                            $item.IsSelected = [string]::Equals($item.Status, 'Up', [System.StringComparison]::OrdinalIgnoreCase)
                        }
                    }
                    $interfacesGrid.Items.Refresh()
                    & $updateSelectionCount
                }
                'All Down' {
                    foreach ($item in $items) {
                        if ($item.PSObject.Properties['IsSelected']) {
                            $item.IsSelected = [string]::Equals($item.Status, 'Down', [System.StringComparison]::OrdinalIgnoreCase)
                        }
                    }
                    $interfacesGrid.Items.Refresh()
                    & $updateSelectionCount
                }
            }
            # Reset dropdown to placeholder
            $selectByStatusDropdown.SelectedIndex = 0
        }.GetNewClosure())
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

    # Quick action: Copy port names only
    if ($copyPortsButton -and $interfacesGrid) {
        $copyPortsButton.Add_Click({
            $grid = $global:interfacesGrid
            $rawSelected = Get-SelectedInterfaceRows -Grid $grid
            $selectedRows = @($rawSelected)
            if ($selectedRows.Count -eq 0) {
                [System.Windows.MessageBox]::Show("No interfaces selected.")
                return
            }
            $ports = $selectedRows | ForEach-Object { $_.Port } | Where-Object { $_ }
            Set-Clipboard -Value ($ports -join "`r`n")
            [System.Windows.MessageBox]::Show("Copied $($ports.Count) port name(s) to clipboard.")
        })
    }

    # Quick action: Copy MAC addresses only
    if ($copyMacsButton -and $interfacesGrid) {
        $copyMacsButton.Add_Click({
            $grid = $global:interfacesGrid
            $rawSelected = Get-SelectedInterfaceRows -Grid $grid
            $selectedRows = @($rawSelected)
            if ($selectedRows.Count -eq 0) {
                [System.Windows.MessageBox]::Show("No interfaces selected.")
                return
            }
            $macs = $selectedRows | ForEach-Object { $_.LearnedMACs } | Where-Object { $_ -and $_ -ne '' }
            if ($macs.Count -eq 0) {
                [System.Windows.MessageBox]::Show("No MAC addresses found on selected interfaces.")
                return
            }
            Set-Clipboard -Value ($macs -join "`r`n")
            [System.Windows.MessageBox]::Show("Copied $($macs.Count) MAC address(es) to clipboard.")
        })
    }

    # Quick action: Copy as formatted table
    $copyTableButton = $interfacesView.FindName('CopyTableButton')
    if ($copyTableButton -and $interfacesGrid) {
        $copyTableButton.Add_Click({
            $grid = $global:interfacesGrid
            $rawSelected = Get-SelectedInterfaceRows -Grid $grid
            $selectedRows = @($rawSelected)
            if ($selectedRows.Count -eq 0) {
                [System.Windows.MessageBox]::Show("No interfaces selected.")
                return
            }
            # Build tab-separated table
            $header = "Port`tName`tStatus`tVLAN`tDuplex`tSpeed`tType`tLearnedMACs`tAuthState"
            $rows = $selectedRows | ForEach-Object {
                "$($_.Port)`t$($_.Name)`t$($_.Status)`t$($_.VLAN)`t$($_.Duplex)`t$($_.Speed)`t$($_.Type)`t$($_.LearnedMACs)`t$($_.AuthState)"
            }
            $table = @($header) + $rows
            Set-Clipboard -Value ($table -join "`r`n")
            [System.Windows.MessageBox]::Show("Copied $($selectedRows.Count) row(s) as table to clipboard.")
        })
    }

    # Quick action: Export selected rows with format selection
    if ($exportSelectedBtn -and $interfacesGrid) {
        $exportSelectedBtn.Add_Click({
            $grid = $global:interfacesGrid
            $rawSelected = Get-SelectedInterfaceRows -Grid $grid
            $selectedRows = @($rawSelected)
            if ($selectedRows.Count -eq 0) {
                [System.Windows.MessageBox]::Show("No interfaces selected.")
                return
            }

            # Get format from dropdown
            $format = 'CSV'
            if ($exportFormatDropdown -and $exportFormatDropdown.SelectedItem) {
                $format = $exportFormatDropdown.SelectedItem.Content
            }

            switch ($format) {
                'Clipboard' {
                    # Copy as tab-separated table to clipboard
                    $header = "Port`tName`tStatus`tVLAN`tDuplex`tSpeed`tType`tLearnedMACs`tAuthState"
                    $rows = $selectedRows | ForEach-Object {
                        "$($_.Port)`t$($_.Name)`t$($_.Status)`t$($_.VLAN)`t$($_.Duplex)`t$($_.Speed)`t$($_.Type)`t$($_.LearnedMACs)`t$($_.AuthState)"
                    }
                    $table = @($header) + $rows
                    Set-Clipboard -Value ($table -join "`r`n")
                    [System.Windows.MessageBox]::Show("Copied $($selectedRows.Count) row(s) to clipboard.", "Export", "OK", "Information")
                }
                'JSON' {
                    # Export to JSON file
                    $dlg = New-Object Microsoft.Win32.SaveFileDialog
                    $dlg.Filter = 'JSON files (*.json)|*.json'
                    $dlg.FileName = 'SelectedInterfaces.json'
                    $dlg.DefaultExt = '.json'
                    if ($dlg.ShowDialog() -eq $true) {
                        $json = $selectedRows | ConvertTo-Json -Depth 10
                        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
                        [System.IO.File]::WriteAllText($dlg.FileName, $json, $utf8NoBom)
                        [System.Windows.MessageBox]::Show("Exported $($selectedRows.Count) interfaces to $($dlg.FileName)", "Export", "OK", "Information")
                    }
                }
                default {
                    # CSV (default)
                    $dlg = New-Object Microsoft.Win32.SaveFileDialog
                    $dlg.Filter = 'CSV files (*.csv)|*.csv'
                    $dlg.FileName = 'SelectedInterfaces.csv'
                    $dlg.DefaultExt = '.csv'
                    if ($dlg.ShowDialog() -eq $true) {
                        $selectedRows | Export-Csv -Path $dlg.FileName -NoTypeInformation
                        [System.Windows.MessageBox]::Show("Exported $($selectedRows.Count) interfaces to $($dlg.FileName)", "Export", "OK", "Information")
                    }
                }
            }
        }.GetNewClosure())
    }

    # Batch VLAN edit
    if ($setVlanButton -and $interfacesGrid) {
        $setVlanButton.Add_Click({
            $grid = $global:interfacesGrid
            $rawSelected = Get-SelectedInterfaceRows -Grid $grid
            $selectedRows = @($rawSelected)
            if ($selectedRows.Count -eq 0) {
                [System.Windows.MessageBox]::Show("No interfaces selected.", "Set VLAN", 'OK', 'Warning')
                return
            }

            # Create simple input dialog
            Add-Type -AssemblyName Microsoft.VisualBasic
            $input = [Microsoft.VisualBasic.Interaction]::InputBox(
                "Enter VLAN number (1-4094) for $($selectedRows.Count) interface(s):",
                "Set VLAN",
                ""
            )

            if ([string]::IsNullOrWhiteSpace($input)) { return }

            $vlan = 0
            if (-not [int]::TryParse($input.Trim(), [ref]$vlan) -or $vlan -lt 1 -or $vlan -gt 4094) {
                [System.Windows.MessageBox]::Show("VLAN must be a number between 1 and 4094.", "Invalid VLAN", 'OK', 'Warning')
                return
            }

            # Apply VLAN to all selected rows
            foreach ($row in $selectedRows) {
                $row.VLAN = $vlan.ToString()
            }
            $grid.Items.Refresh()
            [System.Windows.MessageBox]::Show("Updated VLAN to $vlan for $($selectedRows.Count) interface(s).", "Set VLAN", 'OK', 'Information')
        })
    }

    # Batch Name edit
    if ($setNameButton -and $interfacesGrid) {
        $setNameButton.Add_Click({
            $grid = $global:interfacesGrid
            $rawSelected = Get-SelectedInterfaceRows -Grid $grid
            $selectedRows = @($rawSelected)
            if ($selectedRows.Count -eq 0) {
                [System.Windows.MessageBox]::Show("No interfaces selected.", "Set Name", 'OK', 'Warning')
                return
            }

            # Create simple input dialog
            Add-Type -AssemblyName Microsoft.VisualBasic
            $input = [Microsoft.VisualBasic.Interaction]::InputBox(
                "Enter name for $($selectedRows.Count) interface(s) (max 64 chars):",
                "Set Name",
                ""
            )

            if ([string]::IsNullOrWhiteSpace($input)) { return }

            $name = $input.Trim()
            if ($name.Length -gt 64) {
                [System.Windows.MessageBox]::Show("Name cannot exceed 64 characters.", "Invalid Name", 'OK', 'Warning')
                return
            }

            # Apply name to all selected rows
            foreach ($row in $selectedRows) {
                $row.Name = $name
            }
            $grid.Items.Refresh()
            [System.Windows.MessageBox]::Show("Updated name to '$name' for $($selectedRows.Count) interface(s).", "Set Name", 'OK', 'Information')
        })
    }

    # Select by pattern
    if ($selectPatternButton -and $interfacesGrid) {
        $selectPatternButton.Add_Click({
            $grid = $global:interfacesGrid
            if (-not $grid -or -not $grid.ItemsSource) {
                [System.Windows.MessageBox]::Show("No interface data loaded.", "Select Pattern", 'OK', 'Warning')
                return
            }

            Add-Type -AssemblyName Microsoft.VisualBasic
            $pattern = [Microsoft.VisualBasic.Interaction]::InputBox(
                "Enter pattern to match port names:`n`nExamples:`n  Gi1/0/*  - All GigabitEthernet 1/0 ports`n  Te*      - All TenGig ports`n  *1/0/1   - Port 1/0/1 on any module`n  Gi1/0/[1-12] - Ports 1-12",
                "Select by Pattern",
                "Gi1/0/*"
            )

            if ([string]::IsNullOrWhiteSpace($pattern)) { return }

            # Convert wildcard pattern to regex
            $regexPattern = '^' + [regex]::Escape($pattern).Replace('\*', '.*').Replace('\?', '.') + '$'
            # Handle range patterns like [1-12]
            $regexPattern = $regexPattern -replace '\\\[(\d+)-(\d+)\\\]', {
                $start = [int]$_.Groups[1].Value
                $end = [int]$_.Groups[2].Value
                '(' + (($start..$end) -join '|') + ')'
            }

            $matchCount = 0
            foreach ($row in $grid.ItemsSource) {
                $port = '' + $row.Port
                if ($port -match $regexPattern) {
                    $row.IsSelected = $true
                    $matchCount++
                }
            }
            $grid.Items.Refresh()

            if ($matchCount -eq 0) {
                [System.Windows.MessageBox]::Show("No ports matched pattern '$pattern'", "Select Pattern", 'OK', 'Information')
            } else {
                [System.Windows.MessageBox]::Show("Selected $matchCount port(s) matching '$pattern'", "Select Pattern", 'OK', 'Information')
            }
        })
    }

    # Compare two interfaces
    if ($compareButton -and $interfacesGrid) {
        $compareButton.Add_Click({
            $grid = $global:interfacesGrid
            $rawSelected = Get-SelectedInterfaceRows -Grid $grid
            $selectedRows = @($rawSelected)

            if ($selectedRows.Count -ne 2) {
                [System.Windows.MessageBox]::Show("Please select exactly 2 interfaces to compare.", "Compare Interfaces", 'OK', 'Warning')
                return
            }

            $int1 = $selectedRows[0]
            $int2 = $selectedRows[1]

            # Build comparison table
            $properties = @('Port', 'Name', 'Status', 'VLAN', 'Duplex', 'Speed', 'Type', 'LearnedMACs', 'AuthState', 'AuthMode', 'AuthClientMAC')
            $comparisonLines = @()
            $comparisonLines += "Interface Comparison"
            $comparisonLines += "=" * 60
            $comparisonLines += ""
            $comparisonLines += "{0,-15} {1,-20} {2,-20}" -f "Property", $int1.Port, $int2.Port
            $comparisonLines += "{0,-15} {1,-20} {2,-20}" -f ("-" * 15), ("-" * 20), ("-" * 20)

            foreach ($prop in $properties) {
                $val1 = '' + $int1.$prop
                $val2 = '' + $int2.$prop
                $marker = if ($val1 -ne $val2) { " *" } else { "" }
                # Truncate long values
                if ($val1.Length -gt 18) { $val1 = $val1.Substring(0, 15) + "..." }
                if ($val2.Length -gt 18) { $val2 = $val2.Substring(0, 15) + "..." }
                $comparisonLines += "{0,-15} {1,-20} {2,-20}{3}" -f $prop, $val1, $val2, $marker
            }

            $comparisonLines += ""
            $comparisonLines += "* = values differ"

            $comparisonText = $comparisonLines -join "`n"
            [System.Windows.MessageBox]::Show($comparisonText, "Compare: $($int1.Port) vs $($int2.Port)", 'OK', 'Information')
        })
    }

    # Auto-fit columns to content
    if ($autoFitButton -and $interfacesGrid) {
        $autoFitButton.Add_Click({
            $grid = $global:interfacesGrid
            if (-not $grid) { return }

            foreach ($col in $grid.Columns) {
                if ($col.Visibility -eq 'Visible') {
                    # Set width to Auto to fit content, then back to explicit to allow user resize
                    $col.Width = [System.Windows.Controls.DataGridLength]::Auto
                }
            }

            # Update column widths after auto-fit completes
            $grid.UpdateLayout()

            # Convert Auto widths to explicit widths so users can still resize
            foreach ($col in $grid.Columns) {
                if ($col.Visibility -eq 'Visible') {
                    $actualWidth = $col.ActualWidth
                    if ($actualWidth -gt 0) {
                        $col.Width = New-Object System.Windows.Controls.DataGridLength($actualWidth)
                    }
                }
            }
        })
    }

    # Column visibility menu
    if ($columnsButton -and $interfacesGrid) {
        # Open context menu on button click
        $columnsButton.Add_Click({
            $btn = $columnsButton
            if ($btn.ContextMenu) {
                $btn.ContextMenu.PlacementTarget = $btn
                $btn.ContextMenu.IsOpen = $true
            }
        }.GetNewClosure())

        # Map menu item names to column headers (skip checkbox column at index 0)
        $columnMap = @{
            'ColPort'      = 'Port'
            'ColName'      = 'Name'
            'ColStatus'    = 'Status'
            'ColVLAN'      = 'VLAN'
            'ColDuplex'    = 'Duplex'
            'ColSpeed'     = 'Speed'
            'ColType'      = 'Type'
            'ColMACs'      = 'LearnedMACs'
            'ColAuthState' = 'AuthState'
            'ColAuthMode'  = 'AuthMode'
            'ColAuthMAC'   = 'AuthClientMAC'
        }

        # Wire up each menu item
        foreach ($itemName in $columnMap.Keys) {
            $headerName = $columnMap[$itemName]
            $menuItem = $columnsButton.ContextMenu.Items | Where-Object { $_.Name -eq $itemName } | Select-Object -First 1
            if ($menuItem) {
                $menuItem.Add_Checked({
                    param($sender, $e)
                    $header = $sender.Header
                    $col = $global:interfacesGrid.Columns | Where-Object { $_.Header -eq $header } | Select-Object -First 1
                    if ($col) { $col.Visibility = [System.Windows.Visibility]::Visible }
                })
                $menuItem.Add_Unchecked({
                    param($sender, $e)
                    $header = $sender.Header
                    $col = $global:interfacesGrid.Columns | Where-Object { $_.Header -eq $header } | Select-Object -First 1
                    if ($col) { $col.Visibility = [System.Windows.Visibility]::Collapsed }
                })
            }
        }
    }

    # Compact mode toggle
    $compactToggle = $interfacesView.FindName('CompactModeToggle')
    if ($compactToggle -and $interfacesGrid) {
        $compactToggle.Add_Checked({
            $grid = $global:interfacesGrid
            if ($grid) {
                $grid.RowHeight = 20
                $grid.FontSize = 11
            }
        })
        $compactToggle.Add_Unchecked({
            $grid = $global:interfacesGrid
            if ($grid) {
                $grid.RowHeight = [System.Double]::NaN  # Auto
                $grid.FontSize = 12
            }
        })
    }

    # Sort presets dropdown
    if ($sortPresetDropdown -and $interfacesGrid) {
        $sortPresetDropdown.Add_SelectionChanged({
            $sel = $sortPresetDropdown.SelectedItem
            if (-not $sel) { return }
            $text = $sel.Content
            if ($text -eq 'Sort by...') { return }

            $grid = $global:interfacesGrid
            $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($grid.ItemsSource)
            if (-not $view) { return }

            $view.SortDescriptions.Clear()

            switch ($text) {
                'Port' {
                    $view.SortDescriptions.Add([System.ComponentModel.SortDescription]::new('Port', 'Ascending'))
                }
                'Name' {
                    $view.SortDescriptions.Add([System.ComponentModel.SortDescription]::new('Name', 'Ascending'))
                }
                'Status' {
                    $view.SortDescriptions.Add([System.ComponentModel.SortDescription]::new('Status', 'Ascending'))
                }
                'VLAN' {
                    $view.SortDescriptions.Add([System.ComponentModel.SortDescription]::new('VLAN', 'Ascending'))
                }
                'Issues First' {
                    # Sort by Status descending to put "down" before "up"
                    $view.SortDescriptions.Add([System.ComponentModel.SortDescription]::new('Status', 'Descending'))
                    $view.SortDescriptions.Add([System.ComponentModel.SortDescription]::new('Port', 'Ascending'))
                }
            }

            # Reset dropdown to placeholder
            $sortPresetDropdown.SelectedIndex = 0
        }.GetNewClosure())
    }

    # Group by dropdown - group rows by field
    if ($groupByDropdown -and $interfacesGrid) {
        $groupByDropdown.Add_SelectionChanged({
            $sel = $groupByDropdown.SelectedItem
            if (-not $sel) { return }
            $text = $sel.Content
            if ($text -eq 'Group by...') { return }

            $grid = $global:interfacesGrid
            if (-not $grid -or -not $grid.ItemsSource) { return }
            $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($grid.ItemsSource)
            if (-not $view) { return }

            $view.GroupDescriptions.Clear()

            if ($text -ne 'None') {
                $groupProp = $text
                $view.GroupDescriptions.Add([System.Windows.Data.PropertyGroupDescription]::new($groupProp))
            }

            $view.Refresh()
        }.GetNewClosure())
    }

    # Filter presets - save, load, delete
    if ($filterPresetsDropdown -and $filterBox) {
        # Load saved presets on init
        $settingsPath = Join-Path $PSScriptRoot '..\Data\StateTraceSettings.json'
        try {
            if (Test-Path $settingsPath) {
                $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
                if ($settings.FilterPresets) {
                    foreach ($preset in $settings.FilterPresets) {
                        $item = [System.Windows.Controls.ComboBoxItem]::new()
                        $item.Content = $preset.Name
                        $item.Tag = $preset.FilterText
                        $filterPresetsDropdown.Items.Add($item) | Out-Null
                    }
                }
            }
        } catch { }

        # Load preset when selected
        $filterPresetsDropdown.Add_SelectionChanged({
            $sel = $filterPresetsDropdown.SelectedItem
            if (-not $sel -or $sel.Content -eq 'Presets...') { return }
            $filterText = $sel.Tag
            if ($filterText -ne $null) {
                $global:filterBox.Text = $filterText
            }
        }.GetNewClosure())
    }

    # Save preset button
    if ($savePresetButton -and $filterBox -and $filterPresetsDropdown) {
        $savePresetButton.Add_Click({
            $currentFilter = $global:filterBox.Text
            if ([string]::IsNullOrWhiteSpace($currentFilter)) {
                [System.Windows.MessageBox]::Show("Enter a filter text first", "Save Preset", "OK", "Information")
                return
            }
            $name = [Microsoft.VisualBasic.Interaction]::InputBox("Enter a name for this filter preset:", "Save Filter Preset", "")
            if ([string]::IsNullOrWhiteSpace($name)) { return }

            $settingsPath = Join-Path $PSScriptRoot '..\Data\StateTraceSettings.json'
            $settings = @{}
            try {
                if (Test-Path $settingsPath) {
                    $raw = Get-Content $settingsPath -Raw
                    if ($raw) {
                        $parsed = $raw | ConvertFrom-Json
                        $parsed.PSObject.Properties | ForEach-Object { $settings[$_.Name] = $_.Value }
                    }
                }
            } catch { }

            if (-not $settings.FilterPresets) {
                $settings['FilterPresets'] = @()
            }
            # Remove existing preset with same name
            $settings['FilterPresets'] = @($settings['FilterPresets'] | Where-Object { $_.Name -ne $name })
            $settings['FilterPresets'] += @{ Name = $name; FilterText = $currentFilter }

            try {
                $settings | ConvertTo-Json -Depth 5 | Set-Content $settingsPath -Encoding UTF8
            } catch { }

            # Add to dropdown
            $item = [System.Windows.Controls.ComboBoxItem]::new()
            $item.Content = $name
            $item.Tag = $currentFilter
            $filterPresetsDropdown.Items.Add($item) | Out-Null
            $filterPresetsDropdown.SelectedIndex = $filterPresetsDropdown.Items.Count - 1
        }.GetNewClosure())
    }

    # Delete preset button
    if ($deletePresetButton -and $filterPresetsDropdown) {
        $deletePresetButton.Add_Click({
            $sel = $filterPresetsDropdown.SelectedItem
            if (-not $sel -or $sel.Content -eq 'Presets...') {
                [System.Windows.MessageBox]::Show("Select a preset to delete", "Delete Preset", "OK", "Information")
                return
            }
            $name = $sel.Content
            $result = [System.Windows.MessageBox]::Show("Delete preset '$name'?", "Confirm Delete", "YesNo", "Question")
            if ($result -ne 'Yes') { return }

            $settingsPath = Join-Path $PSScriptRoot '..\Data\StateTraceSettings.json'
            $settings = @{}
            try {
                if (Test-Path $settingsPath) {
                    $raw = Get-Content $settingsPath -Raw
                    if ($raw) {
                        $parsed = $raw | ConvertFrom-Json
                        $parsed.PSObject.Properties | ForEach-Object { $settings[$_.Name] = $_.Value }
                    }
                }
            } catch { }

            if ($settings.FilterPresets) {
                $settings['FilterPresets'] = @($settings['FilterPresets'] | Where-Object { $_.Name -ne $name })
            }

            try {
                $settings | ConvertTo-Json -Depth 5 | Set-Content $settingsPath -Encoding UTF8
            } catch { }

            # Remove from dropdown
            $filterPresetsDropdown.Items.Remove($sel)
            $filterPresetsDropdown.SelectedIndex = 0
        }.GetNewClosure())
    }

    # Context menu for interfaces grid
    if ($interfacesGrid -and $interfacesGrid.ContextMenu) {
        $ctxMenu = $interfacesGrid.ContextMenu

        # Copy Port
        $ctxCopyPort = $ctxMenu.Items | Where-Object { $_.Name -eq 'CtxCopyPort' } | Select-Object -First 1
        if ($ctxCopyPort) {
            $ctxCopyPort.Add_Click({
                $grid = $global:interfacesGrid
                $item = $grid.CurrentItem
                if ($item -and $item.Port) {
                    Set-Clipboard -Value $item.Port
                }
            })
        }

        # Copy MAC
        $ctxCopyMAC = $ctxMenu.Items | Where-Object { $_.Name -eq 'CtxCopyMAC' } | Select-Object -First 1
        if ($ctxCopyMAC) {
            $ctxCopyMAC.Add_Click({
                $grid = $global:interfacesGrid
                $item = $grid.CurrentItem
                if ($item -and $item.LearnedMACs) {
                    Set-Clipboard -Value $item.LearnedMACs
                }
            })
        }

        # Copy Details
        $ctxCopyDetails = $ctxMenu.Items | Where-Object { $_.Name -eq 'CtxCopyDetails' } | Select-Object -First 1
        if ($ctxCopyDetails) {
            $ctxCopyDetails.Add_Click({
                $grid = $global:interfacesGrid
                $item = $grid.CurrentItem
                if ($item) {
                    $details = @(
                        "Port:        $($item.Port)",
                        "Name:        $($item.Name)",
                        "Status:      $($item.Status)",
                        "VLAN:        $($item.VLAN)",
                        "Duplex:      $($item.Duplex)",
                        "Speed:       $($item.Speed)",
                        "Type:        $($item.Type)",
                        "LearnedMACs: $($item.LearnedMACs)",
                        "AuthState:   $($item.AuthState)",
                        "AuthMode:    $($item.AuthMode)",
                        "Client MAC:  $($item.AuthClientMAC)"
                    ) -join "`r`n"
                    Set-Clipboard -Value $details
                }
            })
        }

        # Export Selected
        $ctxExport = $ctxMenu.Items | Where-Object { $_.Name -eq 'CtxExportSelected' } | Select-Object -First 1
        if ($ctxExport) {
            $ctxExport.Add_Click({
                $grid = $global:interfacesGrid
                $rawSelected = Get-SelectedInterfaceRows -Grid $grid
                $selectedRows = @($rawSelected)
                if ($selectedRows.Count -eq 0) {
                    [System.Windows.MessageBox]::Show("No interfaces selected.")
                    return
                }
                Export-StRowsWithFormatChoice -Rows $selectedRows -DefaultBaseName 'SelectedInterfaces' -SuccessNoun 'interfaces'
            })
        }

        # Select Same Status
        $ctxSelectStatus = $ctxMenu.Items | Where-Object { $_.Name -eq 'CtxSelectStatus' } | Select-Object -First 1
        if ($ctxSelectStatus) {
            $ctxSelectStatus.Add_Click({
                $grid = $global:interfacesGrid
                $item = $grid.CurrentItem
                if ($item -and $item.Status) {
                    $targetStatus = $item.Status
                    foreach ($row in $grid.ItemsSource) {
                        if ($row.Status -eq $targetStatus) {
                            $row.IsSelected = $true
                        }
                    }
                    $grid.Items.Refresh()
                }
            })
        }

        # Select Same VLAN
        $ctxSelectVLAN = $ctxMenu.Items | Where-Object { $_.Name -eq 'CtxSelectVLAN' } | Select-Object -First 1
        if ($ctxSelectVLAN) {
            $ctxSelectVLAN.Add_Click({
                $grid = $global:interfacesGrid
                $item = $grid.CurrentItem
                if ($item -and $item.VLAN) {
                    $targetVLAN = $item.VLAN
                    foreach ($row in $grid.ItemsSource) {
                        if ($row.VLAN -eq $targetVLAN) {
                            $row.IsSelected = $true
                        }
                    }
                    $grid.Items.Refresh()
                }
            })
        }
    }

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
            # Capture previous state for change detection
            $previousState = @{}
            if ($grid.ItemsSource) {
                foreach ($row in $grid.ItemsSource) {
                    if ($row.Port) {
                        $previousState[$row.Port] = @{
                            Status = $row.Status
                            VLAN   = $row.VLAN
                            Name   = $row.Name
                            Speed  = $row.Speed
                        }
                    }
                }
            }

            $itemsSource = $DeviceDetails.Interfaces
            if (-not $itemsSource) {
                $itemsSource = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
                $DeviceDetails.Interfaces = $itemsSource
            }

            # Mark changed rows
            $changedCount = 0
            if ($previousState.Count -gt 0) {
                foreach ($row in $itemsSource) {
                    $row.HasChanged = $false
                    if ($row.Port -and $previousState.ContainsKey($row.Port)) {
                        $prev = $previousState[$row.Port]
                        if ($row.Status -ne $prev.Status -or $row.VLAN -ne $prev.VLAN -or $row.Name -ne $prev.Name -or $row.Speed -ne $prev.Speed) {
                            $row.HasChanged = $true
                            $changedCount++
                        }
                    }
                }
            }

            $grid.ItemsSource = $itemsSource
            try { $global:interfacesGrid = $grid } catch {}
            try { $global:CurrentInterfaceCollection = $itemsSource } catch { $global:CurrentInterfaceCollection = $null }
            try { $global:InterfaceChangedCount = $changedCount } catch {}

            # Update last updated timestamp
            $lastUpdatedText = $interfacesView.FindName('InterfacesLastUpdatedText')
            if ($lastUpdatedText) {
                $lastUpdatedText.Text = "Updated: $(Get-Date -Format 'h:mm tt')"
            }

            # Update port status summary
            $statusSummary = $interfacesView.FindName('PortStatusSummary')
            if ($statusSummary -and $itemsSource) {
                $total = @($itemsSource).Count
                # Match common up statuses: up, connected, Up, Connected
                $up = @($itemsSource | Where-Object { $_.Status -match '(?i)^(up|connected)$' }).Count
                # Match common down statuses: down, notconnect, notconnected, disabled, Down
                $down = @($itemsSource | Where-Object { $_.Status -match '(?i)^(down|notconnect|notconnected|disabled)$' }).Count
                $other = $total - $up - $down

                # Count validation warnings
                $missingVlan = @($itemsSource | Where-Object { -not $_.VLAN -or $_.VLAN -eq '' -or $_.VLAN -eq '0' }).Count
                $errorStatus = @($itemsSource | Where-Object { $_.Status -match '(?i)(err|disabled|notconnect)' }).Count
                $warnings = $missingVlan + $errorStatus

                $summaryText = "$total ports: $up up, $down down"
                if ($other -gt 0) { $summaryText += ", $other other" }
                if ($changedCount -gt 0) { $summaryText += " | $changedCount changed" }
                if ($warnings -gt 0) {
                    $summaryText += " | $warnings warnings"
                    $statusSummary.Foreground = [System.Windows.Media.Brushes]::Orange
                } elseif ($changedCount -gt 0) {
                    $statusSummary.Foreground = [System.Windows.Media.Brushes]::DodgerBlue
                } else {
                    $statusSummary.Foreground = $interfacesView.FindResource('Theme.Text.Muted')
                }
                $statusSummary.Text = $summaryText

                # Update tab header with count
                try {
                    $mainWindow = [System.Windows.Application]::Current.MainWindow
                    if ($mainWindow) {
                        $interfacesTab = $mainWindow.FindName('InterfacesTab')
                        if ($interfacesTab) {
                            $interfacesTab.Header = "Interfaces ($total)"
                        }
                    }
                } catch { }
            }
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
    } catch [System.Management.Automation.CommandNotFoundException] {
    } catch { }
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

Export-ModuleMember -Function Get-PortSortKey,Get-PortSortCacheStatistics,Reset-PortSortCache,Get-InterfaceInfo,Get-InterfaceList,New-InterfaceObjectsFromDbRow,Get-InterfaceConfiguration,Set-InterfaceViewData,Get-SpanningTreeInfo,New-InterfacesView,Set-PortLoadingIndicator,Hide-PortLoadingIndicator,Set-HostLoadingIndicator
