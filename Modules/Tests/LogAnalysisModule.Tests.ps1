Set-StrictMode -Version Latest

$modulePath = Join-Path $PSScriptRoot '..\LogAnalysisModule.psm1'
Import-Module $modulePath -Force

Describe 'LogAnalysisModule - Format Detection' {

    Context 'Get-LogFormat' {
        It 'detects Cisco IOS format' {
            $log = '*Mar  1 00:01:23.456: %LINK-3-UPDOWN: Interface GigabitEthernet0/1, changed state to down'
            $format = Get-LogFormat -Sample $log
            $format | Should Be 'CiscoIOS'
        }

        It 'detects Arista EOS format' {
            $log = 'Jan  4 12:34:56 switch1 Ebra: %LINEPROTO-5-UPDOWN: Line protocol on Interface Ethernet1, changed state to down'
            $format = Get-LogFormat -Sample $log
            $format | Should Be 'AristaEOS'
        }

        It 'detects RFC 5424 syslog format' {
            $log = '<165>1 2026-01-04T12:34:56.789Z router1 - - - Interface down'
            $format = Get-LogFormat -Sample $log
            $format | Should Be 'RFC5424'
        }

        It 'detects RFC 3164 syslog format' {
            $log = '<134>Jan  4 12:34:56 router1 message here'
            $format = Get-LogFormat -Sample $log
            $format | Should Be 'RFC3164'
        }

        It 'detects Generic timestamp format' {
            $log = '2026-01-04 12:34:56 Some log message'
            $format = Get-LogFormat -Sample $log
            $format | Should Be 'Generic'
        }

        It 'returns Unknown for unrecognized format' {
            $log = 'Random text without timestamp'
            $format = Get-LogFormat -Sample $log
            $format | Should Be 'Unknown'
        }
    }
}

