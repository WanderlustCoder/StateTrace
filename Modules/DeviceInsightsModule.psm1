Set-StrictMode -Version Latest

if (-not (Get-Variable -Scope Script -Name SearchRegexEnabled -ErrorAction SilentlyContinue)) {
    $script:SearchRegexEnabled = $false
}

function Get-SearchRegexEnabled {
    [CmdletBinding()]
    param()

    return [bool]$script:SearchRegexEnabled
}

function Set-SearchRegexEnabled {
    [CmdletBinding()]
    param([Parameter(Mandatory)][bool]$Enabled)

    $script:SearchRegexEnabled = [bool]$Enabled
}

function Update-SearchResults {
    [CmdletBinding()]
    param([string]$Term)

    $loc = $null
    try { $loc = FilterStateModule\Get-SelectedLocation } catch { $loc = $null }
    $siteSel = if ($loc) { $loc.Site } else { $null }
    $zoneSel = if ($loc) { $loc.Zone } else { $null }
    $bldSel  = if ($loc) { $loc.Building } else { $null }
    $roomSel = if ($loc) { $loc.Room } else { $null }

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

    $results   = New-Object 'System.Collections.Generic.List[object]'
    $termEmpty = [string]::IsNullOrWhiteSpace($Term)
    foreach ($row in $global:AllInterfaces) {
        if (-not $row) { continue }

        $rowSite     = '' + $row.Site
        $rowBuilding = '' + $row.Building
        $rowRoom     = '' + $row.Room
        $rowZone     = ''
        if ($row.PSObject.Properties['Zone']) { $rowZone = '' + $row.Zone }

        if ($siteSel -and $siteSel -ne '' -and $siteSel -ne 'All Sites' -and ($rowSite -ne $siteSel)) { continue }
        if ($zoneSel -and $zoneSel -ne '' -and $zoneSel -ne 'All Zones' -and ($rowZone -ne $zoneSel)) { continue }
        if ($bldSel  -and $bldSel  -ne '' -and ($rowBuilding -ne $bldSel))  { continue }
        if ($roomSel -and $roomSel -ne '' -and ($rowRoom     -ne $roomSel)) { continue }

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

        if ($authFilterVal -ne 'All') {
            $as = '' + $row.AuthState
            if ($authFilterVal -eq 'Authorized') {
                if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals($as, 'authorized')) { continue }
            } elseif ($authFilterVal -eq 'Unauthorized') {
                if ([System.StringComparer]::OrdinalIgnoreCase.Equals($as, 'authorized')) { continue }
            }
        }

        if (-not $termEmpty) {
            if ($script:SearchRegexEnabled) {
                $matched = $false
                try {
                    if ( ('' + $row.Port) -match $Term -or
                         ('' + $row.Name) -match $Term -or
                         ('' + $row.LearnedMACs) -match $Term -or
                         ('' + $row.AuthClientMAC) -match $Term ) {
                        $matched = $true
                    }
                } catch {}
                if (-not $matched) {
                    $q = $Term
                    if (-not ((('' + $row.Port).IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                              (('' + $row.Name).IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                              (('' + $row.LearnedMACs).IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                              (('' + $row.AuthClientMAC).IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0))) {
                        continue
                    }
                }
            } else {
                $q = $Term
                if (-not ((('' + $row.Port).IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                          (('' + $row.Name).IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                          (('' + $row.LearnedMACs).IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                          (('' + $row.AuthClientMAC).IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0))) {
                    continue
                }
            }
        }

        [void]$results.Add($row)
    }

    return ,$results
}

function Update-Summary {
    [CmdletBinding()]
    param()

    if (-not $global:summaryView) { return }

    $loc = $null
    try { $loc = FilterStateModule\Get-SelectedLocation } catch { $loc = $null }
    $siteSel = if ($loc) { $loc.Site } else { $null }
    $zoneSel = if ($loc) { $loc.Zone } else { $null }
    $bldSel  = if ($loc) { $loc.Building } else { $null }
    $roomSel = if ($loc) { $loc.Room } else { $null }

    $devKeys = if ($global:DeviceMetadata) { $global:DeviceMetadata.Keys } else { @() }
    $filteredDevices = [System.Collections.Generic.List[string]]::new()
    foreach ($k in $devKeys) {
        $meta = $global:DeviceMetadata[$k]
        if (-not $meta) { continue }
        if ($siteSel -and $siteSel -ne '' -and $siteSel -ne 'All Sites' -and ($meta.Site -ne $siteSel)) { continue }
        if ($zoneSel -and $zoneSel -ne '' -and $zoneSel -ne 'All Zones') {
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

    foreach ($d in $filteredDevices) {
        try {
            if (-not $global:DeviceInterfaceCache -or -not $global:DeviceInterfaceCache.ContainsKey($d)) {
                DeviceRepositoryModule\Get-InterfaceInfo -Hostname $d | Out-Null
                Write-Host ("[Update-Summary] Loaded interface info for {0}" -f $d)
            }
        } catch {
            $msg = $_.Exception.Message
            Write-Host ("[Update-Summary] Failed to load interface info for {0}: {1}" -f $d, $msg)
        }
    }

    $interfaces = [System.Collections.Generic.List[object]]::new()
    if ($siteSel -and $siteSel -ne '' -and $siteSel -ne 'All Sites') {
        $zoneToLoad = $zoneSel
        if (-not $zoneToLoad -or $zoneToLoad -eq '' -or $zoneToLoad -eq 'All Zones') {
            $zList = @()
            try { $zList = @($filteredDevices | ForEach-Object { ($_ -split '-')[1] } | Sort-Object -Unique) } catch {}
            if ($zList.Count -gt 0) { $zoneToLoad = $zList[0] }
        }
        try { DeviceRepositoryModule\Update-SiteZoneCache -Site $siteSel -Zone $zoneToLoad | Out-Null } catch {}
        foreach ($kv in $global:DeviceInterfaceCache.GetEnumerator()) {
            $hn = $kv.Key
            $parts = ('' + $hn) -split '-'
            $sitePart = if ($parts.Length -ge 1) { $parts[0] } else { '' }
            $zonePart = if ($parts.Length -ge 2) { $parts[1] } else { '' }
            if ($sitePart -ne $siteSel) { continue }
            if ($zoneSel -and $zoneSel -ne '' -and $zoneSel -ne 'All Zones') {
                if ($zonePart -ne $zoneSel) { continue }
            } elseif ($zoneToLoad -and $zoneToLoad -ne '') {
                if ($zonePart -ne $zoneToLoad) { continue }
            }
            foreach ($row in $kv.Value) { [void]$interfaces.Add($row) }
        }
    } else {
        foreach ($kv in $global:DeviceInterfaceCache.GetEnumerator()) {
            foreach ($row in $kv.Value) { [void]$interfaces.Add($row) }
        }
    }

    foreach ($row in $interfaces) {
        if (-not $row) { continue }
        try {
            if (-not $row.PSObject.Properties['Hostname']) {
                $row | Add-Member -NotePropertyName Hostname -NotePropertyValue ('' + $row.Hostname) -ErrorAction SilentlyContinue
            }
        } catch {}
        try {
            if (-not $row.PSObject.Properties['IsSelected']) {
                $row | Add-Member -NotePropertyName IsSelected -NotePropertyValue $false -ErrorAction SilentlyContinue
            }
        } catch {}
    }

    $global:AllInterfaces = $interfaces

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

    $devCount = $filteredDevices.Count
    $intCount = $filteredRows.Count
    $upCount = 0; $downCount = 0; $authCount = 0; $unauthCount = 0
    $vlans = [System.Collections.Generic.List[string]]::new()
    foreach ($row in $filteredRows) {
        $status = '' + $row.Status
        if ($status) {
            switch -Regex ($status) {
                '(?i)^(up|connected)$'    { $upCount++; break }
                '(?i)^(down|notconnect)$' { $downCount++; break }
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

    $vlanSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($v in $vlans) {
        if (-not [string]::IsNullOrWhiteSpace($v)) { [void]$vlanSet.Add($v) }
    }
    $uniqueVlans = [System.Collections.Generic.List[string]]::new($vlanSet)
    $uniqueVlans.Sort([System.StringComparer]::OrdinalIgnoreCase)
    $uniqueCount = $uniqueVlans.Count

    try {
        $sv = $global:summaryView
        if ($sv) {
            ($sv.FindName('SummaryDevicesCount')).Text      = $devCount.ToString()
            ($sv.FindName('SummaryInterfacesCount')).Text   = $intCount.ToString()
            ($sv.FindName('SummaryUpCount')).Text           = $upCount.ToString()
            ($sv.FindName('SummaryDownCount')).Text         = $downCount.ToString()
            ($sv.FindName('SummaryAuthorizedCount')).Text   = $authCount.ToString()
            ($sv.FindName('SummaryUnauthorizedCount')).Text = $unauthCount.ToString()
            ($sv.FindName('SummaryUniqueVlansCount')).Text  = $uniqueCount.ToString()
            $ratio = if ($intCount -gt 0) { [math]::Round(($upCount / $intCount) * 100, 1) } else { 0 }
            ($sv.FindName('SummaryExtra')).Text = "Up %: $ratio%"
            Write-Host "[Update-Summary] Devices=$devCount, Interfaces=$intCount, Up=$upCount, Down=$downCount, Auth=$authCount, Unauth=$unauthCount, UniqueVlans=$uniqueCount, Up%=$ratio%"
        }
    } catch {}
}

function Update-Alerts {
    [CmdletBinding()]
    param()

    $loc = $null
    try { $loc = FilterStateModule\Get-SelectedLocation } catch { $loc = $null }
    $siteSel = if ($loc) { $loc.Site } else { $null }
    $zoneSel = if ($loc) { $loc.Zone } else { $null }
    $bldSel  = if ($loc) { $loc.Building } else { $null }
    $roomSel = if ($loc) { $loc.Room } else { $null }

    $alerts = New-Object 'System.Collections.Generic.List[object]'
    foreach ($row in $global:AllInterfaces) {
        if (-not $row) { continue }
        $rowSite     = '' + $row.Site
        $rowBuilding = '' + $row.Building
        $rowRoom     = '' + $row.Room
        $rowZone     = ''
        if ($row.PSObject.Properties['Zone']) { $rowZone = '' + $row.Zone }
        if ($siteSel -and $siteSel -ne '' -and $siteSel -ne 'All Sites' -and ($rowSite -ne $siteSel)) { continue }
        if ($zoneSel -and $zoneSel -ne '' -and $zoneSel -ne 'All Zones' -and ($rowZone -ne $zoneSel)) { continue }
        if ($bldSel  -and $bldSel  -ne '' -and ($rowBuilding -ne $bldSel)) { continue }
        if ($roomSel -and $roomSel -ne '' -and ($rowRoom     -ne $roomSel)) { continue }

        $reasons = New-Object 'System.Collections.Generic.List[string]'
        $status = '' + $row.Status
        if ($status) {
            if ([System.StringComparer]::OrdinalIgnoreCase.Equals($status, 'down') -or
                [System.StringComparer]::OrdinalIgnoreCase.Equals($status, 'notconnect')) {
                [void]$reasons.Add('Port down')
            }
        }
        $duplex = '' + $row.Duplex
        if ($duplex -and ($duplex -match '(?i)half')) {
            [void]$reasons.Add('Half duplex')
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
    if ($global:alertsView) {
        try {
            $grid = $global:alertsView.FindName('AlertsGrid')
            if ($grid) { $grid.ItemsSource = $global:AlertsList }
        } catch {}
    }
}

function Update-SearchGrid {
    [CmdletBinding()]
    param()

    $searchHostCtrl = $global:window.FindName('SearchInterfacesHost')
    if (-not $searchHostCtrl) { return }
    $view = $searchHostCtrl.Content
    if (-not $view) { return }
    $gridCtrl = $view.FindName('SearchInterfacesGrid')
    $boxCtrl  = $view.FindName('SearchBox')
    if (-not $gridCtrl -or -not $boxCtrl) { return }

    $term = $boxCtrl.Text
    try {
        if (-not $global:AllInterfaces -or $global:AllInterfaces.Count -eq 0) {
            DeviceRepositoryModule\Update-GlobalInterfaceList
        }
    } catch {}

    $results = Update-SearchResults -Term $term
    try {
        $resCount = if ($results) { $results.Count } else { 0 }
        $null = $resCount
    } catch {}

    $gridCtrl.ItemsSource = $results
}

Export-ModuleMember -Function Update-SearchResults, Update-Summary, Update-Alerts, Update-SearchGrid, Get-SearchRegexEnabled, Set-SearchRegexEnabled
