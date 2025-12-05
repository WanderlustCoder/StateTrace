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

function Initialize-DeviceFilters {
    [CmdletBinding()]
    param(
        [object[]]$Hostnames,
        [object]$Window = $global:window
    )

    if (-not $Window) { return }

    $siteDD      = $Window.FindName('SiteDropdown')
    $zoneDD      = $Window.FindName('ZoneDropdown')
    $buildingDD  = $Window.FindName('BuildingDropdown')
    $roomDD      = $Window.FindName('RoomDropdown')
    $hostnameDD  = $Window.FindName('HostnameDropdown')

    $snapshot = $null
    try {
        $snapshot = ViewStateService\Get-FilterSnapshot -DeviceMetadata $global:DeviceMetadata
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
        $siteDD.ItemsSource = $siteItems
        if ($siteItems.Count -gt 1) {
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
        $hostList = New-Object 'System.Collections.Generic.List[string]'
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

    try {
        $global:AllInterfaces = ViewStateService\Get-InterfacesForContext -Site $null -ZoneSelection $null -ZoneToLoad $null -Building $null -Room $null
        if (-not $global:AllInterfaces) {
            $global:AllInterfaces = [System.Collections.Generic.List[object]]::new()
        }
    } catch {
        $global:AllInterfaces = [System.Collections.Generic.List[object]]::new()
    }

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
    if ($script:DeviceFilterFaulted) { return }
    $window = $global:window
    if (-not $window) { return }
    if ($script:DeviceFilterUpdating) { return }
    if (-not (Get-Command -Name 'ViewStateService\Get-FilterSnapshot' -ErrorAction SilentlyContinue)) { return }

    $script:DeviceFilterUpdating = $true
    $___prevProgFlag = $global:ProgrammaticFilterUpdate
    $global:ProgrammaticFilterUpdate = $true

    try {
        if (-not $global:DeviceMetadata) {
            Write-Verbose 'FilterStateModule: DeviceMetadata not yet loaded; skipping device filter update.'
            return
        }

        $locInitial = Get-SelectedLocation -Window $window
        $siteInput      = if ($locInitial) { '' + $locInitial.Site } else { '' }
        $zoneInput      = if ($locInitial) { '' + $locInitial.Zone } else { '' }
        $buildingInput  = if ($locInitial) { '' + $locInitial.Building } else { '' }
        $roomInput      = if ($locInitial) { '' + $locInitial.Room } else { '' }

        $siteChangedCompared = ([System.StringComparer]::OrdinalIgnoreCase.Compare($siteInput, '' + $script:LastSiteSel) -ne 0)
        $zoneChangedCompared = ([System.StringComparer]::OrdinalIgnoreCase.Compare($zoneInput, '' + $script:LastZoneSel) -ne 0)
        $bldChangedCompared  = ([System.StringComparer]::OrdinalIgnoreCase.Compare($buildingInput, '' + $script:LastBuildingSel) -ne 0)
        $roomChangedCompared = ([System.StringComparer]::OrdinalIgnoreCase.Compare($roomInput, '' + $script:LastRoomSel) -ne 0)

        try {
            $diagMsg = "Update-DeviceFilter: siteSel='{0}', zoneSel='{1}', bldSel='{2}', roomSel='{3}', siteChanged={4}, zoneChanged={5}, bldChanged={6}, roomChanged={7}" -f `
                $siteInput, $zoneInput, $buildingInput, $roomInput, $siteChangedCompared, $zoneChangedCompared, $bldChangedCompared, $roomChangedCompared
            if (Get-Command -Name Write-Diag -ErrorAction SilentlyContinue) {
                Write-Diag $diagMsg
            } else {
                Write-Verbose $diagMsg
            }
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

        $metadata = $global:DeviceMetadata

        $allSnapshot = ViewStateService\Get-FilterSnapshot -DeviceMetadata $metadata
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

        $zoneSnapshot = ViewStateService\Get-FilterSnapshot -DeviceMetadata $metadata -Site $siteSelection
        $zoneCandidates = if ($zoneSnapshot -and $zoneSnapshot.Zones) { @($zoneSnapshot.Zones) } else { @() }
        $zoneSelection = Resolve-SelectionValue -Current $zoneInput -Candidates $zoneCandidates -Sentinel 'All Zones'
        if (($siteChangedCompared -or -not $script:LastZoneSel) -and ($zoneSelection -eq 'All Zones') -and $zoneSnapshot -and $zoneSnapshot.ZoneToLoad) {
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

        $buildingSnapshot = ViewStateService\Get-FilterSnapshot -DeviceMetadata $metadata -Site $siteSelection -ZoneSelection $zoneSelection
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

        $roomSnapshot = ViewStateService\Get-FilterSnapshot -DeviceMetadata $metadata -Site $siteSelection -ZoneSelection $zoneSelection -Building $buildingSelection
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

        $finalSnapshot = ViewStateService\Get-FilterSnapshot -DeviceMetadata $metadata -Site $siteSelection -ZoneSelection $zoneSelection -Building $buildingSelection -Room $roomSelection
        $hostCandidates = if ($finalSnapshot -and $finalSnapshot.Hostnames) { @($finalSnapshot.Hostnames) } else { @() }
        $hostCount = 0
        try {
            $hostCount = ViewStateService\Get-SequenceCount -Value $hostCandidates
        } catch { $hostCount = 0 }

        if ($hostnameDD) {
            if ($hostCount -eq 0) {
                Set-DropdownItems -Control $hostnameDD -Items @('')
            } else {
                Set-DropdownItems -Control $hostnameDD -Items $hostCandidates
            }
        }

        try {
            $sampleList = if ($hostCount -gt 0) { (@($hostCandidates) | Select-Object -First ([System.Math]::Min(3, $hostCount))) -join ', ' } else { '' }
            $diagMsgHosts = "HostFilter | site='{0}', zone='{1}', building='{2}', room='{3}', count={4}, examples=[{5}]" -f `
                $siteSelection, $zoneSelection, $buildingSelection, $roomSelection, $hostCount, $sampleList
            if (Get-Command -Name Write-Diag -ErrorAction SilentlyContinue) {
                Write-Diag $diagMsgHosts
            } else {
                Write-Verbose $diagMsgHosts
            }
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

        if ($siteChanged -or $zoneChanged -or $buildingChanged -or $roomChanged) {
            try {
                $global:AllInterfaces = ViewStateService\Get-InterfacesForContext -Site $finalSite -ZoneSelection $finalZone -ZoneToLoad $zoneToLoad -Building $finalBuilding -Room $finalRoom
                if (-not $global:AllInterfaces) {
                    $global:AllInterfaces = [System.Collections.Generic.List[object]]::new()
                }
            } catch {
                $global:AllInterfaces = [System.Collections.Generic.List[object]]::new()
            }
        }
        if (Get-Command Update-SearchGrid -ErrorAction SilentlyContinue) {
            Update-SearchGrid
        }
        $canUpdateSummary = $false
        if (Get-Command Update-Summary -ErrorAction SilentlyContinue) {
            try {
                $summaryVar = Get-Variable -Name summaryView -Scope Global -ErrorAction Stop
                if ($summaryVar.Value) { $canUpdateSummary = $true }
            } catch { $canUpdateSummary = $false }
        }
        if ($canUpdateSummary) {
            Update-Summary
        }
        if (Get-Command Update-Alerts -ErrorAction SilentlyContinue) {
            Update-Alerts
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

Export-ModuleMember -Function Test-StringListEqualCI, Get-SelectedLocation, Get-LastLocation, Set-DropdownItems, Initialize-DeviceFilters, Update-DeviceFilter, Set-FilterFaulted, Get-FilterFaulted
