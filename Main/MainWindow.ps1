Add-Type -AssemblyName PresentationFramework

# 1) Paths
$scriptDir           = Split-Path -Parent $MyInvocation.MyCommand.Path
$parserScript        = Join-Path $scriptDir '.\NetworkReader.ps1'
$interfaceModulePath = Join-Path $scriptDir '..\Modules\InterfaceModule.psm1'
$interfacesViewXaml  = Join-Path $scriptDir '..\Views\InterfacesView.xaml'


# 2) Import Interfaces module
if (-not (Test-Path $interfaceModulePath)) {
    Write-Error "Cannot find InterfaceModule at $interfaceModulePath"
    exit 1
}
Import-Module $interfaceModulePath -Force

# 2a) Import Database module and ensure the database exists
$dbModulePath = Join-Path $scriptDir '..\Modules\DatabaseModule.psm1'
if (Test-Path $dbModulePath) {
    # Import the DatabaseModule globally so that its functions (e.g. Invoke-DbQuery) are available to all modules
    Import-Module $dbModulePath -Force -Global
        try {
            # Attempt to create a modern .accdb database first.  This will use the
            # ACE OLEDB provider if installed.  If the provider is unavailable
            # or creation fails, fall back to creating a .mdb using the Jet
            # provider.  Store the resulting path globally for later use.
            $dataDir = Join-Path $scriptDir '..\Data'
            if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }
            $accdbPath = Join-Path $dataDir 'StateTrace.accdb'
            try {
                $global:StateTraceDb = New-AccessDatabase -Path $accdbPath
            } catch {
                Write-Warning "Failed to create .accdb database: $($_.Exception.Message). Falling back to .mdb."
                $mdbPath = Join-Path $dataDir 'StateTrace.mdb'
                $global:StateTraceDb = New-AccessDatabase -Path $mdbPath
            }
        } catch {
            Write-Warning "Database initialization failed: $_"
        }
} else {
    Write-Warning "Database module not found at $dbModulePath. Parsed results will continue to use CSV files."
}

# 3) Load MainWindow.xaml
$xamlPath = Join-Path $scriptDir 'MainWindow.xaml'
if (-not (Test-Path $xamlPath)) {
    Write-Error "Cannot find MainWindow.xaml at $xamlPath"
    exit 1
}
$xamlContent = Get-Content $xamlPath -Raw
$reader      = New-Object System.Xml.XmlTextReader (New-Object System.IO.StringReader($xamlContent))
$window      = [Windows.Markup.XamlReader]::Load($reader)

Set-Variable -Name window -Value $window -Scope Global

# 4) Helpers

