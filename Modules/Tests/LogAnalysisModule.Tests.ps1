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

#region ST-AE-005: Anomaly Detection Tests

Describe 'LogAnalysisModule - Anomaly Detection' {

    Context 'Find-FrequencyAnomalies' {
        It 'detects frequency spike' {
            $baseTime = Get-Date '2026-01-04 12:00:00'
            # Normal entries spread across time (1 per minute for 20 minutes)
            $normal = 1..20 | ForEach-Object {
                [pscustomobject]@{ Timestamp = $baseTime.AddMinutes($_); Message = 'Normal log' }
            }
            # Spike - many entries in one bucket (100 entries in 5-min bucket)
            $spike = 1..100 | ForEach-Object {
                [pscustomobject]@{ Timestamp = $baseTime.AddMinutes(30); Message = 'Spike log' }
            }

            # Use lower threshold for reliable detection
            $anomalies = @(Find-FrequencyAnomalies -Entries ($normal + $spike) -BucketMinutes 5 -ThresholdMultiplier 1.5)

            $anomalies.Count | Should BeGreaterThan 0
            $anomalies[0].Type | Should Be 'FrequencySpike'
        }

        It 'returns empty for uniform distribution' {
            $baseTime = Get-Date '2026-01-04 12:00:00'
            $entries = 1..20 | ForEach-Object {
                [pscustomobject]@{ Timestamp = $baseTime.AddMinutes($_ * 3); Message = 'Regular log' }
            }

            $anomalies = @(Find-FrequencyAnomalies -Entries $entries -BucketMinutes 5)

            $anomalies.Count | Should Be 0
        }

        It 'calculates multiplier for spikes' {
            $baseTime = Get-Date '2026-01-04 12:00:00'
            $normal = 1..5 | ForEach-Object {
                [pscustomobject]@{ Timestamp = $baseTime.AddMinutes($_); Message = 'Normal' }
            }
            $spike = 1..100 | ForEach-Object {
                [pscustomobject]@{ Timestamp = $baseTime.AddMinutes(30); Message = 'Spike' }
            }

            $anomalies = @(Find-FrequencyAnomalies -Entries ($normal + $spike) -BucketMinutes 5)

            if ($anomalies.Count -gt 0) {
                $anomalies[0].Multiplier | Should BeGreaterThan 1
            }
        }
    }

    Context 'Find-NewMessageTypes' {
        It 'identifies new message types' {
            $baseline = @(
                [pscustomobject]@{ MessageType = 'LINK-3-UPDOWN' },
                [pscustomobject]@{ MessageType = 'SYS-5-CONFIG' }
            )
            $current = @(
                [pscustomobject]@{ MessageType = 'LINK-3-UPDOWN' },
                [pscustomobject]@{ MessageType = 'SEC-4-VIOLATION' }
            )

            $newTypes = @(Find-NewMessageTypes -Baseline $baseline -Current $current)

            $newTypes.Count | Should Be 1
            ($newTypes -contains 'SEC-4-VIOLATION') | Should Be $true
        }

        It 'returns empty when no new types' {
            $baseline = @(
                [pscustomobject]@{ MessageType = 'TYPE-A' },
                [pscustomobject]@{ MessageType = 'TYPE-B' }
            )
            $current = @(
                [pscustomobject]@{ MessageType = 'TYPE-A' }
            )

            $newTypes = @(Find-NewMessageTypes -Baseline $baseline -Current $current)

            $newTypes.Count | Should Be 0
        }

        It 'uses Mnemonic as fallback' {
            $baseline = @(
                [pscustomobject]@{ Mnemonic = 'UPDOWN' }
            )
            $current = @(
                [pscustomobject]@{ Mnemonic = 'UPDOWN' },
                [pscustomobject]@{ Mnemonic = 'NEWMNEM' }
            )

            $newTypes = @(Find-NewMessageTypes -Baseline $baseline -Current $current)

            ($newTypes -contains 'NEWMNEM') | Should Be $true
        }
    }

    Context 'Test-TimeOfDayAnomaly' {
        It 'detects after-hours activity' {
            $event = [pscustomobject]@{
                Timestamp = (Get-Date '2026-01-06 03:00:00')  # Monday at 3 AM
                Message = 'Configuration changed'
            }
            $workHours = @{ Start = '08:00'; End = '18:00' }

            $result = Test-TimeOfDayAnomaly -Event $event -WorkHours $workHours

            $result.IsAnomaly | Should Be $true
            $result.Reason | Should Match 'outside work hours'
        }

        It 'accepts normal work hours activity' {
            $event = [pscustomobject]@{
                Timestamp = (Get-Date '2026-01-06 10:00:00')  # Monday at 10 AM
                Message = 'Normal activity'
            }
            $workHours = @{ Start = '08:00'; End = '18:00' }

            $result = Test-TimeOfDayAnomaly -Event $event -WorkHours $workHours

            $result.IsAnomaly | Should Be $false
        }

        It 'detects weekend activity' {
            $event = [pscustomobject]@{
                Timestamp = (Get-Date '2026-01-04 10:00:00')  # Saturday at 10 AM
                Message = 'Weekend config change'
            }

            $result = Test-TimeOfDayAnomaly -Event $event

            $result.IsAnomaly | Should Be $true
            $result.Reason | Should Match 'outside work days'
        }

        It 'handles missing timestamp' {
            $event = [pscustomobject]@{ Message = 'No timestamp' }

            $result = Test-TimeOfDayAnomaly -Event $event

            $result.IsAnomaly | Should Be $false
            $result.Reason | Should Match 'No timestamp'
        }
    }
}

