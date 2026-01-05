Set-StrictMode -Version Latest

$modulePath = Join-Path $PSScriptRoot '..\ConfigValidationModule.psm1'
Import-Module $modulePath -Force

Describe 'ConfigValidationModule' {

    Context 'New-ValidationRule' {
        It 'creates rule with required parameters' {
            $rule = New-ValidationRule -RuleID 'TEST-001' -Name 'Test Rule'
            $rule | Should -Not -BeNullOrEmpty
            $rule.RuleID | Should -Be 'TEST-001'
            $rule.Name | Should -Be 'Test Rule'
        }

        It 'sets default severity' {
            $rule = New-ValidationRule -RuleID 'TEST-001' -Name 'Test'
            $rule.Severity | Should -Be 'Medium'
        }

        It 'creates required rule' {
            $rule = New-ValidationRule -RuleID 'TEST-001' -Name 'Test' -Match 'test' -Required
            $rule.Required | Should -Be $true
            $rule.Prohibited | Should -Be $false
        }

        It 'creates prohibited rule' {
            $rule = New-ValidationRule -RuleID 'TEST-001' -Name 'Test' -Match 'bad' -Prohibited
            $rule.Prohibited | Should -Be $true
            $rule.Required | Should -Be $false
        }

        It 'accepts pattern for regex matching' {
            $rule = New-ValidationRule -RuleID 'TEST-001' -Name 'Test' -Pattern '^hostname \w+'
            $rule.Pattern | Should -Be '^hostname \w+'
        }
    }

    Context 'New-ValidationStandard' {
        It 'creates standard with rules' {
            $rules = @(
                New-ValidationRule -RuleID 'R1' -Name 'Rule 1' -Match 'test' -Required
                New-ValidationRule -RuleID 'R2' -Name 'Rule 2' -Match 'bad' -Prohibited
            )
            $standard = New-ValidationStandard -Name 'Test Standard' -Rules $rules
            $standard | Should -Not -BeNullOrEmpty
            $standard.Name | Should -Be 'Test Standard'
            $standard.Rules.Count | Should -Be 2
        }

        It 'generates unique StandardID' {
            $s1 = New-ValidationStandard -Name 'S1'
            $s2 = New-ValidationStandard -Name 'S2'
            $s1.StandardID | Should -Not -Be $s2.StandardID
        }
    }

    Context 'Test-ConfigCompliance - Required Rules' {
        It 'passes when required setting is present' {
            $config = @"
hostname SW-01
ip ssh version 2
"@
            $rule = New-ValidationRule -RuleID 'SSH' -Name 'SSH v2' -Match 'ip ssh version 2' -Required -Severity 'Critical'
            $standard = New-ValidationStandard -Name 'Test' -Rules @($rule)

            $result = Test-ConfigCompliance -Config $config -Standard $standard
            $result.Passed | Should -Be 1
            $result.Failed | Should -Be 0
            $result.Score | Should -Be 100
        }

        It 'fails when required setting is missing' {
            $config = 'hostname SW-01'
            $rule = New-ValidationRule -RuleID 'SSH' -Name 'SSH v2' -Match 'ip ssh version 2' -Required -Severity 'Critical'
            $standard = New-ValidationStandard -Name 'Test' -Rules @($rule)

            $result = Test-ConfigCompliance -Config $config -Standard $standard
            $result.Passed | Should -Be 0
            $result.Failed | Should -Be 1
            $result.Critical | Should -Be 1
        }
    }

    Context 'Test-ConfigCompliance - Prohibited Rules' {
        It 'passes when prohibited setting is absent' {
            $config = @"
hostname SW-01
line vty 0 15
 transport input ssh
"@
            $rule = New-ValidationRule -RuleID 'TELNET' -Name 'No Telnet' -Match 'transport input telnet' -Prohibited -Severity 'Critical'
            $standard = New-ValidationStandard -Name 'Test' -Rules @($rule)

            $result = Test-ConfigCompliance -Config $config -Standard $standard
            $result.Passed | Should -Be 1
            $result.Failed | Should -Be 0
        }

        It 'fails when prohibited setting is present' {
            $config = @"
line vty 0 15
 transport input telnet
"@
            $rule = New-ValidationRule -RuleID 'TELNET' -Name 'No Telnet' -Match 'transport input telnet' -Prohibited -Severity 'Critical'
            $standard = New-ValidationStandard -Name 'Test' -Rules @($rule)

            $result = Test-ConfigCompliance -Config $config -Standard $standard
            $result.Passed | Should -Be 0
            $result.Failed | Should -Be 1
        }
    }

    Context 'Test-ConfigCompliance - Pattern Matching' {
        It 'matches regex patterns' {
            $config = @"
hostname SW-BLDG1-01
"@
            $rule = New-ValidationRule -RuleID 'HOST' -Name 'Hostname Format' -Pattern '^hostname [A-Z]+-[A-Z0-9]+-\d+' -Required
            $standard = New-ValidationStandard -Name 'Test' -Rules @($rule)

            $result = Test-ConfigCompliance -Config $config -Standard $standard
            $result.Passed | Should -Be 1
        }

        It 'fails on regex mismatch' {
            $config = 'hostname switch1'
            $rule = New-ValidationRule -RuleID 'HOST' -Name 'Hostname Format' -Pattern '^hostname [A-Z]+-[A-Z0-9]+-\d+' -Required
            $standard = New-ValidationStandard -Name 'Test' -Rules @($rule)

            $result = Test-ConfigCompliance -Config $config -Standard $standard
            $result.Failed | Should -Be 1
        }
    }

    Context 'Test-ConfigCompliance - Multiple Rules' {
        It 'calculates correct score' {
            $config = @"
hostname SW-01
ip ssh version 2
service password-encryption
"@
            $rules = @(
                New-ValidationRule -RuleID 'R1' -Name 'SSH' -Match 'ip ssh version 2' -Required
                New-ValidationRule -RuleID 'R2' -Name 'Passwords' -Match 'service password-encryption' -Required
                New-ValidationRule -RuleID 'R3' -Name 'Logging' -Match 'logging buffered' -Required
                New-ValidationRule -RuleID 'R4' -Name 'No Telnet' -Match 'transport input telnet' -Prohibited
            )
            $standard = New-ValidationStandard -Name 'Test' -Rules $rules

            $result = Test-ConfigCompliance -Config $config -Standard $standard
            $result.TotalRules | Should -Be 4
            $result.Passed | Should -Be 3  # SSH, Passwords, No Telnet
            $result.Failed | Should -Be 1  # Logging
            $result.Score | Should -Be 75
        }
    }

    Context 'Test-ConfigCompliance - Line Numbers' {
        It 'reports correct line numbers' {
            $config = @"
hostname SW-01
!
interface Vlan1
 ip address 10.1.1.1 255.255.255.0
"@
            $rule = New-ValidationRule -RuleID 'IP' -Name 'IP Config' -Match 'ip address' -Required
            $standard = New-ValidationStandard -Name 'Test' -Rules @($rule)

            $result = Test-ConfigCompliance -Config $config -Standard $standard
            $violation = $result.Results | Where-Object { $_.RuleID -eq 'IP' }
            $violation.LineNumber | Should -Be 4
        }
    }

    Context 'Built-in Standards' {
        It 'returns security baseline for Cisco IOS' {
            $standard = Get-SecurityBaseline -Vendor 'Cisco_IOS'
            $standard | Should -Not -BeNullOrEmpty
            $standard.Rules.Count | Should -BeGreaterThan 5
        }

        It 'returns security baseline for Arista' {
            $standard = Get-SecurityBaseline -Vendor 'Arista_EOS'
            $standard | Should -Not -BeNullOrEmpty
            $standard.Rules.Count | Should -BeGreaterThan 0
        }

        It 'returns operational baseline' {
            $standard = Get-OperationalBaseline
            $standard | Should -Not -BeNullOrEmpty
            $standard.Name | Should -Be 'Operational Baseline'
        }

        It 'returns switching baseline' {
            $standard = Get-SwitchingBaseline
            $standard | Should -Not -BeNullOrEmpty
            $standard.Name | Should -Be 'Switching Baseline'
        }

        It 'returns all built-in standards' {
            $standards = Get-BuiltInStandards
            $standards.Count | Should -BeGreaterThan 2
        }
    }

    Context 'Standards Library' {
        BeforeEach {
            Clear-StandardsLibrary
        }

        It 'adds and retrieves standard' {
            $standard = New-ValidationStandard -Name 'lib-test' -Rules @()
            Add-ValidationStandard -Standard $standard
            $retrieved = Get-ValidationStandard -Name 'lib-test'
            $retrieved | Should -Not -BeNullOrEmpty
            $retrieved.Name | Should -Be 'lib-test'
        }

        It 'removes standard' {
            $standard = New-ValidationStandard -Name 'to-remove' -Rules @()
            Add-ValidationStandard -Standard $standard
            $removed = Remove-ValidationStandard -Name 'to-remove'
            $removed | Should -Be $true
            $retrieved = Get-ValidationStandard -Name 'to-remove'
            $retrieved.Count | Should -Be 0
        }

        It 'imports built-in standards' {
            $result = Import-BuiltInStandards
            $result.Imported | Should -BeGreaterThan 0
            $standards = Get-ValidationStandard
            $standards.Count | Should -Be $result.Imported
        }
    }

    Context 'Reporting' {
        BeforeAll {
            $script:testConfig = @"
hostname SW-01
ip ssh version 2
logging buffered 16384
"@
            $script:testRules = @(
                New-ValidationRule -RuleID 'SEC-001' -Name 'SSH v2' -Match 'ip ssh version 2' -Required -Severity 'Critical'
                New-ValidationRule -RuleID 'SEC-002' -Name 'No Telnet' -Match 'transport input telnet' -Prohibited -Severity 'Critical'
                New-ValidationRule -RuleID 'OPS-001' -Name 'Logging' -Match 'logging buffered' -Required -Severity 'Medium'
                New-ValidationRule -RuleID 'SEC-003' -Name 'Password Enc' -Match 'service password-encryption' -Required -Severity 'High' -Remediation 'service password-encryption'
            )
            $script:testStandard = New-ValidationStandard -Name 'Test' -Rules $script:testRules
            $script:testResult = Test-ConfigCompliance -Config $script:testConfig -Standard $script:testStandard -DeviceName 'TEST-SW'
        }

        It 'generates text report' {
            $report = New-ComplianceReport -ComplianceResult $testResult -Format 'Text'
            $report | Should -Not -BeNullOrEmpty
            $report | Should -Match 'COMPLIANCE REPORT'
            $report | Should -Match 'Device: TEST-SW'
            $report | Should -Match 'Score:'
        }

        It 'generates HTML report' {
            $report = New-ComplianceReport -ComplianceResult $testResult -Format 'HTML'
            $report | Should -Not -BeNullOrEmpty
            $report | Should -Match '<html>'
            $report | Should -Match 'TEST-SW'
        }

        It 'generates CSV report' {
            $report = New-ComplianceReport -ComplianceResult $testResult -Format 'CSV'
            $report | Should -Not -BeNullOrEmpty
            $report | Should -Match 'RuleID,RuleName,Status'
        }
    }

    Context 'Remediation Commands' {
        It 'extracts remediation from failures' {
            $config = 'hostname SW-01'
            $rule = New-ValidationRule -RuleID 'SSH' -Name 'SSH v2' -Match 'ip ssh version 2' -Required `
                -Remediation 'ip ssh version 2'
            $standard = New-ValidationStandard -Name 'Test' -Rules @($rule)

            $result = Test-ConfigCompliance -Config $config -Standard $standard
            $commands = Get-RemediationCommands -ComplianceResult $result

            $commands | Should -Contain 'ip ssh version 2'
        }
    }

    Context 'Test-BulkCompliance' {
        It 'tests multiple configs' {
            $configs = @{
                'SW-01' = "hostname SW-01`nip ssh version 2"
                'SW-02' = "hostname SW-02"
            }
            $rule = New-ValidationRule -RuleID 'SSH' -Name 'SSH v2' -Match 'ip ssh version 2' -Required
            $standard = New-ValidationStandard -Name 'Test' -Rules @($rule)

            $results = Test-BulkCompliance -Configs $configs -Standard $standard
            $results.Count | Should -Be 2

            $sw01 = $results | Where-Object { $_.DeviceName -eq 'SW-01' }
            $sw02 = $results | Where-Object { $_.DeviceName -eq 'SW-02' }

            $sw01.Passed | Should -Be 1
            $sw02.Failed | Should -Be 1
        }
    }

    Context 'Import/Export' {
        BeforeEach {
            Clear-StandardsLibrary
        }

        It 'exports and imports library' {
            $standard = New-ValidationStandard -Name 'export-test' -Rules @(
                New-ValidationRule -RuleID 'R1' -Name 'Test' -Match 'test' -Required
            )
            Add-ValidationStandard -Standard $standard

            $tempFile = Join-Path $env:TEMP 'standards-test.json'
            try {
                Export-StandardsLibrary -Path $tempFile
                Clear-StandardsLibrary

                $result = Import-StandardsLibrary -Path $tempFile
                $result.Imported | Should -Be 1

                $retrieved = Get-ValidationStandard -Name 'export-test'
                $retrieved.Rules.Count | Should -Be 1
            }
            finally {
                if (Test-Path $tempFile) { Remove-Item $tempFile }
            }
        }
    }

    Context 'Real-world Config Validation' {
        It 'validates Cisco config against security baseline' {
            $config = @"
hostname SW-CAMPUS-01
!
enable secret 5 $1$xxxx$hashedpassword
!
service password-encryption
!
ip ssh version 2
!
ip http server
!
logging buffered 16384
!
line vty 0 15
 transport input ssh
 access-class 10 in
"@
            $standard = Get-SecurityBaseline -Vendor 'Cisco_IOS'
            $result = Test-ConfigCompliance -Config $config -Standard $standard

            # Should pass: SSH v2, enable secret, password-encryption, logging, no telnet
            # Should fail: ip http server (prohibited), missing https, missing NTP auth
            $result.TotalRules | Should -BeGreaterThan 5
            $result.Score | Should -BeGreaterThan 50
        }
    }
}
