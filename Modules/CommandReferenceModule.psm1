Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Cross-vendor network command reference and translation module.
.DESCRIPTION
    Provides command lookup, translation between vendors (Cisco, Arista, Juniper, HP),
    quick reference generation, and configuration snippet support.
    Part of Plan AD - Cross-Vendor Command Reference.
#>

#region Command Database

# Supported vendors with metadata
$script:Vendors = @{
    'Cisco' = @{
        Name = 'Cisco'
        Aliases = @('Cisco IOS', 'IOS', 'IOS-XE', 'Cisco IOS-XE')
        SyntaxStyle = 'IOS'
        OSFamily = 'IOS'
    }
    'Arista' = @{
        Name = 'Arista'
        Aliases = @('Arista EOS', 'EOS')
        SyntaxStyle = 'EOS'
        OSFamily = 'EOS'
    }
    'Juniper' = @{
        Name = 'Juniper'
        Aliases = @('JunOS', 'Juniper JunOS')
        SyntaxStyle = 'JunOS'
        OSFamily = 'JunOS'
    }
    'HP' = @{
        Name = 'HP'
        Aliases = @('HP ProCurve', 'Aruba', 'HP Aruba', 'ArubaOS-Switch')
        SyntaxStyle = 'ProCurve'
        OSFamily = 'ProCurve'
    }
}

# Command categories
$script:Categories = @{
    'Show' = @{ Name = 'Show Commands'; Description = 'Display information and status' }
    'Interface' = @{ Name = 'Interface Commands'; Description = 'Interface configuration and status' }
    'Routing' = @{ Name = 'Routing Commands'; Description = 'IP routing and protocols' }
    'Switching' = @{ Name = 'Switching Commands'; Description = 'Layer 2 switching, VLANs, STP' }
    'Security' = @{ Name = 'Security Commands'; Description = 'Access lists, authentication' }
    'System' = @{ Name = 'System Commands'; Description = 'Device management and configuration' }
}

