function New-Directories {
    param ([string[]]$Paths)
    foreach ($path in $Paths) {
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path | Out-Null
        }
    }
}

#

function Split-RawLogs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$LogPath,
        [Parameter(Mandatory=$true)][string]$ExtractedPath
    )

    New-Item -ItemType Directory -Force -Path $ExtractedPath | Out-Null

    $rawFiles = Get-ChildItem -Path $LogPath -File | Where-Object {
        $_.Extension -match '^\.(log|txt)$'
    }
    Write-Host "Split-RawLogs (streaming): found $($rawFiles.Count) file(s) in '$LogPath'."

    $reHostname = [regex]::new('(?i)^\s*hostname\s+(\S+)\s*$', 'Compiled')
    $rePrompt   = [regex]::new('^\s*(?:SSH@)?([^\s#>]+)\s*[#>]\s*$', 'Compiled')

    foreach ($file in $rawFiles) {
        Write-Host "`n--- Streaming file: $($file.FullName) ---"

        $sr = $null
        $writer = $null
        $unknownWriter = $null
        $currentHost = $null

        $buffer = New-Object 'System.Collections.Generic.List[string]'
        $bufferLimit = 4000

        try {
            $sr = [System.IO.StreamReader]::new($file.FullName)

            while (-not $sr.EndOfStream) {
                $line = $sr.ReadLine()

                $mPrompt = $rePrompt.Match($line)
                $mHost   = $reHostname.Match($line)

                $detected = $null
                if ($mPrompt.Success) {
                    $detected = $mPrompt.Groups[1].Value
                } elseif ($mHost.Success) {
                    $detected = $mHost.Groups[1].Value
                }

                if ($detected) {
                    if (-not $currentHost -or $detected -ne $currentHost) {
                        if ($null -ne $writer) { $writer.Dispose() }

                        $safe = ($detected -replace '[\\/:*?"<>|]', '_')
                        $outPath = Join-Path $ExtractedPath "$safe.log"
                        $fs = [System.IO.File]::Open($outPath,
                            [System.IO.FileMode]::Append,
                            [System.IO.FileAccess]::Write,
                            [System.IO.FileShare]::Read)
                        $writer = New-Object System.IO.StreamWriter($fs)
                        $writer.AutoFlush = $true
                        $currentHost = $detected
                        Write-Host "Writing slice for host '$currentHost' -> $outPath"

                        if ($buffer.Count -gt 0) {
                            foreach ($b in $buffer) { $writer.WriteLine($b) }
                            $buffer.Clear()
                        }
                    }
                }

                if ($writer -ne $null) {
                    $writer.WriteLine($line)
                } else {
                    if ($buffer.Count -lt $bufferLimit) {
                        $buffer.Add($line) | Out-Null
                    } else {
                        if ($null -eq $unknownWriter) {
                            $uPath = Join-Path $ExtractedPath "_unknown.log"
                            $ufs = [System.IO.File]::Open($uPath,
                                [System.IO.FileMode]::Append,
                                [System.IO.FileAccess]::Write,
                                [System.IO.FileShare]::Read)
                            $unknownWriter = New-Object System.IO.StreamWriter($ufs)
                            $unknownWriter.AutoFlush = $true
                            Write-Host "No host detected yet; spilling overflow to $uPath"
                        }
                        $unknownWriter.WriteLine($line)
                    }
                }
            }

            if ($buffer.Count -gt 0) {
                if ($null -eq $writer) {
                    $uPath = Join-Path $ExtractedPath "_unknown.log"
                    $ufs = [System.IO.File]::Open($uPath,
                        [System.IO.FileMode]::Append,
                        [System.IO.FileAccess]::Write,
                        [System.IO.FileShare]::Read)
                    $uw = New-Object System.IO.StreamWriter($ufs)
                    $uw.AutoFlush = $true
                    foreach ($b in $buffer) { $uw.WriteLine($b) }
                    $uw.Dispose()
                    Write-Host "Completed file without detecting a host; wrote buffered content to $uPath"
                } else {
                    foreach ($b in $buffer) { $writer.WriteLine($b) }
                }
                $buffer.Clear()
            }
        }
        finally {
            if ($writer) { $writer.Dispose() }
            if ($unknownWriter) { $unknownWriter.Dispose() }
            if ($sr) { $sr.Dispose() }
        }
    }

    Write-Host "Split-RawLogs (streaming): complete."
}


