Set-StrictMode -Version Latest

Describe 'Inspect-SharedCacheSnapshot' {
    It 'handles SiteKey-only snapshot entries' {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path -Path (Split-Path -Parent $PSCommandPath) -ChildPath '..\..'))
        $scriptPath = Join-Path -Path $repoRoot -ChildPath 'Tools\Inspect-SharedCacheSnapshot.ps1'
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

        $result = & $scriptPath -SnapshotPath $snapshotPath -Raw

        $result | Should Not BeNullOrEmpty
        $result[0].Site | Should Be 'SNAP'
        $result[0].Hosts | Should Be 1
        $result[0].TotalRows | Should Be 2
    }
}

