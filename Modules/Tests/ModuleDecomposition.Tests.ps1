Set-StrictMode -Version Latest

Describe "Module decomposition shims" -Tag 'Decomposition' {
    Context "DeviceRepository.Cache exports" {
        BeforeAll {
            $modulePath = Join-Path (Split-Path $PSCommandPath) "..\DeviceRepository.Cache.psm1"
            Import-Module (Resolve-Path $modulePath) -Force
        }

        It "exports cache helpers" {
            $module = Get-Module -Name 'DeviceRepository.Cache'
            $module | Should Not BeNullOrEmpty
            ($module.ExportedFunctions.Count) -gt 0 | Should Be $true
        }

        It "exports shared cache snapshots when store entries are wrapped" {
            $siteKey = 'EXPORTTEST'
            $tempPath = Join-Path $env:TEMP ("SharedCacheExportTest-{0}.clixml" -f ([guid]::NewGuid().ToString('N')))

            try {
                DeviceRepository.Cache\Clear-SharedSiteInterfaceCache -Reason 'test'
                $store = DeviceRepository.Cache\Get-SharedSiteInterfaceCacheStore
                $store[$siteKey] = [pscustomobject]@{
                    HostMap = @{
                        'host1' = @{
                            'Gi1/0/1' = [pscustomobject]@{
                                Provider = 'Cache'
                            }
                        }
                    }
                }

                DeviceRepository.Cache\Export-SharedCacheSnapshot -OutputPath $tempPath -SiteFilter @($siteKey)
                (Test-Path -LiteralPath $tempPath) | Should Be $true

                $imported = Import-Clixml -LiteralPath $tempPath
                $entries = @($imported)
                $entries.Count | Should Be 1
                $entries[0].SiteKey | Should Be $siteKey
                $entries[0].HostMap | Should Not BeNullOrEmpty
            } finally {
                try { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue } catch { }
                try { DeviceRepository.Cache\Clear-SharedSiteInterfaceCache -Reason 'test' } catch { }
            }
        }

        It "handles wrapped store entries for snapshot enumeration and reads" {
            $siteKey = 'WRAPPED'

            try {
                DeviceRepository.Cache\Clear-SharedSiteInterfaceCache -Reason 'test'
                $store = DeviceRepository.Cache\Get-SharedSiteInterfaceCacheStore
                $store[$siteKey] = [pscustomobject]@{
                    HostMap = @{
                        'host1' = @{
                            'Gi1/0/1' = [pscustomobject]@{ Port = 'Gi1/0/1'; Provider = 'Cache' }
                            'Gi1/0/2' = [pscustomobject]@{ Port = 'Gi1/0/2'; Provider = 'Cache' }
                        }
                    }
                }

                $entries = @(DeviceRepository.Cache\Get-SharedSiteInterfaceCacheSnapshotEntries)
                $entries | Should Not BeNullOrEmpty
                $entries.Count | Should Be 1
                $entries[0].SiteKey | Should Be $siteKey
                $entries[0].HostMap | Should Not BeNullOrEmpty
                $entries[0].HostCount | Should Be 1
                $entries[0].TotalRows | Should Be 2

                $fetched = DeviceRepository.Cache\Get-SharedSiteInterfaceCacheEntry -SiteKey $siteKey
                $fetched | Should Not BeNullOrEmpty
                ($fetched.Keys -contains 'host1') | Should Be $true
                ($fetched.Keys -contains 'HostMap') | Should Be $false

                $rows = @(DeviceRepository.Cache\Get-SharedSiteInterfaceCache -Site $siteKey)
                $rows | Should Not BeNullOrEmpty
                $rows.Count | Should Be 2
                ($rows[0] -is [System.Collections.DictionaryEntry]) | Should Be $false
            } finally {
                try { DeviceRepository.Cache\Clear-SharedSiteInterfaceCache -Reason 'test' } catch { }
            }
        }

        It "treats shared cache site keys as case-insensitive" {
            $siteKeyLower = 'casetest'
            $siteKeyUpper = 'CASETEST'
            $module = Get-Module -Name 'DeviceRepository.Cache' -ErrorAction Stop

            try {
                DeviceRepository.Cache\Clear-SharedSiteInterfaceCache -Reason 'test'
                try { $module.SessionState.PSVariable.Set('SharedSiteInterfaceCache', $null) } catch { }

                $store = DeviceRepository.Cache\Get-SharedSiteInterfaceCacheStore
                $store | Should Not Be $null

                DeviceRepository.Cache\Set-SharedSiteInterfaceCacheEntry -SiteKey $siteKeyLower -Entry @{
                    'host1' = @{
                        'Gi1/0/1' = [pscustomobject]@{ Port = 'Gi1/0/1' }
                    }
                }

                $fetched = DeviceRepository.Cache\Get-SharedSiteInterfaceCacheEntry -SiteKey $siteKeyUpper
                $fetched | Should Not BeNullOrEmpty
                ($fetched.Keys -contains 'host1') | Should Be $true
            } finally {
                try { DeviceRepository.Cache\Clear-SharedSiteInterfaceCache -Reason 'test' } catch { }
                try { $module.SessionState.PSVariable.Set('SharedSiteInterfaceCache', $null) } catch { }
            }
        }

        It "promotes the shared cache store to the holder and AppDomain" {
            $module = Get-Module -Name 'DeviceRepository.Cache' -ErrorAction Stop
            $cacheKey = $module.SessionState.PSVariable.Get('SharedSiteInterfaceCacheKey').Value

            try {
                DeviceRepository.Cache\Clear-SharedSiteInterfaceCache -Reason 'test'
                try { [System.AppDomain]::CurrentDomain.SetData($cacheKey, $null) } catch { }
                try { [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::ClearStore() } catch { }
                try { $module.SessionState.PSVariable.Set('SharedSiteInterfaceCache', $null) } catch { }

                $expected = New-Object 'System.Collections.Concurrent.ConcurrentDictionary[string, object]' ([System.StringComparer]::OrdinalIgnoreCase)
                [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::SetStore($expected)

                $store = DeviceRepository.Cache\Get-SharedSiteInterfaceCacheStore
                [object]::ReferenceEquals($store, $expected) | Should Be $true

                $domainStore = [System.AppDomain]::CurrentDomain.GetData($cacheKey)
                [object]::ReferenceEquals($domainStore, $expected) | Should Be $true

                $holderStore = [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::GetStore()
                [object]::ReferenceEquals($holderStore, $expected) | Should Be $true
            } finally {
                try { DeviceRepository.Cache\Clear-SharedSiteInterfaceCache -Reason 'test' } catch { }
                try { [System.AppDomain]::CurrentDomain.SetData($cacheKey, $null) } catch { }
                try { [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::ClearStore() } catch { }
                try { $module.SessionState.PSVariable.Set('SharedSiteInterfaceCache', $null) } catch { }
            }
        }
    }

    Context "DeviceRepository.Access exports" {
        BeforeAll {
            $modulePath = Join-Path (Split-Path $PSCommandPath) "..\DeviceRepository.Access.psm1"
            Import-Module (Resolve-Path $modulePath) -Force
        }

        It "exports access helpers" {
            $module = Get-Module -Name 'DeviceRepository.Access'
            $module | Should Not BeNullOrEmpty
            ($module.ExportedFunctions.Count) -gt 0 | Should Be $true
            ($module.ExportedFunctions.Keys -contains 'Get-DbPathForSite') | Should Be $true
            ($module.ExportedFunctions.Keys -contains 'Invoke-ParallelDbQuery') | Should Be $true
        }
    }

    Context "ParserPersistence decomposition exports" {
        BeforeAll {
            $corePath = Join-Path (Split-Path $PSCommandPath) "..\ParserPersistence.Core.psm1"
            $diffPath = Join-Path (Split-Path $PSCommandPath) "..\ParserPersistence.Diff.psm1"
            $warmPath = Join-Path (Split-Path $PSCommandPath) "..\WarmRun.Telemetry.psm1"
            Import-Module (Resolve-Path $corePath) -Force
            Import-Module (Resolve-Path $diffPath) -Force
            Import-Module (Resolve-Path $warmPath) -Force
        }

        It "exports core persistence helpers" {
            $module = Get-Module -Name 'ParserPersistence.Core'
            $module | Should Not BeNullOrEmpty
            ($module.ExportedFunctions.Count) -gt 0 | Should Be $true
            ($module.ExportedFunctions.Keys -contains 'Set-InterfaceBulkChunkSize') | Should Be $true
            ($module.ExportedFunctions.Keys -contains 'Update-DeviceSummaryInDb') | Should Be $true
            ($module.ExportedFunctions.Keys -contains 'Update-InterfacesInDb') | Should Be $true
            ($module.ExportedFunctions.Keys -contains 'Update-SpanInfoInDb') | Should Be $true
            ($module.ExportedFunctions.Keys -contains 'Write-InterfacePersistenceFailure') | Should Be $true
            ($module.ExportedFunctions.Keys -contains 'Get-LastInterfaceSyncTelemetry') | Should Be $true
        }

        It "imports diff module" {
            $module = Get-Module -Name 'ParserPersistence.Diff'
            $module | Should Not BeNullOrEmpty
            ($module.ExportedFunctions.Count) -gt 0 | Should Be $true
            ($module.ExportedFunctions.Keys -contains 'Get-SiteExistingRowCacheSnapshot') | Should Be $true
            ($module.ExportedFunctions.Keys -contains 'Set-SiteExistingRowCacheSnapshot') | Should Be $true
            ($module.ExportedFunctions.Keys -contains 'Clear-SiteExistingRowCache') | Should Be $true
            ($module.ExportedFunctions.Keys -contains 'Import-SiteExistingRowCacheSnapshotFromEnv') | Should Be $true
        }

        It "imports warm-run telemetry module" {
            Get-Module -Name 'WarmRun.Telemetry' | Should Not BeNullOrEmpty
        }

        It "can set/get/clear shared cache entries" {
            # Use module-qualified calls to avoid global state contamination
            $store = DeviceRepository.Cache\Initialize-SharedSiteInterfaceCacheStore
            $siteKey = 'TEST'
            $rows = @(
                [pscustomobject]@{ Hostname = 'h1'; Port = '1'; HostRows = 2 },
                [pscustomobject]@{ Hostname = 'h2'; Port = '2'; HostRows = 3 }
            )
            DeviceRepository.Cache\Set-SharedSiteInterfaceCacheEntry -SiteKey $siteKey -Entry @{ h1 = @($rows[0]); h2 = @($rows[1]) }
            $fetched = DeviceRepository.Cache\Get-SharedSiteInterfaceCacheEntry -SiteKey $siteKey
            $fetched.Keys.Count | Should Be 2
            $stats = DeviceRepository.Cache\Get-SharedSiteInterfaceCacheEntryStatistics -Entry $fetched
            $stats.HostCount | Should Be 2
            $stats.TotalRows | Should Be 2

            $snapshot = New-Object 'System.Collections.Concurrent.ConcurrentDictionary[string, object]' ([System.StringComparer]::OrdinalIgnoreCase)
            $snapshotEntry = New-Object 'StateTrace.Repository.SharedSiteInterfaceCacheEntry'
            $snapshotEntry.SiteKey = $siteKey
            $snapshotEntry.HostMap = New-Object 'System.Collections.Generic.Dictionary[string, object]' ([System.StringComparer]::OrdinalIgnoreCase)
            $snapshotEntry.HostMap['h1'] = @($rows[0])
            $snapshot[$siteKey] = $snapshotEntry
            [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::SetSnapshot($snapshot)

            DeviceRepository.Cache\Clear-SharedSiteInterfaceCache -Reason 'test'
            $cleared = DeviceRepository.Cache\Get-SharedSiteInterfaceCacheEntry -SiteKey $siteKey
            $cleared | Should Be $null
            [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::GetSnapshot() | Should Be $null
        }
    }
}
