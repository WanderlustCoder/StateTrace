Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Log analysis and pattern detection module for network device logs.

.DESCRIPTION
    Provides log parsing for multiple formats (Cisco IOS, Arista EOS, syslog),
    pattern detection for common network issues, event correlation, and search
    functionality. Supports bulk import and analysis reporting.
#>

#region Log Parsing

<#
.SYNOPSIS
    Detects the log format from a sample entry.
#>
function Get-LogFormat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Sample
    )

    # Arista EOS format: Jan  4 12:34:56 hostname Process: %FACILITY-SEVERITY-MNEMONIC:
    # Check Arista FIRST because it has hostname after timestamp (more specific pattern)
    if ($Sample -match '^\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}\s+\S+\s+\w+:.*%\w+-\d-\w+') {
        return 'AristaEOS'
    }

    # Cisco IOS format: *Mar  1 00:01:23.456: %FACILITY-SEVERITY-MNEMONIC:
    if ($Sample -match '^\*?\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}.*%\w+-\d-\w+') {
        return 'CiscoIOS'
    }

    # RFC 5424 syslog: <priority>version timestamp hostname
    if ($Sample -match '^<\d+>\d?\s*\d{4}-\d{2}-\d{2}T') {
        return 'RFC5424'
    }

    # RFC 3164 syslog: <priority>timestamp hostname
    if ($Sample -match '^<\d+>\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}') {
        return 'RFC3164'
    }

    # Generic timestamp format
    if ($Sample -match '^\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}') {
        return 'Generic'
    }

    return 'Unknown'
}

<#
.SYNOPSIS
    Parses a single log entry.
#>
function ConvertFrom-LogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Entry,

        [ValidateSet('CiscoIOS', 'AristaEOS', 'RFC5424', 'RFC3164', 'Generic', 'Auto')]
        [string]$Format = 'Auto',

        [string]$DefaultHostname = ''
    )

    if ([string]::IsNullOrWhiteSpace($Entry)) {
        return $null
    }

    if ($Format -eq 'Auto') {
        $Format = Get-LogFormat -Sample $Entry
    }

    $parsed = [pscustomobject]@{
        RawEntry = $Entry
        Format = $Format
        Timestamp = $null
        TimestampString = ''
        Hostname = $DefaultHostname
        Process = ''
        Facility = ''
        Severity = 6  # Informational by default
        SeverityName = 'Informational'
        Mnemonic = ''
        MessageType = ''
        Message = ''
        ExtractedFields = @{}
    }

    switch ($Format) {
        'CiscoIOS' {
            # Pattern: *Mar  1 00:01:23.456: %LINK-3-UPDOWN: message
            if ($Entry -match '^\*?(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})(?:\.\d+)?:\s*%(\w+)-(\d)-(\w+):\s*(.*)$') {
                $parsed.TimestampString = $Matches[1]
                $parsed.Facility = $Matches[2]
                $parsed.Severity = [int]$Matches[3]
                $parsed.Mnemonic = $Matches[4]
                $parsed.MessageType = "$($Matches[2])-$($Matches[3])-$($Matches[4])"
                $parsed.Message = $Matches[5]

                # Try to parse timestamp (year is ambiguous in Cisco format)
                $currentYear = (Get-Date).Year
                try {
                    $parsed.Timestamp = [datetime]::ParseExact(
                        "$currentYear $($parsed.TimestampString)",
                        'yyyy MMM  d HH:mm:ss',
                        [System.Globalization.CultureInfo]::InvariantCulture
                    )
                } catch {
                    try {
                        $parsed.Timestamp = [datetime]::ParseExact(
                            "$currentYear $($parsed.TimestampString)",
                            'yyyy MMM d HH:mm:ss',
                            [System.Globalization.CultureInfo]::InvariantCulture
                        )
                    } catch { }
                }
            }
            # Simpler pattern without facility
            elseif ($Entry -match '^\*?(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})(?:\.\d+)?:\s*(.*)$') {
                $parsed.TimestampString = $Matches[1]
                $parsed.Message = $Matches[2]
            }
        }

        'AristaEOS' {
            # Pattern: Jan  4 12:34:56 hostname Process: %FACILITY-SEVERITY-MNEMONIC: message
            if ($Entry -match '^(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})\s+(\S+)\s+(\w+):\s*%(\w+)-(\d)-(\w+):\s*(.*)$') {
                $parsed.TimestampString = $Matches[1]
                $parsed.Hostname = $Matches[2]
                $parsed.Process = $Matches[3]
                $parsed.Facility = $Matches[4]
                $parsed.Severity = [int]$Matches[5]
                $parsed.Mnemonic = $Matches[6]
                $parsed.MessageType = "$($Matches[4])-$($Matches[5])-$($Matches[6])"
                $parsed.Message = $Matches[7]

                $currentYear = (Get-Date).Year
                try {
                    $parsed.Timestamp = [datetime]::ParseExact(
                        "$currentYear $($parsed.TimestampString)",
                        'yyyy MMM  d HH:mm:ss',
                        [System.Globalization.CultureInfo]::InvariantCulture
                    )
                } catch {
                    try {
                        $parsed.Timestamp = [datetime]::ParseExact(
                            "$currentYear $($parsed.TimestampString)",
                            'yyyy MMM d HH:mm:ss',
                            [System.Globalization.CultureInfo]::InvariantCulture
                        )
                    } catch { }
                }
            }
            # Without facility pattern
            elseif ($Entry -match '^(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})\s+(\S+)\s+(\w+):\s*(.*)$') {
                $parsed.TimestampString = $Matches[1]
                $parsed.Hostname = $Matches[2]
                $parsed.Process = $Matches[3]
                $parsed.Message = $Matches[4]
            }
        }

        'RFC5424' {
            # Pattern: <priority>version timestamp hostname app-name procid msgid structured-data msg
            if ($Entry -match '^<(\d+)>(\d?)\s*(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})?)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(.*)$') {
                $priority = [int]$Matches[1]
                $parsed.Facility = [math]::Floor($priority / 8)
                $parsed.Severity = $priority % 8
                $parsed.TimestampString = $Matches[3]
                $parsed.Hostname = $Matches[4]
                $parsed.Process = $Matches[5]
                $parsed.Message = $Matches[8]

                try {
                    $parsed.Timestamp = [datetime]::Parse($Matches[3])
                } catch { }
            }
        }

        'RFC3164' {
            # Pattern: <priority>timestamp hostname message
            if ($Entry -match '^<(\d+)>(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})\s+(\S+)\s+(.*)$') {
                $priority = [int]$Matches[1]
                $parsed.Facility = [math]::Floor($priority / 8)
                $parsed.Severity = $priority % 8
                $parsed.TimestampString = $Matches[2]
                $parsed.Hostname = $Matches[3]
                $parsed.Message = $Matches[4]

                $currentYear = (Get-Date).Year
                try {
                    $parsed.Timestamp = [datetime]::ParseExact(
                        "$currentYear $($Matches[2])",
                        'yyyy MMM  d HH:mm:ss',
                        [System.Globalization.CultureInfo]::InvariantCulture
                    )
                } catch { }
            }
        }

        'Generic' {
            # Pattern: 2026-01-04 12:34:56 message
            if ($Entry -match '^(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})\s+(.*)$') {
                $parsed.TimestampString = $Matches[1]
                $parsed.Message = $Matches[2]
                try {
                    $parsed.Timestamp = [datetime]::Parse($Matches[1])
                } catch { }
            }
        }

        default {
            $parsed.Message = $Entry
        }
    }

    # Set severity name
    $parsed.SeverityName = switch ($parsed.Severity) {
        0 { 'Emergency' }
        1 { 'Alert' }
        2 { 'Critical' }
        3 { 'Error' }
        4 { 'Warning' }
        5 { 'Notice' }
        6 { 'Informational' }
        7 { 'Debug' }
        default { 'Unknown' }
    }

    # Extract common fields from message
    $parsed.ExtractedFields = Get-ExtractedFields -Message $parsed.Message

    return $parsed
}

