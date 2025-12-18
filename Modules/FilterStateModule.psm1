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
if (-not (Get-Variable -Scope Global -Name InterfacesLoadAllowed -ErrorAction SilentlyContinue)) {
    $global:InterfacesLoadAllowed = $false
}
if (-not (Get-Variable -Scope Global -Name DeviceLocationEntries -ErrorAction SilentlyContinue)) {
    $global:DeviceLocationEntries = @()
}

try { TelemetryModule\Import-InterfaceCommon | Out-Null } catch { }

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

function Resolve-SelectionValue {
    param(
        [string]$Current,
        [object[]]$Candidates,
        [string]$Sentinel
    )

    $value = if ($null -ne $Current) { '' + $Current } else { '' }
    if ([string]::IsNullOrWhiteSpace($value)) { return $Sentinel }

    if ($Sentinel -and [System.StringComparer]::OrdinalIgnoreCase.Equals($value, $Sentinel)) {
        return $Sentinel
    }

    if ($Candidates) {
        foreach ($candidate in $Candidates) {
            $candidateText = if ($null -ne $candidate) { '' + $candidate } else { '' }
            if ([System.StringComparer]::OrdinalIgnoreCase.Equals($candidateText, $value)) {
                return $candidateText
            }
        }
    }

    return $Sentinel
}

function Set-DropdownItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Windows.Controls.ItemsControl]$Control,
        [object[]]$Items = @()
    )

    if (-not $Items) { $Items = @() }

    $Control.ItemsSource = $Items
    if ($Items -and $Items.Count -gt 0) {
        try { $Control.SelectedIndex = 0 } catch { }
    } else {
        try { $Control.SelectedIndex = -1 } catch { }
    }
}

function script:Get-LocationEntriesFromMetadata {
    [CmdletBinding()]
    param([object]$Metadata)

    if (-not ($Metadata -is [System.Collections.IDictionary])) { return $null }
    if ($Metadata.Count -eq 0) { return $null }

    $keys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $list = [System.Collections.Generic.List[object]]::new()

    foreach ($entry in $Metadata.GetEnumerator()) {
        $hostname = '' + $entry.Key
        $meta = $entry.Value
        if (-not $meta) { continue }

        $siteVal = ''
        $zoneVal = ''
        $buildingVal = ''
        $roomVal = ''
        try { if ($meta.PSObject.Properties['Site']) { $siteVal = '' + $meta.Site } } catch { $siteVal = '' }
        try { if ($meta.PSObject.Properties['Zone']) { $zoneVal = '' + $meta.Zone } } catch { $zoneVal = '' }
        try { if ($meta.PSObject.Properties['Building']) { $buildingVal = '' + $meta.Building } } catch { $buildingVal = '' }
        try { if ($meta.PSObject.Properties['Room']) { $roomVal = '' + $meta.Room } } catch { $roomVal = '' }

        if ([string]::IsNullOrWhiteSpace($siteVal) -or [string]::IsNullOrWhiteSpace($zoneVal)) {
            try {
                $parts = $hostname -split '-', 3
                if ([string]::IsNullOrWhiteSpace($siteVal) -and $parts.Length -ge 1) { $siteVal = $parts[0] }
                if ([string]::IsNullOrWhiteSpace($zoneVal) -and $parts.Length -ge 2) { $zoneVal = $parts[1] }
            } catch { }
        }

        $key = "{0}|{1}|{2}|{3}" -f $siteVal, $zoneVal, $buildingVal, $roomVal
        if (-not $keys.Add($key)) { continue }

        $list.Add([pscustomobject]@{
            Site     = $siteVal
            Zone     = $zoneVal
            Building = $buildingVal
            Room     = $roomVal
        }) | Out-Null
    }

    if ($list.Count -eq 0) { return $null }
    return $list
}

