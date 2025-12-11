Set-StrictMode -Version Latest

if (-not ('StateTrace.Parser.SiteExistingRowCacheHolder' -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Collections.Concurrent;

namespace StateTrace.Parser
{
    public static class SiteExistingRowCacheHolder
    {
        private static readonly object SyncRoot = new object();
        private static ConcurrentDictionary<string, object> _store = CreateStore();

        private static ConcurrentDictionary<string, object> CreateStore()
        {
            return new ConcurrentDictionary<string, object>(StringComparer.OrdinalIgnoreCase);
        }

        public static ConcurrentDictionary<string, object> GetStore()
        {
            if (_store == null)
            {
                lock (SyncRoot)
                {
                    if (_store == null)
                    {
                        _store = CreateStore();
                    }
                }
            }

            return _store;
        }

        public static void SetStore(ConcurrentDictionary<string, object> store)
        {
            lock (SyncRoot)
            {
                _store = store ?? CreateStore();
            }
        }

        public static void ClearStore()
        {
            lock (SyncRoot)
            {
                _store = CreateStore();
            }
        }
    }
}
"@
}

# ADODB helper constants and utilities for parameterized operations
if (-not (Get-Variable -Name AdCmdText -Scope Script -ErrorAction SilentlyContinue)) {
    $script:AdCmdText = 1
    $script:AdParamInput = 1
    $script:AdTypeVarWChar = 202
    $script:AdTypeLongVarWChar = 203
    $script:AdTypeInteger = 3
    $script:AdTypeDate = 7
    $script:AdLongTextDefaultSize = 262144
    $script:AdExecuteNoRecords = 128
    $script:AdUseClient = 3
    $script:AdOpenStatic = 3
    $script:AdLockBatchOptimistic = 4
}

if (-not (Get-Variable -Name AdodbParameterWrapperType -Scope Script -ErrorAction SilentlyContinue)) {
    $script:AdodbParameterWrapperType = $null
}

if (-not (Get-Variable -Name AdodbParameterWrapperTypeResolved -Scope Script -ErrorAction SilentlyContinue)) {
    $script:AdodbParameterWrapperTypeResolved = $false
}

if (-not (Get-Variable -Name InterfaceIndexesEnsured -Scope Script -ErrorAction SilentlyContinue)) {
    $script:InterfaceIndexesEnsured = $false
}

if (-not (Get-Variable -Name InterfaceBulkChunkSizeDefault -Scope Script -ErrorAction SilentlyContinue)) {
    $script:InterfaceBulkChunkSizeDefault = 24
}

if (-not (Get-Variable -Name InterfaceBulkChunkSizeCurrent -Scope Script -ErrorAction SilentlyContinue)) {
    $script:InterfaceBulkChunkSizeCurrent = $script:InterfaceBulkChunkSizeDefault
}

function Set-InterfaceBulkChunkSize {
    [CmdletBinding()]
    param(
        [int]$ChunkSize,
        [switch]$Reset
    )

    $targetSize = $script:InterfaceBulkChunkSizeDefault
    if (-not $Reset -and $PSBoundParameters.ContainsKey('ChunkSize') -and $ChunkSize -gt 0) {
        $targetSize = [int]$ChunkSize
    }

    $script:InterfaceBulkChunkSizeCurrent = $targetSize

    try {
        DeviceRepositoryModule\Set-InterfacePortStreamChunkSize -ChunkSize $targetSize | Out-Null
    } catch { }

    return $script:InterfaceBulkChunkSizeCurrent
}

if (-not (Get-Variable -Name InterfaceIndexesEnsureAttempted -Scope Script -ErrorAction SilentlyContinue)) {
    $script:InterfaceIndexesEnsureAttempted = $false
}

if (-not (Get-Variable -Name InterfaceComparisonProperties -Scope Script -ErrorAction SilentlyContinue)) {
    $script:InterfaceComparisonProperties = @(
        'Name',
        'Status',
        'VLAN',
        'Duplex',
        'Speed',
        'Type',
        'Learned',
        'AuthState',
        'AuthMode',
        'AuthClient',
        'Template',
        'Config',
        'PortColor',
        'StatusTag',
        'ToolTip'
    )
}

if (-not (Get-Variable -Name LastInterfaceSyncTelemetry -Scope Script -ErrorAction SilentlyContinue)) {
    $script:LastInterfaceSyncTelemetry = $null
}

if (-not (Get-Variable -Name SkipSiteCacheUpdate -Scope Script -ErrorAction SilentlyContinue)) {
    $script:SkipSiteCacheUpdate = $false
}

if (-not (Get-Variable -Name SiteExistingRowCache -Scope Script -ErrorAction SilentlyContinue)) {
    try {
        $script:SiteExistingRowCache = [StateTrace.Parser.SiteExistingRowCacheHolder]::GetStore()
    } catch {
        $script:SiteExistingRowCache = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }
}

if ($script:SiteExistingRowCache -isnot [System.Collections.Concurrent.ConcurrentDictionary[string, object]]) {
    $script:SiteExistingRowCache = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
}

try { [StateTrace.Parser.SiteExistingRowCacheHolder]::SetStore($script:SiteExistingRowCache) } catch { }

if (-not (Get-Variable -Name SiteExistingRowCacheSnapshotLoaded -Scope Script -ErrorAction SilentlyContinue)) {
    $script:SiteExistingRowCacheSnapshotLoaded = $false
}

if (-not (Get-Variable -Name SpanTablesEnsured -Scope Script -ErrorAction SilentlyContinue)) {
    $script:SpanTablesEnsured = $false
}

function Clear-SiteExistingRowCache {
    [CmdletBinding()]
    param()

    try {
        [StateTrace.Parser.SiteExistingRowCacheHolder]::ClearStore()
        $script:SiteExistingRowCache = [StateTrace.Parser.SiteExistingRowCacheHolder]::GetStore()
    } catch {
        $script:SiteExistingRowCache = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        try { [StateTrace.Parser.SiteExistingRowCacheHolder]::SetStore($script:SiteExistingRowCache) } catch { }
    }

    $script:SiteExistingRowCacheSnapshotLoaded = $false
}

function Set-ParserSkipSiteCacheUpdate {
    [CmdletBinding()]
    param(
        [switch]$Reset,
        [bool]$Skip = $true
    )

    if ($Reset) {
        $script:SkipSiteCacheUpdate = $false
        Clear-SiteExistingRowCache
    } else {
        $script:SkipSiteCacheUpdate = [bool]$Skip
    }

    return $script:SkipSiteCacheUpdate
}

function New-SiteExistingRowCacheEntry {
    $entries = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $primedEntries = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    return [pscustomobject]@{
        Entries       = $entries
        PrimedEntries = $primedEntries
        Hydrated      = $false
        CachedAt      = $null
        Source        = 'Unknown'
    }
}

function Get-SiteExistingRowCacheEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SiteCode
    )

    if (-not $script:SiteExistingRowCache.ContainsKey($SiteCode)) {
        $script:SiteExistingRowCache[$SiteCode] = New-SiteExistingRowCacheEntry
    }

    $entry = $script:SiteExistingRowCache[$SiteCode]
    if ($entry -and -not ($entry.PSObject.Properties.Name -contains 'Entries')) {
        $entry | Add-Member -MemberType NoteProperty -Name 'Entries' -Value ([System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)) -Force
    }
    if ($entry -and -not ($entry.PSObject.Properties.Name -contains 'PrimedEntries')) {
        $entry | Add-Member -MemberType NoteProperty -Name 'PrimedEntries' -Value ([System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)) -Force
    }

    return $entry
}

function Normalize-SiteExistingRowCacheHostEntry {
    param(
        $Entry
    )

    if (-not $Entry) {
        return [pscustomobject]@{
            Rows                    = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
            LoadSignatureDurationMs = 0.0
        }
    }

    if ($Entry -isnot [psobject]) {
        return Normalize-SiteExistingRowCacheHostEntry -Entry ([pscustomobject]$Entry)
    }

    if (-not ($Entry.PSObject.Properties.Name -contains 'Rows')) {
        $Entry | Add-Member -MemberType NoteProperty -Name 'Rows' -Value ([System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)) -Force
    } elseif ($Entry.Rows -isnot [System.Collections.Concurrent.ConcurrentDictionary[string, object]]) {
        $newRows = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        if ($Entry.Rows -is [System.Collections.IDictionary]) {
            foreach ($key in $Entry.Rows.Keys) { $newRows[$key] = $Entry.Rows[$key] }
        } elseif ($Entry.Rows -is [System.Collections.IEnumerable]) {
            foreach ($item in $Entry.Rows) {
                if ($null -eq $item) { continue }
                $portKey = ''
                try { $portKey = '' + $item.Port } catch { $portKey = '' }
                if (-not [string]::IsNullOrWhiteSpace($portKey)) {
                    $newRows[$portKey] = $item
                }
            }
        }
        $Entry.Rows = $newRows
    }

    if (-not ($Entry.PSObject.Properties.Name -contains 'LoadSignatureDurationMs')) {
        $Entry | Add-Member -MemberType NoteProperty -Name 'LoadSignatureDurationMs' -Value 0.0 -Force
    }

    return $Entry
}

function Copy-SiteExistingRowCacheHostEntry {
    param(
        $Entry
    )

    if (-not $Entry) { return $null }

    $normalized = Normalize-SiteExistingRowCacheHostEntry -Entry ($Entry.PSObject.Copy())
    $copyRows = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($normalized.Rows) {
        foreach ($rowKey in $normalized.Rows.Keys) {
            $copyRows[$rowKey] = $normalized.Rows[$rowKey]
        }
    }
    $normalized.Rows = $copyRows
    return $normalized
}

function Get-SiteExistingRowCacheHostRowCount {
    [CmdletBinding()]
    param(
        [object]$HostEntry
    )

    if (-not $HostEntry) { return 0 }
    if (-not ($HostEntry.PSObject.Properties.Name -contains 'Rows')) { return 0 }

    $rows = $HostEntry.Rows
    if (-not $rows) { return 0 }

    try {
        if ($rows -is [System.Collections.ICollection]) {
            return [int]$rows.Count
        } elseif ($rows -is [System.Collections.IDictionary]) {
            return [int]$rows.Count
        } elseif ($rows.PSObject.Properties.Name -contains 'Count') {
            return [int]$rows.Count
        } elseif ($rows -is [System.Collections.IEnumerable]) {
            $counter = 0
            foreach ($item in $rows) { $counter++ }
            return $counter
        }
    } catch {
        return 0
    }
    return 0
}

function Import-SiteExistingRowCachePrimedHosts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$SiteEntry
    )

    if (-not $SiteEntry -or -not ($SiteEntry.PSObject.Properties.Name -contains 'PrimedEntries')) { return }
    $primedEntries = $SiteEntry.PrimedEntries
    if (-not $primedEntries) { return }

    $entries = $SiteEntry.Entries
    if (-not $entries) {
        $entries = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $SiteEntry.Entries = $entries
    }

    foreach ($host in $primedEntries.Keys) {
        if ($entries.ContainsKey($host)) { continue }
        $entries[$host] = Normalize-SiteExistingRowCacheHostEntry -Entry (Copy-SiteExistingRowCacheHostEntry -Entry $primedEntries[$host])
    }
}

function Import-SiteExistingRowCacheHostFromPrimedData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$SiteEntry,
        [Parameter(Mandatory)][string]$Hostname
    )

    if (-not $SiteEntry -or -not ($SiteEntry.PSObject.Properties.Name -contains 'PrimedEntries')) { return $null }
    $primedEntries = $SiteEntry.PrimedEntries
    if (-not $primedEntries -or -not $primedEntries.ContainsKey($Hostname)) { return $null }

    $hostEntry = Normalize-SiteExistingRowCacheHostEntry -Entry (Copy-SiteExistingRowCacheHostEntry -Entry $primedEntries[$Hostname])
    if (-not $SiteEntry.Entries) {
        $SiteEntry.Entries = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }
    $SiteEntry.Entries[$Hostname] = $hostEntry
    return $hostEntry
}

function Get-SiteExistingRowCacheSnapshot {
    [CmdletBinding()]
    param()

    $snapshot = [System.Collections.Generic.List[object]]::new()
    if (-not $script:SiteExistingRowCache) { return ,$snapshot }

    foreach ($siteKey in $script:SiteExistingRowCache.Keys) {
        $siteEntry = $script:SiteExistingRowCache[$siteKey]
        if (-not $siteEntry) { continue }

        $entries = $null
        if ($siteEntry.PSObject.Properties.Name -contains 'Entries') {
            $entries = $siteEntry.Entries
        }
        if ((-not $entries -or $entries.Count -eq 0) -and $siteEntry.PSObject.Properties.Name -contains 'PrimedEntries') {
            $entries = $siteEntry.PrimedEntries
        }
        if (-not $entries -or $entries.Count -eq 0) { continue }

        foreach ($hostKey in $entries.Keys) {
            $hostEntry = Normalize-SiteExistingRowCacheHostEntry -Entry $entries[$hostKey]
            if (-not $hostEntry -or -not $hostEntry.Rows) { continue }

            $rowsCopy = @{}
            try {
                foreach ($rowKey in $hostEntry.Rows.Keys) {
                    $rowsCopy[$rowKey] = $hostEntry.Rows[$rowKey]
                }
            } catch {
                $rowsCopy = @{}
            }

            $snapshot.Add([pscustomobject]@{
                    Site     = $siteKey
                    Hostname = $hostKey
                    Rows     = $rowsCopy
                }) | Out-Null
        }
    }

    return ,$snapshot
}

function Set-SiteExistingRowCacheSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IEnumerable]$Snapshot
    )

    Clear-SiteExistingRowCache
    if (-not $Snapshot) { return }

    foreach ($item in $Snapshot) {
        if (-not $item) { continue }
        $siteCode = '' + $item.Site
        $hostname = '' + $item.Hostname
        if ([string]::IsNullOrWhiteSpace($siteCode) -or [string]::IsNullOrWhiteSpace($hostname)) { continue }

        $normalizedSiteCode = $siteCode.Trim()
        $normalizedHostname = $hostname.Trim()
        if ([string]::IsNullOrWhiteSpace($normalizedSiteCode) -or [string]::IsNullOrWhiteSpace($normalizedHostname)) { continue }

        $siteEntry = Get-SiteExistingRowCacheEntry -SiteCode $normalizedSiteCode
        $siteEntryEntries = $siteEntry.Entries
        if (-not $siteEntryEntries) { continue }

        $hostRowsDictionary = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        if ($item.Rows -is [System.Collections.IDictionary]) {
            foreach ($rowKey in $item.Rows.Keys) {
                $hostRowsDictionary[$rowKey] = $item.Rows[$rowKey]
            }
        }

        $hostSnapshot = [pscustomobject]@{
            Rows                    = $hostRowsDictionary
            LoadSignatureDurationMs = 0.0
            Hydrated                = $true
            CachedAt                = [DateTime]::UtcNow
            Source                  = 'Snapshot'
        }

        $siteEntryEntries[$normalizedHostname] = $hostSnapshot
        if ($siteEntry.PSObject.Properties.Name -contains 'PrimedEntries') {
            $siteEntry.PrimedEntries[$normalizedHostname] = Copy-SiteExistingRowCacheHostEntry -Entry $hostSnapshot
        }
        try { $siteEntry.Hydrated = $true } catch { }
        try { $siteEntry.Source = 'Snapshot' } catch { }
        try { $siteEntry.CachedAt = [DateTime]::UtcNow } catch { }
    }

    $script:SiteExistingRowCacheSnapshotLoaded = $true
}

function Import-SiteExistingRowCacheSnapshotFromEnv {
    [CmdletBinding()]
    param(
        [switch]$Force
    )

    if (-not $Force -and $script:SiteExistingRowCacheSnapshotLoaded) { return }
    if ($Force) { $script:SiteExistingRowCacheSnapshotLoaded = $false }

    $path = $null
    try {
        if ($env:STATETRACE_SITE_EXISTING_ROW_CACHE_SNAPSHOT) {
            $path = '' + $env:STATETRACE_SITE_EXISTING_ROW_CACHE_SNAPSHOT
        }
    } catch {
        $path = $null
    }
    if ([string]::IsNullOrWhiteSpace($path)) { return }
    if (-not (Test-Path -LiteralPath $path)) { return }

    try {
        $snapshot = Import-Clixml -Path $path
        if ($snapshot -and ($snapshot -isnot [System.Collections.IEnumerable] -or ($snapshot -is [string]))) {
            $snapshot = @($snapshot)
        }
        if ($snapshot -and ($snapshot | Measure-Object).Count -gt 0) {
            Set-SiteExistingRowCacheSnapshot -Snapshot $snapshot
            $script:SiteExistingRowCacheSnapshotLoaded = $true
        }
    } catch {
        Write-Warning ("Failed to import site existing row cache snapshot '{0}': {1}" -f $path, $_.Exception.Message)
    }
}

function Write-SiteExistingRowCacheTelemetry {
    [CmdletBinding()]
    param(
        [string]$Site,
        [string]$Hostname,
        [bool]$CacheEnabled,
        [System.Collections.Concurrent.ConcurrentDictionary[string, object]]$Entries,
        [object]$HostEntry,
        [bool]$CacheHit,
        [bool]$SkipSetting,
        [string[]]$SkipSources,
        [string]$ExistingRowSource,
        [bool]$LoadCacheHit,
        [bool]$LoadCacheMiss,
        [bool]$LoadCacheRefreshed
    )

    $hostEntryRows = Get-SiteExistingRowCacheHostRowCount -HostEntry $HostEntry
    $payload = @{
        Site                = $Site
        Hostname            = $Hostname
        CacheEnabled        = [bool]$CacheEnabled
        SiteHostEntryCount  = if ($Entries) { $Entries.Count } else { 0 }
        HostEntryExists     = [bool]$HostEntry
        HostEntryRowCount   = $hostEntryRows
        CacheHit            = [bool]$CacheHit
        SkipSiteCacheUpdate = [bool]$SkipSetting
        SkipSources         = if ($SkipSources) { @($SkipSources) } else { @() }
        ExistingRowSource   = if ($ExistingRowSource) { $ExistingRowSource } else { 'Unknown' }
        LoadCacheHit        = [bool]$LoadCacheHit
        LoadCacheMiss       = [bool]$LoadCacheMiss
        LoadCacheRefreshed  = [bool]$LoadCacheRefreshed
    }

    if ($Entries -and $Entries.Count -gt 0) {
        try {
            $hostSamples = [System.Collections.Generic.List[string]]::new()
            foreach ($entryKeyCandidate in $Entries.Keys) {
                if ($hostSamples.Count -ge 5) { break }
                if ($null -eq $entryKeyCandidate) { continue }
                try { $hostSamples.Add(('' + $entryKeyCandidate)) | Out-Null } catch { }
            }
            if ($hostSamples.Count -gt 0) {
                $payload['SiteHostEntriesSample'] = $hostSamples.ToArray()
            }
        } catch { }
    }

    try {
        TelemetryModule\Write-StTelemetryEvent -Name 'SiteExistingRowCacheState' -Payload $payload
    } catch { }
}

function Get-InterfaceSignatureFromValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][System.Collections.IEnumerable]$Values
    )

    $builder = New-Object System.Text.StringBuilder
    $first = $true

    foreach ($rawValue in $Values) {
        if (-not $first) {
            [void]$builder.Append('|')
        } else {
            $first = $false
        }

        $text = ''
        if ($null -ne $rawValue -and $rawValue -ne [System.DBNull]::Value) {
            $text = '' + $rawValue
        }

        $lengthValue = 0
        try { $lengthValue = [int]$text.Length } catch { $lengthValue = 0 }
        [void]$builder.Append($lengthValue)
        [void]$builder.Append(':')
        [void]$builder.Append($text)
    }

    return $builder.ToString()
}

function Get-InterfaceRowSignature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][psobject]$Row
    )

    $propertyBag = $Row.PSObject.Properties
    $values = [System.Collections.Generic.List[object]]::new($script:InterfaceComparisonProperties.Count)

    foreach ($prop in $script:InterfaceComparisonProperties) {
        $member = $propertyBag[$prop]
        if ($null -ne $member) {
            $values.Add($member.Value) | Out-Null
        } else {
            $values.Add($null) | Out-Null
        }
    }

    return Get-InterfaceSignatureFromValues -Values $values
}

function Test-IsAdodbConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Connection
    )

    if ($null -eq $Connection) { return $false }
    if ($Connection -is [System.__ComObject]) { return $true }
    try {
        foreach ($name in $Connection.PSObject.TypeNames) {
            if ($name -eq 'ADODB.Connection') { return $true }
        }
    } catch { }
    return $false
}

function Release-ComObjectSafe {
    [CmdletBinding()]
    param(
        [Parameter()][object]$ComObject
    )

    if ($null -eq $ComObject) { return }
    if ($ComObject -is [System.__ComObject]) {
        try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($ComObject) } catch { }
    }
}

function New-AdodbTextCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Connection,
        [Parameter(Mandatory=$true)][string]$CommandText
    )

    try {
        $command = New-Object -ComObject 'ADODB.Command'
    } catch {
        return $null
    }

    try {
        $command.ActiveConnection = $Connection
        $command.CommandType = $script:AdCmdText
        $command.CommandText = $CommandText
        return $command
    } catch {
        Release-ComObjectSafe -ComObject $command
        return $null
    }
}

function New-AdodbInterfaceSeedRecordset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Connection
    )

    if (-not (Test-IsAdodbConnection -Connection $Connection)) { return $null }

    try {
        $recordset = New-Object -ComObject 'ADODB.Recordset'
    } catch {
        return $null
    }

    $opened = $false
    try {
        try { $recordset.CursorLocation = $script:AdUseClient } catch { }
        try { $recordset.CursorType = $script:AdOpenStatic } catch { }
        try { $recordset.LockType = $script:AdLockBatchOptimistic } catch { }

        $recordset.ActiveConnection = $Connection
        $recordset.Source = 'SELECT BatchId, Hostname, RunDateText, RunDate, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip FROM InterfaceBulkSeed WHERE 1=0'
        $recordset.Open()
        $opened = $true
        return $recordset
    } catch {
        if ($opened -and $recordset -and $recordset.State -ne 0) {
            try { $recordset.Close() } catch { }
        }
        Release-ComObjectSafe -ComObject $recordset
        return $null
    }
}

function Add-AdodbParameter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Command,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][int]$Type,
        [Parameter()][object]$Size
    )

    if (-not $Command) { return $null }

    try {
        $sizeValue = $null
        if ($PSBoundParameters.ContainsKey('Size')) {
            $sizeValue = $Size
            if ($sizeValue -is [System.Array]) {
                if ($sizeValue.Length -gt 0) {
                    $sizeValue = $sizeValue[0]
                } else {
                    $sizeValue = $null
                }
            }
            if ($sizeValue -ne $null -and -not ($sizeValue -is [int])) {
                try { $sizeValue = [int]$sizeValue } catch { $sizeValue = 0 }
            }
        }

        if ($sizeValue -is [int] -and $sizeValue -gt 0) {
            $parameter = $Command.CreateParameter($Name, $Type, $script:AdParamInput, $sizeValue)
        } else {
            $parameter = $Command.CreateParameter($Name, $Type, $script:AdParamInput)
        }
        [void]$Command.Parameters.Append($parameter)
        return $parameter
    } catch {
        return $null
    }
}

function Set-AdodbParameterValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Parameter,
        [Parameter()][object]$Value
    )

    if (-not $Parameter) { return }

    $valueToAssign = $Value
    if ($null -eq $Value) {
        $valueToAssign = [System.DBNull]::Value
    }

    if ($Parameter -is [System.__ComObject]) {
        if (-not $script:AdodbParameterWrapperTypeResolved) {
            $script:AdodbParameterWrapperTypeResolved = $true
            try {
                $script:AdodbParameterWrapperType = [type]::GetTypeFromProgID('ADODB.Parameter', $true)
            } catch {
                $script:AdodbParameterWrapperType = $null
            }
        }

        if ($script:AdodbParameterWrapperType) {
            $wrapperProperty = $Parameter.PSObject.Properties['__AdodbParameterWrapper']
            $wrapper = if ($wrapperProperty) { $wrapperProperty.Value } else { $null }

            if (-not $wrapper) {
                try {
                    $wrapper = [System.Runtime.InteropServices.Marshal]::CreateWrapperOfType($Parameter, $script:AdodbParameterWrapperType)
                    if ($wrapperProperty) {
                        $wrapperProperty.Value = $wrapper
                    } else {
                        $Parameter.PSObject.Properties.Add((New-Object PSNoteProperty -ArgumentList '__AdodbParameterWrapper', $wrapper))
                    }
                } catch {
                    $wrapper = $null
                }
            }

            if ($wrapper) {
                try {
                    $wrapper.Value = $valueToAssign
                    return
                } catch {
                    # fall back to late binding attempt
                }
            }
        }

        try {
            $bindingFlags = [System.Reflection.BindingFlags]::SetProperty
            $culture = [System.Globalization.CultureInfo]::InvariantCulture
            $Parameter.GetType().InvokeMember('Value', $bindingFlags, $null, $Parameter, @($valueToAssign), $culture) | Out-Null
            return
        } catch {
            # fall through to default assignment
        }
    }

    $Parameter.Value = $valueToAssign
}

function Invoke-AdodbNonQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Connection,
        [Parameter(Mandatory=$true)][string]$CommandText,
        [switch]$ExpectRecords
    )

    if ($ExpectRecords) {
        try {
            return $Connection.Execute($CommandText)
        } catch {
            throw
        }
    }

    $recordsAffected = 0
    $useOptions = Test-IsAdodbConnection -Connection $Connection
    $options = if ($useOptions) { $script:AdExecuteNoRecords } else { $null }

    try {
        $refRecords = [ref]$recordsAffected
        if ($useOptions) {
            $executeSucceeded = $false
            try {
                $Connection.Execute($CommandText, $refRecords, $options) | Out-Null
                $executeSucceeded = $true
            } catch {
                # fall through to retry without optional arguments (useful for mocks)
            }

            if (-not $executeSucceeded) {
                $Connection.Execute($CommandText) | Out-Null
                $recordsAffected = 0
            }
        } else {
            $Connection.Execute($CommandText) | Out-Null
        }

        return $recordsAffected
    } catch {
        throw
    }
}

function Ensure-SpanInfoTableExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Connection
    )

    if ($script:SpanTablesEnsured) {
        return
    }
    if (-not (Test-IsAdodbConnection -Connection $Connection)) {
        return
    }

    $createSpanInfoTable = @'
CREATE TABLE SpanInfo (
    Hostname    TEXT(64),
    Vlan        TEXT(32),
    RootSwitch  TEXT(64),
    RootPort    TEXT(32),
    Role        TEXT(32),
    Upstream    TEXT(64),
    LastUpdated DATETIME
);
'@
    $createSpanHistoryTable = @'
