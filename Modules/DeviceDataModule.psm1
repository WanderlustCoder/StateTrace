# ----------------------------------------------------------------------------
if (-not (Get-Variable -Name DeviceFilterUpdating -Scope Script -ErrorAction SilentlyContinue)) {
    $script:DeviceFilterUpdating = $false
}

# Track previous selections for site and building so dependent lists can be reset.
if (-not (Get-Variable -Name LastSiteSel -Scope Script -ErrorAction SilentlyContinue)) { $script:LastSiteSel = '' }
if (-not (Get-Variable -Name LastBuildingSel -Scope Script -ErrorAction SilentlyContinue)) { $script:LastBuildingSel = '' }
# Track previous selection for zone as well so that dependent lists can be restored
if (-not (Get-Variable -Name LastZoneSel -Scope Script -ErrorAction SilentlyContinue)) { $script:LastZoneSel = '' }

# Precompute the module root and Data directory paths once.  Many helpers in
# this module previously used Resolve‑Path and Select‑Object to derive the
# module's parent directory and Data folder on every call.  Those pipeline
# operations are relatively expensive.  Here we compute the absolute parent
# path using .NET methods and store it in script‑scoped variables.  These
# values are then reused in Get‑DbPathForHost and Get‑AllSiteDbPaths to avoid
# repeated path resolution.
if (-not (Get-Variable -Name ModuleRootPath -Scope Script -ErrorAction SilentlyContinue)) {
    try {
        $script:ModuleRootPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    } catch {
        # Fallback: use the parent directory via Split-Path if GetFullPath fails
        $script:ModuleRootPath = Split-Path -Parent $PSScriptRoot
    }
    $script:DataDirPath = Join-Path $script:ModuleRootPath 'Data'
}

function Test-StringListEqualCI {
    param([System.Collections.IEnumerable]$A, [System.Collections.IEnumerable]$B)
    $la = @($A); $lb = @($B)
    if ($la.Count -ne $lb.Count) { return $false }
    for ($i = 0; $i -lt $la.Count; $i++) {
        $sa = '' + $la[$i]; $sb = '' + $lb[$i]
        if ([System.StringComparer]::OrdinalIgnoreCase.Compare($sa, $sb) -ne 0) { return $false }
    }
    return $true
}

# DeviceDataModule.psm1

# -------------------------------------------------------------------------
# Helper functions for per-site database selection.  Sites are determined
# by the portion of the hostname before the first dash.  These helpers
# compute the appropriate database path for a given host and enumerate
# all existing site databases.  Using these functions allows the module
# to work with multiple per-site databases instead of a single global DB.

function Get-SiteFromHostname {
    param([string]$Hostname)
    if (-not $Hostname) { return 'Unknown' }
    # Extract the part of the hostname before the first dash
    if ($Hostname -match '^(?<site>[^-]+)-') { return $matches['site'] }
    return $Hostname
}

function Get-DbPathForHost {
    param([Parameter(Mandatory)][string]$Hostname)
    # Determine the site code (substring before the first dash).  We compute the
    # parent directory and Data folder once at module load time (see below)
    # rather than resolving it on every invocation.  This avoids the overhead
    # of Resolve‑Path and pipeline operations.  Join‑Path is used here only
    # to append the site-specific filename.
    $site = Get-SiteFromHostname $Hostname
    return (Join-Path $script:DataDirPath ("$site.accdb"))
}

function Get-AllSiteDbPaths {
    # Return an array of all .accdb files in the Data directory.  If none exist,
    # return an empty array.  We avoid Resolve‑Path and Select‑Object to speed
    # up repeated calls; instead we rely on the precomputed $script:DataDirPath.
    if (-not (Test-Path $script:DataDirPath)) { return @() }
    $files = Get-ChildItem -Path $script:DataDirPath -Filter '*.accdb' -File
    # Build a strongly typed list of strings to collect FullName properties
    $list = New-Object 'System.Collections.Generic.List[string]'
    foreach ($f in $files) { [void]$list.Add($f.FullName) }
    return $list.ToArray()
}

# Initialise a simple in‑memory cache for per‑device interface lists.  When a
if (-not $global:DeviceInterfaceCache) {
    $global:DeviceInterfaceCache = @{}
}

# Initialise a per-site cache for interface lists.  Each entry in this
# dictionary will store an object with two keys: `List`, the array of
# interface PSCustomObjects for the site, and `DbTime`, the last write
# timestamp of the site's database file when the list was loaded.  This
# cache allows the module to avoid reloading interface data from disk
# unnecessarily, yet automatically refreshes the list whenever the
# underlying database file changes (e.g. after new logs are parsed and
# inserted).  Without this cache, the application would load the full
# interface list for every site on startup, which can consume large
# amounts of memory when many devices are present.  See Get-InterfacesForSite
# and Update-GlobalInterfaceList for usage.
if (-not (Get-Variable -Name SiteInterfaceCache -Scope Script -ErrorAction SilentlyContinue)) {
    $script:SiteInterfaceCache = @{}
}

function Get-InterfacesForSite {
    <#
    .SYNOPSIS
        Retrieve interface objects for a specific site or for all sites on demand.

    .DESCRIPTION
        This helper function implements lazy loading of interface data.  When
        called with a specific site code, it checks whether a cached list of
        interfaces already exists for that site and whether it is still
        current.  The cache is keyed by site code and stores both the list
        of PSCustomObject interfaces and the last write time of the site's
        database file.  If the cache is missing or stale (i.e. the database
        has been modified since the list was loaded), the function queries
        the per‑site database, converts the result set into interface
        objects, caches it, and returns the new list.  When called with a
        null or empty site string, the function loads all sites, merging
        each site's list into a single array.  The returned list is sorted
        by Hostname and PortSort to maintain consistent ordering.

    .PARAMETER Site
        The site code to load.  Pass an empty string or 'All Sites' to
        retrieve interface data for all available sites.

    .OUTPUTS
        System.Collections.Generic.List[object]
            A typed list of PSCustomObjects representing interfaces.  Each
            object contains Hostname, Port, PortSort, Name, Status, VLAN,
            Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode,
            AuthClientMAC, Site, Building, Room and Zone properties.

    .EXAMPLE
        # Retrieve interfaces for only the currently selected site
        $currentSite = (Get-LastLocation).Site
        $interfaces = Get-InterfacesForSite -Site $currentSite

        # Retrieve interfaces for all sites when the user selects 'All Sites'
        $interfaces = Get-InterfacesForSite -Site 'All Sites'
    #>
    [CmdletBinding()]
    param(
        [string]$Site
    )
    # Normalize the site parameter to a simple string.  WPF dropdown
    # selections may be objects; convert to a string via concatenation.
    $siteName = ''
    if ($Site) { $siteName = '' + $Site }
    # Treat null/empty or 'All Sites' (case‑insensitive) as a request to
    # load every available site.  Also handle the string 'All' as a
    # synonym for convenience.
    if ([string]::IsNullOrWhiteSpace($siteName) -or
        ([System.StringComparer]::OrdinalIgnoreCase.Equals($siteName, 'All Sites')) -or
        ([System.StringComparer]::OrdinalIgnoreCase.Equals($siteName, 'All')))
    {
        # Build a list by loading each site individually.  Use a typed list
        # to accumulate results efficiently.  Because the per‑site cache
        # stores each site's data separately, this will honour cache
        # freshness for each database.
        $combined = New-Object 'System.Collections.Generic.List[object]'
        $dbPaths = Get-AllSiteDbPaths
        foreach ($p in $dbPaths) {
            # Derive the site code from the filename (without extension)
            try {
                $code = [System.IO.Path]::GetFileNameWithoutExtension($p)
            } catch { $code = '' }
            if (-not [string]::IsNullOrWhiteSpace($code)) {
                $siteList = Get-InterfacesForSite -Site $code
                if ($siteList) {
                    foreach ($item in $siteList) { [void]$combined.Add($item) }
                }
            }
        }
        # Sort the combined list by Hostname and PortSort for consistency
        $comparison = [System.Comparison[object]]{
            param($a, $b)
            $hnc = [System.StringComparer]::OrdinalIgnoreCase.Compare($a.Hostname, $b.Hostname)
            if ($hnc -ne 0) { return $hnc }
            return [System.StringComparer]::Ordinal.Compare($a.PortSort, $b.PortSort)
        }
        try { $combined.Sort($comparison) } catch {}
        return $combined
    }
    # At this point we have a specific site code.  Trim whitespace.
    $siteCode = $siteName.Trim()
    if ([string]::IsNullOrWhiteSpace($siteCode)) { return (New-Object 'System.Collections.Generic.List[object]') }
    # Check if a cached entry exists for this site and if it is current.
    try {
        if ($script:SiteInterfaceCache.ContainsKey($siteCode)) {
            $entry = $script:SiteInterfaceCache[$siteCode]
            # Ensure the entry has both List and DbTime keys.  A stale
            # entry may have been stored before these keys were added.  If so,
            # force a refresh.
            if ($entry -and $entry.PSObject.Properties['List'] -and $entry.PSObject.Properties['DbTime']) {
                # Determine current database last write time.  If obtaining
                # LastWriteTime fails (e.g. file missing), assume stale.
                $dbPath = Join-Path $script:DataDirPath ("$siteCode.accdb")
                $currentTime = $null
                try { $currentTime = (Get-Item -LiteralPath $dbPath).LastWriteTime } catch {}
                if ($currentTime -and ($entry.DbTime -eq $currentTime)) {
                    return $entry.List
                }
            }
        }
    } catch {}
    # If we reach here, either no cache entry exists or the DB has changed.
    # Build the query to retrieve interfaces for this site only.  Join the
    # Interfaces and DeviceSummary tables on Hostname and filter by Site.
    $dbFile = Join-Path $script:DataDirPath ("$siteCode.accdb")
    if (-not (Test-Path $dbFile)) {
        return (New-Object 'System.Collections.Generic.List[object]')
    }
    # Escape the site code for SQL by doubling single quotes
    $siteEsc = $siteCode -replace "'", "''"
    $sqlSite = @"
SELECT i.Hostname, i.Port, i.Name, i.Status, i.VLAN, i.Duplex, i.Speed, i.Type,
       i.LearnedMACs, i.AuthState, i.AuthMode, i.AuthClientMAC,
       ds.Site, ds.Building, ds.Room
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
            # Normalise the result set into an enumerable of DataRow objects
            if ($dt -is [System.Data.DataTable]) {
                $enum = $dt.Rows
            } elseif ($dt -is [System.Data.DataView]) {
                $enum = $dt
            } elseif ($dt -is [System.Collections.IEnumerable]) {
                $enum = $dt
            }
            if ($enum) {
                foreach ($r in $enum) {
                    if ($r -eq $null) { continue }
                    $dataRow = $null
                    if ($r -is [System.Data.DataRow]) {
                        $dataRow = $r
                    } elseif ($r -is [System.Data.DataRowView]) {
                        $dataRow = $r.Row
                    } else {
                        continue
                    }
                    # Extract columns safely, converting null/DBNull to empty strings
                    $hnRaw   = $dataRow['Hostname']
                    $portRaw = $dataRow['Port']
                    $nameRaw = $dataRow['Name']
                    $statusRaw = $dataRow['Status']
                    $vlanRaw   = $dataRow['VLAN']
                    $duplexRaw = $dataRow['Duplex']
                    $speedRaw  = $dataRow['Speed']
                    $typeRaw   = $dataRow['Type']
                    $lmRaw     = $dataRow['LearnedMACs']
                    $aStateRaw = $dataRow['AuthState']
                    $aModeRaw  = $dataRow['AuthMode']
                    $aMACRaw   = $dataRow['AuthClientMAC']
                    $siteRaw   = $dataRow['Site']
                    $bldRaw    = $dataRow['Building']
                    $roomRaw   = $dataRow['Room']
                    $hn     = if ($hnRaw    -ne $null -and $hnRaw    -ne [System.DBNull]::Value) { [string]$hnRaw    } else { '' }
                    $port   = if ($portRaw  -ne $null -and $portRaw  -ne [System.DBNull]::Value) { [string]$portRaw  } else { '' }
                    $name   = if ($nameRaw  -ne $null -and $nameRaw  -ne [System.DBNull]::Value) { [string]$nameRaw  } else { '' }
                    $status = if ($statusRaw -ne $null -and $statusRaw -ne [System.DBNull]::Value) { [string]$statusRaw } else { '' }
                    $vlan   = if ($vlanRaw  -ne $null -and $vlanRaw  -ne [System.DBNull]::Value) { [string]$vlanRaw  } else { '' }
                    $duplex = if ($duplexRaw -ne $null -and $duplexRaw -ne [System.DBNull]::Value) { [string]$duplexRaw} else { '' }
                    $speed  = if ($speedRaw -ne $null -and $speedRaw -ne [System.DBNull]::Value) { [string]$speedRaw } else { '' }
                    $type   = if ($typeRaw  -ne $null -and $typeRaw  -ne [System.DBNull]::Value) { [string]$typeRaw  } else { '' }
                    $lm     = if ($lmRaw    -ne $null -and $lmRaw    -ne [System.DBNull]::Value) { [string]$lmRaw    } else { '' }
                    $aState = if ($aStateRaw -ne $null -and $aStateRaw -ne [System.DBNull]::Value) { [string]$aStateRaw} else { '' }
                    $aMode  = if ($aModeRaw -ne $null -and $aModeRaw -ne [System.DBNull]::Value) { [string]$aModeRaw } else { '' }
                    $aMAC   = if ($aMACRaw  -ne $null -and $aMACRaw  -ne [System.DBNull]::Value) { [string]$aMACRaw  } else { '' }
                    $siteVal= if ($siteRaw  -ne $null -and $siteRaw  -ne [System.DBNull]::Value) { [string]$siteRaw  } else { '' }
                    $bld    = if ($bldRaw   -ne $null -and $bldRaw   -ne [System.DBNull]::Value) { [string]$bldRaw   } else { '' }
                    $room   = if ($roomRaw  -ne $null -and $roomRaw  -ne [System.DBNull]::Value) { [string]$roomRaw  } else { '' }
                    # Compute PortSort using existing helper.  Use a high sort key
                    # when the port field is empty to ensure unknown ports sort last.
                    $portSort = if (-not [string]::IsNullOrWhiteSpace($port)) {
                        Get-PortSortKey -Port $port
                    } else {
                        '99-UNK-99999-99999-99999-99999-99999'
                    }
                    # Derive zone from hostname (second component of hostname delimited by hyphens)
                    $zoneValIf = ''
                    try {
                        $hnParts = $hn -split '-', 3
                        if ($hnParts.Length -ge 2) { $zoneValIf = $hnParts[1] }
                    } catch { $zoneValIf = '' }
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
                    }
                    [void]$rows.Add($obj)
                }
            }
        }
    } catch {
        Write-Warning "Failed to query interfaces for site '$siteCode': $($_.Exception.Message)"
    }
    # Sort the list by Hostname and PortSort before caching
    $comparison2 = [System.Comparison[object]]{
        param($a, $b)
        $hnc2 = [System.StringComparer]::OrdinalIgnoreCase.Compare($a.Hostname, $b.Hostname)
        if ($hnc2 -ne 0) { return $hnc2 }
        return [System.StringComparer]::Ordinal.Compare($a.PortSort, $b.PortSort)
    }
    try { $rows.Sort($comparison2) } catch {}
    # Determine the current last write time of the database for caching metadata
    $dbTime = $null
    try { $dbTime = (Get-Item -LiteralPath $dbFile).LastWriteTime } catch {}
    # Store in cache with metadata.  Overwrite any existing entry.
    try {
        $script:SiteInterfaceCache[$siteCode] = [PSCustomObject]@{
            List   = $rows
            DbTime = $dbTime
        }
    } catch {}
    return $rows
}

