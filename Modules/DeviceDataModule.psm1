# ----------------------------------------------------------------------------
# Reentrancy/refresh guard for filter updates. When repopulating dropdowns,
# SelectionChanged can fire repeatedly; this guard prevents re-entry and
# visible flicker/refresh while the list is open.
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

<#
    DeviceDataModule.psm1

    This module consolidates all device-centric and GUI helper functions
    previously spread across DeviceFunctionsModule.psm1 and GuiModule.psm1.
    The intent of this unified module is to provide a single source of
    truth for retrieving device metadata, applying location filters,
    loading interface details, building the global interface list and
    computing summary/alert metrics.  By merging the two modules we
    eliminate duplicated implementations and simplify the startup
    sequence (only one module needs to be loaded).

    Functions exported by this module:

      * Get-DeviceSummaries     – build the list of available devices
      * Update-DeviceFilter      – filter devices by site/building/room
      * Get-DeviceDetails       – load interface details for a device
      * Update-GlobalInterfaceList – build the global interface list
      * Update-SearchResults     – perform searching and filtering
      * Update-Summary           – update summary metrics
      * Update-Alerts           – build the alerts list
      * Update-SearchGrid       – refresh the search grid contents
      * Get-PortSortKey         – compute a sortable key for port strings

    IMPORTANT: This module relies on several global variables defined by
    MainWindow.ps1 (for example $window, $scriptDir, $global:StateTraceDb,
    $global:DeviceMetadata, $global:interfacesView, etc.).  The main
    script must define these globals before importing this module.
#>

# Initialise a simple in‑memory cache for per‑device interface lists.  When a
# device has been viewed once in the Interfaces tab, its port list will be
# stored in this dictionary keyed by hostname.  Subsequent visits to the same
# device can reuse the cached list rather than issuing another query and
# rebuilding PSCustomObjects.  The cache persists for the lifetime of the
# session and is cleared only when the module is reloaded.  See
# Get-DeviceDetails for usage.  Note that this cache does not implement
# invalidation when underlying data changes; it is intended for read‑only
# scenarios typical of log analysis.
if (-not $global:DeviceInterfaceCache) {
    $global:DeviceInterfaceCache = @{}
}

<#
    Retrieve the currently selected site, building and room from the main
    window.  This helper centralises the lookup of dropdown selections so
    callers do not need to repeatedly reference FindName on the window.  When
    invoked without parameters it defaults to using the global `$window`
    variable.  The return value is a hashtable containing the keys
    `Site`, `Building` and `Room`.  Any missing dropdowns or errors
    encountered during lookup will result in `$null` values for the
    corresponding fields.
#>
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

<#
    Filter a collection of interface-like objects by location.  Given a list
    of items and optional site, building and room selectors, this helper
    returns only those objects whose `Site`, `Building` and `Room` properties
    match the provided values.  Blank or `$null` selectors are treated as
    wildcards (i.e. all values are accepted).  The function tolerates
    arbitrary object types by attempting to read properties via the
    PSObject accessor.  It returns a new array and does not mutate the
    original list.
#>
function Filter-ByLocation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$List,
        [string]$Site,
        [string]$Building,
        [string]$Room
    )
    $outList = @()
    foreach ($item in $List) {
        $rowSite     = ''
        $rowBuilding = ''
        $rowRoom     = ''
        try {
            if ($item -and $item.PSObject) {
                if ($item.PSObject.Properties['Site'])     { $rowSite     = '' + $item.Site }
                if ($item.PSObject.Properties['Building']) { $rowBuilding = '' + $item.Building }
                if ($item.PSObject.Properties['Room'])     { $rowRoom     = '' + $item.Room }
            }
        } catch {}
        if ($Site     -and $Site     -ne '' -and $rowSite     -ne $Site)     { continue }
        if ($Building -and $Building -ne '' -and $rowBuilding -ne $Building) { continue }
        if ($Room     -and $Room     -ne '' -and $rowRoom     -ne $Room)     { continue }
        $outList += $item
    }
    return $outList
}

<#
    Initialise a dropdown or other ItemsControl with a list of items and
    select an appropriate default.  This helper centralises the common
    pattern of assigning the ItemsSource on a WPF control and setting
    SelectedIndex to either the first item (index 0) when items are
    available or to -1 when the list is empty.  Without this helper
    developers repeatedly wrote nearly identical code across multiple
    functions and views, which obscured the intent and made future
    changes more error‑prone.  By encapsulating the logic here we
    eliminate duplication and ensure consistent behaviour across the
    application.

    .PARAMETER Control
        A WPF ItemsControl such as a ComboBox, ListBox or DataGrid on
        which the ItemsSource and SelectedIndex properties will be set.

    .PARAMETER Items
        The list or array of items to assign to the control's ItemsSource.
        The helper will treat `$null` or an empty array as no items and
        select index -1 accordingly.
#>
function Set-DropdownItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Windows.Controls.ItemsControl]$Control,
        [Parameter(Mandatory)][object[]]$Items
    )
    # Assign the ItemsSource and select the first item (index 0) when
    # available, otherwise clear the selection (index -1).  Wrap the
    # SelectedIndex assignment in try/catch to swallow WPF exceptions
    # that can occur if the control has not yet been fully initialised.
    $Control.ItemsSource = $Items
    if ($Items -and $Items.Count -gt 0) {
        try { $Control.SelectedIndex = 0 } catch { $null = $null }
    } else {
        try { $Control.SelectedIndex = -1 } catch { $null = $null }
    }
}