CREATE TABLE SpanHistory (
    ID          COUNTER     PRIMARY KEY,
    Hostname    TEXT(64),
    RunDate     DATETIME,
    Vlan        TEXT(32),
    RootSwitch  TEXT(64),
    RootPort    TEXT(32),
    Role        TEXT(32),
    Upstream    TEXT(64)
);
'@
    $createSpanInfoIndex     = "CREATE INDEX idx_spaninfo_host_vlan ON SpanInfo (Hostname, Vlan)"
    $createSpanHistoryIndex  = "CREATE INDEX idx_spanhistory_host ON SpanHistory (Hostname)"

    try { Invoke-AdodbNonQuery -Connection $Connection -CommandText $createSpanInfoTable | Out-Null } catch { }
    try { Invoke-AdodbNonQuery -Connection $Connection -CommandText $createSpanHistoryTable | Out-Null } catch { }
    try { Invoke-AdodbNonQuery -Connection $Connection -CommandText $createSpanInfoIndex | Out-Null } catch { }
    try { Invoke-AdodbNonQuery -Connection $Connection -CommandText $createSpanHistoryIndex | Out-Null } catch { }

    $script:SpanTablesEnsured = $true
}

function Ensure-InterfaceTableIndexes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Connection
    )

    if ($script:InterfaceIndexesEnsured -or $script:InterfaceIndexesEnsureAttempted) { return }
    if (-not (Test-IsAdodbConnection -Connection $Connection)) { return }

    $script:InterfaceIndexesEnsureAttempted = $true

    $indexStatements = @(
        "CREATE INDEX IX_Interfaces_Hostname ON Interfaces (Hostname)",
        "CREATE INDEX IX_Interfaces_HostnamePort ON Interfaces (Hostname, Port)",
        "CREATE INDEX IX_InterfaceHistory_HostnameRunDate ON InterfaceHistory (Hostname, RunDate)"
    )

    foreach ($sql in $indexStatements) {
        try {
            Invoke-AdodbNonQuery -Connection $Connection -CommandText $sql | Out-Null
        } catch {
            $message = $_.Exception.Message
            if ($null -ne $message -and $message -match 'already exists') {
                continue
            }

            Write-Verbose ("Failed to apply Access index '{0}': {1}" -f $sql, $message)
        }
    }

    $script:InterfaceIndexesEnsured = $true
}

