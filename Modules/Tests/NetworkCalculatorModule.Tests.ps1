Set-StrictMode -Version Latest

$modulePath = Join-Path $PSScriptRoot '..\NetworkCalculatorModule.psm1'
Import-Module $modulePath -Force -ErrorAction Stop
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')

Describe 'NetworkCalculatorModule - CIDR Conversion' -Tag 'Calculator', 'Unit' {

    Context 'Convert-CIDRToMask' {
        It 'converts /0 to 0.0.0.0' {
            Convert-CIDRToMask -CIDR 0 | Should Be '0.0.0.0'
        }

        It 'converts /8 to 255.0.0.0' {
            Convert-CIDRToMask -CIDR 8 | Should Be '255.0.0.0'
        }

        It 'converts /16 to 255.255.0.0' {
            Convert-CIDRToMask -CIDR 16 | Should Be '255.255.0.0'
        }

        It 'converts /24 to 255.255.255.0' {
            Convert-CIDRToMask -CIDR 24 | Should Be '255.255.255.0'
        }

        It 'converts /25 to 255.255.255.128' {
            Convert-CIDRToMask -CIDR 25 | Should Be '255.255.255.128'
        }

        It 'converts /30 to 255.255.255.252' {
            Convert-CIDRToMask -CIDR 30 | Should Be '255.255.255.252'
        }

        It 'converts /32 to 255.255.255.255' {
            Convert-CIDRToMask -CIDR 32 | Should Be '255.255.255.255'
        }

        It 'rejects negative CIDR' {
            { Convert-CIDRToMask -CIDR -1 } | Assert-Throws
        }

        It 'rejects CIDR > 32' {
            { Convert-CIDRToMask -CIDR 33 } | Assert-Throws
        }
    }

    Context 'Convert-MaskToCIDR' {
        It 'converts 255.255.255.0 to /24' {
            Convert-MaskToCIDR -Mask '255.255.255.0' | Should Be 24
        }

        It 'converts 255.255.255.128 to /25' {
            Convert-MaskToCIDR -Mask '255.255.255.128' | Should Be 25
        }

        It 'converts 255.255.254.0 to /23' {
            Convert-MaskToCIDR -Mask '255.255.254.0' | Should Be 23
        }

        It 'converts 255.0.0.0 to /8' {
            Convert-MaskToCIDR -Mask '255.0.0.0' | Should Be 8
        }

        It 'rejects non-contiguous mask 255.255.255.1' {
            { Convert-MaskToCIDR -Mask '255.255.255.1' } | Assert-Throws
        }

        It 'rejects non-contiguous mask 255.0.255.0' {
            { Convert-MaskToCIDR -Mask '255.0.255.0' } | Assert-Throws
        }
    }
}

