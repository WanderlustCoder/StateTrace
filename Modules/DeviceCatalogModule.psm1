Set-StrictMode -Version Latest

if (-not (Get-Variable -Scope Global -Name DeviceMetadata -ErrorAction SilentlyContinue)) {
    $global:DeviceMetadata = @{}
}

function Get-DeviceSummaries {
    [CmdletBinding()]
    param()

    $metadata = @{}
    $hostnames = New-Object 'System.Collections.Generic.List[string]'
    $dbPaths = @()
    try {
        $dbPaths = DeviceRepositoryModule\Get-AllSiteDbPaths
    } catch {
        $dbPaths = @()
    }

    if (-not $dbPaths -or $dbPaths.Count -eq 0) {
        $global:DeviceMetadata = @{}
        return [PSCustomObject]@{
            Hostnames = @()
            Metadata  = $global:DeviceMetadata
        }
    }

    try { DeviceRepositoryModule\Import-DatabaseModule } catch {}

    foreach ($dbPath in $dbPaths) {
        if (-not (Test-Path $dbPath)) { continue }
        try {
            $dt = DatabaseModule\Invoke-DbQuery -DatabasePath $dbPath -Sql "SELECT Hostname, Site, Building, Room FROM DeviceSummary"
        } catch {
            Write-Warning ("DeviceCatalogModule: failed to query device summaries from {0}: {1}" -f $dbPath, $_.Exception.Message)
            continue
        }
        if (-not $dt) { continue }
        foreach ($row in $dt) {
            $name = '' + $row.Hostname
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            if (-not $hostnames.Contains($name)) {
                [void]$hostnames.Add($name)
            }

            $siteVal = ''
            $buildingVal = ''
            $roomVal = ''
            $siteRaw = $row.Site
            if ($siteRaw -ne $null -and $siteRaw -ne [System.DBNull]::Value) { $siteVal = [string]$siteRaw }
            $buildingRaw = $row.Building
            if ($buildingRaw -ne $null -and $buildingRaw -ne [System.DBNull]::Value) { $buildingVal = [string]$buildingRaw }
            $roomRaw = $row.Room
            if ($roomRaw -ne $null -and $roomRaw -ne [System.DBNull]::Value) { $roomVal = [string]$roomRaw }

            $zoneVal = ''
            try {
                $parts = $name -split '-', 3
                if ($parts.Length -ge 2) { $zoneVal = $parts[1] }
                if ([string]::IsNullOrWhiteSpace($siteVal) -and $parts.Length -ge 1) {
                    $siteVal = $parts[0]
                }
            } catch {
                $zoneVal = ''
                if ([string]::IsNullOrWhiteSpace($siteVal)) {
                    $siteVal = ''
                }
            }

            $metadata[$name] = [PSCustomObject]@{
                Site     = $siteVal
                Zone     = $zoneVal
                Building = $buildingVal
                Room     = $roomVal
            }
        }
    }

    $global:DeviceMetadata = $metadata
    return [PSCustomObject]@{
        Hostnames = $hostnames.ToArray()
        Metadata  = $metadata
    }
}

function Get-InterfaceHostnames {
    [CmdletBinding()]
    param(
        [string]$Site,
        [string]$Zone,
        [string]$Building,
        [string]$Room
    )

    $metadata = $global:DeviceMetadata
    if (-not $metadata -or $metadata.Count -eq 0) {
        Get-DeviceSummaries | Out-Null
        $metadata = $global:DeviceMetadata
    }
    if (-not $metadata -or $metadata.Count -eq 0) { return @() }

    $siteFilter = if ([string]::IsNullOrWhiteSpace($Site) -or $Site -ieq 'All Sites') { $null } else { $Site }
    $zoneFilter = if ([string]::IsNullOrWhiteSpace($Zone) -or $Zone -ieq 'All Zones') { $null } else { $Zone }
    $buildingFilter = if ([string]::IsNullOrWhiteSpace($Building) -or $Building -ieq 'All Buildings') { $null } else { $Building }
    $roomFilter = if ([string]::IsNullOrWhiteSpace($Room) -or $Room -ieq 'All Rooms') { $null } else { $Room }

    $hostList = New-Object 'System.Collections.Generic.List[string]'
    foreach ($entry in $metadata.GetEnumerator()) {
        $name = $entry.Key
        $meta = $entry.Value
        if (-not $meta) { continue }

        $metaSite = ''
        if ($meta.PSObject.Properties['Site']) { $metaSite = '' + $meta.Site }
        if ($siteFilter -and ($metaSite -ne $siteFilter)) { continue }

        $metaZone = ''
        if ($meta.PSObject.Properties['Zone']) { $metaZone = '' + $meta.Zone }
        if ($zoneFilter -and ($metaZone -ne $zoneFilter)) { continue }

        $metaBuilding = ''
        if ($meta.PSObject.Properties['Building']) { $metaBuilding = '' + $meta.Building }
        if ($buildingFilter -and ($metaBuilding -ne $buildingFilter)) { continue }

        $metaRoom = ''
        if ($meta.PSObject.Properties['Room']) { $metaRoom = '' + $meta.Room }
        if ($roomFilter -and ($metaRoom -ne $roomFilter)) { continue }

        [void]$hostList.Add($name)
    }

    $hostList.Sort([System.StringComparer]::OrdinalIgnoreCase)
    return $hostList.ToArray()
}

Export-ModuleMember -Function Get-DeviceSummaries, Get-InterfaceHostnames