function ConvertTo-DbDateTime {
    [CmdletBinding()]
    param(
        [Parameter()][string]$RunDateString
    )

    if ([string]::IsNullOrWhiteSpace($RunDateString)) { return $null }

    $formats = @('yyyy-MM-dd HH:mm:ss', 'yyyy-MM-ddTHH:mm:ss', 'o')
    foreach ($fmt in $formats) {
        try {
            return [DateTime]::ParseExact($RunDateString, $fmt, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeLocal)
        } catch { }
    }

    try { return [DateTime]::Parse($RunDateString, [System.Globalization.CultureInfo]::InvariantCulture) } catch { }
    try { return [DateTime]::Parse($RunDateString) } catch { }

    return $null
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
    if ($Facts.PSObject.Properties.Name -contains 'AuthDefaultVLAN' -and $null -ne $Facts.AuthDefaultVLAN -and $Facts.AuthDefaultVLAN -ne '') {
        try { $rawAuthVlan = [string]$Facts.AuthDefaultVLAN } catch { $rawAuthVlan = '' + $Facts.AuthDefaultVLAN }
    }
    $escAuthVlan = $rawAuthVlan -replace "'", "''"
    # Compose the authentication block text
    $authBlockText = ''
    if ($Facts.PSObject.Properties.Name -contains 'AuthenticationBlock' -and $Facts.AuthenticationBlock) {
        $authBlockText = ($Facts.AuthenticationBlock -join "`r`n")
    }
    $escAuthBlock = $authBlockText -replace "'", "''"

    $paramValues = @{
        Make            = $rawMake
        Model           = $rawModel
        Uptime          = $rawUptime
        Site            = $SiteCode
        Building        = $rawBuilding
        Room            = $rawRoom
        Ports           = $portCount
        AuthDefaultVlan = $rawAuthVlan
        AuthBlock       = $authBlockText
    }

    $runDateValue = ConvertTo-DbDateTime -RunDateString $RunDateString
    if ($runDateValue -and (Test-IsAdodbConnection -Connection $Connection)) {
        if (Invoke-DeviceSummaryParameterized -Connection $Connection -Hostname $Hostname -Values $paramValues -RunDate $runDateValue) {
            return
        }
    }

    # Build update and insert statements.  The update will modify an existing
    $updateSql = "UPDATE DeviceSummary SET Make='$escMake', Model='$escModel', Uptime='$escUptime', Site='$escSite', Building='$escBuilding', Room='$escRoom', Ports=$portCount, AuthDefaultVLAN='$escAuthVlan', AuthBlock='$escAuthBlock' WHERE Hostname='$escHostname'"
    $insertSql = "INSERT INTO DeviceSummary (Hostname, Make, Model, Uptime, Site, Building, Room, Ports, AuthDefaultVLAN, AuthBlock) VALUES ('$escHostname', '$escMake', '$escModel', '$escUptime', '$escSite', '$escBuilding', '$escRoom', $portCount, '$escAuthVlan', '$escAuthBlock')"
    # Execute update and insert sequentially
    try {
        Invoke-AdodbNonQuery -Connection $Connection -CommandText $updateSql | Out-Null
    } catch {
        # ignore update errors
    }
    try {
        Invoke-AdodbNonQuery -Connection $Connection -CommandText $insertSql | Out-Null
    } catch {
        # duplicate key is expected on upsert; ignore
    }
    # Insert a row into DeviceHistory. When parameterization isn't available,
    # format the literal from the parsed DateTime to avoid locale issues.
    $runDateLiteral = "#$RunDateString#"
    if ($runDateValue) {
        try {
            $runDateLiteral = "#$($runDateValue.ToString('yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture))#"
        } catch { }
    }
    $histSql = "INSERT INTO DeviceHistory (Hostname, RunDate, Make, Model, Uptime, Site, Building, Room, Ports, AuthDefaultVLAN, AuthBlock) VALUES ('$escHostname', $runDateLiteral, '$escMake', '$escModel', '$escUptime', '$escSite', '$escBuilding', '$escRoom', $portCount, '$escAuthVlan', '$escAuthBlock')"
    try {
        Invoke-AdodbNonQuery -Connection $Connection -CommandText $histSql | Out-Null
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
        [Parameter(Mandatory=$false)][object[]]$Templates,
        [string]$SiteCode,
        [bool]$SkipSiteCacheUpdate = $false
    )

    $script:LastInterfaceSyncTelemetry = $null

    $loadExistingDurationMs = 0.0
    $loadExistingRowSetCount = 0
    $diffDurationMs = 0.0
    $diffComparisonDurationMs = 0.0
    $deleteDurationMs = 0.0
    $fallbackDurationMs = 0.0
    $loadSignatureDurationMs = 0.0
    $diffSignatureDurationMs = 0.0
    $totalFactsCount = 0
    $fallbackUsed = $false
    $diffRowsCompared = 0
    $diffRowsUnchanged = 0
    $diffRowsChanged = 0
    $diffRowsInserted = 0

    $escHostname = $Hostname -replace "'", "''"

    $ifaceRecords = $null
    if ($Facts.PSObject.Properties.Name -contains 'InterfacesCombined') {
        $ifaceRecords = $Facts.InterfacesCombined
    } elseif ($Facts.PSObject.Properties.Name -contains 'Interfaces') {
        $ifaceRecords = $Facts.Interfaces
    }
    if (-not $ifaceRecords) { $ifaceRecords = @() }

    Ensure-InterfaceTableIndexes -Connection $Connection

    Import-SiteExistingRowCacheSnapshotFromEnv

    $skipSiteCacheUpdateFromParameter = ($SkipSiteCacheUpdate -eq $true)
    $skipSiteCacheUpdateFromScript = ($script:SkipSiteCacheUpdate -eq $true)
    $skipSiteCacheUpdateFromEnvironment = $false
    $skipSiteCacheUpdateFlag = $skipSiteCacheUpdateFromScript
    try {
        $envSkipValue = [string]::Empty
        if ($env:STATETRACE_SKIP_SITECACHE_UPDATE) {
            $envSkipValue = '' + $env:STATETRACE_SKIP_SITECACHE_UPDATE
        }
        if (-not [string]::IsNullOrWhiteSpace($envSkipValue)) {
            $envSkipEnabled = $false
            if ([string]::Equals($envSkipValue, '1', [System.StringComparison]::OrdinalIgnoreCase)) {
                $envSkipEnabled = $true
            } else {
                $parsedEnvSkip = $false
                if ([bool]::TryParse($envSkipValue, [ref]$parsedEnvSkip) -and $parsedEnvSkip) {
                    $envSkipEnabled = $true
                }
            }
            if ($envSkipEnabled) {
                $skipSiteCacheUpdateFromEnvironment = $true
                $skipSiteCacheUpdateFlag = $true
            }
        }
    } catch { }
    $skipSiteCacheUpdateSetting = ($skipSiteCacheUpdateFromParameter -or $skipSiteCacheUpdateFlag -or $skipSiteCacheUpdateFromEnvironment)

    $existingRows = $null
    $normalizedHostname = ('' + $Hostname).Trim()
    $siteCodeValue = $SiteCode
    if (-not $siteCodeValue -and $Facts) {
        if ($Facts.PSObject.Properties.Name -contains 'SiteCode' -and $Facts.SiteCode) {
            $candidateSiteCode = '' + $Facts.SiteCode
            if (-not [string]::IsNullOrWhiteSpace($candidateSiteCode)) {
                $siteCodeValue = $candidateSiteCode.Trim()
            }
        } elseif ($Facts.PSObject.Properties.Name -contains 'Site' -and $Facts.Site) {
            $candidateSite = '' + $Facts.Site
            if (-not [string]::IsNullOrWhiteSpace($candidateSite)) {
                $siteCodeValue = $candidateSite.Trim()
            }
        }
    }
    if (-not $siteCodeValue) {
        try {
            $siteCandidate = DeviceRepositoryModule\Get-SiteFromHostname -Hostname $Hostname
            if ($siteCandidate) {
                $siteCodeValue = ('' + $siteCandidate).Trim()
            }
        } catch { }
    }

    $siteExistingCacheEntry = $null
    $siteExistingCacheEntries = $null
    $siteExistingCacheHostEntry = $null
    $siteExistingCacheEnabled = $false
    $siteExistingCacheHit = $false
    $siteExistingCacheHostEntryRowCount = 0
    if (-not [string]::IsNullOrWhiteSpace($siteCodeValue) -and $skipSiteCacheUpdateSetting) {
        $siteExistingCacheEnabled = $true
        try {
            $siteExistingCacheEntry = Get-SiteExistingRowCacheEntry -SiteCode $siteCodeValue
        } catch {
            $siteExistingCacheEntry = $null
        }
        if ($siteExistingCacheEntry) {
            try { Import-SiteExistingRowCachePrimedHosts -SiteEntry $siteExistingCacheEntry | Out-Null } catch { }
            if ($siteExistingCacheEntry.PSObject.Properties.Name -contains 'Entries') {
                $siteExistingCacheEntries = $siteExistingCacheEntry.Entries
            }
        }
    }

    if ($siteExistingCacheEnabled -and -not $siteExistingCacheEntry) {
        try {
            Import-SiteExistingRowCacheSnapshotFromEnv -Force
            $siteExistingCacheEntry = Get-SiteExistingRowCacheEntry -SiteCode $siteCodeValue
            if ($siteExistingCacheEntry -and $siteExistingCacheEntry.PSObject.Properties.Name -contains 'Entries') {
                $siteExistingCacheEntries = $siteExistingCacheEntry.Entries
            }
            if ($siteExistingCacheEntry) {
                try { Import-SiteExistingRowCachePrimedHosts -SiteEntry $siteExistingCacheEntry | Out-Null } catch { }
            }
        } catch { }
    }

    if ($siteExistingCacheEntries -and $siteExistingCacheEntries.ContainsKey($normalizedHostname)) {
        $siteExistingCacheHostEntry = Normalize-SiteExistingRowCacheHostEntry -Entry $siteExistingCacheEntries[$normalizedHostname]
        $siteExistingCacheEntries[$normalizedHostname] = $siteExistingCacheHostEntry
    } elseif ($siteExistingCacheEntry) {
        try { $siteExistingCacheHostEntry = Import-SiteExistingRowCacheHostFromPrimedData -SiteEntry $siteExistingCacheEntry -Hostname $normalizedHostname } catch { $siteExistingCacheHostEntry = $null }
        if (-not $siteExistingCacheHostEntry -and $siteExistingCacheEnabled -and $siteExistingCacheEntries -and $siteExistingCacheEntries.Count -eq 0) {
            try {
                Import-SiteExistingRowCacheSnapshotFromEnv -Force
                $siteExistingCacheEntry = Get-SiteExistingRowCacheEntry -SiteCode $siteCodeValue
                if ($siteExistingCacheEntry -and $siteExistingCacheEntry.PSObject.Properties.Name -contains 'Entries') {
                    $siteExistingCacheEntries = $siteExistingCacheEntry.Entries
                }
                if ($siteExistingCacheEntries -and $siteExistingCacheEntries.ContainsKey($normalizedHostname)) {
                    $siteExistingCacheHostEntry = Normalize-SiteExistingRowCacheHostEntry -Entry $siteExistingCacheEntries[$normalizedHostname]
                    $siteExistingCacheEntries[$normalizedHostname] = $siteExistingCacheHostEntry
                } else {
                    try { $siteExistingCacheHostEntry = Import-SiteExistingRowCacheHostFromPrimedData -SiteEntry $siteExistingCacheEntry -Hostname $normalizedHostname } catch { $siteExistingCacheHostEntry = $null }
                }
            } catch { }
        }
    }

    $loadCacheHit = $false
    $loadCacheMiss = $false
    $loadCacheRefreshed = $false
    $siteCacheResolveContext = @{
        Initial = @{
            Status = 'NotAttempted'
            HostMapType = ''
            HostCount = 0
            MatchedKey = ''
            KeysSample = ''
            CachedAt = $null
            CachedAtText = ''
            EntryType = ''
            PortCount = 0
            PortKeysSample = ''
            PortSignatureSample = ''
            PortSignatureMissingCount = 0
            PortSignatureEmptyCount = 0
        }
        Refresh = @{
            Status = 'NotAttempted'
            HostMapType = ''
            HostCount = 0
            MatchedKey = ''
            KeysSample = ''
            CachedAt = $null
            CachedAtText = ''
            EntryType = ''
            PortCount = 0
            PortKeysSample = ''
            PortSignatureSample = ''
            PortSignatureMissingCount = 0
            PortSignatureEmptyCount = 0
        }
    }
    $cachedRowCount = 0
    $cachePrimedRowCount = 0
    $siteCacheUpdateDurationMs = 0.0
    $siteCacheFetchDurationMs = 0.0
    $siteCacheRefreshDurationMs = 0.0
    $siteCacheFetchStatus = $null
    $siteCacheSnapshotDurationMs = 0.0
    $siteCacheRecordsetDurationMs = 0.0
    $siteCacheRecordsetProjectDurationMs = 0.0
    $siteCacheBuildDurationMs = 0.0
    $siteCacheHostMapDurationMs = 0.0
    $siteCacheHostMapSignatureMatchCount = 0L
    $siteCacheHostMapSignatureRewriteCount = 0L
    $siteCacheHostMapEntryAllocationCount = 0L
    $siteCacheHostMapEntryPoolReuseCount = 0L
    $siteCacheHostMapLookupCount = 0L
    $siteCacheHostMapLookupMissCount = 0L
    $siteCacheHostMapCandidateMissingCount = 0L
    $siteCacheHostMapCandidateSignatureMissingCount = 0L
    $siteCacheHostMapCandidateSignatureMismatchCount = 0L
    $siteCacheHostMapCandidateFromPreviousCount = 0L
    $siteCacheHostMapCandidateFromPoolCount = 0L
    $siteCacheHostMapCandidateInvalidCount = 0L
    $siteCacheHostMapCandidateMissingSamples = @()
    $siteCacheHostMapSignatureMismatchSamples = @()
    $siteCachePreviousHostCount = 0
    $siteCachePreviousPortCount = 0
    $siteCachePreviousHostSample = ''
    $siteCachePreviousSnapshotStatus = 'CacheEntryMissing'
    $siteCachePreviousSnapshotHostMapType = ''
    $siteCachePreviousSnapshotHostCount = 0
    $siteCachePreviousSnapshotPortCount = 0
    $siteCachePreviousSnapshotException = ''
    $siteCacheSortDurationMs = 0.0
    $siteCacheHostCount = 0
    $siteCacheQueryDurationMs = 0.0
    $siteCacheExecuteDurationMs = 0.0
$siteCacheMaterializeDurationMs = 0.0
$siteCacheMaterializeProjectionDurationMs = 0.0
$siteCacheMaterializePortSortDurationMs = 0.0
$siteCacheMaterializePortSortCacheHitCount = 0
$siteCacheMaterializePortSortCacheMissCount = 0
$siteCacheMaterializePortSortCacheSize = 0
$siteCacheMaterializePortSortCacheHitRatio = 0.0
$siteCacheMaterializePortSortUniquePortCount = 0
$siteCacheMaterializePortSortMissSamples = @()
$siteCacheMaterializeTemplateDurationMs = 0.0
$siteCacheMaterializeTemplateLookupDurationMs = 0.0
$siteCacheMaterializeTemplateApplyDurationMs = 0.0
$siteCacheMaterializeObjectDurationMs = 0.0
$siteCacheMaterializeTemplateCacheHitCount = 0
$siteCacheMaterializeTemplateCacheMissCount = 0
$siteCacheMaterializeTemplateReuseCount = 0
$siteCacheMaterializeTemplateCacheHitRatio = 0.0
$siteCacheMaterializeTemplateApplyCount = 0
$siteCacheMaterializeTemplateDefaultedCount = 0
$siteCacheMaterializeTemplateAuthTemplateMissingCount = 0
$siteCacheMaterializeTemplateNoTemplateMatchCount = 0
$siteCacheMaterializeTemplateHintAppliedCount = 0
$siteCacheMaterializeTemplateSetPortColorCount = 0
$siteCacheMaterializeTemplateSetConfigStatusCount = 0
$siteCacheMaterializeTemplateApplySamples = @()
$siteCacheTemplateDurationMs = 0.0
    $siteCacheQueryAttempts = 0
    $siteCacheExclusiveRetryCount = 0
    $siteCacheExclusiveWaitDurationMs = 0.0
    $siteCacheProvider = $null
    $siteCacheProviderFromMetrics = $null
    $siteCacheProviderReason = 'NotEvaluated'
    $siteCacheResultRowCount = 0
    $cacheComparisonCandidateCount = 0
    $cacheComparisonSignatureMatchCount = 0
    $cacheComparisonSignatureMismatchCount = 0
    $cacheComparisonSignatureMissingCount = 0
    $cacheComparisonMissingPortCount = 0
    $cacheComparisonObsoletePortCount = 0
    $siteCacheExistingRowCount = 0
    $siteCacheExistingRowKeysSample = ''
    $siteCacheExistingRowValueType = ''
    $siteCacheExistingRowSource = 'Unknown'
    $sharedCacheDebugEnabled = $false
    try { $sharedCacheDebugEnabled = [string]::Equals($env:STATETRACE_SHARED_CACHE_DEBUG, '1', [System.StringComparison]::OrdinalIgnoreCase) } catch { $sharedCacheDebugEnabled = $false }
    $emitSharedCacheDebug = {
        param(
            [string]$Stage,
            [string]$Outcome,
            [int]$HostCount = 0,
            [int]$TotalRows = 0,
            [string]$CacheStatus = '',
            [string]$Hostname = '',
            [string]$Provider = '',
            [string]$ProviderReason = '',
            [bool]$LoadCacheHit = $false,
            [bool]$LoadCacheMiss = $false
        )

        if (-not $sharedCacheDebugEnabled) { return }

        $payload = @{
            Stage          = if ($Stage) { $Stage } else { '' }
            Site           = if ($siteCodeValue) { $siteCodeValue } else { '' }
            Outcome        = if ($Outcome) { $Outcome } else { '' }
            HostCount      = [int]$HostCount
            TotalRows      = [int]$TotalRows
            CacheStatus    = if ($CacheStatus) { $CacheStatus } else { '' }
            Hostname       = if ($Hostname) { $Hostname } else { '' }
            FetchStatus    = if ($siteCacheFetchStatus) { $siteCacheFetchStatus } else { '' }
            HitSource      = if ($siteCacheHitSource) { $siteCacheHitSource } else { '' }
            SkipHydrate    = [bool]$skipSiteCacheHydration
            Provider       = if ($Provider) { $Provider } else { '' }
            ProviderReason = if ($ProviderReason) { $ProviderReason } else { '' }
            LoadCacheHit   = [bool]$LoadCacheHit
            LoadCacheMiss  = [bool]$LoadCacheMiss
        }

        try { TelemetryModule\Write-StTelemetryEvent -Name 'SharedCacheDebug' -Payload $payload } catch { }
    }

    $getSharedCacheDebugStats = {
        param(
            $EntryCandidate = $null
        )

        $debugHostCount = 0
        $debugTotalRows = 0
        $debugCacheStatus = ''
        $candidates = @()
        if ($EntryCandidate) { $candidates += $EntryCandidate }
        if ($siteCacheEntry) { $candidates += $siteCacheEntry }
        if ($sharedSiteCacheEntry) { $candidates += $sharedSiteCacheEntry }

        foreach ($candidate in $candidates) {
            if (-not $candidate) { continue }
            if ($debugHostCount -le 0) {
                if ($candidate.PSObject.Properties.Name -contains 'HostCount') {
                    try { $debugHostCount = [int]$candidate.HostCount } catch { $debugHostCount = 0 }
                }
                if ($debugHostCount -le 0 -and $candidate.PSObject.Properties.Name -contains 'HostMap' -and $candidate.HostMap -is [System.Collections.IDictionary]) {
                    try { $debugHostCount = [int]$candidate.HostMap.Count } catch { $debugHostCount = 0 }
                }
            }
            if ($debugTotalRows -le 0) {
                if ($candidate.PSObject.Properties.Name -contains 'TotalRows') {
                    try { $debugTotalRows = [int]$candidate.TotalRows } catch { $debugTotalRows = 0 }
                }
                if ($debugTotalRows -le 0 -and $candidate.PSObject.Properties.Name -contains 'HostMap' -and $candidate.HostMap -is [System.Collections.IDictionary]) {
                    foreach ($hostEntry in @($candidate.HostMap.Values)) {
                        if ($hostEntry -is [System.Collections.IDictionary]) {
                            try { $debugTotalRows += [int]$hostEntry.Count } catch { }
                        }
                    }
                }
            }
            if ([string]::IsNullOrWhiteSpace($debugCacheStatus) -and $candidate.PSObject.Properties.Name -contains 'CacheStatus') {
                try { $debugCacheStatus = '' + $candidate.CacheStatus } catch { $debugCacheStatus = '' }
            }
        }

        if ($debugHostCount -le 0 -and $cachedHostEntry -is [System.Collections.IDictionary]) {
            $debugHostCount = 1
            if ($debugTotalRows -le 0) {
                try { $debugTotalRows = [int]$cachedHostEntry.Count } catch { $debugTotalRows = 0 }
            }
        } elseif ($debugTotalRows -le 0 -and $cachedHostEntry -is [System.Collections.IDictionary]) {
            try { $debugTotalRows = [int]$cachedHostEntry.Count } catch { $debugTotalRows = 0 }
        }

        return [pscustomobject]@{
            HostCount   = [int]$debugHostCount
            TotalRows   = [int]$debugTotalRows
            CacheStatus = if ($debugCacheStatus) { $debugCacheStatus } else { '' }
        }
    }

    $siteExistingCacheHostEntryRowCount = Get-SiteExistingRowCacheHostRowCount -HostEntry $siteExistingCacheHostEntry
    if ($siteExistingCacheHostEntryRowCount -gt 0) {
        $siteExistingCacheHit = $true
    }

    if ($siteExistingCacheHit -and $siteExistingCacheHostEntry -and $siteExistingCacheHostEntry.Rows -and $siteExistingCacheHostEntryRowCount -gt 0 -and -not $existingRows) {
        $existingRows = $siteExistingCacheHostEntry.Rows
        $loadCacheHit = $true
        $siteCacheExistingRowSource = 'SiteExistingCache'
    }

    $siteCacheEntry = $null
    $cachedHostEntry = $null
    $resolveCachedHost = {
        param(
            $entry,
            [string]$stage = 'Initial'
        )

        $context = $null
        if ($siteCacheResolveContext.ContainsKey($stage)) {
            $context = $siteCacheResolveContext[$stage]
        } else {
            $context = @{
                Status = 'NotAttempted'
                HostMapType = ''
                HostCount = 0
                MatchedKey = ''
                KeysSample = ''
                CachedAt = $null
                CachedAtText = ''
            }
            $siteCacheResolveContext[$stage] = $context
        }

        $context.Status = 'Ready'
        $context.HostMapType = ''
        $context.HostCount = 0
        $context.MatchedKey = ''
        $context.KeysSample = ''
        $context.CachedAt = $null
        $context.CachedAtText = ''
        $context.EntryType = ''
        $context.PortCount = 0
        $context.PortKeysSample = ''
        $context.PortSignatureSample = ''
        $context.PortSignatureMissingCount = 0
        $context.PortSignatureEmptyCount = 0

        $recordHostEntryDetails = {
            param($candidateEntry)

            $context.EntryType = ''
            $context.PortCount = 0
            $context.PortKeysSample = ''
            $context.PortSignatureSample = ''
            $context.PortSignatureMissingCount = 0
            $context.PortSignatureEmptyCount = 0

            if (-not $candidateEntry) { return }

            try { $context.EntryType = $candidateEntry.GetType().FullName } catch { $context.EntryType = '' }

            $portKeys = [System.Collections.Generic.List[string]]::new()
            $signatureSamples = [System.Collections.Generic.List[string]]::new()
            $signatureMissing = 0
            $signatureEmpty = 0

            $collectPortInfo = {
                param($portKeyValue, $portEntryValue)

                $normalizedKey = ''
                if ($null -ne $portKeyValue) {
                    try { $normalizedKey = ('' + $portKeyValue).Trim() } catch { $normalizedKey = '' }
                }
                if (-not [string]::IsNullOrWhiteSpace($normalizedKey) -and $portKeys.Count -lt 5) {
                    $portKeys.Add($normalizedKey) | Out-Null
                }

                $signatureValue = $null
                if ($null -ne $portEntryValue) {
                    try {
                        if ($portEntryValue -is [StateTrace.Models.InterfaceCacheEntry]) {
                            $signatureValue = $portEntryValue.Signature
                        } elseif ($portEntryValue -is [System.Collections.IDictionary]) {
                            if ($portEntryValue.Contains('Signature')) {
                                $signatureValue = $portEntryValue['Signature']
                            }
                        } else {
                            $entryPsObject = $null
                            try { $entryPsObject = $portEntryValue.PSObject } catch { $entryPsObject = $null }
                            if ($entryPsObject) {
                                $signatureProp = $entryPsObject.Properties['Signature']
                                if ($signatureProp) { $signatureValue = $signatureProp.Value }
                            }
                        }
                    } catch {
                        $signatureValue = $null
                    }
                }

                if ($null -eq $signatureValue -or $signatureValue -eq [System.DBNull]::Value) {
                    $signatureMissing++
                } else {
                    $signatureText = '' + $signatureValue
                    if ([string]::IsNullOrWhiteSpace($signatureText)) {
                        $signatureEmpty++
                    } elseif ($signatureSamples.Count -lt 5) {
                        $signatureSamples.Add($signatureText) | Out-Null
                    }
                }
            }

            if ($candidateEntry -is [System.Collections.IDictionary]) {
                try { $context.PortCount = [int]$candidateEntry.Count } catch { $context.PortCount = 0 }
                foreach ($portEntry in @($candidateEntry.GetEnumerator())) {
                    $portKey = $null
                    $portValue = $null
                    try { $portKey = $portEntry.Key } catch { $portKey = $null }
                    try { $portValue = $portEntry.Value } catch { $portValue = $null }
                    & $collectPortInfo $portKey $portValue
                }
            } elseif ($candidateEntry -is [System.Collections.IEnumerable] -and -not ($candidateEntry -is [string])) {
                $portCounter = 0
                foreach ($item in $candidateEntry) {
                    $portCounter++
                    $candidatePortKey = $null
                    if ($item -is [System.Collections.IDictionary]) {
                        try {
                            if ($item.Contains('Port')) { $candidatePortKey = $item['Port'] }
                        } catch { $candidatePortKey = $null }
                    } else {
                        $itemPsObject = $null
                        try { $itemPsObject = $item.PSObject } catch { $itemPsObject = $null }
                        if ($itemPsObject) {
                            $portProp = $itemPsObject.Properties['Port']
                            if ($portProp) { $candidatePortKey = $portProp.Value }
                        }
                    }
                    & $collectPortInfo $candidatePortKey $item
                }
                $context.PortCount = $portCounter
            }

            if ($portKeys.Count -gt 0) {
                $context.PortKeysSample = [string]::Join('|', $portKeys.ToArray())
            }
            if ($signatureSamples.Count -gt 0) {
                $context.PortSignatureSample = [string]::Join('|', $signatureSamples.ToArray())
            }
            $context.PortSignatureMissingCount = [int]$signatureMissing
            $context.PortSignatureEmptyCount = [int]$signatureEmpty
        }

        if (-not $entry) {
            $context.Status = 'EntryNull'
            return $null
        }

        if (-not $normalizedHostname) {
            $context.Status = 'HostnameMissing'
            return $null
        }

        if ($entry.PSObject.Properties.Name -contains 'CachedAt') {
            $rawCachedAt = $entry.CachedAt
            if ($rawCachedAt -is [datetime]) {
                $context.CachedAt = $rawCachedAt
                $context.CachedAtText = $rawCachedAt.ToString('o')
            } elseif ($null -ne $rawCachedAt) {
                $context.CachedAtText = '' + $rawCachedAt
                try {
                    $context.CachedAt = [datetime]$rawCachedAt
                } catch { }
            }
        }

        $hostMap = $null
        if ($entry.PSObject.Properties.Name -contains 'HostMap') {
            $hostMap = $entry.HostMap
        }

        if (-not $hostMap) {
            $context.Status = 'HostMapMissing'
            return $null
        }

        try {
            $context.HostMapType = $hostMap.GetType().FullName
        } catch {
            $context.HostMapType = ''
        }

        try {
            if ($hostMap.PSObject.Properties.Name -contains 'Count') {
                $context.HostCount = [int]$hostMap.Count
            } elseif ($hostMap -is [System.Collections.ICollection]) {
                $context.HostCount = [int]$hostMap.Count
            } elseif ($hostMap -is [System.Collections.IDictionary]) {
                $context.HostCount = [int]$hostMap.Count
            }
        } catch {
            $context.HostCount = 0
        }

        $context.Status = 'HostMapScanned'
        try {
            $sampleKeys = @()
            foreach ($cacheKey in $hostMap.Keys) {
                if ($sampleKeys.Count -ge 5) { break }
                if ($null -eq $cacheKey) { continue }
                $sampleKeys += ('' + $cacheKey)
            }
            if ($sampleKeys.Count -gt 0) {
                $context.KeysSample = [string]::Join('|', $sampleKeys)
            }
        } catch {
            $context.Status = 'EnumerationFailed'
        }

        $containsKeyMethod = $null
        try {
            $containsKeyMethod = $hostMap.PSObject.Methods['ContainsKey']
        } catch { }

        if ($containsKeyMethod) {
            try {
                if ($containsKeyMethod.Invoke($normalizedHostname)) {
                    $context.Status = 'ExactMatch'
                    $context.MatchedKey = $normalizedHostname
                    $matchedEntry = $hostMap[$normalizedHostname]
                    & $recordHostEntryDetails $matchedEntry
                    return $matchedEntry
                }
            } catch {
                $context.Status = 'ContainsKeyInvokeFailed'
            }
        } else {
            try {
                if ($hostMap.ContainsKey($normalizedHostname)) {
                    $context.Status = 'ExactMatch'
                    $context.MatchedKey = $normalizedHostname
                    $matchedEntry = $hostMap[$normalizedHostname]
                    & $recordHostEntryDetails $matchedEntry
                    return $matchedEntry
                }
            } catch {
                if ($context.Status -eq 'HostMapScanned') {
                    $context.Status = 'ContainsKeyMissing'
                }
            }
        }

        if ($context.Status -ne 'EnumerationFailed') {
            try {
                foreach ($cacheKey in $hostMap.Keys) {
                    if ([System.StringComparer]::OrdinalIgnoreCase.Equals($cacheKey, $normalizedHostname)) {
                        $context.Status = 'CaseInsensitiveMatch'
                        $context.MatchedKey = '' + $cacheKey
                        $matchedEntry = $hostMap[$cacheKey]
                        & $recordHostEntryDetails $matchedEntry
                        return $matchedEntry
                    }
                }
            } catch {
                $context.Status = 'EnumerationFailed'
            }
        }

        if ($context.Status -eq 'HostMapScanned' -or
            $context.Status -eq 'ContainsKeyMissing' -or
            $context.Status -eq 'ContainsKeyInvokeFailed') {
            $context.Status = 'NotFound'
        }

        return $null
    }
    $skipSiteCacheHydration = $false
    $sharedSiteCacheEntry = $null
    $sharedSiteCacheEntryAttempted = $false
    $sharedCacheHitStatus = 'SharedOnly'
    $skipAccessHydration = $false
    $sharedHostEntryMatched = $false
    $siteCacheHitSource = 'None'
    if ($skipSiteCacheUpdateSetting) {
        $skipAccessHydration = $true
        if (-not $siteCacheFetchStatus) {
            $siteCacheFetchStatus = 'Disabled'
        }
        try {
            if ($siteCacheResolveContext.ContainsKey('Initial')) {
                $siteCacheResolveContext['Initial']['Status'] = 'Disabled'
            }
            if ($siteCacheResolveContext.ContainsKey('Refresh')) {
                $siteCacheResolveContext['Refresh']['Status'] = 'Disabled'
            }
        } catch { }
    }

    if ($siteCodeValue) {
        try {
            $siteCacheSummary = DeviceRepositoryModule\Get-InterfaceSiteCacheSummary -Site $siteCodeValue
            if ($siteCacheSummary -and ((-not $siteCacheSummary.CacheExists) -or ([int]$siteCacheSummary.TotalRows -le 0))) {
                $sharedSummaryEntry = $null
                try { $sharedSummaryEntry = DeviceRepositoryModule\Get-SharedSiteInterfaceCacheEntry -SiteKey $siteCodeValue } catch { $sharedSummaryEntry = $null }
                $sharedHostCount = 0
                $sharedTotalRows = 0
                $sharedCacheStatus = ''
                if ($sharedSummaryEntry) {
                    if ($sharedSummaryEntry.PSObject.Properties.Name -contains 'HostMap') {
                        $sharedHostMap = $sharedSummaryEntry.HostMap
                        if ($sharedHostMap -is [System.Collections.IDictionary]) {
                            try { $sharedHostCount = [int]$sharedHostMap.Count } catch { $sharedHostCount = 0 }
                            foreach ($sharedHostEntry in @($sharedHostMap.GetEnumerator())) {
                                $sharedPorts = $sharedHostEntry.Value
                                if ($sharedPorts -is [System.Collections.IDictionary] -or $sharedPorts -is [System.Collections.ICollection]) {
                                    try { $sharedTotalRows += [int]$sharedPorts.Count } catch { }
                                }
                            }
                        }
                    }
                    if ($sharedSummaryEntry.PSObject.Properties.Name -contains 'HostCount' -and $sharedHostCount -le 0) {
                        try { $sharedHostCount = [int]$sharedSummaryEntry.HostCount } catch { }
                    }
                    if ($sharedSummaryEntry.PSObject.Properties.Name -contains 'TotalRows' -and $sharedTotalRows -le 0) {
                        try { $sharedTotalRows = [int]$sharedSummaryEntry.TotalRows } catch { }
                    }
                    if ($sharedSummaryEntry.PSObject.Properties.Name -contains 'CacheStatus') {
                        try { $sharedCacheStatus = '' + $sharedSummaryEntry.CacheStatus } catch { $sharedCacheStatus = '' }
                    }
                }

                if ($sharedCacheDebugEnabled) {
                    & $emitSharedCacheDebug 'Summary' 'SharedSummary' $sharedHostCount $sharedTotalRows $sharedCacheStatus ''
                }

                if ($sharedHostCount -gt 0 -and $sharedTotalRows -gt 0) {
                    $skipSiteCacheHydration = $false
                    $siteCacheFetchStatus = $sharedCacheHitStatus
                    $cachePrimedRowCount = [int][Math]::Max($cachePrimedRowCount, $sharedTotalRows)
                    try {
                        if ($siteCacheResolveContext.ContainsKey('Initial')) {
                            $siteCacheResolveContext['Initial']['Status'] = 'SharedStoreSeed'
                            $siteCacheResolveContext['Initial']['HostCount'] = $sharedHostCount
                        }
                        if ($siteCacheResolveContext.ContainsKey('Refresh')) {
                            $siteCacheResolveContext['Refresh']['Status'] = 'SharedStoreSeed'
                            $siteCacheResolveContext['Refresh']['HostCount'] = $sharedHostCount
                        }
                    } catch { }
                    if ($sharedCacheDebugEnabled) {
                        & $emitSharedCacheDebug 'Summary' 'SharedSummaryPrimed' $sharedHostCount $sharedTotalRows $sharedCacheStatus ''
                    }
                } else {
                    $skipSiteCacheHydration = $true
                    $siteCacheFetchStatus = 'SkippedEmpty'
                    try {
                        if ($siteCacheResolveContext.ContainsKey('Initial')) {
                            $siteCacheResolveContext['Initial']['Status'] = 'SkippedEmpty'
                        }
                        if ($siteCacheResolveContext.ContainsKey('Refresh')) {
                            $siteCacheResolveContext['Refresh']['Status'] = 'SkippedEmpty'
                        }
                    } catch { }
                    if ($sharedCacheDebugEnabled) {
                        & $emitSharedCacheDebug 'Summary' 'SharedSummaryEmpty' $sharedHostCount $sharedTotalRows $sharedCacheStatus ''
                    }
                }
            }
        } catch { }
    }

    $resolveSharedHostEntry = {
        param(
            [string]$stage = 'Initial'
        )

        if (-not $siteCodeValue) { return $null }

        if (-not $sharedSiteCacheEntryAttempted) {
            $sharedSiteCacheEntryAttempted = $true
            try { $sharedSiteCacheEntry = DeviceRepositoryModule\Get-SharedSiteInterfaceCacheEntry -SiteKey $siteCodeValue } catch { $sharedSiteCacheEntry = $null }
        }
        if (-not $sharedSiteCacheEntry) {
            if ($sharedCacheDebugEnabled) {
                Write-Host ("[SharedCacheDebug] No shared entry found for site '{0}'." -f $siteCodeValue) -ForegroundColor DarkYellow
                & $emitSharedCacheDebug $stage 'EntryMissing' 0 0 '' $normalizedHostname
            }
            return $null
        }

        if ($sharedCacheDebugEnabled) {
            $debugHostCount = 0
            $debugRowCount = 0
            try {
                if ($sharedSiteCacheEntry.HostMap -is [System.Collections.IDictionary]) {
                    $debugHostCount = $sharedSiteCacheEntry.HostMap.Count
                    foreach ($m in @($sharedSiteCacheEntry.HostMap.Values)) {
                        if ($m -is [System.Collections.IDictionary]) { $debugRowCount += $m.Count }
                    }
                } elseif ($sharedSiteCacheEntry.PSObject.Properties.Name -contains 'HostCount') {
                    $debugHostCount = [int]$sharedSiteCacheEntry.HostCount
                }
                if ($sharedSiteCacheEntry.PSObject.Properties.Name -contains 'TotalRows' -and $debugRowCount -eq 0) {
                    $debugRowCount = [int]$sharedSiteCacheEntry.TotalRows
                }
            } catch { }
            Write-Host ("[SharedCacheDebug] Shared entry for site '{0}' -> hosts={1}, rows={2}, CacheStatus={3}" -f $siteCodeValue, $debugHostCount, $debugRowCount, $sharedSiteCacheEntry.CacheStatus) -ForegroundColor DarkCyan
            & $emitSharedCacheDebug $stage 'EntryAvailable' $debugHostCount $debugRowCount ('' + $sharedSiteCacheEntry.CacheStatus) $normalizedHostname
        }

        try {
            $sharedHostMap = $null
            try { $sharedHostMap = $sharedSiteCacheEntry.HostMap } catch { }
            $sharedHostCount = 0
            $sharedTotalRows = 0
            if ($sharedHostMap -is [System.Collections.IDictionary]) {
                try { $sharedHostCount = [int]$sharedHostMap.Count } catch { $sharedHostCount = 0 }
                foreach ($sharedHostEntry in @($sharedHostMap.GetEnumerator())) {
                    $sharedPorts = $sharedHostEntry.Value
                    if ($sharedPorts -is [System.Collections.IDictionary]) {
                        try { $sharedTotalRows += [int]$sharedPorts.Count } catch { }
                    }
                }
            } elseif ($sharedSiteCacheEntry.PSObject.Properties.Name -contains 'HostCount') {
                try { $sharedHostCount = [int]$sharedSiteCacheEntry.HostCount } catch { $sharedHostCount = 0 }
            }
            if ($sharedSiteCacheEntry.PSObject.Properties.Name -contains 'TotalRows' -and $sharedTotalRows -eq 0) {
                try { $sharedTotalRows = [int]$sharedSiteCacheEntry.TotalRows } catch { }
            }
            if ($sharedHostCount -gt 0 -and $sharedTotalRows -gt 0) {
                $skipSiteCacheHydration = $false
                if (-not $siteCacheFetchStatus -or $siteCacheFetchStatus -eq 'SkippedEmpty') {
                    $siteCacheFetchStatus = $sharedCacheHitStatus
                }
            }
        } catch { }

        $sharedHostEntry = & $resolveCachedHost $sharedSiteCacheEntry $stage
        if (-not $sharedHostEntry) {
            if ($sharedCacheDebugEnabled) {
                Write-Host ("[SharedCacheDebug] Shared entry for site '{0}' did not contain hostname '{1}'." -f $siteCodeValue, $normalizedHostname) -ForegroundColor DarkYellow
                $sharedCacheStatusValue = ''
                if ($sharedSiteCacheEntry.PSObject.Properties.Name -contains 'CacheStatus') {
                    try { $sharedCacheStatusValue = '' + $sharedSiteCacheEntry.CacheStatus } catch { $sharedCacheStatusValue = '' }
                }
                & $emitSharedCacheDebug $stage 'HostMissing' $sharedHostCount $sharedTotalRows $sharedCacheStatusValue $normalizedHostname
            }
            return $null
        }
        $skipSiteCacheHydration = $false
        $siteCacheEntry = $sharedSiteCacheEntry
        $siteCacheHitSource = 'Shared'
        $skipAccessHydration = $true
        $sharedHostEntryMatched = $true
        if (-not $siteCacheFetchStatus -or $siteCacheFetchStatus -eq 'Refreshed' -or $siteCacheFetchStatus -eq 'Disabled' -or $siteCacheFetchStatus -eq 'SkippedEmpty') {
            $siteCacheFetchStatus = $sharedCacheHitStatus
        } elseif ($skipSiteCacheUpdateSetting -and $siteCacheFetchStatus -eq 'Hit') {
            $siteCacheFetchStatus = $sharedCacheHitStatus
        }
        if ($siteCacheEntry -and $siteCacheEntry.PSObject.Properties.Name -contains 'TotalRows') {
            $cachePrimedRowCount = [int][Math]::Max($cachePrimedRowCount, $siteCacheEntry.TotalRows)
        }
        if ($sharedCacheDebugEnabled) {
            $sharedCacheStatusValue = ''
            if ($siteCacheEntry -and $siteCacheEntry.PSObject.Properties.Name -contains 'CacheStatus') {
                try { $sharedCacheStatusValue = '' + $siteCacheEntry.CacheStatus } catch { $sharedCacheStatusValue = '' }
            }
            Write-Host ("[SharedCacheDebug] Matched shared host '{0}' for site '{1}' via stage '{2}'." -f $normalizedHostname, $siteCodeValue, $stage) -ForegroundColor DarkCyan
            & $emitSharedCacheDebug $stage 'HostMatch' $sharedHostCount $sharedTotalRows $sharedCacheStatusValue $normalizedHostname
        }
        try {
            if ($siteCacheResolveContext.ContainsKey($stage)) {
                $contextEntry = $siteCacheResolveContext[$stage]
                if ($contextEntry) {
                    $contextEntry['Status'] = 'SharedStoreMatch'
                    $contextEntry['MatchedKey'] = $normalizedHostname
                    if ($siteCacheEntry.PSObject.Properties.Name -contains 'HostCount') {
                        $contextEntry['HostCount'] = [int]$siteCacheEntry.HostCount
                    }
                    if ($siteCacheEntry.PSObject.Properties.Name -contains 'CachedAt') {
                        $cacheTimestamp = $siteCacheEntry.CachedAt
                        $contextEntry['CachedAt'] = $cacheTimestamp
                        $contextEntry['CachedAtText'] = if ($cacheTimestamp -is [datetime]) { $cacheTimestamp.ToString('o') } else { '' + $cacheTimestamp }
                    }
                }
            }
        } catch { }

        return $sharedHostEntry
    }

    if ($siteCodeValue) {
        if (-not $cachedHostEntry) {
            $cachedHostEntry = & $resolveSharedHostEntry 'Initial'
        }

        if (-not $cachedHostEntry -and -not $skipSiteCacheHydration -and -not $skipAccessHydration) {
            $siteCacheFetchStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                try { $siteCacheEntry = DeviceRepositoryModule\Get-InterfaceSiteCache -Site $siteCodeValue -Connection $Connection } catch { $siteCacheEntry = $null }
            } finally {
                if ($siteCacheFetchStopwatch) {
                    $siteCacheFetchStopwatch.Stop()
                    $siteCacheFetchDurationMs = [Math]::Round($siteCacheFetchStopwatch.Elapsed.TotalMilliseconds, 3)
                }
            }
            if ($siteCacheEntry -and $siteCacheEntry.PSObject.Properties.Name -contains 'TotalRows') {
                $cachePrimedRowCount = [int]$siteCacheEntry.TotalRows
            }
            $cachedHostEntry = & $resolveCachedHost $siteCacheEntry 'Initial'
            if ($cachedHostEntry) {
                $siteCacheHitSource = 'Access'
            }
        }

        if (-not $cachedHostEntry) {
            $cachedHostEntry = & $resolveSharedHostEntry 'Refresh'
        }

        if (-not $cachedHostEntry -and -not $skipSiteCacheHydration -and -not $skipAccessHydration) {
            $loadCacheRefreshed = $true
            $siteCacheRefreshStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                try { $siteCacheEntry = DeviceRepositoryModule\Get-InterfaceSiteCache -Site $siteCodeValue -Connection $Connection -Refresh } catch { $siteCacheEntry = $siteCacheEntry }
            } finally {
                if ($siteCacheRefreshStopwatch) {
                    $siteCacheRefreshStopwatch.Stop()
                    $siteCacheRefreshDurationMs = [Math]::Round($siteCacheRefreshStopwatch.Elapsed.TotalMilliseconds, 3)
                    if ($siteCacheRefreshDurationMs -gt 0) {
                        $siteCacheFetchDurationMs = $siteCacheRefreshDurationMs
                    }
                }
            }
            if ($siteCacheEntry -and $siteCacheEntry.PSObject.Properties.Name -contains 'TotalRows') {
                $cachePrimedRowCount = [int]$siteCacheEntry.TotalRows
            }
            $cachedHostEntry = & $resolveCachedHost $siteCacheEntry 'Refresh'
            if ($cachedHostEntry -and $siteCacheHitSource -eq 'None') {
                $siteCacheHitSource = 'Access'
            }
        }

        if (-not $cachedHostEntry) {
            $cachedHostEntry = & $resolveSharedHostEntry 'Refresh'
        }
    }

    if ($cachedHostEntry -and $siteCacheHitSource -eq 'Shared') {
        $loadCacheHit = $true
        if ([string]::IsNullOrWhiteSpace($siteCacheFetchStatus) -or $siteCacheFetchStatus -eq 'Disabled' -or $siteCacheFetchStatus -eq 'SkippedEmpty') {
            $siteCacheFetchStatus = $sharedCacheHitStatus
        }
    }

    if ($siteCodeValue -and -not $skipSiteCacheHydration) {
        try {
            $lastSiteCacheMetrics = DeviceRepositoryModule\Get-LastInterfaceSiteCacheMetrics
            if ($lastSiteCacheMetrics -and $lastSiteCacheMetrics.Site -and [System.StringComparer]::OrdinalIgnoreCase.Equals($lastSiteCacheMetrics.Site, $siteCodeValue)) {
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'CacheStatus') {
                    $statusText = '' + $lastSiteCacheMetrics.CacheStatus
                    if (-not [string]::IsNullOrWhiteSpace($statusText) -and (
                        [string]::IsNullOrWhiteSpace($siteCacheFetchStatus) -or
                        $siteCacheFetchStatus -eq 'NotEvaluated' -or
                        $siteCacheFetchStatus -eq 'Unknown')) {
                        $siteCacheFetchStatus = $statusText
                    }
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationSnapshotMs') {
                    $siteCacheSnapshotDurationMs = [Math]::Round([double]$lastSiteCacheMetrics.HydrationSnapshotMs, 3)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationSnapshotRecordsetDurationMs') {
                    $siteCacheRecordsetDurationMs = [Math]::Round([double]$lastSiteCacheMetrics.HydrationSnapshotRecordsetDurationMs, 3)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationSnapshotProjectDurationMs') {
                    $siteCacheRecordsetProjectDurationMs = [Math]::Round([double]$lastSiteCacheMetrics.HydrationSnapshotProjectDurationMs, 3)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationBuildMs') {
                    $siteCacheBuildDurationMs = [Math]::Round([double]$lastSiteCacheMetrics.HydrationBuildMs, 3)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationHostMapDurationMs') {
                    $siteCacheHostMapDurationMs = [Math]::Round([double]$lastSiteCacheMetrics.HydrationHostMapDurationMs, 3)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationHostMapSignatureMatchCount') {
                    $siteCacheHostMapSignatureMatchCount = [long]$lastSiteCacheMetrics.HydrationHostMapSignatureMatchCount
                } elseif ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HostMapSignatureMatchCount') {
                    $siteCacheHostMapSignatureMatchCount = [long]$lastSiteCacheMetrics.HostMapSignatureMatchCount
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationHostMapSignatureRewriteCount') {
                    $siteCacheHostMapSignatureRewriteCount = [long]$lastSiteCacheMetrics.HydrationHostMapSignatureRewriteCount
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationHostMapEntryAllocationCount') {
                    $siteCacheHostMapEntryAllocationCount = [long]$lastSiteCacheMetrics.HydrationHostMapEntryAllocationCount
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationHostMapEntryPoolReuseCount') {
                    $siteCacheHostMapEntryPoolReuseCount = [long]$lastSiteCacheMetrics.HydrationHostMapEntryPoolReuseCount
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationHostMapLookupCount') {
                    $siteCacheHostMapLookupCount = [long]$lastSiteCacheMetrics.HydrationHostMapLookupCount
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationHostMapLookupMissCount') {
                    $siteCacheHostMapLookupMissCount = [long]$lastSiteCacheMetrics.HydrationHostMapLookupMissCount
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationHostMapCandidateMissingCount') {
                    $siteCacheHostMapCandidateMissingCount = [long]$lastSiteCacheMetrics.HydrationHostMapCandidateMissingCount
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationHostMapCandidateSignatureMissingCount') {
                    $siteCacheHostMapCandidateSignatureMissingCount = [long]$lastSiteCacheMetrics.HydrationHostMapCandidateSignatureMissingCount
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationHostMapCandidateSignatureMismatchCount') {
                    $siteCacheHostMapCandidateSignatureMismatchCount = [long]$lastSiteCacheMetrics.HydrationHostMapCandidateSignatureMismatchCount
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationHostMapCandidateFromPreviousCount') {
                    $siteCacheHostMapCandidateFromPreviousCount = [long]$lastSiteCacheMetrics.HydrationHostMapCandidateFromPreviousCount
                } elseif ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HostMapCandidateFromPreviousCount') {
                    $siteCacheHostMapCandidateFromPreviousCount = [long]$lastSiteCacheMetrics.HostMapCandidateFromPreviousCount
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationHostMapCandidateFromPoolCount') {
                    $siteCacheHostMapCandidateFromPoolCount = [long]$lastSiteCacheMetrics.HydrationHostMapCandidateFromPoolCount
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationHostMapCandidateInvalidCount') {
                    $siteCacheHostMapCandidateInvalidCount = [long]$lastSiteCacheMetrics.HydrationHostMapCandidateInvalidCount
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationHostMapCandidateMissingSamples') {
                    $rawMissingSamples = $lastSiteCacheMetrics.HydrationHostMapCandidateMissingSamples
                    if ($null -ne $rawMissingSamples) {
                        if ($rawMissingSamples -is [System.Collections.IEnumerable] -and -not ($rawMissingSamples -is [string])) {
                            $sampleList = [System.Collections.Generic.List[object]]::new()
                            foreach ($sample in $rawMissingSamples) {
                                $sampleList.Add($sample) | Out-Null
                            }
                            $siteCacheHostMapCandidateMissingSamples = $sampleList.ToArray()
                        } else {
                            $siteCacheHostMapCandidateMissingSamples = @($rawMissingSamples)
                        }
                    } else {
                        $siteCacheHostMapCandidateMissingSamples = @()
                    }
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationPreviousHostCount') {
                    $siteCachePreviousHostCount = [int]$lastSiteCacheMetrics.HydrationPreviousHostCount
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationPreviousPortCount') {
                    $siteCachePreviousPortCount = [int]$lastSiteCacheMetrics.HydrationPreviousPortCount
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationPreviousHostSample') {
                    $siteCachePreviousHostSample = '' + $lastSiteCacheMetrics.HydrationPreviousHostSample
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationPreviousSnapshotStatus') {
                    $siteCachePreviousSnapshotStatus = '' + $lastSiteCacheMetrics.HydrationPreviousSnapshotStatus
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationPreviousSnapshotHostMapType') {
                    $siteCachePreviousSnapshotHostMapType = '' + $lastSiteCacheMetrics.HydrationPreviousSnapshotHostMapType
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationPreviousSnapshotHostCount') {
                    $siteCachePreviousSnapshotHostCount = [int]$lastSiteCacheMetrics.HydrationPreviousSnapshotHostCount
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationPreviousSnapshotPortCount') {
                    $siteCachePreviousSnapshotPortCount = [int]$lastSiteCacheMetrics.HydrationPreviousSnapshotPortCount
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationPreviousSnapshotException') {
                    $siteCachePreviousSnapshotException = '' + $lastSiteCacheMetrics.HydrationPreviousSnapshotException
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationHostMapSignatureMismatchSamples') {
                    $rawMismatchSamples = $lastSiteCacheMetrics.HydrationHostMapSignatureMismatchSamples
                    if ($null -ne $rawMismatchSamples) {
                        if ($rawMismatchSamples -is [System.Collections.IEnumerable] -and -not ($rawMismatchSamples -is [string])) {
                            $sampleList = [System.Collections.Generic.List[object]]::new()
                            foreach ($sample in $rawMismatchSamples) {
                                $sampleList.Add($sample) | Out-Null
                            }
                            $siteCacheHostMapSignatureMismatchSamples = $sampleList.ToArray()
                        } else {
                            $siteCacheHostMapSignatureMismatchSamples = @($rawMismatchSamples)
                        }
                    } else {
                        $siteCacheHostMapSignatureMismatchSamples = @()
                    }
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationSortDurationMs') {
                    $siteCacheSortDurationMs = [Math]::Round([double]$lastSiteCacheMetrics.HydrationSortDurationMs, 3)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HostCount') {
                    $siteCacheHostCount = [int]$lastSiteCacheMetrics.HostCount
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationQueryDurationMs') {
                    $siteCacheQueryDurationMs = [Math]::Round([double]$lastSiteCacheMetrics.HydrationQueryDurationMs, 3)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationExecuteDurationMs') {
                    $siteCacheExecuteDurationMs = [Math]::Round([double]$lastSiteCacheMetrics.HydrationExecuteDurationMs, 3)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializeDurationMs') {
                    $siteCacheMaterializeDurationMs = [Math]::Round([double]$lastSiteCacheMetrics.HydrationMaterializeDurationMs, 3)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializeProjectionDurationMs') {
                    $siteCacheMaterializeProjectionDurationMs = [Math]::Round([double]$lastSiteCacheMetrics.HydrationMaterializeProjectionDurationMs, 3)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializePortSortDurationMs') {
                    $siteCacheMaterializePortSortDurationMs = [Math]::Round([double]$lastSiteCacheMetrics.HydrationMaterializePortSortDurationMs, 3)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializePortSortCacheHits') {
                    $siteCacheMaterializePortSortCacheHitCount = [long][Math]::Max(0, $lastSiteCacheMetrics.HydrationMaterializePortSortCacheHits)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializePortSortCacheMisses') {
                    $siteCacheMaterializePortSortCacheMissCount = [long][Math]::Max(0, $lastSiteCacheMetrics.HydrationMaterializePortSortCacheMisses)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializePortSortCacheSize') {
                    $siteCacheMaterializePortSortCacheSize = [long][Math]::Max(0, $lastSiteCacheMetrics.HydrationMaterializePortSortCacheSize)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializePortSortCacheHitRatio') {
                    $siteCacheMaterializePortSortCacheHitRatio = [Math]::Round([double]$lastSiteCacheMetrics.HydrationMaterializePortSortCacheHitRatio, 6)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializePortSortUniquePortCount') {
                    $siteCacheMaterializePortSortUniquePortCount = [long][Math]::Max(0, $lastSiteCacheMetrics.HydrationMaterializePortSortUniquePortCount)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializePortSortMissSamples') {
                    $siteCacheMaterializePortSortMissSamples = @($lastSiteCacheMetrics.HydrationMaterializePortSortMissSamples)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateDurationMs') {
                    $siteCacheMaterializeTemplateDurationMs = [Math]::Round([double]$lastSiteCacheMetrics.HydrationMaterializeTemplateDurationMs, 3)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateLookupDurationMs') {
                    $siteCacheMaterializeTemplateLookupDurationMs = [Math]::Round([double]$lastSiteCacheMetrics.HydrationMaterializeTemplateLookupDurationMs, 3)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateApplyDurationMs') {
                    $siteCacheMaterializeTemplateApplyDurationMs = [Math]::Round([double]$lastSiteCacheMetrics.HydrationMaterializeTemplateApplyDurationMs, 3)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializeObjectDurationMs') {
                    $siteCacheMaterializeObjectDurationMs = [Math]::Round([double]$lastSiteCacheMetrics.HydrationMaterializeObjectDurationMs, 3)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateCacheHitCount') {
                    $siteCacheMaterializeTemplateCacheHitCount = [long][Math]::Max(0, $lastSiteCacheMetrics.HydrationMaterializeTemplateCacheHitCount)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateCacheMissCount') {
                    $siteCacheMaterializeTemplateCacheMissCount = [long][Math]::Max(0, $lastSiteCacheMetrics.HydrationMaterializeTemplateCacheMissCount)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateReuseCount') {
                    $siteCacheMaterializeTemplateReuseCount = [long][Math]::Max(0, $lastSiteCacheMetrics.HydrationMaterializeTemplateReuseCount)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateCacheHitRatio') {
                    $siteCacheMaterializeTemplateCacheHitRatio = [Math]::Round([double]$lastSiteCacheMetrics.HydrationMaterializeTemplateCacheHitRatio, 6)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateApplyCount') {
                    $siteCacheMaterializeTemplateApplyCount = [long][Math]::Max(0, $lastSiteCacheMetrics.HydrationMaterializeTemplateApplyCount)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateDefaultedCount') {
                    $siteCacheMaterializeTemplateDefaultedCount = [long][Math]::Max(0, $lastSiteCacheMetrics.HydrationMaterializeTemplateDefaultedCount)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateAuthTemplateMissingCount') {
                    $siteCacheMaterializeTemplateAuthTemplateMissingCount = [long][Math]::Max(0, $lastSiteCacheMetrics.HydrationMaterializeTemplateAuthTemplateMissingCount)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateNoTemplateMatchCount') {
                    $siteCacheMaterializeTemplateNoTemplateMatchCount = [long][Math]::Max(0, $lastSiteCacheMetrics.HydrationMaterializeTemplateNoTemplateMatchCount)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateHintAppliedCount') {
                    $siteCacheMaterializeTemplateHintAppliedCount = [long][Math]::Max(0, $lastSiteCacheMetrics.HydrationMaterializeTemplateHintAppliedCount)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateSetPortColorCount') {
                    $siteCacheMaterializeTemplateSetPortColorCount = [long][Math]::Max(0, $lastSiteCacheMetrics.HydrationMaterializeTemplateSetPortColorCount)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateSetConfigStatusCount') {
                    $siteCacheMaterializeTemplateSetConfigStatusCount = [long][Math]::Max(0, $lastSiteCacheMetrics.HydrationMaterializeTemplateSetConfigStatusCount)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateApplySamples') {
                    $siteCacheMaterializeTemplateApplySamples = @($lastSiteCacheMetrics.HydrationMaterializeTemplateApplySamples)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationTemplateDurationMs') {
                    $siteCacheTemplateDurationMs = [Math]::Round([double]$lastSiteCacheMetrics.HydrationTemplateDurationMs, 3)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationQueryAttempts') {
                    $siteCacheQueryAttempts = [int]$lastSiteCacheMetrics.HydrationQueryAttempts
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationExclusiveRetryCount') {
                    $siteCacheExclusiveRetryCount = [int]$lastSiteCacheMetrics.HydrationExclusiveRetryCount
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationExclusiveWaitDurationMs') {
                    $siteCacheExclusiveWaitDurationMs = [Math]::Round([double]$lastSiteCacheMetrics.HydrationExclusiveWaitDurationMs, 3)
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationProvider') {
                    $providerValue = '' + $lastSiteCacheMetrics.HydrationProvider
                    if (-not [string]::IsNullOrWhiteSpace($providerValue)) {
                        $siteCacheProviderFromMetrics = $providerValue
                    }
                } elseif ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'Provider') {
                    $providerValue = '' + $lastSiteCacheMetrics.Provider
                    if (-not [string]::IsNullOrWhiteSpace($providerValue)) {
                        $siteCacheProviderFromMetrics = $providerValue
                    }
                }
                if ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'HydrationResultRowCount') {
                    $siteCacheResultRowCount = [int]$lastSiteCacheMetrics.HydrationResultRowCount
                } elseif ($lastSiteCacheMetrics.PSObject.Properties.Name -contains 'ResultRowCount') {
                    $siteCacheResultRowCount = [int]$lastSiteCacheMetrics.ResultRowCount
                }
            }
        } catch { }
    }

    if ($siteCacheHitSource -eq 'Shared') {
        $siteCacheFetchStatus = $sharedCacheHitStatus
        $siteCacheProvider = 'SharedCache'
        $siteCacheProviderReason = 'SharedCacheMatch'
    }
    $queryExistingRows = {
        $result = @{
            Rows = @{}
            LoadSignatureDurationMs = 0.0
        }

        $selectSqlLocal = "SELECT Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip FROM Interfaces WHERE Hostname = '$escHostname'"
        $recordsetLocal = $null
        try {
            $recordsetLocal = $Connection.Execute($selectSqlLocal)
            if ($recordsetLocal -and $recordsetLocal.State -eq 1) {
                while (-not $recordsetLocal.EOF) {
                    $portValue = '' + ($recordsetLocal.Fields.Item('Port').Value)
                    if (-not [string]::IsNullOrWhiteSpace($portValue)) {
                        $normalizedPort = $portValue.Trim()
                        $nameValue       = '' + ($recordsetLocal.Fields.Item('Name').Value)
                        $statusValue     = '' + ($recordsetLocal.Fields.Item('Status').Value)
                        $vlanValue       = '' + ($recordsetLocal.Fields.Item('VLAN').Value)
                        $duplexValue     = '' + ($recordsetLocal.Fields.Item('Duplex').Value)
                        $speedValue      = '' + ($recordsetLocal.Fields.Item('Speed').Value)
                        $typeValue       = '' + ($recordsetLocal.Fields.Item('Type').Value)
                        $learnedValue    = '' + ($recordsetLocal.Fields.Item('LearnedMACs').Value)
                        $authStateValue  = '' + ($recordsetLocal.Fields.Item('AuthState').Value)
                        $authModeValue   = '' + ($recordsetLocal.Fields.Item('AuthMode').Value)
                        $authClientValue = '' + ($recordsetLocal.Fields.Item('AuthClientMAC').Value)
                        $templateValue   = '' + ($recordsetLocal.Fields.Item('AuthTemplate').Value)
                        $configValue     = '' + ($recordsetLocal.Fields.Item('Config').Value)
                        $portColorValue  = '' + ($recordsetLocal.Fields.Item('PortColor').Value)
                        $statusTagValue  = '' + ($recordsetLocal.Fields.Item('ConfigStatus').Value)
                        $toolTipValue    = '' + ($recordsetLocal.Fields.Item('ToolTip').Value)

                        $existingRow = [PSCustomObject]@{
                            Name      = $nameValue
                            Status    = $statusValue
                            VLAN      = $vlanValue
                            Duplex    = $duplexValue
                            Speed     = $speedValue
                            Type      = $typeValue
                            Learned   = $learnedValue
                            AuthState = $authStateValue
                            AuthMode  = $authModeValue
                            AuthClient= $authClientValue
                            Template  = $templateValue
                            Config    = $configValue
                            PortColor = $portColorValue
                            StatusTag = $statusTagValue
                            ToolTip   = $toolTipValue
                        }

                        $signatureStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                        $rowSignature = Get-InterfaceSignatureFromValues -Values @(
                            $nameValue,
                            $statusValue,
                            $vlanValue,
                            $duplexValue,
                            $speedValue,
                            $typeValue,
                            $learnedValue,
                            $authStateValue,
                            $authModeValue,
                            $authClientValue,
                            $templateValue,
                            $configValue,
                            $portColorValue,
                            $statusTagValue,
                            $toolTipValue
                        )
                        $signatureStopwatch.Stop()
                        $result.LoadSignatureDurationMs += $signatureStopwatch.Elapsed.TotalMilliseconds
                        Add-Member -InputObject $existingRow -MemberType NoteProperty -Name Signature -Value $rowSignature -Force

                        $result.Rows[$normalizedPort] = $existingRow
                    }
                    $recordsetLocal.MoveNext() | Out-Null
                }
            }
        } catch {
            $result.Rows = @{}
        } finally {
            if ($recordsetLocal) {
                try { $recordsetLocal.Close() } catch { }
            }
        }

        return $result
    }

    $loadExistingStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $existingRowsHasCollection = (($existingRows -is [System.Collections.IDictionary]) -or ($existingRows -is [System.Collections.ICollection]))
    if ($existingRowsHasCollection -and $existingRows.Count -gt 0) {
        $cachedRowCount = [int]$existingRows.Count
    } elseif ($cachedHostEntry -is [System.Collections.IDictionary]) {
        $existingRows = @{}
        foreach ($key in $cachedHostEntry.Keys) {
            $existingRows[$key] = $cachedHostEntry[$key]
        }
        $loadCacheHit = $true
        $cachedRowCount = $cachedHostEntry.Count
    } elseif ($null -ne $cachedHostEntry) {
        $loadCacheHit = $true
        if ($cachedHostEntry -is [System.Collections.ICollection]) {
            $cachedRowCount = $cachedHostEntry.Count
        } else {
            $cachedRowCount = 0
        }
    } else {
        $loadCacheMiss = $true
        $queryResult = & $queryExistingRows
        $existingRows = $queryResult.Rows
        $loadSignatureDurationMs += $queryResult.LoadSignatureDurationMs
        $cachedRowCount = if ($existingRows) { [int]$existingRows.Count } else { 0 }
        if ($siteExistingCacheEnabled -and $existingRows -and $existingRows.Count -gt 0) {
            if (-not $siteExistingCacheEntry) {
                $siteExistingCacheEntry = Get-SiteExistingRowCacheEntry -SiteCode $siteCodeValue
            }
            if (-not $siteExistingCacheEntries -and $siteExistingCacheEntry) {
                $siteExistingCacheEntries = $siteExistingCacheEntry.Entries
            }
            if (-not $siteExistingCacheEntries) {
                $siteExistingCacheEntries = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                if ($siteExistingCacheEntry) {
                    $siteExistingCacheEntry.Entries = $siteExistingCacheEntries
                }
            }
            if ($siteExistingCacheEntries) {
                $siteExistingCacheHostEntry = Normalize-SiteExistingRowCacheHostEntry -Entry ([pscustomobject]@{
                        Rows                    = $existingRows
                        LoadSignatureDurationMs = $queryResult.LoadSignatureDurationMs
                    })
                try { $siteExistingCacheHostEntry.Hydrated = $true } catch { }
                try { $siteExistingCacheHostEntry.CachedAt = [DateTime]::UtcNow } catch { }
                try { $siteExistingCacheHostEntry.Source = 'DatabaseQuery' } catch { }
                $siteExistingCacheEntries[$normalizedHostname] = $siteExistingCacheHostEntry
                if ($siteExistingCacheEntry -and $siteExistingCacheEntry.PSObject.Properties.Name -contains 'PrimedEntries') {
                    $siteExistingCacheEntry.PrimedEntries[$normalizedHostname] = Copy-SiteExistingRowCacheHostEntry -Entry $siteExistingCacheHostEntry
                }
            }
        }
        if ($siteCodeValue -and -not $skipSiteCacheUpdateSetting) {
            try { DeviceRepositoryModule\Set-InterfaceSiteCacheHost -Site $siteCodeValue -Hostname $normalizedHostname -RowsByPort $existingRows } catch { }
        }
    }
    $loadExistingStopwatch.Stop()
    $loadExistingDurationMs = [Math]::Round($loadExistingStopwatch.Elapsed.TotalMilliseconds, 3)

    $siteCacheExistingRowCount = if ($existingRows) { [int]$existingRows.Count } else { 0 }
    $loadExistingRowSetCount = $siteCacheExistingRowCount
    $siteCacheExistingRowKeysSample = ''
    if ($existingRows -is [System.Collections.IDictionary]) {
        try {
            $existingKeySamples = [System.Collections.Generic.List[string]]::new()
            foreach ($existingKeyCandidate in $existingRows.Keys) {
                if ($existingKeySamples.Count -ge 5) { break }
                if ($null -eq $existingKeyCandidate) { continue }
                try { $existingKeySamples.Add(('' + $existingKeyCandidate)) | Out-Null } catch { }
            }
            if ($existingKeySamples.Count -gt 0) {
                $siteCacheExistingRowKeysSample = [string]::Join('|', $existingKeySamples.ToArray())
            }
        } catch {
            $siteCacheExistingRowKeysSample = ''
        }
    }
    $siteCacheExistingRowValueType = ''
    if ($existingRows -is [System.Collections.IDictionary]) {
        try {
            foreach ($existingEntry in $existingRows.GetEnumerator()) {
                $valueCandidate = $null
                try { $valueCandidate = $existingEntry.Value } catch { $valueCandidate = $null }
                if ($null -eq $valueCandidate) { continue }
                try {
                    $siteCacheExistingRowValueType = $valueCandidate.GetType().FullName
                } catch {
                    $siteCacheExistingRowValueType = ''
                }
                if (-not [string]::IsNullOrEmpty($siteCacheExistingRowValueType)) { break }
            }
        } catch {
            $siteCacheExistingRowValueType = ''
        }
    } elseif ($existingRows -and ($existingRows -is [System.Collections.IEnumerable]) -and -not ($existingRows -is [string])) {
        foreach ($valueCandidate in $existingRows) {
            if ($null -eq $valueCandidate) { continue }
            try {
                $siteCacheExistingRowValueType = $valueCandidate.GetType().FullName
            } catch {
                $siteCacheExistingRowValueType = ''
            }
            if (-not [string]::IsNullOrEmpty($siteCacheExistingRowValueType)) { break }
        }
    }
    if ($siteExistingCacheHit) {
        $siteCacheExistingRowSource = 'SiteExistingCache'
    } elseif ($loadCacheHit -and $loadCacheRefreshed) {
        $siteCacheExistingRowSource = 'CacheRefresh'
    } elseif ($loadCacheHit) {
        $siteCacheExistingRowSource = 'CacheInitial'
    } elseif ($loadCacheMiss) {
        $siteCacheExistingRowSource = 'DatabaseQuery'
    } else {
        $siteCacheExistingRowSource = 'Unknown'
    }


    $skipSourcesList = [System.Collections.Generic.List[string]]::new()
    if ($skipSiteCacheUpdateFromParameter) { [void]$skipSourcesList.Add('Parameter') }
    if ($skipSiteCacheUpdateFromScript)    { [void]$skipSourcesList.Add('Module') }
    if ($skipSiteCacheUpdateFromEnvironment) { [void]$skipSourcesList.Add('Environment') }

    if ($siteExistingCacheEnabled) {
        Write-SiteExistingRowCacheTelemetry `
            -Site $siteCodeValue `
            -Hostname $normalizedHostname `
            -CacheEnabled:$siteExistingCacheEnabled `
            -Entries $siteExistingCacheEntries `
            -HostEntry $siteExistingCacheHostEntry `
            -CacheHit:$siteExistingCacheHit `
            -SkipSetting:$skipSiteCacheUpdateSetting `
            -SkipSources $skipSourcesList.ToArray() `
            -ExistingRowSource $siteCacheExistingRowSource `
            -LoadCacheHit:$loadCacheHit `
            -LoadCacheMiss:$loadCacheMiss `
            -LoadCacheRefreshed:$loadCacheRefreshed
    }

    $toInsert = [System.Collections.Generic.List[object]]::new()
    $toUpdate = [System.Collections.Generic.List[object]]::new()
    $seenPorts = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    $runDateValue = ConvertTo-DbDateTime -RunDateString $RunDateString
    $runDateLiteral = "#$RunDateString#"
    if ($runDateValue) {
        try {
            $runDateLiteral = "#$($runDateValue.ToString('yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture))#"
        } catch { }
    }
    $useAdodbParameters = $runDateValue -and (Test-IsAdodbConnection -Connection $Connection)

    $toDelete = [System.Collections.Generic.List[string]]::new()

    $createInterfaceRow = {
        param(
            [string]$Port,
            [string]$Name,
            [string]$Status,
            [string]$VlanText,
            [int]$VlanNumeric,
            [string]$Duplex,
            [string]$Speed,
            [string]$Type,
            [string]$Learned,
            [string]$AuthState,
            [string]$AuthMode,
            [string]$AuthClient,
            [string]$Template,
            [string]$Config,
            [string]$PortColor,
            [string]$StatusTag,
            [string]$ToolTip,
            [string]$Signature
        )

        return [PSCustomObject]@{
            Port        = $Port
            Name        = $Name
            Status      = $Status
            VLAN        = $VlanText
            VlanNumeric = $VlanNumeric
            Duplex      = $Duplex
            Speed       = $Speed
            Type        = $Type
            Learned     = $Learned
            AuthState   = $AuthState
            AuthMode    = $AuthMode
            AuthClient  = $AuthClient
            Template    = $Template
            Config      = $Config
            PortColor   = $PortColor
            StatusTag   = $StatusTag
            ToolTip     = $ToolTip
            Signature   = $Signature
        }
    }

    $diffStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
    foreach ($iface in $ifaceRecords) {
        if (-not $iface) { continue }
        $comparisonStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            $port = '' + $iface.Port
            if ([string]::IsNullOrWhiteSpace($port)) { continue }
            $normalizedPort = $port.Trim()
            $seenPorts.Add($normalizedPort) | Out-Null
            $totalFactsCount++

            $name   = '' + $iface.Name
            $status = '' + $iface.Status
            $vlan   = '' + $iface.VLAN
            $duplex = '' + $iface.Duplex
            $speed  = '' + $iface.Speed
            $type   = '' + $iface.Type

            $vlanNumeric = 0
            if (-not [int]::TryParse($vlan, [ref]$vlanNumeric)) { $vlanNumeric = 0 }

            $learned = ''
            if ($iface.PSObject.Properties.Name -contains 'LearnedMACsFull' -and ($iface.LearnedMACsFull)) {
                $learned = '' + $iface.LearnedMACsFull
            } elseif ($iface.PSObject.Properties.Name -contains 'LearnedMACs') {
                $lm = $iface.LearnedMACs
                if ($lm -is [string]) {
                    $learned = $lm
                } elseif ($lm) {
                    $macList = [System.Collections.Generic.List[string]]::new()
                    foreach ($mac in $lm) {
                        if ($mac -and $mac -ne '') { [void]$macList.Add($mac) }
                    }
                    $learned = [string]::Join(',', $macList.ToArray())
                }
            }

            $authState = ''
            if ($iface.PSObject.Properties.Name -contains 'AuthState') { $authState = '' + $iface.AuthState }
            $authMode = ''
            if ($iface.PSObject.Properties.Name -contains 'AuthMode') { $authMode = '' + $iface.AuthMode }
            $authClient = ''
            if ($iface.PSObject.Properties.Name -contains 'AuthClientMAC') { $authClient = '' + $iface.AuthClientMAC }
            $authTemplate = ''
            if ($iface.PSObject.Properties.Name -contains 'AuthTemplate') { $authTemplate = '' + $iface.AuthTemplate }

            $configText = ''
            if ($iface.PSObject.Properties.Name -contains 'Config') { $configText = '' + $iface.Config }
            if (-not $configText -or ($configText -is [string] -and $configText.Trim() -eq '')) {
                if ($Facts -and $Facts.Make -eq 'Brocade') {
                    if ($Facts.PSObject.Properties.Name -contains 'AuthenticationBlock' -and $Facts.AuthenticationBlock) {
                        $configText = "AUTH BLOCK (GLOBAL)`r`n" + ($Facts.AuthenticationBlock -join "`r`n")
            }

        $comparisonStopwatch.Stop()
        $diffComparisonDurationMs += $comparisonStopwatch.Elapsed.TotalMilliseconds
    }
            }

            $portColor = ''
            if ($iface.PSObject.Properties.Name -contains 'PortColor') { $portColor = '' + $iface.PortColor }
            $configStatus = ''
            if ($iface.PSObject.Properties.Name -contains 'ConfigStatus') { $configStatus = '' + $iface.ConfigStatus }
            $toolTip = ''
            if ($iface.PSObject.Properties.Name -contains 'ToolTip') { $toolTip = '' + $iface.ToolTip }

            if (-not $portColor -and $Templates) {
                foreach ($tpl in $Templates) {
                    if (-not $tpl) { continue }

                    $tplName = $null
                    $tplColor = $null

                    if ($tpl -is [hashtable]) {
                        if ($tpl.ContainsKey('TemplateName')) { $tplName = $tpl['TemplateName'] }
                        if ($tpl.ContainsKey('PortColor')) { $tplColor = $tpl['PortColor'] }
                    } else {
                        $props = $tpl.PSObject.Properties
                        if ($props.Name -contains 'TemplateName') { $tplName = $tpl.TemplateName }
                        if ($props.Name -contains 'PortColor') { $tplColor = $tpl.PortColor }
                    }

                    if ($tplName -and $tplColor -and $tplName -eq $authTemplate) {
                        $portColor = '' + $tplColor
                        break
                    }
                }
            }

            $signatureStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $newSignature = Get-InterfaceSignatureFromValues -Values @(
                $name,
                $status,
                $vlan,
                $duplex,
                $speed,
                $type,
                $learned,
                $authState,
                $authMode,
                $authClient,
                $authTemplate,
                $configText,
                $portColor,
                $configStatus,
                $toolTip
            )
            $signatureStopwatch.Stop()
            $diffSignatureDurationMs += $signatureStopwatch.Elapsed.TotalMilliseconds

            $diffRowsCompared++

            if ($existingRows.ContainsKey($normalizedPort)) {
                $existing = $existingRows[$normalizedPort]
                $existingSignature = $null
                $cacheComparisonCandidateCount++

                $existingSignaturePresent = $false
                if ($existing.PSObject.Properties.Name -contains 'Signature') {
                    $rawExistingSignature = $existing.Signature
                    if (-not [string]::IsNullOrWhiteSpace(('' + $rawExistingSignature))) {
                        $existingSignaturePresent = $true
                    }
                }
                if (-not $existingSignaturePresent) {
                    $cacheComparisonSignatureMissingCount++
                }

                if ($existing.PSObject.Properties.Name -contains 'Signature' -and $existing.Signature) {
                    $existingSignature = '' + $existing.Signature
                } else {
                    $signatureStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                    $existingSignature = Get-InterfaceRowSignature -Row $existing
                    $signatureStopwatch.Stop()
                    $loadSignatureDurationMs += $signatureStopwatch.Elapsed.TotalMilliseconds
                    Add-Member -InputObject $existing -MemberType NoteProperty -Name Signature -Value $existingSignature -Force
                }

                if (-not [System.StringComparer]::Ordinal.Equals($newSignature, $existingSignature)) {
                    $cacheComparisonSignatureMismatchCount++
                    $diffRowsChanged++
                    $toUpdate.Add((& $createInterfaceRow `
                        $normalizedPort `
                        $name `
                        $status `
                        $vlan `
                        $vlanNumeric `
                        $duplex `
                        $speed `
                        $type `
                        $learned `
                        $authState `
                        $authMode `
                        $authClient `
                        $authTemplate `
                        $configText `
                        $portColor `
                        $configStatus `
                        $toolTip `
                        $newSignature)) | Out-Null
                } else {
                    $cacheComparisonSignatureMatchCount++
                    $diffRowsUnchanged++
                }
            } else {
                $cacheComparisonMissingPortCount++
                $diffRowsInserted++
                $toInsert.Add((& $createInterfaceRow `
                    $normalizedPort `
                    $name `
                    $status `
                    $vlan `
                    $vlanNumeric `
                    $duplex `
                    $speed `
                    $type `
                    $learned `
                    $authState `
                    $authMode `
                    $authClient `
                    $authTemplate `
                    $configText `
                    $portColor `
                    $configStatus `
                    $toolTip `
                    $newSignature)) | Out-Null
            }
        }
        foreach ($existingPort in $existingRows.Keys) {

            if (-not $seenPorts.Contains($existingPort)) {

                $cacheComparisonObsoletePortCount++
                $toDelete.Add($existingPort) | Out-Null

            }

        }
    } finally {
        $diffStopwatch.Stop()
        $diffDurationMs = [Math]::Round($diffStopwatch.Elapsed.TotalMilliseconds, 3)
    }



    $deleteBatchSize = 50

    $invokeDeleteBatch = {
        param(
            [string[]]$PortBatch,
            [string]$ContextLabel
        )

        if (-not $PortBatch -or $PortBatch.Count -eq 0) { return }

        $escapedPorts = [System.Collections.Generic.List[string]]::new()
        foreach ($portName in $PortBatch) {
            $candidate = $portName
            if ($null -eq $candidate) { $candidate = '' }
            $escapedPorts.Add("'" + ($candidate -replace "'", "''") + "'") | Out-Null
        }

        $deleteSql = "DELETE FROM Interfaces WHERE Hostname = '$escHostname' AND Port IN (" + ([string]::Join(',', $escapedPorts)) + ")"

        try {
            Invoke-AdodbNonQuery -Connection $Connection -CommandText $deleteSql | Out-Null
        } catch {
            if ($PortBatch.Count -le 1) {
                $portDetail = if ($PortBatch.Count -eq 1) { $PortBatch[0] } else { '<unknown>' }
                $label = if ([string]::IsNullOrWhiteSpace($ContextLabel)) { 'interface port' } else { $ContextLabel }
                Write-Warning ("Failed to delete {0} {1}/{2}: {3}" -f $label, $Hostname, $portDetail, $_.Exception.Message)
            } else {
                foreach ($singlePort in $PortBatch) {
                    & $invokeDeleteBatch @($singlePort) $ContextLabel
                }
            }
        }
    }

    $removeInterfacePorts = {
        param(
            [System.Collections.Generic.IEnumerable[string]]$PortSequence,
            [string]$ContextLabel,
            [System.Collections.Generic.HashSet[string]]$SeenPorts
        )

        if (-not $PortSequence) { return }
        if (-not $SeenPorts) {
            $SeenPorts = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        }

        $batch = [System.Collections.Generic.List[string]]::new()

        foreach ($portName in $PortSequence) {
            if ([string]::IsNullOrWhiteSpace($portName)) { continue }
            if (-not $SeenPorts.Add($portName)) { continue }

            $batch.Add($portName) | Out-Null

            if ($batch.Count -ge $deleteBatchSize) {
                & $invokeDeleteBatch $batch.ToArray() $ContextLabel
                $batch.Clear()
            }
        }

        if ($batch.Count -gt 0) {
            & $invokeDeleteBatch $batch.ToArray() $ContextLabel
        }
    }

    if ($toDelete.Count -gt 0) {
        $deleteStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            & $removeInterfacePorts $toDelete 'stale interface port'
        } finally {
            $deleteStopwatch.Stop()
            $deleteDurationMs += $deleteStopwatch.Elapsed.TotalMilliseconds
        }
    }



    function Add-InterfaceRow {

        param(

            [object]$Row

        )



        $escPort      = $Row.Port       -replace "'", "''"

        $escName      = $Row.Name       -replace "'", "''"

        $escStatus    = $Row.Status     -replace "'", "''"

        $escDuplex    = $Row.Duplex     -replace "'", "''"

        $escSpeed     = $Row.Speed      -replace "'", "''"

        $escType      = $Row.Type       -replace "'", "''"

        $escLearned   = $Row.Learned    -replace "'", "''"

        $escState     = $Row.AuthState  -replace "'", "''"

        $escModeFld   = $Row.AuthMode   -replace "'", "''"

        $escClient    = $Row.AuthClient -replace "'", "''"

        $escTemplate  = $Row.Template   -replace "'", "''"

        $escConfig    = $Row.Config     -replace "'", "''"

        $escColor     = $Row.PortColor  -replace "'", "''"

        $escCfgStat   = $Row.StatusTag  -replace "'", "''"

        $escToolTip   = $Row.ToolTip    -replace "'", "''"



        $vlanNumeric = 0

        if ($Row.PSObject.Properties.Name -contains 'VlanNumeric' -and $null -ne $Row.VlanNumeric) {

            try { $vlanNumeric = [int]$Row.VlanNumeric } catch { $vlanNumeric = 0 }

        } else {

            [void][int]::TryParse($Row.VLAN, [ref]$vlanNumeric)

        }



        $ifaceSql = "INSERT INTO Interfaces (Hostname, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip) VALUES ('$escHostname', '$escPort', '$escName', '$escStatus', $vlanNumeric, '$escDuplex', '$escSpeed', '$escType', '$escLearned', '$escState', '$escModeFld', '$escClient', '$escTemplate', '$escConfig', '$escColor', '$escCfgStat', '$escToolTip')"

        try { Invoke-AdodbNonQuery -Connection $Connection -CommandText $ifaceSql | Out-Null } catch { Write-Warning "Failed to insert interface record for host ${Hostname} port ${Row.Port}: $($_.Exception.Message)" }



        $histIfaceSql = "INSERT INTO InterfaceHistory (Hostname, RunDate, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip) VALUES ('$escHostname', $runDateLiteral, '$escPort', '$escName', '$escStatus', $vlanNumeric, '$escDuplex', '$escSpeed', '$escType', '$escLearned', '$escState', '$escModeFld', '$escClient', '$escTemplate', '$escConfig', '$escColor', '$escCfgStat', '$escToolTip')"

        try { Invoke-AdodbNonQuery -Connection $Connection -CommandText $histIfaceSql | Out-Null } catch { Write-Warning "Failed to insert interface history for host ${Hostname} port ${Row.Port}: $($_.Exception.Message)" }

    }



    $rowsToWrite = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $toInsert) { $rowsToWrite.Add($row) | Out-Null }

    foreach ($row in $toUpdate) { $rowsToWrite.Add($row) | Out-Null }



    $insertRowCount = if ($toInsert) { [int]$toInsert.Count } else { 0 }
    $updateRowCount = if ($toUpdate) { [int]$toUpdate.Count } else { 0 }

    $bulkSucceeded = $false
    $bulkAttempted = $false
    $bulkMetrics = $null

    $script:LastInterfaceBulkInsertMetrics = $null

    if ($useAdodbParameters -and $rowsToWrite.Count -gt 0) {

        $bulkAttempted = $true

        try {

            $bulkMetrics = $null
            $bulkResult = Invoke-InterfaceBulkInsertInternal -Connection $Connection -Hostname $Hostname -RunDate $runDateValue -Rows $rowsToWrite -InsertRowCount $insertRowCount -UpdateRowCount $updateRowCount

            $bulkSucceeded = [bool]$bulkResult
            if ($script:LastInterfaceBulkInsertMetrics) {
                $bulkMetrics = $script:LastInterfaceBulkInsertMetrics
            }

        } catch {

            Write-Verbose ("Bulk interface insert failed for {0}: {1}" -f $Hostname, $_.Exception.Message)

            $bulkSucceeded = $false
            if ($script:LastInterfaceBulkInsertMetrics) {
                $bulkMetrics = $script:LastInterfaceBulkInsertMetrics
            } else {
                $bulkMetrics = $null
            }

        }

    }



    if (-not $bulkSucceeded) {

        $fallbackShouldRun = ($toInsert.Count -gt 0 -or $toUpdate.Count -gt 0)
        $fallbackStopwatch = $null

        if ($fallbackShouldRun) {
            $fallbackUsed = $true
            $fallbackStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        }

        try {
            if ($toUpdate.Count -gt 0) {
                $fallbackDeleteStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                try {
                    $updatePorts = [System.Collections.Generic.List[string]]::new()
                    foreach ($row in $toUpdate) {
                        if ($row -and $row.PSObject.Properties.Name -contains 'Port') {
                            $updatePorts.Add([string]$row.Port) | Out-Null
                        }
                    }

                    if ($updatePorts.Count -gt 0) {
                        & $removeInterfacePorts $updatePorts 'existing interface port'
                    }
                } finally {
                    $fallbackDeleteStopwatch.Stop()
                    $deleteDurationMs += $fallbackDeleteStopwatch.Elapsed.TotalMilliseconds
                }
            }

            if ($useAdodbParameters) {

                foreach ($row in $toInsert) {

                    $handled = Invoke-InterfaceRowParameterized -Connection $Connection -Hostname $Hostname -Row $row -RunDate $runDateValue

                    if (-not $handled) { Add-InterfaceRow -Row $row }

                }



                foreach ($row in $toUpdate) {

                    $handled = Invoke-InterfaceRowParameterized -Connection $Connection -Hostname $Hostname -Row $row -RunDate $runDateValue

                    if (-not $handled) { Add-InterfaceRow -Row $row }

                }

            } else {

                foreach ($row in $toInsert) {

                    Add-InterfaceRow -Row $row

                }



                foreach ($row in $toUpdate) {

                    Add-InterfaceRow -Row $row

                }

            }
        } finally {
            if ($fallbackStopwatch) {
                $fallbackStopwatch.Stop()
                $fallbackDurationMs = [Math]::Round($fallbackStopwatch.Elapsed.TotalMilliseconds, 3)
            }
        }

    }

    try {
        $rowsInserted = if ($toInsert) { [int]$toInsert.Count } else { 0 }
        $rowsUpdated  = if ($toUpdate) { [int]$toUpdate.Count } else { 0 }
        $rowsDeleted  = if ($toDelete) { [int]$toDelete.Count } else { 0 }
        if (-not $siteCodeValue) {
            try {
                $siteCandidate = DeviceRepositoryModule\Get-SiteFromHostname -Hostname $Hostname
                if ($siteCandidate) { $siteCodeValue = ('' + $siteCandidate).Trim() }
            } catch { }
        }
        TelemetryModule\Write-StTelemetryEvent -Name 'RowsWritten' -Payload @{
            Hostname   = $Hostname
            Site       = $siteCodeValue
            RunDate    = $RunDateString
            Rows       = ($rowsInserted + $rowsUpdated)
            DeletedRows= $rowsDeleted
        }

        $finalHostRows = @{}
        foreach ($key in $existingRows.Keys) {
            $finalHostRows[$key] = $existingRows[$key]
        }
        foreach ($row in $toUpdate) {
            if ($row -and $row.PSObject.Properties.Name -contains 'Port') {
                $portKey = ('' + $row.Port).Trim()
                if ($portKey) { $finalHostRows[$portKey] = $row }
            }
        }
        foreach ($row in $toInsert) {
            if ($row -and $row.PSObject.Properties.Name -contains 'Port') {
                $portKey = ('' + $row.Port).Trim()
                if ($portKey) { $finalHostRows[$portKey] = $row }
            }
        }
        foreach ($port in $toDelete) {
            if ($port) {
                $trimmedPort = ('' + $port).Trim()
                if ($trimmedPort) { [void]$finalHostRows.Remove($trimmedPort) }
            }
        }
        if ($siteCodeValue -and -not $skipSiteCacheUpdateSetting) {
            $siteCacheStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            try { DeviceRepositoryModule\Set-InterfaceSiteCacheHost -Site $siteCodeValue -Hostname $normalizedHostname -RowsByPort $finalHostRows } catch { }
            $siteCacheStopwatch.Stop()
            $siteCacheUpdateDurationMs = [Math]::Round($siteCacheStopwatch.Elapsed.TotalMilliseconds, 3)
        }

        $bulkStageDurationMs = if ($bulkMetrics) { [double]$bulkMetrics.StageDurationMs } else { 0.0 }
        $bulkParameterBindDurationMs = if ($bulkMetrics) { [double]$bulkMetrics.ParameterBindDurationMs } else { 0.0 }
        $bulkCommandExecuteDurationMs = if ($bulkMetrics) { [double]$bulkMetrics.CommandExecuteDurationMs } else { 0.0 }
        $bulkInterfaceUpdateDurationMs = if ($bulkMetrics) { [double]$bulkMetrics.InterfaceUpdateDurationMs } else { 0.0 }
        $bulkInterfaceInsertDurationMs = if ($bulkMetrics) { [double]$bulkMetrics.InterfaceInsertDurationMs } else { 0.0 }
        $bulkHistoryInsertDurationMs = if ($bulkMetrics) { [double]$bulkMetrics.HistoryInsertDurationMs } else { 0.0 }
        $bulkCleanupDurationMs = if ($bulkMetrics) { [double]$bulkMetrics.CleanupDurationMs } else { 0.0 }
        $bulkTransactionCommitDurationMs = if ($bulkMetrics) { [double]$bulkMetrics.TransactionCommitDurationMs } else { 0.0 }
        $bulkRecordsetAttempted = if ($bulkMetrics) { [bool]$bulkMetrics.RecordsetAttempted } else { $false }
        $bulkRecordsetUsed = if ($bulkMetrics) { [bool]$bulkMetrics.RecordsetUsed } else { $false }
        $bulkRowsPrepared = if ($bulkMetrics) { [int]$bulkMetrics.Rows } else { 0 }
        $bulkRowsStaged = if ($bulkMetrics -and $bulkMetrics.PSObject.Properties.Name -contains 'RowsStaged') { [int]$bulkMetrics.RowsStaged } else { 0 }
        $bulkBatchId = if ($bulkMetrics -and $bulkMetrics.PSObject.Properties.Name -contains 'BatchId') { [string]$bulkMetrics.BatchId } else { $null }
        $bulkStreamDispatchDurationMs = if ($bulkMetrics -and $bulkMetrics.PSObject.Properties.Name -contains 'StreamDispatchDurationMs') { [double]$bulkMetrics.StreamDispatchDurationMs } else { 0.0 }
        $uiCloneDurationMsValue = if ($bulkMetrics -and $bulkMetrics.PSObject.Properties.Name -contains 'UiCloneDurationMs') { [double]$bulkMetrics.UiCloneDurationMs } else { 0.0 }
        $streamCloneDurationMs = if ($bulkMetrics -and $bulkMetrics.PSObject.Properties.Name -contains 'StreamCloneDurationMs') { [double]$bulkMetrics.StreamCloneDurationMs } else { 0.0 }
        $streamStateUpdateDurationMs = if ($bulkMetrics -and $bulkMetrics.PSObject.Properties.Name -contains 'StreamStateUpdateDurationMs') { [double]$bulkMetrics.StreamStateUpdateDurationMs } else { 0.0 }
        $streamRowsReceived = if ($bulkMetrics -and $bulkMetrics.PSObject.Properties.Name -contains 'StreamRowsReceived') { [int]$bulkMetrics.StreamRowsReceived } else { 0 }
        $streamRowsReused = if ($bulkMetrics -and $bulkMetrics.PSObject.Properties.Name -contains 'StreamRowsReused') { [int]$bulkMetrics.StreamRowsReused } else { 0 }
        $streamRowsCloned = if ($bulkMetrics -and $bulkMetrics.PSObject.Properties.Name -contains 'StreamRowsCloned') { [int]$bulkMetrics.StreamRowsCloned } else { 0 }

        if (-not $siteCacheFetchStatus) {
            if ($loadCacheRefreshed) {
                $siteCacheFetchStatus = 'Refreshed'
            } elseif ($loadCacheHit) {
                $siteCacheFetchStatus = if ($siteCacheHitSource -eq 'Shared') { $sharedCacheHitStatus } else { 'Hit' }
            } elseif ($loadCacheMiss) {
                $siteCacheFetchStatus = 'Miss'
            } else {
                $siteCacheFetchStatus = 'Unknown'
            }
        }

        if ($siteCacheHitSource -eq 'Shared') {
            $siteCacheFetchStatus = $sharedCacheHitStatus
        }

        if ($loadCacheHit -and ([string]::IsNullOrWhiteSpace($siteCacheHitSource) -or $siteCacheHitSource -eq 'None')) {
            $sharedCacheDebugStats = & $getSharedCacheDebugStats
            $normalizedCacheStatus = '' + $sharedCacheDebugStats.CacheStatus
            $candidateHostCount = [int]$sharedCacheDebugStats.HostCount
            if ($sharedSiteCacheEntry -or $normalizedCacheStatus -like 'Shared*' -or $candidateHostCount -gt 0) {
                $siteCacheHitSource = 'Shared'
                if (-not $siteCacheFetchStatus -or $siteCacheFetchStatus -eq 'Unknown' -or $siteCacheFetchStatus -eq 'Hit') {
                    $siteCacheFetchStatus = $sharedCacheHitStatus
                }
                if ($sharedCacheDebugEnabled) {
                    & $emitSharedCacheDebug 'ProviderResolution' 'HitSourceNormalized' $sharedCacheDebugStats.HostCount $sharedCacheDebugStats.TotalRows $sharedCacheDebugStats.CacheStatus $normalizedHostname $siteCacheProvider $siteCacheProviderReason $loadCacheHit $loadCacheMiss
                }
        } else {
            $siteCacheHitSource = 'Access'
        }
    }

    if ($sharedHostEntryMatched) {
        $loadCacheHit = $true
        $siteCacheHitSource = 'Shared'
        if (-not $siteCacheFetchStatus -or $siteCacheFetchStatus -eq 'Unknown' -or $siteCacheFetchStatus -eq 'Hit') {
            $siteCacheFetchStatus = $sharedCacheHitStatus
        }
        if (-not $siteCacheProvider) {
            $siteCacheProvider = 'SharedCache'
        }
        if ([string]::IsNullOrWhiteSpace($siteCacheProviderReason) -or $siteCacheProviderReason -eq 'NotEvaluated' -or $siteCacheProviderReason -eq 'SharedCacheUnavailable') {
            $siteCacheProviderReason = 'SharedCacheMatch'
        }
        if ($sharedCacheDebugEnabled) {
            $sharedCacheDebugStats = & $getSharedCacheDebugStats
            & $emitSharedCacheDebug 'ProviderResolution' 'SharedHostPinned' $sharedCacheDebugStats.HostCount $sharedCacheDebugStats.TotalRows $sharedCacheDebugStats.CacheStatus $normalizedHostname $siteCacheProvider $siteCacheProviderReason $loadCacheHit $loadCacheMiss
        }
    }

    if (-not $siteCacheProvider) {
        if ($loadCacheRefreshed) {
            $siteCacheProvider = 'Refreshed'
            $siteCacheProviderReason = 'AccessRefresh'
        } elseif ($loadCacheHit) {
            if ($siteCacheHitSource -eq 'Shared') {
                $siteCacheProvider = 'SharedCache'
                if ([string]::IsNullOrWhiteSpace($siteCacheProviderReason) -or $siteCacheProviderReason -eq 'NotEvaluated') {
                    $siteCacheProviderReason = 'SharedCacheMatch'
                }
            } else {
                $siteCacheProvider = 'Cache'
                $siteCacheProviderReason = 'AccessCacheHit'
            }
        } else {
            $siteCacheProvider = 'Unknown'
            if ($skipSiteCacheUpdateSetting -or $skipAccessHydration) {
                $siteCacheProviderReason = 'SkipSiteCacheUpdate'
            } elseif ($skipSiteCacheHydration) {
                $siteCacheProviderReason = 'SharedCacheUnavailable'
                if ($sharedCacheDebugEnabled) {
                    $sharedCacheDebugStats = & $getSharedCacheDebugStats
                    & $emitSharedCacheDebug 'ProviderReason' 'SharedCacheUnavailable' $sharedCacheDebugStats.HostCount $sharedCacheDebugStats.TotalRows $sharedCacheDebugStats.CacheStatus $normalizedHostname
                }
            } else {
                $siteCacheProviderReason = 'DatabaseQueryFallback'
            }
        }
    }
    if (-not $siteCacheProvider -and $siteCacheProviderFromMetrics) {
        $siteCacheProvider = $siteCacheProviderFromMetrics
        if ([string]::IsNullOrWhiteSpace($siteCacheProviderReason) -or $siteCacheProviderReason -eq 'NotEvaluated') {
            switch ($siteCacheProvider) {
                'Refreshed' { $siteCacheProviderReason = 'AccessRefresh'; break }
                'Cache' { $siteCacheProviderReason = 'AccessCacheHit'; break }
                'SharedCache' { $siteCacheProviderReason = 'SharedCacheMatch'; break }
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($siteCacheProviderReason)) {
        if ($siteCacheProvider -eq 'SharedCache') {
            $siteCacheProviderReason = 'SharedCacheMatch'
        } elseif ($siteCacheProvider -eq 'Refreshed') {
            $siteCacheProviderReason = 'AccessRefresh'
        } elseif ($siteCacheProvider -eq 'Cache') {
            $siteCacheProviderReason = 'AccessCacheHit'
        } elseif ($siteCacheProvider -eq 'Unknown') {
            $siteCacheProviderReason = 'Undetermined'
        }
    }
    if ($siteCacheHitSource -eq 'Shared') {
        $loadCacheHit = $true
        $loadCacheMiss = $false
        $siteCacheFetchStatus = $sharedCacheHitStatus
        $siteCacheProvider = 'SharedCache'
        $siteCacheProviderReason = 'SharedCacheMatch'
    }
    if ($sharedHostEntryMatched) {
        $siteCacheHitSource = 'Shared'
        if ($sharedCacheDebugEnabled) {
            $sharedCacheDebugStats = & $getSharedCacheDebugStats
            & $emitSharedCacheDebug 'ProviderResolution' 'SharedHostPinned' $sharedCacheDebugStats.HostCount $sharedCacheDebugStats.TotalRows $sharedCacheDebugStats.CacheStatus $normalizedHostname $siteCacheProvider $siteCacheProviderReason $loadCacheHit $loadCacheMiss
        }
    }
    if ($sharedCacheDebugEnabled -and $siteCacheProviderReason -eq 'SharedCacheUnavailable') {
        $sharedCacheDebugStats = & $getSharedCacheDebugStats
        & $emitSharedCacheDebug 'ProviderResolution' 'SharedCacheUnavailable' $sharedCacheDebugStats.HostCount $sharedCacheDebugStats.TotalRows $sharedCacheDebugStats.CacheStatus $normalizedHostname $siteCacheProvider $siteCacheProviderReason $loadCacheHit $loadCacheMiss
    }
    if ($sharedCacheDebugEnabled) {
        $sharedCacheDebugStats = & $getSharedCacheDebugStats
        & $emitSharedCacheDebug 'ProviderResolution' 'Resolved' $sharedCacheDebugStats.HostCount $sharedCacheDebugStats.TotalRows $sharedCacheDebugStats.CacheStatus $normalizedHostname $siteCacheProvider $siteCacheProviderReason $loadCacheHit $loadCacheMiss
        & $emitSharedCacheDebug 'Provider' 'Resolved' $sharedCacheDebugStats.HostCount $sharedCacheDebugStats.TotalRows $sharedCacheDebugStats.CacheStatus $normalizedHostname $siteCacheProvider $siteCacheProviderReason $loadCacheHit $loadCacheMiss
    }
    if ($siteCacheResultRowCount -le 0) {
        if ($cachePrimedRowCount -gt 0) {
            $siteCacheResultRowCount = $cachePrimedRowCount
        } elseif ($cachedRowCount -gt 0) {
            $siteCacheResultRowCount = $cachedRowCount
        }
    }

    $siteCacheResolveInitialStatus = 'NotCaptured'
    $siteCacheResolveInitialHostCount = 0
    $siteCacheResolveInitialMatchedKey = ''
    $siteCacheResolveInitialKeysSample = ''
    $siteCacheResolveInitialCacheAgeMs = $null
    $siteCacheResolveInitialCachedAtText = ''
    $siteCacheResolveInitialEntryType = ''
    $siteCacheResolveInitialPortCount = 0
    $siteCacheResolveInitialPortKeysSample = ''
    $siteCacheResolveInitialPortSignatureSample = ''
    $siteCacheResolveInitialPortSignatureMissingCount = 0
    $siteCacheResolveInitialPortSignatureEmptyCount = 0
    if ($siteCacheResolveContext.ContainsKey('Initial')) {
        $initialContext = $siteCacheResolveContext['Initial']
        if ($initialContext) {
            if ($initialContext.Status) { $siteCacheResolveInitialStatus = '' + $initialContext.Status }
            if ($initialContext.HostCount -or $initialContext.HostCount -eq 0) { $siteCacheResolveInitialHostCount = [int]$initialContext.HostCount }
            if ($initialContext.MatchedKey) { $siteCacheResolveInitialMatchedKey = '' + $initialContext.MatchedKey }
            if ($initialContext.KeysSample) { $siteCacheResolveInitialKeysSample = '' + $initialContext.KeysSample }
            if ($initialContext.CachedAtText) { $siteCacheResolveInitialCachedAtText = '' + $initialContext.CachedAtText }
            if ($initialContext.EntryType) { $siteCacheResolveInitialEntryType = '' + $initialContext.EntryType }
            if ($initialContext.PortCount -or $initialContext.PortCount -eq 0) { $siteCacheResolveInitialPortCount = [int]$initialContext.PortCount }
            if ($initialContext.PortKeysSample) { $siteCacheResolveInitialPortKeysSample = '' + $initialContext.PortKeysSample }
            if ($initialContext.PortSignatureSample) { $siteCacheResolveInitialPortSignatureSample = '' + $initialContext.PortSignatureSample }
            if ($initialContext.PortSignatureMissingCount -or $initialContext.PortSignatureMissingCount -eq 0) { $siteCacheResolveInitialPortSignatureMissingCount = [int]$initialContext.PortSignatureMissingCount }
            if ($initialContext.PortSignatureEmptyCount -or $initialContext.PortSignatureEmptyCount -eq 0) { $siteCacheResolveInitialPortSignatureEmptyCount = [int]$initialContext.PortSignatureEmptyCount }
            if ($initialContext.CachedAt -is [datetime]) {
                try {
                    $initialAge = (Get-Date) - $initialContext.CachedAt
                    $siteCacheResolveInitialCacheAgeMs = [Math]::Round($initialAge.TotalMilliseconds, 3)
                } catch { }
            }
        }
    }

    $siteCacheResolveRefreshStatus = 'NotCaptured'
    $siteCacheResolveRefreshHostCount = 0
    $siteCacheResolveRefreshMatchedKey = ''
    $siteCacheResolveRefreshKeysSample = ''
    $siteCacheResolveRefreshCacheAgeMs = $null
    $siteCacheResolveRefreshCachedAtText = ''
    $siteCacheResolveRefreshEntryType = ''
    $siteCacheResolveRefreshPortCount = 0
    $siteCacheResolveRefreshPortKeysSample = ''
    $siteCacheResolveRefreshPortSignatureSample = ''
    $siteCacheResolveRefreshPortSignatureMissingCount = 0
    $siteCacheResolveRefreshPortSignatureEmptyCount = 0
    if ($siteCacheResolveContext.ContainsKey('Refresh')) {
        $refreshContext = $siteCacheResolveContext['Refresh']
        if ($refreshContext) {
            if ($refreshContext.Status) { $siteCacheResolveRefreshStatus = '' + $refreshContext.Status }
            if ($refreshContext.HostCount -or $refreshContext.HostCount -eq 0) { $siteCacheResolveRefreshHostCount = [int]$refreshContext.HostCount }
            if ($refreshContext.MatchedKey) { $siteCacheResolveRefreshMatchedKey = '' + $refreshContext.MatchedKey }
            if ($refreshContext.KeysSample) { $siteCacheResolveRefreshKeysSample = '' + $refreshContext.KeysSample }
            if ($refreshContext.CachedAtText) { $siteCacheResolveRefreshCachedAtText = '' + $refreshContext.CachedAtText }
            if ($refreshContext.EntryType) { $siteCacheResolveRefreshEntryType = '' + $refreshContext.EntryType }
            if ($refreshContext.PortCount -or $refreshContext.PortCount -eq 0) { $siteCacheResolveRefreshPortCount = [int]$refreshContext.PortCount }
            if ($refreshContext.PortKeysSample) { $siteCacheResolveRefreshPortKeysSample = '' + $refreshContext.PortKeysSample }
            if ($refreshContext.PortSignatureSample) { $siteCacheResolveRefreshPortSignatureSample = '' + $refreshContext.PortSignatureSample }
            if ($refreshContext.PortSignatureMissingCount -or $refreshContext.PortSignatureMissingCount -eq 0) { $siteCacheResolveRefreshPortSignatureMissingCount = [int]$refreshContext.PortSignatureMissingCount }
            if ($refreshContext.PortSignatureEmptyCount -or $refreshContext.PortSignatureEmptyCount -eq 0) { $siteCacheResolveRefreshPortSignatureEmptyCount = [int]$refreshContext.PortSignatureEmptyCount }
            if ($refreshContext.CachedAt -is [datetime]) {
                try {
                    $refreshAge = (Get-Date) - $refreshContext.CachedAt
                    $siteCacheResolveRefreshCacheAgeMs = [Math]::Round($refreshAge.TotalMilliseconds, 3)
                } catch { }
            }
        }
    }

    if ($siteCacheHostMapCandidateMissingSamples) {
        $appendCandidateSampleDetail = {
            param($targetSample, [string]$propertyName, $propertyValue)

            if ($null -eq $targetSample -or [string]::IsNullOrWhiteSpace($propertyName)) { return }

            if ($targetSample -is [System.Collections.IDictionary]) {
                $targetSample[$propertyName] = $propertyValue
                return
            }

            $targetPsObject = $null
            try { $targetPsObject = $targetSample.PSObject } catch { $targetPsObject = $null }
            if ($targetPsObject) {
                try { Add-Member -InputObject $targetSample -MemberType NoteProperty -Name $propertyName -Value $propertyValue -Force } catch { }
            }
        }

        foreach ($sample in $siteCacheHostMapCandidateMissingSamples) {
            if (-not $sample) { continue }

            & $appendCandidateSampleDetail $sample 'ParserResolveInitialStatus' $siteCacheResolveInitialStatus
            & $appendCandidateSampleDetail $sample 'ParserExistingRowCount' $siteCacheExistingRowCount
            if (-not [string]::IsNullOrWhiteSpace($siteCacheExistingRowKeysSample)) {
                & $appendCandidateSampleDetail $sample 'ParserExistingRowKeysSample' $siteCacheExistingRowKeysSample
            }
            if (-not [string]::IsNullOrWhiteSpace($siteCacheExistingRowValueType)) {
                & $appendCandidateSampleDetail $sample 'ParserExistingRowValueType' $siteCacheExistingRowValueType
            }
            & $appendCandidateSampleDetail $sample 'ParserExistingRowSource' $siteCacheExistingRowSource
            & $appendCandidateSampleDetail $sample 'ParserLoadCacheHit' $loadCacheHit
            & $appendCandidateSampleDetail $sample 'ParserLoadCacheMiss' $loadCacheMiss
            & $appendCandidateSampleDetail $sample 'ParserLoadCacheRefreshed' $loadCacheRefreshed
        }
    }

    TelemetryModule\Write-StTelemetryEvent -Name 'InterfaceSyncTiming' -Payload @{
        Hostname = $Hostname
        Site = $siteCodeValue
        UiCloneDurationMs = $uiCloneDurationMsValue
        LoadExistingDurationMs = $loadExistingDurationMs
            LoadExistingRowSetCount = $loadExistingRowSetCount
            LoadSignatureDurationMs = [Math]::Round($loadSignatureDurationMs, 3)
            LoadCacheHit = $loadCacheHit
            LoadCacheMiss = $loadCacheMiss
            LoadCacheRefreshed = $loadCacheRefreshed
            CachedRowCount = $cachedRowCount
            CachePrimedRowCount = $cachePrimedRowCount
        SiteCacheResolveInitialStatus = $siteCacheResolveInitialStatus
        SiteCacheResolveInitialHostCount = $siteCacheResolveInitialHostCount
        SiteCacheResolveInitialMatchedKey = $siteCacheResolveInitialMatchedKey
        SiteCacheResolveInitialKeysSample = $siteCacheResolveInitialKeysSample
        SiteCacheResolveInitialCacheAgeMs = $siteCacheResolveInitialCacheAgeMs
        SiteCacheResolveInitialCachedAt = $siteCacheResolveInitialCachedAtText
        SiteCacheResolveInitialEntryType = $siteCacheResolveInitialEntryType
        SiteCacheResolveInitialPortCount = $siteCacheResolveInitialPortCount
        SiteCacheResolveInitialPortKeysSample = $siteCacheResolveInitialPortKeysSample
        SiteCacheResolveInitialPortSignatureSample = $siteCacheResolveInitialPortSignatureSample
        SiteCacheResolveInitialPortSignatureMissingCount = $siteCacheResolveInitialPortSignatureMissingCount
        SiteCacheResolveInitialPortSignatureEmptyCount = $siteCacheResolveInitialPortSignatureEmptyCount
        SiteCacheResolveRefreshStatus = $siteCacheResolveRefreshStatus
        SiteCacheResolveRefreshHostCount = $siteCacheResolveRefreshHostCount
        SiteCacheResolveRefreshMatchedKey = $siteCacheResolveRefreshMatchedKey
        SiteCacheResolveRefreshKeysSample = $siteCacheResolveRefreshKeysSample
        SiteCacheResolveRefreshCacheAgeMs = $siteCacheResolveRefreshCacheAgeMs
        SiteCacheResolveRefreshCachedAt = $siteCacheResolveRefreshCachedAtText
        SiteCacheResolveRefreshEntryType = $siteCacheResolveRefreshEntryType
        SiteCacheResolveRefreshPortCount = $siteCacheResolveRefreshPortCount
        SiteCacheResolveRefreshPortKeysSample = $siteCacheResolveRefreshPortKeysSample
        SiteCacheResolveRefreshPortSignatureSample = $siteCacheResolveRefreshPortSignatureSample
        SiteCacheResolveRefreshPortSignatureMissingCount = $siteCacheResolveRefreshPortSignatureMissingCount
        SiteCacheResolveRefreshPortSignatureEmptyCount = $siteCacheResolveRefreshPortSignatureEmptyCount
        SiteCacheFetchDurationMs = $siteCacheFetchDurationMs
        SiteCacheRefreshDurationMs = $siteCacheRefreshDurationMs
        SiteCacheFetchStatus = $siteCacheFetchStatus
        SiteCacheSnapshotDurationMs = $siteCacheSnapshotDurationMs
        SiteCacheRecordsetDurationMs = $siteCacheRecordsetDurationMs
        SiteCacheRecordsetProjectDurationMs = $siteCacheRecordsetProjectDurationMs
        SiteCacheBuildDurationMs = $siteCacheBuildDurationMs
        SiteCacheHostMapDurationMs = $siteCacheHostMapDurationMs
        SiteCacheHostMapSignatureMatchCount   = $siteCacheHostMapSignatureMatchCount
        SiteCacheHostMapSignatureRewriteCount = $siteCacheHostMapSignatureRewriteCount
        SiteCacheHostMapEntryAllocationCount  = $siteCacheHostMapEntryAllocationCount
        SiteCacheHostMapEntryPoolReuseCount   = $siteCacheHostMapEntryPoolReuseCount
        SiteCacheHostMapLookupCount           = $siteCacheHostMapLookupCount
        SiteCacheHostMapLookupMissCount       = $siteCacheHostMapLookupMissCount
        SiteCacheHostMapCandidateMissingCount = $siteCacheHostMapCandidateMissingCount
        SiteCacheHostMapCandidateSignatureMissingCount = $siteCacheHostMapCandidateSignatureMissingCount
        SiteCacheHostMapCandidateSignatureMismatchCount = $siteCacheHostMapCandidateSignatureMismatchCount
        SiteCacheHostMapCandidateFromPreviousCount = $siteCacheHostMapCandidateFromPreviousCount
        SiteCacheHostMapCandidateFromPoolCount     = $siteCacheHostMapCandidateFromPoolCount
        SiteCacheHostMapCandidateInvalidCount      = $siteCacheHostMapCandidateInvalidCount
        SiteCacheHostMapCandidateMissingSamples    = $siteCacheHostMapCandidateMissingSamples
        SiteCacheHostMapSignatureMismatchSamples   = $siteCacheHostMapSignatureMismatchSamples
        SiteCachePreviousHostCount = $siteCachePreviousHostCount
        SiteCachePreviousPortCount = $siteCachePreviousPortCount
        SiteCachePreviousHostSample = $siteCachePreviousHostSample
        SiteCachePreviousSnapshotStatus = $siteCachePreviousSnapshotStatus
        SiteCachePreviousSnapshotHostMapType = $siteCachePreviousSnapshotHostMapType
        SiteCachePreviousSnapshotHostCount = $siteCachePreviousSnapshotHostCount
        SiteCachePreviousSnapshotPortCount = $siteCachePreviousSnapshotPortCount
        SiteCachePreviousSnapshotException = $siteCachePreviousSnapshotException
        SiteCacheSortDurationMs = $siteCacheSortDurationMs
        SiteCacheHostCount = $siteCacheHostCount
        SiteCacheQueryDurationMs = $siteCacheQueryDurationMs
        SiteCacheExecuteDurationMs = $siteCacheExecuteDurationMs
        SiteCacheMaterializeDurationMs = $siteCacheMaterializeDurationMs
        SiteCacheMaterializeProjectionDurationMs = $siteCacheMaterializeProjectionDurationMs
        SiteCacheMaterializePortSortDurationMs   = $siteCacheMaterializePortSortDurationMs
        SiteCacheMaterializePortSortCacheHitCount   = $siteCacheMaterializePortSortCacheHitCount
        SiteCacheMaterializePortSortCacheMissCount = $siteCacheMaterializePortSortCacheMissCount
        SiteCacheMaterializePortSortCacheSize      = $siteCacheMaterializePortSortCacheSize
        SiteCacheMaterializePortSortCacheHitRatio  = $siteCacheMaterializePortSortCacheHitRatio
        SiteCacheMaterializePortSortUniquePortCount = $siteCacheMaterializePortSortUniquePortCount
        SiteCacheMaterializePortSortMissSamples      = $siteCacheMaterializePortSortMissSamples
        SiteCacheMaterializeTemplateDurationMs   = $siteCacheMaterializeTemplateDurationMs
        SiteCacheMaterializeTemplateLookupDurationMs = $siteCacheMaterializeTemplateLookupDurationMs
        SiteCacheMaterializeTemplateApplyDurationMs  = $siteCacheMaterializeTemplateApplyDurationMs
        SiteCacheMaterializeTemplateCacheHitCount    = $siteCacheMaterializeTemplateCacheHitCount
        SiteCacheMaterializeTemplateCacheMissCount   = $siteCacheMaterializeTemplateCacheMissCount
        SiteCacheMaterializeTemplateReuseCount       = $siteCacheMaterializeTemplateReuseCount
        SiteCacheMaterializeTemplateCacheHitRatio    = $siteCacheMaterializeTemplateCacheHitRatio
        SiteCacheMaterializeTemplateApplyCount        = $siteCacheMaterializeTemplateApplyCount
        SiteCacheMaterializeTemplateDefaultedCount    = $siteCacheMaterializeTemplateDefaultedCount
        SiteCacheMaterializeTemplateAuthTemplateMissingCount = $siteCacheMaterializeTemplateAuthTemplateMissingCount
        SiteCacheMaterializeTemplateNoTemplateMatchCount     = $siteCacheMaterializeTemplateNoTemplateMatchCount
        SiteCacheMaterializeTemplateHintAppliedCount   = $siteCacheMaterializeTemplateHintAppliedCount
        SiteCacheMaterializeTemplateSetPortColorCount  = $siteCacheMaterializeTemplateSetPortColorCount
        SiteCacheMaterializeTemplateSetConfigStatusCount = $siteCacheMaterializeTemplateSetConfigStatusCount
        SiteCacheMaterializeTemplateApplySamples       = $siteCacheMaterializeTemplateApplySamples
        SiteCacheMaterializeObjectDurationMs     = $siteCacheMaterializeObjectDurationMs
        SiteCacheTemplateDurationMs = $siteCacheTemplateDurationMs
        SiteCacheQueryAttempts = $siteCacheQueryAttempts
        SiteCacheExclusiveRetryCount = $siteCacheExclusiveRetryCount
        SiteCacheExclusiveWaitDurationMs = $siteCacheExclusiveWaitDurationMs
        SiteCacheProvider = $siteCacheProvider
        SiteCacheProviderReason = $siteCacheProviderReason
        SiteCacheResultRowCount = $siteCacheResultRowCount
        SiteCacheExistingRowCount = $siteCacheExistingRowCount
        SiteCacheExistingRowKeysSample = $siteCacheExistingRowKeysSample
        SiteCacheExistingRowValueType = $siteCacheExistingRowValueType
        SiteCacheExistingRowSource = $siteCacheExistingRowSource
        SiteCacheComparisonCandidateCount = $cacheComparisonCandidateCount
        SiteCacheComparisonSignatureMatchCount = $cacheComparisonSignatureMatchCount
        SiteCacheComparisonSignatureMismatchCount = $cacheComparisonSignatureMismatchCount
        SiteCacheComparisonSignatureMissingCount = $cacheComparisonSignatureMissingCount
        SiteCacheComparisonMissingPortCount = $cacheComparisonMissingPortCount
        SiteCacheComparisonObsoletePortCount = $cacheComparisonObsoletePortCount
        DiffDurationMs = $diffDurationMs
            DiffComparisonDurationMs = [Math]::Round($diffComparisonDurationMs, 3)
            DiffSignatureDurationMs = [Math]::Round($diffSignatureDurationMs, 3)
            DeleteDurationMs = [Math]::Round($deleteDurationMs, 3)
            FallbackDurationMs = $fallbackDurationMs
            FactsConsidered = $totalFactsCount
            ExistingCount = [int]$existingRows.Count
            InsertCandidates = $rowsInserted
            UpdateCandidates = $rowsUpdated
            DeleteCandidates = $rowsDeleted
            DiffRowsCompared = $diffRowsCompared
            DiffRowsUnchanged = $diffRowsUnchanged
            DiffRowsChanged = $diffRowsChanged
            DiffRowsInserted = $diffRowsInserted
            DiffSeenPorts = [int]$seenPorts.Count
            DiffDuplicatePorts = [int][Math]::Max(0, $totalFactsCount - $seenPorts.Count)
            RowsStaged = [int]$rowsToWrite.Count
            BulkAttempted = $bulkAttempted
            BulkSucceeded = $bulkSucceeded
            FallbackUsed = $fallbackUsed
            BulkStageDurationMs = $bulkStageDurationMs
            BulkParameterBindDurationMs = $bulkParameterBindDurationMs
            BulkCommandExecuteDurationMs = $bulkCommandExecuteDurationMs
            BulkInterfaceUpdateDurationMs = $bulkInterfaceUpdateDurationMs
            BulkInterfaceInsertDurationMs = $bulkInterfaceInsertDurationMs
            BulkHistoryInsertDurationMs = $bulkHistoryInsertDurationMs
            BulkCleanupDurationMs = $bulkCleanupDurationMs
            BulkTransactionCommitDurationMs = $bulkTransactionCommitDurationMs
            BulkRecordsetAttempted = $bulkRecordsetAttempted
            BulkRecordsetUsed = $bulkRecordsetUsed
            BulkRowsPrepared = $bulkRowsPrepared
            BulkRowsCommitted = $bulkRowsStaged
            BulkBatchId = $bulkBatchId
            StreamDispatchDurationMs = $bulkStreamDispatchDurationMs
            StreamCloneDurationMs = $streamCloneDurationMs
            StreamStateUpdateDurationMs = $streamStateUpdateDurationMs
            StreamRowsReceived = $streamRowsReceived
            StreamRowsReused = $streamRowsReused
            StreamRowsCloned = $streamRowsCloned
            SiteCacheUpdateDurationMs = $siteCacheUpdateDurationMs
        }
        $script:LastInterfaceSyncTelemetry = [pscustomobject]@{
            Hostname = $Hostname
            Site = $siteCodeValue
            FactsConsidered = $totalFactsCount
            LoadCacheHit = $loadCacheHit
        LoadCacheMiss = $loadCacheMiss
        LoadCacheRefreshed = $loadCacheRefreshed
        CachedRowCount = $cachedRowCount
        CachePrimedRowCount = $cachePrimedRowCount
        SiteCacheResolveInitialStatus = $siteCacheResolveInitialStatus
        SiteCacheResolveInitialHostCount = $siteCacheResolveInitialHostCount
        SiteCacheResolveInitialMatchedKey = $siteCacheResolveInitialMatchedKey
        SiteCacheResolveInitialKeysSample = $siteCacheResolveInitialKeysSample
        SiteCacheResolveInitialCacheAgeMs = $siteCacheResolveInitialCacheAgeMs
        SiteCacheResolveInitialCachedAt = $siteCacheResolveInitialCachedAtText
        SiteCacheResolveInitialEntryType = $siteCacheResolveInitialEntryType
        SiteCacheResolveInitialPortCount = $siteCacheResolveInitialPortCount
        SiteCacheResolveInitialPortKeysSample = $siteCacheResolveInitialPortKeysSample
        SiteCacheResolveInitialPortSignatureSample = $siteCacheResolveInitialPortSignatureSample
        SiteCacheResolveInitialPortSignatureMissingCount = $siteCacheResolveInitialPortSignatureMissingCount
        SiteCacheResolveInitialPortSignatureEmptyCount = $siteCacheResolveInitialPortSignatureEmptyCount
        SiteCacheResolveRefreshStatus = $siteCacheResolveRefreshStatus
        SiteCacheResolveRefreshHostCount = $siteCacheResolveRefreshHostCount
        SiteCacheResolveRefreshMatchedKey = $siteCacheResolveRefreshMatchedKey
        SiteCacheResolveRefreshKeysSample = $siteCacheResolveRefreshKeysSample
        SiteCacheResolveRefreshCacheAgeMs = $siteCacheResolveRefreshCacheAgeMs
        SiteCacheResolveRefreshCachedAt = $siteCacheResolveRefreshCachedAtText
        SiteCacheResolveRefreshEntryType = $siteCacheResolveRefreshEntryType
        SiteCacheResolveRefreshPortCount = $siteCacheResolveRefreshPortCount
        SiteCacheResolveRefreshPortKeysSample = $siteCacheResolveRefreshPortKeysSample
        SiteCacheResolveRefreshPortSignatureSample = $siteCacheResolveRefreshPortSignatureSample
        SiteCacheResolveRefreshPortSignatureMissingCount = $siteCacheResolveRefreshPortSignatureMissingCount
        SiteCacheResolveRefreshPortSignatureEmptyCount = $siteCacheResolveRefreshPortSignatureEmptyCount
        SiteCacheFetchDurationMs = $siteCacheFetchDurationMs
        SiteCacheRefreshDurationMs = $siteCacheRefreshDurationMs
        SiteCacheFetchStatus = $siteCacheFetchStatus
        SiteCacheSnapshotDurationMs = $siteCacheSnapshotDurationMs
        SiteCacheRecordsetDurationMs = $siteCacheRecordsetDurationMs
        SiteCacheRecordsetProjectDurationMs = $siteCacheRecordsetProjectDurationMs
        SiteCacheBuildDurationMs = $siteCacheBuildDurationMs
        SiteCacheHostMapDurationMs = $siteCacheHostMapDurationMs
        SiteCacheHostMapSignatureMatchCount   = $siteCacheHostMapSignatureMatchCount
        SiteCacheHostMapSignatureRewriteCount = $siteCacheHostMapSignatureRewriteCount
        SiteCacheHostMapEntryAllocationCount  = $siteCacheHostMapEntryAllocationCount
        SiteCacheHostMapEntryPoolReuseCount   = $siteCacheHostMapEntryPoolReuseCount
        SiteCacheHostMapLookupCount           = $siteCacheHostMapLookupCount
        SiteCacheHostMapLookupMissCount       = $siteCacheHostMapLookupMissCount
        SiteCacheHostMapCandidateMissingCount = $siteCacheHostMapCandidateMissingCount
        SiteCacheHostMapCandidateSignatureMissingCount = $siteCacheHostMapCandidateSignatureMissingCount
        SiteCacheHostMapCandidateSignatureMismatchCount = $siteCacheHostMapCandidateSignatureMismatchCount
        SiteCacheHostMapCandidateFromPreviousCount = $siteCacheHostMapCandidateFromPreviousCount
        SiteCacheHostMapCandidateFromPoolCount     = $siteCacheHostMapCandidateFromPoolCount
        SiteCacheHostMapCandidateInvalidCount      = $siteCacheHostMapCandidateInvalidCount
        SiteCacheHostMapCandidateMissingSamples    = $siteCacheHostMapCandidateMissingSamples
        SiteCacheHostMapSignatureMismatchSamples   = $siteCacheHostMapSignatureMismatchSamples
        SiteCachePreviousHostCount = $siteCachePreviousHostCount
        SiteCachePreviousPortCount = $siteCachePreviousPortCount
        SiteCachePreviousHostSample = $siteCachePreviousHostSample
        SiteCachePreviousSnapshotStatus = $siteCachePreviousSnapshotStatus
        SiteCachePreviousSnapshotHostMapType = $siteCachePreviousSnapshotHostMapType
        SiteCachePreviousSnapshotHostCount = $siteCachePreviousSnapshotHostCount
        SiteCachePreviousSnapshotPortCount = $siteCachePreviousSnapshotPortCount
        SiteCachePreviousSnapshotException = $siteCachePreviousSnapshotException
        SiteCacheSortDurationMs = $siteCacheSortDurationMs
        SiteCacheHostCount = $siteCacheHostCount
        SiteCacheQueryDurationMs = $siteCacheQueryDurationMs
        SiteCacheExecuteDurationMs = $siteCacheExecuteDurationMs
        SiteCacheMaterializeDurationMs = $siteCacheMaterializeDurationMs
        SiteCacheMaterializeProjectionDurationMs = $siteCacheMaterializeProjectionDurationMs
        SiteCacheMaterializePortSortDurationMs   = $siteCacheMaterializePortSortDurationMs
        SiteCacheMaterializePortSortCacheHitCount   = $siteCacheMaterializePortSortCacheHitCount
        SiteCacheMaterializePortSortCacheMissCount = $siteCacheMaterializePortSortCacheMissCount
        SiteCacheMaterializePortSortCacheSize      = $siteCacheMaterializePortSortCacheSize
        SiteCacheMaterializePortSortCacheHitRatio  = $siteCacheMaterializePortSortCacheHitRatio
        SiteCacheMaterializePortSortUniquePortCount = $siteCacheMaterializePortSortUniquePortCount
        SiteCacheMaterializePortSortMissSamples      = $siteCacheMaterializePortSortMissSamples
        SiteCacheMaterializeTemplateDurationMs   = $siteCacheMaterializeTemplateDurationMs
        SiteCacheMaterializeTemplateLookupDurationMs = $siteCacheMaterializeTemplateLookupDurationMs
        SiteCacheMaterializeTemplateApplyDurationMs  = $siteCacheMaterializeTemplateApplyDurationMs
        SiteCacheMaterializeTemplateCacheHitCount    = $siteCacheMaterializeTemplateCacheHitCount
        SiteCacheMaterializeTemplateCacheMissCount   = $siteCacheMaterializeTemplateCacheMissCount
        SiteCacheMaterializeTemplateReuseCount       = $siteCacheMaterializeTemplateReuseCount
        SiteCacheMaterializeTemplateCacheHitRatio    = $siteCacheMaterializeTemplateCacheHitRatio
        SiteCacheMaterializeTemplateApplyCount        = $siteCacheMaterializeTemplateApplyCount
        SiteCacheMaterializeTemplateDefaultedCount    = $siteCacheMaterializeTemplateDefaultedCount
        SiteCacheMaterializeTemplateAuthTemplateMissingCount = $siteCacheMaterializeTemplateAuthTemplateMissingCount
        SiteCacheMaterializeTemplateNoTemplateMatchCount     = $siteCacheMaterializeTemplateNoTemplateMatchCount
        SiteCacheMaterializeTemplateHintAppliedCount   = $siteCacheMaterializeTemplateHintAppliedCount
        SiteCacheMaterializeTemplateSetPortColorCount  = $siteCacheMaterializeTemplateSetPortColorCount
        SiteCacheMaterializeTemplateSetConfigStatusCount = $siteCacheMaterializeTemplateSetConfigStatusCount
        SiteCacheMaterializeTemplateApplySamples       = $siteCacheMaterializeTemplateApplySamples
        SiteCacheMaterializeObjectDurationMs     = $siteCacheMaterializeObjectDurationMs
        SiteCacheTemplateDurationMs = $siteCacheTemplateDurationMs
        SiteCacheQueryAttempts = $siteCacheQueryAttempts
        SiteCacheExclusiveRetryCount = $siteCacheExclusiveRetryCount
        SiteCacheExclusiveWaitDurationMs = $siteCacheExclusiveWaitDurationMs
        SiteCacheProvider = $siteCacheProvider
        SiteCacheProviderReason = $siteCacheProviderReason
        SiteCacheResultRowCount = $siteCacheResultRowCount
        SiteCacheExistingRowCount = $siteCacheExistingRowCount
        SiteCacheExistingRowKeysSample = $siteCacheExistingRowKeysSample
        SiteCacheExistingRowValueType = $siteCacheExistingRowValueType
        SiteCacheExistingRowSource = $siteCacheExistingRowSource
        SiteCacheComparisonCandidateCount = $cacheComparisonCandidateCount
        SiteCacheComparisonSignatureMatchCount = $cacheComparisonSignatureMatchCount
        SiteCacheComparisonSignatureMismatchCount = $cacheComparisonSignatureMismatchCount
        SiteCacheComparisonSignatureMissingCount = $cacheComparisonSignatureMissingCount
        SiteCacheComparisonMissingPortCount = $cacheComparisonMissingPortCount
        SiteCacheComparisonObsoletePortCount = $cacheComparisonObsoletePortCount
        DiffDurationMs = $diffDurationMs
            DiffComparisonDurationMs = [Math]::Round($diffComparisonDurationMs, 3)
            DiffRowsCompared = $diffRowsCompared
            DiffRowsChanged = $diffRowsChanged
            DiffRowsUnchanged = $diffRowsUnchanged
            DiffRowsInserted = $diffRowsInserted
            DiffDuplicatePorts = [int][Math]::Max(0, $totalFactsCount - $seenPorts.Count)
            BulkCommandExecuteDurationMs = $bulkCommandExecuteDurationMs
            StreamDispatchDurationMs = $bulkStreamDispatchDurationMs
            StreamCloneDurationMs = $streamCloneDurationMs
            StreamStateUpdateDurationMs = $streamStateUpdateDurationMs
            UiCloneDurationMs = $uiCloneDurationMsValue
            StreamRowsReceived = $streamRowsReceived
            StreamRowsReused = $streamRowsReused
            StreamRowsCloned = $streamRowsCloned
            SiteCacheUpdateDurationMs = $siteCacheUpdateDurationMs
            RowsStaged = [int]$rowsToWrite.Count
            InsertCandidates = $rowsInserted
            UpdateCandidates = $rowsUpdated
            DeleteCandidates = $rowsDeleted
        }
    } catch { }
}







function Ensure-InterfaceBulkSeedTable {

    [CmdletBinding()]

    param(

        [Parameter(Mandatory=$true)][object]$Connection

    )

    if (-not (Test-IsAdodbConnection -Connection $Connection)) { return $false }

    try {

        $Connection.Execute('SELECT TOP 1 BatchId FROM InterfaceBulkSeed') | Out-Null

        # Ensure newer schema columns exist for locale-safe RunDate handling.
        try {
            $Connection.Execute('SELECT TOP 1 RunDate FROM InterfaceBulkSeed') | Out-Null
        } catch {
            try {
                Invoke-AdodbNonQuery -Connection $Connection -CommandText 'ALTER TABLE InterfaceBulkSeed ADD COLUMN RunDate DATETIME' | Out-Null
            } catch { }
        }

        return $true

    } catch {

        try {

            $createSql = @"

CREATE TABLE InterfaceBulkSeed (

    BatchId TEXT(36) NOT NULL,

    Hostname TEXT(255),

    RunDateText TEXT(32),

    RunDate DATETIME,

    Port TEXT(255),

    Name TEXT(255),

    Status TEXT(255),

    VLAN INTEGER,

    Duplex TEXT(255),

    Speed TEXT(255),

    Type TEXT(255),

    LearnedMACs MEMO,

    AuthState TEXT(255),

    AuthMode TEXT(255),

    AuthClientMAC TEXT(255),

    AuthTemplate TEXT(255),

    Config MEMO,

    PortColor TEXT(255),

    ConfigStatus TEXT(255),

    ToolTip MEMO

)

"@

            Invoke-AdodbNonQuery -Connection $Connection -CommandText $createSql | Out-Null

            try { Invoke-AdodbNonQuery -Connection $Connection -CommandText 'CREATE INDEX IX_InterfaceBulkSeed_BatchId ON InterfaceBulkSeed (BatchId)' | Out-Null } catch { }

            return $true

        } catch {

            Write-Warning ("Failed to ensure InterfaceBulkSeed staging table: {0}" -f $_.Exception.Message)

            return $false

        }

    }

}

function Invoke-InterfaceBulkInsertInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Connection,
        [Parameter(Mandatory=$true)][string]$Hostname,
        [Parameter(Mandatory=$true)][datetime]$RunDate,
        [Parameter(Mandatory=$true)][System.Collections.IEnumerable]$Rows,
        [Parameter()][int]$InsertRowCount = 0,
        [Parameter()][int]$UpdateRowCount = 0
    )

    $batchId = ([guid]::NewGuid()).ToString()
    $runDateText = $RunDate.ToString('yyyy-MM-dd HH:mm:ss')

    $rowsBuffer = $null
    $stagedCount = 0

    $stageDurationMs = 0.0
    $interfaceUpdateDurationMs = 0.0
    $interfaceInsertDurationMs = 0.0
    $historyInsertDurationMs = 0.0
    $cleanupDurationMs = 0.0
    $transactionCommitDurationMs = 0.0
    $transactionUsed = $false
    $transactionLevel = $null
    $transactionCommitted = $false
    $transactionRolledBack = $false
    $parameterBindDurationMs = 0.0
    $commandExecuteDurationMs = 0.0
    $recordsetAttempted = $false
    $recordsetSucceeded = $false

    $streamDispatchDurationMs = 0.0
    $streamCloneDurationMs = 0.0
    $streamStateUpdateDurationMs = 0.0
    $streamRowsReceived = 0
    $streamRowsReused = 0
    $streamRowsCloned = 0
    $setLastBulkMetrics = {
        param([bool]$resultFlag)

        $script:LastInterfaceBulkInsertMetrics = [pscustomobject]@{
            Hostname = $Hostname
            BatchId = $batchId
            RunDate = $runDateText
            Rows = if ($rowsBuffer) { [int]$rowsBuffer.Count } else { 0 }
            RowsStaged = [int]$stagedCount
            InsertRowCount = [int]$InsertRowCount
            UpdateRowCount = [int]$UpdateRowCount
            UiCloneDurationMs = $uiCloneDurationMs
            StageDurationMs = $stageDurationMs
            ParameterBindDurationMs = $parameterBindDurationMs
            CommandExecuteDurationMs = $commandExecuteDurationMs
            InterfaceUpdateDurationMs = $interfaceUpdateDurationMs
            InterfaceInsertDurationMs = $interfaceInsertDurationMs
            HistoryInsertDurationMs = $historyInsertDurationMs
            CleanupDurationMs = $cleanupDurationMs
            TransactionCommitDurationMs = $transactionCommitDurationMs
            TransactionUsed = $transactionUsed
            TransactionLevel = $transactionLevel
            TransactionCommitted = $transactionCommitted
            TransactionRolledBack = $transactionRolledBack
            RecordsetAttempted = $recordsetAttempted
            RecordsetUsed = $recordsetSucceeded
            StreamDispatchDurationMs = $streamDispatchDurationMs
            StreamCloneDurationMs = $streamCloneDurationMs
            StreamStateUpdateDurationMs = $streamStateUpdateDurationMs
            StreamRowsReceived = $streamRowsReceived
            StreamRowsReused = $streamRowsReused
            StreamRowsCloned = $streamRowsCloned
            Success = [bool]$resultFlag
        }

        return [bool]$resultFlag
    }

    if (-not (Test-IsAdodbConnection -Connection $Connection)) { return (& $setLastBulkMetrics $false) }

    $rowsBufferCapacity = 0
    if ($Rows -is [System.Collections.ICollection]) {
        try { $rowsBufferCapacity = [int]$Rows.Count } catch { $rowsBufferCapacity = 0 }
        if ($rowsBufferCapacity -lt 0) { $rowsBufferCapacity = 0 }
    }

    $newUiList = {
        param([System.Collections.IEnumerable]$items)

        $capacity = 0
        if ($items -is [System.Collections.ICollection]) {
            try { $capacity = [int]$items.Count } catch { $capacity = 0 }
            if ($capacity -lt 0) { $capacity = 0 }
        }

        if ($capacity -gt 0) {
            return [System.Collections.Generic.List[psobject]]::new($capacity)
        }
        return [System.Collections.Generic.List[psobject]]::new()
    }

    $convertUiRow = {
        param($row)

        if ($null -eq $row) { return $null }

        try {
            if (Get-Command -Name 'DeviceRepositoryModule\ConvertTo-PortPsObject' -ErrorAction SilentlyContinue) {
                return DeviceRepositoryModule\ConvertTo-PortPsObject -Row $row -Hostname $Hostname -EnsureHostname -EnsureIsSelected
            }
        } catch { }

        $clone = $null
        if ($row -is [psobject]) {
            $clone = $row
        } elseif ($row -is [System.Collections.IDictionary]) {
            $clone = [PSCustomObject]@{}
            foreach ($key in $row.Keys) {
                $clone | Add-Member -NotePropertyName $key -NotePropertyValue $row[$key] -Force
            }
        } else {
            $clone = New-Object psobject
            try {
                foreach ($prop in $row.PSObject.Properties) {
                    $clone | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
                }
            } catch {
                $clone = [PSCustomObject]@{}
            }
        }

        if (-not $clone.PSObject.Properties['Hostname']) {
            $clone | Add-Member -NotePropertyName Hostname -NotePropertyValue $Hostname -Force
        }
        if (-not $clone.PSObject.Properties['IsSelected']) {
            $clone | Add-Member -NotePropertyName IsSelected -NotePropertyValue $false -Force
        }
        return $clone
    }

    if ($rowsBufferCapacity -gt 0) {
        $rowsBuffer = [System.Collections.Generic.List[object[]]]::new($rowsBufferCapacity)
        $uiRows = & $newUiList $Rows
    } else {
        $rowsBuffer = [System.Collections.Generic.List[object[]]]::new()
        $uiRows = & $newUiList $null
    }
    $uiCloneDurationMs = 0.0
    $uiCloneStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $extractStringValue = {
        param($properties, $propertyName)

        $property = $properties[$propertyName]
        if ($property -and $null -ne $property.Value) {
            return [string]$property.Value
        }
        return ''
    }

    foreach ($row in $Rows) {
        if ($null -eq $row) { continue }

        $properties = $row.PSObject.Properties

        $vlanNumeric = 0
        $vlanNumericProperty = $properties['VlanNumeric']
        if ($vlanNumericProperty) {
            $vlanNumericValue = $vlanNumericProperty.Value
            if ($null -ne $vlanNumericValue) {
                try { $vlanNumeric = [int]$vlanNumericValue } catch { $vlanNumeric = 0 }
            }
        } else {
            $vlanProperty = $properties['VLAN']
            if ($vlanProperty) {
                $vlanValue = $vlanProperty.Value
                if ($null -ne $vlanValue) {
                    $rawVlan = [string]$vlanValue
                    [void][int]::TryParse($rawVlan, [ref]$vlanNumeric)
                }
            }
        }

        $rowValues = New-Object object[] 20
        $rowValues[0] = $batchId
        $rowValues[1] = $Hostname
        $rowValues[2] = $runDateText
        $rowValues[3] = $RunDate
        $rowValues[4] = & $extractStringValue $properties 'Port'
        $rowValues[5] = & $extractStringValue $properties 'Name'
        $rowValues[6] = & $extractStringValue $properties 'Status'
        $rowValues[7] = $vlanNumeric
        $rowValues[8] = & $extractStringValue $properties 'Duplex'
        $rowValues[9] = & $extractStringValue $properties 'Speed'
        $rowValues[10] = & $extractStringValue $properties 'Type'
        $rowValues[11] = & $extractStringValue $properties 'Learned'
        $rowValues[12] = & $extractStringValue $properties 'AuthState'
        $rowValues[13] = & $extractStringValue $properties 'AuthMode'
        $rowValues[14] = & $extractStringValue $properties 'AuthClient'
        $rowValues[15] = & $extractStringValue $properties 'Template'
        $rowValues[16] = & $extractStringValue $properties 'Config'
        $rowValues[17] = & $extractStringValue $properties 'PortColor'
        $rowValues[18] = & $extractStringValue $properties 'StatusTag'
        $rowValues[19] = & $extractStringValue $properties 'ToolTip'

        $rowsBuffer.Add($rowValues) | Out-Null

        try {
            $clone = & $convertUiRow $row
            if ($clone) { $uiRows.Add($clone) | Out-Null }
        } catch { }
    }
    $uiCloneStopwatch.Stop()
    $uiCloneDurationMs = [Math]::Round($uiCloneStopwatch.Elapsed.TotalMilliseconds, 3)

    if ($rowsBuffer.Count -eq 0) { return (& $setLastBulkMetrics $true) }
    if (-not (Ensure-InterfaceBulkSeedTable -Connection $Connection)) { return (& $setLastBulkMetrics $false) }

    $escBatch = $batchId -replace "'", "''"
    $escHostname = $Hostname -replace "'", "''"

    $cleanupSql = "DELETE FROM InterfaceBulkSeed WHERE BatchId = '$escBatch'"
    $invokeCleanup = {
        param([switch]$RecordDuration)

        $cleanupStopwatch = $null
        if ($RecordDuration) {
            $cleanupStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        }

        try { Invoke-AdodbNonQuery -Connection $Connection -CommandText $cleanupSql | Out-Null } catch { }

        if ($cleanupStopwatch) {
            $cleanupStopwatch.Stop()
            $cleanupDurationMs = [Math]::Round($cleanupStopwatch.Elapsed.TotalMilliseconds, 3)
        }
    }
    $streamDispatchDurationMs = 0.0
    $streamCloneDurationMs = 0.0
    $streamStateUpdateDurationMs = 0.0
    $streamRowsReceived = 0
    $streamRowsReused = 0
    $streamRowsCloned = 0

    $seedRecordset = New-AdodbInterfaceSeedRecordset -Connection $Connection
    if ($seedRecordset) {
        $recordsetAttempted = $true
        $stageStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $parameterBindStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $fieldNames = @('BatchId', 'Hostname', 'RunDateText', 'RunDate', 'Port', 'Name', 'Status', 'VLAN', 'Duplex', 'Speed', 'Type', 'LearnedMACs', 'AuthState', 'AuthMode', 'AuthClientMAC', 'AuthTemplate', 'Config', 'PortColor', 'ConfigStatus', 'ToolTip')

            foreach ($rowValues in $rowsBuffer) {
                $seedRecordset.AddNew($fieldNames, $rowValues)
                $stagedCount++
            }

            $parameterBindStopwatch.Stop()
            $parameterBindDurationMs = [Math]::Round($parameterBindStopwatch.Elapsed.TotalMilliseconds, 3)

            if ($stagedCount -gt 0) {
                $executeStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                $seedRecordset.UpdateBatch()
                $executeStopwatch.Stop()
                $commandExecuteDurationMs = [Math]::Round($executeStopwatch.Elapsed.TotalMilliseconds, 3)
            }

            $recordsetSucceeded = $true
        } catch {
            $stagedCount = 0
            $parameterBindDurationMs = 0.0
            $commandExecuteDurationMs = 0.0
            try { $seedRecordset.CancelUpdate() } catch { }
            & $invokeCleanup
        } finally {
            $stageStopwatch.Stop()
            if ($recordsetSucceeded) {
                $stageDurationMs = [Math]::Round($stageStopwatch.Elapsed.TotalMilliseconds, 3)
            }
            try {
                if ($seedRecordset.State -ne 0) { $seedRecordset.Close() }
            } catch { }
            Release-ComObjectSafe -ComObject $seedRecordset
        }
    }

    if (-not $recordsetSucceeded) {
        $stagedCount = 0
        $stageDurationMs = 0.0
        $parameterBindDurationMs = 0.0
        $commandExecuteDurationMs = 0.0

        $insertSql = 'INSERT INTO InterfaceBulkSeed (BatchId, Hostname, RunDateText, RunDate, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
        $insertCmd = New-AdodbTextCommand -Connection $Connection -CommandText $insertSql
        if (-not $insertCmd) { return (& $setLastBulkMetrics $false) }

        try {
            $parameters = @(
                Add-AdodbParameter -Command $insertCmd -Name 'BatchId' -Type $script:AdTypeVarWChar -Size 36
                Add-AdodbParameter -Command $insertCmd -Name 'Hostname' -Type $script:AdTypeVarWChar -Size 255
                Add-AdodbParameter -Command $insertCmd -Name 'RunDateText' -Type $script:AdTypeVarWChar -Size 32
                Add-AdodbParameter -Command $insertCmd -Name 'RunDate' -Type $script:AdTypeDate
                Add-AdodbParameter -Command $insertCmd -Name 'Port' -Type $script:AdTypeVarWChar -Size 255
                Add-AdodbParameter -Command $insertCmd -Name 'Name' -Type $script:AdTypeVarWChar -Size 255
                Add-AdodbParameter -Command $insertCmd -Name 'Status' -Type $script:AdTypeVarWChar -Size 255
                Add-AdodbParameter -Command $insertCmd -Name 'VLAN' -Type $script:AdTypeInteger
                Add-AdodbParameter -Command $insertCmd -Name 'Duplex' -Type $script:AdTypeVarWChar -Size 255
                Add-AdodbParameter -Command $insertCmd -Name 'Speed' -Type $script:AdTypeVarWChar -Size 255
                Add-AdodbParameter -Command $insertCmd -Name 'Type' -Type $script:AdTypeVarWChar -Size 255
                Add-AdodbParameter -Command $insertCmd -Name 'Learned' -Type $script:AdTypeLongVarWChar
                Add-AdodbParameter -Command $insertCmd -Name 'AuthState' -Type $script:AdTypeVarWChar -Size 255
                Add-AdodbParameter -Command $insertCmd -Name 'AuthMode' -Type $script:AdTypeVarWChar -Size 255
                Add-AdodbParameter -Command $insertCmd -Name 'AuthClient' -Type $script:AdTypeVarWChar -Size 255
                Add-AdodbParameter -Command $insertCmd -Name 'AuthTemplate' -Type $script:AdTypeVarWChar -Size 255
                Add-AdodbParameter -Command $insertCmd -Name 'Config' -Type $script:AdTypeLongVarWChar
                Add-AdodbParameter -Command $insertCmd -Name 'PortColor' -Type $script:AdTypeVarWChar -Size 255
                Add-AdodbParameter -Command $insertCmd -Name 'ConfigStatus' -Type $script:AdTypeVarWChar -Size 255
                Add-AdodbParameter -Command $insertCmd -Name 'ToolTip' -Type $script:AdTypeLongVarWChar
            )

            if ($parameters -contains $null) {
                & $invokeCleanup -RecordDuration
                return (& $setLastBulkMetrics $false)
            }

            Set-AdodbParameterValue -Parameter $parameters[0] -Value $batchId
            Set-AdodbParameterValue -Parameter $parameters[1] -Value $Hostname
            Set-AdodbParameterValue -Parameter $parameters[2] -Value $runDateText
            Set-AdodbParameterValue -Parameter $parameters[3] -Value $RunDate

            $stageStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $bindDurationTotal = 0.0
            $executeDurationTotal = 0.0
            try {
                foreach ($rowValues in $rowsBuffer) {
                    $bindStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

                    Set-AdodbParameterValue -Parameter $parameters[4] -Value $rowValues[4]
                    Set-AdodbParameterValue -Parameter $parameters[5] -Value $rowValues[5]
                    Set-AdodbParameterValue -Parameter $parameters[6] -Value $rowValues[6]
                    Set-AdodbParameterValue -Parameter $parameters[7] -Value $rowValues[7]
                    Set-AdodbParameterValue -Parameter $parameters[8] -Value $rowValues[8]
                    Set-AdodbParameterValue -Parameter $parameters[9] -Value $rowValues[9]
                    Set-AdodbParameterValue -Parameter $parameters[10] -Value $rowValues[10]
                    Set-AdodbParameterValue -Parameter $parameters[11] -Value $rowValues[11]
                    Set-AdodbParameterValue -Parameter $parameters[12] -Value $rowValues[12]
                    Set-AdodbParameterValue -Parameter $parameters[13] -Value $rowValues[13]
                    Set-AdodbParameterValue -Parameter $parameters[14] -Value $rowValues[14]
                    Set-AdodbParameterValue -Parameter $parameters[15] -Value $rowValues[15]
                    Set-AdodbParameterValue -Parameter $parameters[16] -Value $rowValues[16]
                    Set-AdodbParameterValue -Parameter $parameters[17] -Value $rowValues[17]
                    Set-AdodbParameterValue -Parameter $parameters[18] -Value $rowValues[18]
                    Set-AdodbParameterValue -Parameter $parameters[19] -Value $rowValues[19]

                    $bindStopwatch.Stop()
                    $bindDurationTotal += $bindStopwatch.Elapsed.TotalMilliseconds

                    $executeStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                    try {
                        $recordsAffectedRef = [ref]0
                        $insertCmd.Execute($recordsAffectedRef, $null, $script:AdExecuteNoRecords) | Out-Null
                    } catch {
                        try {
                            $insertCmd.Execute() | Out-Null
                        } catch {
                            & $invokeCleanup -RecordDuration
                            throw
                        }
                    } finally {
                        $executeStopwatch.Stop()
                        $executeDurationTotal += $executeStopwatch.Elapsed.TotalMilliseconds
                    }

                    $stagedCount++
                }
            } finally {
                $stageStopwatch.Stop()
                $stageDurationMs = [Math]::Round($stageStopwatch.Elapsed.TotalMilliseconds, 3)
                $parameterBindDurationMs = [Math]::Round($bindDurationTotal, 3)
                $commandExecuteDurationMs = [Math]::Round($executeDurationTotal, 3)
            }
        } catch {
            Write-Warning ("Failed to stage interfaces for host {0}: {1}" -f $Hostname, $_.Exception.Message)
            return (& $setLastBulkMetrics $false)
        } finally {
            Release-ComObjectSafe -ComObject $insertCmd
        }
    }

    if ($stagedCount -eq 0) {
        & $invokeCleanup -RecordDuration
        return (& $setLastBulkMetrics $true)
    }

    $success = $false
    $commitStopwatch = $null

    $beginTransMethod = $null
    try { $beginTransMethod = $Connection.PSObject.Methods | Where-Object { $_.Name -eq 'BeginTrans' } } catch { $beginTransMethod = $null }
    if ($beginTransMethod) {
        try {
            $transactionLevel = $Connection.BeginTrans()
            $transactionUsed = $true
        } catch {
            $transactionLevel = $null
            $transactionUsed = $false
        }
    }

    $updateInterfacesSql = "UPDATE Interfaces AS Target
