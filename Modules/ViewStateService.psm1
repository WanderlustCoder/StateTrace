Set-StrictMode -Version Latest

function Get-InterfacesForContext {
    [CmdletBinding()]
    param(
        [string]$Site,
        [string]$ZoneSelection,
        [string]$ZoneToLoad,
        [string]$Building,
        [string]$Room
    )

    $interfaces = DeviceRepositoryModule\Update-GlobalInterfaceList -Site $Site -ZoneSelection $ZoneSelection -ZoneToLoad $ZoneToLoad
    if (-not $interfaces) { return @() }

    if ([string]::IsNullOrWhiteSpace($Building) -and [string]::IsNullOrWhiteSpace($Room)) {
        return $interfaces
    }

    $filtered = New-Object 'System.Collections.Generic.List[object]'
    foreach ($row in $interfaces) {
        if (-not $row) { continue }
        $bldVal = ''
        if ($row.PSObject.Properties['Building']) { $bldVal = '' + $row.Building }
        $roomVal = ''
        if ($row.PSObject.Properties['Room']) { $roomVal = '' + $row.Room }
        if ($Building -and $Building -ne '' -and $bldVal -ne $Building) { continue }
        if ($Room -and $Room -ne '' -and $roomVal -ne $Room) { continue }
        [void]$filtered.Add($row)
    }
    return $filtered
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
