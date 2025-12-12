Set-StrictMode -Version Latest

if (-not ('StateTrace.Repository.SharedSiteInterfaceCacheEntry' -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;

namespace StateTrace.Repository
{
    public sealed class SharedSiteInterfaceCacheEntry
    {
        public string SiteKey { get; set; }
        public IDictionary<string, object> HostMap { get; set; }
    }
}
"@
}

if (-not ('StateTrace.Repository.SharedSiteInterfaceCacheHolder' -as [type])) {
    Add-Type -TypeDefinition @"
namespace StateTrace.Repository
{
    using System.Collections.Concurrent;
    using System.Threading;

    public static class SharedSiteInterfaceCacheHolder
    {
        private static readonly object SyncRoot = new object();
        private static ConcurrentDictionary<string, object> store;
        private static readonly object SnapshotSyncRoot = new object();
        private static ConcurrentDictionary<string, object> snapshot;

        public static ConcurrentDictionary<string, object> GetStore()
        {
            lock (SyncRoot)
            {
                return store;
            }
        }

        public static void SetStore(ConcurrentDictionary<string, object> value)
        {
            lock (SyncRoot)
            {
                store = value;
            }
        }

        public static void ClearStore()
        {
            lock (SyncRoot)
            {
                store = null;
            }
        }

        public static ConcurrentDictionary<string, object> GetSnapshot()
        {
            lock (SnapshotSyncRoot)
            {
                return snapshot;
            }
        }

        public static void SetSnapshot(ConcurrentDictionary<string, object> value)
        {
            lock (SnapshotSyncRoot)
            {
                snapshot = value;
            }
        }

        public static void ClearSnapshot()
        {
            lock (SnapshotSyncRoot)
            {
                snapshot = null;
            }
        }
    }
}
"@
}

if (-not (Get-Variable -Scope Script -Name SharedSiteInterfaceCacheKey -ErrorAction SilentlyContinue)) {
    $script:SharedSiteInterfaceCacheKey = 'StateTrace.Repository.SharedSiteInterfaceCache'
}

if (-not (Get-Variable -Scope Script -Name SharedSiteInterfaceCache -ErrorAction SilentlyContinue)) {
    $script:SharedSiteInterfaceCache = $null
}

function Publish-SharedSiteInterfaceCacheStoreState {
    param(
        [Parameter(Mandatory)][string]$Operation,
        [int]$EntryCount = 0,
        [int]$StoreHashCode = 0
    )

    $runspaceId = ''
    try {
        $currentRunspace = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace
        if ($currentRunspace) { $runspaceId = $currentRunspace.InstanceId.ToString() }
    } catch {
        $runspaceId = ''
    }

    $appDomainId = ''
    $appDomainName = ''
    try {
        $domain = [System.AppDomain]::CurrentDomain
        if ($domain) {
            try { $appDomainId = '' + $domain.Id } catch { $appDomainId = '' }
            try { $appDomainName = '' + $domain.FriendlyName } catch { $appDomainName = '' }
        }
    } catch {
        $appDomainId = ''
        $appDomainName = ''
    }

    $entry = [pscustomobject]@{
        Operation      = $Operation
        EntryCount     = $EntryCount
        StoreHashCode  = $StoreHashCode
        RunspaceId     = $runspaceId
        AppDomainId    = $appDomainId
        AppDomainName  = $appDomainName
        TimestampUtc   = (Get-Date).ToUniversalTime()
    }

    try {
        $global:SharedSiteInterfaceCacheEvents += $entry
    } catch {
        $global:SharedSiteInterfaceCacheEvents = @($entry)
    }
}

function Publish-SharedSiteInterfaceCacheClearInvocation {
    param(
        [string]$CallerFunction = $null,
        [string]$CallerScript = $null,
        [int]$CallerLine = 0,
        [string]$InvocationName = $null,
        [int]$CallStackDepth = 0,
        [string]$Reason = $null
    )

    $item = [pscustomobject]@{
        TimestampUtc   = (Get-Date).ToUniversalTime()
        CallerFunction = $CallerFunction
        CallerScript   = $CallerScript
        CallerLine     = $CallerLine
        InvocationName = $InvocationName
        CallStackDepth = $CallStackDepth
        Reason         = $Reason
    }

    try {
        $global:SharedSiteInterfaceCacheClearEvents += $item
    } catch {
        $global:SharedSiteInterfaceCacheClearEvents = @($item)
    }
}

if (-not (Get-Variable -Scope Global -Name SharedSiteInterfaceCacheEvents -ErrorAction SilentlyContinue)) {
    $global:SharedSiteInterfaceCacheEvents = @()
}
if (-not (Get-Variable -Scope Global -Name SharedSiteInterfaceCacheClearEvents -ErrorAction SilentlyContinue)) {
    $global:SharedSiteInterfaceCacheClearEvents = @()
}

function Import-SharedSiteInterfaceCacheSnapshotFromEnv {
    param([System.Collections.Concurrent.ConcurrentDictionary[string, object]]$TargetStore)

    if ([string]::IsNullOrWhiteSpace($env:STATETRACE_SHARED_CACHE_SNAPSHOT)) { return 0 }
    $snapshotPath = $env:STATETRACE_SHARED_CACHE_SNAPSHOT
    try { $snapshotPath = [System.IO.Path]::GetFullPath($snapshotPath) } catch { }
    if (-not (Test-Path -LiteralPath $snapshotPath)) {
        Write-Warning ("Shared cache snapshot '{0}' not found." -f $snapshotPath)
        return 0
    }

    $imported = 0
    try {
        $entries = Import-Clixml -LiteralPath $snapshotPath
        if ($entries -is [System.Collections.IEnumerable]) {
            foreach ($entry in $entries) {
                if (-not $entry -or -not $entry.SiteKey -or -not $entry.HostMap) { continue }
                $siteKey = $entry.SiteKey
                $hostMap = $entry.HostMap
                $TargetStore[$siteKey] = $hostMap
                $imported++
            }
        }
    } catch {
        Write-Warning ("Failed to import shared cache snapshot '{0}': {1}" -f $snapshotPath, $_.Exception.Message)
        return 0
    }

    return $imported
}

function ConvertTo-SharedCacheEntryArray {
    param([object]$Entries)

    if (-not $Entries) { return @() }

    $current = $Entries
    $depth = 0
    while ($current -is [System.Collections.IList] -and $current.Count -eq 1 -and ($current[0] -is [System.Collections.IList])) {
        if ([object]::ReferenceEquals($current, $current[0])) { break }
        $depth++
        if ($depth -ge 32) { break }
        $current = $current[0]
    }

    if ($current -is [System.Collections.IList]) {
        return @($current)
    }

    return ,$current
}

function Write-SharedCacheSnapshotFileFallback {
    param(
        [Parameter(Mandatory)][string]$Path,
        [System.Collections.IEnumerable]$Entries
    )

    $entryArray = ConvertTo-SharedCacheEntryArray -Entries $Entries
    $sanitizedEntries = [System.Collections.Generic.List[psobject]]::new()

    foreach ($entry in $entryArray) {
        if (-not $entry) { continue }

        $siteValue = ''
        if ($entry.PSObject.Properties.Name -contains 'Site') {
            $siteValue = ('' + $entry.Site).Trim()
        } elseif ($entry.PSObject.Properties.Name -contains 'SiteKey') {
            $siteValue = ('' + $entry.SiteKey).Trim()
        }
        if ([string]::IsNullOrWhiteSpace($siteValue)) { continue }

        $entryValue = $null
        if ($entry.PSObject.Properties.Name -contains 'Entry') {
            $entryValue = $entry.Entry
        }
        if (-not $entryValue) { continue }

        $sanitizedEntries.Add([pscustomobject]@{
                Site  = $siteValue
                Entry = $entryValue
            }) | Out-Null
    }

    $directory = $null
    try { $directory = Split-Path -Parent $Path } catch { $directory = $null }
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        try { $directory = [System.IO.Path]::GetFullPath($directory) } catch { }
    }
    $targetPath = $Path
    try { $targetPath = [System.IO.Path]::GetFullPath($Path) } catch { $targetPath = $Path }
    try {
        if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        $exportEntries = if ($sanitizedEntries.Count -gt 0) { $sanitizedEntries.ToArray() } else { @() }
        # Use the cache module's Clixml export when available to keep depth/shape aligned.
        $cacheExport = Get-Command -Name 'DeviceRepository.Cache\Export-SharedCacheSnapshot' -ErrorAction SilentlyContinue
        if (-not $cacheExport) {
            $cacheExport = Get-Command -Name 'Export-SharedCacheSnapshot' -Module 'DeviceRepository.Cache' -ErrorAction SilentlyContinue
        }
        if ($cacheExport) {
            try {
                $sites = @()
                foreach ($entry in $exportEntries) {
                    if ($entry.Site) { $sites += ('' + $entry.Site).Trim() }
                }
                $args = @{ OutputPath = $targetPath }
                if ($sites.Count -gt 0) { $args['SiteFilter'] = $sites }
                & $cacheExport @args | Out-Null
            } catch {
                Export-Clixml -InputObject $exportEntries -Path $targetPath -Depth 20
            }
        } else {
            Export-Clixml -InputObject $exportEntries -Path $targetPath -Depth 20
        }
    } catch {
        Write-Warning ("Failed to write shared cache snapshot to '{0}': {1}" -f $targetPath, $_.Exception.Message)
    }
}