INNER JOIN InterfaceBulkSeed AS Seed
ON (Target.Hostname = Seed.Hostname) AND (Target.Port = Seed.Port)
SET Target.Name = Seed.Name,
    Target.Status = Seed.Status,
    Target.VLAN = Seed.VLAN,
    Target.Duplex = Seed.Duplex,
    Target.Speed = Seed.Speed,
    Target.Type = Seed.Type,
    Target.LearnedMACs = Seed.LearnedMACs,
    Target.AuthState = Seed.AuthState,
    Target.AuthMode = Seed.AuthMode,
    Target.AuthClientMAC = Seed.AuthClientMAC,
    Target.AuthTemplate = Seed.AuthTemplate,
    Target.Config = Seed.Config,
    Target.PortColor = Seed.PortColor,
    Target.ConfigStatus = Seed.ConfigStatus,
    Target.ToolTip = Seed.ToolTip
WHERE Seed.BatchId = '$escBatch' AND Seed.Hostname = '$escHostname'"

    $insertInterfacesSql = "INSERT INTO Interfaces (Hostname, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip)
SELECT Seed.Hostname, Seed.Port, Seed.Name, Seed.Status, Seed.VLAN, Seed.Duplex, Seed.Speed, Seed.Type, Seed.LearnedMACs, Seed.AuthState, Seed.AuthMode, Seed.AuthClientMAC, Seed.AuthTemplate, Seed.Config, Seed.PortColor, Seed.ConfigStatus, Seed.ToolTip
FROM InterfaceBulkSeed AS Seed
LEFT JOIN Interfaces AS Existing ON (Existing.Hostname = Seed.Hostname) AND (Existing.Port = Seed.Port)
WHERE Seed.BatchId = '$escBatch' AND Seed.Hostname = '$escHostname' AND Existing.Hostname IS NULL"

    $insertHistorySql = "INSERT INTO InterfaceHistory (Hostname, RunDate, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip)
