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
    # Safely select the first filtered hostname via index to avoid SelectedItem exceptions
    if ($filteredNames.Count -gt 0) {
        try { $hostnameDD.SelectedIndex = 0 } catch { $null = $null }
    } else {
        try { $hostnameDD.SelectedIndex = -1 } catch { $null = $null }
    }

    $availableBuildings = @()
    foreach ($name in $DeviceMetadata.Keys) {
        $meta = $DeviceMetadata[$name]
        if ($siteSel -and $siteSel -ne '' -and $meta.Site -ne $siteSel) { continue }
        if ($meta.Building -ne '') { $availableBuildings += $meta.Building }
    }
    $availableBuildings = $availableBuildings | Sort-Object -Unique
    $buildingDD = $window.FindName('BuildingDropdown')
    $buildingDD.ItemsSource = @('') + $availableBuildings
    # Always select first entry via index; avoid SelectedItem exceptions
    if ($buildingDD.ItemsSource -and $buildingDD.ItemsSource.Count -gt 0) {
        try { $buildingDD.SelectedIndex = 0 } catch { $null = $null }
    } else {
        try { $buildingDD.SelectedIndex = -1 } catch { $null = $null }
    }
    $bldSel = ''

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
                    $comboCached.ItemsSource = Get-ConfigurationTemplates -Hostname $hostname
                    if ($comboCached.Items.Count -gt 0) {
                        try { $comboCached.SelectedIndex = 0 } catch { $null = $null }
                    } else {
                        try { $comboCached.SelectedIndex = -1 } catch { $null = $null }
                    }
                    return
                }
            } catch {}

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
            # Cache this device's interface list for future visits.  The cache stores the
            # final PSCustomObject list keyed by hostname.  Subsequent calls to
            # Get-DeviceDetails can reuse this list instead of requerying the database.
            try {
                $global:DeviceInterfaceCache[$hostname] = $list
            } catch {}
            # Update the grid with the freshly built list of interface objects.
            $grid = $interfacesView.FindName('InterfacesGrid')
            $grid.ItemsSource = $list
            # Bind available configuration templates for this device.
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

    Write-Host "DBG: Starting Update-GlobalInterfaceList" -ForegroundColor Yellow
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
        # Log the result of Invoke-DbQuery for debugging
        if ($dt) {
            Write-Host ("DBG: Invoke-DbQuery returned object of type {0}" -f $dt.GetType().FullName) -ForegroundColor Yellow
        } else {
            Write-Host "DBG: Invoke-DbQuery returned null or empty" -ForegroundColor Yellow
        }

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

        # Debug: report row count if available
        $rowCount = 0
        try { $rowCount = $rows.Count } catch { }
        Write-Host "DBG: Number of rows to process: $rowCount" -ForegroundColor Yellow

        $addedCount  = 0
        $skippedNull = 0
        $skippedType = 0
        $rowIndex    = 0

        foreach ($r in $rows) {
            $rowIndex++
            # Skip any null entries
            if ($r -eq $null) {
                $skippedNull++
                if ($skippedNull -le 5) {
                    Write-Host ("DBG: Row {0} is null; skipping." -f $rowIndex) -ForegroundColor Yellow
                }
                continue
            }
            # Support both DataRow and DataRowView.  Convert DataRowView to DataRow.
            $dataRow = $null
            if ($r -is [System.Data.DataRow]) {
                $dataRow = $r
            } elseif ($r -is [System.Data.DataRowView]) {
                $dataRow = $r.Row
            } else {
                # Unexpected row type; skip it and log for the first few occurrences
                $skippedType++
                if ($skippedType -le 5) {
                    Write-Host ("DBG: Row {0} of type {1} is unsupported; skipping." -f $rowIndex, $r.GetType().FullName) -ForegroundColor Yellow
                }
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

            # Debug: log first few processed rows for verification
            if ($addedCount -lt 5) {
                Write-Host ("DBG: Adding interface {0}:{1} (PortSort {2})" -f $hn, $port, $portSort) -ForegroundColor Yellow
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

        Write-Host ("DBG: Completed interface list build. Added {0} rows, skipped {1} null and {2} unsupported rows." -f $addedCount, $skippedNull, $skippedType) -ForegroundColor Yellow
    } catch {
        Write-Warning "Failed to rebuild interface list from database: $($_.Exception.Message)"
    }

    # Publish the interface list globally (sorted by Hostname and PortSort).  Use a
    # stable ordering so that UI controls do not refresh unpredictably when
    # underlying enumeration order changes.
    $global:AllInterfaces = $list | Sort-Object Hostname, PortSort
    Write-Host "DBG: $($global:AllInterfaces.Count) total interfaces available in global list after sorting." -ForegroundColor Yellow

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
    # the search term is blank.  Retrieve the currently selected Site,
    # Building and Room from the dropdowns on the main window.  An
    # empty selection represents "All" so we do not apply that filter.
    $siteSel = $global:window.FindName('SiteDropdown').SelectedItem
    $bldSel  = $global:window.FindName('BuildingDropdown').SelectedItem
    $roomSel = $global:window.FindName('RoomDropdown').SelectedItem

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
            $stLower = ($row.Status -as [string]).ToLower()
            if ($statusFilterVal -eq 'Up') {
                if ($stLower -ne 'up' -and $stLower -ne 'connected') { return $false }
            } elseif ($statusFilterVal -eq 'Down') {
                if ($stLower -ne 'down' -and $stLower -ne 'notconnect') { return $false }
            }
        }
        # Evaluate authorization filter
        if ($authFilterVal -ne 'All') {
            $asLower = ($row.AuthState -as [string]).ToLower()
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
                    if (-not (($row.Port        -as [string]).ToLower().Contains($t) -or
                              ($row.Name        -as [string]).ToLower().Contains($t) -or
                              ($row.LearnedMACs -as [string]).ToLower().Contains($t) -or
                              ($row.AuthClientMAC -as [string]).ToLower().Contains($t))) {
                        return $false
                    }
                }
            } else {
                $t = $Term.ToLower()
                if (-not (($row.Port        -as [string]).ToLower().Contains($t) -or
                          ($row.Name        -as [string]).ToLower().Contains($t) -or
                          ($row.LearnedMACs -as [string]).ToLower().Contains($t) -or
                          ($row.AuthClientMAC -as [string]).ToLower().Contains($t))) {
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
        $siteSel  = $global:window.FindName('SiteDropdown').SelectedItem
        $bldSel   = $global:window.FindName('BuildingDropdown').SelectedItem
        $roomSel  = $global:window.FindName('RoomDropdown').SelectedItem
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
    $uniqueVlans = ($vlans | Sort-Object -Unique)
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
        Write-Host ("DBG: Update-SearchGrid: term='{0}' yielded {1} results." -f $term, $resCount) -ForegroundColor Yellow
    } catch {
        Write-Host "DBG: Update-SearchGrid: unable to determine result count." -ForegroundColor Yellow
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
    if (-not $global:StateTraceDb) { return @() }
    $debug = ($Global:StateTraceDebug -eq $true)
    try {
        $dbModule = Join-Path $PSScriptRoot 'DatabaseModule.psm1'
        if (Test-Path $dbModule) {
            Import-Module $dbModule -Force -Global -ErrorAction SilentlyContinue | Out-Null
        }
        $escHost = $Hostname -replace "'", "''"
        $sql = "SELECT Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip FROM Interfaces WHERE Hostname = '$escHost' ORDER BY Port"
        $dt = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql $sql
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
            } catch {
                if ($debug) { Write-Host "[Get-InterfaceInfo] Failed to load AuthBlock for ${Hostname}: $($_.Exception.Message)" -ForegroundColor Yellow }
            }
        }
        if ($debug) {
            $cnt = 0
            try {
                if ($dt -is [System.Data.DataTable]) { $cnt = $dt.Rows.Count } else { $cnt = @($dt).Count }
            } catch {}
            Write-Host "[Get-InterfaceInfo] Host=$Hostname Vendor=$vendor Rows=$cnt AuthBlockLines=$($authBlockLines.Count)" -ForegroundColor Cyan
            if ($authBlockLines.Count -gt 0) { Write-Host "[Get-InterfaceInfo] AuthBlock first line: $($authBlockLines[0])" -ForegroundColor DarkCyan }
        }
        $vendorFile = if ($vendor -eq 'Cisco') { 'Cisco.json' } else { 'Brocade.json' }
        $jsonFile   = Join-Path $TemplatesPath $vendorFile
        $templates  = $null
        if (Test-Path $jsonFile) {
            $tmplJson = Get-Content $jsonFile -Raw | ConvertFrom-Json
            $templates = $tmplJson.templates
        }
        $results = @()
        foreach ($row in ($dt | Select-Object Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip)) {
            $authTemplate = $row.AuthTemplate
            $match = $null
            if ($templates) {
                $match = $templates | Where-Object {
                    $_.name -ieq $authTemplate -or
                    ($_.aliases -and ($_.aliases -contains $authTemplate))
                } | Select-Object -First 1
            }
            $portColor    = if ($row.PortColor) { $row.PortColor } elseif ($match) { $match.color } else { 'Gray' }
            $configStatus = if ($row.ConfigStatus) { $row.ConfigStatus } elseif ($match) { 'Match' } else { 'Mismatch' }
            $toolTipCore = if ($row.ToolTip) {
                ('' + $row.ToolTip).TrimEnd()
            } else {
                $cfg = '' + $row.Config
                if ($cfg -and $cfg.Trim() -ne '') {
                    "AuthTemplate: $authTemplate`r`n`r`n$cfg"
                } else {
                    "AuthTemplate: $authTemplate"
                }
            }
            $toolTip = $toolTipCore
            if ($vendor -eq 'Brocade' -and $authBlockLines.Count -gt 0 -and ($toolTipCore -notmatch '(?i)GLOBAL AUTH BLOCK')) {
                $toolTip = $toolTipCore + "`r`n`r`n! GLOBAL AUTH BLOCK`r`n" + ($authBlockLines -join "`r`n")
            }
            $results += [PSCustomObject]@{
                Hostname      = $Hostname
                Port          = $row.Port
                Name          = $row.Name
                Status        = $row.Status
                VLAN          = $row.VLAN
                Duplex        = $row.Duplex
                Speed         = $row.Speed
                Type          = $row.Type
                LearnedMACs   = $row.LearnedMACs
                AuthState     = $row.AuthState
                AuthMode      = $row.AuthMode
                AuthClientMAC = $row.AuthClientMAC
                ToolTip       = $toolTip
                IsSelected    = $false
                ConfigStatus  = $configStatus
                PortColor     = $portColor
            }
        }
        return $results
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
    Get-InterfaceList