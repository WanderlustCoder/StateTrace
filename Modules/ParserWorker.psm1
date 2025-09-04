function New-Directories {
    param ([string[]]$Paths)
    foreach ($path in $Paths) {
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path | Out-Null
        }
    }
}

#
# Split raw log files into per-host files.
#
# Given a directory containing raw .log or .txt files, this helper scans each
# file for device hostnames and associated prompt indices, then writes out
# separate log files per host into a specified extraction directory.  It
# accepts the input and output directories as parameters so it can be used
# independently of script‑level variables.  The logic is derived from
# NetworkReader.ps1, but refactored here to allow background processing in
# the ParserWorker module.  All diagnostic messages use Write‑Host for
# consistency with the original implementation.
function Split-RawLogs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$LogPath,
        [Parameter(Mandatory=$true)][string]$ExtractedPath
    )
    Write-Host "Split-RawLogs: scanning directory '$LogPath' for .log and .txt files..."
    # Gather all files in the log directory and classify by extension.  Report
    # which files will be included or skipped to aid debugging.  Normalize
    # extensions to lowercase for comparison.
    $allFiles = Get-ChildItem $LogPath -File
    foreach ($f in $allFiles) {
        $ext = $f.Extension.ToLowerInvariant()
        if ($ext -in '.log', '.txt') {
            Write-Host "Including file for processing: $($f.FullName)"
        } else {
            Write-Host "Skipping file due to unsupported extension '$($f.Extension)': $($f.FullName)"
        }
    }
    $rawFiles = $allFiles | Where-Object {
        $ext = $_.Extension.ToLowerInvariant()
        $ext -in '.log', '.txt'
    }
    Write-Host "Found $($rawFiles.Count) raw log file(s) to process."

    foreach ($file in $rawFiles) {
        Write-Host "\n--- Processing file: $($file.FullName) ---"
        Write-Host "Reading file: $($file.FullName)"
        $lines = Get-Content $file.FullName
        Write-Host "Loaded $($lines.Count) lines from '$($file.Name)'"
        # Use a typed List[object] to collect host markers efficiently. Avoid
        # repeatedly copying arrays when appending new markers (O(n^2)).
        $hostMarkers = New-Object 'System.Collections.Generic.List[object]'

        # Find hostnames in the file.  A hostname line looks like "hostname <name>".
        # For each hostname, search the file for the earliest prompt matching
        # either "SSH@<hostname>#" or "<hostname>#".  If no prompt is found,
        # default to index 0 so the entire file is extracted for that host.
        Write-Host "Searching for hostnames in '$($file.Name)'..."
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '(?i)^\s*hostname\s+(\S+)\s*$') {
                $hostname = $Matches[1]
                Write-Host "Detected hostname '$hostname' at line $i"
                $promptPatterns = @("SSH@${hostname}#", "${hostname}#")
                $foundPromptForHost = $false
                for ($j = 0; $j -lt $lines.Count; $j++) {
                    foreach ($pattern in $promptPatterns) {
                        $regex = "(?i)^\s*$([regex]::Escape($pattern))"
                        if ($lines[$j] -match $regex) {
                            Write-Host "    Found prompt '$pattern' at line $j"
                            [void]$hostMarkers.Add([PSCustomObject]@{
                                Hostname = $hostname
                                Index    = $j
                            })
                            $foundPromptForHost = $true
                            break
                        }
                    }
                    if ($foundPromptForHost) { break }
                }
                if (-not $foundPromptForHost) {
                    Write-Host "  No prompt found for hostname '$hostname', defaulting to start of file"
                    [void]$hostMarkers.Add([PSCustomObject]@{
                        Hostname = $hostname
                        Index    = 0
                    })
                }
            }
        }

        if ($hostMarkers.Count -eq 0) {
            Write-Warning "No host markers found in $($file.Name). Skipping this file."
            continue
        }

        # Sort markers by index.  Wrap in array syntax to preserve Count when
        # only one marker exists.  Report summary to aid debugging.
        # Convert sorted array back into a List[object] to maintain type consistency
        $hostMarkers = [System.Collections.Generic.List[object]]::new(($hostMarkers | Sort-Object Index))
        $markerStrings = $hostMarkers | ForEach-Object { "$($_.Hostname)@$($_.Index)" }
        $markerSummary = $markerStrings -join ', '
        Write-Host "Host markers for '$($file.Name)': $markerSummary"
        Write-Host "Total host markers found in '$($file.Name)': $($hostMarkers.Count)"

        if ($hostMarkers.Count -eq 1) {
            $singleHost = $hostMarkers[0].Hostname
            $safeSingleHost = $singleHost -replace '[\\/:*?"<>|]', '_'
            $outPathSingle = Join-Path $ExtractedPath "$safeSingleHost.log"
            Write-Host "Single-host file detected. Writing entire file for host '$safeSingleHost' to '$outPathSingle' (total $($lines.Count) lines)"
            $lines | Set-Content $outPathSingle
            if (Test-Path $outPathSingle) {
                Write-Host "Successfully wrote file: $outPathSingle"
            } else {
                Write-Warning "Failed to write file: $outPathSingle"
            }
            Write-Host "Finished processing single-host file '$($file.Name)'"
            continue
        }

        Write-Host "Multi-host file detected. Writing slices for each host."
        for ($k = 0; $k -lt $hostMarkers.Count; $k++) {
            $start = $hostMarkers[$k].Index
            $end   = if ($k -lt $hostMarkers.Count - 1) {
                $hostMarkers[$k + 1].Index - 1
            } else {
                $lines.Count - 1
            }
            $slice = $lines[$start..$end]
            $safeHost = $hostMarkers[$k].Hostname -replace '[\\/:*?"<>|]', '_'
            $outPath = Join-Path $ExtractedPath "$safeHost.log"
            Write-Host "  Preparing slice for host '$safeHost': lines $start..$end (total $($slice.Count))"
            Write-Host "  Writing to: $outPath"
            $slice | Set-Content $outPath
            if (Test-Path $outPath) {
                Write-Host "  Successfully wrote file: $outPath"
            } else {
                Write-Warning "  Failed to write file: $outPath"
            }
        }
        Write-Host "Finished processing multi-host file '$($file.Name)'"
    }
}

#
# Start parsing each extracted device log file in parallel.  Uses a runspace
# pool to limit concurrency.  Each runspace imports the necessary vendor
# modules and this ParserWorker module, then calls Invoke-DeviceLogParsing
# for the given file.  The caller can specify the maximum number of threads
# and optionally a database path.  ModulesPath and ArchiveRoot are passed
# through so that runspaces can locate vendor modules and archival
# directories consistently with the main thread.  This function mirrors
# Start-ParallelDeviceProcessing in NetworkReader.ps1 but accepts explicit
# parameters instead of relying on script‑level variables.
function Start-ParallelDeviceProcessing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string[]]$DeviceFiles,
        [int]$MaxThreads = 20,
        [string]$DatabasePath,
        [Parameter(Mandatory=$true)][string]$ModulesPath,
        [Parameter(Mandatory=$true)][string]$ArchiveRoot
    )
    # Create a runspace pool with a maximum thread count.  The minimum is
    # always 1; the maximum is user specified.  Using an InitialSessionState
    # allows import of modules in each runspace.  Pass $Host to ensure
    # host-specific variables (e.g. progress) are available.
    $sessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxThreads, $sessionState, $Host)
    $runspacePool.Open()
    # Use a typed List[object] to collect runspaces efficiently, avoiding
    # O(n^2) behaviour when appending items to arrays.
    $runspaces = New-Object 'System.Collections.Generic.List[object]'
    foreach ($file in $DeviceFiles) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $runspacePool
        # Build the script block to execute in each runspace.  Import the vendor
        # modules and the ParserWorker module itself.  If a database path
        # exists, import the DatabaseModule globally so its functions are
        # available for invoking SQL commands.  Then call Invoke-DeviceLogParsing.
        $ps.AddScript({
            param($filePath, $modulesPath, $archiveRoot, $dbPath)
            Import-Module (Join-Path $modulesPath 'AristaModule.psm1') -Force
            Import-Module (Join-Path $modulesPath 'CiscoModule.psm1') -Force
            Import-Module (Join-Path $modulesPath 'BrocadeModule.psm1') -Force
            Import-Module (Join-Path $modulesPath 'ParserWorker.psm1') -Force
            if ($dbPath -and (Test-Path (Join-Path $modulesPath 'DatabaseModule.psm1'))) {
                Import-Module (Join-Path $modulesPath 'DatabaseModule.psm1') -Force -Global
            }
            # Invoke the parser.  Pass ArchiveRoot and DatabasePath so that
            # Invoke-DeviceLogParsing can archive logs and write to the DB.
            Invoke-DeviceLogParsing -FilePath $filePath -ArchiveRoot $archiveRoot -DatabasePath $dbPath
        }).AddArgument($file).AddArgument($ModulesPath).AddArgument($ArchiveRoot).AddArgument($DatabasePath)
        [void]$runspaces.Add([PSCustomObject]@{
            Pipe = $ps
            AsyncResult = $ps.BeginInvoke()
        })
    }
    foreach ($r in $runspaces) {
        $r.Pipe.EndInvoke($r.AsyncResult)
        $r.Pipe.Dispose()
    }
    $runspacePool.Close()
    $runspacePool.Dispose()
}

#
# Clear all files from the extracted log directory.  This helper accepts
# an explicit path rather than relying on module-level variables so that
# callers can control where extracted files are located.  Removing the
# extracted files prevents stale data from persisting between runs.
function Clear-ExtractedLogs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ExtractedPath
    )
    Get-ChildItem $ExtractedPath -File | Remove-Item -Force -ErrorAction SilentlyContinue
}

