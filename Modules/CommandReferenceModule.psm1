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

    # Security commands
    'show-access-lists' = @{
        Task = 'Show access control lists'
        Category = 'Security'
        Commands = @{
            'Cisco' = @{
                Command = 'show access-lists'
                Syntax = 'show access-lists [<acl-name>]'
                Description = 'Displays all access lists or specific ACL'
            }
            'Arista' = @{
                Command = 'show ip access-lists'
                Syntax = 'show ip access-lists [<acl-name>]'
                Description = 'Displays IP access lists'
            }
            'Juniper' = @{
                Command = 'show firewall filter'
                Syntax = 'show firewall filter <filter-name>'
                Description = 'Displays firewall filter configuration'
            }
            'HP' = @{
                Command = 'show access-list'
                Syntax = 'show access-list <acl-id>'
                Description = 'Displays access list'
            }
        }
    }
    'show-port-security' = @{
        Task = 'Show port security status'
        Category = 'Security'
        Commands = @{
            'Cisco' = @{
                Command = 'show port-security'
                Syntax = 'show port-security [interface <interface>] [address]'
                Description = 'Displays port security settings and violations'
            }
            'Arista' = @{
                Command = 'show port-security'
                Syntax = 'show port-security [interface <interface>]'
                Description = 'Displays port security configuration'
            }
            'Juniper' = @{
                Command = 'show ethernet-switching port-security'
                Syntax = 'show ethernet-switching port-security'
                Description = 'Displays port security information'
            }
            'HP' = @{
                Command = 'show port-security'
                Syntax = 'show port-security [<port>]'
                Description = 'Displays port security status'
            }
        }
    }
    'show-aaa' = @{
        Task = 'Show AAA configuration'
        Category = 'Security'
        Commands = @{
            'Cisco' = @{
                Command = 'show aaa servers'
                Syntax = 'show aaa servers'
                Description = 'Displays AAA server statistics'
            }
            'Arista' = @{
                Command = 'show aaa'
                Syntax = 'show aaa'
                Description = 'Displays AAA configuration'
            }
            'Juniper' = @{
                Command = 'show system aaa'
                Syntax = 'show system aaa'
                Description = 'Displays AAA information'
            }
            'HP' = @{
                Command = 'show authentication'
                Syntax = 'show authentication'
                Description = 'Displays authentication configuration'
            }
        }
    }
    'show-dot1x' = @{
        Task = 'Show 802.1X status'
        Category = 'Security'
        Commands = @{
            'Cisco' = @{
                Command = 'show dot1x all'
                Syntax = 'show dot1x all [details]'
                Description = 'Displays 802.1X authentication status'
            }
            'Arista' = @{
                Command = 'show dot1x'
                Syntax = 'show dot1x [interface <interface>]'
                Description = 'Displays 802.1X status'
            }
            'Juniper' = @{
                Command = 'show dot1x interface'
                Syntax = 'show dot1x interface'
                Description = 'Displays 802.1X interface status'
            }
            'HP' = @{
                Command = 'show port-access authenticator'
                Syntax = 'show port-access authenticator [<port>]'
                Description = 'Displays 802.1X authenticator status'
            }
        }
    }
    'show-users' = @{
        Task = 'Show logged in users'
        Category = 'Security'
        Commands = @{
            'Cisco' = @{
                Command = 'show users'
                Syntax = 'show users'
                Description = 'Displays users logged into the device'
            }
            'Arista' = @{
                Command = 'show users'
                Syntax = 'show users'
                Description = 'Displays logged in users'
            }
            'Juniper' = @{
                Command = 'show system users'
                Syntax = 'show system users'
                Description = 'Displays logged in users'
            }
            'HP' = @{
                Command = 'show users'
                Syntax = 'show users'
                Description = 'Displays active sessions'
            }
        }
    }

    # Management commands
    'show-ntp' = @{
        Task = 'Show NTP status'
        Category = 'System'
        Commands = @{
            'Cisco' = @{
                Command = 'show ntp status'
                Syntax = 'show ntp status'
                Description = 'Displays NTP synchronization status'
            }
            'Arista' = @{
                Command = 'show ntp status'
                Syntax = 'show ntp status'
                Description = 'Displays NTP status'
            }
            'Juniper' = @{
                Command = 'show ntp status'
                Syntax = 'show ntp status'
                Description = 'Displays NTP status'
            }
            'HP' = @{
                Command = 'show ntp status'
                Syntax = 'show ntp status'
                Description = 'Displays NTP status'
            }
        }
    }
    'show-ntp-associations' = @{
        Task = 'Show NTP peers/associations'
        Category = 'System'
        Commands = @{
            'Cisco' = @{
                Command = 'show ntp associations'
                Syntax = 'show ntp associations [detail]'
                Description = 'Displays NTP peer associations'
            }
            'Arista' = @{
                Command = 'show ntp associations'
                Syntax = 'show ntp associations'
                Description = 'Displays NTP associations'
            }
            'Juniper' = @{
                Command = 'show ntp associations'
                Syntax = 'show ntp associations'
                Description = 'Displays NTP associations'
            }
            'HP' = @{
                Command = 'show ntp associations'
                Syntax = 'show ntp associations'
                Description = 'Displays NTP associations'
            }
        }
    }
    'show-snmp' = @{
        Task = 'Show SNMP configuration'
        Category = 'System'
        Commands = @{
            'Cisco' = @{
                Command = 'show snmp'
                Syntax = 'show snmp [community | host | user]'
                Description = 'Displays SNMP configuration'
            }
            'Arista' = @{
                Command = 'show snmp'
                Syntax = 'show snmp [community | host]'
                Description = 'Displays SNMP settings'
            }
            'Juniper' = @{
                Command = 'show snmp statistics'
                Syntax = 'show snmp statistics'
                Description = 'Displays SNMP statistics'
            }
            'HP' = @{
                Command = 'show snmp-server'
                Syntax = 'show snmp-server'
                Description = 'Displays SNMP configuration'
            }
        }
    }
    'show-clock' = @{
        Task = 'Show system clock'
        Category = 'System'
        Commands = @{
            'Cisco' = @{
                Command = 'show clock'
                Syntax = 'show clock [detail]'
                Description = 'Displays current system time'
            }
            'Arista' = @{
                Command = 'show clock'
                Syntax = 'show clock'
                Description = 'Displays system time'
            }
            'Juniper' = @{
                Command = 'show system uptime'
                Syntax = 'show system uptime'
                Description = 'Displays system time and uptime'
            }
            'HP' = @{
                Command = 'show time'
                Syntax = 'show time'
                Description = 'Displays current time'
            }
        }
    }
    'show-boot' = @{
        Task = 'Show boot configuration'
        Category = 'System'
        Commands = @{
            'Cisco' = @{
                Command = 'show boot'
                Syntax = 'show boot'
                Description = 'Displays boot variable settings'
            }
            'Arista' = @{
                Command = 'show boot-config'
                Syntax = 'show boot-config'
                Description = 'Displays boot configuration'
            }
            'Juniper' = @{
                Command = 'show system boot-messages'
                Syntax = 'show system boot-messages'
                Description = 'Displays boot messages'
            }
            'HP' = @{
                Command = 'show flash'
                Syntax = 'show flash'
                Description = 'Displays flash contents and boot image'
            }
        }
    }
    'show-environment' = @{
        Task = 'Show environmental status (fans, power, temp)'
        Category = 'System'
        Commands = @{
            'Cisco' = @{
                Command = 'show environment'
                Syntax = 'show environment [all | fan | power | temperature]'
                Description = 'Displays environmental status'
            }
            'Arista' = @{
                Command = 'show environment all'
                Syntax = 'show environment [all | cooling | power | temperature]'
                Description = 'Displays environmental information'
            }
            'Juniper' = @{
                Command = 'show chassis environment'
                Syntax = 'show chassis environment'
                Description = 'Displays chassis environmental status'
            }
            'HP' = @{
                Command = 'show system fans'
                Syntax = 'show system [fans | power-supply | temperature]'
                Description = 'Displays system environmental data'
            }
        }
    }

    # High Availability commands
    'show-hsrp' = @{
        Task = 'Show HSRP/standby status'
        Category = 'Routing'
        Commands = @{
            'Cisco' = @{
                Command = 'show standby'
                Syntax = 'show standby [brief] [<interface>]'
                Description = 'Displays HSRP status'
            }
            'Arista' = @{
                Command = 'show vrrp'
                Syntax = 'show vrrp [brief]'
                Description = 'Arista uses VRRP instead of HSRP'
                Notes = 'Arista does not support HSRP, use VRRP'
            }
            'Juniper' = @{
                Command = 'show vrrp'
                Syntax = 'show vrrp [brief]'
                Description = 'Displays VRRP status'
            }
            'HP' = @{
                Command = 'show vrrp'
                Syntax = 'show vrrp [<vrid>]'
                Description = 'Displays VRRP status'
            }
        }
    }
    'show-vrrp' = @{
        Task = 'Show VRRP status'
        Category = 'Routing'
        Commands = @{
            'Cisco' = @{
                Command = 'show vrrp'
                Syntax = 'show vrrp [brief] [<interface>]'
                Description = 'Displays VRRP status'
            }
            'Arista' = @{
                Command = 'show vrrp'
                Syntax = 'show vrrp [brief]'
                Description = 'Displays VRRP status'
            }
            'Juniper' = @{
                Command = 'show vrrp'
                Syntax = 'show vrrp [brief | detail]'
                Description = 'Displays VRRP information'
            }
            'HP' = @{
                Command = 'show vrrp'
                Syntax = 'show vrrp [<vrid>]'
                Description = 'Displays VRRP status'
            }
        }
    }

    # More interface commands
    'show-interface-description' = @{
        Task = 'Show interface descriptions'
        Category = 'Interface'
        Commands = @{
            'Cisco' = @{
                Command = 'show interface description'
                Syntax = 'show interface description'
                Description = 'Displays interface descriptions'
            }
            'Arista' = @{
                Command = 'show interfaces description'
                Syntax = 'show interfaces description'
                Description = 'Displays interface descriptions'
            }
            'Juniper' = @{
                Command = 'show interfaces descriptions'
                Syntax = 'show interfaces descriptions'
                Description = 'Displays interface descriptions'
            }
            'HP' = @{
                Command = 'show name'
                Syntax = 'show name'
                Description = 'Displays port names'
            }
        }
    }
    'show-interface-trunk' = @{
        Task = 'Show trunk port information'
        Category = 'Switching'
        Commands = @{
            'Cisco' = @{
                Command = 'show interface trunk'
                Syntax = 'show interface trunk'
                Description = 'Displays trunk port status and VLANs'
            }
            'Arista' = @{
                Command = 'show interfaces trunk'
                Syntax = 'show interfaces trunk'
                Description = 'Displays trunk information'
            }
            'Juniper' = @{
                Command = 'show vlans extensive'
                Syntax = 'show vlans extensive'
                Description = 'Displays VLAN trunk information'
            }
            'HP' = @{
                Command = 'show trunks'
                Syntax = 'show trunks'
                Description = 'Displays trunk groups'
            }
        }
    }
    'show-interface-switchport' = @{
        Task = 'Show switchport configuration'
        Category = 'Switching'
        Commands = @{
            'Cisco' = @{
                Command = 'show interface switchport'
                Syntax = 'show interface <interface> switchport'
                Description = 'Displays switchport configuration details'
            }
            'Arista' = @{
                Command = 'show interfaces switchport'
                Syntax = 'show interfaces <interface> switchport'
                Description = 'Displays switchport settings'
            }
            'Juniper' = @{
                Command = 'show ethernet-switching interface'
                Syntax = 'show ethernet-switching interface <interface>'
                Description = 'Displays ethernet switching interface'
            }
            'HP' = @{
                Command = 'show vlans ports'
                Syntax = 'show vlans ports <port>'
                Description = 'Displays port VLAN membership'
            }
        }
    }
    'show-interface-transceiver' = @{
        Task = 'Show transceiver/SFP information'
        Category = 'Interface'
        Commands = @{
            'Cisco' = @{
                Command = 'show interface transceiver'
                Syntax = 'show interface transceiver [<interface>]'
                Description = 'Displays transceiver DOM information'
            }
            'Arista' = @{
                Command = 'show interfaces transceiver'
                Syntax = 'show interfaces <interface> transceiver'
                Description = 'Displays transceiver details'
            }
            'Juniper' = @{
                Command = 'show interfaces diagnostics optics'
                Syntax = 'show interfaces diagnostics optics <interface>'
                Description = 'Displays optical diagnostics'
            }
            'HP' = @{
                Command = 'show interfaces transceiver'
                Syntax = 'show interfaces transceiver [<port>]'
                Description = 'Displays transceiver information'
            }
        }
    }

    # More routing commands
    'show-ip-protocols' = @{
        Task = 'Show routing protocols'
        Category = 'Routing'
        Commands = @{
            'Cisco' = @{
                Command = 'show ip protocols'
                Syntax = 'show ip protocols'
                Description = 'Displays routing protocol information'
            }
            'Arista' = @{
                Command = 'show ip protocols'
                Syntax = 'show ip protocols'
                Description = 'Displays routing protocol settings'
            }
            'Juniper' = @{
                Command = 'show route protocol'
                Syntax = 'show route protocol <protocol>'
                Description = 'Displays routes by protocol'
            }
            'HP' = @{
                Command = 'show ip'
                Syntax = 'show ip'
                Description = 'Displays IP configuration'
            }
        }
    }
    'show-ip-ospf' = @{
        Task = 'Show OSPF configuration'
        Category = 'Routing'
        Commands = @{
            'Cisco' = @{
                Command = 'show ip ospf'
                Syntax = 'show ip ospf [<process-id>]'
                Description = 'Displays OSPF process information'
            }
            'Arista' = @{
                Command = 'show ip ospf'
                Syntax = 'show ip ospf'
                Description = 'Displays OSPF configuration'
            }
            'Juniper' = @{
                Command = 'show ospf overview'
                Syntax = 'show ospf overview'
                Description = 'Displays OSPF overview'
            }
            'HP' = @{
                Command = 'show ip ospf'
                Syntax = 'show ip ospf'
                Description = 'Displays OSPF settings'
            }
        }
    }
    'show-ip-ospf-interface' = @{
        Task = 'Show OSPF interface details'
        Category = 'Routing'
        Commands = @{
            'Cisco' = @{
                Command = 'show ip ospf interface'
                Syntax = 'show ip ospf interface [<interface>]'
                Description = 'Displays OSPF interface information'
            }
            'Arista' = @{
                Command = 'show ip ospf interface'
                Syntax = 'show ip ospf interface [<interface>]'
                Description = 'Displays OSPF interface details'
            }
            'Juniper' = @{
                Command = 'show ospf interface'
                Syntax = 'show ospf interface [<interface>]'
                Description = 'Displays OSPF interface info'
            }
            'HP' = @{
                Command = 'show ip ospf interface'
                Syntax = 'show ip ospf interface'
                Description = 'Displays OSPF interfaces'
            }
        }
    }
    'show-ip-ospf-database' = @{
        Task = 'Show OSPF link-state database'
        Category = 'Routing'
        Commands = @{
            'Cisco' = @{
                Command = 'show ip ospf database'
                Syntax = 'show ip ospf database [router | network | summary | external]'
                Description = 'Displays OSPF LSDB'
            }
            'Arista' = @{
                Command = 'show ip ospf database'
                Syntax = 'show ip ospf database'
                Description = 'Displays OSPF database'
            }
            'Juniper' = @{
                Command = 'show ospf database'
                Syntax = 'show ospf database [brief | detail | extensive]'
                Description = 'Displays OSPF database'
            }
            'HP' = @{
                Command = 'show ip ospf link-state'
                Syntax = 'show ip ospf link-state'
                Description = 'Displays OSPF LSAs'
            }
        }
    }
    'show-ip-bgp' = @{
        Task = 'Show BGP table'
        Category = 'Routing'
        Commands = @{
            'Cisco' = @{
                Command = 'show ip bgp'
                Syntax = 'show ip bgp [<prefix>] [neighbors]'
                Description = 'Displays BGP routing table'
            }
            'Arista' = @{
                Command = 'show ip bgp'
                Syntax = 'show ip bgp [<prefix>]'
                Description = 'Displays BGP table'
            }
            'Juniper' = @{
                Command = 'show route protocol bgp'
                Syntax = 'show route protocol bgp [table inet.0]'
                Description = 'Displays BGP routes'
            }
            'HP' = @{
                Command = 'show ip bgp'
                Syntax = 'show ip bgp'
                Description = 'Displays BGP routes'
            }
        }
    }
    'show-ip-bgp-neighbors' = @{
        Task = 'Show BGP neighbor details'
        Category = 'Routing'
        Commands = @{
            'Cisco' = @{
                Command = 'show ip bgp neighbors'
                Syntax = 'show ip bgp neighbors [<neighbor-ip>]'
                Description = 'Displays BGP neighbor details'
            }
            'Arista' = @{
                Command = 'show ip bgp neighbors'
                Syntax = 'show ip bgp neighbors [<neighbor-ip>]'
                Description = 'Displays BGP peer information'
            }
            'Juniper' = @{
                Command = 'show bgp neighbor'
                Syntax = 'show bgp neighbor [<neighbor-ip>]'
                Description = 'Displays BGP neighbor details'
            }
            'HP' = @{
                Command = 'show ip bgp neighbors'
                Syntax = 'show ip bgp neighbors'
                Description = 'Displays BGP neighbors'
            }
        }
    }
    'show-ip-eigrp-neighbors' = @{
        Task = 'Show EIGRP neighbors'
        Category = 'Routing'
        Commands = @{
            'Cisco' = @{
                Command = 'show ip eigrp neighbors'
                Syntax = 'show ip eigrp neighbors [<interface>]'
                Description = 'Displays EIGRP neighbor adjacencies'
            }
            'Arista' = @{
                Command = 'N/A'
                Description = 'Arista does not support EIGRP'
                Notes = 'Use OSPF or BGP instead'
            }
            'Juniper' = @{
                Command = 'N/A'
                Description = 'Juniper does not support EIGRP'
                Notes = 'Use OSPF or IS-IS instead'
            }
            'HP' = @{
                Command = 'N/A'
                Description = 'HP does not support EIGRP'
                Notes = 'Use OSPF instead'
            }
        }
    }
    'show-ip-static-route' = @{
        Task = 'Show static routes'
        Category = 'Routing'
        Commands = @{
            'Cisco' = @{
                Command = 'show ip route static'
                Syntax = 'show ip route static'
                Description = 'Displays static routes'
            }
            'Arista' = @{
                Command = 'show ip route static'
                Syntax = 'show ip route static'
                Description = 'Displays static routes'
            }
            'Juniper' = @{
                Command = 'show route protocol static'
                Syntax = 'show route protocol static'
                Description = 'Displays static routes'
            }
            'HP' = @{
                Command = 'show ip route static'
                Syntax = 'show ip route static'
                Description = 'Displays static routes'
            }
        }
    }

    # Multicast commands
    'show-ip-igmp-groups' = @{
        Task = 'Show IGMP groups'
        Category = 'Routing'
        Commands = @{
            'Cisco' = @{
                Command = 'show ip igmp groups'
                Syntax = 'show ip igmp groups [<interface>]'
                Description = 'Displays IGMP group membership'
            }
            'Arista' = @{
                Command = 'show ip igmp groups'
                Syntax = 'show ip igmp groups'
                Description = 'Displays IGMP groups'
            }
            'Juniper' = @{
                Command = 'show igmp group'
                Syntax = 'show igmp group'
                Description = 'Displays IGMP group information'
            }
            'HP' = @{
                Command = 'show ip igmp'
                Syntax = 'show ip igmp [groups]'
                Description = 'Displays IGMP information'
            }
        }
    }
    'show-ip-mroute' = @{
        Task = 'Show multicast routing table'
        Category = 'Routing'
        Commands = @{
            'Cisco' = @{
                Command = 'show ip mroute'
                Syntax = 'show ip mroute [<group>]'
                Description = 'Displays multicast routing table'
            }
            'Arista' = @{
                Command = 'show ip mroute'
                Syntax = 'show ip mroute'
                Description = 'Displays multicast routes'
            }
            'Juniper' = @{
                Command = 'show multicast route'
                Syntax = 'show multicast route'
                Description = 'Displays multicast routing'
            }
            'HP' = @{
                Command = 'show ip mroute'
                Syntax = 'show ip mroute'
                Description = 'Displays multicast routes'
            }
        }
    }

    # Power over Ethernet
    'show-power-inline' = @{
        Task = 'Show PoE status'
        Category = 'Interface'
        Commands = @{
            'Cisco' = @{
                Command = 'show power inline'
                Syntax = 'show power inline [<interface>]'
                Description = 'Displays PoE status and power consumption'
            }
            'Arista' = @{
                Command = 'show poe status'
                Syntax = 'show poe status [interface <interface>]'
                Description = 'Displays PoE status'
            }
            'Juniper' = @{
                Command = 'show poe interface'
                Syntax = 'show poe interface'
                Description = 'Displays PoE interface status'
            }
            'HP' = @{
                Command = 'show power-over-ethernet'
                Syntax = 'show power-over-ethernet [<port>]'
                Description = 'Displays PoE information'
            }
        }
    }

    # DHCP
    'show-ip-dhcp-binding' = @{
        Task = 'Show DHCP bindings/leases'
        Category = 'Routing'
        Commands = @{
            'Cisco' = @{
                Command = 'show ip dhcp binding'
                Syntax = 'show ip dhcp binding'
                Description = 'Displays DHCP server bindings'
            }
            'Arista' = @{
                Command = 'show ip dhcp binding'
                Syntax = 'show ip dhcp binding'
                Description = 'Displays DHCP bindings'
            }
            'Juniper' = @{
                Command = 'show dhcp server binding'
                Syntax = 'show dhcp server binding'
                Description = 'Displays DHCP server bindings'
            }
            'HP' = @{
                Command = 'show dhcp-server binding'
                Syntax = 'show dhcp-server binding'
                Description = 'Displays DHCP bindings'
            }
        }
    }
    'show-ip-dhcp-snooping' = @{
        Task = 'Show DHCP snooping bindings'
        Category = 'Security'
        Commands = @{
            'Cisco' = @{
                Command = 'show ip dhcp snooping binding'
                Syntax = 'show ip dhcp snooping binding'
                Description = 'Displays DHCP snooping binding table'
            }
            'Arista' = @{
                Command = 'show ip dhcp snooping binding'
                Syntax = 'show ip dhcp snooping binding'
                Description = 'Displays DHCP snooping bindings'
            }
            'Juniper' = @{
                Command = 'show dhcp-security binding'
                Syntax = 'show dhcp-security binding'
                Description = 'Displays DHCP security bindings'
            }
            'HP' = @{
                Command = 'show dhcp-snooping binding'
                Syntax = 'show dhcp-snooping binding'
                Description = 'Displays DHCP snooping table'
            }
        }
    }

    # Hardware/stack commands
    'show-switch' = @{
        Task = 'Show switch stack status'
        Category = 'System'
        Commands = @{
            'Cisco' = @{
                Command = 'show switch'
                Syntax = 'show switch [detail]'
                Description = 'Displays switch stack members and status'
            }
            'Arista' = @{
                Command = 'show mlag'
                Syntax = 'show mlag [detail]'
                Description = 'Displays MLAG status (Arista uses MLAG instead of stacking)'
            }
            'Juniper' = @{
                Command = 'show virtual-chassis'
                Syntax = 'show virtual-chassis'
                Description = 'Displays virtual chassis members'
            }
            'HP' = @{
                Command = 'show stacking'
                Syntax = 'show stacking'
                Description = 'Displays stacking information'
            }
        }
    }
    'show-module' = @{
        Task = 'Show module/linecard status'
        Category = 'System'
        Commands = @{
            'Cisco' = @{
                Command = 'show module'
                Syntax = 'show module [<slot>]'
                Description = 'Displays module status in modular switches'
            }
            'Arista' = @{
                Command = 'show module'
                Syntax = 'show module [<slot>]'
                Description = 'Displays module information'
            }
            'Juniper' = @{
                Command = 'show chassis fpc'
                Syntax = 'show chassis fpc'
                Description = 'Displays FPC (line card) status'
            }
            'HP' = @{
                Command = 'show modules'
                Syntax = 'show modules'
                Description = 'Displays installed modules'
            }
        }
    }

    # VRF commands
    'show-ip-vrf' = @{
        Task = 'Show VRF information'
        Category = 'Routing'
        Commands = @{
            'Cisco' = @{
                Command = 'show ip vrf'
                Syntax = 'show ip vrf [<vrf-name>]'
                Description = 'Displays VRF information'
            }
            'Arista' = @{
                Command = 'show vrf'
                Syntax = 'show vrf [<vrf-name>]'
                Description = 'Displays VRF details'
            }
            'Juniper' = @{
                Command = 'show route instance'
                Syntax = 'show route instance [<instance-name>]'
                Description = 'Displays routing instances'
            }
            'HP' = @{
                Command = 'show ip vrf'
                Syntax = 'show ip vrf'
                Description = 'Displays VRF information'
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
    'static-route' = @{
        Task = 'Configure static route'
        Category = 'Routing'
        Variables = @('network', 'mask', 'next_hop', 'admin_distance')
        Snippets = @{
            'Cisco' = @'
ip route {{network}} {{mask}} {{next_hop}} {{admin_distance}}
'@
            'Arista' = @'
ip route {{network}}/{{mask}} {{next_hop}} {{admin_distance}}
'@
            'Juniper' = @'
set routing-options static route {{network}}/{{mask}} next-hop {{next_hop}} preference {{admin_distance}}
'@
            'HP' = @'
ip route {{network}} {{mask}} {{next_hop}} distance {{admin_distance}}
'@
        }
    }
    'svi-interface' = @{
        Task = 'Configure SVI (VLAN interface)'
        Category = 'Routing'
        Variables = @('vlan_id', 'ip_address', 'subnet_mask', 'description')
        Snippets = @{
            'Cisco' = @'
interface Vlan{{vlan_id}}
 description {{description}}
 ip address {{ip_address}} {{subnet_mask}}
 no shutdown
'@
            'Arista' = @'
interface Vlan{{vlan_id}}
   description {{description}}
   ip address {{ip_address}}/{{subnet_mask}}
   no shutdown
'@
            'Juniper' = @'
set interfaces irb unit {{vlan_id}} description "{{description}}"
set interfaces irb unit {{vlan_id}} family inet address {{ip_address}}/{{subnet_mask}}
'@
            'HP' = @'
vlan {{vlan_id}}
 ip address {{ip_address}} {{subnet_mask}}
 name "{{description}}"
'@
        }
    }
    'port-security' = @{
        Task = 'Configure port security'
        Category = 'Security'
        Variables = @('interface', 'max_macs', 'violation_action')
        Snippets = @{
            'Cisco' = @'
interface {{interface}}
 switchport port-security
 switchport port-security maximum {{max_macs}}
 switchport port-security violation {{violation_action}}
 switchport port-security mac-address sticky
'@
            'Arista' = @'
interface {{interface}}
   switchport port-security
   switchport port-security maximum {{max_macs}}
   switchport port-security violation {{violation_action}}
'@
            'Juniper' = @'
set ethernet-switching-options secure-access-port interface {{interface}} mac-limit {{max_macs}} action {{violation_action}}
'@
            'HP' = @'
interface {{interface}}
 port-security
 port-security mac-address sticky
 port-security maximum {{max_macs}}
 port-security violation {{violation_action}}
'@
        }
    }
    'acl-standard' = @{
        Task = 'Configure standard ACL'
        Category = 'Security'
        Variables = @('acl_name', 'action', 'source_network', 'source_wildcard')
        Snippets = @{
            'Cisco' = @'
ip access-list standard {{acl_name}}
 {{action}} {{source_network}} {{source_wildcard}}
'@
            'Arista' = @'
ip access-list standard {{acl_name}}
   {{action}} {{source_network}}/{{source_wildcard}}
'@
            'Juniper' = @'
set firewall family inet filter {{acl_name}} term 1 from source-address {{source_network}}/{{source_wildcard}}
set firewall family inet filter {{acl_name}} term 1 then {{action}}
'@
            'HP' = @'
ip access-list standard {{acl_name}}
 {{action}} {{source_network}} {{source_wildcard}}
'@
        }
    }
    'acl-extended' = @{
        Task = 'Configure extended ACL'
        Category = 'Security'
        Variables = @('acl_name', 'action', 'protocol', 'src_network', 'src_wildcard', 'dst_network', 'dst_wildcard', 'dst_port')
        Snippets = @{
            'Cisco' = @'
ip access-list extended {{acl_name}}
 {{action}} {{protocol}} {{src_network}} {{src_wildcard}} {{dst_network}} {{dst_wildcard}} eq {{dst_port}}
'@
            'Arista' = @'
ip access-list {{acl_name}}
   {{action}} {{protocol}} {{src_network}}/{{src_wildcard}} {{dst_network}}/{{dst_wildcard}} eq {{dst_port}}
'@
            'Juniper' = @'
set firewall family inet filter {{acl_name}} term 1 from protocol {{protocol}}
set firewall family inet filter {{acl_name}} term 1 from source-address {{src_network}}/{{src_wildcard}}
set firewall family inet filter {{acl_name}} term 1 from destination-address {{dst_network}}/{{dst_wildcard}}
set firewall family inet filter {{acl_name}} term 1 from destination-port {{dst_port}}
set firewall family inet filter {{acl_name}} term 1 then {{action}}
'@
            'HP' = @'
ip access-list extended {{acl_name}}
 {{action}} {{protocol}} {{src_network}} {{src_wildcard}} {{dst_network}} {{dst_wildcard}} eq {{dst_port}}
'@
        }
    }
    'ntp-server' = @{
        Task = 'Configure NTP server'
        Category = 'System'
        Variables = @('ntp_server', 'prefer')
        Snippets = @{
            'Cisco' = @'
ntp server {{ntp_server}} {{prefer}}
'@
            'Arista' = @'
ntp server {{ntp_server}} {{prefer}}
'@
            'Juniper' = @'
set system ntp server {{ntp_server}} {{prefer}}
'@
            'HP' = @'
timesync ntp
ntp server {{ntp_server}}
'@
        }
    }
    'snmp-community' = @{
        Task = 'Configure SNMP community'
        Category = 'System'
        Variables = @('community', 'access_mode', 'acl_name')
        Snippets = @{
            'Cisco' = @'
snmp-server community {{community}} {{access_mode}} {{acl_name}}
'@
            'Arista' = @'
snmp-server community {{community}} {{access_mode}} {{acl_name}}
'@
            'Juniper' = @'
set snmp community {{community}} authorization {{access_mode}}
set snmp community {{community}} clients {{acl_name}}
'@
            'HP' = @'
snmp-server community {{community}} {{access_mode}}
'@
        }
    }
    'syslog-server' = @{
        Task = 'Configure syslog server'
        Category = 'System'
        Variables = @('syslog_server', 'severity')
        Snippets = @{
            'Cisco' = @'
logging host {{syslog_server}}
logging trap {{severity}}
'@
            'Arista' = @'
logging host {{syslog_server}}
logging trap {{severity}}
'@
            'Juniper' = @'
set system syslog host {{syslog_server}} any {{severity}}
'@
            'HP' = @'
logging {{syslog_server}}
logging severity {{severity}}
'@
        }
    }
    'hsrp-config' = @{
        Task = 'Configure HSRP'
        Category = 'Routing'
        Variables = @('interface', 'group_id', 'virtual_ip', 'priority', 'preempt')
        Snippets = @{
            'Cisco' = @'
interface {{interface}}
 standby {{group_id}} ip {{virtual_ip}}
 standby {{group_id}} priority {{priority}}
 standby {{group_id}} preempt
'@
            'Arista' = @'
! Arista uses VRRP instead of HSRP
interface {{interface}}
   vrrp {{group_id}} ipv4 {{virtual_ip}}
   vrrp {{group_id}} priority {{priority}}
   vrrp {{group_id}} preempt
'@
            'Juniper' = @'
set interfaces {{interface}} unit 0 family inet address {{virtual_ip}}/24 vrrp-group {{group_id}} virtual-address {{virtual_ip}}
set interfaces {{interface}} unit 0 family inet address {{virtual_ip}}/24 vrrp-group {{group_id}} priority {{priority}}
set interfaces {{interface}} unit 0 family inet address {{virtual_ip}}/24 vrrp-group {{group_id}} preempt
'@
            'HP' = @'
interface {{interface}}
 vrrp vrid {{group_id}}
  ip address {{virtual_ip}}
  priority {{priority}}
  preempt
'@
        }
    }
    'ospf-basic' = @{
        Task = 'Configure OSPF basic'
        Category = 'Routing'
        Variables = @('process_id', 'router_id', 'network', 'wildcard', 'area')
        Snippets = @{
            'Cisco' = @'
router ospf {{process_id}}
 router-id {{router_id}}
 network {{network}} {{wildcard}} area {{area}}
'@
            'Arista' = @'
router ospf {{process_id}}
   router-id {{router_id}}
   network {{network}}/{{wildcard}} area {{area}}
'@
            'Juniper' = @'
set protocols ospf area {{area}} interface {{network}}.0
set routing-options router-id {{router_id}}
'@
            'HP' = @'
router ospf
 router-id {{router_id}}
 area {{area}}
 enable
'@
        }
    }
    'bgp-neighbor' = @{
        Task = 'Configure BGP neighbor'
        Category = 'Routing'
        Variables = @('local_as', 'neighbor_ip', 'remote_as', 'description')
        Snippets = @{
            'Cisco' = @'
router bgp {{local_as}}
 neighbor {{neighbor_ip}} remote-as {{remote_as}}
 neighbor {{neighbor_ip}} description {{description}}
'@
            'Arista' = @'
router bgp {{local_as}}
   neighbor {{neighbor_ip}} remote-as {{remote_as}}
   neighbor {{neighbor_ip}} description {{description}}
'@
            'Juniper' = @'
set protocols bgp group external neighbor {{neighbor_ip}} description "{{description}}"
set protocols bgp group external neighbor {{neighbor_ip}} peer-as {{remote_as}}
set routing-options autonomous-system {{local_as}}
'@
            'HP' = @'
router bgp {{local_as}}
 neighbor {{neighbor_ip}} remote-as {{remote_as}}
'@
        }
    }
    'interface-shutdown' = @{
        Task = 'Shutdown interface'
        Category = 'Interface'
        Variables = @('interface')
        Snippets = @{
            'Cisco' = @'
interface {{interface}}
 shutdown
'@
            'Arista' = @'
interface {{interface}}
   shutdown
'@
            'Juniper' = @'
set interfaces {{interface}} disable
'@
            'HP' = @'
interface {{interface}}
 disable
'@
        }
    }
    'interface-no-shutdown' = @{
        Task = 'Enable interface'
        Category = 'Interface'
        Variables = @('interface')
        Snippets = @{
            'Cisco' = @'
interface {{interface}}
 no shutdown
'@
            'Arista' = @'
interface {{interface}}
   no shutdown
'@
            'Juniper' = @'
delete interfaces {{interface}} disable
'@
            'HP' = @'
interface {{interface}}
 enable
'@
        }
    }
    'interface-description' = @{
        Task = 'Set interface description'
        Category = 'Interface'
        Variables = @('interface', 'description')
        Snippets = @{
            'Cisco' = @'
interface {{interface}}
 description {{description}}
'@
            'Arista' = @'
interface {{interface}}
   description {{description}}
'@
            'Juniper' = @'
set interfaces {{interface}} description "{{description}}"
'@
            'HP' = @'
interface {{interface}}
 name "{{description}}"
'@
        }
    }
    'spanning-tree-portfast' = @{
        Task = 'Configure STP portfast'
        Category = 'Switching'
        Variables = @('interface')
        Snippets = @{
            'Cisco' = @'
interface {{interface}}
 spanning-tree portfast
 spanning-tree bpduguard enable
'@
            'Arista' = @'
interface {{interface}}
   spanning-tree portfast
   spanning-tree bpduguard enable
'@
            'Juniper' = @'
set protocols rstp interface {{interface}} edge
set ethernet-switching-options bpdu-block interface {{interface}}
'@
            'HP' = @'
interface {{interface}}
 spanning-tree admin-edge-port
 spanning-tree bpdu-guard
'@
        }
    }
    'dhcp-snooping' = @{
        Task = 'Configure DHCP snooping'
        Category = 'Security'
        Variables = @('vlan_id', 'trusted_interface')
        Snippets = @{
            'Cisco' = @'
ip dhcp snooping
ip dhcp snooping vlan {{vlan_id}}
interface {{trusted_interface}}
 ip dhcp snooping trust
'@
            'Arista' = @'
ip dhcp snooping
ip dhcp snooping vlan {{vlan_id}}
interface {{trusted_interface}}
   ip dhcp snooping trust
'@
            'Juniper' = @'
set ethernet-switching-options secure-access-port vlan {{vlan_id}} dhcp-snooping
set ethernet-switching-options secure-access-port interface {{trusted_interface}} dhcp-trusted
'@
            'HP' = @'
dhcp-snooping
dhcp-snooping vlan {{vlan_id}}
interface {{trusted_interface}}
 dhcp-snooping trust
'@
        }
    }
    'banner-login' = @{
        Task = 'Configure login banner'
        Category = 'System'
        Variables = @('banner_text')
        Snippets = @{
            'Cisco' = @'
banner login ^
{{banner_text}}
^
'@
            'Arista' = @'
banner login
{{banner_text}}
EOF
'@
            'Juniper' = @'
set system login message "{{banner_text}}"
'@
            'HP' = @'
banner motd "{{banner_text}}"
'@
        }
    }
    'aaa-tacacs' = @{
        Task = 'Configure TACACS+ server'
        Category = 'Security'
        Variables = @('server_ip', 'shared_key')
        Snippets = @{
            'Cisco' = @'
tacacs-server host {{server_ip}} key {{shared_key}}
aaa new-model
aaa authentication login default group tacacs+ local
aaa authorization exec default group tacacs+ local
'@
            'Arista' = @'
tacacs-server host {{server_ip}} key {{shared_key}}
aaa authentication login default group tacacs+ local
aaa authorization exec default group tacacs+ local
'@
            'Juniper' = @'
set system tacplus-server {{server_ip}} secret {{shared_key}}
set system authentication-order [tacplus password]
'@
            'HP' = @'
tacacs-server host {{server_ip}} key {{shared_key}}
aaa authentication login default group tacacs local
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

#region Learning Mode (ST-AD-006)

# In-memory progress storage (per-session)
$script:LearningProgress = @{}

function New-CommandQuiz {
    <#
    .SYNOPSIS
        Generates a command translation quiz.
    .DESCRIPTION
        Creates quiz questions that test knowledge of cross-vendor command equivalents.
    .PARAMETER Type
        Quiz type: Translation (default), Identification, or Syntax.
    .PARAMETER Count
        Number of questions to generate (default 10).
    .PARAMETER Category
        Optionally filter questions by command category.
    .PARAMETER Vendors
        Vendors to include in questions (default all).
    .EXAMPLE
        New-CommandQuiz -Type Translation -Count 5
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Translation', 'Identification', 'Syntax')]
        [string]$Type = 'Translation',

        [ValidateRange(1, 50)]
        [int]$Count = 10,

        [string]$Category,

        [string[]]$Vendors
    )

    $allVendors = [System.Collections.ArrayList]@()
    if ($Vendors) {
        foreach ($v in $Vendors) {
            $resolved = Resolve-VendorName -Vendor $v
            if ($resolved) {
                [void]$allVendors.Add($resolved)
            }
        }
    } else {
        foreach ($v in $script:Vendors.Keys) {
            [void]$allVendors.Add($v)
        }
    }

    if ($allVendors.Count -lt 2) {
        Write-Warning "At least 2 vendors required for quiz generation"
        return $null
    }

    $questions = @()
    $usedTasks = @{}

    # Get all commands that have entries for multiple vendors
    $eligibleTasks = @()
    foreach ($taskKey in $script:CommandDatabase.Keys) {
        $entry = $script:CommandDatabase[$taskKey]

        if ($Category -and $entry.Category -ne $Category) { continue }

        $vendorCount = ($entry.Commands.Keys | Where-Object { $allVendors -contains $_ }).Count
        if ($vendorCount -ge 2) {
            $eligibleTasks += $taskKey
        }
    }

    # Shuffle tasks
    $eligibleTasks = $eligibleTasks | Get-Random -Count $eligibleTasks.Count

    $questionIndex = 0
    foreach ($taskKey in $eligibleTasks) {
        if ($questions.Count -ge $Count) { break }

        $entry = $script:CommandDatabase[$taskKey]
        $availableVendors = @($entry.Commands.Keys | Where-Object { $allVendors -contains $_ })

        if ($availableVendors.Count -lt 2) { continue }

        # Pick source and target vendors
        $sourceVendor = $availableVendors | Get-Random
        $targetVendor = $availableVendors | Where-Object { $_ -ne $sourceVendor } | Get-Random

        $sourceCmd = $entry.Commands[$sourceVendor].Command
        $correctAnswer = $entry.Commands[$targetVendor].Command

        # Generate wrong options from other commands
        $wrongOptions = @()
        foreach ($otherTask in ($script:CommandDatabase.Keys | Where-Object { $_ -ne $taskKey })) {
            $otherEntry = $script:CommandDatabase[$otherTask]
            if ($otherEntry.Commands.ContainsKey($targetVendor)) {
                $otherCmd = $otherEntry.Commands[$targetVendor].Command
                if ($otherCmd -ne $correctAnswer -and $otherCmd -ne 'N/A') {
                    $wrongOptions += $otherCmd
                }
            }
        }

        # Pick 2-3 wrong options
        $wrongOptions = $wrongOptions | Get-Random -Count ([Math]::Min(3, $wrongOptions.Count))
        $allOptions = @($correctAnswer) + $wrongOptions | Get-Random -Count (1 + $wrongOptions.Count)

        $questions += [PSCustomObject]@{
            Index = $questionIndex
            Type = $Type
            SourceVendor = $sourceVendor
            TargetVendor = $targetVendor
            SourceCommand = $sourceCmd
            Task = $entry.Task
            Category = $entry.Category
            Options = $allOptions
            CorrectAnswer = $correctAnswer
        }

        $questionIndex++
    }

    return [PSCustomObject]@{
        QuizId = [guid]::NewGuid().ToString()
        Type = $Type
        GeneratedAt = Get-Date
        QuestionCount = $questions.Count
        Questions = $questions
    }
}

function Submit-QuizAnswers {
    <#
    .SYNOPSIS
        Scores quiz answers and records progress.
    .PARAMETER Quiz
        The quiz object from New-CommandQuiz.
    .PARAMETER Answers
        Array of answer objects with QuestionIndex and Answer properties.
    .PARAMETER User
        Optional user identifier for progress tracking.
    .EXAMPLE
        $result = Submit-QuizAnswers -Quiz $quiz -Answers @(
            @{ QuestionIndex = 0; Answer = 'show route' }
        )
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Quiz,

        [Parameter(Mandatory)]
        [array]$Answers,

        [string]$User = 'default'
    )

    $correct = 0
    $incorrect = 0
    $results = @()

    foreach ($answer in $Answers) {
        $questionIndex = $answer.QuestionIndex
        $userAnswer = $answer.Answer

        $question = $Quiz.Questions | Where-Object { $_.Index -eq $questionIndex }
        if (-not $question) { continue }

        $isCorrect = ($userAnswer -eq $question.CorrectAnswer)
        if ($isCorrect) {
            $correct++
        } else {
            $incorrect++
        }

        $results += [PSCustomObject]@{
            QuestionIndex = $questionIndex
            UserAnswer = $userAnswer
            CorrectAnswer = $question.CorrectAnswer
            IsCorrect = $isCorrect
            Task = $question.Task
        }
    }

    $percentage = if (($correct + $incorrect) -gt 0) {
        [Math]::Round(($correct / ($correct + $incorrect)) * 100, 0)
    } else {
        0
    }

    # Update progress
    if (-not $script:LearningProgress.ContainsKey($User)) {
        $script:LearningProgress[$User] = @{
            TotalQuizzes = 0
            TotalQuestions = 0
            TotalCorrect = 0
            QuizHistory = @()
        }
    }

    $script:LearningProgress[$User].TotalQuizzes++
    $script:LearningProgress[$User].TotalQuestions += ($correct + $incorrect)
    $script:LearningProgress[$User].TotalCorrect += $correct
    $script:LearningProgress[$User].QuizHistory += [PSCustomObject]@{
        QuizId = $Quiz.QuizId
        Date = Get-Date
        Score = $percentage
        Correct = $correct
        Total = ($correct + $incorrect)
    }

    return [PSCustomObject]@{
        QuizId = $Quiz.QuizId
        Correct = $correct
        Incorrect = $incorrect
        Unanswered = $Quiz.QuestionCount - ($correct + $incorrect)
        Percentage = $percentage
        Results = $results
    }
}

function Get-LearningProgress {
    <#
    .SYNOPSIS
        Gets learning progress for a user.
    .PARAMETER User
        User identifier (default 'default').
    .EXAMPLE
        Get-LearningProgress -User 'testuser'
    #>
    [CmdletBinding()]
    param(
        [string]$User = 'default'
    )

    if (-not $script:LearningProgress.ContainsKey($User)) {
        return [PSCustomObject]@{
            User = $User
            TotalQuizzes = 0
            TotalQuestions = 0
            TotalCorrect = 0
            AverageScore = 0
            QuizHistory = @()
        }
    }

    $progress = $script:LearningProgress[$User]
    $averageScore = if ($progress.TotalQuestions -gt 0) {
        [Math]::Round(($progress.TotalCorrect / $progress.TotalQuestions) * 100, 1)
    } else {
        0
    }

    return [PSCustomObject]@{
        User = $User
        TotalQuizzes = $progress.TotalQuizzes
        TotalQuestions = $progress.TotalQuestions
        TotalCorrect = $progress.TotalCorrect
        AverageScore = $averageScore
        QuizHistory = $progress.QuizHistory
    }
}

function Reset-LearningProgress {
    <#
    .SYNOPSIS
        Resets learning progress for a user.
    .PARAMETER User
        User identifier (default 'default').
    .EXAMPLE
        Reset-LearningProgress -User 'testuser'
    #>
    [CmdletBinding()]
    param(
        [string]$User = 'default'
    )

    if ($script:LearningProgress.ContainsKey($User)) {
        $script:LearningProgress.Remove($User)
    }

    return $true
}

function New-FlashCards {
    <#
    .SYNOPSIS
        Generates flash cards for command learning.
    .DESCRIPTION
        Creates flash card sets with command on front and vendor equivalents on back.
    .PARAMETER Category
        Filter by command category.
    .PARAMETER Count
        Number of cards to generate.
    .PARAMETER Vendors
        Vendors to include (default Cisco and Arista).
    .EXAMPLE
        New-FlashCards -Category 'Routing' -Count 10
    #>
    [CmdletBinding()]
    param(
        [string]$Category,

        [ValidateRange(1, 100)]
        [int]$Count = 20,

        [string[]]$Vendors = @('Cisco', 'Arista')
    )

    $resolvedVendors = $Vendors | ForEach-Object { Resolve-VendorName -Vendor $_ } | Where-Object { $_ }

    $cards = @()
    $eligibleTasks = @()

    foreach ($taskKey in $script:CommandDatabase.Keys) {
        $entry = $script:CommandDatabase[$taskKey]

        if ($Category -and $entry.Category -ne $Category) { continue }

        $hasAllVendors = $true
        foreach ($v in $resolvedVendors) {
            if (-not $entry.Commands.ContainsKey($v)) {
                $hasAllVendors = $false
                break
            }
        }

        if ($hasAllVendors) {
            $eligibleTasks += $taskKey
        }
    }

    # Shuffle and limit
    $eligibleTasks = $eligibleTasks | Get-Random -Count ([Math]::Min($Count, $eligibleTasks.Count))

    foreach ($taskKey in $eligibleTasks) {
        $entry = $script:CommandDatabase[$taskKey]

        # Build front (task description)
        $front = $entry.Task

        # Build back (commands for each vendor)
        $backLines = @()
        foreach ($v in $resolvedVendors) {
            $cmd = $entry.Commands[$v].Command
            $backLines += "$v`: $cmd"
        }
        $back = $backLines -join "`n"

        $cards += [PSCustomObject]@{
            Front = $front
            Back = $back
            Category = $entry.Category
            TaskKey = $taskKey
            Vendors = $resolvedVendors
        }
    }

    return $cards
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
    'Get-StatusCodes',
    'New-CommandQuiz',
    'Submit-QuizAnswers',
    'Get-LearningProgress',
    'Reset-LearningProgress',
    'New-FlashCards'
)
