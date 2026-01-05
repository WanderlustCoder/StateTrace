# Plan Y - Network Calculator Tools

<!-- LANDMARK: ST-E-001 telemetry gates link -->
Telemetry gates: [docs/telemetry/Automation_Gates.md](../telemetry/Automation_Gates.md).

## Objective
Provide a comprehensive suite of network calculation tools for daily engineering tasks. Enable quick subnet calculations, bandwidth planning, protocol timers, and configuration generators without external tools or internet access.

## Problem Statement
Network engineers frequently need to:
- Calculate subnet boundaries, masks, and usable ranges
- Convert between different IP notation formats
- Plan bandwidth and determine link requirements
- Calculate protocol timers and parameters
- Generate standard configuration snippets
- Verify address ranges and CIDR aggregation

## Current status (2026-01)
- No built-in network calculators
- Engineers rely on external websites or standalone tools
- Configuration generation is limited to Port Reorg scripts
- No bandwidth or protocol timer calculators

## Proposed Features

### Y.1 Subnet Calculator
- **CIDR Calculator**: From any input format:
  - Network address and prefix (/24)
  - Network address and subnet mask
  - IP range (first - last)
- **Output**: Network, broadcast, mask, wildcard, usable range, host count
- **Subnet Division**: Split into smaller subnets (/24 -> /26)
- **Supernet Aggregation**: Combine contiguous subnets
- **Subnet Allocation**: Allocate subnets from a parent block

### Y.2 IP Address Tools
- **Format Conversion**:
  - Dotted decimal <-> Binary
  - Dotted decimal <-> Hexadecimal
  - CIDR <-> Subnet mask <-> Wildcard
- **Address Validation**: Check if IP is valid, public/private, reserved
- **Address Classification**: Identify class (A/B/C/D/E), RFC ranges
- **In-Subnet Check**: Verify if IP is within a given subnet

### Y.3 VLAN Calculator
- **VLAN Range Expansion**: "10-20,25,30-35" -> list all VLANs
- **VLAN Range Compression**: List of VLANs -> compact notation
- **VLAN Conflict Finder**: Identify overlapping ranges
- **Trunk Allowed VLAN Optimizer**: Minimize trunk config syntax

### Y.4 Bandwidth Calculator
- **Data Transfer Time**: Calculate transfer time for given size and speed
- **Required Bandwidth**: Bandwidth needed for given data in given time
- **Link Utilization**: Actual throughput at given utilization percentage
- **Aggregation Calculator**: Combined bandwidth of multiple links
- **Unit Conversion**: Mbps/Gbps/MB/s/GB/s conversions

### Y.5 Protocol Calculators
- **STP Timers**:
  - Max Age, Forward Delay, Hello Time relationships
  - Convergence time estimation
  - Diameter/delay recommendations
- **OSPF Timers**:
  - Hello/Dead interval relationships
  - LSA aging and refresh
  - SPF throttling
- **EIGRP Metrics**:
  - Composite metric calculation
  - K-value impact analysis
- **BGP Timers**:
  - Keepalive/Hold timer relationships
  - Route advertisement interval

### Y.6 Configuration Generators
- **ACL Builder**: Interactive ACL construction with:
  - Permit/deny selection
  - Protocol (IP, TCP, UDP, ICMP)
  - Source/destination with wildcards
  - Port specifications
  - Remarks/comments
- **Interface Config**: Generate interface configuration from parameters
- **VLAN Config**: Generate VLAN creation commands
- **Routing Config**: Generate static routes, route-maps

### Y.7 Quick Reference
- **Well-Known Ports**: Searchable port number reference
- **Protocol Numbers**: IP protocol number lookup
- **DSCP/CoS Values**: QoS marking reference
- **Private IP Ranges**: RFC 1918 and other reserved ranges

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-Y-001 | Subnet calculator core | Tools | Pending | CIDR math and conversions |
| ST-Y-002 | IP address utilities | Tools | Pending | Format conversion and validation |
| ST-Y-003 | Bandwidth calculator | Tools | Pending | Transfer time and utilization |
| ST-Y-004 | Protocol timer calculators | Tools | Pending | STP, OSPF, EIGRP, BGP |
| ST-Y-005 | ACL builder UI | UI | Pending | Interactive ACL construction |
| ST-Y-006 | Calculator toolbar view | UI | Pending | Integrated calculator panel |

## Testing Requirements

### Core Subnet Calculator Tests (`Modules/Tests/NetworkCalculator.Subnet.Tests.ps1`)