# Clear the per‑site interface cache.  This function resets the
# SiteInterfaceCache dictionary so that subsequent calls to
# Get-InterfacesForSite will reload interface data from the database.
# Use this after bulk updates to the databases (e.g. after parsing logs)
# to ensure the cached lists reflect the latest data.
function Clear-SiteInterfaceCache {
    [CmdletBinding()]
    param()
    try {
        $script:SiteInterfaceCache = @{}
    } catch {
        # ignore errors and recreate dictionary
        Set-Variable -Name SiteInterfaceCache -Scope Script -Value @{}
    }
}

# Initialise an in‑memory cache for vendor configuration templates.  This cache
# prevents repeated disk reads and JSON parsing of Cisco.json/Brocade.json on
# every call.  The cache is keyed by the vendor name (e.g. 'Cisco', 'Brocade')
# and holds the array of template objects for that vendor.  A companion
# $script:TemplatesByName hash table will be populated from these cached
# arrays when needed for O(1) name lookups.
if (-not (Get-Variable -Name TemplatesCache -Scope Script -ErrorAction SilentlyContinue)) {
    $script:TemplatesCache = @{}
}
if (-not (Get-Variable -Name TemplatesByName -Scope Script -ErrorAction SilentlyContinue)) {
    $script:TemplatesByName = @{}
}

# -----------------------------------------------------------------------------
# Helper to ensure the database module is imported once.  Several functions in
# this module previously imported the DatabaseModule on every invocation, which
# incurs unnecessary overhead and can slow down interface lookups when executed
# repeatedly.  The following helper checks whether the DatabaseModule is already
# loaded; if not, it attempts to import it from the same directory as this
# module.  Errors during import are silently ignored so callers don't need to
# handle exceptions.  See Get-ConfigurationTemplates/Get-InterfaceInfo/etc.
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

function Get-SelectedLocation {
    [CmdletBinding()]
    param([object]$Window = $global:window)
    $siteSel = $null
    $zoneSel = $null
    $bldSel  = $null
    $roomSel = $null
    try {
        if ($Window) {
            $siteCtrl = $Window.FindName('SiteDropdown')
            $zoneCtrl = $Window.FindName('ZoneDropdown')
            $bldCtrl  = $Window.FindName('BuildingDropdown')
            $roomCtrl = $Window.FindName('RoomDropdown')
            if ($siteCtrl) { $siteSel = $siteCtrl.SelectedItem }
            if ($zoneCtrl) { $zoneSel = $zoneCtrl.SelectedItem }
            if ($bldCtrl)  { $bldSel  = $bldCtrl.SelectedItem }
            if ($roomCtrl){ $roomSel = $roomCtrl.SelectedItem }
        }
    } catch {
        # ignore lookup errors
    }
    return @{ Site = $siteSel; Zone = $zoneSel; Building = $bldSel; Room = $roomSel }
}

# Return the last recorded location selections (site, zone, building, room).
# These values are maintained by Update-DeviceFilter to capture the most
# recently chosen filters.  Exposing them via a function allows other
# modules (e.g. CompareViewModule) to query the last known selections
# without directly accessing script-scoped variables.
function Get-LastLocation {
    [CmdletBinding()]
    param()
    $site = $null
    $zone = $null
    $bld  = $null
    $room = $null
    try { $site = $script:LastSiteSel } catch { $site = $null }
    try { $zone = $script:LastZoneSel } catch { $zone = $null }
    try { $bld  = $script:LastBuildingSel } catch { $bld  = $null }
    try { $room = $script:LastRoomSel } catch { $room = $null }
    return @{ Site = $site; Zone = $zone; Building = $bld; Room = $room }
}

# Filter a collection of interface-like objects by location.  Given a list


# Initialise a dropdown or other ItemsControl with a list of items and

function Set-DropdownItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Windows.Controls.ItemsControl]$Control,
        [Parameter(Mandatory)][object[]]$Items
    )
    # Assign the ItemsSource and select the first item (index 0) when
    $Control.ItemsSource = $Items
    if ($Items -and $Items.Count -gt 0) {
        try { $Control.SelectedIndex = 0 } catch { $null = $null }
    } else {
        try { $Control.SelectedIndex = -1 } catch { $null = $null }
    }
}

###

function Get-SqlLiteral {
    
    param([Parameter(Mandatory)][string]$Value)
    # Replace single quotes with doubled single quotes
    return $Value -replace "'", "''"
}

