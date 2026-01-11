Set-StrictMode -Version Latest

if (-not (Get-Variable -Name StateTraceDebug -Scope Global -ErrorAction SilentlyContinue)) {
    Set-Variable -Scope Global -Name StateTraceDebug -Value $false -Option None
}
try {
    TelemetryModule\Initialize-StateTraceDebug
} catch { }
if (-not (Get-Variable -Name DbProviderCache -Scope Script -ErrorAction SilentlyContinue)) {
    $script:DbProviderCache = [System.Collections.Concurrent.ConcurrentDictionary[string,string]]::new([System.StringComparer]::OrdinalIgnoreCase)
}

# Cache database connections per runspace to avoid repeated opens.
if (-not (Get-Variable -Name ConnectionCache -Scope Script -ErrorAction SilentlyContinue)) {

    $script:ConnectionCache = [hashtable]::Synchronized(@{})

}

if (-not (Get-Variable -Name ConnectionCacheTtlMinutes -Scope Script -ErrorAction SilentlyContinue)) {

    $script:ConnectionCacheTtlMinutes = 5

}
if (-not (Get-Variable -Name ConnectionCacheShutdownRegistered -Scope Script -ErrorAction SilentlyContinue)) {
    $script:ConnectionCacheShutdownRegistered = $false
}

if (-not (Get-Variable -Name TemplatesModuleImportWarned -Scope Script -ErrorAction SilentlyContinue)) {
    $script:TemplatesModuleImportWarned = $false
}

function script:Get-QualifiedOrFallbackCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$QualifiedName,
        [string]$FallbackName
    )

    $cmd = $null
    try { $cmd = Get-Command -Name $QualifiedName -ErrorAction SilentlyContinue } catch { $cmd = $null }
    if (-not $cmd -and -not [string]::IsNullOrWhiteSpace($FallbackName)) {
        try { $cmd = Get-Command -Name $FallbackName -ErrorAction SilentlyContinue } catch { $cmd = $null }
    }
    return $cmd
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
        $tokensList = [System.Collections.Generic.List[string]]::new()
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



function New-ShowBlockState {
    $state = [PSCustomObject]@{
        Blocks     = @{}
        CurrentCmd = ''
        Buffer     = [System.Collections.Generic.List[string]]::new()
        Recording  = $false
    }
    return $state
}

# Precompile prompt regexes used when carving show command blocks to avoid
# repeated parsing of the same patterns on every line.
if (-not (Get-Variable -Name ShowPromptWithCommandRegex -Scope Script -ErrorAction SilentlyContinue)) {
    # Allow prompts with or without host tokens (e.g., "switch# show ..." or "# show ...").
    $script:ShowPromptWithCommandRegex = [regex]::new(
        '^\s*[^\s]*[>#]\s*(?:do\s+)?(show\s+.+)$',
        ([System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Compiled)
    )
}
if (-not (Get-Variable -Name ShowPromptStartRegex -Scope Script -ErrorAction SilentlyContinue)) {
    $script:ShowPromptStartRegex = [regex]::new(
        '^\s*[^\s]*[>#]',
        ([System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Compiled)
    )
}

# Cache compiled regex instances used across parsing helpers to avoid per-host recompilation.
if (-not (Get-Variable -Name DeviceLogParserRegexCache -Scope Script -ErrorAction SilentlyContinue)) {
    $script:DeviceLogParserRegexCache = [System.Collections.Concurrent.ConcurrentDictionary[string,System.Text.RegularExpressions.Regex]]::new([System.StringComparer]::Ordinal)
}
if (-not (Get-Variable -Name RegexCacheKeySeparator -Scope Script -ErrorAction SilentlyContinue)) {
    $script:RegexCacheKeySeparator = [char]0x1F
}

# Fast-path character array for prompt token detection - avoids regex for non-prompt lines
if (-not (Get-Variable -Name PromptTokenChars -Scope Script -ErrorAction SilentlyContinue)) {
    $script:PromptTokenChars = [char[]]@('#', '>')
}

function script:Test-MayBePromptLine {
    <#
    .SYNOPSIS
        Fast check to determine if a line could possibly be a prompt line.
        Returns $false for lines that definitely cannot match prompt regexes,
        allowing callers to skip expensive regex evaluation.
    #>
    param([string]$Line)
    if ([string]::IsNullOrEmpty($Line)) { return $false }
    return ($Line.IndexOfAny($script:PromptTokenChars) -ge 0)
}

function script:Get-CachedRegex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Pattern,
        [System.Text.RegularExpressions.RegexOptions]$Options = ([System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Compiled)
    )

    if ([string]::IsNullOrWhiteSpace($Pattern)) { return $null }

    $key = "$([int]$Options)$($script:RegexCacheKeySeparator)$Pattern"
    $cached = $null
    if ($script:DeviceLogParserRegexCache.TryGetValue($key, [ref]$cached)) {
        return $cached
    }

    $regex = [regex]::new($Pattern, $Options)
    $script:DeviceLogParserRegexCache[$key] = $regex
    return $regex
}

if (-not (Get-Variable -Name BrocadeAuthBlockRegex -Scope Script -ErrorAction SilentlyContinue)) {
    $script:BrocadeAuthBlockRegex = [regex]::new(
        '^\s*(?:auth-?default-?vlan\s*\d+|re-?authentication|dot1x\s+enable(?:\s+ethe.+)?|dot1x\s+port-?control\s+auto(?:\s+ethe.+)?|mac-?authentication\s+enable(?:\s+ethe.+)?|mac-?authentication\s+dot1x\s+override)\s*$',
        ([System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Compiled)
    )
}

function Update-ShowBlockState {
    param(
        [psobject]$State,
        [string]$Line
    )

    if (-not $State) { return }

    $lineText = if ($null -ne $Line) { [string]$Line } else { '' }

    # Fast-path: skip regex work for lines that cannot possibly be prompts
    if (script:Test-MayBePromptLine -Line $lineText) {
        # Match a prompt followed by a show command.  Accept both '#' and '>'
        $promptMatch = $script:ShowPromptWithCommandRegex.Match($lineText)
        if ($promptMatch.Success) {
            if ($State.Recording -and $State.CurrentCmd) {
                $State.Blocks[$State.CurrentCmd] = $State.Buffer
            }
            $State.CurrentCmd = $promptMatch.Groups[1].Value.Trim().ToLowerInvariant()
            $State.Buffer     = [System.Collections.Generic.List[string]]::new()
            $State.Recording  = $true
            return
        }

        # Detect the start of the next prompt which signals the end of the current block
        if ($State.Recording -and $script:ShowPromptStartRegex.IsMatch($lineText)) {
            $State.Blocks[$State.CurrentCmd] = $State.Buffer
            $State.CurrentCmd = ''
            $State.Buffer     = [System.Collections.Generic.List[string]]::new()
            $State.Recording  = $false
            return
        }
    }

    # Append lines to the current buffer if we are within a block
    if ($State.Recording) {
        [void]$State.Buffer.Add($lineText)
    }
}

function Complete-ShowBlockState {
    param([psobject]$State)

    if (-not $State) { return @{} }
    if ($State.Recording -and $State.CurrentCmd) {
        $State.Blocks[$State.CurrentCmd] = $State.Buffer
    }
    return $State.Blocks
}

function Get-ShowCommandBlocks {
    [CmdletBinding()]
    param(
        [string[]]$Lines
    )

    $state = New-ShowBlockState
    foreach ($line in $Lines) {
        Update-ShowBlockState -State $state -Line $line
    }
    return (Complete-ShowBlockState -State $state)
}

function Get-ShowBlock {
    [CmdletBinding()]
    param(
        [hashtable]$Blocks,
        [string[]]$PreferredKeys = @(),
        [string[]]$RegexPatterns = @(),
        [string[]]$Lines,
        [string[]]$CommandRegexes = @(),
        [string[]]$DefaultValue = @()
    )

    if (-not $Blocks) { $Blocks = @{} }

    foreach ($key in $PreferredKeys) {
        if ($Blocks.ContainsKey($key)) { return ,@($Blocks[$key]) }
    }

    $compiledRegexPatterns = [System.Collections.Generic.List[regex]]::new()
    if ($RegexPatterns -and $RegexPatterns.Count -gt 0) {
        foreach ($pattern in $RegexPatterns) {
            if ([string]::IsNullOrWhiteSpace($pattern)) { continue }
            try {
                $re = script:Get-CachedRegex -Pattern $pattern
                if ($re) { [void]$compiledRegexPatterns.Add($re) }
            } catch { }
        }
    }

    if ($Blocks.Count -gt 0 -and $compiledRegexPatterns.Count -gt 0) {
        foreach ($re in $compiledRegexPatterns) {
            foreach ($key in $Blocks.Keys) {
                if ($re.IsMatch($key)) { return ,@($Blocks[$key]) }
            }
        }
    }

    # Fallback: derive the block directly from raw lines when a regex matches a command
    $compiledCommandRegexes = [System.Collections.Generic.List[regex]]::new()
    if ($CommandRegexes -and $CommandRegexes.Count -gt 0) {
        foreach ($pattern in $CommandRegexes) {
            if ([string]::IsNullOrWhiteSpace($pattern)) { continue }
            try {
                $re = script:Get-CachedRegex -Pattern $pattern
                if ($re) { [void]$compiledCommandRegexes.Add($re) }
            } catch { }
        }
    }

    if ($Lines -and $compiledCommandRegexes.Count -gt 0) {
        foreach ($regex in $compiledCommandRegexes) {
            $startIndex = -1
            for ($i = 0; $i -lt $Lines.Count; $i++) {
                if ($regex.IsMatch($Lines[$i])) { $startIndex = $i; break }
            }
            if ($startIndex -lt 0) { continue }

            $buffer = [System.Collections.Generic.List[string]]::new()
            for ($j = $startIndex + 1; $j -lt $Lines.Count; $j++) {
                $line = $Lines[$j]
                # Fast-path: skip regex if line cannot be a prompt
                if ((script:Test-MayBePromptLine -Line $line) -and $script:ShowPromptStartRegex.IsMatch($line)) { break }
                [void]$buffer.Add($line)
            }
            return ,$buffer.ToArray()
        }
    }

    if ($null -eq $DefaultValue) { $DefaultValue = @() }
    return ,$DefaultValue
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

function Resolve-DatabaseWriteBreakdownCacheProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Payload,
        [string]$ExistingRowSource,
        [object]$Telemetry
    )

    if (-not $Payload) { return }
    $sourceCandidate = $ExistingRowSource
    if ([string]::IsNullOrWhiteSpace($sourceCandidate) -and $Telemetry) {
        try {
            if ($Telemetry.PSObject.Properties.Name -contains 'SiteCacheExistingRowSource') {
                $sourceCandidate = '' + $Telemetry.SiteCacheExistingRowSource
            }
        } catch {
            $sourceCandidate = $null
        }
    }
    if ([string]::IsNullOrWhiteSpace($sourceCandidate)) { return }

    $normalizedSource = $sourceCandidate.Trim()
    if ([string]::Equals($normalizedSource, 'SiteExistingCache', [System.StringComparison]::OrdinalIgnoreCase)) {
        $Payload['SiteCacheProvider'] = 'Cache'
        $Payload['SiteCacheProviderReason'] = 'SiteExistingCache'
        $Payload['SiteCacheExistingRowSource'] = 'SiteExistingCache'

        $currentStatus = $null
        if ($Payload.ContainsKey('SiteCacheFetchStatus')) {
            $currentStatus = '' + $Payload['SiteCacheFetchStatus']
        } elseif ($Telemetry -and $Telemetry.PSObject.Properties.Name -contains 'SiteCacheFetchStatus') {
            $currentStatus = '' + $Telemetry.SiteCacheFetchStatus
        }

        if ([string]::IsNullOrWhiteSpace($currentStatus) -or -not [string]::Equals($currentStatus, 'Hit', [System.StringComparison]::OrdinalIgnoreCase)) {
            $Payload['SiteCacheFetchStatus'] = 'Hit'
        }
    }
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

function Close-StaleConnections {

    [CmdletBinding()]

    param()



    $ttlMinutes = 5

    try { if ($script:ConnectionCacheTtlMinutes -ne $null) { $ttlMinutes = [int]$script:ConnectionCacheTtlMinutes } } catch { $ttlMinutes = 5 }

    if ($ttlMinutes -lt 0) { return }



    $now = [DateTime]::UtcNow

    $toRemove = [System.Collections.Generic.List[string]]::new()

    foreach ($key in @($script:ConnectionCache.Keys)) {

        $entry = $script:ConnectionCache[$key]

        if (-not $entry) { continue }

        if ($entry.RefCount -gt 0) { continue }

        $last = $entry.LastUsedUtc

        if (-not $last) { $last = [DateTime]::MinValue }

        $elapsedMinutes = ($now - $last).TotalMinutes

        if ($entry.Connection -and ($ttlMinutes -eq 0 -or $elapsedMinutes -ge $ttlMinutes)) {

            $connectionToRelease = $entry.Connection
            try { $connectionToRelease.Close() } catch {
                Write-Warning ("Failed to close cached database connection for key '{0}': {1}" -f $key, $_.Exception.Message)
            }
            TelemetryModule\Remove-ComObjectSafe -ComObject $connectionToRelease
            $entry.Connection = $null

        }

        if (-not $entry.Connection -and $entry.RefCount -eq 0) {

            $toRemove.Add($key) | Out-Null

        }

    }



    foreach ($key in $toRemove) {

        $null = $script:ConnectionCache.Remove($key)

    }

}

function Clear-ConnectionCache {
    [CmdletBinding()]
    param(
        [switch]$Force
    )

    if (-not $script:ConnectionCache) { return }

    foreach ($key in @($script:ConnectionCache.Keys)) {
        $entry = $script:ConnectionCache[$key]
        if (-not $entry) { continue }

        if ($entry.RefCount -gt 0 -and -not $Force) { continue }

        if ($entry.Connection) {
            $connectionToRelease = $entry.Connection
            try { $connectionToRelease.Close() } catch {
                Write-Warning ("Failed to close cached database connection for key '{0}': {1}" -f $key, $_.Exception.Message)
            }
            try {
                TelemetryModule\Remove-ComObjectSafe -ComObject $connectionToRelease
            } catch {
                Write-Warning ("Failed to release cached database connection for key '{0}': {1}" -f $key, $_.Exception.Message)
            }
            $entry.Connection = $null
        }

        if ($entry.RefCount -le 0 -or $Force) {
            $null = $script:ConnectionCache.Remove($key)
        }
    }
}

if (-not $script:ConnectionCacheShutdownRegistered) {
    try {
        $null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
            try {
                $cleanup = Get-Command -Name 'DeviceLogParserModule\Clear-ConnectionCache' -ErrorAction SilentlyContinue
                if ($cleanup) { & $cleanup -Force }
            } catch { }
        }
        $script:ConnectionCacheShutdownRegistered = $true
    } catch {
        Write-Verbose ("[DeviceLogParserModule] Failed to register connection cache shutdown hook: {0}" -f $_.Exception.Message)
    }
}



function Invoke-ProviderProbe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [Parameter(Mandatory)][string]$Provider,
        [ScriptBlock]$ConnectionFactory,
        [ScriptBlock]$ReleaseAction
    )

    # LANDMARK: Provider probe cleanup - guard close/release and report status
    $factory = if ($ConnectionFactory) { $ConnectionFactory } else { { New-Object -ComObject ADODB.Connection } }
    $release = if ($ReleaseAction) { $ReleaseAction } else { { param($conn) TelemetryModule\Remove-ComObjectSafe -ComObject $conn } }

    $connection = $null
    $opened = $false
    $status = 'ProbeFailed'
    $message = $null

    try {
        $connection = & $factory
        if (-not $connection) { throw "Connection factory returned null." }
        try {
            $connection.Open("Provider=$Provider;Data Source=$DatabasePath;Mode=ReadWrite;Jet OLEDB:Database Locking Mode=1")
            $opened = $true
            $status = 'Available'
        } catch {
            $status = 'MissingProvider'
            $message = $_.Exception.Message
        }
    } catch {
        $status = 'ProbeFailed'
        $message = $_.Exception.Message
    } finally {
        if ($connection) {
            if ($opened) {
                $shouldClose = $false
                try {
                    if ($connection.PSObject.Properties.Name -contains 'State') {
                        $shouldClose = ($connection.State -eq 1)
                    } else {
                        $shouldClose = $true
                    }
                } catch {
                    $shouldClose = $true
                }

                if ($shouldClose) {
                    try { $connection.Close() } catch {
                        Write-Verbose ("Failed to close provider probe connection for '{0}' ({1}): {2}" -f $DatabasePath, $Provider, $_.Exception.Message)
                    }
                }
            }

            try { & $release $connection } catch {
                Write-Verbose ("Failed to release provider probe connection for '{0}' ({1}): {2}" -f $DatabasePath, $Provider, $_.Exception.Message)
            }
        }
    }

    return [PSCustomObject]@{
        Status   = $status
        Provider = $Provider
        Message  = $message
    }
}

