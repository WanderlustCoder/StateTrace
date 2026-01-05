Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Configuration Template Engine module.

.DESCRIPTION
    Provides template-based configuration generation with variable substitution,
    conditionals, loops, and includes. Supports multiple network vendors.
    Part of Plan U - Configuration Templates & Validation.
#>

#region Template Data Structures

<#
.SYNOPSIS
    Creates a new configuration template object.
#>
function New-ConfigTemplate {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [ValidateSet('Cisco_IOS', 'Cisco_IOSXE', 'Cisco_NXOS', 'Arista_EOS', 'Brocade', 'Juniper', 'Generic')]
        [string]$Vendor = 'Generic',

        [Parameter()]
        [ValidateSet('Access', 'Distribution', 'Core', 'Router', 'Firewall', 'WLC', 'Other')]
        [string]$DeviceType = 'Other',

        [Parameter()]
        [string]$Category,

        [Parameter()]
        [string]$Version = '1.0',

        [Parameter()]
        [hashtable]$DefaultVariables,

        [Parameter()]
        [string]$Author,

        [Parameter()]
        [string]$Notes
    )

    $now = Get-Date

    [PSCustomObject]@{
        TemplateID       = [guid]::NewGuid().ToString()
        Name             = $Name
        Content          = $Content
        Description      = $Description
        Vendor           = $Vendor
        DeviceType       = $DeviceType
        Category         = $Category
        Version          = $Version
        DefaultVariables = if ($DefaultVariables) { $DefaultVariables } else { @{} }
        Author           = $Author
        Notes            = $Notes
        CreatedDate      = $now
        ModifiedDate     = $now
    }
}

<#
.SYNOPSIS
    Creates a template variable definition.
#>
function New-TemplateVariable {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [ValidateSet('String', 'Number', 'Boolean', 'List', 'Object')]
        [string]$Type = 'String',

        [Parameter()]
        $DefaultValue,

        [Parameter()]
        [switch]$Required,

        [Parameter()]
        [string]$ValidationPattern,

        [Parameter()]
        [string[]]$AllowedValues
    )

    [PSCustomObject]@{
        Name              = $Name
        Description       = $Description
        Type              = $Type
        DefaultValue      = $DefaultValue
        Required          = $Required.IsPresent
        ValidationPattern = $ValidationPattern
        AllowedValues     = $AllowedValues
    }
}

#endregion

#region Template Engine Core

<#
.SYNOPSIS
    Expands a template with the provided variables.
#>
function Expand-ConfigTemplate {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Template,

        [Parameter()]
        [hashtable]$Variables = @{},

        [Parameter()]
        [switch]$StrictMode
    )

    $result = $Template

    # Process includes first (simple include syntax: {% include "name" %})
    $result = Expand-Includes -Template $result -Variables $Variables

    # Process for loops
    $result = Expand-ForLoops -Template $result -Variables $Variables

    # Process if/else conditionals
    $result = Expand-Conditionals -Template $result -Variables $Variables

    # Process simple variable substitution
    $result = Expand-Variables -Template $result -Variables $Variables -StrictMode:$StrictMode

    $result
}

<#
.SYNOPSIS
    Expands simple variable substitutions {{ variable }}.
#>
function Expand-Variables {
    [CmdletBinding()]
    param(
        [string]$Template,
        [hashtable]$Variables,
        [switch]$StrictMode
    )

    $pattern = '\{\{\s*([a-zA-Z_][a-zA-Z0-9_\.]*)\s*\}\}'

    $result = [regex]::Replace($Template, $pattern, {
        param($match)
        $varPath = $match.Groups[1].Value
        $value = Get-NestedValue -Variables $Variables -Path $varPath

        if ($null -eq $value) {
            if ($StrictMode) {
                Write-Warning "Undefined variable: $varPath"
            }
            return $match.Value  # Leave unchanged if not found
        }

        return [string]$value
    })

    $result
}

<#
.SYNOPSIS
    Gets a nested value from a hashtable using dot notation.
