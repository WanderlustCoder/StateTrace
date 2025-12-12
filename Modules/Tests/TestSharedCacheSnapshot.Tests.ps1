Set-StrictMode -Version Latest

Describe 'Test-SharedCacheSnapshot' {
    It 'computes TotalRows from snapshot HostMap values' {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path -Path (Split-Path -Parent $PSCommandPath) -ChildPath '..\..'))
        $scriptPath = Join-Path -Path $repoRoot -ChildPath 'Tools\Test-SharedCacheSnapshot.ps1'
        $snapshotPath = Join-Path -Path $TestDrive -ChildPath ("SharedCacheSnapshot-{0}.clixml" -f ([System.Guid]::NewGuid().ToString('N')))

        $entries = @(
            [pscustomobject]@{
                SiteKey = 'SNAP'
                HostMap = @{
                    'SNAP-A01-AS-01' = @{
                        'Gi1/0/1' = [pscustomobject]@{ Name = 'GigabitEthernet1/0/1' }
                        'Gi1/0/2' = [pscustomobject]@{ Name = 'GigabitEthernet1/0/2' }
                    }
                }
            }
        )
        $entries | Export-Clixml -Path $snapshotPath -Depth 5

        $result = & $scriptPath -Path $snapshotPath -MinimumSiteCount 1 -MinimumHostCount 1 -MinimumTotalRowCount 2 -RequiredSites @('SNAP') -PassThru

        $result | Should Not BeNullOrEmpty
        $result.SiteCount | Should Be 1
        $result.HostCount | Should Be 1
        $result.TotalRows | Should Be 2
        $result.MissingSites | Should BeNullOrEmpty
    }

    It 'accepts comma-delimited RequiredSites arguments' {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path -Path (Split-Path -Parent $PSCommandPath) -ChildPath '..\..'))
        $scriptPath = Join-Path -Path $repoRoot -ChildPath 'Tools\Test-SharedCacheSnapshot.ps1'
        $summaryPath = Join-Path -Path $TestDrive -ChildPath ("SharedCacheSnapshot-{0}-summary.json" -f ([System.Guid]::NewGuid().ToString('N')))

        $summaryEntries = @(
            [pscustomobject]@{ Site = 'BOYO'; Hosts = 1; TotalRows = 2; CachedAt = (Get-Date) },
            [pscustomobject]@{ Site = 'WLLS'; Hosts = 1; TotalRows = 2; CachedAt = (Get-Date) }
        )
        $summaryEntries | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $summaryPath -Encoding utf8

        $result = & $scriptPath -Path $summaryPath -MinimumSiteCount 2 -MinimumHostCount 2 -MinimumTotalRowCount 4 -RequiredSites 'BOYO,WLLS' -PassThru

        $result | Should Not BeNullOrEmpty
        $result.SiteCount | Should Be 2
        $result.HostCount | Should Be 2
        $result.TotalRows | Should Be 4
        $result.MissingSites | Should BeNullOrEmpty
    }
}
