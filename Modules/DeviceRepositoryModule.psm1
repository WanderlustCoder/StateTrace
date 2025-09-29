Set-StrictMode -Version Latest

if (-not (Get-Variable -Scope Script -Name ModuleRootPath -ErrorAction SilentlyContinue)) {
    try {
        $script:ModuleRootPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    } catch {
        $script:ModuleRootPath = Split-Path -Parent $PSScriptRoot
    }
}

if (-not (Get-Variable -Scope Script -Name DataDirPath -ErrorAction SilentlyContinue)) {
    $rootPath = if ($script:ModuleRootPath) { $script:ModuleRootPath } else { Split-Path -Parent $PSScriptRoot }
    $script:DataDirPath = Join-Path $rootPath 'Data'
}

if (-not (Get-Variable -Scope Script -Name SiteInterfaceCache -ErrorAction SilentlyContinue)) {
    $script:SiteInterfaceCache = @{}
}

if (-not (Get-Variable -Scope Global -Name DeviceInterfaceCache -ErrorAction SilentlyContinue)) {
    $global:DeviceInterfaceCache = @{}
}

if (-not (Get-Variable -Scope Global -Name AllInterfaces -ErrorAction SilentlyContinue)) {
    $global:AllInterfaces = New-Object 'System.Collections.Generic.List[object]'
}

if (-not (Get-Variable -Scope Global -Name LoadedSiteZones -ErrorAction SilentlyContinue)) {
    $global:LoadedSiteZones = @{}
}

function Get-DataDirectoryPath {
    [CmdletBinding()]
    param()
    if (-not (Get-Variable -Scope Script -Name DataDirPath -ErrorAction SilentlyContinue)) {
        if (-not (Get-Variable -Scope Script -Name ModuleRootPath -ErrorAction SilentlyContinue)) {
            try {
                $script:ModuleRootPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
            } catch {
                $script:ModuleRootPath = Split-Path -Parent $PSScriptRoot
            }
        }
        $rootPath = if ($script:ModuleRootPath) { $script:ModuleRootPath } else { Split-Path -Parent $PSScriptRoot }
        $script:DataDirPath = Join-Path $rootPath 'Data'
    }
    return $script:DataDirPath
}

function Get-SiteFromHostname {
    [CmdletBinding()]
    param(
        [string]$Hostname,
        [int]$FallbackLength = 0
    )

    if ([string]::IsNullOrWhiteSpace($Hostname)) { return 'Unknown' }

    $clean = ('' + $Hostname).Trim()
    if ($clean -like 'SSH@*') { $clean = $clean.Substring(4) }
    $clean = $clean.Trim()

    if ($clean -match '^(?<site>[^-]+)-') {
        return $matches['site']
    }

    if ($FallbackLength -gt 0 -and $clean.Length -ge $FallbackLength) {
        return $clean.Substring(0, $FallbackLength)
    }

    return $clean
}


function Get-DbPathForSite {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Site)

    $siteCode = ('' + $Site).Trim()
    if ([string]::IsNullOrWhiteSpace($siteCode)) { $siteCode = 'Unknown' }

    $dataDir = Get-DataDirectoryPath
    $prefix = $siteCode
    $dashIndex = $prefix.IndexOf('-')
    if ($dashIndex -gt 0) { $prefix = $prefix.Substring(0, $dashIndex) }

    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    foreach ($ch in $invalidChars) {
        $prefix = $prefix.Replace([string]$ch, '_')
    }
    if ([string]::IsNullOrWhiteSpace($prefix)) { $prefix = 'Unknown' }

    $modernDir = Join-Path $dataDir $prefix
    $modernPath = Join-Path $modernDir ("{0}.accdb" -f $siteCode)
    $legacyPath = Join-Path $dataDir ("{0}.accdb" -f $siteCode)

    if (Test-Path -LiteralPath $modernPath) { return $modernPath }
    if (Test-Path -LiteralPath $legacyPath) { return $legacyPath }

    return $modernPath
}

function Get-DbPathForHost {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Hostname)
    $site = Get-SiteFromHostname -Hostname $Hostname
    return Get-DbPathForSite -Site $site
}

function Get-AllSiteDbPaths {
    [CmdletBinding()]
    param()
    $dataDir = Get-DataDirectoryPath
    if (-not (Test-Path $dataDir)) { return @() }
    $files = Get-ChildItem -Path $dataDir -Filter '*.accdb' -File -Recurse
    $list = New-Object 'System.Collections.Generic.List[string]'
    foreach ($f in $files) { [void]$list.Add($f.FullName) }
    return $list.ToArray()
}

function Clear-SiteInterfaceCache {
    [CmdletBinding()]
    param()
    try {
        $script:SiteInterfaceCache = @{}
    } catch {
        Set-Variable -Name SiteInterfaceCache -Scope Script -Value @{}
    }
}

function Import-DatabaseModule {
    [CmdletBinding()]
    param()
    try {
        # Check by module name rather than path; avoids multiple loads when
        # different relative paths point at the same module.  If DatabaseModule
        # isn't loaded yet, attempt to import it from this folder.  The
        # Force/Global flags mirror the original behaviour but only run once.
        if (-not (Get-Module -Name DatabaseModule)) {
            $dbModulePath = Join-Path $PSScriptRoot 'DatabaseModule.psm1'
            if (Test-Path $dbModulePath) {
                Import-Module $dbModulePath -Force -Global -ErrorAction SilentlyContinue | Out-Null
            }
        }
    } catch {
        # Swallow any import errors; downstream functions will handle missing cmdlets.
    }
}