#>
function Get-NestedValue {
    [CmdletBinding()]
    param(
        [hashtable]$Variables,
        [string]$Path
    )

    $parts = $Path -split '\.'
    $current = $Variables

    foreach ($part in $parts) {
        if ($null -eq $current) { return $null }

        if ($current -is [hashtable]) {
            $current = $current[$part]
        }
        elseif ($current -is [PSCustomObject]) {
            $current = $current.$part
        }
        elseif ($current.PSObject.Properties[$part]) {
            $current = $current.$part
        }
        else {
            return $null
        }
    }

    $current
}

<#
.SYNOPSIS
    Expands for loop blocks.
#>
function Expand-ForLoops {
    [CmdletBinding()]
    param(
        [string]$Template,
        [hashtable]$Variables
    )

    # Pattern: {% for item in list %}...{% endfor %}
    $pattern = '(?s)\{%\s*for\s+(\w+)\s+in\s+(\w+)\s*%\}(.*?)\{%\s*endfor\s*%\}'

    $result = $Template

    # Process nested loops from innermost to outermost
    $maxIterations = 10  # Prevent infinite loops
    $iteration = 0

    while ($result -match $pattern -and $iteration -lt $maxIterations) {
        $iteration++

        $result = [regex]::Replace($result, $pattern, {
            param($match)
            $itemName = $match.Groups[1].Value
            $listName = $match.Groups[2].Value
            $body = $match.Groups[3].Value

            $list = $Variables[$listName]
            if ($null -eq $list -or $list.Count -eq 0) {
                return ''
            }

            $output = New-Object System.Text.StringBuilder
            $index = 0

            foreach ($item in $list) {
                # Create a copy of variables with loop variable added
                $loopVars = $Variables.Clone()

                if ($item -is [hashtable]) {
                    $loopVars[$itemName] = $item
                    # Also flatten item properties for direct access
                    foreach ($key in $item.Keys) {
                        $loopVars["$itemName.$key"] = $item[$key]
                    }
                }
                elseif ($item -is [PSCustomObject]) {
                    $loopVars[$itemName] = $item
                    foreach ($prop in $item.PSObject.Properties) {
                        $loopVars["$itemName.$($prop.Name)"] = $prop.Value
                    }
                }
                else {
                    $loopVars[$itemName] = $item
                }

                # Add loop metadata
                $loopVars['loop.index'] = $index
                $loopVars['loop.first'] = ($index -eq 0)
                $loopVars['loop.last'] = ($index -eq $list.Count - 1)

                # Expand the body with loop variables
                $expandedBody = Expand-Variables -Template $body -Variables $loopVars
                $expandedBody = Expand-Conditionals -Template $expandedBody -Variables $loopVars

                $output.Append($expandedBody) | Out-Null
                $index++
            }

            return $output.ToString()
        })
    }

    $result
}

<#
.SYNOPSIS
    Expands conditional blocks.
#>
function Expand-Conditionals {
    [CmdletBinding()]
    param(
        [string]$Template,
        [hashtable]$Variables
    )

    $result = $Template

    # Pattern for if/else/endif
    $ifElsePattern = '(?s)\{%\s*if\s+(.+?)\s*%\}(.*?)\{%\s*else\s*%\}(.*?)\{%\s*endif\s*%\}'
    $ifOnlyPattern = '(?s)\{%\s*if\s+(.+?)\s*%\}(.*?)\{%\s*endif\s*%\}'

    $maxIterations = 20
    $iteration = 0

    # Process if/else first
    while ($result -match $ifElsePattern -and $iteration -lt $maxIterations) {
        $iteration++
        $result = [regex]::Replace($result, $ifElsePattern, {
            param($match)
            $condition = $match.Groups[1].Value
            $trueBranch = $match.Groups[2].Value
            $falseBranch = $match.Groups[3].Value

            if (Test-TemplateCondition -Condition $condition -Variables $Variables) {
                return $trueBranch
            }
            else {
                return $falseBranch
            }
        })
    }

    # Then process simple if (no else)
    $iteration = 0
    while ($result -match $ifOnlyPattern -and $iteration -lt $maxIterations) {
        $iteration++
        $result = [regex]::Replace($result, $ifOnlyPattern, {
            param($match)
            $condition = $match.Groups[1].Value
            $body = $match.Groups[2].Value

            if (Test-TemplateCondition -Condition $condition -Variables $Variables) {
                return $body
            }
            else {
                return ''
            }
        })
    }

    $result
}