# Core command database - commands indexed by a canonical task name
$script:CommandDatabase = @{
    # Show interface commands
    'show-interface-brief' = @{
        Task = 'Show interface summary'
        Category = 'Interface'
        Commands = @{
            'Cisco' = @{
                Command = 'show ip interface brief'
                Syntax = 'show ip interface brief [<interface>]'
                Description = 'Displays brief IP interface status'
                OutputColumns = @('Interface', 'IP-Address', 'OK?', 'Method', 'Status', 'Protocol')
            }
            'Arista' = @{
                Command = 'show ip interface brief'
                Syntax = 'show ip interface brief [<interface>]'
                Description = 'Displays brief IP interface status'
                OutputColumns = @('Interface', 'IP Address', 'Status', 'Protocol')
                Notes = 'Output format similar to Cisco'
            }
            'Juniper' = @{
                Command = 'show interfaces terse'
                Syntax = 'show interfaces terse [<interface>]'
                Description = 'Displays terse interface status'
                OutputColumns = @('Interface', 'Admin', 'Link', 'Proto', 'Local', 'Remote')
            }
            'HP' = @{
                Command = 'show interface brief'
                Syntax = 'show interface brief [<interface>]'
                Description = 'Displays brief interface status'
            }
        }
    }
    'show-interface-status' = @{
        Task = 'Show interface status (L2)'
        Category = 'Interface'
        Commands = @{
            'Cisco' = @{
                Command = 'show interface status'
                Syntax = 'show interface status [<interface>]'
                Description = 'Displays interface status including VLAN, duplex, speed'
                OutputColumns = @('Port', 'Name', 'Status', 'Vlan', 'Duplex', 'Speed', 'Type')
            }
            'Arista' = @{
                Command = 'show interfaces status'
                Syntax = 'show interfaces status [<interface>]'
                Description = 'Displays interface status'
                OutputColumns = @('Port', 'Name', 'Status', 'Vlan', 'Duplex', 'Speed', 'Type')
            }
            'Juniper' = @{
                Command = 'show interfaces brief'
                Syntax = 'show interfaces brief'
                Description = 'Displays brief interface information'
            }
            'HP' = @{
                Command = 'show interfaces brief'
                Syntax = 'show interfaces brief'
                Description = 'Displays brief interface status'
            }
        }
    }
    'show-interface-detail' = @{
        Task = 'Show interface details'
        Category = 'Interface'
        Commands = @{
            'Cisco' = @{
                Command = 'show interface'
                Syntax = 'show interface <interface>'
                Description = 'Displays detailed interface information including counters'
            }
            'Arista' = @{
                Command = 'show interfaces'
                Syntax = 'show interfaces <interface>'
                Description = 'Displays detailed interface information'
            }
            'Juniper' = @{
                Command = 'show interfaces'
                Syntax = 'show interfaces <interface> extensive'
                Description = 'Displays extensive interface information'
            }
            'HP' = @{
                Command = 'show interface'
                Syntax = 'show interface <interface>'
                Description = 'Displays interface details'
            }
        }
    }
    'show-interface-counters' = @{
        Task = 'Show interface counters/statistics'
        Category = 'Interface'
        Commands = @{
            'Cisco' = @{
                Command = 'show interface counters'
                Syntax = 'show interface <interface> counters'
                Description = 'Displays interface packet counters'
            }
            'Arista' = @{
                Command = 'show interfaces counters'
                Syntax = 'show interfaces <interface> counters'
                Description = 'Displays interface counters'
            }
            'Juniper' = @{
                Command = 'show interfaces statistics'
                Syntax = 'show interfaces <interface> statistics'
                Description = 'Displays interface statistics'
            }
            'HP' = @{
                Command = 'show interface counters'
                Syntax = 'show interface <interface> counters'
                Description = 'Displays interface counters'
            }
        }
    }

    # Routing commands
    'show-ip-route' = @{
        Task = 'Show IP routing table'
        Category = 'Routing'
        Commands = @{
            'Cisco' = @{
                Command = 'show ip route'
                Syntax = 'show ip route [<prefix>] [<protocol>]'
                Description = 'Displays IP routing table'
                StatusCodes = @{
                    'C' = 'Connected'
                    'S' = 'Static'
                    'O' = 'OSPF'
                    'B' = 'BGP'
                    'D' = 'EIGRP'
                    'R' = 'RIP'
                    '*' = 'Candidate default'
                }
            }
            'Arista' = @{
                Command = 'show ip route'
                Syntax = 'show ip route [<prefix>] [<protocol>]'
                Description = 'Displays IP routing table'
                Notes = 'Very similar to Cisco IOS output'
                StatusCodes = @{
                    'C' = 'Connected'
                    'S' = 'Static'
                    'O' = 'OSPF'
                    'B' = 'BGP'
                }
            }
            'Juniper' = @{
                Command = 'show route'
                Syntax = 'show route [<prefix>] [protocol <protocol>]'
                Description = 'Displays routing table'
                Notes = 'Different output format than Cisco/Arista'
            }
            'HP' = @{
                Command = 'show ip route'
                Syntax = 'show ip route [<prefix>]'
                Description = 'Displays IP routing table'
            }
        }
    }
    'show-ip-route-summary' = @{
        Task = 'Show routing table summary'
        Category = 'Routing'
        Commands = @{
            'Cisco' = @{
                Command = 'show ip route summary'
                Syntax = 'show ip route summary'
                Description = 'Displays routing table summary by protocol'
            }
            'Arista' = @{
                Command = 'show ip route summary'
                Syntax = 'show ip route summary'
                Description = 'Displays routing table summary'
            }
            'Juniper' = @{
                Command = 'show route summary'
                Syntax = 'show route summary'
                Description = 'Displays route table summary'
            }
            'HP' = @{
                Command = 'show ip route summary'
                Syntax = 'show ip route summary'
                Description = 'Displays routing summary'
            }
        }
    }
    'show-ospf-neighbors' = @{
        Task = 'Show OSPF neighbors'
        Category = 'Routing'
        Commands = @{
            'Cisco' = @{
                Command = 'show ip ospf neighbor'
                Syntax = 'show ip ospf neighbor [<interface>]'
                Description = 'Displays OSPF neighbor adjacencies'
            }
            'Arista' = @{
                Command = 'show ip ospf neighbor'
                Syntax = 'show ip ospf neighbor [<interface>]'
                Description = 'Displays OSPF neighbors'
            }
            'Juniper' = @{
                Command = 'show ospf neighbor'
                Syntax = 'show ospf neighbor [<interface>]'
                Description = 'Displays OSPF neighbor information'
            }
            'HP' = @{
                Command = 'show ip ospf neighbor'
                Syntax = 'show ip ospf neighbor'
                Description = 'Displays OSPF neighbors'
            }
        }
    }
    'show-bgp-summary' = @{
        Task = 'Show BGP summary'
        Category = 'Routing'
        Commands = @{
            'Cisco' = @{
                Command = 'show ip bgp summary'
                Syntax = 'show ip bgp summary'
                Description = 'Displays BGP neighbor summary'
            }
            'Arista' = @{
                Command = 'show ip bgp summary'
                Syntax = 'show ip bgp summary'
                Description = 'Displays BGP summary'
            }
            'Juniper' = @{
                Command = 'show bgp summary'
                Syntax = 'show bgp summary'
                Description = 'Displays BGP summary'
            }
            'HP' = @{
                Command = 'show ip bgp summary'
                Syntax = 'show ip bgp summary'
                Description = 'Displays BGP summary'
            }
        }
    }

    # Switching commands
    'show-vlan' = @{
        Task = 'Show VLANs'
        Category = 'Switching'
        Commands = @{
            'Cisco' = @{
                Command = 'show vlan brief'
                Syntax = 'show vlan [brief] [id <vlan-id>]'
                Description = 'Displays VLAN information'
            }
            'Arista' = @{
                Command = 'show vlan'
                Syntax = 'show vlan [<vlan-id>]'
                Description = 'Displays VLAN information'
            }
            'Juniper' = @{
                Command = 'show vlans'
                Syntax = 'show vlans [<vlan-name>]'
                Description = 'Displays VLAN configuration'
            }
            'HP' = @{
                Command = 'show vlans'
                Syntax = 'show vlans [<vlan-id>]'
                Description = 'Displays VLAN information'
            }
        }
    }
    'show-mac-table' = @{
        Task = 'Show MAC address table'
        Category = 'Switching'
        Commands = @{
            'Cisco' = @{
                Command = 'show mac address-table'
                Syntax = 'show mac address-table [dynamic] [vlan <vlan-id>] [interface <interface>]'
                Description = 'Displays MAC address table'
                Notes = 'Older IOS uses "show mac-address-table"'
            }
            'Arista' = @{
                Command = 'show mac address-table'
                Syntax = 'show mac address-table [dynamic] [vlan <vlan-id>]'
                Description = 'Displays MAC address table'
            }
            'Juniper' = @{
                Command = 'show ethernet-switching table'
                Syntax = 'show ethernet-switching table [vlan <vlan-name>]'
                Description = 'Displays Ethernet switching table'
            }
            'HP' = @{
                Command = 'show mac-address'
                Syntax = 'show mac-address [vlan <vlan-id>]'
                Description = 'Displays MAC addresses'
            }
        }
    }
    'show-spanning-tree' = @{
        Task = 'Show spanning tree status'
        Category = 'Switching'
        Commands = @{
            'Cisco' = @{
                Command = 'show spanning-tree'
                Syntax = 'show spanning-tree [vlan <vlan-id>] [interface <interface>]'
                Description = 'Displays spanning tree information'
            }
            'Arista' = @{
                Command = 'show spanning-tree'
                Syntax = 'show spanning-tree [vlan <vlan-id>]'
                Description = 'Displays spanning tree status'
            }
            'Juniper' = @{
                Command = 'show spanning-tree bridge'
                Syntax = 'show spanning-tree bridge [<bridge-name>]'
                Description = 'Displays STP bridge information'
            }
            'HP' = @{
                Command = 'show spanning-tree'
                Syntax = 'show spanning-tree [vlan <vlan-id>]'
                Description = 'Displays spanning tree'
            }
        }
    }
    'show-port-channel' = @{
        Task = 'Show port-channel/LAG status'
        Category = 'Switching'
        Commands = @{
            'Cisco' = @{
                Command = 'show etherchannel summary'
                Syntax = 'show etherchannel summary'
                Description = 'Displays EtherChannel summary'
            }
            'Arista' = @{
                Command = 'show port-channel summary'
                Syntax = 'show port-channel summary'
                Description = 'Displays port-channel summary'
            }
            'Juniper' = @{
                Command = 'show lacp interfaces'
                Syntax = 'show lacp interfaces'
                Description = 'Displays LACP interface information'
            }
            'HP' = @{
                Command = 'show trunks'
                Syntax = 'show trunks'
                Description = 'Displays trunk groups'
            }
        }
    }

    # System commands
    'show-version' = @{
        Task = 'Show system version/hardware'
        Category = 'System'
        Commands = @{
            'Cisco' = @{
                Command = 'show version'
                Syntax = 'show version'
                Description = 'Displays system hardware and software version'
            }
            'Arista' = @{
                Command = 'show version'
                Syntax = 'show version'
                Description = 'Displays system version information'
            }
            'Juniper' = @{
                Command = 'show version'
                Syntax = 'show version'
                Description = 'Displays software version'
            }
            'HP' = @{
                Command = 'show version'
                Syntax = 'show version'
                Description = 'Displays firmware version'
            }
        }
    }
    'show-running-config' = @{
        Task = 'Show running configuration'
        Category = 'System'
        Commands = @{
            'Cisco' = @{
                Command = 'show running-config'
                Syntax = 'show running-config [interface <interface>] [| section <pattern>]'
                Description = 'Displays current running configuration'
            }
            'Arista' = @{
                Command = 'show running-config'
                Syntax = 'show running-config [interfaces <interface>] [section <pattern>]'
                Description = 'Displays running configuration'
            }
            'Juniper' = @{
                Command = 'show configuration'
                Syntax = 'show configuration [<hierarchy>]'
                Description = 'Displays current configuration'
                Notes = 'JunOS uses hierarchical configuration display'
            }
            'HP' = @{
                Command = 'show running-config'
                Syntax = 'show running-config'
                Description = 'Displays running configuration'
            }
        }
    }
    'show-logging' = @{
        Task = 'Show system logs'
        Category = 'System'
        Commands = @{
            'Cisco' = @{
                Command = 'show logging'
                Syntax = 'show logging [| include <pattern>]'
                Description = 'Displays system log buffer'
            }
            'Arista' = @{
                Command = 'show logging'
                Syntax = 'show logging [last <count>]'
                Description = 'Displays system logs'
            }
            'Juniper' = @{
                Command = 'show log messages'
                Syntax = 'show log messages [last <count>]'
                Description = 'Displays system messages log'
            }
            'HP' = @{
                Command = 'show logging'
                Syntax = 'show logging'
                Description = 'Displays event log'
            }
        }
    }
    'show-inventory' = @{
        Task = 'Show hardware inventory'
        Category = 'System'
        Commands = @{
            'Cisco' = @{
                Command = 'show inventory'
                Syntax = 'show inventory'
                Description = 'Displays hardware inventory with serial numbers'
            }
            'Arista' = @{
                Command = 'show inventory'
                Syntax = 'show inventory'
                Description = 'Displays hardware inventory'
            }
            'Juniper' = @{
                Command = 'show chassis hardware'
                Syntax = 'show chassis hardware'
                Description = 'Displays chassis hardware details'
            }
            'HP' = @{
                Command = 'show system information'
                Syntax = 'show system information'
                Description = 'Displays system information'
            }
        }
    }
    'show-cpu' = @{
        Task = 'Show CPU utilization'
        Category = 'System'
        Commands = @{
            'Cisco' = @{
                Command = 'show processes cpu'
                Syntax = 'show processes cpu [sorted] [history]'
                Description = 'Displays CPU utilization'
            }
            'Arista' = @{
                Command = 'show processes top once'
                Syntax = 'show processes top once'
                Description = 'Displays process CPU usage'
            }
            'Juniper' = @{
                Command = 'show chassis routing-engine'
                Syntax = 'show chassis routing-engine'
                Description = 'Displays RE CPU and memory'
            }
            'HP' = @{
                Command = 'show cpu'
                Syntax = 'show cpu'
                Description = 'Displays CPU utilization'
            }
        }
    }
    'show-memory' = @{
        Task = 'Show memory utilization'
        Category = 'System'
        Commands = @{
            'Cisco' = @{
                Command = 'show memory statistics'
                Syntax = 'show memory statistics'
                Description = 'Displays memory usage statistics'
            }
            'Arista' = @{
                Command = 'show version'
                Syntax = 'show version'
                Description = 'Memory shown in version output'
                Notes = 'Also: show processes top once'
            }
            'Juniper' = @{
                Command = 'show chassis routing-engine'
                Syntax = 'show chassis routing-engine'
                Description = 'Displays RE memory usage'
            }
            'HP' = @{
                Command = 'show system information'
                Syntax = 'show system information'
                Description = 'Memory in system info'
            }
        }
    }

    # ARP and neighbor discovery
    'show-arp' = @{
        Task = 'Show ARP table'
        Category = 'Routing'
        Commands = @{
            'Cisco' = @{
                Command = 'show ip arp'
                Syntax = 'show ip arp [<ip-address>] [<interface>]'
                Description = 'Displays ARP cache'
            }
            'Arista' = @{
                Command = 'show ip arp'
                Syntax = 'show ip arp [<ip-address>]'
                Description = 'Displays ARP table'
            }
            'Juniper' = @{
                Command = 'show arp'
                Syntax = 'show arp [hostname <host>]'
                Description = 'Displays ARP table'
            }
            'HP' = @{
                Command = 'show arp'
                Syntax = 'show arp [<ip-address>]'
                Description = 'Displays ARP cache'
            }
        }
    }
    'show-lldp-neighbors' = @{
        Task = 'Show LLDP neighbors'
        Category = 'Interface'
        Commands = @{
            'Cisco' = @{
                Command = 'show lldp neighbors'
                Syntax = 'show lldp neighbors [detail]'
                Description = 'Displays LLDP neighbor information'
            }
            'Arista' = @{
                Command = 'show lldp neighbors'
                Syntax = 'show lldp neighbors [<interface>]'
                Description = 'Displays LLDP neighbors'
            }
            'Juniper' = @{
                Command = 'show lldp neighbors'
                Syntax = 'show lldp neighbors'
                Description = 'Displays LLDP neighbor information'
            }
            'HP' = @{
                Command = 'show lldp info remote-device'
                Syntax = 'show lldp info remote-device'
                Description = 'Displays LLDP remote device info'
            }
        }
    }
    'show-cdp-neighbors' = @{
        Task = 'Show CDP neighbors'
        Category = 'Interface'
        Commands = @{
            'Cisco' = @{
                Command = 'show cdp neighbors'
                Syntax = 'show cdp neighbors [detail]'
                Description = 'Displays CDP neighbor information'
            }
            'Arista' = @{
                Command = 'show lldp neighbors'
                Syntax = 'show lldp neighbors'
                Description = 'Arista uses LLDP (CDP receiver only)'
                Notes = 'Arista can receive CDP but primarily uses LLDP'
            }
            'Juniper' = @{
                Command = 'N/A'
                Description = 'Juniper does not support CDP'
                Notes = 'Use LLDP instead: show lldp neighbors'
            }
            'HP' = @{
                Command = 'show cdp neighbors'
                Syntax = 'show cdp neighbors [detail]'
                Description = 'Displays CDP neighbors'
            }
        }
    }
}

