Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Pester tests for IPAMModule.
#>

$modulePath = Join-Path $PSScriptRoot '..\IPAMModule.psm1'
Import-Module $modulePath -Force

Describe 'IPAMModule' {

    BeforeEach {
        $script:testDb = IPAMModule\New-IPAMDatabase
    }

    #region Subnet Calculations

    Context 'Get-SubnetDetails' {

        It 'Calculates /24 subnet correctly' {
            $result = IPAMModule\Get-SubnetDetails -NetworkAddress '192.168.1.0' -PrefixLength 24

            $result.NetworkAddress | Should Be '192.168.1.0'
            $result.SubnetMask | Should Be '255.255.255.0'
            $result.BroadcastAddress | Should Be '192.168.1.255'
            $result.FirstUsable | Should Be '192.168.1.1'
            $result.LastUsable | Should Be '192.168.1.254'
            $result.TotalHosts | Should Be 254
        }

        It 'Calculates /16 subnet correctly' {
            $result = IPAMModule\Get-SubnetDetails -NetworkAddress '10.1.0.0' -PrefixLength 16

            $result.NetworkAddress | Should Be '10.1.0.0'
            $result.SubnetMask | Should Be '255.255.0.0'
            $result.BroadcastAddress | Should Be '10.1.255.255'
            $result.TotalHosts | Should Be 65534
        }

        It 'Calculates /30 subnet correctly' {
            $result = IPAMModule\Get-SubnetDetails -NetworkAddress '10.0.0.0' -PrefixLength 30

            $result.TotalHosts | Should Be 2
            $result.FirstUsable | Should Be '10.0.0.1'
            $result.LastUsable | Should Be '10.0.0.2'
        }

        It 'Returns CIDR notation' {
            $result = IPAMModule\Get-SubnetDetails -NetworkAddress '172.16.0.0' -PrefixLength 12

            $result.CIDR | Should Be '172.16.0.0/12'
        }
    }

    Context 'Test-IPInSubnet' {

        It 'Returns true for IP in subnet' {
            $result = IPAMModule\Test-IPInSubnet -IPAddress '192.168.1.50' -NetworkAddress '192.168.1.0' -PrefixLength 24
            $result | Should Be $true
        }

        It 'Returns false for IP outside subnet' {
            $result = IPAMModule\Test-IPInSubnet -IPAddress '192.168.2.50' -NetworkAddress '192.168.1.0' -PrefixLength 24
            $result | Should Be $false
        }

        It 'Handles larger subnets correctly' {
            $result = IPAMModule\Test-IPInSubnet -IPAddress '10.5.100.200' -NetworkAddress '10.0.0.0' -PrefixLength 8
            $result | Should Be $true
        }
    }

    Context 'Split-Subnet' {

        It 'Splits /24 into four /26 subnets' {
            $results = @(IPAMModule\Split-Subnet -NetworkAddress '192.168.1.0' -PrefixLength 24 -NewPrefixLength 26)

            $results.Count | Should Be 4
            $results[0].NetworkAddress | Should Be '192.168.1.0'
            $results[1].NetworkAddress | Should Be '192.168.1.64'
            $results[2].NetworkAddress | Should Be '192.168.1.128'
            $results[3].NetworkAddress | Should Be '192.168.1.192'
        }

        It 'Splits /24 into two /25 subnets' {
            $results = @(IPAMModule\Split-Subnet -NetworkAddress '10.1.0.0' -PrefixLength 24 -NewPrefixLength 25)

            $results.Count | Should Be 2
            $results[0].NetworkAddress | Should Be '10.1.0.0'
            $results[1].NetworkAddress | Should Be '10.1.0.128'
        }

        It 'Returns empty for invalid split' {
            $results = @(IPAMModule\Split-Subnet -NetworkAddress '192.168.1.0' -PrefixLength 24 -NewPrefixLength 20)
            $results.Count | Should Be 0
        }
    }

    Context 'Test-SubnetOverlap' {

        It 'Detects overlapping subnets' {
            $result = IPAMModule\Test-SubnetOverlap `
                -Subnet1Network '192.168.1.0' -Subnet1Prefix 24 `
                -Subnet2Network '192.168.1.128' -Subnet2Prefix 25

            $result | Should Be $true
        }

        It 'Detects non-overlapping subnets' {
            $result = IPAMModule\Test-SubnetOverlap `
                -Subnet1Network '192.168.1.0' -Subnet1Prefix 24 `
                -Subnet2Network '192.168.2.0' -Subnet2Prefix 24

            $result | Should Be $false
        }

        It 'Detects supernet containing subnet' {
            $result = IPAMModule\Test-SubnetOverlap `
                -Subnet1Network '10.0.0.0' -Subnet1Prefix 8 `
                -Subnet2Network '10.1.0.0' -Subnet2Prefix 24

            $result | Should Be $true
        }
    }

    #endregion

    #region VLAN Operations

    Context 'New-VLAN' {

        It 'Creates VLAN with required parameters' {
            $vlan = IPAMModule\New-VLAN -VlanNumber 10 -VlanName 'Users'

            $vlan | Should Not BeNullOrEmpty
            $vlan.VlanNumber | Should Be 10
            $vlan.VlanName | Should Be 'Users'
            $vlan.Status | Should Be 'Active'
            $vlan.Purpose | Should Be 'Data'
        }

        It 'Creates VLAN with optional parameters' {
            $vlan = IPAMModule\New-VLAN -VlanNumber 20 -VlanName 'Voice' `
                -Purpose 'Voice' -Site 'CAMPUS' -Description 'Voice VLAN'

            $vlan.Purpose | Should Be 'Voice'
            $vlan.Site | Should Be 'CAMPUS'
            $vlan.Description | Should Be 'Voice VLAN'
        }

        It 'Generates VlanID' {
            $vlan = IPAMModule\New-VLAN -VlanNumber 100 -VlanName 'Management'

            $vlan.VlanID | Should Not BeNullOrEmpty
            $vlan.VlanID.Length | Should BeGreaterThan 0
        }
    }

    Context 'Add-VLAN and Get-VLANRecord' {

        It 'Adds VLAN to database' {
            $vlan = IPAMModule\New-VLAN -VlanNumber 10 -VlanName 'Users' -Site 'SITE-A'
            IPAMModule\Add-VLAN -VLAN $vlan -Database $script:testDb

            $results = @(IPAMModule\Get-VLANRecord -Database $script:testDb)
            $results.Count | Should Be 1
        }

        It 'Filters VLANs by number' {
            $vlan1 = IPAMModule\New-VLAN -VlanNumber 10 -VlanName 'Users' -Site 'SITE-A'
            $vlan2 = IPAMModule\New-VLAN -VlanNumber 20 -VlanName 'Voice' -Site 'SITE-A'
            IPAMModule\Add-VLAN -VLAN $vlan1 -Database $script:testDb
            IPAMModule\Add-VLAN -VLAN $vlan2 -Database $script:testDb

            $results = @(IPAMModule\Get-VLANRecord -VlanNumber 10 -Database $script:testDb)
            $results.Count | Should Be 1
            $results[0].VlanName | Should Be 'Users'
        }

        It 'Filters VLANs by site' {
            $vlan1 = IPAMModule\New-VLAN -VlanNumber 10 -VlanName 'Users' -Site 'SITE-A'
            $vlan2 = IPAMModule\New-VLAN -VlanNumber 10 -VlanName 'Users' -Site 'SITE-B'
            IPAMModule\Add-VLAN -VLAN $vlan1 -Database $script:testDb
            IPAMModule\Add-VLAN -VLAN $vlan2 -Database $script:testDb

            $results = @(IPAMModule\Get-VLANRecord -Site 'SITE-A' -Database $script:testDb)
            $results.Count | Should Be 1
        }

        It 'Rejects duplicate VLAN at same site' {
            $vlan1 = IPAMModule\New-VLAN -VlanNumber 10 -VlanName 'Users' -Site 'SITE-A'
            $vlan2 = IPAMModule\New-VLAN -VlanNumber 10 -VlanName 'Data' -Site 'SITE-A'
            IPAMModule\Add-VLAN -VLAN $vlan1 -Database $script:testDb
            $result = IPAMModule\Add-VLAN -VLAN $vlan2 -Database $script:testDb -WarningAction SilentlyContinue

            $result | Should BeNullOrEmpty
            $script:testDb.VLANs.Count | Should Be 1
        }
    }

    Context 'Update-VLAN' {

        It 'Updates VLAN properties' {
            $vlan = IPAMModule\New-VLAN -VlanNumber 10 -VlanName 'Users'
            IPAMModule\Add-VLAN -VLAN $vlan -Database $script:testDb

            $result = IPAMModule\Update-VLAN -VlanID $vlan.VlanID `
                -Properties @{ VlanName = 'DataUsers'; Description = 'Updated' } `
                -Database $script:testDb

            $result.VlanName | Should Be 'DataUsers'
            $result.Description | Should Be 'Updated'
        }
    }

    Context 'Remove-VLAN' {

        It 'Removes VLAN from database' {
            $vlan = IPAMModule\New-VLAN -VlanNumber 10 -VlanName 'Users'
            IPAMModule\Add-VLAN -VLAN $vlan -Database $script:testDb

            $result = IPAMModule\Remove-VLAN -VlanID $vlan.VlanID -Database $script:testDb

            $result | Should Be $true
            $script:testDb.VLANs.Count | Should Be 0
        }
    }

    #endregion

    #region Subnet Operations

    Context 'New-Subnet' {

        It 'Creates subnet with calculated details' {
            $subnet = IPAMModule\New-Subnet -NetworkAddress '192.168.1.0' -PrefixLength 24

            $subnet | Should Not BeNullOrEmpty
            $subnet.NetworkAddress | Should Be '192.168.1.0'
            $subnet.PrefixLength | Should Be 24
            $subnet.SubnetMask | Should Be '255.255.255.0'
            $subnet.TotalHosts | Should Be 254
        }

        It 'Creates subnet with optional parameters' {
            $subnet = IPAMModule\New-Subnet -NetworkAddress '10.1.10.0' -PrefixLength 24 `
                -VlanNumber 10 -Site 'CAMPUS' -Purpose 'Data' -GatewayAddress '10.1.10.1'

            $subnet.VlanNumber | Should Be 10
            $subnet.Site | Should Be 'CAMPUS'
            $subnet.Purpose | Should Be 'Data'
            $subnet.GatewayAddress | Should Be '10.1.10.1'
        }
    }

    Context 'Add-Subnet and Get-SubnetRecord' {

        It 'Adds subnet to database' {
            $subnet = IPAMModule\New-Subnet -NetworkAddress '192.168.1.0' -PrefixLength 24
            IPAMModule\Add-Subnet -Subnet $subnet -Database $script:testDb

            $results = @(IPAMModule\Get-SubnetRecord -Database $script:testDb)
            $results.Count | Should Be 1
        }

        It 'Filters subnets by VLAN number' {
            $subnet1 = IPAMModule\New-Subnet -NetworkAddress '10.1.10.0' -PrefixLength 24 -VlanNumber 10
            $subnet2 = IPAMModule\New-Subnet -NetworkAddress '10.1.20.0' -PrefixLength 24 -VlanNumber 20
            IPAMModule\Add-Subnet -Subnet $subnet1 -Database $script:testDb
            IPAMModule\Add-Subnet -Subnet $subnet2 -Database $script:testDb

            $results = @(IPAMModule\Get-SubnetRecord -VlanNumber 10 -Database $script:testDb)
            $results.Count | Should Be 1
            $results[0].NetworkAddress | Should Be '10.1.10.0'
        }

        It 'Warns about overlapping subnets' {
            $subnet1 = IPAMModule\New-Subnet -NetworkAddress '10.0.0.0' -PrefixLength 16
            $subnet2 = IPAMModule\New-Subnet -NetworkAddress '10.0.1.0' -PrefixLength 24
            IPAMModule\Add-Subnet -Subnet $subnet1 -Database $script:testDb

            # Should warn but still add
            IPAMModule\Add-Subnet -Subnet $subnet2 -Database $script:testDb -WarningAction SilentlyContinue

            $script:testDb.Subnets.Count | Should Be 2
        }
    }

    #endregion

    #region IP Address Operations

    Context 'New-IPAddressRecord' {

        It 'Creates IP address record' {
            $ip = IPAMModule\New-IPAddressRecord -IPAddress '192.168.1.10' `
                -DeviceName 'SW-01' -InterfaceName 'Vlan10'

            $ip | Should Not BeNullOrEmpty
            $ip.IPAddress | Should Be '192.168.1.10'
            $ip.DeviceName | Should Be 'SW-01'
            $ip.AddressType | Should Be 'Static'
        }
    }

    Context 'Add-IPAddressRecord and Get-IPAddressRecord' {

        It 'Adds IP address to database' {
            $ip = IPAMModule\New-IPAddressRecord -IPAddress '192.168.1.10' -DeviceName 'SW-01'
            IPAMModule\Add-IPAddressRecord -IPRecord $ip -Database $script:testDb

            $results = @(IPAMModule\Get-IPAddressRecord -Database $script:testDb)
            $results.Count | Should Be 1
        }

        It 'Filters by device name' {
            $ip1 = IPAMModule\New-IPAddressRecord -IPAddress '192.168.1.10' -DeviceName 'SW-01'
            $ip2 = IPAMModule\New-IPAddressRecord -IPAddress '192.168.1.11' -DeviceName 'SW-02'
            IPAMModule\Add-IPAddressRecord -IPRecord $ip1 -Database $script:testDb
            IPAMModule\Add-IPAddressRecord -IPRecord $ip2 -Database $script:testDb

            $results = @(IPAMModule\Get-IPAddressRecord -DeviceName 'SW-01' -Database $script:testDb)
            $results.Count | Should Be 1
        }

        It 'Warns about duplicate IP addresses' {
            $ip1 = IPAMModule\New-IPAddressRecord -IPAddress '192.168.1.10' -DeviceName 'SW-01'
            $ip2 = IPAMModule\New-IPAddressRecord -IPAddress '192.168.1.10' -DeviceName 'SW-02'
            IPAMModule\Add-IPAddressRecord -IPRecord $ip1 -Database $script:testDb
            IPAMModule\Add-IPAddressRecord -IPRecord $ip2 -Database $script:testDb -WarningAction SilentlyContinue

            # Both should be added (warning only)
            $script:testDb.IPAddresses.Count | Should Be 2
        }
    }

    #endregion

    #region Conflict Detection

    Context 'Find-VLANConflicts' {

        It 'Detects VLAN name mismatches' {
            $vlan1 = IPAMModule\New-VLAN -VlanNumber 100 -VlanName 'Management' -Site 'SITE-A'
            $vlan2 = IPAMModule\New-VLAN -VlanNumber 100 -VlanName 'Mgmt' -Site 'SITE-B'
            IPAMModule\Add-VLAN -VLAN $vlan1 -Database $script:testDb
            IPAMModule\Add-VLAN -VLAN $vlan2 -Database $script:testDb

            $conflicts = @(IPAMModule\Find-VLANConflicts -Database $script:testDb)

            $conflicts.Count | Should Be 1
            $conflicts[0].Type | Should Be 'VLANNameMismatch'
            $conflicts[0].VlanNumber | Should Be 100
        }

        It 'Returns empty when no conflicts' {
            $vlan1 = IPAMModule\New-VLAN -VlanNumber 10 -VlanName 'Users' -Site 'SITE-A'
            $vlan2 = IPAMModule\New-VLAN -VlanNumber 20 -VlanName 'Voice' -Site 'SITE-A'
            IPAMModule\Add-VLAN -VLAN $vlan1 -Database $script:testDb
            IPAMModule\Add-VLAN -VLAN $vlan2 -Database $script:testDb

            $conflicts = @(IPAMModule\Find-VLANConflicts -Database $script:testDb)

            $conflicts.Count | Should Be 0
        }
    }

    Context 'Find-IPConflicts' {

        It 'Detects duplicate IP addresses' {
            $ip1 = IPAMModule\New-IPAddressRecord -IPAddress '10.1.1.1' -DeviceName 'SW-01'
            $ip2 = IPAMModule\New-IPAddressRecord -IPAddress '10.1.1.1' -DeviceName 'SW-02'
            IPAMModule\Add-IPAddressRecord -IPRecord $ip1 -Database $script:testDb -WarningAction SilentlyContinue
            IPAMModule\Add-IPAddressRecord -IPRecord $ip2 -Database $script:testDb -WarningAction SilentlyContinue

            $conflicts = @(IPAMModule\Find-IPConflicts -Database $script:testDb)

            $conflicts.Count | Should Be 1
            $conflicts[0].Type | Should Be 'DuplicateIP'
            $conflicts[0].Severity | Should Be 'Critical'
        }
    }

    Context 'Find-IPAMConflicts' {

        It 'Detects subnet overlaps' {
            $subnet1 = IPAMModule\New-Subnet -NetworkAddress '10.0.0.0' -PrefixLength 16
            $subnet2 = IPAMModule\New-Subnet -NetworkAddress '10.0.1.0' -PrefixLength 24
            IPAMModule\Add-Subnet -Subnet $subnet1 -Database $script:testDb -WarningAction SilentlyContinue
            IPAMModule\Add-Subnet -Subnet $subnet2 -Database $script:testDb -WarningAction SilentlyContinue

            $conflicts = @(IPAMModule\Find-IPAMConflicts -Database $script:testDb)

            $subnetOverlaps = @($conflicts | Where-Object { $_.Type -eq 'SubnetOverlap' })
            $subnetOverlaps.Count | Should Be 1
        }
    }

    #endregion

    #region Planning Tools

    Context 'Find-AvailableVLANs' {

        It 'Returns available VLANs' {
            $vlan1 = IPAMModule\New-VLAN -VlanNumber 10 -VlanName 'Users' -Site 'SITE-A'
            $vlan2 = IPAMModule\New-VLAN -VlanNumber 20 -VlanName 'Voice' -Site 'SITE-A'
            IPAMModule\Add-VLAN -VLAN $vlan1 -Database $script:testDb
            IPAMModule\Add-VLAN -VLAN $vlan2 -Database $script:testDb

            $available = @(IPAMModule\Find-AvailableVLANs -StartVlan 1 -EndVlan 30 -Count 5 -Database $script:testDb)

            $available.Count | Should Be 5
            ($available -contains 10) | Should Be $false
            ($available -contains 20) | Should Be $false
            ($available -contains 1) | Should Be $true
        }

        It 'Filters by site' {
            $vlan1 = IPAMModule\New-VLAN -VlanNumber 10 -VlanName 'Users' -Site 'SITE-A'
            $vlan2 = IPAMModule\New-VLAN -VlanNumber 10 -VlanName 'Users' -Site 'SITE-B'
            IPAMModule\Add-VLAN -VLAN $vlan1 -Database $script:testDb
            IPAMModule\Add-VLAN -VLAN $vlan2 -Database $script:testDb

            $available = @(IPAMModule\Find-AvailableVLANs -StartVlan 10 -EndVlan 15 -Site 'SITE-A' -Count 5 -Database $script:testDb)

            ($available -contains 10) | Should Be $false
            ($available -contains 11) | Should Be $true
        }
    }

    Context 'Find-AvailableSubnets' {

        It 'Finds available subnets in supernet' {
            $subnet1 = IPAMModule\New-Subnet -NetworkAddress '10.1.0.0' -PrefixLength 24
            IPAMModule\Add-Subnet -Subnet $subnet1 -Database $script:testDb

            $available = @(IPAMModule\Find-AvailableSubnets `
                -SupernetAddress '10.1.0.0' -SupernetPrefix 16 `
                -DesiredPrefix 24 -Count 3 -Database $script:testDb)

            $available.Count | Should Be 3
            # First available should be 10.1.1.0/24 since 10.1.0.0/24 is taken
            $available[0].NetworkAddress | Should Be '10.1.1.0'
        }
    }

    Context 'New-SiteAddressPlan' {

        It 'Generates address plan for new site' {
            $plan = IPAMModule\New-SiteAddressPlan `
                -SiteName 'Building-A' `
                -SupernetAddress '10.5.0.0' `
                -SupernetPrefix 16 `
                -Database $script:testDb

            $plan | Should Not BeNullOrEmpty
            $plan.SiteName | Should Be 'Building-A'
            $plan.Allocations.Count | Should BeGreaterThan 0
        }

        It 'Respects custom VLAN requirements' {
            $requirements = @{
                Data = @{ Hosts = 50; VlanNumber = 10 }
            }

            $plan = IPAMModule\New-SiteAddressPlan `
                -SiteName 'Building-B' `
                -SupernetAddress '10.6.0.0' `
                -SupernetPrefix 16 `
                -VLANRequirements $requirements `
                -Database $script:testDb

            $plan.Allocations.Count | Should Be 1
            $plan.Allocations[0].VlanNumber | Should Be 10
        }
    }

    #endregion

    #region Import/Export

    Context 'Export and Import IPAMDatabase' {

        It 'Exports database to JSON' {
            $vlan = IPAMModule\New-VLAN -VlanNumber 10 -VlanName 'Users'
            $subnet = IPAMModule\New-Subnet -NetworkAddress '10.1.10.0' -PrefixLength 24
            IPAMModule\Add-VLAN -VLAN $vlan -Database $script:testDb
            IPAMModule\Add-Subnet -Subnet $subnet -Database $script:testDb

            $exportPath = Join-Path $env:TEMP 'IPAMTest.json'

            try {
                IPAMModule\Export-IPAMDatabase -Path $exportPath -Database $script:testDb
                Test-Path $exportPath | Should Be $true
            }
            finally {
                if (Test-Path $exportPath) { Remove-Item $exportPath -Force }
            }
        }

        It 'Imports database from JSON' {
            $vlan = IPAMModule\New-VLAN -VlanNumber 10 -VlanName 'Users'
            $subnet = IPAMModule\New-Subnet -NetworkAddress '10.1.10.0' -PrefixLength 24
            IPAMModule\Add-VLAN -VLAN $vlan -Database $script:testDb
            IPAMModule\Add-Subnet -Subnet $subnet -Database $script:testDb

            $exportPath = Join-Path $env:TEMP 'IPAMTest.json'

            try {
                IPAMModule\Export-IPAMDatabase -Path $exportPath -Database $script:testDb

                $importDb = IPAMModule\New-IPAMDatabase
                $result = IPAMModule\Import-IPAMDatabase -Path $exportPath -Database $importDb

                $result.VLANsImported | Should Be 1
                $result.SubnetsImported | Should Be 1
            }
            finally {
                if (Test-Path $exportPath) { Remove-Item $exportPath -Force }
            }
        }
    }

    Context 'Get-IPAMStats' {

        It 'Returns correct statistics' {
            $vlan1 = IPAMModule\New-VLAN -VlanNumber 10 -VlanName 'Users' -Purpose 'Data'
            $vlan2 = IPAMModule\New-VLAN -VlanNumber 20 -VlanName 'Voice' -Purpose 'Voice'
            $subnet = IPAMModule\New-Subnet -NetworkAddress '10.1.10.0' -PrefixLength 24 -Purpose 'Data'
            IPAMModule\Add-VLAN -VLAN $vlan1 -Database $script:testDb
            IPAMModule\Add-VLAN -VLAN $vlan2 -Database $script:testDb
            IPAMModule\Add-Subnet -Subnet $subnet -Database $script:testDb

            $stats = IPAMModule\Get-IPAMStats -Database $script:testDb

            $stats.TotalVLANs | Should Be 2
            $stats.TotalSubnets | Should Be 1
            $stats.VLANsByPurpose['Data'] | Should Be 1
            $stats.VLANsByPurpose['Voice'] | Should Be 1
        }
    }

    #endregion

    #region VLAN Discovery

    Context 'Import-VLANsFromConfig' {

        It 'Parses Cisco IOS VLAN definitions' {
            $config = @'
vlan 10
 name Users_Data
vlan 20
 name Voice_VLAN
vlan 100
 name Management
'@
            $vlans = @(IPAMModule\Import-VLANsFromConfig -ConfigText $config)

            $vlans.Count | Should Be 3
            $vlans[0].VlanNumber | Should Be 10
            $vlans[0].VlanName | Should Be 'Users_Data'
            $vlans[1].VlanNumber | Should Be 20
            $vlans[1].VlanName | Should Be 'Voice_VLAN'
        }

        It 'Auto-detects purpose from VLAN name' {
            $config = @'
vlan 10
 name Data_Users
vlan 20
 name Voice
vlan 100
 name Management
vlan 200
 name Guest_WiFi
'@
            $vlans = @(IPAMModule\Import-VLANsFromConfig -ConfigText $config)

            $vlans[0].Purpose | Should Be 'Data'
            $vlans[1].Purpose | Should Be 'Voice'
            $vlans[2].Purpose | Should Be 'Management'
            $vlans[3].Purpose | Should Be 'Guest'
        }

        It 'Handles Arista EOS format' {
            $config = @'
vlan 10
   name Users
vlan 20
   name Voice
'@
            $vlans = @(IPAMModule\Import-VLANsFromConfig -ConfigText $config -Vendor 'Arista_EOS')

            $vlans.Count | Should Be 2
        }

        It 'Returns empty for config without VLANs' {
            $config = @'
hostname SW-01
interface Gi1/0/1
 switchport mode access
'@
            $vlans = @(IPAMModule\Import-VLANsFromConfig -ConfigText $config)

            $vlans.Count | Should Be 0
        }

        It 'Sets device name when provided' {
            $config = @'
vlan 10
 name Users
'@
            $vlans = @(IPAMModule\Import-VLANsFromConfig -ConfigText $config -DeviceName 'SW-CORE-01')

            $vlans[0].DeviceName | Should Be 'SW-CORE-01'
        }
    }

    Context 'Import-SVIsFromConfig' {

        It 'Parses SVI interfaces with IP addresses' {
            $config = @'
interface Vlan10
 description User Network
 ip address 10.1.10.1 255.255.255.0
!
interface Vlan20
 description Voice Network
 ip address 10.1.20.1 255.255.255.0
'@
            $svis = @(IPAMModule\Import-SVIsFromConfig -ConfigText $config)

            $svis.Count | Should Be 2
            $svis[0].VlanNumber | Should Be 10
            $svis[0].IPAddress | Should Be '10.1.10.1'
            $svis[0].SubnetMask | Should Be '255.255.255.0'
            $svis[0].Description | Should Be 'User Network'
        }

        It 'Extracts HSRP virtual IP' {
            $config = @'
interface Vlan100
 ip address 10.1.100.2 255.255.255.0
 standby 100 ip 10.1.100.1
'@
            $svis = @(IPAMModule\Import-SVIsFromConfig -ConfigText $config)

            $svis[0].HSRPAddress | Should Be '10.1.100.1'
        }

        It 'Extracts VRRP virtual IP' {
            $config = @'
interface Vlan100
 ip address 10.1.100.2 255.255.255.0
 vrrp 100 ip 10.1.100.1
'@
            $svis = @(IPAMModule\Import-SVIsFromConfig -ConfigText $config)

            $svis[0].VRRPAddress | Should Be '10.1.100.1'
        }

        It 'Returns empty for config without SVIs' {
            $config = @'
interface Gi1/0/1
 ip address 10.1.1.1 255.255.255.252
'@
            $svis = @(IPAMModule\Import-SVIsFromConfig -ConfigText $config)

            $svis.Count | Should Be 0
        }
    }

    Context 'Import-VLANsToDatabase' {

        It 'Imports VLANs to database' {
            $config = @'
vlan 10
 name Users
vlan 20
 name Voice
'@
            $result = IPAMModule\Import-VLANsToDatabase -ConfigText $config -DeviceName 'SW-01' -Database $script:testDb

            $result.Imported | Should Be 2
            $result.Skipped | Should Be 0
            $script:testDb.VLANs.Count | Should Be 2
        }

        It 'Skips duplicates with SkipDuplicates' {
            $vlan = IPAMModule\New-VLAN -VlanNumber 10 -VlanName 'Existing'
            IPAMModule\Add-VLAN -VLAN $vlan -Database $script:testDb

            $config = @'
vlan 10
 name Users
vlan 20
 name Voice
'@
            $result = IPAMModule\Import-VLANsToDatabase -ConfigText $config -Database $script:testDb -SkipDuplicates

            $result.Imported | Should Be 1
            $result.Skipped | Should Be 1
        }

        It 'Updates existing with UpdateExisting' {
            $vlan = IPAMModule\New-VLAN -VlanNumber 10 -VlanName 'OldName'
            IPAMModule\Add-VLAN -VLAN $vlan -Database $script:testDb

            $config = @'
vlan 10
 name NewName
'@
            $result = IPAMModule\Import-VLANsToDatabase -ConfigText $config -Database $script:testDb -UpdateExisting

            $result.Updated | Should Be 1
            $updated = @(IPAMModule\Get-VLANRecord -VlanNumber 10 -Database $script:testDb)
            $updated[0].VlanName | Should Be 'NewName'
        }
    }

    Context 'Merge-VLANDiscovery' {

        It 'Merges VLANs from multiple devices' {
            $config1 = @'
vlan 10
 name Users
vlan 20
 name Voice
'@
            $config2 = @'
vlan 10
 name Users
vlan 30
 name Guest
'@
            $deviceConfigs = @{
                'SW-01' = $config1
                'SW-02' = $config2
            }

            $result = IPAMModule\Merge-VLANDiscovery -DeviceConfigs $deviceConfigs

            $result.TotalVLANs | Should Be 3
        }

        It 'Detects name conflicts across devices' {
            $config1 = @'
vlan 10
 name Users
'@
            $config2 = @'
vlan 10
 name Data
'@
            $deviceConfigs = @{
                'SW-01' = $config1
                'SW-02' = $config2
            }

            $result = IPAMModule\Merge-VLANDiscovery -DeviceConfigs $deviceConfigs

            $result.ConflictCount | Should Be 1
            $result.Conflicts[0].VlanNumber | Should Be 10
        }

        It 'Tracks device sources for merged VLANs' {
            $config1 = @'
vlan 10
 name Users
'@
            $config2 = @'
vlan 10
 name Users
'@
            $deviceConfigs = @{
                'SW-01' = $config1
                'SW-02' = $config2
            }

            $result = IPAMModule\Merge-VLANDiscovery -DeviceConfigs $deviceConfigs

            $vlan10 = $result.VLANs | Where-Object { $_.VlanNumber -eq 10 }
            $vlan10.Sources.Count | Should Be 2
        }
    }

    Context 'New-VLANDiscoveryReport' {

        It 'Generates text report' {
            $config = @'
vlan 10
 name Users
vlan 20
 name Voice
'@
            $deviceConfigs = @{ 'SW-01' = $config }
            $discoveryResult = IPAMModule\Merge-VLANDiscovery -DeviceConfigs $deviceConfigs

            $report = IPAMModule\New-VLANDiscoveryReport -DiscoveryResult $discoveryResult -Format 'Text'

            $report | Should Match 'VLAN Discovery Report'
            $report | Should Match '10'
            $report | Should Match 'Users'
        }

        It 'Generates markdown report' {
            $config = @'
vlan 10
 name Users
'@
            $deviceConfigs = @{ 'SW-01' = $config }
            $discoveryResult = IPAMModule\Merge-VLANDiscovery -DeviceConfigs $deviceConfigs

            $report = IPAMModule\New-VLANDiscoveryReport -DiscoveryResult $discoveryResult -Format 'Markdown'

            $report | Should Match '# VLAN Discovery Report'
            $report | Should Match '\| VLAN \| Name \|'
        }

        It 'Generates CSV report' {
            $config = @'
vlan 10
 name Users
vlan 20
 name Voice
'@
            $deviceConfigs = @{ 'SW-01' = $config }
            $discoveryResult = IPAMModule\Merge-VLANDiscovery -DeviceConfigs $deviceConfigs

            $report = IPAMModule\New-VLANDiscoveryReport -DiscoveryResult $discoveryResult -Format 'CSV'

            $report | Should Match 'VlanNumber'
            $report | Should Match '10,'
        }
    }

    #endregion

    #region ST-V-006: Site Planning Wizard UI Tests

    Context 'IPAMView XAML Wizard Controls' {
        BeforeAll {
            $script:xamlPath = Join-Path $PSScriptRoot '..\..\Views\IPAMView.xaml'
            $script:xamlContent = Get-Content -Path $script:xamlPath -Raw
        }

        It 'XAML file exists' {
            Test-Path $script:xamlPath | Should Be $true
        }

        It 'contains WizardPanel overlay' {
            $script:xamlContent | Should Match 'Name="WizardPanel"'
        }

        It 'contains WizardSiteNameBox' {
            $script:xamlContent | Should Match 'Name="WizardSiteNameBox"'
        }

        It 'contains WizardSupernetBox' {
            $script:xamlContent | Should Match 'Name="WizardSupernetBox"'
        }

        It 'contains WizardPrefixCombo' {
            $script:xamlContent | Should Match 'Name="WizardPrefixCombo"'
        }

        It 'contains WizardGrowthSlider' {
            $script:xamlContent | Should Match 'Name="WizardGrowthSlider"'
        }

        It 'contains WizardPreviewPanel' {
            $script:xamlContent | Should Match 'Name="WizardPreviewPanel"'
        }

        It 'contains VLAN type checkboxes' {
            $script:xamlContent | Should Match 'Name="WizardDataCheck"'
            $script:xamlContent | Should Match 'Name="WizardVoiceCheck"'
            $script:xamlContent | Should Match 'Name="WizardMgmtCheck"'
            $script:xamlContent | Should Match 'Name="WizardGuestCheck"'
            $script:xamlContent | Should Match 'Name="WizardIoTCheck"'
            $script:xamlContent | Should Match 'Name="WizardServerCheck"'
        }

        It 'contains host count input boxes' {
            $script:xamlContent | Should Match 'Name="WizardDataHostsBox"'
            $script:xamlContent | Should Match 'Name="WizardVoiceHostsBox"'
            $script:xamlContent | Should Match 'Name="WizardMgmtHostsBox"'
        }

        It 'contains subnet recommendation texts' {
            $script:xamlContent | Should Match 'Name="WizardDataSubnetText"'
            $script:xamlContent | Should Match 'Name="WizardVoiceSubnetText"'
            $script:xamlContent | Should Match 'Name="WizardMgmtSubnetText"'
        }

        It 'contains wizard buttons' {
            $script:xamlContent | Should Match 'Name="WizardGenerateButton"'
            $script:xamlContent | Should Match 'Name="WizardApplyButton"'
            $script:xamlContent | Should Match 'Name="WizardCancelButton"'
        }

        It 'contains PlanSiteButton in toolbar' {
            $script:xamlContent | Should Match 'Name="PlanSiteButton"'
        }
    }

    Context 'IPAMViewModule Wizard Wiring' {
        BeforeAll {
            $script:modulePath = Join-Path $PSScriptRoot '..\IPAMViewModule.psm1'
            $script:moduleContent = Get-Content -Path $script:modulePath -Raw
        }

        It 'view module file exists' {
            Test-Path $script:modulePath | Should Be $true
        }

        It 'contains wizard control references' {
            $script:moduleContent | Should Match '\$wizardPanel\s*='
            $script:moduleContent | Should Match '\$wizardSiteNameBox\s*='
            $script:moduleContent | Should Match '\$wizardSupernetBox\s*='
            $script:moduleContent | Should Match '\$wizardPrefixCombo\s*='
            $script:moduleContent | Should Match '\$wizardGrowthSlider\s*='
        }

        It 'contains WizardPlan state in Tag' {
            $script:moduleContent | Should Match 'WizardPlan\s*='
        }

        It 'contains Get-RecommendedPrefix helper' {
            $script:moduleContent | Should Match 'function Get-RecommendedPrefix'
        }

        It 'contains updateSubnetRecommendations helper' {
            $script:moduleContent | Should Match '\$updateSubnetRecommendations\s*='
        }

        It 'contains resetWizard helper' {
            $script:moduleContent | Should Match '\$resetWizard\s*='
        }

        It 'wires PlanSiteButton click handler' {
            $script:moduleContent | Should Match '\$planSiteButton\.Add_Click'
        }

        It 'wires WizardGrowthSlider value changed' {
            $script:moduleContent | Should Match '\$wizardGrowthSlider\.Add_ValueChanged'
        }

        It 'wires WizardGenerateButton click handler' {
            $script:moduleContent | Should Match '\$wizardGenerateButton\.Add_Click'
        }

        It 'wires WizardApplyButton click handler' {
            $script:moduleContent | Should Match '\$wizardApplyButton\.Add_Click'
        }

        It 'wires WizardCancelButton click handler' {
            $script:moduleContent | Should Match '\$wizardCancelButton\.Add_Click'
        }

        It 'wires host count text changed handlers' {
            $script:moduleContent | Should Match '\$wizardDataHostsBox\.Add_TextChanged'
            $script:moduleContent | Should Match '\$wizardVoiceHostsBox\.Add_TextChanged'
            $script:moduleContent | Should Match '\$wizardMgmtHostsBox\.Add_TextChanged'
        }
    }

    #endregion
}
