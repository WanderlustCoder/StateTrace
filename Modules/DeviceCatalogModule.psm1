Set-StrictMode -Version Latest

if (-not (Get-Variable -Scope Global -Name DeviceMetadata -ErrorAction SilentlyContinue)) {
    $global:DeviceMetadata = @{}
}

if (-not (Get-Variable -Scope Global -Name DeviceHostnameOrder -ErrorAction SilentlyContinue)) {
    $global:DeviceHostnameOrder = @()
}

function Get-BalancedHostnames {
    [CmdletBinding()]
    param([System.Collections.IEnumerable]$Hostnames)

    if (-not $Hostnames) { return @() }

    $siteQueues = @{}
    foreach ($name in $Hostnames) {
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $site = ''
        try {
            $parts = $name -split '-', 2
            if ($parts.Length -gt 0 -and -not [string]::IsNullOrWhiteSpace($parts[0])) {
                $site = $parts[0]
            } else {
                $site = '(unknown)'
            }
        } catch {
            $site = '(unknown)'
        }

        if (-not $siteQueues.ContainsKey($site)) {
            $siteQueues[$site] = New-Object 'System.Collections.Generic.Queue[string]'
        }
        $siteQueues[$site].Enqueue($name)
    }

    if ($siteQueues.Count -le 1) {
        return @($Hostnames)
    }

    $siteOrder = $siteQueues.GetEnumerator() |
        Sort-Object @{ Expression = { $_.Value.Count }; Descending = $true },
                     @{ Expression = { $_.Key }; Descending = $false } |
        ForEach-Object { $_.Key }

    $balanced = New-Object 'System.Collections.Generic.List[string]'
    while ($true) {
        $added = $false
        foreach ($site in $siteOrder) {
            $queue = $siteQueues[$site]
            if ($queue.Count -gt 0) {
                $balanced.Add($queue.Dequeue()) | Out-Null
                $added = $true
            }
        }
        if (-not $added) { break }
    }

    return $balanced.ToArray()
}

function Get-DeviceSummaries {
    [CmdletBinding()]
    param(
        [string[]]$SiteFilter
    )

    $metadata = @{}
    $hostnames = New-Object 'System.Collections.Generic.List[string]'

    $normalizedSites = @()
    if ($PSBoundParameters.ContainsKey('SiteFilter') -and $SiteFilter) {
        foreach ($siteEntry in $SiteFilter) {
            if ($null -eq $siteEntry) { continue }
            $candidates = @($siteEntry -split ',')
            foreach ($candidate in $candidates) {
                $trimmed = ('' + $candidate).Trim()
                if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
                if ($trimmed -ieq 'All Sites') { continue }
                $normalizedSites += $trimmed
            }
        }
        $normalizedSites = @($normalizedSites | Select-Object -Unique)
    }

    $dbPaths = @()
    if ($normalizedSites.Count -gt 0) {
        $paths = New-Object 'System.Collections.Generic.List[string]'
        foreach ($siteName in $normalizedSites) {
            $path = $null
            try { $path = DeviceRepositoryModule\Get-DbPathForSite -Site $siteName } catch { $path = $null }
            if ($path -and -not [string]::IsNullOrWhiteSpace($path)) {
                [void]$paths.Add($path)
            }
        }
        if ($paths.Count -gt 0) {
            $dbPaths = @($paths | Select-Object -Unique)
        }
    } else {
        try {
            $dbPaths = DeviceRepositoryModule\Get-AllSiteDbPaths
        } catch {
            $dbPaths = @()
        }
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
    $balancedHostnames = Get-BalancedHostnames -Hostnames $hostnames
    $global:DeviceHostnameOrder = $balancedHostnames

    return [PSCustomObject]@{
        Hostnames = $balancedHostnames
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
