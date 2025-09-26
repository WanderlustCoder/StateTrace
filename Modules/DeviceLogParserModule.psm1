Set-StrictMode -Version Latest

if (-not (Get-Variable -Name StateTraceDebug -Scope Global -ErrorAction SilentlyContinue)) {
    Set-Variable -Scope Global -Name StateTraceDebug -Value $false -Option None
}

# Cache vendor templates per runspace to avoid repeated JSON parsing.
if (-not (Get-Variable -Name VendorTemplatesCache -Scope Script -ErrorAction SilentlyContinue)) {
    $script:VendorTemplatesCache = @{}
}

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
        # number of underscores between tokens.  Avoid the Where-Object pipeline
        # by manually filtering out empty strings into a strongly typed list.
        $rawTokens = $Location -split '_+'
        $tokensList = New-Object 'System.Collections.Generic.List[string]'
        foreach ($t in $rawTokens) {
            if ($t -ne '') { [void]$tokensList.Add($t) }
        }
        for ($i = 0; $i -lt $tokensList.Count - 1; $i++) {
            $key = $tokensList[$i].Trim()
            $value = $tokensList[$i + 1].Trim()
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






function Invoke-DeviceLogParsing {
    param (
        [string]$FilePath,
        [string]$ArchiveRoot,
        [string]$DatabasePath
    )

    # Emit debug message only when StateTrace debugging is enabled
    if ($Global:StateTraceDebug) {
        Write-Host "[DEBUG] Parsing file '$FilePath'" -ForegroundColor Yellow
    }
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
            # Locate the first line matching auth-default-vlan using a manual loop
            # instead of Where-Object/Select-Object.  Break immediately on the
            # first match to avoid enumerating the entire collection.
            $authLine = $null
            foreach ($ln in $lines) {
                if ($ln -match 'auth-?default-?vlan\s*(\d+)') { $authLine = $ln; break }
            }
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
        $siteCode = DeviceRepositoryModule\Get-SiteFromHostname -Hostname $facts.Hostname -FallbackLength 4
        # Compute the absolute project root for constructing the Data directory.
        # Compute the project root using GetFullPath instead of Resolve‑Path to
        # avoid pipeline overhead.  This is executed inside each runspace, so
        # efficiency matters when processing many logs.
        try {
            $projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
        } catch {
            $projectRoot = (Split-Path -Parent $PSScriptRoot)
        }
        $dbDir = Join-Path $projectRoot 'Data'
        if (-not (Test-Path $dbDir)) {
            # Create the Data directory if it doesn't exist
            New-Item -ItemType Directory -Force -Path $dbDir | Out-Null
        }
        # Compose a file name for the site database; always use .accdb extension
        $DatabasePath = Join-Path $dbDir ("$siteCode.accdb")
        # Ensure the database exists and has the required schema.  This helper
        # is idempotent, so calling it from multiple runspaces is safe.
        # Use a named mutex to avoid race conditions when multiple runspaces
        # attempt to create the same per‑site database concurrently.  The mutex
        # name is derived from the site code so that only runspaces targeting
        # the same database will block each other.  Inside the mutex, check
        # again whether the file exists before creating it.  If the file is
        # created by another runspace while waiting, the creation call will be
        # skipped.
        $createMutexName = "StateTraceDbCreateMutex_${siteCode}"
        $dbCreateMutex = New-Object System.Threading.Mutex($false, $createMutexName)
        try {
            $null = $dbCreateMutex.WaitOne()
            if (Get-Command -Name New-DatabaseIfMissing -ErrorAction SilentlyContinue) {
                # Always call New-DatabaseIfMissing, which is expected to be idempotent.
                try {
                    New-DatabaseIfMissing -Path $DatabasePath
                } catch {
                    # Swallow errors related to existing database to avoid noisy warnings.
                }
            } elseif (Get-Command -Name New-AccessDatabase -ErrorAction SilentlyContinue) {
                # Only create the database if it does not already exist.
                if (-not (Test-Path $DatabasePath)) {
                    try {
                        New-AccessDatabase -Path $DatabasePath | Out-Null
                    } catch {
                        # Ignore failures caused by concurrent creation.
                    }
                }
            }
        } finally {
            try { $dbCreateMutex.ReleaseMutex() } catch { }
            $dbCreateMutex.Dispose()
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

    # Ensure archive directories exist even if ParserWorker isn't imported.
    foreach ($dir in @($devicePath, $archivePath)) {
        if ([string]::IsNullOrWhiteSpace($dir)) { continue }
        [System.IO.Directory]::CreateDirectory($dir) | Out-Null
    }

    if ($facts.PSObject.Properties.Name -contains "InterfacesCombined") {
        # CSV export disabled – historical data is now stored in the database
    } else {
        # CSV export disabled – historical data is now stored in the database
    }

    # Export spanning tree information if available.  The facts may contain
    if ($facts.PSObject.Properties.Name -contains 'SpanInfo') {
        $spanData = $facts.SpanInfo
        if ($spanData) {
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
        AuthDefaultVLAN  = if ($facts.PSObject.Properties.Name -contains 'AuthDefaultVLAN') { $facts.AuthDefaultVLAN } else { "" }
        AuthBlock        = if ($facts.PSObject.Properties.Name -contains 'AuthenticationBlock' -and $facts.AuthenticationBlock) { $facts.AuthenticationBlock -join "`n" } else { "" }
    }

    # Summary CSV export disabled – historical data is now stored in the database

    # If a database path was supplied, insert the summary and interface data
    if ($DatabasePath) {
        if ($Global:StateTraceDebug) {
            Write-Host "[DEBUG] Writing results for host '$cleanHostname' to database at '$DatabasePath'" -ForegroundColor Yellow
        }
        try {
            # Capture the current run time for historical records.  Format it
            $runDateString = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            # The summary and interface SQL statements will be constructed by helper functions.  No per‑field escaping is required here.

            #-------------------------------------------------------------------------
            $templates = $null
            try {
                $vendor = 'Cisco'
                if ($facts.Make) {
                    # Match known vendors in a case-insensitive manner without specifying all vendor strings.
                    if ($facts.Make -match '(?i)brocade') { $vendor = 'Brocade' }
                    elseif ($facts.Make -match '(?i)arista') { $vendor = 'Brocade' }
                }
                $tplDir   = Join-Path $PSScriptRoot '..\Templates'
                $jsonFile = Join-Path $tplDir "$vendor.json"
                # Use the script-scoped cache to avoid repeatedly reading and parsing the same
                # vendor template file within a single runspace.  Populate the cache on
                # first use; thereafter reuse the stored templates array.
                if (-not $script:VendorTemplatesCache) { $script:VendorTemplatesCache = @{} }
                if ($script:VendorTemplatesCache.ContainsKey($vendor)) {
                    $templates = $script:VendorTemplatesCache[$vendor]
                } else {
                    if (Test-Path $jsonFile) {
                        $json = Get-Content -Path $jsonFile -Raw | ConvertFrom-Json
                        if ($json.templates) {
                            $templates = $json.templates
                        } else {
                            $templates = @()
                        }
                        $script:VendorTemplatesCache[$vendor] = $templates
                    } else {
                        $templates = @()
                    }
                }
            } catch {
                # Ignore template load errors; compliance info will remain default
            }

            #---------------------------------------------------------------------
            $mutexName = 'StateTraceDbWriteMutex'
            $dbMutex = New-Object System.Threading.Mutex($false, $mutexName)
            try {
                if ($Global:StateTraceDebug) {
                    Write-Host "[DEBUG] Waiting to acquire DB write mutex for host '$cleanHostname'" -ForegroundColor Yellow
                }
                # Wait until we can acquire the mutex.  This call blocks until
                $null = $dbMutex.WaitOne()
                if ($Global:StateTraceDebug) {
                    Write-Host "[DEBUG] Acquired DB write mutex for host '$cleanHostname'" -ForegroundColor Yellow
                }

                # Establish a single connection to the database for all statements.
                $__dbProvider = $null
                if ($Global:StateTraceDebug) {
                    Write-Host "[DEBUG] Detecting available OLEDB provider for database" -ForegroundColor Yellow
                }
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
                if ($Global:StateTraceDebug) {
                    Write-Host "[DEBUG] Opening DB connection to '$DatabasePath' using provider '$__dbProvider'" -ForegroundColor Yellow
                }
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
                    $summaryCmd = Get-Command -Name 'ParserPersistenceModule\\Update-DeviceSummaryInDb' -ErrorAction SilentlyContinue
                    if (-not $summaryCmd) { $summaryCmd = Get-Command -Name 'Update-DeviceSummaryInDb' -ErrorAction SilentlyContinue }
                    if (-not $summaryCmd) { throw "Required parser persistence helper 'Update-DeviceSummaryInDb' is not available. Ensure ParserPersistenceModule.psm1 is imported." }
                    $summaryParams = @{
                        Connection      = $__dbConn
                        Facts           = $facts
                        Hostname        = $cleanHostname
                        SiteCode        = $siteCode
                        LocationDetails = $locDetails
                        RunDateString   = $runDateString
                    }
                    & $summaryCmd @summaryParams
                    $ifaceCmd = Get-Command -Name 'ParserPersistenceModule\\Update-InterfacesInDb' -ErrorAction SilentlyContinue
                    if (-not $ifaceCmd) { $ifaceCmd = Get-Command -Name 'Update-InterfacesInDb' -ErrorAction SilentlyContinue }
                    if (-not $ifaceCmd) { throw "Required parser persistence helper 'Update-InterfacesInDb' is not available. Ensure ParserPersistenceModule.psm1 is imported." }
                    $ifaceParams = @{
                        Connection    = $__dbConn
                        Facts         = $facts
                        Hostname      = $cleanHostname
                        RunDateString = $runDateString
                        Templates     = $templates
                    }
                    & $ifaceCmd @ifaceParams
                    # Commit the transaction after all operations have executed.
                    try {
                        if ($Global:StateTraceDebug) {
                            Write-Host "[DEBUG] Committing transaction for host '$cleanHostname'" -ForegroundColor Yellow
                        }
                        $__dbConn.CommitTrans()
                        try {
                            $jet = New-Object -ComObject JRO.JetEngine
                            $jet.RefreshCache($__dbConn)
                            if ($Global:StateTraceDebug) {
                                Write-Host "[DEBUG] Refreshed Jet cache after commit for host '$cleanHostname'" -ForegroundColor Yellow
                            }
                        } catch {}
                    } catch {
                        if ($Global:StateTraceDebug) {
                            Write-Host "[DEBUG] Commit failed for host '$cleanHostname', rolling back" -ForegroundColor Yellow
                        }
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
                    if ($Global:StateTraceDebug) {
                        Write-Host "[DEBUG] Releasing DB write mutex for host '$cleanHostname'" -ForegroundColor Yellow
                    }
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



Export-ModuleMember -Function Get-LocationDetails, Get-ShowCommandBlocks, Get-DeviceMakeFromBlocks, Get-SnmpLocationFromLines, ConvertFrom-SpanningTree, Remove-OldArchiveFolder, Get-BrocadeAuthBlockFromLines, Invoke-DeviceLogParsing







