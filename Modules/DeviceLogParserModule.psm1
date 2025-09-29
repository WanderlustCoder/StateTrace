Set-StrictMode -Version Latest

if (-not (Get-Variable -Name StateTraceDebug -Scope Global -ErrorAction SilentlyContinue)) {
    Set-Variable -Scope Global -Name StateTraceDebug -Value $false -Option None
}
if (-not (Get-Variable -Name DbProviderCache -Scope Script -ErrorAction SilentlyContinue)) {
    $script:DbProviderCache = [System.Collections.Concurrent.ConcurrentDictionary[string,string]]::new([System.StringComparer]::OrdinalIgnoreCase)
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

function Get-CanonicalDatabaseKey {
    param([string]$DatabasePath)

    if ([string]::IsNullOrWhiteSpace($DatabasePath)) { return '' }

    $candidate = $DatabasePath
    try {
        $candidate = [System.IO.Path]::GetFullPath($DatabasePath)
    } catch {
        # Ignore path resolution errors and fall back to the provided value
    }

    return $candidate.Trim().ToLowerInvariant()
}

function Get-DatabaseMutexName {
    param([string]$DatabasePath)

    $key = Get-CanonicalDatabaseKey -DatabasePath $DatabasePath
    if ([string]::IsNullOrEmpty($key)) { return 'StateTraceDbWriteMutex' }

    $hash = $null
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($key)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $hashBytes = $sha.ComputeHash($bytes)
            $hash = ([System.BitConverter]::ToString($hashBytes) -replace '-', '')
        } finally {
            if ($sha) { $sha.Dispose() }
        }
    } catch {
        $hash = [Math]::Abs($key.GetHashCode())
    }

    if (-not $hash) { $hash = 'Default' }
    return "StateTraceDbWriteMutex_$hash"
}

function Get-FileHashHex {
    param([Parameter(Mandatory)][string]$FilePath)

    if (-not (Test-Path -LiteralPath $FilePath)) {
        throw "File '$FilePath' not found"
    }

    $stream = $null
    $sha    = $null
    try {
        $stream = [System.IO.File]::Open($FilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $hashBytes = $sha.ComputeHash($stream)
        return ([System.BitConverter]::ToString($hashBytes) -replace '-', '').ToLowerInvariant()
    } finally {
        if ($stream) { $stream.Dispose() }
        if ($sha) { $sha.Dispose() }
    }
}

function Get-DeviceLogContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath
    )

    $linesList = New-Object 'System.Collections.Generic.List[string]'
    $blocks = @{}
    $currentCmd = ''
    $buffer = New-Object 'System.Collections.Generic.List[string]'
    $recording = $false
    $promptPattern = '^[^\s]+[>#]\s*(?:do\s+)?(show\s+.+)$'
    $promptStartPattern = '^[^\s]+[>#]'

    $reader = $null
    try {
        $reader = [System.IO.StreamReader]::new($FilePath)
        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            [void]$linesList.Add($line)

            if ($line -match $promptPattern) {
                if ($recording -and $currentCmd) {
                    $blocks[$currentCmd] = $buffer
                }
                $currentCmd = $matches[1].Trim().ToLower()
                $buffer = New-Object 'System.Collections.Generic.List[string]'
                $recording = $true
                continue
            }
            if ($recording -and $line -match $promptStartPattern) {
                $blocks[$currentCmd] = $buffer
                $currentCmd = ''
                $buffer = New-Object 'System.Collections.Generic.List[string]'
                $recording = $false
                continue
            }
            if ($recording) {
                [void]$buffer.Add($line)
            }
        }
    } finally {
        if ($reader) { $reader.Dispose() }
    }

    if ($recording -and $currentCmd) {
        $blocks[$currentCmd] = $buffer
    }

    $lineArray = $linesList.ToArray()
    return [PSCustomObject]@{
        Lines  = $lineArray
        Blocks = $blocks
    }
}
# Determine the device vendor from the contents of a "show version" block.  Rather than

function Get-LogParseContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath
    )

    return Get-DeviceLogContext -FilePath $FilePath
}

