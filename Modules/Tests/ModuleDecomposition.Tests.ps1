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
        }

        It "imports diff module" {
            Get-Module -Name 'ParserPersistence.Diff' | Should Not BeNullOrEmpty
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