<#
.SYNOPSIS
    Evaluates a template condition.
#>
function Test-TemplateCondition {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [string]$Condition,
        [hashtable]$Variables
    )

    $cond = $Condition.Trim()

    # Handle 'not' prefix
    $negate = $false
    if ($cond -match '^not\s+(.+)$') {
        $negate = $true
        $cond = $Matches[1]
    }

    # Handle comparisons: var == value, var != value, var > value, etc.
    if ($cond -match '^(\S+)\s*(==|!=|>=|<=|>|<)\s*(.+)$') {
        $left = $Matches[1]
        $op = $Matches[2]
        $right = $Matches[3].Trim().Trim('"', "'")

        $leftVal = Get-NestedValue -Variables $Variables -Path $left
        if ($null -eq $leftVal) { $leftVal = $left }

        # Try to parse as number if possible
        $leftNum = $null
        $rightNum = $null
        [double]::TryParse($leftVal, [ref]$leftNum) | Out-Null
        [double]::TryParse($right, [ref]$rightNum) | Out-Null

        $result = switch ($op) {
            '==' { $leftVal -eq $right }
            '!=' { $leftVal -ne $right }
            '>'  { if ($leftNum -ne $null -and $rightNum -ne $null) { $leftNum -gt $rightNum } else { $false } }
            '<'  { if ($leftNum -ne $null -and $rightNum -ne $null) { $leftNum -lt $rightNum } else { $false } }
            '>=' { if ($leftNum -ne $null -and $rightNum -ne $null) { $leftNum -ge $rightNum } else { $false } }
            '<=' { if ($leftNum -ne $null -and $rightNum -ne $null) { $leftNum -le $rightNum } else { $false } }
            default { $false }
        }

        if ($negate) { return -not $result }
        return $result
    }

    # Simple truthy check
    $value = Get-NestedValue -Variables $Variables -Path $cond
    $result = $false

    if ($null -ne $value) {
        if ($value -is [bool]) {
            $result = $value
        }
        elseif ($value -is [string]) {
            $result = -not [string]::IsNullOrEmpty($value)
        }
        elseif ($value -is [array]) {
            $result = $value.Count -gt 0
        }
        else {
            $result = $true
        }
    }

    if ($negate) { return -not $result }
    return $result
}

<#
.SYNOPSIS
    Expands include directives.
#>
function Expand-Includes {
    [CmdletBinding()]
    param(
        [string]$Template,
        [hashtable]$Variables
    )

    # Simple include: {% include "template_name" %}
    $pattern = '\{%\s*include\s+"([^"]+)"\s*%\}'

    $result = [regex]::Replace($Template, $pattern, {
        param($match)
        $includeName = $match.Groups[1].Value

        # Try to find in template library
        $includeTemplate = Get-ConfigTemplate -Name $includeName
        if ($includeTemplate) {
            return Expand-ConfigTemplate -Template $includeTemplate.Content -Variables $Variables
        }

        Write-Warning "Include not found: $includeName"
        return "! Include not found: $includeName"
    })

    $result
}

#endregion

#region Template Library

# Module-level template storage
$script:TemplateLibrary = @{
    Templates = New-Object System.Collections.ArrayList
}

<#
.SYNOPSIS
    Initializes a new template library.
#>
function New-TemplateLibrary {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    @{
        Templates = New-Object System.Collections.ArrayList
    }
}

<#
.SYNOPSIS
    Adds a template to the library.
#>
function Add-ConfigTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSCustomObject]$Template,

        [Parameter()]
        [hashtable]$Library
    )

    process {
        $lib = if ($Library) { $Library } else { $script:TemplateLibrary }

        # Check for duplicate name
        $existing = $lib.Templates | Where-Object { $_.Name -eq $Template.Name } | Select-Object -First 1
        if ($existing) {
            Write-Warning "Template '$($Template.Name)' already exists. Use Update-ConfigTemplate to modify."
            return $null
        }

        $lib.Templates.Add($Template) | Out-Null
        $Template
    }
}

<#
.SYNOPSIS
    Gets templates from the library.