# Configuration snippets
$script:ConfigSnippets = @{
    'vlan-create' = @{
        Task = 'Create VLAN'
        Category = 'Switching'
        Variables = @('vlan_id', 'vlan_name')
        Snippets = @{
            'Cisco' = @'
vlan {{vlan_id}}
 name {{vlan_name}}
'@
            'Arista' = @'
vlan {{vlan_id}}
   name {{vlan_name}}
'@
            'Juniper' = @'
set vlans {{vlan_name}} vlan-id {{vlan_id}}
'@
            'HP' = @'
vlan {{vlan_id}}
 name "{{vlan_name}}"
'@
        }
    }
    'interface-access-port' = @{
        Task = 'Configure access port'
        Category = 'Switching'
        Variables = @('interface', 'vlan_id', 'description')
        Snippets = @{
            'Cisco' = @'
interface {{interface}}
 description {{description}}
 switchport mode access
 switchport access vlan {{vlan_id}}
 spanning-tree portfast
'@
            'Arista' = @'
interface {{interface}}
   description {{description}}
   switchport mode access
   switchport access vlan {{vlan_id}}
   spanning-tree portfast
'@
            'Juniper' = @'
set interfaces {{interface}} description "{{description}}"
set interfaces {{interface}} unit 0 family ethernet-switching vlan members {{vlan_id}}
'@
            'HP' = @'
interface {{interface}}
 name "{{description}}"
 untagged vlan {{vlan_id}}
 spanning-tree admin-edge-port
'@
        }
    }
    'interface-trunk-port' = @{
        Task = 'Configure trunk port'
        Category = 'Switching'
        Variables = @('interface', 'allowed_vlans', 'native_vlan', 'description')
        Snippets = @{
            'Cisco' = @'
interface {{interface}}
 description {{description}}
 switchport trunk encapsulation dot1q
 switchport mode trunk
 switchport trunk native vlan {{native_vlan}}
 switchport trunk allowed vlan {{allowed_vlans}}
'@
            'Arista' = @'
interface {{interface}}
   description {{description}}
   switchport mode trunk
   switchport trunk native vlan {{native_vlan}}
   switchport trunk allowed vlan {{allowed_vlans}}
'@
            'Juniper' = @'
set interfaces {{interface}} description "{{description}}"
set interfaces {{interface}} native-vlan-id {{native_vlan}}
set interfaces {{interface}} unit 0 family ethernet-switching interface-mode trunk
set interfaces {{interface}} unit 0 family ethernet-switching vlan members [{{allowed_vlans}}]
'@
            'HP' = @'
interface {{interface}}
 name "{{description}}"
 tagged vlan {{allowed_vlans}}
 untagged vlan {{native_vlan}}
'@
        }
    }
}