#
# Entry point for full parsing from the GUI.  This function encapsulates
# the entire processing pipeline previously defined in NetworkReader.ps1.
# It computes project paths relative to the module location, creates
# necessary directories, splits raw logs, invokes per‑device parsing in
# parallel and finally cleans up temporary files.  An optional
# DatabasePath parameter allows callers to override the database path or
# rely on the StateTraceDb environment/global variables.  The caller
# should import this module before invoking the function.
function Invoke-StateTraceParsing {
    [CmdletBinding()]
    param(
        [string]$DatabasePath
    )
    # Determine project root based on the module's location.  $PSScriptRoot is
    # the Modules directory; its parent is the project root.
    $projectRoot = Join-Path $PSScriptRoot '..' | Resolve-Path | Select-Object -ExpandProperty Path
    $logPath      = Join-Path $projectRoot 'Logs'
    $extractedPath= Join-Path $logPath 'Extracted'
    $modulesPath  = Join-Path $projectRoot 'Modules'
    $archiveRoot  = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'SwitchArchives'
    # Ensure directories exist.
    New-Directories @($logPath, $extractedPath, $archiveRoot)
    # Split raw logs into per‑device logs.
    Split-RawLogs -LogPath $logPath -ExtractedPath $extractedPath
    # Gather the extracted device files.
    $deviceFiles = Get-ChildItem $extractedPath -File | Select-Object -ExpandProperty FullName
    if ($deviceFiles.Count -gt 0) {
        Write-Host "Extracted $($deviceFiles.Count) device log file(s) to process:" -ForegroundColor Yellow
        foreach ($dev in $deviceFiles) { Write-Host "  - $dev" -ForegroundColor Yellow }
    } else {
        Write-Warning "No device logs were extracted; the parser will not run."
    }
    # Determine thread count up to 8 for concurrency.
    $threadCount = [Math]::Min(8, [Environment]::ProcessorCount)
    # Determine database path precedence: explicit parameter, environment variable, then global.
    $dbPath = $null
    if ($PSBoundParameters.ContainsKey('DatabasePath') -and $DatabasePath) {
        $dbPath = $DatabasePath
    } elseif ($env:StateTraceDbPath -and $env:StateTraceDbPath -ne '') {
        $dbPath = $env:StateTraceDbPath
    } elseif ($global:StateTraceDb) {
        $dbPath = $global:StateTraceDb
    }
    # Process each device file using parallel runspaces.
    if ($deviceFiles.Count -gt 0) {
        Write-Host "Processing $($deviceFiles.Count) logs in parallel..." -ForegroundColor Yellow
        Start-ParallelDeviceProcessing -DeviceFiles $deviceFiles -MaxThreads $threadCount -DatabasePath $dbPath -ModulesPath $modulesPath -ArchiveRoot $archiveRoot
    }
    # Cleanup extracted logs.
    Clear-ExtractedLogs -ExtractedPath $extractedPath
    Write-Host "Processing complete." -ForegroundColor Yellow
}

# Extract structured details from an SNMP location string.  Cisco and Brocade devices
# allow arbitrary strings for the `snmp-server location` configuration; a common
# convention in this environment is to separate fields with underscores.  For
# example: `Bldg_244_Floor_1_Room_33_Row_1_Rack_1`.  This helper splits the
# string on underscores and inspects adjacent key/value pairs.  Keys are
# matched case-insensitively so `bldg`, `building` and `Bldg` are all accepted.
# Returns a hashtable containing the discovered values.  Unmatched keys are
# ignored.
function Get-LocationDetails {
    [CmdletBinding()] param(
        [string]$Location
    )
    # Default return structure with empty strings.  Additional keys can be
    # appended here if more metadata is introduced in the future.
    $details = @{
        Building = ''
        Floor    = ''
        Room     = ''
        Row      = ''
        Rack     = ''
    }
    if (-not [string]::IsNullOrWhiteSpace($Location)) {
        # Split on underscores to capture tokens.  Use `-split` to support any
        # whitespace surrounding underscores and remove empty elements.
        $tokens = $Location -split '_+' | Where-Object { $_ -ne '' }
        for ($i = 0; $i -lt $tokens.Count - 1; $i++) {
            $key = $tokens[$i].Trim()
            $value = $tokens[$i + 1].Trim()
            # Perform case-insensitive matching using inline regex option instead of
            # converting the key to lowercase.  The (?i) prefix in each pattern
            # instructs PowerShell's regex engine to ignore case, which avoids
            # allocating a new lowercase string for every token while preserving
            # the original semantics.
            switch -regex ($key) {
                '(?i)^(bldg|building)$' { $details['Building'] = $value; continue }
                '(?i)^floor$'          { $details['Floor']    = $value; continue }
                '(?i)^room$'           { $details['Room']     = $value; continue }
                '(?i)^row$'            { $details['Row']      = $value; continue }
                '(?i)^rack$'           { $details['Rack']     = $value; continue }
            }
        }
    }
    return $details
}

<# 
    Splits the raw log lines into discrete blocks keyed by the "show" command
    that generated them.  This helper scans the provided Lines array for
    device prompts followed by a show command (e.g. "hostname# show version")
    and collects all subsequent lines until the next prompt.  Commands are
    normalized to lowercase and returned as hashtable keys mapping to an
    array of output lines.  The prompt pattern is flexible enough to handle
    both "#" and ">" prompt terminators to support different device types.

    .PARAMETER Lines
        The raw log content as an array of strings.  Each element should be
        one line from the log file.

    .OUTPUTS
        A hashtable where each key is the normalized show command (e.g.
        "show interface status") and each value is an array of strings
        representing the lines of output for that command.
#>
function Get-ShowCommandBlocks {
    [CmdletBinding()]
    param(
        [string[]]$Lines
    )
    # Initialize tracking variables for the current command and buffer
    $blocks     = @{}
    $currentCmd = ''
    # Use a typed List[string] for the buffer to accumulate lines efficiently.
    $buffer     = New-Object 'System.Collections.Generic.List[string]'
    $recording  = $false

    foreach ($line in $Lines) {
        # Match a prompt followed by a show command.  Accept both '#' and '>'
        # as prompt terminators and capture the command text.
        if ($line -match '^[^\s]+[>#]\s*(?:do\s+)?(show\s+.+)$') {
            # If we were recording a previous command, save its buffer
            if ($recording -and $currentCmd) {
                $blocks[$currentCmd] = $buffer
            }
            # Set new current command, normalize to lowercase, reset buffer
            $currentCmd = $matches[1].Trim().ToLower()
            $buffer     = New-Object 'System.Collections.Generic.List[string]'
            $recording  = $true
            continue
        }
        # Detect the start of the next prompt which signals the end of the current block
        if ($recording -and $line -match '^[^\s]+[>#]') {
            $blocks[$currentCmd] = $buffer
            $currentCmd = ''
            $buffer     = New-Object 'System.Collections.Generic.List[string]'
            $recording  = $false
            continue
        }
        # Append lines to the current buffer if we are within a block
        if ($recording) {
            [void]$buffer.Add($line)
        }
    }
    # Flush the final block if still recording
    if ($recording -and $currentCmd) {
            $blocks[$currentCmd] = $buffer
    }
    return $blocks
}

# Determine the device vendor from the contents of a "show version" block.  Rather than
# scanning the entire log for vendor keywords, which can lead to false positives if
# other vendors are referenced in the configuration or comments, this helper examines
# only the local device's version information.  It accepts a hashtable of show
# command blocks as returned from Get-ShowCommandBlocks and searches the
# "show version" output for vendor-specific identifiers.  If a vendor
# cannot be determined, an empty string is returned.
function Get-DeviceMakeFromBlocks {
    [CmdletBinding()]
    param(
        [hashtable]$Blocks
    )
    if (-not $Blocks -or -not $Blocks.ContainsKey('show version')) { return '' }
    $verLines = $Blocks['show version']
    foreach ($ln in $verLines) {
        # Look for Arista identifiers first because other vendors may reference
        # "Cisco" in generic text (e.g. access lists).  Arista show version
        # typically begins with "Arista" followed by the model.  Perform a
        # case-insensitive match on "Arista".
        if ($ln -match '(?i)\bArista\b') { return 'Arista' }
        # Brocade FastIron/IronWare output often references "Brocade" or
        # "Stackable", and may include the phrase "Communications Systems".
        if ($ln -match '(?i)\bBrocade\b' -or $ln -match '(?i)\bStackable\b' -or $ln -match '(?i)\bIronWare\b') { return 'Brocade' }
        # Cisco IOS, NX-OS, and IOS-XE show version always reference "Cisco".
        if ($ln -match '(?i)\bCisco\b') { return 'Cisco' }
    }
    return ''
}

# Extract the SNMP location string from a log.  Different vendors
# present the location using slightly different keywords, such as
# ``snmp-server location ...``, ``SNMP location: ...`` or ``Location: ...``.
# This helper attempts to match any of these forms in a case-insensitive
# manner and returns the captured location text trimmed of whitespace.
# If no location is found, it returns 'Unspecified'.
function Get-SnmpLocationFromLines {
    [CmdletBinding()]
    param(
        [string[]]$Lines
    )
    foreach ($line in $Lines) {
        # Cisco/Brocade style: snmp-server location <value>
        if ($line -match '(?i)^\s*snmp-server\s+location\s+(.+)$') {
            return $matches[1].Trim()
        }
        # Arista style: SNMP location: <value>
        if ($line -match '(?i)^\s*snmp\s+location:\s*(.+)$') {
            return $matches[1].Trim()
        }
        # Generic fallback: Location: <value>
        if ($line -match '(?i)^\s*location:\s*(.+)$') {
            return $matches[1].Trim()
        }
    }
    return 'Unspecified'
}