#>
function Get-ConfigTemplate {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Name,

        [Parameter()]
        [string]$Vendor,

        [Parameter()]
        [string]$DeviceType,

        [Parameter()]
        [string]$Category,

        [Parameter()]
        [hashtable]$Library
    )

    $lib = if ($Library) { $Library } else { $script:TemplateLibrary }
    $results = @($lib.Templates)

    if ($Name) {
        $results = @($results | Where-Object { $_.Name -eq $Name -or $_.Name -like "*$Name*" })
    }
    if ($Vendor) {
        $results = @($results | Where-Object { $_.Vendor -eq $Vendor })
    }
    if ($DeviceType) {
        $results = @($results | Where-Object { $_.DeviceType -eq $DeviceType })
    }
    if ($Category) {
        $results = @($results | Where-Object { $_.Category -eq $Category })
    }

    $results
}

<#
.SYNOPSIS
    Updates an existing template.
#>
function Update-ConfigTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter()]
        [hashtable]$Properties,

        [Parameter()]
        [hashtable]$Library
    )

    $lib = if ($Library) { $Library } else { $script:TemplateLibrary }
    $template = $lib.Templates | Where-Object { $_.Name -eq $Name } | Select-Object -First 1

    if (-not $template) {
        Write-Warning "Template '$Name' not found"
        return $null
    }

    foreach ($key in $Properties.Keys) {
        if ($template.PSObject.Properties[$key]) {
            $template.$key = $Properties[$key]
        }
    }
    $template.ModifiedDate = Get-Date

    $template
}

<#
.SYNOPSIS
    Removes a template from the library.
#>
function Remove-ConfigTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter()]
        [hashtable]$Library
    )

    $lib = if ($Library) { $Library } else { $script:TemplateLibrary }
    $template = $lib.Templates | Where-Object { $_.Name -eq $Name } | Select-Object -First 1

    if (-not $template) {
        Write-Warning "Template '$Name' not found"
        return $false
    }

    $lib.Templates.Remove($template)
    $true
}

<#
.SYNOPSIS
    Clears all templates from the library.
#>
function Clear-TemplateLibrary {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable]$Library
    )

    $lib = if ($Library) { $Library } else { $script:TemplateLibrary }
    $lib.Templates.Clear()
}

#endregion

#region Built-in Templates

<#
.SYNOPSIS
    Gets built-in starter templates.