```powershell
Describe 'Subnet Calculator Core' -Tag 'Calculator' {

    Describe 'CIDR to Subnet Mask Conversion' {
        It 'converts /0 to 0.0.0.0' {
            Convert-CIDRToMask -CIDR 0 | Should -Be '0.0.0.0'
        }
        It 'converts /8 to 255.0.0.0' {
            Convert-CIDRToMask -CIDR 8 | Should -Be '255.0.0.0'
        }
        It 'converts /16 to 255.255.0.0' {
            Convert-CIDRToMask -CIDR 16 | Should -Be '255.255.0.0'
        }
        It 'converts /24 to 255.255.255.0' {
            Convert-CIDRToMask -CIDR 24 | Should -Be '255.255.255.0'
        }
        It 'converts /25 to 255.255.255.128' {
            Convert-CIDRToMask -CIDR 25 | Should -Be '255.255.255.128'
        }
        It 'converts /30 to 255.255.255.252' {
            Convert-CIDRToMask -CIDR 30 | Should -Be '255.255.255.252'
        }
        It 'converts /32 to 255.255.255.255' {
            Convert-CIDRToMask -CIDR 32 | Should -Be '255.255.255.255'
        }
        It 'rejects invalid CIDR values' {
            { Convert-CIDRToMask -CIDR -1 } | Should -Throw
            { Convert-CIDRToMask -CIDR 33 } | Should -Throw
        }
    }

    Describe 'Subnet Mask to CIDR Conversion' {
        It 'converts 255.255.255.0 to /24' {
            Convert-MaskToCIDR -Mask '255.255.255.0' | Should -Be 24
        }
        It 'converts 255.255.255.128 to /25' {
            Convert-MaskToCIDR -Mask '255.255.255.128' | Should -Be 25
        }
        It 'converts 255.255.254.0 to /23' {
            Convert-MaskToCIDR -Mask '255.255.254.0' | Should -Be 23
        }
        It 'rejects invalid masks' {
            { Convert-MaskToCIDR -Mask '255.255.255.1' } | Should -Throw
            { Convert-MaskToCIDR -Mask '255.0.255.0' } | Should -Throw
        }
    }

    Describe 'Subnet Calculation' {
        It 'calculates /24 network correctly' {
            $result = Get-SubnetInfo -Network '192.168.1.0' -CIDR 24
            $result.NetworkAddress | Should -Be '192.168.1.0'
            $result.BroadcastAddress | Should -Be '192.168.1.255'
            $result.SubnetMask | Should -Be '255.255.255.0'
            $result.WildcardMask | Should -Be '0.0.0.255'
            $result.FirstUsable | Should -Be '192.168.1.1'
            $result.LastUsable | Should -Be '192.168.1.254'
            $result.TotalHosts | Should -Be 254
        }

        It 'calculates /30 network correctly' {
            $result = Get-SubnetInfo -Network '10.0.0.0' -CIDR 30
            $result.NetworkAddress | Should -Be '10.0.0.0'
            $result.BroadcastAddress | Should -Be '10.0.0.3'
            $result.FirstUsable | Should -Be '10.0.0.1'
            $result.LastUsable | Should -Be '10.0.0.2'
            $result.TotalHosts | Should -Be 2
        }

        It 'calculates /31 point-to-point correctly' {
            $result = Get-SubnetInfo -Network '10.0.0.0' -CIDR 31
            $result.TotalHosts | Should -Be 2
            $result.FirstUsable | Should -Be '10.0.0.0'
            $result.LastUsable | Should -Be '10.0.0.1'
        }

        It 'calculates /32 host route correctly' {
            $result = Get-SubnetInfo -Network '10.0.0.1' -CIDR 32
            $result.TotalHosts | Should -Be 1
            $result.FirstUsable | Should -Be '10.0.0.1'
            $result.LastUsable | Should -Be '10.0.0.1'
        }

        It 'normalizes non-network addresses to network address' {
            $result = Get-SubnetInfo -Network '192.168.1.50' -CIDR 24
            $result.NetworkAddress | Should -Be '192.168.1.0'
        }
    }

    Describe 'Subnet Division' {
        It 'splits /24 into four /26 subnets' {
            $result = Split-Subnet -Network '192.168.1.0/24' -NewPrefix 26
            $result.Count | Should -Be 4
            $result[0].NetworkAddress | Should -Be '192.168.1.0'
            $result[1].NetworkAddress | Should -Be '192.168.1.64'
            $result[2].NetworkAddress | Should -Be '192.168.1.128'
            $result[3].NetworkAddress | Should -Be '192.168.1.192'
        }

        It 'splits /16 into 256 /24 subnets' {
            $result = Split-Subnet -Network '10.1.0.0/16' -NewPrefix 24
            $result.Count | Should -Be 256
        }

        It 'rejects invalid split (smaller to larger)' {
            { Split-Subnet -Network '192.168.1.0/24' -NewPrefix 16 } | Should -Throw
        }
    }

    Describe 'Supernet Aggregation' {
        It 'aggregates two /24 into one /23' {
            $subnets = @('192.168.0.0/24', '192.168.1.0/24')
            $result = Merge-Subnets -Subnets $subnets
            $result.NetworkAddress | Should -Be '192.168.0.0'
            $result.CIDR | Should -Be 23
        }

        It 'identifies non-contiguous subnets' {
            $subnets = @('192.168.0.0/24', '192.168.2.0/24')
            { Merge-Subnets -Subnets $subnets } | Should -Throw
        }
    }

    Describe 'Address Containment' {
        It 'identifies IP within subnet' {
            Test-IPInSubnet -IP '192.168.1.50' -Network '192.168.1.0/24' | Should -BeTrue
        }

        It 'identifies IP outside subnet' {
            Test-IPInSubnet -IP '192.168.2.50' -Network '192.168.1.0/24' | Should -BeFalse
        }

        It 'handles subnet boundaries correctly' {
            Test-IPInSubnet -IP '192.168.1.0' -Network '192.168.1.0/24' | Should -BeTrue  # Network addr
            Test-IPInSubnet -IP '192.168.1.255' -Network '192.168.1.0/24' | Should -BeTrue  # Broadcast
            Test-IPInSubnet -IP '192.168.0.255' -Network '192.168.1.0/24' | Should -BeFalse
        }
    }
}
```

