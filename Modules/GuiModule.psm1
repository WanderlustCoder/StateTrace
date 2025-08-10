<##
    .SYNOPSIS
        Provides helper functions for the Network Reader GUI.

    .DESCRIPTION
        This module extracts a number of helper functions from the main
        `MainWindow.ps1` script.  Moving these functions into a module
        makes the main script easier to read and maintain by separating
        business logic from UI wiring.  The functions exported here are
        identical to the originals that lived in `MainWindow.ps1` and
        operate on the same global variables defined in that script.

        The following functions are exported:

        * Get-DeviceSummaries     – builds the list of available devices
        * Update-DeviceFilter      – filters devices by site/building/room
        * Get-DeviceDetails       – loads interface details for a device
        * Update-GlobalInterfaceList – constructs the global interface list
        * Update-SearchResults     – performs searching and filtering
        * Update-Summary           – updates summary metrics
        * Update-Alerts           – builds the alerts list
        * Update-SearchGrid       – refreshes the search grid contents

        Because these functions reference variables from the main script
        (such as `$window` and `$scriptDir`), the main script must define
        those variables before importing this module.  The module makes
        no assumptions about the UI beyond those exposed variables.

        To use this module, import it from `MainWindow.ps1` after
        establishing `$scriptDir` and loading the XAML window:

            $guiModulePath = Join-Path $scriptDir '..\Modules\GuiModule.psm1'
            Import-Module $guiModulePath -Force

        Once imported, the helper functions will be available for use.
##>

