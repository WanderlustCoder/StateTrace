Set-StrictMode -Version Latest

$modulePath = Join-Path $PSScriptRoot '..\ConfigTemplateModule.psm1'
Import-Module $modulePath -Force

Describe 'ConfigTemplateModule' {

    Context 'New-ConfigTemplate' {
        It 'creates template with required parameters' {
            $template = New-ConfigTemplate -Name 'test-template' -Content 'hostname {{ hostname }}'
            $template | Should -Not -BeNullOrEmpty
            $template.Name | Should -Be 'test-template'
            $template.Content | Should -Be 'hostname {{ hostname }}'
            $template.TemplateID | Should -Not -BeNullOrEmpty
        }

        It 'sets default values' {
            $template = New-ConfigTemplate -Name 'test' -Content 'test'
            $template.Vendor | Should -Be 'Generic'
            $template.DeviceType | Should -Be 'Other'
            $template.Version | Should -Be '1.0'
        }

        It 'accepts optional parameters' {
            $template = New-ConfigTemplate -Name 'test' -Content 'test' `
                -Description 'Test desc' -Vendor 'Cisco_IOS' -DeviceType 'Access' `
                -Category 'Standard' -Author 'Tester'
            $template.Description | Should -Be 'Test desc'
            $template.Vendor | Should -Be 'Cisco_IOS'
            $template.DeviceType | Should -Be 'Access'
            $template.Category | Should -Be 'Standard'
            $template.Author | Should -Be 'Tester'
        }
    }

    Context 'Expand-ConfigTemplate - Variables' {
        It 'expands simple variables' {
            $template = 'hostname {{ hostname }}'
            $vars = @{ hostname = 'SW-01' }
            $result = Expand-ConfigTemplate -Template $template -Variables $vars
            $result | Should -Be 'hostname SW-01'
        }

        It 'expands multiple variables' {
            $template = 'ip address {{ ip }} {{ mask }}'
            $vars = @{ ip = '10.1.1.1'; mask = '255.255.255.0' }
            $result = Expand-ConfigTemplate -Template $template -Variables $vars
            $result | Should -Be 'ip address 10.1.1.1 255.255.255.0'
        }

        It 'handles variables with underscores' {
            $template = 'vlan {{ vlan_id }}'
            $vars = @{ vlan_id = '100' }
            $result = Expand-ConfigTemplate -Template $template -Variables $vars
            $result | Should -Be 'vlan 100'
        }

        It 'leaves undefined variables unchanged' {
            $template = 'value: {{ undefined }}'
            $result = Expand-ConfigTemplate -Template $template -Variables @{}
            $result | Should -Be 'value: {{ undefined }}'
        }
    }

    Context 'Expand-ConfigTemplate - Conditionals' {
        It 'includes content when condition is true' {
            $template = '{% if enabled %}feature on{% endif %}'
            $vars = @{ enabled = $true }
            $result = Expand-ConfigTemplate -Template $template -Variables $vars
            $result | Should -Be 'feature on'
        }

        It 'excludes content when condition is false' {
            $template = '{% if enabled %}feature on{% endif %}'
            $vars = @{ enabled = $false }
            $result = Expand-ConfigTemplate -Template $template -Variables $vars
            $result | Should -Be ''
        }

        It 'handles if/else blocks' {
            $template = '{% if production %}prod config{% else %}dev config{% endif %}'
            $result1 = Expand-ConfigTemplate -Template $template -Variables @{ production = $true }
            $result2 = Expand-ConfigTemplate -Template $template -Variables @{ production = $false }
            $result1 | Should -Be 'prod config'
            $result2 | Should -Be 'dev config'
        }

        It 'handles string truthy check' {
            $template = '{% if name %}has name{% endif %}'
            $result1 = Expand-ConfigTemplate -Template $template -Variables @{ name = 'test' }
            $result2 = Expand-ConfigTemplate -Template $template -Variables @{ name = '' }
            $result1 | Should -Be 'has name'
            $result2 | Should -Be ''
        }

        It 'handles not operator' {
            $template = '{% if not disabled %}enabled{% endif %}'
            $vars = @{ disabled = $false }
            $result = Expand-ConfigTemplate -Template $template -Variables $vars
            $result | Should -Be 'enabled'
        }

        It 'handles equality comparison' {
            $template = '{% if vendor == "Cisco" %}cisco config{% endif %}'
            $vars = @{ vendor = 'Cisco' }
            $result = Expand-ConfigTemplate -Template $template -Variables $vars
            $result | Should -Be 'cisco config'
        }

        It 'handles inequality comparison' {
            $template = '{% if vendor != "Cisco" %}other vendor{% endif %}'
            $vars = @{ vendor = 'Arista' }
            $result = Expand-ConfigTemplate -Template $template -Variables $vars
            $result | Should -Be 'other vendor'
        }
    }

    Context 'Expand-ConfigTemplate - For Loops' {
        It 'expands simple list' {
            $template = '{% for server in servers %}ntp server {{ server }}
{% endfor %}'
            $vars = @{ servers = @('10.1.1.1', '10.1.1.2') }
            $result = Expand-ConfigTemplate -Template $template -Variables $vars
            $result | Should -Match 'ntp server 10.1.1.1'
            $result | Should -Match 'ntp server 10.1.1.2'
        }

        It 'handles empty list' {
            $template = '{% for item in items %}{{ item }}{% endfor %}'
            $vars = @{ items = @() }
            $result = Expand-ConfigTemplate -Template $template -Variables $vars
            $result | Should -Be ''
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
            $result | Should -Match 'interface Gi1/0/1'
            $result | Should -Match 'interface Gi1/0/2'
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
            ($result -split 'voice vlan').Count | Should -Be 2  # One occurrence + 1
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
            $retrieved | Should -Not -BeNullOrEmpty
            $retrieved.Name | Should -Be 'lib-test'
        }

        It 'prevents duplicate names' {
            $t1 = New-ConfigTemplate -Name 'duplicate' -Content 'first'
            $t2 = New-ConfigTemplate -Name 'duplicate' -Content 'second'
            Add-ConfigTemplate -Template $t1
            $result = Add-ConfigTemplate -Template $t2 -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }

        It 'removes template' {
            $template = New-ConfigTemplate -Name 'to-remove' -Content 'test'
            Add-ConfigTemplate -Template $template
            $removed = Remove-ConfigTemplate -Name 'to-remove'
            $removed | Should -Be $true
            $retrieved = Get-ConfigTemplate -Name 'to-remove'
            $retrieved.Count | Should -Be 0
        }

        It 'updates template' {
            $template = New-ConfigTemplate -Name 'to-update' -Content 'original'
            Add-ConfigTemplate -Template $template
            Update-ConfigTemplate -Name 'to-update' -Properties @{ Content = 'updated' }
            $retrieved = Get-ConfigTemplate -Name 'to-update'
            $retrieved.Content | Should -Be 'updated'
        }

        It 'filters by vendor' {
            Add-ConfigTemplate -Template (New-ConfigTemplate -Name 't1' -Content '' -Vendor 'Cisco_IOS')
            Add-ConfigTemplate -Template (New-ConfigTemplate -Name 't2' -Content '' -Vendor 'Arista_EOS')
            $cisco = Get-ConfigTemplate -Vendor 'Cisco_IOS'
            $cisco.Count | Should -Be 1
            $cisco[0].Name | Should -Be 't1'
        }
    }

    Context 'Built-in Templates' {
        It 'returns built-in templates' {
            $templates = Get-BuiltInTemplates
            $templates.Count | Should -BeGreaterThan 0
        }

        It 'includes access switch template' {
            $templates = Get-BuiltInTemplates
            $access = $templates | Where-Object { $_.Name -eq 'access-switch-basic' }
            $access | Should -Not -BeNullOrEmpty
            $access.Vendor | Should -Be 'Cisco_IOS'
        }

        It 'imports built-in templates' {
            Clear-TemplateLibrary
            $result = Import-BuiltInTemplates
            $result.Imported | Should -BeGreaterThan 0
            $templates = Get-ConfigTemplate
            $templates.Count | Should -Be $result.Imported
        }
    }

    Context 'Get-TemplateVariables' {
        It 'extracts variable names' {
            $template = 'hostname {{ hostname }} ip {{ ip_address }}'
            $vars = Get-TemplateVariables -Template $template
            $vars | Should -Contain 'hostname'
            $vars | Should -Contain 'ip_address'
        }

        It 'extracts loop variables' {
            $template = '{% for server in ntp_servers %}{{ server }}{% endfor %}'
            $vars = Get-TemplateVariables -Template $template
            $vars | Should -Contain 'ntp_servers'
        }

        It 'returns unique variables' {
            $template = '{{ name }} and {{ name }} again'
            $vars = Get-TemplateVariables -Template $template
            ($vars | Where-Object { $_ -eq 'name' }).Count | Should -Be 1
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
            $config | Should -Not -BeNullOrEmpty
            $config | Should -Match 'hostname TEST-SW-01'
            $config | Should -Match 'interface Vlan100'
            $config | Should -Match 'ntp server 10.1.1.1'
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
                $result.Imported | Should -Be 1

                $retrieved = Get-ConfigTemplate -Name 'export-test'
                $retrieved.Content | Should -Be 'test content'
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
            Add-ConfigTemplate -Template (New-ConfigTemplate -Name 't1' -Content '' -Vendor 'Cisco_IOS' -DeviceType 'Access')
            Add-ConfigTemplate -Template (New-ConfigTemplate -Name 't2' -Content '' -Vendor 'Cisco_IOS' -DeviceType 'Distribution')
            Add-ConfigTemplate -Template (New-ConfigTemplate -Name 't3' -Content '' -Vendor 'Arista_EOS' -DeviceType 'Access')

            $stats = Get-TemplateLibraryStats
            $stats.TotalTemplates | Should -Be 3
            $stats.ByVendor['Cisco_IOS'] | Should -Be 2
            $stats.ByVendor['Arista_EOS'] | Should -Be 1
            $stats.ByDeviceType['Access'] | Should -Be 2
        }
    }
}
