Set-StrictMode -Version Latest

if (-not (Get-Variable -Scope Script -Name CachedSite -ErrorAction SilentlyContinue)) {
    $script:CachedSite = $null
    $script:CachedZoneSelection = $null
    $script:CachedZoneLoad = $null
}
if (-not (Get-Variable -Scope Script -Name CachedInterfaces -ErrorAction SilentlyContinue)) {
    $script:CachedInterfaces = $null
}
if (-not (Get-Variable -Scope Global -Name InterfacesLoadAllowed -ErrorAction SilentlyContinue)) {
    $global:InterfacesLoadAllowed = $false
}

try { TelemetryModule\Import-InterfaceCommon | Out-Null } catch { Write-Verbose "Caught exception in ViewStateService.psm1: $($_.Exception.Message)" }

$script:InterfaceStringPropertyValueCmd = $null

function script:Get-InterfaceStringPropertyValueCommand {
    [CmdletBinding()]
    param()

    $cmd = $script:InterfaceStringPropertyValueCmd
    if ($cmd) { return $cmd }

    try { $cmd = Get-Command -Name 'InterfaceCommon\Get-StringPropertyValue' -ErrorAction SilentlyContinue } catch { $cmd = $null }
    if ($cmd) { $script:InterfaceStringPropertyValueCmd = $cmd }
    return $cmd
}

