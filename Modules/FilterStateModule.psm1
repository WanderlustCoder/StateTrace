Set-StrictMode -Version Latest

if (-not (Get-Variable -Scope Script -Name DeviceFilterUpdating -ErrorAction SilentlyContinue)) {
    $script:DeviceFilterUpdating = $false
}
if (-not (Get-Variable -Scope Script -Name DeviceFilterFaulted -ErrorAction SilentlyContinue)) {
    $script:DeviceFilterFaulted = $false
}
if (-not (Get-Variable -Scope Script -Name LastSiteSel -ErrorAction SilentlyContinue)) {
    $script:LastSiteSel = ''
}
if (-not (Get-Variable -Scope Script -Name LastZoneSel -ErrorAction SilentlyContinue)) {
    $script:LastZoneSel = ''
}
if (-not (Get-Variable -Scope Script -Name LastBuildingSel -ErrorAction SilentlyContinue)) {
    $script:LastBuildingSel = ''
}
if (-not (Get-Variable -Scope Script -Name LastRoomSel -ErrorAction SilentlyContinue)) {
    $script:LastRoomSel = ''
}
if (-not (Get-Variable -Scope Global -Name ProgrammaticFilterUpdate -ErrorAction SilentlyContinue)) {
    $global:ProgrammaticFilterUpdate = $false
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

function Initialize-DeviceFilters {
    [CmdletBinding()]
    param(
        [object[]]$Hostnames,
        [object]$Window = $global:window
    )

    if (-not $Window) { return }

    $hostList = New-Object 'System.Collections.Generic.List[string]'
    if ($Hostnames) {
        foreach ($raw in $Hostnames) {
            $name = '' + $raw
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            if (-not $hostList.Contains($name)) { [void]$hostList.Add($name) }
        }
    } elseif ($global:DeviceMetadata) {
        foreach ($entry in $global:DeviceMetadata.GetEnumerator()) {
            $key = '' + $entry.Key
            if ([string]::IsNullOrWhiteSpace($key)) { continue }
            if (-not $hostList.Contains($key)) { [void]$hostList.Add($key) }
        }
    }

    $hostnameDD = $Window.FindName('HostnameDropdown')
    if ($hostnameDD) {
        Set-DropdownItems -Control $hostnameDD -Items $hostList
    }

    $metadata = $global:DeviceMetadata
    if (-not $metadata) { $metadata = @{} }

    $uniqueSites = @()
    if ($metadata.Count -gt 0) {
        $siteSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($meta in $metadata.Values) {
            $site = ''
            if ($meta -and $meta.PSObject.Properties['Site']) { $site = '' + $meta.Site }
            if (-not [string]::IsNullOrWhiteSpace($site)) { [void]$siteSet.Add($site) }
        }
        $uniqueSites = [System.Collections.Generic.List[string]]::new($siteSet)
        $uniqueSites.Sort([System.StringComparer]::OrdinalIgnoreCase)
    }

    $siteDD = $Window.FindName('SiteDropdown')
    if ($siteDD) {
        Set-DropdownItems -Control $siteDD -Items (@('All Sites') + $uniqueSites)
        try {
            if ($uniqueSites.Count -gt 0) { $siteDD.SelectedItem = $uniqueSites[0] }
        } catch {}
    }

    $zoneDD = $Window.FindName('ZoneDropdown')
    if ($zoneDD) {
        Set-DropdownItems -Control $zoneDD -Items @('All Zones')
        $zoneDD.IsEnabled = $true
    }

    $buildingDD = $Window.FindName('BuildingDropdown')
    if ($buildingDD) {
        Set-DropdownItems -Control $buildingDD -Items @('')
        $buildingDD.IsEnabled = $false
    }

    $roomDD = $Window.FindName('RoomDropdown')
    if ($roomDD) {
        Set-DropdownItems -Control $roomDD -Items @('')
        $roomDD.IsEnabled = $false
    }

    try {
        if (Get-Command -Name Update-GlobalInterfaceList -ErrorAction SilentlyContinue) {
            Update-GlobalInterfaceList
        } else {
            DeviceRepositoryModule\Update-GlobalInterfaceList | Out-Null
        }
    } catch {}

    try {
        $searchHostCtrl = $Window.FindName('SearchInterfacesHost')
        if ($searchHostCtrl -is [System.Windows.Controls.ContentControl]) {
            $searchView = $searchHostCtrl.Content
            if ($searchView) {
                $searchGrid = $searchView.FindName('SearchInterfacesGrid')
                if ($searchGrid) { $searchGrid.ItemsSource = $global:AllInterfaces }
            }
        }
    } catch {}
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
            Set-DropdownItems -Control $zoneDD -Items @('All Zones')
            # Always leave the zone dropdown enabled when a site is selected (including the "All Sites" sentinel).  If no site
            # selection exists (blank), the zone list will remain enabled so the user can choose a zone across sites later.
            $zoneDD.IsEnabled = $true
        }
        if ( ($siteChanged -or $zoneChanged) -and $buildingDD ) {
            # When the site or zone changes, clear the building and room lists and disable room until a building is selected.
            Set-DropdownItems -Control $buildingDD -Items @('')
            $buildingDD.IsEnabled = if ($currentSiteSel -and $currentSiteSel -ne '' -and $currentSiteSel -ne 'All Sites') { $true } else { $false }
            if ($roomDD) {
                Set-DropdownItems -Control $roomDD -Items @('')
                $roomDD.IsEnabled = $false
            }
        } elseif ($bldChanged -and $roomDD) {
            # Building changed: clear the room list and update its enabled state.
            Set-DropdownItems -Control $roomDD -Items @('')
            $roomDD.IsEnabled = if ($currentBldSel -and $currentBldSel -ne '') { $true } else { $false }
        }

        if (-not $global:DeviceMetadata) {
            Write-Verbose 'FilterStateModule: DeviceMetadata not yet loaded; skipping device filter update.'
            return
        }

        $DeviceMetadata = $global:DeviceMetadata

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
        # Enable the room dropdown only when a non-blank site and building are
        if (($siteSel -and $siteSel -ne '') -and ($buildingDD.SelectedIndex -gt 0)) {
            $roomDD.IsEnabled = $true
        } else {
            $roomDD.IsEnabled = $false
        }
    }

    # ---------------------------------------------------------------------
    # When the site or zone selection changes, the set of devices and interfaces
    # visible to the user may change dramatically.  Rebuild the global
    # interface list and the per-device cache so that subsequent operations
    # (search, summary, alerts, compare) operate on the correct dataset.
    try {
        if (Get-Command -Name 'Update-GlobalInterfaceList' -ErrorAction SilentlyContinue) {
            # Only refresh the global interface list when the site or zone has changed.
            # Avoid unnecessary reloads when the user merely tweaks the building or room
            # filters, which are applied client-side to the already loaded data.
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

function Set-FilterFaulted {
    [CmdletBinding()]
    param([bool]$Faulted = $true)
    $script:DeviceFilterFaulted = [bool]$Faulted
}

function Get-FilterFaulted {
    [CmdletBinding()]
    param()
    return [bool]$script:DeviceFilterFaulted
}

Export-ModuleMember -Function Test-StringListEqualCI, Get-SelectedLocation, Get-LastLocation, Set-DropdownItems, Initialize-DeviceFilters, Update-DeviceFilter, Set-FilterFaulted, Get-FilterFaulted



