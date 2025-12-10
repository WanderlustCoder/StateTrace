Set-StrictMode -Version Latest

try { ViewStateService\Import-ViewStateServiceModule | Out-Null } catch { }
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

    $interfaces = ViewStateService\Get-InterfacesForContext -Site $siteSel -ZoneSelection $zoneSel -ZoneToLoad $zoneSel -Building $bldSel -Room $roomSel
    $results   = [System.Collections.Generic.List[object]]::new()
    $termEmpty = [string]::IsNullOrWhiteSpace($Term)

    foreach ($row in $interfaces) {
        if (-not $row) { continue }

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


    $loc = $null
    try { $loc = FilterStateModule\Get-SelectedLocation } catch { $loc = $null }
    $siteSel = if ($loc) { $loc.Site } else { $null }
    $zoneSel = if ($loc) { $loc.Zone } else { $null }
    $bldSel  = if ($loc) { $loc.Building } else { $null }
    $roomSel = if ($loc) { $loc.Room } else { $null }

    $zoneToLoad = ''
    if ($zoneSel -and $zoneSel -ne '' -and $zoneSel -ne 'All Zones') {
        $zoneToLoad = $zoneSel
    }

    if ($siteSel -and $siteSel -ne '' -and $siteSel -ne 'All Sites') {
        try { DeviceRepositoryModule\Update-SiteZoneCache -Site $siteSel -Zone $zoneToLoad | Out-Null } catch {}
    }

    $interfaces = ViewStateService\Get-InterfacesForContext -Site $siteSel -ZoneSelection $zoneSel -ZoneToLoad $zoneToLoad -Building $bldSel -Room $roomSel
    try {
        $locSite = if ($siteSel) { '' + $siteSel } else { '' }
        $locZone = if ($zoneSel) { '' + $zoneSel } else { '' }
        $locBuilding = if ($bldSel) { '' + $bldSel } else { '' }
        $locRoom = if ($roomSel) { '' + $roomSel } else { '' }
        $locText = ("Site={0};Zone={1};Building={2};Room={3}" -f $locSite, $locZone, $locBuilding, $locRoom)
        $ifaceCount = ViewStateService\Get-SequenceCount -Value $interfaces
        Write-Diag ("Update-Summary context | Location={0} | InterfaceCount={1}" -f $locText, $ifaceCount)
    } catch {}
    if (-not $interfaces) { $interfaces = @() }

    foreach ($row in $interfaces) {
        if (-not $row) { continue }
        try {
            if (Get-Command -Name 'DeviceRepositoryModule\Ensure-PortRowDefaults' -ErrorAction SilentlyContinue) {
                DeviceRepositoryModule\Ensure-PortRowDefaults -Row $row -Hostname ('' + $row.Hostname)
            } else {
                if (-not $row.PSObject.Properties['Hostname']) {
                    $row | Add-Member -NotePropertyName Hostname -NotePropertyValue ('' + $row.Hostname) -ErrorAction SilentlyContinue
                }
                if (-not $row.PSObject.Properties['IsSelected']) {
                    $row | Add-Member -NotePropertyName IsSelected -NotePropertyValue $false -ErrorAction SilentlyContinue
                }
            }
        } catch {}
    }

    $global:AllInterfaces = $interfaces

    $deviceSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $interfaces) {
        if ($row -and $row.PSObject.Properties['Hostname']) {
            $hostname = '' + $row.Hostname
            if (-not [string]::IsNullOrWhiteSpace($hostname)) { [void]$deviceSet.Add($hostname) }
        }
    }

    $devCount = $deviceSet.Count
    $intCount = $interfaces.Count
    $upCount = 0; $downCount = 0; $authCount = 0; $unauthCount = 0
    $vlans = [System.Collections.Generic.List[string]]::new()
    foreach ($row in $interfaces) {
        if (-not $row) { continue }
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

    $summaryVar = $null
    try {
        $summaryVar = Get-Variable -Name summaryView -Scope Global -ErrorAction Stop
    } catch {
        try { Write-Diag ("Update-Summary skipped | Reason=SummaryViewMissing") } catch {}
        return
    }

    $sv = $summaryVar.Value
    if (-not $sv) { return }

    try {
        ($sv.FindName("SummaryDevicesCount")).Text      = $devCount.ToString()
        ($sv.FindName("SummaryInterfacesCount")).Text   = $intCount.ToString()
        ($sv.FindName("SummaryUpCount")).Text           = $upCount.ToString()
        ($sv.FindName("SummaryDownCount")).Text         = $downCount.ToString()
        ($sv.FindName("SummaryAuthorizedCount")).Text   = $authCount.ToString()
        ($sv.FindName("SummaryUnauthorizedCount")).Text = $unauthCount.ToString()
        ($sv.FindName("SummaryUniqueVlansCount")).Text  = $uniqueCount.ToString()
        $ratio = if ($intCount -gt 0) { [math]::Round(($upCount / $intCount) * 100, 1) } else { 0 }
        ($sv.FindName("SummaryExtra")).Text = "Up %: $ratio%"
        Write-Host "[Update-Summary] Devices=$devCount, Interfaces=$intCount, Up=$upCount, Down=$downCount, Auth=$authCount, Unauth=$unauthCount, UniqueVlans=$uniqueCount, Up%=$ratio%"
        try { Write-Diag ("Update-Summary metrics | Devices={0} | Interfaces={1} | Up={2} | Down={3} | Auth={4} | Unauth={5} | UniqueVlans={6} | UpPct={7}" -f $devCount, $intCount, $upCount, $downCount, $authCount, $unauthCount, $uniqueCount, $ratio) } catch {}
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

    $zoneToLoad = ''
    if ($zoneSel -and $zoneSel -ne '' -and $zoneSel -ne 'All Zones') {
        $zoneToLoad = $zoneSel
    }

    if ($siteSel -and $siteSel -ne '' -and $siteSel -ne 'All Sites') {
        try { DeviceRepositoryModule\Update-SiteZoneCache -Site $siteSel -Zone $zoneToLoad | Out-Null } catch {}
    }

    $interfaces = ViewStateService\Get-InterfacesForContext -Site $siteSel -ZoneSelection $zoneSel -ZoneToLoad $zoneToLoad -Building $bldSel -Room $roomSel
    if (-not $interfaces) { $interfaces = @() }

        $alerts = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $interfaces) {
        if (-not $row) { continue }

        $reasons = [System.Collections.Generic.List[string]]::new()
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
    $results = Update-SearchResults -Term $term
    $resultList = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $results) {
        if ($item) { [void]$resultList.Add($item) }
    }
    try {
        $resCount = $resultList.Count
        $null = $resCount
    } catch {}

    $gridCtrl.ItemsSource = $resultList
}

Export-ModuleMember -Function Update-SearchResults, Update-Summary, Update-Alerts, Update-SearchGrid, Get-SearchRegexEnabled, Set-SearchRegexEnabled