function Import-ViewStateServiceModule {
    [CmdletBinding()]
    param()

    if (Get-Module -Name 'ViewStateService' -ErrorAction SilentlyContinue) { return $true }

    $modulePath = Join-Path $PSScriptRoot 'ViewStateService.psm1'
    if (-not (Test-Path -LiteralPath $modulePath)) { return $false }

    try {
        Import-Module -Name $modulePath -Force -Global | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Get-SequenceCount {
    param([object]$Value)

    if ($null -eq $Value) { return 0 }

    if ($Value -is [System.Data.DataTable]) {
        try { return [int]$Value.Rows.Count } catch { return 0 }
    }
    elseif ($Value -is [System.Collections.ICollection]) {
        try { return [int]$Value.Count } catch {
            try {
                $count = 0
                foreach ($item in [System.Collections.IEnumerable]$Value) { $count++ }
                return $count
            } catch { return 0 }
        }
    }
    elseif ($Value.PSObject -and $Value.PSObject.Properties["Count"]) {
        try { return [int]$Value.Count } catch { Write-Verbose "Caught exception in ViewStateService.psm1: $($_.Exception.Message)" }
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

function Get-PreferredHostnames {
    param([System.Collections.Generic.HashSet[string]]$HostSet)

    $ordered = [System.Collections.Generic.List[string]]::new()
    if (-not $HostSet -or $HostSet.Count -eq 0) { return ,$ordered }

    $rotation = $null
    try { $rotation = $global:DeviceHostnameOrder } catch { $rotation = $null }
    $rotationList = @()
    try { $rotationList = @($rotation) } catch { $rotationList = @() }
    $rotationCount = 0
    try { $rotationCount = Get-SequenceCount -Value $rotationList } catch { $rotationCount = 0 }

    $added = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    if ($rotationCount -gt 0) {
        foreach ($entry in $rotationList) {
            $candidate = ('' + $entry).Trim()
            if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
            if (-not $HostSet.Contains($candidate)) { continue }
            if ($added.Add($candidate)) {
                $ordered.Add($candidate) | Out-Null
            }
        }
    }

    if ($HostSet.Count -gt $added.Count) {
        $remaining = [System.Collections.Generic.List[string]]::new()
        foreach ($name in $HostSet) {
            if ($added.Contains($name)) { continue }
            $remaining.Add($name) | Out-Null
        }
        if ($remaining.Count -gt 1) {
            $remaining.Sort([System.StringComparer]::OrdinalIgnoreCase)
        }
        foreach ($name in $remaining) {
            if ($added.Add($name)) {
                $ordered.Add($name) | Out-Null
            }
        }
    }

    return ,$ordered
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

    if (-not $global:InterfacesLoadAllowed) {
        Write-Verbose '[ViewStateService] Interfaces not allowed yet; returning empty context.'
        return @()
    }

    $siteFilter = ConvertTo-FilterValue -Value $Site -Sentinels @('All Sites')
    $zoneFilter = ConvertTo-FilterValue -Value $ZoneSelection -Sentinels @('All Zones')
    $zoneLoadParam = ConvertTo-FilterValue -Value $ZoneToLoad -Sentinels @('All Zones')
    $buildingFilter = ConvertTo-FilterValue -Value $Building -Sentinels @('', 'All Buildings')
    $roomFilter = ConvertTo-FilterValue -Value $Room -Sentinels @('', 'All Rooms')

    $cachedSite = $script:CachedSite
    $cachedZoneSelection = $script:CachedZoneSelection
    $cachedZoneLoad = $script:CachedZoneLoad
    $cachedInterfaces = $script:CachedInterfaces

    $siteMatch = ([string]::IsNullOrEmpty($siteFilter) -and [string]::IsNullOrEmpty($cachedSite)) -or [string]::Equals($siteFilter, $cachedSite, [System.StringComparison]::OrdinalIgnoreCase)
    $zoneMatch = ([string]::IsNullOrEmpty($zoneFilter) -and [string]::IsNullOrEmpty($cachedZoneSelection)) -or [string]::Equals($zoneFilter, $cachedZoneSelection, [System.StringComparison]::OrdinalIgnoreCase)
    $zoneLoadMatch = ([string]::IsNullOrEmpty($zoneLoadParam) -and [string]::IsNullOrEmpty($cachedZoneLoad)) -or [string]::Equals($zoneLoadParam, $cachedZoneLoad, [System.StringComparison]::OrdinalIgnoreCase)

    $interfacesSnapshot = $null
    $hostScopedSnapshotSelected = $false

    if (($buildingFilter -or $roomFilter) -and $siteFilter) {
        $zoneHostFilter = $null
        if ($zoneFilter) {
            $zoneHostFilter = $zoneFilter
        } elseif ($zoneLoadParam) {
            $zoneHostFilter = $zoneLoadParam
        }

        $metadataLookupForHosts = $null
        try { $metadataLookupForHosts = $global:DeviceMetadata } catch { $metadataLookupForHosts = $null }
        $metadataAvailableForHosts = $false
        try {
            if ($metadataLookupForHosts -is [System.Collections.IDictionary]) {
                $metadataAvailableForHosts = ($metadataLookupForHosts.Count -gt 0)
            }
        } catch { $metadataAvailableForHosts = $false }

        if ($metadataAvailableForHosts) {
            $hostCandidates = @()
            try {
                $hostParams = @{ DeviceMetadata = $metadataLookupForHosts; Site = $siteFilter }
                if ($zoneHostFilter) { $hostParams.ZoneSelection = $zoneHostFilter }
                if ($buildingFilter) { $hostParams.Building = $buildingFilter }
                if ($roomFilter) { $hostParams.Room = $roomFilter }
                $hostSnapshot = Get-FilterSnapshot @hostParams
                if ($hostSnapshot -and $hostSnapshot.Hostnames) { $hostCandidates = @($hostSnapshot.Hostnames) }
            } catch {
                $hostCandidates = @()
            }

            $filteredHostList = [System.Collections.Generic.List[string]]::new()
            $seenHostnames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($candidate in $hostCandidates) {
                $candidateValue = if ($null -ne $candidate) { ('' + $candidate).Trim() } else { '' }
                if ([string]::IsNullOrWhiteSpace($candidateValue)) { continue }
                if (-not $seenHostnames.Add($candidateValue)) { continue }

                $parts = $null
                try { $parts = $candidateValue.Split('-', [System.StringSplitOptions]::RemoveEmptyEntries) } catch { $parts = $null }

                if ($parts -and $parts.Length -ge 1) {
                    if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals($parts[0], $siteFilter)) { continue }
                    if ($zoneHostFilter) {
                        if ($parts.Length -lt 2) { continue }
                        if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals($parts[1], $zoneHostFilter)) { continue }
                    }
                } elseif ($zoneHostFilter) {
                    continue
                }

                [void]$filteredHostList.Add($candidateValue)
            }

            $hostCandidates = $filteredHostList.ToArray()
            if ($filteredHostList.Count -eq 0) {
                return ,([System.Collections.Generic.List[object]]::new())
            }

            $missingHosts = $null
            $cacheChecked = $false
            try {
                $cacheResult = DeviceRepositoryModule\Invoke-InterfaceCacheLock {
                    $interfaceCache = $global:DeviceInterfaceCache
                    if ($interfaceCache -is [System.Collections.IDictionary]) {
                        $missing = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
                        foreach ($hn in $hostCandidates) {
                            $hnValue = if ($null -ne $hn) { ('' + $hn).Trim() } else { '' }
                            if ([string]::IsNullOrWhiteSpace($hnValue)) { continue }
                            if (-not $interfaceCache.Contains($hnValue)) { [void]$missing.Add($hnValue) }
                        }
                        return [pscustomobject]@{ CacheChecked = $true; MissingHosts = $missing }
                    }
                    return [pscustomobject]@{ CacheChecked = $false; MissingHosts = $null }
                }
                if ($cacheResult) {
                    $cacheChecked = [bool]$cacheResult.CacheChecked
                    $missingHosts = $cacheResult.MissingHosts
                }
            } catch {
                $missingHosts = $null
                $cacheChecked = $false
                try {
                    $interfaceCache = $global:DeviceInterfaceCache
                    if ($interfaceCache -is [System.Collections.IDictionary]) {
                        $cacheChecked = $true
                        $missingHosts = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
                        foreach ($hn in $hostCandidates) {
                            $hnValue = if ($null -ne $hn) { ('' + $hn).Trim() } else { '' }
                            if ([string]::IsNullOrWhiteSpace($hnValue)) { continue }
                            if (-not $interfaceCache.Contains($hnValue)) { [void]$missingHosts.Add($hnValue) }
                        }
                    }
                } catch {
                    $missingHosts = $null
                    $cacheChecked = $false
                }
            }

            if (($missingHosts -and $missingHosts.Count -gt 0) -or -not $cacheChecked) {
                try {
                    DeviceRepositoryModule\Update-HostInterfaceCache -Site $siteFilter -Zone $zoneHostFilter -Hostnames $hostCandidates
                } catch { Write-Verbose "Caught exception in ViewStateService.psm1: $($_.Exception.Message)" }
            }

            $cacheComplete = $false
            $hostInterfaces = $null
            try {
                $cacheResult = DeviceRepositoryModule\Invoke-InterfaceCacheLock {
                    $interfaceCache = $global:DeviceInterfaceCache
                    if ($interfaceCache -is [System.Collections.IDictionary]) {
                        $complete = $true
                        foreach ($hn in $hostCandidates) {
                            $hnValue = if ($null -ne $hn) { ('' + $hn).Trim() } else { '' }
                            if ([string]::IsNullOrWhiteSpace($hnValue)) { continue }
                            if (-not $interfaceCache.Contains($hnValue)) {
                                $complete = $false
                                break
                            }
                        }

                        if ($complete) {
                            $collected = [System.Collections.Generic.List[object]]::new()
                            foreach ($hn in $hostCandidates) {
                                $hnValue = if ($null -ne $hn) { ('' + $hn).Trim() } else { '' }
                                if ([string]::IsNullOrWhiteSpace($hnValue)) { continue }
                                $rows = $interfaceCache[$hnValue]
                                if (-not $rows) { continue }
                                foreach ($row in $rows) {
                                    if (-not $row) { continue }
                                    [void]$collected.Add($row)
                                }
                            }
                            return [pscustomobject]@{ CacheComplete = $true; HostInterfaces = $collected }
                        }

                        return [pscustomobject]@{ CacheComplete = $false; HostInterfaces = $null }
                    }

                    return [pscustomobject]@{ CacheComplete = $false; HostInterfaces = $null }
                }
                if ($cacheResult) {
                    $cacheComplete = [bool]$cacheResult.CacheComplete
                    $hostInterfaces = $cacheResult.HostInterfaces
                }
            } catch {
                $cacheComplete = $false
                $hostInterfaces = $null
                try {
                    $interfaceCache = $global:DeviceInterfaceCache
                    if ($interfaceCache -is [System.Collections.IDictionary]) {
                        $cacheComplete = $true
                        foreach ($hn in $hostCandidates) {
                            $hnValue = if ($null -ne $hn) { ('' + $hn).Trim() } else { '' }
                            if ([string]::IsNullOrWhiteSpace($hnValue)) { continue }
                            if (-not $interfaceCache.Contains($hnValue)) {
                                $cacheComplete = $false
                                break
                            }
                        }
                        if ($cacheComplete) {
                            $hostInterfaces = [System.Collections.Generic.List[object]]::new()
                            foreach ($hn in $hostCandidates) {
                                $hnValue = if ($null -ne $hn) { ('' + $hn).Trim() } else { '' }
                                if ([string]::IsNullOrWhiteSpace($hnValue)) { continue }
                                $rows = $interfaceCache[$hnValue]
                                if (-not $rows) { continue }
                                foreach ($row in $rows) {
                                    if (-not $row) { continue }
                                    [void]$hostInterfaces.Add($row)
                                }
                            }
                        }
                    }
                } catch {
                    $cacheComplete = $false
                    $hostInterfaces = $null
                }
            }

            if ($cacheComplete -and $hostInterfaces) {
                $interfacesSnapshot = $hostInterfaces
                $hostScopedSnapshotSelected = $true
            }
        }
    }

    if (-not $hostScopedSnapshotSelected) {
        if ($siteMatch -and $zoneMatch -and $zoneLoadMatch -and (Get-SequenceCount $cachedInterfaces) -gt 0) {
            $interfacesSnapshot = $cachedInterfaces
        }
    }

    if (-not $interfacesSnapshot) {
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

        $interfacesSnapshot = if ($snapshot -and $snapshot.Length -gt 0) {
            [System.Collections.Generic.List[object]]::new($snapshot)
        } else {
            [System.Collections.Generic.List[object]]::new()
        }

        $script:CachedInterfaces = $interfacesSnapshot
        $script:CachedSite = $siteFilter
        $script:CachedZoneSelection = $zoneFilter
        $script:CachedZoneLoad = $zoneLoadParam
    }

    if ($null -eq $interfacesSnapshot) { return @() }

    $results = [System.Collections.Generic.List[object]]::new()
    $metadataLookup = $null
    try { $metadataLookup = $global:DeviceMetadata } catch { $metadataLookup = $null }
    $stringPropertyCmd = script:Get-InterfaceStringPropertyValueCommand

    foreach ($row in $interfacesSnapshot) {
        if (-not $row) { continue }

        $rowMetadata = $null
        $hostnameValue = if ($stringPropertyCmd) { & $stringPropertyCmd -InputObject $row -PropertyNames @('Hostname') } else { '' }
        if (-not $hostnameValue) {
            try {
                if ($row.PSObject.Properties['Hostname']) { $hostnameValue = '' + $row.Hostname }
            } catch { $hostnameValue = '' }
        }

        if ($siteFilter) {
            $siteValue = if ($stringPropertyCmd) { & $stringPropertyCmd -InputObject $row -PropertyNames @('Site') } else { '' }
            if ([string]::IsNullOrWhiteSpace($siteValue) -and $row.PSObject.Properties['Site']) { $siteValue = '' + $row.Site }
            if ([string]::IsNullOrWhiteSpace($siteValue) -and $metadataLookup -and $hostnameValue) {
                try {
                    if (-not $rowMetadata) { $rowMetadata = $metadataLookup[$hostnameValue] }
                    if ($rowMetadata -and $rowMetadata.PSObject.Properties['Site']) { $siteValue = '' + $rowMetadata.Site }
                } catch { Write-Verbose "Caught exception in ViewStateService.psm1: $($_.Exception.Message)" }
            }
            if ([string]::IsNullOrWhiteSpace($siteValue) -and $hostnameValue) {
                try { $siteValue = DeviceRepositoryModule\Get-SiteFromHostname -Hostname $hostnameValue } catch { $siteValue = '' }
                if ([string]::IsNullOrWhiteSpace($siteValue)) {
                    try {
                        $partsSite = $hostnameValue -split '-', 2
                        if ($partsSite.Length -ge 1) { $siteValue = '' + $partsSite[0] }
                    } catch { $siteValue = '' }
                }
                try {
                    if ($row.PSObject.Properties['Site']) {
                        $row.Site = $siteValue
                    } else {
                        $row | Add-Member -NotePropertyName Site -NotePropertyValue $siteValue -Force
                    }
                } catch { Write-Verbose "Caught exception in ViewStateService.psm1: $($_.Exception.Message)" }
            }
            if (-not [string]::Equals($siteValue, $siteFilter, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        }

        if ($zoneFilter) {
            $zoneValue = if ($stringPropertyCmd) { & $stringPropertyCmd -InputObject $row -PropertyNames @('Zone') } else { '' }
            if ([string]::IsNullOrWhiteSpace($zoneValue) -and $row.PSObject.Properties['Zone']) { $zoneValue = '' + $row.Zone }
            if ([string]::IsNullOrWhiteSpace($zoneValue) -and $metadataLookup -and $hostnameValue) {
                try {
                    if (-not $rowMetadata) { $rowMetadata = $metadataLookup[$hostnameValue] }
                    if ($rowMetadata -and $rowMetadata.PSObject.Properties['Zone']) { $zoneValue = '' + $rowMetadata.Zone }
                } catch { Write-Verbose "Caught exception in ViewStateService.psm1: $($_.Exception.Message)" }
            }
            if ([string]::IsNullOrWhiteSpace($zoneValue) -and $hostnameValue) {
                try {
                    $partsZone = $hostnameValue -split '-', 3
                    if ($partsZone.Length -ge 2) { $zoneValue = '' + $partsZone[1] }
                } catch { $zoneValue = '' }
                try {
                    if ($row.PSObject.Properties['Zone']) {
                        $row.Zone = $zoneValue
                    } else {
                        $row | Add-Member -NotePropertyName Zone -NotePropertyValue $zoneValue -Force
                    }
                } catch { Write-Verbose "Caught exception in ViewStateService.psm1: $($_.Exception.Message)" }
            }
            if (-not [string]::Equals($zoneValue, $zoneFilter, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        }

        if ($buildingFilter) {
            $bldValue = if ($stringPropertyCmd) { & $stringPropertyCmd -InputObject $row -PropertyNames @('Building') } else { '' }
            if ([string]::IsNullOrWhiteSpace($bldValue) -and $row.PSObject.Properties['Building']) { $bldValue = '' + $row.Building }
            if ([string]::IsNullOrWhiteSpace($bldValue) -and $metadataLookup -and $hostnameValue) {
                try {
                    if (-not $rowMetadata) { $rowMetadata = $metadataLookup[$hostnameValue] }
                    if ($rowMetadata -and $rowMetadata.PSObject.Properties['Building']) { $bldValue = '' + $rowMetadata.Building }
                } catch { Write-Verbose "Caught exception in ViewStateService.psm1: $($_.Exception.Message)" }
            }
            if (-not [string]::Equals($bldValue, $buildingFilter, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        }

        if ($roomFilter) {
            $roomValue = if ($stringPropertyCmd) { & $stringPropertyCmd -InputObject $row -PropertyNames @('Room') } else { '' }
            if ([string]::IsNullOrWhiteSpace($roomValue) -and $row.PSObject.Properties['Room']) { $roomValue = '' + $row.Room }
            if ([string]::IsNullOrWhiteSpace($roomValue) -and $metadataLookup -and $hostnameValue) {
                try {
                    if (-not $rowMetadata) { $rowMetadata = $metadataLookup[$hostnameValue] }
                    if ($rowMetadata -and $rowMetadata.PSObject.Properties['Room']) { $roomValue = '' + $rowMetadata.Room }
                } catch { Write-Verbose "Caught exception in ViewStateService.psm1: $($_.Exception.Message)" }
            }
            if (-not [string]::Equals($roomValue, $roomFilter, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        }

        [void]$results.Add($row)
    }

    return ,$results
}
function Get-FilterSnapshot {
    [CmdletBinding()]
    param(
        [object]$DeviceMetadata = $global:DeviceMetadata,
        [string]$Site,
        [string]$ZoneSelection,
        [string]$Building,
        [string]$Room,
        [object[]]$LocationEntries
    )

    $siteFilter = ConvertTo-FilterValue -Value $Site -Sentinels @('All Sites')
    $zoneFilter = ConvertTo-FilterValue -Value $ZoneSelection -Sentinels @('All Zones')
    $buildingFilter = ConvertTo-FilterValue -Value $Building -Sentinels @('')
    $roomFilter = ConvertTo-FilterValue -Value $Room -Sentinels @('')

    $buildSnapshot = {
        param($sitesArray, $zonesArray, $buildingsArray, $roomsArray, $hostsArray, $zoneHint)
        return [PSCustomObject]@{
            Sites      = $sitesArray
            Zones      = $zonesArray
            Buildings  = $buildingsArray
            Rooms      = $roomsArray
            Hostnames  = $hostsArray
            ZoneToLoad = $zoneHint
        }
    }

    $emptySnapshot = { & $buildSnapshot @() @() @() @() @() '' }

    try {
        # Fast path: when metadata is null or not enumerable, return an empty snapshot to avoid null derefs.
        $metadataAvailable = $false
        try {
            if ($DeviceMetadata -is [System.Collections.IDictionary]) {
                try {
                    $metaCount = Get-SequenceCount -Value $DeviceMetadata.Keys
                    $metadataAvailable = ($metaCount -gt 0)
                } catch { $metadataAvailable = $false }
            } elseif ($DeviceMetadata -is [System.Collections.IEnumerable]) {
                try {
                    $metaCount = Get-SequenceCount -Value $DeviceMetadata
                    $metadataAvailable = ($metaCount -gt 0)
                } catch { $metadataAvailable = $false }
            }
        } catch { $metadataAvailable = $false }
        $locationAvailable = $false
        try {
            $locCount = Get-SequenceCount -Value $LocationEntries
            $locationAvailable = ($locCount -ge 0)
        } catch { $locationAvailable = $false }
        if (-not $metadataAvailable -and -not $locationAvailable) {
            return & $emptySnapshot
        }

        $siteSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        $zoneSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        $buildingSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        $roomSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        $hostSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

        $entries = $null
        try {
            if ($metadataAvailable) {
                if ($DeviceMetadata -is [System.Collections.IDictionary]) {
                    $entries = $DeviceMetadata.GetEnumerator()
                } elseif ($DeviceMetadata -is [System.Collections.IEnumerable]) {
                    $entries = $DeviceMetadata.GetEnumerator()
                }
            } elseif ($locationAvailable) {
                $entries = $LocationEntries.GetEnumerator()
            }
        } catch {
            $entries = $null
        }
        if (-not $entries) {
            return & $emptySnapshot
        }

        $stringPropertyCmd = script:Get-InterfaceStringPropertyValueCommand

        foreach ($entry in $entries) {
            $hostname = ''
            $meta = $null
            if ($entry -is [System.Collections.DictionaryEntry]) {
                $hostname = '' + $entry.Key
                $meta = $entry.Value
            } elseif ($entry -and $entry.PSObject.Properties['Key'] -and $entry.PSObject.Properties['Value']) {
                $hostname = '' + $entry.Key
                $meta = $entry.Value
            } else {
                $meta = $entry
                if ($entry -and $entry.PSObject.Properties['Hostname']) {
                    $hostname = '' + $entry.Hostname
                }
            }
            if ([string]::IsNullOrWhiteSpace($hostname)) { $hostname = '' }
            if (-not $meta) { continue }
            $siteValue = if ($stringPropertyCmd) { & $stringPropertyCmd -InputObject $meta -PropertyNames @('Site') } else { '' }
            if ([string]::IsNullOrWhiteSpace($siteValue) -and $meta -and $meta.PSObject.Properties['Site']) {
                $siteValue = '' + $meta.Site
            }
            if (-not [string]::IsNullOrWhiteSpace($siteValue)) { [void]$siteSet.Add($siteValue) }

            $zoneValue = if ($stringPropertyCmd) { & $stringPropertyCmd -InputObject $meta -PropertyNames @('Zone') } else { '' }
            if ([string]::IsNullOrWhiteSpace($zoneValue) -and $meta -and $meta.PSObject.Properties['Zone']) {
                $zoneValue = '' + $meta.Zone
            }
            if ([string]::IsNullOrWhiteSpace($zoneValue)) {
                try {
                    $parts = $hostname -split '-'
                    if ($parts.Length -ge 2) { $zoneValue = $parts[1] }
                } catch { $zoneValue = '' }
            }

            $buildingValue = if ($stringPropertyCmd) { & $stringPropertyCmd -InputObject $meta -PropertyNames @('Building') } else { '' }
            if ([string]::IsNullOrWhiteSpace($buildingValue) -and $meta -and $meta.PSObject.Properties['Building']) {
                $buildingValue = '' + $meta.Building
            }

            $roomValue = if ($stringPropertyCmd) { & $stringPropertyCmd -InputObject $meta -PropertyNames @('Room') } else { '' }
            if ([string]::IsNullOrWhiteSpace($roomValue) -and $meta -and $meta.PSObject.Properties['Room']) {
                $roomValue = '' + $meta.Room
            }

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
                if (-not [string]::IsNullOrWhiteSpace($hostname)) {
                    [void]$hostSet.Add($hostname)
                }
            }
        }

        $sites = New-SortedStringList -Set $siteSet
        $zones = New-SortedStringList -Set $zoneSet
        $buildings = New-SortedStringList -Set $buildingSet
        $rooms = New-SortedStringList -Set $roomSet
        $hosts = Get-PreferredHostnames -HostSet $hostSet
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

        return & $buildSnapshot $sitesArray $zonesArray $buildingsArray $roomsArray $hostsArray $zoneToLoad
    } catch {
        Write-Verbose ("[ViewStateService] Get-FilterSnapshot failed: {0}" -f $_.Exception.Message)
        return & $emptySnapshot
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

Export-ModuleMember -Function Import-ViewStateServiceModule, Get-InterfacesForContext, Get-FilterSnapshot, Get-ZoneLoadHint, Get-SequenceCount