function Get-InterfacesForHostsBatch {
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [Parameter(Mandatory)][string[]]$Hostnames
    )
    # If no hostnames were provided, return an empty table immediately.
    if (-not $Hostnames -or $Hostnames.Count -eq 0) {
        return (New-Object System.Data.DataTable)
    }
    # Sanitize and de-duplicate hostnames.  Filter out null/empty values using a
    # hash-set approach instead of Select-Object -Unique to avoid pipeline
    # overhead in hot paths.  Preserve the first occurrence of each
    # hostname (case-sensitive) in order.
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
    # Build an IN clause from the sanitized hostnames.  Escape each name.  Use a
    # typed List[string] to avoid the overhead of the ForEach-Object pipeline.
    $listItems = New-Object 'System.Collections.Generic.List[string]'
    foreach ($host in $cleanHosts) {
        if ($host -ne $null) {
            $escaped = Get-SqlLiteral $host
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
    # Perform the query using a short‑lived read session to benefit
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

# Construct interface PSCustomObject instances from database results.  This helper

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
    # Resolve the per-site database path for this host.  This allows the
    # module to query the correct database when multiple site databases
    # exist.  Do not rely on a global database path.
    $dbPath = Get-DbPathForHost $Hostname
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
        if ($Data -is [System.Data.DataTable]) {
            if ($Data.Rows.Count -gt 0) { $firstRow = $Data.Rows[0] }
        } elseif ($Data -is [System.Data.DataView]) {
            if ($Data.Count -gt 0) { $firstRow = $Data[0].Row }
        } elseif ($Data -is [System.Collections.IEnumerable]) {
            $enum = $Data.GetEnumerator()
            if ($enum -and $enum.MoveNext()) { $firstRow = $enum.Current }
        }
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
                if ($mkDt -is [System.Data.DataTable]) {
                    if ($mkDt.Rows.Count -gt 0) {
                        $mk = '' + $mkDt.Rows[0].Make
                        if ($mk -match '(?i)brocade') { $vendor = 'Brocade' }
                    }
                } else {
                    $mkRow = $mkDt | Select-Object -First 1
                    if ($mkRow -and $mkRow.PSObject.Properties['Make']) {
                        $mk = '' + $mkRow.Make
                        if ($mk -match '(?i)brocade') { $vendor = 'Brocade' }
                    }
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
                    if ($abDt -is [System.Data.DataTable]) {
                        if ($abDt.Rows.Count -gt 0) { $abText = '' + $abDt.Rows[0].AuthBlock }
                    } else {
                        $abRow = $abDt | Select-Object -First 1
                        if ($abRow -and $abRow.PSObject.Properties['AuthBlock']) { $abText = '' + $abRow.AuthBlock }
                    }
                }
            } catch {}
        }
        if ($abText) {
            # Split into non-empty trimmed lines.  Use a typed list instead of ForEach-Object to
            # avoid pipeline overhead when processing large authentication blocks.
            $__tmpLines = $abText -split "`r?`n"
            $__list = New-Object 'System.Collections.Generic.List[string]'
            foreach ($ln in $__tmpLines) {
                $s = ('' + $ln).Trim()
                if ($s -ne '') { [void]$__list.Add($s) }
            }
            $authBlockLines = $__list.ToArray()
        }
    }
    # Retrieve compliance templates for this vendor.  Avoid repeatedly reading
    # JSON from disk by caching the parsed templates per vendor.  When the
    # cache does not contain an entry, read from the appropriate .json file,
    # convert it, and store it for future calls.  Afterwards, build the
    # $script:TemplatesByName index for O(1) lookups by template name.  Use
    # -AsString to ensure the hash table uses string keys consistently.
    $templates = $null
    try {
        $vendorFile = if ($vendor -eq 'Cisco') { 'Cisco.json' } else { 'Brocade.json' }
        $jsonFile   = Join-Path $TemplatesPath $vendorFile
        # Ensure the templates cache exists.  Without this, lookups on
        # $script:TemplatesCache would throw.  Note: the cache lives in
        # script scope and persists across calls.
        if (-not $script:TemplatesCache) { $script:TemplatesCache = @{} }
        if ($script:TemplatesCache.ContainsKey($vendor)) {
            $templates = $script:TemplatesCache[$vendor]
        } else {
            if (Test-Path $jsonFile) {
                $tmplJson = Get-Content $jsonFile -Raw | ConvertFrom-Json
                if ($tmplJson -and $tmplJson.PSObject.Properties['templates']) {
                    $templates = $tmplJson.templates
                } else {
                    $templates = @()
                }
                $script:TemplatesCache[$vendor] = $templates
            } else {
                $templates = @()
            }
        }
        # Build name → template(s) index on each call so that
        # Get-InterfaceConfiguration can look up a template by name in O(1) time.
        try {
            if ($templates) {
                $script:TemplatesByName = $templates | Group-Object -Property name -AsHashTable -AsString
            } else {
                $script:TemplatesByName = @{}
            }
        } catch {
            $script:TemplatesByName = @{}
        }
    } catch {}
    # Normalise $Data into an enumerable collection of rows.  Support DataTable,
    $rows = @()
    if ($Data -is [System.Data.DataTable]) {
        $rows = $Data.Rows
    } elseif ($Data -is [System.Data.DataView]) {
        $rows = $Data
    } elseif ($Data -is [System.Collections.IEnumerable]) {
        $rows = $Data
    } else {
        return @()
    }
    # Use a strongly typed List[object] instead of a PowerShell array.  Using
    $resultList = New-Object 'System.Collections.Generic.List[object]'

    # Precompute a lookup table for compliance templates when available.  When
    $templateLookup = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
    if ($templates) {
        foreach ($tmpl in $templates) {
            # Add the primary name as-is.  The dictionary key comparer will treat
            $key = ('' + $tmpl.name)
            if (-not $templateLookup.ContainsKey($key)) { $templateLookup[$key] = $tmpl }
            # Add each alias as a separate key.  Guard against null alias lists.
            if ($tmpl.aliases) {
                foreach ($a in $tmpl.aliases) {
                    $aliasKey = ('' + $a)
                    if (-not $templateLookup.ContainsKey($aliasKey)) { $templateLookup[$aliasKey] = $tmpl }
                }
            }
        }
    }
    foreach ($row in $rows) {
        if (-not $row) { continue }
        # Safely extract fields; some properties may not exist on all row types.
        $authTemplate = $null
        if ($row.PSObject.Properties['AuthTemplate']) { $authTemplate = $row.AuthTemplate }
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
        $hasPortColor    = $false
        $hasConfigStatus = $false
        if ($row.PSObject.Properties['PortColor'] -and $row.PortColor) {
            $portColorVal = $row.PortColor
            $hasPortColor = $true
        }
        if ($row.PSObject.Properties['ConfigStatus'] -and $row.ConfigStatus) {
            $cfgStatusVal = $row.ConfigStatus
            $hasConfigStatus = $true
        }
        # If no explicit values were provided, look up the template colour and status.
        if (-not $hasPortColor -or -not $hasConfigStatus) {
            $match = $null
            if ($authTemplate) {
                # Perform a case-insensitive lookup in the prebuilt template map.  The keys
                $key = ('' + $authTemplate).ToLower()
                if ($templateLookup.ContainsKey($key)) { $match = $templateLookup[$key] }
            }
            if (-not $hasPortColor) {
                if ($match) { $portColorVal = $match.color } else { $portColorVal = 'Gray' }
            }
            if (-not $hasConfigStatus) {
                if ($match) {
                    $cfgStatusVal = 'Match'
                } elseif ($authTemplate) {
                    $cfgStatusVal = 'Mismatch'
                } else {
                    # When no template information exists, fall back to Unknown for consistency with Get‑DeviceDetails.
                    $cfgStatusVal = 'Unknown'
                }
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
        [void]$resultList.Add([PSCustomObject]@{
            Hostname      = $Hostname
            Port          = $(if ($row.PSObject.Properties['Port']) { $row.Port } else { $null })
            Name          = $(if ($row.PSObject.Properties['Name']) { $row.Name } else { $null })
            Status        = $(if ($row.PSObject.Properties['Status']) { $row.Status } else { $null })
            VLAN          = $(if ($row.PSObject.Properties['VLAN']) { $row.VLAN } else { $null })
            Duplex        = $(if ($row.PSObject.Properties['Duplex']) { $row.Duplex } else { $null })
            Speed         = $(if ($row.PSObject.Properties['Speed']) { $row.Speed } else { $null })
            Type          = $(if ($row.PSObject.Properties['Type']) { $row.Type } else { $null })
            LearnedMACs   = $(if ($row.PSObject.Properties['LearnedMACs']) { $row.LearnedMACs } else { $null })
            AuthState     = $(if ($row.PSObject.Properties['AuthState']) { $row.AuthState } else { $null })
            AuthMode      = $(if ($row.PSObject.Properties['AuthMode']) { $row.AuthMode } else { $null })
            AuthClientMAC = $(if ($row.PSObject.Properties['AuthClientMAC']) { $row.AuthClientMAC } else { $null })
            ToolTip       = $finalTip
            IsSelected    = $false
            ConfigStatus  = $cfgStatusVal
            PortColor     = $portColorVal
        })
    }
    return $resultList
}

function Get-DeviceSummaries {
    # Always prefer loading device summaries from all available per-site databases.
    $names = New-Object 'System.Collections.Generic.List[string]'
    $global:DeviceMetadata = @{}
    $dbPaths = Get-AllSiteDbPaths
    if ($dbPaths.Count -gt 0) {
        foreach ($dbPath in $dbPaths) {
            try {
                $dt = Invoke-DbQuery -DatabasePath $dbPath -Sql "SELECT Hostname, Site, Building, Room FROM DeviceSummary"
                if ($dt) {
                    $rows = $dt | Select-Object Hostname, Site, Building, Room
                    foreach ($row in $rows) {
                        $name = $row.Hostname
                        if (-not [string]::IsNullOrWhiteSpace($name)) {
                            if (-not $names.Contains($name)) { [void]$names.Add($name) }
                            $siteRaw     = $row.Site
                            $buildingRaw = $row.Building
                            $roomRaw     = $row.Room
                            $siteVal     = if ($siteRaw -eq $null -or $siteRaw -eq [System.DBNull]::Value) { '' } else { [string]$siteRaw }
                            $buildingVal = if ($buildingRaw -eq $null -or $buildingRaw -eq [System.DBNull]::Value) { '' } else { [string]$buildingRaw }
                            $roomVal     = if ($roomRaw -eq $null -or $roomRaw -eq [System.DBNull]::Value) { '' } else { [string]$roomRaw }
                            # Derive the zone from the hostname.  A zone is defined as the string
                            # between the first and second hyphen in the device name (e.g. A05 in WLLS-A05-AS-05).
                            $zoneVal = ''
                            try {
                                $parts = $name -split '-', 3
                                if ($parts.Length -ge 2) { $zoneVal = $parts[1] }
                            } catch { $zoneVal = '' }
                            $meta = [PSCustomObject]@{
                                Site     = $siteVal
                                Zone     = $zoneVal
                                Building = $buildingVal
                                Room     = $roomVal
                            }
                            $global:DeviceMetadata[$name] = $meta
                        }
                    }
                }
            } catch {
                Write-Warning ("Failed to query device summaries from {0}: {1}" -f $dbPath, $_.Exception.Message)
            }
        }
    } else {
        Write-Warning "No per-site databases found. Device list will be empty."
    }

    # Update the host dropdown and location filters based on the loaded device metadata.
    $hostnameDD = $window.FindName('HostnameDropdown')
    # Initialise the hostname dropdown with the loaded list of names.  This helper
    Set-DropdownItems -Control $hostnameDD -Items $names

    $siteDD = $window.FindName('SiteDropdown')
    $uniqueSites = @()
    if ($DeviceMetadata.Count -gt 0) {
        # Build unique site list using a HashSet for better performance on large metadata sets.
        $siteSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($meta in $DeviceMetadata.Values) {
            $s = $meta.Site
            if (-not [string]::IsNullOrWhiteSpace($s)) { [void]$siteSet.Add($s) }
        }
        $uniqueSites = [System.Collections.Generic.List[string]]::new($siteSet)
        $uniqueSites.Sort([System.StringComparer]::OrdinalIgnoreCase)
    }
    # Prepend an "All Sites" entry to the list of unique sites so users can see all sites at once.
    Set-DropdownItems -Control $siteDD -Items (@('All Sites') + $uniqueSites)
    # Default to the first actual site rather than "All Sites" to improve performance.
    try {
        if ($uniqueSites.Count -gt 0) { $siteDD.SelectedItem = $uniqueSites[0] }
    } catch { }

    # Initialise the zone dropdown with "All Zones" and disable until a site is selected.
    $zoneDD = $window.FindName('ZoneDropdown')
    if ($zoneDD) {
        Set-DropdownItems -Control $zoneDD -Items @('All Zones')
        # Enable the zone dropdown from the outset so that users can select a zone even when "All Sites" is chosen.
        $zoneDD.IsEnabled = $true
    }

    $buildingDD = $window.FindName('BuildingDropdown')
    # Initialise building dropdown with a single blank option and disable until a site is chosen.
    Set-DropdownItems -Control $buildingDD -Items @('')
    $buildingDD.IsEnabled = $false

    $roomDD = $window.FindName('RoomDropdown')
    if ($roomDD) {
        # Initialise room dropdown with a blank entry and disable initially.
        Set-DropdownItems -Control $roomDD -Items @('')
        $roomDD.IsEnabled = $false
    }

    # Rebuild the global interface list and update the search grid.  Without the
    if (Get-Command Update-GlobalInterfaceList -ErrorAction SilentlyContinue) {
        Update-GlobalInterfaceList
        $searchHostCtrl = $window.FindName('SearchInterfacesHost')
        if ($searchHostCtrl -is [System.Windows.Controls.ContentControl]) {
            $searchView = $searchHostCtrl.Content
            if ($searchView) {
                $searchGrid = $searchView.FindName('SearchInterfacesGrid')
                if ($searchGrid) { $searchGrid.ItemsSource = $global:AllInterfaces }
            }
        }
    }
}

function Update-DeviceFilter {
    # Abort immediately if a previous filter update threw an error.  The
    # main timer catch handler will set $script:DeviceFilterFaulted to $true
    # when an unhandled exception occurs, avoiding a tight retry loop that
    # spams warnings when the host runspace is constrained (e.g. NoLanguage).
    if ($script:DeviceFilterFaulted) { return }
    if ($script:DeviceFilterUpdating) { return }
    $script:DeviceFilterUpdating = $true
    # When repopulating the filter dropdowns, temporarily suppress any
    # selection-changed events from triggering a new Request-DeviceFilterUpdate.
    # Set a global flag so that Request-DeviceFilterUpdate can detect programmatic
    # updates and ignore them.  Preserve the prior state to restore later.
    $___prevProgFlag = $global:ProgrammaticFilterUpdate
    $global:ProgrammaticFilterUpdate = $true
    try {
        # Detect changes in site and building selections from the last invocation.  When the
        $loc0 = Get-SelectedLocation
        $currentSiteSel = $loc0.Site
        $currentZoneSel = $loc0.Zone
        $currentBldSel  = $loc0.Building
        # Determine which filters have changed since the last invocation.
        $siteChanged = ([System.StringComparer]::OrdinalIgnoreCase.Compare(('' + $currentSiteSel), ('' + $script:LastSiteSel)) -ne 0)
        $zoneChanged = ([System.StringComparer]::OrdinalIgnoreCase.Compare(('' + $currentZoneSel), ('' + $script:LastZoneSel)) -ne 0)
        $bldChanged  = ([System.StringComparer]::OrdinalIgnoreCase.Compare(('' + $currentBldSel),  ('' + $script:LastBuildingSel)) -ne 0)

        # Emit diagnostics to help track filter update state.  Use the Write-Diag helper if defined;
        # otherwise fall back to Write-Verbose.  Log current selections and which filters changed.
        try {
            $diagMsg = "Update-DeviceFilter: siteSel='{0}', zoneSel='{1}', bldSel='{2}', siteChanged={3}, zoneChanged={4}, bldChanged={5}" -f `
                ('' + $currentSiteSel), ('' + $currentZoneSel), ('' + $currentBldSel), $siteChanged, $zoneChanged, $bldChanged
            if (Get-Command -Name Write-Diag -ErrorAction SilentlyContinue) {
                Write-Diag $diagMsg
            } else {
                Write-Verbose $diagMsg
            }
        } catch {}

        # Reset dependent dropdowns when parent selections change.
        $zoneDD     = $window.FindName('ZoneDropdown')
        $buildingDD = $window.FindName('BuildingDropdown')
        $roomDD     = $window.FindName('RoomDropdown')
        if ($siteChanged -and $zoneDD) {
            # When the site changes, reset the zone list to the sentinel only.  Do not disable the control here.
            DeviceDataModule\Set-DropdownItems -Control $zoneDD -Items @('All Zones')
            # Always leave the zone dropdown enabled when a site is selected (including the "All Sites" sentinel).  If no site
            # selection exists (blank), the zone list will remain enabled so the user can choose a zone across sites later.
            $zoneDD.IsEnabled = $true
        }
        if ( ($siteChanged -or $zoneChanged) -and $buildingDD ) {
            # When the site or zone changes, clear the building and room lists and disable room until a building is selected.
            DeviceDataModule\Set-DropdownItems -Control $buildingDD -Items @('')
            $buildingDD.IsEnabled = if ($currentSiteSel -and $currentSiteSel -ne '' -and $currentSiteSel -ne 'All Sites') { $true } else { $false }
            if ($roomDD) {
                DeviceDataModule\Set-DropdownItems -Control $roomDD -Items @('')
                $roomDD.IsEnabled = $false
            }
        } elseif ($bldChanged -and $roomDD) {
            # Building changed: clear the room list and update its enabled state.
            DeviceDataModule\Set-DropdownItems -Control $roomDD -Items @('')
            $roomDD.IsEnabled = if ($currentBldSel -and $currentBldSel -ne '') { $true } else { $false }
        }

        if (-not $global:DeviceMetadata) {
            Write-Verbose 'DeviceDataModule: DeviceMetadata not yet loaded; skipping device filter update.'
            return
        }

    # Determine the currently selected site (we intentionally ignore building
    $loc    = Get-SelectedLocation
    $siteSel = $loc.Site
    $zoneSel = $loc.Zone

    # ---------------------------------------------------------------------
    $buildingSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($meta in $DeviceMetadata.Values) {
        if ($siteSel -and $siteSel -ne '' -and $siteSel -ne 'All Sites' -and $meta.Site -ne $siteSel) { continue }
        if ($zoneSel -and $zoneSel -ne '' -and $zoneSel -ne 'All Zones' -and ($meta.PSObject.Properties.Name -contains 'Zone') -and $meta.Zone -ne $zoneSel) { continue }
        $b = $meta.Building
        if (-not [string]::IsNullOrWhiteSpace($b)) { [void]$buildingSet.Add($b) }
    }
    $availableBuildings = [System.Collections.Generic.List[string]]::new($buildingSet)
    $availableBuildings.Sort([System.StringComparer]::OrdinalIgnoreCase)
    # Build the list of zones for the selected site.  A zone represents the
    # second hyphen-delimited component in the hostname (e.g. A05 in WLLS-A05-AS-05).
    $zoneDD = $window.FindName('ZoneDropdown')
    if ($zoneDD) {
        $zoneSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($meta in $DeviceMetadata.Values) {
            if ($siteSel -and $siteSel -ne '' -and $siteSel -ne 'All Sites' -and $meta.Site -ne $siteSel) { continue }
            $z = ''
            if ($meta.PSObject.Properties.Name -contains 'Zone') { $z = $meta.Zone }
            if (-not [string]::IsNullOrWhiteSpace($z)) { [void]$zoneSet.Add($z) }
        }
        $zones = [System.Collections.Generic.List[string]]::new($zoneSet)
        $zones.Sort([System.StringComparer]::OrdinalIgnoreCase)
        $prevZoneSel = $zoneDD.SelectedItem
        # Populate zone dropdown with an "All Zones" sentinel plus the zones.
        Set-DropdownItems -Control $zoneDD -Items (@('All Zones') + $zones)
        # Always enable the zone dropdown regardless of the site selection.  This allows
        # users to select a specific zone even when "All Sites" is chosen.  Disabling
        # the control based on a blank site selection prevented zone filtering from
        # working when loading all devices.
        $zoneDD.IsEnabled = $true

        # Determine which zone should be selected in the new list.  The logic prioritizes the user's
        # current selection (captured in $prevZoneSel) when the zone is changed by the user, falls back
        # to the first real zone on the first run or when the site changes, and otherwise attempts to
        # preserve the previously selected zone stored in $script:LastZoneSel.  If the requested zone
        # does not exist in the new zone list, fall back to the sentinel ("All Zones").
        $selectIndex = 0
        $selectItem  = $null
        # Determine if this is the initial invocation or if the site changed.  When the site changes, we
        # reset the zone to the first real zone if available to limit the data loaded.
        $firstRunOrSiteChange = $false
        try {
            if (-not ($script:LastSiteSel) -or (-not [string]::IsNullOrEmpty($script:LastSiteSel) -and
                [System.StringComparer]::OrdinalIgnoreCase.Compare(('' + $script:LastSiteSel), ('' + $siteSel)) -ne 0)) {
                $firstRunOrSiteChange = $true
            }
        } catch { $firstRunOrSiteChange = $true }
        if ($firstRunOrSiteChange) {
            # When the site changes (or during the first run), pick a default zone.  For specific
            # sites, default to the first real zone (index 1) if available.  Otherwise, for
            # "All Sites" or blank selections, default to the sentinel (index 0) so that all
            # zones remain visible.
            # When a specific site (not "All Sites") is selected and there is at least one real zone,
            # default to the first real zone (index 1).  Treat the site selection as a string for
            # comparison because SelectedItem may not be a string object.  Otherwise, default to the
            # sentinel at index 0 so that all zones remain visible.
            $siteText = '' + $siteSel
            if ($siteText -ne '' -and $siteText -ne 'All Sites' -and $zoneDD.Items.Count -gt 1) {
                $selectIndex = 1
            } else {
                $selectIndex = 0
            }
        } elseif ($zoneChanged) {
            # User explicitly changed the zone.  Preserve the current selection if it exists in the list.
            if ($prevZoneSel -and $prevZoneSel -ne '' -and $prevZoneSel -ne 'All Zones' -and ($zones -contains $prevZoneSel)) {
                $selectItem = $prevZoneSel
            } elseif ($prevZoneSel -and $prevZoneSel -eq 'All Zones') {
                $selectIndex = 0
            } else {
                # Unknown or invalid zone: fall back to sentinel.
                $selectIndex = 0
            }
        } else {
            # Neither first run nor user-initiated zone change.  Attempt to restore the last zone.
            $lastZone = $null
            try { $lastZone = $script:LastZoneSel } catch { $lastZone = $null }
            if ($lastZone -and $lastZone -ne '' -and $lastZone -ne 'All Zones' -and ($zones -contains $lastZone)) {
                $selectItem = $lastZone
            } else {
                $selectIndex = 0
            }
        }
        # Apply the computed selection to the zone dropdown.  Prefer SelectedItem when a specific
        # zone string is requested; otherwise use SelectedIndex.  Wrap in try/catch to avoid throwing.
        try {
            if ($selectItem) {
                $zoneDD.SelectedItem = $selectItem
            } else {
                $zoneDD.SelectedIndex = $selectIndex
            }
        } catch { }

        # Diagnostic: log how zone selection was determined and what was ultimately selected.
        try {
            $finalZone = ''
            try { $finalZone = '' + $zoneDD.SelectedItem } catch {}
            $diagZoneMsg = "ZoneSelection | firstRunOrSiteChange={0}, lastZone='{1}', selectIndex={2}, selectItem='{3}', finalSelected='{4}'" -f `
                $firstRunOrSiteChange, ('' + $lastZone), $selectIndex, ('' + $selectItem), $finalZone
            if (Get-Command -Name Write-Diag -ErrorAction SilentlyContinue) {
                Write-Diag $diagZoneMsg
            } else {
                Write-Verbose $diagZoneMsg
            }
        } catch {}
    }

    $buildingDD = $window.FindName('BuildingDropdown')
    $prevBuildingSel = $buildingDD.SelectedItem
    # Populate building dropdown with a blank entry plus all available buildings.
    $currentBuildings = @()
try { $currentBuildings = @($buildingDD.ItemsSource) } catch {}
if ($currentBuildings.Count -gt 0 -and ('' + $currentBuildings[0]) -eq '') {
    if ($currentBuildings.Count -gt 1) { $currentBuildings = $currentBuildings[1..($currentBuildings.Count-1)] } else { $currentBuildings = @() }
}
if (-not (Test-StringListEqualCI $currentBuildings $availableBuildings)) {
    Set-DropdownItems -Control $buildingDD -Items (@('') + $availableBuildings)
}

    # Restore prior selection if it still exists in the list (ignoring the
    if ($prevBuildingSel -and $prevBuildingSel -ne '' -and ($availableBuildings -contains $prevBuildingSel)) {
        try { $buildingDD.SelectedItem = $prevBuildingSel } catch { }
    }
    # Enable or disable the building dropdown based on site selection (excluding the "All Sites" sentinel).
    if ($siteSel -and $siteSel -ne '' -and $siteSel -ne 'All Sites') {
        $buildingDD.IsEnabled = $true
    } else {
        $buildingDD.IsEnabled = $false
    }

    # Capture the now-finalised building and room selections after the dropdown
    $bldSel  = $buildingDD.SelectedItem
    $roomDD  = $window.FindName('RoomDropdown')
    $roomSel = if ($roomDD) { $roomDD.SelectedItem } else { $null }

    # Refresh the selected zone for filtering.  The zone may have changed
    # as a result of resetting the dropdowns above, so retrieve the current
    # location selections again.  If the call fails, default to null.  We
    # compute this here instead of using the earlier $currentZoneSel so that
    # the latest user selection is respected when filtering hostnames.
    $zoneSel = $null
    try {
        $locFinal = Get-SelectedLocation
        $zoneSel = $locFinal.Zone
    } catch { $zoneSel = $null }

    # ---------------------------------------------------------------------
    $filteredNames = New-Object 'System.Collections.Generic.List[string]'
    foreach ($name in $DeviceMetadata.Keys) {
        $meta = $DeviceMetadata[$name]
        # Apply site filtering only when a specific site (other than the "All Sites" sentinel) is selected.
        if ($siteSel -and $siteSel -ne '' -and $siteSel -ne 'All Sites' -and $meta.Site -ne $siteSel) { continue }
        # Apply zone filtering when a specific zone (other than All Zones) is selected.  Determine the
        # zone from the metadata if available; otherwise parse it from the hostname.  Only include hosts
        # whose computed zone matches the selected zone.
        if ($zoneSel -and $zoneSel -ne '' -and $zoneSel -ne 'All Zones') {
            $metaZone = $null
            if ($meta.PSObject.Properties['Zone']) {
                $metaZone = '' + $meta.Zone
            } else {
                try {
                    $parts = ('' + $name) -split '-'
                    if ($parts.Length -ge 2) { $metaZone = $parts[1] }
                } catch { $metaZone = $null }
            }
            if (-not $metaZone -or $metaZone -ne $zoneSel) { continue }
        }
        if ($bldSel  -and $bldSel  -ne '' -and $meta.Building -ne $bldSel)  { continue }
        if ($roomSel -and $roomSel -ne '' -and $meta.Room     -ne $roomSel) { continue }
        [void]$filteredNames.Add($name)
    }
    # Emit diagnostics about the host filtering result: number of hosts and sample names.
    try {
        $siteDbg = '' + $siteSel
        $zoneDbg = '' + $zoneSel
        $bldDbg  = '' + $bldSel
        $roomDbg = '' + $roomSel
        $countDbg = if ($filteredNames) { $filteredNames.Count } else { 0 }
        $sample = ''
        try {
            if ($filteredNames -and $filteredNames.Count -gt 0) {
                # Capture up to the first 5 hostnames for diagnostics.
                $sample = ($filteredNames | Select-Object -First 5) -join ','
            }
        } catch { $sample = '' }
        $diagHostMsg = "HostFilter | site='{0}', zone='{1}', building='{2}', room='{3}', count={4}, sample=[{5}]" -f `
            $siteDbg, $zoneDbg, $bldDbg, $roomDbg, $countDbg, $sample
        if (Get-Command -Name Write-Diag -ErrorAction SilentlyContinue) {
            Write-Diag $diagHostMsg
        } else {
            Write-Verbose $diagHostMsg
        }
    } catch {}

    # Sort the filtered hostnames alphabetically (ascending) using OrdinalIgnoreCase.  This ensures
    if ($filteredNames -and $filteredNames.Count -gt 1) {
        $filteredNames.Sort([System.StringComparer]::OrdinalIgnoreCase)
        $unknownIndex = $filteredNames.IndexOf('Unknown')
        if ($unknownIndex -gt 0) {
            $tmp = $filteredNames[0]
            $filteredNames[0] = $filteredNames[$unknownIndex]
            $filteredNames[$unknownIndex] = $tmp
        }
    }
    $hostnameDD = $window.FindName('HostnameDropdown')
    # Populate the hostname dropdown with the filtered list.  When no hosts match
    # the current site/building/room filters, ensure we still pass at least one
    # entry to satisfy the mandatory object[] parameter for Set-DropdownItems.
    if (-not $filteredNames -or $filteredNames.Count -eq 0) {
        # Provide a single blank entry to allow binding and leave the dropdown empty.
        Set-DropdownItems -Control $hostnameDD -Items @('')
    } else {
        Set-DropdownItems -Control $hostnameDD -Items $filteredNames
    }

    # Diagnostic: log the number of filtered hosts and the current zone selection.  Include
    # the first few hostnames for inspection.  Use Write-Diag if available.
    try {
        $hostCount = if ($filteredNames) { $filteredNames.Count } else { 0 }
        $exampleHosts = ''
        if ($hostCount -gt 0) {
            $take = [System.Math]::Min(3, $hostCount)
            $exampleHosts = ($filteredNames | Select-Object -First $take) -join ', '
        }
        $locCur = Get-SelectedLocation
        $msgHosts = "HostFilter | site='{0}', zone='{1}', building='{2}', room='{3}', count={4}, examples=[{5}]" -f `
            ('' + $locCur.Site), ('' + $locCur.Zone), ('' + $locCur.Building), ('' + $locCur.Room), $hostCount, $exampleHosts
        if (Get-Command -Name Write-Diag -ErrorAction SilentlyContinue) {
            Write-Diag $msgHosts
        } else {
            Write-Verbose $msgHosts
        }
    } catch {}

    # ---------------------------------------------------------------------
    $roomSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($meta in $DeviceMetadata.Values) {
        if ($siteSel -and $siteSel -ne '' -and $meta.Site -ne $siteSel) { continue }
        if ($bldSel  -and $bldSel  -ne '' -and $meta.Building -ne $bldSel) { continue }
        $r = $meta.Room
        if (-not [string]::IsNullOrWhiteSpace($r)) { [void]$roomSet.Add($r) }
    }
    $availableRooms = [System.Collections.Generic.List[string]]::new($roomSet)
    $availableRooms.Sort([System.StringComparer]::OrdinalIgnoreCase)
    if ($roomDD) {
        $currentRooms = @()
        try { $currentRooms = @($roomDD.ItemsSource) } catch {}
        # Remove any leading blank from the current ItemsSource so only the
        if ($currentRooms.Count -gt 0 -and ('' + $currentRooms[0]) -eq '') {
            if ($currentRooms.Count -gt 1) {
                $currentRooms = $currentRooms[1..($currentRooms.Count - 1)]
            } else {
                $currentRooms = @()
            }
        }
        # Determine whether we need to force a reset of the room list.  When
        $forceRoomReset = $siteChanged -or $bldChanged
        if ($forceRoomReset -or -not (Test-StringListEqualCI $currentRooms $availableRooms)) {
            Set-DropdownItems -Control $roomDD -Items (@('') + $availableRooms)
        }
        # Enable the room dropdown only when a non‑blank site and building are
        if (($siteSel -and $siteSel -ne '') -and ($buildingDD.SelectedIndex -gt 0)) {
            $roomDD.IsEnabled = $true
        } else {
            $roomDD.IsEnabled = $false
        }
    }

    # ---------------------------------------------------------------------
    if (Get-Command Update-SearchGrid -ErrorAction SilentlyContinue) {
        Update-SearchGrid
    }
    if (Get-Command Update-Summary -ErrorAction SilentlyContinue) {
        Update-Summary
    }
    if (Get-Command Update-Alerts -ErrorAction SilentlyContinue) {
        Update-Alerts
    }
        # Record the current site and building selections for the next invocation.  Storing
        try {
            $locFinal = Get-SelectedLocation
            $script:LastSiteSel     = $locFinal.Site
            $script:LastZoneSel     = $locFinal.Zone
            $script:LastBuildingSel = $locFinal.Building
            try { $script:LastRoomSel = $locFinal.Room } catch {}
        } catch {}
    } finally {
        # Restore the prior programmatic flag and clear the DeviceFilterUpdating lock.
        $global:ProgrammaticFilterUpdate = $___prevProgFlag
        $script:DeviceFilterUpdating = $false
    }
}