<#
    Parse spanning-tree output into structured entries.  Both Cisco and Brocade
    devices report spanning-tree information in a similar format, with sections
    labelled by VLAN or MST instance (e.g. ``VLAN0001`` or ``MST0``) and
    subsequent lines indicating the root switch MAC address and the local port
    used to reach the root.  This helper accepts the raw lines from a
    ``show spanning-tree`` or ``show span`` command and emits a collection
    of PSCustomObjects with the following properties:

      * ``VLAN`` – the section identifier (``VLANxxxx`` or ``MSTx``)
      * ``RootSwitch`` – the MAC address of the spanning-tree root switch
      * ``RootPort`` – the interface on the local device that connects to the root
      * ``Role`` and ``Upstream`` – placeholders reserved for future use

    .PARAMETER SpanLines
        An array of strings containing the spanning-tree output lines.

    .OUTPUTS
        A collection of PSCustomObject entries summarising the spanning-tree
        topology for each VLAN or MST instance.
#>
function ConvertFrom-SpanningTree {
    [CmdletBinding()]
    param(
        [string[]]$SpanLines
    )
    # Use a typed List[object] to accumulate spanning tree entries to avoid
    # repeated array copies when appending objects.
    $entries = New-Object 'System.Collections.Generic.List[object]'
    $current    = ''
    $rootSwitch = ''
    $rootPort   = ''
    foreach ($ln in $SpanLines) {
        $line = $ln.Trim()
        # Identify a new section header.  Match VLANxxxx or MST<number> in a
        # case-insensitive manner.  When a new section starts, flush any
        # existing context into the results.
        if ($line -match '(?i)^(vlan\d+|mst\d+)') {
            if ($current -ne '') {
                [void]$entries.Add([PSCustomObject]@{
                    VLAN       = $current
                    RootSwitch = $rootSwitch
                    RootPort   = $rootPort
                    Role       = ''
                    Upstream   = ''
                })
            }
            $current    = $matches[1]
            $rootSwitch = ''
            $rootPort   = ''
            continue
        }
        # Capture the root switch MAC from a line containing "Address".
        if (-not $rootSwitch -and $line -match 'Address\s+(\S+)') {
            $rootSwitch = $matches[1]
            continue
        }
        # Capture the root port from a line like "Root port Fa0/1, cost 4".
        if (-not $rootPort -and $line -match 'Root\s+port\s+(\S+),') {
            $rootPort = $matches[1]
            continue
        }
    }
    # Flush the final entry if any context remains
    if ($current -ne '') {
        [void]$entries.Add([PSCustomObject]@{
            VLAN       = $current
            RootSwitch = $rootSwitch
            RootPort   = $rootPort
            Role       = ''
            Upstream   = ''
        })
    }
    return $entries
}
function Remove-OldArchiveFolder {
    param (
        [string]$DeviceArchivePath,
        [int]$RetentionDays = 30
    )
    if (-not (Test-Path $DeviceArchivePath)) { return }

    Get-ChildItem $DeviceArchivePath -Directory | Where-Object {
        $folderDate = $null
        try {
            $folderDate = [datetime]::ParseExact($_.Name, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
        } catch { return $false }
        return $folderDate -lt (Get-Date).AddDays(-$RetentionDays)
    } | ForEach-Object {
        try { Remove-Item $_.FullName -Recurse -Force }
        catch { Write-Warning "Failed to delete archive '$_': $($_.Exception.Message)" }
    }
}

# Extract global authentication configuration lines from Brocade logs.
#
# The Brocade FastIron configuration stores the authentication commands
# globally rather than per interface.  If the device parsing logic does
# not populate the AuthenticationBlock property, this helper will scan
# the raw log for common authentication directives and return them as
# an ordered array of strings.  Duplicate lines are suppressed.
function Get-BrocadeAuthBlockFromLines {
    [CmdletBinding()]
    param([string[]]$Lines)

    if (-not $Lines) { return @() }

    # Patterns to match the Brocade auth block.  Allow optional dashes
    # and whitespace between keywords for flexibility.  Capture both
    # global enable lines and per‑range commands.
    $patterns = @(
        '^\s*auth-?default-?vlan\s*\d+\s*$',
        '^\s*re-?authentication\s*$',
        '^\s*dot1x\s+enable(?:\s+ethe.+)?\s*$',
        '^\s*dot1x\s+port-?control\s+auto(?:\s+ethe.+)?\s*$',
        '^\s*mac-?authentication\s+enable(?:\s+ethe.+)?\s*$',
        '^\s*mac-?authentication\s+dot1x\s+override\s*$'
    )
    $regex = [string]::Join('|', $patterns)

    $found = New-Object System.Collections.Generic.List[string]
    foreach ($ln in $Lines) {
        if ($ln -match $regex) {
            # Normalize whitespace and remove extra spaces
            $norm = ($ln -replace '\s+', ' ').Trim()
            if (-not $found.Contains($norm)) { $found.Add($norm) }
        }
    }
    return ,$found.ToArray()
}

<#
    Saves device summary information to the database.  This helper performs
    an "upsert" on the DeviceSummary table by first executing an UPDATE
    statement (which will affect zero rows if the hostname does not exist)
    followed by an INSERT statement.  It then records the same summary
    information in the DeviceHistory table using the provided run date.

    .PARAMETER Connection
        An open ADO connection object configured for the target database.  The
        caller is responsible for beginning and committing the surrounding
        transaction.

    .PARAMETER Facts
        The parsed device facts object returned from the vendor parsing module.

    .PARAMETER Hostname
        The normalized hostname of the device.  This is used as the primary
        key and for lookup when performing the upsert.

    .PARAMETER SiteCode
        A short code representing the logical site (e.g. campus or facility).

    .PARAMETER LocationDetails
        A hashtable containing building, floor, room, row and rack values
        extracted from the SNMP location string.

    .PARAMETER RunDateString
        The current timestamp formatted as "yyyy-MM-dd HH:mm:ss".  A date
        literal will be constructed from this string when inserting into
        DeviceHistory.
#>
function Update-DeviceSummaryInDb {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Connection,
        [Parameter(Mandatory=$true)][object]$Facts,
        [Parameter(Mandatory=$true)][string]$Hostname,
        [Parameter(Mandatory=$true)][string]$SiteCode,
        [Parameter(Mandatory=$true)][hashtable]$LocationDetails,
        [Parameter(Mandatory=$true)][string]$RunDateString
    )
    # Escape single quotes for SQL literals.  PowerShell 5.1 does not support the
    # ternary operator, so use explicit if/else logic to safely retrieve
    # optional properties.  Assign raw values first, then escape quotes.
    $escHostname = $Hostname -replace "'", "''"
    # Make
    $rawMake = ''
    if ($Facts.PSObject.Properties.Name -contains 'Make' -and $Facts.Make) {
        $rawMake = $Facts.Make
    }
    $escMake = $rawMake -replace "'", "''"
    # Model
    $rawModel = ''
    if ($Facts.PSObject.Properties.Name -contains 'Model' -and $Facts.Model) {
        $rawModel = $Facts.Model
    }
    $escModel = $rawModel -replace "'", "''"
    # Uptime
    $rawUptime = ''
    if ($Facts.PSObject.Properties.Name -contains 'Uptime' -and $Facts.Uptime) {
        $rawUptime = $Facts.Uptime
    }
    $escUptime = $rawUptime -replace "'", "''"
    # Site code (always provided)
    $escSite = $SiteCode -replace "'", "''"
    # Building
    $rawBuilding = ''
    if ($LocationDetails.ContainsKey('Building') -and $LocationDetails.Building) {
        $rawBuilding = $LocationDetails.Building
    }
    $escBuilding = $rawBuilding -replace "'", "''"
    # Room
    $rawRoom = ''
    if ($LocationDetails.ContainsKey('Room') -and $LocationDetails.Room) {
        $rawRoom = $LocationDetails.Room
    }
    $escRoom = $rawRoom -replace "'", "''"
    # Determine number of interfaces if provided
    $portCount = 0
    if ($Facts.PSObject.Properties.Name -contains 'InterfaceCount') {
        $portCount = $Facts.InterfaceCount
    }
    # Extract the default authentication VLAN
    $rawAuthVlan = ''
    if ($Facts.PSObject.Properties.Name -contains 'AuthDefaultVLAN' -and $Facts.AuthDefaultVLAN) {
        $rawAuthVlan = $Facts.AuthDefaultVLAN
    }
    $escAuthVlan = $rawAuthVlan -replace "'", "''"
    # Compose the authentication block text
    $authBlockText = ''
    if ($Facts.PSObject.Properties.Name -contains 'AuthenticationBlock' -and $Facts.AuthenticationBlock) {
        $authBlockText = ($Facts.AuthenticationBlock -join "`r`n")
    }
    $escAuthBlock = $authBlockText -replace "'", "''"
    # Build update and insert statements.  The update will modify an existing
    # row if present; the insert will succeed for new devices and fail for
    # duplicates (ignored).
    $updateSql = "UPDATE DeviceSummary SET Make='$escMake', Model='$escModel', Uptime='$escUptime', Site='$escSite', Building='$escBuilding', Room='$escRoom', Ports=$portCount, AuthDefaultVLAN='$escAuthVlan', AuthBlock='$escAuthBlock' WHERE Hostname='$escHostname'"
    $insertSql = "INSERT INTO DeviceSummary (Hostname, Make, Model, Uptime, Site, Building, Room, Ports, AuthDefaultVLAN, AuthBlock) VALUES ('$escHostname', '$escMake', '$escModel', '$escUptime', '$escSite', '$escBuilding', '$escRoom', $portCount, '$escAuthVlan', '$escAuthBlock')"
    # Execute update and insert sequentially
    try {
        $Connection.Execute($updateSql) | Out-Null
    } catch {
        # ignore update errors
    }
    try {
        $Connection.Execute($insertSql) | Out-Null
    } catch {
        # duplicate key is expected on upsert; ignore
    }
    # Insert a row into DeviceHistory.  Use the run date literal enclosed
    # in # characters to satisfy Access date syntax.
    $runDateLiteral = "#$RunDateString#"
    $histSql = "INSERT INTO DeviceHistory (Hostname, RunDate, Make, Model, Uptime, Site, Building, Room, Ports, AuthDefaultVLAN, AuthBlock) VALUES ('$escHostname', $runDateLiteral, '$escMake', '$escModel', '$escUptime', '$escSite', '$escBuilding', '$escRoom', $portCount, '$escAuthVlan', '$escAuthBlock')"
    try {
        $Connection.Execute($histSql) | Out-Null
    } catch {
        Write-Warning "Failed to insert device history for host ${Hostname}: $($_.Exception.Message)"
    }
}