#>
function Get-BuiltInTemplates {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    $templates = @()

    # Basic Access Switch Template
    $templates += New-ConfigTemplate -Name 'access-switch-basic' `
        -Description 'Basic access switch configuration' `
        -Vendor 'Cisco_IOS' -DeviceType 'Access' -Category 'Standard' `
        -Content @'
! {{ hostname }} - Access Switch Configuration
! Generated: {{ generated_date }}
! Template: access-switch-basic

hostname {{ hostname }}

{% if enable_secret %}
enable secret {{ enable_secret }}
{% endif %}

{% if domain_name %}
ip domain-name {{ domain_name }}
{% endif %}

! Management Interface
interface Vlan{{ mgmt_vlan }}
 description Management VLAN
 ip address {{ mgmt_ip }} {{ mgmt_mask }}
 no shutdown

ip default-gateway {{ default_gateway }}

! NTP Configuration
{% for server in ntp_servers %}
ntp server {{ server }}
{% endfor %}

! Logging
{% for server in syslog_servers %}
logging host {{ server }}
{% endfor %}
logging buffered 16384

! SNMP (v3 recommended)
{% if snmp_community %}
snmp-server community {{ snmp_community }} RO
{% endif %}

! SSH Configuration
ip ssh version 2
{% if ssh_timeout %}
ip ssh time-out {{ ssh_timeout }}
{% endif %}

line vty 0 15
 transport input ssh
 login local

! Access Ports
{% for port in access_ports %}
interface {{ port.interface }}
 description {{ port.description }}
 switchport mode access
 switchport access vlan {{ port.vlan }}
{% if port.voice_vlan %}
 switchport voice vlan {{ port.voice_vlan }}
{% endif %}
 spanning-tree portfast
 no shutdown
{% endfor %}

! Trunk Ports
{% for trunk in trunk_ports %}
interface {{ trunk.interface }}
 description {{ trunk.description }}
 switchport mode trunk
 switchport trunk allowed vlan {{ trunk.allowed_vlans }}
 no shutdown
{% endfor %}

end
'@ -DefaultVariables @{
            hostname = 'SW-NEW-01'
            mgmt_vlan = 100
            mgmt_ip = '10.1.100.1'
            mgmt_mask = '255.255.255.0'
            default_gateway = '10.1.100.254'
            ntp_servers = @('10.1.1.1', '10.1.1.2')
            syslog_servers = @('10.1.1.10')
        }

    # VLAN Configuration Template
    $templates += New-ConfigTemplate -Name 'vlan-configuration' `
        -Description 'VLAN definitions and SVI configuration' `
        -Vendor 'Cisco_IOS' -DeviceType 'Other' -Category 'VLAN' `
        -Content @'
! VLAN Configuration
! Generated: {{ generated_date }}

{% for vlan in vlans %}
vlan {{ vlan.id }}
 name {{ vlan.name }}
{% endfor %}

! SVI Interfaces
{% for svi in svis %}
interface Vlan{{ svi.vlan }}
 description {{ svi.description }}
 ip address {{ svi.ip }} {{ svi.mask }}
{% if svi.hsrp_ip %}
 standby 1 ip {{ svi.hsrp_ip }}
 standby 1 priority {{ svi.hsrp_priority }}
 standby 1 preempt
{% endif %}
 no shutdown
{% endfor %}
'@

    # Port Security Template
    $templates += New-ConfigTemplate -Name 'port-security' `
        -Description 'Port security configuration for access ports' `
        -Vendor 'Cisco_IOS' -DeviceType 'Access' -Category 'Security' `
        -Content @'
! Port Security Configuration
! Apply to access ports

{% for port in ports %}
interface {{ port.interface }}
 switchport port-security
 switchport port-security maximum {{ port.max_macs }}
 switchport port-security violation {{ port.violation_action }}
{% if port.sticky %}
 switchport port-security mac-address sticky
{% endif %}
{% endfor %}
'@

    # Banner Template
    $templates += New-ConfigTemplate -Name 'login-banner' `
        -Description 'Standard login banner' `
        -Vendor 'Generic' -DeviceType 'Other' -Category 'Security' `
        -Content @'
banner login ^
************************************************************
*                                                          *
*  AUTHORIZED ACCESS ONLY                                  *
*                                                          *
*  This system is the property of {{ organization }}.      *
*  Unauthorized access is prohibited.                      *
*  All access is logged and monitored.                     *
*                                                          *
*  Site: {{ site_name }}                                   *
*  Contact: {{ contact_email }}                            *
*                                                          *
************************************************************
^
'@

    # Arista EOS Template
    $templates += New-ConfigTemplate -Name 'arista-access-switch' `
        -Description 'Arista EOS access switch configuration' `
        -Vendor 'Arista_EOS' -DeviceType 'Access' -Category 'Standard' `
        -Content @'
! {{ hostname }} - Arista EOS Access Switch
! Generated: {{ generated_date }}

hostname {{ hostname }}

{% if enable_secret %}
enable secret sha512 {{ enable_secret }}
{% endif %}

! Management Interface
interface Management1
 ip address {{ mgmt_ip }}/{{ mgmt_prefix }}

ip route 0.0.0.0/0 {{ default_gateway }}

! NTP
{% for server in ntp_servers %}
ntp server {{ server }}
{% endfor %}

! Logging
{% for server in syslog_servers %}
logging host {{ server }}
{% endfor %}

! SSH
management ssh
 idle-timeout 60

! Access Ports
{% for port in access_ports %}
interface {{ port.interface }}
 description {{ port.description }}
 switchport mode access
 switchport access vlan {{ port.vlan }}
 spanning-tree portfast
 no shutdown
{% endfor %}

! Trunk Ports
{% for trunk in trunk_ports %}
interface {{ trunk.interface }}
 description {{ trunk.description }}
 switchport mode trunk
 switchport trunk allowed vlan {{ trunk.allowed_vlans }}
 no shutdown
{% endfor %}
'@

    $templates
}

<#
.SYNOPSIS
    Loads built-in templates into the library.
#>
function Import-BuiltInTemplates {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable]$Library
    )

    $lib = if ($Library) { $Library } else { $script:TemplateLibrary }
    $builtIn = Get-BuiltInTemplates

    $imported = 0
    foreach ($template in $builtIn) {
        $existing = $lib.Templates | Where-Object { $_.Name -eq $template.Name }
        if (-not $existing) {
            $lib.Templates.Add($template) | Out-Null
            $imported++
        }
    }

    [PSCustomObject]@{
        Imported = $imported
        Total    = $builtIn.Count
    }
}

#endregion

#region Import/Export

<#
.SYNOPSIS
    Exports templates to a JSON file.
#>
function Export-TemplateLibrary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter()]
        [hashtable]$Library
    )

    $lib = if ($Library) { $Library } else { $script:TemplateLibrary }

    $export = @{
        ExportDate = (Get-Date).ToString('o')
        Version    = '1.0'
        Templates  = @($lib.Templates)
    }

    $export | ConvertTo-Json -Depth 10 | Set-Content -Path $Path -Encoding UTF8
}

<#
.SYNOPSIS
    Imports templates from a JSON file.
#>
function Import-TemplateLibrary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter()]
        [switch]$Merge,

        [Parameter()]
        [hashtable]$Library
    )

    if (-not (Test-Path $Path)) {
        Write-Warning "File not found: $Path"
        return $null
    }

    $lib = if ($Library) { $Library } else { $script:TemplateLibrary }
    $content = Get-Content -Path $Path -Raw | ConvertFrom-Json

    if (-not $Merge) {
        $lib.Templates.Clear()
    }

    $imported = 0
    foreach ($template in $content.Templates) {
        $existing = $lib.Templates | Where-Object { $_.Name -eq $template.Name }
        if (-not $existing) {
            $lib.Templates.Add($template) | Out-Null
            $imported++
        }
    }

    [PSCustomObject]@{
        Imported = $imported
        Total    = $content.Templates.Count
    }
}

<#
.SYNOPSIS
    Parses a YAML-like variable file into a hashtable.
#>
function Import-TemplateVariables {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        Write-Warning "File not found: $Path"
        return @{}
    }

    $content = Get-Content -Path $Path -Raw
    $extension = [System.IO.Path]::GetExtension($Path).ToLower()

    if ($extension -eq '.json') {
        return $content | ConvertFrom-Json -AsHashtable
    }

    # Simple YAML-like parser for common cases
    $result = @{}
    $currentList = $null
    $currentListName = $null
    $lines = $content -split "`n"

    foreach ($line in $lines) {
        $line = $line.TrimEnd()

        # Skip comments and empty lines
        if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }

        # List item
        if ($line -match '^\s+-\s+(.+)$') {
            if ($currentList) {
                $item = $Matches[1].Trim().Trim('"', "'")
                $currentList.Add($item) | Out-Null
            }
            continue
        }

        # Key-value pair
        if ($line -match '^(\w+):\s*(.*)$') {
            $key = $Matches[1]
            $value = $Matches[2].Trim().Trim('"', "'")

            # End previous list if any
            if ($currentList -and $currentListName) {
                $result[$currentListName] = @($currentList)
                $currentList = $null
                $currentListName = $null
            }

            if ([string]::IsNullOrEmpty($value)) {
                # Start of a list or nested object
                $currentList = New-Object System.Collections.ArrayList
                $currentListName = $key
            }
            else {
                $result[$key] = $value
            }
        }
    }

    # End final list if any
    if ($currentList -and $currentListName) {
        $result[$currentListName] = @($currentList)
    }

    $result
}