function Import-SharedSiteInterfaceCacheSnapshot {
    param(
        [Parameter(Mandatory)][System.Collections.Concurrent.ConcurrentDictionary[string, object]]$Store,
        [switch]$Force
    )

    $storeKey = $script:SharedSiteInterfaceCacheKey

    try {
        if (-not $Force.IsPresent) {
            $getDataResult = $null
            try { $getDataResult = [System.AppDomain]::CurrentDomain.GetData($storeKey) } catch { $getDataResult = $null }
            if ($getDataResult -is [System.Collections.Concurrent.ConcurrentDictionary[string, object]]) {
                $adStore = $getDataResult
                if ($adStore.Count -gt 0) {
                    foreach ($key in $adStore.Keys) {
                        $Store[$key] = $adStore[$key]
                    }
                    $hashCode = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Store)
                    Publish-SharedSiteInterfaceCacheStoreState -Operation 'AppDomainSeeded' -EntryCount ([int]$Store.Count) -StoreHashCode $hashCode
                    return $Store.Count
                }
            }
        }
    } catch {
        Write-Warning ("Shared cache store reuse from AppDomain failed: {0}" -f $_.Exception.Message)
    }

    $imported = Import-SharedSiteInterfaceCacheSnapshotFromEnv -TargetStore $Store
    if ($imported -gt 0) {
        try { [System.AppDomain]::CurrentDomain.SetData($storeKey, $Store) } catch { }
        $hashCode = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Store)
        Publish-SharedSiteInterfaceCacheStoreState -Operation 'SnapshotImported' -EntryCount ([int]$Store.Count) -StoreHashCode $hashCode
        return $Store.Count
    }

    return 0
}

