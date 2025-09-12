# ----------------------------------------------------------------------------
if (-not (Get-Variable -Name DeviceFilterUpdating -Scope Script -ErrorAction SilentlyContinue)) {
    $script:DeviceFilterUpdating = $false
}

# Track previous selections for site and building so dependent lists can be reset.
if (-not (Get-Variable -Name LastSiteSel -Scope Script -ErrorAction SilentlyContinue)) { $script:LastSiteSel = '' }
if (-not (Get-Variable -Name LastBuildingSel -Scope Script -ErrorAction SilentlyContinue)) { $script:LastBuildingSel = '' }

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

# Initialise a simple in‑memory cache for per‑device interface lists.  When a
if (-not $global:DeviceInterfaceCache) {
    $global:DeviceInterfaceCache = @{}
}

# -----------------------------------------------------------------------------
# Helper functions to locate the appropriate Access database.  Rather than
# relying on a single global database path, each device's hostname encodes a
# site identifier in the portion before the first dash (e.g. "WLLS" in
# "WLLS-A05-AS-05").  The database for a given device is stored under
# Data/<SITE>.accdb relative to the project root.  The helpers below extract
# the site code from a hostname, build a database path for that host, and
# enumerate all site databases for global queries.

function Get-SiteFromHostname {
    param([string]$Hostname)
    if (-not $Hostname) { return 'Unknown' }
    if ($Hostname -match '^(?<site>[^-]+)-') { return $matches['site'] }
    return $Hostname
}

function Get-DbPathForHost {
    param([Parameter(Mandatory)][string]$Hostname)
    $site   = Get-SiteFromHostname $Hostname
    # Resolve the module root (Modules/.. -> project root)
    $root   = Join-Path $PSScriptRoot '..' | Resolve-Path | Select-Object -ExpandProperty Path
    $data   = Join-Path $root 'Data'
    return (Join-Path $data ("{0}.accdb" -f $site))
}