#endregion

#region Utility Functions

<#
.SYNOPSIS
    Generates a configuration from a template and variables.
#>
function New-ConfigFromTemplate {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TemplateName,

        [Parameter()]
        [hashtable]$Variables = @{},

        [Parameter()]
        [string]$VariablesPath,

        [Parameter()]
        [hashtable]$Library,

        [Parameter()]
        [string]$OutputPath
    )

    # Get template
    $lib = if ($Library) { $Library } else { $script:TemplateLibrary }
    $template = $lib.Templates | Where-Object { $_.Name -eq $TemplateName } | Select-Object -First 1

    if (-not $template) {
        Write-Warning "Template '$TemplateName' not found"
        return $null
    }

    # Load variables from file if specified
    $allVars = @{}

    # Start with template defaults
    if ($template.DefaultVariables) {
        foreach ($key in $template.DefaultVariables.Keys) {
            $allVars[$key] = $template.DefaultVariables[$key]
        }
    }

    # Load from file
    if ($VariablesPath) {
        $fileVars = Import-TemplateVariables -Path $VariablesPath
        foreach ($key in $fileVars.Keys) {
            $allVars[$key] = $fileVars[$key]
        }
    }

    # Override with provided variables
    foreach ($key in $Variables.Keys) {
        $allVars[$key] = $Variables[$key]
    }

    # Add automatic variables
    $allVars['generated_date'] = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $allVars['template_name'] = $template.Name
    $allVars['template_version'] = $template.Version

    # Expand template
    $result = Expand-ConfigTemplate -Template $template.Content -Variables $allVars

    # Output
    if ($OutputPath) {
        $result | Set-Content -Path $OutputPath -Encoding UTF8
        Write-Host "Configuration saved to: $OutputPath"
    }

    $result
}