<#
    Saves all interface information for a device to the database.  This helper
    deletes existing interface rows for the given host, then inserts each
    interface into the Interfaces and InterfaceHistory tables.  It relies on
    the compliance templates provided to compute the PortColor and ConfigStatus
    fields.  The caller must commit the transaction after this function
    returns.

    .PARAMETER Connection
        An open ADO connection object configured for the target database.

    .PARAMETER Facts
        The parsed device facts object which contains either an
        InterfacesCombined or Interfaces property enumerating the
        interface records.

    .PARAMETER Hostname
        The normalized hostname used to delete existing rows.

    .PARAMETER RunDateString
        The current timestamp formatted as "yyyy-MM-dd HH:mm:ss".  Used to
        construct a date literal for the InterfaceHistory table.

    .PARAMETER Templates
        An optional array of compliance template objects loaded from the
        vendor-specific JSON.  If provided, the AuthTemplate value for
        each interface will be matched against template names and aliases
        to derive the PortColor and ConfigStatus fields.  When absent,
        defaults of Gray/Mismatch are used.
#>
function Update-InterfacesInDb {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Connection,
        [Parameter(Mandatory=$true)][object]$Facts,
        [Parameter(Mandatory=$true)][string]$Hostname,
        [Parameter(Mandatory=$true)][string]$RunDateString,
        [Parameter(Mandatory=$false)][object[]]$Templates
    )
    # Escape hostname once for reuse
    $escHostname = $Hostname -replace "'", "''"
    # Delete existing interface rows for this host using a retry loop to
    # avoid transient lock failures.  Try up to three times, waiting 200ms
    # between attempts.
    $delSql = "DELETE FROM Interfaces WHERE Hostname = '$escHostname'"
    $deleted = $false
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $Connection.Execute($delSql) | Out-Null
            $deleted = $true
            break
        } catch {
            if ($attempt -lt 3) {
                Start-Sleep -Milliseconds 200
            } else {
                Write-Warning "Failed to delete old interface rows for host ${Hostname}: $($_.Exception.Message)"
            }
        }
    }
    # Determine which interface collection to use
    $ifaceRecords = $null
    if ($Facts.PSObject.Properties.Name -contains 'InterfacesCombined') {
        $ifaceRecords = $Facts.InterfacesCombined
    } elseif ($Facts.PSObject.Properties.Name -contains 'Interfaces') {
        $ifaceRecords = $Facts.Interfaces
    }
    if (-not $ifaceRecords) { return }
    # Prepare run date literal for history table
    $runDateLiteral = "#$RunDateString#"
    foreach ($iface in $ifaceRecords) {
        # Extract scalar fields safely
        $port   = ($iface.PSObject.Properties['Port']   | ForEach-Object { $_.Value }) -join ''
        $name   = ($iface.PSObject.Properties['Name']   | ForEach-Object { $_.Value }) -join ''
        $status = ($iface.PSObject.Properties['Status'] | ForEach-Object { $_.Value }) -join ''
        $vlan   = ($iface.PSObject.Properties['VLAN']   | ForEach-Object { $_.Value }) -join ''
        $duplex = ($iface.PSObject.Properties['Duplex'] | ForEach-Object { $_.Value }) -join ''
        $speed  = ($iface.PSObject.Properties['Speed']  | ForEach-Object { $_.Value }) -join ''
        $type   = ($iface.PSObject.Properties['Type']   | ForEach-Object { $_.Value }) -join ''
        $learned = ''
        if ($iface.PSObject.Properties.Name -contains 'LearnedMACs') {
            $learned = $iface.LearnedMACs -join ','
        }
        $authState = ''
        if ($iface.PSObject.Properties.Name -contains 'AuthState') {
            $authState = $iface.AuthState
        }
        $authMode = ''
        if ($iface.PSObject.Properties.Name -contains 'AuthMode') {
            $authMode = $iface.AuthMode
        }
        $authClient = ''
        if ($iface.PSObject.Properties.Name -contains 'AuthClientMAC') {
            $authClient = $iface.AuthClientMAC
        }
        $authTemplate = ''
        if ($iface.PSObject.Properties.Name -contains 'AuthTemplate') {
            $authTemplate = $iface.AuthTemplate
        }
        $configText = ''
        if ($iface.PSObject.Properties.Name -contains 'Config') {
            $configText = $iface.Config
        }
        # If the config is empty and this is a Brocade device, substitute
        # the global authentication block so administrators can see required
        # auth commands.  Only do this when Facts.AuthenticationBlock exists.
        if (-not $configText -or ($configText -is [string] -and $configText.Trim() -eq '')) {
            if ($Facts -and $Facts.Make -eq 'Brocade') {
                if ($Facts.PSObject.Properties.Name -contains 'AuthenticationBlock' -and $Facts.AuthenticationBlock) {
                    $configText = "AUTH BLOCK (GLOBAL)`r`n" + ($Facts.AuthenticationBlock -join "`r`n")
                }
            }
        }
        # Compose a tooltip combining the template name and the raw config
        $toolTip = "AuthTemplate: $authTemplate"
        if ($configText) { $toolTip = "$toolTip`n`n$configText" }
        # Compute compliance fields based on templates
        $portColor    = 'Gray'
        $configStatus = 'Mismatch'
        if ($Templates) {
            foreach ($tpl in $Templates) {
                $nameMatch  = $false
                if ($tpl.name) {
                    if ($tpl.name -ieq $authTemplate) { $nameMatch = $true }
                }
                $aliasMatch = $false
                if (-not $nameMatch -and $tpl.aliases) {
                    foreach ($al in $tpl.aliases) {
                        if ($al -ieq $authTemplate) { $aliasMatch = $true; break }
                    }
                }
                if ($nameMatch -or $aliasMatch) {
                    $portColor    = $tpl.color
                    $configStatus = 'Match'
                    break
                }
            }
        }
        # Escape fields for SQL
        $escPort      = $port        -replace "'", "''"
        $escName      = $name        -replace "'", "''"
        $escStatus    = $status      -replace "'", "''"
        $escDuplex    = $duplex      -replace "'", "''"
        $escSpeed     = $speed       -replace "'", "''"
        $escType      = $type        -replace "'", "''"
        $escLearned   = $learned      -replace "'", "''"
        $escState     = $authState    -replace "'", "''"
        $escModeFld   = $authMode     -replace "'", "''"
        $escClient    = $authClient   -replace "'", "''"
        $escTemplate  = $authTemplate -replace "'", "''"
        $escConfig    = $configText   -replace "'", "''"
        $escColor     = $portColor    -replace "'", "''"
        $escCfgStat   = $configStatus -replace "'", "''"
        $escToolTip   = $toolTip      -replace "'", "''"
        # Convert VLAN to numeric when possible
        $vlanNumeric = 0
        [void][int]::TryParse($vlan, [ref]$vlanNumeric)
        # Build insert SQL for Interfaces and InterfaceHistory
        $ifaceSql = "INSERT INTO Interfaces (Hostname, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip) VALUES ('$escHostname', '$escPort', '$escName', '$escStatus', $vlanNumeric, '$escDuplex', '$escSpeed', '$escType', '$escLearned', '$escState', '$escModeFld', '$escClient', '$escTemplate', '$escConfig', '$escColor', '$escCfgStat', '$escToolTip')"
        try {
            $Connection.Execute($ifaceSql) | Out-Null
        } catch {
            Write-Warning "Failed to insert interface record for host ${Hostname} port ${port}: $($_.Exception.Message)"
        }
        $histIfaceSql = "INSERT INTO InterfaceHistory (Hostname, RunDate, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip) VALUES ('$escHostname', $runDateLiteral, '$escPort', '$escName', '$escStatus', $vlanNumeric, '$escDuplex', '$escSpeed', '$escType', '$escLearned', '$escState', '$escModeFld', '$escClient', '$escTemplate', '$escConfig', '$escColor', '$escCfgStat', '$escToolTip')"
        try {
            $Connection.Execute($histIfaceSql) | Out-Null
        } catch {
            Write-Warning "Failed to insert interface history for host ${Hostname} port ${port}: $($_.Exception.Message)"
        }
    }
}