# Retrieve the currently selected site, building and room from the main


function Update-SiteZoneCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Site,
        [string]$Zone
    )
    if ([string]::IsNullOrWhiteSpace($Site)) { return }
    $zoneKey = if ([string]::IsNullOrWhiteSpace($Zone) -or ($Zone -ieq 'All Zones')) { '' } else { '' + $Zone }
    $key = "$Site|$zoneKey"
    if ($global:LoadedSiteZones.ContainsKey($key)) { return }
    $global:LoadedSiteZones[$key] = $true

    $hostNames = @()
    try {
        if ($global:DeviceMetadata) {
            foreach ($entry in $global:DeviceMetadata.GetEnumerator()) {
                $hn = $entry.Key
                $meta = $entry.Value
                if ($meta.Site -and $meta.Site -ne $Site) { continue }
                if ($zoneKey -ne '') {
                    $mZone = $null
                    try {
                        if ($meta.PSObject.Properties['Zone']) { $mZone = '' + $meta.Zone }
                    } catch {
                        $mZone = $null
                    }
                    if ($mZone -and $mZone -ne $zoneKey) { continue }
                }
                $hostNames += $hn
            }
        } elseif (Get-Command -Name Get-InterfaceHostnames -ErrorAction SilentlyContinue) {
            $names = Get-InterfaceHostnames -Site $Site
            foreach ($n in $names) {
                if ($zoneKey -ne '') {
                    $parts = ($n -split '-')
                    if ($parts.Count -ge 2) {
                        $zonePart = $parts[1]
                        if ($zonePart -ne $zoneKey) { continue }
                    }
                }
                $hostNames += $n
            }
        }
    } catch {
        return
    }

    if (-not $hostNames -or $hostNames.Count -eq 0) { return }

    $newRows = New-Object 'System.Collections.Generic.List[object]'
    foreach ($hn in $hostNames) {
        if ($global:DeviceInterfaceCache.ContainsKey($hn)) { continue }
        try {
            $ifaceList = Get-InterfaceInfo -Hostname $hn
            if ($ifaceList) {
                foreach ($row in $ifaceList) { [void]$newRows.Add($row) }
            }
        } catch {
        }
    }

    if ($newRows.Count -gt 0) {
        try {
            if (-not $global:AllInterfaces) {
                $global:AllInterfaces = $newRows
            } else {
                foreach ($r in $newRows) { [void]$global:AllInterfaces.Add($r) }
            }
        } catch {
        }
    }
}
function Invoke-ParallelDbQuery {
    [CmdletBinding()]
    param(
        [string[]]$DbPaths,
        [string]$Sql
    )
    if (-not $DbPaths -or $DbPaths.Count -eq 0) {
        return @()
    }
    try { Import-DatabaseModule } catch {}
    $modulePath = Join-Path $PSScriptRoot 'DatabaseModule.psm1'
    $maxThreads = [Math]::Max(1, [Environment]::ProcessorCount)
    $pool = [runspacefactory]::CreateRunspacePool(1, $maxThreads)
    $pool.Open()
    $jobs = @()
    foreach ($dbPath in $DbPaths) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool
        $null = $ps.AddScript({
            param($dbPathArg, $sqlArg, $modPath)
            try { Import-Module -Name $modPath -DisableNameChecking -Force } catch {}
            try {
                return Invoke-DbQuery -DatabasePath $dbPathArg -Sql $sqlArg
            } catch {
                return $null
            }
        }).AddArgument($dbPath).AddArgument($Sql).AddArgument($modulePath)
        $job = [pscustomobject]@{ PS = $ps; AsyncResult = $ps.BeginInvoke() }
        $jobs += $job
    }
    $results = New-Object 'System.Collections.Generic.List[object]'
    foreach ($job in $jobs) {
        try {
            $dt = $job.PS.EndInvoke($job.AsyncResult)
            if ($dt) { [void]$results.Add($dt) }
        } catch {}
        finally {
            $job.PS.Dispose()
        }
    }
    $pool.Close()
    $pool.Dispose()
    return $results.ToArray()
}
function Get-GlobalInterfaceSnapshot {
    [CmdletBinding()]
    param(
        [string]$Site,
        [string]$ZoneSelection,
        [string]$ZoneToLoad
    )

    $siteValue = if ($Site) { '' + $Site } else { '' }
    $zoneSelectionValue = if ($ZoneSelection) { '' + $ZoneSelection } else { '' }
    $zoneLoadValue = if ($PSBoundParameters.ContainsKey('ZoneToLoad')) { '' + $ZoneToLoad } else { '' }

    $interfaces = New-Object 'System.Collections.Generic.List[object]'
    $appendRows = {
        param($hostname, $rows)
        if (-not $rows) { return }
        foreach ($row in $rows) {
            if (-not $row) { continue }
            try {
                if (-not $row.PSObject.Properties['Hostname']) {
                    $row | Add-Member -NotePropertyName Hostname -NotePropertyValue ($hostname) -ErrorAction SilentlyContinue
                }
            } catch {}
            try {
                if (-not $row.PSObject.Properties['IsSelected']) {
                    $row | Add-Member -NotePropertyName IsSelected -NotePropertyValue $false -ErrorAction SilentlyContinue
                }
            } catch {}
            [void]$interfaces.Add($row)
        }
    }

    if ([string]::IsNullOrWhiteSpace($siteValue) -or [System.StringComparer]::OrdinalIgnoreCase.Equals($siteValue, 'All Sites')) {
        foreach ($kv in $global:DeviceInterfaceCache.GetEnumerator()) {
            & $appendRows $kv.Key $kv.Value
        }
    } else {
        $loadArg = $zoneLoadValue
        try { Update-SiteZoneCache -Site $siteValue -Zone $loadArg | Out-Null } catch {}
        foreach ($kv in $global:DeviceInterfaceCache.GetEnumerator()) {
            $hostname = $kv.Key
            $rows = $kv.Value
            if (-not $rows) { continue }
            $parts = ('' + $hostname) -split '-'
            $sitePart = if ($parts.Length -ge 1) { $parts[0] } else { '' }
            if ([System.StringComparer]::OrdinalIgnoreCase.Compare($sitePart, $siteValue) -ne 0) { continue }
            $zonePart = if ($parts.Length -ge 2) { $parts[1] } else { '' }

            if (-not [string]::IsNullOrWhiteSpace($zoneSelectionValue) -and -not [System.StringComparer]::OrdinalIgnoreCase.Equals($zoneSelectionValue, 'All Zones')) {
                if ([System.StringComparer]::OrdinalIgnoreCase.Compare($zonePart, $zoneSelectionValue) -ne 0) { continue }
            } elseif (-not [string]::IsNullOrWhiteSpace($loadArg)) {
                if ([System.StringComparer]::OrdinalIgnoreCase.Compare($zonePart, $loadArg) -ne 0) { continue }
            }

            & $appendRows $hostname $rows
        }
    }

    return ,($interfaces.ToArray())
}