#
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
    $sessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxThreads, $sessionState, $Host)
    $runspacePool.Open()
    # Use a typed List[object] to collect runspaces efficiently, avoiding
    $runspaces = New-Object 'System.Collections.Generic.List[object]'
    foreach ($file in $DeviceFiles) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $runspacePool
        # Build the script block to execute in each runspace.  Import the vendor
        $ps.AddScript({
            param($filePath, $modulesPath, $archiveRoot, $dbPath)
            Import-Module (Join-Path $modulesPath 'AristaModule.psm1') -Force
            Import-Module (Join-Path $modulesPath 'CiscoModule.psm1') -Force
            Import-Module (Join-Path $modulesPath 'BrocadeModule.psm1') -Force
            Import-Module (Join-Path $modulesPath 'ParserWorker.psm1') -Force
            # Always import the database module so that helper functions such as
            # New-DatabaseIfMissing and New-AccessDatabase are available.  Do not
            # conditionally load it based on $dbPath or path existence.
            Import-Module (Join-Path $modulesPath 'DatabaseModule.psm1') -Force -Global
            # Invoke the parser.  Pass ArchiveRoot and DatabasePath so that
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
function Clear-ExtractedLogs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ExtractedPath
    )
    Get-ChildItem $ExtractedPath -File | Remove-Item -Force -ErrorAction SilentlyContinue
}

# Extract the site identifier from a hostname.  Sites are defined
# by the substring before the first dash ("-") in the host name.  If no dash
# is present, this helper returns the first four characters of the hostname.
# If the hostname is shorter than four characters, the full hostname is returned.
function Get-SiteFromHostname {
    param([string]$Hostname)
    if (-not $Hostname) { return 'Unknown' }
    # Remove any SSH@ prefix and trim whitespace
    $clean = $Hostname -replace '^SSH@',''
    $clean = $clean.Trim()
    # Extract the part before the first dash
    if ($clean -match '^(?<site>[^-]+)-') {
        return $matches['site']
    }
    # Fallback: use the first 4 characters if possible
    if ($clean.Length -ge 4) {
        return $clean.Substring(0,4)
    }
    return $clean
}