function Invoke-DeviceLogParsing {
    param (
        [string]$FilePath,
        [string]$ArchiveRoot,
        [string]$DatabasePath
    )

    Write-Host "[DEBUG] Parsing file '$FilePath'" -ForegroundColor Yellow
    $lines = Get-Content $FilePath
    # Partition the log into show command blocks once.  These blocks are used
    # both for vendor detection and to avoid redundant scanning within the
    # vendor parsing modules.  If no blocks are returned, default to an empty
    # hashtable.
    $blocks = Get-ShowCommandBlocks -Lines $lines
    if (-not $blocks) { $blocks = @{} }

    # Determine the vendor (device make) using only the "show version" output.
    $make = Get-DeviceMakeFromBlocks -Blocks $blocks
    if (-not $make) {
        # Fallback heuristic: scan the entire log for vendor keywords in a
        # preferential order.  Arista and Brocade are checked before Cisco
        # to reduce the chance of misclassification due to references to
        # remote devices.  If no vendor is found, emit a warning and abort.
        if ($lines -match "Arista") { $make = "Arista" }
        elseif ($lines -match "Brocade" -or $lines -match "IronWare" -or $lines -match "Stackable") { $make = "Brocade" }
        elseif ($lines -match "Cisco") { $make = "Cisco" }
        else {
            Write-Warning "Unknown vendor for file $FilePath"
            return
        }
    }

    try {
        switch ($make) {
            "Cisco" {
                # Supply the precomputed command blocks to avoid recomputing
                $facts = Get-CiscoDeviceFacts -Lines $lines -Blocks $blocks
            }
            "Brocade" {
                $facts = Get-BrocadeDeviceFacts -Lines $lines -Blocks $blocks
            }
            "Arista" {
                $facts = Get-AristaDeviceFacts -Lines $lines -Blocks $blocks
            }
        }
    } catch {
        Write-Warning "Failed to parse $make log '${FilePath}': $($_.Exception.Message)"
        return
    }

    #
    # Brocade fallback: if the vendor parser did not populate the AuthenticationBlock
    # or AuthDefaultVLAN properties, derive them directly from the raw configuration.
    # Also, later when inserting interface rows, the global auth block will be used
    # when per-port configuration is empty.  Only execute this logic for Brocade.
    if ($make -eq 'Brocade') {
        # Determine whether the AuthenticationBlock property is missing or empty
        $needBlock = $true
        if ($facts -and ($facts.PSObject.Properties.Name -contains 'AuthenticationBlock')) {
            $needBlock = -not $facts.AuthenticationBlock -or $facts.AuthenticationBlock.Count -eq 0
        }
        if ($needBlock) {
            $brocadeBlock = Get-BrocadeAuthBlockFromLines -Lines $lines
            if ($brocadeBlock -and $brocadeBlock.Count -gt 0) {
                if ($facts.PSObject.Properties.Name -contains 'AuthenticationBlock') {
                    $facts.AuthenticationBlock = $brocadeBlock
                } else {
                    Add-Member -InputObject $facts -NotePropertyName AuthenticationBlock -NotePropertyValue $brocadeBlock -Force
                }
            }
        }
        # Populate AuthDefaultVLAN if missing
        $needVlan = $true
        if ($facts -and ($facts.PSObject.Properties.Name -contains 'AuthDefaultVLAN')) {
            $val = $facts.AuthDefaultVLAN
            # Some parsers may set an empty string or zero; treat these as missing
            if ($val -and ($val -ne '')) { $needVlan = $false }
        }
    if ($needVlan) {
        $authLine = $lines | Where-Object { $_ -match 'auth-?default-?vlan\s*(\d+)' } | Select-Object -First 1
        if ($authLine) {
            $match = [regex]::Match($authLine, '\d+')
            if ($match.Success) {
                $v = $match.Value
                if ($facts.PSObject.Properties.Name -contains 'AuthDefaultVLAN') {
                    $facts.AuthDefaultVLAN = $v
                } else {
                    Add-Member -InputObject $facts -NotePropertyName AuthDefaultVLAN -NotePropertyValue $v -Force
                }
            }
        }
    }

    # At this point we have extracted all necessary information from the raw log
    # lines and show command blocks.  Free these large arrays to release memory
    # back to the garbage collector.  Without explicitly nulling these
    # references, they may persist on the heap until the end of the function
    # scope which can significantly increase memory usage when processing many
    # devices.  See the Phase 1 performance audit recommendations.
    $lines = $null
    $blocks = $null
    try {
        [System.GC]::Collect()
    } catch {
        # Ignore GC exceptions; not all hosts permit explicit collection
    }
    }

    if (-not $facts -or -not $facts.Hostname) {
        Write-Warning "No valid facts returned for $FilePath"
        return
    }

    $hostname     = $facts.Hostname -replace '[\\\/:\*\?"<>\|]', '_'
    $today        = Get-Date -Format "yyyy-MM-dd"
    $devicePath   = Join-Path $ArchiveRoot $hostname
    $archivePath  = Join-Path $devicePath $today
    $timestamp    = (Get-Date).ToUniversalTime().ToString("HHmm") + "Z"

    New-Directories @($devicePath, $archivePath)

    if ($facts.PSObject.Properties.Name -contains "InterfacesCombined") {
        # CSV export disabled – historical data is now stored in the database
    } else {
        # CSV export disabled – historical data is now stored in the database
    }

    # Export spanning tree information if available.  The facts may contain
    # a property named SpanInfo which is a collection of records.  Create
    # a *_Span.csv file in both the parsed and archive directories.  Skip
    # export if the property does not exist or is empty.
    if ($facts.PSObject.Properties.Name -contains 'SpanInfo') {
        $spanData = $facts.SpanInfo
        if ($spanData -and $spanData.Count -gt 0) {
            # Span CSV export disabled – historical data is now stored in the database only
        }
    }

    # Derive additional metadata about the device.  The site is defined as the
    # first four characters of the hostname (when available).  Location
    # information (building, floor, room, etc.) is encoded in the
    # `snmp-server location` string and parsed via the helper above.  These
    # values will be persisted to the summary so the GUI can filter devices.
    # Clean the hostname to remove any SSH@ prefix that may have been
    # inadvertently captured from prompts.  The raw facts.Hostname comes from
    # the device's configuration and may include such prefixes.
    $cleanHostname = $facts.Hostname
    if ($cleanHostname) {
        # Remove any SSH@ prefix and trim leading/trailing whitespace or control characters.
        $cleanHostname = $cleanHostname -replace '^SSH@',''
        $cleanHostname = $cleanHostname.Trim()
    }
    $siteCode = ''
    if ($cleanHostname -and $cleanHostname.Length -ge 4) {
        $siteCode = $cleanHostname.Substring(0,4)
    } elseif ($cleanHostname) {
        # For very short hostnames just use the full name as a site code
        $siteCode = $cleanHostname
    }
    $locDetails = Get-LocationDetails -Location $facts.Location

    $summaryObj = [PSCustomObject]@{
        Hostname         = $cleanHostname
        Make             = $facts.Make
        Model            = $facts.Model
        Version          = $facts.Version
        Uptime           = $facts.Uptime
        Location         = $facts.Location
        Site             = $siteCode
        Building         = $locDetails.Building
        Floor            = $locDetails.Floor
        Room             = $locDetails.Room
        Row              = $locDetails.Row
        Rack             = $locDetails.Rack
        InterfaceCount   = $facts.InterfaceCount
        AuthDefaultVLAN  = $facts.AuthDefaultVLAN
        AuthBlock        = if ($facts.AuthenticationBlock) { $facts.AuthenticationBlock -join "`n" } else { "" }
    }

    # Summary CSV export disabled – historical data is now stored in the database

    # If a database path was supplied, insert the summary and interface data
    # into the Access database.  Use Invoke-DbNonQuery from DatabaseModule
    # for efficient, parameterized execution.  Escape single quotes in
    # values to prevent SQL injection and syntax errors.  Many fields may
    # contain apostrophes (e.g., model names); doubling the quote is the
    # accepted way to escape it in SQL.
    if ($DatabasePath) {
        Write-Host "[DEBUG] Writing results for host '$cleanHostname' to database at '$DatabasePath'" -ForegroundColor Yellow
        try {
            # Capture the current run time for historical records.  Format it
            # as a standard timestamp string.  The helper functions will
            # convert this to an Access date literal as needed.
            $runDateString = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            # The summary and interface SQL statements will be constructed by helper functions.  No per‑field escaping is required here.

            #-------------------------------------------------------------------------
            # Prepare configuration compliance template lookup.  Determine vendor
            # based on the device make.  Cisco and Brocade are supported; unknown
            # vendors will fall back to Cisco.json.  Load the templates only once
            # per device to avoid redundant file reads.  Each template object
            # contains a name, optional aliases and a color property.  Matching
            # is case-insensitive against both the template name and aliases.
            $templates = $null
            try {
                $vendor = 'Cisco'
                if ($facts.Make) {
                    # Match known vendors in a case-insensitive manner without
                    # converting the entire Make string to lowercase.  The (?i)
                    # inline option performs a case-insensitive regex match.
                    if ($facts.Make -match '(?i)brocade') { $vendor = 'Brocade' }
                    elseif ($facts.Make -match '(?i)arista') { $vendor = 'Brocade' }
                }
                $tplDir = Join-Path $PSScriptRoot '..\Templates'
                $jsonFile = Join-Path $tplDir "$vendor.json"
                if (Test-Path $jsonFile) {
                    $json = Get-Content -Path $jsonFile -Raw | ConvertFrom-Json
                    if ($json.templates) { $templates = $json.templates }
                }
            } catch {
                # Ignore template load errors; compliance info will remain default
            }

            #---------------------------------------------------------------------
            # To prevent Access database locks when multiple runspaces write
            # concurrently, acquire a named mutex around all write operations.
            # Only one runspace will hold the mutex at a time, ensuring that
            # the file is updated sequentially and avoiding "Could not update;
            # currently locked" errors.  Use a short, friendly mutex name.
            $mutexName = 'StateTraceDbWriteMutex'
            $dbMutex = New-Object System.Threading.Mutex($false, $mutexName)
            try {
                Write-Host "[DEBUG] Waiting to acquire DB write mutex for host '$cleanHostname'" -ForegroundColor Yellow
                # Wait until we can acquire the mutex.  This call blocks until
                # no other runspace is currently writing to the database.
                $null = $dbMutex.WaitOne()
                Write-Host "[DEBUG] Acquired DB write mutex for host '$cleanHostname'" -ForegroundColor Yellow

                # Establish a single connection to the database for all statements.
                # Opening and closing a new connection for each SQL statement is
                # extremely expensive with the Access OLEDB provider.  Using a
                # persistent connection reduces overhead and significantly improves
                # performance when inserting hundreds of interface rows.
                $__dbProvider = $null
                Write-Host "[DEBUG] Detecting available OLEDB provider for database" -ForegroundColor Yellow
                # Prefer the ACE provider when available; fall back to Jet for .mdb files.
                foreach ($provCandidate in @('Microsoft.ACE.OLEDB.12.0','Microsoft.Jet.OLEDB.4.0')) {
                    try {
                        $testConn = New-Object -ComObject ADODB.Connection
                        $testConn.Open("Provider=$provCandidate;Data Source=$DatabasePath")
                        $testConn.Close()
                        $__dbProvider = $provCandidate
                        break
                    } catch { }
                }
                if (-not $__dbProvider) {
                    throw "No suitable OLEDB provider found to open Access database. Install the Microsoft ACE OLEDB provider."
                }
                $__dbConn = New-Object -ComObject ADODB.Connection
                Write-Host "[DEBUG] Opening DB connection to '$DatabasePath' using provider '$__dbProvider'" -ForegroundColor Yellow
                # Configure the connection for read/write access and row‑level locking.
                # Mode=ReadWrite ensures that both reads and writes are allowed.  Jet
                # supports page‑ and row‑level locking; specifying
                # Jet OLEDB:Database Locking Mode=1 requests row‑level locking to
                # minimize contention.  If the property is unsupported, the
                # provider silently ignores it.
                $__dbConn.Open("Provider=$__dbProvider;Data Source=$DatabasePath;Mode=ReadWrite;Jet OLEDB:Database Locking Mode=1")
                # When using the Jet OLEDB provider, we can request synchronous
                # transaction commits via the Jet OLEDB:Transaction Commit Mode
                # property.  The ACE provider does not support this property
                # and will throw if included in the connection string.  Set
                # the property programmatically and catch any exception for
                # unsupported providers.
                try {
                    $prop = $__dbConn.Properties.Item('Jet OLEDB:Transaction Commit Mode')
                    if ($prop) { $prop.Value = 1 }
                } catch { }
                # Use an explicit transaction to batch all SQL statements.  Jet/ACE
                # supports transactions through BeginTrans/CommitTrans.  A single
                # transaction improves performance dramatically when inserting
                # many rows and ensures that all operations either succeed or
                # rollback together in case of failure.
                $__dbConn.BeginTrans()
                try {
                    #------------------------------------------------------------------
                    # In the initial implementation we updated/inserted the summary
                    # row prior to deleting old interface records.  However, Jet/ACE
                    # can hold locks on rows that have been updated but not yet
                    # committed.  Because the Interfaces table has a foreign key
                    # referencing DeviceSummary.Hostname, attempting to delete
                    # interface rows after updating the summary can fail with
                    # "could not update; currently locked".  To avoid this, perform
                    # the interface deletion first, then upsert the summary, and
                    # finally insert new interface rows.  All operations are
                    # encapsulated within a single transaction so that the
                    # database remains consistent on success or failure.

                    # Persist the parsed data using centralized helpers.  These
                    # functions handle upserting the device summary and inserting
                    # all interface rows and their history.  The transaction
                    # remains open and will be committed below.
                    Update-DeviceSummaryInDb -Connection $__dbConn -Facts $facts -Hostname $cleanHostname -SiteCode $siteCode -LocationDetails $locDetails -RunDateString $runDateString
                    Update-InterfacesInDb    -Connection $__dbConn -Facts $facts -Hostname $cleanHostname -RunDateString $runDateString -Templates $templates
                    # Commit the transaction after all operations have executed.
                    try {
                        Write-Host "[DEBUG] Committing transaction for host '$cleanHostname'" -ForegroundColor Yellow
                        $__dbConn.CommitTrans()
                        try {
                            $jet = New-Object -ComObject JRO.JetEngine
                            $jet.RefreshCache($__dbConn)
                            Write-Host "[DEBUG] Refreshed Jet cache after commit for host '$cleanHostname'" -ForegroundColor Yellow
                        } catch {}
                    } catch {
                        Write-Host "[DEBUG] Commit failed for host '$cleanHostname', rolling back" -ForegroundColor Yellow
                        try { $__dbConn.RollbackTrans() } catch {}
                        throw
                    }
                } finally {
                    if ($__dbConn -and $__dbConn.State -ne 0) {
                        try { $__dbConn.Close() } catch {}
                    }
                }
            } finally {
                # Release the mutex to allow other runspaces to write.  Always
                # release the mutex even if an exception occurred.  Disposing
                # the mutex afterwards frees underlying handles.
                try {
                    Write-Host "[DEBUG] Releasing DB write mutex for host '$cleanHostname'" -ForegroundColor Yellow
                    $dbMutex.ReleaseMutex()
                } catch {}
                $dbMutex.Dispose()
            }
        } catch {
            # Use curly braces around variable names that precede a colon to avoid
            # PowerShell interpreting the colon as part of the variable name.
            Write-Warning "Failed to insert data into database for host ${cleanHostname}: $($_.Exception.Message)"
        }
    }

    Remove-OldArchiveFolder -DeviceArchivePath $devicePath -RetentionDays 30
}

