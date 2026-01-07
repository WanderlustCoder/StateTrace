# VendorCommandTemplates.psm1
# Show command templates for each supported network device vendor
# Provides standard commands for gathering device information

Set-StrictMode -Version Latest

$script:CommandTemplates = @{
    Cisco = @{
        DisplayName = 'Cisco IOS/IOS-XE/NX-OS'
        BasicInfo = @(
            'show version'
            'show running-config'
            'show interfaces status'
            'show ip interface brief'
        )
        Interfaces = @(
            'show interfaces'
            'show interfaces status'
            'show interfaces description'
            'show ip interface brief'
        )
        Layer2 = @(
            'show mac address-table'
            'show vlan brief'
            'show spanning-tree'
            'show etherchannel summary'
        )
        Layer3 = @(
            'show ip route'
            'show ip arp'
            'show ip ospf neighbor'
            'show ip bgp summary'
        )
        Security = @(
            'show authentication sessions'
            'show dot1x all'
            'show access-lists'
        )
        Diagnostics = @(
            'show logging'
            'show environment'
            'show processes cpu'
            'show memory statistics'
        )
        FullCapture = @(
            'terminal length 0'
            'show version'
            'show running-config'
            'show interfaces status'
            'show mac address-table'
            'show vlan brief'
            'show ip route'
            'show spanning-tree'
            'show authentication sessions'
        )
    }

    Arista = @{
        DisplayName = 'Arista EOS'
        BasicInfo = @(
            'show version'
            'show running-config'
            'show interfaces status'
        )
        Interfaces = @(
            'show interfaces'
            'show interfaces status'
            'show interfaces description'
        )
        Layer2 = @(
            'show mac address-table'
            'show vlan'
            'show spanning-tree'
            'show port-channel summary'
        )
        Layer3 = @(
            'show ip route'
            'show arp'
            'show ip ospf neighbor'
            'show bgp summary'
        )
        Security = @(
            'show dot1x'
            'show aaa sessions'
        )
        Diagnostics = @(
            'show logging'
            'show environment all'
            'show processes top'
        )
        FullCapture = @(
            'terminal length 0'
            'show version'
            'show running-config'
            'show interfaces status'
            'show mac address-table'
            'show vlan'
            'show ip route'
            'show spanning-tree'
        )
    }

    Juniper = @{
        DisplayName = 'Juniper JunOS'
        BasicInfo = @(
            'show version'
            'show configuration | display set'
            'show interfaces terse'
        )
        Interfaces = @(
            'show interfaces'
            'show interfaces terse'
            'show interfaces descriptions'
            'show interfaces extensive'
        )
        Layer2 = @(
            'show ethernet-switching table'
            'show vlans'
            'show spanning-tree bridge'
            'show lacp interfaces'
        )
        Layer3 = @(
            'show route'
            'show route summary'
            'show arp no-resolve'
            'show ospf neighbor'
            'show bgp summary'
        )
        Security = @(
            'show dot1x interface'
            'show security policies'
        )
        Diagnostics = @(
            'show log messages'
            'show chassis environment'
            'show system processes'
            'show system memory'
        )
        FullCapture = @(
            'set cli screen-length 0'
            'show version'
            'show configuration | display set'
            'show interfaces terse'
            'show ethernet-switching table'
            'show vlans'
            'show route'
            'show spanning-tree bridge'
        )
    }

    Aruba = @{
        DisplayName = 'Aruba/HPE ProCurve'
        BasicInfo = @(
            'show version'
            'show running-config'
            'show interfaces brief'
        )
        Interfaces = @(
            'show interfaces'
            'show interfaces brief'
            'show interfaces status'
        )
        Layer2 = @(
            'show mac-address-table'
            'show vlans'
            'show spanning-tree'
            'show trunk'
        )
        Layer3 = @(
            'show ip route'
            'show arp'
            'show ip ospf neighbor'
        )
        Security = @(
            'show port-access clients'
            'show aaa authentication'
        )
        Diagnostics = @(
            'show logging'
            'show system'
            'show cpu'
            'show memory'
        )
        FullCapture = @(
            'no page'
            'show version'
            'show running-config'
            'show interfaces brief'
            'show mac-address-table'
            'show vlans'
            'show ip route'
            'show spanning-tree'
        )
    }

    PaloAlto = @{
        DisplayName = 'Palo Alto PAN-OS'
        BasicInfo = @(
            'show system info'
            'show interface all'
            'show high-availability state'
        )
        Interfaces = @(
            'show interface all'
            'show interface hardware'
            'show interface logical'
        )
        Layer2 = @(
            'show mac all'
            'show arp all'
        )
        Layer3 = @(
            'show routing route'
            'show routing summary'
            'show routing protocol ospf neighbor'
            'show routing protocol bgp peer'
        )
        Security = @(
            'show session all'
            'show zone'
            'show running security-policy'
            'show running nat-policy'
        )
        Diagnostics = @(
            'show log system'
            'show system resources'
            'show running resource-monitor'
            'show counter global'
        )
        FullCapture = @(
            'set cli pager off'
            'show system info'
            'show interface all'
            'show routing route'
            'show zone'
            'show high-availability state'
            'show session info'
        )
    }

    Brocade = @{
        DisplayName = 'Brocade/Ruckus ICX'
        BasicInfo = @(
            'show version'
            'show running-config'
            'show interfaces brief'
        )
        Interfaces = @(
            'show interfaces'
            'show interfaces brief'
            'show interfaces status'
        )
        Layer2 = @(
            'show mac-address'
            'show vlan'
            'show spanning-tree'
            'show trunk'
        )
        Layer3 = @(
            'show ip route'
            'show arp'
            'show ip ospf neighbor'
        )
        Security = @(
            'show dot1x'
            'show authentication'
        )
        Diagnostics = @(
            'show log'
            'show cpu'
            'show memory'
            'show flash'
        )
        FullCapture = @(
            'skip-page-display'
            'show version'
            'show running-config'
            'show interfaces brief'
            'show mac-address'
            'show vlan'
            'show ip route'
            'show spanning-tree'
        )
    }
}