#endregion

#region Helper Functions

function Resolve-VendorName {
    <#
    .SYNOPSIS
        Resolves vendor alias to canonical vendor name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Vendor
    )

    # Direct match
    if ($script:Vendors.ContainsKey($Vendor)) {
        return $Vendor
    }

    # Check aliases
    foreach ($v in $script:Vendors.Keys) {
        $info = $script:Vendors[$v]
        if ($info.Aliases -contains $Vendor) {
            return $v
        }
    }

    # Fuzzy match
    $vendorLower = $Vendor.ToLower()
    foreach ($v in $script:Vendors.Keys) {
        if ($v.ToLower() -eq $vendorLower) {
            return $v
        }
        foreach ($alias in $script:Vendors[$v].Aliases) {
            if ($alias.ToLower() -eq $vendorLower) {
                return $v
            }
        }
    }

    return $null
}

function Expand-TemplateVariables {
    <#
    .SYNOPSIS
        Expands {{variable}} placeholders in a template string.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Template,

        [Parameter(Mandatory)]
        [hashtable]$Variables
    )

    $result = $Template
    foreach ($key in $Variables.Keys) {
        $pattern = "\{\{$key\}\}"
        $result = $result -replace $pattern, $Variables[$key]
    }
    return $result
}

#endregion

