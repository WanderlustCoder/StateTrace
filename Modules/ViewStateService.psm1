Set-StrictMode -Version Latest

if (-not (Get-Variable -Scope Script -Name CachedSite -ErrorAction SilentlyContinue)) {
    $script:CachedSite = $null
    $script:CachedZoneSelection = $null
    $script:CachedZoneLoad = $null
}
function Get-SequenceCount {
    param([object]$Value)

    if ($null -eq $Value) { return 0 }

    if ($Value -is [System.Data.DataTable]) { return $Value.Rows.Count }
    elseif ($Value -is [System.Collections.ICollection]) { return [int]$Value.Count }
    elseif ($Value.PSObject -and $Value.PSObject.Properties["Count"]) {
        try { return [int]$Value.Count } catch { }
    }
    elseif ($Value -is [System.Collections.IEnumerable]) {
        $count = 0
        foreach ($item in $Value) { $count++ }
        return $count
    }
    return 0
}


function ConvertTo-FilterValue {
    param(
        [string]$Value,
        [string[]]$Sentinels
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    foreach ($sentinel in $Sentinels) {
        if ([System.StringComparer]::OrdinalIgnoreCase.Equals($Value, $sentinel)) {
            return $null
        }
    }
    return $Value.Trim()
}

function New-SortedStringList {
    param([System.Collections.Generic.HashSet[string]]$Set)

    $list = [System.Collections.Generic.List[string]]::new()
    if ($Set) {
        foreach ($item in $Set) {
            if (-not [string]::IsNullOrWhiteSpace($item)) {
                [void]$list.Add($item.Trim())
            }
        }
    }
    if ($list.Count -gt 1) {
        $list.Sort([System.StringComparer]::OrdinalIgnoreCase)
    }
    return $list
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

    $siteFilter = ConvertTo-FilterValue -Value $Site -Sentinels @('All Sites')
    $zoneFilter = ConvertTo-FilterValue -Value $ZoneSelection -Sentinels @('All Zones')
    $zoneLoadParam = ConvertTo-FilterValue -Value $ZoneToLoad -Sentinels @('All Zones')

    $cachedSite = $script:CachedSite
    $cachedZoneSelection = $script:CachedZoneSelection
    $cachedZoneLoad = $script:CachedZoneLoad

    $siteMatch = ([string]::IsNullOrEmpty($siteFilter) -and [string]::IsNullOrEmpty($cachedSite)) -or [string]::Equals($siteFilter, $cachedSite, [System.StringComparison]::OrdinalIgnoreCase)
    $zoneMatch = ([string]::IsNullOrEmpty($zoneFilter) -and [string]::IsNullOrEmpty($cachedZoneSelection)) -or [string]::Equals($zoneFilter, $cachedZoneSelection, [System.StringComparison]::OrdinalIgnoreCase)
    $zoneLoadMatch = ([string]::IsNullOrEmpty($zoneLoadParam) -and [string]::IsNullOrEmpty($cachedZoneLoad)) -or [string]::Equals($zoneLoadParam, $cachedZoneLoad, [System.StringComparison]::OrdinalIgnoreCase)

    $interfaces = $null
    if ($siteMatch -and $zoneMatch -and $zoneLoadMatch -and (Get-SequenceCount $global:AllInterfaces) -gt 0) {
        $interfaces = $global:AllInterfaces
    }

    if (-not $interfaces) {
        $params = @{}
        if ($null -ne $siteFilter) { $params.Site = $siteFilter }
        if ($null -ne $zoneFilter) { $params.ZoneSelection = $zoneFilter }
        if ($null -ne $zoneLoadParam) { $params.ZoneToLoad = $zoneLoadParam }

        $snapshot = @()
        try {
            if ($params.Count -gt 0) {
                $snapshot = DeviceRepositoryModule\Get-GlobalInterfaceSnapshot @params
            } else {
                $snapshot = DeviceRepositoryModule\Get-GlobalInterfaceSnapshot
            }
        } catch {
            $snapshot = @()
        }

        $interfaces = if ($snapshot -and $snapshot.Length -gt 0) {
            [System.Collections.Generic.List[object]]::new($snapshot)
        } else {
            [System.Collections.Generic.List[object]]::new()
        }

        $global:AllInterfaces = $interfaces
        $script:CachedSite = $siteFilter
        $script:CachedZoneSelection = $zoneFilter
        $script:CachedZoneLoad = $zoneLoadParam
    }

    if (-not $interfaces) { return @() }

    $buildingFilter = ConvertTo-FilterValue -Value $Building -Sentinels @('')
    $roomFilter = ConvertTo-FilterValue -Value $Room -Sentinels @('')

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
function Get-FilterSnapshot {
    [CmdletBinding()]
    param(
        [hashtable]$DeviceMetadata = $global:DeviceMetadata,
        [string]$Site,
        [string]$ZoneSelection,
        [string]$Building,
        [string]$Room
    )

    $siteFilter = ConvertTo-FilterValue -Value $Site -Sentinels @('All Sites')
    $zoneFilter = ConvertTo-FilterValue -Value $ZoneSelection -Sentinels @('All Zones')
    $buildingFilter = ConvertTo-FilterValue -Value $Building -Sentinels @('')
    $roomFilter = ConvertTo-FilterValue -Value $Room -Sentinels @('')

    $siteSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $zoneSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $buildingSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $roomSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $hostSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    if ($DeviceMetadata) {
        foreach ($entry in $DeviceMetadata.GetEnumerator()) {
            $hostname = '' + $entry.Key
            if ([string]::IsNullOrWhiteSpace($hostname)) { continue }

            $meta = $entry.Value
            $siteValue = ''
            if ($meta -and $meta.PSObject.Properties['Site']) { $siteValue = '' + $meta.Site }
            if (-not [string]::IsNullOrWhiteSpace($siteValue)) { [void]$siteSet.Add($siteValue) }

            $zoneValue = ''
            if ($meta -and $meta.PSObject.Properties['Zone']) {
                $zoneValue = '' + $meta.Zone
            }
            if ([string]::IsNullOrWhiteSpace($zoneValue)) {
                try {
                    $parts = $hostname -split '-'
                    if ($parts.Length -ge 2) { $zoneValue = $parts[1] }
                } catch { $zoneValue = '' }
            }

            $buildingValue = ''
            if ($meta -and $meta.PSObject.Properties['Building']) { $buildingValue = '' + $meta.Building }

            $roomValue = ''
            if ($meta -and $meta.PSObject.Properties['Room']) { $roomValue = '' + $meta.Room }

            $siteMatches = (-not $siteFilter) -or [System.StringComparer]::OrdinalIgnoreCase.Equals($siteValue, $siteFilter)
            $zoneMatches = (-not $zoneFilter) -or [System.StringComparer]::OrdinalIgnoreCase.Equals($zoneValue, $zoneFilter)
            $buildingMatches = (-not $buildingFilter) -or [System.StringComparer]::OrdinalIgnoreCase.Equals($buildingValue, $buildingFilter)
            $roomMatches = (-not $roomFilter) -or [System.StringComparer]::OrdinalIgnoreCase.Equals($roomValue, $roomFilter)

            if ($siteMatches -and -not [string]::IsNullOrWhiteSpace($zoneValue)) {
                [void]$zoneSet.Add($zoneValue)
            }

            if ($siteMatches -and $zoneMatches -and -not [string]::IsNullOrWhiteSpace($buildingValue)) {
                [void]$buildingSet.Add($buildingValue)
            }

            if ($siteMatches -and $buildingMatches -and -not [string]::IsNullOrWhiteSpace($roomValue)) {
                [void]$roomSet.Add($roomValue)
            }

            if ($siteMatches -and $zoneMatches -and $buildingMatches -and $roomMatches) {
                [void]$hostSet.Add($hostname)
            }
        }
    }

    $sites = New-SortedStringList -Set $siteSet
    $zones = New-SortedStringList -Set $zoneSet
    $buildings = New-SortedStringList -Set $buildingSet
    $rooms = New-SortedStringList -Set $roomSet
    $hosts = [System.Collections.Generic.List[string]]::new($hostSet)
    if ((Get-SequenceCount $hosts) -gt 1) {
        $hosts.Sort([System.StringComparer]::OrdinalIgnoreCase)
    }
    $unknownIndex = $hosts.IndexOf('Unknown')
    if ($unknownIndex -gt 0) {
        $first = $hosts[0]
        $hosts[0] = $hosts[$unknownIndex]
        $hosts[$unknownIndex] = $first
    }

    $sitesArray     = @($sites)
    $zonesArray     = @($zones)
    $buildingsArray = @($buildings)
    $roomsArray     = @($rooms)
    $hostsArray     = @($hosts)

    $zoneCandidates = @('All Zones')
    if ((Get-SequenceCount $zonesArray) -gt 0) { $zoneCandidates += $zonesArray }
    $zoneToLoad = Get-ZoneLoadHint -SelectedZone $ZoneSelection -AvailableZones $zoneCandidates

    return [PSCustomObject]@{
        Sites      = $sitesArray
        Zones      = $zonesArray
        Buildings  = $buildingsArray
        Rooms      = $roomsArray
        Hostnames  = $hostsArray
        ZoneToLoad = $zoneToLoad
    }
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

Export-ModuleMember -Function Get-InterfacesForContext, Get-FilterSnapshot, Get-ZoneLoadHint, Get-SequenceCount







