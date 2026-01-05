# Plan AE - Log Analysis & Pattern Detection

<!-- LANDMARK: ST-E-001 telemetry gates link -->
Telemetry gates: [docs/telemetry/Automation_Gates.md](../telemetry/Automation_Gates.md).

## Objective
Provide intelligent log analysis and pattern detection capabilities for network device logs. Enable network teams to quickly identify issues, correlate events across devices, recognize recurring problems, and extract actionable insights from log data without direct device access.

## Problem Statement
Network teams struggle with:
- Analyzing large volumes of device logs manually
- Identifying patterns in log messages across multiple devices
- Correlating events that happen on different devices
- Recognizing recurring issues that waste troubleshooting time
- Extracting meaningful metrics from unstructured log data
- Filtering signal from noise in verbose log output
- Understanding root cause when multiple events cascade

## Current status (2026-01)
- Log ingestion exists for routing data
- No dedicated log analysis or pattern detection
- No event correlation across devices
- No historical pattern recognition

## Proposed Features

### AE.1 Log Ingestion & Parsing
- **Multi-Format Support**:
  - Syslog (RFC 3164 / RFC 5424)
  - Cisco IOS/IOS-XE format
  - Arista EOS format
  - Generic timestamped logs
  - CSV log exports
- **Field Extraction**:
  - Timestamp normalization
  - Severity/priority parsing
  - Facility identification
  - Message classification
  - Structured data extraction
- **Bulk Import**:
  - Paste logs directly
  - Import from file
  - Import from directory (batch)

### AE.2 Pattern Detection
- **Known Pattern Library**: Recognize common issues:
  - Link flapping
  - STP topology changes
  - Authentication failures
  - Power supply issues
  - High CPU/memory conditions
  - Interface errors
  - Routing adjacency changes
  - Port security violations
- **Anomaly Detection**:
  - Unusual message frequency
  - New/unseen message types
  - Time-of-day anomalies
  - Volume spikes
- **Custom Patterns**: User-defined detection rules:
  - Regex patterns
  - Keyword combinations
  - Threshold triggers

### AE.3 Event Correlation
- **Temporal Correlation**: Group related events:
  - Events within time window
  - Cause-and-effect chains
  - Cascading failures
- **Device Correlation**: Link across devices:
  - Same issue on multiple devices
  - Upstream/downstream relationships
  - Peer device events
- **Root Cause Analysis**:
  - Identify triggering event
  - Show event cascade timeline
  - Suggest probable cause

### AE.4 Log Visualization
- **Timeline View**: Events plotted over time:
  - Severity color coding
  - Device grouping
  - Zoom/pan navigation
  - Event density heatmap
- **Pattern Dashboard**:
  - Top patterns detected
  - Frequency charts
  - Trend analysis
- **Device Comparison**:
  - Side-by-side log view
  - Synchronized scrolling
  - Highlight matching events

### AE.5 Search & Filter
- **Full-Text Search**: Find any log message
- **Structured Queries**:
  - By severity level
  - By device/source
  - By facility
  - By time range
  - By pattern type
- **Saved Searches**: Store common queries
- **Export Results**: To CSV, JSON, or report format

### AE.6 Alerting & Reporting
- **Pattern Reports**: Summarize detected issues:
  - Top 10 recurring patterns
  - New patterns this period
  - Pattern frequency trends
- **Health Summary**: Overall log health score
- **Trend Analysis**: Compare periods:
  - This week vs last week
  - Before/after change window

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-AE-001 | Log parser engine | Tools | Pending | Multi-format parsing |
| ST-AE-002 | Pattern library | Tools | Pending | Known issue patterns |
| ST-AE-003 | Correlation engine | Tools | Pending | Cross-device event linking |
| ST-AE-004 | Log analysis UI | UI | Pending | Timeline and search views |
| ST-AE-005 | Anomaly detection | Tools | Pending | Statistical analysis |
| ST-AE-006 | Pattern reports | Tools | Pending | Summary and trend reports |

## Data Model (Proposed)