### IP Address Utility Tests (`Modules/Tests/NetworkCalculator.IPUtils.Tests.ps1`)

```powershell
Describe 'IP Address Utilities' -Tag 'Calculator' {

    Describe 'IP Address Validation' {
        It 'validates correct IPv4 addresses' {
            Test-IPv4Address -IP '192.168.1.1' | Should -BeTrue
            Test-IPv4Address -IP '0.0.0.0' | Should -BeTrue
            Test-IPv4Address -IP '255.255.255.255' | Should -BeTrue
        }

        It 'rejects invalid IPv4 addresses' {
            Test-IPv4Address -IP '256.1.1.1' | Should -BeFalse
            Test-IPv4Address -IP '192.168.1' | Should -BeFalse
            Test-IPv4Address -IP '192.168.1.1.1' | Should -BeFalse
            Test-IPv4Address -IP 'not.an.ip.addr' | Should -BeFalse
        }
    }

    Describe 'Private/Public Classification' {
        It 'identifies RFC1918 private addresses' {
            Test-PrivateIP -IP '10.0.0.1' | Should -BeTrue
            Test-PrivateIP -IP '172.16.0.1' | Should -BeTrue
            Test-PrivateIP -IP '172.31.255.254' | Should -BeTrue
            Test-PrivateIP -IP '192.168.0.1' | Should -BeTrue
        }

        It 'identifies public addresses' {
            Test-PrivateIP -IP '8.8.8.8' | Should -BeFalse
            Test-PrivateIP -IP '1.1.1.1' | Should -BeFalse
        }

        It 'identifies link-local addresses' {
            Test-LinkLocalIP -IP '169.254.1.1' | Should -BeTrue
            Test-LinkLocalIP -IP '192.168.1.1' | Should -BeFalse
        }

        It 'identifies loopback addresses' {
            Test-LoopbackIP -IP '127.0.0.1' | Should -BeTrue
            Test-LoopbackIP -IP '127.255.255.254' | Should -BeTrue
            Test-LoopbackIP -IP '128.0.0.1' | Should -BeFalse
        }
    }

    Describe 'Format Conversion' {
        It 'converts IP to binary' {
            Convert-IPToBinary -IP '192.168.1.1' | Should -Be '11000000.10101000.00000001.00000001'
        }

        It 'converts binary to IP' {
            Convert-BinaryToIP -Binary '11000000.10101000.00000001.00000001' | Should -Be '192.168.1.1'
        }

        It 'converts IP to decimal' {
            Convert-IPToDecimal -IP '192.168.1.1' | Should -Be 3232235777
        }

        It 'converts decimal to IP' {
            Convert-DecimalToIP -Decimal 3232235777 | Should -Be '192.168.1.1'
        }
    }
}
```

