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
}