<#
.SYNOPSIS
    Extracts common fields from log messages.
#>
function Get-ExtractedFields {
    [CmdletBinding()]
    param(
        [string]$Message
    )

    $fields = @{}

    # Interface name extraction
    if ($Message -match '(?:Interface|interface|Int)\s+(\S+)') {
        $fields['Interface'] = $Matches[1] -replace '[,\.]$', ''
    }
    if ($Message -match '((?:Gigabit|Fast)?Ethernet\d+(?:/\d+)+|Gi\d+(?:/\d+)+|Fa\d+(?:/\d+)+|Te\d+(?:/\d+)+|Eth\d+(?:/\d+)*)') {
        $fields['Interface'] = $Matches[1]
    }

    # State changes
    if ($Message -match 'changed state to (\w+)') {
        $fields['NewState'] = $Matches[1]
    }
    if ($Message -match 'state to (up|down|administratively down)') {
        $fields['NewState'] = $Matches[1]
    }

    # IP addresses
    if ($Message -match '(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})') {
        $fields['IPAddress'] = $Matches[1]
    }

    # VLAN IDs
    if ($Message -match 'VLAN\s*(\d+)') {
        $fields['VLAN'] = [int]$Matches[1]
    }

    # MAC addresses
    if ($Message -match '([0-9A-Fa-f]{4}\.[0-9A-Fa-f]{4}\.[0-9A-Fa-f]{4}|[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2})') {
        $fields['MACAddress'] = $Matches[1]
    }

    return $fields
}

<#
.SYNOPSIS
    Imports log entries from a file.
#>
function Import-LogFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,

        [ValidateSet('CiscoIOS', 'AristaEOS', 'RFC5424', 'RFC3164', 'Generic', 'Auto')]
        [string]$Format = 'Auto',

        [string]$DefaultHostname = ''
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Log file not found: $Path"
    }

    $lines = Get-Content -LiteralPath $Path
    $result = Import-LogEntries -Entries $lines -Format $Format -DefaultHostname $DefaultHostname
    $result | Add-Member -NotePropertyName 'SourceFile' -NotePropertyValue $Path -Force

    return $result
}

<#
.SYNOPSIS
    Imports log entries from an array of strings.
#>
function Import-LogEntries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$Entries,

        [ValidateSet('CiscoIOS', 'AristaEOS', 'RFC5424', 'RFC3164', 'Generic', 'Auto')]
        [string]$Format = 'Auto',

        [string]$DefaultHostname = ''
    )

    $parsed = New-Object System.Collections.ArrayList
    $errors = New-Object System.Collections.ArrayList
    $detectedFormat = $null

    # Filter out empty entries first
    $validEntries = @($Entries | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    foreach ($entry in $validEntries) {

        try {
            $useFormat = $Format
            if ($Format -eq 'Auto' -and -not $detectedFormat) {
                $detectedFormat = Get-LogFormat -Sample $entry
                $useFormat = $detectedFormat
            } elseif ($Format -eq 'Auto') {
                $useFormat = $detectedFormat
            }

            $log = ConvertFrom-LogEntry -Entry $entry -Format $useFormat -DefaultHostname $DefaultHostname
            if ($log -and (-not [string]::IsNullOrWhiteSpace($log.Message))) {
                [void]$parsed.Add($log)
            } else {
                [void]$errors.Add([pscustomobject]@{
                    Entry = $entry
                    Error = 'Failed to parse entry'
                })
            }
        } catch {
            [void]$errors.Add([pscustomobject]@{
                Entry = $entry
                Error = $_.Exception.Message
            })
        }
    }

    return [pscustomobject]@{
        Entries = @($parsed)
        ImportedCount = $parsed.Count
        TotalLines = $Entries.Count
        Errors = @($errors)
        ErrorCount = $errors.Count
        DetectedFormat = if ($detectedFormat) { $detectedFormat } else { $Format }
        ImportDate = Get-Date
    }
}

#endregion

#region Pattern Detection