function Get-DeviceDetails {
    param($hostname)
    try {
        # Determine the per-site database path for this host.  Use database
        # queries only if the file exists; otherwise fall back to CSV.
        $dbPath = Get-DbPathForHost $hostname
        $useDb = $false
        if (Test-Path $dbPath) { $useDb = $true }

        if ($useDb) {
            # Prepare for database operations.  (No explicit session reuse at this level.)
            $hostTrim = ($hostname -as [string]).Trim()
            $escHost   = $hostTrim -replace "'", "''"
            # Build a comma-separated list of character codes using a typed list
            $charCodesList = New-Object 'System.Collections.Generic.List[int]'
            foreach ($ch in $hostTrim.ToCharArray()) { [void]$charCodesList.Add([int]$ch) }
            $charCodes = [string]::Join(',', $charCodesList)

            $summarySql = "SELECT Hostname, Make, Model, Uptime, Ports, AuthDefaultVLAN, Building, Room " +
                          "FROM DeviceSummary " +
                          "WHERE Hostname = '$escHost' " +
                          "   OR Hostname LIKE '*$escHost*'"
            $dtSummary = Invoke-DbQuery -DatabasePath $dbPath -Sql $summarySql

            if ($dtSummary) {
                foreach ($rowTmp in ($dtSummary | Select-Object Hostname, Make, Model, Uptime, Ports, AuthDefaultVLAN, Building, Room)) {
                    # no-op; loop exists solely to assign variables if needed
                    $null = $rowTmp
                }
            }
            $summaryObjects = @()
            if ($dtSummary) {
                $summaryObjects = @($dtSummary | Select-Object Hostname, Make, Model, Uptime, Ports, AuthDefaultVLAN, Building, Room)
            }
            $dtSummaryAll = Invoke-DbQuery -DatabasePath $dbPath -Sql "SELECT Hostname, Make, Model, Uptime, Ports, AuthDefaultVLAN, Building, Room FROM DeviceSummary"

            $esc = $hostTrim -replace "'", "''"
            $fbMake = ''
            $fbModel = ''
            $fbUptime = ''
            $fbAuthDef = ''
            $fbBuilding = ''
            $fbRoom = ''
            $fbPorts = ''
            try {
                $hist = Invoke-DbQuery -DatabasePath $dbPath -Sql "SELECT TOP 1 Make, Model, Uptime, AuthDefaultVLAN, Building, Room FROM DeviceHistory WHERE Trim(Hostname) = '$esc' ORDER BY RunDate DESC"
                if ($hist -and $hist.Rows.Count -gt 0) {
                    $hrow = ($hist | Select-Object Make, Model, Uptime, AuthDefaultVLAN, Building, Room)[0]
                    $fbMake    = $hrow.Make
                    $fbModel   = $hrow.Model
                    $fbUptime  = $hrow.Uptime
                    $fbAuthDef = $hrow.AuthDefaultVLAN
                    $fbBuilding= $hrow.Building
                    $fbRoom    = $hrow.Room
                }
            } catch {}
            try {
                $cntDt = Invoke-DbQuery -DatabasePath $dbPath -Sql "SELECT COUNT(*) AS PortCount FROM Interfaces WHERE Trim(Hostname) = '$esc'"
                if ($cntDt -and $cntDt.Rows.Count -gt 0) {
                    $fbPorts = ($cntDt | Select-Object -ExpandProperty PortCount)[0]
                }
            } catch {}

            if ($summaryObjects.Count -gt 0) {
                $row = $summaryObjects[0]
                $makeVal    = $row.Make
                if (-not $makeVal -or $makeVal -eq [System.DBNull]::Value -or $makeVal -eq '') { $makeVal = $fbMake }
                $modelVal   = $row.Model
                if (-not $modelVal -or $modelVal -eq [System.DBNull]::Value -or $modelVal -eq '') { $modelVal = $fbModel }
                $uptimeVal  = $row.Uptime
                if (-not $uptimeVal -or $uptimeVal -eq [System.DBNull]::Value -or $uptimeVal -eq '') { $uptimeVal = $fbUptime }
                $portsVal   = $row.Ports
                if (-not $portsVal -or $portsVal -eq [System.DBNull]::Value -or $portsVal -eq 0) { $portsVal = $fbPorts }
                $authDefVal= $row.AuthDefaultVLAN
                if (-not $authDefVal -or $authDefVal -eq [System.DBNull]::Value -or $authDefVal -eq '') { $authDefVal = $fbAuthDef }
                $buildingVal= $row.Building
                if (-not $buildingVal -or $buildingVal -eq [System.DBNull]::Value -or $buildingVal -eq '') { $buildingVal = $fbBuilding }
                $roomVal    = $row.Room
                if (-not $roomVal -or $roomVal -eq [System.DBNull]::Value -or $roomVal -eq '') { $roomVal = $fbRoom }
                $interfacesView.FindName('HostnameBox').Text        = $row.Hostname
                $interfacesView.FindName('MakeBox').Text            = $makeVal
                $interfacesView.FindName('ModelBox').Text           = $modelVal
                $interfacesView.FindName('UptimeBox').Text          = $uptimeVal
                $interfacesView.FindName('PortCountBox').Text       = $portsVal
                $interfacesView.FindName('AuthDefaultVLANBox').Text = $authDefVal
                $interfacesView.FindName('BuildingBox').Text        = $buildingVal
                $interfacesView.FindName('RoomBox').Text            = $roomVal

            } else {
                $interfacesView.FindName('HostnameBox').Text        = $hostname
                $interfacesView.FindName('MakeBox').Text            = $fbMake
                $interfacesView.FindName('ModelBox').Text           = $fbModel
                $interfacesView.FindName('UptimeBox').Text          = $fbUptime
                $interfacesView.FindName('PortCountBox').Text       = $fbPorts
                $interfacesView.FindName('AuthDefaultVLANBox').Text = $fbAuthDef
                $interfacesView.FindName('BuildingBox').Text        = $fbBuilding
                $interfacesView.FindName('RoomBox').Text            = $fbRoom

                if ($dtSummaryAll) {
                    # iterate rows silently
                    foreach ($rowAll in ($dtSummaryAll | Select-Object Hostname, Make, Model, Uptime, Ports, AuthDefaultVLAN, Building, Room)) {
                        $null = $rowAll
                    }
                }
            }
            # If a cached interface list exists for this device, reuse it to avoid re-querying
            try {
                if ($global:DeviceInterfaceCache.ContainsKey($hostname)) {
                    $cachedList = $global:DeviceInterfaceCache[$hostname]
                    $gridCached = $interfacesView.FindName('InterfacesGrid')
                    $gridCached.ItemsSource = $cachedList
                    $comboCached = $interfacesView.FindName('ConfigOptionsDropdown')
                    # Retrieve configuration templates and populate the combo using
                    $tmplList = Get-ConfigurationTemplates -Hostname $hostname
                    Set-DropdownItems -Control $comboCached -Items $tmplList
                    return
                }
            } catch {}

            # Query interface details for the specified host from the database.  Include
            $dtIfs = Invoke-DbQuery -DatabasePath $dbPath -Sql "SELECT Hostname, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, ConfigStatus, PortColor, ToolTip FROM Interfaces WHERE Hostname = '$($hostname -replace "'", "''")'"
            # Use a shared helper to build the interface PSCustomObject list.  This centralises vendor detection,
            $list = New-InterfaceObjectsFromDbRow -Data $dtIfs -Hostname $hostname -TemplatesPath (Join-Path $PSScriptRoot '..\Templates')
            # Cache this device's interface list for future visits.  The cache stores the final PSCustomObject list keyed by hostname.
            try {
                $global:DeviceInterfaceCache[$hostname] = $list
            } catch {}
            # Update the grid with the freshly built list of interface objects.
            $grid = $interfacesView.FindName('InterfacesGrid')
            $grid.ItemsSource = $list
            # Bind available configuration templates for this device.
            $combo = $interfacesView.FindName('ConfigOptionsDropdown')
            # Retrieve configuration templates and populate the combo using the helper.
            $tmplList2 = Get-ConfigurationTemplates -Hostname $hostname
            Set-DropdownItems -Control $combo -Items $tmplList2
        } else {
            $base     = Join-Path (Join-Path $scriptDir '..\ParsedData') $hostname
            $summary  = @(Import-Csv "${base}_Summary.csv")[0]
            $interfacesView.FindName('HostnameBox').Text        = $summary.Hostname
            $interfacesView.FindName('MakeBox').Text            = $summary.Make
            $interfacesView.FindName('ModelBox').Text           = $summary.Model
            $interfacesView.FindName('UptimeBox').Text          = $summary.Uptime
            $interfacesView.FindName('PortCountBox').Text       = $summary.InterfaceCount
            $interfacesView.FindName('AuthDefaultVLANBox').Text = $summary.AuthDefaultVLAN
            $interfacesView.FindName('BuildingBox').Text        = if ($summary.PSObject.Properties.Name -contains 'Building') { $summary.Building } else { '' }
            $interfacesView.FindName('RoomBox').Text            = if ($summary.PSObject.Properties.Name -contains 'Room')     { $summary.Room     } else { '' }

            $grid = $interfacesView.FindName('InterfacesGrid')
            $grid.ItemsSource = Get-InterfaceInfo -Hostname $hostname
            $combo = $interfacesView.FindName('ConfigOptionsDropdown')
            # Retrieve configuration templates and populate the combo using the helper.
            $tmplList3 = Get-ConfigurationTemplates -Hostname $hostname
            Set-DropdownItems -Control $combo -Items $tmplList3
        }
    } catch {
        [System.Windows.MessageBox]::Show("Error loading ${hostname}:`n$($_.Exception.Message)")
    }
}