function Load-DeviceSummaries {
    <#
        Build the list of available devices by querying the database.  The
        database is treated as the single source of truth for all device
        metadata.  If the database is not configured or the query fails,
        the device list will remain empty and no legacy CSV fallback is
        attempted.  This enforces a consistent data model across the
        application.
    #>
    # Immediately forward to the new helper and exit.  This preserves backwards
    # compatibility while ensuring the updated Get-DeviceSummaries implementation
    # is used.  All legacy logic below will not be executed.
    if (Get-Command Get-DeviceSummaries -ErrorAction SilentlyContinue) {
        return & Get-DeviceSummaries
    }

    $names = @()
    $global:DeviceMetadata = @{}
    if ($global:StateTraceDb) {
        try {
            # Import the database module relative to the project root.  Resolve
            # root via $scriptDir if available, otherwise relative to this module.
            $rootDir  = if ($scriptDir) { (Join-Path $scriptDir '..') } else { (Join-Path $PSScriptRoot '..') }
            $dbModule = Join-Path (Join-Path $rootDir 'Modules') 'DatabaseModule.psm1'
            if (Test-Path $dbModule) {
                Import-Module $dbModule -Force -Global -ErrorAction Stop | Out-Null
            }
            # Query device metadata from DeviceSummary.  Select fields needed for
            # building location filters.
            $dt = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT Hostname, Site, Building, Room FROM DeviceSummary ORDER BY Hostname"
            foreach ($row in ($dt | Select-Object Hostname, Site, Building, Room)) {
                $name = $row.Hostname
                if (-not [string]::IsNullOrWhiteSpace($name)) {
                    $names += $name
                    $siteRaw     = $row.Site
                    $buildingRaw = $row.Building
                    $roomRaw     = $row.Room
                    $siteVal     = if ($siteRaw     -eq $null -or $siteRaw     -eq [System.DBNull]::Value) { '' } else { [string]$siteRaw }
                    $buildingVal = if ($buildingRaw -eq $null -or $buildingRaw -eq [System.DBNull]::Value) { '' } else { [string]$buildingRaw }
                    $roomVal     = if ($roomRaw     -eq $null -or $roomRaw     -eq [System.DBNull]::Value) { '' } else { [string]$roomRaw }
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

    # Populate the host dropdown with all hostnames
    $hostnameDD = $global:window.FindName('HostnameDropdown')
    $hostnameDD.ItemsSource = $names
    if ($names -and $names.Count -gt 0) {
        # select first item via index to avoid SelectedItem exceptions
        $hostnameDD.SelectedIndex = 0
    } else {
        $hostnameDD.SelectedIndex = -1
    }

    # Populate the site dropdown with unique site codes (include blank for All)
    $siteDD = $global:window.FindName('SiteDropdown')
    $uniqueSites = @()
    if ($global:DeviceMetadata.Count -gt 0) {
        $uniqueSites = $global:DeviceMetadata.Values | ForEach-Object { $_.Site } | Where-Object { $_ -ne '' } | Sort-Object -Unique
    }
    $siteDD.ItemsSource = @('') + $uniqueSites
    if ($siteDD.ItemsSource -and $siteDD.ItemsSource.Count -gt 0) {
        $siteDD.SelectedIndex = 0
    } else {
        $siteDD.SelectedIndex = -1
    }

    # Initialize building dropdown and disable until site selected
    $buildingDD = $global:window.FindName('BuildingDropdown')
    $buildingDD.ItemsSource = @('')
    if ($buildingDD.ItemsSource -and $buildingDD.ItemsSource.Count -gt 0) {
        $buildingDD.SelectedIndex = 0
    } else {
        $buildingDD.SelectedIndex = -1
    }
    $buildingDD.IsEnabled = $false

    # Initialize room dropdown and disable until both site and building selected
    $roomDD = $global:window.FindName('RoomDropdown')
    if ($roomDD) {
        $roomDD.ItemsSource = @('')
        if ($roomDD.ItemsSource -and $roomDD.ItemsSource.Count -gt 0) {
            $roomDD.SelectedIndex = 0
        } else {
            $roomDD.SelectedIndex = -1
        }
        $roomDD.IsEnabled = $false
    }

    # Refresh the global interface list used by the search tab (if defined)
    if (Get-Command Update-GlobalInterfaceList -ErrorAction SilentlyContinue) {
        Update-GlobalInterfaceList
        # Update the search grid if it has been initialised
        $searchHostCtrl = $global:window.FindName('SearchInterfacesHost')
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

    $siteSel = $global:window.FindName('SiteDropdown').SelectedItem
    $bldSel  = $global:window.FindName('BuildingDropdown').SelectedItem
    $roomSel = $global:window.FindName('RoomDropdown').SelectedItem

    # Filter hostnames based on selections
    $filteredNames = @()
    foreach ($name in $DeviceMetadata.Keys) {
        $meta = $DeviceMetadata[$name]
        if ($siteSel -and $siteSel -ne '' -and $meta.Site -ne $siteSel) { continue }
        if ($bldSel  -and $bldSel  -ne '' -and $meta.Building -ne $bldSel) { continue }
        if ($roomSel -and $roomSel -ne '' -and $meta.Room     -ne $roomSel) { continue }
        $filteredNames += $name
    }

    # Repopulate hostname dropdown but preserve the previous host if possible
    $hostnameDD = $global:window.FindName('HostnameDropdown')
    $hostnameDD.ItemsSource = $filteredNames
    $prevHost = $hostnameDD.SelectedItem
    if ($prevHost -and ($filteredNames -contains $prevHost)) {
        try { $hostnameDD.SelectedItem = $prevHost } catch { try { $hostnameDD.SelectedIndex = ($filteredNames.IndexOf($prevHost)) } catch { $hostnameDD.SelectedIndex = 0 } }
    } else {
        if ($filteredNames.Count -gt 0) {
            $hostnameDD.SelectedIndex = 0
        } else {
            $hostnameDD.SelectedIndex = -1
        }
    }

    # Rebuild building dropdown options based on the selected site
    $availableBuildings = @()
    foreach ($name in $DeviceMetadata.Keys) {
        $meta = $DeviceMetadata[$name]
        if ($siteSel -and $siteSel -ne '' -and $meta.Site -ne $siteSel) { continue }
        if ($meta.Building -ne '') { $availableBuildings += $meta.Building }
    }
    $availableBuildings = $availableBuildings | Sort-Object -Unique
    $buildingDD = $global:window.FindName('BuildingDropdown')
    # Preserve the old building selection if it is still valid in the new list
    $oldBuilding = $bldSel
    # Populate the Building dropdown.  Always include a blank entry as the
    # first element so users can clear the filter.  Preserve the old
    # building selection whenever possible.  If the old selection is not
    # present in the new list, default to the blank entry (index 0) so
    # that all devices remain visible.  Do not automatically select a
    # specific building when the previous selection is invalid.
    $buildingDD.ItemsSource = @('') + $availableBuildings
    if ($oldBuilding -and $oldBuilding -ne '' -and ($buildingDD.ItemsSource -contains $oldBuilding)) {
        try { $buildingDD.SelectedItem = $oldBuilding } catch { $buildingDD.SelectedIndex = 0 }
    } else {
        # Select the blank (all) option when no previous selection is valid
        if ($buildingDD.ItemsSource -and $buildingDD.ItemsSource.Count -gt 0) {
            $buildingDD.SelectedIndex = 0
        } else {
            $buildingDD.SelectedIndex = -1
        }
    }
    # Update local copy of the building selection for subsequent room filtering
    $bldSel = $buildingDD.SelectedItem

    # Enable or disable the Building dropdown based on the current site
    # selection.  A blank site selection means the user has not chosen a
    # site yet, so the Building dropdown remains disabled.  Otherwise it
    # becomes enabled so the user may pick a building.
    if ($siteSel -and $siteSel -ne '') {
        $buildingDD.IsEnabled = $true
    } else {
        $buildingDD.IsEnabled = $false
    }

    # Rebuild room dropdown options based on selected site and building
    $availableRooms = @()
    foreach ($name in $DeviceMetadata.Keys) {
        $meta = $DeviceMetadata[$name]
        if ($siteSel -and $siteSel -ne '' -and $meta.Site -ne $siteSel) { continue }
        if ($bldSel  -and $bldSel  -ne '' -and $meta.Building -ne $bldSel) { continue }
        if ($meta.Room -ne '') { $availableRooms += $meta.Room }
    }
    $availableRooms = $availableRooms | Sort-Object -Unique
    $roomDD = $global:window.FindName('RoomDropdown')
    if ($roomDD) {
        $roomDD.ItemsSource = @('') + $availableRooms
        # Always select first entry via index
        if ($roomDD.ItemsSource -and $roomDD.ItemsSource.Count -gt 0) {
            $roomDD.SelectedIndex = 0
        } else {
            $roomDD.SelectedIndex = -1
        }

        # Enable or disable the Room dropdown.  The Room selection
        # should only be possible once both a site and a building have
        # been chosen.  If either the site or building is blank, the
        # Room dropdown is disabled; otherwise it is enabled.
        if (($siteSel -and $siteSel -ne '') -and ($buildingDD.SelectedIndex -gt 0)) {
            $roomDD.IsEnabled = $true
        } else {
            $roomDD.IsEnabled = $false
        }
    }

    # Refresh the search results grid to honour the updated
    # Site/Building/Room filters.  This ensures that the global
    # interface search respects the same filtering criteria as the
    # device selector.  Only call this function if it exists (it is
    # defined in the search tab injection logic).
    if (Get-Command Update-SearchGrid -ErrorAction SilentlyContinue) {
        Update-SearchGrid
    }

    # Update summary and alerts when the location filters change.  This allows
    # the Summary tab and Alerts tab to reflect the selected site, building
    # and room.  Only call these helpers if defined.
    if (Get-Command Update-Summary -ErrorAction SilentlyContinue) {
        Update-Summary
    }
    if (Get-Command Update-Alerts -ErrorAction SilentlyContinue) {
        Update-Alerts
    }
}

function Load-DeviceDetails {
    param($hostname)
    # Forward to the new helper and exit.  This stub maintains backwards
    # compatibility while delegating to Get-DeviceDetails.  The original
    # implementation below will not execute.
    if (Get-Command Get-DeviceDetails -ErrorAction SilentlyContinue) {
        return & Get-DeviceDetails $hostname
    }
    # Do not attempt to load details for a blank or null hostname.  Instead clear
    # the interface view fields and return early.  This prevents attempts to
    # open files like "_Summary.csv" when no device is selected.
    if (-not $hostname -or $hostname -eq '') {
        # Clear fields when no hostname is selected.  The controls we update live
        # inside the InterfacesView UserControl, not directly on the main
        # window.  Therefore look up each control from the global interfaces
        # view rather than the main window.  This avoids errors when the
        # controls cannot be found on the window’s namescope.
        if ($global:interfacesView) {
            $iview = $global:interfacesView
            $iview.FindName('HostnameBox').Text        = ''
            $iview.FindName('MakeBox').Text            = ''
            $iview.FindName('ModelBox').Text           = ''
            $iview.FindName('UptimeBox').Text          = ''
            $iview.FindName('PortCountBox').Text       = ''
            $iview.FindName('AuthDefaultVLANBox').Text = ''
            $iview.FindName('BuildingBox').Text        = ''
            $iview.FindName('RoomBox').Text            = ''
            $gridCtrl = $iview.FindName('InterfacesGrid')
            if ($gridCtrl) { $gridCtrl.ItemsSource = $null }
            $comboCtrl = $iview.FindName('ConfigOptionsDropdown')
            if ($comboCtrl) { $comboCtrl.ItemsSource = @() }
        }
        return
    }
    try {
        # Determine whether the database is available.  When present, load
        # summary and interface details from the database instead of CSV.
        $useDb = $false
        if ($global:StateTraceDb) { $useDb = $true }
        if ($useDb) {
            # Import DatabaseModule relative to the project root
            try {
                $rootDir  = if ($scriptDir) { (Join-Path $scriptDir '..') } else { (Join-Path $PSScriptRoot '..') }
                $dbModule = Join-Path (Join-Path $rootDir 'Modules') 'DatabaseModule.psm1'
                if (Test-Path $dbModule) {
                    # Import DatabaseModule globally so Invoke-DbQuery is visible across modules
                    Import-Module $dbModule -Force -Global -ErrorAction Stop | Out-Null
                }
            } catch {
                Write-Warning "Failed to import DatabaseModule: $($_.Exception.Message). Falling back to CSV."
                $useDb = $false
            }
        }
        if ($useDb) {
            # Query summary information for the selected device using a robust SQL query.  Perform a case‑insensitive comparison
            # on the trimmed hostname and allow for trailing characters by also using a LIKE predicate.  This avoids
            # retrieving the entire table and filtering in PowerShell, and accommodates rows that may contain
            # extraneous whitespace or control characters after the hostname.
            # Trim the hostname before quoting to avoid matching against unintended leading/trailing whitespace.
            $hostTrim = ($hostname -as [string]).Trim()
            $escHost  = $hostTrim -replace "'", "''"
            # Emit diagnostic information about the incoming hostname.  Output the trimmed string, its length,
            # and the numeric character codes to detect hidden characters that Trim() may not remove.
            $charCodes = ($hostTrim.ToCharArray() | ForEach-Object { [int]$_ }) -join ','
            Write-Host "[DEBUG] hostTrim='$hostTrim' (Len=$($hostTrim.Length)) Codes=[$charCodes]" -ForegroundColor Yellow
            # Build a summary query that avoids provider‑specific functions.  Use explicit LIKE predicates and Trim() where supported.
            # Access databases are generally case‑insensitive, so comparing without UCASE should still match regardless of case.
        # Jet/ACE providers use '*' and '?' as wildcards in LIKE expressions.  Using
        # '%' and '_' will return no rows.  Compose the query to find an exact
        # match and, failing that, a substring match using '*'.  See:
        # https://learn.microsoft.com/en-us/office/client-developer/access/desktop-database-reference/like-operator-microsoft-access-sql
        $summarySql = "SELECT Hostname, Make, Model, Uptime, Ports, AuthDefaultVLAN, Building, Room " +
                      "FROM DeviceSummary " +
                      "WHERE Hostname = '$escHost' " +
                      "   OR Hostname LIKE '*$escHost*'"
            $dtSummary    = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql $summarySql
            # Log the query used and the count of rows returned for further diagnostics
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
            # Convert the returned rows into PSObjects for easier property access
            $summaryRows  = @()
            if ($dtSummary) {
                $summaryRows = $dtSummary | Select-Object Hostname, Make, Model, Uptime, Ports, AuthDefaultVLAN, Building, Room
            }
            # Also retrieve all summary rows for diagnostics.  This can be used for debugging when no match is found.
            $dtSummaryAll = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT Hostname, Make, Model, Uptime, Ports, AuthDefaultVLAN, Building, Room FROM DeviceSummary"
            $iview = $global:interfacesView
            # Precompute fallback values from DeviceHistory and port count.  These
            # provide reasonable defaults when the summary is missing or contains
            # empty/null values.
            $fbMake = ''
            $fbModel = ''
            $fbUptime = ''
            $fbAuthDef = ''
            $fbBuilding = ''
            $fbRoom = ''
            $fbPorts = ''
            try {
                $histFb = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT TOP 1 Make, Model, Uptime, AuthDefaultVLAN, Building, Room FROM DeviceHistory WHERE Trim(Hostname) = '$escHost' ORDER BY RunDate DESC"
                if ($histFb -and $histFb.Rows.Count -gt 0) {
                    $hFbRow = ($histFb | Select-Object Make, Model, Uptime, AuthDefaultVLAN, Building, Room)[0]
                    $fbMake     = $hFbRow.Make
                    $fbModel    = $hFbRow.Model
                    $fbUptime   = $hFbRow.Uptime
                    $fbAuthDef  = $hFbRow.AuthDefaultVLAN
                    $fbBuilding = $hFbRow.Building
                    $fbRoom     = $hFbRow.Room
                }
            } catch {
                # ignore history fallback failures
            }
            try {
                # Use a named alias for the count to avoid provider‑generated column names
                $cntFb = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT COUNT(*) AS PortCount FROM Interfaces WHERE Trim(Hostname) = '$escHost'"
                if ($cntFb -and $cntFb.Rows.Count -gt 0) {
                    $fbPorts = ($cntFb | Select-Object -ExpandProperty PortCount)[0]
                }
            } catch {
                # ignore count fallback failures
            }
            if ($summaryRows -and $summaryRows.Count -gt 0) {
                # There is a summary record; use it but fall back to history for blank fields
                $row = $summaryRows[0]
                $makeVal    = $row.Make
                if (-not $makeVal -or $makeVal -eq [System.DBNull]::Value -or $makeVal -eq '') { $makeVal = $fbMake }
                $modelVal   = $row.Model
                if (-not $modelVal -or $modelVal -eq [System.DBNull]::Value -or $modelVal -eq '') { $modelVal = $fbModel }
                $uptimeVal  = $row.Uptime
                if (-not $uptimeVal -or $uptimeVal -eq [System.DBNull]::Value -or $uptimeVal -eq '') { $uptimeVal = $fbUptime }
                $portsVal   = $row.Ports
                if (-not $portsVal -or $portsVal -eq [System.DBNull]::Value -or $portsVal -eq 0) { $portsVal = $fbPorts }
                $authDefVal = $row.AuthDefaultVLAN
                if (-not $authDefVal -or $authDefVal -eq [System.DBNull]::Value -or $authDefVal -eq '') { $authDefVal = $fbAuthDef }
                $buildingVal= $row.Building
                if (-not $buildingVal -or $buildingVal -eq [System.DBNull]::Value -or $buildingVal -eq '') { $buildingVal = $fbBuilding }
                $roomVal    = $row.Room
                if (-not $roomVal -or $roomVal -eq [System.DBNull]::Value -or $roomVal -eq '') { $roomVal = $fbRoom }
                $iview.FindName('HostnameBox').Text        = $row.Hostname
                $iview.FindName('MakeBox').Text            = $makeVal
                $iview.FindName('ModelBox').Text           = $modelVal
                $iview.FindName('UptimeBox').Text          = $uptimeVal
                $iview.FindName('PortCountBox').Text       = $portsVal
                $iview.FindName('AuthDefaultVLANBox').Text = $authDefVal
                $iview.FindName('BuildingBox').Text        = $buildingVal
                $iview.FindName('RoomBox').Text            = $roomVal
                # Emit debug information about summary and fallback values for this device
                Write-Host "[DEBUG] Summary values for ${hostname}: Make='$($row.Make)', Model='$($row.Model)', Uptime='$($row.Uptime)', Ports='$($row.Ports)', AuthDefaultVLAN='$($row.AuthDefaultVLAN)', Building='$($row.Building)', Room='$($row.Room)'" -ForegroundColor DarkCyan
                Write-Host "[DEBUG] Fallback values: Make='$fbMake', Model='$fbModel', Uptime='$fbUptime', Ports='$fbPorts', AuthDefaultVLAN='$fbAuthDef', Building='$fbBuilding', Room='$fbRoom'" -ForegroundColor DarkMagenta
            } else {
                # No summary record; populate controls entirely from fallback values
                $iview.FindName('HostnameBox').Text        = $hostname
                $iview.FindName('MakeBox').Text            = $fbMake
                $iview.FindName('ModelBox').Text           = $fbModel
                $iview.FindName('UptimeBox').Text          = $fbUptime
                $iview.FindName('PortCountBox').Text       = $fbPorts
                $iview.FindName('AuthDefaultVLANBox').Text = $fbAuthDef
                $iview.FindName('BuildingBox').Text        = $fbBuilding
                $iview.FindName('RoomBox').Text            = $fbRoom
                # Emit debug information when no summary exists
                Write-Host "[DEBUG] No summary row found for ${hostname}. Using fallback values: Make='$fbMake', Model='$fbModel', Uptime='$fbUptime', Ports='$fbPorts', AuthDefaultVLAN='$fbAuthDef', Building='$fbBuilding', Room='$fbRoom'" -ForegroundColor DarkMagenta
                # Additional diagnostics: list all DeviceSummary rows so we can inspect raw hostnames and values
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
            # Load interface information using Get-InterfaceInfo (which already queries DB)
            $gridCtrl = $iview.FindName('InterfacesGrid')
            $gridCtrl.ItemsSource = Get-InterfaceInfo -Hostname $hostname
            # Load available configuration templates
            $comboCtrl = $iview.FindName('ConfigOptionsDropdown')
            $comboCtrl.ItemsSource = Get-ConfigurationTemplates -Hostname $hostname
            if ($comboCtrl -and $comboCtrl.Items.Count -gt 0) {
                # select first template via index to avoid SelectedItem exceptions
                $comboCtrl.SelectedIndex = 0
            } else {
                if ($comboCtrl) { $comboCtrl.SelectedIndex = -1 }
            }
        } else {
            # When the database is unavailable, do not attempt to load legacy CSV
            # files.  Simply clear the detail fields and populate the interface
            # grid and configuration dropdown with empty data.  This enforces
            # the database as the single source of truth for all device
            # information.
            $iview = $global:interfacesView
            if ($iview) {
                $iview.FindName('HostnameBox').Text        = $hostname
                $iview.FindName('MakeBox').Text            = ''
                $iview.FindName('ModelBox').Text           = ''
                $iview.FindName('UptimeBox').Text          = ''
                $iview.FindName('PortCountBox').Text       = ''
                $iview.FindName('AuthDefaultVLANBox').Text = ''
                $iview.FindName('BuildingBox').Text        = ''
                $iview.FindName('RoomBox').Text            = ''
                $gridCtrl = $iview.FindName('InterfacesGrid')
                if ($gridCtrl) { $gridCtrl.ItemsSource = @() }
                $comboCtrl = $iview.FindName('ConfigOptionsDropdown')
                if ($comboCtrl) {
                    $comboCtrl.ItemsSource = @()
                    $comboCtrl.SelectedIndex = -1
                }
            }
        }
    } catch {
        [System.Windows.MessageBox]::Show("Error loading ${hostname}:`n$($_.Exception.Message)")
    }
}

function Update-GlobalInterfaceList {
    # Populate the global interface list either from the database (when available)
    # or from legacy CSV files.  When using the database, join Interfaces
    # with DeviceSummary to retrieve site/building/room metadata.  When the
    # database is unavailable or the query fails, fall back to reading
    # interface CSVs in ParsedData.
    # Reset the global interface list.  Always rely on the database as the single
    # source of truth.  Legacy CSV fallbacks have been removed.  If the
    # database path is unset or the query fails, the list will remain empty.
    $list = @()
    if ($global:StateTraceDb) {
        try {
            # Import DatabaseModule relative to project root
            $rootDir   = if ($scriptDir) { (Join-Path $scriptDir '..') } else { (Join-Path $PSScriptRoot '..') }
            $dbModule  = Join-Path (Join-Path $rootDir 'Modules') 'DatabaseModule.psm1'
            if (Test-Path $dbModule) {
                # Import DatabaseModule globally so Invoke-DbQuery is visible across modules
                Import-Module $dbModule -Force -Global -ErrorAction Stop | Out-Null
            }
            # Query all interfaces with site/building/room via a LEFT JOIN
            $sql = @"
SELECT i.Hostname, i.Port, i.Name, i.Status, i.VLAN, i.Duplex, i.Speed, i.Type, i.LearnedMACs,
       i.AuthState, i.AuthMode, i.AuthClientMAC,
       ds.Site, ds.Building, ds.Room
FROM Interfaces AS i
LEFT JOIN DeviceSummary AS ds ON i.Hostname = ds.Hostname
ORDER BY i.Hostname, i.Port
"@
            $dt = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql $sql
            foreach ($row in ($dt | Select-Object Hostname, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, Site, Building, Room)) {
                $list += [PSCustomObject]@{
                    Hostname      = $row.Hostname
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
                    Site          = if ($row.Site)     { [string]$row.Site }     else { '' }
                    Building      = if ($row.Building) { [string]$row.Building } else { '' }
                    Room          = if ($row.Room)     { [string]$row.Room }     else { '' }
                }
            }
        } catch {
            Write-Warning "Failed to rebuild interface list from database: $($_.Exception.Message)"
        }
    } else {
        Write-Warning "Database not configured. Interface list will be empty."
    }
    $global:AllInterfaces = $list
    # After rebuilding the interface list, update summary metrics and alerts.
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
                    # If the regex is invalid, fall back to case‑insensitive substring search
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
    $gridCtrl.ItemsSource = Update-SearchResults -Term $term
}

# Export the functions defined in this module.  Specify them on a single line
# to avoid parsing issues caused by line continuations.  Backticks are not
# necessary when listing multiple function names separated by commas.
Export-ModuleMember -Function Get-DeviceSummaries, Update-DeviceFilter, Get-DeviceDetails, Update-GlobalInterfaceList, Update-SearchResults, Update-Summary, Update-Alerts, Update-SearchGrid