# Built-in pattern definitions
$script:BuiltInPatterns = @(
    @{
        Name = 'LinkFlapping'
        Description = 'Interface link state changes rapidly'
        Category = 'Layer1'
        Severity = 'Warning'
        Regex = '%LINK-\d-UPDOWN.*changed state to'
        MinOccurrences = 3
        TimeWindowSeconds = 300
        RecommendedAction = 'Check cable, SFP, and remote device'
    },
    @{
        Name = 'STPTopologyChange'
        Description = 'Spanning Tree topology change detected'
        Category = 'Layer2'
        Severity = 'Notice'
        Regex = '%SPANTREE.*TOPOTRAP|%STP.*TCN|Topology change'
        MinOccurrences = 1
        RecommendedAction = 'Review STP configuration and recent port changes'
    },
    @{
        Name = 'STPRootChange'
        Description = 'Spanning Tree root bridge changed'
        Category = 'Layer2'
        Severity = 'Warning'
        Regex = '%SPANTREE.*ROOTCHANGE|Root.*changed|new root'
        MinOccurrences = 1
        RecommendedAction = 'Verify intended root bridge and priorities'
    },
    @{
        Name = 'AuthenticationFailure'
        Description = 'Login or authentication failed'
        Category = 'Security'
        Severity = 'Warning'
        Regex = '%SEC.*LOGIN_FAILED|authentication failure|login failed|invalid password'
        MinOccurrences = 1
        RecommendedAction = 'Review access logs and verify credentials'
    },
    @{
        Name = 'PortSecurityViolation'
        Description = 'Port security violation detected'
        Category = 'Security'
        Severity = 'Error'
        Regex = '%PM.*ERR_DISABLE|%PORT_SECURITY.*VIOLATION|Security violation'
        MinOccurrences = 1
        RecommendedAction = 'Check device connected to port, clear violation if authorized'
    },
    @{
        Name = 'DuplexMismatch'
        Description = 'Speed or duplex mismatch detected'
        Category = 'Layer1'
        Severity = 'Warning'
        Regex = '%CDP.*DUPLEX_MISMATCH|%DUPLEX.*MISMATCH|duplex mismatch'
        MinOccurrences = 1
        RecommendedAction = 'Configure matching speed/duplex on both ends'
    },
    @{
        Name = 'PowerSupplyFailure'
        Description = 'Power supply issue detected'
        Category = 'Hardware'
        Severity = 'Critical'
        Regex = '%PLATFORM.*PS_FAIL|power supply.*fail|PS\d+.*down'
        MinOccurrences = 1
        RecommendedAction = 'Check power supply, replace if failed'
    },
    @{
        Name = 'HighCPU'
        Description = 'High CPU utilization detected'
        Category = 'Performance'
        Severity = 'Warning'
        Regex = 'CPU utilization.*\d{2,3}%|High CPU|%SYS.*CPUHOG'
        MinOccurrences = 1
        RecommendedAction = 'Identify high CPU process, review traffic patterns'
    },
    @{
        Name = 'MemoryLow'
        Description = 'Low memory condition detected'
        Category = 'Performance'
        Severity = 'Warning'
        Regex = '%SYS.*MALLOCFAIL|memory low|out of memory'
        MinOccurrences = 1
        RecommendedAction = 'Review memory usage, consider device upgrade'
    },
    @{
        Name = 'InterfaceErrors'
        Description = 'Interface error counters increasing'
        Category = 'Layer1'
        Severity = 'Warning'
        Regex = 'input errors|output errors|CRC|runts|giants|collisions'
        MinOccurrences = 1
        RecommendedAction = 'Check cable quality and interface statistics'
    },
    @{
        Name = 'ConfigurationChange'
        Description = 'Configuration was modified'
        Category = 'Change'
        Severity = 'Notice'
        Regex = '%SYS.*CONFIG_I|Configured from|config.*saved|startup-config'
        MinOccurrences = 1
        RecommendedAction = 'Verify change was authorized and documented'
    },
    @{
        Name = 'NeighborDown'
        Description = 'Routing neighbor or adjacency lost'
        Category = 'Layer3'
        Severity = 'Error'
        Regex = '%OSPF.*ADJCHG.*DOWN|%BGP.*ADJCHANGE.*Down|neighbor.*down|adjacency.*lost'
        MinOccurrences = 1
        RecommendedAction = 'Check connectivity to neighbor, review routing configuration'
    },
    @{
        Name = 'NeighborUp'
        Description = 'Routing neighbor or adjacency established'
        Category = 'Layer3'
        Severity = 'Notice'
        Regex = '%OSPF.*ADJCHG.*FULL|%BGP.*ADJCHANGE.*Up|neighbor.*established'
        MinOccurrences = 1
        RecommendedAction = 'Verify expected neighbor relationship'
    },
    @{
        Name = 'VLANCreated'
        Description = 'New VLAN created'
        Category = 'Change'
        Severity = 'Notice'
        Regex = 'VLAN.*created|new VLAN|added VLAN'
        MinOccurrences = 1
        RecommendedAction = 'Verify VLAN creation was planned'
    },
    @{
        Name = 'StackMemberChange'
        Description = 'Stack member added or removed'
        Category = 'Hardware'
        Severity = 'Warning'
        Regex = '%STACKMGR|stack.*member|switch.*added|switch.*removed'
        MinOccurrences = 1
        RecommendedAction = 'Verify stack status and member connectivity'
    }
)

<#
.SYNOPSIS
    Gets the list of built-in patterns.
#>
function Get-LogPattern {
    [CmdletBinding()]
    param(
        [string]$Name,
        [string]$Category,
        [switch]$List
    )

    $patterns = $script:BuiltInPatterns

    if ($List) {
        return @($patterns | ForEach-Object {
            [pscustomobject]@{
                Name = $_.Name
                Description = $_.Description
                Category = $_.Category
                Severity = $_.Severity
            }
        })
    }

    if ($Name) {
        $patterns = @($patterns | Where-Object { $_.Name -eq $Name })
    }

    if ($Category) {
        $patterns = @($patterns | Where-Object { $_.Category -eq $Category })
    }

    return @($patterns)
}

<#
.SYNOPSIS
    Finds pattern matches in log entries.