#
# Split raw log files into per-host files.
#
# Given a directory containing raw .log or .txt files, this helper scans each
# file for device hostnames and associated prompt indices, then writes out
# separate log files per host into a specified extraction directory.  It
# accepts the input and output directories as parameters so it can be used
# independently of script‑level variables.  The logic is derived from
# NetworkReader.ps1, but refactored here to allow background processing in
# the ParserWorker module.  All diagnostic messages use Write‑Host for
# consistency with the original implementation.
function Split-RawLogs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$LogPath,
        [Parameter(Mandatory=$true)][string]$ExtractedPath
    )
    Write-Host "Split-RawLogs: scanning directory '$LogPath' for .log and .txt files..."
    # Gather all files in the log directory and classify by extension.  Report
    # which files will be included or skipped to aid debugging.  Normalize
    # extensions to lowercase for comparison.
    $allFiles = Get-ChildItem $LogPath -File
    foreach ($f in $allFiles) {
        $ext = $f.Extension.ToLowerInvariant()
        if ($ext -in '.log', '.txt') {
            Write-Host "Including file for processing: $($f.FullName)"
        } else {
            Write-Host "Skipping file due to unsupported extension '$($f.Extension)': $($f.FullName)"
        }
    }
    $rawFiles = $allFiles | Where-Object {
        $ext = $_.Extension.ToLowerInvariant()
        $ext -in '.log', '.txt'
    }
    Write-Host "Found $($rawFiles.Count) raw log file(s) to process."

    foreach ($file in $rawFiles) {
        Write-Host "\n--- Processing file: $($file.FullName) ---"
        Write-Host "Reading file: $($file.FullName)"
        $lines = Get-Content $file.FullName
        Write-Host "Loaded $($lines.Count) lines from '$($file.Name)'"
        $hostMarkers = @()

        # Find hostnames in the file.  A hostname line looks like "hostname <name>".
        # For each hostname, search the file for the earliest prompt matching
        # either "SSH@<hostname>#" or "<hostname>#".  If no prompt is found,
        # default to index 0 so the entire file is extracted for that host.
        Write-Host "Searching for hostnames in '$($file.Name)'..."
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '(?i)^\s*hostname\s+(\S+)\s*$') {
                $hostname = $Matches[1]
                Write-Host "Detected hostname '$hostname' at line $i"
                $promptPatterns = @("SSH@${hostname}#", "${hostname}#")
                $foundPromptForHost = $false
                for ($j = 0; $j -lt $lines.Count; $j++) {
                    foreach ($pattern in $promptPatterns) {
                        $regex = "(?i)^\s*$([regex]::Escape($pattern))"
                        if ($lines[$j] -match $regex) {
                            Write-Host "    Found prompt '$pattern' at line $j"
                            $hostMarkers += [PSCustomObject]@{
                                Hostname = $hostname
                                Index    = $j
                            }
                            $foundPromptForHost = $true
                            break
                        }
                    }
                    if ($foundPromptForHost) { break }
                }
                if (-not $foundPromptForHost) {
                    Write-Host "  No prompt found for hostname '$hostname', defaulting to start of file"
                    $hostMarkers += [PSCustomObject]@{
                        Hostname = $hostname
                        Index    = 0
                    }
                }
            }
        }

        if ($hostMarkers.Count -eq 0) {
            Write-Warning "No host markers found in $($file.Name). Skipping this file."
            continue
        }

        # Sort markers by index.  Wrap in array syntax to preserve Count when
        # only one marker exists.  Report summary to aid debugging.
        $hostMarkers = @($hostMarkers | Sort-Object Index)
        $markerStrings = $hostMarkers | ForEach-Object { "$($_.Hostname)@$($_.Index)" }
        $markerSummary = $markerStrings -join ', '
        Write-Host "Host markers for '$($file.Name)': $markerSummary"
        Write-Host "Total host markers found in '$($file.Name)': $($hostMarkers.Count)"

        if ($hostMarkers.Count -eq 1) {
            $singleHost = $hostMarkers[0].Hostname
            $safeSingleHost = $singleHost -replace '[\\/:*?"<>|]', '_'
            $outPathSingle = Join-Path $ExtractedPath "$safeSingleHost.log"
            Write-Host "Single-host file detected. Writing entire file for host '$safeSingleHost' to '$outPathSingle' (total $($lines.Count) lines)"
            $lines | Set-Content $outPathSingle
            if (Test-Path $outPathSingle) {
                Write-Host "Successfully wrote file: $outPathSingle"
            } else {
                Write-Warning "Failed to write file: $outPathSingle"
            }
            Write-Host "Finished processing single-host file '$($file.Name)'"
            continue
        }

        Write-Host "Multi-host file detected. Writing slices for each host."
        for ($k = 0; $k -lt $hostMarkers.Count; $k++) {
            $start = $hostMarkers[$k].Index
            $end   = if ($k -lt $hostMarkers.Count - 1) {
                $hostMarkers[$k + 1].Index - 1
            } else {
                $lines.Count - 1
            }
            $slice = $lines[$start..$end]
            $safeHost = $hostMarkers[$k].Hostname -replace '[\\/:*?"<>|]', '_'
            $outPath = Join-Path $ExtractedPath "$safeHost.log"
            Write-Host "  Preparing slice for host '$safeHost': lines $start..$end (total $($slice.Count))"
            Write-Host "  Writing to: $outPath"
            $slice | Set-Content $outPath
            if (Test-Path $outPath) {
                Write-Host "  Successfully wrote file: $outPath"
            } else {
                Write-Warning "  Failed to write file: $outPath"
            }
        }
        Write-Host "Finished processing multi-host file '$($file.Name)'"
    }
}