SELECT Seed.Hostname, IIf(IsNull(Seed.RunDate), CDate(Seed.RunDateText), Seed.RunDate), Seed.Port, Seed.Name, Seed.Status, Seed.VLAN, Seed.Duplex, Seed.Speed, Seed.Type, Seed.LearnedMACs, Seed.AuthState, Seed.AuthMode, Seed.AuthClientMAC, Seed.AuthTemplate, Seed.Config, Seed.PortColor, Seed.ConfigStatus, Seed.ToolTip
FROM InterfaceBulkSeed AS Seed
WHERE Seed.BatchId = '$escBatch' AND Seed.Hostname = '$escHostname'"

    try {
        if ($UpdateRowCount -gt 0) {
            $updateStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Invoke-AdodbNonQuery -Connection $Connection -CommandText $updateInterfacesSql | Out-Null
            $updateStopwatch.Stop()
            $interfaceUpdateDurationMs = [Math]::Round($updateStopwatch.Elapsed.TotalMilliseconds, 3)
        }

        if ($InsertRowCount -gt 0) {
            $interfacesStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Invoke-AdodbNonQuery -Connection $Connection -CommandText $insertInterfacesSql | Out-Null
            $interfacesStopwatch.Stop()
            $interfaceInsertDurationMs = [Math]::Round($interfacesStopwatch.Elapsed.TotalMilliseconds, 3)
        }

        $historyStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        Invoke-AdodbNonQuery -Connection $Connection -CommandText $insertHistorySql | Out-Null
        $historyStopwatch.Stop()
        $historyInsertDurationMs = [Math]::Round($historyStopwatch.Elapsed.TotalMilliseconds, 3)

        if ($transactionUsed) {
            $commitMethod = $null
            try { $commitMethod = $Connection.PSObject.Methods | Where-Object { $_.Name -eq 'CommitTrans' } } catch { $commitMethod = $null }
            if ($commitMethod) {
                $commitStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                try {
                    $null = $Connection.CommitTrans()
                    $transactionCommitted = $true
                } finally {
                    $commitStopwatch.Stop()
                    $transactionCommitDurationMs = [Math]::Round($commitStopwatch.Elapsed.TotalMilliseconds, 3)
                }
            }
        }

        $success = $true
    } catch {
        if ($transactionUsed -and -not $transactionCommitted) {
            $rollbackMethod = $null
            try { $rollbackMethod = $Connection.PSObject.Methods | Where-Object { $_.Name -eq 'RollbackTrans' } } catch { $rollbackMethod = $null }
            if ($rollbackMethod) {
                try {
                    $Connection.RollbackTrans() | Out-Null
                    $transactionRolledBack = $true
                } catch {
                    $transactionRolledBack = $false
                }
            }
        }

        Write-Warning ("Failed to commit bulk interface rows for host {0}: {1}" -f $Hostname, $_.Exception.Message)
    } finally {
        & $invokeCleanup -RecordDuration
    }

    try {
        TelemetryModule\Write-StTelemetryEvent -Name 'InterfaceBulkInsertTiming' -Payload @{
            Hostname = $Hostname
            BatchId  = $batchId
            Rows     = [int]$rowsBuffer.Count
            RunDate  = $runDateText
            UiCloneDurationMs = $uiCloneDurationMs
            StageDurationMs = $stageDurationMs
            ParameterBindDurationMs = $parameterBindDurationMs
            CommandExecuteDurationMs = $commandExecuteDurationMs
            InterfaceUpdateDurationMs = $interfaceUpdateDurationMs
            InterfaceInsertDurationMs = $interfaceInsertDurationMs
            HistoryInsertDurationMs = $historyInsertDurationMs
            CleanupDurationMs = $cleanupDurationMs
            TransactionUsed = $transactionUsed
            TransactionLevel = $transactionLevel
            TransactionCommitted = $transactionCommitted
            TransactionRolledBack = $transactionRolledBack
            TransactionCommitDurationMs = $transactionCommitDurationMs
            RecordsetAttempted = $recordsetAttempted
            RecordsetUsed = $recordsetSucceeded
            StreamDispatchDurationMs = $streamDispatchDurationMs
            StreamCloneDurationMs = $streamCloneDurationMs
            StreamStateUpdateDurationMs = $streamStateUpdateDurationMs
            StreamRowsReceived = $streamRowsReceived
            StreamRowsReused = $streamRowsReused
            StreamRowsCloned = $streamRowsCloned
            InsertRowCount = [int]$InsertRowCount
            UpdateRowCount = [int]$UpdateRowCount
            Success = $success
        }
    } catch { }

    try {
        TelemetryModule\Write-StTelemetryEvent -Name 'InterfaceBulkInsert' -Payload @{
            Hostname = $Hostname
            BatchId  = $batchId
            Rows     = [int]$rowsBuffer.Count
            RunDate  = $runDateText
            Success  = $success
        }
    } catch { }

    if ($success) {
        $totalPorts = 0
        if ($uiRows -and $uiRows.Count -gt 0) {
            $totalPorts = [int]$uiRows.Count
        } elseif ($rowsBuffer -and $rowsBuffer.Count -gt 0) {
            $totalPorts = [int]$rowsBuffer.Count
        }
        $streamStopwatch = $null
        try {
            $streamStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            DeviceRepositoryModule\Set-InterfacePortStreamData -Hostname $Hostname -RunDate $RunDate -InterfaceRows $uiRows -BatchId $batchId
        } catch { }
        finally {
            if ($streamStopwatch) {
                $streamStopwatch.Stop()
                $streamDispatchDurationMs = [Math]::Round($streamStopwatch.Elapsed.TotalMilliseconds, 3)
            }
        }

        $streamMetrics = $null
        try { $streamMetrics = DeviceRepositoryModule\Get-LastInterfacePortStreamMetrics } catch { $streamMetrics = $null }
        if ($streamMetrics) {
            if ($streamMetrics.PSObject.Properties.Name -contains 'StreamCloneDurationMs') {
                $streamCloneDurationMs = [double]$streamMetrics.StreamCloneDurationMs
            }
            if ($streamMetrics.PSObject.Properties.Name -contains 'StreamStateUpdateDurationMs') {
                $streamStateUpdateDurationMs = [double]$streamMetrics.StreamStateUpdateDurationMs
            }
            if ($streamMetrics.PSObject.Properties.Name -contains 'RowsReceived') {
                $streamRowsReceived = [int]$streamMetrics.RowsReceived
            }
            if ($streamMetrics.PSObject.Properties.Name -contains 'RowsReused') {
                $streamRowsReused = [int]$streamMetrics.RowsReused
            }
            if ($streamMetrics.PSObject.Properties.Name -contains 'RowsCloned') {
                $streamRowsCloned = [int]$streamMetrics.RowsCloned
            }
            if ($script:LastInterfaceSyncTelemetry -and $script:LastInterfaceSyncTelemetry.Hostname -eq $Hostname) {
                $script:LastInterfaceSyncTelemetry.StreamCloneDurationMs = $streamCloneDurationMs
                $script:LastInterfaceSyncTelemetry.StreamStateUpdateDurationMs = $streamStateUpdateDurationMs
                $script:LastInterfaceSyncTelemetry.StreamRowsReceived = $streamRowsReceived
                $script:LastInterfaceSyncTelemetry.StreamRowsReused = $streamRowsReused
                $script:LastInterfaceSyncTelemetry.StreamRowsCloned = $streamRowsCloned
                $script:LastInterfaceSyncTelemetry.StreamDispatchDurationMs = $streamDispatchDurationMs
            }
        }

        $chunkSize = 24
        try { $chunkSize = DeviceRepositoryModule\Get-InterfacePortBatchChunkSize } catch { $chunkSize = 24 }
        if ($chunkSize -le 0) { $chunkSize = 24 }
        $estimatedBatchCount = if ($totalPorts -gt 0) { [int][Math]::Ceiling($totalPorts / [double]$chunkSize) } else { 0 }

        try {
            TelemetryModule\Write-StTelemetryEvent -Name 'PortBatchReady' -Payload @{
                Hostname             = $Hostname
                BatchId              = $batchId
                RunDate              = $runDateText
                PortsCommitted       = $totalPorts
                ChunkSize            = $chunkSize
                EstimatedBatchCount  = $estimatedBatchCount
            }
        } catch { }
    } else {
        try { DeviceRepositoryModule\Clear-InterfacePortStream -Hostname $Hostname } catch { }
    }

    return (& $setLastBulkMetrics $success)
}







