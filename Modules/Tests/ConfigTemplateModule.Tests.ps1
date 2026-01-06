Set-StrictMode -Version Latest

$modulePath = Join-Path $PSScriptRoot '..\ConfigTemplateModule.psm1'
Import-Module $modulePath -Force

Describe 'ConfigTemplateModule' {

    Context 'New-ConfigTemplate' {
        It 'creates template with required parameters' {
            $template = New-ConfigTemplate -Name 'test-template' -Content 'hostname {{ hostname }}'
            $template | Should Not BeNullOrEmpty
            $template.Name | Should Be 'test-template'
            $template.Content | Should Be 'hostname {{ hostname }}'
            $template.TemplateID | Should Not BeNullOrEmpty
        }

        It 'sets default values' {
            $template = New-ConfigTemplate -Name 'test' -Content 'test'
            $template.Vendor | Should Be 'Generic'
            $template.DeviceType | Should Be 'Other'
            $template.Version | Should Be '1.0'
        }

        It 'accepts optional parameters' {
            $template = New-ConfigTemplate -Name 'test' -Content 'test' `
                -Description 'Test desc' -Vendor 'Cisco_IOS' -DeviceType 'Access' `
                -Category 'Standard' -Author 'Tester'
            $template.Description | Should Be 'Test desc'
            $template.Vendor | Should Be 'Cisco_IOS'
            $template.DeviceType | Should Be 'Access'
            $template.Category | Should Be 'Standard'
            $template.Author | Should Be 'Tester'
        }
    }

    Context 'Expand-ConfigTemplate - Variables' {
        It 'expands simple variables' {
            $template = 'hostname {{ hostname }}'
            $vars = @{ hostname = 'SW-01' }
            $result = Expand-ConfigTemplate -Template $template -Variables $vars
            $result | Should Be 'hostname SW-01'
        }

        It 'expands multiple variables' {
            $template = 'ip address {{ ip }} {{ mask }}'
            $vars = @{ ip = '10.1.1.1'; mask = '255.255.255.0' }
            $result = Expand-ConfigTemplate -Template $template -Variables $vars
            $result | Should Be 'ip address 10.1.1.1 255.255.255.0'
        }

        It 'handles variables with underscores' {
            $template = 'vlan {{ vlan_id }}'
            $vars = @{ vlan_id = '100' }
            $result = Expand-ConfigTemplate -Template $template -Variables $vars
            $result | Should Be 'vlan 100'
        }

        It 'leaves undefined variables unchanged' {
            $template = 'value: {{ undefined }}'
            $result = Expand-ConfigTemplate -Template $template -Variables @{}
            $result | Should Be 'value: {{ undefined }}'
        }
    }

    Context 'Expand-ConfigTemplate - Conditionals' {
        It 'includes content when condition is true' {
            $template = '{% if enabled %}feature on{% endif %}'
            $vars = @{ enabled = $true }
            $result = Expand-ConfigTemplate -Template $template -Variables $vars
            $result | Should Be 'feature on'
        }

        It 'excludes content when condition is false' {
            $template = '{% if enabled %}feature on{% endif %}'
            $vars = @{ enabled = $false }
            $result = Expand-ConfigTemplate -Template $template -Variables $vars
            $result | Should Be ''
        }

        It 'handles if/else blocks' {
            $template = '{% if production %}prod config{% else %}dev config{% endif %}'
            $result1 = Expand-ConfigTemplate -Template $template -Variables @{ production = $true }
            $result2 = Expand-ConfigTemplate -Template $template -Variables @{ production = $false }
            $result1 | Should Be 'prod config'
            $result2 | Should Be 'dev config'
        }

        It 'handles string truthy check' {
            $template = '{% if name %}has name{% endif %}'
            $result1 = Expand-ConfigTemplate -Template $template -Variables @{ name = 'test' }
            $result2 = Expand-ConfigTemplate -Template $template -Variables @{ name = '' }
            $result1 | Should Be 'has name'
            $result2 | Should Be ''
        }

        It 'handles not operator' {
            $template = '{% if not disabled %}enabled{% endif %}'
            $vars = @{ disabled = $false }
            $result = Expand-ConfigTemplate -Template $template -Variables $vars
            $result | Should Be 'enabled'
        }

        It 'handles equality comparison' {
            $template = '{% if vendor == "Cisco" %}cisco config{% endif %}'
            $vars = @{ vendor = 'Cisco' }
            $result = Expand-ConfigTemplate -Template $template -Variables $vars
            $result | Should Be 'cisco config'
        }

        It 'handles inequality comparison' {
            $template = '{% if vendor != "Cisco" %}other vendor{% endif %}'
            $vars = @{ vendor = 'Arista' }
            $result = Expand-ConfigTemplate -Template $template -Variables $vars
            $result | Should Be 'other vendor'
        }
    }

    Context 'Expand-ConfigTemplate - For Loops' {
        It 'expands simple list' {
            $template = '{% for server in servers %}ntp server {{ server }}
{% endfor %}'
            $vars = @{ servers = @('10.1.1.1', '10.1.1.2') }
            $result = Expand-ConfigTemplate -Template $template -Variables $vars
            $result | Should Match 'ntp server 10.1.1.1'
            $result | Should Match 'ntp server 10.1.1.2'
        }

        It 'handles empty list' {
            $template = '{% for item in items %}{{ item }}{% endfor %}'
            $vars = @{ items = @() }
            $result = Expand-ConfigTemplate -Template $template -Variables $vars
            $result | Should Be ''
        }

        It 'expands list of objects' {
            $template = '{% for port in ports %}interface {{ port.name }}{% endfor %}'
            $vars = @{
                ports = @(
                    @{ name = 'Gi1/0/1' }
                    @{ name = 'Gi1/0/2' }
                )
            }
            $result = Expand-ConfigTemplate -Template $template -Variables $vars
            $result | Should Match 'interface Gi1/0/1'
            $result | Should Match 'interface Gi1/0/2'
        }

        It 'handles conditionals inside loops' {
            $template = '{% for port in ports %}{% if port.voice %}voice vlan{% endif %}{% endfor %}'
            $vars = @{
                ports = @(
                    @{ voice = $true }
                    @{ voice = $false }
                )
            }
            $result = Expand-ConfigTemplate -Template $template -Variables $vars
            ($result -split 'voice vlan').Count | Should Be 2  # One occurrence + 1
        }
    }

    Context 'Template Library' {
        BeforeEach {
            Clear-TemplateLibrary
        }

        It 'adds and retrieves template' {
            $template = New-ConfigTemplate -Name 'lib-test' -Content 'test content'
            Add-ConfigTemplate -Template $template
            $retrieved = Get-ConfigTemplate -Name 'lib-test'
            $retrieved | Should Not BeNullOrEmpty
            $retrieved.Name | Should Be 'lib-test'
        }

        It 'prevents duplicate names' {
            $t1 = New-ConfigTemplate -Name 'duplicate' -Content 'first'
            $t2 = New-ConfigTemplate -Name 'duplicate' -Content 'second'
            Add-ConfigTemplate -Template $t1
            $result = Add-ConfigTemplate -Template $t2 -WarningAction SilentlyContinue
            $result | Should BeNullOrEmpty
        }

        It 'removes template' {
            $template = New-ConfigTemplate -Name 'to-remove' -Content 'test'
            Add-ConfigTemplate -Template $template
            $removed = Remove-ConfigTemplate -Name 'to-remove'
            $removed | Should Be $true
            $retrieved = Get-ConfigTemplate -Name 'to-remove'
            @($retrieved).Count | Should Be 0
        }

        It 'updates template' {
            $template = New-ConfigTemplate -Name 'to-update' -Content 'original'
            Add-ConfigTemplate -Template $template
            Update-ConfigTemplate -Name 'to-update' -Properties @{ Content = 'updated' }
            $retrieved = Get-ConfigTemplate -Name 'to-update'
            $retrieved.Content | Should Be 'updated'
        }

        It 'filters by vendor' {
            Add-ConfigTemplate -Template (New-ConfigTemplate -Name 't1' -Content 'cisco config' -Vendor 'Cisco_IOS')
            Add-ConfigTemplate -Template (New-ConfigTemplate -Name 't2' -Content 'arista config' -Vendor 'Arista_EOS')
            $cisco = Get-ConfigTemplate -Vendor 'Cisco_IOS'
            @($cisco).Count | Should Be 1
            $cisco[0].Name | Should Be 't1'
        }
    }

    Context 'Built-in Templates' {
        It 'returns built-in templates' {
            $templates = Get-BuiltInTemplates
            $templates.Count | Should BeGreaterThan 0
        }

        It 'includes access switch template' {
            $templates = Get-BuiltInTemplates
            $access = $templates | Where-Object { $_.Name -eq 'access-switch-basic' }
            $access | Should Not BeNullOrEmpty
            $access.Vendor | Should Be 'Cisco_IOS'
        }

        It 'imports built-in templates' {
            Clear-TemplateLibrary
            $result = Import-BuiltInTemplates
            $result.Imported | Should BeGreaterThan 0
            $templates = Get-ConfigTemplate
            $templates.Count | Should Be $result.Imported
        }
    }

    Context 'Get-TemplateVariables' {
        It 'extracts variable names' {
            $template = 'hostname {{ hostname }} ip {{ ip_address }}'
            $vars = Get-TemplateVariables -Template $template
            ($vars -contains 'hostname') | Should Be $true
            ($vars -contains 'ip_address') | Should Be $true
        }

        It 'extracts loop variables' {
            $template = '{% for server in ntp_servers %}{{ server }}{% endfor %}'
            $vars = Get-TemplateVariables -Template $template
            ($vars -contains 'ntp_servers') | Should Be $true
        }

        It 'returns unique variables' {
            $template = '{{ name }} and {{ name }} again'
            $vars = Get-TemplateVariables -Template $template
            @($vars | Where-Object { $_ -eq 'name' }).Count | Should Be 1
        }
    }

    Context 'New-ConfigFromTemplate' {
        BeforeEach {
            Clear-TemplateLibrary
            Import-BuiltInTemplates
        }

        It 'generates config from template name' {
            $vars = @{
                hostname = 'TEST-SW-01'
                mgmt_vlan = 100
                mgmt_ip = '10.1.100.1'
                mgmt_mask = '255.255.255.0'
                default_gateway = '10.1.100.254'
                ntp_servers = @('10.1.1.1')
                syslog_servers = @('10.1.1.10')
            }
            $config = New-ConfigFromTemplate -TemplateName 'access-switch-basic' -Variables $vars
            $config | Should Not BeNullOrEmpty
            $config | Should Match 'hostname TEST-SW-01'
            $config | Should Match 'interface Vlan100'
            $config | Should Match 'ntp server 10.1.1.1'
        }
    }

    Context 'Import/Export' {
        BeforeEach {
            Clear-TemplateLibrary
        }

        It 'exports and imports library' {
            $template = New-ConfigTemplate -Name 'export-test' -Content 'test content'
            Add-ConfigTemplate -Template $template

            $tempFile = Join-Path $env:TEMP 'template-test.json'
            try {
                Export-TemplateLibrary -Path $tempFile
                Clear-TemplateLibrary

                $result = Import-TemplateLibrary -Path $tempFile
                $result.Imported | Should Be 1

                $retrieved = Get-ConfigTemplate -Name 'export-test'
                $retrieved.Content | Should Be 'test content'
            }
            finally {
                if (Test-Path $tempFile) { Remove-Item $tempFile }
            }
        }
    }

    Context 'Get-TemplateLibraryStats' {
        BeforeEach {
            Clear-TemplateLibrary
        }

        It 'returns statistics' {
            Add-ConfigTemplate -Template (New-ConfigTemplate -Name 't1' -Content 'config1' -Vendor 'Cisco_IOS' -DeviceType 'Access')
            Add-ConfigTemplate -Template (New-ConfigTemplate -Name 't2' -Content 'config2' -Vendor 'Cisco_IOS' -DeviceType 'Distribution')
            Add-ConfigTemplate -Template (New-ConfigTemplate -Name 't3' -Content 'config3' -Vendor 'Arista_EOS' -DeviceType 'Access')

            $stats = Get-TemplateLibraryStats
            $stats.TotalTemplates | Should Be 3
            $stats.ByVendor['Cisco_IOS'] | Should Be 2
            $stats.ByVendor['Arista_EOS'] | Should Be 1
            $stats.ByDeviceType['Access'] | Should Be 2
        }
    }
}

