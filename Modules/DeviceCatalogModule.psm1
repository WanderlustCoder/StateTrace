Set-StrictMode -Version Latest

if (-not (Get-Variable -Scope Global -Name DeviceMetadata -ErrorAction SilentlyContinue)) {
    $global:DeviceMetadata = @{}
}

if (-not (Get-Variable -Scope Global -Name DeviceHostnameOrder -ErrorAction SilentlyContinue)) {
    $global:DeviceHostnameOrder = @()
}

if (-not (Get-Variable -Scope Global -Name DeviceLocationEntries -ErrorAction SilentlyContinue)) {
    $global:DeviceLocationEntries = @()
}

function script:Ensure-LocalStateTraceModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ModuleName,
        [Parameter(Mandatory)][string]$ModuleFileName
    )

    try {
        if (Get-Module -Name $ModuleName -ErrorAction SilentlyContinue) { return }

        $modulePath = Join-Path $PSScriptRoot $ModuleFileName
        if (Test-Path -LiteralPath $modulePath) {
            Import-Module -Name $modulePath -Global -ErrorAction SilentlyContinue | Out-Null
        } else {
            Import-Module -Name $ModuleName -Global -ErrorAction SilentlyContinue | Out-Null
        }
    } catch { }
}

function script:Ensure-DeviceRepositoryModule {
    script:Ensure-LocalStateTraceModule -ModuleName 'DeviceRepositoryModule' -ModuleFileName 'DeviceRepositoryModule.psm1'
}

function Get-NormalizedSiteFilterList {
    [CmdletBinding()]
    param([string[]]$SiteFilter)

    $uniqueSites = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $normalizedSites = [System.Collections.Generic.List[string]]::new()
    if (-not $SiteFilter) { return $normalizedSites.ToArray() }

    foreach ($siteEntry in $SiteFilter) {
        if ($null -eq $siteEntry) { continue }
        $candidates = @($siteEntry -split ',')
        foreach ($candidate in $candidates) {
            $trimmed = ('' + $candidate).Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
            if ($trimmed -ieq 'All Sites') { continue }
            if ($uniqueSites.Add($trimmed)) { [void]$normalizedSites.Add($trimmed) }
        }
    }

    return $normalizedSites.ToArray()
}

function Get-DbPathsForNormalizedSites {
    [CmdletBinding()]
    param([string[]]$NormalizedSites)

    if ($NormalizedSites -and $NormalizedSites.Count -gt 0) {
        $paths = [System.Collections.Generic.List[string]]::new()
        foreach ($siteName in $NormalizedSites) {
            $path = $null
            try { $path = DeviceRepositoryModule\Get-DbPathForSite -Site $siteName } catch { $path = $null }
            if ($path -and -not [string]::IsNullOrWhiteSpace($path)) {
                [void]$paths.Add($path)
            }
        }
        if ($paths.Count -gt 0) {
            return @($paths | Select-Object -Unique)
        }
        return @()
    }

    try {
        return @(DeviceRepositoryModule\Get-AllSiteDbPaths)
    } catch {
        return @()
    }
}

function Get-DeviceCatalogRowLocation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [Parameter(Mandatory)][object]$Row
    )

    $siteVal = ''
    $buildingVal = ''
    $roomVal = ''

    $siteRaw = $Row.Site
    if ($siteRaw -ne $null -and $siteRaw -ne [System.DBNull]::Value) { $siteVal = [string]$siteRaw }
    $buildingRaw = $Row.Building
    if ($buildingRaw -ne $null -and $buildingRaw -ne [System.DBNull]::Value) { $buildingVal = [string]$buildingRaw }
    $roomRaw = $Row.Room
    if ($roomRaw -ne $null -and $roomRaw -ne [System.DBNull]::Value) { $roomVal = [string]$roomRaw }

    $zoneVal = ''
    try {
        $parts = $Hostname -split '-', 3
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

    return [PSCustomObject]@{
        Site     = $siteVal
        Zone     = $zoneVal
        Building = $buildingVal
        Room     = $roomVal
    }
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

    $balanced = [System.Collections.Generic.List[string]]::new()
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
    $hostnames = [System.Collections.Generic.List[string]]::new()

    $normalizedSites = Get-NormalizedSiteFilterList -SiteFilter $SiteFilter
    $dbPaths = @(Get-DbPathsForNormalizedSites -NormalizedSites $normalizedSites)

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

            $metadata[$name] = Get-DeviceCatalogRowLocation -Hostname $name -Row $row
        }
    }

    $global:DeviceMetadata = $metadata
    $balancedHostnames = Get-BalancedHostnames -Hostnames $hostnames
    $balancedHostArray = @($balancedHostnames)
    $global:DeviceHostnameOrder = $balancedHostArray

    return [PSCustomObject]@{
        Hostnames = $balancedHostArray
        Metadata  = $metadata
    }
}

function Get-DeviceLocationEntries {
    [CmdletBinding()]
    param(
        [string[]]$SiteFilter
    )

    script:Ensure-DeviceRepositoryModule

    $normalizedSites = Get-NormalizedSiteFilterList -SiteFilter $SiteFilter
    $dbPaths = @(Get-DbPathsForNormalizedSites -NormalizedSites $normalizedSites)

    if (-not $dbPaths -or $dbPaths.Count -eq 0) {
        $global:DeviceLocationEntries = @()
        return @()
    }

    try { DeviceRepositoryModule\Import-DatabaseModule } catch {}

    $uniqueKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $locations = [System.Collections.Generic.List[object]]::new()

    foreach ($dbPath in $dbPaths) {
        if (-not (Test-Path $dbPath)) { continue }
        $dt = $null
        try {
            $dt = DatabaseModule\Invoke-DbQuery -DatabasePath $dbPath -Sql "SELECT Hostname, Site, Building, Room FROM DeviceSummary"
        } catch {
            Write-Warning ("DeviceCatalogModule: failed to query location metadata from {0}: {1}" -f $dbPath, $_.Exception.Message)
            continue
        }
        if (-not $dt) { continue }
        foreach ($row in $dt) {
            $hostname = '' + $row.Hostname

            $location = Get-DeviceCatalogRowLocation -Hostname $hostname -Row $row

            $key = "{0}|{1}|{2}|{3}" -f $location.Site, $location.Zone, $location.Building, $location.Room
            if (-not $uniqueKeys.Add($key)) { continue }

            $locations.Add($location) | Out-Null
        }
    }

    $global:DeviceLocationEntries = $locations
    return $locations
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

    $hostList = [System.Collections.Generic.List[string]]::new()
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

Export-ModuleMember -Function Get-DeviceSummaries, Get-InterfaceHostnames, Get-DeviceLocationEntries