function Update-GlobalInterfaceList {
    [CmdletBinding()]
    param(
        [string]$Site,
        [string]$ZoneSelection,
        [string]$ZoneToLoad
    )

    $snapshot = Get-GlobalInterfaceSnapshot @PSBoundParameters
    if ($snapshot -and $snapshot.Length -gt 0) {
        $global:AllInterfaces = [System.Collections.Generic.List[object]]::new($snapshot)
    } else {
        $global:AllInterfaces = [System.Collections.Generic.List[object]]::new()
    }
    return $global:AllInterfaces
}

function Get-InterfacesForSite {
    [CmdletBinding()]
    param(
        [string]$Site,
        [string]$ZoneSelection,
        [string]$ZoneToLoad
    )

    $snapshot = Get-GlobalInterfaceSnapshot @PSBoundParameters
    if ($snapshot -and $snapshot.Length -gt 0) {
        $global:AllInterfaces = [System.Collections.Generic.List[object]]::new($snapshot)
    } else {
        $global:AllInterfaces = [System.Collections.Generic.List[object]]::new()
    }
    return $global:AllInterfaces
}

function Get-InterfacesForSite {
    [CmdletBinding()]
    param([string]$Site)

    $siteName = if ($Site) { '' + $Site } else { '' }
    if ([string]::IsNullOrWhiteSpace($siteName) -or
        ([System.StringComparer]::OrdinalIgnoreCase.Equals($siteName, 'All Sites')) -or
        ([System.StringComparer]::OrdinalIgnoreCase.Equals($siteName, 'All')))
    {
        $combined = New-Object 'System.Collections.Generic.List[object]'
        $dbPaths = Get-AllSiteDbPaths
        foreach ($p in $dbPaths) {
            $code = ''
            try { $code = [System.IO.Path]::GetFileNameWithoutExtension($p) } catch { $code = '' }
            if (-not [string]::IsNullOrWhiteSpace($code)) {
                $siteList = Get-InterfacesForSite -Site $code
                if ($siteList) {
                    foreach ($item in $siteList) { [void]$combined.Add($item) }
                }
            }
        }
        $comparison = [System.Comparison[object]]{
            param($a, $b)
            $hnc = [System.StringComparer]::OrdinalIgnoreCase.Compare($a.Hostname, $b.Hostname)
            if ($hnc -ne 0) { return $hnc }
            return [System.StringComparer]::Ordinal.Compare($a.PortSort, $b.PortSort)
        }
        try { $combined.Sort($comparison) } catch {}
        return $combined
    }

    $siteCode = $siteName.Trim()
    if ([string]::IsNullOrWhiteSpace($siteCode)) {
        return (New-Object 'System.Collections.Generic.List[object]')
    }

    try {
        if ($script:SiteInterfaceCache.ContainsKey($siteCode)) {
            $entry = $script:SiteInterfaceCache[$siteCode]
            if ($entry -and $entry.PSObject.Properties['List'] -and $entry.PSObject.Properties['DbTime']) {
                $dbPath = Get-DbPathForSite -Site $siteCode
                $currentTime = $null
                try { $currentTime = (Get-Item -LiteralPath $dbPath).LastWriteTime } catch {}
                if ($currentTime -and ($entry.DbTime -eq $currentTime)) {
                    return $entry.List
                }
            }
        }
    } catch {}

    $dbFile = Get-DbPathForSite -Site $siteCode
    if (-not (Test-Path $dbFile)) {
        return (New-Object 'System.Collections.Generic.List[object]')
    }

    $siteEsc = $siteCode
    try {
        Import-DatabaseModule
        $siteEsc = DatabaseModule\Get-SqlLiteral -Value $siteCode
    } catch {
        $siteEsc = $siteCode -replace "'", "''"
    }
    $sqlSite = @"
SELECT i.Hostname, i.Port, i.Name, i.Status, i.VLAN, i.Duplex, i.Speed, i.Type,
       i.LearnedMACs, i.AuthState, i.AuthMode, i.AuthClientMAC,
       ds.Site, ds.Building, ds.Room, ds.Make,
       i.AuthTemplate, i.Config, i.ConfigStatus, i.PortColor, i.ToolTip
FROM Interfaces AS i
LEFT JOIN DeviceSummary AS ds ON i.Hostname = ds.Hostname
WHERE ds.Site = '$siteEsc'
ORDER BY i.Hostname, i.Port
"@

    $rows = New-Object 'System.Collections.Generic.List[object]'
    try {
        $dt = Invoke-DbQuery -DatabasePath $dbFile -Sql $sqlSite
        if ($dt) {
            $enum = $null
            if ($dt -is [System.Data.DataTable]) {
                $enum = $dt.Rows
            } elseif ($dt -is [System.Data.DataView]) {
                $enum = $dt
            } elseif ($dt -is [System.Collections.IEnumerable]) {
                $enum = $dt
            }
            if ($enum) {
                $lookupByVendor = @{}
                try {
                    $templatesDir = Join-Path $PSScriptRoot '..\Templates'
                    foreach ($vendorName in @('Cisco', 'Brocade')) {
                        $templateData = $null
                        try {
                            $templateData = TemplatesModule\Get-ConfigurationTemplateData -Vendor $vendorName -TemplatesPath $templatesDir
                        } catch {
                            $templateData = $null
                        }
                        if ($templateData -and $templateData.Exists -and $templateData.Lookup) {
                            $lookupByVendor[$vendorName] = $templateData.Lookup
                        }
                    }
                } catch {}

                foreach ($row in $enum) {
                    $hn = '' + $row.Hostname
                    $port = '' + $row.Port
                    $name = '' + $row.Name
                    $status = '' + $row.Status
                    $vlan = '' + $row.VLAN
                    $duplex = '' + $row.Duplex
                    $speed = '' + $row.Speed
                    $type = '' + $row.Type
                    $lm = '' + $row.LearnedMACs
                    $aState = '' + $row.AuthState
                    $aMode = '' + $row.AuthMode
                    $aMAC = '' + $row.AuthClientMAC
                    $siteVal = '' + $row.Site
                    $bld = '' + $row.Building
                    $room = '' + $row.Room
                    $makeVal = '' + $row.Make
                    $authTmpl = '' + $row.AuthTemplate
                    $cfgVal = '' + $row.Config
                    $cfgStatVal = '' + $row.ConfigStatus
                    $portColorVal = '' + $row.PortColor
                    $tipVal = '' + $row.ToolTip

                    $zoneValIf = ''
                    if ($hn -match '^(?<site>[^-]+)-(?<zone>[^-]+)-') {
                        $zoneValIf = $matches['zone']
                    }

                    $portSort = if (-not [string]::IsNullOrWhiteSpace($port)) {
                        InterfaceModule\Get-PortSortKey -Port $port
                    } else {
                        '99-UNK-99999-99999-99999-99999-99999'
                    }

                    $vendor = 'Cisco'
                    if ($makeVal -match '(?i)brocade') { $vendor = 'Brocade' }
                    $tmplLookup = if ($lookupByVendor.ContainsKey($vendor)) { $lookupByVendor[$vendor] } else { $null }

                    $tipCore = ($tipVal.TrimEnd())
                    if (-not $tipCore) {
                        if ($cfgVal -and ($cfgVal.Trim() -ne '')) {
                            $tipCore = "AuthTemplate: $authTmpl`r`n`r`n$cfgVal"
                        } elseif ($authTmpl) {
                            $tipCore = "AuthTemplate: $authTmpl"
                        } else {
                            $tipCore = ''
                        }
                    }

                    $finalPortColor = $portColorVal
                    $finalCfgStatus = $cfgStatVal
                    $hasPortColor = -not [string]::IsNullOrWhiteSpace($finalPortColor)
                    $hasCfgStatus = -not [string]::IsNullOrWhiteSpace($finalCfgStatus)
                    if (-not $hasPortColor -or -not $hasCfgStatus) {
                        $match = $null
                        if ($authTmpl -and $tmplLookup -and $tmplLookup.ContainsKey($authTmpl)) {
                            $match = $tmplLookup[$authTmpl]
                        }
                        if (-not $hasPortColor) {
                            $finalPortColor = if ($match) { $match.color } else { 'Gray' }
                        }
                        if (-not $hasCfgStatus) {
                            if ($match) {
                                $finalCfgStatus = 'Match'
                            } elseif ($authTmpl) {
                                $finalCfgStatus = 'Mismatch'
                            } else {
                                $finalCfgStatus = 'Unknown'
                            }
                        }
                    }

                    $obj = [PSCustomObject]@{
                        Hostname      = $hn
                        Port          = $port
                        PortSort      = $portSort
                        Name          = $name
                        Status        = $status
                        VLAN          = $vlan
                        Duplex        = $duplex
                        Speed         = $speed
                        Type          = $type
                        LearnedMACs   = $lm
                        AuthState     = $aState
                        AuthMode      = $aMode
                        AuthClientMAC = $aMAC
                        Site          = $siteVal
                        Building      = $bld
                        Room          = $room
                        Zone          = $zoneValIf
                        AuthTemplate  = $authTmpl
                        Config        = $cfgVal
                        ConfigStatus  = $finalCfgStatus
                        PortColor     = $finalPortColor
                        ToolTip       = $tipCore
                        IsSelected    = $false
                    }
                    [void]$rows.Add($obj)
                }
            }
        }
    } catch {
        Write-Warning "Failed to query interfaces for site '$siteCode': $($_.Exception.Message)"
    }

    $comparison2 = [System.Comparison[object]]{
        param($a, $b)
        $hnc2 = [System.StringComparer]::OrdinalIgnoreCase.Compare($a.Hostname, $b.Hostname)
        if ($hnc2 -ne 0) { return $hnc2 }
        return [System.StringComparer]::Ordinal.Compare($a.PortSort, $b.PortSort)
    }
    try { $rows.Sort($comparison2) } catch {}

    $dbTime = $null
    try { $dbTime = (Get-Item -LiteralPath $dbFile).LastWriteTime } catch {}
    try {
        $script:SiteInterfaceCache[$siteCode] = [PSCustomObject]@{
            List   = $rows
            DbTime = $dbTime
        }
    } catch {}
    return $rows
}

