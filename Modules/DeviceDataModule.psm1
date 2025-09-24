# ----------------------------------------------------------------------------
# Precompute the module root and Data directory paths once.  Many helpers in
# this module previously used Resolve-Path and Select-Object to derive the
# module's parent directory and Data folder on every call.  Those pipeline
# operations are relatively expensive.  Here we compute the absolute parent
# path using .NET methods and store it in script-scoped variables.  These
# values are then reused in Get-DbPathForHost and Get-AllSiteDbPaths to avoid
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
    [CmdletBinding()]
    param(
        [System.Collections.IEnumerable]$A,
        [System.Collections.IEnumerable]$B
    )
    FilterStateModule\Test-StringListEqualCI @PSBoundParameters
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
    FilterStateModule\Get-SelectedLocation @PSBoundParameters
}



# Return the last recorded location selections (site, zone, building, room).
# These values are maintained by Update-DeviceFilter to capture the most
# recently chosen filters.  Exposing them via a function allows other
# modules (e.g. CompareViewModule) to query the last known selections
# without directly accessing script-scoped variables.
function Get-LastLocation {
    [CmdletBinding()]
    param()
    FilterStateModule\Get-LastLocation
}



# Filter a collection of interface-like objects by location.  Given a list


# Initialise a dropdown or other ItemsControl with a list of items and

function Set-DropdownItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Windows.Controls.ItemsControl]$Control,
        [Parameter(Mandatory)][object[]]$Items
    )
    FilterStateModule\Set-DropdownItems @PSBoundParameters
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
    FilterStateModule\Update-DeviceFilter @PSBoundParameters
}



function Get-DeviceDetails {
    param([Parameter()][string]$Hostname)

    $hostTrim = ('' + $Hostname).Trim()
    if ([string]::IsNullOrWhiteSpace($hostTrim)) { return }

    $interfacesView = $null
    try { $interfacesView = $global:interfacesView } catch { $interfacesView = $null }
    if (-not $interfacesView) {
        try {
            $interfacesHost = $global:window.FindName('InterfacesHost')
            if ($interfacesHost -is [System.Windows.Controls.ContentControl]) {
                $interfacesView = $interfacesHost.Content
            }
        } catch {
            $interfacesView = $null
        }
    }
    if (-not $interfacesView) { return }

    $dto = $null
    try {
        $dto = DeviceDetailsModule\Get-DeviceDetailsData -Hostname $hostTrim
    } catch {
        [System.Windows.MessageBox]::Show("Error loading ${hostTrim}:`n$($_.Exception.Message)")
        return
    }
    if (-not $dto) {
        [System.Windows.MessageBox]::Show("No device details available for ${hostTrim}.")
        return
    }

    $summary = $dto.Summary
    if (-not $summary) {
        $summary = [PSCustomObject]@{
            Hostname        = $hostTrim
            Make            = ''
            Model           = ''
            Uptime          = ''
            Ports           = ''
            AuthDefaultVLAN = ''
            Building        = ''
            Room            = ''
        }
    }

    $getValue = {
        param($obj, [string]$name, [string]$defaultValue = '')
        if (-not $obj) { return $defaultValue }
        try {
            $val = $null
            if ($obj -is [hashtable]) {
                if ($obj.ContainsKey($name)) { $val = $obj[$name] }
            } elseif ($obj.PSObject -and $obj.PSObject.Properties[$name]) {
                $val = $obj.$name
            }
            if ($null -eq $val -or $val -eq [System.DBNull]::Value) { return $defaultValue }
            $text = '' + $val
            if ([string]::IsNullOrEmpty($text)) { return $defaultValue }
            return $text
        } catch {
            return $defaultValue
        }
    }

    $setText = {
        param($view, [string]$controlName, [string]$value)
        try {
            $ctrl = $view.FindName($controlName)
            if ($ctrl) { $ctrl.Text = $value }
        } catch {}
    }

    $hostnameValue = & $getValue $summary 'Hostname' $hostTrim
    & $setText $interfacesView 'HostnameBox'        $hostnameValue
    & $setText $interfacesView 'MakeBox'            (& $getValue $summary 'Make')
    & $setText $interfacesView 'ModelBox'           (& $getValue $summary 'Model')
    & $setText $interfacesView 'UptimeBox'          (& $getValue $summary 'Uptime')
    & $setText $interfacesView 'PortCountBox'       (& $getValue $summary 'Ports')
    & $setText $interfacesView 'AuthDefaultVLANBox' (& $getValue $summary 'AuthDefaultVLAN')
    & $setText $interfacesView 'BuildingBox'        (& $getValue $summary 'Building')
    & $setText $interfacesView 'RoomBox'            (& $getValue $summary 'Room')

    try {
        $grid = $interfacesView.FindName('InterfacesGrid')
        if ($grid) {
            $grid.ItemsSource = if ($dto.Interfaces) { $dto.Interfaces } else { @() }
        }
    } catch {}

    try {
        $combo = $interfacesView.FindName('ConfigOptionsDropdown')
        if ($combo) {
            $items = New-Object 'System.Collections.Generic.List[object]'
            if ($dto.Templates) {
                foreach ($item in $dto.Templates) {
                    if ($null -ne $item) { [void]$items.Add(('' + $item)) }
                }
            }
            Set-DropdownItems -Control $combo -Items $items.ToArray()
        }
    } catch {}
}

# Retrieve device details and interface list without updating any UI controls.  This helper is

function Get-DeviceDetailsData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Hostname
    )

    DeviceDetailsModule\Get-DeviceDetailsData @PSBoundParameters
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
        perÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¹ÃƒÆ’Ã¢â‚¬Â¦ÃƒÂ¢Ã¢â€šÂ¬Ã…â€œsite interface data is cached and automatically refreshed when
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
            # No zone explicitly selected ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã¢â‚¬Å“ choose the first zone for the site
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
    [CmdletBinding()]
    param([string]$Term)

    DeviceInsightsModule\Update-SearchResults @PSBoundParameters
}

function Update-Summary {
    [CmdletBinding()]
    param()

    DeviceInsightsModule\Update-Summary @PSBoundParameters
}

function Update-Alerts {
    [CmdletBinding()]
    param()

    DeviceInsightsModule\Update-Alerts @PSBoundParameters
}

function Update-SearchGrid {
    [CmdletBinding()]
    param()

    DeviceInsightsModule\Update-SearchGrid @PSBoundParameters
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

    DeviceDetailsModule\Get-DeviceConfigurationTemplates @PSBoundParameters
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