# Retrieve device details and interface list without updating any UI controls.  This helper is

function Get-DeviceDetailsData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Hostname
    )
    # Coerce hostname to trimmed string
    $hostTrim = ('' + $Hostname).Trim()
    # Result object to populate
    $result = [PSCustomObject]@{
        Summary    = $null
        Interfaces = @()
        Templates  = @()
    }
    try {
        # Determine whether database is configured: use per-site DB if it exists
        $dbPath = Get-DbPathForHost $hostTrim
        $useDb = $false
        if (Test-Path $dbPath) { $useDb = $true }
        if (-not $useDb) {
            # Fallback to CSV import when no database is available
            $scriptDir = $PSScriptRoot
            $base  = Join-Path (Join-Path $scriptDir '..\ParsedData') $hostTrim
            # Attempt to import summary CSV
            $summary  = $null
            try {
                $summary  = @(Import-Csv "${base}_Summary.csv")[0]
            } catch {}
            # Build summary hashtable
            $sumHash = @{}
            if ($summary) {
                $sumHash.Hostname        = $summary.Hostname
                $sumHash.Make            = $summary.Make
                $sumHash.Model           = $summary.Model
                $sumHash.Uptime          = $summary.Uptime
                $sumHash.Ports           = $summary.InterfaceCount
                $sumHash.AuthDefaultVLAN = $summary.AuthDefaultVLAN
                $sumHash.Building        = if ($summary.PSObject.Properties.Name -contains 'Building') { $summary.Building } else { '' }
                $sumHash.Room            = if ($summary.PSObject.Properties.Name -contains 'Room')     { $summary.Room     } else { '' }
            } else {
                # Provide minimal summary with hostname only
                $sumHash.Hostname        = $hostTrim
                $sumHash.Make            = ''
                $sumHash.Model           = ''
                $sumHash.Uptime          = ''
                $sumHash.Ports           = ''
                $sumHash.AuthDefaultVLAN = ''
                $sumHash.Building        = ''
                $sumHash.Room            = ''
            }
            $result.Summary = $sumHash
            # Interfaces via Get‑InterfaceInfo (from CSV) if available
            try {
                $list = Get-InterfaceInfo -Hostname $hostTrim
                if ($list) { $result.Interfaces = $list }
            } catch {}
            # Configuration templates
            try {
                $tmpl = Get-ConfigurationTemplates -Hostname $hostTrim
                if ($tmpl) { $result.Templates = $tmpl }
            } catch {}
            return $result
        }
        # Escaped host for SQL
        $escHost   = $hostTrim -replace "'", "''"
        # Query summary row(s)
        $summarySql = "SELECT Hostname, Make, Model, Uptime, Ports, AuthDefaultVLAN, Building, Room FROM DeviceSummary WHERE Hostname = '$escHost' OR Hostname LIKE '*$escHost*'"
        $dtSummary = $null
        try { $dtSummary = Invoke-DbQuery -DatabasePath $dbPath -Sql $summarySql } catch {}
        # Gather summary fields from the first matching row, if any
        $makeVal     = ''
        $modelVal    = ''
        $uptimeVal   = ''
        $portsVal    = ''
        $authDefVal  = ''
        $buildingVal = ''
        $roomVal     = ''
        if ($dtSummary) {
            # Support DataTable/DataView or enumerable rows
            $rowObj = $null
            if ($dtSummary -is [System.Data.DataTable]) {
                if ($dtSummary.Rows.Count -gt 0) { $rowObj = $dtSummary.Rows[0] }
            } elseif ($dtSummary -is [System.Collections.IEnumerable]) {
                try { $rowObj = ($dtSummary | Select-Object -First 1) } catch {}
            }
            if ($rowObj) {
                $makeVal    = $rowObj.Make
                $modelVal   = $rowObj.Model
                $uptimeVal  = $rowObj.Uptime
                $portsVal   = $rowObj.Ports
                $authDefVal = $rowObj.AuthDefaultVLAN
                $buildingVal= $rowObj.Building
                $roomVal    = $rowObj.Room
            }
        }
        # Retrieve fallback values from DeviceHistory and Interfaces count
        $fbMake     = ''
        $fbModel    = ''
        $fbUptime   = ''
        $fbAuthDef  = ''
        $fbBuilding = ''
        $fbRoom     = ''
        $fbPorts    = ''
        try {
            $hist = Invoke-DbQuery -DatabasePath $dbPath -Sql "SELECT TOP 1 Make, Model, Uptime, AuthDefaultVLAN, Building, Room FROM DeviceHistory WHERE Trim(Hostname) = '$escHost' ORDER BY RunDate DESC"
            if ($hist -and $hist.Rows.Count -gt 0) {
                $hrow = $hist.Rows[0]
                $fbMake     = $hrow.Make
                $fbModel    = $hrow.Model
                $fbUptime   = $hrow.Uptime
                $fbAuthDef  = $hrow.AuthDefaultVLAN
                $fbBuilding = $hrow.Building
                $fbRoom     = $hrow.Room
            }
        } catch {}
        try {
            $cntDt = Invoke-DbQuery -DatabasePath $dbPath -Sql "SELECT COUNT(*) AS PortCount FROM Interfaces WHERE Trim(Hostname) = '$escHost'"
            if ($cntDt -and $cntDt.Rows.Count -gt 0) {
                $fbPorts = ($cntDt | Select-Object -ExpandProperty PortCount)[0]
            }
        } catch {}
        # Choose fallback values when summary values are missing
        if (-not $makeVal -or $makeVal -eq [System.DBNull]::Value -or $makeVal -eq '') { $makeVal = $fbMake }
        if (-not $modelVal -or $modelVal -eq [System.DBNull]::Value -or $modelVal -eq '') { $modelVal = $fbModel }
        if (-not $uptimeVal -or $uptimeVal -eq [System.DBNull]::Value -or $uptimeVal -eq '') { $uptimeVal = $fbUptime }
        if (-not $portsVal  -or $portsVal  -eq [System.DBNull]::Value -or $portsVal  -eq 0  -or $portsVal -eq '') { $portsVal  = $fbPorts }
        if (-not $authDefVal -or $authDefVal -eq [System.DBNull]::Value -or $authDefVal -eq '') { $authDefVal = $fbAuthDef }
        if (-not $buildingVal -or $buildingVal -eq [System.DBNull]::Value -or $buildingVal -eq '') { $buildingVal = $fbBuilding }
        if (-not $roomVal    -or $roomVal    -eq [System.DBNull]::Value -or $roomVal    -eq '') { $roomVal    = $fbRoom }
        # Build summary hashtable
        $result.Summary = @{
            Hostname        = $hostTrim
            Make            = $makeVal
            Model           = $modelVal
            Uptime          = $uptimeVal
            Ports           = $portsVal
            AuthDefaultVLAN = $authDefVal
            Building        = $buildingVal
            Room            = $roomVal
        }
        # Check for cached interface list
        $listIfs = @()
        $cacheHit = $false
        try {
            if ($global:DeviceInterfaceCache -and $global:DeviceInterfaceCache.ContainsKey($hostTrim)) {
                $listIfs = $global:DeviceInterfaceCache[$hostTrim]
                $cacheHit = $true
            }
        } catch {}
        if (-not $cacheHit) {
            # Query interfaces and build list
            $sqlIf = "SELECT Hostname, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, ConfigStatus, PortColor, ToolTip FROM Interfaces WHERE Hostname = '$escHost'"
            $dtIfs = $null
            try { $dtIfs = Invoke-DbQuery -DatabasePath $dbPath -Sql $sqlIf } catch {}
            if ($dtIfs) {
                try { $listIfs = New-InterfaceObjectsFromDbRow -Data $dtIfs -Hostname $hostTrim -TemplatesPath (Join-Path $PSScriptRoot '..\Templates') } catch {}
            }
            # Cache list for future use
            try {
                if (-not $global:DeviceInterfaceCache) { $global:DeviceInterfaceCache = @{} }
                $global:DeviceInterfaceCache[$hostTrim] = $listIfs
            } catch {}
        }
        $result.Interfaces = $listIfs
        # Retrieve configuration templates
        $tmplList = @()
        try { $tmplList = Get-ConfigurationTemplates -Hostname $hostTrim } catch {}
        if ($tmplList) { $result.Templates = $tmplList }
        return $result
    } catch {
        # On error, return null to indicate failure
        return $null
    }
}

