Set-StrictMode -Version Latest

if (-not (Get-Variable -Scope Script -Name CachedSite -ErrorAction SilentlyContinue)) {
    $script:CachedSite = $null
    $script:CachedZoneSelection = $null
    $script:CachedZoneLoad = $null
}

function Get-InterfacesForContext {
    [CmdletBinding()]
    param(
        [string]$Site,
        [string]$ZoneSelection,
        [string]$ZoneToLoad,
        [string]$Building,
        [string]$Room
    )

    $siteFilter = if ([string]::IsNullOrWhiteSpace($Site) -or $Site -eq 'All Sites') { $null } else { $Site }
    $zoneFilter = if ([string]::IsNullOrWhiteSpace($ZoneSelection) -or $ZoneSelection -eq 'All Zones') { $null } else { $ZoneSelection }
    $zoneLoadParam = if ([string]::IsNullOrWhiteSpace($ZoneToLoad) -or $ZoneToLoad -eq 'All Zones') { $null } else { $ZoneToLoad }

    $cachedSite = $script:CachedSite
    $cachedZoneSelection = $script:CachedZoneSelection
    $cachedZoneLoad = $script:CachedZoneLoad

    $siteMatch = ([string]::IsNullOrEmpty($siteFilter) -and [string]::IsNullOrEmpty($cachedSite)) -or [string]::Equals($siteFilter, $cachedSite, [System.StringComparison]::OrdinalIgnoreCase)
    $zoneMatch = ([string]::IsNullOrEmpty($zoneFilter) -and [string]::IsNullOrEmpty($cachedZoneSelection)) -or [string]::Equals($zoneFilter, $cachedZoneSelection, [System.StringComparison]::OrdinalIgnoreCase)
    $zoneLoadMatch = ([string]::IsNullOrEmpty($zoneLoadParam) -and [string]::IsNullOrEmpty($cachedZoneLoad)) -or [string]::Equals($zoneLoadParam, $cachedZoneLoad, [System.StringComparison]::OrdinalIgnoreCase)

    $interfaces = $null
    if ($siteMatch -and $zoneMatch -and $zoneLoadMatch -and $global:AllInterfaces -and $global:AllInterfaces.Count -gt 0) {
        $interfaces = $global:AllInterfaces
    }

    if (-not $interfaces) {
        $params = @{}
        if ($null -ne $siteFilter) { $params.Site = $siteFilter }
        if ($null -ne $zoneFilter) { $params.ZoneSelection = $zoneFilter }
        if ($null -ne $zoneLoadParam) { $params.ZoneToLoad = $zoneLoadParam }

        try {
            if ($params.Count -gt 0) {
                $interfaces = DeviceRepositoryModule\Update-GlobalInterfaceList @params
            } else {
                $interfaces = DeviceRepositoryModule\Update-GlobalInterfaceList
            }
        } catch {
            $interfaces = $null
        }

        if ($interfaces) {
            $global:AllInterfaces = $interfaces
            $script:CachedSite = $siteFilter
            $script:CachedZoneSelection = $zoneFilter
            $script:CachedZoneLoad = $zoneLoadParam
        }
    }

    if (-not $interfaces) { return @() }

    $buildingFilter = if ([string]::IsNullOrWhiteSpace($Building)) { $null } else { $Building }
    $roomFilter = if ([string]::IsNullOrWhiteSpace($Room)) { $null } else { $Room }

    $results = New-Object 'System.Collections.Generic.List[object]'

    foreach ($row in $interfaces) {
        if (-not $row) { continue }

        if ($siteFilter) {
            $siteValue = ''
            if ($row.PSObject.Properties['Site']) { $siteValue = '' + $row.Site }
            if (-not [string]::Equals($siteValue, $siteFilter, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        }

        if ($zoneFilter) {
            $zoneValue = ''
            if ($row.PSObject.Properties['Zone']) { $zoneValue = '' + $row.Zone }
            if (-not [string]::Equals($zoneValue, $zoneFilter, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        }

        if ($buildingFilter) {
            $bldValue = ''
            if ($row.PSObject.Properties['Building']) { $bldValue = '' + $row.Building }
            if (-not [string]::Equals($bldValue, $buildingFilter, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        }

        if ($roomFilter) {
            $roomValue = ''
            if ($row.PSObject.Properties['Room']) { $roomValue = '' + $row.Room }
            if (-not [string]::Equals($roomValue, $roomFilter, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        }

        [void]$results.Add($row)
    }

    return $results
}

function Get-ZoneLoadHint {
    [CmdletBinding()]
    param(
        [string]$SelectedZone,
        [string[]]$AvailableZones
    )

    if ($SelectedZone -and $SelectedZone -ne '' -and $SelectedZone -ne 'All Zones') {
        return $SelectedZone
    }

    if ($AvailableZones) {
        foreach ($zone in $AvailableZones) {
            if (-not [string]::IsNullOrWhiteSpace($zone) -and $zone -ne 'All Zones') {
                return $zone
            }
        }
    }

    return ''
}

Export-ModuleMember -Function Get-InterfacesForContext, Get-ZoneLoadHint