function Ensure-SharedSiteInterfaceCacheSnapshotImported {
    param(
        [Parameter(Mandatory)][System.Collections.Concurrent.ConcurrentDictionary[string, object]]$Store,
        [switch]$Force
    )

    Write-Verbose "Ensure-SharedSiteInterfaceCacheSnapshotImported is deprecated; use Import-SharedSiteInterfaceCacheSnapshot instead."
    return (Import-SharedSiteInterfaceCacheSnapshot -Store $Store -Force:$Force.IsPresent)
}

function Initialize-SharedSiteInterfaceCacheStore {
    $storeKey = $script:SharedSiteInterfaceCacheKey
    $store = $null

    if (Get-Variable -Scope Script -Name SharedSiteInterfaceCache -ErrorAction SilentlyContinue) {
        $store = $script:SharedSiteInterfaceCache
    }

    try {
        $existing = $null
        try { $existing = [System.AppDomain]::CurrentDomain.GetData($storeKey) } catch { $existing = $null }
        if ($existing -is [System.Collections.Concurrent.ConcurrentDictionary[string, object]]) {
            $store = $existing
        } else {
            $holderStore = $null
            try { $holderStore = [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::GetStore() } catch { $holderStore = $null }
            if ($holderStore -is [System.Collections.Concurrent.ConcurrentDictionary[string, object]]) {
                $store = $holderStore
            }
        }
    } catch { }

    if (-not ($store -is [System.Collections.Concurrent.ConcurrentDictionary[string, object]])) {
        $store = New-Object 'System.Collections.Concurrent.ConcurrentDictionary[string, object]' ([System.StringComparer]::OrdinalIgnoreCase)
    }

    try { [System.AppDomain]::CurrentDomain.SetData($storeKey, $store) } catch { }
    try { [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::SetStore($store) } catch { }

    $count = Import-SharedSiteInterfaceCacheSnapshot -Store $store
    $storeHashCode = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($store)
    if ($count -gt 0) {
        Publish-SharedSiteInterfaceCacheStoreState -Operation 'InitializedWithSnapshot' -EntryCount ([int]$store.Count) -StoreHashCode $storeHashCode
    } else {
        Publish-SharedSiteInterfaceCacheStoreState -Operation 'InitializedEmpty' -EntryCount ([int]$store.Count) -StoreHashCode $storeHashCode
    }

    return $store
}

function Get-SharedSiteInterfaceCacheStore {
    $storeKey = $script:SharedSiteInterfaceCacheKey
    if (Get-Variable -Scope Script -Name SharedSiteInterfaceCache -ErrorAction SilentlyContinue) {
        $store = $script:SharedSiteInterfaceCache
    } else {
        $store = $null
    }

    if ($store -and ($store -is [System.Collections.Concurrent.ConcurrentDictionary[string, object]])) {
        $domainStore = $null
        try { $domainStore = [System.AppDomain]::CurrentDomain.GetData($storeKey) } catch { $domainStore = $null }
        if ($domainStore -is [System.Collections.Concurrent.ConcurrentDictionary[string, object]] -and -not [object]::ReferenceEquals($domainStore, $store)) {
            $scriptCount = 0
            $domainCount = 0
            try { $scriptCount = [int]$store.Count } catch { $scriptCount = 0 }
            try { $domainCount = [int]$domainStore.Count } catch { $domainCount = 0 }
            if ($scriptCount -gt $domainCount) {
                try { [System.AppDomain]::CurrentDomain.SetData($storeKey, $store) } catch { }
            } else {
                $store = $domainStore
                $script:SharedSiteInterfaceCache = $store
            }
        } elseif (-not ($domainStore -is [System.Collections.Concurrent.ConcurrentDictionary[string, object]])) {
            try { [System.AppDomain]::CurrentDomain.SetData($storeKey, $store) } catch { }
        }
        try { [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::SetStore($store) } catch { }
        return $store
    }

    $store = Initialize-SharedSiteInterfaceCacheStore
    $script:SharedSiteInterfaceCache = $store

    return $store
}

function Resolve-SharedSiteInterfaceCacheHostMap {
    param([object]$Entry)

    if (-not $Entry) { return $null }

    if ($Entry -is [System.Collections.IDictionary]) {
        try {
            if ($Entry.Contains('HostMap')) {
                return $Entry['HostMap']
            }
            if ($Entry.ContainsKey -and $Entry.ContainsKey('HostMap')) {
                return $Entry['HostMap']
            }
        } catch { }
        return $Entry
    }

    try {
        if ($Entry.PSObject.Properties.Name -contains 'HostMap') {
            return $Entry.HostMap
        }
    } catch { }

    return $null
}

function Get-SharedSiteInterfaceCacheEntry {
    param([Parameter(Mandatory)][string]$SiteKey)

    $store = Get-SharedSiteInterfaceCacheStore

    $storeHashCode = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($store)
    $entryCount = [int]$store.Count

    try {
        if ($store.ContainsKey($SiteKey)) {
            $entry = $store[$SiteKey]
            if ($null -eq $entry) {
                Publish-SharedSiteInterfaceCacheEvent -SiteKey $SiteKey -Operation 'GetMiss' -EntryCount $entryCount -StoreHashCode $storeHashCode
                return $null
            }
            $hostMap = Resolve-SharedSiteInterfaceCacheHostMap -Entry $entry
            if (-not ($hostMap -is [System.Collections.IDictionary])) {
                Publish-SharedSiteInterfaceCacheEvent -SiteKey $SiteKey -Operation 'GetMiss' -EntryCount $entryCount -StoreHashCode $storeHashCode
                return $null
            }
            # Clone the host map so downstream consumers do not mutate the shared store.
            $clone = New-Object 'System.Collections.Generic.Dictionary[string, object]'
            foreach ($key in @($hostMap.Keys)) {
                $clone[$key] = $hostMap[$key]
            }
            $stats = Get-SharedSiteInterfaceCacheEntryStatistics -Entry $clone
            Publish-SharedSiteInterfaceCacheEvent -SiteKey $SiteKey -Operation 'GetHit' -EntryCount $entryCount -HostCount $stats.HostCount -TotalRows $stats.TotalRows -StoreHashCode $storeHashCode
            return $clone
        }
    } catch {
        Write-Warning ("Failed to read shared cache entry for site {0}: {1}" -f $SiteKey, $_.Exception.Message)
    }

    Publish-SharedSiteInterfaceCacheEvent -SiteKey $SiteKey -Operation 'GetMiss' -EntryCount $entryCount -StoreHashCode $storeHashCode
    return $null
}

function Set-SharedSiteInterfaceCacheEntry {
    param(
        [Parameter(Mandatory)][string]$SiteKey,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Entry
    )

    $store = Get-SharedSiteInterfaceCacheStore
    $storeHashCode = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($store)

    # Normalize keys to preserve ordering and avoid null references
    $normalized = New-Object 'System.Collections.Generic.Dictionary[string, object]'
    $keyList = @()
    if ($Entry -is [System.Collections.IDictionary]) {
        $keyList = $Entry.Keys
    } else {
        try { $keyList = $Entry.PSObject.Properties.Name } catch { $keyList = @() }
    }

    foreach ($key in @($keyList | Sort-Object)) {
        $value = $null
        if ($Entry -is [System.Collections.IDictionary]) {
            $value = $Entry[$key]
        } else {
            try { $value = $Entry.PSObject.Properties[$key].Value } catch { $value = $null }
        }
        if ($null -eq $value) { continue }

        # Preserve lists as arrays so row counts are retained.
        if ($value -is [System.Collections.IDictionary]) {
            $normalized[$key] = $value
        } elseif ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
            $normalized[$key] = @($value)
        } else {
            $normalized[$key] = $value
        }
    }

    $store[$SiteKey] = $normalized
    $entryCount = [int]$store.Count
    $stats = Get-SharedSiteInterfaceCacheEntryStatistics -Entry $normalized
    Publish-SharedSiteInterfaceCacheEvent -SiteKey $SiteKey -Operation 'Set' -EntryCount $entryCount -HostCount $stats.HostCount -TotalRows $stats.TotalRows -StoreHashCode $storeHashCode

    $snapshotStore = $null
    try { $snapshotStore = [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::GetSnapshot() } catch { $snapshotStore = $null }
    if ($snapshotStore -is [System.Collections.IDictionary]) {
        $hasSnapshotEntry = $false
        try {
            if ($snapshotStore -is [System.Collections.Concurrent.ConcurrentDictionary[string, object]]) {
                $hasSnapshotEntry = $snapshotStore.ContainsKey($SiteKey)
            } elseif ($snapshotStore.PSObject.Methods['ContainsKey']) {
                $hasSnapshotEntry = $snapshotStore.ContainsKey($SiteKey)
            } elseif ($snapshotStore.PSObject.Methods['Contains']) {
                $hasSnapshotEntry = $snapshotStore.Contains($SiteKey)
            }
        } catch {
            $hasSnapshotEntry = $false
        }

        if (-not $hasSnapshotEntry) {
            $snapshotStore[$SiteKey] = New-Object 'StateTrace.Repository.SharedSiteInterfaceCacheEntry'
        }
        $snapshotStore[$SiteKey].SiteKey = $SiteKey
        $snapshotStore[$SiteKey].HostMap = $normalized
        try { [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::SetSnapshot($snapshotStore) } catch { }
    }
}

function Export-SharedCacheSnapshot {
    param(
        [Parameter(Mandatory)][string]$OutputPath,
        [string[]]$SiteFilter
    )

    $store = Get-SharedSiteInterfaceCacheStore

    $snapshot = [System.Collections.Generic.List[object]]::new()

    foreach ($siteKey in $store.Keys) {
        if ($SiteFilter -and $SiteFilter.Count -gt 0 -and ($SiteFilter -notcontains $siteKey)) {
            continue
        }

        $hostMapSource = $null
        try { $hostMapSource = $store[$siteKey] } catch { $hostMapSource = $null }
        if ($hostMapSource -and -not ($hostMapSource -is [System.Collections.IDictionary]) -and ($hostMapSource.PSObject.Properties.Name -contains 'HostMap')) {
            try { $hostMapSource = $hostMapSource.HostMap } catch { }
        }
        if (-not $hostMapSource) { continue }

        $hostMap = $hostMapSource
        if (-not ($hostMap -is [System.Collections.Generic.IDictionary[string, object]])) {
            $converted = New-Object 'System.Collections.Generic.Dictionary[string, object]' ([System.StringComparer]::OrdinalIgnoreCase)
            if ($hostMap -is [System.Collections.IDictionary]) {
                foreach ($key in @($hostMap.Keys)) {
                    $name = if ($key) { ('' + $key).Trim() } else { '' }
                    if ([string]::IsNullOrWhiteSpace($name)) { continue }
                    $converted[$name] = $hostMap[$key]
                }
            }
            $hostMap = $converted
        }

        $entry = New-Object 'StateTrace.Repository.SharedSiteInterfaceCacheEntry'
        $entry.SiteKey = $siteKey
        $entry.HostMap = $hostMap
        $snapshot.Add($entry) | Out-Null
    }

    try {
        $snapshot | Export-Clixml -LiteralPath $OutputPath -Depth 5
        Write-Host ("Shared cache snapshot exported to {0}" -f $OutputPath) -ForegroundColor Green
    } catch {
        Write-Warning ("Failed to export shared cache snapshot '{0}': {1}" -f $OutputPath, $_.Exception.Message)
    }
}

function Get-SharedSiteInterfaceCacheSnapshotEntries {
    $entries = [System.Collections.Generic.List[object]]::new()

    $store = Get-SharedSiteInterfaceCacheStore
    if ($store -is [System.Collections.IDictionary]) {
        foreach ($siteKey in @($store.Keys | Sort-Object)) {
            $entry = $store[$siteKey]
            if (-not $entry) { continue }
            $hostMap = Resolve-SharedSiteInterfaceCacheHostMap -Entry $entry
            if (-not ($hostMap -is [System.Collections.IDictionary])) { continue }
            $stats = Get-SharedSiteInterfaceCacheEntryStatistics -Entry $hostMap
            $entries.Add([pscustomobject]@{
                    SiteKey   = $siteKey
                    HostCount = $stats.HostCount
                    TotalRows = $stats.TotalRows
                    HostMap   = $hostMap
                }) | Out-Null
        }
    }

    if ($entries.Count -eq 0) {
        $snapshotStore = $null
        try { $snapshotStore = [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::GetSnapshot() } catch { $snapshotStore = $null }
        if ($snapshotStore -is [System.Collections.IDictionary]) {
            foreach ($siteKey in @($snapshotStore.Keys | Sort-Object)) {
                if ([string]::IsNullOrWhiteSpace($siteKey)) { continue }
                $entry = $snapshotStore[$siteKey]
                if (-not $entry) { continue }
                $hostMap = Resolve-SharedSiteInterfaceCacheHostMap -Entry $entry
                if (-not ($hostMap -is [System.Collections.IDictionary])) { continue }
                $stats = Get-SharedSiteInterfaceCacheEntryStatistics -Entry $hostMap
                $entries.Add([pscustomobject]@{
                        SiteKey   = $siteKey
                        HostCount = $stats.HostCount
                        TotalRows = $stats.TotalRows
                        HostMap   = $hostMap
                    }) | Out-Null
            }
        }
    }

    return $entries.ToArray()
}

function Clear-SharedSiteInterfaceCache {
    param([string]$Reason)

    $invocation = $MyInvocation
    $callStackDepth = 0
    $callerFunction = $null
    $callerScript = $null
    $callerLine = 0
    $invocationName = $null

    if ($invocation -and $invocation.PSCommandPath) {
        try {
            $stack = Get-PSCallStack
            if ($stack) { $callStackDepth = $stack.Count }
        } catch {
            $callStackDepth = 0
        }

        try { $callerFunction = $invocation.InvocationName } catch { $callerFunction = $null }
        try { $callerScript = $invocation.PSCommandPath } catch { $callerScript = $null }
        try { $callerLine = [int]$invocation.ScriptLineNumber } catch { $callerLine = 0 }
        try { $invocationName = $invocation.MyCommand.Name } catch { $invocationName = $null }
    }

    Publish-SharedSiteInterfaceCacheClearInvocation `
        -CallerFunction $callerFunction `
        -CallerScript $callerScript `
        -CallerLine $callerLine `
        -InvocationName $invocationName `
        -CallStackDepth $callStackDepth `
        -Reason $Reason

    $store = Get-SharedSiteInterfaceCacheStore
    $storeHashCode = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($store)

    $preClearCount = [int]$store.Count
    $preClearHash = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($store)

    if ($store -is [System.Collections.Concurrent.ConcurrentDictionary[string, object]]) {
        try { [System.AppDomain]::CurrentDomain.SetData($script:SharedSiteInterfaceCacheKey, $null) } catch { }
        try { $store.Clear() } catch { }
        try { [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::ClearStore() } catch { }
    }

    try { [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::ClearSnapshot() } catch { }

    $postClearHash = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($store)
    $postClearCount = [int]$store.Count
    Publish-SharedSiteInterfaceCacheStoreState -Operation 'ClearRequested' -EntryCount $preClearCount -StoreHashCode $preClearHash
    Publish-SharedSiteInterfaceCacheStoreState -Operation 'Cleared' -EntryCount $postClearCount -StoreHashCode $postClearHash
}

function Get-SharedSiteInterfaceCacheEntryStatistics {
    param([System.Collections.IDictionary]$Entry)

    $hostCount = 0
    $totalRows = 0

    if ($Entry) {
        $hostMap = $null
        try {
            if ($Entry.Contains('HostMap')) {
                $hostMap = $Entry['HostMap']
            } elseif ($Entry.ContainsKey -and $Entry.ContainsKey('HostMap')) {
                $hostMap = $Entry['HostMap']
            }
        } catch { $hostMap = $null }

        if ($hostMap -is [System.Collections.IDictionary]) {
            try { $hostCount = [int]$hostMap.Count } catch { $hostCount = 0 }
            foreach ($hostEntry in @($hostMap.Keys)) {
                $value = $hostMap[$hostEntry]
                if ($value -is [System.Collections.ICollection]) {
                    $totalRows += $value.Count
                } else {
                    $totalRows++
                }
            }
        } elseif ($Entry.Count -gt 0) {
            $hostCount = $Entry.Count
            foreach ($key in @($Entry.Keys)) {
                $value = $Entry[$key]
                if ($value -is [System.Collections.ICollection]) {
                    $totalRows += $value.Count
                } else {
                    $totalRows++
                }
            }
        }
    }

    [pscustomobject]@{
        HostCount = $hostCount
        TotalRows = $totalRows
    }
}

function Publish-SharedSiteInterfaceCacheEvent {
    param(
        [string]$SiteKey,
        [string]$Operation,
        [int]$EntryCount,
        [int]$HostCount = 0,
        [int]$TotalRows = 0,
        [int]$StoreHashCode = 0
    )

    $entry = [pscustomobject]@{
        SiteKey      = $SiteKey
        Operation    = $Operation
        EntryCount   = $EntryCount
        HostCount    = $HostCount
        TotalRows    = $TotalRows
        StoreHashCode = $StoreHashCode
        TimestampUtc = (Get-Date).ToUniversalTime()
    }

    try {
        $global:SharedSiteInterfaceCacheEvents += $entry
    } catch {
        $global:SharedSiteInterfaceCacheEvents = @($entry)
    }
}

function Get-SharedSiteInterfaceCache {
    param([Parameter(Mandatory)][string]$Site)

    $siteKey = ('' + $Site).Trim()
    if ([string]::IsNullOrWhiteSpace($siteKey)) { return @() }

    $siteCache = Get-SharedSiteInterfaceCacheEntry -SiteKey $siteKey
    if (-not $siteCache) { return @() }

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($hostKey in @($siteCache.Keys | Sort-Object)) {
        $hostRows = $siteCache[$hostKey]
        if (-not $hostRows) { continue }
        if ($hostRows -is [System.Collections.IDictionary]) {
            foreach ($row in $hostRows.Values) {
                $rows.Add($row) | Out-Null
            }
        } elseif ($hostRows -is [System.Collections.IEnumerable] -and -not ($hostRows -is [string])) {
            foreach ($row in $hostRows) {
                $rows.Add($row) | Out-Null
            }
        } else {
            $rows.Add($hostRows) | Out-Null
        }
    }

    return $rows.ToArray()
}

# Exports for consumers
Export-ModuleMember -Function `
    Get-SharedSiteInterfaceCacheStore, `
    Get-SharedSiteInterfaceCacheEntry, `
    Get-SharedSiteInterfaceCacheSnapshotEntries, `
    Export-SharedCacheSnapshot, `
    Get-SharedSiteInterfaceCache, `
    Set-SharedSiteInterfaceCacheEntry, `
    Clear-SharedSiteInterfaceCache, `
    Publish-SharedSiteInterfaceCacheStoreState, `
    Publish-SharedSiteInterfaceCacheEvent, `
    Publish-SharedSiteInterfaceCacheClearInvocation, `
    Get-SharedSiteInterfaceCacheEntryStatistics, `
    Initialize-SharedSiteInterfaceCacheStore, `
    Import-SharedSiteInterfaceCacheSnapshotFromEnv, `
    Import-SharedSiteInterfaceCacheSnapshot, `
    ConvertTo-SharedCacheEntryArray, `
    Write-SharedCacheSnapshotFileFallback