Describe 'NetworkCalculatorModule - Subnet Calculation' -Tag 'Calculator', 'Unit' {

    Context 'Get-SubnetInfo' {
        It 'calculates /24 network correctly' {
            $result = Get-SubnetInfo -Network '192.168.1.0' -CIDR 24

            $result.NetworkAddress | Should Be '192.168.1.0'
            $result.BroadcastAddress | Should Be '192.168.1.255'
            $result.SubnetMask | Should Be '255.255.255.0'
            $result.WildcardMask | Should Be '0.0.0.255'
            $result.FirstUsable | Should Be '192.168.1.1'
            $result.LastUsable | Should Be '192.168.1.254'
            $result.TotalHosts | Should Be 254
        }

        It 'calculates /30 network correctly' {
            $result = Get-SubnetInfo -Network '10.0.0.0' -CIDR 30

            $result.NetworkAddress | Should Be '10.0.0.0'
            $result.BroadcastAddress | Should Be '10.0.0.3'
            $result.FirstUsable | Should Be '10.0.0.1'
            $result.LastUsable | Should Be '10.0.0.2'
            $result.TotalHosts | Should Be 2
        }

        It 'calculates /31 point-to-point correctly' {
            $result = Get-SubnetInfo -Network '10.0.0.0' -CIDR 31

            $result.TotalHosts | Should Be 2
            $result.FirstUsable | Should Be '10.0.0.0'
            $result.LastUsable | Should Be '10.0.0.1'
        }

        It 'calculates /32 host route correctly' {
            $result = Get-SubnetInfo -Network '10.0.0.1' -CIDR 32

            $result.TotalHosts | Should Be 1
            $result.FirstUsable | Should Be '10.0.0.1'
            $result.LastUsable | Should Be '10.0.0.1'
        }

        It 'normalizes non-network addresses to network address' {
            $result = Get-SubnetInfo -Network '192.168.1.50' -CIDR 24

            $result.NetworkAddress | Should Be '192.168.1.0'
        }

        It 'calculates /16 network correctly' {
            $result = Get-SubnetInfo -Network '172.16.0.0' -CIDR 16

            $result.NetworkAddress | Should Be '172.16.0.0'
            $result.BroadcastAddress | Should Be '172.16.255.255'
            $result.TotalHosts | Should Be 65534
        }
    }

    Context 'Test-IPInSubnet' {
        It 'identifies IP within subnet' {
            Test-IPInSubnet -IP '192.168.1.50' -Network '192.168.1.0/24' | Should Be $true
        }

        It 'identifies IP outside subnet' {
            Test-IPInSubnet -IP '192.168.2.50' -Network '192.168.1.0/24' | Should Be $false
        }

        It 'handles network address correctly' {
            Test-IPInSubnet -IP '192.168.1.0' -Network '192.168.1.0/24' | Should Be $true
        }

        It 'handles broadcast address correctly' {
            Test-IPInSubnet -IP '192.168.1.255' -Network '192.168.1.0/24' | Should Be $true
        }

        It 'rejects IP just outside subnet' {
            Test-IPInSubnet -IP '192.168.0.255' -Network '192.168.1.0/24' | Should Be $false
        }
    }

    Context 'Split-Subnet' {
        It 'splits /24 into four /26 subnets' {
            $result = Split-Subnet -Network '192.168.1.0/24' -NewPrefix 26

            $result.Count | Should Be 4
            $result[0].NetworkAddress | Should Be '192.168.1.0'
            $result[1].NetworkAddress | Should Be '192.168.1.64'
            $result[2].NetworkAddress | Should Be '192.168.1.128'
            $result[3].NetworkAddress | Should Be '192.168.1.192'
        }

        It 'splits /24 into two /25 subnets' {
            $result = Split-Subnet -Network '10.0.0.0/24' -NewPrefix 25

            $result.Count | Should Be 2
            $result[0].NetworkAddress | Should Be '10.0.0.0'
            $result[1].NetworkAddress | Should Be '10.0.0.128'
        }

        It 'rejects invalid split (smaller to larger)' {
            { Split-Subnet -Network '192.168.1.0/24' -NewPrefix 16 } | Assert-Throws
        }
    }

    Context 'Merge-Subnets' {
        It 'aggregates two /24 into one /23' {
            $subnets = @('192.168.0.0/24', '192.168.1.0/24')
            $result = Merge-Subnets -Subnets $subnets

            $result.NetworkAddress | Should Be '192.168.0.0'
            $result.CIDR | Should Be 23
        }

        It 'aggregates four /26 into one /24' {
            $subnets = @('192.168.1.0/26', '192.168.1.64/26', '192.168.1.128/26', '192.168.1.192/26')
            $result = Merge-Subnets -Subnets $subnets

            $result.NetworkAddress | Should Be '192.168.1.0'
            $result.CIDR | Should Be 24
        }

        It 'throws for non-contiguous subnets' {
            $subnets = @('192.168.0.0/24', '192.168.2.0/24')
            { Merge-Subnets -Subnets $subnets } | Assert-Throws
        }
    }
}