### VLAN Calculator Tests (`Modules/Tests/NetworkCalculator.VLAN.Tests.ps1`)

```powershell
Describe 'VLAN Calculator' -Tag 'Calculator' {

    Describe 'VLAN Range Expansion' {
        It 'expands simple range' {
            $result = Expand-VLANRange -Range '10-15'
            $result | Should -Be @(10, 11, 12, 13, 14, 15)
        }

        It 'expands complex range' {
            $result = Expand-VLANRange -Range '10-12,20,30-32'
            $result | Should -Be @(10, 11, 12, 20, 30, 31, 32)
        }

        It 'handles single VLAN' {
            $result = Expand-VLANRange -Range '100'
            $result | Should -Be @(100)
        }

        It 'rejects invalid VLAN IDs' {
            { Expand-VLANRange -Range '0-10' } | Should -Throw
            { Expand-VLANRange -Range '4090-4096' } | Should -Throw
        }
    }

    Describe 'VLAN Range Compression' {
        It 'compresses sequential VLANs' {
            $vlans = @(10, 11, 12, 13, 14, 15)
            Compress-VLANRange -VLANs $vlans | Should -Be '10-15'
        }

        It 'compresses mixed VLANs' {
            $vlans = @(10, 11, 12, 20, 30, 31, 32)
            Compress-VLANRange -VLANs $vlans | Should -Be '10-12,20,30-32'
        }

        It 'handles single VLAN' {
            Compress-VLANRange -VLANs @(100) | Should -Be '100'
        }
    }
}
```

### Bandwidth Calculator Tests (`Modules/Tests/NetworkCalculator.Bandwidth.Tests.ps1`)

```powershell
Describe 'Bandwidth Calculator' -Tag 'Calculator' {

    Describe 'Transfer Time Calculation' {
        It 'calculates transfer time for 1GB at 1Gbps' {
            $result = Get-TransferTime -Size '1GB' -Bandwidth '1Gbps'
            $result.Seconds | Should -BeGreaterThan 7
            $result.Seconds | Should -BeLessThan 9  # ~8 seconds
        }

        It 'calculates transfer time for 100MB at 100Mbps' {
            $result = Get-TransferTime -Size '100MB' -Bandwidth '100Mbps'
            $result.Seconds | Should -BeGreaterThan 7
            $result.Seconds | Should -BeLessThan 9  # ~8 seconds
        }

        It 'accounts for link utilization' {
            $result = Get-TransferTime -Size '1GB' -Bandwidth '1Gbps' -Utilization 50
            $result.Seconds | Should -BeGreaterThan 15
        }
    }

    Describe 'Required Bandwidth Calculation' {
        It 'calculates bandwidth needed for 1GB in 60 seconds' {
            $result = Get-RequiredBandwidth -Size '1GB' -TimeSeconds 60
            $result.Mbps | Should -BeGreaterThan 130
            $result.Mbps | Should -BeLessThan 140  # ~133 Mbps
        }
    }

    Describe 'Unit Conversion' {
        It 'converts Mbps to Gbps' {
            Convert-Bandwidth -Value 1000 -FromUnit 'Mbps' -ToUnit 'Gbps' | Should -Be 1
        }

        It 'converts MB/s to Mbps' {
            Convert-Bandwidth -Value 100 -FromUnit 'MBps' -ToUnit 'Mbps' | Should -Be 800
        }
    }
}
```

### Protocol Timer Tests (`Modules/Tests/NetworkCalculator.Timers.Tests.ps1`)

```powershell
Describe 'Protocol Timer Calculators' -Tag 'Calculator' {

    Describe 'STP Timer Validation' {
        It 'validates default STP timers' {
            $result = Test-STPTimers -Hello 2 -Forward 15 -MaxAge 20
            $result.Valid | Should -BeTrue
        }

        It 'rejects invalid timer relationships' {
            $result = Test-STPTimers -Hello 5 -Forward 10 -MaxAge 15
            $result.Valid | Should -BeFalse
            $result.Reason | Should -Match 'MaxAge'
        }

        It 'calculates convergence time' {
            $result = Get-STPConvergenceTime -Forward 15 -MaxAge 20
            $result.WorstCase | Should -Be 50  # MaxAge + 2*Forward
        }
    }

    Describe 'OSPF Timer Validation' {
        It 'validates default OSPF timers' {
            $result = Test-OSPFTimers -Hello 10 -Dead 40
            $result.Valid | Should -BeTrue
        }

        It 'identifies non-standard dead interval' {
            $result = Test-OSPFTimers -Hello 10 -Dead 30
            $result.Valid | Should -BeTrue
            $result.Warning | Should -Match 'non-standard'
        }
    }
}
```

