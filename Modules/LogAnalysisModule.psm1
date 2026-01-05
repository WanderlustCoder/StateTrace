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
                        if ($_.PSObject.Properties['ExtractedFields'] -and $_.ExtractedFields -and $_.ExtractedFields.Interface) {
                            $_.ExtractedFields.Interface
                        }
                    } | Where-Object { $_ } | Select-Object -Unique)
                    $patternMatch | Add-Member -NotePropertyName 'Interfaces' -NotePropertyValue $interfaces -Force
                    $patternMatch | Add-Member -NotePropertyName 'TransitionCount' -NotePropertyValue $patternMatches.Count -Force
                }

                # Extract source IP for auth failures
                if ($pattern.Name -eq 'AuthenticationFailure') {
                    $ips = @($patternMatches | ForEach-Object {
                        if ($_.PSObject.Properties['ExtractedFields'] -and $_.ExtractedFields -and $_.ExtractedFields.IPAddress) {
                            $_.ExtractedFields.IPAddress
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
        $sorted = $entriesWithTime | Sort-Object { $_.Timestamp }
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
    'Get-LogAnalysisSummary'
)

#endregion