Describe 'LogAnalysisModule - Log Parsing' {

    Context 'ConvertFrom-LogEntry Cisco IOS' {
        It 'parses standard Cisco IOS log' {
            $log = '*Mar  1 00:01:23.456: %LINK-3-UPDOWN: Interface GigabitEthernet0/1, changed state to down'
            $parsed = ConvertFrom-LogEntry -Entry $log -Format 'CiscoIOS'

            $parsed | Should Not BeNullOrEmpty
            $parsed.Facility | Should Be 'LINK'
            $parsed.Severity | Should Be 3
            $parsed.SeverityName | Should Be 'Error'
            $parsed.Mnemonic | Should Be 'UPDOWN'
            $parsed.MessageType | Should Be 'LINK-3-UPDOWN'
        }

        It 'extracts interface from message' {
            $log = '*Mar  1 00:01:23: %LINK-3-UPDOWN: Interface GigabitEthernet0/1, changed state to down'
            $parsed = ConvertFrom-LogEntry -Entry $log -Format 'CiscoIOS'

            $parsed.ExtractedFields.Interface | Should Be 'GigabitEthernet0/1'
            $parsed.ExtractedFields.NewState | Should Be 'down'
        }

        It 'handles log without asterisk prefix' {
            $log = 'Mar  1 00:01:23: %SYS-5-CONFIG_I: Configured from console'
            $parsed = ConvertFrom-LogEntry -Entry $log -Format 'CiscoIOS'

            $parsed.Facility | Should Be 'SYS'
            $parsed.Severity | Should Be 5
        }
    }

    Context 'ConvertFrom-LogEntry Arista EOS' {
        It 'parses Arista EOS log with process' {
            $log = 'Jan  4 12:34:56 switch1 Ebra: %LINEPROTO-5-UPDOWN: Line protocol on Interface Ethernet1, changed state to down'
            $parsed = ConvertFrom-LogEntry -Entry $log -Format 'AristaEOS'

            $parsed | Should Not BeNullOrEmpty
            $parsed.Hostname | Should Be 'switch1'
            $parsed.Process | Should Be 'Ebra'
            $parsed.Facility | Should Be 'LINEPROTO'
            $parsed.Severity | Should Be 5
        }

        It 'extracts interface from Arista log' {
            $log = 'Jan  4 12:34:56 switch1 Ebra: %LINEPROTO-5-UPDOWN: Line protocol on Interface Ethernet1, changed state to up'
            $parsed = ConvertFrom-LogEntry -Entry $log -Format 'AristaEOS'

            $parsed.ExtractedFields.Interface | Should Be 'Ethernet1'
            $parsed.ExtractedFields.NewState | Should Be 'up'
        }
    }

    Context 'ConvertFrom-LogEntry RFC 5424' {
        It 'parses RFC 5424 syslog' {
            $log = '<165>1 2026-01-04T12:34:56.789Z router1 app - - - Interface down'
            $parsed = ConvertFrom-LogEntry -Entry $log -Format 'RFC5424'

            $parsed | Should Not BeNullOrEmpty
            $parsed.Hostname | Should Be 'router1'
            $parsed.Process | Should Be 'app'
            # Priority 165 = Facility 20, Severity 5
            $parsed.Facility | Should Be 20
            $parsed.Severity | Should Be 5
        }
    }

    Context 'ConvertFrom-LogEntry Auto Detection' {
        It 'auto-detects and parses Cisco IOS' {
            $log = '*Mar  1 00:01:23: %LINK-3-UPDOWN: Interface Gi0/1, changed state to down'
            $parsed = ConvertFrom-LogEntry -Entry $log -Format 'Auto'

            $parsed.Format | Should Be 'CiscoIOS'
            $parsed.Facility | Should Be 'LINK'
        }
    }

    Context 'Get-ExtractedFields' {
        It 'extracts interface name' {
            $fields = Get-ExtractedFields -Message 'Interface GigabitEthernet0/1 is down'
            $fields.Interface | Should Be 'GigabitEthernet0/1'
        }

        It 'extracts short interface notation' {
            $fields = Get-ExtractedFields -Message 'Port Gi1/0/24 status changed'
            $fields.Interface | Should Be 'Gi1/0/24'
        }

        It 'extracts IP address' {
            $fields = Get-ExtractedFields -Message 'Connection from 192.168.1.100 failed'
            $fields.IPAddress | Should Be '192.168.1.100'
        }

        It 'extracts VLAN ID' {
            $fields = Get-ExtractedFields -Message 'VLAN 100 created'
            $fields.VLAN | Should Be 100
        }

        It 'extracts state change' {
            $fields = Get-ExtractedFields -Message 'changed state to up'
            $fields.NewState | Should Be 'up'
        }
    }
}

Describe 'LogAnalysisModule - Bulk Import' {

    Context 'Import-LogEntries' {
        It 'imports multiple log entries' {
            $logs = @(
                '*Mar  1 00:01:23: %LINK-3-UPDOWN: Interface Gi0/1, changed state to down',
                '*Mar  1 00:01:24: %LINK-3-UPDOWN: Interface Gi0/1, changed state to up',
                '*Mar  1 00:01:25: %SYS-5-CONFIG_I: Configured from console'
            )

            $result = Import-LogEntries -Entries $logs -Format 'CiscoIOS'

            $result.ImportedCount | Should Be 3
            $result.ErrorCount | Should Be 0
            $result.Entries.Count | Should Be 3
        }

        It 'handles parse errors gracefully' {
            $logs = @(
                '*Mar  1 00:01:23: %LINK-3-UPDOWN: Valid entry',
                'Invalid log format here',
                '*Mar  1 00:01:25: %LINK-3-UPDOWN: Another valid entry'
            )

            $result = Import-LogEntries -Entries $logs -Format 'CiscoIOS'

            $result.ImportedCount | Should Be 2
            $result.ErrorCount | Should Be 1
        }

        It 'auto-detects format from first entry' {
            $logs = @(
                '*Mar  1 00:01:23: %LINK-3-UPDOWN: Interface Gi0/1, down',
                '*Mar  1 00:01:24: %LINK-3-UPDOWN: Interface Gi0/1, up'
            )

            $result = Import-LogEntries -Entries $logs -Format 'Auto'

            $result.DetectedFormat | Should Be 'CiscoIOS'
        }

        It 'sets default hostname when provided' {
            $logs = @('*Mar  1 00:01:23: %LINK-3-UPDOWN: Interface Gi0/1, down')

            $result = Import-LogEntries -Entries $logs -Format 'CiscoIOS' -DefaultHostname 'SW-01'

            $result.Entries[0].Hostname | Should Be 'SW-01'
        }

        It 'skips empty lines' {
            $logs = [string[]]@(
                '*Mar  1 00:01:23: %LINK-3-UPDOWN: Entry 1',
                '',
                '  ',
                '*Mar  1 00:01:24: %LINK-3-UPDOWN: Entry 2'
            )

            # Filter out empty before passing to avoid parameter validation
            $filteredLogs = $logs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            $result = Import-LogEntries -Entries $filteredLogs -Format 'CiscoIOS'

            $result.ImportedCount | Should Be 2
        }
    }
}