function Get-AllSiteDbPaths {
    # Enumerate all *.accdb files in the Data folder.  If the folder does not
    # exist, return an empty array.
    $root = Join-Path $PSScriptRoot '..' | Resolve-Path | Select-Object -ExpandProperty Path
    $data = Join-Path $root 'Data'
    if (-not (Test-Path $data)) { return @() }
    return Get-ChildItem -Path $data -Filter '*.accdb' -File | Select-Object -ExpandProperty FullName
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

# Retrieve the currently selected site, building and room from the main

function Get-SelectedLocation {
    [CmdletBinding()]
    param([object]$Window = $global:window)
    $siteSel = $null
    $bldSel  = $null
    $roomSel = $null
    try {
        if ($Window) {
            $siteCtrl = $Window.FindName('SiteDropdown')
            $bldCtrl  = $Window.FindName('BuildingDropdown')
            $roomCtrl = $Window.FindName('RoomDropdown')
            if ($siteCtrl) { $siteSel = $siteCtrl.SelectedItem }
            if ($bldCtrl)  { $bldSel  = $bldCtrl.SelectedItem }
            if ($roomCtrl){ $roomSel = $roomCtrl.SelectedItem }
        }
    } catch {
        # ignore lookup errors
    }
    return @{ Site = $siteSel; Building = $bldSel; Room = $roomSel }
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
    # Build an IN clause from the sanitized hostnames.  Escape each name.
    $inList = ($cleanHosts | ForEach-Object { "'" + (Get-SqlLiteral $_) + "'" }) -join ","
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
        [Parameter(Mandatory)][object]$Data,
        [Parameter(Mandatory)][string]$Hostname,
        [string]$TemplatesPath = (Join-Path $PSScriptRoot '..\Templates')
    )
    # Determine the per-site database path for this host.  We no longer rely
    # on a single global database; instead each host's data resides in
    # Data/<SITE>.accdb.  Compute this upfront for vendor and auth block
    # lookups.  If the file does not exist, queries will simply return no
    # results and the fallback logic below will infer defaults.
    $dbPath  = Get-DbPathForHost $Hostname
    # Escape the hostname once for reuse in SQL queries.  Doubling single quotes
    $escHost = $Hostname -replace "'", "''"

    # Determine vendor (Cisco vs Brocade) and global auth block using any joined
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
            # Split into non‑empty trimmed lines
            $authBlockLines = $abText -split "`r?`n" | ForEach-Object { ('' + $_).Trim() } | Where-Object { $_ -ne '' }
        }
    }
    # Load compliance templates based on vendor.  If the JSON file is missing the
    $templates = $null
    try {
        $vendorFile = if ($vendor -eq 'Cisco') { 'Cisco.json' } else { 'Brocade.json' }
        $jsonFile   = Join-Path $TemplatesPath $vendorFile
        if (Test-Path $jsonFile) {
            $tmplJson = Get-Content $jsonFile -Raw | ConvertFrom-Json
            if ($tmplJson -and $tmplJson.PSObject.Properties['templates']) {
                $templates = $tmplJson.templates
                # Build name -> template(s) index for O(1) lookups
                try {
                    if ($templates) {
                        # `-AsString` ensures string keys are used even if the property is not strictly typed as [string]
                        $script:TemplatesByName = $templates | Group-Object -Property name -AsHashTable -AsString
                    } else {
                        $script:TemplatesByName = @{}
                    }
                } catch {
                    $script:TemplatesByName = @{}
                }
            }
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
    # Always prefer loading device summaries from the database.  If the database
    $names = New-Object 'System.Collections.Generic.List[string]'
    $global:DeviceMetadata = @{}
    # Populate the global DeviceMetadata hash and list of hostnames by reading
    # all site databases.  Iterate through every *.accdb file in the Data
    # directory, querying the DeviceSummary table.  If no site databases are
    # present, the $names list remains empty and a warning is issued.
    $hasData = $false
    foreach ($dbPath in (Get-AllSiteDbPaths)) {
        try {
            $dt = Invoke-DbQuery -DatabasePath $dbPath -Sql "SELECT Hostname, Site, Building, Room FROM DeviceSummary"
            if ($dt) {
                $hasData = $true
                $rows = $dt | Select-Object Hostname, Site, Building, Room
                foreach ($row in $rows) {
                    $name = $row.Hostname
                    if (-not [string]::IsNullOrWhiteSpace($name)) {
                        [void]$names.Add($name)
                        $siteRaw     = $row.Site
                        $buildingRaw = $row.Building
                        $roomRaw     = $row.Room
                        $siteVal     = if ($siteRaw -eq $null -or $siteRaw -eq [System.DBNull]::Value) { '' } else { [string]$siteRaw }
                        $buildingVal = if ($buildingRaw -eq $null -or $buildingRaw -eq [System.DBNull]::Value) { '' } else { [string]$buildingRaw }
                        $roomVal     = if ($roomRaw -eq $null -or $roomRaw -eq [System.DBNull]::Value) { '' } else { [string]$roomRaw }
                        $meta = [PSCustomObject]@{
                            Site     = $siteVal
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
    if (-not $hasData) {
        Write-Warning "Database not configured. Device list will be empty."
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
    # Prepend a blank entry to the list of unique sites so the first item is always blank.
    Set-DropdownItems -Control $siteDD -Items (@('') + $uniqueSites)

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
    if ($script:DeviceFilterUpdating) { return }
    $script:DeviceFilterUpdating = $true
    try {
        # Detect changes in site and building selections from the last invocation.  When the
        $loc0 = Get-SelectedLocation
        $currentSiteSel = $loc0.Site
        $currentBldSel  = $loc0.Building
        $siteChanged = ([System.StringComparer]::OrdinalIgnoreCase.Compare(('' + $currentSiteSel), ('' + $script:LastSiteSel)) -ne 0)
        $bldChanged  = ([System.StringComparer]::OrdinalIgnoreCase.Compare(('' + $currentBldSel),  ('' + $script:LastBuildingSel)) -ne 0)

        # Reset dependent dropdowns when parent selections change.
        $buildingDD = $window.FindName('BuildingDropdown')
        $roomDD     = $window.FindName('RoomDropdown')
        if ($siteChanged -and $buildingDD) {
            # Site changed: clear building and room lists and disable room until a building is selected.
            DeviceDataModule\Set-DropdownItems -Control $buildingDD -Items @('')
            $buildingDD.IsEnabled = if ($currentSiteSel -and $currentSiteSel -ne '') { $true } else { $false }
            if ($roomDD) {
                DeviceDataModule\Set-DropdownItems -Control $roomDD -Items @('')
                $roomDD.IsEnabled = $false
            }
        } elseif ($bldChanged -and $roomDD) {
            # Building changed: clear the room list and update its enabled state.
            DeviceDataModule\Set-DropdownItems -Control $roomDD -Items @('')
            $roomDD.IsEnabled = if ($currentBldSel -and $currentBldSel -ne '') { $true } else { $false }
        }

        if (-not $global:DeviceMetadata) { return }

    # Determine the currently selected site (we intentionally ignore building
    $loc    = Get-SelectedLocation
    $siteSel = $loc.Site

    # ---------------------------------------------------------------------
    $buildingSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($meta in $DeviceMetadata.Values) {
        if ($siteSel -and $siteSel -ne '' -and $meta.Site -ne $siteSel) { continue }
        $b = $meta.Building
        if (-not [string]::IsNullOrWhiteSpace($b)) { [void]$buildingSet.Add($b) }
    }
    $availableBuildings = [System.Collections.Generic.List[string]]::new($buildingSet)
    $availableBuildings.Sort([System.StringComparer]::OrdinalIgnoreCase)
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
    # Enable or disable the building dropdown based solely on site selection.
    if ($siteSel -and $siteSel -ne '') {
        $buildingDD.IsEnabled = $true
    } else {
        $buildingDD.IsEnabled = $false
    }

    # Capture the now-finalised building and room selections after the dropdown
    $bldSel  = $buildingDD.SelectedItem
    $roomDD  = $window.FindName('RoomDropdown')
    $roomSel = if ($roomDD) { $roomDD.SelectedItem } else { $null }

    # ---------------------------------------------------------------------
    $filteredNames = New-Object 'System.Collections.Generic.List[string]'
    foreach ($name in $DeviceMetadata.Keys) {
        $meta = $DeviceMetadata[$name]
        if ($siteSel -and $siteSel -ne '' -and $meta.Site     -ne $siteSel) { continue }
        if ($bldSel  -and $bldSel  -ne '' -and $meta.Building -ne $bldSel)  { continue }
        if ($roomSel -and $roomSel -ne '' -and $meta.Room     -ne $roomSel) { continue }
        [void]$filteredNames.Add($name)
    }
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
    # Populate the hostname dropdown with the filtered list.  Selecting the
    Set-DropdownItems -Control $hostnameDD -Items $filteredNames

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
            $script:LastSiteSel = $locFinal.Site
            $script:LastBuildingSel = $locFinal.Building
        } catch {}
    } finally { $script:DeviceFilterUpdating = $false }
}

function Get-DeviceDetails {
    param($hostname)
    try {
        # Compute the per-site database path for this host.  If the file does not
        # exist, $useDb remains false and fallback values will be used exclusively.
        $useDb = $false
        $hostTrim = ($hostname -as [string]).Trim()
        $dbPath  = Get-DbPathForHost $hostTrim
        if (Test-Path $dbPath) { $useDb = $true }

        if ($useDb) {
            # Prepare for database operations.  (No explicit session reuse at this level.)
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

            # Query interface details for the specified host from the per-site database.  Include
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
        # Determine the per-site database path for this host.  Use database
        # only if the per-site file exists; otherwise fall back to CSV import.
        $useDb = $false
        $dbPath = Get-DbPathForHost $hostTrim
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

function Update-GlobalInterfaceList {
    # Build a comprehensive list of all interfaces by querying the database and

    # Use a strongly-typed list for efficient accumulation of objects
    $list = New-Object 'System.Collections.Generic.List[object]'

    # Build a comprehensive list of all interfaces by querying every site database.
    $dbPaths = Get-AllSiteDbPaths
    if (-not $dbPaths -or $dbPaths.Count -eq 0) {
        Write-Warning "Database not configured. Interface list will be empty."
        $global:AllInterfaces = @()
        return
    }
    try {
        $listRows = New-Object 'System.Collections.Generic.List[System.Data.DataRow]'
        foreach ($path in $dbPaths) {
            $sql = @"
SELECT i.Hostname, i.Port, i.Name, i.Status, i.VLAN, i.Duplex, i.Speed, i.Type,
       i.LearnedMACs, i.AuthState, i.AuthMode, i.AuthClientMAC,
       ds.Site, ds.Building, ds.Room
FROM Interfaces AS i
LEFT JOIN DeviceSummary AS ds ON i.Hostname = ds.Hostname
"@
            try {
                $dtLocal = Invoke-DbQuery -DatabasePath $path -Sql $sql
                if ($dtLocal) {
                    # Add each DataRow/DataRowView to the list for later enumeration
                    if ($dtLocal -is [System.Data.DataTable]) {
                        foreach ($r in $dtLocal.Rows) { [void]$listRows.Add($r) }
                    } elseif ($dtLocal -is [System.Data.DataView]) {
                        foreach ($rv in $dtLocal) { [void]$listRows.Add($rv.Row) }
                    } elseif ($dtLocal -is [System.Collections.IEnumerable]) {
                        foreach ($row in $dtLocal) { [void]$listRows.Add($row) }
                    }
                }
            } catch {
                Write-Warning ("Failed to query interfaces from {0}: {1}" -f $path, $_.Exception.Message)
            }
        }
        # Create a DataTable-like enumerable from the collected rows
        $dt = $listRows
        # The returned query result may be a DataTable, DataView or other enumerable

        # Prepare an enumerable of rows depending on the type of $dt.  When
        # aggregating across databases $dt may be a generic List[DataRow].  In
        # that case it will satisfy IEnumerable and we can iterate directly.
        $rows = @()
        if ($dt -is [System.Data.DataTable]) {
            $rows = $dt.Rows
        } elseif ($dt -is [System.Data.DataView]) {
            $rows = $dt  # DataView is enumerable of DataRowView
        } elseif ($dt -is [System.Collections.IEnumerable]) {
            $rows = $dt  # Generic list or array of DataRow/DataRowView
        } else {
            Write-Warning "DBG: Unexpected query result type; skipping row enumeration."
        }

        $rowCount = 0
        try { $rowCount = $rows.Count } catch { }

        $addedCount  = 0
        $skippedNull = 0
        $skippedType = 0
        $rowIndex    = 0

        foreach ($r in $rows) {
            $rowIndex++
            # Skip any null entries
            if ($r -eq $null) {
                $skippedNull++
                # skip null entries silently
                continue
            }
            # Support both DataRow and DataRowView.  Convert DataRowView to DataRow.
            $dataRow = $null
            if ($r -is [System.Data.DataRow]) {
                $dataRow = $r
            } elseif ($r -is [System.Data.DataRowView]) {
                $dataRow = $r.Row
            } else {
                # Unexpected row type; skip it silently
                $skippedType++
                continue
            }
            # Safely extract each column.  Use $dataRow['ColumnName'] indexer.
            $hnRaw       = $dataRow['Hostname']
            $portRaw     = $dataRow['Port']
            $nameRaw     = $dataRow['Name']
            $statusRaw   = $dataRow['Status']
            $vlanRaw     = $dataRow['VLAN']
            $duplexRaw   = $dataRow['Duplex']
            $speedRaw    = $dataRow['Speed']
            $typeRaw     = $dataRow['Type']
            $lmRaw       = $dataRow['LearnedMACs']
            $aStateRaw   = $dataRow['AuthState']
            $aModeRaw    = $dataRow['AuthMode']
            $aMACRaw     = $dataRow['AuthClientMAC']
            $siteRaw     = $dataRow['Site']
            $bldRaw      = $dataRow['Building']
            $roomRaw     = $dataRow['Room']

            $hn      = if ($hnRaw    -ne $null -and $hnRaw    -ne [System.DBNull]::Value) { [string]$hnRaw    } else { '' }
            $port    = if ($portRaw  -ne $null -and $portRaw  -ne [System.DBNull]::Value) { [string]$portRaw  } else { '' }
            $name    = if ($nameRaw  -ne $null -and $nameRaw  -ne [System.DBNull]::Value) { [string]$nameRaw  } else { '' }
            $status  = if ($statusRaw -ne $null -and $statusRaw -ne [System.DBNull]::Value) { [string]$statusRaw } else { '' }
            $vlan    = if ($vlanRaw  -ne $null -and $vlanRaw  -ne [System.DBNull]::Value) { [string]$vlanRaw  } else { '' }
            $duplex  = if ($duplexRaw -ne $null -and $duplexRaw -ne [System.DBNull]::Value) { [string]$duplexRaw} else { '' }
            $speed   = if ($speedRaw -ne $null -and $speedRaw -ne [System.DBNull]::Value) { [string]$speedRaw } else { '' }
            $type    = if ($typeRaw  -ne $null -and $typeRaw  -ne [System.DBNull]::Value) { [string]$typeRaw  } else { '' }
            $lm      = if ($lmRaw    -ne $null -and $lmRaw    -ne [System.DBNull]::Value) { [string]$lmRaw    } else { '' }
            $aState  = if ($aStateRaw -ne $null -and $aStateRaw -ne [System.DBNull]::Value) { [string]$aStateRaw} else { '' }
            $aMode   = if ($aModeRaw -ne $null -and $aModeRaw -ne [System.DBNull]::Value) { [string]$aModeRaw } else { '' }
            $aMAC    = if ($aMACRaw  -ne $null -and $aMACRaw  -ne [System.DBNull]::Value) { [string]$aMACRaw  } else { '' }
            $site    = if ($siteRaw  -ne $null -and $siteRaw  -ne [System.DBNull]::Value) { [string]$siteRaw  } else { '' }
            $bld     = if ($bldRaw   -ne $null -and $bldRaw   -ne [System.DBNull]::Value) { [string]$bldRaw   } else { '' }
            $room    = if ($roomRaw  -ne $null -and $roomRaw  -ne [System.DBNull]::Value) { [string]$roomRaw  } else { '' }

            # Compute PortSort key using fallback when Port is empty/whitespace
            $portSort = if (-not [string]::IsNullOrWhiteSpace($port)) {
                Get-PortSortKey -Port $port
            } else {
                '99-UNK-99999-99999-99999-99999-99999'
            }


            # Construct object and add to list
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
                Site          = $site
                Building      = $bld
                Room          = $room
            }
            [void]$list.Add($obj)
            $addedCount++
        }

    } catch {
        Write-Warning "Failed to rebuild interface list from database: $($_.Exception.Message)"
    }

    # Publish the interface list globally (sorted by Hostname and PortSort).  Use a
    $comparison = [System.Comparison[object]]{
        param($a, $b)
        # Compare hostnames using a case-insensitive ordinal comparison first
        $hnc = [System.StringComparer]::OrdinalIgnoreCase.Compare($a.Hostname, $b.Hostname)
        if ($hnc -ne 0) { return $hnc }
        # When hostnames match, compare the PortSort values using an ordinal comparison
        return [System.StringComparer]::Ordinal.Compare($a.PortSort, $b.PortSort)
    }
    # Perform the sort in-place on the list
    $list.Sort($comparison)
    # Assign the now-sorted list to the global AllInterfaces variable
    $global:AllInterfaces = $list

    # If available, update summary and alerts to reflect new interface data
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
        # Apply location filtering
        if ($siteSel -and $siteSel -ne '' -and ($rowSite -ne $siteSel)) { continue }
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
    $siteSel = $null; $bldSel = $null; $roomSel = $null
    try {
        # Retrieve location selections via helper
        $loc = Get-SelectedLocation
        $siteSel = $loc.Site
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
            if ($siteSel -and $siteSel -ne '' -and $meta.Site -ne $siteSel) { continue }
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
        $rBld  = '' + $row.Building
        $rRoom = '' + $row.Room
        if ($siteSel -and $siteSel -ne '' -and $rSite -ne $siteSel) { continue }
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
    # Build the list of alerts using a typed List[object] to avoid O(n^2)
    $alerts = New-Object 'System.Collections.Generic.List[object]'
    foreach ($row in $global:AllInterfaces) {
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
            # Only flag duplex values containing "half" as non-full duplex; perform
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
    # Update the Alerts grid if it has been initialised
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
    # Return all hostnames from every site database.  Ignore ParsedDataPath.
    try {
        $dbModule = Join-Path $PSScriptRoot 'DatabaseModule.psm1'
        if (Test-Path $dbModule) {
            Import-Module $dbModule -Force -Global -ErrorAction SilentlyContinue | Out-Null
        }
        $hostSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($dbPath in (Get-AllSiteDbPaths)) {
            try {
                $dtHosts = Invoke-DbQuery -DatabasePath $dbPath -Sql 'SELECT Hostname FROM DeviceSummary'
                if ($dtHosts) {
                    foreach ($row in $dtHosts) {
                        $hn = '' + $row.Hostname
                        if ($hn) { [void]$hostSet.Add($hn) }
                    }
                }
            } catch {
                Write-Warning ("Failed to query hostnames from {0}: {1}" -f $dbPath, $_.Exception.Message)
            }
        }
        $hosts = [System.Collections.Generic.List[string]]::new($hostSet)
        $hosts.Sort([System.StringComparer]::OrdinalIgnoreCase)
        return $hosts.ToArray()
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
    # Retrieve configuration template names for the specified host by reading
    # the appropriate site database.  Without a database file for the host,
    # return an empty array.
    try {
        $dbModulePath = Join-Path $PSScriptRoot 'DatabaseModule.psm1'
        if (Test-Path $dbModulePath) {
            Import-Module $dbModulePath -Force -Global -ErrorAction SilentlyContinue | Out-Null
        }
        $dbPath = Get-DbPathForHost $Hostname
        if (-not (Test-Path $dbPath)) { return @() }
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
    # Always use the consolidated helper to build interface details for a host.
    try {
        $dbModule = Join-Path $PSScriptRoot 'DatabaseModule.psm1'
        if (Test-Path $dbModule) {
            Import-Module $dbModule -Force -Global -ErrorAction SilentlyContinue | Out-Null
        }
        $dbPath = Get-DbPathForHost $Hostname
        if (-not (Test-Path $dbPath)) { return @() }
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
    # Determine the per-site database path for this host.  Without a
    # database file, return an empty array.
    $dbPath = Get-DbPathForHost $Hostname
    if (-not (Test-Path $dbPath)) { return @() }
    $debug = ($Global:StateTraceDebug -eq $true)
        try {
            $dbModule = Join-Path $PSScriptRoot 'DatabaseModule.psm1'
            if (Test-Path $dbModule) {
                Import-Module $dbModule -Force -Global -ErrorAction SilentlyContinue | Out-Null
            }
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
        $ports = @($Interfaces | Where-Object { $_ -ne $null } | ForEach-Object { $_.ToString() })
            if ($ports.Count -gt 0) {
                # Escape single quotes and build IN list
                $escapedPorts = $ports | ForEach-Object { ($_ -replace "'", "''") }
                $inList = ($escapedPorts | ForEach-Object { "'$_'" }) -join ", "
                $sqlCfgAll = "SELECT Hostname, Port, Config FROM Interfaces WHERE Hostname = '$escHost' AND Port IN ($inList)"
                $session = $null
                try {
                    $session = Open-DbReadSession -DatabasePath $dbPath
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
    try {
        $dbModule = Join-Path $PSScriptRoot 'DatabaseModule.psm1'
        if (Test-Path $dbModule) {
            Import-Module $dbModule -Force -Global -ErrorAction SilentlyContinue | Out-Null
        }
        $dbPath = Get-DbPathForHost $Hostname
        if (-not (Test-Path $dbPath)) { return @() }
        $escHost = $Hostname -replace "'", "''"
        $dt = Invoke-DbQuery -DatabasePath $dbPath -Sql "SELECT Port FROM Interfaces WHERE Hostname = '$escHost' ORDER BY Port"
        # Build the list of ports using a typed list instead of piping through
        $portList = New-Object 'System.Collections.Generic.List[string]'
        foreach ($row in $dt) {
            [void]$portList.Add([string]$row.Port)
        }
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
    Set-DropdownItems,
    Get-SqlLiteral,
    Get-InterfacesForHostsBatch