Describe 'NetworkCalculatorModule - IP Validation' -Tag 'Calculator', 'Unit' {

    Context 'Test-IPv4Address' {
        It 'validates correct IPv4 addresses' {
            Test-IPv4Address -IP '192.168.1.1' | Should Be $true
            Test-IPv4Address -IP '0.0.0.0' | Should Be $true
            Test-IPv4Address -IP '255.255.255.255' | Should Be $true
        }

        It 'rejects octet > 255' {
            Test-IPv4Address -IP '256.1.1.1' | Should Be $false
        }

        It 'rejects incomplete address' {
            Test-IPv4Address -IP '192.168.1' | Should Be $false
        }

        It 'rejects address with extra octet' {
            Test-IPv4Address -IP '192.168.1.1.1' | Should Be $false
        }

        It 'rejects non-numeric address' {
            Test-IPv4Address -IP 'not.an.ip.addr' | Should Be $false
        }
    }

    Context 'Test-PrivateIP' {
        It 'identifies 10.x.x.x as private' {
            Test-PrivateIP -IP '10.0.0.1' | Should Be $true
            Test-PrivateIP -IP '10.255.255.254' | Should Be $true
        }

        It 'identifies 172.16-31.x.x as private' {
            Test-PrivateIP -IP '172.16.0.1' | Should Be $true
            Test-PrivateIP -IP '172.31.255.254' | Should Be $true
        }

        It 'rejects 172.15.x.x as public' {
            Test-PrivateIP -IP '172.15.0.1' | Should Be $false
        }

        It 'identifies 192.168.x.x as private' {
            Test-PrivateIP -IP '192.168.0.1' | Should Be $true
            Test-PrivateIP -IP '192.168.255.254' | Should Be $true
        }

        It 'identifies public addresses' {
            Test-PrivateIP -IP '8.8.8.8' | Should Be $false
            Test-PrivateIP -IP '1.1.1.1' | Should Be $false
        }
    }

    Context 'Test-LinkLocalIP' {
        It 'identifies 169.254.x.x as link-local' {
            Test-LinkLocalIP -IP '169.254.1.1' | Should Be $true
            Test-LinkLocalIP -IP '169.254.255.254' | Should Be $true
        }

        It 'rejects non-link-local' {
            Test-LinkLocalIP -IP '192.168.1.1' | Should Be $false
        }
    }

    Context 'Test-LoopbackIP' {
        It 'identifies 127.x.x.x as loopback' {
            Test-LoopbackIP -IP '127.0.0.1' | Should Be $true
            Test-LoopbackIP -IP '127.255.255.254' | Should Be $true
        }

        It 'rejects non-loopback' {
            Test-LoopbackIP -IP '128.0.0.1' | Should Be $false
        }
    }
}

Describe 'NetworkCalculatorModule - Format Conversion' -Tag 'Calculator', 'Unit' {

    Context 'Convert-IPToBinary' {
        It 'converts 192.168.1.1 to binary' {
            Convert-IPToBinary -IP '192.168.1.1' | Should Be '11000000.10101000.00000001.00000001'
        }

        It 'converts 0.0.0.0 to binary' {
            Convert-IPToBinary -IP '0.0.0.0' | Should Be '00000000.00000000.00000000.00000000'
        }

        It 'converts 255.255.255.255 to binary' {
            Convert-IPToBinary -IP '255.255.255.255' | Should Be '11111111.11111111.11111111.11111111'
        }
    }

    Context 'Convert-BinaryToIP' {
        It 'converts binary to 192.168.1.1' {
            Convert-BinaryToIP -Binary '11000000.10101000.00000001.00000001' | Should Be '192.168.1.1'
        }
    }

    Context 'Convert-IPToDecimal' {
        It 'converts 192.168.1.1 to decimal' {
            Convert-IPToDecimal -IP '192.168.1.1' | Should Be 3232235777
        }

        It 'converts 10.0.0.1 to decimal' {
            Convert-IPToDecimal -IP '10.0.0.1' | Should Be 167772161
        }
    }

    Context 'Convert-DecimalToIP' {
        It 'converts decimal to 192.168.1.1' {
            Convert-DecimalToIP -Decimal 3232235777 | Should Be '192.168.1.1'
        }
    }
}