# === GUI helper functions (merged from GuiModule) ===

function Invoke-ParallelDbQuery {
    [CmdletBinding()]
    param(
        [string[]]$DbPaths,
        [string]$Sql
    )
    # Determine the path to DatabaseModule.psm1.  Both modules reside in the same
    # directory, so join the current module directory with the module filename.
    $modulePath = Join-Path $PSScriptRoot 'DatabaseModule.psm1'
    # Limit concurrency to the number of logical processors.  At least one thread.
    $maxThreads = [Math]::Max(1, [Environment]::ProcessorCount)
    $pool = [runspacefactory]::CreateRunspacePool(1, $maxThreads)
    $pool.Open()
    $jobs = @()
    foreach ($dbPath in $DbPaths) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool
        # Use a script block that imports DatabaseModule and runs Invoke-DbQuery.
        # Pass all parameters explicitly to avoid relying on parent scope variables.
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
        } catch {} finally {
            $job.PS.Dispose()
        }
    }
    $pool.Close(); $pool.Dispose()
    return $results.ToArray()
}

function Update-GlobalInterfaceList {
    <#
    .SYNOPSIS
        Refresh the global interface list based on the current site selection.

    .DESCRIPTION
        This function replaces the previous implementation that loaded all
        interfaces from every site database at once.  Instead, it uses
        Get-InterfacesForSite to load only the interfaces for the currently
        selected site (or all sites when the user selects "All Sites").  The
        per‑site interface data is cached and automatically refreshed when
        the underlying database file changes, significantly reducing memory
        usage and improving startup time on systems with many devices.  After
        loading the interfaces, the function updates the global AllInterfaces
        variable and triggers a refresh of the Summary and Alerts views.

    .NOTES
        The site selection is obtained from Get-LastLocation so that
        Update-DeviceFilter can set the last known selections.  If no site
        has been selected or the selection is "All Sites", interfaces for
        all available sites will be loaded via Get-InterfacesForSite.
    #>
    # Determine the currently selected site by querying the UI directly.  Using
    # Get-SelectedLocation ensures we react to the user's latest selection
    # rather than the previously recorded LastSiteSel value.  This avoids
    # accidentally loading all sites on startup before LastSiteSel is set.
    $loc = $null
    try { $loc = Get-SelectedLocation } catch { $loc = $null }
    $siteSel = $null
    if ($loc) {
        try { $siteSel = $loc.Site } catch { $siteSel = $null }
    }
    # Load interfaces for the selected site.  Passing an empty or
    # null site argument instructs Get-InterfacesForSite to load all sites.
    $interfaces = $null
    try {
        $interfaces = Get-InterfacesForSite -Site $siteSel
    } catch {
        Write-Warning "Failed to load interfaces for site '$siteSel': $($_.Exception.Message)"
        $interfaces = New-Object 'System.Collections.Generic.List[object]'
    }
    # Publish the loaded list globally.  The list is already sorted by
    # Hostname and PortSort in Get-InterfacesForSite, so no additional sort
    # is required here.
    $global:AllInterfaces = $interfaces
    # Trigger dependent views to refresh if they are available.  These
    # functions honour location filters and will use the updated
    # $global:AllInterfaces list.
    if (Get-Command Update-Summary -ErrorAction SilentlyContinue) {
        Update-Summary
    }
    if (Get-Command Update-Alerts -ErrorAction SilentlyContinue) {
        Update-Alerts
    }
}

