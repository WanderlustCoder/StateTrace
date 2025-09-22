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
    [CmdletBinding()]
    param([string]$Hostname)
    DeviceRepositoryModule\Get-SiteFromHostname @PSBoundParameters
}

function Get-DbPathForHost {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Hostname)
    DeviceRepositoryModule\Get-DbPathForHost @PSBoundParameters
}

function Get-AllSiteDbPaths {
    [CmdletBinding()]
    param()
    DeviceRepositoryModule\Get-AllSiteDbPaths @PSBoundParameters
}

function Update-SiteZoneCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Site,
        [string]$Zone
    )
    DeviceRepositoryModule\Update-SiteZoneCache @PSBoundParameters
}

function Get-InterfacesForSite {
    [CmdletBinding()]
    param([string]$Site)
    DeviceRepositoryModule\Get-InterfacesForSite @PSBoundParameters
}

function Clear-SiteInterfaceCache {
    [CmdletBinding()]
    param()
    DeviceRepositoryModule\Clear-SiteInterfaceCache @PSBoundParameters
}

function Import-DatabaseModule {
    [CmdletBinding()]
    param()
    DeviceRepositoryModule\Import-DatabaseModule
}

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
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Value)

    try { Import-DatabaseModule } catch {}
    try {
        return DatabaseModule\Get-SqlLiteral @PSBoundParameters
    } catch {
        return $Value -replace "'", "''"
    }
}

function Get-InterfacesForHostsBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [Parameter(Mandatory)][string[]]$Hostnames
    )
    DeviceRepositoryModule\Get-InterfacesForHostsBatch @PSBoundParameters
}