### LogEntry Table
```
EntryID (PK), ImportBatchID, Timestamp, SourceDevice, Facility,
Severity, MessageType, RawMessage, ParsedFields, PatternID (FK)
```

### LogPattern Table
```
PatternID (PK), Name, Description, Category, RegexPattern,
Severity, IsBuiltIn, RecommendedAction, KBArticleLink
```

### PatternMatch Table
```
MatchID (PK), EntryID (FK), PatternID (FK), MatchedAt,
Confidence, ExtractedValues
```

### CorrelationGroup Table
```
GroupID (PK), Name, StartTime, EndTime, TriggerEntryID,
RootCause, DevicesInvolved, EventCount, Notes
```

### LogImport Table
```
ImportID (PK), ImportDate, SourceType, FileName,
EntryCount, ParseErrors, ProcessingTime, Notes
```

## Testing Requirements

### Unit Tests (`Modules/Tests/LogAnalysisModule.Tests.ps1`)

```powershell
Describe 'Log Analysis' -Tag 'LogAnalysis' {

    Describe 'Log Parsing' {
        It 'parses Cisco IOS syslog format' {
            $log = '*Mar  1 00:01:23.456: %LINK-3-UPDOWN: Interface GigabitEthernet0/1, changed state to down'

            $parsed = Parse-LogEntry -Entry $log -Format 'CiscoIOS'

            $parsed.Timestamp | Should -Not -BeNullOrEmpty
            $parsed.Facility | Should -Be 'LINK'
            $parsed.Severity | Should -Be 3
            $parsed.MessageType | Should -Be 'UPDOWN'
            $parsed.Interface | Should -Be 'GigabitEthernet0/1'
        }

        It 'parses RFC 5424 syslog format' {
            $log = '<165>1 2026-01-04T12:34:56.789Z router1 - - - Interface down'

            $parsed = Parse-LogEntry -Entry $log -Format 'RFC5424'

            $parsed.Priority | Should -Be 165
            $parsed.Facility | Should -Be 20  # 165 / 8
            $parsed.Severity | Should -Be 5   # 165 % 8
            $parsed.Hostname | Should -Be 'router1'
        }

        It 'parses Arista EOS log format' {
            $log = 'Jan  4 12:34:56 switch1 Ebra: %LINEPROTO-5-UPDOWN: Line protocol on Interface Ethernet1, changed state to down'

            $parsed = Parse-LogEntry -Entry $log -Format 'AristaEOS'

            $parsed.Hostname | Should -Be 'switch1'
            $parsed.Process | Should -Be 'Ebra'
            $parsed.Interface | Should -Be 'Ethernet1'
        }

        It 'auto-detects log format' {
            $ciscoLog = '*Mar  1 00:01:23: %SYS-5-CONFIG_I: Configured from console'
            $aristaLog = 'Jan  4 12:34:56 switch1 ConfigAgent: Config saved'

            $format1 = Detect-LogFormat -Sample $ciscoLog
            $format2 = Detect-LogFormat -Sample $aristaLog

            $format1 | Should -Be 'CiscoIOS'
            $format2 | Should -Be 'AristaEOS'
        }

        It 'handles multi-line log entries' {
            $log = @'
*Mar  1 00:01:23: %SYS-5-CONFIG_I: Configured from console
  Additional context line 1
  Additional context line 2
'@
            $parsed = Parse-LogEntry -Entry $log -Format 'CiscoIOS' -MultiLine

            $parsed.Message | Should -Match 'context line'
        }

        It 'extracts structured fields from message' {
            $log = '*Mar  1 00:01:23: %LINK-3-UPDOWN: Interface GigabitEthernet0/1, changed state to down'

            $parsed = Parse-LogEntry -Entry $log -Format 'CiscoIOS'

            $parsed.ExtractedFields.Interface | Should -Be 'GigabitEthernet0/1'
            $parsed.ExtractedFields.NewState | Should -Be 'down'
        }
    }

    Describe 'Pattern Detection' {
        BeforeAll {
            $script:testLogs = @(
                @{ Timestamp = '2026-01-04 12:00:00'; Message = '%LINK-3-UPDOWN: Interface Gi0/1, changed state to down' },
                @{ Timestamp = '2026-01-04 12:00:05'; Message = '%LINK-3-UPDOWN: Interface Gi0/1, changed state to up' },
                @{ Timestamp = '2026-01-04 12:00:10'; Message = '%LINK-3-UPDOWN: Interface Gi0/1, changed state to down' },
                @{ Timestamp = '2026-01-04 12:00:15'; Message = '%LINK-3-UPDOWN: Interface Gi0/1, changed state to up' }
            )
        }

        It 'detects link flapping pattern' {
            $patterns = Find-LogPatterns -Entries $testLogs

            $flapping = $patterns | Where-Object { $_.PatternName -eq 'LinkFlapping' }
            $flapping | Should -Not -BeNullOrEmpty
            $flapping.Interface | Should -Be 'Gi0/1'
            $flapping.TransitionCount | Should -BeGreaterThan 2
        }

        It 'detects STP topology change pattern' {
            $stpLogs = @(
                @{ Message = '%SPANTREE-5-TOPOTRAP: Topology change trap' },
                @{ Message = '%SPANTREE-5-ROOTCHANGE: Root Changed' }
            )

            $patterns = Find-LogPatterns -Entries $stpLogs

            $stpPattern = $patterns | Where-Object { $_.PatternName -match 'STP' }
            $stpPattern | Should -Not -BeNullOrEmpty
        }

        It 'identifies authentication failure pattern' {
            $authLogs = @(
                @{ Message = '%SEC_LOGIN-4-LOGIN_FAILED: Login failed from 192.168.1.100' },
                @{ Message = '%SEC_LOGIN-4-LOGIN_FAILED: Login failed from 192.168.1.100' },
                @{ Message = '%SEC_LOGIN-4-LOGIN_FAILED: Login failed from 192.168.1.100' }
            )

            $patterns = Find-LogPatterns -Entries $authLogs

            $authPattern = $patterns | Where-Object { $_.PatternName -eq 'AuthenticationFailure' }
            $authPattern.FailureCount | Should -Be 3
            $authPattern.SourceIP | Should -Be '192.168.1.100'
        }

        It 'applies custom pattern rules' {
            $customPattern = @{
                Name = 'CustomError'
                Regex = 'CUSTOM-ERROR-(\d+)'
                Severity = 'High'
            }
            $logs = @(@{ Message = 'CUSTOM-ERROR-42: Something bad happened' })

            $matches = Find-LogPatterns -Entries $logs -CustomPatterns @($customPattern)

            $matches | Where-Object { $_.PatternName -eq 'CustomError' } | Should -Not -BeNullOrEmpty
        }

        It 'calculates pattern frequency over time' {
            $logs = 1..100 | ForEach-Object {
                @{ Timestamp = (Get-Date).AddMinutes(-$_); Message = '%LINK-3-UPDOWN: state change' }
            }

            $frequency = Get-PatternFrequency -Entries $logs -Pattern 'UPDOWN' -BucketMinutes 10

            $frequency.Buckets.Count | Should -BeGreaterThan 5
        }
    }

    Describe 'Event Correlation' {
        It 'groups temporally related events' {
            $events = @(
                @{ Timestamp = '2026-01-04 12:00:00'; Device = 'SW-01'; Message = 'Interface down' },
                @{ Timestamp = '2026-01-04 12:00:02'; Device = 'SW-01'; Message = 'STP recalculating' },
                @{ Timestamp = '2026-01-04 12:00:05'; Device = 'SW-02'; Message = 'Lost neighbor' },
                @{ Timestamp = '2026-01-04 13:00:00'; Device = 'SW-03'; Message = 'Unrelated event' }
            )

            $groups = Group-CorrelatedEvents -Events $events -WindowSeconds 60

            $groups.Count | Should -Be 2
            $groups[0].Events.Count | Should -Be 3
        }

        It 'identifies cascade relationships' {
            $events = @(
                @{ Timestamp = '12:00:00'; Device = 'CORE'; Message = 'Power supply failed' },
                @{ Timestamp = '12:00:01'; Device = 'DS-01'; Message = 'Lost uplink to CORE' },
                @{ Timestamp = '12:00:01'; Device = 'DS-02'; Message = 'Lost uplink to CORE' },
                @{ Timestamp = '12:00:02'; Device = 'AS-01'; Message = 'Lost path to gateway' }
            )

            $cascade = Find-EventCascade -Events $events

            $cascade.TriggerEvent.Device | Should -Be 'CORE'
            $cascade.AffectedDevices | Should -Contain 'DS-01'
            $cascade.AffectedDevices | Should -Contain 'AS-01'
        }

        It 'correlates same issue across devices' {
            $events = @(
                @{ Device = 'SW-01'; Message = '%DUPLEX-3-MISMATCH on Gi0/1' },
                @{ Device = 'SW-02'; Message = '%DUPLEX-3-MISMATCH on Gi0/24' }
            )

            $correlation = Find-CrossDevicePatterns -Events $events

            $correlation.PatternName | Should -Be 'DuplexMismatch'
            $correlation.AffectedDevices.Count | Should -Be 2
        }

        It 'suggests root cause' {
            $events = @(
                @{ Timestamp = '12:00:00'; Message = 'Power supply 1 failed' },
                @{ Timestamp = '12:00:01'; Message = 'High CPU detected' },
                @{ Timestamp = '12:00:02'; Message = 'Interface errors increasing' }
            )

            $analysis = Get-RootCauseAnalysis -Events $events

            $analysis.ProbableCause | Should -Match 'Power'
            $analysis.Confidence | Should -BeGreaterThan 0.5
        }
    }

    Describe 'Anomaly Detection' {
        It 'detects unusual message frequency' {
            $normal = 1..10 | ForEach-Object { @{ Timestamp = "12:00:$_"; Message = 'Normal log' } }
            $spike = 1..100 | ForEach-Object { @{ Timestamp = "12:05:00"; Message = 'Spike log' } }

            $anomalies = Find-FrequencyAnomalies -Entries ($normal + $spike) -BaselinePeriod 60

            $anomalies | Should -Not -BeNullOrEmpty
            $anomalies.Type | Should -Contain 'FrequencySpike'
        }

        It 'identifies new message types' {
            $baseline = @(
                @{ MessageType = 'LINK-UPDOWN' },
                @{ MessageType = 'CONFIG-CHANGE' }
            )
            $current = @(
                @{ MessageType = 'LINK-UPDOWN' },
                @{ MessageType = 'SECURITY-VIOLATION' }  # New
            )

            $newTypes = Find-NewMessageTypes -Baseline $baseline -Current $current

            $newTypes | Should -Contain 'SECURITY-VIOLATION'
        }

        It 'detects after-hours activity' {
            $event = @{
                Timestamp = '2026-01-04 03:00:00'
                Message = 'Configuration changed'
            }
            $workHours = @{ Start = '08:00'; End = '18:00' }

            $anomaly = Test-TimeOfDayAnomaly -Event $event -WorkHours $workHours

            $anomaly.IsAnomaly | Should -BeTrue
            $anomaly.Reason | Should -Match 'outside.*hours'
        }
    }

    Describe 'Search and Filter' {
        BeforeAll {
            $script:sampleLogs = @(
                @{ Timestamp = '2026-01-04 12:00:00'; Severity = 3; Device = 'SW-01'; Message = 'Interface down' },
                @{ Timestamp = '2026-01-04 12:05:00'; Severity = 5; Device = 'SW-01'; Message = 'Config saved' },
                @{ Timestamp = '2026-01-04 12:10:00'; Severity = 3; Device = 'SW-02'; Message = 'Interface down' },
                @{ Timestamp = '2026-01-04 12:15:00'; Severity = 2; Device = 'CORE'; Message = 'Power warning' }
            )
        }

        It 'searches by keyword' {
            $results = Search-LogEntries -Entries $sampleLogs -Keyword 'Interface'

            $results.Count | Should -Be 2
        }

        It 'filters by severity' {
            $results = Search-LogEntries -Entries $sampleLogs -MaxSeverity 3

            $results.Count | Should -Be 3
            $results.Severity | Should -Not -Contain 5
        }

        It 'filters by device' {
            $results = Search-LogEntries -Entries $sampleLogs -Device 'SW-01'

            $results.Count | Should -Be 2
            $results.Device | ForEach-Object { $_ | Should -Be 'SW-01' }
        }

        It 'filters by time range' {
            $results = Search-LogEntries -Entries $sampleLogs `
                -StartTime '2026-01-04 12:00:00' `
                -EndTime '2026-01-04 12:07:00'

            $results.Count | Should -Be 2
        }

        It 'combines multiple filters' {
            $results = Search-LogEntries -Entries $sampleLogs `
                -Device 'SW-01' `
                -MaxSeverity 3

            $results.Count | Should -Be 1
        }

        It 'saves and loads search queries' {
            $query = @{
                Name = 'Critical Errors'
                Filters = @{ MaxSeverity = 3; Keyword = 'error' }
            }
            Save-LogSearch -Query $query

            $loaded = Get-LogSearch -Name 'Critical Errors'
            $loaded.Filters.MaxSeverity | Should -Be 3
        }
    }

    Describe 'Report Generation' {
        It 'generates pattern summary report' {
            $report = New-LogAnalysisReport -Entries $sampleLogs -Type 'PatternSummary'

            $report.TopPatterns | Should -Not -BeNullOrEmpty
            $report.TotalEntries | Should -BeGreaterThan 0
        }

        It 'generates trend comparison report' {
            $report = New-LogAnalysisReport `
                -CurrentPeriod $sampleLogs `
                -PreviousPeriod $sampleLogs `
                -Type 'TrendComparison'

            $report.Comparison | Should -Not -BeNullOrEmpty
        }

        It 'exports report to PDF' {
            $report = New-LogAnalysisReport -Entries $sampleLogs -Type 'Summary'
            $path = Export-LogReport -Report $report -Format PDF

            Test-Path $path | Should -BeTrue
        }
    }

    Describe 'Bulk Import' {
        It 'imports logs from file' {
            $tempFile = [System.IO.Path]::GetTempFileName()
            @'
*Mar  1 00:01:23: %LINK-3-UPDOWN: Interface Gi0/1, changed state to down
*Mar  1 00:01:24: %LINK-3-UPDOWN: Interface Gi0/1, changed state to up
'@ | Set-Content $tempFile

            $result = Import-LogFile -Path $tempFile -Format 'CiscoIOS'

            $result.ImportedCount | Should -Be 2
            $result.Errors.Count | Should -Be 0

            Remove-Item $tempFile
        }

        It 'handles parse errors gracefully' {
            $logs = @(
                '*Mar  1 00:01:23: %LINK-3-UPDOWN: Valid entry',
                'Invalid log format here',
                '*Mar  1 00:01:25: %LINK-3-UPDOWN: Another valid entry'
            )

            $result = Import-LogEntries -Entries $logs -Format 'CiscoIOS'

            $result.ImportedCount | Should -Be 2
            $result.Errors.Count | Should -Be 1
        }
    }
}
```

## UI Mockup Concepts

### Log Analysis Dashboard
```
+------------------------------------------------------------------+
| Log Analysis                                    [Import][Settings]|
+------------------------------------------------------------------+
| SUMMARY: 2,456 entries | Last 24 hours | 3 devices              |
+------------------------------------------------------------------+
| TOP PATTERNS DETECTED                | SEVERITY BREAKDOWN        |
| [!] Link Flapping (12 occurrences)   | Critical: 23             |
| [!] STP Topology Changes (5)         | Warning:  156            |
| [i] Config Changes (8)               | Notice:   1,892          |
| [i] Auth Failures (3)                | Info:     385            |
+------------------------------------------------------------------+
| TIMELINE                                                         |
|  ^                                                               |
|  |    *     **                                                   |
|  | *  ** *  ****   *                                            |
|  |****************************                                   |
|  +------------------------------------------------------------>  |
|  00:00     06:00     12:00     18:00     00:00                  |
+------------------------------------------------------------------+
| [View Patterns] [Search Logs] [Correlate Events] [Generate Report]|
+------------------------------------------------------------------+
```

### Pattern Detail View
```
+------------------------------------------------------------------+
| Pattern: Link Flapping                                [Dismiss]  |
+------------------------------------------------------------------+
| SEVERITY: Warning          OCCURRENCES: 12                       |
| AFFECTED: SW-01 (Gi0/1), SW-02 (Gi0/24), SW-03 (Gi1/0/15)       |
| TIMEFRAME: 2026-01-04 10:15 - 11:45                             |
+------------------------------------------------------------------+
| PATTERN TIMELINE:                                                |
| SW-01 Gi0/1:   |--up--|down|up|dn|up|dn|--up--|                 |
|                10:15              10:45      11:45               |
+------------------------------------------------------------------+
| PROBABLE CAUSES:                                                 |
| - Bad cable or connector (70% confidence)                        |
| - SFP/transceiver issue (20% confidence)                        |
| - Remote device issue (10% confidence)                          |
+------------------------------------------------------------------+
| RECOMMENDED ACTIONS:                                             |
| 1. Check physical cable at both ends                            |
| 2. Verify SFP is properly seated                                |
| 3. Review interface error counters                              |
| 4. Test with known-good cable                                   |
+------------------------------------------------------------------+
| [View All Events] [Create Incident] [Link to KB Article]         |
+------------------------------------------------------------------+
```

### Event Correlation View
```
+------------------------------------------------------------------+
| Event Cascade: Power Failure Impact                              |
+------------------------------------------------------------------+
| TRIGGER EVENT (Root Cause)                                       |
| [12:00:00] CORE-01: Power supply 1 failed                       |
|                |                                                 |
|                v                                                 |
| IMMEDIATE EFFECTS (+1 sec)                                       |
| [12:00:01] DS-01: Lost uplink to CORE-01                        |
| [12:00:01] DS-02: Lost uplink to CORE-01                        |
|                |                                                 |
|                v                                                 |
| CASCADED EFFECTS (+2 sec)                                        |
| [12:00:02] AS-01: Default gateway unreachable                   |
| [12:00:02] AS-02: Default gateway unreachable                   |
| [12:00:02] AS-03: STP root change detected                      |
+------------------------------------------------------------------+
| Impact Summary:                                                  |
| - 5 devices affected                                            |
| - 3 layer cascade                                               |
| - Estimated user impact: 150 endpoints                          |
+------------------------------------------------------------------+
```

## Automation hooks
- `Tools\Import-DeviceLogs.ps1 -Path logs.txt -Format CiscoIOS`
- `Tools\Find-LogPatterns.ps1 -Path logs.txt -OutputReport`
- `Tools\Get-EventCorrelation.ps1 -StartTime "12:00" -EndTime "13:00"`
- `Tools\Search-Logs.ps1 -Keyword "error" -Severity 3 -Device SW-01`
- `Tools\New-LogAnalysisReport.ps1 -Period LastWeek -Format PDF`
- `Tools\Compare-LogPeriods.ps1 -Before "2026-01-01" -After "2026-01-02"`

## Telemetry gates
- Log imports emit `LogImport` with count and format
- Pattern detection emits `PatternDetected` with pattern name and count
- Correlation analysis emits `EventCorrelation` with scope
- Report generation emits `LogReport` with type and period

## Dependencies
- Existing log ingestion infrastructure
- Pattern library definitions
- Report generation (Plan AA)
- Troubleshooting trees (Plan AB) for recommended actions

## References
- `docs/plans/PlanAB_TroubleshootingDecisionTrees.md` (Action recommendations)
- `docs/plans/PlanAA_DocumentationGenerator.md` (Report export)
- `docs/Troubleshooting/KnowledgeBase.yml` (KB article linking)
- `Tests/Fixtures/Routing/LogExplorer/` (Sample log formats)