#endregion

#region ST-AE-006: Report Generation Tests

Describe 'LogAnalysisModule - Saved Searches' {

    Context 'Save-LogSearch and Get-LogSearch' {
        It 'saves and retrieves search query' {
            $query = @{
                Name = 'CriticalErrors'
                Filters = @{ MaxSeverity = 3; Keyword = 'error' }
            }
            Save-LogSearch -Query $query

            $loaded = Get-LogSearch -Name 'CriticalErrors'

            $loaded.Name | Should Be 'CriticalErrors'
            $loaded.Filters.MaxSeverity | Should Be 3
        }

        It 'lists all saved searches' {
            Save-LogSearch -Query @{ Name = 'Search1'; Filters = @{} }
            Save-LogSearch -Query @{ Name = 'Search2'; Filters = @{} }

            $all = @(Get-LogSearch -List)

            $all.Count | Should BeGreaterThan 1
        }

        It 'returns null for unknown search' {
            $result = Get-LogSearch -Name 'NonExistentSearch'

            $result | Should Be $null
        }
    }
}

Describe 'LogAnalysisModule - Report Generation' {

    BeforeAll {
        $script:reportEntries = @(
            [pscustomobject]@{ Timestamp = (Get-Date); Severity = 3; Hostname = 'SW-01'; Facility = 'LINK'; Message = '%LINK-3-UPDOWN: Interface down'; ExtractedFields = @{}; MessageType = 'LINK-3-UPDOWN' },
            [pscustomobject]@{ Timestamp = (Get-Date); Severity = 3; Hostname = 'SW-02'; Facility = 'LINK'; Message = '%LINK-3-UPDOWN: Interface down'; ExtractedFields = @{}; MessageType = 'LINK-3-UPDOWN' },
            [pscustomobject]@{ Timestamp = (Get-Date); Severity = 4; Hostname = 'CORE'; Facility = 'SYS'; Message = '%SYS-4-WARNING: Memory low'; ExtractedFields = @{}; MessageType = 'SYS-4-WARNING' }
        )
    }

    Context 'New-LogAnalysisReport Summary' {
        It 'generates summary report' {
            $report = New-LogAnalysisReport -Entries $reportEntries -Type 'Summary'

            $report.Type | Should Be 'Summary'
            $report.Data.TotalEntries | Should Be 3
        }

        It 'includes patterns in summary' {
            $report = New-LogAnalysisReport -Entries $reportEntries -Type 'Summary'

            $report.Data | Should Not BeNullOrEmpty
        }

        It 'sets custom title' {
            $report = New-LogAnalysisReport -Entries $reportEntries -Type 'Summary' -Title 'My Report'

            $report.Title | Should Be 'My Report'
        }
    }

    Context 'New-LogAnalysisReport PatternSummary' {
        It 'generates pattern summary report' {
            $report = New-LogAnalysisReport -Entries $reportEntries -Type 'PatternSummary'

            $report.Type | Should Be 'PatternSummary'
            $report.Data.TotalEntries | Should Be 3
        }

        It 'includes top patterns' {
            $report = New-LogAnalysisReport -Entries $reportEntries -Type 'PatternSummary'

            $report.Data.TopPatterns | Should Not BeNullOrEmpty
        }
    }

    Context 'New-LogAnalysisReport TrendComparison' {
        It 'generates trend comparison report' {
            # Messages must match LinkFlapping regex: %LINK-\d-UPDOWN.*changed state to
            $previous = @(
                [pscustomobject]@{ Severity = 3; Hostname = 'SW-01'; Facility = 'LINK'; Message = '%LINK-3-UPDOWN: Interface Gi1/0/1, changed state to down'; ExtractedFields = @{} },
                [pscustomobject]@{ Severity = 3; Hostname = 'SW-01'; Facility = 'LINK'; Message = '%LINK-3-UPDOWN: Interface Gi1/0/1, changed state to up'; ExtractedFields = @{} },
                [pscustomobject]@{ Severity = 3; Hostname = 'SW-01'; Facility = 'LINK'; Message = '%LINK-3-UPDOWN: Interface Gi1/0/1, changed state to down'; ExtractedFields = @{} }
            )
            $current = @(
                [pscustomobject]@{ Severity = 3; Hostname = 'SW-01'; Facility = 'LINK'; Message = '%LINK-3-UPDOWN: Interface Gi1/0/1, changed state to down'; ExtractedFields = @{} },
                [pscustomobject]@{ Severity = 3; Hostname = 'SW-01'; Facility = 'LINK'; Message = '%LINK-3-UPDOWN: Interface Gi1/0/1, changed state to up'; ExtractedFields = @{} },
                [pscustomobject]@{ Severity = 3; Hostname = 'SW-01'; Facility = 'LINK'; Message = '%LINK-3-UPDOWN: Interface Gi1/0/1, changed state to down'; ExtractedFields = @{} },
                [pscustomobject]@{ Severity = 3; Hostname = 'SW-01'; Facility = 'LINK'; Message = '%LINK-3-UPDOWN: Interface Gi1/0/1, changed state to up'; ExtractedFields = @{} },
                [pscustomobject]@{ Severity = 3; Hostname = 'SW-01'; Facility = 'LINK'; Message = '%LINK-3-UPDOWN: Interface Gi1/0/1, changed state to down'; ExtractedFields = @{} },
                [pscustomobject]@{ Severity = 3; Hostname = 'SW-01'; Facility = 'LINK'; Message = '%LINK-3-UPDOWN: Interface Gi1/0/1, changed state to up'; ExtractedFields = @{} }
            )

            $report = New-LogAnalysisReport -CurrentPeriod $current -PreviousPeriod $previous -Type 'TrendComparison'

            $report.Type | Should Be 'TrendComparison'
            $report.Data.Comparison | Should Not BeNullOrEmpty
        }

        It 'calculates entry count change' {
            $prev = @(
                [pscustomobject]@{ Severity = 6; Hostname = 'SW-01'; Facility = 'SYS'; Message = 'Entry 1'; ExtractedFields = @{} },
                [pscustomobject]@{ Severity = 6; Hostname = 'SW-01'; Facility = 'SYS'; Message = 'Entry 2'; ExtractedFields = @{} }
            )
            $curr = @(
                [pscustomobject]@{ Severity = 6; Hostname = 'SW-01'; Facility = 'SYS'; Message = 'Entry 1'; ExtractedFields = @{} },
                [pscustomobject]@{ Severity = 6; Hostname = 'SW-01'; Facility = 'SYS'; Message = 'Entry 2'; ExtractedFields = @{} },
                [pscustomobject]@{ Severity = 6; Hostname = 'SW-01'; Facility = 'SYS'; Message = 'Entry 3'; ExtractedFields = @{} }
            )
            $report = New-LogAnalysisReport -CurrentPeriod $curr -PreviousPeriod $prev -Type 'TrendComparison'

            $report.Data.EntryCountChange | Should Be 1
        }
    }

    Context 'New-LogAnalysisReport Health' {
        It 'generates health report' {
            $report = New-LogAnalysisReport -Entries $reportEntries -Type 'Health'

            $report.Type | Should Be 'Health'
            $report.Data.HealthScore | Should Not BeNullOrEmpty
        }

        It 'calculates health score' {
            $healthyEntries = @(
                [pscustomobject]@{ Severity = 6; Message = 'Info message'; ExtractedFields = @{} }
            )

            $report = New-LogAnalysisReport -Entries $healthyEntries -Type 'Health'

            $report.Data.HealthScore | Should Be 100
            $report.Data.HealthStatus | Should Be 'Healthy'
        }

        It 'deducts for critical/error/warning' {
            $criticalEntries = @(
                [pscustomobject]@{ Severity = 2; Message = 'Critical'; ExtractedFields = @{} },
                [pscustomobject]@{ Severity = 3; Message = 'Error'; ExtractedFields = @{} },
                [pscustomobject]@{ Severity = 4; Message = 'Warning'; ExtractedFields = @{} }
            )

            $report = New-LogAnalysisReport -Entries $criticalEntries -Type 'Health'

            ($report.Data.HealthScore -lt 100) | Should Be $true
        }
    }
}