function Get-VendorTemplates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Vendor,
        [string]$TemplatesRoot
    )

    if (-not $script:VendorTemplatesCache) { $script:VendorTemplatesCache = @{} }

    $vendorKey = ('' + $Vendor).Trim()
    if ([string]::IsNullOrWhiteSpace($vendorKey)) { return @() }

    if (-not $TemplatesRoot) {
        $TemplatesRoot = Join-Path $PSScriptRoot '..\Templates'
    }

    if ($script:VendorTemplatesCache.ContainsKey($vendorKey)) {
        return $script:VendorTemplatesCache[$vendorKey]
    }

    $templates = @()
    try {
        $jsonFile = Join-Path $TemplatesRoot ("{0}.json" -f $vendorKey)
        if (Test-Path $jsonFile) {
            $json = Get-Content -Path $jsonFile -Raw | ConvertFrom-Json
            if ($json.templates) {
                $templates = $json.templates
            }
        }
    } catch {
        $templates = @()
    }

    $script:VendorTemplatesCache[$vendorKey] = $templates
    return $templates
}

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

    $entries = New-Object 'System.Collections.Generic.List[object]'
    $current    = ''
    $rootSwitch = ''
    $rootPort   = ''
    $firstInterface = ''
    $firstRole = ''
    $captureInterfaces = $false

    foreach ($ln in $SpanLines) {
        $line = if ($null -ne $ln) { $ln.Trim() } else { '' }

        if ($line -match '(?i)^(vlan\d+|mst\d+)') {
            if ($current -ne '') {
                [void]$entries.Add([PSCustomObject]@{
                    VLAN       = $current
                    RootSwitch = $rootSwitch
                    RootPort   = $rootPort
                    Role       = $firstRole
                    Upstream   = $firstInterface
                })
            }
            $current = $matches[1]
            $rootSwitch = ''
            $rootPort   = ''
            $firstInterface = ''
            $firstRole = ''
            $captureInterfaces = $false
            continue
        }

        if (-not $rootSwitch -and $line -match 'Address\s+(\S+)') {
            $rootSwitch = $matches[1]
            continue
        }

        if (-not $rootPort -and $line -match 'Root\s+port\s+(\S+),') {
            $rootPort = $matches[1]
            continue
        }

        if ($line -match '(?i)^Interface\s+Role\s+Sts') {
            $captureInterfaces = $true
            continue
        }

        if ($captureInterfaces) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line -match '^-{2,}') { continue }
            $parts = $line -split '\s+', 6
            if ($parts.Count -ge 2) {
                if (-not $firstInterface) { $firstInterface = $parts[0] }
                if (-not $firstRole)      { $firstRole      = $parts[1] }
            }
        }
    }

    if ($current -ne '') {
        [void]$entries.Add([PSCustomObject]@{
            VLAN       = $current
            RootSwitch = $rootSwitch
            RootPort   = $rootPort
            Role       = $firstRole
            Upstream   = $firstInterface
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

    if ($Global:StateTraceDebug) {
        Write-Host "[DEBUG] Parsing file '$FilePath'" -ForegroundColor Yellow
    }

    try {
        $projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    } catch {
        $projectRoot = (Split-Path -Parent $PSScriptRoot)
    }

    $historyKey = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
    if ([string]::IsNullOrWhiteSpace($historyKey)) { $historyKey = 'UnknownHost' }
    $siteKey = $historyKey
    try {
        $siteKey = DeviceRepositoryModule\Get-SiteFromHostname -Hostname $historyKey -FallbackLength 4
    } catch { }
    if ([string]::IsNullOrWhiteSpace($siteKey)) { $siteKey = 'Unknown' }
    $sanitizedSiteKey = ($siteKey -replace '[^A-Za-z0-9_-]', '_')

    $historyRoot = Join-Path $projectRoot 'Data\IngestionHistory'
    try { [System.IO.Directory]::CreateDirectory($historyRoot) | Out-Null } catch { }
    $historyFilePath = Join-Path $historyRoot ("{0}.json" -f $sanitizedSiteKey)
    $historyMutexName = "StateTraceHistory_{0}" -f $sanitizedSiteKey

    $fileInfo = $null
    $fileHash = $null
    $sourceLength = 0
    $sourceTimestampUtc = $null
    try {
        $fileInfo = Get-Item -LiteralPath $FilePath -ErrorAction Stop
        $sourceLength = [long]$fileInfo.Length
        $sourceTimestampUtc = $fileInfo.LastWriteTimeUtc
        try { $fileHash = Get-FileHashHex -FilePath $FilePath } catch { $fileHash = $null }
    } catch {
        Write-Warning ("Failed to read file details for {0}: {1}" -f $FilePath, $_.Exception.Message)
    }

    $historyContext = [PSCustomObject]@{
        Key = $historyKey
        SiteKey = $siteKey
        SanitizedSiteKey = $sanitizedSiteKey
        FilePath = $historyFilePath
        MutexName = $historyMutexName
        FileHash = $fileHash
        SourceLength = $sourceLength
        SourceTimestampUtc = $sourceTimestampUtc
    }

    $skipProcessing = $false
    if ($fileHash) {
        $historyMutex = $null
        try {
            $historyMutex = New-Object System.Threading.Mutex($false, $historyMutexName)
            $null = $historyMutex.WaitOne()

            $historyRecords = @()
            if (Test-Path -LiteralPath $historyFilePath) {
                try {
                    $rawHistory = Get-Content -LiteralPath $historyFilePath -Raw
                    if (-not [string]::IsNullOrWhiteSpace($rawHistory)) {
                        $parsed = $rawHistory | ConvertFrom-Json
                        if ($parsed) {
                            if ($parsed -is [System.Array]) { $historyRecords = @($parsed) }
                            else { $historyRecords = @($parsed) }
                        }
                    }
                } catch { $historyRecords = @() }
            }

            foreach ($record in $historyRecords) {
                if ($record.Hostname -eq $historyKey -and $record.FileHash -eq $fileHash -and ([long]$record.SourceLength -eq $sourceLength)) {
                    $skipProcessing = $true
                    break
                }
            }
        } finally {
            if ($historyMutex) { try { $historyMutex.ReleaseMutex() } catch { } ; $historyMutex.Dispose() }
        }
    }

    if ($skipProcessing) {
        if ($Global:StateTraceDebug) {
            Write-Host "[DEBUG] Skipping '$historyKey' because log hash matches previous ingestion" -ForegroundColor Yellow
        }
        return
    }

    $logContext = Get-DeviceLogContext -FilePath $FilePath
    $lines = $logContext.Lines
    $blocks = if ($logContext.Blocks) { $logContext.Blocks } else { @{} }
    $logContext = $null

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
            }}
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
            $dbCreateMutex.Dispose()}
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
    $ingestionSucceeded = $false
    if ($DatabasePath) {
        if ($Global:StateTraceDebug) {
            Write-Host "[DEBUG] Writing results for host '$cleanHostname' to database at '$DatabasePath'" -ForegroundColor Yellow
        }
        try {
            # Capture the current run time for historical records.  Format it
            $runDateString = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            # The summary and interface SQL statements will be constructed by helper functions.  No per‑field escaping is required here.

            #-------------------------------------------------------------------------
            $templates = @()
            try {
                $vendor = 'Cisco'
                if ($facts.Make) {
                    if ($facts.Make -match '(?i)brocade') { $vendor = 'Brocade' }
                    elseif ($facts.Make -match '(?i)arista') { $vendor = 'Brocade' }
                }
                $tplDir = Join-Path $PSScriptRoot '..\Templates'
                $templates = Get-VendorTemplates -Vendor $vendor -TemplatesRoot $tplDir
            } catch {
                # Ignore template load errors; compliance info will remain default
            }

            #---------------------------------------------------------------------
            $databaseKey = Get-CanonicalDatabaseKey -DatabasePath $DatabasePath
            $mutexName = Get-DatabaseMutexName -DatabasePath $DatabasePath
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
                $providerErrors = [System.Collections.Generic.List[object]]::new()
                if ($Global:StateTraceDebug) {
                    Write-Host "[DEBUG] Detecting available OLEDB provider for database" -ForegroundColor Yellow
                }
                if ($databaseKey -and $script:DbProviderCache.ContainsKey($databaseKey)) {
                    $__dbProvider = $script:DbProviderCache[$databaseKey]
                    if ($Global:StateTraceDebug) {
                        Write-Host ("[DEBUG] Reusing cached provider '{0}' for database '{1}'" -f $__dbProvider, $DatabasePath) -ForegroundColor Yellow
                    }
                }
                # Prefer the ACE provider when available; fall back to Jet for .mdb files.
                if (-not $__dbProvider) {
                    foreach ($provCandidate in @('Microsoft.ACE.OLEDB.12.0','Microsoft.Jet.OLEDB.4.0')) {
                        $testConn = $null
                        try {
                            $testConn = New-Object -ComObject ADODB.Connection
                            $testConn.Open("Provider=$provCandidate;Data Source=$DatabasePath")
                            $testConn.Close()
                            $__dbProvider = $provCandidate
                            if ($Global:StateTraceDebug) {
                                Write-Host ("[DEBUG] Provider '{0}' validated for database '{1}'" -f $__dbProvider, $DatabasePath) -ForegroundColor Yellow
                            }
                            break
                        } catch {
                            $errorMessage = $_.Exception.Message
                            $hresult = $null
                            try { $hresult = ('0x{0:X8}' -f $_.Exception.HResult) } catch { }
                            $providerErrors.Add([PSCustomObject]@{
                                Provider = $provCandidate
                                Message  = $errorMessage
                                HResult  = $hresult
                            })
                            if ($Global:StateTraceDebug) {
                                Write-Host ("[DEBUG] Provider '{0}' test failed: {1}" -f $provCandidate, $errorMessage) -ForegroundColor Yellow
                            }
                        } finally {
                            if ($testConn) {
                                try { $testConn.Close() } catch { }
                                try { [System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($testConn) | Out-Null } catch { }
                            }
                        }
                    }
                }

                if (-not $__dbProvider) {
                    $candidateList = 'Microsoft.ACE.OLEDB.12.0, Microsoft.Jet.OLEDB.4.0'
                    $detailText = 'No provider-specific diagnostics were captured.'
                    if ($providerErrors.Count -gt 0) {
                        $detailLines = foreach ($entry in $providerErrors) {
                            $hrNote = if ($entry.HResult) { " (HRESULT=$($entry.HResult))" } else { '' }
                            "- Provider '{0}': {1}{2}" -f $entry.Provider, $entry.Message, $hrNote
                        }
                        $detailText = [string]::Join([System.Environment]::NewLine, $detailLines)
                    }
                    throw "Failed to open Access database '$DatabasePath'. Tried providers: $candidateList.`n$detailText"
                }

                if ($__dbProvider -and $databaseKey) {
                    $script:DbProviderCache[$databaseKey] = $__dbProvider
                }
                $__dbConn = New-Object -ComObject ADODB.Connection
                if ($Global:StateTraceDebug) {
                    Write-Host "[DEBUG] Opening DB connection to '$DatabasePath' using provider '$__dbProvider'" -ForegroundColor Yellow
                }
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
                        $ingestionSucceeded = $true
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

    if ($ingestionSucceeded -and $historyContext -and $historyContext.FileHash) {
        $historyMutex = $null
        try {
            $historyMutex = New-Object System.Threading.Mutex($false, $historyContext.MutexName)
            $null = $historyMutex.WaitOne()

            $historyRecords = @()
            if (Test-Path -LiteralPath $historyContext.FilePath) {
                try {
                    $rawHistory = Get-Content -LiteralPath $historyContext.FilePath -Raw
                    if (-not [string]::IsNullOrWhiteSpace($rawHistory)) {
                        $parsed = $rawHistory | ConvertFrom-Json
                        if ($parsed) {
                            if ($parsed -is [System.Array]) { $historyRecords = @($parsed) }
                            else { $historyRecords = @($parsed) }
                        }
                    }
                } catch { $historyRecords = @() }
            }

            $updated = New-Object 'System.Collections.Generic.List[object]'
            foreach ($record in $historyRecords) {
                if ($record.Hostname -ne $historyContext.Key) { [void]$updated.Add($record) }
            }
            $sourceStamp = ''
            if ($historyContext.SourceTimestampUtc) {
                try { $sourceStamp = ([DateTime]$historyContext.SourceTimestampUtc).ToUniversalTime().ToString('o') } catch { $sourceStamp = '' }
            }
            $updated.Add([PSCustomObject]@{
                Hostname = $historyContext.Key
                ActualHostname = $cleanHostname
                Site = $historyContext.SiteKey
                FileHash = $historyContext.FileHash
                SourceLength = $historyContext.SourceLength
                SourceTimestampUtc = $sourceStamp
                LastIngestedUtc = (Get-Date).ToUniversalTime().ToString('o')
            }) | Out-Null
            $json = $updated | ConvertTo-Json -Depth 4
            $json | Set-Content -LiteralPath $historyContext.FilePath -Encoding UTF8
        } catch {
            Write-Warning "Failed to update ingestion history for ${cleanHostname}: $($_.Exception.Message)"
        } finally {
            if ($historyMutex) { try { $historyMutex.ReleaseMutex() } catch { } ; $historyMutex.Dispose() }
        }
    }

    Remove-OldArchiveFolder -DeviceArchivePath $devicePath -RetentionDays 30
}

#



Export-ModuleMember -Function Get-LocationDetails, Get-ShowCommandBlocks, Get-DeviceMakeFromBlocks, Get-SnmpLocationFromLines, ConvertFrom-SpanningTree, Remove-OldArchiveFolder, Get-BrocadeAuthBlockFromLines, Invoke-DeviceLogParsing, Get-LogParseContext, Get-VendorTemplates, Get-DatabaseMutexName