function Update-SearchResults {
    param([string]$Term)
    # Do not pre-normalize the search term to lowercase.  Case-insensitive comparisons
    $t = $Term
    # Always honour the location (site/building/room) filters, even when the search
    $loc = Get-SelectedLocation
    $siteSel = $loc.Site
    $zoneSel = $loc.Zone
    $bldSel  = $loc.Building
    $roomSel = $loc.Room
    # Acquire status and authorization filter selections once.  Lookup via the
    $statusFilterVal = 'All'
    $authFilterVal   = 'All'
    try {
        $searchHostCtrl = $global:window.FindName('SearchInterfacesHost')
        if ($searchHostCtrl) {
            $view = $searchHostCtrl.Content
            if ($view) {
                $statusCtrl = $view.FindName('StatusFilter')
                $authCtrl   = $view.FindName('AuthFilter')
                if ($statusCtrl -and $statusCtrl.SelectedItem) {
                    $statusFilterVal = $statusCtrl.SelectedItem.Content
                }
                if ($authCtrl -and $authCtrl.SelectedItem) {
                    $authFilterVal = $authCtrl.SelectedItem.Content
                }
            }
        }
    } catch {
    }
    # Create a typed list for results.  Using a .NET List avoids O(n^2) array growth
    $results = New-Object 'System.Collections.Generic.List[object]'
    # Determine if term is empty once
    $termEmpty = [string]::IsNullOrWhiteSpace($Term)
    foreach ($row in $global:AllInterfaces) {
        if (-not $row) { continue }
        # Cast row metadata to strings to ensure comparisons succeed.  When
        $rowSite     = '' + $row.Site
        $rowBuilding = '' + $row.Building
        $rowRoom     = '' + $row.Room
        # Use a normal if statement to derive the zone string.  Inline `(if ...)`
        # inside an expression is invalid in PowerShell and triggers a
        # CommandNotFoundException, even in FullLanguage.  Assign an empty
        # string by default, and populate it only if the Zone property exists.
        $rowZone = ''
        if ($row.PSObject.Properties['Zone']) {
            $rowZone = '' + $row.Zone
        }
        # Apply location filtering, taking into account "All" sentinels
        if ($siteSel -and $siteSel -ne '' -and $siteSel -ne 'All Sites' -and ($rowSite -ne $siteSel)) { continue }
        if ($zoneSel -and $zoneSel -ne '' -and $zoneSel -ne 'All Zones' -and ($rowZone -ne $zoneSel)) { continue }
        if ($bldSel  -and $bldSel  -ne '' -and ($rowBuilding -ne $bldSel))  { continue }
        if ($roomSel -and $roomSel -ne '' -and ($rowRoom     -ne $roomSel)) { continue }
        # Apply status filter
        if ($statusFilterVal -ne 'All') {
            $st = '' + $row.Status
            if ($statusFilterVal -eq 'Up') {
                if (-not ([System.StringComparer]::OrdinalIgnoreCase.Equals($st, 'up') -or
                          [System.StringComparer]::OrdinalIgnoreCase.Equals($st, 'connected'))) {
                    continue
                }
            } elseif ($statusFilterVal -eq 'Down') {
                if (-not ([System.StringComparer]::OrdinalIgnoreCase.Equals($st, 'down') -or
                          [System.StringComparer]::OrdinalIgnoreCase.Equals($st, 'notconnect'))) {
                    continue
                }
            }
        }
        # Apply authorization filter
        if ($authFilterVal -ne 'All') {
            $as = '' + $row.AuthState
            if ($authFilterVal -eq 'Authorized') {
                if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals($as, 'authorized')) { continue }
            } elseif ($authFilterVal -eq 'Unauthorized') {
                if ([System.StringComparer]::OrdinalIgnoreCase.Equals($as, 'authorized')) { continue }
            }
        }
        # Apply textual search filter
        if (-not $termEmpty) {
            if ($script:SearchRegexEnabled) {
                $matched = $false
                try {
                    if ( ('' + $row.Port)        -match $Term -or
                         ('' + $row.Name)        -match $Term -or
                         ('' + $row.LearnedMACs) -match $Term -or
                         ('' + $row.AuthClientMAC) -match $Term ) {
                        $matched = $true
                    }
                } catch {
                    # fall back to substring search
                }
                if (-not $matched) {
                    # fallback using case-insensitive substring search
                    $q = $Term
                    if (-not ((('' + $row.Port).IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                              (('' + $row.Name).IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                              (('' + $row.LearnedMACs).IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                              (('' + $row.AuthClientMAC).IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0))) {
                        continue
                    }
                }
            } else {
                # substring search
                $q = $Term
                if (-not ((('' + $row.Port).IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                          (('' + $row.Name).IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                          (('' + $row.LearnedMACs).IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                          (('' + $row.AuthClientMAC).IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0))) {
                    continue
                }
            }
        }
        # If all filters pass, add to result
        [void]$results.Add($row)
    }
    return ,$results
}

function Update-Summary {
    if (-not $global:summaryView) { return }
    # Determine location filters from the main window.  When blank,
    $siteSel = $null; $zoneSel = $null; $bldSel = $null; $roomSel = $null
    try {
        # Retrieve location selections via helper
        $loc = Get-SelectedLocation
        $siteSel = $loc.Site
        $zoneSel = $loc.Zone
        $bldSel  = $loc.Building
        $roomSel = $loc.Room
    } catch {}
    # Compute device count under location filters
    $devKeys = if ($global:DeviceMetadata) { $global:DeviceMetadata.Keys } else { @() }
    # Use a typed List to accumulate filtered device keys.  List.Add has amortized O(1) growth and
    $filteredDevices = [System.Collections.Generic.List[string]]::new()
    foreach ($k in $devKeys) {
        $meta = $global:DeviceMetadata[$k]
        if ($meta) {
            if ($siteSel -and $siteSel -ne '' -and $siteSel -ne 'All Sites' -and $meta.Site -ne $siteSel) { continue }
            if ($zoneSel -and $zoneSel -ne '' -and $zoneSel -ne 'All Zones' -and ($meta.PSObject.Properties['Zone']) -and $meta.Zone -ne $zoneSel) { continue }
            if ($bldSel  -and $bldSel  -ne '' -and $meta.Building -ne $bldSel) { continue }
            if ($roomSel -and $roomSel -ne '' -and $meta.Room     -ne $roomSel) { continue }
            [void]$filteredDevices.Add($k)
        }
    }
    $devCount = $filteredDevices.Count
    # Filter interface rows according to location
    $rows = if ($global:AllInterfaces) { $global:AllInterfaces } else { @() }
    # Use a typed List for filtered rows to avoid O(n^2) growth
    $filteredRows = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $rows) {
        $rSite = '' + $row.Site
        # Derive zone string without using an inline if expression.  Inline
        # `if` inside parentheses is invalid.  Assign empty by default.
        $rZone = ''
        if ($row.PSObject.Properties['Zone']) {
            $rZone = '' + $row.Zone
        }
        $rBld  = '' + $row.Building
        $rRoom = '' + $row.Room
        if ($siteSel -and $siteSel -ne '' -and $siteSel -ne 'All Sites' -and $rSite -ne $siteSel) { continue }
        if ($zoneSel -and $zoneSel -ne '' -and $zoneSel -ne 'All Zones' -and $rZone -ne $zoneSel) { continue }
        if ($bldSel  -and $bldSel  -ne '' -and $rBld  -ne $bldSel)  { continue }
        if ($roomSel -and $roomSel -ne '' -and $rRoom -ne $roomSel) { continue }
        [void]$filteredRows.Add($row)
    }
    $intCount = $filteredRows.Count
    $upCount = 0; $downCount = 0; $authCount = 0; $unauthCount = 0;
    # Gather VLANs using a typed List to avoid repeated array copies
    $vlans = [System.Collections.Generic.List[string]]::new()
    foreach ($row in $filteredRows) {
        $status = '' + $row.Status
        if ($status) {
            # Use case-insensitive regex patterns via (?i) instead of lowering
            switch -Regex ($status) {
                '(?i)^(up|connected)$' { $upCount++; break }
                '(?i)^(down|notconnect)$' { $downCount++; break }
                default { }
            }
        }
        $authState = '' + $row.AuthState
        if ($authState) {
            if ([System.StringComparer]::OrdinalIgnoreCase.Equals($authState, 'authorized')) { $authCount++ } else { $unauthCount++ }
        } else {
            $unauthCount++
        }
        if ($row.VLAN -and $row.VLAN -ne '') { [void]$vlans.Add($row.VLAN) }
    }
    # Build a unique set of VLANs using a HashSet.  Using Sort-Object -Unique on large
    $vlanSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($v in $vlans) {
        if (-not [string]::IsNullOrWhiteSpace($v)) { [void]$vlanSet.Add($v) }
    }
    $uniqueVlans = [System.Collections.Generic.List[string]]::new($vlanSet)
    $uniqueVlans.Sort([System.StringComparer]::OrdinalIgnoreCase)
    $uniqueCount = $uniqueVlans.Count
    try {
        $sv = $global:summaryView
        ($sv.FindName('SummaryDevicesCount')).Text      = $devCount.ToString()
        ($sv.FindName('SummaryInterfacesCount')).Text   = $intCount.ToString()
        ($sv.FindName('SummaryUpCount')).Text           = $upCount.ToString()
        ($sv.FindName('SummaryDownCount')).Text         = $downCount.ToString()
        ($sv.FindName('SummaryAuthorizedCount')).Text    = $authCount.ToString()
        ($sv.FindName('SummaryUnauthorizedCount')).Text  = $unauthCount.ToString()
        ($sv.FindName('SummaryUniqueVlansCount')).Text   = $uniqueCount.ToString()
        $ratio = if ($intCount -gt 0) { [math]::Round(($upCount / $intCount) * 100, 1) } else { 0 }
        ($sv.FindName('SummaryExtra')).Text = "Up %: $ratio%"
    } catch {
    }
}

function Update-Alerts {
    # Acquire location filters from the UI.  When site, zone, building or room
    # selections are specified (and not the "All" sentinel values), alerts
    # should be restricted to interfaces in the selected location.  Default
    # values of $null or blank will match all rows.
    $siteSel = $null; $zoneSel = $null; $bldSel = $null; $roomSel = $null
    try {
        $loc = Get-SelectedLocation
        $siteSel = $loc.Site
        $zoneSel = $loc.Zone
        $bldSel  = $loc.Building
        $roomSel = $loc.Room
    } catch {}
    # Build the list of alerts using a typed List[object] to avoid O(n^2)
    $alerts = New-Object 'System.Collections.Generic.List[object]'
    foreach ($row in $global:AllInterfaces) {
        if (-not $row) { continue }
        # Extract row metadata as strings for comparison
        $rowSite     = '' + $row.Site
        $rowBuilding = '' + $row.Building
        $rowRoom     = '' + $row.Room
        $rowZone     = ''
        if ($row.PSObject.Properties['Zone']) { $rowZone = '' + $row.Zone }
        # Apply location filters, honouring "All" sentinels.  Skip rows that
        # do not match the current site/zone/building/room selections.
        if ($siteSel -and $siteSel -ne '' -and $siteSel -ne 'All Sites' -and ($rowSite -ne $siteSel)) { continue }
        if ($zoneSel -and $zoneSel -ne '' -and $zoneSel -ne 'All Zones' -and ($rowZone -ne $zoneSel)) { continue }
        if ($bldSel  -and $bldSel  -ne '' -and ($rowBuilding -ne $bldSel)) { continue }
        if ($roomSel -and $roomSel -ne '' -and ($rowRoom     -ne $roomSel)) { continue }
        # Derive alert reasons from status, duplex and auth state.  Use a
        # typed list of strings for efficient accumulation.
        $reasons = New-Object 'System.Collections.Generic.List[string]'
        $status = '' + $row.Status
        if ($status) {
            # Flag ports that are down or notconnect using case-insensitive comparison
            if ([System.StringComparer]::OrdinalIgnoreCase.Equals($status, 'down') -or
                [System.StringComparer]::OrdinalIgnoreCase.Equals($status, 'notconnect')) {
                [void]$reasons.Add('Port down')
            }
        }
        $duplex = '' + $row.Duplex
        if ($duplex) {
            # Only flag duplex values containing "half" as non-full duplex
            if ($duplex -match '(?i)half') {
                [void]$reasons.Add('Half duplex')
            }
        }
        $authState = '' + $row.AuthState
        if ($authState) {
            if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals($authState, 'authorized')) { [void]$reasons.Add('Unauthorized') }
        } else {
            [void]$reasons.Add('Unauthorized')
        }
        if ($reasons.Count -gt 0) {
            # Construct the alert object including selected reason(s)
            $alert = [PSCustomObject]@{
                Hostname  = $row.Hostname
                Port      = $row.Port
                Name      = $row.Name
                Status    = $row.Status
                VLAN      = $row.VLAN
                Duplex    = $row.Duplex
                AuthState = $row.AuthState
                Reason    = ($reasons -join '; ')
            }
            [void]$alerts.Add($alert)
        }
    }
    $global:AlertsList = $alerts
    # Update the Alerts grid if it has been initialised.  Assign the new
    # filtered list as the ItemsSource.  Wrap in try/catch to avoid errors
    # when the view is not ready.
    if ($global:alertsView) {
        try {
            $grid = $global:alertsView.FindName('AlertsGrid')
            if ($grid) { $grid.ItemsSource = $global:AlertsList }
        } catch {}
    }
}

function Update-SearchGrid {
    # Access controls within the search view
    $searchHostCtrl = $global:window.FindName('SearchInterfacesHost')
    if (-not $searchHostCtrl) { return }
    $view = $searchHostCtrl.Content
    if (-not $view) { return }
    $gridCtrl  = $view.FindName('SearchInterfacesGrid')
    $boxCtrl   = $view.FindName('SearchBox')
    if (-not $gridCtrl -or -not $boxCtrl) { return }
    $term = $boxCtrl.Text
    # If the global interface list has not yet been built (e.g. on first
    try {
        if (-not $global:AllInterfaces -or $global:AllInterfaces.Count -eq 0) {
            if (Get-Command Update-GlobalInterfaceList -ErrorAction SilentlyContinue) {
                Update-GlobalInterfaceList
            }
        }
    } catch {}
    # Invoke search results and capture them before assignment so we can log
    $results = Update-SearchResults -Term $term
    try {
        $resCount = if ($results) { $results.Count } else { 0 }
    } catch {
        # ignore errors determining result count
    }
    $gridCtrl.ItemsSource = $results
}

function Get-PortSortKey {
    param([Parameter(Mandatory)][string]$Port)
    if ([string]::IsNullOrWhiteSpace($Port)) { return '99-UNK-99999-99999-99999-99999-99999' }

    $u = $Port.Trim().ToUpperInvariant()
    # Normalize common long/varied forms → short codes
    $u = $u `
      -replace 'HUNDRED\s*GIG(?:ABIT\s*ETHERNET|E)?','HU' `
      -replace 'FOUR\s*HUNDRED\s*GIG(?:ABIT\s*ETHERNET|E)?','TH' `
      -replace 'FORTY\s*GIG(?:ABIT\s*ETHERNET|E)?','FO' `
      -replace 'TWENTY\s*FIVE\s*GIG(?:ABIT\s*ETHERNET|E|IGE)?','TW' `
      -replace 'TEN\s*GIG(?:ABIT\s*ETHERNET|E)?','TE' `
      -replace 'GIGABIT\s*ETHERNET','GI' `
      -replace 'FAST\s*ETHERNET','FA' `
      -replace 'ETHERNET','ET' `
      -replace 'MANAGEMENT','MGMT' `
      -replace 'PORT-?\s*CHANNEL','PO' `
      -replace 'LOOPBACK','LO' `
      -replace 'VLAN','VL'

    $m = [regex]::Match($u, '^(?<type>[A-Z\-]+)?\s*(?<nums>[\d/.:]+)')
    $type = if ($m.Success -and $m.Groups['type'].Value) { $m.Groups['type'].Value } else {
        if ($u -match '^\d') { 'ET' } else { ($u -creplace '[^A-Z]','') }
    }

    # Type weights: lower sorts first (bundles/hi‑speed first, mgmt low)
    $weights = @{ 'MGMT'=5; 'PO'=10; 'TH'=22; 'HU'=23; 'FO'=24; 'TE'=25; 'TW'=26; 'ET'=30; 'GI'=40; 'FA'=50; 'VL'=97; 'LO'=98 }
    $w = if ($weights.ContainsKey($type)) { $weights[$type] } else { 60 }

    $numsPart = if ($m.Success) { $m.Groups['nums'].Value } else { $u }
    # Build a typed list of numeric segments.  Using a .NET List[int] avoids the
    $matchesInts = [regex]::Matches($numsPart, '\d+')
    $numsList = New-Object 'System.Collections.Generic.List[int]'
    foreach ($mnum in $matchesInts) {
        [void]$numsList.Add([int]$mnum.Value)
    }
    # Pad with zeros until we have at least four segments.
    while ($numsList.Count -lt 4) { [void]$numsList.Add(0) }
    # Convert the first six segments into zero‑padded strings.  Build this list
    $segmentsList = New-Object 'System.Collections.Generic.List[string]'
    $limit = [Math]::Min(6, $numsList.Count)
    for ($i = 0; $i -lt $limit; $i++) {
        [void]$segmentsList.Add('{0:00000}' -f $numsList[$i])
    }
    $segments = $segmentsList

    return ('{0:00}-{1}-{2}' -f $w, $type, ($segments -join '-'))
}

##

function Get-InterfaceHostnames {
    [CmdletBinding()]
    param([string]$ParsedDataPath)
    # Ignore ParsedDataPath; always use the database when available.
    if (-not $global:StateTraceDb) {
        return @()
    }
    try {
        # Ensure the database module is loaded only once.  Without this helper
        # the DatabaseModule was being imported on each call which slows down
        # repeated invocations of this function.
        Import-DatabaseModule
        $dtHosts = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql 'SELECT Hostname FROM DeviceSummary ORDER BY Hostname'
        # Build the list of hostnames using a typed list rather than piping through
        $hostList = New-Object 'System.Collections.Generic.List[string]'
        foreach ($row in $dtHosts) {
            [void]$hostList.Add([string]$row.Hostname)
        }
        # Return the array directly.  Using a leading comma would wrap the
        return $hostList.ToArray()
    } catch {
        Write-Warning "Failed to query hostnames from database: $($_.Exception.Message)"
        return @()
    }
}

function Get-ConfigurationTemplates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [string]$TemplatesPath = (Join-Path $PSScriptRoot '..\Templates')
    )
    # Determine the per-site database path for this host; return empty if it does not exist.
    $dbPath = Get-DbPathForHost $Hostname
    if (-not (Test-Path $dbPath)) { return @() }
    try {
        # Load the database module once.  Previously this module was imported on
        # every call which is inefficient; use the helper to import only when
        # necessary.
        Import-DatabaseModule
        $escHost = $Hostname -replace "'", "''"
        $dt = Invoke-DbQuery -DatabasePath $dbPath -Sql "SELECT Make FROM DeviceSummary WHERE Hostname = '$escHost'"
        $make = ''
        if ($dt) {
            if ($dt -is [System.Data.DataTable]) {
                if ($dt.Rows.Count -gt 0) { $make = $dt.Rows[0].Make }
            } else {
                $firstRow = $dt | Select-Object -First 1
                if ($firstRow -and $firstRow.PSObject.Properties['Make']) { $make = $firstRow.Make }
            }
        }
        # Determine the vendor based on the device make.  Normalize to a capitalized
        # vendor name without the .json extension (e.g. 'Cisco' or 'Brocade').
        $vendor = if ($make -match '(?i)brocade') { 'Brocade' } else { 'Cisco' }
        $jsonFile = Join-Path $TemplatesPath "${vendor}.json"
        if (-not (Test-Path $jsonFile)) { throw "Template file missing: $jsonFile" }

        # Ensure the templates cache exists.  Use a script‑scoped cache keyed by vendor.
        if (-not $script:TemplatesCache) { $script:TemplatesCache = @{} }

        # Retrieve the templates from the cache when available, otherwise load
        # from disk and update the cache.  Avoid repeated disk I/O and JSON
        # parsing on subsequent calls.
        $templates = $null
        if ($script:TemplatesCache.ContainsKey($vendor)) {
            $templates = $script:TemplatesCache[$vendor]
        } else {
            $tmplJson = Get-Content $jsonFile -Raw | ConvertFrom-Json
            if ($tmplJson -and $tmplJson.PSObject.Properties['templates']) {
                $templates = $tmplJson.templates
            } else {
                $templates = @()
            }
            $script:TemplatesCache[$vendor] = $templates
        }

        # Build or update the name→template index for this vendor.  Although
        # Get‑ConfigurationTemplates only needs the names, updating
        # $script:TemplatesByName here keeps the index fresh for consumers
        # like Get‑InterfaceConfiguration.
        try {
            if ($templates) {
                $script:TemplatesByName = $templates | Group-Object -Property name -AsHashTable -AsString
            } else {
                $script:TemplatesByName = @{}
            }
        } catch {
            $script:TemplatesByName = @{}
        }

        return $templates | Select-Object -ExpandProperty name
    } catch {
        Write-Warning ("Failed to determine configuration templates from database for {0}: {1}" -f $Hostname, $_.Exception.Message)
        return @()
    }
}

function Get-InterfaceInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [string]$TemplatesPath = (Join-Path $PSScriptRoot '..\Templates')
    )
    # Always use the consolidated helper to build interface details.  Determine the per-site database
    # and return an empty list if it does not exist.
    $dbPath = Get-DbPathForHost $Hostname
    if (-not (Test-Path $dbPath)) { return @() }
    try {
        # Ensure the database module is loaded once rather than on every call.
        Import-DatabaseModule
        $escHost = $Hostname -replace "'", "''"
        $sql = "SELECT Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, ConfigStatus, PortColor, ToolTip FROM Interfaces WHERE Hostname = '$escHost' ORDER BY Port"
        $dt = Invoke-DbQuery -DatabasePath $dbPath -Sql $sql
        # Delegate to the shared helper which returns an array of PSCustomObject.
        return New-InterfaceObjectsFromDbRow -Data $dt -Hostname $Hostname -TemplatesPath $TemplatesPath
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
        $escHost = $Hostname -replace "'", "''"
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
        $jsonFile = Join-Path $TemplatesPath "${vendor}.json"
        if (-not (Test-Path $jsonFile)) { throw "Template file missing: $jsonFile" }

        # Ensure the templates cache exists.  Use a script‑scoped cache keyed by vendor.
        if (-not $script:TemplatesCache) { $script:TemplatesCache = @{} }

        # Retrieve the templates from the cache when available; otherwise
        # read from disk and update the cache.  This avoids repeated JSON
        # parsing and file I/O.
        $templates = $null
        if ($script:TemplatesCache.ContainsKey($vendor)) {
            $templates = $script:TemplatesCache[$vendor]
        } else {
            $tmplJson = Get-Content $jsonFile -Raw | ConvertFrom-Json
            if ($tmplJson -and $tmplJson.PSObject.Properties['templates']) {
                $templates = $tmplJson.templates
            } else {
                $templates = @()
            }
            $script:TemplatesCache[$vendor] = $templates
        }

        # Build or update the name→template index for this vendor.  This
        # ensures that lookups by template name are O(1).  If an error
        # occurs, reset the index to an empty hash table.
        try {
            if ($templates) {
                $script:TemplatesByName = $templates | Group-Object -Property name -AsHashTable -AsString
            } else {
                $script:TemplatesByName = @{}
            }
        } catch {
            $script:TemplatesByName = @{}
        }

        # Look up the requested template using the prebuilt index.  If not
        # found, throw an informative error.
        $tmpl = if ($script:TemplatesByName -and $script:TemplatesByName.ContainsKey($TemplateName)) {
            $script:TemplatesByName[$TemplateName] | Select-Object -First 1
        } else {
            $null
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
                $escaped = $item -replace "'", "''"
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

function Get-InterfaceList {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Hostname)
    if (-not $global:StateTraceDb) { return @() }
    try {
        # Ensure the database module is loaded only once.  Repeatedly importing
        # DatabaseModule on each call slows down retrieval of port lists.
        Import-DatabaseModule
        $escHost = $Hostname -replace "'", "''"
        $dt = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT Port FROM Interfaces WHERE Hostname = '$escHost' ORDER BY Port"
        # Build the list of ports using a typed list instead of piping through
        $portList = New-Object 'System.Collections.Generic.List[string]'
        foreach ($row in $dt) {
            [void]$portList.Add([string]$row.Port)
        }
        # Return the port list array directly rather than prefixing a comma.  A
        return $portList.ToArray()
    } catch {
        Write-Warning ("Failed to get interface list for {0}: {1}" -f $Hostname, $_.Exception.Message)
        return @()
    }
}

# Export all helper functions.  When this module is imported with -Global,
Export-ModuleMember -Function `
    Get-DeviceSummaries, `
    Update-DeviceFilter, `
    Get-DeviceDetails, `
    Update-GlobalInterfaceList, `
    Update-SearchResults, `
    Update-Summary, `
    Update-Alerts, `
    Update-SearchGrid, `
    Get-PortSortKey, `
    Get-InterfaceHostnames, `
    Get-ConfigurationTemplates, `
    Get-InterfaceInfo, `
    Get-InterfaceConfiguration, `
    Get-InterfaceList, `
    Set-DropdownItems, `
    Get-SqlLiteral, `
    Get-InterfacesForHostsBatch, `
    Get-InterfacesForSite, `
    Clear-SiteInterfaceCache