#region Public Functions

function Get-SupportedVendors {
    <#
    .SYNOPSIS
        Returns list of supported vendor names.
    .EXAMPLE
        Get-SupportedVendors
    #>
    [CmdletBinding()]
    param()

    return @($script:Vendors.Keys | Sort-Object)
}

function Get-VendorInfo {
    <#
    .SYNOPSIS
        Returns metadata for a specific vendor.
    .EXAMPLE
        Get-VendorInfo -Name 'Cisco'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $resolved = Resolve-VendorName -Vendor $Name
    if (-not $resolved) {
        Write-Warning "Unknown vendor: $Name"
        return $null
    }

    return [PSCustomObject]@{
        Name = $script:Vendors[$resolved].Name
        Aliases = $script:Vendors[$resolved].Aliases
        SyntaxStyle = $script:Vendors[$resolved].SyntaxStyle
        OSFamily = $script:Vendors[$resolved].OSFamily
    }
}

function Get-CommandCategories {
    <#
    .SYNOPSIS
        Returns available command categories.
    #>
    [CmdletBinding()]
    param()

    $script:Categories.Keys | ForEach-Object {
        [PSCustomObject]@{
            Name = $_
            Description = $script:Categories[$_].Description
        }
    }
}

function Get-NetworkCommand {
    <#
    .SYNOPSIS
        Retrieves command information for a specific vendor.
    .EXAMPLE
        Get-NetworkCommand -Command 'show ip route' -Vendor 'Cisco'
    .EXAMPLE
        Get-NetworkCommand -Command 'show interfaces' -Vendor 'Arista'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [Parameter(Mandatory)]
        [string]$Vendor
    )

    $resolvedVendor = Resolve-VendorName -Vendor $Vendor
    if (-not $resolvedVendor) {
        Write-Warning "Unknown vendor: $Vendor"
        return $null
    }

    $commandLower = $Command.ToLower().Trim()

    foreach ($taskKey in $script:CommandDatabase.Keys) {
        $entry = $script:CommandDatabase[$taskKey]
        if ($entry.Commands.ContainsKey($resolvedVendor)) {
            $vendorCmd = $entry.Commands[$resolvedVendor]
            $cmdText = $vendorCmd.Command.ToLower()

            if ($cmdText -eq $commandLower -or $commandLower.StartsWith($cmdText)) {
                return [PSCustomObject]@{
                    TaskKey = $taskKey
                    Task = $entry.Task
                    Category = $entry.Category
                    Vendor = $resolvedVendor
                    Command = $vendorCmd.Command
                    Syntax = if ($vendorCmd.ContainsKey('Syntax')) { $vendorCmd.Syntax } else { $null }
                    Description = if ($vendorCmd.ContainsKey('Description')) { $vendorCmd.Description } else { $null }
                    OutputColumns = if ($vendorCmd.ContainsKey('OutputColumns')) { $vendorCmd.OutputColumns } else { $null }
                    StatusCodes = if ($vendorCmd.ContainsKey('StatusCodes')) { $vendorCmd.StatusCodes } else { $null }
                    Notes = if ($vendorCmd.ContainsKey('Notes')) { $vendorCmd.Notes } else { $null }
                }
            }
        }
    }

    return $null
}