function Invoke-DeviceSummaryParameterized {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Connection,
        [Parameter(Mandatory=$true)][string]$Hostname,
        [Parameter(Mandatory=$true)][hashtable]$Values,
        [Parameter(Mandatory=$true)][datetime]$RunDate
    )

    $updateSql = 'UPDATE DeviceSummary SET Make=?, Model=?, Uptime=?, Site=?, Building=?, Room=?, Ports=?, AuthDefaultVLAN=?, AuthBlock=? WHERE Hostname=?'
    $updateCmd = New-AdodbTextCommand -Connection $Connection -CommandText $updateSql
    if (-not $updateCmd) { return $false }

    try {
        $parameters = @(
            Add-AdodbParameter -Command $updateCmd -Name 'Make' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $updateCmd -Name 'Model' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $updateCmd -Name 'Uptime' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $updateCmd -Name 'Site' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $updateCmd -Name 'Building' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $updateCmd -Name 'Room' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $updateCmd -Name 'Ports' -Type $script:AdTypeInteger
            Add-AdodbParameter -Command $updateCmd -Name 'AuthDefaultVLAN' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $updateCmd -Name 'AuthBlock' -Type $script:AdTypeLongVarWChar
            Add-AdodbParameter -Command $updateCmd -Name 'Hostname' -Type $script:AdTypeVarWChar -Size 255
        )

        if ($parameters -contains $null) { return $false }

        Set-AdodbParameterValue -Parameter $parameters[0] -Value ([string]$Values.Make)
        Set-AdodbParameterValue -Parameter $parameters[1] -Value ([string]$Values.Model)
        Set-AdodbParameterValue -Parameter $parameters[2] -Value ([string]$Values.Uptime)
        Set-AdodbParameterValue -Parameter $parameters[3] -Value ([string]$Values.Site)
        Set-AdodbParameterValue -Parameter $parameters[4] -Value ([string]$Values.Building)
        Set-AdodbParameterValue -Parameter $parameters[5] -Value ([string]$Values.Room)
        Set-AdodbParameterValue -Parameter $parameters[6] -Value ([int]$Values.Ports)
        Set-AdodbParameterValue -Parameter $parameters[7] -Value ([string]$Values.AuthDefaultVlan)
        Set-AdodbParameterValue -Parameter $parameters[8] -Value ([string]$Values.AuthBlock)
        Set-AdodbParameterValue -Parameter $parameters[9] -Value $Hostname

        try { $updateCmd.Execute() | Out-Null } catch { }
    } finally {
        Release-ComObjectSafe -ComObject $updateCmd
    }

    $insertSql = 'INSERT INTO DeviceSummary (Hostname, Make, Model, Uptime, Site, Building, Room, Ports, AuthDefaultVLAN, AuthBlock) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
    $insertCmd = New-AdodbTextCommand -Connection $Connection -CommandText $insertSql
    if (-not $insertCmd) { return $false }

    try {
        $parameters = @(
            Add-AdodbParameter -Command $insertCmd -Name 'Hostname' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $insertCmd -Name 'Make' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $insertCmd -Name 'Model' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $insertCmd -Name 'Uptime' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $insertCmd -Name 'Site' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $insertCmd -Name 'Building' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $insertCmd -Name 'Room' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $insertCmd -Name 'Ports' -Type $script:AdTypeInteger
            Add-AdodbParameter -Command $insertCmd -Name 'AuthDefaultVLAN' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $insertCmd -Name 'AuthBlock' -Type $script:AdTypeLongVarWChar
        )

        if ($parameters -contains $null) { return $false }

        Set-AdodbParameterValue -Parameter $parameters[0] -Value $Hostname
        Set-AdodbParameterValue -Parameter $parameters[1] -Value ([string]$Values.Make)
        Set-AdodbParameterValue -Parameter $parameters[2] -Value ([string]$Values.Model)
        Set-AdodbParameterValue -Parameter $parameters[3] -Value ([string]$Values.Uptime)
        Set-AdodbParameterValue -Parameter $parameters[4] -Value ([string]$Values.Site)
        Set-AdodbParameterValue -Parameter $parameters[5] -Value ([string]$Values.Building)
        Set-AdodbParameterValue -Parameter $parameters[6] -Value ([string]$Values.Room)
        Set-AdodbParameterValue -Parameter $parameters[7] -Value ([int]$Values.Ports)
        Set-AdodbParameterValue -Parameter $parameters[8] -Value ([string]$Values.AuthDefaultVlan)
        Set-AdodbParameterValue -Parameter $parameters[9] -Value ([string]$Values.AuthBlock)

        try { $insertCmd.Execute() | Out-Null } catch { }
    } finally {
        Release-ComObjectSafe -ComObject $insertCmd
    }

    $historySql = 'INSERT INTO DeviceHistory (Hostname, RunDate, Make, Model, Uptime, Site, Building, Room, Ports, AuthDefaultVLAN, AuthBlock) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
    $historyCmd = New-AdodbTextCommand -Connection $Connection -CommandText $historySql
    if (-not $historyCmd) { return $false }

    try {
        $parameters = @(
            Add-AdodbParameter -Command $historyCmd -Name 'Hostname' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $historyCmd -Name 'RunDate' -Type $script:AdTypeDate
            Add-AdodbParameter -Command $historyCmd -Name 'Make' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $historyCmd -Name 'Model' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $historyCmd -Name 'Uptime' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $historyCmd -Name 'Site' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $historyCmd -Name 'Building' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $historyCmd -Name 'Room' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $historyCmd -Name 'Ports' -Type $script:AdTypeInteger
            Add-AdodbParameter -Command $historyCmd -Name 'AuthDefaultVLAN' -Type $script:AdTypeVarWChar -Size 255
            Add-AdodbParameter -Command $historyCmd -Name 'AuthBlock' -Type $script:AdTypeLongVarWChar
        )

        if ($parameters -contains $null) { return $false }

        Set-AdodbParameterValue -Parameter $parameters[0] -Value $Hostname
        Set-AdodbParameterValue -Parameter $parameters[1] -Value $RunDate
        Set-AdodbParameterValue -Parameter $parameters[2] -Value ([string]$Values.Make)
        Set-AdodbParameterValue -Parameter $parameters[3] -Value ([string]$Values.Model)
        Set-AdodbParameterValue -Parameter $parameters[4] -Value ([string]$Values.Uptime)
        Set-AdodbParameterValue -Parameter $parameters[5] -Value ([string]$Values.Site)
        Set-AdodbParameterValue -Parameter $parameters[6] -Value ([string]$Values.Building)
        Set-AdodbParameterValue -Parameter $parameters[7] -Value ([string]$Values.Room)
        Set-AdodbParameterValue -Parameter $parameters[8] -Value ([int]$Values.Ports)
        Set-AdodbParameterValue -Parameter $parameters[9] -Value ([string]$Values.AuthDefaultVlan)
        Set-AdodbParameterValue -Parameter $parameters[10] -Value ([string]$Values.AuthBlock)

        try { $historyCmd.Execute() | Out-Null } catch {
            Write-Warning "Failed to insert device history for host ${Hostname}: $($_.Exception.Message)"
            Write-Verbose ("Device history exception details: {0}" -f ($_.Exception | Format-List * | Out-String))
        }
    } finally {
        Release-ComObjectSafe -ComObject $historyCmd
    }

    return $true
}