<#
.SYNOPSIS
    Extracts variable names from a template.
#>
function Get-TemplateVariables {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Template
    )

    $variables = @()

    # Find {{ variable }} patterns
    $varPattern = '\{\{\s*([a-zA-Z_][a-zA-Z0-9_\.]*)\s*\}\}'
    $matches = [regex]::Matches($Template, $varPattern)
    foreach ($match in $matches) {
        $variables += $match.Groups[1].Value
    }

    # Find variables in for loops
    $forPattern = '\{%\s*for\s+\w+\s+in\s+(\w+)\s*%\}'
    $matches = [regex]::Matches($Template, $forPattern)
    foreach ($match in $matches) {
        $variables += $match.Groups[1].Value
    }

    # Find variables in conditions
    $ifPattern = '\{%\s*if\s+([a-zA-Z_][a-zA-Z0-9_\.]*)'
    $matches = [regex]::Matches($Template, $ifPattern)
    foreach ($match in $matches) {
        $variables += $match.Groups[1].Value
    }

    $variables | Select-Object -Unique | Sort-Object
}

<#
.SYNOPSIS
    Gets library statistics.
#>
function Get-TemplateLibraryStats {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [hashtable]$Library
    )

    $lib = if ($Library) { $Library } else { $script:TemplateLibrary }
    $templates = @($lib.Templates)

    $byVendor = @{}
    $byDeviceType = @{}
    $byCategory = @{}

    foreach ($t in $templates) {
        if ($t.Vendor) {
            if (-not $byVendor[$t.Vendor]) { $byVendor[$t.Vendor] = 0 }
            $byVendor[$t.Vendor]++
        }
        if ($t.DeviceType) {
            if (-not $byDeviceType[$t.DeviceType]) { $byDeviceType[$t.DeviceType] = 0 }
            $byDeviceType[$t.DeviceType]++
        }
        if ($t.Category) {
            if (-not $byCategory[$t.Category]) { $byCategory[$t.Category] = 0 }
            $byCategory[$t.Category]++
        }
    }

    [PSCustomObject]@{
        TotalTemplates = $templates.Count
        ByVendor       = $byVendor
        ByDeviceType   = $byDeviceType
        ByCategory     = $byCategory
    }
}

#endregion

Export-ModuleMember -Function @(
    'New-ConfigTemplate'
    'New-TemplateVariable'
    'Expand-ConfigTemplate'
    'New-TemplateLibrary'
    'Add-ConfigTemplate'
    'Get-ConfigTemplate'
    'Update-ConfigTemplate'
    'Remove-ConfigTemplate'
    'Clear-TemplateLibrary'
    'Get-BuiltInTemplates'
    'Import-BuiltInTemplates'
    'Export-TemplateLibrary'
    'Import-TemplateLibrary'
    'Import-TemplateVariables'
    'New-ConfigFromTemplate'
    'Get-TemplateVariables'
    'Get-TemplateLibraryStats'
)
