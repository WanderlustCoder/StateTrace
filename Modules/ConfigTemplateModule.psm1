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

#region Configuration Comparison (ST-U-005)

<#
.SYNOPSIS
    Parses configuration text into logical sections.
.DESCRIPTION
    Identifies major sections in network device configs: interfaces, VLANs,
    routing, ACLs, etc. Returns structured section data for semantic comparison.
#>
function Get-ConfigSection {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowEmptyString()]
        [string]$ConfigText,

        [Parameter()]
        [ValidateSet('Cisco_IOS', 'Cisco_IOSXE', 'Arista_EOS', 'Generic')]
        [string]$Vendor = 'Cisco_IOS'
    )

    $lines = $ConfigText -split "`r?`n"
    $sections = [System.Collections.ArrayList]::new()
    $currentSection = $null
    $currentLines = [System.Collections.ArrayList]::new()
    $lineNumber = 0

    # Section start patterns
    $sectionPatterns = @{
        'Interface'  = '^interface\s+'
        'VLAN'       = '^vlan\s+\d+'
        'Router'     = '^router\s+'
        'IPRoute'    = '^ip route\s+'
        'ACL'        = '^(ip\s+)?access-list\s+'
        'RouteMap'   = '^route-map\s+'
        'PrefixList' = '^ip prefix-list\s+'
        'Banner'     = '^banner\s+'
        'Line'       = '^line\s+'
        'SNMP'       = '^snmp-server\s+'
        'Logging'    = '^logging\s+'
        'NTP'        = '^ntp\s+'
        'AAA'        = '^aaa\s+'
        'SpanningTree' = '^spanning-tree\s+'
    }

    foreach ($line in $lines) {
        $lineNumber++
        $trimmed = $line.TrimEnd()

        # Check for section start
        $newSectionType = $null
        $sectionName = $null

        foreach ($type in $sectionPatterns.Keys) {
            if ($trimmed -match $sectionPatterns[$type]) {
                $newSectionType = $type
                $sectionName = $trimmed
                break
            }
        }

        # Check for end of indented block (line doesn't start with space and isn't empty)
        $isIndented = $trimmed -match '^\s+' -or [string]::IsNullOrWhiteSpace($trimmed)
        $isEndMarker = $trimmed -eq '!' -or $trimmed -eq 'exit' -or $trimmed -eq 'end'

        if ($newSectionType) {
            # Save previous section
            if ($currentSection -and $currentLines.Count -gt 0) {
                [void]$sections.Add([PSCustomObject]@{
                    Type = $currentSection.Type
                    Name = $currentSection.Name
                    StartLine = $currentSection.StartLine
                    EndLine = $lineNumber - 1
                    Content = ($currentLines -join "`n")
                    Lines = @($currentLines)
                })
            }

            # Start new section
            $currentSection = @{ Type = $newSectionType; Name = $sectionName; StartLine = $lineNumber }
            $currentLines = [System.Collections.ArrayList]::new()
            [void]$currentLines.Add($trimmed)
        }
        elseif ($currentSection) {
            if ($isEndMarker -and -not $isIndented) {
                # End of section
                [void]$sections.Add([PSCustomObject]@{
                    Type = $currentSection.Type
                    Name = $currentSection.Name
                    StartLine = $currentSection.StartLine
                    EndLine = $lineNumber
                    Content = ($currentLines -join "`n")
                    Lines = @($currentLines)
                })
                $currentSection = $null
                $currentLines = [System.Collections.ArrayList]::new()
            }
            elseif (-not $isIndented -and $trimmed -ne '' -and $trimmed -notmatch '^\s*!') {
                # Non-indented line (not comment) - end section
                [void]$sections.Add([PSCustomObject]@{
                    Type = $currentSection.Type
                    Name = $currentSection.Name
                    StartLine = $currentSection.StartLine
                    EndLine = $lineNumber - 1
                    Content = ($currentLines -join "`n")
                    Lines = @($currentLines)
                })
                $currentSection = $null
                $currentLines = [System.Collections.ArrayList]::new()
            }
            else {
                [void]$currentLines.Add($trimmed)
            }
        }
    }

    # Save final section
    if ($currentSection -and $currentLines.Count -gt 0) {
        [void]$sections.Add([PSCustomObject]@{
            Type = $currentSection.Type
            Name = $currentSection.Name
            StartLine = $currentSection.StartLine
            EndLine = $lineNumber
            Content = ($currentLines -join "`n")
            Lines = @($currentLines)
        })
    }

    return @($sections)
}

<#
.SYNOPSIS
    Compares two configuration texts line by line.
.DESCRIPTION
    Returns differences between two configs with line numbers and change type.