<#
    Construct interface PSCustomObject instances from database results.  This helper
    centralises the vendor detection, authentication block augmentation and
    JSON template handling previously duplicated across Get‑DeviceDetails and
    Get‑InterfaceInfo.  Given a set of rows returned from the Interfaces table,
    it determines the device vendor based on the DeviceSummary.Make field,
    loads the appropriate compliance templates from the Templates folder, builds
    per‑row tooltips including any global Brocade authentication block, and
    computes the PortColor and ConfigStatus fields by combining existing
    database values with template defaults.  The resulting array of
    [PSCustomObject] is returned to the caller.  This function is internal to
    this module and is not exported.
#>
function Build-InterfaceObjectsFromDbRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Data,
        [Parameter(Mandatory)][string]$Hostname,
        [string]$TemplatesPath = (Join-Path $PSScriptRoot '..\Templates')
    )
    # If the database is unavailable return an empty array immediately.
    if (-not $global:StateTraceDb) { return @() }
    # Escape the hostname once for reuse in SQL queries.  Doubling single quotes
    # prevents SQL injection and ensures proper matching in Access queries.
    $escHost = $Hostname -replace "'", "''"
    # Attempt to determine the vendor from the DeviceSummary table.  Default to Cisco
    # when no make is found or an error occurs.
    $vendor = 'Cisco'
    try {
        $mkDt = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT Make FROM DeviceSummary WHERE Hostname = '$escHost'"
        if ($mkDt) {
            if ($mkDt -is [System.Data.DataTable]) {
                if ($mkDt.Rows.Count -gt 0) {
                    $mk = $mkDt.Rows[0].Make
                    if ($mk -and ($mk -match '(?i)brocade')) { $vendor = 'Brocade' }
                }
            } else {
                $mkRow = $mkDt | Select-Object -First 1
                if ($mkRow -and $mkRow.PSObject.Properties['Make']) {
                    $mk = $mkRow.Make
                    if ($mk -and ($mk -match '(?i)brocade')) { $vendor = 'Brocade' }
                }
            }
        }
    } catch {}
    # For Brocade devices, retrieve the device-level AuthBlock from DeviceSummary.
    $authBlockLines = @()
    if ($vendor -eq 'Brocade') {
        try {
            $abDt = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT AuthBlock FROM DeviceSummary WHERE Hostname = '$escHost'"
            if ($abDt) {
                $abText = $null
                if ($abDt -is [System.Data.DataTable]) {
                    if ($abDt.Rows.Count -gt 0) { $abText = '' + $abDt.Rows[0].AuthBlock }
                } else {
                    $abRow = $abDt | Select-Object -First 1
                    if ($abRow -and $abRow.PSObject.Properties['AuthBlock']) { $abText = '' + $abRow.AuthBlock }
                }
                if ($abText -and $abText.Trim() -ne '') {
                    $authBlockLines = $abText -split "`r?`n"
                }
            }
        } catch {}
    }
    # Load compliance templates based on vendor.  If the JSON file is missing the
    # Templates array will be $null and matches will fail, resulting in defaults.
    $templates = $null
    try {
        $vendorFile = if ($vendor -eq 'Cisco') { 'Cisco.json' } else { 'Brocade.json' }
        $jsonFile   = Join-Path $TemplatesPath $vendorFile
        if (Test-Path $jsonFile) {
            $tmplJson = Get-Content $jsonFile -Raw | ConvertFrom-Json
            if ($tmplJson -and $tmplJson.PSObject.Properties['templates']) {
                $templates = $tmplJson.templates
            }
        }
    } catch {}
    # Normalise $Data into an enumerable collection of rows.  Support DataTable,
    # DataView and any IEnumerable.  If an unsupported type is passed, return an empty list.
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
    $resultList = @()
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
            if ($templates -and $authTemplate) {
                $match = $templates | Where-Object {
                    $_.name -ieq $authTemplate -or
                    ($_.aliases -and ($_.aliases -contains $authTemplate))
                } | Select-Object -First 1
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
        $resultList += [PSCustomObject]@{
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
        }
    }
    return $resultList
}

