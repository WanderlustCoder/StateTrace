<#
    DeviceFunctionsModule.psm1

    This module encapsulates device-centric helper functions that were
    previously defined in MainWindow.ps1.  By moving these helpers into
    a separate module we reduce the size of MainWindow.ps1 and make it
    easier to maintain.  These functions rely on several global variables
    established in MainWindow.ps1, including:

      * $window           - the top-level WPF Window
      * $scriptDir        - the directory of the MainWindow.ps1 script
      * $global:StateTraceDb - the path/handle to the database
      * $global:DeviceMetadata - dictionary of hostname → site/building/room
      * $global:interfacesView - the Interfaces tab view control

    All functions defined here are exported so they can be invoked
    directly by the main script once this module is imported with
    `-Global`.
#>

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
            Write-Host "[DEBUG] Loaded $($names.Count) device(s) from DB" -ForegroundColor DarkGray
        } catch {
            Write-Warning "Failed to query device summaries from database: $($_.Exception.Message)"
        }
    } else {
        Write-Warning "Database not configured. Device list will be empty."
    }

    # Update the host dropdown and location filters based on the loaded device metadata.
    $hostnameDD = $window.FindName('HostnameDropdown')
    $hostnameDD.ItemsSource = $names
    # Safely select the first hostname via SelectedIndex; avoid SelectedItem exceptions
    if ($names -and $names.Count -gt 0) {
        try { $hostnameDD.SelectedIndex = 0 } catch { $null = $null }
    } else {
        try { $hostnameDD.SelectedIndex = -1 } catch { $null = $null }
    }

    $siteDD = $window.FindName('SiteDropdown')
    $uniqueSites = @()
    if ($DeviceMetadata.Count -gt 0) {
        $uniqueSites = $DeviceMetadata.Values | ForEach-Object { $_.Site } | Where-Object { $_ -ne '' } | Sort-Object -Unique
    }
    $siteDD.ItemsSource = @('') + $uniqueSites
    # Always select the first site via index.  Avoid using SelectedItem on primitive
    # strings to prevent WPF style-binding exceptions.
    if ($siteDD.ItemsSource -and $siteDD.ItemsSource.Count -gt 0) {
        $siteDD.SelectedIndex = 0
    } else {
        $siteDD.SelectedIndex = -1
    }

    $buildingDD = $window.FindName('BuildingDropdown')
    $buildingDD.ItemsSource = @('')
    # Select the blank entry via index and disable until a site is chosen.
    if ($buildingDD.ItemsSource -and $buildingDD.ItemsSource.Count -gt 0) {
        $buildingDD.SelectedIndex = 0
    } else {
        $buildingDD.SelectedIndex = -1
    }
    $buildingDD.IsEnabled = $false

    $roomDD = $window.FindName('RoomDropdown')
    if ($roomDD) {
        $roomDD.ItemsSource = @('')
        # Select blank entry via index and disable initially.
        if ($roomDD.ItemsSource -and $roomDD.ItemsSource.Count -gt 0) {
            $roomDD.SelectedIndex = 0
        } else {
            $roomDD.SelectedIndex = -1
        }
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
    if (-not $global:DeviceMetadata) { return }

    $siteSel = $window.FindName('SiteDropdown').SelectedItem
    $bldSel  = $window.FindName('BuildingDropdown').SelectedItem
    $roomSel = $window.FindName('RoomDropdown').SelectedItem

    Write-Host "[DEBUG] Filtering devices by site='$siteSel', building='$bldSel', room='$roomSel'" -ForegroundColor DarkGray

    $filteredNames = @()
    foreach ($name in $DeviceMetadata.Keys) {
        $meta = $DeviceMetadata[$name]
        if ($siteSel -and $siteSel -ne '' -and $meta.Site -ne $siteSel) { continue }
        if ($bldSel  -and $bldSel  -ne '' -and $meta.Building -ne $bldSel) { continue }
        if ($roomSel -and $roomSel -ne '' -and $meta.Room     -ne $roomSel) { continue }
        $filteredNames += $name
    }
    Write-Host "[DEBUG] Device filter matched $($filteredNames.Count) host(s)" -ForegroundColor DarkGray

    $hostnameDD = $window.FindName('HostnameDropdown')
    $hostnameDD.ItemsSource = $filteredNames
    # Preserve previously selected host if still in the filtered list; otherwise select first entry
    $oldHost = $hostnameDD.SelectedItem
    if ($oldHost -and ($filteredNames -contains $oldHost)) {
        try { $hostnameDD.SelectedItem = $oldHost } catch { try { $hostnameDD.SelectedIndex = ($filteredNames.IndexOf($oldHost)) } catch { } }
    } else {
        if ($filteredNames.Count -gt 0) {
            try { $hostnameDD.SelectedIndex = 0 } catch { $null = $null }
        } else {
            try { $hostnameDD.SelectedIndex = -1 } catch { $null = $null }
        }
    }

    $availableBuildings = @()
    foreach ($name in $DeviceMetadata.Keys) {
        $meta = $DeviceMetadata[$name]
        if ($siteSel -and $siteSel -ne '' -and $meta.Site -ne $siteSel) { continue }
        if ($meta.Building -ne '') { $availableBuildings += $meta.Building }
    }
    $availableBuildings = $availableBuildings | Sort-Object -Unique
    $buildingDD = $window.FindName('BuildingDropdown')
    # Preserve previous building selection when possible.  If the old
    # selection is still available, select it.  Otherwise default to the
    # blank entry (all buildings) so that filtering does not exclude
    # devices unintentionally.  Do not automatically select a specific
    # building when the previous selection is invalid.
    $oldBuilding = $bldSel
    $buildingDD.ItemsSource = @('') + $availableBuildings
    if ($oldBuilding -and $oldBuilding -ne '' -and ($buildingDD.ItemsSource -contains $oldBuilding)) {
        try { $buildingDD.SelectedItem = $oldBuilding } catch { $buildingDD.SelectedIndex = 0 }
    } else {
        if ($buildingDD.ItemsSource -and $buildingDD.ItemsSource.Count -gt 0) {
            $buildingDD.SelectedIndex = 0
        } else {
            $buildingDD.SelectedIndex = -1
        }
    }
    # Update bldSel to reflect the current building selection
    $bldSel = $buildingDD.SelectedItem

    if ($siteSel -and $siteSel -ne '') {
        $buildingDD.IsEnabled = $true
    } else {
        $buildingDD.IsEnabled = $false
    }

    $availableRooms = @()
    foreach ($name in $DeviceMetadata.Keys) {
        $meta = $DeviceMetadata[$name]
        if ($siteSel -and $siteSel -ne '' -and $meta.Site -ne $siteSel) { continue }
        if ($bldSel  -and $bldSel  -ne '' -and $meta.Building -ne $bldSel) { continue }
        if ($meta.Room -ne '') { $availableRooms += $meta.Room }
    }
    $availableRooms = $availableRooms | Sort-Object -Unique
    $roomDD = $window.FindName('RoomDropdown')
    if ($roomDD) {
        $roomDD.ItemsSource = @('') + $availableRooms
        # Always select first room via index
        if ($roomDD.ItemsSource -and $roomDD.ItemsSource.Count -gt 0) {
            try { $roomDD.SelectedIndex = 0 } catch { $null = $null }
        } else {
            try { $roomDD.SelectedIndex = -1 } catch { $null = $null }
        }
        # Enable room dropdown only if site selected and building index > 0
        if (($siteSel -and $siteSel -ne '') -and ($buildingDD.SelectedIndex -gt 0)) {
            $roomDD.IsEnabled = $true
        } else {
            $roomDD.IsEnabled = $false
        }
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
}

function Get-DeviceDetails {
    param($hostname)
    try {
        Write-Host "[DEBUG] Loading details for host '$hostname'" -ForegroundColor DarkGray
        $useDb = $false
        if ($global:StateTraceDb) { $useDb = $true }
        Write-Host "[DEBUG] Using database: $useDb" -ForegroundColor DarkGray

        if ($useDb) {
            $hostTrim = ($hostname -as [string]).Trim()
            $escHost   = $hostTrim -replace "'", "''"
            $charCodes = ($hostTrim.ToCharArray() | ForEach-Object { [int]$_ }) -join ','
            Write-Host "[DEBUG] hostTrim='$hostTrim' (Len=$($hostTrim.Length)) Codes=[$charCodes]" -ForegroundColor Yellow
            $summarySql = "SELECT Hostname, Make, Model, Uptime, Ports, AuthDefaultVLAN, Building, Room " +
                          "FROM DeviceSummary " +
                          "WHERE Hostname = '$escHost' " +
                          "   OR Hostname LIKE '*$escHost*'"
            $dtSummary = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql $summarySql
            Write-Host "[DEBUG] summarySql=$summarySql" -ForegroundColor Yellow
            if ($dtSummary) {
                Write-Host "[DEBUG] dtSummary.Rows.Count=$($dtSummary.Rows.Count)" -ForegroundColor Yellow
                foreach ($rowTmp in ($dtSummary | Select-Object Hostname, Make, Model, Uptime, Ports, AuthDefaultVLAN, Building, Room)) {
                    $hnRaw  = '' + $rowTmp.Hostname
                    $hnTrim = $hnRaw.Trim()
                    $codes  = ($hnRaw.ToCharArray() | ForEach-Object { [int]$_ }) -join ','
                    Write-Host "[DEBUG] dtSummary HostnameRaw='$hnRaw' Trimmed='$hnTrim' Codes=[$codes]" -ForegroundColor Yellow
                }
            }
            $summaryObjects = @()
            if ($dtSummary) {
                $summaryObjects = @($dtSummary | Select-Object Hostname, Make, Model, Uptime, Ports, AuthDefaultVLAN, Building, Room)
            }
            $dtSummaryAll = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT Hostname, Make, Model, Uptime, Ports, AuthDefaultVLAN, Building, Room FROM DeviceSummary"
            Write-Host "[DEBUG] Summary rows returned: $($summaryObjects.Count)" -ForegroundColor DarkGray
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
                Write-Host "[DEBUG] Summary values for ${hostname}: Make='$($row.Make)', Model='$($row.Model)', Uptime='$($row.Uptime)', Ports='$($row.Ports)', AuthDefaultVLAN='$($row.AuthDefaultVLAN)', Building='$($row.Building)', Room='$($row.Room)'" -ForegroundColor DarkCyan
                Write-Host "[DEBUG] Fallback values: Make='$fbMake', Model='$fbModel', Uptime='$fbUptime', Ports='$fbPorts', AuthDefaultVLAN='$fbAuthDef', Building='$fbBuilding', Room='$fbRoom'" -ForegroundColor DarkMagenta
            } else {
                $interfacesView.FindName('HostnameBox').Text        = $hostname
                $interfacesView.FindName('MakeBox').Text            = $fbMake
                $interfacesView.FindName('ModelBox').Text           = $fbModel
                $interfacesView.FindName('UptimeBox').Text          = $fbUptime
                $interfacesView.FindName('PortCountBox').Text       = $fbPorts
                $interfacesView.FindName('AuthDefaultVLANBox').Text = $fbAuthDef
                $interfacesView.FindName('BuildingBox').Text        = $fbBuilding
                $interfacesView.FindName('RoomBox').Text            = $fbRoom
                Write-Host "[DEBUG] No summary row found for ${hostname}. Using fallback values: Make='$fbMake', Model='$fbModel', Uptime='$fbUptime', Ports='$fbPorts', AuthDefaultVLAN='$fbAuthDef', Building='$fbBuilding', Room='$fbRoom'" -ForegroundColor DarkMagenta
                if ($dtSummaryAll) {
                    Write-Host "[DEBUG] DeviceSummary table contents:" -ForegroundColor Yellow
                    foreach ($rowAll in ($dtSummaryAll | Select-Object Hostname, Make, Model, Uptime, Ports, AuthDefaultVLAN, Building, Room)) {
                        $hnRaw   = '' + $rowAll.Hostname
                        $hnTrim  = $hnRaw.Trim()
                        $lenRaw  = if ($hnRaw) { $hnRaw.Length } else { 0 }
                        $lenTrim = if ($hnTrim) { $hnTrim.Length } else { 0 }
                        Write-Host "[DEBUG] HostnameRaw='$hnRaw' (Len=$lenRaw) Trimmed='$hnTrim' (Len=$lenTrim) -> Make='$($rowAll.Make)', Model='$($rowAll.Model)', Ports='$($rowAll.Ports)', AuthVLAN='$($rowAll.AuthDefaultVLAN)', Building='$($rowAll.Building)', Room='$($rowAll.Room)'" -ForegroundColor Yellow
                    }
                }
            }
            $dtIfs = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT Hostname, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, ConfigStatus, PortColor, ToolTip FROM Interfaces WHERE Hostname = '$($hostname -replace "'", "''")'"
            $ifObjects = $dtIfs | Select-Object Hostname, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, ConfigStatus, PortColor, ToolTip
            Write-Host "[DEBUG] Interface rows returned: $($ifObjects.Count)" -ForegroundColor DarkGray
            # Determine device vendor and load global authentication block from the summary table.  When a device is
            # Brocade and the per-port Config doesn’t include the individual port-auth lines (common on 8.x firmware),
            # append the global AuthBlock to each row’s tooltip so administrators can see the complete
            # authentication configuration in the hover tooltip.
            $mkVal = ''
            try {
                # Use summary values if available, otherwise fallback values captured above
                if ($summaryObjects -and $summaryObjects.Count -gt 0) {
                    $mkVal = $summaryObjects[0].Make
                }
                if (-not $mkVal -or $mkVal -eq [System.DBNull]::Value -or $mkVal -eq '') {
                    $mkVal = $fbMake
                }
            } catch {}
            $deviceVendor = ''
            if ($mkVal -and ($mkVal -match '(?i)brocade')) { $deviceVendor = 'Brocade' }
            # Retrieve the device-level AuthBlock lines from the DeviceSummary table for Brocade devices
            $globalAuthLines = @()
            if ($deviceVendor -eq 'Brocade') {
                try {
                    $qryAb = "SELECT AuthBlock FROM DeviceSummary WHERE Hostname = '$esc'"
                    $abDt  = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql $qryAb
                    if ($abDt) {
                        $abRaw = $null
                        if ($abDt -is [System.Data.DataTable]) {
                            if ($abDt.Rows.Count -gt 0) { $abRaw = '' + $abDt.Rows[0].AuthBlock }
                        } else {
                            $rowAb = $abDt | Select-Object -First 1
                            if ($rowAb -and $rowAb.PSObject.Properties['AuthBlock']) { $abRaw = '' + $rowAb.AuthBlock }
                        }
                        if ($abRaw -and $abRaw.Trim() -ne '') {
                            $globalAuthLines = $abRaw -split '\r?\n'
                        }
                    }
                } catch {}
            }
            $list = @()
            foreach ($r in $ifObjects) {
                # Build the tooltip; if this device is Brocade and a global auth block exists, append it once per row.
                $tp = ''
                if ($r.ToolTip) { $tp = '' + $r.ToolTip }
                if ($deviceVendor -eq 'Brocade' -and $globalAuthLines.Count -gt 0 -and ($tp -notmatch '(?i)GLOBAL AUTH BLOCK')) {
                    # Append a header without database annotation. Handle empty or existing tooltip gracefully.
                    if ($tp -and $tp.Trim() -ne '') {
                        $tp = $tp.TrimEnd() + "`r`n`r`n! GLOBAL AUTH BLOCK`r`n" + ($globalAuthLines -join "`r`n")
                    } else {
                        $tp = "! GLOBAL AUTH BLOCK`r`n" + ($globalAuthLines -join "`r`n")
                    }
                }
                $obj = [PSCustomObject]@{
                    Hostname      = $r.Hostname
                    Port          = $r.Port
                    Name          = $r.Name
                    Status        = $r.Status
                    VLAN          = $r.VLAN
                    Duplex        = $r.Duplex
                    Speed         = $r.Speed
                    Type          = $r.Type
                    LearnedMACs   = $r.LearnedMACs
                    AuthState     = $r.AuthState
                    AuthMode      = $r.AuthMode
                    AuthClientMAC = $r.AuthClientMAC
                    ToolTip       = $tp
                    IsSelected    = $false
                    ConfigStatus  = if ($r.ConfigStatus) { $r.ConfigStatus } else { 'Unknown' }
                    PortColor     = if ($r.PortColor) { $r.PortColor } else { 'Gray' }
                }
                $list += $obj
            }
            $grid = $interfacesView.FindName('InterfacesGrid')
            $grid.ItemsSource = $list
            $combo = $interfacesView.FindName('ConfigOptionsDropdown')
            $combo.ItemsSource = Get-ConfigurationTemplates -Hostname $hostname
            # Safely select the first configuration item via index if available
            if ($combo.Items.Count -gt 0) {
                try { $combo.SelectedIndex = 0 } catch { $null = $null }
            } else {
                try { $combo.SelectedIndex = -1 } catch { $null = $null }
            }
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
            $combo.ItemsSource = Get-ConfigurationTemplates -Hostname $hostname
            # Safely select first template via index if available
            if ($combo.Items.Count -gt 0) {
                try { $combo.SelectedIndex = 0 } catch { $null = $null }
            } else {
                try { $combo.SelectedIndex = -1 } catch { $null = $null }
            }
        }
    } catch {
        [System.Windows.MessageBox]::Show("Error loading ${hostname}:`n$($_.Exception.Message)")
    }
}

Export-ModuleMember -Function Get-DeviceSummaries, Update-DeviceFilter, Get-DeviceDetails