Describe 'NetworkCalculatorModule - VLAN Calculator' -Tag 'Calculator', 'Unit' {

    Context 'Expand-VLANRange' {
        It 'expands simple range' {
            $result = Expand-VLANRange -Range '10-15'

            $result.Count | Should Be 6
            $result[0] | Should Be 10
            $result[5] | Should Be 15
        }

        It 'expands complex range' {
            $result = Expand-VLANRange -Range '10-12,20,30-32'

            $result.Count | Should Be 7
            $result -contains 10 | Should Be $true
            $result -contains 20 | Should Be $true
            $result -contains 32 | Should Be $true
        }

        It 'handles single VLAN' {
            $result = @(Expand-VLANRange -Range '100')

            $result.Count | Should Be 1
            $result[0] | Should Be 100
        }

        It 'rejects VLAN 0' {
            { Expand-VLANRange -Range '0-10' } | Assert-Throws
        }

        It 'rejects VLAN > 4094' {
            { Expand-VLANRange -Range '4090-4096' } | Assert-Throws
        }
    }

    Context 'Compress-VLANRange' {
        It 'compresses sequential VLANs' {
            $vlans = @(10, 11, 12, 13, 14, 15)
            Compress-VLANRange -VLANs $vlans | Should Be '10-15'
        }

        It 'compresses mixed VLANs' {
            $vlans = @(10, 11, 12, 20, 30, 31, 32)
            Compress-VLANRange -VLANs $vlans | Should Be '10-12,20,30-32'
        }

        It 'handles single VLAN' {
            Compress-VLANRange -VLANs @(100) | Should Be '100'
        }

        It 'handles unsorted input' {
            $vlans = @(15, 10, 12, 11, 14, 13)
            Compress-VLANRange -VLANs $vlans | Should Be '10-15'
        }
    }
}

Describe 'NetworkCalculatorModule - Bandwidth Calculator' -Tag 'Calculator', 'Unit' {

    Context 'Get-TransferTime' {
        It 'calculates transfer time for 1GB at 1Gbps' {
            $result = Get-TransferTime -Size '1GB' -Bandwidth '1Gbps'

            # 1GB = 8Gb, at 1Gbps = 8 seconds
            $result.Seconds | Should BeGreaterThan 7
            $result.Seconds | Should BeLessThan 9
        }

        It 'calculates transfer time for 100MB at 100Mbps' {
            $result = Get-TransferTime -Size '100MB' -Bandwidth '100Mbps'

            # 100MB = 800Mb, at 100Mbps = 8 seconds
            $result.Seconds | Should BeGreaterThan 7
            $result.Seconds | Should BeLessThan 9
        }

        It 'accounts for link utilization' {
            $result = Get-TransferTime -Size '1GB' -Bandwidth '1Gbps' -Utilization 50

            # At 50% util, should take ~17 seconds (1GB = 1024MB, so slightly more)
            $result.Seconds | Should BeGreaterThan 15
            $result.Seconds | Should BeLessThan 18
        }
    }

    Context 'Get-RequiredBandwidth' {
        It 'calculates bandwidth for 1GB in 60 seconds' {
            $result = Get-RequiredBandwidth -Size '1GB' -TimeSeconds 60

            # 1GB = 1024*1024*1024 bytes = 8589934592 bits / 60s = ~143 Mbps
            $result.Mbps | Should BeGreaterThan 140
            $result.Mbps | Should BeLessThan 150
        }

        It 'calculates bandwidth for 100MB in 10 seconds' {
            $result = Get-RequiredBandwidth -Size '100MB' -TimeSeconds 10

            # 100MB = 104857600 bytes = 838860800 bits / 10s = ~84 Mbps
            $result.Mbps | Should BeGreaterThan 80
            $result.Mbps | Should BeLessThan 90
        }
    }

    Context 'Convert-Bandwidth' {
        It 'converts Mbps to Gbps' {
            Convert-Bandwidth -Value 1000 -FromUnit 'Mbps' -ToUnit 'Gbps' | Should Be 1
        }

        It 'converts MBps to Mbps' {
            # 100 MBps = 100 * 8 * 1024 * 1024 bps = 838,860,800 bps = 838.8608 Mbps
            $result = Convert-Bandwidth -Value 100 -FromUnit 'MBps' -ToUnit 'Mbps'
            $result | Should BeGreaterThan 838
            $result | Should BeLessThan 839
        }

        It 'converts Gbps to Mbps' {
            Convert-Bandwidth -Value 1 -FromUnit 'Gbps' -ToUnit 'Mbps' | Should Be 1000
        }
    }
}