#
# Start parsing each extracted device log file in parallel.  Uses a runspace
# pool to limit concurrency.  Each runspace imports the necessary vendor
# modules and this ParserWorker module, then calls Invoke-DeviceLogParsing
# for the given file.  The caller can specify the maximum number of threads
# and optionally a database path.  ModulesPath and ArchiveRoot are passed
# through so that runspaces can locate vendor modules and archival
# directories consistently with the main thread.  This function mirrors
# Start-ParallelDeviceProcessing in NetworkReader.ps1 but accepts explicit
# parameters instead of relying on script‑level variables.
function Start-ParallelDeviceProcessing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string[]]$DeviceFiles,
        [int]$MaxThreads = 20,
        [string]$DatabasePath,
        [Parameter(Mandatory=$true)][string]$ModulesPath,
        [Parameter(Mandatory=$true)][string]$ArchiveRoot
    )
    $sessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxThreads, $sessionState, $Host)
    $runspacePool.Open()
    # Use a typed List[object] for runspaces to avoid O(n^2) array copies
    $runspaces = New-Object 'System.Collections.Generic.List[object]'
    foreach ($file in $DeviceFiles) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $runspacePool
        $ps.AddScript({
            param($filePath, $modulesPath, $archiveRoot, $dbPath)
            Import-Module (Join-Path $modulesPath 'AristaModule.psm1') -Force
            Import-Module (Join-Path $modulesPath 'CiscoModule.psm1') -Force
            Import-Module (Join-Path $modulesPath 'BrocadeModule.psm1') -Force
            Import-Module (Join-Path $modulesPath 'ParserWorker.psm1') -Force
            if ($dbPath -and (Test-Path (Join-Path $modulesPath 'DatabaseModule.psm1'))) {
                Import-Module (Join-Path $modulesPath 'DatabaseModule.psm1') -Force -Global
            }
            Invoke-DeviceLogParsing -FilePath $filePath -ArchiveRoot $archiveRoot -DatabasePath $dbPath
        }).AddArgument($file).AddArgument($ModulesPath).AddArgument($ArchiveRoot).AddArgument($DatabasePath)
        [void]$runspaces.Add([PSCustomObject]@{
            Pipe = $ps
            AsyncResult = $ps.BeginInvoke()
        })
    }
    foreach ($r in $runspaces) {
        $r.Pipe.EndInvoke($r.AsyncResult)
        $r.Pipe.Dispose()
    }
    $runspacePool.Close()
    $runspacePool.Dispose()
}

#
# Clear all files from the extracted log directory.  This helper accepts
# an explicit path rather than relying on module-level variables so that
# callers can control where extracted files are located.  Removing the
# extracted files prevents stale data from persisting between runs.
function Clear-ExtractedLogs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ExtractedPath
    )
    Get-ChildItem $ExtractedPath -File | Remove-Item -Force -ErrorAction SilentlyContinue
}

#
# Entry point for full parsing from the GUI.  This function encapsulates
# the entire processing pipeline previously defined in NetworkReader.ps1.
# It computes project paths relative to the module location, creates
# necessary directories, splits raw logs, invokes per‑device parsing in
# parallel and finally cleans up temporary files.  An optional
# DatabasePath parameter allows callers to override the database path or
# rely on the StateTraceDb environment/global variables.  The caller
# should import this module before invoking the function.
function Invoke-StateTraceParsing {
    [CmdletBinding()]
    param(
        [string]$DatabasePath
    )
    $projectRoot = Join-Path $PSScriptRoot '..' | Resolve-Path | Select-Object -ExpandProperty Path
    $logPath       = Join-Path $projectRoot 'Logs'
    $extractedPath = Join-Path $logPath 'Extracted'
    $modulesPath   = Join-Path $projectRoot 'Modules'
    $archiveRoot   = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'SwitchArchives'
    New-Directories @($logPath, $extractedPath, $archiveRoot)
    Split-RawLogs -LogPath $logPath -ExtractedPath $extractedPath
    $deviceFiles = Get-ChildItem $extractedPath -File | Select-Object -ExpandProperty FullName
    if ($deviceFiles.Count -gt 0) {
        Write-Host "Extracted $($deviceFiles.Count) device log file(s) to process:" -ForegroundColor Yellow
        foreach ($dev in $deviceFiles) { Write-Host "  - $dev" -ForegroundColor Yellow }
    } else {
        Write-Warning "No device logs were extracted; the parser will not run."
    }
    $threadCount = [Math]::Min(8, [Environment]::ProcessorCount)
    $dbPath = $null
    if ($PSBoundParameters.ContainsKey('DatabasePath') -and $DatabasePath) {
        $dbPath = $DatabasePath
    } elseif ($env:StateTraceDbPath -and $env:StateTraceDbPath -ne '') {
        $dbPath = $env:StateTraceDbPath
    } elseif ($global:StateTraceDb) {
        $dbPath = $global:StateTraceDb
    }
    if ($deviceFiles.Count -gt 0) {
        Write-Host "Processing $($deviceFiles.Count) logs in parallel..." -ForegroundColor Yellow
        Start-ParallelDeviceProcessing -DeviceFiles $deviceFiles -MaxThreads $threadCount -DatabasePath $dbPath -ModulesPath $modulesPath -ArchiveRoot $archiveRoot
    }
    Clear-ExtractedLogs -ExtractedPath $extractedPath
    Write-Host "Processing complete." -ForegroundColor Yellow
}