function Search-NetworkCommands {
    <#
    .SYNOPSIS
        Searches commands by keyword. Returns all commands if keyword is empty.
    .EXAMPLE
        Search-NetworkCommands -Keyword 'interface'
        Search-NetworkCommands -Keyword 'route' -Vendor 'Cisco'
        Search-NetworkCommands  # Returns all commands
    #>
    [CmdletBinding()]
    param(
        [string]$Keyword,

        [string]$Vendor,

        [string]$Category
    )

    $results = @()
    $keywordLower = if ([string]::IsNullOrWhiteSpace($Keyword)) { '' } else { $Keyword.ToLower() }
    $matchAll = [string]::IsNullOrWhiteSpace($Keyword)
    $resolvedVendor = if ($Vendor) { Resolve-VendorName -Vendor $Vendor } else { $null }

    foreach ($taskKey in $script:CommandDatabase.Keys) {
        $entry = $script:CommandDatabase[$taskKey]

        # Category filter
        if ($Category -and $entry.Category -ne $Category) { continue }

        # Search in task description
        $matchesTask = $entry.Task.ToLower().Contains($keywordLower)

        foreach ($v in $entry.Commands.Keys) {
            # Vendor filter
            if ($resolvedVendor -and $v -ne $resolvedVendor) { continue }

            $vendorCmd = $entry.Commands[$v]
            $matchesCommand = $vendorCmd.Command.ToLower().Contains($keywordLower)
            $matchesDesc = $vendorCmd.Description -and $vendorCmd.Description.ToLower().Contains($keywordLower)

            if ($matchAll -or $matchesTask -or $matchesCommand -or $matchesDesc) {
                $results += [PSCustomObject]@{
                    TaskKey = $taskKey
                    Task = $entry.Task
                    Category = $entry.Category
                    Vendor = $v
                    Command = $vendorCmd.Command
                    Syntax = if ($vendorCmd.ContainsKey('Syntax')) { $vendorCmd.Syntax } else { $null }
                    Description = if ($vendorCmd.ContainsKey('Description')) { $vendorCmd.Description } else { $null }
                }
            }
        }
    }

    return $results
}

function Find-CommandByTask {
    <#
    .SYNOPSIS
        Finds commands by task description.
    .EXAMPLE
        Find-CommandByTask -Task 'check port status'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Task
    )

    $taskLower = $Task.ToLower()
    $keywords = $taskLower -split '\s+'

    $results = @()
    foreach ($taskKey in $script:CommandDatabase.Keys) {
        $entry = $script:CommandDatabase[$taskKey]
        $taskDescLower = $entry.Task.ToLower()

        $matchCount = 0
        foreach ($kw in $keywords) {
            if ($taskDescLower.Contains($kw) -or $taskKey.Contains($kw)) {
                $matchCount++
            }
        }

        if ($matchCount -gt 0) {
            $vendors = @()
            foreach ($v in $entry.Commands.Keys) {
                $vendors += [PSCustomObject]@{
                    Vendor = $v
                    Command = $entry.Commands[$v].Command
                }
            }

            $results += [PSCustomObject]@{
                TaskKey = $taskKey
                Task = $entry.Task
                Category = $entry.Category
                MatchScore = $matchCount
                Vendors = $vendors
            }
        }
    }

    return $results | Sort-Object -Property MatchScore -Descending
}