#>
function Find-LogPatterns {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$Entries,

        [array]$CustomPatterns,

        [string[]]$IncludePatterns,

        [string[]]$ExcludePatterns
    )

    $allPatterns = @($script:BuiltInPatterns)
    if ($CustomPatterns) {
        $allPatterns += $CustomPatterns
    }

    if ($IncludePatterns) {
        $allPatterns = @($allPatterns | Where-Object { $_.Name -in $IncludePatterns })
    }
    if ($ExcludePatterns) {
        $allPatterns = @($allPatterns | Where-Object { $_.Name -notin $ExcludePatterns })
    }

    $matchList = New-Object System.Collections.ArrayList

    foreach ($pattern in $allPatterns) {
        $patternMatches = New-Object System.Collections.ArrayList

        foreach ($entry in $Entries) {
            $message = if ($entry -is [string]) { $entry } elseif ($entry.PSObject.Properties['Message']) { $entry.Message } elseif ($entry.PSObject.Properties['RawEntry']) { $entry.RawEntry } else { "$entry" }

            if ($message -match $pattern.Regex) {
                [void]$patternMatches.Add($entry)
            }
        }

        if ($patternMatches.Count -gt 0) {
            $minOccur = if ($pattern.MinOccurrences) { $pattern.MinOccurrences } else { 1 }
            if ($patternMatches.Count -ge $minOccur) {
                $patternMatch = [pscustomobject]@{
                    PatternName = $pattern.Name
                    Description = $pattern.Description
                    Category = $pattern.Category
                    Severity = $pattern.Severity
                    MatchCount = $patternMatches.Count
                    MatchedEntries = @($patternMatches)
                    RecommendedAction = $pattern.RecommendedAction
                    FirstMatch = $patternMatches[0]
                    LastMatch = $patternMatches[$patternMatches.Count - 1]
                }

                # Extract interface if flapping
                if ($pattern.Name -eq 'LinkFlapping') {
                    $interfaces = @($patternMatches | ForEach-Object {
                        $ef = $_.PSObject.Properties['ExtractedFields']
                        if ($ef -and $ef.Value) {
                            $fields = $ef.Value
                            if ($fields -is [hashtable] -and $fields.ContainsKey('Interface')) {
                                $fields['Interface']
                            } elseif ($fields.PSObject.Properties['Interface']) {
                                $fields.Interface
                            }
                        }
                    } | Where-Object { $_ } | Select-Object -Unique)
                    $patternMatch | Add-Member -NotePropertyName 'Interfaces' -NotePropertyValue $interfaces -Force
                    $patternMatch | Add-Member -NotePropertyName 'TransitionCount' -NotePropertyValue $patternMatches.Count -Force
                }

                # Extract source IP for auth failures
                if ($pattern.Name -eq 'AuthenticationFailure') {
                    $ips = @($patternMatches | ForEach-Object {
                        $ef = $_.PSObject.Properties['ExtractedFields']
                        if ($ef -and $ef.Value) {
                            $fields = $ef.Value
                            if ($fields -is [hashtable] -and $fields.ContainsKey('IPAddress')) {
                                $fields['IPAddress']
                            } elseif ($fields.PSObject.Properties['IPAddress']) {
                                $fields.IPAddress
                            }
                        }
                    } | Where-Object { $_ } | Select-Object -Unique)
                    $patternMatch | Add-Member -NotePropertyName 'SourceIPs' -NotePropertyValue $ips -Force
                    $patternMatch | Add-Member -NotePropertyName 'FailureCount' -NotePropertyValue $patternMatches.Count -Force
                }

                [void]$matchList.Add($patternMatch)
            }
        }
    }

    return @($matchList)
}

<#
.SYNOPSIS
    Detects link flapping on specific interfaces.
#>
function Find-LinkFlapping {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$Entries,

        [int]$MinTransitions = 3,

        [int]$TimeWindowSeconds = 300
    )

    # Filter to link state changes
    $linkChanges = @($Entries | Where-Object {
        $msg = if ($_.Message) { $_.Message } else { "$_" }
        $msg -match 'UPDOWN|changed state to|link.*up|link.*down'
    })

    if ($linkChanges.Count -lt $MinTransitions) {
        return @()
    }

    # Group by interface
    $byInterface = @{}
    foreach ($entry in $linkChanges) {
        $interface = 'Unknown'
        if ($entry.PSObject.Properties['ExtractedFields'] -and $entry.ExtractedFields -and $entry.ExtractedFields.Interface) {
            $interface = $entry.ExtractedFields.Interface
        }
        if (-not $byInterface.ContainsKey($interface)) {
            $byInterface[$interface] = New-Object System.Collections.ArrayList
        }
        [void]$byInterface[$interface].Add($entry)
    }

    $results = New-Object System.Collections.ArrayList

    foreach ($interface in $byInterface.Keys) {
        $changes = $byInterface[$interface]
        if ($changes.Count -ge $MinTransitions) {
            [void]$results.Add([pscustomobject]@{
                PatternName = 'LinkFlapping'
                Interface = $interface
                TransitionCount = $changes.Count
                FirstOccurrence = $changes[0]
                LastOccurrence = $changes[$changes.Count - 1]
                Entries = @($changes)
                Severity = 'Warning'
                RecommendedAction = 'Check cable, SFP transceiver, and remote device'
            })
        }
    }

    return @($results)
}

#endregion

#region Event Correlation

<#
.SYNOPSIS
    Groups temporally related events.
#>
function Group-CorrelatedEvents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$Events,

        [int]$WindowSeconds = 60
    )

    if ($Events.Count -eq 0) { return @() }

    # Sort by timestamp
    $sorted = @($Events | Sort-Object {
        if ($_.Timestamp) { $_.Timestamp }
        elseif ($_.TimestampString) { $_.TimestampString }
        else { $_ }
    })

    $groups = New-Object System.Collections.ArrayList
    $currentGroup = New-Object System.Collections.ArrayList
    $groupStart = $null

    foreach ($event in $sorted) {
        $timestamp = $null
        if ($event.PSObject.Properties['Timestamp']) {
            $timestamp = $event.Timestamp
        }

        if ($null -eq $groupStart) {
            $groupStart = $timestamp
            [void]$currentGroup.Add($event)
        }
        elseif ($null -eq $timestamp) {
            [void]$currentGroup.Add($event)
        }
        elseif (($timestamp - $groupStart).TotalSeconds -le $WindowSeconds) {
            [void]$currentGroup.Add($event)
        }
        else {
            # Start new group
            if ($currentGroup.Count -gt 0) {
                [void]$groups.Add([pscustomobject]@{
                    StartTime = $groupStart
                    EndTime = $currentGroup[$currentGroup.Count - 1].Timestamp
                    Events = @($currentGroup)
                    EventCount = $currentGroup.Count
                    Devices = @($currentGroup | ForEach-Object { $_.Hostname } | Where-Object { $_ } | Select-Object -Unique)
                })
            }
            $currentGroup = New-Object System.Collections.ArrayList
            [void]$currentGroup.Add($event)
            $groupStart = $timestamp
        }
    }

    # Add final group
    if ($currentGroup.Count -gt 0) {
        [void]$groups.Add([pscustomobject]@{
            StartTime = $groupStart
            EndTime = if ($currentGroup[$currentGroup.Count - 1].Timestamp) { $currentGroup[$currentGroup.Count - 1].Timestamp } else { $groupStart }
            Events = @($currentGroup)
            EventCount = $currentGroup.Count
            Devices = @($currentGroup | ForEach-Object { $_.Hostname } | Where-Object { $_ } | Select-Object -Unique)
        })
    }

    return @($groups)
}