function Get-DeviceSummaries {
    # Always prefer loading device summaries from the database.  If the database
    # is unavailable or the query fails, the list will remain empty and the
    # UI will reflect this.  Legacy CSV fallbacks have been removed to
    # enforce the database as the single source of truth.
    $names = @()
    $global:DeviceMetadata = @{}
    if ($global:StateTraceDb) {
        try {
            $dt = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT Hostname, Site, Building, Room FROM DeviceSummary ORDER BY Hostname"
            $rows = $dt | Select-Object Hostname, Site, Building, Room
            foreach ($row in $rows) {
                $name = $row.Hostname
                if (-not [string]::IsNullOrWhiteSpace($name)) {
                    $names += $name
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
            # Removed debug output about number of devices loaded
        } catch {
            Write-Warning "Failed to query device summaries from database: $($_.Exception.Message)"
        }
    } else {
        Write-Warning "Database not configured. Device list will be empty."
    }

    # Update the host dropdown and location filters based on the loaded device metadata.
    $hostnameDD = $window.FindName('HostnameDropdown')
    # Initialise the hostname dropdown with the loaded list of names.  This helper
    # sets ItemsSource and safely selects the first item when available.
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
    # database, this list will remain empty.
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
        # parent (site) changes, the dependent building and room dropdowns should reset.
        # When the building changes, the room dropdown should reset.  This prevents stale
        # selections from being applied to new lists and eliminates the need for the user
        # to manually clear a room when changing location.
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
    # and room at this stage so that we can update those lists first).  We
    # defer host filtering until after the building dropdown has been
    # repopulated to ensure we use the final building selection rather than
    # whatever value happened to be selected prior to updating the list.
    $loc    = Get-SelectedLocation
    $siteSel = $loc.Site

    # ---------------------------------------------------------------------
    # Step 1: Build and refresh the list of available buildings for the
    # currently selected site.  Capture the user's current building
    # selection so it can be restored after repopulating the dropdown.
    $availableBuildings = @()
    foreach ($name in $DeviceMetadata.Keys) {
        $meta = $DeviceMetadata[$name]
        if ($siteSel -and $siteSel -ne '' -and $meta.Site -ne $siteSel) { continue }
        if ($meta.Building -ne '') { $availableBuildings += $meta.Building }
    }
    # Remove duplicates from the building list using a HashSet before sorting.
    $buildingSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($b in $availableBuildings) {
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
    # leading blank).  Otherwise leave the selection on the blank entry.
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
    # has been repopulated.  We retrieve them directly from the controls rather
    # than relying on earlier variables so they reflect the restored value.
    $bldSel  = $buildingDD.SelectedItem
    $roomDD  = $window.FindName('RoomDropdown')
    $roomSel = if ($roomDD) { $roomDD.SelectedItem } else { $null }

    # ---------------------------------------------------------------------
    # Step 2: Filter hostnames based on the selected site, building and room.
    $filteredNames = @()
    foreach ($name in $DeviceMetadata.Keys) {
        $meta = $DeviceMetadata[$name]
        if ($siteSel -and $siteSel -ne '' -and $meta.Site     -ne $siteSel) { continue }
        if ($bldSel  -and $bldSel  -ne '' -and $meta.Building -ne $bldSel)  { continue }
        if ($roomSel -and $roomSel -ne '' -and $meta.Room     -ne $roomSel) { continue }
        $filteredNames += $name
    }
    $hostnameDD = $window.FindName('HostnameDropdown')
    # Populate the hostname dropdown with the filtered list.  Selecting the
    # first item ensures a host is always chosen when the list is non-empty.
    Set-DropdownItems -Control $hostnameDD -Items $filteredNames

    # ---------------------------------------------------------------------
    # Step 3: Refresh the list of available rooms based on the final site and
    # building selections.  A leading blank entry is included when one or
    # more rooms exist.  Enable the room dropdown only when a non‑blank
    # building has been chosen (SelectedIndex > 0 refers to the first real
    # value after the blank).  The user's room selection is cleared when
    # either the site or building has changed to prevent a stale room from
    # remaining selected.  When neither parent changed, preserve the room
    # selection if the list of available rooms is identical.
    $availableRooms = @()
    foreach ($name in $DeviceMetadata.Keys) {
        $meta = $DeviceMetadata[$name]
        if ($siteSel -and $siteSel -ne '' -and $meta.Site -ne $siteSel) { continue }
        if ($bldSel  -and $bldSel  -ne '' -and $meta.Building -ne $bldSel) { continue }
        if ($meta.Room -ne '') { $availableRooms += $meta.Room }
    }
    # Remove duplicates from the rooms list using a HashSet before sorting.
    $roomSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($r in $availableRooms) {
        if (-not [string]::IsNullOrWhiteSpace($r)) { [void]$roomSet.Add($r) }
    }
    $availableRooms = [System.Collections.Generic.List[string]]::new($roomSet)
    $availableRooms.Sort([System.StringComparer]::OrdinalIgnoreCase)
    if ($roomDD) {
        $currentRooms = @()
        try { $currentRooms = @($roomDD.ItemsSource) } catch {}
        # Remove any leading blank from the current ItemsSource so only the
        # actual room values are compared.  We intentionally avoid mutating
        # ItemsSource here; $currentRooms is a copy used solely for comparison.
        if ($currentRooms.Count -gt 0 -and ('' + $currentRooms[0]) -eq '') {
            if ($currentRooms.Count -gt 1) {
                $currentRooms = $currentRooms[1..($currentRooms.Count - 1)]
            } else {
                $currentRooms = @()
            }
        }
        # Determine whether we need to force a reset of the room list.  When
        # either the site or building has changed since the last update,
        # previously selected rooms are invalid and should be cleared even if
        # the underlying list of rooms is identical (for example when two
        # buildings happen to offer the same set of rooms).
        $forceRoomReset = $siteChanged -or $bldChanged
        if ($forceRoomReset -or -not (Test-StringListEqualCI $currentRooms $availableRooms)) {
            Set-DropdownItems -Control $roomDD -Items (@('') + $availableRooms)
        }
        # Enable the room dropdown only when a non‑blank site and building are
        # selected.  We evaluate the building dropdown's SelectedIndex rather
        # than the possibly stale $bldSel variable to reflect the final state
        # after any previous Set-DropdownItems call.
        if (($siteSel -and $siteSel -ne '') -and ($buildingDD.SelectedIndex -gt 0)) {
            $roomDD.IsEnabled = $true
        } else {
            $roomDD.IsEnabled = $false
        }
    }

    # ---------------------------------------------------------------------
    # Step 4: Notify dependent views to refresh using the updated filters.
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
        # these values allows us to detect changes on the next call and reset dependent
        # dropdowns appropriately.
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
        # Loading details for host; removed debug output
        $useDb = $false
        if ($global:StateTraceDb) { $useDb = $true }
        # Removed debug output about database usage

        if ($useDb) {
            $hostTrim = ($hostname -as [string]).Trim()
            $escHost   = $hostTrim -replace "'", "''"
            $charCodes = ($hostTrim.ToCharArray() | ForEach-Object { [int]$_ }) -join ','
            # Removed debug output for hostTrim
            $summarySql = "SELECT Hostname, Make, Model, Uptime, Ports, AuthDefaultVLAN, Building, Room " +
                          "FROM DeviceSummary " +
                          "WHERE Hostname = '$escHost' " +
                          "   OR Hostname LIKE '*$escHost*'"
            $dtSummary = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql $summarySql
            # Removed debug output for summarySql
            if ($dtSummary) {
                # Iterate through summary rows (debug output removed)
                foreach ($rowTmp in ($dtSummary | Select-Object Hostname, Make, Model, Uptime, Ports, AuthDefaultVLAN, Building, Room)) {
                    # no-op; loop exists solely to assign variables if needed
                    $null = $rowTmp
                }
            }
            $summaryObjects = @()
            if ($dtSummary) {
                $summaryObjects = @($dtSummary | Select-Object Hostname, Make, Model, Uptime, Ports, AuthDefaultVLAN, Building, Room)
            }
            $dtSummaryAll = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT Hostname, Make, Model, Uptime, Ports, AuthDefaultVLAN, Building, Room FROM DeviceSummary"
            # Removed debug output for summary row count
            $esc = $hostTrim -replace "'", "''"
            $fbMake = ''
            $fbModel = ''
            $fbUptime = ''
            $fbAuthDef = ''
            $fbBuilding = ''
            $fbRoom = ''
            $fbPorts = ''
            try {
                $hist = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT TOP 1 Make, Model, Uptime, AuthDefaultVLAN, Building, Room FROM DeviceHistory WHERE Trim(Hostname) = '$esc' ORDER BY RunDate DESC"
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
                $cntDt = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT COUNT(*) AS PortCount FROM Interfaces WHERE Trim(Hostname) = '$esc'"
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
                # Removed debug output for summary and fallback values
            } else {
                $interfacesView.FindName('HostnameBox').Text        = $hostname
                $interfacesView.FindName('MakeBox').Text            = $fbMake
                $interfacesView.FindName('ModelBox').Text           = $fbModel
                $interfacesView.FindName('UptimeBox').Text          = $fbUptime
                $interfacesView.FindName('PortCountBox').Text       = $fbPorts
                $interfacesView.FindName('AuthDefaultVLANBox').Text = $fbAuthDef
                $interfacesView.FindName('BuildingBox').Text        = $fbBuilding
                $interfacesView.FindName('RoomBox').Text            = $fbRoom
                # Removed debug output when no summary row found
                if ($dtSummaryAll) {
                    # iterate rows silently
                    foreach ($rowAll in ($dtSummaryAll | Select-Object Hostname, Make, Model, Uptime, Ports, AuthDefaultVLAN, Building, Room)) {
                        $null = $rowAll
                    }
                }
            }
            # If a cached interface list exists for this device, reuse it to avoid re-querying
            # the database.  The summary fields above have already been updated.  We still
            # need to refresh the configuration templates for the current device.  If a
            # cached list is found, bind it to the Interfaces grid and return early.
            try {
                if ($global:DeviceInterfaceCache.ContainsKey($hostname)) {
                    $cachedList = $global:DeviceInterfaceCache[$hostname]
                    $gridCached = $interfacesView.FindName('InterfacesGrid')
                    $gridCached.ItemsSource = $cachedList
                    $comboCached = $interfacesView.FindName('ConfigOptionsDropdown')
                    # Retrieve configuration templates and populate the combo using
                    # the dropdown helper.  The helper sets ItemsSource and selects
                    # the first template when available.
                    $tmplList = Get-ConfigurationTemplates -Hostname $hostname
                    Set-DropdownItems -Control $comboCached -Items $tmplList
                    return
                }
            } catch {}

            # Query interface details for the specified host from the database.  Include
            # AuthTemplate and Config so the helper can derive colour and compliance
            # information directly when not provided by the row.
            $dtIfs = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT Hostname, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, ConfigStatus, PortColor, ToolTip FROM Interfaces WHERE Hostname = '$($hostname -replace "'", "''")'"
            # Use a shared helper to build the interface PSCustomObject list.  This centralises vendor detection,
            # tooltip augmentation and JSON‑based colour/status logic for both Get‑DeviceDetails and Get‑InterfaceInfo.
            $list = Build-InterfaceObjectsFromDbRow -Data $dtIfs -Hostname $hostname -TemplatesPath (Join-Path $PSScriptRoot '..\Templates')
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

<#
    Retrieve device details and interface list without updating any UI controls.  This helper is
    intended for asynchronous use (e.g. in background tasks) so that the heavy database queries
    and interface list construction do not block the UI thread.  It mirrors the logic of
    Get‑DeviceDetails: it pulls summary information from DeviceSummary and DeviceHistory tables,
    computes fallback values when necessary, queries the Interfaces table, builds a list of
    interface objects via Build‑InterfaceObjectsFromDbRow, and retrieves configuration template
    options via Get‑ConfigurationTemplates.  The result is returned as a single PSCustomObject
    with properties Summary, Interfaces and Templates.  UI modules can consume this object to
    populate controls on the dispatcher thread.

    .PARAMETER Hostname
        The hostname of the device to load.

    .OUTPUTS
        A PSCustomObject with the following properties:
            Summary    – a hashtable of top‑level fields (Hostname, Make, Model, Uptime, Ports,
                         AuthDefaultVLAN, Building, Room)
            Interfaces – an array of PSCustomObject instances representing each interface
            Templates  – an array of strings representing available configuration templates
#>
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
        # Determine whether database is configured
        $useDb = $false
        if ($global:StateTraceDb) { $useDb = $true }
        if (-not $useDb) {
            # Fallback to CSV import when no database is available
            # Determine the module directory; PSScriptRoot points to the Modules directory
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
        try { $dtSummary = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql $summarySql } catch {}
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
            $hist = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT TOP 1 Make, Model, Uptime, AuthDefaultVLAN, Building, Room FROM DeviceHistory WHERE Trim(Hostname) = '$escHost' ORDER BY RunDate DESC"
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
            $cntDt = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT COUNT(*) AS PortCount FROM Interfaces WHERE Trim(Hostname) = '$escHost'"
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
            try { $dtIfs = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql $sqlIf } catch {}
            if ($dtIfs) {
                try { $listIfs = Build-InterfaceObjectsFromDbRow -Data $dtIfs -Hostname $hostTrim -TemplatesPath (Join-Path $PSScriptRoot '..\Templates') } catch {}
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
    <#
        Build a comprehensive list of all interfaces by querying the database and
        joining with the DeviceSummary table to include location metadata.  This
        implementation adds extensive debugging statements to aid in diagnosis
        should the list fail to populate.  It validates each row returned from
        Invoke-DbQuery, extracts all expected columns via the DataRow indexer,
        converts $null/DBNull values to empty strings, computes a sortable key
        for the port, and constructs a PSCustomObject for each interface.  The
        resulting list is stored in $global:AllInterfaces sorted by Hostname
        and PortSort.  If any anomalies arise (null rows or unexpected
        object types), they are logged and skipped rather than causing the
        process to abort.
    #>

    # Begin building the global interface list (debug output removed)
    # Use a strongly-typed list for efficient accumulation of objects
    $list = New-Object 'System.Collections.Generic.List[object]'

    if (-not $global:StateTraceDb) {
        Write-Warning "Database not configured. Interface list will be empty."
        $global:AllInterfaces = @()
        return
    }

    try {
        $sql = @"
SELECT i.Hostname, i.Port, i.Name, i.Status, i.VLAN, i.Duplex, i.Speed, i.Type,
       i.LearnedMACs, i.AuthState, i.AuthMode, i.AuthClientMAC,
       ds.Site, ds.Building, ds.Room
FROM Interfaces AS i
LEFT JOIN DeviceSummary AS ds ON i.Hostname = ds.Hostname
ORDER BY i.Hostname, i.Port
"@
        $dt = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql $sql
        # The returned query result may be a DataTable, DataView or other enumerable
        # (previous debug logging removed)

        # Prepare an enumerable of rows depending on the type of $dt.  Only
        # System.Data.DataTable is currently supported; other types will be
        # skipped entirely.  This avoids indexing into unexpected structures.
        $rows = @()
        if ($dt -is [System.Data.DataTable]) {
            $rows = $dt.Rows
        } elseif ($dt -is [System.Data.DataView]) {
            $rows = $dt  # DataView is enumerable of DataRowView
        } elseif ($dt -is [System.Collections.IEnumerable]) {
            $rows = $dt  # In case Invoke-DbQuery returns DataRow[] or similar
        } else {
            Write-Warning "DBG: Unexpected query result type; skipping row enumeration."
        }

        # Determine row count if available (removed debug output)
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

            # Optionally log first few processed rows (debug removed)

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

        # Completed interface list build; debug output removed
    } catch {
        Write-Warning "Failed to rebuild interface list from database: $($_.Exception.Message)"
    }

    # Publish the interface list globally (sorted by Hostname and PortSort).  Use a
    # stable ordering so that UI controls do not refresh unpredictably when
    # underlying enumeration order changes.
    #
    # Instead of piping through Sort-Object (which can be slow on large
    # collections due to pipeline overhead and repeated allocations), perform
    # an in-place sort on the strongly typed list using a .NET comparison
    # delegate.  This avoids unnecessary copies and provides a noticeable
    # performance improvement when processing tens of thousands of rows.
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
    # Provide final count of interfaces (debug output removed)

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
    $t = $Term.ToLower()
    # Always honour the location (site/building/room) filters, even when
    # the search term is blank.  Use the helper to retrieve the current
    # selections from the main window.  An empty selection represents
    # "All" so we do not apply that filter.
    $loc = Get-SelectedLocation
    $siteSel = $loc.Site
    $bldSel  = $loc.Building
    $roomSel = $loc.Room

    return $global:AllInterfaces | Where-Object {
        $row = $_
        # Cast row metadata to strings to ensure comparisons succeed.  When
        # the CSV values are numeric, the cast prevents mismatches when
        # comparing against the dropdown selections (which are strings).
        $rowSite     = [string]$row.Site
        $rowBuilding = [string]$row.Building
        $rowRoom     = [string]$row.Room
        # Apply site/building/room filtering first.  Skip rows that
        # don't match the selected values.  If the selection is blank
        # ("All"), then all values are permitted for that field.
        if ($siteSel -and $siteSel -ne '' -and ($rowSite -ne $siteSel)) { return $false }
        if ($bldSel  -and $bldSel  -ne '' -and ($rowBuilding -ne $bldSel)) { return $false }
        if ($roomSel -and $roomSel -ne '' -and ($rowRoom     -ne $roomSel)) { return $false }
        # Apply status and authorization filters.  Retrieve the selections
        # from the search view's StatusFilter and AuthFilter combo boxes.
        # Default to 'All' when no selection is present.  Treat 'Up'
        # equivalently to both 'Up' and 'connected', and 'Down' as both
        # 'Down' and 'notconnect'.  Authorisation filter matches exactly
        # 'Authorized' or everything else.
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
        } catch {}
        # Evaluate status filter
        if ($statusFilterVal -ne 'All') {
            # Convert status to a string safely; concatenation with an empty
            # string returns an empty string for null values, preventing null
            # method calls.
            $stLower = ('' + $row.Status).ToLower()
            if ($statusFilterVal -eq 'Up') {
                if ($stLower -ne 'up' -and $stLower -ne 'connected') { return $false }
            } elseif ($statusFilterVal -eq 'Down') {
                if ($stLower -ne 'down' -and $stLower -ne 'notconnect') { return $false }
            }
        }
        # Evaluate authorization filter
        if ($authFilterVal -ne 'All') {
            $asLower = ('' + $row.AuthState).ToLower()
            if ($authFilterVal -eq 'Authorized') {
                if ($asLower -ne 'authorized') { return $false }
            } elseif ($authFilterVal -eq 'Unauthorized') {
                if ($asLower -eq 'authorized') { return $false }
            }
        }

        # Apply the textual search filter only when a term is provided.  Match
        # against port, name, learned MACs and auth client MAC.  If the
        # search term is empty or whitespace, skip this check and allow
        # the row to pass based solely on location filtering.
        if (-not [string]::IsNullOrWhiteSpace($Term)) {
            if ($script:SearchRegexEnabled) {
                # When regex mode is enabled, treat the term as a regular expression.
                try {
                    if ( ($row.Port        -as [string]) -match $Term -or
                         ($row.Name        -as [string]) -match $Term -or
                         ($row.LearnedMACs -as [string]) -match $Term -or
                         ($row.AuthClientMAC -as [string]) -match $Term ) {
                        # matched; continue
                    } else {
                        return $false
                    }
                } catch {
                    # If the regex is invalid, fall back to case-insensitive substring search
                    $t = $Term.ToLower()
                    if (-not ((('' + $row.Port).ToLower().Contains($t)) -or
                              (('' + $row.Name).ToLower().Contains($t)) -or
                              (('' + $row.LearnedMACs).ToLower().Contains($t)) -or
                              (('' + $row.AuthClientMAC).ToLower().Contains($t)))) {
                        return $false
                    }
                }
            } else {
                $t = $Term.ToLower()
                if (-not ((('' + $row.Port).ToLower().Contains($t)) -or
                          (('' + $row.Name).ToLower().Contains($t)) -or
                          (('' + $row.LearnedMACs).ToLower().Contains($t)) -or
                          (('' + $row.AuthClientMAC).ToLower().Contains($t)))) {
                    return $false
                }
            }
        }
        return $true
    }
}

function Update-Summary {
    if (-not $global:summaryView) { return }
    # Determine location filters from the main window.  When blank,
    # the filter is treated as "All" and no restriction is applied.
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
    $filteredDevices = @()
    foreach ($k in $devKeys) {
        $meta = $global:DeviceMetadata[$k]
        if ($meta) {
            if ($siteSel -and $siteSel -ne '' -and $meta.Site -ne $siteSel) { continue }
            if ($bldSel  -and $bldSel  -ne '' -and $meta.Building -ne $bldSel) { continue }
            if ($roomSel -and $roomSel -ne '' -and $meta.Room     -ne $roomSel) { continue }
            $filteredDevices += $k
        }
    }
    $devCount = $filteredDevices.Count
    # Filter interface rows according to location
    $rows = if ($global:AllInterfaces) { $global:AllInterfaces } else { @() }
    $filteredRows = @()
    foreach ($row in $rows) {
        $rSite = '' + $row.Site
        $rBld  = '' + $row.Building
        $rRoom = '' + $row.Room
        if ($siteSel -and $siteSel -ne '' -and $rSite -ne $siteSel) { continue }
        if ($bldSel  -and $bldSel  -ne '' -and $rBld  -ne $bldSel)  { continue }
        if ($roomSel -and $roomSel -ne '' -and $rRoom -ne $roomSel) { continue }
        $filteredRows += $row
    }
    $intCount = $filteredRows.Count
    $upCount = 0; $downCount = 0; $authCount = 0; $unauthCount = 0; $vlans = @()
    foreach ($row in $filteredRows) {
        $status = '' + $row.Status
        if ($status) {
            switch -Regex ($status.ToLower()) {
                '^(up|connected)$' { $upCount++; break }
                '^(down|notconnect)$' { $downCount++; break }
                default { }
            }
        }
        $authState = '' + $row.AuthState
        if ($authState) {
            if ($authState.ToLower() -eq 'authorized') { $authCount++ } else { $unauthCount++ }
        } else {
            $unauthCount++
        }
        if ($row.VLAN -and $row.VLAN -ne '') { $vlans += $row.VLAN }
    }
    # Build a unique set of VLANs using a HashSet.  Using Sort-Object -Unique on large
    # collections performs an O(n log n) sort before deduplication, which can be
    # expensive when there are thousands of VLAN values.  A HashSet provides
    # O(1) average-time insertions and avoids intermediary pipeline overhead.  After
    # deduplication, sort the unique list once using a case-insensitive ordinal
    # comparer.  This preserves the previous behaviour of sorting strings in a
    # culture-invariant manner.
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
    $alerts = @()
    foreach ($row in $global:AllInterfaces) {
        $reasons = @()
        $status = '' + $row.Status
        if ($status) {
            $statusLow = $status.ToLower()
            if ($statusLow -eq 'down' -or $statusLow -eq 'notconnect') { $reasons += 'Port down' }
        }
        $duplex = '' + $row.Duplex
        if ($duplex) {
            $dx = $duplex.ToLower()
            # Consider both "full" and auto/adaptive full modes as acceptable.  Only flag
            # duplex values containing "half" as non-full duplex.
            if ($dx -match 'half') {
                $reasons += 'Half duplex'
            }
        }
        $authState = '' + $row.AuthState
        if ($authState) {
            if ($authState.ToLower() -ne 'authorized') { $reasons += 'Unauthorized' }
        } else {
            $reasons += 'Unauthorized'
        }
        if ($reasons.Count -gt 0) {
            $alerts += [PSCustomObject]@{
                Hostname  = $row.Hostname
                Port      = $row.Port
                Name      = $row.Name
                Status    = $row.Status
                VLAN      = $row.VLAN
                Duplex    = $row.Duplex
                AuthState = $row.AuthState
                Reason    = ($reasons -join '; ')
            }
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
    # visit to the Search tab), trigger a rebuild now.  Without this
    # call, $global:AllInterfaces remains empty because the initial load
    # is deferred until the user performs a search.  This ensures that
    # Update-SearchResults has data to work with.  The check guards
    # against unnecessary reloads after the list has been populated.
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
        # debug output removed
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
    $nums = [regex]::Matches($numsPart, '\d+') | ForEach-Object { [int]$_.Value }
    while ($nums.Count -lt 4) { $nums += 0 }        # pad
    $segments = ($nums | Select-Object -First 6 | ForEach-Object { '{0:00000}' -f $_ })

    return ('{0:00}-{1}-{2}' -f $w, $type, ($segments -join '-'))
}

##
# Centralised data-access helper functions moved from InterfaceModule.
# These functions provide a single point of access for interface hostnames,
# interface information, configuration templates and configuration generation.
# By defining them here, all view modules can call into DeviceDataModule for
# backend data without importing InterfaceModule.

function Get-InterfaceHostnames {
    [CmdletBinding()]
    param([string]$ParsedDataPath)
    # Ignore ParsedDataPath; always use the database when available.
    if (-not $global:StateTraceDb) {
        return @()
    }
    try {
        $dbModule = Join-Path $PSScriptRoot 'DatabaseModule.psm1'
        if (Test-Path $dbModule) {
            Import-Module $dbModule -Force -Global -ErrorAction SilentlyContinue | Out-Null
        }
        $dtHosts = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql 'SELECT Hostname FROM DeviceSummary ORDER BY Hostname'
        return ($dtHosts | ForEach-Object { $_.Hostname })
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
    if (-not $global:StateTraceDb) { return @() }
    try {
        $dbModulePath = Join-Path $PSScriptRoot 'DatabaseModule.psm1'
        if (Test-Path $dbModulePath) {
            Import-Module $dbModulePath -Force -Global -ErrorAction SilentlyContinue | Out-Null
        }
        $escHost = $Hostname -replace "'", "''"
        $dt = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT Make FROM DeviceSummary WHERE Hostname = '$escHost'"
        $make = ''
        if ($dt) {
            if ($dt -is [System.Data.DataTable]) {
                if ($dt.Rows.Count -gt 0) { $make = $dt.Rows[0].Make }
            } else {
                $firstRow = $dt | Select-Object -First 1
                if ($firstRow -and $firstRow.PSObject.Properties['Make']) { $make = $firstRow.Make }
            }
        }
        $vendorFile = if ($make -match '(?i)brocade') { 'Brocade.json' } else { 'Cisco.json' }
        $jsonFile = Join-Path $TemplatesPath $vendorFile
        if (-not (Test-Path $jsonFile)) { throw "Template file missing: $jsonFile" }
        $templates = (Get-Content $jsonFile -Raw | ConvertFrom-Json).templates
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
    # Always use the consolidated helper to build interface details.  By delegating
    # to Build‑InterfaceObjectsFromDbRow we avoid duplicating vendor detection,
    # template loading, tooltip augmentation and per‑row logic.  We only need
    # to query the Interfaces table for the specified host and pass the result.
    if (-not $global:StateTraceDb) { return @() }
    try {
        $dbModule = Join-Path $PSScriptRoot 'DatabaseModule.psm1'
        if (Test-Path $dbModule) {
            Import-Module $dbModule -Force -Global -ErrorAction SilentlyContinue | Out-Null
        }
        $escHost = $Hostname -replace "'", "''"
        $sql = "SELECT Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, ConfigStatus, PortColor, ToolTip FROM Interfaces WHERE Hostname = '$escHost' ORDER BY Port"
        $dt = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql $sql
        # Delegate to the shared helper which returns an array of PSCustomObject.
        return Build-InterfaceObjectsFromDbRow -Data $dt -Hostname $Hostname -TemplatesPath $TemplatesPath
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
    if (-not $global:StateTraceDb) { return @() }
    $debug = ($Global:StateTraceDebug -eq $true)
    try {
        $dbModule = Join-Path $PSScriptRoot 'DatabaseModule.psm1'
        if (Test-Path $dbModule) {
            Import-Module $dbModule -Force -Global -ErrorAction SilentlyContinue | Out-Null
        }
        $escHost = $Hostname -replace "'", "''"
        $vendor = 'Cisco'
        try {
            $mkDt = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT Make FROM DeviceSummary WHERE Hostname = '$escHost'"
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
        $templates = (Get-Content $jsonFile -Raw | ConvertFrom-Json).templates
        $tmpl = $templates | Where-Object { $_.name -eq $TemplateName } | Select-Object -First 1
        if (-not $tmpl) { throw "Template '$TemplateName' not found in ${vendor}.json" }
        $oldConfigs = @{}
        foreach ($p in $Interfaces) {
            $pEsc = $p -replace "'", "''"
            $sqlCfg = "SELECT Config FROM Interfaces WHERE Hostname = '$escHost' AND Port = '$pEsc'"
            $dtCfg  = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql $sqlCfg
            if ($dtCfg) {
                if ($dtCfg -is [System.Data.DataTable]) {
                    if ($dtCfg.Rows.Count -gt 0) {
                        $cfgText = $dtCfg.Rows[0].Config
                        $oldConfigs[$p] = if ($cfgText) { $cfgText -split "`n" } else { @() }
                    }
                } else {
                    $rowCfg = $dtCfg | Select-Object -First 1
                    if ($rowCfg -and $rowCfg.PSObject.Properties['Config']) {
                        $cfgText = $rowCfg.Config
                        $oldConfigs[$p] = if ($cfgText) { $cfgText -split "`n" } else { @() }
                    }
                }
            }
        }
        $outLines = foreach ($port in $Interfaces) {
            "interface $port"
            $pending = @()
            $nameOverride = if ($NewNames.ContainsKey($port)) { $NewNames[$port] } else { $null }
            $vlanOverride = if ($NewVlans.ContainsKey($port)) { $NewVlans[$port] } else { $null }
            if ($nameOverride) {
                $pending += $(if ($vendor -eq 'Cisco') { "description $nameOverride" } else { "port-name $nameOverride" })
            }
            if ($vlanOverride) {
                $pending += $(if ($vendor -eq 'Cisco') { "switchport access vlan $vlanOverride" } else { "auth-default-vlan $vlanOverride" })
            }
            foreach ($cmd in $tmpl.required_commands) { $pending += $cmd.Trim() }
            if ($oldConfigs.ContainsKey($port)) {
                foreach ($oldLine in $oldConfigs[$port]) {
                    $trimOld  = $oldLine.Trim()
                    if (-not $trimOld) { continue }
                    $lowerOld = $trimOld.ToLower()
                    if ($lowerOld.StartsWith('interface') -or $lowerOld -eq 'exit') { continue }
                    $existsInNew = $false
                    foreach ($newCmd in $pending) {
                        if ($lowerOld -like ("$($newCmd.ToLower())*")) { $existsInNew = $true; break }
                    }
                    if ($existsInNew) { continue }
                    if ($vendor -eq 'Cisco') {
                        if ($lowerOld.StartsWith('authentication') -or $lowerOld.StartsWith('dot1x') -or $lowerOld -eq 'mab') {
                            " no $trimOld"
                        }
                    } else {
                        if ($lowerOld -match 'dot1x\s+port-control\s+auto' -or $lowerOld -match 'mac-authentication\s+enable') {
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
        $dbModule = Join-Path $PSScriptRoot 'DatabaseModule.psm1'
        if (Test-Path $dbModule) {
            Import-Module $dbModule -Force -Global -ErrorAction SilentlyContinue | Out-Null
        }
        $escHost = $Hostname -replace "'", "''"
        $dt = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT Port FROM Interfaces WHERE Hostname = '$escHost' ORDER BY Port"
        $ports = $dt | ForEach-Object { $_.Port }
        return $ports
    } catch {
        Write-Warning ("Failed to get interface list for {0}: {1}" -f $Hostname, $_.Exception.Message)
        return @()
    }
}

# Export all helper functions.  When this module is imported with -Global,
# these names will be added to the global scope and callable without
# qualification.  Exporting explicitly helps prevent private helper
# functions from leaking unintentionally.
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
    Set-DropdownItems