## UI Mockup Concepts

### Calculator Toolbar
```
+------------------------------------------------------------------+
| Network Calculator                    [Subnet] [VLAN] [Bandwidth]|
+------------------------------------------------------------------+
| SUBNET CALCULATOR                                                 |
| Network: [192.168.1.0   ] / [24 v]  [Calculate]                  |
+------------------------------------------------------------------+
| RESULTS                                                          |
| Network Address:    192.168.1.0                                  |
| Broadcast Address:  192.168.1.255                                |
| Subnet Mask:        255.255.255.0                                |
| Wildcard Mask:      0.0.0.255                                    |
| Usable Range:       192.168.1.1 - 192.168.1.254                  |
| Total Hosts:        254                                          |
|                                                                   |
| [Split to /26] [Copy Results] [Export]                           |
+------------------------------------------------------------------+
```

### ACL Builder
```
+------------------------------------------------------------------+
| ACL Builder                                                       |
+------------------------------------------------------------------+
| ACL Name: [BLOCK-GUEST-TO-SERVERS]                               |
+------------------------------------------------------------------+
| #  | Action | Protocol | Source           | Destination      |  |
|----|--------|----------|------------------|------------------|--|
| 10 | deny   | ip       | 10.1.50.0/24    | 10.1.10.0/24    |X |
| 20 | deny   | ip       | 10.1.50.0/24    | 10.1.20.0/24    |X |
| 30 | permit | ip       | 10.1.50.0/24    | any             |X |
+------------------------------------------------------------------+
| [+ Add Entry] [Validate] [Generate Config]                        |
+------------------------------------------------------------------+
| GENERATED CONFIG:                                                 |
| ip access-list extended BLOCK-GUEST-TO-SERVERS                    |
|  10 deny ip 10.1.50.0 0.0.0.255 10.1.10.0 0.0.0.255              |
|  20 deny ip 10.1.50.0 0.0.0.255 10.1.20.0 0.0.0.255              |
|  30 permit ip 10.1.50.0 0.0.0.255 any                            |
| [Copy to Clipboard]                                               |
+------------------------------------------------------------------+
```

## Automation hooks
- `Tools\Get-SubnetInfo.ps1 -Network 192.168.1.0/24` for subnet calculation
- `Tools\Split-Subnet.ps1 -Network 10.0.0.0/16 -NewPrefix 24` for division
- `Tools\Test-STPTimers.ps1 -Hello 2 -Forward 15 -MaxAge 20` for validation
- `Tools\New-ACLConfig.ps1 -Name BLOCK-GUEST -Rules rules.json` for ACL generation
- `Tools\Get-TransferTime.ps1 -Size 10GB -Bandwidth 1Gbps` for bandwidth calc

## Telemetry gates
- Calculator usage emits `CalculatorUsage` with calculator type
- Config generation emits `ConfigGenerated` with type and line count

## Implementation Notes

### PowerShell IP Math
```powershell
# Core IP conversion functions
function Convert-IPToUInt32 {
    param([string]$IP)
    $octets = $IP.Split('.')
    [uint32]($octets[0] * 16777216 + $octets[1] * 65536 + $octets[2] * 256 + $octets[3])
}

function Convert-UInt32ToIP {
    param([uint32]$Value)
    "{0}.{1}.{2}.{3}" -f (
        ($Value -shr 24) -band 255,
        ($Value -shr 16) -band 255,
        ($Value -shr 8) -band 255,
        $Value -band 255
    )
}

function Get-NetworkAddress {
    param([string]$IP, [int]$CIDR)
    $ipInt = Convert-IPToUInt32 $IP
    $mask = [uint32]([Math]::Pow(2, 32) - [Math]::Pow(2, 32 - $CIDR))
    Convert-UInt32ToIP ($ipInt -band $mask)
}
```

## Dependencies
- Core PowerShell math capabilities
- WPF for calculator UI
- No external network dependencies (fully offline)

## References
- `docs/plans/PlanV_IPAddressVLANPlanning.md` (IPAM integration)
- `docs/plans/PlanU_ConfigurationTemplates.md` (Config generation patterns)
- `Modules/PortReorgModule.psm1` (Script generation patterns)