function Invoke-InterfaceRowParameterized {

    [CmdletBinding()]

    param(

        [Parameter(Mandatory=$true)][object]$Connection,

        [Parameter(Mandatory=$true)][string]$Hostname,

        [Parameter(Mandatory=$true)][object]$Row,

        [Parameter(Mandatory=$true)][datetime]$RunDate

    )



    $insertSql = 'INSERT INTO Interfaces (Hostname, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'

    $insertCmd = New-AdodbTextCommand -Connection $Connection -CommandText $insertSql

    if (-not $insertCmd) { return $false }



    $vlanNumeric = 0

    if ($Row.PSObject.Properties.Name -contains 'VlanNumeric' -and $null -ne $Row.VlanNumeric) {

        try { $vlanNumeric = [int]$Row.VlanNumeric } catch { $vlanNumeric = 0 }

    } else {

        [void][int]::TryParse($Row.VLAN, [ref]$vlanNumeric)

    }



    try {

        $parameters = @(

            Add-AdodbParameter -Command $insertCmd -Name 'Hostname' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'Port' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'Name' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'Status' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'VLAN' -Type $script:AdTypeInteger

            Add-AdodbParameter -Command $insertCmd -Name 'Duplex' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'Speed' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'Type' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'Learned' -Type $script:AdTypeLongVarWChar

            Add-AdodbParameter -Command $insertCmd -Name 'AuthState' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'AuthMode' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'AuthClient' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'AuthTemplate' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'Config' -Type $script:AdTypeLongVarWChar

            Add-AdodbParameter -Command $insertCmd -Name 'PortColor' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'ConfigStatus' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $insertCmd -Name 'ToolTip' -Type $script:AdTypeLongVarWChar

        )



        if ($parameters -contains $null) { return $false }



        Set-AdodbParameterValue -Parameter $parameters[0] -Value $Hostname

        Set-AdodbParameterValue -Parameter $parameters[1] -Value ([string]$Row.Port)

        Set-AdodbParameterValue -Parameter $parameters[2] -Value ([string]$Row.Name)

        Set-AdodbParameterValue -Parameter $parameters[3] -Value ([string]$Row.Status)

        Set-AdodbParameterValue -Parameter $parameters[4] -Value $vlanNumeric

        Set-AdodbParameterValue -Parameter $parameters[5] -Value ([string]$Row.Duplex)

        Set-AdodbParameterValue -Parameter $parameters[6] -Value ([string]$Row.Speed)

        Set-AdodbParameterValue -Parameter $parameters[7] -Value ([string]$Row.Type)

        Set-AdodbParameterValue -Parameter $parameters[8] -Value ([string]$Row.Learned)

        Set-AdodbParameterValue -Parameter $parameters[9] -Value ([string]$Row.AuthState)

        Set-AdodbParameterValue -Parameter $parameters[10] -Value ([string]$Row.AuthMode)

        Set-AdodbParameterValue -Parameter $parameters[11] -Value ([string]$Row.AuthClient)

        Set-AdodbParameterValue -Parameter $parameters[12] -Value ([string]$Row.Template)

        Set-AdodbParameterValue -Parameter $parameters[13] -Value ([string]$Row.Config)

        Set-AdodbParameterValue -Parameter $parameters[14] -Value ([string]$Row.PortColor)

        Set-AdodbParameterValue -Parameter $parameters[15] -Value ([string]$Row.StatusTag)

        Set-AdodbParameterValue -Parameter $parameters[16] -Value ([string]$Row.ToolTip)



        try {

            $insertCmd.Execute() | Out-Null

        } catch {

            Write-Warning "Failed to insert interface record for host ${Hostname} port ${Row.Port}: $($_.Exception.Message)"

            Write-Verbose ("Interface insert exception details: {0}" -f ($_.Exception | Format-List * | Out-String))

            return $false

        }

    } finally {

        Release-ComObjectSafe -ComObject $insertCmd

    }



    $historySql = 'INSERT INTO InterfaceHistory (Hostname, RunDate, Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, PortColor, ConfigStatus, ToolTip) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'

    $historyCmd = New-AdodbTextCommand -Connection $Connection -CommandText $historySql

    if (-not $historyCmd) { return $true }



    try {

        $parameters = @(

            Add-AdodbParameter -Command $historyCmd -Name 'Hostname' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'RunDate' -Type $script:AdTypeDate

            Add-AdodbParameter -Command $historyCmd -Name 'Port' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'Name' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'Status' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'VLAN' -Type $script:AdTypeInteger

            Add-AdodbParameter -Command $historyCmd -Name 'Duplex' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'Speed' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'Type' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'Learned' -Type $script:AdTypeLongVarWChar

            Add-AdodbParameter -Command $historyCmd -Name 'AuthState' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'AuthMode' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'AuthClient' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'AuthTemplate' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'Config' -Type $script:AdTypeLongVarWChar

            Add-AdodbParameter -Command $historyCmd -Name 'PortColor' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'ConfigStatus' -Type $script:AdTypeVarWChar -Size 255

            Add-AdodbParameter -Command $historyCmd -Name 'ToolTip' -Type $script:AdTypeLongVarWChar

        )



        if ($parameters -contains $null) { return $true }



        Set-AdodbParameterValue -Parameter $parameters[0] -Value $Hostname

        Set-AdodbParameterValue -Parameter $parameters[1] -Value $RunDate

        Set-AdodbParameterValue -Parameter $parameters[2] -Value ([string]$Row.Port)

        Set-AdodbParameterValue -Parameter $parameters[3] -Value ([string]$Row.Name)

        Set-AdodbParameterValue -Parameter $parameters[4] -Value ([string]$Row.Status)

        Set-AdodbParameterValue -Parameter $parameters[5] -Value $vlanNumeric

        Set-AdodbParameterValue -Parameter $parameters[6] -Value ([string]$Row.Duplex)

        Set-AdodbParameterValue -Parameter $parameters[7] -Value ([string]$Row.Speed)

        Set-AdodbParameterValue -Parameter $parameters[8] -Value ([string]$Row.Type)

        Set-AdodbParameterValue -Parameter $parameters[9] -Value ([string]$Row.Learned)

        Set-AdodbParameterValue -Parameter $parameters[10] -Value ([string]$Row.AuthState)

        Set-AdodbParameterValue -Parameter $parameters[11] -Value ([string]$Row.AuthMode)

        Set-AdodbParameterValue -Parameter $parameters[12] -Value ([string]$Row.AuthClient)

        Set-AdodbParameterValue -Parameter $parameters[13] -Value ([string]$Row.Template)

        Set-AdodbParameterValue -Parameter $parameters[14] -Value ([string]$Row.Config)

        Set-AdodbParameterValue -Parameter $parameters[15] -Value ([string]$Row.PortColor)

        Set-AdodbParameterValue -Parameter $parameters[16] -Value ([string]$Row.StatusTag)

        Set-AdodbParameterValue -Parameter $parameters[17] -Value ([string]$Row.ToolTip)



        try {

            $historyCmd.Execute() | Out-Null

        } catch {

            Write-Warning "Failed to insert interface history for host ${Hostname} port ${Row.Port}: $($_.Exception.Message)"

        }

    } finally {

        Release-ComObjectSafe -ComObject $historyCmd

    }



    return $true

}