function Initialize-DeviceFilters {
    [CmdletBinding()]
    param(
        [object[]]$Hostnames,
        [object]$Window = $global:window,
        [object[]]$LocationEntries
    )

    if (-not $Window) { return }

    $previousProgrammaticFilterUpdate = $false
    try { $previousProgrammaticFilterUpdate = [bool]$global:ProgrammaticFilterUpdate } catch { $previousProgrammaticFilterUpdate = $false }
    $global:ProgrammaticFilterUpdate = $true
    try {
    if ($LocationEntries) {
        $global:DeviceLocationEntries = $LocationEntries
    } else {
        $existingLocations = $null
        try { $existingLocations = $global:DeviceLocationEntries } catch { $existingLocations = $null }
        $locationCount = 0
        try { $locationCount = ViewStateService\Get-SequenceCount -Value $existingLocations } catch { $locationCount = 0 }
        if ($locationCount -eq 0) {
            $derivedLocations = $null
            try { $derivedLocations = script:Get-LocationEntriesFromMetadata -Metadata $global:DeviceMetadata } catch { $derivedLocations = $null }

            if ($derivedLocations) {
                $global:DeviceLocationEntries = $derivedLocations
            } else {
                try {
                    $global:DeviceLocationEntries = DeviceCatalogModule\Get-DeviceLocationEntries
                } catch [System.Management.Automation.CommandNotFoundException] {
                } catch { }
            }
        }
    }

    $siteDD      = $Window.FindName('SiteDropdown')
    $zoneDD      = $Window.FindName('ZoneDropdown')
    $buildingDD  = $Window.FindName('BuildingDropdown')
    $roomDD      = $Window.FindName('RoomDropdown')
    $hostnameDD  = $Window.FindName('HostnameDropdown')

    $snapshot = $null
    try {
        $snapshot = ViewStateService\Get-FilterSnapshot -DeviceMetadata $global:DeviceMetadata -LocationEntries $global:DeviceLocationEntries
    } catch {
        $snapshot = $null
    }

    if ($siteDD) {
        $siteItems = [System.Collections.Generic.List[string]]::new()
        [void]$siteItems.Add('All Sites')
        if ($snapshot -and $snapshot.Sites) {
            foreach ($site in $snapshot.Sites) {
                if ([string]::IsNullOrWhiteSpace($site)) { continue }
                if (-not $siteItems.Contains($site)) { [void]$siteItems.Add($site) }
            }
        }
        if ($siteItems.Count -le 1) {
            try {
                $paths = DeviceRepositoryModule\Get-AllSiteDbPaths
                foreach ($p in $paths) {
                    try {
                        if (-not $p) { continue }
                        $leaf = [System.IO.Path]::GetFileNameWithoutExtension($p)
                        if ([string]::IsNullOrWhiteSpace($leaf)) { continue }
                        if (-not $siteItems.Contains($leaf)) { [void]$siteItems.Add($leaf) }
                    } catch {}
                }
            } catch [System.Management.Automation.CommandNotFoundException] {
            } catch {}
        }
        $siteDD.ItemsSource = $siteItems
        if (-not $global:InterfacesLoadAllowed) {
            # When interfaces are blocked, default to "All Sites" so the union of locations is visible immediately.
            $siteDD.SelectedIndex = 0
        } elseif ($siteItems.Count -gt 1) {
            $siteDD.SelectedIndex = 1
        } else {
            $siteDD.SelectedIndex = 0
        }
    }

    if ($zoneDD) {
        $zoneDD.ItemsSource = @('All Zones')
        $zoneDD.SelectedIndex = 0
        $zoneDD.IsEnabled = $true
    }

    if ($buildingDD) {
        $buildingDD.ItemsSource = @('')
        $buildingDD.SelectedIndex = 0
        $buildingDD.IsEnabled = $false
    }

    if ($roomDD) {
        $roomDD.ItemsSource = @('')
        $roomDD.SelectedIndex = 0
        $roomDD.IsEnabled = $false
    }

    if ($hostnameDD) {
        $hostList = [System.Collections.Generic.List[string]]::new()
        if ($Hostnames) {
            foreach ($raw in $Hostnames) {
                $name = '' + $raw
                if ([string]::IsNullOrWhiteSpace($name)) { continue }
                if (-not $hostList.Contains($name)) { [void]$hostList.Add($name) }
            }
        } elseif ($snapshot -and $snapshot.Hostnames) {
            foreach ($name in $snapshot.Hostnames) {
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
        Set-DropdownItems -Control $hostnameDD -Items $hostList
    }

    # Avoid hydrating interfaces during filter initialization; Update-DeviceFilter (and the Search view)
    # will populate the global interface snapshot when needed. This keeps large device sets responsive.
    $global:AllInterfaces = [System.Collections.Generic.List[object]]::new()

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
    } finally {
        $global:ProgrammaticFilterUpdate = $previousProgrammaticFilterUpdate
    }
}
function Update-DeviceFilter {
    if ($script:DeviceFilterFaulted) { return }
    $window = $global:window
    if (-not $window) { return }
    if ($script:DeviceFilterUpdating) { return }

    $filterSnapshotCmd = $null
    try { $filterSnapshotCmd = Get-Command -Name 'ViewStateService\Get-FilterSnapshot' -ErrorAction SilentlyContinue } catch { $filterSnapshotCmd = $null }
    if (-not $filterSnapshotCmd) { return }

    $interfacesAllowed = $global:InterfacesLoadAllowed

    $script:DeviceFilterUpdating = $true
    $___prevProgFlag = $global:ProgrammaticFilterUpdate
    $global:ProgrammaticFilterUpdate = $true

    try {
        $metadata = $global:DeviceMetadata
        $locationEntries = $global:DeviceLocationEntries
        $locationCount = 0
        try { $locationCount = ViewStateService\Get-SequenceCount -Value $locationEntries } catch { $locationCount = 0 }
        if ($locationCount -eq 0) {
            $derivedLocations = $null
            try { $derivedLocations = script:Get-LocationEntriesFromMetadata -Metadata $metadata } catch { $derivedLocations = $null }

            if ($derivedLocations) {
                $locationEntries = $derivedLocations
                try { $global:DeviceLocationEntries = $derivedLocations } catch { }
            } else {
                try {
                    $locationEntries = DeviceCatalogModule\Get-DeviceLocationEntries
                    $global:DeviceLocationEntries = $locationEntries
                } catch [System.Management.Automation.CommandNotFoundException] {
                } catch { }
            }
        }
        $hasMetadata = $false
        try { $hasMetadata = $metadata -ne $null -and ($metadata.Count -ge 0 -or $metadata.Keys) } catch { $hasMetadata = $false }
        $hasLocations = $false
        try { $hasLocations = (ViewStateService\Get-SequenceCount -Value $locationEntries) -ge 0 } catch { $hasLocations = $false }
        if (-not $hasMetadata -and -not $hasLocations) {
            Write-Verbose 'FilterStateModule: Device metadata unavailable; skipping device filter update.'
            return
        }

        $locInitial = Get-SelectedLocation -Window $window
        $siteInput      = if ($locInitial) { '' + $locInitial.Site } else { '' }
        $zoneInput      = if ($locInitial) { '' + $locInitial.Zone } else { '' }
        $buildingInput  = if ($locInitial) { '' + $locInitial.Building } else { '' }
        $roomInput      = if ($locInitial) { '' + $locInitial.Room } else { '' }

        $pendingRestore = $null
        try { $pendingRestore = $global:PendingFilterRestore } catch { $pendingRestore = $null }
        if ($pendingRestore) {
            try {
                $pendingSite = $null
                $pendingZone = $null
                $pendingBuilding = $null
                $pendingRoom = $null

                if ($pendingRestore -is [hashtable]) {
                    if ($pendingRestore.ContainsKey('Site')) { $pendingSite = $pendingRestore.Site }
                    if ($pendingRestore.ContainsKey('Zone')) { $pendingZone = $pendingRestore.Zone }
                    if ($pendingRestore.ContainsKey('Building')) { $pendingBuilding = $pendingRestore.Building }
                    if ($pendingRestore.ContainsKey('Room')) { $pendingRoom = $pendingRestore.Room }
                } else {
                    if ($pendingRestore.PSObject.Properties['Site']) { $pendingSite = $pendingRestore.Site }
                    if ($pendingRestore.PSObject.Properties['Zone']) { $pendingZone = $pendingRestore.Zone }
                    if ($pendingRestore.PSObject.Properties['Building']) { $pendingBuilding = $pendingRestore.Building }
                    if ($pendingRestore.PSObject.Properties['Room']) { $pendingRoom = $pendingRestore.Room }
                }

                if ($null -ne $pendingSite) { $siteInput = '' + $pendingSite }
                if ($null -ne $pendingZone) { $zoneInput = '' + $pendingZone }
                if ($null -ne $pendingBuilding) { $buildingInput = '' + $pendingBuilding }
                if ($null -ne $pendingRoom) { $roomInput = '' + $pendingRoom }

                try {
                    $diagMsg = "Update-DeviceFilter: applied PendingFilterRestore | site='{0}', zone='{1}', bld='{2}', room='{3}'" -f `
                        $siteInput, $zoneInput, $buildingInput, $roomInput
                    try { Write-Diag $diagMsg } catch [System.Management.Automation.CommandNotFoundException] { Write-Verbose $diagMsg } catch { }
                } catch { }
            } catch { }
            try { $global:PendingFilterRestore = $null } catch { }
        }

        $siteChangedCompared = ([System.StringComparer]::OrdinalIgnoreCase.Compare($siteInput, '' + $script:LastSiteSel) -ne 0)
        $zoneChangedCompared = ([System.StringComparer]::OrdinalIgnoreCase.Compare($zoneInput, '' + $script:LastZoneSel) -ne 0)
        $bldChangedCompared  = ([System.StringComparer]::OrdinalIgnoreCase.Compare($buildingInput, '' + $script:LastBuildingSel) -ne 0)
        $roomChangedCompared = ([System.StringComparer]::OrdinalIgnoreCase.Compare($roomInput, '' + $script:LastRoomSel) -ne 0)

        try {
            $diagMsg = "Update-DeviceFilter: siteSel='{0}', zoneSel='{1}', bldSel='{2}', roomSel='{3}', siteChanged={4}, zoneChanged={5}, bldChanged={6}, roomChanged={7}" -f `
                $siteInput, $zoneInput, $buildingInput, $roomInput, $siteChangedCompared, $zoneChangedCompared, $bldChangedCompared, $roomChangedCompared
            try { Write-Diag $diagMsg } catch [System.Management.Automation.CommandNotFoundException] { Write-Verbose $diagMsg } catch { }
        } catch {}

        $siteDD     = $window.FindName('SiteDropdown')
        $zoneDD     = $window.FindName('ZoneDropdown')
        $buildingDD = $window.FindName('BuildingDropdown')
        $roomDD     = $window.FindName('RoomDropdown')
        $hostnameDD = $window.FindName('HostnameDropdown')

        # If the window has not finished constructing these controls, bail out quietly.
        if (-not $siteDD -or -not $zoneDD -or -not $buildingDD -or -not $roomDD -or -not $hostnameDD) {
            Write-Verbose 'FilterStateModule: dropdown controls not available yet; skipping device filter update.' -Verbose:$true
            return
        }

        $allSnapshot = ViewStateService\Get-FilterSnapshot -DeviceMetadata $metadata -LocationEntries $locationEntries
        $siteCandidates = if ($allSnapshot -and $allSnapshot.Sites) { @($allSnapshot.Sites) } else { @() }
        $siteSelection = Resolve-SelectionValue -Current $siteInput -Candidates $siteCandidates -Sentinel 'All Sites'

        $siteItems = [System.Collections.Generic.List[string]]::new()
        $seenSites = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        [void]$siteItems.Add('All Sites')
        [void]$seenSites.Add('All Sites')
        foreach ($candidate in $siteCandidates) {
            if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
            if ($seenSites.Add($candidate)) { [void]$siteItems.Add($candidate) }
        }

        if ($siteDD) {
            $siteDD.ItemsSource = $siteItems
            if ($siteItems.Contains($siteSelection)) {
                $siteDD.SelectedItem = $siteSelection
            } else {
                $siteDD.SelectedIndex = 0
                $siteSelection = '' + $siteDD.SelectedItem
            }
        }

        $zoneSnapshot = ViewStateService\Get-FilterSnapshot -DeviceMetadata $metadata -Site $siteSelection -LocationEntries $locationEntries
        $zoneCandidates = if ($zoneSnapshot -and $zoneSnapshot.Zones) { @($zoneSnapshot.Zones) } else { @() }
        $zoneSelection = Resolve-SelectionValue -Current $zoneInput -Candidates $zoneCandidates -Sentinel 'All Zones'
        if ($interfacesAllowed -and ($siteChangedCompared -or -not $script:LastZoneSel) -and ($zoneSelection -eq 'All Zones') -and $zoneSnapshot -and $zoneSnapshot.ZoneToLoad) {
            $zoneSelection = '' + $zoneSnapshot.ZoneToLoad
        }

        $zoneItems = [System.Collections.Generic.List[string]]::new()
        $seenZones = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        [void]$zoneItems.Add('All Zones')
        [void]$seenZones.Add('All Zones')
        foreach ($candidate in $zoneCandidates) {
            if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
            if ($seenZones.Add($candidate)) { [void]$zoneItems.Add($candidate) }
        }

        if ($zoneDD) {
            $zoneDD.ItemsSource = $zoneItems
            if ($zoneItems.Contains($zoneSelection)) {
                $zoneDD.SelectedItem = $zoneSelection
            } else {
                $zoneDD.SelectedIndex = 0
                $zoneSelection = '' + $zoneDD.SelectedItem
            }
            $zoneDD.IsEnabled = $true
        }

        $buildingSnapshot = ViewStateService\Get-FilterSnapshot -DeviceMetadata $metadata -Site $siteSelection -ZoneSelection $zoneSelection -LocationEntries $locationEntries
        $buildingCandidates = if ($buildingSnapshot -and $buildingSnapshot.Buildings) { @($buildingSnapshot.Buildings) } else { @() }
        $buildingSelection = Resolve-SelectionValue -Current $buildingInput -Candidates $buildingCandidates -Sentinel ''

        $buildingItems = [System.Collections.Generic.List[string]]::new()
        $seenBuildings = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        [void]$buildingItems.Add('')
        [void]$seenBuildings.Add('')
        foreach ($candidate in $buildingCandidates) {
            if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
            if ($seenBuildings.Add($candidate)) { [void]$buildingItems.Add($candidate) }
        }

        if ($buildingDD) {
            $buildingDD.ItemsSource = $buildingItems
            if ($buildingSelection -and $buildingSelection -ne '' -and $buildingItems.Contains($buildingSelection)) {
                $buildingDD.SelectedItem = $buildingSelection
            } else {
                $buildingDD.SelectedIndex = 0
                $buildingSelection = ''
            }
            $buildingDD.IsEnabled = ($siteSelection -and $siteSelection -ne '' -and $siteSelection -ne 'All Sites')
        }

        $roomSnapshot = ViewStateService\Get-FilterSnapshot -DeviceMetadata $metadata -Site $siteSelection -ZoneSelection $zoneSelection -Building $buildingSelection -LocationEntries $locationEntries
        $roomCandidates = if ($roomSnapshot -and $roomSnapshot.Rooms) { @($roomSnapshot.Rooms) } else { @() }
        $roomSelection = Resolve-SelectionValue -Current $roomInput -Candidates $roomCandidates -Sentinel ''

        $roomItems = [System.Collections.Generic.List[string]]::new()
        $seenRooms = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        [void]$roomItems.Add('')
        [void]$seenRooms.Add('')
        foreach ($candidate in $roomCandidates) {
            if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
            if ($seenRooms.Add($candidate)) { [void]$roomItems.Add($candidate) }
        }

        if ($roomDD) {
            $roomDD.ItemsSource = $roomItems
            if ($roomSelection -and $roomSelection -ne '' -and $roomItems.Contains($roomSelection)) {
                $roomDD.SelectedItem = $roomSelection
            } else {
                $roomDD.SelectedIndex = 0
                $roomSelection = ''
            }
            $roomDD.IsEnabled = ($buildingSelection -and $buildingSelection -ne '')
        }

        $finalSnapshot = ViewStateService\Get-FilterSnapshot -DeviceMetadata $metadata -Site $siteSelection -ZoneSelection $zoneSelection -Building $buildingSelection -Room $roomSelection -LocationEntries $locationEntries
        $hostCandidates = if ($finalSnapshot -and $finalSnapshot.Hostnames) { @($finalSnapshot.Hostnames) } else { @() }
        $hostCount = 0
        try {
            $hostCount = ViewStateService\Get-SequenceCount -Value $hostCandidates
        } catch { $hostCount = 0 }

        $previousHostnameSelection = ''
        try {
            if ($hostnameDD -and $hostnameDD.SelectedItem) {
                $previousHostnameSelection = '' + $hostnameDD.SelectedItem
            }
        } catch {
            $previousHostnameSelection = ''
        }

        $targetHostnameSelection = ''
        if ($hostCount -gt 0 -and -not [string]::IsNullOrWhiteSpace($previousHostnameSelection)) {
            foreach ($candidate in $hostCandidates) {
                $candidateText = if ($null -ne $candidate) { '' + $candidate } else { '' }
                if ([System.StringComparer]::OrdinalIgnoreCase.Equals($candidateText, $previousHostnameSelection)) {
                    $targetHostnameSelection = $candidateText
                    break
                }
            }
        }

        if ([string]::IsNullOrWhiteSpace($targetHostnameSelection)) {
            if ($hostCount -gt 0) {
                try { $targetHostnameSelection = '' + ($hostCandidates | Select-Object -First 1) } catch { $targetHostnameSelection = '' }
            } else {
                $targetHostnameSelection = ''
            }
        }

        $hostnameSelectionChanged = $false
        if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals($targetHostnameSelection, $previousHostnameSelection)) {
            $hostnameSelectionChanged = $true
        }

        if ($hostnameDD) {
            $previousProgrammaticHostnameUpdate = $false
            try { $previousProgrammaticHostnameUpdate = [bool]$global:ProgrammaticHostnameUpdate } catch { $previousProgrammaticHostnameUpdate = $false }
            $global:ProgrammaticHostnameUpdate = $true
            try {
                if ($hostCount -eq 0) {
                    $hostnameDD.ItemsSource = @('')
                    $hostnameDD.SelectedIndex = 0
                } else {
                    $hostnameDD.ItemsSource = @($hostCandidates)
                    if (-not [string]::IsNullOrWhiteSpace($targetHostnameSelection)) {
                        $hostnameDD.SelectedItem = $targetHostnameSelection
                    } else {
                        $hostnameDD.SelectedIndex = 0
                    }
                }
            } finally {
                $global:ProgrammaticHostnameUpdate = $previousProgrammaticHostnameUpdate
            }
        }

        try {
            $sampleList = if ($hostCount -gt 0) { (@($hostCandidates) | Select-Object -First ([System.Math]::Min(3, $hostCount))) -join ', ' } else { '' }
            $diagMsgHosts = "HostFilter | site='{0}', zone='{1}', building='{2}', room='{3}', count={4}, examples=[{5}]" -f `
                $siteSelection, $zoneSelection, $buildingSelection, $roomSelection, $hostCount, $sampleList
            try { Write-Diag $diagMsgHosts } catch [System.Management.Automation.CommandNotFoundException] { Write-Verbose $diagMsgHosts } catch { }
        } catch {}

        $finalSite      = $siteSelection
        $finalZone      = $zoneSelection
        $finalBuilding  = $buildingSelection
        $finalRoom      = $roomSelection

        $siteChanged      = ([System.StringComparer]::OrdinalIgnoreCase.Compare($finalSite, '' + $script:LastSiteSel) -ne 0)
        $zoneChanged      = ([System.StringComparer]::OrdinalIgnoreCase.Compare($finalZone, '' + $script:LastZoneSel) -ne 0)
        $buildingChanged  = ([System.StringComparer]::OrdinalIgnoreCase.Compare($finalBuilding, '' + $script:LastBuildingSel) -ne 0)
        $roomChanged      = ([System.StringComparer]::OrdinalIgnoreCase.Compare($finalRoom, '' + $script:LastRoomSel) -ne 0)

        $zoneToLoad = ''
        if ($finalZone -and $finalZone -ne '' -and $finalZone -ne 'All Zones') {
            $zoneToLoad = $finalZone
        } elseif ($finalSnapshot -and $finalSnapshot.ZoneToLoad) {
            $zoneToLoad = '' + $finalSnapshot.ZoneToLoad
        }

        $summaryVisible = $false
        $searchVisible = $false
        $alertsVisible = $false
        $visibilityProbeSucceeded = $false
        try {
            $summaryHost = $window.FindName('SummaryHost')
            if ($summaryHost) {
                $visibilityProbeSucceeded = $true
                if ($summaryHost.IsVisible) { $summaryVisible = $true }
            }
        } catch { }
        try {
            $searchHost = $window.FindName('SearchInterfacesHost')
            if ($searchHost) {
                $visibilityProbeSucceeded = $true
                if ($searchHost.IsVisible) { $searchVisible = $true }
            }
        } catch { }
        try {
            $alertsHost = $window.FindName('AlertsHost')
            if ($alertsHost) {
                $visibilityProbeSucceeded = $true
                if ($alertsHost.IsVisible) { $alertsVisible = $true }
            }
        } catch { }

        $filtersChanged = ($siteChanged -or $zoneChanged -or $buildingChanged -or $roomChanged)
        $refreshInterfacesForViews = $true
        if ($visibilityProbeSucceeded) {
            $refreshInterfacesForViews = ($summaryVisible -or $searchVisible -or $alertsVisible)
        }

        if ($interfacesAllowed -and $filtersChanged) {
            if (-not $refreshInterfacesForViews) {
                # Defer expensive interface snapshot work until a tab that consumes it is visible.
                # Clear any previously-loaded snapshot so Summary/Search/Alerts lazily reload for the new context.
                $global:AllInterfaces = [System.Collections.Generic.List[object]]::new()
            } else {
                try {
                    $refreshStopwatch = $null
                    try { $refreshStopwatch = [System.Diagnostics.Stopwatch]::StartNew() } catch { $refreshStopwatch = $null }
                    $global:AllInterfaces = ViewStateService\Get-InterfacesForContext -Site $finalSite -ZoneSelection $finalZone -ZoneToLoad $zoneToLoad -Building $finalBuilding -Room $finalRoom
                    $refreshDurationMs = 0.0
                    if ($refreshStopwatch) {
                        try { $refreshStopwatch.Stop() } catch { }
                        try { $refreshDurationMs = [math]::Round($refreshStopwatch.Elapsed.TotalMilliseconds, 3) } catch { $refreshDurationMs = 0.0 }
                    }
                    if (-not $global:AllInterfaces) {
                        $global:AllInterfaces = [System.Collections.Generic.List[object]]::new()
                    }

                    try {
                        $ifaceCount = 0
                        try { $ifaceCount = ViewStateService\Get-SequenceCount -Value $global:AllInterfaces } catch { $ifaceCount = 0 }
                        $diagRefresh = "Update-DeviceFilter refreshed interfaces | DurationMs={0} | Interfaces={1}" -f $refreshDurationMs, $ifaceCount
                        try { Write-Diag $diagRefresh } catch [System.Management.Automation.CommandNotFoundException] { Write-Verbose $diagRefresh } catch { }
                    } catch { }
                } catch {
                    $global:AllInterfaces = [System.Collections.Generic.List[object]]::new()
                }
            }
        } elseif (-not $interfacesAllowed) {
            $global:AllInterfaces = [System.Collections.Generic.List[object]]::new()
        }

        # Only refresh views that are currently visible. This avoids reprocessing large interface
        # snapshots when the user is focused on a different tab.
        if ($interfacesAllowed -and $searchVisible) {
            try { Update-SearchGrid } catch [System.Management.Automation.CommandNotFoundException] { }
        }

        $canUpdateSummary = $false
        if ($interfacesAllowed -and $summaryVisible) {
            try {
                $summaryVar = Get-Variable -Name summaryView -Scope Global -ErrorAction Stop
                if ($summaryVar.Value) { $canUpdateSummary = $true }
            } catch { $canUpdateSummary = $false }
        }
        if ($canUpdateSummary) {
            try { Update-Summary } catch [System.Management.Automation.CommandNotFoundException] { }
        }

        if ($interfacesAllowed -and $alertsVisible) {
            try { Update-Alerts } catch [System.Management.Automation.CommandNotFoundException] { }
        }

        if ($interfacesAllowed -and $hostnameSelectionChanged) {
            $hostnameChangeCmd = $null
            try { $hostnameChangeCmd = Get-Command -Name 'Get-HostnameChanged' -ErrorAction SilentlyContinue } catch { $hostnameChangeCmd = $null }
            if ($hostnameChangeCmd) {
                try { & $hostnameChangeCmd -Hostname $targetHostnameSelection } catch { }
            }
        }

        $script:LastSiteSel     = $finalSite
        $script:LastZoneSel     = $finalZone
        $script:LastBuildingSel = $finalBuilding
        try { $script:LastRoomSel = $finalRoom } catch {}
    } catch {
        Set-FilterFaulted -Faulted $true
        throw
    } finally {
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

Export-ModuleMember -Function Get-SelectedLocation, Get-LastLocation, Set-DropdownItems, Initialize-DeviceFilters, Update-DeviceFilter, Set-FilterFaulted, Get-FilterFaulted