<#
.SYNOPSIS
    Finds event cascades (cause and effect chains).
#>
function Find-EventCascade {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$Events,

        [int]$CascadeWindowSeconds = 10
    )

    if ($Events.Count -lt 2) { return $null }

    # Sort by timestamp
    $sorted = @($Events | Sort-Object { $_.Timestamp })

    $trigger = $sorted[0]
    $affected = @($sorted | Select-Object -Skip 1)
    $affectedDevices = @($affected | ForEach-Object { $_.Hostname } | Where-Object { $_ } | Select-Object -Unique)

    return [pscustomobject]@{
        TriggerEvent = $trigger
        TriggerDevice = $trigger.Hostname
        TriggerTime = $trigger.Timestamp
        AffectedEvents = $affected
        AffectedDevices = $affectedDevices
        CascadeDepth = ($affectedDevices | Measure-Object).Count
        TotalEvents = $Events.Count
    }
}

#endregion

#region Search and Filter

<#
.SYNOPSIS
    Searches log entries with various filters.
#>
function Search-LogEntries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$Entries,

        [string]$Keyword,

        [string]$Device,

        [int]$MaxSeverity,

        [int]$MinSeverity,

        [string]$Facility,

        [string]$MessageType,

        [datetime]$StartTime,

        [datetime]$EndTime,

        [string]$Interface
    )

    $results = $Entries

    if ($Keyword) {
        $results = @($results | Where-Object {
            $msg = if ($_.Message) { $_.Message } elseif ($_.RawEntry) { $_.RawEntry } else { "$_" }
            $msg -match [regex]::Escape($Keyword)
        })
    }

    if ($Device) {
        $results = @($results | Where-Object { $_.Hostname -eq $Device })
    }

    if ($PSBoundParameters.ContainsKey('MaxSeverity')) {
        $results = @($results | Where-Object { $_.Severity -le $MaxSeverity })
    }

    if ($PSBoundParameters.ContainsKey('MinSeverity')) {
        $results = @($results | Where-Object { $_.Severity -ge $MinSeverity })
    }

    if ($Facility) {
        $results = @($results | Where-Object { $_.Facility -eq $Facility })
    }

    if ($MessageType) {
        $results = @($results | Where-Object { $_.MessageType -match $MessageType })
    }

    if ($StartTime) {
        $results = @($results | Where-Object { $_.Timestamp -and $_.Timestamp -ge $StartTime })
    }

    if ($EndTime) {
        $results = @($results | Where-Object { $_.Timestamp -and $_.Timestamp -le $EndTime })
    }

    if ($Interface) {
        $results = @($results | Where-Object {
            $hasMatch = $false
            if ($_.PSObject.Properties['ExtractedFields'] -and $_.ExtractedFields) {
                $ef = $_.ExtractedFields
                $ifVal = $null
                if ($ef -is [hashtable] -and $ef.ContainsKey('Interface')) {
                    $ifVal = $ef['Interface']
                } elseif ($ef.PSObject.Properties['Interface']) {
                    $ifVal = $ef.Interface
                }
                if ($ifVal -eq $Interface) {
                    $hasMatch = $true
                }
            }
            if (-not $hasMatch -and $_.PSObject.Properties['Message'] -and $_.Message -match [regex]::Escape($Interface)) {
                $hasMatch = $true
            }
            $hasMatch
        })
    }

    return @($results)
}

<#
.SYNOPSIS
    Gets severity statistics from log entries.
#>
function Get-LogSeverityStats {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$Entries
    )

    $stats = @{
        Emergency = 0
        Alert = 0
        Critical = 0
        Error = 0
        Warning = 0
        Notice = 0
        Informational = 0
        Debug = 0
    }

    foreach ($entry in $Entries) {
        $sevName = switch ($entry.Severity) {
            0 { 'Emergency' }
            1 { 'Alert' }
            2 { 'Critical' }
            3 { 'Error' }
            4 { 'Warning' }
            5 { 'Notice' }
            6 { 'Informational' }
            7 { 'Debug' }
            default { 'Informational' }
        }
        $stats[$sevName]++
    }

    return [pscustomobject]$stats
}

<#
.SYNOPSIS
    Gets a summary of log analysis.
#>
function Get-LogAnalysisSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$Entries,

        [array]$Patterns
    )

    $severityStats = Get-LogSeverityStats -Entries $Entries
    $devices = @($Entries | ForEach-Object { $_.Hostname } | Where-Object { $_ } | Select-Object -Unique)
    $facilities = @($Entries | ForEach-Object { $_.Facility } | Where-Object { $_ } | Select-Object -Unique)

    $timeRange = $null
    $entriesWithTime = @($Entries | Where-Object { $_.Timestamp })
    if ($entriesWithTime.Count -gt 0) {
        $sorted = @($entriesWithTime | Sort-Object { $_.Timestamp })
        $timeRange = [pscustomobject]@{
            Start = $sorted[0].Timestamp
            End = $sorted[$sorted.Count - 1].Timestamp
            Duration = ($sorted[$sorted.Count - 1].Timestamp - $sorted[0].Timestamp)
        }
    }

    return [pscustomobject]@{
        TotalEntries = $Entries.Count
        SeverityBreakdown = $severityStats
        DeviceCount = $devices.Count
        Devices = $devices
        Facilities = $facilities
        PatternsDetected = if ($Patterns) { $Patterns.Count } else { 0 }
        TopPatterns = if ($Patterns) { @($Patterns | Select-Object -First 5) } else { @() }
        TimeRange = $timeRange
        AnalyzedAt = Get-Date
    }
}

#endregion

#region Anomaly Detection

<#
.SYNOPSIS
    Detects unusual message frequency spikes.