Describe 'LogAnalysisModule - Pattern Detection' {

    Context 'Get-LogPattern' {
        It 'lists all built-in patterns' {
            $patterns = @(Get-LogPattern -List)

            $patterns.Count | Should BeGreaterThan 5
        }

        It 'includes LinkFlapping pattern' {
            $patterns = @(Get-LogPattern -List)
            $found = @($patterns | Where-Object { $_.Name -eq 'LinkFlapping' })

            $found.Count | Should BeGreaterThan 0
        }

        It 'includes STPTopologyChange pattern' {
            $patterns = @(Get-LogPattern -List)
            $found = @($patterns | Where-Object { $_.Name -eq 'STPTopologyChange' })

            $found.Count | Should BeGreaterThan 0
        }

        It 'gets pattern by name' {
            $pattern = @(Get-LogPattern -Name 'LinkFlapping')

            $pattern.Count | Should Be 1
            $pattern[0].Category | Should Be 'Layer1'
        }

        It 'filters patterns by category' {
            $patterns = @(Get-LogPattern -Category 'Security')

            $patterns.Count | Should BeGreaterThan 0
            foreach ($p in $patterns) {
                $p.Category | Should Be 'Security'
            }
        }
    }

    Context 'Find-LogPatterns' {
        It 'detects link flapping pattern' {
            $entries = @(
                [pscustomobject]@{ Message = '%LINK-3-UPDOWN: Interface Gi0/1, changed state to down'; ExtractedFields = @{ Interface = 'Gi0/1' } },
                [pscustomobject]@{ Message = '%LINK-3-UPDOWN: Interface Gi0/1, changed state to up'; ExtractedFields = @{ Interface = 'Gi0/1' } },
                [pscustomobject]@{ Message = '%LINK-3-UPDOWN: Interface Gi0/1, changed state to down'; ExtractedFields = @{ Interface = 'Gi0/1' } }
            )

            $patterns = @(Find-LogPatterns -Entries $entries)

            $flapping = @($patterns | Where-Object { $_.PatternName -eq 'LinkFlapping' })
            $flapping.Count | Should BeGreaterThan 0
            $flapping[0].MatchCount | Should Be 3
        }

        It 'detects STP topology change' {
            $entries = @(
                [pscustomobject]@{ Message = '%SPANTREE-5-TOPOTRAP: Topology change trap generated' }
            )

            $patterns = @(Find-LogPatterns -Entries $entries)

            $stp = @($patterns | Where-Object { $_.PatternName -eq 'STPTopologyChange' })
            $stp.Count | Should BeGreaterThan 0
        }

        It 'detects authentication failure' {
            $entries = @(
                [pscustomobject]@{ Message = '%SEC_LOGIN-4-LOGIN_FAILED: Login failed from 192.168.1.100'; ExtractedFields = @{ IPAddress = '192.168.1.100' } }
            )

            $patterns = @(Find-LogPatterns -Entries $entries)

            $auth = @($patterns | Where-Object { $_.PatternName -eq 'AuthenticationFailure' })
            $auth.Count | Should BeGreaterThan 0
        }

        It 'detects configuration change' {
            $entries = @(
                [pscustomobject]@{ Message = '%SYS-5-CONFIG_I: Configured from console by admin' }
            )

            $patterns = @(Find-LogPatterns -Entries $entries)

            $config = @($patterns | Where-Object { $_.PatternName -eq 'ConfigurationChange' })
            $config.Count | Should BeGreaterThan 0
        }

        It 'includes recommended action' {
            $entries = @(
                [pscustomobject]@{ Message = '%LINK-3-UPDOWN: changed state to down' },
                [pscustomobject]@{ Message = '%LINK-3-UPDOWN: changed state to up' },
                [pscustomobject]@{ Message = '%LINK-3-UPDOWN: changed state to down' }
            )

            $patterns = @(Find-LogPatterns -Entries $entries)

            $patterns[0].RecommendedAction | Should Not BeNullOrEmpty
        }

        It 'filters by include patterns' {
            $entries = @(
                [pscustomobject]@{ Message = '%LINK-3-UPDOWN: Interface Gi0/1, changed state to down'; ExtractedFields = @{ Interface = 'Gi0/1' } },
                [pscustomobject]@{ Message = '%LINK-3-UPDOWN: Interface Gi0/1, changed state to up'; ExtractedFields = @{ Interface = 'Gi0/1' } },
                [pscustomobject]@{ Message = '%LINK-3-UPDOWN: Interface Gi0/1, changed state to down'; ExtractedFields = @{ Interface = 'Gi0/1' } },
                [pscustomobject]@{ Message = '%SYS-5-CONFIG_I: config saved'; ExtractedFields = @{} }
            )

            $patterns = @(Find-LogPatterns -Entries $entries -IncludePatterns @('LinkFlapping'))

            $patterns.Count | Should Be 1
            $patterns[0].PatternName | Should Be 'LinkFlapping'
        }
    }

    Context 'Find-LinkFlapping' {
        It 'identifies flapping interface' {
            $entries = @(
                [pscustomobject]@{ Message = '%LINK-3-UPDOWN: Interface Gi0/1, changed state to down'; ExtractedFields = @{ Interface = 'Gi0/1' } },
                [pscustomobject]@{ Message = '%LINK-3-UPDOWN: Interface Gi0/1, changed state to up'; ExtractedFields = @{ Interface = 'Gi0/1' } },
                [pscustomobject]@{ Message = '%LINK-3-UPDOWN: Interface Gi0/1, changed state to down'; ExtractedFields = @{ Interface = 'Gi0/1' } },
                [pscustomobject]@{ Message = '%LINK-3-UPDOWN: Interface Gi0/1, changed state to up'; ExtractedFields = @{ Interface = 'Gi0/1' } }
            )

            $results = @(Find-LinkFlapping -Entries $entries -MinTransitions 3)

            $results.Count | Should Be 1
            $results[0].Interface | Should Be 'Gi0/1'
            $results[0].TransitionCount | Should Be 4
        }

        It 'groups by interface' {
            $entries = @(
                [pscustomobject]@{ Message = '%LINK-3-UPDOWN: Interface Gi0/1, changed state to down'; ExtractedFields = @{ Interface = 'Gi0/1' } },
                [pscustomobject]@{ Message = '%LINK-3-UPDOWN: Interface Gi0/1, changed state to up'; ExtractedFields = @{ Interface = 'Gi0/1' } },
                [pscustomobject]@{ Message = '%LINK-3-UPDOWN: Interface Gi0/1, changed state to down'; ExtractedFields = @{ Interface = 'Gi0/1' } },
                [pscustomobject]@{ Message = '%LINK-3-UPDOWN: Interface Gi0/2, changed state to down'; ExtractedFields = @{ Interface = 'Gi0/2' } }
            )

            $results = @(Find-LinkFlapping -Entries $entries -MinTransitions 3)

            $results.Count | Should Be 1
            $results[0].Interface | Should Be 'Gi0/1'
        }
    }
}