function Get-DeviceSummaries {
    $catalogResult = $null
    try { $catalogResult = DeviceCatalogModule\Get-DeviceSummaries } catch { $catalogResult = $null }
    $names = New-Object 'System.Collections.Generic.List[string]'
    if ($catalogResult -and $catalogResult.Hostnames) {
        foreach ($n in $catalogResult.Hostnames) {
            if ([string]::IsNullOrWhiteSpace($n)) { continue }
            if (-not $names.Contains($n)) { [void]$names.Add($n) }
        }
    }
    $DeviceMetadata = $global:DeviceMetadata
    if (-not $DeviceMetadata) {
        $DeviceMetadata = @{}
        $global:DeviceMetadata = $DeviceMetadata
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
    # When the site or zone selection changes, the set of devices and interfaces
    # visible to the user may change dramatically.  Rebuild the global
    # interface list and the per‑device cache so that subsequent operations
    # (search, summary, alerts, compare) operate on the correct dataset.
    try {
        if (Get-Command -Name 'Update-GlobalInterfaceList' -ErrorAction SilentlyContinue) {
            # Only refresh the global interface list when the site or zone has changed.
            # Avoid unnecessary reloads when the user merely tweaks the building or room
            # filters, which are applied client‑side to the already loaded data.
            if ($siteChanged -or $zoneChanged) {
                Update-GlobalInterfaceList
            }
        }
    } catch {
        # Suppress any errors during refresh; continue to update downstream views.
    }
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
            $list = InterfaceModule\New-InterfaceObjectsFromDbRow -Data $dtIfs -Hostname $hostname -TemplatesPath (Join-Path $PSScriptRoot '..\Templates')
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
            $grid.ItemsSource = InterfaceModule\Get-InterfaceInfo -Hostname $hostname
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
                $list = InterfaceModule\Get-InterfaceInfo -Hostname $hostTrim
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
                try { $listIfs = InterfaceModule\New-InterfaceObjectsFromDbRow -Data $dtIfs -Hostname $hostTrim -TemplatesPath (Join-Path $PSScriptRoot '..\Templates') } catch {}
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
    DeviceRepositoryModule\Invoke-ParallelDbQuery @PSBoundParameters
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
    # Determine the currently selected zone (if any) from the location object
    $zoneSel = $null
    if ($loc) {
        try { $zoneSel = $loc.Zone } catch { $zoneSel = $null }
    }
    # Build a new list of interfaces for the selected site/zone.  This list is derived
    # from the per-device interface cache rather than loading directly from the
    # database.  When a specific site is selected, ensure its data is loaded via
    # Update-SiteZoneCache.  When 'All Sites' is selected, all currently cached
    # interfaces are returned without loading additional data.
    $interfaces = New-Object 'System.Collections.Generic.List[object]'
    if ($siteSel -and $siteSel -ne '' -and $siteSel -ne 'All Sites') {
        # Determine which zone to load.  When a specific zone is selected (not blank and not
        # 'All Zones'), use that zone.  When the selection is 'All Zones', pass an
        # empty string to Update-SiteZoneCache so that it loads all zones for the site.
        # Otherwise (no zone selected), pick the first available zone from DeviceMetadata
        # to avoid loading every zone prematurely.
        $zoneToLoad = $null
        if ($zoneSel -and $zoneSel -ne '') {
            if ($zoneSel -ieq 'All Zones') {
                # Empty string signals Update-SiteZoneCache to load all zones
                $zoneToLoad = ''
            } else {
                $zoneToLoad = $zoneSel
            }
        } else {
            # No zone explicitly selected – choose the first zone for the site
            $zSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
            try {
                if ($global:DeviceMetadata) {
                    foreach ($entry in $global:DeviceMetadata.GetEnumerator()) {
                        $metaSite = '' + $entry.Value.Site
                        if ($metaSite -ne $siteSel) { continue }
                        $z = $null
                        if ($entry.Value.PSObject.Properties['Zone']) {
                            try { $z = '' + $entry.Value.Zone } catch { $z = $null }
                        }
                        if (-not $z) {
                            $hnParts = ('' + $entry.Key) -split '-'
                            if ($hnParts.Length -ge 2) { $z = '' + $hnParts[1] }
                        }
                        if ($z -and $z -ne '') { [void]$zSet.Add($z) }
                    }
                }
            } catch { }
            if ($zSet.Count -gt 0) {
                $zList = $zSet.ToArray()
                [array]::Sort($zList, [System.StringComparer]::OrdinalIgnoreCase)
                $zoneToLoad = $zList[0]
            }
        }
        # Load interface data for the selected site and chosen zone (if any)
        try { Update-SiteZoneCache -Site $siteSel -Zone $zoneToLoad | Out-Null } catch { }
        foreach ($kv in $global:DeviceInterfaceCache.GetEnumerator()) {
            $hn = $kv.Key
            # Parse site and zone from the hostname (format: SITE-ZONE-...)
            $parts = ('' + $hn) -split '-'
            $sitePart = if ($parts.Length -ge 1) { $parts[0] } else { '' }
            $zonePart = if ($parts.Length -ge 2) { $parts[1] } else { '' }
            if ($sitePart -ne $siteSel) { continue }
            if ($zoneSel -and $zoneSel -ne '' -and $zoneSel -ne 'All Zones') {
                if ($zonePart -ne $zoneSel) { continue }
            } elseif ($zoneToLoad -and $zoneToLoad -ne '') {
                # When no specific zone is selected, filter by the zone we loaded
                if ($zonePart -ne $zoneToLoad) { continue }
            }
            foreach ($row in $kv.Value) {
                [void]$interfaces.Add($row)
            }
        }
    } else {
        foreach ($kv in $global:DeviceInterfaceCache.GetEnumerator()) {
            foreach ($row in $kv.Value) {
                [void]$interfaces.Add($row)
            }
        }
    }
    # Ensure each interface row exposes the Hostname and IsSelected properties for UI binding
    foreach ($row in $interfaces) {
        if (-not $row) { continue }
        try {
            if (-not $row.PSObject.Properties['Hostname']) {
                $hnVal = ''
                try { $hnVal = '' + $row.Hostname } catch { $hnVal = '' }
                $row | Add-Member -NotePropertyName Hostname -NotePropertyValue $hnVal -ErrorAction SilentlyContinue
            }
        } catch { }
        try {
            if (-not $row.PSObject.Properties['IsSelected']) {
                $row | Add-Member -NotePropertyName IsSelected -NotePropertyValue $false -ErrorAction SilentlyContinue
            }
        } catch { }
    }
    # Publish the filtered interface list globally
    $global:AllInterfaces = $interfaces
    # Do not reset DeviceInterfaceCache here; it accumulates data across loaded sites and zones
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
    # Determine device count under location filters.  Build a list of device keys
    # matching the selected site/zone/building/room.  Use a typed list for efficiency.
    $devKeys = if ($global:DeviceMetadata) { $global:DeviceMetadata.Keys } else { @() }
    $filteredDevices = [System.Collections.Generic.List[string]]::new()
    foreach ($k in $devKeys) {
        $meta = $global:DeviceMetadata[$k]
        if (-not $meta) { continue }
        if ($siteSel -and $siteSel -ne '' -and $siteSel -ne 'All Sites' -and ($meta.Site -ne $siteSel)) { continue }
        if ($zoneSel -and $zoneSel -ne '' -and $zoneSel -ne 'All Zones') {
            # When metadata has a Zone property, require it to match; otherwise parse hostname
            $mZ = $null
            if ($meta.PSObject.Properties['Zone']) { $mZ = '' + $meta.Zone }
            if (-not $mZ) {
                $partsZ = ('' + $k) -split '-'
                if ($partsZ.Length -ge 2) { $mZ = $partsZ[1] }
            }
            if ($mZ -ne $zoneSel) { continue }
        }
        if ($bldSel  -and $bldSel  -ne '' -and ($meta.Building -ne $bldSel))  { continue }
        if ($roomSel -and $roomSel -ne '' -and ($meta.Room     -ne $roomSel)) { continue }
        [void]$filteredDevices.Add($k)
    }
    $devCount = $filteredDevices.Count
    # Ensure interface data for each filtered device is loaded.  When a host is not present
    # in the DeviceInterfaceCache, retrieve its interface information from the database.
        foreach ($d in $filteredDevices) {
        try {
            if (-not $global:DeviceInterfaceCache -or -not $global:DeviceInterfaceCache.ContainsKey($d)) {
                # Load interface information for this host when not present in the cache.  Call the
                # local Get-InterfaceInfo function directly (do not qualify with the module name)
                # because we are already within the DeviceDataModule context.
                Get-InterfaceInfo -Hostname $d | Out-Null
                # Use a formatted string to avoid variable parsing issues when printing debug output.
                Write-Host ("[Update-Summary] Loaded interface info for {0}" -f $d)
            }
        } catch {
            # Format the error message using the format operator so that the colon following the
            # hostname does not confuse PowerShell's variable parsing.  Without formatting, the
            # `$d:` portion would be treated as a drive-qualified variable name and cause a
            # ParserError when loading this module.
            $msg = $_.Exception.Message
            Write-Host ("[Update-Summary] Failed to load interface info for {0}: {1}" -f $d, $msg)
        }
    }
    # Build a collection of interface rows for the filtered devices, applying zone/building/room
    # filters to each row.  Use a typed list for efficiency.
    $filteredRows = [System.Collections.Generic.List[object]]::new()
    foreach ($dev in $filteredDevices) {
        $rowsForDev = $null
        try {
            if ($global:DeviceInterfaceCache -and $global:DeviceInterfaceCache.ContainsKey($dev)) {
                $rowsForDev = $global:DeviceInterfaceCache[$dev]
            }
        } catch {}
        if (-not $rowsForDev) { continue }
        foreach ($row in $rowsForDev) {
            if (-not $row) { continue }
            $rSite = '' + $row.Site
            $rZone = ''
            if ($row.PSObject.Properties['Zone']) { $rZone = '' + $row.Zone }
            $rBld  = '' + $row.Building
            $rRoom = '' + $row.Room
            if ($siteSel -and $siteSel -ne '' -and $siteSel -ne 'All Sites' -and ($rSite -ne $siteSel)) { continue }
            if ($zoneSel -and $zoneSel -ne '' -and $zoneSel -ne 'All Zones' -and ($rZone -ne $zoneSel)) { continue }
            if ($bldSel  -and $bldSel  -ne '' -and ($rBld  -ne $bldSel))  { continue }
            if ($roomSel -and $roomSel -ne '' -and ($rRoom -ne $roomSel)) { continue }
            [void]$filteredRows.Add($row)
        }
    }
    # Compute interface metrics from the filtered rows.
    $intCount = $filteredRows.Count
    $upCount = 0; $downCount = 0; $authCount = 0; $unauthCount = 0;
    $vlans = [System.Collections.Generic.List[string]]::new()
    foreach ($row in $filteredRows) {
        $status = '' + $row.Status
        if ($status) {
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
    # Determine unique VLANs
    $vlanSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($v in $vlans) {
        if (-not [string]::IsNullOrWhiteSpace($v)) { [void]$vlanSet.Add($v) }
    }
    $uniqueVlans = [System.Collections.Generic.List[string]]::new($vlanSet)
    $uniqueVlans.Sort([System.StringComparer]::OrdinalIgnoreCase)
    $uniqueCount = $uniqueVlans.Count
    # Update summary display elements
    try {
        $sv = $global:summaryView
        if ($sv) {
            ($sv.FindName('SummaryDevicesCount')).Text      = $devCount.ToString()
            ($sv.FindName('SummaryInterfacesCount')).Text   = $intCount.ToString()
            ($sv.FindName('SummaryUpCount')).Text           = $upCount.ToString()
            ($sv.FindName('SummaryDownCount')).Text         = $downCount.ToString()
            ($sv.FindName('SummaryAuthorizedCount')).Text    = $authCount.ToString()
            ($sv.FindName('SummaryUnauthorizedCount')).Text  = $unauthCount.ToString()
            ($sv.FindName('SummaryUniqueVlansCount')).Text   = $uniqueCount.ToString()
            $ratio = if ($intCount -gt 0) { [math]::Round(($upCount / $intCount) * 100, 1) } else { 0 }
            ($sv.FindName('SummaryExtra')).Text = "Up %: $ratio%"
            # Emit debugging information to the terminal to help trace summary computations.
            Write-Host "[Update-Summary] Devices=$devCount, Interfaces=$intCount, Up=$upCount, Down=$downCount, Auth=$authCount, Unauth=$unauthCount, UniqueVlans=$uniqueCount, Up%=$ratio%"
        }
    } catch {}
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
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Port)
    InterfaceModule\Get-PortSortKey @PSBoundParameters
}

function Get-InterfaceHostnames {
    [CmdletBinding()]
    param(
        [string]$ParsedDataPath,
        [string]$Site,
        [string]$Zone,
        [string]$Building,
        [string]$Room
    )
    DeviceCatalogModule\Get-InterfaceHostnames @PSBoundParameters
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
    DeviceRepositoryModule\Get-InterfaceInfo @PSBoundParameters
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
    Get-InterfaceConfiguration, `
    Set-DropdownItems, `
    Get-SqlLiteral, `
    Get-InterfacesForHostsBatch, `
    Get-InterfacesForSite, `
    Update-SiteZoneCache, `
    Clear-SiteInterfaceCache, `
    Import-DatabaseModule