#
# Split raw log files into per-host files.
#
# Given a directory containing raw .log or .txt files, this helper scans each
# file for device hostnames and associated prompt indices, then writes out
# separate log files per host into a specified extraction directory.  It
# accepts the input and output directories as parameters so it can be used
# independently of script‑level variables.  The logic is derived from
# NetworkReader.ps1, but refactored here to allow background processing in
# the ParserWorker module.  All diagnostic messages use Write‑Host for
# consistency with the original implementation.
function Split-RawLogs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$LogPath,
        [Parameter(Mandatory=$true)][string]$ExtractedPath
    )
    Write-Host "Split-RawLogs: scanning directory '$LogPath' for .log and .txt files..."
    # Gather all files in the log directory and classify by extension.  Report
    # which files will be included or skipped to aid debugging.  Normalize
    # extensions to lowercase for comparison.
    $allFiles = Get-ChildItem $LogPath -File
    foreach ($f in $allFiles) {
        $ext = $f.Extension.ToLowerInvariant()
        if ($ext -in '.log', '.txt') {
            Write-Host "Including file for processing: $($f.FullName)"
        } else {
            Write-Host "Skipping file due to unsupported extension '$($f.Extension)': $($f.FullName)"
        }
    }
    $rawFiles = $allFiles | Where-Object {
        $ext = $_.Extension.ToLowerInvariant()
        $ext -in '.log', '.txt'
    }
    Write-Host "Found $($rawFiles.Count) raw log file(s) to process."

    foreach ($file in $rawFiles) {
        Write-Host "\n--- Processing file: $($file.FullName) ---"
        Write-Host "Reading file: $($file.FullName)"
        $lines = Get-Content $file.FullName
        Write-Host "Loaded $($lines.Count) lines from '$($file.Name)'"
        $hostMarkers = @()

        # Find hostnames in the file.  A hostname line looks like "hostname <name>".
        # For each hostname, search the file for the earliest prompt matching
        # either "SSH@<hostname>#" or "<hostname>#".  If no prompt is found,
        # default to index 0 so the entire file is extracted for that host.
        Write-Host "Searching for hostnames in '$($file.Name)'..."
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '(?i)^\s*hostname\s+(\S+)\s*$') {
                $hostname = $Matches[1]
                Write-Host "Detected hostname '$hostname' at line $i"
                $promptPatterns = @("SSH@${hostname}#", "${hostname}#")
                $foundPromptForHost = $false
                for ($j = 0; $j -lt $lines.Count; $j++) {
                    foreach ($pattern in $promptPatterns) {
                        $regex = "(?i)^\s*$([regex]::Escape($pattern))"
                        if ($lines[$j] -match $regex) {
                            Write-Host "    Found prompt '$pattern' at line $j"
                            $hostMarkers += [PSCustomObject]@{
                                Hostname = $hostname
                                Index    = $j
                            }
                            $foundPromptForHost = $true
                            break
                        }
                    }
                    if ($foundPromptForHost) { break }
                }
                if (-not $foundPromptForHost) {
                    Write-Host "  No prompt found for hostname '$hostname', defaulting to start of file"
                    $hostMarkers += [PSCustomObject]@{
                        Hostname = $hostname
                        Index    = 0
                    }
                }
            }
        }

        if ($hostMarkers.Count -eq 0) {
            Write-Warning "No host markers found in $($file.Name). Skipping this file."
            continue
        }

        # Sort markers by index.  Wrap in array syntax to preserve Count when
        # only one marker exists.  Report summary to aid debugging.
        $hostMarkers = @($hostMarkers | Sort-Object Index)
        $markerStrings = $hostMarkers | ForEach-Object { "$($_.Hostname)@$($_.Index)" }
        $markerSummary = $markerStrings -join ', '
        Write-Host "Host markers for '$($file.Name)': $markerSummary"
        Write-Host "Total host markers found in '$($file.Name)': $($hostMarkers.Count)"

        if ($hostMarkers.Count -eq 1) {
            $singleHost = $hostMarkers[0].Hostname
            $safeSingleHost = $singleHost -replace '[\\/:*?"<>|]', '_'
            $outPathSingle = Join-Path $ExtractedPath "$safeSingleHost.log"
            Write-Host "Single-host file detected. Writing entire file for host '$safeSingleHost' to '$outPathSingle' (total $($lines.Count) lines)"
            $lines | Set-Content $outPathSingle
            if (Test-Path $outPathSingle) {
                Write-Host "Successfully wrote file: $outPathSingle"
            } else {
                Write-Warning "Failed to write file: $outPathSingle"
            }
            Write-Host "Finished processing single-host file '$($file.Name)'"
            continue
        }

        Write-Host "Multi-host file detected. Writing slices for each host."
        for ($k = 0; $k -lt $hostMarkers.Count; $k++) {
            $start = $hostMarkers[$k].Index
            $end   = if ($k -lt $hostMarkers.Count - 1) {
                $hostMarkers[$k + 1].Index - 1
            } else {
                $lines.Count - 1
            }
            $slice = $lines[$start..$end]
            $safeHost = $hostMarkers[$k].Hostname -replace '[\\/:*?"<>|]', '_'
            $outPath = Join-Path $ExtractedPath "$safeHost.log"
            Write-Host "  Preparing slice for host '$safeHost': lines $start..$end (total $($slice.Count))"
            Write-Host "  Writing to: $outPath"
            $slice | Set-Content $outPath
            if (Test-Path $outPath) {
                Write-Host "  Successfully wrote file: $outPath"
            } else {
                Write-Warning "  Failed to write file: $outPath"
            }
        }
        Write-Host "Finished processing multi-host file '$($file.Name)'"
    }
}

#
# Start parsing each extracted device log file in parallel.  Uses a runspace
# pool to limit concurrency.  Each runspace imports the necessary vendor
# modules and this ParserWorker module, then calls Invoke-DeviceLogParsing
# for the given file.  The caller can specify the maximum number of threads
# and optionally a database path.  ModulesPath and ArchiveRoot are passed
# through so that runspaces can locate vendor modules and archival
# directories consistently with the main thread.  This function mirrors
# Start-ParallelDeviceProcessing in NetworkReader.ps1 but accepts explicit
# parameters instead of relying on script‑level variables.
function Start-ParallelDeviceProcessing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string[]]$DeviceFiles,
        [int]$MaxThreads = 20,
        [string]$DatabasePath,
        [Parameter(Mandatory=$true)][string]$ModulesPath,
        [Parameter(Mandatory=$true)][string]$ArchiveRoot
    )
    $sessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxThreads, $sessionState, $Host)
    $runspacePool.Open()
    # Use a typed List[object] to collect runspaces efficiently, avoiding
    # O(n^2) behaviour when appending items to arrays.
    $runspaces = New-Object 'System.Collections.Generic.List[object]'
    foreach ($file in $DeviceFiles) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $runspacePool
        $ps.AddScript({
            param($filePath, $modulesPath, $archiveRoot, $dbPath)
            Import-Module (Join-Path $modulesPath 'AristaModule.psm1') -Force
            Import-Module (Join-Path $modulesPath 'CiscoModule.psm1') -Force
            Import-Module (Join-Path $modulesPath 'BrocadeModule.psm1') -Force
            Import-Module (Join-Path $modulesPath 'ParserWorker.psm1') -Force
            if ($dbPath -and (Test-Path (Join-Path $modulesPath 'DatabaseModule.psm1'))) {
                Import-Module (Join-Path $modulesPath 'DatabaseModule.psm1') -Force -Global
            }
            Invoke-DeviceLogParsing -FilePath $filePath -ArchiveRoot $archiveRoot -DatabasePath $dbPath
        }).AddArgument($file).AddArgument($ModulesPath).AddArgument($ArchiveRoot).AddArgument($DatabasePath)
        [void]$runspaces.Add([PSCustomObject]@{
            Pipe = $ps
            AsyncResult = $ps.BeginInvoke()
        })
    }
    foreach ($r in $runspaces) {
        $r.Pipe.EndInvoke($r.AsyncResult)
        $r.Pipe.Dispose()
    }
    $runspacePool.Close()
    $runspacePool.Dispose()
}

#
# Clear all files from the extracted log directory.  This helper accepts
# an explicit path rather than relying on module-level variables so that
# callers can control where extracted files are located.  Removing the
# extracted files prevents stale data from persisting between runs.
function Clear-ExtractedLogs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ExtractedPath
    )
    Get-ChildItem $ExtractedPath -File | Remove-Item -Force -ErrorAction SilentlyContinue
}

#
# Entry point for full parsing from the GUI.  This function encapsulates
# the entire processing pipeline previously defined in NetworkReader.ps1.
# It computes project paths relative to the module location, creates
# necessary directories, splits raw logs, invokes per‑device parsing in
# parallel and finally cleans up temporary files.  An optional
# DatabasePath parameter allows callers to override the database path or
# rely on the StateTraceDb environment/global variables.  The caller
# should import this module before invoking the function.
function Invoke-StateTraceParsing {
    [CmdletBinding()]
    param(
        [string]$DatabasePath
    )
    $projectRoot = Join-Path $PSScriptRoot '..' | Resolve-Path | Select-Object -ExpandProperty Path
    $logPath       = Join-Path $projectRoot 'Logs'
    $extractedPath = Join-Path $logPath 'Extracted'
    $modulesPath   = Join-Path $projectRoot 'Modules'
    $archiveRoot   = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'SwitchArchives'
    New-Directories @($logPath, $extractedPath, $archiveRoot)
    Split-RawLogs -LogPath $logPath -ExtractedPath $extractedPath
    $deviceFiles = Get-ChildItem $extractedPath -File | Select-Object -ExpandProperty FullName
    if ($deviceFiles.Count -gt 0) {
        Write-Host "Extracted $($deviceFiles.Count) device log file(s) to process:" -ForegroundColor Yellow
        foreach ($dev in $deviceFiles) { Write-Host "  - $dev" -ForegroundColor Yellow }
    } else {
        Write-Warning "No device logs were extracted; the parser will not run."
    }
    $threadCount = [Math]::Min(8, [Environment]::ProcessorCount)
    $dbPath = $null
    if ($PSBoundParameters.ContainsKey('DatabasePath') -and $DatabasePath) {
        $dbPath = $DatabasePath
    } elseif ($env:StateTraceDbPath -and $env:StateTraceDbPath -ne '') {
        $dbPath = $env:StateTraceDbPath
    } elseif ($global:StateTraceDb) {
        $dbPath = $global:StateTraceDb
    }
    if ($deviceFiles.Count -gt 0) {
        Write-Host "Processing $($deviceFiles.Count) logs in parallel..." -ForegroundColor Yellow
        Start-ParallelDeviceProcessing -DeviceFiles $deviceFiles -MaxThreads $threadCount -DatabasePath $dbPath -ModulesPath $modulesPath -ArchiveRoot $archiveRoot
    }
    Clear-ExtractedLogs -ExtractedPath $extractedPath
    Write-Host "Processing complete." -ForegroundColor Yellow
}