#>
function Compare-ConfigText {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$ReferenceConfig,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$DifferenceConfig,

        [Parameter()]
        [switch]$IgnoreComments,

        [Parameter()]
        [switch]$IgnoreWhitespace,

        [Parameter()]
        [string]$ReferenceName = 'Reference',

        [Parameter()]
        [string]$DifferenceName = 'Difference'
    )

    $refLines = @($ReferenceConfig -split "`r?`n")
    $diffLines = @($DifferenceConfig -split "`r?`n")

    if ($IgnoreComments) {
        $refLines = @($refLines | Where-Object { $_ -notmatch '^\s*!' })
        $diffLines = @($diffLines | Where-Object { $_ -notmatch '^\s*!' })
    }

    if ($IgnoreWhitespace) {
        $refLines = @($refLines | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
        $diffLines = @($diffLines | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    }

    # Build lookup sets
    $refSet = [System.Collections.Generic.HashSet[string]]::new()
    $diffSet = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($line in $refLines) { [void]$refSet.Add($line) }
    foreach ($line in $diffLines) { [void]$diffSet.Add($line) }

    # Find differences
    $removed = [System.Collections.ArrayList]::new()
    $added = [System.Collections.ArrayList]::new()
    $unchanged = [System.Collections.ArrayList]::new()

    $lineNum = 0
    foreach ($line in $refLines) {
        $lineNum++
        if (-not $diffSet.Contains($line)) {
            [void]$removed.Add([PSCustomObject]@{
                LineNumber = $lineNum
                Content = $line
                Source = $ReferenceName
            })
        }
        else {
            [void]$unchanged.Add($line)
        }
    }

    $lineNum = 0
    foreach ($line in $diffLines) {
        $lineNum++
        if (-not $refSet.Contains($line)) {
            [void]$added.Add([PSCustomObject]@{
                LineNumber = $lineNum
                Content = $line
                Source = $DifferenceName
            })
        }
    }

    [PSCustomObject]@{
        ReferenceName = $ReferenceName
        DifferenceName = $DifferenceName
        ReferenceLineCount = $refLines.Count
        DifferenceLineCount = $diffLines.Count
        RemovedCount = $removed.Count
        AddedCount = $added.Count
        UnchangedCount = $unchanged.Count
        Removed = @($removed)
        Added = @($added)
        HasDifferences = ($removed.Count -gt 0 -or $added.Count -gt 0)
        SimilarityPercent = if (($refLines.Count + $diffLines.Count) -gt 0) {
            [math]::Round(($unchanged.Count * 2 / ($refLines.Count + $diffLines.Count)) * 100, 1)
        } else { 100 }
    }
}

<#
.SYNOPSIS
    Compares configurations by logical sections.
.DESCRIPTION
    Performs semantic comparison by parsing configs into sections and comparing
    matching sections (e.g., interface Gi1/0/1 to interface Gi1/0/1).
#>
function Compare-ConfigSections {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReferenceConfig,

        [Parameter(Mandatory = $true)]
        [string]$DifferenceConfig,

        [Parameter()]
        [ValidateSet('Cisco_IOS', 'Cisco_IOSXE', 'Arista_EOS', 'Generic')]
        [string]$Vendor = 'Cisco_IOS',

        [Parameter()]
        [string]$ReferenceName = 'Reference',

        [Parameter()]
        [string]$DifferenceName = 'Difference'
    )

    $refSections = @(Get-ConfigSection -ConfigText $ReferenceConfig -Vendor $Vendor)
    $diffSections = @(Get-ConfigSection -ConfigText $DifferenceConfig -Vendor $Vendor)

    $comparisons = [System.Collections.ArrayList]::new()
    $onlyInRef = [System.Collections.ArrayList]::new()
    $onlyInDiff = [System.Collections.ArrayList]::new()

    # Index difference sections by name
    $diffIndex = @{}
    foreach ($section in $diffSections) {
        $diffIndex[$section.Name] = $section
    }

    $matchedDiff = [System.Collections.Generic.HashSet[string]]::new()

    # Compare reference sections
    foreach ($refSection in $refSections) {
        if ($diffIndex.ContainsKey($refSection.Name)) {
            $diffSection = $diffIndex[$refSection.Name]
            [void]$matchedDiff.Add($refSection.Name)

            $sectionDiff = Compare-ConfigText -ReferenceConfig $refSection.Content `
                -DifferenceConfig $diffSection.Content `
                -ReferenceName $ReferenceName -DifferenceName $DifferenceName

            [void]$comparisons.Add([PSCustomObject]@{
                SectionType = $refSection.Type
                SectionName = $refSection.Name
                Status = if ($sectionDiff.HasDifferences) { 'Modified' } else { 'Unchanged' }
                RefStartLine = $refSection.StartLine
                DiffStartLine = $diffSection.StartLine
                Diff = $sectionDiff
            })
        }
        else {
            [void]$onlyInRef.Add([PSCustomObject]@{
                SectionType = $refSection.Type
                SectionName = $refSection.Name
                StartLine = $refSection.StartLine
                Content = $refSection.Content
            })
        }
    }

    # Find sections only in difference
    foreach ($diffSection in $diffSections) {
        if (-not $matchedDiff.Contains($diffSection.Name)) {
            [void]$onlyInDiff.Add([PSCustomObject]@{
                SectionType = $diffSection.Type
                SectionName = $diffSection.Name
                StartLine = $diffSection.StartLine
                Content = $diffSection.Content
            })
        }
    }

    # Calculate stats
    $modifiedCount = @($comparisons | Where-Object { $_.Status -eq 'Modified' }).Count
    $unchangedCount = @($comparisons | Where-Object { $_.Status -eq 'Unchanged' }).Count

    [PSCustomObject]@{
        ReferenceName = $ReferenceName
        DifferenceName = $DifferenceName
        ReferenceSectionCount = $refSections.Count
        DifferenceSectionCount = $diffSections.Count
        ModifiedSections = $modifiedCount
        UnchangedSections = $unchangedCount
        OnlyInReferenceCount = $onlyInRef.Count
        OnlyInDifferenceCount = $onlyInDiff.Count
        Comparisons = @($comparisons)
        OnlyInReference = @($onlyInRef)
        OnlyInDifference = @($onlyInDiff)
        HasDifferences = ($modifiedCount -gt 0 -or $onlyInRef.Count -gt 0 -or $onlyInDiff.Count -gt 0)
    }
}

<#
.SYNOPSIS
    Generates a comprehensive diff report between configurations.
.DESCRIPTION
    Combines text and section comparison with summary and detailed change listing.
#>
function New-ConfigDiffReport {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReferenceConfig,

        [Parameter(Mandatory = $true)]
        [string]$DifferenceConfig,

        [Parameter()]
        [string]$ReferenceName = 'Baseline',

        [Parameter()]
        [string]$DifferenceName = 'Current',

        [Parameter()]
        [ValidateSet('Cisco_IOS', 'Cisco_IOSXE', 'Arista_EOS', 'Generic')]
        [string]$Vendor = 'Cisco_IOS',

        [Parameter()]
        [switch]$IncludeUnchanged
    )

    $textDiff = Compare-ConfigText -ReferenceConfig $ReferenceConfig `
        -DifferenceConfig $DifferenceConfig `
        -ReferenceName $ReferenceName -DifferenceName $DifferenceName

    $sectionDiff = Compare-ConfigSections -ReferenceConfig $ReferenceConfig `
        -DifferenceConfig $DifferenceConfig `
        -Vendor $Vendor -ReferenceName $ReferenceName -DifferenceName $DifferenceName

    # Build change summary by section type
    $changesByType = @{}
    foreach ($comp in $sectionDiff.Comparisons) {
        if ($comp.Status -eq 'Modified' -or $IncludeUnchanged) {
            if (-not $changesByType[$comp.SectionType]) {
                $changesByType[$comp.SectionType] = [System.Collections.ArrayList]::new()
            }
            [void]$changesByType[$comp.SectionType].Add($comp)
        }
    }

    # Determine overall status
    $overallStatus = if (-not $textDiff.HasDifferences) {
        'Identical'
    }
    elseif ($textDiff.SimilarityPercent -ge 90) {
        'MinorChanges'
    }
    elseif ($textDiff.SimilarityPercent -ge 70) {
        'ModerateChanges'
    }
    else {
        'MajorChanges'
    }

    [PSCustomObject]@{
        ReportID = "DIFF-$(Get-Date -Format 'yyyyMMddHHmmss')"
        GeneratedAt = Get-Date
        ReferenceName = $ReferenceName
        DifferenceName = $DifferenceName
        Vendor = $Vendor
        OverallStatus = $overallStatus
        Summary = [PSCustomObject]@{
            SimilarityPercent = $textDiff.SimilarityPercent
            LinesRemoved = $textDiff.RemovedCount
            LinesAdded = $textDiff.AddedCount
            SectionsModified = $sectionDiff.ModifiedSections
            SectionsOnlyInReference = $sectionDiff.OnlyInReferenceCount
            SectionsOnlyInDifference = $sectionDiff.OnlyInDifferenceCount
        }
        TextDiff = $textDiff
        SectionDiff = $sectionDiff
        ChangesByType = $changesByType
    }
}

<#
.SYNOPSIS
    Compares multiple configurations against a baseline.
.DESCRIPTION
    Identifies drift across a fleet of devices by comparing each against a golden config.
#>
function Get-ConfigDrift {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaselineConfig,

        [Parameter(Mandatory = $true)]
        [hashtable]$DeviceConfigs,

        [Parameter()]
        [string]$BaselineName = 'Golden',

        [Parameter()]
        [ValidateSet('Cisco_IOS', 'Cisco_IOSXE', 'Arista_EOS', 'Generic')]
        [string]$Vendor = 'Cisco_IOS',

        [Parameter()]
        [int]$DriftThreshold = 10
    )

    $results = [System.Collections.ArrayList]::new()

    foreach ($device in $DeviceConfigs.Keys) {
        $config = $DeviceConfigs[$device]
        $diff = Compare-ConfigText -ReferenceConfig $BaselineConfig `
            -DifferenceConfig $config `
            -ReferenceName $BaselineName -DifferenceName $device

        $driftScore = 100 - $diff.SimilarityPercent
        $hasDrift = $driftScore -gt $DriftThreshold

        [void]$results.Add([PSCustomObject]@{
            DeviceName = $device
            SimilarityPercent = $diff.SimilarityPercent
            DriftScore = $driftScore
            HasDrift = $hasDrift
            LinesRemoved = $diff.RemovedCount
            LinesAdded = $diff.AddedCount
            Status = if ($driftScore -eq 0) { 'Compliant' }
                     elseif ($driftScore -le 5) { 'MinorDrift' }
                     elseif ($driftScore -le 15) { 'ModerateDrift' }
                     else { 'MajorDrift' }
            Diff = $diff
        })
    }

    # Sort by drift score descending
    return @($results | Sort-Object -Property DriftScore -Descending)
}

