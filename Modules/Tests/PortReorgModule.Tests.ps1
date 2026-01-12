Set-StrictMode -Version Latest

Describe "PortReorgModule script generation" {
    BeforeAll {
        $modulePath = Join-Path (Split-Path $PSCommandPath) "..\\PortReorgModule.psm1"
        Import-Module (Resolve-Path $modulePath) -Force
    }

    AfterAll {
        Remove-Module PortReorgModule -Force -ErrorAction SilentlyContinue
    }

    It "generates Cisco change + rollback scripts for a move + rename" {
        $baseline = @(
            [pscustomobject]@{
                Port = 'Gi1/0/1'
                Name = 'OldLabel'
                Status = 'connected'
                PortSort = '01-GI-00001'
                Config = @(
                    'interface Gi1/0/1',
                    ' description OldLabel',
                    ' switchport mode access',
                    ' switchport access vlan 20',
                    ' shutdown',
                    '!'
                ) -join "`n"
            },
            [pscustomobject]@{
                Port = 'Gi1/0/2'
                Name = 'UserPort'
                Status = 'connected'
                PortSort = '01-GI-00002'
                Config = @(
                    'interface Gi1/0/2',
                    ' description UserPort',
                    ' switchport access vlan 10',
                    ' no shutdown',
                    '!'
                ) -join "`n"
            }
        )

        $plan = @(
            [pscustomobject]@{ SourcePort = 'Gi1/0/1'; TargetPort = 'Gi1/0/2'; NewLabel = 'PRN-01' }
        )

        $result = PortReorgModule\New-PortReorgScripts -Hostname 'TEST-SW1' -PlanRows $plan -BaselineInterfaces $baseline -Vendor 'Cisco' -ChunkSize 0

        $result | Should Not BeNullOrEmpty
        $result.Vendor | Should Be 'Cisco'
        $result.ChangeScript.Count | Should BeGreaterThan 0
        $result.RollbackScript.Count | Should BeGreaterThan 0

        ($result.ChangeScript -join "`n") | Should Match 'default interface Gi1/0/2'
        ($result.ChangeScript -join "`n") | Should Match 'interface Gi1/0/2'
        ($result.ChangeScript -join "`n") | Should Match '\s+switchport access vlan 20'
        ($result.ChangeScript -join "`n") | Should Match '\s+description PRN-01'
        # Source port was shutdown, so the script should not re-enable it at the end.
        ($result.ChangeScript -join "`n") | Should Not Match '\s+no shutdown'

        # Rollback restores the original target port name and VLAN and should re-enable it.
        ($result.RollbackScript -join "`n") | Should Match '\s+description UserPort'
        ($result.RollbackScript -join "`n") | Should Match '\s+switchport access vlan 10'
        ($result.RollbackScript -join "`n") | Should Match '\s+no shutdown'
    }

    It "clears a Cisco port when the label/profile is unassigned" {
        $baseline = @(
            [pscustomobject]@{
                Port = 'Gi1/0/2'
                Name = 'UserPort'
                Status = 'connected'
                PortSort = '01-GI-00002'
                Config = @(
                    'interface Gi1/0/2',
                    ' description UserPort',
                    ' switchport access vlan 10',
                    ' switchport voice vlan 100',
                    ' authentication port-control auto',
                    ' no shutdown',
                    '!'
                ) -join "`n"
            }
        )

        $plan = @(
            [pscustomobject]@{ SourcePort = ''; TargetPort = 'Gi1/0/2'; NewLabel = '' }
        )

        $result = PortReorgModule\New-PortReorgScripts -Hostname 'TEST-SW1' -PlanRows $plan -BaselineInterfaces $baseline -Vendor 'Cisco' -ChunkSize 0

        $changeText = ($result.ChangeScript -join "`n")
        $changeText | Should Match '! Clear Gi1/0/2'
        $changeText | Should Match 'default interface Gi1/0/2'
        $changeText | Should Match 'interface Gi1/0/2'
        $changeText | Should Match '\s+shutdown'
        $changeText | Should Match '\s+no description'
        $changeText | Should Not Match '\s+no shutdown'
        $changeText | Should Not Match '\s+switchport access vlan'
        $changeText | Should Not Match '\s+switchport voice vlan'

        $rollbackText = ($result.RollbackScript -join "`n")
        $rollbackText | Should Match '\s+description UserPort'
        $rollbackText | Should Match '\s+switchport access vlan 10'
        $rollbackText | Should Match '\s+switchport voice vlan 100'
        $rollbackText | Should Match '\s+no shutdown'
    }

    It "generates Brocade scripts using disable/enable and port-name quoting" {
        $baseline = @(
            [pscustomobject]@{
                Port = 'Et1/1/1'
                Name = 'User1'
                Status = 'Up'
                PortSort = '01-ET-00001'
                Config = @(
                    'port-name User1',
                    'authentication auth-default-vlan 20',
                    'mac-authentication enable'
                ) -join "`n"
            },
            [pscustomobject]@{
                Port = 'Et1/1/2'
                Name = 'Uplink2'
                Status = 'Disable'
                PortSort = '01-ET-00002'
                Config = @(
                    'port-name Uplink2',
                    'authentication auth-default-vlan 30',
                    'spanning-tree edge-port'
                ) -join "`n"
            }
        )

        $plan = @(
            [pscustomobject]@{ SourcePort = 'Et1/1/1'; TargetPort = 'Et1/1/2'; NewLabel = 'USER-01' }
        )

        $result = PortReorgModule\New-PortReorgScripts -Hostname 'TEST-AS1' -PlanRows $plan -BaselineInterfaces $baseline -Vendor 'Brocade' -ChunkSize 0

        $result | Should Not BeNullOrEmpty
        $result.Vendor | Should Be 'Brocade'

        $changeText = ($result.ChangeScript -join "`n")
        $changeText | Should Match 'interface ethernet 1/1/2'
        $changeText | Should Match '\s+disable'
        $changeText | Should Match '\s+no port-name'
        $changeText | Should Match '\s+no authentication auth-default-vlan 30'
        $changeText | Should Match '\s+no spanning-tree edge-port'
        $changeText | Should Match '\s+authentication auth-default-vlan 20'
        $changeText | Should Match '\s+mac-authentication enable'
        $changeText | Should Match '\s+port-name \"?USER-01\"?'
        $changeText | Should Match '\s+enable'

        $rollbackText = ($result.RollbackScript -join "`n")
        $rollbackText | Should Match 'interface ethernet 1/1/2'
        $rollbackText | Should Match '\s+port-name \"?Uplink2\"?'
        $rollbackText | Should Match '\s+no authentication auth-default-vlan 20'
        $rollbackText | Should Match '\s+no mac-authentication enable'
        $rollbackText | Should Match '\s+authentication auth-default-vlan 30'
        $rollbackText | Should Match '\s+spanning-tree edge-port'
        # Target baseline status was Disable, so rollback should not enable it.
        $rollbackText | Should Not Match '\s+enable\s*$'
    }
}