#
function Invoke-StateTraceParsing {
    [CmdletBinding()]
    param(
        [string]$DatabasePath
    )
    # Determine project root based on the module's location.  $PSScriptRoot is
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
    # Determine database path precedence: use explicit parameter only.  All
    # per-site database paths are computed inside the parser worker.
    $dbPath = $null
    if ($PSBoundParameters.ContainsKey('DatabasePath') -and $DatabasePath) {
        $dbPath = $DatabasePath
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
function Get-LocationDetails {
    [CmdletBinding()] param(
        [string]$Location
    )
    # Default return structure with empty strings.  Additional keys can be
    $details = @{
        Building = ''
        Floor    = ''
        Room     = ''
        Row      = ''
        Rack     = ''
    }
    if (-not [string]::IsNullOrWhiteSpace($Location)) {
        # Split on underscores to capture tokens.  Use `-split` to support any
        $tokens = $Location -split '_+' | Where-Object { $_ -ne '' }
        for ($i = 0; $i -lt $tokens.Count - 1; $i++) {
            $key = $tokens[$i].Trim()
            $value = $tokens[$i + 1].Trim()
            # Perform case-insensitive matching using inline regex option instead of
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
function Get-DeviceMakeFromBlocks {
    [CmdletBinding()]
    param(
        [hashtable]$Blocks
    )
    if (-not $Blocks -or -not $Blocks.ContainsKey('show version')) { return '' }
    $verLines = $Blocks['show version']
    foreach ($ln in $verLines) {
        # Look for Arista identifiers first because other vendors may reference
        if ($ln -match '(?i)\bArista\b') { return 'Arista' }
        # Brocade FastIron/IronWare output often references "Brocade" or
        if ($ln -match '(?i)\bBrocade\b' -or $ln -match '(?i)\bStackable\b' -or $ln -match '(?i)\bIronWare\b') { return 'Brocade' }
        # Cisco IOS, NX-OS, and IOS-XE show version always reference "Cisco".
        if ($ln -match '(?i)\bCisco\b') { return 'Cisco' }
    }
    return ''
}

# Extract the SNMP location string from a log.  Different vendors
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


function ConvertFrom-SpanningTree {
    [CmdletBinding()]
    param(
        [string[]]$SpanLines
    )
    # Use a typed List[object] to accumulate spanning tree entries to avoid
    $entries = New-Object 'System.Collections.Generic.List[object]'
    $current    = ''
    $rootSwitch = ''
    $rootPort   = ''
    foreach ($ln in $SpanLines) {
        $line = $ln.Trim()
        # Identify a new section header.  Match VLANxxxx or MST<number> in a
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
    # If the archive path does not exist, do nothing.
    if (-not (Test-Path $DeviceArchivePath)) { return }

    # Precompute the cutoff date once.  Any archive folder with a date older
    $cutoff = (Get-Date).AddDays(-$RetentionDays)
    foreach ($folder in (Get-ChildItem -Path $DeviceArchivePath -Directory)) {
        $folderDate = $null
        try {
            $folderDate = [datetime]::ParseExact($folder.Name, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
        } catch {
            # Skip folders whose names do not match the expected date format
            continue
        }
        if ($folderDate -lt $cutoff) {
            try {
                Remove-Item $folder.FullName -Recurse -Force
            } catch {
                Write-Warning "Failed to delete archive '$($folder.FullName)': $($_.Exception.Message)"
            }
        }
    }
}

# Extract global authentication configuration lines from Brocade logs.
function Get-BrocadeAuthBlockFromLines {
    [CmdletBinding()]
    param([string[]]$Lines)

    if (-not $Lines) { return @() }

    # Patterns to match the Brocade auth block.  Allow optional dashes
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
    $runDateLiteral = "#$RunDateString#"
    $histSql = "INSERT INTO DeviceHistory (Hostname, RunDate, Make, Model, Uptime, Site, Building, Room, Ports, AuthDefaultVLAN, AuthBlock) VALUES ('$escHostname', $runDateLiteral, '$escMake', '$escModel', '$escUptime', '$escSite', '$escBuilding', '$escRoom', $portCount, '$escAuthVlan', '$escAuthBlock')"
    try {
        $Connection.Execute($histSql) | Out-Null
    } catch {
        Write-Warning "Failed to insert device history for host ${Hostname}: $($_.Exception.Message)"
    }
}


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
        $port   = '' + $iface.Port
        $name   = '' + $iface.Name
        $status = '' + $iface.Status
        $vlan   = '' + $iface.VLAN
        $duplex = '' + $iface.Duplex
        $speed  = '' + $iface.Speed
        $type   = '' + $iface.Type
        # Normalize LearnedMACs handling so that both strings and arrays
        # are written correctly.  Prefer the full list property when
        # provided; otherwise join array elements or accept the string as-is.
        $learned = ''
        if ($iface.PSObject.Properties.Name -contains 'LearnedMACsFull' -and ($iface.LearnedMACsFull)) {
            # The vendor module provided an explicit comma-separated string of
            # all learned MACs; use it directly.
            $learned = '' + $iface.LearnedMACsFull
        } elseif ($iface.PSObject.Properties.Name -contains 'LearnedMACs') {
            $lm = $iface.LearnedMACs
            if ($lm -is [string]) {
                # Already a single MAC string; assign as-is
                $learned = $lm
            } elseif ($lm -ne $null) {
                # Join a list of MACs into a comma-separated string.  Filter out
                # null or empty entries to avoid extraneous commas.
                $learned = ($lm | Where-Object { $_ -and $_ -ne '' }) -join ','
            }
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
    $blocks = Get-ShowCommandBlocks -Lines $lines
    if (-not $blocks) { $blocks = @{} }

    # Determine the vendor (device make) using only the "show version" output.
    $make = Get-DeviceMakeFromBlocks -Blocks $blocks
    if (-not $make) {
        # Fallback heuristic: scan the entire log for vendor keywords in a
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

    # Determine a per-site database path using the device hostname.  Sites
    # correspond to the portion of the hostname before the first dash.  Override
    # the incoming DatabasePath parameter so that each site writes into its own
    # Access database under the project's Data folder.
    try {
        $siteCode = Get-SiteFromHostname $facts.Hostname
        # Compute the absolute project root for constructing the Data directory.
        $projectRoot = Join-Path $PSScriptRoot '..' | Resolve-Path | Select-Object -ExpandProperty Path
        $dbDir = Join-Path $projectRoot 'Data'
        if (-not (Test-Path $dbDir)) {
            # Create the Data directory if it doesn't exist
            New-Item -ItemType Directory -Force -Path $dbDir | Out-Null
        }
        # Compose a file name for the site database; always use .accdb extension
        $DatabasePath = Join-Path $dbDir ("$siteCode.accdb")
        # Ensure the database exists and has the required schema.  This helper
        # is idempotent, so calling it from multiple runspaces is safe.
        if (Get-Command -Name New-DatabaseIfMissing -ErrorAction SilentlyContinue) {
            New-DatabaseIfMissing -Path $DatabasePath
        } elseif (-not (Test-Path $DatabasePath) -and (Get-Command -Name New-AccessDatabase -ErrorAction SilentlyContinue)) {
            New-AccessDatabase -Path $DatabasePath | Out-Null
        }
    } catch {
        # If any error occurs deriving or creating the per-site database, emit a warning
        Write-Warning ("Failed to set up per-site database for host {0}: {1}" -f $facts.Hostname, $_.Exception.Message)
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
    if ($facts.PSObject.Properties.Name -contains 'SpanInfo') {
        $spanData = $facts.SpanInfo
        if ($spanData -and $spanData.Count -gt 0) {
            # Span CSV export disabled – historical data is now stored in the database only
        }
    }

    # Derive additional metadata about the device.  The site is defined as the
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
    if ($DatabasePath) {
        Write-Host "[DEBUG] Writing results for host '$cleanHostname' to database at '$DatabasePath'" -ForegroundColor Yellow
        try {
            # Capture the current run time for historical records.  Format it
            $runDateString = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            # The summary and interface SQL statements will be constructed by helper functions.  No per‑field escaping is required here.

            #-------------------------------------------------------------------------
            $templates = $null
            try {
                $vendor = 'Cisco'
                if ($facts.Make) {
                    # Match known vendors in a case-insensitive manner without
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
            $mutexName = 'StateTraceDbWriteMutex'
            $dbMutex = New-Object System.Threading.Mutex($false, $mutexName)
            try {
                Write-Host "[DEBUG] Waiting to acquire DB write mutex for host '$cleanHostname'" -ForegroundColor Yellow
                # Wait until we can acquire the mutex.  This call blocks until
                $null = $dbMutex.WaitOne()
                Write-Host "[DEBUG] Acquired DB write mutex for host '$cleanHostname'" -ForegroundColor Yellow

                # Establish a single connection to the database for all statements.
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
                $__dbConn.Open("Provider=$__dbProvider;Data Source=$DatabasePath;Mode=ReadWrite;Jet OLEDB:Database Locking Mode=1")
                # When using the Jet OLEDB provider, we can request synchronous
                try {
                    $prop = $__dbConn.Properties.Item('Jet OLEDB:Transaction Commit Mode')
                    if ($prop) { $prop.Value = 1 }
                } catch { }
                # Use an explicit transaction to batch all SQL statements.  Jet/ACE
                $__dbConn.BeginTrans()
                try {
                    #------------------------------------------------------------------

                    # Persist the parsed data using centralized helpers.  These
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
                try {
                    Write-Host "[DEBUG] Releasing DB write mutex for host '$cleanHostname'" -ForegroundColor Yellow
                    $dbMutex.ReleaseMutex()
                } catch {}
                $dbMutex.Dispose()
            }
        } catch {
            # Use curly braces around variable names that precede a colon to avoid
            Write-Warning "Failed to insert data into database for host ${cleanHostname}: $($_.Exception.Message)"
        }
    }

    Remove-OldArchiveFolder -DeviceArchivePath $devicePath -RetentionDays 30
}

#

# Removed duplicate function definition(s)


#

# Removed duplicate function definition(s)


#

# Removed duplicate function definition(s)


#

# Removed duplicate function definition(s)


#

# Removed duplicate function definition(s)


#

# Removed duplicate function definition(s)


#

# Removed duplicate function definition(s)


#

# Removed duplicate function definition(s)
