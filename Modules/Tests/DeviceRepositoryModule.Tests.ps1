Set-StrictMode -Version Latest

function Set-RepositoryVar {
    param([string]$Name, $Value)
    $module = Get-Module DeviceRepositoryModule -ErrorAction Stop
    $module.SessionState.PSVariable.Set($Name, $Value)
}

function Remove-RepositoryVar {
    param([string]$Name)
    $module = Get-Module DeviceRepositoryModule -ErrorAction Stop
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
            $metrics.CacheStatus | Should Be 'Hit'
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
        } finally {
            Set-RepositoryVar -Name 'SiteInterfaceSignatureCache' -Value @{}
        }
    }
}
