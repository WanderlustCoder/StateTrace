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
if (-not (Get-Variable -Scope Script -Name SharedSiteInterfaceCacheEventLock -ErrorAction SilentlyContinue)) {
    $script:SharedSiteInterfaceCacheEventLock = New-Object object
}

if (-not (Get-Variable -Scope Script -Name SharedSiteInterfaceCacheEventsMaxEntries -ErrorAction SilentlyContinue)) {
    $script:SharedSiteInterfaceCacheEventsMaxEntries = 2000
}
if (-not (Get-Variable -Scope Script -Name SharedSiteInterfaceCacheClearEventsMaxEntries -ErrorAction SilentlyContinue)) {
    $script:SharedSiteInterfaceCacheClearEventsMaxEntries = 2000
}

function Invoke-SharedSiteInterfaceCacheEventLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ScriptBlock]$ScriptBlock
    )

    $lockTaken = $false
    try {
        [System.Threading.Monitor]::Enter($script:SharedSiteInterfaceCacheEventLock, [ref]$lockTaken)
        & $ScriptBlock
    } finally {
        if ($lockTaken) {
            [System.Threading.Monitor]::Exit($script:SharedSiteInterfaceCacheEventLock)
        }
    }
}

function script:Limit-SharedCacheEventList {
    [CmdletBinding()]
    param(
        [Parameter()][object]$List,
        [Parameter(Mandatory)][int]$MaxEntries
    )

    if (-not $List) { return @() }
    if ($MaxEntries -le 0) { return @($List) }

    $current = @($List)
    if ($current.Count -le $MaxEntries) { return $current }

    return @($current | Select-Object -Last $MaxEntries)
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

    Invoke-SharedSiteInterfaceCacheEventLock {
        try {
            $global:SharedSiteInterfaceCacheEvents += $entry
        } catch {
            $global:SharedSiteInterfaceCacheEvents = @($entry)
        }
        $global:SharedSiteInterfaceCacheEvents = script:Limit-SharedCacheEventList -List $global:SharedSiteInterfaceCacheEvents -MaxEntries $script:SharedSiteInterfaceCacheEventsMaxEntries
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

    Invoke-SharedSiteInterfaceCacheEventLock {
        try {
            $global:SharedSiteInterfaceCacheClearEvents += $item
        } catch {
            $global:SharedSiteInterfaceCacheClearEvents = @($item)
        }
        $global:SharedSiteInterfaceCacheClearEvents = script:Limit-SharedCacheEventList -List $global:SharedSiteInterfaceCacheClearEvents -MaxEntries $script:SharedSiteInterfaceCacheClearEventsMaxEntries
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
        try {
            $sites = @()
            foreach ($entry in $exportEntries) {
                if ($entry.Site) { $sites += ('' + $entry.Site).Trim() }
            }
            $args = @{ OutputPath = $targetPath }
            if ($sites.Count -gt 0) { $args['SiteFilter'] = $sites }
            Export-SharedCacheSnapshot @args | Out-Null
        } catch {
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
        try { [System.AppDomain]::CurrentDomain.SetData($storeKey, $Store) } catch {
            Write-Warning ("Failed to publish shared cache store to AppDomain ({0}): {1}" -f $storeKey, $_.Exception.Message)
        }
        $hashCode = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Store)
        Publish-SharedSiteInterfaceCacheStoreState -Operation 'SnapshotImported' -EntryCount ([int]$Store.Count) -StoreHashCode $hashCode
        return $Store.Count
    }

    return 0
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

    try { [System.AppDomain]::CurrentDomain.SetData($storeKey, $store) } catch {
        Write-Warning ("Failed to publish shared cache store to AppDomain ({0}): {1}" -f $storeKey, $_.Exception.Message)
    }
    try { [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::SetStore($store) } catch {
        Write-Warning ("Failed to publish shared cache store to holder: {0}" -f $_.Exception.Message)
    }

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
                try { [System.AppDomain]::CurrentDomain.SetData($storeKey, $store) } catch {
                    Write-Warning ("Failed to publish shared cache store to AppDomain ({0}): {1}" -f $storeKey, $_.Exception.Message)
                }
            } else {
                $store = $domainStore
                $script:SharedSiteInterfaceCache = $store
            }
        } elseif (-not ($domainStore -is [System.Collections.Concurrent.ConcurrentDictionary[string, object]])) {
            try { [System.AppDomain]::CurrentDomain.SetData($storeKey, $store) } catch {
                Write-Warning ("Failed to publish shared cache store to AppDomain ({0}): {1}" -f $storeKey, $_.Exception.Message)
            }
        }
        try { [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::SetStore($store) } catch {
            Write-Warning ("Failed to publish shared cache store to holder: {0}" -f $_.Exception.Message)
        }
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
    $sharedCacheDisabled = $false
    try {
        $sharedCacheDisabled = [string]::Equals($env:STATETRACE_DISABLE_SHARED_CACHE, '1', [System.StringComparison]::OrdinalIgnoreCase)
    } catch {
        $sharedCacheDisabled = $false
    }
    if ($sharedCacheDisabled) {
        Publish-SharedSiteInterfaceCacheEvent -SiteKey $SiteKey -Operation 'GetMiss' -EntryCount $entryCount -StoreHashCode $storeHashCode
        return $null
    }

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

    $sharedCacheDisabled = $false
    try {
        $sharedCacheDisabled = [string]::Equals($env:STATETRACE_DISABLE_SHARED_CACHE, '1', [System.StringComparison]::OrdinalIgnoreCase)
    } catch {
        $sharedCacheDisabled = $false
    }
    if ($sharedCacheDisabled) { return }

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

    $mergedHostMap = $normalized
    $existingEntry = $null
    try { $existingEntry = $store[$SiteKey] } catch { $existingEntry = $null }
    $existingHostMap = $null
    if ($existingEntry) {
        try { $existingHostMap = Resolve-SharedSiteInterfaceCacheHostMap -Entry $existingEntry } catch { $existingHostMap = $null }
    }
    if ($existingHostMap -is [System.Collections.IDictionary]) {
        $mergedHostMap = New-Object 'System.Collections.Generic.Dictionary[string, object]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($existingKey in @($existingHostMap.Keys)) {
            $normalizedExistingKey = if ($existingKey) { ('' + $existingKey).Trim() } else { '' }
            if ([string]::IsNullOrWhiteSpace($normalizedExistingKey)) { continue }
            $existingValue = $existingHostMap[$existingKey]
            if ($null -eq $existingValue) { continue }
            $mergedHostMap[$normalizedExistingKey] = $existingValue
        }
        foreach ($incomingKey in @($normalized.Keys)) {
            $normalizedIncomingKey = if ($incomingKey) { ('' + $incomingKey).Trim() } else { '' }
            if ([string]::IsNullOrWhiteSpace($normalizedIncomingKey)) { continue }
            $incomingValue = $normalized[$incomingKey]
            if ($null -eq $incomingValue) {
                $null = $mergedHostMap.Remove($normalizedIncomingKey)
                continue
            }
            if ($incomingValue -is [System.Collections.ICollection] -and $incomingValue.Count -eq 0) {
                $null = $mergedHostMap.Remove($normalizedIncomingKey)
                continue
            }
            $mergedHostMap[$normalizedIncomingKey] = $incomingValue
        }
    }
    $store[$SiteKey] = $mergedHostMap
    $entryCount = [int]$store.Count
    $stats = Get-SharedSiteInterfaceCacheEntryStatistics -Entry $mergedHostMap
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
        $snapshotStore[$SiteKey].HostMap = $mergedHostMap
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
    $seenSites = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    $appendEntry = {
        param($siteKey, $entryValue)

        if ([string]::IsNullOrWhiteSpace($siteKey)) { return }
        if ($SiteFilter -and $SiteFilter.Count -gt 0 -and ($SiteFilter -notcontains $siteKey)) {
            return
        }

        $hostMapSource = Resolve-SharedSiteInterfaceCacheHostMap -Entry $entryValue
        if (-not ($hostMapSource -is [System.Collections.IDictionary])) { return }

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
        $null = $seenSites.Add($siteKey)
    }

    if ($store -is [System.Collections.IDictionary]) {
        foreach ($siteKey in @($store.Keys)) {
            $entryValue = $store[$siteKey]
            if (-not $entryValue) { continue }
            & $appendEntry $siteKey $entryValue
        }
    }

    $snapshotStore = $null
    try { $snapshotStore = [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::GetSnapshot() } catch { $snapshotStore = $null }
    if ($snapshotStore -is [System.Collections.IDictionary]) {
        foreach ($siteKey in @($snapshotStore.Keys)) {
            if ($seenSites.Contains($siteKey)) { continue }
            $entryValue = $snapshotStore[$siteKey]
            if (-not $entryValue) { continue }
            & $appendEntry $siteKey $entryValue
        }
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
    $seenSites = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

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
            if (-not [string]::IsNullOrWhiteSpace($siteKey)) {
                $null = $seenSites.Add($siteKey)
            }
        }
    }

    $snapshotStore = $null
    try { $snapshotStore = [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::GetSnapshot() } catch { $snapshotStore = $null }
    if ($snapshotStore -is [System.Collections.IDictionary]) {
        foreach ($siteKey in @($snapshotStore.Keys | Sort-Object)) {
            if ([string]::IsNullOrWhiteSpace($siteKey)) { continue }
            if ($seenSites.Contains($siteKey)) { continue }
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
            $null = $seenSites.Add($siteKey)
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
        try { [System.AppDomain]::CurrentDomain.SetData($script:SharedSiteInterfaceCacheKey, $null) } catch {
            Write-Warning ("Failed to clear shared cache AppDomain store ({0}): {1}" -f $script:SharedSiteInterfaceCacheKey, $_.Exception.Message)
        }
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

    Invoke-SharedSiteInterfaceCacheEventLock {
        try {
            $global:SharedSiteInterfaceCacheEvents += $entry
        } catch {
            $global:SharedSiteInterfaceCacheEvents = @($entry)
        }
        $global:SharedSiteInterfaceCacheEvents = script:Limit-SharedCacheEventList -List $global:SharedSiteInterfaceCacheEvents -MaxEntries $script:SharedSiteInterfaceCacheEventsMaxEntries
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

# ============================================================================
# Cross-Process Memory-Mapped Cache Support
# ============================================================================

$script:MemoryMappedCachePath = $null
$script:MemoryMappedCacheEnabled = $false
$script:MemoryMappedCacheSyncIntervalMs = 5000

function Get-MemoryMappedCachePath {
    <#
    .SYNOPSIS
    Returns the path to the memory-mapped cache file.
    #>
    if ($script:MemoryMappedCachePath) {
        return $script:MemoryMappedCachePath
    }

    $dataDir = Join-Path $PSScriptRoot '..\Data'
    if (-not (Test-Path $dataDir)) {
        New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    }
    $script:MemoryMappedCachePath = Join-Path $dataDir 'SharedCache.mmf'
    return $script:MemoryMappedCachePath
}

function Initialize-MemoryMappedCache {
    <#
    .SYNOPSIS
    Initializes memory-mapped file support for cross-process cache sharing.
    .DESCRIPTION
    Creates or opens a shared memory region that can be accessed by multiple
    PowerShell processes for cache synchronization.
    #>
    [CmdletBinding()]
    param(
        [switch]$Force
    )

    if ($script:MemoryMappedCacheEnabled -and -not $Force) {
        return $true
    }

    $mmfPath = Get-MemoryMappedCachePath

    try {
        # Try to load existing cache from file
        if (Test-Path -LiteralPath $mmfPath) {
            $imported = Import-MemoryMappedCacheFromFile -Path $mmfPath
            if ($imported -gt 0) {
                Write-Verbose ("Loaded {0} sites from memory-mapped cache file." -f $imported)
            }
        }

        $script:MemoryMappedCacheEnabled = $true
        return $true
    } catch {
        Write-Warning ("Failed to initialize memory-mapped cache: {0}" -f $_.Exception.Message)
        return $false
    }
}

function Import-MemoryMappedCacheFromFile {
    <#
    .SYNOPSIS
    Imports cache entries from the memory-mapped cache file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return 0
    }

    $imported = 0
    $store = Get-SharedSiteInterfaceCacheStore

    try {
        $lockPath = "$Path.lock"
        $lockTaken = $false
        $lockStream = $null

        # Try to acquire file lock with timeout
        $retries = 0
        while (-not $lockTaken -and $retries -lt 10) {
            try {
                $lockStream = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
                $lockTaken = $true
            } catch {
                $retries++
                Start-Sleep -Milliseconds 100
            }
        }

        if (-not $lockTaken) {
            Write-Warning "Could not acquire lock for memory-mapped cache file."
            return 0
        }

        try {
            $cacheData = Get-Content -Path $Path -Raw -ErrorAction Stop | ConvertFrom-Json
            if ($cacheData -and $cacheData.Sites) {
                foreach ($site in $cacheData.Sites) {
                    if (-not $site.SiteKey -or -not $site.HostMap) { continue }

                    $hostMap = @{}
                    foreach ($prop in $site.HostMap.PSObject.Properties) {
                        $hostMap[$prop.Name] = $prop.Value
                    }

                    if ($hostMap.Count -gt 0) {
                        $store[$site.SiteKey] = $hostMap
                        $imported++
                    }
                }
            }
        } finally {
            if ($lockStream) {
                $lockStream.Close()
                $lockStream.Dispose()
            }
        }
    } catch {
        Write-Warning ("Failed to import memory-mapped cache: {0}" -f $_.Exception.Message)
    }

    return $imported
}

function Export-MemoryMappedCacheToFile {
    <#
    .SYNOPSIS
    Exports current cache to the memory-mapped cache file for cross-process sharing.
    #>
    [CmdletBinding()]
    param(
        [string]$Path
    )

    if (-not $Path) {
        $Path = Get-MemoryMappedCachePath
    }

    $store = Get-SharedSiteInterfaceCacheStore
    if (-not $store -or $store.Count -eq 0) {
        return $false
    }

    try {
        $lockPath = "$Path.lock"
        $lockTaken = $false
        $lockStream = $null

        # Try to acquire file lock
        $retries = 0
        while (-not $lockTaken -and $retries -lt 10) {
            try {
                $lockStream = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
                $lockTaken = $true
            } catch {
                $retries++
                Start-Sleep -Milliseconds 100
            }
        }

        if (-not $lockTaken) {
            Write-Warning "Could not acquire lock for memory-mapped cache export."
            return $false
        }

        try {
            $sites = @()
            foreach ($siteKey in $store.Keys) {
                $entry = $store[$siteKey]
                $hostMap = Resolve-SharedSiteInterfaceCacheHostMap -Entry $entry
                if ($hostMap) {
                    $sites += @{
                        SiteKey = $siteKey
                        HostMap = $hostMap
                        UpdatedUtc = (Get-Date).ToUniversalTime().ToString('o')
                    }
                }
            }

            $cacheData = @{
                Version = 1
                UpdatedUtc = (Get-Date).ToUniversalTime().ToString('o')
                Sites = $sites
            }

            $json = $cacheData | ConvertTo-Json -Depth 10 -Compress
            [System.IO.File]::WriteAllText($Path, $json, [System.Text.Encoding]::UTF8)
            return $true
        } finally {
            if ($lockStream) {
                $lockStream.Close()
                $lockStream.Dispose()
            }
        }
    } catch {
        Write-Warning ("Failed to export memory-mapped cache: {0}" -f $_.Exception.Message)
        return $false
    }
}

function Sync-MemoryMappedCache {
    <#
    .SYNOPSIS
    Synchronizes the in-memory cache with the memory-mapped file.
    .DESCRIPTION
    Reads updates from other processes and writes local changes to the shared file.
    #>
    [CmdletBinding()]
    param(
        [switch]$Export,
        [switch]$Import
    )

    $mmfPath = Get-MemoryMappedCachePath

    if ($Import -or (-not $Export -and -not $Import)) {
        # Import changes from file
        if (Test-Path -LiteralPath $mmfPath) {
            $imported = Import-MemoryMappedCacheFromFile -Path $mmfPath
            if ($imported -gt 0) {
                Write-Verbose ("Synced {0} sites from shared cache." -f $imported)
            }
        }
    }

    if ($Export -or (-not $Export -and -not $Import)) {
        # Export current cache to file
        $exported = Export-MemoryMappedCacheToFile -Path $mmfPath
        if ($exported) {
            Write-Verbose "Exported cache to shared file."
        }
    }
}

function Get-MemoryMappedCacheStats {
    <#
    .SYNOPSIS
    Returns statistics about the memory-mapped cache.
    #>
    [CmdletBinding()]
    param()

    $mmfPath = Get-MemoryMappedCachePath
    $stats = [PSCustomObject]@{
        Enabled = $script:MemoryMappedCacheEnabled
        FilePath = $mmfPath
        FileExists = (Test-Path -LiteralPath $mmfPath)
        FileSizeBytes = 0
        LastModifiedUtc = $null
    }

    if ($stats.FileExists) {
        try {
            $fileInfo = Get-Item -LiteralPath $mmfPath
            $stats.FileSizeBytes = $fileInfo.Length
            $stats.LastModifiedUtc = $fileInfo.LastWriteTimeUtc
        } catch { }
    }

    return $stats
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
    Write-SharedCacheSnapshotFileFallback, `
    Initialize-MemoryMappedCache, `
    Import-MemoryMappedCacheFromFile, `
    Export-MemoryMappedCacheToFile, `
    Sync-MemoryMappedCache, `
    Get-MemoryMappedCacheStats

# ============================================================================
# Data Lineage Tracking
# ============================================================================

$script:DataLineageStore = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
$script:CurrentParseSessionId = $null

function New-DataLineageContext {
    <#
    .SYNOPSIS
    Creates a new data lineage context for tracking record origins.
    .DESCRIPTION
    Creates a context object that tracks the source file, parse timestamp,
    and session ID for records created during a parsing session.
    .PARAMETER SourceFile
    Path to the source file being parsed.
    .PARAMETER SessionId
    Optional session identifier. If not provided, a new GUID is generated.
    .OUTPUTS
    Returns a DataLineageContext object.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourceFile,
        [string]$SessionId
    )

    if (-not $SessionId) {
        $SessionId = [System.Guid]::NewGuid().ToString('N').Substring(0, 12)
    }

    $context = [PSCustomObject]@{
        PSTypeName = 'StateTrace.DataLineageContext'
        SessionId = $SessionId
        SourceFile = $SourceFile
        SourceFileName = [System.IO.Path]::GetFileName($SourceFile)
        ParseTimestamp = [datetime]::UtcNow
        RecordCount = 0
        Hostname = $env:COMPUTERNAME
        Username = $env:USERNAME
    }

    $script:CurrentParseSessionId = $SessionId

    return $context
}

function Add-DataLineage {
    <#
    .SYNOPSIS
    Adds lineage metadata to a record or collection of records.
    .PARAMETER Record
    The record or records to add lineage to.
    .PARAMETER Context
    The DataLineageContext from New-DataLineageContext.
    .PARAMETER RecordType
    Type of record (e.g., 'Interface', 'Device', 'SpanInfo').
    .OUTPUTS
    Returns the record with lineage properties added.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][object]$Record,
        [Parameter(Mandatory)][object]$Context,
        [string]$RecordType = 'Unknown'
    )

    process {
        if (-not $Record) { return $null }

        # Add lineage properties
        $Record | Add-Member -NotePropertyName '_SourceFile' -NotePropertyValue $Context.SourceFile -Force
        $Record | Add-Member -NotePropertyName '_ParseTimestamp' -NotePropertyValue $Context.ParseTimestamp -Force
        $Record | Add-Member -NotePropertyName '_ParseSessionId' -NotePropertyValue $Context.SessionId -Force
        $Record | Add-Member -NotePropertyName '_RecordType' -NotePropertyValue $RecordType -Force

        # Store in lineage dictionary for later lookup
        $recordKey = "{0}:{1}:{2}" -f $Context.SessionId, $RecordType, $Context.RecordCount
        $script:DataLineageStore[$recordKey] = [PSCustomObject]@{
            SourceFile = $Context.SourceFile
            ParseTimestamp = $Context.ParseTimestamp
            SessionId = $Context.SessionId
            RecordType = $RecordType
            RecordIndex = $Context.RecordCount
        }

        $Context.RecordCount++

        return $Record
    }
}

function Get-DataLineage {
    <#
    .SYNOPSIS
    Retrieves lineage information for a record or session.
    .PARAMETER Record
    A record with lineage metadata.
    .PARAMETER SessionId
    Session ID to look up lineage for.
    .OUTPUTS
    Returns lineage information.
    #>
    [CmdletBinding()]
    param(
        [Parameter()][object]$Record,
        [Parameter()][string]$SessionId
    )

    if ($Record) {
        # Extract lineage from record
        $lineage = [PSCustomObject]@{
            SourceFile = $null
            ParseTimestamp = $null
            ParseSessionId = $null
            RecordType = $null
        }

        if ($Record.PSObject.Properties.Name -contains '_SourceFile') {
            $lineage.SourceFile = $Record._SourceFile
        }
        if ($Record.PSObject.Properties.Name -contains '_ParseTimestamp') {
            $lineage.ParseTimestamp = $Record._ParseTimestamp
        }
        if ($Record.PSObject.Properties.Name -contains '_ParseSessionId') {
            $lineage.ParseSessionId = $Record._ParseSessionId
        }
        if ($Record.PSObject.Properties.Name -contains '_RecordType') {
            $lineage.RecordType = $Record._RecordType
        }

        return $lineage
    }

    if ($SessionId) {
        # Return all lineage entries for a session
        $entries = @()
        $prefix = "${SessionId}:"
        foreach ($key in $script:DataLineageStore.Keys) {
            if ($key.StartsWith($prefix)) {
                $entries += $script:DataLineageStore[$key]
            }
        }
        return $entries
    }

    # Return summary of all sessions
    $sessions = @{}
    foreach ($key in $script:DataLineageStore.Keys) {
        $parts = $key.Split(':')
        if ($parts.Count -ge 1) {
            $sid = $parts[0]
            if (-not $sessions.ContainsKey($sid)) {
                $sessions[$sid] = 0
            }
            $sessions[$sid]++
        }
    }

    return $sessions.GetEnumerator() | ForEach-Object {
        [PSCustomObject]@{
            SessionId = $_.Key
            RecordCount = $_.Value
        }
    }
}

# =============================================================================
# Cache TTL (Time-To-Live) Management - ST-AI-004
# =============================================================================

# Default TTL in minutes for cache entries
if (-not (Get-Variable -Scope Script -Name CacheEntryTTLMinutes -ErrorAction SilentlyContinue)) {
    $script:CacheEntryTTLMinutes = 30
}

# Store for tracking entry timestamps (site -> timestamp)
if (-not (Get-Variable -Scope Script -Name CacheEntryTimestamps -ErrorAction SilentlyContinue)) {
    $script:CacheEntryTimestamps = [System.Collections.Concurrent.ConcurrentDictionary[string, datetime]]::new([System.StringComparer]::OrdinalIgnoreCase)
}

# Store for tracking invalidation reasons
if (-not (Get-Variable -Scope Script -Name CacheInvalidationLog -ErrorAction SilentlyContinue)) {
    $script:CacheInvalidationLog = [System.Collections.Generic.List[object]]::new()
}

function Set-CacheEntryTTL {
    <#
    .SYNOPSIS
    Sets the cache entry TTL (time-to-live) in minutes.
    .PARAMETER Minutes
    TTL in minutes. Set to 0 for no expiration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$Minutes
    )

    $script:CacheEntryTTLMinutes = [Math]::Max(0, $Minutes)
    return $script:CacheEntryTTLMinutes
}

function Get-CacheEntryTTL {
    <#
    .SYNOPSIS
    Gets the current cache entry TTL in minutes.
    #>
    [CmdletBinding()]
    param()

    return $script:CacheEntryTTLMinutes
}

function Update-CacheEntryTimestamp {
    <#
    .SYNOPSIS
    Updates the timestamp for a cache entry.
    .PARAMETER SiteKey
    The site key to update.
    .PARAMETER Timestamp
    Optional timestamp. Defaults to current UTC time.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SiteKey,
        [datetime]$Timestamp
    )

    if ([string]::IsNullOrWhiteSpace($SiteKey)) { return }

    $ts = if ($Timestamp) { $Timestamp.ToUniversalTime() } else { [datetime]::UtcNow }
    $script:CacheEntryTimestamps[$SiteKey] = $ts
}

function Get-CacheEntryTimestamp {
    <#
    .SYNOPSIS
    Gets the timestamp for a cache entry.
    .PARAMETER SiteKey
    The site key to query.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SiteKey
    )

    if ([string]::IsNullOrWhiteSpace($SiteKey)) { return $null }

    $ts = $null
    if ($script:CacheEntryTimestamps.TryGetValue($SiteKey, [ref]$ts)) {
        return $ts
    }
    return $null
}

function Test-CacheEntryExpired {
    <#
    .SYNOPSIS
    Tests if a cache entry has expired based on TTL.
    .PARAMETER SiteKey
    The site key to test.
    .PARAMETER TTLMinutes
    Optional TTL override. Uses global setting if not specified.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SiteKey,
        [int]$TTLMinutes = -1
    )

    $ttl = if ($TTLMinutes -ge 0) { $TTLMinutes } else { $script:CacheEntryTTLMinutes }

    # TTL of 0 means no expiration
    if ($ttl -eq 0) { return $false }

    $ts = Get-CacheEntryTimestamp -SiteKey $SiteKey
    if (-not $ts) {
        # No timestamp means entry was created before TTL tracking - treat as expired
        return $true
    }

    $age = [datetime]::UtcNow - $ts
    return ($age.TotalMinutes -gt $ttl)
}

function Get-CacheEntryAge {
    <#
    .SYNOPSIS
    Gets the age of a cache entry in minutes.
    .PARAMETER SiteKey
    The site key to query.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SiteKey
    )

    $ts = Get-CacheEntryTimestamp -SiteKey $SiteKey
    if (-not $ts) { return -1 }

    $age = [datetime]::UtcNow - $ts
    return [int]$age.TotalMinutes
}

function Remove-ExpiredCacheEntries {
    <#
    .SYNOPSIS
    Removes all expired cache entries.
    .PARAMETER TTLMinutes
    Optional TTL override. Uses global setting if not specified.
    #>
    [CmdletBinding()]
    param(
        [int]$TTLMinutes = -1
    )

    $ttl = if ($TTLMinutes -ge 0) { $TTLMinutes } else { $script:CacheEntryTTLMinutes }

    # TTL of 0 means no expiration
    if ($ttl -eq 0) { return 0 }

    $store = Get-SharedSiteInterfaceCacheStore
    $removed = 0
    $expiredKeys = [System.Collections.Generic.List[string]]::new()

    foreach ($key in @($script:CacheEntryTimestamps.Keys)) {
        if (Test-CacheEntryExpired -SiteKey $key -TTLMinutes $ttl) {
            [void]$expiredKeys.Add($key)
        }
    }

    foreach ($key in $expiredKeys) {
        try {
            $removedValue = $null
            if ($store.TryRemove($key, [ref]$removedValue)) {
                $removed++
                $removedTs = $null
                [void]$script:CacheEntryTimestamps.TryRemove($key, [ref]$removedTs)

                # Log invalidation
                $logEntry = [PSCustomObject]@{
                    SiteKey = $key
                    Reason = 'TTL_Expired'
                    ExpiredAt = [datetime]::UtcNow
                    AgeMinutes = Get-CacheEntryAge -SiteKey $key
                }
                $script:CacheInvalidationLog.Add($logEntry)

                Publish-SharedSiteInterfaceCacheEvent -SiteKey $key -Operation 'TTLExpired' -EntryCount $store.Count
            }
        } catch {
            Write-Verbose "[Cache] Failed to remove expired entry '$key': $($_.Exception.Message)"
        }
    }

    return $removed
}

function Invoke-CacheEntryTTLCheck {
    <#
    .SYNOPSIS
    Checks if a cache entry is valid (not expired). Returns $true if valid.
    .PARAMETER SiteKey
    The site key to check.
    .PARAMETER AutoInvalidate
    If $true, automatically removes expired entries.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SiteKey,
        [switch]$AutoInvalidate
    )

    if (-not (Test-CacheEntryExpired -SiteKey $SiteKey)) {
        return $true
    }

    if ($AutoInvalidate.IsPresent) {
        $store = Get-SharedSiteInterfaceCacheStore
        $removedValue = $null
        if ($store.TryRemove($SiteKey, [ref]$removedValue)) {
            $removedTs = $null
            [void]$script:CacheEntryTimestamps.TryRemove($SiteKey, [ref]$removedTs)

            $logEntry = [PSCustomObject]@{
                SiteKey = $SiteKey
                Reason = 'TTL_AutoInvalidated'
                InvalidatedAt = [datetime]::UtcNow
            }
            $script:CacheInvalidationLog.Add($logEntry)

            Publish-SharedSiteInterfaceCacheEvent -SiteKey $SiteKey -Operation 'TTLAutoInvalidated' -EntryCount $store.Count
        }
    }

    return $false
}

function Get-CacheInvalidationLog {
    <#
    .SYNOPSIS
    Gets the cache invalidation log.
    .PARAMETER SiteKey
    Optional filter by site key.
    .PARAMETER Last
    Number of recent entries to return.
    #>
    [CmdletBinding()]
    param(
        [string]$SiteKey,
        [int]$Last = 100
    )

    $entries = @($script:CacheInvalidationLog)

    if (-not [string]::IsNullOrWhiteSpace($SiteKey)) {
        $entries = @($entries | Where-Object { $_.SiteKey -eq $SiteKey })
    }

    if ($Last -gt 0 -and $entries.Count -gt $Last) {
        $entries = @($entries | Select-Object -Last $Last)
    }

    return $entries
}

function Clear-CacheInvalidationLog {
    <#
    .SYNOPSIS
    Clears the cache invalidation log.
    #>
    [CmdletBinding()]
    param()

    $script:CacheInvalidationLog.Clear()
}

function Get-CacheTTLStats {
    <#
    .SYNOPSIS
    Gets statistics about cache entries and TTL.
    #>
    [CmdletBinding()]
    param()

    $store = Get-SharedSiteInterfaceCacheStore
    $totalEntries = $store.Count
    $trackedEntries = $script:CacheEntryTimestamps.Count
    $expiredCount = 0
    $oldestAge = 0
    $newestAge = [int]::MaxValue

    foreach ($key in @($script:CacheEntryTimestamps.Keys)) {
        $age = Get-CacheEntryAge -SiteKey $key
        if ($age -ge 0) {
            if ($age -gt $oldestAge) { $oldestAge = $age }
            if ($age -lt $newestAge) { $newestAge = $age }
        }
        if (Test-CacheEntryExpired -SiteKey $key) {
            $expiredCount++
        }
    }

    if ($newestAge -eq [int]::MaxValue) { $newestAge = 0 }

    return [PSCustomObject]@{
        TotalEntries = $totalEntries
        TrackedEntries = $trackedEntries
        ExpiredEntries = $expiredCount
        TTLMinutes = $script:CacheEntryTTLMinutes
        OldestAgeMinutes = $oldestAge
        NewestAgeMinutes = $newestAge
        InvalidationLogCount = $script:CacheInvalidationLog.Count
    }
}

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
    Write-SharedCacheSnapshotFileFallback, `
    Initialize-MemoryMappedCache, `
    Import-MemoryMappedCacheFromFile, `
    Export-MemoryMappedCacheToFile, `
    Sync-MemoryMappedCache, `
    Get-MemoryMappedCacheStats, `
    New-DataLineageContext, `
    Add-DataLineage, `
    Get-DataLineage, `
    Set-CacheEntryTTL, `
    Get-CacheEntryTTL, `
    Update-CacheEntryTimestamp, `
    Get-CacheEntryTimestamp, `
    Test-CacheEntryExpired, `
    Get-CacheEntryAge, `
    Remove-ExpiredCacheEntries, `
    Invoke-CacheEntryTTLCheck, `
    Get-CacheInvalidationLog, `
    Clear-CacheInvalidationLog, `
    Get-CacheTTLStats