#>
function Find-FrequencyAnomalies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$Entries,

        [int]$BaselinePeriodMinutes = 60,

        [int]$BucketMinutes = 5,

        [double]$ThresholdMultiplier = 3.0
    )

    if ($Entries.Count -eq 0) { return @() }

    # Get entries with timestamps
    $entriesWithTime = @($Entries | Where-Object { $_.Timestamp })
    if ($entriesWithTime.Count -eq 0) { return @() }

    # Sort by timestamp
    $sorted = @($entriesWithTime | Sort-Object { $_.Timestamp })

    # Calculate bucket counts
    $buckets = @{}
    foreach ($entry in $sorted) {
        $bucketKey = $entry.Timestamp.ToString('yyyy-MM-dd HH:') + ([math]::Floor($entry.Timestamp.Minute / $BucketMinutes) * $BucketMinutes).ToString('00')
        if (-not $buckets.ContainsKey($bucketKey)) {
            $buckets[$bucketKey] = [System.Collections.ArrayList]::new()
        }
        [void]$buckets[$bucketKey].Add($entry)
    }

    if ($buckets.Count -lt 2) { return @() }

    # Calculate average and std deviation
    $counts = @($buckets.Values | ForEach-Object { $_.Count })
    $avg = ($counts | Measure-Object -Average).Average
    $variance = ($counts | ForEach-Object { [math]::Pow($_ - $avg, 2) } | Measure-Object -Average).Average
    $stdDev = [math]::Sqrt($variance)
    $threshold = $avg + ($stdDev * $ThresholdMultiplier)

    # Find anomalies
    $anomalies = [System.Collections.ArrayList]::new()
    foreach ($bucket in $buckets.Keys) {
        $count = $buckets[$bucket].Count
        if ($count -gt $threshold -and $count -gt ($avg * 2)) {
            [void]$anomalies.Add([pscustomobject]@{
                Type = 'FrequencySpike'
                TimeBucket = $bucket
                MessageCount = $count
                BaselineAverage = [math]::Round($avg, 1)
                Threshold = [math]::Round($threshold, 1)
                Multiplier = [math]::Round($count / $avg, 1)
                SampleEntries = @($buckets[$bucket] | Select-Object -First 5)
                Severity = if ($count -gt ($avg * 5)) { 'Critical' } elseif ($count -gt ($avg * 3)) { 'Warning' } else { 'Notice' }
            })
        }
    }

    return @($anomalies)
}

<#
.SYNOPSIS
    Identifies message types not seen in baseline period.
#>
function Find-NewMessageTypes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$Baseline,

        [Parameter(Mandatory=$true)]
        [array]$Current
    )

    # Extract message types from baseline
    $baselineTypes = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($entry in $Baseline) {
        $msgType = $null
        if ($entry.PSObject.Properties['MessageType'] -and $entry.MessageType) {
            $msgType = $entry.MessageType
        } elseif ($entry.PSObject.Properties['Mnemonic'] -and $entry.Mnemonic) {
            $msgType = $entry.Mnemonic
        }
        if ($msgType) {
            [void]$baselineTypes.Add($msgType)
        }
    }

    # Find new types in current period
    $newTypes = [System.Collections.ArrayList]::new()
    $seenNew = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($entry in $Current) {
        $msgType = $null
        if ($entry.PSObject.Properties['MessageType'] -and $entry.MessageType) {
            $msgType = $entry.MessageType
        } elseif ($entry.PSObject.Properties['Mnemonic'] -and $entry.Mnemonic) {
            $msgType = $entry.Mnemonic
        }
        if ($msgType -and -not $baselineTypes.Contains($msgType) -and -not $seenNew.Contains($msgType)) {
            [void]$seenNew.Add($msgType)
            [void]$newTypes.Add($msgType)
        }
    }

    return @($newTypes)
}

<#
.SYNOPSIS
    Detects activity outside normal work hours.
#>
function Test-TimeOfDayAnomaly {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [pscustomobject]$Event,

        [hashtable]$WorkHours = @{ Start = '08:00'; End = '18:00' },

        [string[]]$WorkDays = @('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday')
    )

    $timestamp = $null
    if ($Event.PSObject.Properties['Timestamp'] -and $Event.Timestamp) {
        $timestamp = $Event.Timestamp
    } elseif ($Event.PSObject.Properties['TimestampString'] -and $Event.TimestampString) {
        try { $timestamp = [datetime]::Parse($Event.TimestampString) } catch { }
    }

    if (-not $timestamp) {
        return [pscustomobject]@{
            IsAnomaly = $false
            Reason = 'No timestamp available'
            Event = $Event
        }
    }

    $dayName = $timestamp.DayOfWeek.ToString()
    $timeOfDay = $timestamp.ToString('HH:mm')

    $startTime = $WorkHours.Start
    $endTime = $WorkHours.End

    $isWorkDay = $dayName -in $WorkDays
    $isWorkHours = $timeOfDay -ge $startTime -and $timeOfDay -le $endTime

    if (-not $isWorkDay) {
        return [pscustomobject]@{
            IsAnomaly = $true
            Reason = "Activity on $dayName (outside work days)"
            Timestamp = $timestamp
            DayOfWeek = $dayName
            TimeOfDay = $timeOfDay
            Event = $Event
            Severity = 'Warning'
        }
    }

    if (-not $isWorkHours) {
        return [pscustomobject]@{
            IsAnomaly = $true
            Reason = "Activity at $timeOfDay (outside work hours $startTime-$endTime)"
            Timestamp = $timestamp
            DayOfWeek = $dayName
            TimeOfDay = $timeOfDay
            Event = $Event
            Severity = 'Notice'
        }
    }

    return [pscustomobject]@{
        IsAnomaly = $false
        Reason = 'Within normal work hours'
        Timestamp = $timestamp
        DayOfWeek = $dayName
        TimeOfDay = $timeOfDay
        Event = $Event
    }
}

#endregion

#region Reports and Saved Searches

# Saved searches storage
$script:SavedSearches = @{}

<#
.SYNOPSIS
    Saves a log search query for later reuse.
#>
function Save-LogSearch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Query
    )

    $name = $Query.Name
    if (-not $name) {
        throw "Query must have a Name property"
    }

    $script:SavedSearches[$name] = $Query
    return $Query
}

<#
.SYNOPSIS
    Gets a saved log search query.
#>
function Get-LogSearch {
    [CmdletBinding()]
    param(
        [string]$Name,
        [switch]$List
    )

    if ($List) {
        return @($script:SavedSearches.Values)
    }

    if ($Name -and $script:SavedSearches.ContainsKey($Name)) {
        return $script:SavedSearches[$Name]
    }

    return $null
}

<#
.SYNOPSIS
    Generates a log analysis report.