function Convert-NetworkCommand {
    <#
    .SYNOPSIS
        Translates a command from one vendor to another.
    .EXAMPLE
        Convert-NetworkCommand -Command 'show ip route' -FromVendor 'Cisco' -ToVendor 'Juniper'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [Parameter(Mandatory)]
        [string]$FromVendor,

        [Parameter(Mandatory)]
        [string]$ToVendor
    )

    $resolvedFrom = Resolve-VendorName -Vendor $FromVendor
    $resolvedTo = Resolve-VendorName -Vendor $ToVendor

    if (-not $resolvedFrom) {
        return [PSCustomObject]@{
            Success = $false
            Error = "Unknown source vendor: $FromVendor"
        }
    }
    if (-not $resolvedTo) {
        return [PSCustomObject]@{
            Success = $false
            Error = "Unknown target vendor: $ToVendor"
        }
    }

    # Find matching command
    $sourceCmd = Get-NetworkCommand -Command $Command -Vendor $resolvedFrom
    if (-not $sourceCmd) {
        return [PSCustomObject]@{
            Success = $false
            SourceCommand = $Command
            FromVendor = $resolvedFrom
            ToVendor = $resolvedTo
            HasEquivalent = $false
            Error = "Command not found in database for $resolvedFrom"
        }
    }

    # Get target vendor command
    $entry = $script:CommandDatabase[$sourceCmd.TaskKey]
    if (-not $entry.Commands.ContainsKey($resolvedTo)) {
        return [PSCustomObject]@{
            Success = $false
            SourceCommand = $Command
            FromVendor = $resolvedFrom
            ToVendor = $resolvedTo
            HasEquivalent = $false
            Task = $entry.Task
            Error = "No equivalent command for $resolvedTo"
        }
    }

    $targetCmd = $entry.Commands[$resolvedTo]
    $notes = @()

    if ($targetCmd.Command -eq 'N/A') {
        return [PSCustomObject]@{
            Success = $false
            SourceCommand = $sourceCmd.Command
            FromVendor = $resolvedFrom
            ToVendor = $resolvedTo
            HasEquivalent = $false
            Task = $entry.Task
            Notes = if ($targetCmd.ContainsKey('Notes')) { $targetCmd.Notes } else { $null }
        }
    }

    # Build notes
    if ($sourceCmd.Command -eq $targetCmd.Command) {
        $notes += "Command syntax is identical between $resolvedFrom and $resolvedTo"
    } else {
        $notes += "Syntax differs between vendors"
    }
    if ($targetCmd.ContainsKey('Notes') -and $targetCmd.Notes) {
        $notes += $targetCmd.Notes
    }

    return [PSCustomObject]@{
        Success = $true
        SourceCommand = $sourceCmd.Command
        TranslatedCommand = $targetCmd.Command
        FromVendor = $resolvedFrom
        ToVendor = $resolvedTo
        HasEquivalent = $true
        Task = $entry.Task
        Category = $entry.Category
        Syntax = if ($targetCmd.ContainsKey('Syntax')) { $targetCmd.Syntax } else { $null }
        Description = if ($targetCmd.ContainsKey('Description')) { $targetCmd.Description } else { $null }
        Notes = ($notes -join '; ')
    }
}

function Get-CommandComparison {
    <#
    .SYNOPSIS
        Gets side-by-side comparison of commands across vendors.
    .EXAMPLE
        Get-CommandComparison -Task 'show routing table' -Vendors @('Cisco', 'Arista', 'Juniper')
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Task,

        [string[]]$Vendors = @('Cisco', 'Arista', 'Juniper', 'HP')
    )

    $matches = Find-CommandByTask -Task $Task

    $results = @()
    foreach ($match in $matches) {
        $row = [ordered]@{
            Task = $match.Task
            Category = $match.Category
        }

        $entry = $script:CommandDatabase[$match.TaskKey]
        foreach ($v in $Vendors) {
            $resolved = Resolve-VendorName -Vendor $v
            if ($resolved -and $entry.Commands.ContainsKey($resolved)) {
                $row[$resolved] = $entry.Commands[$resolved].Command
            } else {
                $row[$resolved] = 'N/A'
            }
        }

        $results += [PSCustomObject]$row
    }

    return $results
}