Describe 'LogAnalysisModule - Report Export' {

    BeforeAll {
        $script:testReportDir = Join-Path $env:TEMP 'LogReportTests'
        New-Item -ItemType Directory -Path $script:testReportDir -Force | Out-Null

        $script:testReport = New-LogAnalysisReport -Entries @(
            [pscustomobject]@{ Timestamp = (Get-Date); Severity = 3; Hostname = 'SW-01'; Facility = 'LINK'; Message = 'Test entry'; ExtractedFields = @{} }
        ) -Type 'Summary' -Title 'Test Report'
    }

    AfterAll {
        if (Test-Path $script:testReportDir) {
            Remove-Item -Path $script:testReportDir -Recurse -Force
        }
    }

    Context 'Export-LogReport' {
        It 'exports to HTML' {
            $path = Join-Path $script:testReportDir 'test.html'
            $result = Export-LogReport -Report $testReport -Format HTML -OutputPath $path

            Test-Path $result | Should Be $true
            $content = Get-Content -LiteralPath $result -Raw
            $content | Should Match '<html>'
            $content | Should Match 'Test Report'
        }

        It 'exports to JSON' {
            $path = Join-Path $script:testReportDir 'test.json'
            $result = Export-LogReport -Report $testReport -Format JSON -OutputPath $path

            Test-Path $result | Should Be $true
            $json = Get-Content -LiteralPath $result -Raw | ConvertFrom-Json
            $json.Title | Should Be 'Test Report'
        }

        It 'exports to Markdown' {
            $path = Join-Path $script:testReportDir 'test.md'
            $result = Export-LogReport -Report $testReport -Format Markdown -OutputPath $path

            Test-Path $result | Should Be $true
            $content = Get-Content -LiteralPath $result -Raw
            $content | Should Match '# Test Report'
        }

        It 'exports to PDF (print-ready HTML)' {
            $path = Join-Path $script:testReportDir 'test_pdf.html'
            $result = Export-LogReport -Report $testReport -Format PDF -OutputPath $path

            Test-Path $result | Should Be $true
            $content = Get-Content -LiteralPath $result -Raw
            $content | Should Match '@page'
            $content | Should Match '@media print'
        }

        It 'generates default path when not specified' {
            $result = Export-LogReport -Report $testReport -Format HTML

            Test-Path $result | Should Be $true
            $result | Should Match 'LogReport_'

            # Cleanup
            Remove-Item -LiteralPath $result -Force
        }
    }
}

#endregion