function Load-DeviceSummaries {
    # If a database path is defined, query the DeviceSummary table for hostnames
    # and location metadata.  Otherwise fall back to loading from CSV files in
    # the ParsedData folder.  The DeviceMetadata dictionary maps hostnames to
    # their site/building/room values.  This data drives the Site/Building/Room
    # dropdowns.
    $names = @()
    $global:DeviceMetadata = @{}
    $useDb = $false
    if ($global:StateTraceDb) { $useDb = $true }
    # Debug: indicate whether we are using the database
    Write-Host "[DEBUG] Device summaries from DB: $useDb" -ForegroundColor DarkGray

    if ($useDb) {
        try {
            $dt = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT Hostname, Site, Building, Room FROM DeviceSummary ORDER BY Hostname"
            # Convert the DataTable into simple PSObjects via Select-Object to avoid
            # DataRow indexing issues.  This ensures each row exposes its columns as
            # properties and avoids the "Cannot index into a null array" error.
            $rows = $dt | Select-Object Hostname, Site, Building, Room
            foreach ($row in $rows) {
                $name = $row.Hostname
                if (-not [string]::IsNullOrWhiteSpace($name)) {
                    $names += $name
                    # Handle null/DBNull values for location metadata by
                    # substituting empty strings.  Cast to string to ensure
                    # consistent comparisons in dropdown filters.
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
                    if (-not $global:DeviceMetadata) { $global:DeviceMetadata = @{} }
                    $global:DeviceMetadata[$name] = $meta
                }
            }
            Write-Host "[DEBUG] Loaded $($names.Count) device(s) from DB" -ForegroundColor DarkGray
        } catch {
            Write-Warning "Failed to query device summaries from database: $($_.Exception.Message)"
            $useDb = $false
        }
    }

    if (-not $useDb) {
        # Retrieve a list of device hostnames from the parsed data directory
        $names = Get-DeviceSummaries
        foreach ($name in $names) {
            $summaryPath = Join-Path (Join-Path $scriptDir '..\ParsedData') "${name}_Summary.csv"
            if (Test-Path $summaryPath) {
                try {
                    $rec = @(Import-Csv $summaryPath)[0]
                    $meta = [PSCustomObject]@{
                        Site     = if ($rec.PSObject.Properties.Match('Site'))     { $rec.Site }     else { '' }
                        Building = if ($rec.PSObject.Properties.Match('Building')) { $rec.Building } else { '' }
                        Room     = if ($rec.PSObject.Properties.Match('Room'))     { $rec.Room }     else { '' }
                    }
                    $global:DeviceMetadata[$name] = $meta
                } catch {
                    # Skip devices that fail to load metadata
                }
            }
        }
        Write-Host "[DEBUG] Loaded $($names.Count) device(s) from CSV" -ForegroundColor DarkGray
    }

    # Populate the host dropdown initially with all names.  Filtering will be
    # applied through the Site/Building/Room dropdowns.  Use ItemsSource
    # assignment to refresh the list.
    $hostnameDD = $window.FindName('HostnameDropdown')
    $hostnameDD.ItemsSource = $names
    # Select the first element by item rather than index to avoid touching
    # built‑in PowerShell variables.  If there are no names, clear selection.
    if ($names -and $names.Count -gt 0) {
        $hostnameDD.SelectedItem = $names[0]
    } else {
        $hostnameDD.SelectedItem = $null
    }

    # Populate the site dropdown with unique site codes.  Include an empty
    # option at the beginning to represent "all sites".  Sort the list for
    # consistent ordering.  Only devices that produced metadata contribute
    # entries.
    $siteDD = $window.FindName('SiteDropdown')
    $uniqueSites = @()
    if ($DeviceMetadata.Count -gt 0) {
        $uniqueSites = $DeviceMetadata.Values | ForEach-Object { $_.Site } | Where-Object { $_ -ne '' } | Sort-Object -Unique
    }
    $siteDD.ItemsSource = @('') + $uniqueSites
    if ($siteDD.ItemsSource -and $siteDD.ItemsSource.Count -gt 0) {
        $siteDD.SelectedItem = $siteDD.ItemsSource[0]
    } else {
        $siteDD.SelectedItem = $null
    }

    # Clear the building and room dropdowns until a site is selected
    $buildingDD = $window.FindName('BuildingDropdown')
    $buildingDD.ItemsSource = @('')
    if ($buildingDD.ItemsSource -and $buildingDD.ItemsSource.Count -gt 0) {
        $buildingDD.SelectedItem = $buildingDD.ItemsSource[0]
    } else {
        $buildingDD.SelectedItem = $null
    }
    $buildingDD.IsEnabled = $false

    $roomDD = $window.FindName('RoomDropdown')
    if ($roomDD) {
        $roomDD.ItemsSource = @('')
        # Select the blank entry via SelectedItem
        $roomDD.SelectedItem = ''
        # Disable the Room dropdown initially.  It will be re‑enabled once
        # both a site and building have been selected via Update‑DeviceFilter.
        $roomDD.IsEnabled = $false
    }

    # Refresh the global interface list used by the search tab (if defined)
    if (Get-Command Rebuild-GlobalInterfaceList -ErrorAction SilentlyContinue) {
        Rebuild-GlobalInterfaceList
        # If the search grid has been initialized, refresh its ItemsSource to
        # show all interfaces for the newly loaded data.
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

# Update the device dropdown based on the currently selected Site, Building and Room.
# This helper constructs a filtered list of hostnames from $DeviceMetadata.  It
# also repopulates the Building and Room dropdowns so the available values
# reflect the current site or building selection.  An empty selection for any
# dropdown represents "all".
function Update-DeviceFilter {
    if (-not $global:DeviceMetadata) { return }

    $siteSel = $window.FindName('SiteDropdown').SelectedItem
    $bldSel  = $window.FindName('BuildingDropdown').SelectedItem
    $roomSel = $window.FindName('RoomDropdown').SelectedItem

    Write-Host "[DEBUG] Filtering devices by site='$siteSel', building='$bldSel', room='$roomSel'" -ForegroundColor DarkGray

    # Filter hostnames based on selections
    $filteredNames = @()
    foreach ($name in $DeviceMetadata.Keys) {
        $meta = $DeviceMetadata[$name]
        if ($siteSel -and $siteSel -ne '' -and $meta.Site -ne $siteSel) { continue }
        if ($bldSel  -and $bldSel  -ne '' -and $meta.Building -ne $bldSel) { continue }
        if ($roomSel -and $roomSel -ne '' -and $meta.Room     -ne $roomSel) { continue }
        $filteredNames += $name
    }
    Write-Host "[DEBUG] Device filter matched $($filteredNames.Count) host(s)" -ForegroundColor DarkGray

    # Repopulate hostname dropdown
    $hostnameDD = $window.FindName('HostnameDropdown')
    $hostnameDD.ItemsSource = $filteredNames
    # Assign selection using SelectedItem to avoid modifying the read-only
    # PowerShell $Host variable
    if ($filteredNames.Count -gt 0) {
        $hostnameDD.SelectedItem = $filteredNames[0]
    } else {
        $hostnameDD.SelectedItem = $null
    }

    # Rebuild building dropdown options based on the selected site
    $availableBuildings = @()
    foreach ($name in $DeviceMetadata.Keys) {
        $meta = $DeviceMetadata[$name]
        if ($siteSel -and $siteSel -ne '' -and $meta.Site -ne $siteSel) { continue }
        if ($meta.Building -ne '') { $availableBuildings += $meta.Building }
    }
    $availableBuildings = $availableBuildings | Sort-Object -Unique
    $buildingDD = $window.FindName('BuildingDropdown')
    $buildingDD.ItemsSource = @('') + $availableBuildings
    # Preserve previously selected building if still valid
    if ($bldSel -and ($availableBuildings -contains $bldSel)) {
        $buildingDD.SelectedItem = $bldSel
    } else {
        # Default to blank when nothing matches
        if ($buildingDD.ItemsSource.Count -gt 0) {
            $buildingDD.SelectedItem = $buildingDD.ItemsSource[0]
        } else {
            $buildingDD.SelectedItem = $null
        }
        $bldSel = ''
    }

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
    $roomDD = $window.FindName('RoomDropdown')
    if ($roomDD) {
        $roomDD.ItemsSource = @('') + $availableRooms
        if ($roomSel -and ($availableRooms -contains $roomSel)) {
            $roomDD.SelectedItem = $roomSel
        } else {
            if ($roomDD.ItemsSource.Count -gt 0) {
                $roomDD.SelectedItem = $roomDD.ItemsSource[0]
            } else {
                $roomDD.SelectedItem = $null
            }
        }

        # Enable or disable the Room dropdown.  The Room selection
        # should only be possible once both a site and a building have
        # been chosen.  If either the site or building is blank, the
        # Room dropdown is disabled; otherwise it is enabled.
        if (($siteSel -and $siteSel -ne '') -and ($buildingDD.SelectedItem -and $buildingDD.SelectedItem -ne '')) {
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
    if (Get-Command Refresh-SearchGrid -ErrorAction SilentlyContinue) {
        Refresh-SearchGrid
    }

    # Update summary and alerts when the location filters change.  This allows
    # the Summary tab and Alerts tab to reflect the selected site, building
    # and room.  Only call these helpers if defined.
    if (Get-Command Update-Summary -ErrorAction SilentlyContinue) {
        Update-Summary
    }
    if (Get-Command Compute-Alerts -ErrorAction SilentlyContinue) {
        Compute-Alerts
    }
}

function Load-DeviceDetails {
    param($hostname)
    try {
        Write-Host "[DEBUG] Loading details for host '$hostname'" -ForegroundColor DarkGray
        $useDb = $false
        if ($global:StateTraceDb) { $useDb = $true }
        Write-Host "[DEBUG] Using database: $useDb" -ForegroundColor DarkGray

        if ($useDb) {
            # Query summary information for the selected device using a robust SQL query.  Perform a case‑insensitive comparison
            # on the trimmed hostname and allow for trailing characters by also using a LIKE predicate.  This avoids
            # retrieving the entire table and filtering in PowerShell, and accommodates rows that may contain
            # extraneous whitespace or control characters after the hostname.
            # Trim the hostname before quoting to avoid matching against unintended leading/trailing whitespace.
            $hostTrim = ($hostname -as [string]).Trim()
            $escHost   = $hostTrim -replace "'", "''"
            # Emit diagnostic information about the incoming hostname.  Output the trimmed string, its length,
            # and the numeric character codes to detect hidden characters that Trim() may not remove.
            $charCodes = ($hostTrim.ToCharArray() | ForEach-Object { [int]$_ }) -join ','
            Write-Host "[DEBUG] hostTrim='$hostTrim' (Len=$($hostTrim.Length)) Codes=[$charCodes]" -ForegroundColor Yellow
            # Build a summary query that avoids provider‑specific functions.  Use explicit LIKE predicates and Trim() where supported.
            # Access databases are generally case‑insensitive, so comparing without UCASE should still match regardless of case.
            # NOTE: When querying an Access database via the Jet/ACE providers the
            # wildcard characters for LIKE are '*' and '?', not '%' and '_'.
            # Using '%' will silently return zero rows in many circumstances.
            # Compose a query that looks for an exact match on Hostname and
            # performs a case‑insensitive substring match using '*'.  See:
            # https://learn.microsoft.com/en-us/office/client-developer/access/desktop-database-reference/like-operator-microsoft-access-sql
            $summarySql = "SELECT Hostname, Make, Model, Uptime, Ports, AuthDefaultVLAN, Building, Room " +
                          "FROM DeviceSummary " +
                          "WHERE Hostname = '$escHost' " +
                          "   OR Hostname LIKE '*$escHost*'"
            $dtSummary = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql $summarySql
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
            # Convert to an array of PSObjects.  Without wrapping in @(), a single returned row will be a single
            # object rather than an array, which causes .Count to be $null and the summary check to fail.
            $summaryObjects = @()
            if ($dtSummary) {
                $summaryObjects = @($dtSummary | Select-Object Hostname, Make, Model, Uptime, Ports, AuthDefaultVLAN, Building, Room)
            }
            # Also retrieve all summary rows for diagnostics.  This can be used for debugging when no match is found.
            $dtSummaryAll = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT Hostname, Make, Model, Uptime, Ports, AuthDefaultVLAN, Building, Room FROM DeviceSummary"
            # Log how many summary rows matched this hostname
            Write-Host "[DEBUG] Summary rows returned: $($summaryObjects.Count)" -ForegroundColor DarkGray
            # Compute fallback values from DeviceHistory and Interface count.  These are used
            # when the summary table is missing or contains null/blank values.  The
            # queries run once here so we can reference the results for each field.
            # Use the same trimmed hostname for fallback queries
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
            } catch {
                # ignore history failures
            }
            try {
                # Use a named alias for the count to avoid provider‑generated column names
                $cntDt = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT COUNT(*) AS PortCount FROM Interfaces WHERE Trim(Hostname) = '$esc'"
                if ($cntDt -and $cntDt.Rows.Count -gt 0) {
                    $fbPorts = ($cntDt | Select-Object -ExpandProperty PortCount)[0]
                }
            } catch {
                # ignore count failures
            }

            if ($summaryObjects.Count -gt 0) {
                # Populate device details from the DeviceSummary table when present.  Use
                # fallback values for fields that are null, DBNull or empty.
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
                # Emit debug information about the summary and fallback values
                Write-Host "[DEBUG] Summary values for ${hostname}: Make='$($row.Make)', Model='$($row.Model)', Uptime='$($row.Uptime)', Ports='$($row.Ports)', AuthDefaultVLAN='$($row.AuthDefaultVLAN)', Building='$($row.Building)', Room='$($row.Room)'" -ForegroundColor DarkCyan
                Write-Host "[DEBUG] Fallback values: Make='$fbMake', Model='$fbModel', Uptime='$fbUptime', Ports='$fbPorts', AuthDefaultVLAN='$fbAuthDef', Building='$fbBuilding', Room='$fbRoom'" -ForegroundColor DarkMagenta
            } else {
                # Populate controls using fallback values when no summary exists.  Always
                # set the hostname.
                $interfacesView.FindName('HostnameBox').Text        = $hostname
                $interfacesView.FindName('MakeBox').Text            = $fbMake
                $interfacesView.FindName('ModelBox').Text           = $fbModel
                $interfacesView.FindName('UptimeBox').Text          = $fbUptime
                $interfacesView.FindName('PortCountBox').Text       = $fbPorts
                $interfacesView.FindName('AuthDefaultVLANBox').Text = $fbAuthDef
                $interfacesView.FindName('BuildingBox').Text        = $fbBuilding
                $interfacesView.FindName('RoomBox').Text            = $fbRoom
                # Emit debug information when no summary exists
                Write-Host "[DEBUG] No summary row found for ${hostname}. Using fallback values: Make='$fbMake', Model='$fbModel', Uptime='$fbUptime', Ports='$fbPorts', AuthDefaultVLAN='$fbAuthDef', Building='$fbBuilding', Room='$fbRoom'" -ForegroundColor DarkMagenta

                # Additional diagnostics: enumerate all DeviceSummary rows to see what hostnames are present.  This can
                # help identify trailing spaces or other characters that prevent matching.  Output the raw and trimmed
                # hostnames along with lengths and select key fields.
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
            # Query interfaces for the selected device including compliance fields
            $dtIfs = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT Hostname, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, ConfigStatus, PortColor, ToolTip FROM Interfaces WHERE Hostname = '$($hostname -replace "'", "''")'"
            # Convert to PSObjects to avoid DataRow indexing issues
            $ifObjects = $dtIfs | Select-Object Hostname, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, ConfigStatus, PortColor, ToolTip
            Write-Host "[DEBUG] Interface rows returned: $($ifObjects.Count)" -ForegroundColor DarkGray
            $list = @()
            foreach ($r in $ifObjects) {
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
                    ToolTip       = $r.ToolTip
                    IsSelected    = $false
                    ConfigStatus  = if ($r.ConfigStatus) { $r.ConfigStatus } else { 'Unknown' }
                    PortColor     = if ($r.PortColor) { $r.PortColor } else { 'Gray' }
                }
                $list += $obj
            }
            $grid = $interfacesView.FindName('InterfacesGrid')
            $grid.ItemsSource = $list
            # Populate configuration template dropdown normally by reading JSON
            $combo = $interfacesView.FindName('ConfigOptionsDropdown')
            $combo.ItemsSource = Get-ConfigurationTemplates -Hostname $hostname
            if ($combo.Items.Count -gt 0) { $combo.SelectedItem = $combo.Items[0] }
        } else {
            # Fall back to CSV-based loading
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
            if ($combo.Items.Count -gt 0) { $combo.SelectedItem = $combo.Items[0] }
        }
    } catch {
        [System.Windows.MessageBox]::Show("Error loading ${hostname}:`n$($_.Exception.Message)")
    }
}

# 5) Inject InterfacesView
if (Test-Path $interfacesViewXaml) {
    $ifaceXaml     = Get-Content $interfacesViewXaml -Raw
    $ifaceReader   = New-Object System.Xml.XmlTextReader (New-Object System.IO.StringReader($ifaceXaml))
    $interfacesView= [Windows.Markup.XamlReader]::Load($ifaceReader)

    $interfacesHost = $window.FindName('InterfacesHost')
    if ($interfacesHost -is [System.Windows.Controls.ContentControl]) {
        $interfacesHost.Content = $interfacesView
    } else {
        Write-Warning "Could not find ContentControl 'InterfacesHost'"
    }

    $compareButton      = $interfacesView.FindName('CompareButton')
    $interfacesGrid     = $interfacesView.FindName('InterfacesGrid')
    $configureButton    = $interfacesView.FindName('ConfigureButton')
    $templateDropdown   = $interfacesView.FindName('ConfigOptionsDropdown')
    $filterBox          = $interfacesView.FindName('FilterBox')
    $clearBtn           = $interfacesView.FindName('ClearFilterButton')
    $copyDetailsButton  = $interfacesView.FindName('CopyDetailsButton')

    # 5b) Compare button
    if ($compareButton -and $interfacesGrid) {
        $compareButton.Add_Click({
            $selected = $interfacesGrid.ItemsSource | Where-Object { $_.IsSelected }
            if ($selected.Count -ne 2) {
                [System.Windows.MessageBox]::Show("Select exactly two interfaces to compare.")
                return
            }

            $int1 = $selected[0]
            $int2 = $selected[1]

            try {
                Compare-InterfaceConfigs `
                    -Switch1 $int1.Hostname -Interface1 $int1.Port `
                    -Switch2 $int2.Hostname -Interface2 $int2.Port
            } catch {
                [System.Windows.MessageBox]::Show("Compare failed:`n$($_.Exception.Message)")
            }
        })
    }

    # 5c) Configure button
    if ($configureButton -and $interfacesGrid -and $templateDropdown) {
        $configureButton.Add_Click({
            $selected = $interfacesGrid.ItemsSource | Where-Object { $_.IsSelected }
            if (-not $selected) {
                [System.Windows.MessageBox]::Show("No interfaces selected.")
                return
            }

            $template = $templateDropdown.SelectedItem
            if (-not $template) {
                [System.Windows.MessageBox]::Show("No template selected.")
                return
            }

            # Obtain hostname from the detail box in the Interfaces view
            $hostname = $interfacesView.FindName('HostnameBox').Text

            try {
                # Build hashtables containing any modified Name and VLAN values.  When the user
                # edits the Name or VLAN columns in the grid, the underlying objects are
                # updated.  Capture those values so they can be passed along to the
                # configuration generator.  Keys are the port identifiers, values are the
                # overridden names/VLANs.
                $namesMap = @{}
                $vlansMap = @{}
                foreach ($int in $selected) {
                    if ($int.Name -and $int.Name -ne '') { $namesMap[$int.Port] = $int.Name }
                    if ($int.VLAN -and $int.VLAN -ne '') { $vlansMap[$int.Port] = $int.VLAN }
                }
                $ports = $selected | ForEach-Object { $_.Port }
                $lines = Get-InterfaceConfiguration -Hostname $hostname -Interfaces $ports -TemplateName $template -NewNames $namesMap -NewVlans $vlansMap
                Set-Clipboard -Value ($lines -join "`r`n")
                [System.Windows.MessageBox]::Show(($lines -join "`n"), "Generated Config")
            } catch {
                [System.Windows.MessageBox]::Show("Failed to build config:`n$($_.Exception.Message)")
            }
        })
    }

    # 5d) Filter logic
    if ($clearBtn -and $filterBox -and $interfacesGrid) {
        $clearBtn.Add_Click({
            $filterBox.Text = ""
            $filterBox.Focus()
        })
    }

    if ($filterBox -and $interfacesGrid) {
        $filterBox.Add_TextChanged({
            $text = $filterBox.Text.ToLower()
            $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($interfacesGrid.ItemsSource)
            if ($null -eq $view) { return }

            $view.Filter = {
                param ($item)
                return (
                    ($item.Port       -as [string]).ToLower().Contains($text) -or
                    ($item.Name       -as [string]).ToLower().Contains($text) -or
                    ($item.Status     -as [string]).ToLower().Contains($text) -or
                    ($item.VLAN       -as [string]).ToLower().Contains($text) -or
                    ($item.AuthState  -as [string]).ToLower().Contains($text)
                )
            }
            $view.Refresh()
        })
    }

    # 5e) Copy Details button
    if ($copyDetailsButton -and $interfacesGrid) {
        $copyDetailsButton.Add_Click({
            $selected = $interfacesGrid.ItemsSource | Where-Object { $_.IsSelected }
            if (-not $selected -or $selected.Count -eq 0) {
                [System.Windows.MessageBox]::Show("No interfaces selected.")
                return
            }

            # Obtain hostname from the detail box in the Interfaces view
            $hostname = $interfacesView.FindName('HostnameBox').Text
            $summaryPath = Join-Path (Join-Path $scriptDir '..\ParsedData') "${hostname}_Summary.csv"

            $authBlock = ""
            if (Test-Path $summaryPath) {
                $summary = @(Import-Csv $summaryPath)[0]
                if ($summary.AuthBlock -and $summary.AuthBlock.Trim() -ne "") {
                    $authBlock = $summary.AuthBlock.Trim()
                }
            }

            $header = @("Hostname: $hostname","------------------------------")
            if ($authBlock -ne "") {
                $header += @("Auth Block:", $authBlock, "","------------------------------")
            } else {
                $header += ""
            }

            $output = foreach ($int in $selected) {
                $lines = @(
                    "Port:        $($int.Port)"
                    "Name:        $($int.Name)"
                    "Status:      $($int.Status)"
                    "VLAN:        $($int.VLAN)"
                    "Duplex:      $($int.Duplex)"
                    "Speed:       $($int.Speed)"
                    "Type:        $($int.Type)"
                    "LearnedMACs: $($int.LearnedMACs)"
                    "AuthState:   $($int.AuthState)"
                    "AuthMode:    $($int.AuthMode)"
                    "Client MAC:  $($int.AuthClientMAC)"
                    "Config:"
                    "$($int.ToolTip)"
                    "------------------------------"
                )
                $lines -join "`r`n"
            }

            $final = $header + $output
            Set-Clipboard -Value ($final -join "`r`n")

            [System.Windows.MessageBox]::Show("Copied $($selected.Count) interface(s) with auth block to clipboard.")
        })
    }

    # 5f) Colour-code the configuration dropdown based on the selected template name.
    if ($templateDropdown) {
        $templateDropdown.Add_SelectionChanged({
            $sel = $templateDropdown.SelectedItem
            # Default colour (black) if nothing matches
            $brush = [System.Windows.Media.Brushes]::Black
            if ($sel) {
                $name = '' + $sel
                $lower = $name.ToLower()
                if ($lower -match 'cisco') {
                    $brush = [System.Windows.Media.Brushes]::DodgerBlue
                } elseif ($lower -match 'brocade') {
                    $brush = [System.Windows.Media.Brushes]::Goldenrod
                } elseif ($lower -match 'arista') {
                    $brush = [System.Windows.Media.Brushes]::MediumSeaGreen
                }
            }
            $templateDropdown.Foreground = $brush
        })
    }
    
} else {
    Write-Warning "Missing InterfacesView.xaml at $interfacesViewXaml"
}

# 5c) Inject SpanView
$spanViewXamlPath = Join-Path $scriptDir '..\Views\SpanView.xaml'
if (Test-Path $spanViewXamlPath) {
    $spanXaml   = Get-Content $spanViewXamlPath -Raw
    $spanReader = New-Object System.Xml.XmlTextReader (New-Object System.IO.StringReader($spanXaml))
    $spanView   = [Windows.Markup.XamlReader]::Load($spanReader)
    $spanHost   = $window.FindName('SpanHost')
    if ($spanHost -is [System.Windows.Controls.ContentControl]) {
        $spanHost.Content = $spanView
    } else {
        Write-Warning "Could not find ContentControl 'SpanHost'"
    }
    # Access controls
    $spanGrid     = $spanView.FindName('SpanGrid')
    $vlanDropdown = $spanView.FindName('VlanDropdown')
    $spanRefresh  = $spanView.FindName('RefreshSpanButton')

    # Helper to load spanning tree data for the currently selected device.  It
    # populates the grid and VLAN dropdown.  If no data exists for the
    # device, the grid will be cleared and the dropdown reset.
    function Load-SpanInfo {
        param([string]$Hostname)
        if (-not $spanGrid) { return }
        # If no hostname provided, clear the grid and dropdown
        if (-not $Hostname) {
            $spanGrid.ItemsSource = @()
            if ($vlanDropdown) {
                $vlanDropdown.ItemsSource = @('')
                # When clearing the dropdown use SelectedItem instead of SelectedIndex. Using
                # SelectedIndex can inadvertently attempt to set the built‑in $Host variable
                # which is read‑only and will throw an exception.  Selecting the first item
                # via SelectedItem avoids this pitfall.
                if ($vlanDropdown.ItemsSource.Count -gt 0) {
                    $vlanDropdown.SelectedItem = $vlanDropdown.ItemsSource[0]
                } else {
                    $vlanDropdown.SelectedItem = $null
                }
            }
            return
        }
        # Retrieve spanning tree data for the hostname.  Import failures
        # return an empty collection.
        try {
            $data = Get-SpanningTreeInfo -Hostname $Hostname
        } catch {
            $data = @()
        }
        $spanGrid.ItemsSource = $data
        if ($vlanDropdown) {
            $instances = ($data | ForEach-Object { $_.VLAN }) | Sort-Object -Unique
            $vlanDropdown.ItemsSource = @('') + $instances
            # Select the first item safely using SelectedItem.  Avoid SelectedIndex to
            # prevent conflicts with the PowerShell $Host variable.
            if ($vlanDropdown.ItemsSource -and $vlanDropdown.ItemsSource.Count -gt 0) {
                $vlanDropdown.SelectedItem = $vlanDropdown.ItemsSource[0]
            } else {
                $vlanDropdown.SelectedItem = $null
            }
        }
    }
    # Handler for VLAN dropdown filtering
    if ($vlanDropdown) {
        $vlanDropdown.Add_SelectionChanged({
            $sel = $vlanDropdown.SelectedItem
            if (-not $spanGrid) { return }
            # Retrieve the currently selected hostname.  Use a local variable
            # name other than $host to avoid conflict with the built‑in $Host
            # variable (PowerShell is case‑insensitive, so $host would
            # reference the same read‑only Host object).
            $selectedHost = $window.FindName('HostnameDropdown').SelectedItem
            if (-not $selectedHost) { return }
            # Reload data for the host
            $all = Get-SpanningTreeInfo -Hostname $selectedHost
            if (-not $sel -or $sel -eq '') {
                $spanGrid.ItemsSource = $all
            } else {
                $spanGrid.ItemsSource = $all | Where-Object { $_.VLAN -eq $sel }
            }
        })
    }
    # Refresh button to reparse logs for spanning tree info.  This triggers
    # log parsing like the main refresh button and then reloads the span info.
    if ($spanRefresh) {
        $spanRefresh.Add_Click({
            # Set the database path environment variable if defined
            if ($global:StateTraceDb) { $env:StateTraceDbPath = $global:StateTraceDb }
            # Run the parser script to update parsed data (honouring archive flags).  Reuse
            # environment variables from the main refresh button.
            & "$parserScript"
            # Reload summaries and span info for selected host.
            Load-DeviceSummaries
            Update-DeviceFilter
            $currentHost = $window.FindName('HostnameDropdown').SelectedItem
            if ($currentHost) { Load-SpanInfo $currentHost }
        })
    }
    # Load span info when host selection changes.  We'll add this in the
    # existing hostname dropdown event after it's defined.
} else {
    Write-Warning "Missing SpanView.xaml at $spanViewXamlPath"
}

# 5a) Inject SearchInterfacesView
$searchViewXamlPath = Join-Path $scriptDir '..\Views\SearchInterfacesView.xaml'
if (Test-Path $searchViewXamlPath) {
    $searchXaml      = Get-Content $searchViewXamlPath -Raw
    $searchReader    = New-Object System.Xml.XmlTextReader (New-Object System.IO.StringReader($searchXaml))
    $searchView      = [Windows.Markup.XamlReader]::Load($searchReader)

    $searchHost      = $window.FindName('SearchInterfacesHost')
    if ($searchHost -is [System.Windows.Controls.ContentControl]) {
        $searchHost.Content = $searchView
    } else {
        Write-Warning "Could not find ContentControl 'SearchInterfacesHost'"
    }

    # Access key controls from the search view
    $searchBox        = $searchView.FindName('SearchBox')
    $searchClearBtn   = $searchView.FindName('SearchClearButton')
    $searchGrid       = $searchView.FindName('SearchInterfacesGrid')

    # Additional controls: regex mode checkbox and export button
    $regexCheckbox    = $searchView.FindName('RegexCheckbox')
    $exportBtn        = $searchView.FindName('ExportSearchButton')

    # Initialise regex search flag and hook events
    $script:SearchRegexEnabled = $false
    if ($regexCheckbox) {
        $regexCheckbox.Add_Checked({
            $script:SearchRegexEnabled = $true
            if (Get-Command Refresh-SearchGrid -ErrorAction SilentlyContinue) { Refresh-SearchGrid }
        })
        $regexCheckbox.Add_Unchecked({
            $script:SearchRegexEnabled = $false
            if (Get-Command Refresh-SearchGrid -ErrorAction SilentlyContinue) { Refresh-SearchGrid }
        })
    }
    # Export current search results to a CSV file
    if ($exportBtn) {
        $exportBtn.Add_Click({
            if (-not $searchGrid) { return }
            $rows = $searchGrid.ItemsSource
            if (-not $rows -or $rows.Count -eq 0) {
                [System.Windows.MessageBox]::Show('No results to export.')
                return
            }
            $dlg = New-Object Microsoft.Win32.SaveFileDialog
            $dlg.Filter = 'CSV files (*.csv)|*.csv|All files (*.*)|*.*'
            $dlg.FileName = 'SearchResults.csv'
            if ($dlg.ShowDialog() -eq $true) {
                $path = $dlg.FileName
                try {
                    $rows | Export-Csv -Path $path -NoTypeInformation
                    [System.Windows.MessageBox]::Show("Exported $($rows.Count) rows to $path", 'Export Complete')
                } catch {
                    [System.Windows.MessageBox]::Show("Failed to export: $($_.Exception.Message)")
                }
            }
        })
    }

    # Additional dropdowns for status/auth filters
    $statusFilter = $searchView.FindName('StatusFilter')
    $authFilter   = $searchView.FindName('AuthFilter')
    if ($statusFilter) {
        $statusFilter.Add_SelectionChanged({
            if (Get-Command Refresh-SearchGrid -ErrorAction SilentlyContinue) { Refresh-SearchGrid }
        })
    }
    if ($authFilter) {
        $authFilter.Add_SelectionChanged({
            if (Get-Command Refresh-SearchGrid -ErrorAction SilentlyContinue) { Refresh-SearchGrid }
        })
    }

    # Build a global interface list for searching.  This will be refreshed
    # whenever Load-DeviceSummaries is invoked (i.e. after log parsing).  Use
    # a script-level variable so the collection persists between searches.
    $global:AllInterfaces = @()
    function Rebuild-GlobalInterfaceList {
        Write-Host "[DEBUG] Rebuild-GlobalInterfaceList: rebuilding interface list" -ForegroundColor Green
        $list = @()
        # When a database is present, build the global interface list from
        # the database rather than the parsed CSV files.  This ensures that
        # the application remains consistent even when the CSVs are deleted
        # or stale.  Join Interfaces to DeviceSummary to obtain location
        # metadata.  Include compliance fields for later use.
        if ($global:StateTraceDb) {
            try {
                $sql = "SELECT i.Hostname, i.Port, i.Name, i.Status, i.VLAN, i.Duplex, i.Speed, i.Type, i.LearnedMACs, i.AuthState, i.AuthMode, i.AuthClientMAC, i.ConfigStatus, i.PortColor, i.ToolTip, d.Site, d.Building, d.Room FROM Interfaces AS i INNER JOIN DeviceSummary AS d ON i.Hostname = d.Hostname"
                $dt = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql $sql
                $rows = $dt | Select-Object Hostname, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, ConfigStatus, PortColor, ToolTip, Site, Building, Room
                foreach ($r in $rows) {
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
                        ConfigStatus  = $r.ConfigStatus
                        PortColor     = $r.PortColor
                        ToolTip       = $r.ToolTip
                        Site          = [string]$r.Site
                        Building      = [string]$r.Building
                        Room          = [string]$r.Room
                    }
                    $list += $obj
                }
                Write-Host "[DEBUG] Rebuild-GlobalInterfaceList: built $($list.Count) interface record(s) from DB" -ForegroundColor Green
            } catch {
                Write-Warning "Failed to rebuild interface list from database: $($_.Exception.Message)"
            }
        }
        # Fall back to CSV-based rebuild when no database is available or when
        # database query fails.  Preserve existing behaviour for legacy
        # scenarios.  Only execute this block when the list is still empty.
        if (-not $list -or $list.Count -eq 0) {
            # Determine the parsed data directory relative to this script
            $parsedDir = Join-Path $scriptDir '..\ParsedData'
            if (-not (Test-Path $parsedDir)) {
                $global:AllInterfaces = @()
                return
            }
            # Enumerate all interface CSVs, including those with dated suffixes
            $files = Get-ChildItem -Path $parsedDir -Filter '*_Interfaces_Combined*.csv' -File
            Write-Host "[DEBUG] Found $($files.Count) interface CSV file(s) in '$parsedDir'" -ForegroundColor Green
            foreach ($f in $files) {
                # Extract hostname by splitting on the first underscore
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
                $parts = $baseName -split '_'
                $hostName = $parts[0]
                # Load summary data for this host to obtain site/building/room
                $summaryPath = Join-Path $parsedDir "$hostName`_Summary.csv"
                $site = ''; $building=''; $room=''
                if (Test-Path $summaryPath) {
                    try {
                        $summary = @(Import-Csv $summaryPath)[0]
                        if ($summary.PSObject.Properties.Name -contains 'Site')     { $site     = [string]$summary.Site }
                        if ($summary.PSObject.Properties.Name -contains 'Building') { $building = [string]$summary.Building }
                        if ($summary.PSObject.Properties.Name -contains 'Room')     { $room     = [string]$summary.Room }
                    } catch {}
                }
                try {
                    $csvData = Import-Csv $f.FullName
                    foreach ($row in $csvData) {
                        $obj = [PSCustomObject]@{}
                        foreach ($prop in $row.PSObject.Properties) {
                            $obj | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
                        }
                        $obj | Add-Member -NotePropertyName Hostname -NotePropertyValue $hostName -Force
                        $obj | Add-Member -NotePropertyName Site      -NotePropertyValue ([string]$site)      -Force
                        $obj | Add-Member -NotePropertyName Building  -NotePropertyValue ([string]$building)  -Force
                        $obj | Add-Member -NotePropertyName Room      -NotePropertyValue ([string]$room)      -Force
                        $list += $obj
                    }
                } catch {}
            }
            Write-Host "[DEBUG] Rebuild-GlobalInterfaceList: built $($list.Count) interface record(s) from CSV" -ForegroundColor Green
        }
        $global:AllInterfaces = $list
        # After rebuilding the interface list, update summary metrics and alerts.
        if (Get-Command Update-Summary -ErrorAction SilentlyContinue) {
            Update-Summary
        }
        if (Get-Command Compute-Alerts -ErrorAction SilentlyContinue) {
            Compute-Alerts
        }
    }
    # Do not rebuild the interface list immediately.  Building the global
    # interface collection can be expensive for large datasets because it
    # imports every `*_Interfaces_Combined.csv` file in the ParsedData
    # folder.  Instead, defer rebuilding until it is actually needed (e.g.
    # when the user performs a search).  This allows the GUI to load
    # quickly while logs continue to be processed in the background.
    # Rebuild-GlobalInterfaceList

    # Filter the global interface list based on the search term.  The term
    # matches across several fields (port, name, learned MACs and auth client
    # MAC).  The search is case-insensitive.
    function Filter-SearchResults {
        param([string]$Term)
        # Log the search term and mode at the start of the function
        Write-Host "[DEBUG] Search term='$Term' regexMode=$script:SearchRegexEnabled" -ForegroundColor DarkGray
        $t = $Term.ToLower()
        # Retrieve the selected Site/Building/Room values once per invocation.  These
        # values are used both in the database query and when filtering the
        # in‑memory list.  An empty string (or null) means "All" and will
        # not restrict the query.
        $siteSel = $window.FindName('SiteDropdown').SelectedItem
        $bldSel  = $window.FindName('BuildingDropdown').SelectedItem
        $roomSel = $window.FindName('RoomDropdown').SelectedItem

        # When a database is present and regex mode is not enabled, query the
        # database directly to filter results.  Otherwise fall back to the
        # in‑memory list.  Building the query at runtime allows filtering
        # by location and simple substring matching on interface fields.
        if ($global:StateTraceDb -and (-not $script:SearchRegexEnabled)) {
            $conditions = @()
            # Location filters
            if ($siteSel -and $siteSel -ne '') {
                $safeSite = $siteSel -replace "'", "''"
                $conditions += "d.Site = '$safeSite'"
            }
            if ($bldSel -and $bldSel -ne '') {
                $safeBld = $bldSel -replace "'", "''"
                $conditions += "d.Building = '$safeBld'"
            }
            if ($roomSel -and $roomSel -ne '') {
                $safeRoom = $roomSel -replace "'", "''"
                $conditions += "d.Room = '$safeRoom'"
            }
            # Simple substring search (non‑regex).  Build LIKE pattern using *
            if (-not [string]::IsNullOrWhiteSpace($Term)) {
                $escaped = ($Term -replace "'", "''")
                # Use % as wildcard for the ACE OLEDB provider.  The Jet provider
                # also accepts % for LIKE comparisons.  Build the pattern
                # accordingly.  Do not use * as it may be interpreted as a
                # literal asterisk by some providers.
                $pattern = "%" + $escaped + "%"
                $conditions += "(UCASE(i.Port) LIKE UCASE('$pattern') OR UCASE(i.Name) LIKE UCASE('$pattern') OR UCASE(i.LearnedMACs) LIKE UCASE('$pattern') OR UCASE(i.AuthClientMAC) LIKE UCASE('$pattern'))"
            }
            # Compose WHERE clause
            $whereSql = ''
            if ($conditions.Count -gt 0) { $whereSql = ' WHERE ' + ($conditions -join ' AND ') }
            # Build a single line SQL to avoid here-string parsing issues
            $sql = "SELECT i.Hostname, i.Port, i.Name, i.Status, i.VLAN, i.Duplex, i.Speed, i.Type, i.LearnedMACs, i.AuthState, i.AuthMode, i.AuthClientMAC, d.Site, d.Building, d.Room FROM Interfaces AS i INNER JOIN DeviceSummary AS d ON i.Hostname = d.Hostname" + $whereSql
            Write-Host "[DEBUG] Executing search query against DB" -ForegroundColor DarkGray
            try {
                $dt = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql $sql
                # Convert the DataTable rows to PSObjects to avoid DataRow
                # indexing issues.  Select-Object produces a sequence of
                # PSCustomObjects with the desired properties.
                $rows = $dt | Select-Object Hostname, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, Site, Building, Room
                $resultList = @()
                foreach ($row in $rows) {
                    $obj = [PSCustomObject]@{
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
                        Site          = [string]$row.Site
                        Building      = [string]$row.Building
                        Room          = [string]$row.Room
                    }
                    $resultList += $obj
                }
                Write-Host "[DEBUG] Search query returned $($resultList.Count) row(s) before filtering" -ForegroundColor DarkGray
                # Apply status and authorization filters in PowerShell to reuse
                # existing semantics.
                # Apply status and authorization filters and ensure the return value is
                # always a collection (even when 0 or 1 elements) so that
                # ItemsSource receives an IEnumerable.  Without the unary
                # comma, a single PSCustomObject would be treated as a scalar
                # value and cause binding errors.
                $filtered = $resultList | Where-Object {
                    $row = $_
                    # Evaluate status filter
                    $statusFilterVal = 'All'
                    $authFilterVal   = 'All'
                    try {
                        $searchHostCtrl = $window.FindName('SearchInterfacesHost')
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
                    if ($statusFilterVal -ne 'All') {
                        $stLower = ($row.Status -as [string]).ToLower()
                        if ($statusFilterVal -eq 'Up') {
                            if ($stLower -ne 'up' -and $stLower -ne 'connected') { return $false }
                        } elseif ($statusFilterVal -eq 'Down') {
                            if ($stLower -ne 'down' -and $stLower -ne 'notconnect') { return $false }
                        }
                    }
                    if ($authFilterVal -ne 'All') {
                        $asLower = ($row.AuthState -as [string]).ToLower()
                        if ($authFilterVal -eq 'Authorized') {
                            if ($asLower -ne 'authorized') { return $false }
                        } elseif ($authFilterVal -eq 'Unauthorized') {
                            if ($asLower -eq 'authorized') { return $false }
                        }
                    }
                    return $true
                }
                return ,$filtered
            } catch {
                Write-Warning "Database search failed: $($_.Exception.Message)"
                # On failure, fall through to the in-memory path
            }
        }

        # FALLBACK: No database or regex-enabled search.  Use the global interface list.
        # Lazily build the interface list on first search.
        if (-not $global:AllInterfaces -or $global:AllInterfaces.Count -eq 0) {
            if (Get-Command Rebuild-GlobalInterfaceList -ErrorAction SilentlyContinue) {
                Rebuild-GlobalInterfaceList
            }
        }
        Write-Host "[DEBUG] Using in-memory list of $($global:AllInterfaces.Count) interface(s)" -ForegroundColor DarkGray
        # Always honour the location (site/building/room) filters, even when
        # the search term is blank.  Retrieve the currently selected Site,
        # Building and Room from the dropdowns on the main window.  An
        # empty selection represents "All" so we do not apply that filter.
        $siteSel = $window.FindName('SiteDropdown').SelectedItem
        $bldSel  = $window.FindName('BuildingDropdown').SelectedItem
        $roomSel = $window.FindName('RoomDropdown').SelectedItem

        # Always return an array even when only a single object matches.
        $filteredInMem = $global:AllInterfaces | Where-Object {
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
                $searchHostCtrl = $window.FindName('SearchInterfacesHost')
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
        return ,$filteredInMem
    }

    # Compute summary metrics and update the Summary tab UI.  This function
    # calculates counts of devices, interfaces, up/down ports, authorized
    # versus unauthorized ports and unique VLANs.  The results are
    # displayed in the SummaryView via TextBlocks.
    function Update-Summary {
        if (-not $global:summaryView) { return }
        # Determine location filters from the main window.  When blank,
        # the filter is treated as "All" and no restriction is applied.
        $siteSel = $null; $bldSel = $null; $roomSel = $null
        try {
            $siteSel  = $window.FindName('SiteDropdown').SelectedItem
            $bldSel   = $window.FindName('BuildingDropdown').SelectedItem
            $roomSel  = $window.FindName('RoomDropdown').SelectedItem
        } catch {}
        if ($global:StateTraceDb) {
            # Compute counts directly from the database using SQL queries.  Build
            # WHERE clauses based on the selected site/building/room.  Use
            # UCASE to perform case-insensitive comparisons for status values.
            $where = '1=1'
            if ($siteSel -and $siteSel -ne '') { $where += " AND Site = '" + ($siteSel -replace "'", "''") + "'" }
            if ($bldSel  -and $bldSel  -ne '') { $where += " AND Building = '" + ($bldSel  -replace "'", "''") + "'" }
            if ($roomSel -and $roomSel -ne '') { $where += " AND Room = '" + ($roomSel -replace "'", "''") + "'" }
            # Device count
            $devCount  = 0
            try {
                $dtDev = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT COUNT(*) AS C FROM DeviceSummary WHERE $where"
                if ($dtDev.Rows.Count -gt 0) { $devCount = [int]$dtDev.Rows[0].C }
            } catch {}
            # Interfaces count and other counts; filter by hostnames in DeviceSummary
            $subQuery = "SELECT Hostname FROM DeviceSummary WHERE $where"
            $intCount = 0; $upCount = 0; $downCount = 0; $authCount = 0; $unauthCount = 0; $uniqueVlansCount = 0
            try {
                $dtInt = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT COUNT(*) AS C FROM Interfaces WHERE Hostname IN ($subQuery)"
                $rInt = ($dtInt | Select-Object -First 1 C)
                if ($rInt) { $intCount = [int]$rInt.C }
                $dtUp  = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT COUNT(*) AS C FROM Interfaces WHERE Hostname IN ($subQuery) AND UCASE(Status) IN ('UP','CONNECTED')"
                $rUp = ($dtUp | Select-Object -First 1 C)
                if ($rUp) { $upCount = [int]$rUp.C }
                $dtDown= Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT COUNT(*) AS C FROM Interfaces WHERE Hostname IN ($subQuery) AND UCASE(Status) IN ('DOWN','NOTCONNECT')"
                $rDown = ($dtDown | Select-Object -First 1 C)
                if ($rDown) { $downCount = [int]$rDown.C }
                $dtAuth= Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT COUNT(*) AS C FROM Interfaces WHERE Hostname IN ($subQuery) AND UCASE(AuthState) = 'AUTHORIZED'"
                $rAuth = ($dtAuth | Select-Object -First 1 C)
                if ($rAuth) { $authCount = [int]$rAuth.C }
                $unauthCount = $intCount - $authCount
                $dtVlan= Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT DISTINCT VLAN FROM Interfaces WHERE Hostname IN ($subQuery) AND VLAN IS NOT NULL AND VLAN <> ''"
                $uniqueVlansCount = ($dtVlan | Select-Object VLAN).Count
            } catch {}
            try {
                $sv = $global:summaryView
                ($sv.FindName('SummaryDevicesCount')).Text      = $devCount.ToString()
                ($sv.FindName('SummaryInterfacesCount')).Text   = $intCount.ToString()
                ($sv.FindName('SummaryUpCount')).Text           = $upCount.ToString()
                ($sv.FindName('SummaryDownCount')).Text         = $downCount.ToString()
                ($sv.FindName('SummaryAuthorizedCount')).Text    = $authCount.ToString()
                ($sv.FindName('SummaryUnauthorizedCount')).Text  = $unauthCount.ToString()
                ($sv.FindName('SummaryUniqueVlansCount')).Text   = $uniqueVlansCount.ToString()
                $ratio = if ($intCount -gt 0) { [math]::Round(($upCount / $intCount) * 100, 1) } else { 0 }
                ($sv.FindName('SummaryExtra')).Text = "Up %: $ratio%"
            } catch {}
        } else {
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
            } catch {}
        }
    }

    # Compute alerts from the global interface list.  An alert is generated for
    # each interface that is down, unauthorized or has a duplex other than
    # full.  The resulting list is stored in $global:AlertsList and
    # automatically bound to the AlertsGrid.
    function Compute-Alerts {
        $alerts = @()
        if ($global:StateTraceDb) {
            try {
                # Query only the necessary columns from the Interfaces table
                $dtAlerts = Invoke-DbQuery -DatabasePath $global:StateTraceDb -Sql "SELECT Hostname, Port, Name, Status, VLAN, Duplex, AuthState FROM Interfaces"
                # Convert to PSObjects via Select-Object to avoid DataRow indexing issues
                $rows = $dtAlerts | Select-Object Hostname, Port, Name, Status, VLAN, Duplex, AuthState
                foreach ($row in $rows) {
                    $reasons = @()
                    $status = '' + $row.Status
                    if ($status) {
                        $statusLow = $status.ToLower()
                        if ($statusLow -eq 'down' -or $statusLow -eq 'notconnect') { $reasons += 'Port down' }
                    }
                    $duplex = '' + $row.Duplex
                    if ($duplex) {
                        $dx = $duplex.ToLower()
                        if ($dx -match 'half') { $reasons += 'Half duplex' }
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
            } catch {
                Write-Warning "Failed to query alerts from database: $($_.Exception.Message)"
            }
        } else {
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
        }
        $global:AlertsList = $alerts
        if ($global:alertsView) {
            try {
                $grid = $global:alertsView.FindName('AlertsGrid')
                if ($grid) { $grid.ItemsSource = $global:AlertsList }
            } catch {}
        }
    }

    # Event handler for search box
    if ($searchBox) {
        $searchBox.Add_TextChanged({
            # When the search term changes, refresh the search grid so
            # results reflect both the textual filter and the current
            # Site/Building/Room selections.
            if (Get-Command Refresh-SearchGrid -ErrorAction SilentlyContinue) {
                Refresh-SearchGrid
            } else {
                # Fallback if the helper isn't defined yet
                $term = $searchBox.Text
                $results = Filter-SearchResults -Term $term
                $searchGrid.ItemsSource = $results
            }
        })
    }
    # Event handler for clear button
    if ($searchClearBtn) {
        $searchClearBtn.Add_Click({
            $searchBox.Text = ''
            $searchBox.Focus()
            if (Get-Command Refresh-SearchGrid -ErrorAction SilentlyContinue) {
                Refresh-SearchGrid
            }
        })
    }
    # Populate the initial empty table
    if ($searchGrid) {
        $searchGrid.ItemsSource = $global:AllInterfaces
    }

    # Helper to refresh the search grid when site/building/room
    # selections change or when the search term updates.  This pulls
    # the current search term from the search box and re-filters
    # $global:AllInterfaces accordingly.
    function Refresh-SearchGrid {
        # Access controls within the search view
        $searchHostCtrl = $window.FindName('SearchInterfacesHost')
        if (-not $searchHostCtrl) { return }
        $view = $searchHostCtrl.Content
        if (-not $view) { return }
        $gridCtrl  = $view.FindName('SearchInterfacesGrid')
        $boxCtrl   = $view.FindName('SearchBox')
        if (-not $gridCtrl -or -not $boxCtrl) { return }
        $term = $boxCtrl.Text
        $gridCtrl.ItemsSource = Filter-SearchResults -Term $term
    }
} else {
    Write-Warning "Missing SearchInterfacesView.xaml at $searchViewXamlPath"
}

### Inject SummaryView
$summaryViewXamlPath = Join-Path $scriptDir '..\Views\SummaryView.xaml'
if (Test-Path $summaryViewXamlPath) {
    $summaryXaml    = Get-Content $summaryViewXamlPath -Raw
    $summaryReader  = New-Object System.Xml.XmlTextReader (New-Object System.IO.StringReader($summaryXaml))
    try {
        $summaryView   = [Windows.Markup.XamlReader]::Load($summaryReader)
        $summaryHost   = $window.FindName('SummaryHost')
        if ($summaryHost -is [System.Windows.Controls.ContentControl]) {
            $summaryHost.Content = $summaryView
        }
        # Expose summary view globally so helper functions may update its contents
        $global:summaryView = $summaryView
        # After loading the summary view, immediately update metrics if the helper exists
        if (Get-Command Update-Summary -ErrorAction SilentlyContinue) {
            Update-Summary
        }
    } catch {
        Write-Warning "Failed to load SummaryView: $($_.Exception.Message)"
    }
} else {
    Write-Warning "Missing SummaryView.xaml at $summaryViewXamlPath"
}

### Inject TemplatesView
$templatesViewPath = Join-Path $scriptDir '..\Views\TemplatesView.xaml'
if (Test-Path $templatesViewPath) {
    $tplXaml    = Get-Content $templatesViewPath -Raw
    $tplReader  = New-Object System.Xml.XmlTextReader (New-Object System.IO.StringReader($tplXaml))
    try {
        $templatesView = [Windows.Markup.XamlReader]::Load($tplReader)
        $templatesHost = $window.FindName('TemplatesHost')
        if ($templatesHost -is [System.Windows.Controls.ContentControl]) {
            $templatesHost.Content = $templatesView
        }
        $global:templatesView = $templatesView
        # Populate the templates list on load
        $templatesList = $templatesView.FindName('TemplatesList')
        $templateEditor = $templatesView.FindName('TemplateEditor')
        $reloadBtn = $templatesView.FindName('ReloadTemplateButton')
        $saveBtn   = $templatesView.FindName('SaveTemplateButton')
        # Directory of templates
        $script:TemplatesDir = Join-Path $scriptDir '..\Templates'
        function Refresh-TemplatesList {
            if (-not $templatesList) { return }
            if (-not (Test-Path $script:TemplatesDir)) { return }
            $files = Get-ChildItem -Path $script:TemplatesDir -Filter '*.json' -File
            # Display just the file names
            $items = $files | ForEach-Object { $_.Name }
            $templatesList.ItemsSource = $items
        }
        Refresh-TemplatesList
        # Selection change: load file contents
        if ($templatesList) {
            $templatesList.Add_SelectionChanged({
                $sel = $templatesList.SelectedItem
                if ($sel) {
                    $path = Join-Path $script:TemplatesDir $sel
                    try {
                        $templateEditor.Text = Get-Content -Path $path -Raw
                    } catch {
                        $templateEditor.Text = ""
                    }
                } else {
                    $templateEditor.Text = ""
                }
            })
        }
        # Reload button: reload the selected template from disk
        if ($reloadBtn) {
            $reloadBtn.Add_Click({
                $sel = $templatesList.SelectedItem
                if (-not $sel) { return }
                $path = Join-Path $script:TemplatesDir $sel
                try {
                    $templateEditor.Text = Get-Content -Path $path -Raw
                } catch {
                    [System.Windows.MessageBox]::Show("Failed to load template: $($_.Exception.Message)")
                }
            })
        }
        # Save button: write edits back to the file
        if ($saveBtn) {
            $saveBtn.Add_Click({
                $sel = $templatesList.SelectedItem
                if (-not $sel) {
                    [System.Windows.MessageBox]::Show('No template selected.')
                    return
                }
                $path = Join-Path $script:TemplatesDir $sel
                try {
                    Set-Content -Path $path -Value $templateEditor.Text -Force
                    [System.Windows.MessageBox]::Show("Saved template $sel.")
                    Refresh-TemplatesList
                } catch {
                    [System.Windows.MessageBox]::Show("Failed to save template: $($_.Exception.Message)")
                }
            })
        }

        # Add button: create a new template file with the given name and OS
        $addBtn = $templatesView.FindName('AddTemplateButton')
        $newNameBox = $templatesView.FindName('NewTemplateNameBox')
        $newOsCombo = $templatesView.FindName('NewTemplateOSType')
        if ($addBtn) {
            $addBtn.Add_Click({
                $name = $newNameBox.Text
                if (-not $name -or $name.Trim() -eq '') {
                    [System.Windows.MessageBox]::Show('Please enter a template name.')
                    return
                }
                # Ensure file ends with .json
                $fileName = if ($name.EndsWith('.json')) { $name } else { "$name.json" }
                $path = Join-Path $script:TemplatesDir $fileName
                if (Test-Path $path) {
                    [System.Windows.MessageBox]::Show('Template already exists.')
                    return
                }
                $osType = 'Cisco'
                try {
                    if ($newOsCombo -and $newOsCombo.SelectedItem) {
                        $osType = $newOsCombo.SelectedItem.Content
                    }
                } catch {}
                # Build a simple default template structure based on OS type
                $templateObj = $null
                switch ($osType) {
                    'Cisco' {
                        $templateObj = @{ PortType = 'Cisco'; Commands = @(
                            'interface {Port}',
                            'description {Name}',
                            'switchport access vlan {VLAN}',
                            'switchport mode access'
                        ) }
                    }
                    'Brocade' {
                        $templateObj = @{ PortType = 'Brocade'; Commands = @(
                            'interface ethernet {Port}',
                            'description {Name}',
                            'untagged {VLAN}',
                            'enable'
                        ) }
                    }
                    'Arista' {
                        $templateObj = @{ PortType = 'Arista'; Commands = @(
                            'interface Ethernet{Port}',
                            'description {Name}',
                            'switchport access vlan {VLAN}',
                            'switchport mode access'
                        ) }
                    }
                    default {
                        $templateObj = @{ PortType = $osType; Commands = @() }
                    }
                }
                try {
                    $json = $templateObj | ConvertTo-Json -Depth 4
                    Set-Content -Path $path -Value $json -Force
                    Refresh-TemplatesList
                    $templatesList.SelectedItem = $fileName
                    $templateEditor.Text = $json
                    [System.Windows.MessageBox]::Show("Created new template $fileName.")
                } catch {
                    [System.Windows.MessageBox]::Show("Failed to create template: $($_.Exception.Message)")
                }
            })
        }
    } catch {
        Write-Warning "Failed to load TemplatesView: $($_.Exception.Message)"
    }
} else {
    Write-Warning "Missing TemplatesView.xaml at $templatesViewPath"
}

### Inject AlertsView
$alertsViewPath = Join-Path $scriptDir '..\Views\AlertsView.xaml'
if (Test-Path $alertsViewPath) {
    $alertXaml    = Get-Content $alertsViewPath -Raw
    $alertReader  = New-Object System.Xml.XmlTextReader (New-Object System.IO.StringReader($alertXaml))
    try {
        $alertsView  = [Windows.Markup.XamlReader]::Load($alertReader)
        $alertsHost  = $window.FindName('AlertsHost')
        if ($alertsHost -is [System.Windows.Controls.ContentControl]) {
            $alertsHost.Content = $alertsView
        }
        $global:alertsView = $alertsView
        # After loading the alerts view, compute and display current alerts if helper exists
        if (Get-Command Compute-Alerts -ErrorAction SilentlyContinue) {
            Compute-Alerts
        }
        # Export button handler
        $expAlertsBtn = $alertsView.FindName('ExportAlertsButton')
        if ($expAlertsBtn) {
            $expAlertsBtn.Add_Click({
                $grid = $alertsView.FindName('AlertsGrid')
                if (-not $grid) { return }
                $rows = $grid.ItemsSource
                if (-not $rows -or $rows.Count -eq 0) {
                    [System.Windows.MessageBox]::Show('No alerts to export.')
                    return
                }
                $dlg = New-Object Microsoft.Win32.SaveFileDialog
                $dlg.Filter = 'CSV files (*.csv)|*.csv|All files (*.*)|*.*'
                $dlg.FileName = 'Alerts.csv'
                if ($dlg.ShowDialog() -eq $true) {
                    $path = $dlg.FileName
                    try {
                        $rows | Export-Csv -Path $path -NoTypeInformation
                        [System.Windows.MessageBox]::Show("Exported $($rows.Count) alerts to $path", 'Export Complete')
                    } catch {
                        [System.Windows.MessageBox]::Show("Failed to export alerts: $($_.Exception.Message)")
                    }
                }
            })
        }
    } catch {
        Write-Warning "Failed to load AlertsView: $($_.Exception.Message)"
    }
} else {
    Write-Warning "Missing AlertsView.xaml at $alertsViewPath"
}

# 6) Hook up main window controls
$refreshBtn = $window.FindName('RefreshButton')
if ($refreshBtn) {
    $refreshBtn.Add_Click({
        # Capture archive inclusion settings from the checkboxes.  Blank/unset
        # values indicate that archives should not be processed.  Use strings
        # instead of booleans so the downstream script can detect them via
        # $env variables.
        $includeArchiveCB = $window.FindName('IncludeArchiveCheckbox')
        $includeHistoricalCB = $window.FindName('IncludeHistoricalCheckbox')
        if ($includeArchiveCB) {
            if ($includeArchiveCB.IsChecked) { $env:IncludeArchive = 'true' } else { $env:IncludeArchive = '' }
        }
        if ($includeHistoricalCB) {
            if ($includeHistoricalCB.IsChecked) { $env:IncludeHistorical = 'true' } else { $env:IncludeHistorical = '' }
        }
        # Set the database path environment variable if defined
        if ($global:StateTraceDb) { $env:StateTraceDbPath = $global:StateTraceDb }
        # Run the parser script.  It will inspect the environment variables
        # defined above to determine whether to include archive data.  After
        # completion, reload the device summaries and refresh the filters.
        & "$parserScript"
        Load-DeviceSummaries
        Update-DeviceFilter
    })
}

$hostnameDropdown = $window.FindName('HostnameDropdown')
if ($hostnameDropdown) {
    $hostnameDropdown.Add_SelectionChanged({
        $sel = $hostnameDropdown.SelectedItem
        if ($sel) {
            Load-DeviceDetails $sel
            # If the Span tab is loaded and helper exists, load span info
            if (Get-Command Load-SpanInfo -ErrorAction SilentlyContinue) {
                Load-SpanInfo $sel
            }
        } else {
            # Clear span grid when nothing selected
            if (Get-Command Load-SpanInfo -ErrorAction SilentlyContinue) {
                Load-SpanInfo ''
            }
        }
    })
}

# Hook site/building/room dropdowns to update filtering
$siteDropdown = $window.FindName('SiteDropdown')
if ($siteDropdown) {
    $siteDropdown.Add_SelectionChanged({
        Update-DeviceFilter
    })
}

$buildingDropdown = $window.FindName('BuildingDropdown')
if ($buildingDropdown) {
    $buildingDropdown.Add_SelectionChanged({
        Update-DeviceFilter
    })
}

$roomDropdown = $window.FindName('RoomDropdown')
if ($roomDropdown) {
    $roomDropdown.Add_SelectionChanged({
        Update-DeviceFilter
    })
}

# Hook up ShowCisco and ShowBrocade buttons to copy show command sequences
$showCiscoBtn   = $window.FindName('ShowCiscoButton')
$showBrocadeBtn = $window.FindName('ShowBrocadeButton')
$brocadeOSDD    = $window.FindName('BrocadeOSDropdown')

if ($showCiscoBtn) {
    $showCiscoBtn.Add_Click({
        # Build a list of Cisco show commands.  Prepend a command to
        # disable pagination so the output is not interrupted.  Adjust
        # commands as needed to collect all relevant information.
        $cmds = @(
            'terminal length 0',
            'show version',
            'show running-config',
            'show interfaces status',
            'show mac address-table',
            'show spanning-tree',
            'show lldp neighbors',
            'show cdp neighbors',
            'show dot1x all',
            'show access-lists'
        )
        $text = $cmds -join "`r`n"
        Set-Clipboard -Value $text
        [System.Windows.MessageBox]::Show("Cisco show commands copied to clipboard.")
    })
}

if ($showBrocadeBtn) {
    $showBrocadeBtn.Add_Click({
        # Determine the selected OS version from dropdown; default to first item
        $osVersion = 'v8.0.30'
        if ($brocadeOSDD -and $brocadeOSDD.SelectedItem) {
            $osVersion = $brocadeOSDD.SelectedItem.Content
        }
        # Build common Brocade commands.  Use skip-page to disable paging.
        $cmds = @(
            'skip-page',
            'show version',
            'show config',
            'show interfaces brief',
            'show mac-address',
            'show spanning-tree',
            'show lldp neighbors',
            'show cdp neighbors',
            'show dot1x sessions all',
            'show mac-authentication sessions all',
            'show access-lists'
        )
        # Some OS versions might require variant commands.  For example, version
        # 8.0.95 (jufi) may include stack information.  Add extra commands
        # when that version is selected.
        if ($osVersion -eq 'v8.0.95') {
            $cmds += 'show stacking',
                     'show vlan'
        }
        $text = $cmds -join "`r`n"
        Set-Clipboard -Value $text
        [System.Windows.MessageBox]::Show("Brocade show commands for $osVersion copied to clipboard.")
    })
}

# Help button: open the help window when clicked.
$helpBtn = $window.FindName('HelpButton')
if ($helpBtn) {
    $helpBtn.Add_Click({
        $helpXamlPath = Join-Path $scriptDir '..\Views\HelpWindow.xaml'
        if (-not (Test-Path $helpXamlPath)) {
            [System.Windows.MessageBox]::Show('Help file not found.')
            return
        }
        try {
            $helpXaml   = Get-Content $helpXamlPath -Raw
            $helpReader = New-Object System.Xml.XmlTextReader (New-Object System.IO.StringReader($helpXaml))
            $helpWin    = [Windows.Markup.XamlReader]::Load($helpReader)
            # Set owner so the help window centres relative to main window
            $helpWin.Owner = $window
            $helpWin.ShowDialog() | Out-Null
        } catch {
            [System.Windows.MessageBox]::Show("Failed to load help: $($_.Exception.Message)")
        }
    })
}

# 7) Load initial state after window shows
$window.Add_Loaded({
    try {
        # Set the database path environment variable before running the parser
        if ($global:StateTraceDb) { $env:StateTraceDbPath = $global:StateTraceDb }
        & "$parserScript"
        Load-DeviceSummaries
        if ($window.FindName('HostnameDropdown').Items.Count -gt 0) {
            $first = $window.FindName('HostnameDropdown').Items[0]
            Load-DeviceDetails $first
            if (Get-Command Load-SpanInfo -ErrorAction SilentlyContinue) {
                Load-SpanInfo $first
            }
        }
    } catch {
        [System.Windows.MessageBox]::Show("Log parsing failed:`n$($_.Exception.Message)", "Error")
    }
})


if ($window.FindName('HostnameDropdown').Items.Count -gt 0) {
    $first = $window.FindName('HostnameDropdown').Items[0]
    Load-DeviceDetails $first
    if (Get-Command Load-SpanInfo -ErrorAction SilentlyContinue) {
        Load-SpanInfo $first
    }
}

# 8) Show window
$window.ShowDialog() | Out-Null

# 9) Cleanup
$parsedDir = Join-Path $scriptDir '..\ParsedData'
if (Test-Path $parsedDir) {
    try { Get-ChildItem $parsedDir -Recurse | Remove-Item -Force -Recurse }
    catch { Write-Warning "Failed to clear ParsedData: $_" }
}