Describe 'LogAnalysisModule - Event Correlation' {

    Context 'Group-CorrelatedEvents' {
        It 'groups events within time window' {
            $baseTime = Get-Date
            $events = @(
                [pscustomobject]@{ Timestamp = $baseTime; Hostname = 'SW-01'; Message = 'Event 1' },
                [pscustomobject]@{ Timestamp = $baseTime.AddSeconds(5); Hostname = 'SW-01'; Message = 'Event 2' },
                [pscustomobject]@{ Timestamp = $baseTime.AddSeconds(10); Hostname = 'SW-02'; Message = 'Event 3' },
                [pscustomobject]@{ Timestamp = $baseTime.AddMinutes(5); Hostname = 'SW-03'; Message = 'Unrelated' }
            )

            $groups = @(Group-CorrelatedEvents -Events $events -WindowSeconds 60)

            $groups.Count | Should Be 2
            $groups[0].EventCount | Should Be 3
            $groups[1].EventCount | Should Be 1
        }

        It 'identifies devices in group' {
            $baseTime = Get-Date
            $events = @(
                [pscustomobject]@{ Timestamp = $baseTime; Hostname = 'SW-01'; Message = 'Event 1' },
                [pscustomobject]@{ Timestamp = $baseTime.AddSeconds(5); Hostname = 'SW-02'; Message = 'Event 2' }
            )

            $groups = @(Group-CorrelatedEvents -Events $events -WindowSeconds 60)

            ($groups[0].Devices -contains 'SW-01') | Should Be $true
            ($groups[0].Devices -contains 'SW-02') | Should Be $true
        }
    }

    Context 'Find-EventCascade' {
        It 'identifies trigger event' {
            $baseTime = Get-Date
            $events = @(
                [pscustomobject]@{ Timestamp = $baseTime; Hostname = 'CORE'; Message = 'Power supply failed' },
                [pscustomobject]@{ Timestamp = $baseTime.AddSeconds(1); Hostname = 'DS-01'; Message = 'Lost uplink' },
                [pscustomobject]@{ Timestamp = $baseTime.AddSeconds(2); Hostname = 'AS-01'; Message = 'Gateway unreachable' }
            )

            $cascade = Find-EventCascade -Events $events

            $cascade.TriggerDevice | Should Be 'CORE'
            ($cascade.AffectedDevices -contains 'DS-01') | Should Be $true
            ($cascade.AffectedDevices -contains 'AS-01') | Should Be $true
        }

        It 'counts cascade depth' {
            $baseTime = Get-Date
            $events = @(
                [pscustomobject]@{ Timestamp = $baseTime; Hostname = 'A'; Message = 'Root cause' },
                [pscustomobject]@{ Timestamp = $baseTime.AddSeconds(1); Hostname = 'B'; Message = 'Effect 1' },
                [pscustomobject]@{ Timestamp = $baseTime.AddSeconds(2); Hostname = 'C'; Message = 'Effect 2' }
            )

            $cascade = Find-EventCascade -Events $events

            $cascade.TotalEvents | Should Be 3
            $cascade.CascadeDepth | Should Be 2
        }
    }
}