#region ST-U-005: Configuration Comparison Tests

Describe 'ConfigTemplateModule - Config Comparison' {

    Context 'Get-ConfigSection' {
        It 'parses interface sections' {
            $config = @'
interface GigabitEthernet1/0/1
 description Uplink
 switchport mode trunk
!
interface GigabitEthernet1/0/2
 description Access Port
 switchport mode access
!
'@
            $sections = @(Get-ConfigSection -ConfigText $config)
            $sections.Count | Should Be 2
            $sections[0].Type | Should Be 'Interface'
            $sections[0].Name | Should Match 'GigabitEthernet1/0/1'
            $sections[1].Name | Should Match 'GigabitEthernet1/0/2'
        }

        It 'parses VLAN sections' {
            $config = @'
vlan 100
 name Management
vlan 200
 name Data
'@
            $sections = @(Get-ConfigSection -ConfigText $config)
            $sections.Count | Should Be 2
            $sections[0].Type | Should Be 'VLAN'
            $sections[0].Name | Should Be 'vlan 100'
        }

        It 'parses router sections' {
            $config = @'
router ospf 1
 network 10.0.0.0 0.255.255.255 area 0
!
router bgp 65001
 neighbor 10.1.1.1 remote-as 65002
!
'@
            $sections = @(Get-ConfigSection -ConfigText $config)
            $sections.Count | Should Be 2
            $sections[0].Type | Should Be 'Router'
        }

        It 'returns empty for empty config' {
            $sections = @(Get-ConfigSection -ConfigText '')
            $sections.Count | Should Be 0
        }
    }

    Context 'Compare-ConfigText' {
        It 'detects identical configs' {
            $config = "hostname SW-01`nip domain-name test.local"
            $result = Compare-ConfigText -ReferenceConfig $config -DifferenceConfig $config
            $result.HasDifferences | Should Be $false
            $result.SimilarityPercent | Should Be 100
        }

        It 'detects removed lines' {
            $ref = "line1`nline2`nline3"
            $diff = "line1`nline3"
            $result = Compare-ConfigText -ReferenceConfig $ref -DifferenceConfig $diff
            $result.HasDifferences | Should Be $true
            $result.RemovedCount | Should Be 1
            $result.Removed[0].Content | Should Be 'line2'
        }

        It 'detects added lines' {
            $ref = "line1`nline2"
            $diff = "line1`nline2`nline3"
            $result = Compare-ConfigText -ReferenceConfig $ref -DifferenceConfig $diff
            $result.AddedCount | Should Be 1
            $result.Added[0].Content | Should Be 'line3'
        }

        It 'calculates similarity percentage' {
            $ref = "a`nb`nc`nd"
            $diff = "a`nb`nx`ny"
            $result = Compare-ConfigText -ReferenceConfig $ref -DifferenceConfig $diff
            # 2 unchanged (a, b), 2 removed (c, d), 2 added (x, y)
            # similarity = 2 * 2 / (4 + 4) = 50%
            $result.SimilarityPercent | Should Be 50
        }

        It 'ignores comments when specified' {
            $ref = "! comment`nhostname SW-01"
            $diff = "! different comment`nhostname SW-01"
            $result = Compare-ConfigText -ReferenceConfig $ref -DifferenceConfig $diff -IgnoreComments
            $result.HasDifferences | Should Be $false
        }

        It 'ignores whitespace when specified' {
            $ref = "hostname SW-01  `n  ip domain-name test"
            $diff = "hostname SW-01`nip domain-name test"
            $result = Compare-ConfigText -ReferenceConfig $ref -DifferenceConfig $diff -IgnoreWhitespace
            $result.HasDifferences | Should Be $false
        }
    }

    Context 'Compare-ConfigSections' {
        It 'compares matching sections' {
            $ref = @'
interface Gi1/0/1
 description Old
!
'@
            $diff = @'
interface Gi1/0/1
 description New
!
'@
            $result = Compare-ConfigSections -ReferenceConfig $ref -DifferenceConfig $diff
            $result.Comparisons.Count | Should Be 1
            $result.Comparisons[0].Status | Should Be 'Modified'
        }

        It 'identifies sections only in reference' {
            $ref = @'
interface Gi1/0/1
 description Port1
!
interface Gi1/0/2
 description Port2
!
'@
            $diff = @'
interface Gi1/0/1
 description Port1
!
'@
            $result = Compare-ConfigSections -ReferenceConfig $ref -DifferenceConfig $diff
            $result.OnlyInReferenceCount | Should Be 1
            $result.OnlyInReference[0].SectionName | Should Match 'Gi1/0/2'
        }

        It 'identifies sections only in difference' {
            $ref = @'
interface Gi1/0/1
 description Port1
!
'@
            $diff = @'
interface Gi1/0/1
 description Port1
!
interface Gi1/0/3
 description NewPort
!
'@
            $result = Compare-ConfigSections -ReferenceConfig $ref -DifferenceConfig $diff
            $result.OnlyInDifferenceCount | Should Be 1
        }

        It 'identifies unchanged sections' {
            $config = @'
interface Gi1/0/1
 description Same
!
'@
            $result = Compare-ConfigSections -ReferenceConfig $config -DifferenceConfig $config
            $result.UnchangedSections | Should Be 1
            $result.ModifiedSections | Should Be 0
        }
    }

    Context 'New-ConfigDiffReport' {
        It 'generates comprehensive report' {
            $ref = "hostname SW-01`ninterface Gi1/0/1`n description Old"
            $diff = "hostname SW-02`ninterface Gi1/0/1`n description New"
            $report = New-ConfigDiffReport -ReferenceConfig $ref -DifferenceConfig $diff
            $report.ReportID | Should Match '^DIFF-'
            $report.Summary | Should Not BeNullOrEmpty
            $report.TextDiff | Should Not BeNullOrEmpty
            $report.SectionDiff | Should Not BeNullOrEmpty
        }

        It 'determines overall status correctly' {
            $identical = "hostname SW-01"
            $report = New-ConfigDiffReport -ReferenceConfig $identical -DifferenceConfig $identical
            $report.OverallStatus | Should Be 'Identical'
        }

        It 'uses custom names' {
            $report = New-ConfigDiffReport -ReferenceConfig 'a' -DifferenceConfig 'b' `
                -ReferenceName 'Golden' -DifferenceName 'Device1'
            $report.ReferenceName | Should Be 'Golden'
            $report.DifferenceName | Should Be 'Device1'
        }
    }

    Context 'Get-ConfigDrift' {
        It 'compares multiple devices against baseline' {
            $baseline = "hostname GOLDEN`nip domain-name test.local"
            $devices = @{
                'SW-01' = "hostname SW-01`nip domain-name test.local"
                'SW-02' = "hostname SW-02`nip domain-name test.local"
            }
            $results = @(Get-ConfigDrift -BaselineConfig $baseline -DeviceConfigs $devices)
            $results.Count | Should Be 2
            $results[0].DeviceName | Should Not BeNullOrEmpty
            $results[0].DriftScore | Should Not BeNullOrEmpty
        }

        It 'sorts by drift score descending' {
            $baseline = "line1`nline2`nline3`nline4"
            $devices = @{
                'LowDrift' = "line1`nline2`nline3`nline4"
                'HighDrift' = "different1`ndifferent2`ndifferent3`ndifferent4"
            }
            $results = @(Get-ConfigDrift -BaselineConfig $baseline -DeviceConfigs $devices)
            $results[0].DriftScore | Should BeGreaterThan $results[1].DriftScore
        }

        It 'applies drift threshold' {
            $baseline = "a`nb`nc`nd`ne`nf`ng`nh`ni`nj"
            $devices = @{
                'Device1' = "a`nb`nc`nd`ne`nf`ng`nh`ni`nX"  # 10% drift
            }
            $results = @(Get-ConfigDrift -BaselineConfig $baseline -DeviceConfigs $devices -DriftThreshold 5)
            $results[0].HasDrift | Should Be $true
        }

        It 'assigns correct status' {
            $baseline = "a"
            $devices = @{
                'Compliant' = "a"
            }
            $results = @(Get-ConfigDrift -BaselineConfig $baseline -DeviceConfigs $devices)
            $results[0].Status | Should Be 'Compliant'
        }
    }

    Context 'Export-ConfigDiffReport' {
        BeforeAll {
            $script:testReport = New-ConfigDiffReport `
                -ReferenceConfig "hostname OLD`nip domain-name old.local" `
                -DifferenceConfig "hostname NEW`nip domain-name new.local" `
                -ReferenceName 'Baseline' -DifferenceName 'Current'
        }

        It 'exports to Text format' {
            $output = Export-ConfigDiffReport -Report $testReport -Format Text
            $output | Should Match 'CONFIGURATION DIFF REPORT'
            $output | Should Match 'Baseline'
            $output | Should Match 'Current'
        }

        It 'exports to Markdown format' {
            $output = Export-ConfigDiffReport -Report $testReport -Format Markdown
            $output | Should Match '# Configuration Diff Report'
            $output | Should Match '\| Metric \| Value \|'
        }

        It 'exports to HTML format' {
            $output = Export-ConfigDiffReport -Report $testReport -Format HTML
            $output | Should Match '<html>'
            $output | Should Match 'Config Diff:'
        }

        It 'exports to JSON format' {
            $output = Export-ConfigDiffReport -Report $testReport -Format JSON
            $json = $output | ConvertFrom-Json
            $json.ReferenceName | Should Be 'Baseline'
        }

        It 'writes to file when OutputPath specified' {
            $tempFile = Join-Path $env:TEMP 'diff-report-test.txt'
            try {
                $result = Export-ConfigDiffReport -Report $testReport -Format Text -OutputPath $tempFile
                Test-Path $result | Should Be $true
                $content = Get-Content -LiteralPath $result -Raw
                $content | Should Match 'DIFF REPORT'
            }
            finally {
                if (Test-Path $tempFile) { Remove-Item $tempFile }
            }
        }
    }

    #region Vendor Syntax Modules (ST-U-006)

    Context 'Get-ConfigVendor' {

        It 'detects Cisco IOS config' {
            $config = @'
Cisco IOS Software, C3560 Software
hostname SW-01
switchport mode access
line vty 0 15
'@
            $result = Get-ConfigVendor -ConfigText $config
            $result.Vendor | Should Be 'Cisco_IOS'
            $result.Confidence | Should Be 'High'
        }

        It 'detects Arista EOS config' {
            $config = @'
! Arista vEOS
hostname SW-EOS-01
transceiver qsfp default-mode 4x10G
management api http-commands
'@
            $result = Get-ConfigVendor -ConfigText $config
            $result.Vendor | Should Be 'Arista_EOS'
            $result.Confidence | Should Be 'High'
        }

        It 'detects Cisco NX-OS config' {
            $config = @'
Cisco Nexus Operating System (NX-OS) Software
feature vpc
vpc domain 100
'@
            $result = Get-ConfigVendor -ConfigText $config
            $result.Vendor | Should Be 'Cisco_NXOS'
            $result.Confidence | Should Be 'High'
        }

        It 'detects Juniper config' {
            $config = @'
set system host-name JUNOS-SW
set interfaces ge-0/0/0 unit 0
set routing-options static route 0.0.0.0/0 next-hop 10.1.1.1
'@
            $result = Get-ConfigVendor -ConfigText $config
            $result.Vendor | Should Be 'Juniper'
            $result.Confidence | Should Be 'High'
        }

        It 'returns Generic for unknown config' {
            $config = 'some random text'
            $result = Get-ConfigVendor -ConfigText $config
            $result.Vendor | Should Be 'Generic'
            $result.Confidence | Should Be 'None'
        }
    }

    Context 'Get-VendorSectionPatterns' {

        It 'returns Cisco IOS patterns' {
            $patterns = Get-VendorSectionPatterns -Vendor 'Cisco_IOS'
            $patterns.Interface | Should Not BeNullOrEmpty
            $patterns.VLAN | Should Not BeNullOrEmpty
            $patterns.ACL | Should Not BeNullOrEmpty
            $patterns.SectionEnd | Should Not BeNullOrEmpty
        }

        It 'returns Juniper patterns' {
            $patterns = Get-VendorSectionPatterns -Vendor 'Juniper'
            $patterns.Interface | Should Not BeNullOrEmpty
            $patterns.System | Should Not BeNullOrEmpty
            $patterns.SectionEnd | Should Be '^}'
        }

        It 'returns NX-OS specific patterns' {
            $patterns = Get-VendorSectionPatterns -Vendor 'Cisco_NXOS'
            $patterns.Feature | Should Not BeNullOrEmpty
            $patterns.VPC | Should Not BeNullOrEmpty
        }
    }

    Context 'Get-VendorInterfaceNaming' {

        It 'parses Cisco GigabitEthernet interface' {
            $result = Get-VendorInterfaceNaming -InterfaceName 'GigabitEthernet1/0/24' -Vendor 'Cisco_IOS'
            $result.Type | Should Be 'GigabitEthernet'
            $result.TypeShort | Should Be 'Gi'
            $result.Module | Should Be 1
            $result.Slot | Should Be 0
            $result.Port | Should Be 24
            $result.Speed | Should Be '1G'
            $result.IsVirtual | Should Be $false
        }

        It 'parses Cisco short interface name' {
            $result = Get-VendorInterfaceNaming -InterfaceName 'Gi0/1' -Vendor 'Cisco_IOS'
            $result.Type | Should Be 'GigabitEthernet'
            $result.Slot | Should Be 0
            $result.Port | Should Be 1
        }

        It 'parses port-channel as virtual' {
            $result = Get-VendorInterfaceNaming -InterfaceName 'Port-channel1' -Vendor 'Cisco_IOS'
            $result.Type | Should Be 'Port-channel'
            $result.IsVirtual | Should Be $true
        }

        It 'parses Vlan interface' {
            $result = Get-VendorInterfaceNaming -InterfaceName 'Vlan100' -Vendor 'Cisco_IOS'
            $result.Type | Should Be 'Vlan'
            $result.Port | Should Be 100
            $result.IsVirtual | Should Be $true
        }

        It 'parses Juniper interface' {
            $result = Get-VendorInterfaceNaming -InterfaceName 'ge-0/0/1' -Vendor 'Juniper'
            $result.Type | Should Be 'GigabitEthernet'
            $result.TypeShort | Should Be 'ge'
            $result.Module | Should Be 0
            $result.Slot | Should Be 0
            $result.Port | Should Be 1
        }

        It 'parses TenGigabitEthernet' {
            $result = Get-VendorInterfaceNaming -InterfaceName 'Te1/1/1' -Vendor 'Cisco_IOS'
            $result.Type | Should Be 'TenGigabitEthernet'
            $result.Speed | Should Be '10G'
        }
    }

    Context 'ConvertTo-VendorSyntax' {

        It 'returns same command for same vendor' {
            $result = ConvertTo-VendorSyntax -Command 'switchport mode access' -FromVendor 'Cisco_IOS' -ToVendor 'Cisco_IOS'
            $result | Should Be 'switchport mode access'
        }

        It 'converts portfast to NX-OS' {
            $result = ConvertTo-VendorSyntax -Command 'spanning-tree portfast' -FromVendor 'Cisco_IOS' -ToVendor 'Cisco_NXOS'
            $result | Should Be 'spanning-tree port type edge'
        }

        It 'converts hostname to Juniper' {
            $result = ConvertTo-VendorSyntax -Command 'hostname SW-01' -FromVendor 'Cisco_IOS' -ToVendor 'Juniper'
            $result | Should Be 'set system host-name SW-01'
        }

        It 'converts NTP to Juniper' {
            $result = ConvertTo-VendorSyntax -Command 'ntp server 10.1.1.1' -FromVendor 'Cisco_IOS' -ToVendor 'Juniper'
            $result | Should Be 'set system ntp server 10.1.1.1'
        }

        It 'converts shutdown to Juniper' {
            $result = ConvertTo-VendorSyntax -Command 'shutdown' -FromVendor 'Cisco_IOS' -ToVendor 'Juniper'
            $result | Should Be 'set disable'
        }

        It 'marks untranslatable commands' {
            $result = ConvertTo-VendorSyntax -Command 'some-unique-command xyz' -FromVendor 'Cisco_IOS' -ToVendor 'Juniper'
            $result | Should Match 'TODO: Manual translation'
        }
    }

    Context 'Get-VendorCommandReference' {

        It 'returns Cisco IOS commands' {
            $commands = @(Get-VendorCommandReference -Vendor 'Cisco_IOS' -Category 'All')
            $commands.Count | Should BeGreaterThan 10
            $commands[0].Vendor | Should Be 'Cisco_IOS'
        }

        It 'filters by category' {
            $commands = @(Get-VendorCommandReference -Vendor 'Cisco_IOS' -Category 'Interface')
            $commands.Count | Should BeGreaterThan 0
            $commands | ForEach-Object { $_.Category | Should Be 'Interface' }
        }

        It 'returns Juniper commands' {
            $commands = @(Get-VendorCommandReference -Vendor 'Juniper' -Category 'All')
            $commands.Count | Should BeGreaterThan 5
            $commands[0].Command | Should Match 'set'
        }

        It 'returns Arista EOS commands' {
            $commands = @(Get-VendorCommandReference -Vendor 'Arista_EOS' -Category 'Security')
            $commands.Count | Should BeGreaterThan 0
        }
    }

    Context 'ConvertTo-NormalizedConfig' {

        It 'normalizes hostname' {
            $config = 'hostname SW-TEST-01'
            $result = @(ConvertTo-NormalizedConfig -ConfigText $config -Vendor 'Cisco_IOS')
            $result.Count | Should Be 1
            $result[0].Type | Should Be 'System'
            $result[0].Key | Should Be 'hostname'
            $result[0].Value | Should Be 'SW-TEST-01'
        }

        It 'normalizes interface declarations' {
            $config = @'
interface GigabitEthernet0/1
 description Uplink
 switchport mode trunk
'@
            $result = @(ConvertTo-NormalizedConfig -ConfigText $config -Vendor 'Cisco_IOS')
            $result.Count | Should Be 3
            $result[0].Type | Should Be 'InterfaceDeclaration'
            $result[1].Type | Should Be 'Description'
            $result[2].Type | Should Be 'SwitchportMode'
        }

        It 'normalizes VLAN declarations' {
            $config = @'
vlan 10
 name Users
'@
            $result = @(ConvertTo-NormalizedConfig -ConfigText $config -Vendor 'Cisco_IOS')
            $result[0].Type | Should Be 'VLANDeclaration'
            $result[0].Value | Should Be '10'
            $result[1].Type | Should Be 'VLANName'
            $result[1].Value | Should Be 'Users'
        }

        It 'auto-detects vendor' {
            $config = @'
Cisco IOS Software
hostname SW-01
'@
            $result = @(ConvertTo-NormalizedConfig -ConfigText $config -Vendor 'Auto')
            $result[0].Vendor | Should Be 'Cisco_IOS'
        }

        It 'tracks context for nested lines' {
            $config = @'
interface Vlan100
 ip address 10.1.100.1 255.255.255.0
'@
            $result = @(ConvertTo-NormalizedConfig -ConfigText $config -Vendor 'Cisco_IOS')
            $result[1].Context.Count | Should Be 2
            $result[1].Context[0] | Should Be 'interface'
        }
    }

    #endregion
}

#endregion