#>
function New-LogAnalysisReport {
    [CmdletBinding()]
    param(
        [array]$Entries,

        [array]$CurrentPeriod,

        [array]$PreviousPeriod,

        [ValidateSet('PatternSummary', 'TrendComparison', 'Summary', 'Health')]
        [string]$Type = 'Summary',

        [string]$Title
    )

    $reportDate = Get-Date
    $report = [pscustomobject]@{
        ReportID = "RPT-$(Get-Date -Format 'yyyyMMddHHmmss')"
        Type = $Type
        Title = if ($Title) { $Title } else { "$Type Report" }
        GeneratedAt = $reportDate
        Data = $null
    }

    switch ($Type) {
        'Summary' {
            if (-not $Entries) { $Entries = @() }
            $patterns = @(Find-LogPatterns -Entries $Entries)
            $summary = Get-LogAnalysisSummary -Entries $Entries -Patterns $patterns

            $report.Data = [pscustomobject]@{
                TotalEntries = $summary.TotalEntries
                SeverityBreakdown = $summary.SeverityBreakdown
                DeviceCount = $summary.DeviceCount
                Devices = $summary.Devices
                PatternsDetected = $patterns.Count
                TopPatterns = @($patterns | Select-Object PatternName, MatchCount, Severity -First 10)
                TimeRange = $summary.TimeRange
            }
        }

        'PatternSummary' {
            if (-not $Entries) { $Entries = @() }
            $patterns = @(Find-LogPatterns -Entries $Entries)

            $byCategory = @($patterns | Group-Object -Property Category)
            $bySeverity = @($patterns | Group-Object -Property Severity)

            $report.Data = [pscustomobject]@{
                TotalEntries = $Entries.Count
                TotalPatterns = $patterns.Count
                TopPatterns = @($patterns | Sort-Object -Property MatchCount -Descending | Select-Object PatternName, MatchCount, Severity, Category -First 10)
                ByCategory = @($byCategory | ForEach-Object { [pscustomobject]@{ Category = $_.Name; Count = $_.Count } })
                BySeverity = @($bySeverity | ForEach-Object { [pscustomobject]@{ Severity = $_.Name; Count = $_.Count } })
                PatternDetails = @($patterns)
            }
        }

        'TrendComparison' {
            if (-not $CurrentPeriod) { $CurrentPeriod = @() }
            if (-not $PreviousPeriod) { $PreviousPeriod = @() }

            $currentPatterns = @(Find-LogPatterns -Entries $CurrentPeriod)
            $previousPatterns = @(Find-LogPatterns -Entries $PreviousPeriod)

            $currentSeverity = Get-LogSeverityStats -Entries $CurrentPeriod
            $previousSeverity = Get-LogSeverityStats -Entries $PreviousPeriod

            # Calculate changes
            $patternChanges = [System.Collections.ArrayList]::new()
            $allPatterns = [System.Collections.ArrayList]::new()
            foreach ($p in $currentPatterns) { [void]$allPatterns.Add($p) }
            foreach ($p in $previousPatterns) { [void]$allPatterns.Add($p) }
            $allPatternNames = @($allPatterns | ForEach-Object { $_.PatternName } | Select-Object -Unique)

            foreach ($name in $allPatternNames) {
                $curr = $currentPatterns | Where-Object { $_.PatternName -eq $name }
                $prev = $previousPatterns | Where-Object { $_.PatternName -eq $name }
                $currCount = if ($curr) { $curr.MatchCount } else { 0 }
                $prevCount = if ($prev) { $prev.MatchCount } else { 0 }
                $change = $currCount - $prevCount
                $pctChange = if ($prevCount -gt 0) { [math]::Round((($currCount - $prevCount) / $prevCount) * 100, 1) } else { if ($currCount -gt 0) { 100 } else { 0 } }

                [void]$patternChanges.Add([pscustomobject]@{
                    PatternName = $name
                    CurrentCount = $currCount
                    PreviousCount = $prevCount
                    Change = $change
                    PercentChange = $pctChange
                    Trend = if ($change -gt 0) { 'Increasing' } elseif ($change -lt 0) { 'Decreasing' } else { 'Stable' }
                })
            }

            $report.Data = [pscustomobject]@{
                CurrentPeriodEntries = $CurrentPeriod.Count
                PreviousPeriodEntries = $PreviousPeriod.Count
                EntryCountChange = $CurrentPeriod.Count - $PreviousPeriod.Count
                CurrentSeverity = $currentSeverity
                PreviousSeverity = $previousSeverity
                Comparison = @($patternChanges | Sort-Object -Property Change -Descending)
                NewPatterns = @($patternChanges | Where-Object { $_.PreviousCount -eq 0 -and $_.CurrentCount -gt 0 })
                ResolvedPatterns = @($patternChanges | Where-Object { $_.CurrentCount -eq 0 -and $_.PreviousCount -gt 0 })
            }
        }

        'Health' {
            if (-not $Entries) { $Entries = @() }
            $patterns = Find-LogPatterns -Entries $Entries
            $severity = Get-LogSeverityStats -Entries $Entries

            # Calculate health score (0-100)
            $criticalWeight = 10
            $errorWeight = 5
            $warningWeight = 2

            $deductions = ($severity.Critical * $criticalWeight) + ($severity.Error * $errorWeight) + ($severity.Warning * $warningWeight)
            $healthScore = [math]::Max(0, 100 - $deductions)

            $report.Data = [pscustomobject]@{
                HealthScore = $healthScore
                HealthStatus = if ($healthScore -ge 90) { 'Healthy' } elseif ($healthScore -ge 70) { 'Fair' } elseif ($healthScore -ge 50) { 'Degraded' } else { 'Critical' }
                TotalEntries = $Entries.Count
                CriticalCount = $severity.Critical
                ErrorCount = $severity.Error
                WarningCount = $severity.Warning
                TopIssues = @($patterns | Where-Object { $_.Severity -in @('Critical', 'Error', 'Warning') } | Select-Object -First 5)
                RecommendedActions = @($patterns | Where-Object { $_.RecommendedAction } | Select-Object PatternName, RecommendedAction -First 5)
            }
        }
    }

    return $report
}

<#
.SYNOPSIS
    Exports a log analysis report to file.