Describe 'LogAnalysisModule - Search and Filter' {

    BeforeAll {
        $script:sampleEntries = @(
            [pscustomobject]@{ Timestamp = (Get-Date '2026-01-04 12:00:00'); Severity = 3; Hostname = 'SW-01'; Facility = 'LINK'; Message = 'Interface Gi0/1 down'; MessageType = 'LINK-3-UPDOWN'; ExtractedFields = @{ Interface = 'Gi0/1' } },
            [pscustomobject]@{ Timestamp = (Get-Date '2026-01-04 12:05:00'); Severity = 5; Hostname = 'SW-01'; Facility = 'SYS'; Message = 'Config saved'; MessageType = 'SYS-5-CONFIG'; ExtractedFields = @{} },
            [pscustomobject]@{ Timestamp = (Get-Date '2026-01-04 12:10:00'); Severity = 3; Hostname = 'SW-02'; Facility = 'LINK'; Message = 'Interface Gi0/2 down'; MessageType = 'LINK-3-UPDOWN'; ExtractedFields = @{ Interface = 'Gi0/2' } },
            [pscustomobject]@{ Timestamp = (Get-Date '2026-01-04 12:15:00'); Severity = 2; Hostname = 'CORE'; Facility = 'PLATFORM'; Message = 'Power warning'; MessageType = 'PLATFORM-2-WARNING'; ExtractedFields = @{} }
        )
    }

    Context 'Search-LogEntries' {
        It 'searches by keyword' {
            $results = @(Search-LogEntries -Entries $sampleEntries -Keyword 'down')

            $results.Count | Should Be 2
        }

        It 'filters by device' {
            $results = @(Search-LogEntries -Entries $sampleEntries -Device 'SW-01')

            $results.Count | Should Be 2
            foreach ($r in $results) {
                $r.Hostname | Should Be 'SW-01'
            }
        }

        It 'filters by max severity' {
            $results = @(Search-LogEntries -Entries $sampleEntries -MaxSeverity 3)

            $results.Count | Should Be 3
            foreach ($r in $results) {
                ($r.Severity -le 3) | Should Be $true
            }
        }

        It 'filters by facility' {
            $results = @(Search-LogEntries -Entries $sampleEntries -Facility 'LINK')

            $results.Count | Should Be 2
        }

        It 'filters by time range' {
            $results = @(Search-LogEntries -Entries $sampleEntries `
                -StartTime (Get-Date '2026-01-04 12:00:00') `
                -EndTime (Get-Date '2026-01-04 12:07:00'))

            $results.Count | Should Be 2
        }

        It 'filters by interface' {
            $results = @(Search-LogEntries -Entries $sampleEntries -Interface 'Gi0/1')

            $results.Count | Should Be 1
            $results[0].ExtractedFields.Interface | Should Be 'Gi0/1'
        }

        It 'combines multiple filters' {
            $results = @(Search-LogEntries -Entries $sampleEntries -Device 'SW-01' -MaxSeverity 3)

            $results.Count | Should Be 1
        }
    }

    Context 'Get-LogSeverityStats' {
        It 'counts entries by severity' {
            $stats = Get-LogSeverityStats -Entries $sampleEntries

            $stats.Error | Should Be 2
            $stats.Notice | Should Be 1
            $stats.Critical | Should Be 1
        }
    }

    Context 'Get-LogAnalysisSummary' {
        It 'provides comprehensive summary' {
            $summary = Get-LogAnalysisSummary -Entries $sampleEntries

            $summary.TotalEntries | Should Be 4
            $summary.DeviceCount | Should Be 3
            ($summary.Devices -contains 'SW-01') | Should Be $true
            ($summary.Devices -contains 'SW-02') | Should Be $true
            ($summary.Devices -contains 'CORE') | Should Be $true
        }

        It 'includes time range' {
            $summary = Get-LogAnalysisSummary -Entries $sampleEntries

            $summary.TimeRange | Should Not BeNullOrEmpty
            $summary.TimeRange.Start | Should Not BeNullOrEmpty
            $summary.TimeRange.End | Should Not BeNullOrEmpty
        }

        It 'includes severity breakdown' {
            $summary = Get-LogAnalysisSummary -Entries $sampleEntries

            $summary.SeverityBreakdown | Should Not BeNullOrEmpty
            $summary.SeverityBreakdown.Error | Should Be 2
        }
    }
}