function Write-InterfacePersistenceFailure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Stage,
        [Parameter(Mandatory=$true)][string]$Hostname,
        [Parameter(Mandatory=$true)][System.Exception]$Exception,
        [Parameter()][hashtable]$Metadata
    )

    $payload = @{
        Stage = $Stage
        Hostname = $Hostname
        ExceptionMessage = $Exception.Message
        ExceptionType = $Exception.GetType().FullName
    }

    if ($Metadata) {
        foreach ($key in $Metadata.Keys) {
            $payload[$key] = $Metadata[$key]
        }
    }

    try {
        TelemetryModule\Write-StTelemetryEvent -Name 'InterfacePersistenceFailure' -Payload $payload
    } catch {
        Write-Warning ("Failed to emit interface persistence telemetry: {0}" -f $_.Exception.Message)
    }
}

function Update-SpanInfoInDb {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Connection,
        [Parameter(Mandatory=$true)][string]$Hostname,
        [Parameter(Mandatory=$true)][string]$RunDateString,
        [Parameter()][object[]]$SpanInfo
    )

    $escHostname = $Hostname -replace "'", "''"
    $runDateLiteral = "#$RunDateString#"
    $runDateValue = ConvertTo-DbDateTime -RunDateString $RunDateString
    if ($runDateValue) {
        try {
            $runDateLiteral = "#$($runDateValue.ToString('yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture))#"
        } catch { }
    }

    Ensure-SpanInfoTableExists -Connection $Connection

    try {
        Invoke-AdodbNonQuery -Connection $Connection -CommandText "DELETE FROM SpanInfo WHERE Hostname = '$escHostname'" | Out-Null
    } catch {
        Write-Warning "Failed to clear span data for host ${Hostname}: $($_.Exception.Message)"
    }

    if (-not $SpanInfo) { return }

    foreach ($item in $SpanInfo) {
        if ($null -eq $item) { continue }

        $vlan = ''
        if ($item.PSObject.Properties['VLAN']) { $vlan = '' + $item.VLAN }

        $rootSwitch = ''
        if ($item.PSObject.Properties['RootSwitch']) { $rootSwitch = '' + $item.RootSwitch }

        $rootPort = ''
        if ($item.PSObject.Properties['RootPort']) { $rootPort = '' + $item.RootPort }

        $role = ''
        if ($item.PSObject.Properties['Role']) { $role = '' + $item.Role }

        $upstream = ''
        if ($item.PSObject.Properties['Upstream']) { $upstream = '' + $item.Upstream }

        $escVlan     = $vlan -replace "'", "''"
        $escRoot     = $rootSwitch -replace "'", "''"
        $escPort     = $rootPort -replace "'", "''"
        $escRole     = $role -replace "'", "''"
        $escUpstream = $upstream -replace "'", "''"

        $insertSql = "INSERT INTO SpanInfo (Hostname, Vlan, RootSwitch, RootPort, Role, Upstream, LastUpdated) VALUES ('$escHostname', '$escVlan', '$escRoot', '$escPort', '$escRole', '$escUpstream', $runDateLiteral)"
        try {
            Invoke-AdodbNonQuery -Connection $Connection -CommandText $insertSql | Out-Null
        } catch {
            Write-Warning "Failed to insert span info for host ${Hostname}: $($_.Exception.Message)"
        }

        $histSql = "INSERT INTO SpanHistory (Hostname, RunDate, Vlan, RootSwitch, RootPort, Role, Upstream) VALUES ('$escHostname', $runDateLiteral, '$escVlan', '$escRoot', '$escPort', '$escRole', '$escUpstream')"
        try {
            Invoke-AdodbNonQuery -Connection $Connection -CommandText $histSql | Out-Null
        } catch {
            Write-Warning "Failed to insert span history for host ${Hostname}: $($_.Exception.Message)"
        }
    }
}

function Get-LastInterfaceSyncTelemetry {
    [CmdletBinding()]
    param()

    return $script:LastInterfaceSyncTelemetry
}

Export-ModuleMember -Function Update-DeviceSummaryInDb, Update-InterfacesInDb, Update-SpanInfoInDb, Write-InterfacePersistenceFailure, Get-LastInterfaceSyncTelemetry, Set-ParserSkipSiteCacheUpdate, Set-InterfaceBulkChunkSize, Get-SiteExistingRowCacheSnapshot, Set-SiteExistingRowCacheSnapshot, Clear-SiteExistingRowCache, Import-SiteExistingRowCacheSnapshotFromEnv