function Get-CachedDbConnection {

    [CmdletBinding()]

    param(

        [Parameter(Mandatory)][string]$DatabasePath,

        [string[]]$ProviderCandidates = @('Microsoft.ACE.OLEDB.16.0','Microsoft.ACE.OLEDB.12.0','Microsoft.Jet.OLEDB.4.0')

    )



    Close-StaleConnections



    $key = Get-CanonicalDatabaseKey -DatabasePath $DatabasePath

    if ([string]::IsNullOrWhiteSpace($key)) { throw "Invalid database path '$DatabasePath'" }



    if (-not $script:ConnectionCache.ContainsKey($key)) {

        $script:ConnectionCache[$key] = [PSCustomObject]@{

            Connection   = $null

            Provider     = $null

            RefCount     = 0

            LastUsedUtc  = [DateTime]::MinValue

        }

    }



    $entry = $script:ConnectionCache[$key]

    if ($entry.Connection -and $entry.Connection.State -ne 1) {

        $connectionToRelease = $entry.Connection
        try { $connectionToRelease.Close() } catch {
            Write-Warning ("Failed to close cached database connection for key '{0}': {1}" -f $key, $_.Exception.Message)
        }
        TelemetryModule\Remove-ComObjectSafe -ComObject $connectionToRelease
        $entry.Connection = $null

    }



    $provider = $entry.Provider

    if (-not $provider -and $script:DbProviderCache.ContainsKey($key)) {

        $provider = $script:DbProviderCache[$key]

    }



    if (-not $entry.Connection) {

        $errors = [System.Collections.Generic.List[string]]::new()

        if (-not $provider) {

            foreach ($provCandidate in $ProviderCandidates) {

                $probeResult = Invoke-ProviderProbe -DatabasePath $DatabasePath -Provider $provCandidate

                if ($probeResult.Status -eq 'Available') {
                    $provider = $provCandidate
                    break
                }

                $detail = if ([string]::IsNullOrWhiteSpace($probeResult.Message)) { 'No additional detail.' } else { $probeResult.Message }
                $errors.Add(("- Provider '{0}': {1} - {2}" -f $provCandidate, $probeResult.Status, $detail)) | Out-Null
                $provider = $null

            }

        }



        if (-not $provider) {

            $detail = if ($errors.Count -gt 0) { $errors -join "`n" } else { 'No providers succeeded.' }

            throw "Failed to open Access database '$DatabasePath'. Tried providers:`n$detail"

        }



        $entry.Connection = New-Object -ComObject ADODB.Connection

        $entry.Connection.Open("Provider=$provider;Data Source=$DatabasePath;Mode=ReadWrite;Jet OLEDB:Database Locking Mode=1")

        try {

            $prop = $entry.Connection.Properties.Item('Jet OLEDB:Transaction Commit Mode')

            if ($prop) { $prop.Value = 1 }

        } catch { }

        $entry.Provider = $provider

        $script:DbProviderCache[$key] = $provider

    }



    $entry.RefCount++

    $entry.LastUsedUtc = [DateTime]::UtcNow



    return [PSCustomObject]@{ Connection = $entry.Connection; Key = $key; Provider = $entry.Provider }

}