#>
function Export-LogReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [pscustomobject]$Report,

        [ValidateSet('HTML', 'JSON', 'PDF', 'Markdown')]
        [string]$Format = 'HTML',

        [string]$OutputPath
    )

    if (-not $OutputPath) {
        $ext = switch ($Format) {
            'HTML' { '.html' }
            'JSON' { '.json' }
            'PDF' { '.html' }  # PDF is print-ready HTML
            'Markdown' { '.md' }
        }
        $OutputPath = Join-Path $env:TEMP "LogReport_$($Report.ReportID)$ext"
    }

    switch ($Format) {
        'JSON' {
            $Report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
        }

        'Markdown' {
            $md = @()
            $md += "# $($Report.Title)"
            $md += ""
            $md += "**Generated:** $($Report.GeneratedAt)"
            $md += "**Report ID:** $($Report.ReportID)"
            $md += ""

            if ($Report.Data.PSObject.Properties['TotalEntries'] -and $Report.Data.TotalEntries) {
                $md += "## Summary"
                $md += "- **Total Entries:** $($Report.Data.TotalEntries)"
            }
            if ($Report.Data.PSObject.Properties['HealthScore'] -and $Report.Data.HealthScore) {
                $md += "- **Health Score:** $($Report.Data.HealthScore)/100 ($($Report.Data.HealthStatus))"
            }
            if ($Report.Data.TopPatterns) {
                $md += ""
                $md += "## Top Patterns"
                $md += "| Pattern | Count | Severity |"
                $md += "|---------|-------|----------|"
                foreach ($p in $Report.Data.TopPatterns) {
                    $md += "| $($p.PatternName) | $($p.MatchCount) | $($p.Severity) |"
                }
            }

            $md -join "`n" | Set-Content -LiteralPath $OutputPath -Encoding UTF8
        }

        { $_ -in @('HTML', 'PDF') } {
            $printStyles = if ($Format -eq 'PDF') {
                @"
<style>
@page { size: letter; margin: 1in; }
@media print {
    body { font-size: 10pt; }
    .no-print { display: none; }
}
</style>
"@
            } else { '' }

            $html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>$($Report.Title)</title>
<style>
body { font-family: Arial, sans-serif; margin: 20px; }
h1 { color: #333; border-bottom: 2px solid #007acc; padding-bottom: 10px; }
h2 { color: #007acc; margin-top: 20px; }
table { border-collapse: collapse; width: 100%; margin: 10px 0; }
th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
th { background-color: #007acc; color: white; }
tr:nth-child(even) { background-color: #f9f9f9; }
.score-healthy { color: green; font-weight: bold; }
.score-fair { color: orange; font-weight: bold; }
.score-degraded { color: darkorange; font-weight: bold; }
.score-critical { color: red; font-weight: bold; }
.meta { color: #666; font-size: 0.9em; }
</style>
$printStyles
</head>
<body>
<h1>$($Report.Title)</h1>
<p class="meta">Generated: $($Report.GeneratedAt) | Report ID: $($Report.ReportID)</p>
"@

            if ($Report.Data.PSObject.Properties['HealthScore'] -and $Report.Data.HealthScore) {
                $scoreClass = switch ($Report.Data.HealthStatus) {
                    'Healthy' { 'score-healthy' }
                    'Fair' { 'score-fair' }
                    'Degraded' { 'score-degraded' }
                    default { 'score-critical' }
                }
                $html += "<h2>Health Score</h2>"
                $html += "<p class=`"$scoreClass`">$($Report.Data.HealthScore)/100 - $($Report.Data.HealthStatus)</p>"
            }

            if ($Report.Data.PSObject.Properties['TotalEntries'] -and $Report.Data.TotalEntries) {
                $html += "<h2>Summary</h2>"
                $html += "<ul>"
                $html += "<li><strong>Total Entries:</strong> $($Report.Data.TotalEntries)</li>"
                if ($Report.Data.DeviceCount) {
                    $html += "<li><strong>Devices:</strong> $($Report.Data.DeviceCount)</li>"
                }
                if ($Report.Data.PatternsDetected) {
                    $html += "<li><strong>Patterns Detected:</strong> $($Report.Data.PatternsDetected)</li>"
                }
                $html += "</ul>"
            }

            if ($Report.Data.PSObject.Properties['TopPatterns'] -and $Report.Data.TopPatterns -and $Report.Data.TopPatterns.Count -gt 0) {
                $html += "<h2>Top Patterns</h2>"
                $html += "<table><tr><th>Pattern</th><th>Count</th><th>Severity</th></tr>"
                foreach ($p in $Report.Data.TopPatterns) {
                    $html += "<tr><td>$($p.PatternName)</td><td>$($p.MatchCount)</td><td>$($p.Severity)</td></tr>"
                }
                $html += "</table>"
            }

            if ($Report.Data.PSObject.Properties['Comparison'] -and $Report.Data.Comparison -and $Report.Data.Comparison.Count -gt 0) {
                $html += "<h2>Trend Comparison</h2>"
                $html += "<table><tr><th>Pattern</th><th>Current</th><th>Previous</th><th>Change</th><th>Trend</th></tr>"
                foreach ($c in $Report.Data.Comparison) {
                    $html += "<tr><td>$($c.PatternName)</td><td>$($c.CurrentCount)</td><td>$($c.PreviousCount)</td><td>$($c.Change)</td><td>$($c.Trend)</td></tr>"
                }
                $html += "</table>"
            }

            $html += "<hr><p class=`"meta`">Generated by StateTrace Log Analysis</p>"
            $html += "</body></html>"

            $html | Set-Content -LiteralPath $OutputPath -Encoding UTF8
        }
    }

    return $OutputPath
}

#endregion

#region Exports

Export-ModuleMember -Function @(
    # Parsing
    'Get-LogFormat',
    'ConvertFrom-LogEntry',
    'Get-ExtractedFields',
    'Import-LogFile',
    'Import-LogEntries',
    # Pattern Detection
    'Get-LogPattern',
    'Find-LogPatterns',
    'Find-LinkFlapping',
    # Correlation
    'Group-CorrelatedEvents',
    'Find-EventCascade',
    # Search
    'Search-LogEntries',
    'Get-LogSeverityStats',
    'Get-LogAnalysisSummary',
    # Anomaly Detection (ST-AE-005)
    'Find-FrequencyAnomalies',
    'Find-NewMessageTypes',
    'Test-TimeOfDayAnomaly',
    # Reports and Saved Searches (ST-AE-006)
    'Save-LogSearch',
    'Get-LogSearch',
    'New-LogAnalysisReport',
    'Export-LogReport'
)

#endregion
