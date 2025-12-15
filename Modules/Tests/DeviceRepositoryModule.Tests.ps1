Set-StrictMode -Version Latest

function Set-RepositoryVar {
    param(
        [string]$Name,
        $Value,
        [string]$ModuleName = 'DeviceRepositoryModule'
    )
    $module = Get-Module $ModuleName -ErrorAction Stop
    $module.SessionState.PSVariable.Set($Name, $Value)
}

function Remove-RepositoryVar {
    param(
        [string]$Name,
        [string]$ModuleName = 'DeviceRepositoryModule'
    )
    $module = Get-Module $ModuleName -ErrorAction Stop
    try { $module.SessionState.PSVariable.Remove($Name) } catch {}
}

Describe "DeviceRepositoryModule core helpers" {
    BeforeAll {
        $modulePath = Join-Path (Split-Path $PSCommandPath) "..\DeviceRepositoryModule.psm1"
        Import-Module (Resolve-Path $modulePath) -Force

        $script:OriginalGlobals = @{}
        foreach ($name in 'DeviceInterfaceCache','AllInterfaces','LoadedSiteZones','DeviceMetadata') {
            if (Get-Variable -Name $name -Scope Global -ErrorAction SilentlyContinue) {
                $script:OriginalGlobals[$name] = Get-Variable -Name $name -Scope Global -ValueOnly
            } else {
                $script:OriginalGlobals[$name] = $null
            }
        }
    }

    AfterAll {
        Remove-Module DeviceRepositoryModule -Force
        foreach ($name in $script:OriginalGlobals.Keys) {
            $value = $script:OriginalGlobals[$name]
            if ($value -ne $null) {
                Set-Variable -Name $name -Scope Global -Value $value
            } else {
                Remove-Variable -Name $name -Scope Global -ErrorAction SilentlyContinue
            }
        }
    }

    BeforeEach {
        $global:DeviceInterfaceCache = @{}
        $global:AllInterfaces = [System.Collections.Generic.List[object]]::new()
        $global:LoadedSiteZones = @{}
        $global:DeviceMetadata = @{}
        Set-RepositoryVar -Name 'SiteInterfaceCache' -Value @{}
        Remove-RepositoryVar -Name 'DataDirPath'
    }

    It "derives site codes from hostnames" {
        DeviceRepositoryModule\Get-SiteFromHostname -Hostname 'SITE1-Z1-SW1' | Should Be 'SITE1'
        DeviceRepositoryModule\Get-SiteFromHostname -Hostname 'SSH@SITE2-Z9-EDGE' | Should Be 'SITE2'
        DeviceRepositoryModule\Get-SiteFromHostname -Hostname 'core' -FallbackLength 3 | Should Be 'cor'
    }

    It "returns absolute paths for discovered .accdb files" {
        $dataRoot = Join-Path $TestDrive 'DbPaths'
        New-Item -ItemType Directory -Path $dataRoot -Force | Out-Null
        $legacy = Join-Path $dataRoot 'Legacy.accdb'
        New-Item -ItemType File -Path $legacy -Force | Out-Null

        $siteDir = Join-Path $dataRoot 'SITE1'
        New-Item -ItemType Directory -Path $siteDir -Force | Out-Null
        $grouped = Join-Path $siteDir 'SITE1-EDGE.accdb'
        New-Item -ItemType File -Path $grouped -Force | Out-Null

        Set-RepositoryVar -Name 'DataDirPath' -Value $dataRoot

        $paths = DeviceRepositoryModule\Get-AllSiteDbPaths

        $paths | Should Not BeNullOrEmpty
        $paths.Count | Should Be 2
        ($paths -contains $legacy) | Should Be $true
        ($paths -contains $grouped) | Should Be $true
        foreach ($path in $paths) {
            [System.IO.Path]::IsPathRooted($path) | Should Be $true
            [System.IO.Path]::GetExtension($path) | Should Be '.accdb'
        }
    }

    It "prefers grouped directories when deriving new database paths" {
        $dataRoot = Join-Path $TestDrive 'GroupedLayouts'
        New-Item -ItemType Directory -Path $dataRoot -Force | Out-Null
        Set-RepositoryVar -Name 'DataDirPath' -Value $dataRoot

        $path = DeviceRepositoryModule\Get-DbPathForSite -Site 'WLLS'
        $expected = Join-Path (Join-Path $dataRoot 'WLLS') 'WLLS.accdb'
        $path | Should Be $expected
    }

    It "derives grouped paths when host-style tokens are provided" {
        $dataRoot = Join-Path $TestDrive 'HostStyleLayouts'
        New-Item -ItemType Directory -Path $dataRoot -Force | Out-Null
        Set-RepositoryVar -Name 'DataDirPath' -Value $dataRoot

        $path = DeviceRepositoryModule\Get-DbPathForSite -Site 'WLLS-A01-SW01'
        $expected = Join-Path (Join-Path $dataRoot 'WLLS') 'WLLS-A01-SW01.accdb'
        $path | Should Be $expected
    }

    It "falls back to legacy root when an existing database is present" {
        $dataRoot = Join-Path $TestDrive 'LegacyLayouts'
        New-Item -ItemType Directory -Path $dataRoot -Force | Out-Null
        $legacy = Join-Path $dataRoot 'BRAVO.accdb'
        New-Item -ItemType File -Path $legacy -Force | Out-Null
        Set-RepositoryVar -Name 'DataDirPath' -Value $dataRoot

        $path = DeviceRepositoryModule\Get-DbPathForSite -Site 'BRAVO'
        $path | Should Be $legacy
    }

    It "sanitizes invalid characters in site prefixes" {
        $dataRoot = Join-Path $TestDrive 'SanitizedLayouts'
        New-Item -ItemType Directory -Path $dataRoot -Force | Out-Null
        Set-RepositoryVar -Name 'DataDirPath' -Value $dataRoot

        $path = DeviceRepositoryModule\Get-DbPathForSite -Site 'ACME:HQ-EDGE1'
        $expectedDir = Join-Path $dataRoot 'ACME_HQ'
        $expected = Join-Path $expectedDir 'ACME:HQ-EDGE1.accdb'
        $path | Should Be $expected
    }
      It "clears the per-site interface cache" {
          Set-RepositoryVar -Name 'SiteInterfaceCache' -Value @{ 'SITE1' = 1 }
          DeviceRepositoryModule\Clear-SiteInterfaceCache
          $cache = Get-Module DeviceRepositoryModule | ForEach-Object { $_.SessionState.PSVariable.Get('SiteInterfaceCache').Value }
          $cache.Keys.Count | Should Be 0
      }
      It "accepts a reason when clearing the cache" {
          { DeviceRepositoryModule\Clear-SiteInterfaceCache -Reason 'UnitTest' } | Should Not Throw
      }

    It "adopts shared cache entries from the AppDomain store when script cache is empty" {
        $module = Get-Module DeviceRepositoryModule -ErrorAction Stop
        $cacheKey = $module.SessionState.PSVariable.Get('SharedSiteInterfaceCacheKey').Value
        $domainStore = New-Object 'System.Collections.Concurrent.ConcurrentDictionary[string, object]' ([System.StringComparer]::OrdinalIgnoreCase)
        $entry = [pscustomobject]@{ Site = 'SITE1'; HostCount = 1 }
        [void]$domainStore.TryAdd('SITE1', $entry)
        [System.AppDomain]::CurrentDomain.SetData($cacheKey, $domainStore)
        try { [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::ClearStore() } catch { }
        Set-RepositoryVar -Name 'SharedSiteInterfaceCache' -Value (New-Object 'System.Collections.Concurrent.ConcurrentDictionary[string, object]' ([System.StringComparer]::OrdinalIgnoreCase))

        $store = $module.Invoke({ Get-SharedSiteInterfaceCacheStore })

        [object]::ReferenceEquals($store, $domainStore) | Should Be $true
        $scriptStore = $module.SessionState.PSVariable.Get('SharedSiteInterfaceCache').Value
        [object]::ReferenceEquals($scriptStore, $domainStore) | Should Be $true
        $holderStore = $module.Invoke({ try { [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::GetStore() } catch { $null } })
        [object]::ReferenceEquals($holderStore, $domainStore) | Should Be $true

        DeviceRepositoryModule\Clear-SiteInterfaceCache
        [System.AppDomain]::CurrentDomain.SetData($cacheKey, $null)
        try { [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::ClearStore() } catch { }
    }

    It "marks cache status as SharedOnly when reusing shared store entries" {
        DeviceRepositoryModule\Clear-SiteInterfaceCache
        $siteKey = 'SHAREDONLY'
        $hostKey = 'SHAREDONLY-A01-AS-01'
        $ports = New-Object 'System.Collections.Generic.Dictionary[string,StateTrace.Models.InterfaceCacheEntry]' ([System.StringComparer]::OrdinalIgnoreCase)
        $entryModel = [StateTrace.Models.InterfaceCacheEntry]::new()
        $entryModel.Name = 'Gi1/0/1'
        $entryModel.Status = 'up'
        $entryModel.Signature = 'sig-sharedonly'
        $ports['Gi1/0/1'] = $entryModel
        $hostMap = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.Dictionary[string,StateTrace.Models.InterfaceCacheEntry]]' ([System.StringComparer]::OrdinalIgnoreCase)
        $hostMap[$hostKey] = $ports
        $sharedEntry = [pscustomobject]@{
            HostMap   = $hostMap
            TotalRows = 1
            HostCount = 1
            CachedAt  = Get-Date
        }

        $module = Get-Module DeviceRepositoryModule -ErrorAction Stop
        try { [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::ClearStore() } catch { }
        Set-RepositoryVar -Name 'SharedSiteInterfaceCache' -Value (New-Object 'System.Collections.Concurrent.ConcurrentDictionary[string, object]' ([System.StringComparer]::OrdinalIgnoreCase))

        try {
            $module.Invoke({ param($site, $entry) Set-SharedSiteInterfaceCacheEntry -SiteKey $site -Entry $entry }, $siteKey, $sharedEntry) | Out-Null

            $result = DeviceRepositoryModule\Get-InterfaceSiteCache -Site $siteKey
            $result | Should Not BeNullOrEmpty
            $result.HostMap.Keys.Count | Should Be 1
            $result.HostMap.ContainsKey($hostKey) | Should Be $true

            $metrics = DeviceRepositoryModule\Get-LastInterfaceSiteCacheMetrics
            $metrics | Should Not BeNullOrEmpty
            $metrics.CacheStatus | Should Be 'SharedOnly'
            $metrics.HydrationProvider | Should Be 'Cache'
            $metrics.TotalRows | Should Be 1
            $metrics.HostCount | Should Be 1
        } finally {
            $module.Invoke({ param($site) Set-SharedSiteInterfaceCacheEntry -SiteKey $site -Entry $null }, $siteKey) | Out-Null
            Set-RepositoryVar -Name 'SharedSiteInterfaceCache' -Value (New-Object 'System.Collections.Concurrent.ConcurrentDictionary[string, object]' ([System.StringComparer]::OrdinalIgnoreCase))
            try { [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::ClearStore() } catch { }
        }
    }

    It "loads site data once per zone" {
        $global:DeviceMetadata = @{
            'SITE1-Z1-SW1' = [pscustomobject]@{ Site = 'SITE1'; Zone = 'Z1' }
        }
        Mock -ModuleName DeviceRepositoryModule -CommandName Get-InterfaceInfo {
            param([string]$Hostname)
            @([pscustomobject]@{ Hostname = $Hostname; Site = 'SITE1'; Zone = 'Z1'; Port = 'Gi1' })
        }

        DeviceRepositoryModule\Update-SiteZoneCache -Site 'SITE1' -Zone 'Z1'
        DeviceRepositoryModule\Update-SiteZoneCache -Site 'SITE1' -Zone 'Z1'

        $global:LoadedSiteZones.ContainsKey('SITE1|Z1') | Should Be $true
        $global:AllInterfaces.Count | Should Be 1
        Assert-MockCalled Get-InterfaceInfo -ModuleName DeviceRepositoryModule -Times 1 -ParameterFilter { $Hostname -eq 'SITE1-Z1-SW1' }
    }

    It "returns snapshots without mutating global interface cache" {
        $global:DeviceInterfaceCache = @{
            'SITE1-Z1-SW1' = @([pscustomobject]@{ Hostname = 'SITE1-Z1-SW1'; Site = 'SITE1'; Zone = 'Z1'; Port = 'Gi1'; PortSort = '001'; Status = 'up'; AuthState = 'authorized' })
        }

        $snapshot = DeviceRepositoryModule\Get-GlobalInterfaceSnapshot -Site 'SITE1' -ZoneSelection 'Z1'

        $snapshot | Should Not BeNullOrEmpty
        $snapshot.Length | Should Be 1
        $snapshot[0].Hostname | Should Be 'SITE1-Z1-SW1'
        (Get-Variable -Name AllInterfaces -Scope Global -ValueOnly).Count | Should Be 0
    }
    It "filters global snapshots by zone when site is not specified" {
        $global:DeviceInterfaceCache = @{
            'SITE1-Z1-SW1' = @([pscustomobject]@{ Hostname = 'SITE1-Z1-SW1'; Site = 'SITE1'; Zone = 'Z1'; Port = 'Gi1'; Status = 'up' })
            'SITE2-Z2-SW2' = @([pscustomobject]@{ Hostname = 'SITE2-Z2-SW2'; Site = 'SITE2'; Zone = 'Z2'; Port = 'Gi2'; Status = 'down' })
        }

        $snapshot = DeviceRepositoryModule\Get-GlobalInterfaceSnapshot -ZoneSelection 'Z1'

        $snapshot | Should Not BeNullOrEmpty
        $snapshot.Length | Should Be 1
        $snapshot[0].Hostname | Should Be 'SITE1-Z1-SW1'
    }
    It "builds the global interface list for a site/zone selection" {
        $global:DeviceInterfaceCache = @{
            'SITE1-Z1-SW1' = @([pscustomobject]@{ Hostname = 'SITE1-Z1-SW1'; Site = 'SITE1'; Zone = 'Z1'; Port = 'Gi1'; PortSort = '001'; Status = 'up'; AuthState = 'authorized' })
            'SITE1-Z2-SW2' = @([pscustomobject]@{ Hostname = 'SITE1-Z2-SW2'; Site = 'SITE1'; Zone = 'Z2'; Port = 'Gi2'; PortSort = '002'; Status = 'down'; AuthState = 'unauthorized' })
        }
        Mock -ModuleName DeviceRepositoryModule -CommandName Update-SiteZoneCache {}

        $result = @(DeviceRepositoryModule\Update-GlobalInterfaceList -Site 'SITE1' -ZoneSelection 'Z1')

        $result.Count | Should Be 1
        $result[0].Hostname | Should Be 'SITE1-Z1-SW1'
        ($result[0].PSObject.Properties.Name -contains 'IsSelected') | Should Be $true
    }

    It "projects interface rows when InterfaceModule helpers are unavailable" {
        $module = Get-Module DeviceRepositoryModule -ErrorAction Stop
        $row = [pscustomobject]@{
            Port          = 'Gi1/0/1'
            Name          = 'Port1'
            Status        = 'Up'
            VLAN          = '10'
            Duplex        = 'full'
            Speed         = '1G'
            Type          = 'access'
            LearnedMACs   = '0011.2233.4455'
            AuthState     = 'Authorized'
            AuthMode      = 'dot1x'
            AuthClientMAC = '0011.2233.4455'
            AuthTemplate  = 'Default'
            Config        = ''
            ConfigStatus  = 'Match'
            PortColor     = 'Green'
            ToolTip       = ''
        }

        $result = $module.Invoke({
            param($data, $host)
            ConvertTo-InterfacePortRecordsFallback -Data $data -Hostname $host
        }, @(@($row), 'SITE1-Z1-SW1'))
        $items = @($result)

        $items | Should Not BeNullOrEmpty
        $items.Count | Should Be 1
        $items[0].Port | Should Be 'Gi1/0/1'
        $items[0].Hostname | Should Be 'SITE1-Z1-SW1'
        ($items[0].PSObject.Properties.Name -contains 'IsSelected') | Should Be $true
    }

    It "emits cache-hit metrics when returning cached site entry" {
        $hostMap = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.Dictionary[string,StateTrace.Models.InterfaceCacheEntry]]' ([System.StringComparer]::OrdinalIgnoreCase)
        $portMap = New-Object 'System.Collections.Generic.Dictionary[string,StateTrace.Models.InterfaceCacheEntry]' ([System.StringComparer]::OrdinalIgnoreCase)
        $entry = [StateTrace.Models.InterfaceCacheEntry]::new()
        $entry.Name = 'Et1/1/1'
        $entry.Status = 'up'
        $entry.Signature = 'sig-et1'
        $portMap['Et1/1/1'] = $entry
        $hostMap['SITE1-A01-AS-01'] = $portMap

        $cachedSiteEntry = [pscustomobject]@{
            HostMap   = $hostMap
            TotalRows = 1
            HostCount = 1
            CachedAt  = Get-Date
            CacheStatus = 'Hydrated'
            HydrationProvider = 'ADODB'
            HydrationHostMapSignatureRewriteCount = 1
            HydrationHostMapCandidateMissingCount = 1
            HydrationHostMapCandidateMissingSamples = @([pscustomobject]@{
                    Hostname                 = 'SITE1-A01-AS-01'
                    Port                     = 'Et1/1/1'
                    Reason                   = 'HostSnapshotMissing'
                    PreviousHostEntryPresent = $false
                    PreviousPortEntryPresent = $false
                    CachedPortCount          = 0
                    CachedPortSample         = ''
                    CachedSignature          = $null
                    PreviousRemainingPortCount = 0
                    CandidateSource          = ''
                })
            HydrationResultRowCount = 1
        }

        Set-RepositoryVar -Name 'SiteInterfaceSignatureCache' -Value @{ 'SITE1' = $cachedSiteEntry }

        try {
            $result = DeviceRepositoryModule\Get-InterfaceSiteCache -Site 'SITE1'

            $result | Should Not BeNullOrEmpty
            $result.HostMap.Keys.Count | Should Be 1
            $result.HostMap['SITE1-A01-AS-01'].ContainsKey('Et1/1/1') | Should Be $true

            $metrics = DeviceRepositoryModule\Get-LastInterfaceSiteCacheMetrics
            $metrics | Should Not BeNullOrEmpty
            $metrics.CacheStatus | Should Be 'Hydrated'
            $metrics.HydrationProvider | Should Be 'Cache'
            $metrics.HydrationHostMapSignatureMatchCount | Should Be 1
            $metrics.HydrationHostMapCandidateMissingCount | Should Be 0
            $metrics.TotalRows | Should Be 1
            $metrics.HostCount | Should Be 1
            $metrics.HydrationDurationMs | Should Be 0
            ($metrics.PSObject.Properties.Name -contains 'HydrationSnapshotRecordsetDurationMs') | Should Be $true
            $metrics.HydrationSnapshotRecordsetDurationMs | Should Be 0
            ($metrics.PSObject.Properties.Name -contains 'HydrationSnapshotProjectDurationMs') | Should Be $true
            $metrics.HydrationSnapshotProjectDurationMs | Should Be 0
            ($metrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateLookupDurationMs') | Should Be $true
            $metrics.HydrationMaterializeTemplateLookupDurationMs | Should Be 0
            ($metrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateApplyDurationMs') | Should Be $true
            $metrics.HydrationMaterializeTemplateApplyDurationMs | Should Be 0
            ($metrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateCacheHitCount') | Should Be $true
            $metrics.HydrationMaterializeTemplateCacheHitCount | Should Be 0
            ($metrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateCacheMissCount') | Should Be $true
            $metrics.HydrationMaterializeTemplateCacheMissCount | Should Be 0
            ($metrics.PSObject.Properties.Name -contains 'HydrationMaterializePortSortUniquePortCount') | Should Be $true
            $metrics.HydrationMaterializePortSortUniquePortCount | Should Be 0
            ($metrics.PSObject.Properties.Name -contains 'HydrationMaterializePortSortMissSamples') | Should Be $true
            @($metrics.HydrationMaterializePortSortMissSamples).Count | Should Be 0
            ($metrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateApplyCount') | Should Be $true
            $metrics.HydrationMaterializeTemplateApplyCount | Should Be 0
            ($metrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateDefaultedCount') | Should Be $true
            $metrics.HydrationMaterializeTemplateDefaultedCount | Should Be 0
            ($metrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateAuthTemplateMissingCount') | Should Be $true
            $metrics.HydrationMaterializeTemplateAuthTemplateMissingCount | Should Be 0
            ($metrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateNoTemplateMatchCount') | Should Be $true
            $metrics.HydrationMaterializeTemplateNoTemplateMatchCount | Should Be 0
            ($metrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateReuseCount') | Should Be $true
            $metrics.HydrationMaterializeTemplateReuseCount | Should Be 0
            ($metrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateHintAppliedCount') | Should Be $true
            $metrics.HydrationMaterializeTemplateHintAppliedCount | Should Be 0
            ($metrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateSetPortColorCount') | Should Be $true
            $metrics.HydrationMaterializeTemplateSetPortColorCount | Should Be 0
            ($metrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateSetConfigStatusCount') | Should Be $true
            $metrics.HydrationMaterializeTemplateSetConfigStatusCount | Should Be 0
            ($metrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateApplySamples') | Should Be $true
            @($metrics.HydrationMaterializeTemplateApplySamples).Count | Should Be 0
        } finally {
            Set-RepositoryVar -Name 'SiteInterfaceSignatureCache' -Value @{}
        }
    }

    It "persists port sort values when caching site hosts" {
        $siteKey = 'SITE1'
        $hostKey = 'SITE1-A01-AS-01'
        $portKey = 'Gi1/0/1'
        $expectedPortSort = '01-GI-00001-00000-00000-00000-00000'

        Set-RepositoryVar -Name 'SiteInterfaceSignatureCache' -Value @{}

        try {
            $rowsByPort = @{
                $portKey = [pscustomobject]@{
                    Name      = 'GigabitEthernet1/0/1'
                    Status    = 'up'
                    Port      = $portKey
                    PortSort  = $expectedPortSort
                    AuthState = 'authorized'
                }
            }

            DeviceRepositoryModule\Set-InterfaceSiteCacheHost -Site $siteKey -Hostname $hostKey -RowsByPort $rowsByPort

            $module = Get-Module DeviceRepositoryModule -ErrorAction Stop
            $signatureCache = $module.SessionState.PSVariable.GetValue('SiteInterfaceSignatureCache')

            $signatureCache | Should Not BeNullOrEmpty
            $signatureCache.ContainsKey($siteKey) | Should Be $true

            $hostMap = $signatureCache[$siteKey].HostMap
            $hostMap.ContainsKey($hostKey) | Should Be $true

            $storedEntry = $hostMap[$hostKey][$portKey]
            $storedEntry | Should Not BeNullOrEmpty
            $storedEntry | Should BeOfType 'StateTrace.Models.InterfaceCacheEntry'
            $storedEntry.PortSort | Should Be $expectedPortSort
        } finally {
            Set-RepositoryVar -Name 'SiteInterfaceSignatureCache' -Value @{}
        }
    }

    It "retains existing hosts when updating cached rows without a new snapshot" {
        $siteKey = 'SITECACHEPRESERVE'
        $hostOne = 'SITECACHEPRESERVE-A01-AS-01'
        $hostTwo = 'SITECACHEPRESERVE-A01-AS-02'

        Set-RepositoryVar -Name 'SiteInterfaceSignatureCache' -Value @{}

        try {
            $entryOne = [StateTrace.Models.InterfaceCacheEntry]::new()
            $entryOne.Name = 'GigabitEthernet1/0/1'
            $entryOne.Status = 'up'
            $entryOne.PortSort = '01-GI-00001-00000-00000-00000-00000'
            $entryOne.Signature = 'sig-host1-port1'

            $entryTwo = [StateTrace.Models.InterfaceCacheEntry]::new()
            $entryTwo.Name = 'GigabitEthernet1/0/2'
            $entryTwo.Status = 'up'
            $entryTwo.PortSort = '01-GI-00002-00000-00000-00000-00000'
            $entryTwo.Signature = 'sig-host2-port1'

            $hostOnePorts = New-Object 'System.Collections.Generic.Dictionary[string,StateTrace.Models.InterfaceCacheEntry]' ([System.StringComparer]::OrdinalIgnoreCase)
            $hostOnePorts['Gi1/0/1'] = $entryOne

            $hostTwoPorts = New-Object 'System.Collections.Generic.Dictionary[string,StateTrace.Models.InterfaceCacheEntry]' ([System.StringComparer]::OrdinalIgnoreCase)
            $hostTwoPorts['Gi1/0/2'] = $entryTwo

            $seedHostMap = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.Dictionary[string,StateTrace.Models.InterfaceCacheEntry]]' ([System.StringComparer]::OrdinalIgnoreCase)
            $seedHostMap[$hostOne] = $hostOnePorts
            $seedHostMap[$hostTwo] = $hostTwoPorts

            $seedEntry = [pscustomobject]@{
                HostMap   = $seedHostMap
                TotalRows = 2
                HostCount = 2
                CachedAt  = Get-Date
                CacheStatus = 'Hit'
                HydrationHostMapSignatureMatchCount = 2
                HydrationHostMapCandidateFromPreviousCount = 2
            }

            Set-RepositoryVar -Name 'SiteInterfaceSignatureCache' -Value @{ $siteKey = $seedEntry }

            $cachedRowsHostOne = @{
                'Gi1/0/1' = [pscustomobject]@{
                    Port      = 'Gi1/0/1'
                    Name      = 'GigabitEthernet1/0/1'
                    Status    = 'up'
                    Signature = 'sig-host1-port1'
                    PortSort  = '01-GI-00001-00000-00000-00000-00000'
                }
            }

            DeviceRepositoryModule\Set-InterfaceSiteCacheHost -Site $siteKey -Hostname $hostOne -RowsByPort $cachedRowsHostOne

            $module = Get-Module DeviceRepositoryModule -ErrorAction Stop
            $signatureCache = $module.SessionState.PSVariable.GetValue('SiteInterfaceSignatureCache')

            $signatureCache.ContainsKey($siteKey) | Should Be $true
            $updatedEntry = $signatureCache[$siteKey]
            $updatedEntry.HostMap.Keys.Count | Should Be 2
            $updatedEntry.HostMap.ContainsKey($hostOne) | Should Be $true
            $updatedEntry.HostMap.ContainsKey($hostTwo) | Should Be $true
            $updatedEntry.HostMap[$hostTwo].ContainsKey('Gi1/0/2') | Should Be $true

            $metrics = DeviceRepositoryModule\Get-LastInterfaceSiteCacheMetrics
            $metrics.CacheStatus | Should Be 'Hydrated'
            $metrics.HydrationHostMapCandidateFromPreviousCount | Should Be 1
            $metrics.HydrationHostMapSignatureMatchCount | Should Be 1

            $cachedRowsHostTwo = @{
                'Gi1/0/2' = [pscustomobject]@{
                    Port      = 'Gi1/0/2'
                    Name      = 'GigabitEthernet1/0/2'
                    Status    = 'up'
                    Signature = 'sig-host2-port1'
                    PortSort  = '01-GI-00002-00000-00000-00000-00000'
                }
            }

            DeviceRepositoryModule\Set-InterfaceSiteCacheHost -Site $siteKey -Hostname $hostTwo -RowsByPort $cachedRowsHostTwo

            $postUpdateCache = $module.SessionState.PSVariable.GetValue('SiteInterfaceSignatureCache')
            $postUpdateCache[$siteKey].HostMap.Keys.Count | Should Be 2
            $postUpdateCache[$siteKey].HostMap.ContainsKey($hostOne) | Should Be $true
            $postUpdateCache[$siteKey].HostMap.ContainsKey($hostTwo) | Should Be $true
        } finally {
            Set-RepositoryVar -Name 'SiteInterfaceSignatureCache' -Value @{}
        }
    }

    It "merges shared cache entries when multiple workers publish hosts" {
        $siteKey = 'SHAREDMERGE'
        $hostOne = 'SHAREDMERGE-A01-AS-01'
        $hostTwo = 'SHAREDMERGE-A01-AS-02'
        $module = Get-Module DeviceRepositoryModule -ErrorAction Stop

        $sharedStore = New-Object 'System.Collections.Concurrent.ConcurrentDictionary[string, object]' ([System.StringComparer]::OrdinalIgnoreCase)
        Set-RepositoryVar -Name 'SharedSiteInterfaceCache' -Value $sharedStore

        try {
            $initialEntry = [pscustomobject]@{
                HostMap = @{
                    $hostOne = @{
                        'Gi1/0/1' = [pscustomobject]@{
                            Port       = 'Gi1/0/1'
                            Name       = 'GigabitEthernet1/0/1'
                            Status     = 'up'
                            Signature  = 'sig-host1-port1'
                            PortSort   = '01-GI-00001-00000-00000-00000-00000'
                        }
                    }
                }
                CacheStatus = 'Hit'
                CachedAt    = (Get-Date).AddMinutes(-1)
                HostCount   = 1
                TotalRows   = 1
                HydrationHostMapSignatureMatchCount = 1
            }

            $module.Invoke({ param($site, $entry) Set-SharedSiteInterfaceCacheEntry -SiteKey $site -Entry $entry }, $siteKey, $initialEntry) | Out-Null

            $updateEntry = [pscustomobject]@{
                HostMap = @{
                    $hostTwo = @{
                        'Gi1/0/2' = [pscustomobject]@{
                            Port       = 'Gi1/0/2'
                            Name       = 'GigabitEthernet1/0/2'
                            Status     = 'up'
                            Signature  = 'sig-host2-port1'
                            PortSort   = '01-GI-00002-00000-00000-00000-00000'
                        }
                    }
                }
                CacheStatus = 'Hit'
                CachedAt    = Get-Date
                HydrationHostMapSignatureMatchCount = 1
            }

            $module.Invoke({ param($site, $entry) Set-SharedSiteInterfaceCacheEntry -SiteKey $site -Entry $entry }, $siteKey, $updateEntry) | Out-Null

            $merged = $module.Invoke({ param($site) Get-SharedSiteInterfaceCacheEntry -SiteKey $site }, $siteKey)

            $merged | Should Not BeNullOrEmpty
            $merged.HostCount | Should Be 2
            $merged.TotalRows | Should Be 2
            $merged.HostMap.ContainsKey($hostOne) | Should Be $true
            $merged.HostMap.ContainsKey($hostTwo) | Should Be $true
            $merged.HostMap[$hostOne].ContainsKey('Gi1/0/1') | Should Be $true
            $merged.HostMap[$hostTwo].ContainsKey('Gi1/0/2') | Should Be $true
            $merged.HydrationHostMapSignatureMatchCount | Should Be 1
            $merged.CacheStatus | Should Be 'Hit'
        } finally {
            $module.Invoke({ param($site) Set-SharedSiteInterfaceCacheEntry -SiteKey $site -Entry $null }, $siteKey) | Out-Null
            Set-RepositoryVar -Name 'SharedSiteInterfaceCache' -Value (New-Object 'System.Collections.Concurrent.ConcurrentDictionary[string, object]' ([System.StringComparer]::OrdinalIgnoreCase))
        }
    }
    It "refreshes script cache from shared store when host map is incomplete" {
        DeviceRepositoryModule\Clear-SiteInterfaceCache
        $module = Get-Module DeviceRepositoryModule -ErrorAction Stop
        Set-RepositoryVar -Name 'SharedSiteInterfaceCache' -Value (New-Object 'System.Collections.Concurrent.ConcurrentDictionary[string, object]' ([System.StringComparer]::OrdinalIgnoreCase))
        $siteKey = 'SITE1'

        $host1Rows = @{
            'Gi1/0/1' = [pscustomobject]@{
                Name          = 'Gi1/0/1'
                Status        = 'up'
                VLAN          = '1'
                Duplex        = 'full'
                Speed         = '1 Gbps'
                Type          = 'access'
                LearnedMACs   = ''
                AuthState     = 'authorized'
                AuthMode      = 'dot1x'
                AuthClientMAC = ''
                AuthTemplate  = ''
                Config        = ''
                PortColor     = ''
                ConfigStatus  = ''
                ToolTip       = ''
                Signature     = 'sig-host1'
            }
        }

        DeviceRepositoryModule\Set-InterfaceSiteCacheHost -Site $siteKey -Hostname 'SITE1-A01-AS-01' -RowsByPort $host1Rows

        $sharedEntry = $module.Invoke({ param($site) Get-SharedSiteInterfaceCacheEntry -SiteKey $site }, $siteKey)
        $hostMap = $sharedEntry.HostMap
        $typedHostTwo = New-Object 'System.Collections.Generic.Dictionary[string,StateTrace.Models.InterfaceCacheEntry]' ([System.StringComparer]::OrdinalIgnoreCase)
        $portEntryTwo = $module.Invoke({
                param($row)
                ConvertTo-InterfaceCacheEntryObject -InputObject $row
            }, ([pscustomobject]@{
                Name          = 'Gi1/0/2'
                Status        = 'down'
                VLAN          = '2'
                Duplex        = 'full'
                Speed         = '1 Gbps'
                Type          = 'access'
                LearnedMACs   = ''
                AuthState     = 'unauthorized'
                AuthMode      = 'dot1x'
                AuthClientMAC = ''
                AuthTemplate  = ''
                Config        = ''
                PortColor     = ''
                ConfigStatus  = ''
                ToolTip       = ''
                Signature     = 'sig-host2'
            }))
        $typedHostTwo['Gi1/0/2'] = $portEntryTwo
        $hostMap['SITE1-A02-AS-01'] = $typedHostTwo
        $sharedEntry.TotalRows = 2
        $sharedEntry.HostCount = 2

        try {
            $module.Invoke({ param($site, $entry) Set-SharedSiteInterfaceCacheEntry -SiteKey $site -Entry $entry }, $siteKey, $sharedEntry) | Out-Null

            $preHostCount = $module.Invoke({
                    param($site)
                    if ($script:SiteInterfaceSignatureCache.ContainsKey($site)) {
                        $map = $script:SiteInterfaceSignatureCache[$site].HostMap
                        if ($map -is [System.Collections.IDictionary]) { return [int]$map.Count }
                    }
                    return 0
                }, $siteKey)
            $preHostCount | Should Be 1

            $result = DeviceRepositoryModule\Get-InterfaceSiteCache -Site $siteKey

            $result | Should Not BeNullOrEmpty
            $result.HostMap.Count | Should Be 2
            $result.HostMap.ContainsKey('SITE1-A02-AS-01') | Should Be $true

            $postHostCount = $module.Invoke({
                    param($site)
                    if ($script:SiteInterfaceSignatureCache.ContainsKey($site)) {
                        $map = $script:SiteInterfaceSignatureCache[$site].HostMap
                        if ($map -is [System.Collections.IDictionary]) { return [int]$map.Count }
                    }
                    return 0
                }, $siteKey)
            $postHostCount | Should Be 2
        } finally {
            $module.Invoke({ param($site) Set-SharedSiteInterfaceCacheEntry -SiteKey $site -Entry $null }, $siteKey) | Out-Null
            Set-RepositoryVar -Name 'SharedSiteInterfaceCache' -Value (New-Object 'System.Collections.Concurrent.ConcurrentDictionary[string, object]' ([System.StringComparer]::OrdinalIgnoreCase))
        }
    }

    It "exports shared cache snapshot entries with host maps" {
        $siteKey = 'SNAPSHOTTEST'
        $hostname = 'SNAPSHOTTEST-A01-AS-01'
        $module = Get-Module DeviceRepositoryModule -ErrorAction Stop

        try {
            DeviceRepositoryModule\Clear-SiteInterfaceCache
            try { [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::ClearSnapshot() } catch { }

            $rows = @{
                'Gi1/0/1' = [pscustomobject]@{
                    Port      = 'Gi1/0/1'
                    Name      = 'GigabitEthernet1/0/1'
                    Status    = 'up'
                    VLAN      = '10'
                    Signature = 'snapshot-port1'
                    PortSort  = '01-GI-00001-00000-00000-00000-00000'
                }
                'Gi1/0/2' = [pscustomobject]@{
                    Port      = 'Gi1/0/2'
                    Name      = 'GigabitEthernet1/0/2'
                    Status    = 'down'
                    VLAN      = '20'
                    Signature = 'snapshot-port2'
                    PortSort  = '01-GI-00002-00000-00000-00000-00000'
                }
            }

            DeviceRepositoryModule\Set-InterfaceSiteCacheHost -Site $siteKey -Hostname $hostname -RowsByPort $rows

            $snapshotEntries = $module.Invoke({ Get-SharedSiteInterfaceCacheSnapshotEntries })
            $snapshotEntries | Should Not BeNullOrEmpty
            $snapshotEntries.Count | Should Be 1

            $entry = $snapshotEntries[0].Entry
            $entry | Should Not BeNullOrEmpty
            $entry.HostMap.GetType().FullName | Should Be 'System.Collections.Hashtable'
            $entry.HostMap.Keys.Count | Should Be 1
            $entry.HostMap.ContainsKey($hostname) | Should Be $true
            $entry.HostMap[$hostname].Keys.Count | Should Be 2

            $portEntry = $entry.HostMap[$hostname]['Gi1/0/1']
            $portEntry | Should Not BeNullOrEmpty
            $portEntry.GetType().FullName | Should Be 'System.Management.Automation.PSCustomObject'
            $portEntry.Name | Should Be 'GigabitEthernet1/0/1'
            $portEntry.Status | Should Be 'up'
            $entry.HostCount | Should BeGreaterThan 0
            $entry.TotalRows | Should BeGreaterThan 0

            $normalized = $module.Invoke({ param($payload) Normalize-InterfaceSiteCacheEntry -Entry $payload }, $entry)
            $normalized | Should Not BeNullOrEmpty
            $normalized.HostMap.ContainsKey($hostname) | Should Be $true
            $normalized.HostMap[$hostname].ContainsKey('Gi1/0/1') | Should Be $true
            $normalized.HostMap[$hostname]['Gi1/0/1'].GetType().FullName | Should Be 'StateTrace.Models.InterfaceCacheEntry'
        } finally {
            DeviceRepositoryModule\Clear-SiteInterfaceCache
            try { [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::ClearSnapshot() } catch { }
        }
    }

    It "clones typed host maps when snapshotting shared cache entries" {
        $siteKey = 'SITECLONE'
        Set-RepositoryVar -Name 'SiteInterfaceSignatureCache' -Value @{}
        try {
            $typedPortMap = New-Object 'System.Collections.Generic.Dictionary[string,StateTrace.Models.InterfaceCacheEntry]' ([System.StringComparer]::OrdinalIgnoreCase)
            $portEntry = [StateTrace.Models.InterfaceCacheEntry]::new()
            $portEntry.Name = 'GigabitEthernet1/0/1'
            $portEntry.Status = 'up'
            $portEntry.PortSort = '01-GI-00001-00000-00000-00000-00000'
            $typedPortMap['Gi1/0/1'] = $portEntry

            $typedHostMap = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.Dictionary[string,StateTrace.Models.InterfaceCacheEntry]]' ([System.StringComparer]::OrdinalIgnoreCase)
            $typedHostMap['SITECLONE-A01-AS-01'] = $typedPortMap

            $cacheEntry = [pscustomobject]@{
                HostMap   = $typedHostMap
                TotalRows = 1
                HostCount = 1
                CacheStatus = 'Hit'
            }

            $module = Get-Module DeviceRepositoryModule -ErrorAction Stop
            $module.Invoke({ param($site, $entry) Set-SharedSiteInterfaceCacheEntry -SiteKey $site -Entry $entry }, $siteKey, $cacheEntry) | Out-Null
            $restored = $module.Invoke({ param($site) Get-SharedSiteInterfaceCacheEntry -SiteKey $site }, $siteKey)

            $restored | Should Not BeNullOrEmpty
            $restored.HostMap | Should Not BeNullOrEmpty
            $restored.HostMap.ContainsKey('SITECLONE-A01-AS-01') | Should Be $true
            $restored.HostMap['SITECLONE-A01-AS-01'].ContainsKey('Gi1/0/1') | Should Be $true
            $restored.HostMap['SITECLONE-A01-AS-01']['Gi1/0/1'].Name | Should Be 'GigabitEthernet1/0/1'
        } finally {
            Set-RepositoryVar -Name 'SiteInterfaceSignatureCache' -Value @{}
            $module = Get-Module DeviceRepositoryModule -ErrorAction SilentlyContinue
            if ($module) {
                $module.Invoke({ param($site) Set-SharedSiteInterfaceCacheEntry -SiteKey $site -Entry $null }, $siteKey) | Out-Null
            }
        }
    }

    It "normalizes snapshot host maps into typed dictionaries" {
        $siteKey = 'SNAPSHOTNORMALIZE'
        $rawEntry = [pscustomobject]@{
            HostMap = @{
                'SNAPSHOTNORMALIZE-A01-AS-01' = @{
                    'Gi1/0/1' = [pscustomobject]@{
                        Port           = 'Gi1/0/1'
                        Name           = 'GigabitEthernet1/0/1'
                        Status         = 'up'
                        VLAN           = '1'
                        Duplex         = 'full'
                        Speed          = '1000'
                        Type           = 'access'
                        LearnedMACs    = '00:11:22:33:44:55'
                        AuthState      = 'authorized'
                        AuthMode       = 'dot1x'
                        AuthClientMAC  = '00:11:22:33:44:55'
                        AuthTemplate   = 'Default'
                        Config         = 'running'
                        PortColor      = 'green'
                        ConfigStatus   = 'OK'
                        ToolTip        = ''
                        CacheSignature = 'sig-normalize'
                        PortSort       = '01-GI-00001'
                    }
                }
            }
            CacheStatus = 'Hit'
            CachedAt    = Get-Date
        }

        $module = Get-Module DeviceRepositoryModule -ErrorAction Stop
        $normalized = $module.Invoke({ param($entry) Normalize-InterfaceSiteCacheEntry -Entry $entry }, $rawEntry)

        $normalized | Should Not BeNullOrEmpty
        $normalized.HostCount | Should Be 1
        $normalized.TotalRows | Should Be 1
        $normalized.HostMap | Should BeOfType ([System.Collections.Generic.Dictionary[string,System.Collections.Generic.Dictionary[string,StateTrace.Models.InterfaceCacheEntry]]])
        $normalized.HostMap.ContainsKey('SNAPSHOTNORMALIZE-A01-AS-01') | Should Be $true
        $normalized.HostMap['SNAPSHOTNORMALIZE-A01-AS-01'].ContainsKey('Gi1/0/1') | Should Be $true
        $normalized.HostMap['SNAPSHOTNORMALIZE-A01-AS-01']['Gi1/0/1'] | Should BeOfType 'StateTrace.Models.InterfaceCacheEntry'
    }

    It "computes PortSort when cached rows omit it" {
        InModuleScope DeviceRepositoryModule {
            if (-not (Get-Module -Name InterfaceModule -ErrorAction SilentlyContinue)) {
                $interfaceModulePath = Join-Path $PSScriptRoot '..\InterfaceModule.psm1'
                Import-Module -Name $interfaceModulePath -Force
            }

            $portName = 'GigabitEthernet1/0/42'
            $converted = ConvertTo-InterfaceCacheEntryObject -InputObject ([pscustomobject]@{
                    Name      = $portName
                    Status    = 'up'
                    VLAN      = '42'
                    Signature = 'sig-port42'
                })

            $converted | Should Not BeNullOrEmpty
            $converted.PortSort | Should Be (InterfaceModule\Get-PortSortKey -Port $portName)
        }
    }

    It "restores shared cache entries with populated host maps from snapshot data" {
        $siteKey = 'SNAPSHOTRESTORE'
        $hostKey = 'SNAPSHOTRESTORE-A01-AS-01'
        $module = Get-Module DeviceRepositoryModule -ErrorAction Stop
        $module.Invoke({ Set-Variable -Name 'SiteInterfaceSignatureCache' -Scope Script -Value @{} })

        try {
            $snapshotEntry = [pscustomobject]@{
                HostMap = @{
                    $hostKey = @{
                        'Gi1/0/1' = [pscustomobject]@{
                            Port           = 'Gi1/0/1'
                            Name           = 'GigabitEthernet1/0/1'
                            Status         = 'up'
                            VLAN           = '1'
                            PortSort       = '01-GI-00001'
                            CacheSignature = 'sig-restore-1'
                        }
                        'Gi1/0/2' = [pscustomobject]@{
                            Port           = 'Gi1/0/2'
                            Name           = 'GigabitEthernet1/0/2'
                            Status         = 'down'
                            VLAN           = '1'
                            PortSort       = '01-GI-00002'
                            CacheSignature = 'sig-restore-2'
                        }
                    }
                }
                CacheStatus = 'Hit'
                CachedAt    = Get-Date
            }

            $module.Invoke(
                {
                    param($site, $entry)
                    $normalized = Normalize-InterfaceSiteCacheEntry -Entry $entry
                    if (-not $script:SiteInterfaceSignatureCache) {
                        $script:SiteInterfaceSignatureCache = @{}
                    }
                    $script:SiteInterfaceSignatureCache[$site] = $normalized
                    Set-SharedSiteInterfaceCacheEntry -SiteKey $site -Entry $normalized
                },
                $siteKey,
                $snapshotEntry
            ) | Out-Null

            $restored = $module.Invoke({ param($site) Get-SharedSiteInterfaceCacheEntry -SiteKey $site }, $siteKey)

            $restored | Should Not BeNullOrEmpty
            $restored.HostCount | Should Be 1
            $restored.TotalRows | Should Be 2
            $restored.HostMap.ContainsKey($hostKey) | Should Be $true
            $restored.HostMap[$hostKey].ContainsKey('Gi1/0/1') | Should Be $true
            $restored.HostMap[$hostKey]['Gi1/0/1'] | Should BeOfType 'StateTrace.Models.InterfaceCacheEntry'
            $restored.HostMap[$hostKey]['Gi1/0/1'].Name | Should Be 'GigabitEthernet1/0/1'
        } finally {
            $module.Invoke({ param($site) Set-SharedSiteInterfaceCacheEntry -SiteKey $site -Entry $null }, $siteKey) | Out-Null
            $module.Invoke({ Set-Variable -Name 'SiteInterfaceSignatureCache' -Scope Script -Value @{} })
        }
    }

    It "imports shared cache snapshot from STATETRACE_SHARED_CACHE_SNAPSHOT when initializing the store" {
        $siteKey = 'ENVIMPORT'
        $hostKey = 'ENVIMPORT-A01-AS-01'
        $module = Get-Module DeviceRepositoryModule -ErrorAction Stop
        $snapshotPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("SharedCacheSnapshot-{0}.clixml" -f ([System.Guid]::NewGuid().ToString('N')))
        $existingEnv = $null
        try {
            $snapshotEntry = [pscustomobject]@{
                Site  = $siteKey
                Entry = [pscustomobject]@{
                    HostMap = @{
                        $hostKey = @{
                            'Gi1/0/1' = [pscustomobject]@{
                                Port     = 'Gi1/0/1'
                                Name     = 'GigabitEthernet1/0/1'
                                Status   = 'up'
                                VLAN     = '1'
                                PortSort = '01-GI-00001'
                                Signature = 'env-import'
                            }
                        }
                    }
                    CacheStatus = 'SharedOnly'
                    CachedAt    = Get-Date
                }
            }

            @($snapshotEntry) | Export-Clixml -Path $snapshotPath -Depth 10

            $module.Invoke({ Clear-SiteInterfaceCache }) | Out-Null
            $module.Invoke({ [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::ClearStore() }) | Out-Null
            try { $existingEnv = $env:STATETRACE_SHARED_CACHE_SNAPSHOT } catch { $existingEnv = $null }
            $module.Invoke({ param($path) $env:STATETRACE_SHARED_CACHE_SNAPSHOT = $path }, $snapshotPath)

            $module.Invoke({ Initialize-SharedSiteInterfaceCacheStore | Out-Null })
            $restoredEntry = $module.Invoke({ param($site) Get-SharedSiteInterfaceCacheEntry -SiteKey $site }, $siteKey)

            $restoredEntry | Should Not BeNullOrEmpty
            $restoredEntry.HostCount | Should Be 1
            $restoredEntry.TotalRows | Should Be 1
            $restoredEntry.HostMap.ContainsKey($hostKey) | Should Be $true
            $restoredEntry.HostMap[$hostKey]['Gi1/0/1'] | Should BeOfType 'StateTrace.Models.InterfaceCacheEntry'
        } finally {
            if ($existingEnv -ne $null) {
                $module.Invoke({ param($value) $env:STATETRACE_SHARED_CACHE_SNAPSHOT = $value }, $existingEnv)
            } else {
                $module.Invoke({ Remove-Item Env:STATETRACE_SHARED_CACHE_SNAPSHOT -ErrorAction SilentlyContinue })
            }
            Remove-Item -LiteralPath $snapshotPath -ErrorAction SilentlyContinue
            $module.Invoke({ Clear-SiteInterfaceCache }) | Out-Null
        }
    }

    Context "shared cache snapshot fallbacks" {
        BeforeAll {
            $toolsPath = Join-Path -Path (Split-Path -Parent $PSCommandPath) -ChildPath '..\..\Tools\Invoke-WarmRunTelemetry.ps1'
            $script:WarmTelemetryPreviousSkip = $null
            if (Test-Path -LiteralPath 'variable:global:WarmRunTelemetrySkipMain') {
                $script:WarmTelemetryPreviousSkip = Get-Variable -Name 'WarmRunTelemetrySkipMain' -Scope Global -ValueOnly
            }
            Set-Variable -Name 'WarmRunTelemetrySkipMain' -Scope Global -Value $true
            . (Resolve-Path $toolsPath)
            if ($null -ne $script:WarmTelemetryPreviousSkip) {
                Set-Variable -Name 'WarmRunTelemetrySkipMain' -Scope Global -Value $script:WarmTelemetryPreviousSkip
            } else {
                Remove-Variable -Name 'WarmRunTelemetrySkipMain' -Scope Global -ErrorAction SilentlyContinue
            }
            $module = Get-Module DeviceRepositoryModule -ErrorAction Stop
            $script:WarmTelemetrySharedCacheKey = $module.SessionState.PSVariable.Get('SharedSiteInterfaceCacheKey').Value
        }

        AfterAll {
            Remove-Variable -Name 'WarmTelemetrySharedCacheKey' -Scope Script -ErrorAction SilentlyContinue
            Remove-Variable -Name 'WarmTelemetryPreviousSkip' -Scope Script -ErrorAction SilentlyContinue
        }

        BeforeEach {
            $module = Get-Module DeviceRepositoryModule -ErrorAction Stop
            $module.Invoke(
                {
                    param($storeKey)
                    try { [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::ClearSnapshot() } catch { }
                    try { [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::ClearStore() } catch { }
                    $store = New-Object 'System.Collections.Concurrent.ConcurrentDictionary[string, object]' ([System.StringComparer]::OrdinalIgnoreCase)
                    Set-Variable -Name 'SharedSiteInterfaceCache' -Scope Script -Value $store
                    Set-Variable -Name 'SiteInterfaceSignatureCache' -Scope Script -Value @{}
                    try { [System.AppDomain]::CurrentDomain.SetData($storeKey, $store) } catch { }
                    try { [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::SetStore($store) } catch { }
                },
                $script:WarmTelemetrySharedCacheKey
            ) | Out-Null
        }

        It "returns signature cache entries when shared store empty" {
            $module = Get-Module DeviceRepositoryModule -ErrorAction Stop
            $siteKey = 'SNAPSHOT1'
            $entry = [pscustomobject]@{
                HostMap = @{
                    'host-a' = @{
                        'Gi1/0/1' = [pscustomobject]@{
                            Provider    = 'Cache'
                            CacheStatus = 'Hit'
                        }
                    }
                }
            }
            $normalized = $module.Invoke({ param($value) Normalize-InterfaceSiteCacheEntry -Entry $value }, $entry)
            $module.Invoke(
                {
                    param($site, $cacheEntry)
                    if (-not $script:SiteInterfaceSignatureCache) { $script:SiteInterfaceSignatureCache = @{} }
                    $script:SiteInterfaceSignatureCache[$site] = $cacheEntry
                },
                $siteKey,
                $normalized
            ) | Out-Null

            $snapshot = Get-SharedCacheEntriesSnapshot

            ($snapshot | Measure-Object).Count | Should Be 1
            $snapshot[0].Site | Should Be $siteKey
            $snapshot[0].Entry | Should Not BeNullOrEmpty
            $snapshot[0].Entry.HostCount | Should Be 1
        }

        It "converts typed host maps when exporting shared cache entries" {
            $module = Get-Module DeviceRepositoryModule -ErrorAction Stop
            $portMap = New-Object 'System.Collections.Generic.Dictionary[string,StateTrace.Models.InterfaceCacheEntry]' ([System.StringComparer]::OrdinalIgnoreCase)
            $cacheEntry = [StateTrace.Models.InterfaceCacheEntry]::new()
            $cacheEntry.Name = 'Gi1/0/9'
            $cacheEntry.PortSort = '01-AAA-00001-00001-00001-00001-00001'
            $portMap['Gi1/0/9'] = $cacheEntry

            $hostMap = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.Dictionary[string,StateTrace.Models.InterfaceCacheEntry]]' ([System.StringComparer]::OrdinalIgnoreCase)
            $hostMap['HOST-TYPED'] = $portMap

            $export = $module.Invoke(
                {
                    param($map)
                    Convert-InterfaceSiteCacheHostMapToExportMap -HostMap $map
                },
                $hostMap
            )

            ($export.Keys | Measure-Object).Count | Should Be 1
            ($export['HOST-TYPED'].Keys | Measure-Object).Count | Should Be 1
        }

        It "hydrates fallback sites when cache stores are empty" {
            $module = Get-Module DeviceRepositoryModule -ErrorAction Stop
            $siteKey = 'SNAPSHOT2'
            Mock -ModuleName DeviceRepositoryModule -CommandName Get-InterfaceSiteCache -MockWith {
                param([string]$Site, [switch]$Refresh)
                if ($Site -eq 'SNAPSHOT2') {
                    return [pscustomobject]@{
                        HostMap = @{
                            'host-b' = @{
                                'Gi1/0/2' = [pscustomobject]@{
                                    Provider = 'Hydrate'
                                }
                            }
                        }
                    }
                }
                return $null
            } -Verifiable

            $snapshot = Get-SharedCacheEntriesSnapshot -FallbackSites @($siteKey)

            ($snapshot | Measure-Object).Count | Should Be 1
            $snapshot[0].Site | Should Be $siteKey
            $snapshot[0].Entry.HostCount | Should Be 1
            Assert-MockCalled Get-InterfaceSiteCache -ModuleName DeviceRepositoryModule -Times 1 -ParameterFilter { $Site -eq $siteKey -and $Refresh }
        }

        It "returns shared cache snapshot entries when live store is empty but snapshot is preserved" {
            InModuleScope -ModuleName DeviceRepositoryModule {
                $originalStore = [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::GetStore()
                $originalSnapshot = [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::GetSnapshot()
                try {
                    $emptyStore = New-Object 'System.Collections.Concurrent.ConcurrentDictionary[string, object]' ([System.StringComparer]::OrdinalIgnoreCase)
                    [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::SetStore($emptyStore)

                    $hostMap = New-Object 'System.Collections.Concurrent.ConcurrentDictionary[string, object]' ([System.StringComparer]::OrdinalIgnoreCase)
                    $hostMap['SNAP-A01-AS-01'] = @{
                        'Gi1/0/1' = [pscustomobject]@{
                            Port = 'Gi1/0/1'
                            Name = 'Snapshot Port'
                        }
                    }

                    $snapshotStore = New-Object 'System.Collections.Concurrent.ConcurrentDictionary[string, object]' ([System.StringComparer]::OrdinalIgnoreCase)
                    $snapshotStore['SNAP'] = @{
                        HostMap     = $hostMap
                        CacheStatus = 'SharedOnly'
                    }
                    [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::SetSnapshot($snapshotStore)

                    $results = Get-SharedSiteInterfaceCacheSnapshotEntries

                    $results | Should Not BeNullOrEmpty
                    $results.Count | Should Be 1
                    $result = $results[0]
                    $siteValue = ''
                    if ($result.PSObject.Properties.Name -contains 'Site') {
                        $siteValue = $result.Site
                    } elseif ($result.PSObject.Properties.Name -contains 'SiteKey') {
                        $siteValue = $result.SiteKey
                    }
                    $siteValue | Should Be 'SNAP'

                    $hostMapValue = $null
                    if ($result.PSObject.Properties.Name -contains 'Entry') {
                        $hostMapValue = $result.Entry.HostMap
                    } elseif ($result.PSObject.Properties.Name -contains 'HostMap') {
                        $hostMapValue = $result.HostMap
                    }
                    $hostMapValue | Should Not BeNullOrEmpty
                    ((($hostMapValue.Keys | Measure-Object).Count) -gt 0) | Should Be $true
                } finally {
                    [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::SetStore($originalStore)
                    [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::SetSnapshot($originalSnapshot)
                }
            }
        }

        It "rehydrates snapshot entries missing host data" {
            InModuleScope -ModuleName DeviceRepositoryModule {
                Mock -ModuleName DeviceRepositoryModule -CommandName Get-InterfaceSiteCache -MockWith {
                    param([string]$Site, [switch]$Refresh)
                    if ($Site -eq 'SITE1' -and $Refresh) {
                        return [pscustomobject]@{
                            HostMap     = @{
                                'HOST1' = @{
                                    'Gi1/0/1' = [pscustomobject]@{
                                        Provider = 'Cache'
                                    }
                                }
                            }
                            HostCount   = 1
                            TotalRows   = 1
                            CacheStatus = 'Cache'
                        }
                    }
                    return $null
                } -Verifiable

                $entries = @(
                    [pscustomobject]@{
                        Site  = 'SITE1'
                        Entry = [pscustomobject]@{
                            HostCount = 0
                            HostMap   = $null
                        }
                    }
                )

                $resolved = Resolve-SharedSiteInterfaceCacheSnapshotEntries -Entries $entries -RehydrateMissingEntries

                $resolved | Should Not BeNullOrEmpty
                $resolved.Count | Should Be 1
                $resolved[0].Entry.HostMap | Should Not BeNullOrEmpty
                Assert-MockCalled Get-InterfaceSiteCache -ModuleName DeviceRepositoryModule -Times 1 -ParameterFilter { $Site -eq 'SITE1' -and $Refresh }
            }
        }

        It "hydrates fallback sites when snapshot entries are empty" {
            InModuleScope -ModuleName DeviceRepositoryModule {
                Mock -ModuleName DeviceRepositoryModule -CommandName Get-InterfaceSiteCache -MockWith {
                    param([string]$Site, [switch]$Refresh)
                    if ($Site -eq 'SNAP' -and $Refresh) {
                        return [pscustomobject]@{
                            HostMap   = @{
                                'snap-host' = @{
                                    'Et1' = [pscustomobject]@{
                                        Provider = 'Hydrate'
                                    }
                                }
                            }
                            HostCount = 1
                            TotalRows = 1
                        }
                    }
                    return $null
                } -Verifiable

                $resolved = Resolve-SharedSiteInterfaceCacheSnapshotEntries -Entries @() -FallbackSites @('SNAP-01') -RehydrateMissingEntries

                $resolved | Should Not BeNullOrEmpty
                $resolved.Count | Should Be 1
                $resolved[0].Site | Should Be 'SNAP'
                Assert-MockCalled Get-InterfaceSiteCache -ModuleName DeviceRepositoryModule -Times 1 -ParameterFilter { $Site -eq 'SNAP' -and $Refresh }
            }
        }

        It "returns site filters as strings for snapshot exporters" {
            InModuleScope -ModuleName DeviceRepositoryModule {
                $entries = @(
                    [pscustomobject]@{
                        Site  = 'SITE1'
                        Entry = [pscustomobject]@{
                            HostMap = @{}
                        }
                    },
                    [pscustomobject]@{
                        SiteKey = 'SITE2'
                        HostMap = @{}
                    }
                )

                $sites = @(Get-SharedCacheSiteFilterFromEntries -Entries $entries)

                $sites | Should Not BeNullOrEmpty
                $sites.Count | Should Be 2
                $sites[0] | Should BeOfType System.String
                ($sites -contains 'SITE1') | Should Be $true
                ($sites -contains 'SITE2') | Should Be $true
            }
        }

        It "skips shared cache entries missing payload during restore" {
            $module = Get-Module DeviceRepositoryModule -ErrorAction Stop
            $validSite = 'RESTORE1'
            $entry = [pscustomobject]@{
                HostMap = @{
                    'host-c' = @{
                        'Gi1/0/3' = [pscustomobject]@{
                            Provider = 'Cache'
                        }
                    }
                }
            }
            Mock -ModuleName DeviceRepositoryModule -CommandName Get-InterfaceSiteCache -MockWith { $null }
            Mock -CommandName Import-Module -ParameterFilter { $Name -like '*ParserRunspaceModule.psm1' } -MockWith { $null }

            $entries = @(
                [pscustomobject]@{ Site = $validSite; Entry = $entry },
                [pscustomobject]@{ Site = 'INVALID'; Entry = $null }
            )

            try {
                $restored = Restore-SharedCacheEntries -Entries $entries

                $restored | Should Be 1
                $restoredEntry = $module.Invoke({ param($site) Get-SharedSiteInterfaceCacheEntry -SiteKey $site }, $validSite)
                $restoredEntry | Should Not BeNullOrEmpty
                $restoredEntry.HostCount | Should Be 1
                $missingEntry = $module.Invoke({ param($site) Get-SharedSiteInterfaceCacheEntry -SiteKey $site }, 'INVALID')
                $missingEntry | Should Be $null
            } finally {
                $module.Invoke({ param($site) Set-SharedSiteInterfaceCacheEntry -SiteKey $site -Entry $null }, $validSite) | Out-Null
            }
        }
    }
}