function Get-ConfigSnippet {
    <#
    .SYNOPSIS
        Retrieves a configuration snippet template.
    .EXAMPLE
        Get-ConfigSnippet -Task 'Create VLAN' -Vendor 'Cisco'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Task,

        [Parameter(Mandatory)]
        [string]$Vendor
    )

    $resolvedVendor = Resolve-VendorName -Vendor $Vendor
    if (-not $resolvedVendor) {
        Write-Warning "Unknown vendor: $Vendor"
        return $null
    }

    $taskLower = $Task.ToLower()
    foreach ($key in $script:ConfigSnippets.Keys) {
        $snippet = $script:ConfigSnippets[$key]
        if ($snippet.Task.ToLower().Contains($taskLower) -or $key.Contains($taskLower)) {
            if ($snippet.Snippets.ContainsKey($resolvedVendor)) {
                return [PSCustomObject]@{
                    TaskKey = $key
                    Task = $snippet.Task
                    Category = $snippet.Category
                    Vendor = $resolvedVendor
                    Variables = $snippet.Variables
                    Template = $snippet.Snippets[$resolvedVendor]
                }
            }
        }
    }

    return $null
}

function Expand-ConfigSnippet {
    <#
    .SYNOPSIS
        Expands a configuration snippet with variable values.
    .EXAMPLE
        $snippet = Get-ConfigSnippet -Task 'VLAN' -Vendor 'Cisco'
        Expand-ConfigSnippet -Snippet $snippet -Variables @{ vlan_id = 100; vlan_name = 'Users' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Snippet,

        [Parameter(Mandatory)]
        [hashtable]$Variables
    )

    return Expand-TemplateVariables -Template $Snippet.Template -Variables $Variables
}

function Get-ConfigSnippets {
    <#
    .SYNOPSIS
        Lists available configuration snippets.
    .EXAMPLE
        Get-ConfigSnippets
        Get-ConfigSnippets -Category 'Switching' -Vendor 'Arista'
    #>
    [CmdletBinding()]
    param(
        [string]$Category,
        [string]$Vendor
    )

    $resolvedVendor = if ($Vendor) { Resolve-VendorName -Vendor $Vendor } else { $null }

    $results = @()
    foreach ($key in $script:ConfigSnippets.Keys) {
        $snippet = $script:ConfigSnippets[$key]

        if ($Category -and $snippet.Category -ne $Category) { continue }

        $vendors = @($snippet.Snippets.Keys)
        if ($resolvedVendor -and $vendors -notcontains $resolvedVendor) { continue }

        $results += [PSCustomObject]@{
            TaskKey = $key
            TaskName = $snippet.Task
            Category = $snippet.Category
            Variables = $snippet.Variables
            Vendors = $vendors
        }
    }

    return $results
}

function Test-ConfigSnippet {
    <#
    .SYNOPSIS
        Validates that all required variables are provided for a snippet.
    .EXAMPLE
        $snippet = Get-ConfigSnippet -Task 'VLAN' -Vendor 'Cisco'
        Test-ConfigSnippet -Snippet $snippet -Variables @{ vlan_id = 100 }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Snippet,

        [Parameter(Mandatory)]
        [hashtable]$Variables
    )

    $missing = @()
    foreach ($var in $Snippet.Variables) {
        if (-not $Variables.ContainsKey($var)) {
            $missing += $var
        }
    }

    return [PSCustomObject]@{
        IsValid = ($missing.Count -eq 0)
        MissingVariables = $missing
        ProvidedVariables = @($Variables.Keys)
        RequiredVariables = $Snippet.Variables
    }
}

function Get-OutputFormat {
    <#
    .SYNOPSIS
        Gets output format documentation for a command.
    .EXAMPLE
        Get-OutputFormat -Command 'show interface status' -Vendor 'Cisco'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [Parameter(Mandatory)]
        [string]$Vendor
    )

    $cmd = Get-NetworkCommand -Command $Command -Vendor $Vendor
    if (-not $cmd) {
        return $null
    }

    return [PSCustomObject]@{
        Command = $cmd.Command
        Vendor = $cmd.Vendor
        Columns = $cmd.OutputColumns
        StatusCodes = $cmd.StatusCodes
        Notes = $cmd.Notes
    }
}

function Get-StatusCodes {
    <#
    .SYNOPSIS
        Gets status code definitions for a command.
    .EXAMPLE
        Get-StatusCodes -Command 'show ip route' -Vendor 'Cisco'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [Parameter(Mandatory)]
        [string]$Vendor
    )

    $cmd = Get-NetworkCommand -Command $Command -Vendor $Vendor
    if (-not $cmd -or -not $cmd.StatusCodes) {
        return @{}
    }

    return $cmd.StatusCodes
}

#endregion

Export-ModuleMember -Function @(
    'Get-SupportedVendors',
    'Get-VendorInfo',
    'Get-CommandCategories',
    'Get-NetworkCommand',
    'Search-NetworkCommands',
    'Find-CommandByTask',
    'Convert-NetworkCommand',
    'Get-CommandComparison',
    'Get-ConfigSnippet',
    'Expand-ConfigSnippet',
    'Get-ConfigSnippets',
    'Test-ConfigSnippet',
    'Get-OutputFormat',
    'Get-StatusCodes'
)