function Get-VendorCommands {
    <#
    .SYNOPSIS
    Gets show command templates for a specific vendor.
    .PARAMETER Vendor
    The vendor name.
    .PARAMETER Category
    Optional category filter: BasicInfo, Interfaces, Layer2, Layer3, Security, Diagnostics, FullCapture.
    .OUTPUTS
    Array of command strings or hashtable of all categories.
    .EXAMPLE
    Get-VendorCommands -Vendor Cisco -Category Layer2
    .EXAMPLE
    Get-VendorCommands -Vendor Juniper
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Vendor,
        [ValidateSet('BasicInfo', 'Interfaces', 'Layer2', 'Layer3', 'Security', 'Diagnostics', 'FullCapture')]
        [string]$Category
    )

    if (-not $script:CommandTemplates.ContainsKey($Vendor)) {
        Write-Warning "Unknown vendor: $Vendor. Supported: $($script:CommandTemplates.Keys -join ', ')"
        return @()
    }

    $template = $script:CommandTemplates[$Vendor]

    if ($Category) {
        if ($template.ContainsKey($Category)) {
            return $template[$Category]
        } else {
            Write-Warning "Category '$Category' not found for vendor $Vendor"
            return @()
        }
    }

    return $template
}

function Get-AllVendorTemplates {
    <#
    .SYNOPSIS
    Returns all vendor command templates.
    #>
    [CmdletBinding()]
    param()

    return $script:CommandTemplates
}

function Get-VendorFullCapture {
    <#
    .SYNOPSIS
    Gets the full capture command set for a vendor (typically used for SSH automation).
    .PARAMETER Vendor
    The vendor name.
    .PARAMETER AsScript
    Return as a single script string instead of array.
    .EXAMPLE
    Get-VendorFullCapture -Vendor Cisco -AsScript
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Vendor,
        [switch]$AsScript
    )

    $commands = Get-VendorCommands -Vendor $Vendor -Category FullCapture

    if ($AsScript.IsPresent) {
        return $commands -join "`n"
    }

    return $commands
}

function Compare-VendorCommands {
    <#
    .SYNOPSIS
    Compares equivalent commands across vendors.
    .PARAMETER Category
    The category to compare.
    .OUTPUTS
    Table showing equivalent commands for each vendor.
    .EXAMPLE
    Compare-VendorCommands -Category Layer2
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('BasicInfo', 'Interfaces', 'Layer2', 'Layer3', 'Security', 'Diagnostics')]
        [string]$Category
    )

    $comparison = [System.Collections.Generic.List[object]]::new()

    $maxCommands = 0
    foreach ($vendor in $script:CommandTemplates.Keys) {
        $cmds = $script:CommandTemplates[$vendor][$Category]
        if ($cmds.Count -gt $maxCommands) { $maxCommands = $cmds.Count }
    }

    for ($i = 0; $i -lt $maxCommands; $i++) {
        $row = [ordered]@{ Index = $i + 1 }
        foreach ($vendor in ($script:CommandTemplates.Keys | Sort-Object)) {
            $cmds = $script:CommandTemplates[$vendor][$Category]
            $row[$vendor] = if ($i -lt $cmds.Count) { $cmds[$i] } else { '-' }
        }
        [void]$comparison.Add([PSCustomObject]$row)
    }

    return $comparison
}

function New-CaptureScript {
    <#
    .SYNOPSIS
    Generates a capture script for a specific vendor and categories.
    .PARAMETER Vendor
    The vendor name.
    .PARAMETER Categories
    Array of categories to include.
    .PARAMETER IncludeComments
    Add comments explaining each command.
    .EXAMPLE
    New-CaptureScript -Vendor Cisco -Categories 'BasicInfo','Layer2' -IncludeComments
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Vendor,
        [string[]]$Categories = @('FullCapture'),
        [switch]$IncludeComments
    )

    if (-not $script:CommandTemplates.ContainsKey($Vendor)) {
        Write-Warning "Unknown vendor: $Vendor"
        return ''
    }

    $sb = [System.Text.StringBuilder]::new()
    $template = $script:CommandTemplates[$Vendor]

    [void]$sb.AppendLine("# $($template.DisplayName) Capture Script")
    [void]$sb.AppendLine("# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    [void]$sb.AppendLine("")

    foreach ($category in $Categories) {
        if (-not $template.ContainsKey($category)) { continue }

        if ($IncludeComments.IsPresent) {
            [void]$sb.AppendLine("# === $category ===")
        }

        foreach ($cmd in $template[$category]) {
            [void]$sb.AppendLine($cmd)
        }

        [void]$sb.AppendLine("")
    }

    return $sb.ToString()
}

Export-ModuleMember -Function @(
    'Get-VendorCommands',
    'Get-AllVendorTemplates',
    'Get-VendorFullCapture',
    'Compare-VendorCommands',
    'New-CaptureScript'
)