Describe 'NetworkCalculatorModule - Protocol Timers' -Tag 'Calculator', 'Unit' {

    Context 'Test-STPTimers' {
        It 'validates default STP timers' {
            $result = Test-STPTimers -Hello 2 -Forward 15 -MaxAge 20

            $result.Valid | Should Be $true
        }

        It 'rejects invalid timer relationships' {
            # MaxAge must be >= 2*(Hello+1) = 2*(5+1) = 12, but also <= 2*(Forward-1) = 2*(8-1) = 14
            # If MaxAge=20, it violates the second rule (20 > 14)
            $result = Test-STPTimers -Hello 5 -Forward 8 -MaxAge 20

            $result.Valid | Should Be $false
            $result.Reason | Should Match 'MaxAge'
        }
    }

    Context 'Get-STPConvergenceTime' {
        It 'calculates worst case convergence' {
            $result = Get-STPConvergenceTime -Forward 15 -MaxAge 20

            # MaxAge + 2*Forward = 20 + 30 = 50
            $result.WorstCase | Should Be 50
        }
    }

    Context 'Test-OSPFTimers' {
        It 'validates default OSPF timers' {
            $result = Test-OSPFTimers -Hello 10 -Dead 40

            $result.Valid | Should Be $true
            $result.Warning | Should BeNullOrEmpty
        }

        It 'warns on non-standard dead interval' {
            $result = Test-OSPFTimers -Hello 10 -Dead 30

            $result.Valid | Should Be $true
            $result.Warning | Should Match 'non-standard'
        }

        It 'rejects dead <= hello' {
            $result = Test-OSPFTimers -Hello 10 -Dead 10

            $result.Valid | Should Be $false
        }
    }
}

Describe 'NetworkCalculatorModule - Well-Known Ports' -Tag 'Calculator', 'Unit' {

    Context 'Get-WellKnownPorts' {
        It 'returns port list' {
            $ports = Get-WellKnownPorts

            $ports.Count | Should BeGreaterThan 20
        }

        It 'finds SSH port' {
            $ports = @(Get-WellKnownPorts -Search 'SSH')

            $ports.Count | Should Be 1
            $ports[0].Port | Should Be 22
        }

        It 'finds port by number' {
            $ports = @(Get-WellKnownPorts -Search '443')

            $ports.Count | Should BeGreaterThan 0
            $ports[0].Service | Should Be 'HTTPS'
        }
    }
}