function Release-CachedDbConnection {

    [CmdletBinding()]

    param(

        [Parameter(Mandatory)][object]$Lease,

        [switch]$ForceRemove

    )



    if (-not $Lease) { return }

    $key = $Lease.Key

    if (-not $key) { return }

    if (-not $script:ConnectionCache.ContainsKey($key)) { return }

    $entry = $script:ConnectionCache[$key]

    if ($entry.RefCount -gt 0) { $entry.RefCount-- }

    $entry.LastUsedUtc = [DateTime]::UtcNow



    if ($ForceRemove -and $entry.Connection) {

        $connectionToRelease = $entry.Connection
        try { $connectionToRelease.Close() } catch {
            Write-Warning ("Failed to close cached database connection for key '{0}': {1}" -f $key, $_.Exception.Message)
        }
        TelemetryModule\Remove-ComObjectSafe -ComObject $connectionToRelease
        $entry.Connection = $null

    }



    Close-StaleConnections

}



function Get-DeviceLogContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath
    )

    $linesList = [System.Collections.Generic.List[string]]::new()
    $blockState = New-ShowBlockState
    $reader = $null
    try {
        $reader = [System.IO.StreamReader]::new($FilePath)
        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            [void]$linesList.Add($line)
            Update-ShowBlockState -State $blockState -Line $line
        }
    } finally {
        if ($reader) { $reader.Dispose() }
    }

    $lineArray = $linesList.ToArray()
    $blocks = Complete-ShowBlockState -State $blockState
    return [PSCustomObject]@{
        Lines  = $lineArray
        Blocks = $blocks
    }
}
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

    $vendorKey = ('' + $Vendor).Trim()
    if ([string]::IsNullOrWhiteSpace($vendorKey)) { return @() }

    $resolvedTemplatesPath = $TemplatesRoot
    if (-not $resolvedTemplatesPath) {
        $resolvedTemplatesPath = Join-Path $PSScriptRoot '..\Templates'
    }

    try {
        $templateCmd = script:Get-QualifiedOrFallbackCommand -QualifiedName 'TemplatesModule\Get-ConfigurationTemplateData'
        if (-not $templateCmd) {
            $templatesModulePath = Join-Path $PSScriptRoot 'TemplatesModule.psm1'
            if (Test-Path -LiteralPath $templatesModulePath) {
                try {
                    Import-Module -Name $templatesModulePath -Force -Global -ErrorAction Stop | Out-Null
                } catch {
                    if (-not $script:TemplatesModuleImportWarned) {
                        $script:TemplatesModuleImportWarned = $true
                        Write-Warning ("[DeviceLogParser] Failed to import TemplatesModule from '{0}': {1}" -f $templatesModulePath, $_.Exception.Message)
                    }
                }
            } elseif (-not $script:TemplatesModuleImportWarned) {
                $script:TemplatesModuleImportWarned = $true
                Write-Warning ("[DeviceLogParser] TemplatesModule not found at '{0}'; vendor templates unavailable." -f $templatesModulePath)
            }
            $templateCmd = script:Get-QualifiedOrFallbackCommand -QualifiedName 'TemplatesModule\Get-ConfigurationTemplateData'
        }
        if (-not $templateCmd -and -not $script:TemplatesModuleImportWarned) {
            $script:TemplatesModuleImportWarned = $true
            Write-Warning "[DeviceLogParser] TemplatesModule command unavailable; vendor templates may be missing."
        }

        $entry = $null
        if ($templateCmd) {
            $entry = & $templateCmd -Vendor $vendorKey -TemplatesPath $resolvedTemplatesPath
        }

        if ($entry -and $entry.Templates) {
            return $entry.Templates
        }
    } catch {
    }

    return @()
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

    $entries = [System.Collections.Generic.List[object]]::new()
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
            continue
        }

        if ($line -match '^Port\s+\d+\s+\(([^)]+)\).+?\s+is\s+([A-Za-z]+(?:\s+[A-Za-z]+)?)') {
            $ifaceName = $matches[1]
            $rolePhrase = $matches[2].Trim().ToLowerInvariant()
            if (-not $firstInterface) { $firstInterface = $ifaceName }
            if (-not $firstRole) {
                switch ($rolePhrase) {
                    'designated forwarding' { $firstRole = 'Desg FWD'; break }
                    'root forwarding'       { $firstRole = 'Root FWD'; break }
                    'backup blocking'       { $firstRole = 'Back BLK'; break }
                    'alternate blocking'    { $firstRole = 'Altn BLK'; break }
                    default                 { $firstRole = $rolePhrase }
                }
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
        [string]$ArchiveRoot,
        [int]$RetentionDays = 30
    )
    if ([string]::IsNullOrWhiteSpace($DeviceArchivePath)) { return }

    $resolvedDevicePath = $null
    $resolvedArchiveRoot = $null
    try { $resolvedDevicePath = [System.IO.Path]::GetFullPath($DeviceArchivePath) } catch { $resolvedDevicePath = $null }
    if ($ArchiveRoot) {
        try { $resolvedArchiveRoot = [System.IO.Path]::GetFullPath($ArchiveRoot) } catch { $resolvedArchiveRoot = $null }
    }

    if ($resolvedDevicePath) {
        $pathRoot = $null
        try { $pathRoot = [System.IO.Path]::GetPathRoot($resolvedDevicePath) } catch { $pathRoot = $null }
        if ($pathRoot -and [System.StringComparer]::OrdinalIgnoreCase.Equals($resolvedDevicePath.TrimEnd('\'), $pathRoot.TrimEnd('\'))) {
            Write-Warning ("Archive cleanup skipped for root path '{0}'." -f $resolvedDevicePath)
            return
        }
        if ($resolvedArchiveRoot) {
            $rootNormalized = $resolvedArchiveRoot.TrimEnd('\')
            $deviceNormalized = $resolvedDevicePath.TrimEnd('\')
            if (-not $deviceNormalized.StartsWith($rootNormalized, [System.StringComparison]::OrdinalIgnoreCase)) {
                Write-Warning ("Archive cleanup skipped because '{0}' is outside '{1}'." -f $resolvedDevicePath, $resolvedArchiveRoot)
                return
            }
            $relative = $deviceNormalized.Substring($rootNormalized.Length).TrimStart('\')
            if ([string]::IsNullOrWhiteSpace($relative)) {
                Write-Warning ("Archive cleanup skipped because device path matches archive root '{0}'." -f $resolvedArchiveRoot)
                return
            }
        }
    }

    # If the archive path does not exist, do nothing.
    if (-not (Test-Path -LiteralPath $DeviceArchivePath)) { return }

    # Precompute the cutoff date once.  Any archive folder with a date older    
    $cutoff = (Get-Date).AddDays(-$RetentionDays)
    foreach ($folder in (Get-ChildItem -LiteralPath $DeviceArchivePath -Directory)) {
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

    $regex = $script:BrocadeAuthBlockRegex
    if (-not $regex) { return @() }

    $seen  = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $found = [System.Collections.Generic.List[string]]::new()
    foreach ($ln in $Lines) {
        if ($regex.IsMatch($ln)) {
            # Normalize whitespace and remove extra spaces
            $norm = ($ln -replace '\s+', ' ').Trim()
            if ($seen.Add($norm)) { [void]$found.Add($norm) }
        }
    }
    return ,$found.ToArray()
}

function Read-IngestionHistoryRecords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return @()
    }

    $records = New-Object System.Collections.Generic.List[object]
    $reader = $null
    try {
        $reader = [System.IO.StreamReader]::new($Path)
        $buffer = New-Object System.Text.StringBuilder
        $inString = $false
        $escape = $false
        $depth = 0

        while (($line = $reader.ReadLine()) -ne $null) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            foreach ($ch in $line.ToCharArray()) {
                $appendChar = $false
                if ($inString) {
                    if ($escape) {
                        $escape = $false
                    } elseif ($ch -eq '\') {
                        $escape = $true
                    } elseif ($ch -eq '"') {
                        $inString = $false
                    }
                    $appendChar = ($depth -gt 0)
                } else {
                    if ($ch -eq '"') {
                        $inString = $true
                        $appendChar = ($depth -gt 0)
                    } elseif ($ch -eq '{') {
                        if ($depth -eq 0) { $null = $buffer.Clear() }
                        $depth++
                        $appendChar = $true
                    } elseif ($ch -eq '}') {
                        if ($depth -gt 0) {
                            $appendChar = $true
                            $depth--
                        }
                    } else {
                        $appendChar = ($depth -gt 0)
                    }
                }

                if ($appendChar) {
                    $null = $buffer.Append($ch)
                }

                if ($depth -eq 0 -and $buffer.Length -gt 0) {
                    $record = $null
                    try {
                        $record = $buffer.ToString() | ConvertFrom-Json -ErrorAction Stop
                    } catch {
                        $record = $null
                    }
                    if ($record) { $records.Add($record) | Out-Null }
                    $null = $buffer.Clear()
                }
            }
            if ($depth -gt 0) { $null = $buffer.AppendLine() }
        }
    } finally {
        if ($reader) { $reader.Dispose() }
    }

    return ,$records.ToArray()
}






function Invoke-DeviceLogParsing {
    param (
        [string]$FilePath,
        [string]$ArchiveRoot,
        [string]$DatabasePath
    )
    $__stParseStart = Get-Date
    $__stParseSw = [System.Diagnostics.Stopwatch]::StartNew()
    $cleanHostname = ''
    $siteCode = ''
    $ingestionSucceeded = $false
    $skippedDuplicate = $false
    $duplicateMetadata = @{}

    if ($Global:StateTraceDebug) {
        Write-Host "[DEBUG] Parsing file '$FilePath'" -ForegroundColor Yellow
    }

    try {
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

    # Default telemetry host/site values from the file name so failures surface
    # meaningful identifiers even when the vendor parser cannot resolve a prompt.
    $cleanHostname = $historyKey
    $siteCode = $siteKey

    $historyRoot = Join-Path $projectRoot 'Data\IngestionHistory'
    try { [System.IO.Directory]::CreateDirectory($historyRoot) | Out-Null } catch {
        Write-Warning ("Failed to create ingestion history directory '{0}': {1}" -f $historyRoot, $_.Exception.Message)
    }
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
    $matchedHistoryRecord = $null
    if ($fileHash) {
        $historyMutex = $null
        try {
            $historyMutex = New-Object System.Threading.Mutex($false, $historyMutexName)
            $null = $historyMutex.WaitOne()

            $historyRecords = @()
            if (Test-Path -LiteralPath $historyFilePath) {
                try {
                    $historyRecords = Read-IngestionHistoryRecords -Path $historyFilePath
                } catch { $historyRecords = @() }
            }

            foreach ($record in $historyRecords) {
                if ($record.Hostname -eq $historyKey -and $record.FileHash -eq $fileHash -and ([long]$record.SourceLength -eq $sourceLength)) {
                    $skipProcessing = $true
                    $matchedHistoryRecord = $record
                    break
                }
            }
        } finally {
            if ($historyMutex) {
                try { $historyMutex.ReleaseMutex() } catch {
                    Write-Warning ("Failed to release ingestion history mutex '{0}': {1}" -f $historyMutexName, $_.Exception.Message)
                }
                $historyMutex.Dispose()
            }
        }
    }

    if ($skipProcessing) {
        # Ensure we do not skip when the per-site database is missing.
        $expectedDbPath = $null
        if ($DatabasePath) {
            try { $expectedDbPath = [System.IO.Path]::GetFullPath($DatabasePath) } catch { $expectedDbPath = $DatabasePath }
        }
        if (-not $expectedDbPath) {
            $dbPathCmd = script:Get-QualifiedOrFallbackCommand -QualifiedName 'DeviceRepositoryModule\Get-DbPathForSite' -FallbackName 'Get-DbPathForSite'
            if ($dbPathCmd) {
                $siteForDb = $null
                if ($matchedHistoryRecord -and $matchedHistoryRecord.PSObject.Properties.Name -contains 'Site' -and -not [string]::IsNullOrWhiteSpace($matchedHistoryRecord.Site)) {
                    $siteForDb = '' + $matchedHistoryRecord.Site
                } elseif (-not [string]::IsNullOrWhiteSpace($historyContext.SiteKey)) {
                    $siteForDb = '' + $historyContext.SiteKey
                }
                if (-not [string]::IsNullOrWhiteSpace($siteForDb)) {
                    try {
                        $candidatePath = & $dbPathCmd -Site $siteForDb
                        if ($candidatePath) { $expectedDbPath = $candidatePath }
                    } catch { }
                }
            }
        }
        $shouldReprocess = $false
        if ($expectedDbPath) {
            try {
                if (-not (Test-Path -LiteralPath $expectedDbPath)) { $shouldReprocess = $true }
            } catch { $shouldReprocess = $true }
        }
        if ($shouldReprocess) {
            $skipProcessing = $false
            if ($Global:StateTraceDebug) {
                Write-Host ("[DEBUG] Reprocessing '{0}' because database '{1}' is missing" -f $historyKey, $expectedDbPath) -ForegroundColor Yellow
            }
        } else {
            if ($Global:StateTraceDebug) {
                Write-Host "[DEBUG] Skipping '$historyKey' because log hash matches previous ingestion" -ForegroundColor Yellow
            }

            $cleanHostname = $historyKey
            if (-not [string]::IsNullOrWhiteSpace($historyContext.SiteKey)) {
                $siteCode = $historyContext.SiteKey
            }

            $skippedDuplicate = $true
            $duplicateMetadata = @{
                Reason       = 'HashMatch'
                FileHash     = $fileHash
                SourceLength = $sourceLength
                Site         = $siteCode
            }

            if ($matchedHistoryRecord -and $matchedHistoryRecord.PSObject.Properties.Name -contains 'LastIngestedUtc' -and -not [string]::IsNullOrWhiteSpace($matchedHistoryRecord.LastIngestedUtc)) {
                $duplicateMetadata['LastIngestedUtc'] = '' + $matchedHistoryRecord.LastIngestedUtc
            }

            try {
                $dupPayload = @{
                    Hostname = $cleanHostname
                    Site     = $siteCode
                    Reason   = 'HashMatch'
                }
                if ($fileHash) { $dupPayload['FileHash'] = $fileHash }
                if ($sourceLength -gt 0) { $dupPayload['SourceLength'] = [long]$sourceLength }
                if ($duplicateMetadata.ContainsKey('LastIngestedUtc')) {
                    $dupPayload['LastIngestedUtc'] = $duplicateMetadata['LastIngestedUtc']
                }
                TelemetryModule\Write-StTelemetryEvent -Name 'SkippedDuplicate' -Payload $dupPayload
            } catch { }

            return
        }
    }

    $logContext = Get-DeviceLogContext -FilePath $FilePath
    $lines = $logContext.Lines
    $blocks = if ($logContext.Blocks) { $logContext.Blocks } else { @{} }
    $logContext = $null

    # Determine the vendor (device make) using only the "show version" output.
    $make = Get-DeviceMakeFromBlocks -Blocks $blocks
    if (-not $make) {
        # Fallback heuristic: scan the entire log for vendor keywords in a
        $foundCisco = $false
        $foundBrocade = $false
        foreach ($ln in $lines) {
            if ([string]::IsNullOrWhiteSpace($ln)) { continue }

            if (-not $foundCisco -and $ln.IndexOf('Cisco', [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $foundCisco = $true
            }
            if (-not $foundBrocade) {
                if ($ln.IndexOf('Brocade', [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                    $ln.IndexOf('IronWare', [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                    $ln.IndexOf('Stackable', [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    $foundBrocade = $true
                }
            }
            if ($ln.IndexOf('Arista', [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $make = 'Arista'
                break
            }
        }

        if (-not $make) {
            if ($foundBrocade) { $make = 'Brocade' }
            elseif ($foundCisco) { $make = 'Cisco' }
        }

        if (-not $make) {
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

    if ([string]::Equals($make, 'Brocade', [System.StringComparison]::OrdinalIgnoreCase)) {
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
    }

    # At this point we have extracted all necessary information from the raw log
    $lines = $null
    $blocks = $null
    try {
        if ($sourceLength -gt 5MB) {
            [System.GC]::Collect([System.GC]::MaxGeneration, [System.GCCollectionMode]::Optimized)
        }
    } catch {
        # Ignore GC exceptions; not all hosts permit explicit collection
    }

    if ($facts) {
        $factsHostname = ''
        try { $factsHostname = '' + $facts.Hostname } catch { $factsHostname = '' }

        if ([string]::IsNullOrWhiteSpace($factsHostname) -and -not [string]::IsNullOrWhiteSpace($historyKey)) {
            $fallbackHostname = ('' + $historyKey).Trim()
            if ($fallbackHostname -match '^(?<Host>.+?)[-_]\d{8}[-_]\d{6}$') {
                $fallbackHostname = ('' + $Matches.Host).Trim()
            }
            $fallbackHostname = $fallbackHostname -replace '^SSH@', ''

            if (-not [string]::IsNullOrWhiteSpace($fallbackHostname)) {
                if ($facts.PSObject.Properties.Name -contains 'Hostname') {
                    $facts.Hostname = $fallbackHostname
                } else {
                    Add-Member -InputObject $facts -NotePropertyName Hostname -NotePropertyValue $fallbackHostname -Force
                }
            }
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
        $providedDbPath = $null
        if ($PSBoundParameters.ContainsKey('DatabasePath') -and $PSBoundParameters['DatabasePath']) {
            $providedDbPath = $PSBoundParameters['DatabasePath']
        }

        if ($providedDbPath) {
            $DatabasePath = $providedDbPath
            $siteDbDir = $null
            try { $siteDbDir = [System.IO.Path]::GetDirectoryName($DatabasePath) } catch { $siteDbDir = $null }
            if ($siteDbDir -and -not (Test-Path -LiteralPath $siteDbDir)) {
                [System.IO.Directory]::CreateDirectory($siteDbDir) | Out-Null
            }
        } else {
            $dataDir = DeviceRepositoryModule\Get-DataDirectoryPath
            if (-not (Test-Path -LiteralPath $dataDir)) {
                [System.IO.Directory]::CreateDirectory($dataDir) | Out-Null
            }

            $DatabasePath = DeviceRepositoryModule\Get-DbPathForSite -Site $siteCode
            $siteDbDir = $null
            try { $siteDbDir = [System.IO.Path]::GetDirectoryName($DatabasePath) } catch { $siteDbDir = $null }
            if ($siteDbDir -and -not (Test-Path -LiteralPath $siteDbDir)) {
                [System.IO.Directory]::CreateDirectory($siteDbDir) | Out-Null
            }
        }

        $createMutexName = "StateTraceDbCreateMutex_${siteCode}"
        $dbCreateMutex = New-Object System.Threading.Mutex($false, $createMutexName)
        try {
            $null = $dbCreateMutex.WaitOne()
            try {
                New-DatabaseIfMissing -Path $DatabasePath
            } catch [System.Management.Automation.CommandNotFoundException] {
                if (-not (Test-Path -LiteralPath $DatabasePath)) {
                    try {
                        New-AccessDatabase -Path $DatabasePath | Out-Null
                    } catch [System.Management.Automation.CommandNotFoundException] {
                    } catch {
                        # Ignore failures caused by concurrent creation.
                    }
                }
            } catch {
                # Swallow errors related to existing database to avoid noisy warnings.
            }
        } finally {
            try { $dbCreateMutex.ReleaseMutex() } catch {
                Write-Warning ("Failed to release database create mutex '{0}': {1}" -f $createMutexName, $_.Exception.Message)
            }
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
        # CSV export disabled - historical data is now stored in the database
    } else {
        # CSV export disabled - historical data is now stored in the database
    }

    # Export spanning tree information if available.  The facts may contain
    if ($facts.PSObject.Properties.Name -contains 'SpanInfo') {
        $spanData = $facts.SpanInfo
        if ($spanData) {
            # Span CSV export disabled - historical data is now stored in the database only
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

    # Summary CSV export disabled - historical data is now stored in the database
    # If a database path was supplied, insert the summary and interface data
    $ingestionSucceeded = $false
    if ($DatabasePath) {
        if ($Global:StateTraceDebug) {
            Write-Host "[DEBUG] Writing results for host '$cleanHostname' to database at '$DatabasePath'" -ForegroundColor Yellow
        }
        try {
            # Capture the current run time for historical records.  Format it
            $runDateString = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            # The summary and interface SQL statements will be constructed by helper functions.  No per-field escaping is required here.

            #-------------------------------------------------------------------------
            $templates = @()
            try {
                $vendor = 'Cisco'
                if ($facts.Make) {
                    if ($facts.Make -match '(?i)brocade') { $vendor = 'Brocade' }
                    elseif ($facts.Make -match '(?i)arista') { $vendor = 'Arista' }
                }
                $tplDir = Join-Path $PSScriptRoot '..\Templates'
                $templates = Get-VendorTemplates -Vendor $vendor -TemplatesRoot $tplDir
            } catch {
                # Ignore template load errors; compliance info will remain default
            }

            #---------------------------------------------------------------------
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

                $connectionLease = $null

                try {

                    $providerCandidates = @('Microsoft.ACE.OLEDB.16.0','Microsoft.ACE.OLEDB.12.0','Microsoft.Jet.OLEDB.4.0')

                    if ($Global:StateTraceDebug) {

                        Write-Host ("[DEBUG] Acquiring database connection for '{0}'" -f $DatabasePath) -ForegroundColor Yellow

                    }

                    $connectionLease = Get-CachedDbConnection -DatabasePath $DatabasePath -ProviderCandidates $providerCandidates

                    $__dbConn = $connectionLease.Connection

                    $__dbProvider = $connectionLease.Provider

                    if ($Global:StateTraceDebug) {

                        Write-Host ("[DEBUG] Using provider '{0}' for database '{1}'" -f $__dbProvider, $DatabasePath) -ForegroundColor Yellow

                    }



                    $__stDbSw = [System.Diagnostics.Stopwatch]::StartNew()
                    $__dbConn.BeginTrans()

                    try {

                        #------------------------------------------------------------------



                        # Persist the parsed data using centralized helpers.  These

                        $summaryCmd = script:Get-QualifiedOrFallbackCommand -QualifiedName 'ParserPersistenceModule\Update-DeviceSummaryInDb' -FallbackName 'Update-DeviceSummaryInDb'

                        if (-not $summaryCmd) { throw "Required parser persistence helper 'Update-DeviceSummaryInDb' is not available. Ensure ParserPersistenceModule.psm1 is imported." }

                        $summaryParams = @{

                            Connection      = $__dbConn

                            Facts           = $facts

                            Hostname        = $cleanHostname

                            SiteCode        = $siteCode

                            LocationDetails = $locDetails

                            RunDateString   = $runDateString

                        }

                        $summaryDurationMs = 0.0
                        $interfaceDurationMs = 0.0
                        $commitDurationMs = 0.0
                        $databaseLatencyMs = 0
                        $refreshDurationMs = 0.0
                        $latestSyncTelemetry = $null

                        $summaryStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                        try {
                            & $summaryCmd @summaryParams
                        } finally {
                            $summaryStopwatch.Stop()
                            $summaryDurationMs = [Math]::Round($summaryStopwatch.Elapsed.TotalMilliseconds, 3)
                        }

                        $ifaceCmd = script:Get-QualifiedOrFallbackCommand -QualifiedName 'ParserPersistenceModule\Update-InterfacesInDb' -FallbackName 'Update-InterfacesInDb'

                        if (-not $ifaceCmd) { throw "Required parser persistence helper 'Update-InterfacesInDb' is not available. Ensure ParserPersistenceModule.psm1 is imported." }

                        $ifaceParams = @{

                            Connection    = $__dbConn

                            Facts         = $facts

                            Hostname      = $cleanHostname

                            RunDateString = $runDateString

                            Templates     = $templates

                            SiteCode      = $siteCode

                        }

                        $interfaceStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                        try {
                            & $ifaceCmd @ifaceParams
                        } finally {
                            $interfaceStopwatch.Stop()
                            $interfaceDurationMs = [Math]::Round($interfaceStopwatch.Elapsed.TotalMilliseconds, 3)
                        }

                        $spanCmd = script:Get-QualifiedOrFallbackCommand -QualifiedName 'ParserPersistenceModule\Update-SpanInfoInDb' -FallbackName 'Update-SpanInfoInDb'
                        if (-not $spanCmd) { throw "Required parser persistence helper 'Update-SpanInfoInDb' is not available. Ensure ParserPersistenceModule.psm1 is imported." }

                        $spanParams = @{
                            Connection    = $__dbConn
                            Hostname      = $cleanHostname
                            RunDateString = $runDateString
                            SpanInfo      = if ($facts.PSObject.Properties.Name -contains 'SpanInfo') { $facts.SpanInfo } else { @() }
                        }

                        try {
                            & $spanCmd @spanParams
                        } catch {
                            Write-Warning ("Failed to persist spanning tree data for host {0}: {1}" -f $cleanHostname, $_.Exception.Message)
                        }

                        try {
                            $metricsCmd = script:Get-QualifiedOrFallbackCommand -QualifiedName 'ParserPersistenceModule\Get-LastInterfaceSyncTelemetry' -FallbackName 'Get-LastInterfaceSyncTelemetry'
                            if ($metricsCmd) {
                                $latestSyncTelemetry = & $metricsCmd
                            }
                        } catch {
                            $latestSyncTelemetry = $null
                        }

                        # Commit the transaction after all operations have executed.

                        if ($Global:StateTraceDebug) {

                            Write-Host "[DEBUG] Committing transaction for host '$cleanHostname'" -ForegroundColor Yellow

                        }

                        $commitStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                        try {
                            $__dbConn.CommitTrans()
                        } finally {
                            $commitStopwatch.Stop()
                            $commitDurationMs = [Math]::Round($commitStopwatch.Elapsed.TotalMilliseconds, 3)
                        }

                        try {
                            $__stDbSw.Stop()
                            $databaseLatencyMs = [int][Math]::Round($__stDbSw.Elapsed.TotalMilliseconds, 0)
                            TelemetryModule\Write-StTelemetryEvent -Name 'DatabaseWriteLatency' -Payload @{ Hostname = $cleanHostname; Site = $siteCode; LatencyMs = $databaseLatencyMs }
                        } catch { }

                        $refreshStopwatch = $null
                        $jet = $null
                        try {
                            $refreshStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                            $jet = New-Object -ComObject JRO.JetEngine
                            $jet.RefreshCache($__dbConn)
                            if ($Global:StateTraceDebug) {
                                Write-Host "[DEBUG] Refreshed Jet cache after commit for host '$cleanHostname'" -ForegroundColor Yellow
                            }
                        } catch { }
                        finally {
                            if ($jet) {
                                TelemetryModule\Remove-ComObjectSafe -ComObject $jet
                            }
                            if ($refreshStopwatch) {
                                $refreshStopwatch.Stop()
                                $refreshDurationMs = [Math]::Round($refreshStopwatch.Elapsed.TotalMilliseconds, 3)
                            }
                        }

                        try {
                            $breakdownPayload = @{
                                Hostname                  = $cleanHostname
                                Site                      = $siteCode
                                SummaryDurationMs         = $summaryDurationMs
                                InterfaceCallDurationMs   = $interfaceDurationMs
                                CommitDurationMs          = $commitDurationMs
                                DatabaseWriteLatencyMs    = $databaseLatencyMs
                                RefreshDurationMs         = $refreshDurationMs
                            }

                            $siteCacheExistingRowSourceValue = $null
                            if ($latestSyncTelemetry) {
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'DiffDurationMs') {
                                    $breakdownPayload['InterfaceDiffDurationMs'] = [double]$latestSyncTelemetry.DiffDurationMs
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'DiffComparisonDurationMs') {
                                    $breakdownPayload['InterfaceDiffComparisonDurationMs'] = [double]$latestSyncTelemetry.DiffComparisonDurationMs
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'BulkCommandExecuteDurationMs') {
                                    $breakdownPayload['BulkCommandExecuteDurationMs'] = [double]$latestSyncTelemetry.BulkCommandExecuteDurationMs
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'StreamDispatchDurationMs') {
                                    $breakdownPayload['StreamDispatchDurationMs'] = [double]$latestSyncTelemetry.StreamDispatchDurationMs
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'UiCloneDurationMs') {
                                    $breakdownPayload['UiCloneDurationMs'] = [double]$latestSyncTelemetry.UiCloneDurationMs
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'StreamCloneDurationMs') {
                                    $breakdownPayload['StreamCloneDurationMs'] = [double]$latestSyncTelemetry.StreamCloneDurationMs
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'StreamStateUpdateDurationMs') {
                                    $breakdownPayload['StreamStateUpdateDurationMs'] = [double]$latestSyncTelemetry.StreamStateUpdateDurationMs
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'StreamRowsReceived') {
                                    $breakdownPayload['StreamRowsReceived'] = [int]$latestSyncTelemetry.StreamRowsReceived
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'StreamRowsReused') {
                                    $breakdownPayload['StreamRowsReused'] = [int]$latestSyncTelemetry.StreamRowsReused
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'StreamRowsCloned') {
                                    $breakdownPayload['StreamRowsCloned'] = [int]$latestSyncTelemetry.StreamRowsCloned
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheUpdateDurationMs') {
                                    $breakdownPayload['SiteCacheUpdateDurationMs'] = [double]$latestSyncTelemetry.SiteCacheUpdateDurationMs
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheFetchDurationMs') {
                                    $breakdownPayload['SiteCacheFetchDurationMs'] = [double]$latestSyncTelemetry.SiteCacheFetchDurationMs
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheRefreshDurationMs') {
                                    $breakdownPayload['SiteCacheRefreshDurationMs'] = [double]$latestSyncTelemetry.SiteCacheRefreshDurationMs
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheFetchStatus') {
                                    $statusValue = '' + $latestSyncTelemetry.SiteCacheFetchStatus
                                    if (-not [string]::IsNullOrWhiteSpace($statusValue)) {
                                        $breakdownPayload['SiteCacheFetchStatus'] = $statusValue
                                    }
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheSnapshotDurationMs') {
                                    $breakdownPayload['SiteCacheSnapshotDurationMs'] = [double]$latestSyncTelemetry.SiteCacheSnapshotDurationMs
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheRecordsetDurationMs') {
                                    $breakdownPayload['SiteCacheRecordsetDurationMs'] = [double]$latestSyncTelemetry.SiteCacheRecordsetDurationMs
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheRecordsetProjectDurationMs') {
                                    $breakdownPayload['SiteCacheRecordsetProjectDurationMs'] = [double]$latestSyncTelemetry.SiteCacheRecordsetProjectDurationMs
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheBuildDurationMs') {
                                    $breakdownPayload['SiteCacheBuildDurationMs'] = [double]$latestSyncTelemetry.SiteCacheBuildDurationMs
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheHostMapDurationMs') {
                                    $breakdownPayload['SiteCacheHostMapDurationMs'] = [double]$latestSyncTelemetry.SiteCacheHostMapDurationMs
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheHostMapSignatureMatchCount') {
                                    $breakdownPayload['SiteCacheHostMapSignatureMatchCount'] = [long]$latestSyncTelemetry.SiteCacheHostMapSignatureMatchCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheHostMapSignatureRewriteCount') {
                                    $breakdownPayload['SiteCacheHostMapSignatureRewriteCount'] = [long]$latestSyncTelemetry.SiteCacheHostMapSignatureRewriteCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheHostMapEntryAllocationCount') {
                                    $breakdownPayload['SiteCacheHostMapEntryAllocationCount'] = [long]$latestSyncTelemetry.SiteCacheHostMapEntryAllocationCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheHostMapEntryPoolReuseCount') {
                                    $breakdownPayload['SiteCacheHostMapEntryPoolReuseCount'] = [long]$latestSyncTelemetry.SiteCacheHostMapEntryPoolReuseCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheHostMapLookupCount') {
                                    $breakdownPayload['SiteCacheHostMapLookupCount'] = [long]$latestSyncTelemetry.SiteCacheHostMapLookupCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheHostMapLookupMissCount') {
                                    $breakdownPayload['SiteCacheHostMapLookupMissCount'] = [long]$latestSyncTelemetry.SiteCacheHostMapLookupMissCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheHostMapCandidateMissingCount') {
                                    $breakdownPayload['SiteCacheHostMapCandidateMissingCount'] = [long]$latestSyncTelemetry.SiteCacheHostMapCandidateMissingCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheHostMapCandidateSignatureMissingCount') {
                                    $breakdownPayload['SiteCacheHostMapCandidateSignatureMissingCount'] = [long]$latestSyncTelemetry.SiteCacheHostMapCandidateSignatureMissingCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheHostMapCandidateSignatureMismatchCount') {
                                    $breakdownPayload['SiteCacheHostMapCandidateSignatureMismatchCount'] = [long]$latestSyncTelemetry.SiteCacheHostMapCandidateSignatureMismatchCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheHostMapCandidateFromPreviousCount') {
                                    $breakdownPayload['SiteCacheHostMapCandidateFromPreviousCount'] = [long]$latestSyncTelemetry.SiteCacheHostMapCandidateFromPreviousCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheHostMapCandidateFromPoolCount') {
                                    $breakdownPayload['SiteCacheHostMapCandidateFromPoolCount'] = [long]$latestSyncTelemetry.SiteCacheHostMapCandidateFromPoolCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheHostMapCandidateInvalidCount') {
                                    $breakdownPayload['SiteCacheHostMapCandidateInvalidCount'] = [long]$latestSyncTelemetry.SiteCacheHostMapCandidateInvalidCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheHostMapCandidateMissingSamples') {
                                    $samples = $latestSyncTelemetry.SiteCacheHostMapCandidateMissingSamples
                                    if ($null -ne $samples) {
                                        if ($samples -is [System.Collections.IEnumerable] -and -not ($samples -is [string])) {
                                            $breakdownPayload['SiteCacheHostMapCandidateMissingSamples'] = @($samples | ForEach-Object { $_ })
                                        } else {
                                            $breakdownPayload['SiteCacheHostMapCandidateMissingSamples'] = @($samples)
                                        }
                                    } else {
                                        $breakdownPayload['SiteCacheHostMapCandidateMissingSamples'] = @()
                                    }
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheHostMapSignatureMismatchSamples') {
                                    $samples = $latestSyncTelemetry.SiteCacheHostMapSignatureMismatchSamples
                                    if ($null -ne $samples) {
                                        if ($samples -is [System.Collections.IEnumerable] -and -not ($samples -is [string])) {
                                            $breakdownPayload['SiteCacheHostMapSignatureMismatchSamples'] = @($samples | ForEach-Object { $_ })
                                        } else {
                                            $breakdownPayload['SiteCacheHostMapSignatureMismatchSamples'] = @($samples)
                                        }
                                    } else {
                                        $breakdownPayload['SiteCacheHostMapSignatureMismatchSamples'] = @()
                                    }
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheResolveInitialStatus') {
                                    $initialResolveStatus = '' + $latestSyncTelemetry.SiteCacheResolveInitialStatus
                                    if (-not [string]::IsNullOrWhiteSpace($initialResolveStatus)) {
                                        $breakdownPayload['SiteCacheResolveInitialStatus'] = $initialResolveStatus
                                    }
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheResolveInitialHostCount') {
                                    $breakdownPayload['SiteCacheResolveInitialHostCount'] = [int]$latestSyncTelemetry.SiteCacheResolveInitialHostCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheResolveInitialMatchedKey') {
                                    $initialMatchedKey = '' + $latestSyncTelemetry.SiteCacheResolveInitialMatchedKey
                                    if (-not [string]::IsNullOrWhiteSpace($initialMatchedKey)) {
                                        $breakdownPayload['SiteCacheResolveInitialMatchedKey'] = $initialMatchedKey
                                    }
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheResolveInitialKeysSample') {
                                    $initialKeysSample = '' + $latestSyncTelemetry.SiteCacheResolveInitialKeysSample
                                    if (-not [string]::IsNullOrWhiteSpace($initialKeysSample)) {
                                        $breakdownPayload['SiteCacheResolveInitialKeysSample'] = $initialKeysSample
                                    }
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheResolveInitialCacheAgeMs') {
                                    $initialAge = $latestSyncTelemetry.SiteCacheResolveInitialCacheAgeMs
                                    if ($null -ne $initialAge) {
                                        $breakdownPayload['SiteCacheResolveInitialCacheAgeMs'] = [double]$initialAge
                                    }
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheResolveInitialCachedAt') {
                                    $initialCachedAt = '' + $latestSyncTelemetry.SiteCacheResolveInitialCachedAt
                                    if (-not [string]::IsNullOrWhiteSpace($initialCachedAt)) {
                                        $breakdownPayload['SiteCacheResolveInitialCachedAt'] = $initialCachedAt
                                    }
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheResolveInitialEntryType') {
                                    $initialEntryType = '' + $latestSyncTelemetry.SiteCacheResolveInitialEntryType
                                    if (-not [string]::IsNullOrWhiteSpace($initialEntryType)) {
                                        $breakdownPayload['SiteCacheResolveInitialEntryType'] = $initialEntryType
                                    }
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheResolveInitialPortCount') {
                                    $breakdownPayload['SiteCacheResolveInitialPortCount'] = [int]$latestSyncTelemetry.SiteCacheResolveInitialPortCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheResolveInitialPortKeysSample') {
                                    $initialPortKeysSample = '' + $latestSyncTelemetry.SiteCacheResolveInitialPortKeysSample
                                    if (-not [string]::IsNullOrWhiteSpace($initialPortKeysSample)) {
                                        $breakdownPayload['SiteCacheResolveInitialPortKeysSample'] = $initialPortKeysSample
                                    }
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheResolveInitialPortSignatureSample') {
                                    $initialSignatureSample = '' + $latestSyncTelemetry.SiteCacheResolveInitialPortSignatureSample
                                    if (-not [string]::IsNullOrWhiteSpace($initialSignatureSample)) {
                                        $breakdownPayload['SiteCacheResolveInitialPortSignatureSample'] = $initialSignatureSample
                                    }
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheResolveInitialPortSignatureMissingCount') {
                                    $breakdownPayload['SiteCacheResolveInitialPortSignatureMissingCount'] = [int]$latestSyncTelemetry.SiteCacheResolveInitialPortSignatureMissingCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheResolveInitialPortSignatureEmptyCount') {
                                    $breakdownPayload['SiteCacheResolveInitialPortSignatureEmptyCount'] = [int]$latestSyncTelemetry.SiteCacheResolveInitialPortSignatureEmptyCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheResolveRefreshStatus') {
                                    $refreshResolveStatus = '' + $latestSyncTelemetry.SiteCacheResolveRefreshStatus
                                    if (-not [string]::IsNullOrWhiteSpace($refreshResolveStatus)) {
                                        $breakdownPayload['SiteCacheResolveRefreshStatus'] = $refreshResolveStatus
                                    }
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheResolveRefreshHostCount') {
                                    $breakdownPayload['SiteCacheResolveRefreshHostCount'] = [int]$latestSyncTelemetry.SiteCacheResolveRefreshHostCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheResolveRefreshMatchedKey') {
                                    $refreshMatchedKey = '' + $latestSyncTelemetry.SiteCacheResolveRefreshMatchedKey
                                    if (-not [string]::IsNullOrWhiteSpace($refreshMatchedKey)) {
                                        $breakdownPayload['SiteCacheResolveRefreshMatchedKey'] = $refreshMatchedKey
                                    }
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheResolveRefreshKeysSample') {
                                    $refreshKeysSample = '' + $latestSyncTelemetry.SiteCacheResolveRefreshKeysSample
                                    if (-not [string]::IsNullOrWhiteSpace($refreshKeysSample)) {
                                        $breakdownPayload['SiteCacheResolveRefreshKeysSample'] = $refreshKeysSample
                                    }
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheResolveRefreshCacheAgeMs') {
                                    $refreshAge = $latestSyncTelemetry.SiteCacheResolveRefreshCacheAgeMs
                                    if ($null -ne $refreshAge) {
                                        $breakdownPayload['SiteCacheResolveRefreshCacheAgeMs'] = [double]$refreshAge
                                    }
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheResolveRefreshCachedAt') {
                                    $refreshCachedAt = '' + $latestSyncTelemetry.SiteCacheResolveRefreshCachedAt
                                    if (-not [string]::IsNullOrWhiteSpace($refreshCachedAt)) {
                                        $breakdownPayload['SiteCacheResolveRefreshCachedAt'] = $refreshCachedAt
                                    }
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheResolveRefreshEntryType') {
                                    $refreshEntryType = '' + $latestSyncTelemetry.SiteCacheResolveRefreshEntryType
                                    if (-not [string]::IsNullOrWhiteSpace($refreshEntryType)) {
                                        $breakdownPayload['SiteCacheResolveRefreshEntryType'] = $refreshEntryType
                                    }
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheResolveRefreshPortCount') {
                                    $breakdownPayload['SiteCacheResolveRefreshPortCount'] = [int]$latestSyncTelemetry.SiteCacheResolveRefreshPortCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheResolveRefreshPortKeysSample') {
                                    $refreshPortKeysSample = '' + $latestSyncTelemetry.SiteCacheResolveRefreshPortKeysSample
                                    if (-not [string]::IsNullOrWhiteSpace($refreshPortKeysSample)) {
                                        $breakdownPayload['SiteCacheResolveRefreshPortKeysSample'] = $refreshPortKeysSample
                                    }
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheResolveRefreshPortSignatureSample') {
                                    $refreshSignatureSample = '' + $latestSyncTelemetry.SiteCacheResolveRefreshPortSignatureSample
                                    if (-not [string]::IsNullOrWhiteSpace($refreshSignatureSample)) {
                                        $breakdownPayload['SiteCacheResolveRefreshPortSignatureSample'] = $refreshSignatureSample
                                    }
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheResolveRefreshPortSignatureMissingCount') {
                                    $breakdownPayload['SiteCacheResolveRefreshPortSignatureMissingCount'] = [int]$latestSyncTelemetry.SiteCacheResolveRefreshPortSignatureMissingCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheResolveRefreshPortSignatureEmptyCount') {
                                    $breakdownPayload['SiteCacheResolveRefreshPortSignatureEmptyCount'] = [int]$latestSyncTelemetry.SiteCacheResolveRefreshPortSignatureEmptyCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheSortDurationMs') {
                                    $breakdownPayload['SiteCacheSortDurationMs'] = [double]$latestSyncTelemetry.SiteCacheSortDurationMs
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheHostCount') {
                                    $breakdownPayload['SiteCacheHostCount'] = [int]$latestSyncTelemetry.SiteCacheHostCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheQueryDurationMs') {
                                    $breakdownPayload['SiteCacheQueryDurationMs'] = [double]$latestSyncTelemetry.SiteCacheQueryDurationMs
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheExecuteDurationMs') {
                                    $breakdownPayload['SiteCacheExecuteDurationMs'] = [double]$latestSyncTelemetry.SiteCacheExecuteDurationMs
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'LoadExistingDurationMs') {
                                    $breakdownPayload['LoadExistingDurationMs'] = [double]$latestSyncTelemetry.LoadExistingDurationMs
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'LoadExistingRowSetCount') {
                                    $breakdownPayload['LoadExistingRowSetCount'] = [int]$latestSyncTelemetry.LoadExistingRowSetCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheMaterializeDurationMs') {
                                    $breakdownPayload['SiteCacheMaterializeDurationMs'] = [double]$latestSyncTelemetry.SiteCacheMaterializeDurationMs
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheMaterializeProjectionDurationMs') {
                                    $breakdownPayload['SiteCacheMaterializeProjectionDurationMs'] = [double]$latestSyncTelemetry.SiteCacheMaterializeProjectionDurationMs
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheMaterializePortSortDurationMs') {
                                    $breakdownPayload['SiteCacheMaterializePortSortDurationMs'] = [double]$latestSyncTelemetry.SiteCacheMaterializePortSortDurationMs
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheMaterializePortSortCacheHitCount') {
                                    $breakdownPayload['SiteCacheMaterializePortSortCacheHitCount'] = [long]$latestSyncTelemetry.SiteCacheMaterializePortSortCacheHitCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheMaterializePortSortCacheMissCount') {
                                    $breakdownPayload['SiteCacheMaterializePortSortCacheMissCount'] = [long]$latestSyncTelemetry.SiteCacheMaterializePortSortCacheMissCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheMaterializePortSortCacheSize') {
                                    $breakdownPayload['SiteCacheMaterializePortSortCacheSize'] = [long]$latestSyncTelemetry.SiteCacheMaterializePortSortCacheSize
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheMaterializePortSortCacheHitRatio') {
                                    $breakdownPayload['SiteCacheMaterializePortSortCacheHitRatio'] = [double]$latestSyncTelemetry.SiteCacheMaterializePortSortCacheHitRatio
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheMaterializePortSortUniquePortCount') {
                                    $breakdownPayload['SiteCacheMaterializePortSortUniquePortCount'] = [long]$latestSyncTelemetry.SiteCacheMaterializePortSortUniquePortCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheMaterializePortSortMissSamples') {
                                    $breakdownPayload['SiteCacheMaterializePortSortMissSamples'] = @($latestSyncTelemetry.SiteCacheMaterializePortSortMissSamples)
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateDurationMs') {
                                    $breakdownPayload['SiteCacheMaterializeTemplateDurationMs'] = [double]$latestSyncTelemetry.SiteCacheMaterializeTemplateDurationMs
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateLookupDurationMs') {
                                    $breakdownPayload['SiteCacheMaterializeTemplateLookupDurationMs'] = [double]$latestSyncTelemetry.SiteCacheMaterializeTemplateLookupDurationMs
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateApplyDurationMs') {
                                    $breakdownPayload['SiteCacheMaterializeTemplateApplyDurationMs'] = [double]$latestSyncTelemetry.SiteCacheMaterializeTemplateApplyDurationMs
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateCacheHitCount') {
                                    $breakdownPayload['SiteCacheMaterializeTemplateCacheHitCount'] = [long]$latestSyncTelemetry.SiteCacheMaterializeTemplateCacheHitCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateCacheMissCount') {
                                    $breakdownPayload['SiteCacheMaterializeTemplateCacheMissCount'] = [long]$latestSyncTelemetry.SiteCacheMaterializeTemplateCacheMissCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateCacheHitRatio') {
                                    $breakdownPayload['SiteCacheMaterializeTemplateCacheHitRatio'] = [double]$latestSyncTelemetry.SiteCacheMaterializeTemplateCacheHitRatio
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateApplyCount') {
                                    $breakdownPayload['SiteCacheMaterializeTemplateApplyCount'] = [long]$latestSyncTelemetry.SiteCacheMaterializeTemplateApplyCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateDefaultedCount') {
                                    $breakdownPayload['SiteCacheMaterializeTemplateDefaultedCount'] = [long]$latestSyncTelemetry.SiteCacheMaterializeTemplateDefaultedCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateAuthTemplateMissingCount') {
                                    $breakdownPayload['SiteCacheMaterializeTemplateAuthTemplateMissingCount'] = [long]$latestSyncTelemetry.SiteCacheMaterializeTemplateAuthTemplateMissingCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateNoTemplateMatchCount') {
                                    $breakdownPayload['SiteCacheMaterializeTemplateNoTemplateMatchCount'] = [long]$latestSyncTelemetry.SiteCacheMaterializeTemplateNoTemplateMatchCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateReuseCount') {
                                    $breakdownPayload['SiteCacheMaterializeTemplateReuseCount'] = [long]$latestSyncTelemetry.SiteCacheMaterializeTemplateReuseCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateHintAppliedCount') {
                                    $breakdownPayload['SiteCacheMaterializeTemplateHintAppliedCount'] = [long]$latestSyncTelemetry.SiteCacheMaterializeTemplateHintAppliedCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateSetPortColorCount') {
                                    $breakdownPayload['SiteCacheMaterializeTemplateSetPortColorCount'] = [long]$latestSyncTelemetry.SiteCacheMaterializeTemplateSetPortColorCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateSetConfigStatusCount') {
                                    $breakdownPayload['SiteCacheMaterializeTemplateSetConfigStatusCount'] = [long]$latestSyncTelemetry.SiteCacheMaterializeTemplateSetConfigStatusCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheMaterializeTemplateApplySamples') {
                                    $breakdownPayload['SiteCacheMaterializeTemplateApplySamples'] = @($latestSyncTelemetry.SiteCacheMaterializeTemplateApplySamples)
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheMaterializeObjectDurationMs') {
                                    $breakdownPayload['SiteCacheMaterializeObjectDurationMs'] = [double]$latestSyncTelemetry.SiteCacheMaterializeObjectDurationMs
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheTemplateDurationMs') {
                                    $breakdownPayload['SiteCacheTemplateDurationMs'] = [double]$latestSyncTelemetry.SiteCacheTemplateDurationMs
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheQueryAttempts') {
                                    $breakdownPayload['SiteCacheQueryAttempts'] = [int]$latestSyncTelemetry.SiteCacheQueryAttempts
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheExclusiveRetryCount') {
                                    $breakdownPayload['SiteCacheExclusiveRetryCount'] = [int]$latestSyncTelemetry.SiteCacheExclusiveRetryCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheExclusiveWaitDurationMs') {
                                    $breakdownPayload['SiteCacheExclusiveWaitDurationMs'] = [double]$latestSyncTelemetry.SiteCacheExclusiveWaitDurationMs
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheProvider') {
                                    $providerValue = '' + $latestSyncTelemetry.SiteCacheProvider
                                    if (-not [string]::IsNullOrWhiteSpace($providerValue)) {
                                        $breakdownPayload['SiteCacheProvider'] = $providerValue
                                    }
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheProviderReason') {
                                    $providerReasonValue = '' + $latestSyncTelemetry.SiteCacheProviderReason
                                    if (-not [string]::IsNullOrWhiteSpace($providerReasonValue)) {
                                        $breakdownPayload['SiteCacheProviderReason'] = $providerReasonValue.Trim()
                                    }
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheResultRowCount') {
                                    $breakdownPayload['SiteCacheResultRowCount'] = [int]$latestSyncTelemetry.SiteCacheResultRowCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheExistingRowCount') {
                                    $breakdownPayload['SiteCacheExistingRowCount'] = [int]$latestSyncTelemetry.SiteCacheExistingRowCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheExistingRowKeysSample') {
                                    $breakdownPayload['SiteCacheExistingRowKeysSample'] = '' + $latestSyncTelemetry.SiteCacheExistingRowKeysSample
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheExistingRowValueType') {
                                    $breakdownPayload['SiteCacheExistingRowValueType'] = '' + $latestSyncTelemetry.SiteCacheExistingRowValueType
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheExistingRowSource') {
                                    $siteCacheExistingRowSourceValue = '' + $latestSyncTelemetry.SiteCacheExistingRowSource
                                    if (-not [string]::IsNullOrWhiteSpace($siteCacheExistingRowSourceValue)) {
                                        $siteCacheExistingRowSourceValue = $siteCacheExistingRowSourceValue.Trim()
                                        $breakdownPayload['SiteCacheExistingRowSource'] = $siteCacheExistingRowSourceValue
                                    }
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheComparisonCandidateCount') {
                                    $breakdownPayload['SiteCacheComparisonCandidateCount'] = [int]$latestSyncTelemetry.SiteCacheComparisonCandidateCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheComparisonSignatureMatchCount') {
                                    $breakdownPayload['SiteCacheComparisonSignatureMatchCount'] = [int]$latestSyncTelemetry.SiteCacheComparisonSignatureMatchCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheComparisonSignatureMismatchCount') {
                                    $breakdownPayload['SiteCacheComparisonSignatureMismatchCount'] = [int]$latestSyncTelemetry.SiteCacheComparisonSignatureMismatchCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheComparisonSignatureMissingCount') {
                                    $breakdownPayload['SiteCacheComparisonSignatureMissingCount'] = [int]$latestSyncTelemetry.SiteCacheComparisonSignatureMissingCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheComparisonMissingPortCount') {
                                    $breakdownPayload['SiteCacheComparisonMissingPortCount'] = [int]$latestSyncTelemetry.SiteCacheComparisonMissingPortCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'SiteCacheComparisonObsoletePortCount') {
                                    $breakdownPayload['SiteCacheComparisonObsoletePortCount'] = [int]$latestSyncTelemetry.SiteCacheComparisonObsoletePortCount
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'RowsStaged') {
                                    $breakdownPayload['RowsStaged'] = [int]$latestSyncTelemetry.RowsStaged
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'InsertCandidates') {
                                    $breakdownPayload['InsertCandidates'] = [int]$latestSyncTelemetry.InsertCandidates
                                }
                                if ($latestSyncTelemetry.PSObject.Properties.Name -contains 'UpdateCandidates') {
                                    $breakdownPayload['UpdateCandidates'] = [int]$latestSyncTelemetry.UpdateCandidates
                                }
                            }

                            if (-not $siteCacheExistingRowSourceValue -and $breakdownPayload.ContainsKey('SiteCacheExistingRowSource')) {
                                $candidateSourceValue = '' + $breakdownPayload['SiteCacheExistingRowSource']
                                if (-not [string]::IsNullOrWhiteSpace($candidateSourceValue)) {
                                    $siteCacheExistingRowSourceValue = $candidateSourceValue.Trim()
                                }
                            }

                            Resolve-DatabaseWriteBreakdownCacheProvider -Payload $breakdownPayload -ExistingRowSource $siteCacheExistingRowSourceValue -Telemetry $latestSyncTelemetry

                            TelemetryModule\Write-StTelemetryEvent -Name 'DatabaseWriteBreakdown' -Payload $breakdownPayload
                        } catch { }

                        $ingestionSucceeded = $true

                    } catch {
                        $transactionError = $_

                        if ($Global:StateTraceDebug) {

                            Write-Host ("[DEBUG] Transaction failed for host '{0}', rolling back: {1}" -f $cleanHostname, $transactionError.Exception.Message) -ForegroundColor Yellow

                        }

                        try {
                            $__dbConn.RollbackTrans()
                        } catch {
                            $rollbackMessage = $_.Exception.Message
                            if ([string]::IsNullOrWhiteSpace($rollbackMessage)) { $rollbackMessage = 'Rollback failed without a message.' }
                            Write-Warning ("Rollback failed for host '{0}': {1}" -f $cleanHostname, $rollbackMessage)
                        }

                        throw $transactionError

                    }

                } catch {

                    if ($connectionLease) {

                        Release-CachedDbConnection -Lease $connectionLease -ForceRemove

                        $connectionLease = $null

                    }

                    if ($Global:StateTraceDebug) {

                        Write-Host ("[DEBUG] Database operation failed for host '{0}': {1}" -f $cleanHostname, $_.Exception.Message) -ForegroundColor Yellow

                    }

                    throw

                } finally {

                    if ($connectionLease) {

                        Release-CachedDbConnection -Lease $connectionLease

                        $connectionLease = $null

                    }

                }
            } finally {
                # Release the mutex to allow other runspaces to write.  Always
                try {
                    if ($Global:StateTraceDebug) {
                        Write-Host "[DEBUG] Releasing DB write mutex for host '$cleanHostname'" -ForegroundColor Yellow
                    }
                    $dbMutex.ReleaseMutex()
                } catch {
                    Write-Warning ("Failed to release DB write mutex for host '{0}': {1}" -f $cleanHostname, $_.Exception.Message)
                }
                $dbMutex.Dispose()
            }
        } catch {
            # Use curly braces around variable names that precede a colon to avoid
            $metadata = @{
                DatabasePath = $DatabasePath
                Provider     = $__dbProvider
            }
            ParserPersistenceModule\Write-InterfacePersistenceFailure -Stage 'DeviceLogParserUnhandled' -Hostname $cleanHostname -Exception $_.Exception -Metadata $metadata
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
                    $historyRecords = Read-IngestionHistoryRecords -Path $historyContext.FilePath
                } catch { $historyRecords = @() }
            }

            $updated = [System.Collections.Generic.List[object]]::new()
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
            if ($historyMutex) {
                try { $historyMutex.ReleaseMutex() } catch {
                    $mutexName = if ($historyContext) { $historyContext.MutexName } else { $null }
                    $label = if ([string]::IsNullOrWhiteSpace($mutexName)) { 'StateTraceHistory' } else { $mutexName }
                    Write-Warning ("Failed to release ingestion history mutex '{0}': {1}" -f $label, $_.Exception.Message)
                }
                $historyMutex.Dispose()
            }
        }
    }

    Remove-OldArchiveFolder -DeviceArchivePath $devicePath -ArchiveRoot $ArchiveRoot -RetentionDays 30
    }
    finally {
        try {
            if ($__stParseSw) { $__stParseSw.Stop() }

            if (-not $skippedDuplicate) {
                $payload = @{
                    Hostname = $cleanHostname
                    Site = $siteCode
                    StartTime = $__stParseStart.ToUniversalTime().ToString('o')
                    DurationSeconds = [Math]::Round($__stParseSw.Elapsed.TotalSeconds, 3)
                    Success = [bool]$ingestionSucceeded
                }

                if ($FilePath) {
                    $payload['FileName'] = [System.IO.Path]::GetFileName($FilePath)
                }

                TelemetryModule\Write-StTelemetryEvent -Name 'ParseDuration' -Payload $payload
            }
        } catch { }
    }
}

Export-ModuleMember -Function Get-LocationDetails, Get-ShowCommandBlocks, Get-ShowBlock, Get-DeviceMakeFromBlocks, Get-SnmpLocationFromLines, ConvertFrom-SpanningTree, Remove-OldArchiveFolder, Get-BrocadeAuthBlockFromLines, Invoke-DeviceLogParsing, Get-LogParseContext, Get-VendorTemplates, Get-DatabaseMutexName