function Get-InterfaceInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [string]$TemplatesPath = (Join-Path $PSScriptRoot '..\Templates')
    )
        # Check if this host's interface details are already available in the in-memory cache.  When available,
        # simply return the cached list to avoid re-querying the database.  Ensure that any returned objects
        # expose the expected properties (Hostname, Port, IsSelected, etc.) by adding them on the fly when
        # missing.  Without this defensive injection, callers like Get-SelectedInterfaceRows may receive
        # non-PSCustomObject types (e.g. DataRow) that do not have PSObject.Properties defined, which
        # manifests as black boxes in the Interfaces grid or errors when accessing the Hostname property.
        try {
            if ($global:DeviceInterfaceCache -and $global:DeviceInterfaceCache.ContainsKey($Hostname)) {
                $cached = $global:DeviceInterfaceCache[$Hostname]
                if ($cached) {
                    foreach ($o in $cached) {
                        if ($null -eq $o) { continue }
                        # Guarantee that the object exposes a Hostname property.  Some callers may
                        # accidentally store raw database rows in the cache prior to the full preload, which
                        # lack our added properties.  Add missing properties using Add-Member.  Skip when
                        # the property already exists to avoid duplicate definitions.
                        try {
                            if (-not $o.PSObject.Properties['Hostname']) {
                                # Derive the hostname from the current context since all objects in this list
                                # correspond to the same device.  Store as a string for consistency.
                                $o | Add-Member -NotePropertyName Hostname -NotePropertyValue ($Hostname) -ErrorAction SilentlyContinue
                            }
                        } catch {}
                        try {
                            if (-not $o.PSObject.Properties['IsSelected']) {
                                # Initialise IsSelected to $false so that the DataGrid checkbox has a proper
                                # binding target.  Do not overwrite existing values.
                                $o | Add-Member -NotePropertyName IsSelected -NotePropertyValue $false -ErrorAction SilentlyContinue
                            }
                        } catch {}
                    }
                    return $cached
                }
            }
        } catch {}
    # Determine the per-site database path and return empty list if missing.
    $dbPath = Get-DbPathForHost $Hostname
    if (-not (Test-Path $dbPath)) { return @() }
    try {
        # Ensure the database module is loaded once rather than on every call.
        Import-DatabaseModule
        $escHost = $Hostname
        try {
            $escHost = DatabaseModule\Get-SqlLiteral -Value $Hostname
        } catch {
            $escHost = $Hostname -replace "'", "''"
        }
        $sql = "SELECT Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, ConfigStatus, PortColor, ToolTip FROM Interfaces WHERE Hostname = '$escHost' ORDER BY Port"
        $dt = Invoke-DbQuery -DatabasePath $dbPath -Sql $sql
        # Delegate to the shared helper which returns an array of PSCustomObject.
            $objs = InterfaceModule\New-InterfaceObjectsFromDbRow -Data $dt -Hostname $Hostname -TemplatesPath $TemplatesPath
            # For each returned object ensure expected properties exist.  This is necessary when the
            # database contains incomplete rows or when InterfaceModule\New-InterfaceObjectsFromDbRow returns an object
            # without IsSelected (should not happen, but defensive programming).  Add any missing
            # Hostname/IsSelected/Site/Zone/Building/Room properties before caching.
            if ($objs) {
                foreach ($oo in $objs) {
                    if ($null -eq $oo) { continue }
                    try {
                        if (-not $oo.PSObject.Properties['Hostname']) {
                            $oo | Add-Member -NotePropertyName Hostname -NotePropertyValue ($Hostname) -ErrorAction SilentlyContinue
                        }
                    } catch {}
                    try {
                        if (-not $oo.PSObject.Properties['IsSelected']) {
                            $oo | Add-Member -NotePropertyName IsSelected -NotePropertyValue $false -ErrorAction SilentlyContinue
                        }
                    } catch {}
                    # Inject location metadata for summary filtering.  When the Site/Zone/Building/Room
                    # properties are absent, derive them from DeviceMetadata or by parsing the hostname.
                    try {
                        $needSite    = (-not $oo.PSObject.Properties['Site'])
                        $needZone    = (-not $oo.PSObject.Properties['Zone'])
                        $needBld     = (-not $oo.PSObject.Properties['Building'])
                        $needRoom    = (-not $oo.PSObject.Properties['Room'])
                        if ($needSite -or $needZone -or $needBld -or $needRoom) {
                            $meta = $null
                            try {
                                if ($global:DeviceMetadata -and $global:DeviceMetadata.ContainsKey($Hostname)) {
                                    $meta = $global:DeviceMetadata[$Hostname]
                                }
                            } catch {}
                            $siteVal = ''
                            $zoneVal = ''
                            $bldVal  = ''
                            $roomVal = ''
                            if ($meta) {
                                try { $siteVal = '' + $meta.Site } catch {}
                                try { $bldVal  = '' + $meta.Building } catch {}
                                try { $roomVal = '' + $meta.Room } catch {}
                                # Zone may be stored as a property or may need to be parsed
                                if ($meta.PSObject.Properties['Zone']) {
                                    try { $zoneVal = '' + $meta.Zone } catch {}
                                }
                            }
                            # Parse hostname to derive site and zone when not found in metadata
                            if (-not $siteVal -or $siteVal -eq '') {
                                $partsHN = ('' + $Hostname) -split '-'
                                if ($partsHN.Length -ge 1) { $siteVal = '' + $partsHN[0] }
                                if ($partsHN.Length -ge 2) { if (-not $zoneVal -or $zoneVal -eq '') { $zoneVal = '' + $partsHN[1] } }
                            }
                            # When zone is still unknown, leave as empty string
                            if ($needSite)    { $oo | Add-Member -NotePropertyName Site     -NotePropertyValue $siteVal -ErrorAction SilentlyContinue }
                            if ($needZone)    { $oo | Add-Member -NotePropertyName Zone     -NotePropertyValue $zoneVal -ErrorAction SilentlyContinue }
                            if ($needBld)     { $oo | Add-Member -NotePropertyName Building -NotePropertyValue $bldVal  -ErrorAction SilentlyContinue }
                            if ($needRoom)    { $oo | Add-Member -NotePropertyName Room     -NotePropertyValue $roomVal -ErrorAction SilentlyContinue }
                        }
                    } catch {}
                }
            }
            # Update the global cache with the loaded objects for this host.
            try {
                if (-not $global:DeviceInterfaceCache) { $global:DeviceInterfaceCache = @{} }
                $listCache = New-Object 'System.Collections.Generic.List[object]'
                if ($objs) {
                    foreach ($o in $objs) { [void]$listCache.Add($o) }
                }
                $global:DeviceInterfaceCache[$Hostname] = $listCache
            } catch {}
            return $objs
    } catch {
        Write-Warning ("Failed to load interface information from database for {0}: {1}" -f $Hostname, $_.Exception.Message)
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
    # Determine the per-site database path for this host; return empty list if missing
    $dbPath = Get-DbPathForHost $Hostname
    if (-not (Test-Path $dbPath)) { return @() }
    $debug = ($Global:StateTraceDebug -eq $true)
    try {
        # Ensure the database module is loaded once rather than on every call.
        Import-DatabaseModule
        $escHost = $Hostname
        try {
            $escHost = DatabaseModule\Get-SqlLiteral -Value $Hostname
        } catch {
            $escHost = $Hostname -replace "'", "''"
        }
        $vendor = 'Cisco'
        try {
            $mkDt = Invoke-DbQuery -DatabasePath $dbPath -Sql "SELECT Make FROM DeviceSummary WHERE Hostname = '$escHost'"
            if ($mkDt) {
                if ($mkDt -is [System.Data.DataTable]) {
                    if ($mkDt.Rows.Count -gt 0) {
                        $mk = $mkDt.Rows[0].Make
                        if ($mk -match '(?i)brocade') { $vendor = 'Brocade' }
                    }
                } else {
                    $mkRow = $mkDt | Select-Object -First 1
                    if ($mkRow -and $mkRow.PSObject.Properties['Make']) {
                        $mk = $mkRow.Make
                        if ($mk -match '(?i)brocade') { $vendor = 'Brocade' }
                    }
                }
            }
        } catch {}
        $templateData = TemplatesModule\Get-ConfigurationTemplateData -Vendor $vendor -TemplatesPath $TemplatesPath
        if (-not $templateData.Exists) { throw "Template file missing: $($templateData.Path)" }
        $templates = $templateData.Templates
        $templateLookup = $templateData.Lookup
        $tmpl = $null
        if ($templateLookup -and $templateLookup.ContainsKey($TemplateName)) {
            $tmpl = $templateLookup[$TemplateName]
        }
        if (-not $tmpl) { throw "Template '$TemplateName' not found in ${vendor}.json" }
        # --- Batched query instead of N+1 per-port lookups ---
        $oldConfigs = @{}
        # Build a normalized list of ports without using ForEach-Object pipelines for better performance
        $portsList = New-Object 'System.Collections.Generic.List[string]'
        foreach ($p in $Interfaces) {
            if ($p -ne $null) {
                [void]$portsList.Add($p.ToString())
            }
        }
        if ($portsList.Count -gt 0) {
            # Escape single quotes and build IN list using typed lists
            $portItems = New-Object 'System.Collections.Generic.List[string]'
            foreach ($item in $portsList) {
                $escaped = $item
                try {
                    $escaped = DatabaseModule\Get-SqlLiteral -Value $item
                } catch {
                    $escaped = $item -replace "'", "''"
                }
                [void]$portItems.Add("'" + $escaped + "'")
            }
            $inList = [string]::Join(", ", $portItems.ToArray())
            $sqlCfgAll = "SELECT Hostname, Port, Config FROM Interfaces WHERE Hostname = '$escHost' AND Port IN ($inList)"
            $session = $null
            try {
                if (Test-Path $dbPath) { $session = Open-DbReadSession -DatabasePath $dbPath }
            } catch {}
            try {
                $dtAll = if ($session) {
                    Invoke-DbQuery -DatabasePath $dbPath -Sql $sqlCfgAll -Session $session
                } else {
                    Invoke-DbQuery -DatabasePath $dbPath -Sql $sqlCfgAll
                }
                if ($dtAll) {
                    $rows = @()
                    if ($dtAll -is [System.Data.DataTable]) { $rows = $dtAll.Rows }
                    elseif ($dtAll -is [System.Collections.IEnumerable]) { $rows = $dtAll }
                    foreach ($row in $rows) {
                        $portVal = $row.Port
                        $cfgText = $row.Config
                        $oldConfigs[$portVal] = if ($cfgText) { $cfgText -split "`n" } else { @() }
                    }
                }
            } finally {
                if ($session) { Close-DbReadSession -Session $session }
            }
        }
        foreach ($p in $Interfaces) {
            if (-not $oldConfigs.ContainsKey($p)) { $oldConfigs[$p] = @() }
        }
        # --- End batched lookup ---
        $outLines = foreach ($port in $Interfaces) {
            "interface $port"
            # Use a typed list instead of a PowerShell array when building the set of
            $pending = New-Object 'System.Collections.Generic.List[string]'
            $nameOverride = if ($NewNames.ContainsKey($port)) { $NewNames[$port] } else { $null }
            $vlanOverride = if ($NewVlans.ContainsKey($port)) { $NewVlans[$port] } else { $null }
            if ($nameOverride) {
                $val = if ($vendor -eq 'Cisco') { "description $nameOverride" } else { "port-name $nameOverride" }
                [void]$pending.Add($val)
            }
            if ($vlanOverride) {
                $val2 = if ($vendor -eq 'Cisco') { "switchport access vlan $vlanOverride" } else { "auth-default-vlan $vlanOverride" }
                [void]$pending.Add($val2)
            }
            foreach ($cmd in $tmpl.required_commands) { [void]$pending.Add($cmd.Trim()) }
            if ($oldConfigs.ContainsKey($port)) {
                foreach ($oldLine in $oldConfigs[$port]) {
                    $trimOld  = $oldLine.Trim()
                    if (-not $trimOld) { continue }
                    # Skip interface and exit lines using case-insensitive comparisons
                    if ($trimOld.StartsWith('interface', [System.StringComparison]::OrdinalIgnoreCase) -or
                        $trimOld.Equals('exit', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                    $existsInNew = $false
                    foreach ($newCmd in $pending) {
                        # Check if the existing command matches any pending command using
                        $cmdTrim = $newCmd.Trim()
                        if ($trimOld.StartsWith($cmdTrim, [System.StringComparison]::OrdinalIgnoreCase)) { $existsInNew = $true; break }
                    }
                    if ($existsInNew) { continue }
                    if ($vendor -eq 'Cisco') {
                        # Remove legacy authentication commands.  Compare prefixes
                        if ($trimOld.StartsWith('authentication', [System.StringComparison]::OrdinalIgnoreCase) -or
                            $trimOld.StartsWith('dot1x',        [System.StringComparison]::OrdinalIgnoreCase) -or
                            $trimOld.Equals('mab',             [System.StringComparison]::OrdinalIgnoreCase)) {
                            " no $trimOld"
                        }
                    } else {
                        # For non-Cisco vendors, remove specific dot1x/mac-authentication lines.
                        if ($trimOld -match '(?i)^dot1x\s+port-control\s+auto' -or
                            $trimOld -match '(?i)^mac-authentication\s+enable') {
                            " no $trimOld"
                        }
                    }
                }
            }
            if ($nameOverride) {
                $(if ($vendor -eq 'Cisco') { " description $nameOverride" } else { " port-name $nameOverride" })
            }
            if ($vlanOverride) {
                $(if ($vendor -eq 'Cisco') { " switchport access vlan $vlanOverride" } else { " auth-default-vlan $vlanOverride" })
            }
            foreach ($cmd in $tmpl.required_commands) { $cmd }
            'exit'
            ''
        }
        return $outLines
    } catch {
        Write-Warning ("Failed to build interface configuration from database for {0}: {1}" -f $Hostname, $_.Exception.Message)
        return @()
    }
}

function Get-InterfacesForHostsBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [Parameter(Mandatory)][string[]]$Hostnames
    )
    if (-not $Hostnames -or $Hostnames.Count -eq 0) {
        return (New-Object System.Data.DataTable)
    }

    $seen = @{}
    $cleanList = New-Object 'System.Collections.Generic.List[string]'
    foreach ($h in $Hostnames) {
        if ($null -ne $h) {
            $t = ('' + $h).Trim()
            if ($t -and -not $seen.ContainsKey($t)) {
                $seen[$t] = $true
                [void]$cleanList.Add($t)
            }
        }
    }

    $cleanHosts = $cleanList.ToArray()
    if (-not $cleanHosts -or $cleanHosts.Count -eq 0) {
        return (New-Object System.Data.DataTable)
    }

    Import-DatabaseModule
    $listItems = New-Object 'System.Collections.Generic.List[string]'
    foreach ($host in $cleanHosts) {
        if ($host -ne $null) {
            $escaped = $host
            try {
                $escaped = DatabaseModule\Get-SqlLiteral -Value $host
            } catch {
                $escaped = $host -replace "'", "''"
            }
            [void]$listItems.Add("'" + $escaped + "'")
        }
    }

    $inList = [string]::Join(',', $listItems.ToArray())
    if ([string]::IsNullOrWhiteSpace($inList)) {
        return (New-Object System.Data.DataTable)
    }

    $sql = @"
SELECT
    i.Hostname,
    i.Port,
    i.Name,
    i.Status,
    i.VLAN,
    i.Duplex,
    i.Speed,
    i.Type,
    i.LearnedMACs,
    i.AuthState,
    i.AuthMode,
    i.AuthClientMAC,
    ds.Site,
    ds.Building,
    ds.Room,
    ds.Make,
    ds.AuthBlock
FROM Interfaces AS i
LEFT JOIN DeviceSummary AS ds ON i.Hostname = ds.Hostname
WHERE i.Hostname IN ($inList)
ORDER BY i.Hostname, i.Port
"@

    $session = $null
    try {
        $session = Open-DbReadSession -DatabasePath $DatabasePath
    } catch {
        $session = $null
    }

    try {
        if ($session) {
            return Invoke-DbQuery -DatabasePath $DatabasePath -Sql $sql -Session $session
        } else {
            return Invoke-DbQuery -DatabasePath $DatabasePath -Sql $sql
        }
    } finally {
        if ($session) { Close-DbReadSession -Session $session }
    }
}
function Get-SpanningTreeInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Hostname
    )

    $hostTrim = ('' + $Hostname).Trim()
    if ([string]::IsNullOrWhiteSpace($hostTrim)) { return @() }

    Import-DatabaseModule

    $dbPath = $null
    try { $dbPath = Get-DbPathForHost -Hostname $hostTrim } catch { $dbPath = $null }
    if (-not $dbPath -or -not (Test-Path -LiteralPath $dbPath)) { return @() }

    $escHost = $hostTrim -replace "'", "''"
    $sql = "SELECT Vlan, RootSwitch, RootPort, Role, Upstream, LastUpdated FROM SpanInfo WHERE Hostname = '$escHost' ORDER BY Vlan, RootPort, Role, Upstream"

    $session = $null
    try { $session = Open-DbReadSession -DatabasePath $dbPath } catch { $session = $null }

    try {
        if ($session) {
            $data = Invoke-DbQuery -DatabasePath $dbPath -Sql $sql -Session $session
        } else {
            $data = Invoke-DbQuery -DatabasePath $dbPath -Sql $sql
        }
    } finally {
        if ($session) { Close-DbReadSession -Session $session }
    }

    if (-not $data) { return @() }

    $rows = @()
    if ($data -is [System.Data.DataTable]) {
        $rows = $data.Rows
    } elseif ($data -is [System.Collections.IEnumerable]) {
        $rows = @($data)
    }

    if (-not $rows -or $rows.Count -eq 0) { return @() }

    $list = New-Object 'System.Collections.Generic.List[object]'
    foreach ($row in $rows) {
        if (-not $row) { continue }

        $vlan = ''
        $rootSwitch = ''
        $rootPort = ''
        $role = ''
        $upstream = ''
        $lastUpdated = ''

        try {
            if ($row -is [System.Data.DataRow]) {
                $vlan = '' + ($row['Vlan'])
                $rootSwitch = '' + ($row['RootSwitch'])
                $rootPort = '' + ($row['RootPort'])
                $role = '' + ($row['Role'])
                $upstream = '' + ($row['Upstream'])
                if ($row.Table.Columns.Contains('LastUpdated')) {
                    $lastUpdated = '' + ($row['LastUpdated'])
                }
            } elseif ($row.PSObject) {
                if ($row.PSObject.Properties['Vlan']) { $vlan = '' + $row.Vlan }
                if ($row.PSObject.Properties['RootSwitch']) { $rootSwitch = '' + $row.RootSwitch }
                if ($row.PSObject.Properties['RootPort']) { $rootPort = '' + $row.RootPort }
                if ($row.PSObject.Properties['Role']) { $role = '' + $row.Role }
                if ($row.PSObject.Properties['Upstream']) { $upstream = '' + $row.Upstream }
                if ($row.PSObject.Properties['LastUpdated']) { $lastUpdated = '' + $row.LastUpdated }
            }
        } catch {}

        $obj = [PSCustomObject]@{
            VLAN        = $vlan
            RootSwitch  = $rootSwitch
            RootPort    = $rootPort
            Role        = $role
            Upstream    = $upstream
            LastUpdated = $lastUpdated
        }
        [void]$list.Add($obj)
    }


    try {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $debugDir = Join-Path $projectRoot 'Logs\Debug'
        if (-not (Test-Path $debugDir)) { New-Item -ItemType Directory -Path $debugDir -Force | Out-Null }
        $logPath = Join-Path $debugDir 'SpanDebug.log'
        $rowCount = $list.Count
        $timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
        $line = ("{0} Host={1} Rows={2}" -f $timestamp, $hostTrim, $rowCount)
        Add-Content -Path $logPath -Value $line -Encoding UTF8
    } catch { }

    return $list.ToArray()
}
Export-ModuleMember -Function Get-DataDirectoryPath, Get-SiteFromHostname, Get-DbPathForSite, Get-DbPathForHost, Get-AllSiteDbPaths, Clear-SiteInterfaceCache, Update-SiteZoneCache, Get-GlobalInterfaceSnapshot, Update-GlobalInterfaceList, Get-InterfacesForSite, Get-InterfaceInfo, Get-InterfaceConfiguration, Get-SpanningTreeInfo, Get-InterfacesForHostsBatch, Invoke-ParallelDbQuery, Import-DatabaseModule