<#
.SYNOPSIS
    Exports a config diff report to various formats.
#>
function Export-ConfigDiffReport {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Report,

        [Parameter()]
        [ValidateSet('Text', 'HTML', 'Markdown', 'JSON')]
        [string]$Format = 'Text',

        [Parameter()]
        [string]$OutputPath
    )

    $output = switch ($Format) {
        'JSON' {
            $Report | ConvertTo-Json -Depth 10
        }

        'Markdown' {
            $md = @()
            $md += "# Configuration Diff Report"
            $md += ""
            $md += "**Generated:** $($Report.GeneratedAt)"
            $md += "**Reference:** $($Report.ReferenceName)"
            $md += "**Difference:** $($Report.DifferenceName)"
            $md += "**Status:** $($Report.OverallStatus)"
            $md += ""
            $md += "## Summary"
            $md += "| Metric | Value |"
            $md += "|--------|-------|"
            $md += "| Similarity | $($Report.Summary.SimilarityPercent)% |"
            $md += "| Lines Removed | $($Report.Summary.LinesRemoved) |"
            $md += "| Lines Added | $($Report.Summary.LinesAdded) |"
            $md += "| Sections Modified | $($Report.Summary.SectionsModified) |"
            $md += ""

            if ($Report.TextDiff.Removed.Count -gt 0) {
                $md += "## Removed Lines"
                $md += '```'
                foreach ($r in $Report.TextDiff.Removed | Select-Object -First 20) {
                    $md += "- $($r.Content)"
                }
                if ($Report.TextDiff.Removed.Count -gt 20) {
                    $md += "... and $($Report.TextDiff.Removed.Count - 20) more"
                }
                $md += '```'
                $md += ""
            }

            if ($Report.TextDiff.Added.Count -gt 0) {
                $md += "## Added Lines"
                $md += '```'
                foreach ($a in $Report.TextDiff.Added | Select-Object -First 20) {
                    $md += "+ $($a.Content)"
                }
                if ($Report.TextDiff.Added.Count -gt 20) {
                    $md += "... and $($Report.TextDiff.Added.Count - 20) more"
                }
                $md += '```'
            }

            $md -join "`n"
        }

        'HTML' {
            @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Config Diff: $($Report.ReferenceName) vs $($Report.DifferenceName)</title>
<style>
body { font-family: Arial, sans-serif; margin: 20px; }
h1 { color: #333; }
.summary { background: #f5f5f5; padding: 15px; border-radius: 5px; margin: 10px 0; }
.removed { background: #ffdddd; color: #990000; }
.added { background: #ddffdd; color: #009900; }
pre { background: #f9f9f9; padding: 10px; border: 1px solid #ddd; overflow-x: auto; }
table { border-collapse: collapse; width: 100%; margin: 10px 0; }
th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
th { background: #007acc; color: white; }
</style>
</head>
<body>
<h1>Configuration Diff Report</h1>
<div class="summary">
<p><strong>Generated:</strong> $($Report.GeneratedAt)</p>
<p><strong>Reference:</strong> $($Report.ReferenceName) | <strong>Difference:</strong> $($Report.DifferenceName)</p>
<p><strong>Status:</strong> $($Report.OverallStatus) | <strong>Similarity:</strong> $($Report.Summary.SimilarityPercent)%</p>
</div>
<h2>Summary</h2>
<table>
<tr><th>Metric</th><th>Value</th></tr>
<tr><td>Lines Removed</td><td>$($Report.Summary.LinesRemoved)</td></tr>
<tr><td>Lines Added</td><td>$($Report.Summary.LinesAdded)</td></tr>
<tr><td>Sections Modified</td><td>$($Report.Summary.SectionsModified)</td></tr>
</table>
$(if ($Report.TextDiff.Removed.Count -gt 0) {
    "<h2>Removed Lines</h2><pre class='removed'>" +
    (($Report.TextDiff.Removed | Select-Object -First 30 | ForEach-Object { "- $($_.Content)" }) -join "`n") +
    "</pre>"
})
$(if ($Report.TextDiff.Added.Count -gt 0) {
    "<h2>Added Lines</h2><pre class='added'>" +
    (($Report.TextDiff.Added | Select-Object -First 30 | ForEach-Object { "+ $($_.Content)" }) -join "`n") +
    "</pre>"
})
</body>
</html>
"@
        }

        default {
            # Text format
            $txt = @()
            $txt += "=" * 60
            $txt += "CONFIGURATION DIFF REPORT"
            $txt += "=" * 60
            $txt += "Generated: $($Report.GeneratedAt)"
            $txt += "Reference: $($Report.ReferenceName)"
            $txt += "Difference: $($Report.DifferenceName)"
            $txt += "Status: $($Report.OverallStatus)"
            $txt += "-" * 60
            $txt += "SUMMARY"
            $txt += "  Similarity: $($Report.Summary.SimilarityPercent)%"
            $txt += "  Lines Removed: $($Report.Summary.LinesRemoved)"
            $txt += "  Lines Added: $($Report.Summary.LinesAdded)"
            $txt += "  Sections Modified: $($Report.Summary.SectionsModified)"
            $txt += "-" * 60

            if ($Report.TextDiff.Removed.Count -gt 0) {
                $txt += "REMOVED LINES:"
                foreach ($r in $Report.TextDiff.Removed | Select-Object -First 30) {
                    $txt += "  - $($r.Content)"
                }
            }

            if ($Report.TextDiff.Added.Count -gt 0) {
                $txt += "ADDED LINES:"
                foreach ($a in $Report.TextDiff.Added | Select-Object -First 30) {
                    $txt += "  + $($a.Content)"
                }
            }

            $txt += "=" * 60
            $txt -join "`n"
        }
    }

    if ($OutputPath) {
        $output | Set-Content -LiteralPath $OutputPath -Encoding UTF8
        return $OutputPath
    }

    return $output
}

#endregion

#region Vendor Syntax Modules (ST-U-006)

<#
.SYNOPSIS
    Auto-detects the vendor from configuration text.
.DESCRIPTION
    Analyzes configuration text to determine which vendor/platform it belongs to.
    Uses distinctive patterns to identify Cisco IOS, IOS-XE, NX-OS, Arista EOS,
    Juniper, and Brocade configurations.
#>
function Get-ConfigVendor {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$ConfigText
    )

    $scores = @{
        'Cisco_IOS'    = 0
        'Cisco_IOSXE'  = 0
        'Cisco_NXOS'   = 0
        'Arista_EOS'   = 0
        'Juniper'      = 0
        'Brocade'      = 0
    }

    $indicators = @{
        'Cisco_IOS' = @(
            @{ Pattern = 'Cisco IOS Software'; Weight = 10 }
            @{ Pattern = 'IOS \(tm\)'; Weight = 10 }
            @{ Pattern = 'switchport mode'; Weight = 2 }
            @{ Pattern = 'spanning-tree portfast'; Weight = 2 }
            @{ Pattern = 'ip classless'; Weight = 3 }
            @{ Pattern = 'line vty'; Weight = 2 }
            @{ Pattern = 'enable secret'; Weight = 2 }
        )
        'Cisco_IOSXE' = @(
            @{ Pattern = 'Cisco IOS XE Software'; Weight = 15 }
            @{ Pattern = 'IOS-XE'; Weight = 10 }
            @{ Pattern = 'license boot level'; Weight = 5 }
            @{ Pattern = 'platform\s+\w+'; Weight = 3 }
        )
        'Cisco_NXOS' = @(
            @{ Pattern = 'Cisco Nexus'; Weight = 15 }
            @{ Pattern = 'NX-OS'; Weight = 10 }
            @{ Pattern = 'feature\s+\w+'; Weight = 5 }
            @{ Pattern = 'vdc\s+'; Weight = 5 }
            @{ Pattern = 'vpc domain'; Weight = 5 }
            @{ Pattern = 'fabricpath'; Weight = 5 }
        )
        'Arista_EOS' = @(
            @{ Pattern = 'Arista'; Weight = 15 }
            @{ Pattern = 'EOS'; Weight = 5 }
            @{ Pattern = 'daemon\s+'; Weight = 3 }
            @{ Pattern = 'transceiver qsfp'; Weight = 5 }
            @{ Pattern = 'management api'; Weight = 5 }
            @{ Pattern = 'vlan internal order'; Weight = 3 }
        )
        'Juniper' = @(
            @{ Pattern = 'set\s+system\s+'; Weight = 10 }
            @{ Pattern = 'set\s+interfaces\s+'; Weight = 5 }
            @{ Pattern = 'junos'; Weight = 15 }
            @{ Pattern = 'policy-options\s+{'; Weight = 5 }
            @{ Pattern = 'protocols\s+{'; Weight = 3 }
            @{ Pattern = 'set\s+routing-options'; Weight = 5 }
        )
        'Brocade' = @(
            @{ Pattern = 'Brocade'; Weight = 15 }
            @{ Pattern = 'FastIron'; Weight = 10 }
            @{ Pattern = 'ICX'; Weight = 10 }
            @{ Pattern = 'module\s+\d+\s+'; Weight = 3 }
            @{ Pattern = 'lag\s+"'; Weight = 5 }
        )
    }

    # Score each vendor
    foreach ($vendor in $indicators.Keys) {
        foreach ($indicator in $indicators[$vendor]) {
            if ($ConfigText -match $indicator.Pattern) {
                $scores[$vendor] += $indicator.Weight
            }
        }
    }

    # Find best match
    $bestVendor = 'Unknown'
    $bestScore = 0
    $confidence = 'Low'

    foreach ($vendor in $scores.Keys) {
        if ($scores[$vendor] -gt $bestScore) {
            $bestScore = $scores[$vendor]
            $bestVendor = $vendor
        }
    }

    if ($bestScore -ge 10) {
        $confidence = 'High'
    }
    elseif ($bestScore -ge 5) {
        $confidence = 'Medium'
    }
    elseif ($bestScore -gt 0) {
        $confidence = 'Low'
    }
    else {
        $bestVendor = 'Generic'
        $confidence = 'None'
    }

    [PSCustomObject]@{
        Vendor     = $bestVendor
        Score      = $bestScore
        Confidence = $confidence
        AllScores  = $scores
    }
}

<#
.SYNOPSIS
    Gets vendor-specific section patterns for config parsing.
.DESCRIPTION
    Returns regex patterns for identifying configuration sections
    specific to each vendor's syntax.
#>
function Get-VendorSectionPatterns {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Cisco_IOS', 'Cisco_IOSXE', 'Cisco_NXOS', 'Arista_EOS', 'Juniper', 'Brocade', 'Generic')]
        [string]$Vendor
    )

    $patterns = @{}

    switch ($Vendor) {
        'Cisco_IOS' {
            $patterns = @{
                Interface     = '^interface\s+(\S+)'
                VLAN          = '^vlan\s+(\d+(?:[-,]\d+)*)'
                Router        = '^router\s+(\S+)\s*(\d*)'
                IPRoute       = '^ip route\s+'
                ACL           = '^(ip\s+)?access-list\s+(standard|extended)?\s*(\S+)'
                RouteMap      = '^route-map\s+(\S+)\s+(permit|deny)\s+(\d+)'
                PrefixList    = '^ip prefix-list\s+(\S+)'
                Banner        = '^banner\s+(motd|login|exec)'
                Line          = '^line\s+(con|aux|vty)\s+(\d+)\s*(\d*)'
                SNMP          = '^snmp-server\s+'
                Logging       = '^logging\s+'
                NTP           = '^ntp\s+'
                AAA           = '^aaa\s+(authentication|authorization|accounting)'
                SpanningTree  = '^spanning-tree\s+'
                ClassMap      = '^class-map\s+'
                PolicyMap     = '^policy-map\s+'
                CryptoMap     = '^crypto\s+map\s+'
                SectionEnd    = '^(!|exit|end)$'
            }
        }

        'Cisco_IOSXE' {
            $patterns = @{
                Interface     = '^interface\s+(\S+)'
                VLAN          = '^vlan\s+(\d+(?:[-,]\d+)*)'
                Router        = '^router\s+(\S+)\s*(\d*)'
                IPRoute       = '^ip route\s+'
                ACL           = '^(ip\s+)?access-list\s+(standard|extended)?\s*(\S+)'
                RouteMap      = '^route-map\s+(\S+)\s+(permit|deny)\s+(\d+)'
                PrefixList    = '^ip prefix-list\s+(\S+)'
                License       = '^license\s+'
                Platform      = '^platform\s+'
                Line          = '^line\s+(con|aux|vty)\s+(\d+)\s*(\d*)'
                AAA           = '^aaa\s+(authentication|authorization|accounting)'
                SectionEnd    = '^(!|exit|end)$'
            }
        }

        'Cisco_NXOS' {
            $patterns = @{
                Interface     = '^interface\s+(\S+)'
                VLAN          = '^vlan\s+(\d+(?:[-,]\d+)*)'
                Router        = '^router\s+(\S+)\s*(\d*)'
                Feature       = '^feature\s+(\S+)'
                VPC           = '^vpc\s+(domain\s+\d+|peer-link)'
                VDC           = '^vdc\s+(\S+)'
                PortChannel   = '^interface\s+port-channel\s*(\d+)'
                RouteMap      = '^route-map\s+(\S+)\s+(permit|deny)\s+(\d+)'
                ACL           = '^ip access-list\s+(\S+)'
                SectionEnd    = '^(!|exit|end)$'
            }
        }

        'Arista_EOS' {
            $patterns = @{
                Interface     = '^interface\s+(\S+)'
                VLAN          = '^vlan\s+(\d+(?:[-,]\d+)*)'
                Router        = '^router\s+(\S+)\s*(\d*)'
                IPRoute       = '^ip route\s+'
                ACL           = '^ip access-list\s+(\S+)'
                RouteMap      = '^route-map\s+(\S+)\s+(permit|deny)\s+(\d+)'
                PrefixList    = '^ip prefix-list\s+(\S+)'
                Daemon        = '^daemon\s+(\S+)'
                ManagementAPI = '^management\s+api\s+(\S+)'
                MLAG          = '^mlag\s+'
                SectionEnd    = '^(!|exit|end)$'
            }
        }

        'Juniper' {
            $patterns = @{
                Interface     = '^(set\s+)?interfaces\s+(\S+)'
                VLAN          = '^(set\s+)?vlans\s+(\S+)'
                Policy        = '^(set\s+)?policy-options\s+'
                Routing       = '^(set\s+)?routing-options\s+'
                Protocols     = '^(set\s+)?protocols\s+(\S+)'
                Security      = '^(set\s+)?security\s+'
                System        = '^(set\s+)?system\s+'
                Firewall      = '^(set\s+)?firewall\s+'
                SectionEnd    = '^}'
            }
        }

        'Brocade' {
            $patterns = @{
                Interface     = '^interface\s+(ethernet|ve|loopback)\s*(\S*)'
                VLAN          = '^vlan\s+(\d+(?:[-,]\d+)*)'
                Router        = '^router\s+(\S+)\s*(\d*)'
                LAG           = '^lag\s+"([^"]+)"'
                ACL           = '^(ip\s+)?access-list\s+(\S+)'
                SpanningTree  = '^spanning-tree\s+'
                SectionEnd    = '^(!|exit|end)$'
            }
        }

        default {
            $patterns = @{
                Interface     = '^interface\s+'
                VLAN          = '^vlan\s+\d+'
                Router        = '^router\s+'
                ACL           = '^access-list\s+'
                SectionEnd    = '^(!|exit|end)$'
            }
        }
    }

    return $patterns
}

<#
.SYNOPSIS
    Parses interface names into normalized components.
.DESCRIPTION
    Breaks down interface names into type, module, port components
    using vendor-specific naming conventions.
#>
function Get-VendorInterfaceNaming {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InterfaceName,

        [Parameter()]
        [ValidateSet('Cisco_IOS', 'Cisco_IOSXE', 'Cisco_NXOS', 'Arista_EOS', 'Juniper', 'Brocade', 'Generic')]
        [string]$Vendor = 'Cisco_IOS'
    )

    $result = [PSCustomObject]@{
        Original     = $InterfaceName
        Type         = 'Unknown'
        TypeShort    = ''
        TypeLong     = ''
        Module       = $null
        Slot         = $null
        Port         = $null
        SubInterface = $null
        IsVirtual    = $false
        Speed        = $null
    }

    # Common interface type mappings
    $typeMap = @{
        'Gi'  = @{ Short = 'Gi'; Long = 'GigabitEthernet'; Speed = '1G' }
        'Gig' = @{ Short = 'Gi'; Long = 'GigabitEthernet'; Speed = '1G' }
        'GigabitEthernet' = @{ Short = 'Gi'; Long = 'GigabitEthernet'; Speed = '1G' }
        'Te'  = @{ Short = 'Te'; Long = 'TenGigabitEthernet'; Speed = '10G' }
        'TenGig' = @{ Short = 'Te'; Long = 'TenGigabitEthernet'; Speed = '10G' }
        'TenGigabitEthernet' = @{ Short = 'Te'; Long = 'TenGigabitEthernet'; Speed = '10G' }
        'Tw'  = @{ Short = 'Tw'; Long = 'TwentyFiveGigE'; Speed = '25G' }
        'Fo'  = @{ Short = 'Fo'; Long = 'FortyGigabitEthernet'; Speed = '40G' }
        'Hu'  = @{ Short = 'Hu'; Long = 'HundredGigE'; Speed = '100G' }
        'Fa'  = @{ Short = 'Fa'; Long = 'FastEthernet'; Speed = '100M' }
        'FastEthernet' = @{ Short = 'Fa'; Long = 'FastEthernet'; Speed = '100M' }
        'Et'  = @{ Short = 'Et'; Long = 'Ethernet'; Speed = $null }
        'Ethernet' = @{ Short = 'Et'; Long = 'Ethernet'; Speed = $null }
        'Eth' = @{ Short = 'Et'; Long = 'Ethernet'; Speed = $null }
        'Po'  = @{ Short = 'Po'; Long = 'Port-channel'; Speed = $null; Virtual = $true }
        'Port-channel' = @{ Short = 'Po'; Long = 'Port-channel'; Speed = $null; Virtual = $true }
        'Vlan' = @{ Short = 'Vl'; Long = 'Vlan'; Speed = $null; Virtual = $true }
        'Vl'  = @{ Short = 'Vl'; Long = 'Vlan'; Speed = $null; Virtual = $true }
        'Lo'  = @{ Short = 'Lo'; Long = 'Loopback'; Speed = $null; Virtual = $true }
        'Loopback' = @{ Short = 'Lo'; Long = 'Loopback'; Speed = $null; Virtual = $true }
        'Tu'  = @{ Short = 'Tu'; Long = 'Tunnel'; Speed = $null; Virtual = $true }
        'Tunnel' = @{ Short = 'Tu'; Long = 'Tunnel'; Speed = $null; Virtual = $true }
        'Mgmt' = @{ Short = 'Ma'; Long = 'Management'; Speed = $null }
        'Management' = @{ Short = 'Ma'; Long = 'Management'; Speed = $null }
        'Ma'  = @{ Short = 'Ma'; Long = 'Management'; Speed = $null }
    }

    # Parse based on vendor
    switch ($Vendor) {
        { $_ -in 'Cisco_IOS', 'Cisco_IOSXE', 'Generic' } {
            # Cisco format: Type[Module/]Slot/Port[.SubInt]
            if ($InterfaceName -match '^(\D+)(\d+(?:/\d+)*(?:\.\d+)?)$') {
                $typeStr = $Matches[1]
                $numbering = $Matches[2]

                if ($typeMap.ContainsKey($typeStr)) {
                    $result.Type = $typeMap[$typeStr].Long
                    $result.TypeShort = $typeMap[$typeStr].Short
                    $result.TypeLong = $typeMap[$typeStr].Long
                    $result.Speed = $typeMap[$typeStr].Speed
                    $result.IsVirtual = if ($typeMap[$typeStr].ContainsKey('Virtual')) { $typeMap[$typeStr].Virtual } else { $false }
                }
                else {
                    $result.Type = $typeStr
                    $result.TypeShort = $typeStr
                    $result.TypeLong = $typeStr
                }

                # Parse numbering
                if ($numbering -match '^(\d+)/(\d+)/(\d+)(?:\.(\d+))?$') {
                    $result.Module = [int]$Matches[1]
                    $result.Slot = [int]$Matches[2]
                    $result.Port = [int]$Matches[3]
                    if ($Matches[4]) { $result.SubInterface = [int]$Matches[4] }
                }
                elseif ($numbering -match '^(\d+)/(\d+)(?:\.(\d+))?$') {
                    $result.Slot = [int]$Matches[1]
                    $result.Port = [int]$Matches[2]
                    if ($Matches[3]) { $result.SubInterface = [int]$Matches[3] }
                }
                elseif ($numbering -match '^(\d+)(?:\.(\d+))?$') {
                    $result.Port = [int]$Matches[1]
                    if ($Matches[2]) { $result.SubInterface = [int]$Matches[2] }
                }
            }
        }

        'Cisco_NXOS' {
            # NX-OS format similar but with Ethernet prefix common
            if ($InterfaceName -match '^(\D+)(\d+(?:/\d+)*)$') {
                $typeStr = $Matches[1]
                $numbering = $Matches[2]

                if ($typeMap.ContainsKey($typeStr)) {
                    $result.Type = $typeMap[$typeStr].Long
                    $result.TypeShort = $typeMap[$typeStr].Short
                    $result.TypeLong = $typeMap[$typeStr].Long
                    $result.Speed = $typeMap[$typeStr].Speed
                    $result.IsVirtual = if ($typeMap[$typeStr].ContainsKey('Virtual')) { $typeMap[$typeStr].Virtual } else { $false }
                }

                if ($numbering -match '^(\d+)/(\d+)(?:/(\d+))?$') {
                    $result.Module = [int]$Matches[1]
                    $result.Port = [int]$Matches[2]
                    if ($Matches[3]) { $result.SubInterface = [int]$Matches[3] }
                }
            }
        }

        'Arista_EOS' {
            # Arista format: Ethernet1/2 or Et1/2
            if ($InterfaceName -match '^(\D+)(\d+(?:/\d+)*)$') {
                $typeStr = $Matches[1]
                $numbering = $Matches[2]

                if ($typeMap.ContainsKey($typeStr)) {
                    $result.Type = $typeMap[$typeStr].Long
                    $result.TypeShort = $typeMap[$typeStr].Short
                    $result.TypeLong = $typeMap[$typeStr].Long
                    $result.Speed = $typeMap[$typeStr].Speed
                    $result.IsVirtual = if ($typeMap[$typeStr].ContainsKey('Virtual')) { $typeMap[$typeStr].Virtual } else { $false }
                }

                if ($numbering -match '^(\d+)/(\d+)$') {
                    $result.Module = [int]$Matches[1]
                    $result.Port = [int]$Matches[2]
                }
                elseif ($numbering -match '^(\d+)$') {
                    $result.Port = [int]$Matches[1]
                }
            }
        }

        'Juniper' {
            # Juniper format: ge-0/0/0 or xe-0/0/0
            if ($InterfaceName -match '^(ge|xe|et|ae|lo|vlan|irb)-?(\d+(?:/\d+)*)(?:\.(\d+))?$') {
                $typeStr = $Matches[1].ToLower()
                $numbering = $Matches[2]

                $juniperTypes = @{
                    'ge' = @{ Short = 'ge'; Long = 'GigabitEthernet'; Speed = '1G' }
                    'xe' = @{ Short = 'xe'; Long = 'TenGigabitEthernet'; Speed = '10G' }
                    'et' = @{ Short = 'et'; Long = 'HundredGigE'; Speed = '100G' }
                    'ae' = @{ Short = 'ae'; Long = 'AggregatedEthernet'; Speed = $null; Virtual = $true }
                    'lo' = @{ Short = 'lo'; Long = 'Loopback'; Speed = $null; Virtual = $true }
                    'vlan' = @{ Short = 'vlan'; Long = 'VLAN'; Speed = $null; Virtual = $true }
                    'irb' = @{ Short = 'irb'; Long = 'IRB'; Speed = $null; Virtual = $true }
                }

                if ($juniperTypes.ContainsKey($typeStr)) {
                    $result.Type = $juniperTypes[$typeStr].Long
                    $result.TypeShort = $juniperTypes[$typeStr].Short
                    $result.TypeLong = $juniperTypes[$typeStr].Long
                    $result.Speed = $juniperTypes[$typeStr].Speed
                    $result.IsVirtual = if ($juniperTypes[$typeStr].ContainsKey('Virtual')) { $juniperTypes[$typeStr].Virtual } else { $false }
                }

                if ($numbering -match '^(\d+)/(\d+)/(\d+)$') {
                    $result.Module = [int]$Matches[1]
                    $result.Slot = [int]$Matches[2]
                    $result.Port = [int]$Matches[3]
                }
                if ($Matches[3]) { $result.SubInterface = [int]$Matches[3] }
            }
        }

        'Brocade' {
            # Brocade format: ethernet 1/1/1
            if ($InterfaceName -match '^(ethernet|ve|loopback)\s*(\d+(?:/\d+)*)$') {
                $typeStr = $Matches[1].ToLower()
                $numbering = $Matches[2]

                $brocadeTypes = @{
                    'ethernet' = @{ Short = 'e'; Long = 'Ethernet'; Speed = $null }
                    've' = @{ Short = 've'; Long = 'VirtualEthernet'; Speed = $null; Virtual = $true }
                    'loopback' = @{ Short = 'lo'; Long = 'Loopback'; Speed = $null; Virtual = $true }
                }

                if ($brocadeTypes.ContainsKey($typeStr)) {
                    $result.Type = $brocadeTypes[$typeStr].Long
                    $result.TypeShort = $brocadeTypes[$typeStr].Short
                    $result.TypeLong = $brocadeTypes[$typeStr].Long
                    $result.Speed = $brocadeTypes[$typeStr].Speed
                    $result.IsVirtual = if ($brocadeTypes[$typeStr].ContainsKey('Virtual')) { $brocadeTypes[$typeStr].Virtual } else { $false }
                }

                if ($numbering -match '^(\d+)/(\d+)/(\d+)$') {
                    $result.Module = [int]$Matches[1]
                    $result.Slot = [int]$Matches[2]
                    $result.Port = [int]$Matches[3]
                }
            }
        }
    }

    return $result
}

<#
.SYNOPSIS
    Converts configuration commands to a different vendor's syntax.
.DESCRIPTION
    Translates common configuration commands between vendor syntaxes.
    Useful for migrations or creating multi-vendor templates.
#>
function ConvertTo-VendorSyntax {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Command,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Cisco_IOS', 'Cisco_IOSXE', 'Cisco_NXOS', 'Arista_EOS', 'Juniper', 'Brocade')]
        [string]$FromVendor,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Cisco_IOS', 'Cisco_IOSXE', 'Cisco_NXOS', 'Arista_EOS', 'Juniper', 'Brocade')]
        [string]$ToVendor
    )

    # If same vendor, return as-is
    if ($FromVendor -eq $ToVendor) {
        return $Command
    }

    $translated = $Command.Trim()

    # Translation rules organized by command type
    $translations = @{
        # Interface access mode
        'switchport mode access' = @{
            'Cisco_IOS' = 'switchport mode access'
            'Cisco_IOSXE' = 'switchport mode access'
            'Cisco_NXOS' = 'switchport mode access'
            'Arista_EOS' = 'switchport mode access'
            'Juniper' = 'set interface-mode access'
            'Brocade' = 'switchport mode access'
        }
        # Interface trunk mode
        'switchport mode trunk' = @{
            'Cisco_IOS' = 'switchport mode trunk'
            'Cisco_IOSXE' = 'switchport mode trunk'
            'Cisco_NXOS' = 'switchport mode trunk'
            'Arista_EOS' = 'switchport mode trunk'
            'Juniper' = 'set interface-mode trunk'
            'Brocade' = 'switchport mode trunk'
        }
        # Spanning tree portfast
        'spanning-tree portfast' = @{
            'Cisco_IOS' = 'spanning-tree portfast'
            'Cisco_IOSXE' = 'spanning-tree portfast'
            'Cisco_NXOS' = 'spanning-tree port type edge'
            'Arista_EOS' = 'spanning-tree portfast'
            'Juniper' = 'set protocols rstp interface <int> edge'
            'Brocade' = 'spanning-tree 802-1w admin-edge-port'
        }
        # Enable password encryption
        'service password-encryption' = @{
            'Cisco_IOS' = 'service password-encryption'
            'Cisco_IOSXE' = 'service password-encryption'
            'Cisco_NXOS' = 'feature password encryption aes'
            'Arista_EOS' = 'service password-encryption'
            'Juniper' = 'set system services password-encryption'
            'Brocade' = 'service password-encryption'
        }
        # SSH version 2
        'ip ssh version 2' = @{
            'Cisco_IOS' = 'ip ssh version 2'
            'Cisco_IOSXE' = 'ip ssh version 2'
            'Cisco_NXOS' = 'ssh version 2'
            'Arista_EOS' = 'ip ssh version 2'
            'Juniper' = 'set system services ssh protocol-version v2'
            'Brocade' = 'ip ssh version 2'
        }
        # No IP routing
        'no ip routing' = @{
            'Cisco_IOS' = 'no ip routing'
            'Cisco_IOSXE' = 'no ip routing'
            'Cisco_NXOS' = 'no ip routing'
            'Arista_EOS' = 'no ip routing'
            'Juniper' = 'delete routing-options'
            'Brocade' = 'no ip routing'
        }
    }

    # Check exact matches first
    foreach ($pattern in $translations.Keys) {
        if ($translated -eq $pattern -or $translated -match "^$([regex]::Escape($pattern))$") {
            if ($translations[$pattern].ContainsKey($ToVendor)) {
                return $translations[$pattern][$ToVendor]
            }
        }
    }

    # Pattern-based translations
    # VLAN assignment
    if ($translated -match '^switchport access vlan (\d+)$') {
        $vlanId = $Matches[1]
        switch ($ToVendor) {
            'Juniper' { return "set vlan members vlan$vlanId" }
            default { return "switchport access vlan $vlanId" }
        }
    }

    # Description
    if ($translated -match '^description (.+)$') {
        $desc = $Matches[1]
        switch ($ToVendor) {
            'Juniper' { return "set description `"$desc`"" }
            default { return "description $desc" }
        }
    }

    # NTP server
    if ($translated -match '^ntp server (\S+)$') {
        $server = $Matches[1]
        switch ($ToVendor) {
            'Juniper' { return "set system ntp server $server" }
            'Cisco_NXOS' { return "ntp server $server use-vrf default" }
            default { return "ntp server $server" }
        }
    }

    # Hostname
    if ($translated -match '^hostname (\S+)$') {
        $name = $Matches[1]
        switch ($ToVendor) {
            'Juniper' { return "set system host-name $name" }
            default { return "hostname $name" }
        }
    }

    # IP address on interface
    if ($translated -match '^ip address (\S+)\s+(\S+)$') {
        $ip = $Matches[1]
        $mask = $Matches[2]
        switch ($ToVendor) {
            'Juniper' {
                # Convert mask to prefix
                $prefix = (($mask -split '\.' | ForEach-Object { [Convert]::ToString([int]$_, 2) }) -join '' -replace '0', '').Length
                return "set family inet address $ip/$prefix"
            }
            default { return "ip address $ip $mask" }
        }
    }

    # No shutdown
    if ($translated -match '^no shutdown$') {
        switch ($ToVendor) {
            'Juniper' { return 'delete disable' }
            default { return 'no shutdown' }
        }
    }

    # Shutdown
    if ($translated -match '^shutdown$') {
        switch ($ToVendor) {
            'Juniper' { return 'set disable' }
            default { return 'shutdown' }
        }
    }

    # If no translation found, return original with a comment
    return "! TODO: Manual translation needed: $translated"
}

<#
.SYNOPSIS
    Gets a list of common commands for a specific vendor.
.DESCRIPTION
    Returns frequently used configuration commands specific to each vendor
    for quick reference or template generation.
#>
function Get-VendorCommandReference {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Cisco_IOS', 'Cisco_IOSXE', 'Cisco_NXOS', 'Arista_EOS', 'Juniper', 'Brocade')]
        [string]$Vendor,

        [Parameter()]
        [ValidateSet('Interface', 'VLAN', 'Routing', 'Security', 'Management', 'All')]
        [string]$Category = 'All'
    )

    $commands = [System.Collections.ArrayList]::new()

    $allCommands = @{
        'Cisco_IOS' = @{
            'Interface' = @(
                @{ Command = 'interface GigabitEthernet0/1'; Description = 'Enter interface config mode' }
                @{ Command = 'switchport mode access'; Description = 'Set port to access mode' }
                @{ Command = 'switchport mode trunk'; Description = 'Set port to trunk mode' }
                @{ Command = 'switchport access vlan <id>'; Description = 'Assign access VLAN' }
                @{ Command = 'switchport trunk allowed vlan <list>'; Description = 'Set allowed VLANs on trunk' }
                @{ Command = 'spanning-tree portfast'; Description = 'Enable PortFast' }
                @{ Command = 'no shutdown'; Description = 'Enable interface' }
                @{ Command = 'description <text>'; Description = 'Set interface description' }
            )
            'VLAN' = @(
                @{ Command = 'vlan <id>'; Description = 'Create/enter VLAN' }
                @{ Command = 'name <name>'; Description = 'Set VLAN name' }
                @{ Command = 'interface Vlan<id>'; Description = 'Create SVI' }
            )
            'Routing' = @(
                @{ Command = 'ip route <net> <mask> <next-hop>'; Description = 'Static route' }
                @{ Command = 'router ospf <id>'; Description = 'Enable OSPF' }
                @{ Command = 'router bgp <asn>'; Description = 'Enable BGP' }
            )
            'Security' = @(
                @{ Command = 'enable secret <password>'; Description = 'Set enable password' }
                @{ Command = 'service password-encryption'; Description = 'Encrypt passwords' }
                @{ Command = 'ip ssh version 2'; Description = 'Enable SSH v2' }
                @{ Command = 'line vty 0 15'; Description = 'Configure VTY lines' }
                @{ Command = 'transport input ssh'; Description = 'SSH only on VTY' }
            )
            'Management' = @(
                @{ Command = 'hostname <name>'; Description = 'Set hostname' }
                @{ Command = 'ntp server <ip>'; Description = 'Configure NTP' }
                @{ Command = 'logging <ip>'; Description = 'Configure syslog' }
                @{ Command = 'snmp-server community <string> RO'; Description = 'SNMP community' }
            )
        }
        'Arista_EOS' = @{
            'Interface' = @(
                @{ Command = 'interface Ethernet1'; Description = 'Enter interface config mode' }
                @{ Command = 'switchport mode access'; Description = 'Set port to access mode' }
                @{ Command = 'switchport mode trunk'; Description = 'Set port to trunk mode' }
                @{ Command = 'switchport access vlan <id>'; Description = 'Assign access VLAN' }
                @{ Command = 'switchport trunk allowed vlan <list>'; Description = 'Set allowed VLANs' }
                @{ Command = 'spanning-tree portfast'; Description = 'Enable PortFast' }
                @{ Command = 'no shutdown'; Description = 'Enable interface' }
            )
            'VLAN' = @(
                @{ Command = 'vlan <id>'; Description = 'Create/enter VLAN' }
                @{ Command = 'name <name>'; Description = 'Set VLAN name' }
                @{ Command = 'interface Vlan<id>'; Description = 'Create SVI' }
            )
            'Routing' = @(
                @{ Command = 'ip route <net>/<prefix> <next-hop>'; Description = 'Static route' }
                @{ Command = 'router ospf <id>'; Description = 'Enable OSPF' }
                @{ Command = 'router bgp <asn>'; Description = 'Enable BGP' }
            )
            'Security' = @(
                @{ Command = 'enable secret <password>'; Description = 'Set enable password' }
                @{ Command = 'management api http-commands'; Description = 'Enable eAPI' }
                @{ Command = 'username <name> privilege 15 secret <pw>'; Description = 'Create user' }
            )
            'Management' = @(
                @{ Command = 'hostname <name>'; Description = 'Set hostname' }
                @{ Command = 'ntp server <ip>'; Description = 'Configure NTP' }
                @{ Command = 'logging host <ip>'; Description = 'Configure syslog' }
            )
        }
        'Juniper' = @{
            'Interface' = @(
                @{ Command = 'set interfaces ge-0/0/0 unit 0'; Description = 'Configure interface' }
                @{ Command = 'set interface-mode access'; Description = 'Set port to access mode' }
                @{ Command = 'set interface-mode trunk'; Description = 'Set port to trunk mode' }
                @{ Command = 'set vlan members <name>'; Description = 'Assign VLAN' }
                @{ Command = 'set family ethernet-switching'; Description = 'Enable L2 switching' }
            )
            'VLAN' = @(
                @{ Command = 'set vlans <name> vlan-id <id>'; Description = 'Create VLAN' }
                @{ Command = 'set vlans <name> l3-interface irb.<id>'; Description = 'Create IRB' }
            )
            'Routing' = @(
                @{ Command = 'set routing-options static route <net> next-hop <ip>'; Description = 'Static route' }
                @{ Command = 'set protocols ospf area 0'; Description = 'Enable OSPF' }
                @{ Command = 'set protocols bgp group <name>'; Description = 'Enable BGP' }
            )
            'Security' = @(
                @{ Command = 'set system login user <name> class super-user'; Description = 'Create user' }
                @{ Command = 'set system services ssh protocol-version v2'; Description = 'SSH v2' }
            )
            'Management' = @(
                @{ Command = 'set system host-name <name>'; Description = 'Set hostname' }
                @{ Command = 'set system ntp server <ip>'; Description = 'Configure NTP' }
                @{ Command = 'set system syslog host <ip>'; Description = 'Configure syslog' }
            )
        }
    }

    # Default to Cisco IOS if vendor not fully defined
    if (-not $allCommands.ContainsKey($Vendor)) {
        $Vendor = 'Cisco_IOS'
    }

    $vendorCommands = $allCommands[$Vendor]

    if ($Category -eq 'All') {
        foreach ($cat in $vendorCommands.Keys) {
            foreach ($cmd in $vendorCommands[$cat]) {
                [void]$commands.Add([PSCustomObject]@{
                    Vendor      = $Vendor
                    Category    = $cat
                    Command     = $cmd.Command
                    Description = $cmd.Description
                })
            }
        }
    }
    elseif ($vendorCommands.ContainsKey($Category)) {
        foreach ($cmd in $vendorCommands[$Category]) {
            [void]$commands.Add([PSCustomObject]@{
                Vendor      = $Vendor
                Category    = $Category
                Command     = $cmd.Command
                Description = $cmd.Description
            })
        }
    }

    return @($commands)
}

<#
.SYNOPSIS
    Normalizes configuration text to a standard format.
.DESCRIPTION
    Converts vendor-specific configuration to a normalized intermediate format
    that can be compared across vendors or converted to another vendor's syntax.
#>
function ConvertTo-NormalizedConfig {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigText,

        [Parameter()]
        [ValidateSet('Cisco_IOS', 'Cisco_IOSXE', 'Cisco_NXOS', 'Arista_EOS', 'Juniper', 'Brocade', 'Auto')]
        [string]$Vendor = 'Auto'
    )

    # Auto-detect vendor if needed
    if ($Vendor -eq 'Auto') {
        $detection = Get-ConfigVendor -ConfigText $ConfigText
        $Vendor = if ($detection.Vendor -eq 'Unknown') { 'Cisco_IOS' } else { $detection.Vendor }
    }

    $normalized = [System.Collections.ArrayList]::new()
    $lines = $ConfigText -split "`r?`n"
    $currentContext = @()

    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed -eq '!' -or $trimmed -match '^#') {
            continue
        }

        $entry = [PSCustomObject]@{
            Type       = 'Unknown'
            Context    = @()
            Key        = ''
            Value      = ''
            Original   = $trimmed
            Vendor     = $Vendor
        }

        # Detect indentation level for context tracking
        $indent = 0
        if ($line -match '^(\s+)') {
            $indent = $Matches[1].Length
        }

        # Normalize based on line content
        switch -Regex ($trimmed) {
            '^hostname\s+(\S+)$' {
                $entry.Type = 'System'
                $entry.Key = 'hostname'
                $entry.Value = $Matches[1]
                break
            }
            '^interface\s+(.+)$' {
                $entry.Type = 'InterfaceDeclaration'
                $entry.Key = 'interface'
                $entry.Value = $Matches[1]
                $currentContext = @('interface', $Matches[1])
                break
            }
            '^vlan\s+(\d+)$' {
                $entry.Type = 'VLANDeclaration'
                $entry.Key = 'vlan'
                $entry.Value = $Matches[1]
                $currentContext = @('vlan', $Matches[1])
                break
            }
            '^\s*name\s+(.+)$' {
                $entry.Type = 'VLANName'
                $entry.Key = 'name'
                $entry.Value = $Matches[1]
                $entry.Context = $currentContext
                break
            }
            '^\s*description\s+(.+)$' {
                $entry.Type = 'Description'
                $entry.Key = 'description'
                $entry.Value = $Matches[1]
                $entry.Context = $currentContext
                break
            }
            '^\s*ip address\s+(\S+)\s+(\S+)$' {
                $entry.Type = 'IPAddress'
                $entry.Key = 'ip_address'
                $entry.Value = "$($Matches[1])/$($Matches[2])"
                $entry.Context = $currentContext
                break
            }
            '^\s*switchport mode\s+(access|trunk)$' {
                $entry.Type = 'SwitchportMode'
                $entry.Key = 'switchport_mode'
                $entry.Value = $Matches[1]
                $entry.Context = $currentContext
                break
            }
            '^\s*switchport access vlan\s+(\d+)$' {
                $entry.Type = 'AccessVLAN'
                $entry.Key = 'access_vlan'
                $entry.Value = $Matches[1]
                $entry.Context = $currentContext
                break
            }
            '^\s*spanning-tree portfast$' {
                $entry.Type = 'SpanningTree'
                $entry.Key = 'portfast'
                $entry.Value = 'enabled'
                $entry.Context = $currentContext
                break
            }
            '^\s*no shutdown$' {
                $entry.Type = 'AdminStatus'
                $entry.Key = 'admin_status'
                $entry.Value = 'up'
                $entry.Context = $currentContext
                break
            }
            '^\s*shutdown$' {
                $entry.Type = 'AdminStatus'
                $entry.Key = 'admin_status'
                $entry.Value = 'down'
                $entry.Context = $currentContext
                break
            }
            '^ntp server\s+(\S+)' {
                $entry.Type = 'NTP'
                $entry.Key = 'ntp_server'
                $entry.Value = $Matches[1]
                break
            }
            '^ip route\s+(\S+)\s+(\S+)\s+(\S+)' {
                $entry.Type = 'StaticRoute'
                $entry.Key = 'static_route'
                $entry.Value = "$($Matches[1])/$($Matches[2]) via $($Matches[3])"
                break
            }
            default {
                $entry.Type = 'Other'
                $entry.Key = 'raw'
                $entry.Value = $trimmed
                if ($indent -gt 0) {
                    $entry.Context = $currentContext
                }
            }
        }

        [void]$normalized.Add($entry)
    }

    return @($normalized)
}

#endregion

Export-ModuleMember -Function @(
    # Template functions
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
    # Configuration Comparison (ST-U-005)
    'Get-ConfigSection'
    'Compare-ConfigText'
    'Compare-ConfigSections'
    'New-ConfigDiffReport'
    'Get-ConfigDrift'
    'Export-ConfigDiffReport'
    # Vendor Syntax Modules (ST-U-006)
    'Get-ConfigVendor'
    'Get-VendorSectionPatterns'
    'Get-VendorInterfaceNaming'
    'ConvertTo-VendorSyntax'
    'Get-VendorCommandReference'
    'ConvertTo-NormalizedConfig'
)