Describe 'NetworkCalculatorModule - ACL Builder' -Tag 'Calculator', 'Unit' {

    Context 'New-ACLEntry' {
        It 'creates deny ip entry with any source and any dest' {
            $entry = New-ACLEntry -Action 'deny' -Protocol 'ip' -SourceNetwork 'any' -DestinationNetwork 'any'

            $entry.Action | Should Be 'deny'
            $entry.Protocol | Should Be 'ip'
            $entry.Source | Should Be 'any'
            $entry.Destination | Should Be 'any'
            $entry.SourceWildcard | Should Be 'any'
            $entry.DestWildcard | Should Be 'any'
        }

        It 'creates permit tcp entry with CIDR networks' {
            $entry = New-ACLEntry -Action 'permit' -Protocol 'tcp' -SourceNetwork '10.0.0.0/24' -DestinationNetwork '192.168.1.0/24'

            $entry.Action | Should Be 'permit'
            $entry.Protocol | Should Be 'tcp'
            $entry.Source | Should Be '10.0.0.0/24'
            $entry.SourceWildcard.Network | Should Be '10.0.0.0'
            $entry.SourceWildcard.Wildcard | Should Be '0.0.0.255'
            $entry.DestWildcard.Network | Should Be '192.168.1.0'
            $entry.DestWildcard.Wildcard | Should Be '0.0.0.255'
        }

        It 'creates entry with ports for TCP' {
            $entry = New-ACLEntry -Action 'permit' -Protocol 'tcp' -SourceNetwork 'any' -DestinationNetwork 'any' `
                -SourcePort '1024' -DestinationPort '443'

            $entry.SourcePort | Should Be '1024'
            $entry.DestinationPort | Should Be '443'
        }

        It 'creates entry with ports for UDP' {
            $entry = New-ACLEntry -Action 'deny' -Protocol 'udp' -SourceNetwork 'any' -DestinationNetwork 'any' `
                -DestinationPort '53'

            $entry.Protocol | Should Be 'udp'
            $entry.DestinationPort | Should Be '53'
        }

        It 'creates entry with remark' {
            $entry = New-ACLEntry -Action 'deny' -Protocol 'ip' -SourceNetwork '10.0.0.0/8' -DestinationNetwork 'any' `
                -Remark 'Block private addresses'

            $entry.Remark | Should Be 'Block private addresses'
        }

        It 'rejects ports for IP protocol' {
            { New-ACLEntry -Action 'deny' -Protocol 'ip' -SourceNetwork 'any' -DestinationNetwork 'any' `
                -DestinationPort '80' } | Assert-Throws
        }

        It 'rejects ports for ICMP protocol' {
            { New-ACLEntry -Action 'permit' -Protocol 'icmp' -SourceNetwork 'any' -DestinationNetwork 'any' `
                -DestinationPort '8' } | Assert-Throws
        }

        It 'rejects invalid source IP' {
            { New-ACLEntry -Action 'deny' -Protocol 'ip' -SourceNetwork '999.0.0.0/24' -DestinationNetwork 'any' } | Assert-Throws
        }

        It 'rejects invalid destination IP' {
            { New-ACLEntry -Action 'deny' -Protocol 'ip' -SourceNetwork 'any' -DestinationNetwork '10.0.0.0' } | Assert-Throws
        }
    }

    Context 'Get-ACLConfig' {
        It 'generates Cisco extended ACL header' {
            $entry = New-ACLEntry -Action 'deny' -Protocol 'ip' -SourceNetwork 'any' -DestinationNetwork 'any'
            $config = Get-ACLConfig -ACLName 'TEST-ACL' -Entries @($entry) -Vendor 'Cisco'

            $config | Should Match 'ip access-list extended TEST-ACL'
        }

        It 'generates Arista ACL header' {
            $entry = New-ACLEntry -Action 'permit' -Protocol 'ip' -SourceNetwork 'any' -DestinationNetwork 'any'
            $config = Get-ACLConfig -ACLName 'TEST-ACL' -Entries @($entry) -Vendor 'Arista'

            $config | Should Match 'ip access-list TEST-ACL'
        }

        It 'generates ACE with any source and destination' {
            $entry = New-ACLEntry -Action 'deny' -Protocol 'ip' -SourceNetwork 'any' -DestinationNetwork 'any'
            $config = Get-ACLConfig -ACLName 'TEST-ACL' -Entries @($entry)

            $config | Should Match 'deny ip any any'
        }

        It 'generates ACE with wildcard masks' {
            $entry = New-ACLEntry -Action 'deny' -Protocol 'ip' -SourceNetwork '10.0.0.0/24' -DestinationNetwork '192.168.1.0/24'
            $config = Get-ACLConfig -ACLName 'TEST-ACL' -Entries @($entry)

            $config | Should Match 'deny ip 10.0.0.0 0.0.0.255 192.168.1.0 0.0.0.255'
        }

        It 'generates ACE with destination port' {
            $entry = New-ACLEntry -Action 'permit' -Protocol 'tcp' -SourceNetwork 'any' -DestinationNetwork 'any' `
                -DestinationPort '443'
            $config = Get-ACLConfig -ACLName 'TEST-ACL' -Entries @($entry)

            $config | Should Match 'permit tcp any any eq 443'
        }

        It 'generates ACE with port range' {
            $entry = New-ACLEntry -Action 'permit' -Protocol 'tcp' -SourceNetwork 'any' -DestinationNetwork 'any' `
                -DestinationPort '1024-65535'
            $config = Get-ACLConfig -ACLName 'TEST-ACL' -Entries @($entry)

            $config | Should Match 'permit tcp any any range 1024 65535'
        }

        It 'generates remark lines' {
            $entry = New-ACLEntry -Action 'deny' -Protocol 'ip' -SourceNetwork '10.0.0.0/8' -DestinationNetwork 'any' `
                -Remark 'Block RFC1918'
            $config = Get-ACLConfig -ACLName 'TEST-ACL' -Entries @($entry)

            $config | Should Match 'remark Block RFC1918'
        }

        It 'assigns sequence numbers' {
            $entry1 = New-ACLEntry -Action 'deny' -Protocol 'ip' -SourceNetwork '10.0.0.0/8' -DestinationNetwork 'any'
            $entry2 = New-ACLEntry -Action 'permit' -Protocol 'ip' -SourceNetwork 'any' -DestinationNetwork 'any'
            $config = Get-ACLConfig -ACLName 'TEST-ACL' -Entries @($entry1, $entry2)

            $config | Should Match '10 deny'
            $config | Should Match '20 permit'
        }
    }

    Context 'Test-ACLEntry' {
        It 'validates correct entry' {
            $entry = New-ACLEntry -Action 'permit' -Protocol 'tcp' -SourceNetwork '10.0.0.0/24' -DestinationNetwork 'any'
            $result = Test-ACLEntry -Entry $entry

            $result.Valid | Should Be $true
            $result.Issues.Count | Should Be 0
        }

        It 'identifies invalid action' {
            $entry = [PSCustomObject]@{
                Action = 'allow'
                Protocol = 'ip'
                Source = 'any'
                Destination = 'any'
            }
            $result = Test-ACLEntry -Entry $entry

            $result.Valid | Should Be $false
            $result.Issues | Should Match 'Invalid action'
        }

        It 'identifies invalid protocol' {
            $entry = [PSCustomObject]@{
                Action = 'permit'
                Protocol = 'gre'
                Source = 'any'
                Destination = 'any'
            }
            $result = Test-ACLEntry -Entry $entry

            $result.Valid | Should Be $false
            $result.Issues | Should Match 'Invalid protocol'
        }
    }

    Context 'Get-ACLTemplates' {
        It 'returns template list' {
            $templates = Get-ACLTemplates

            $templates.Count | Should BeGreaterThan 0
        }

        It 'returns templates with required properties' {
            $templates = Get-ACLTemplates

            $templates[0].Name | Should Not BeNullOrEmpty
            $templates[0].Description | Should Not BeNullOrEmpty
            $templates[0].Entries.Count | Should BeGreaterThan 0
        }

        It 'includes Block RFC1918 template' {
            $templates = Get-ACLTemplates
            $rfc1918 = @($templates | Where-Object { $_.Name -match 'RFC1918' })

            $rfc1918.Count | Should Be 1
            $rfc1918[0].Entries.Count | Should BeGreaterThan 2
        }

        It 'includes Allow Web Traffic template' {
            $templates = Get-ACLTemplates
            $webTraffic = @($templates | Where-Object { $_.Name -match 'Web Traffic' })

            $webTraffic.Count | Should Be 1
        }
    }
}
