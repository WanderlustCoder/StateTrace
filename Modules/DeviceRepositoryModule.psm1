Set-StrictMode -Version Latest

if (-not (Get-Variable -Scope Script -Name ModuleRootPath -ErrorAction SilentlyContinue)) {
    try {
        $script:ModuleRootPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    } catch {
        $script:ModuleRootPath = Split-Path -Parent $PSScriptRoot
    }
}

if (-not (Get-Variable -Scope Script -Name DataDirPath -ErrorAction SilentlyContinue)) {
    $rootPath = if ($script:ModuleRootPath) { $script:ModuleRootPath } else { Split-Path -Parent $PSScriptRoot }
    $script:DataDirPath = Join-Path $rootPath 'Data'
}

if (-not (Get-Variable -Scope Script -Name SiteInterfaceCache -ErrorAction SilentlyContinue)) {
    $script:SiteInterfaceCache = @{}
}

if (-not (Get-Variable -Scope Script -Name SiteInterfaceSignatureCache -ErrorAction SilentlyContinue)) {
    $script:SiteInterfaceSignatureCache = @{}
}

if (-not (Get-Variable -Scope Script -Name SharedSiteInterfaceCacheKey -ErrorAction SilentlyContinue)) {
    $script:SharedSiteInterfaceCacheKey = 'StateTrace.Repository.SharedSiteInterfaceCache'
}

if (-not ('StateTrace.Models.InterfacePortRecord' -as [type])) {
    Add-Type -TypeDefinition @"
namespace StateTrace.Models
{
    public sealed class InterfacePortRecord
    {
        public string Hostname { get; set; }
        public string Port { get; set; }
        public string PortSort { get; set; }
        public string Name { get; set; }
        public string Status { get; set; }
        public string VLAN { get; set; }
        public string Duplex { get; set; }
        public string Speed { get; set; }
        public string Type { get; set; }
        public string LearnedMACs { get; set; }
        public string AuthState { get; set; }
        public string AuthMode { get; set; }
        public string AuthClientMAC { get; set; }
        public string Site { get; set; }
        public string Building { get; set; }
        public string Room { get; set; }
        public string Zone { get; set; }
        public string AuthTemplate { get; set; }
        public string Config { get; set; }
        public string ConfigStatus { get; set; }
        public string PortColor { get; set; }
        public string ToolTip { get; set; }
        public string CacheSignature { get; set; }
        public bool IsSelected { get; set; }
    }

    public sealed class InterfaceTemplateHint
    {
        public string PortColor { get; set; }
        public string ConfigStatus { get; set; }
        public bool HasTemplate { get; set; }
    }
}
"@ -Language CSharp
}

if (-not ('StateTrace.Models.InterfaceCacheEntry' -as [type])) {
    Add-Type -TypeDefinition @"
namespace StateTrace.Models
{
    public sealed class InterfaceCacheEntry
    {
        public string Name { get; set; }
        public string Status { get; set; }
        public string VLAN { get; set; }
        public string Duplex { get; set; }
        public string Speed { get; set; }
        public string Type { get; set; }
        public string Learned { get; set; }
        public string AuthState { get; set; }
        public string AuthMode { get; set; }
        public string AuthClient { get; set; }
        public string Template { get; set; }
        public string Config { get; set; }
        public string PortSort { get; set; }
        public string PortColor { get; set; }
        public string StatusTag { get; set; }
        public string ToolTip { get; set; }
        public string Signature { get; set; }
    }
}
"@ -Language CSharp
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

    $processId = 0
    try { $processId = [System.Diagnostics.Process]::GetCurrentProcess().Id } catch { $processId = 0 }

    $threadId = 0
    try { $threadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId } catch { $threadId = 0 }

    try {
        TelemetryModule\Write-StTelemetryEvent -Name 'InterfaceSiteCacheSharedStoreState' -Payload @{
            Operation     = $Operation
            EntryCount    = $EntryCount
            StoreHashCode = $StoreHashCode
            RunspaceId    = $runspaceId
            AppDomainId   = $appDomainId
            AppDomainName = $appDomainName
            ProcessId     = $processId
            ThreadId      = $threadId
        }
    } catch { }
}

function Publish-SharedSiteInterfaceCacheClearInvocation {
    param(
        [string]$Reason,
        [string]$CallerFunction,
        [string]$CallerScript,
        [int]$CallerLine,
        [string]$InvocationName,
        [int]$CallStackDepth
    )

    $runspaceId = ''
    try {
        $currentRunspace = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace
        if ($currentRunspace) { $runspaceId = $currentRunspace.InstanceId.ToString() }
    } catch {
        $runspaceId = ''
    }

    $processId = 0
    try { $processId = [System.Diagnostics.Process]::GetCurrentProcess().Id } catch { $processId = 0 }

    $threadId = 0
    try { $threadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId } catch { $threadId = 0 }

    try {
        TelemetryModule\Write-StTelemetryEvent -Name 'InterfaceSiteCacheClearInvocation' -Payload @{
            Reason         = $Reason
            CallerFunction = $CallerFunction
            CallerScript   = $CallerScript
            CallerLine     = $CallerLine
            InvocationName = $InvocationName
            CallStackDepth = $CallStackDepth
            RunspaceId     = $runspaceId
            ProcessId      = $processId
            ThreadId       = $threadId
        }
    } catch { }
}

function Import-SharedSiteInterfaceCacheSnapshotFromEnv {
    param(
        [System.Collections.Concurrent.ConcurrentDictionary[string, object]]$TargetStore
    )

    if (-not ($TargetStore -is [System.Collections.Concurrent.ConcurrentDictionary[string, object]])) {
        return 0
    }

    $snapshotPath = $null
    try { $snapshotPath = $env:STATETRACE_SHARED_CACHE_SNAPSHOT } catch { $snapshotPath = $null }
    if ([string]::IsNullOrWhiteSpace($snapshotPath) -or -not (Test-Path -LiteralPath $snapshotPath)) {
        return 0
    }

    $entries = $null
    try {
        $entries = Import-Clixml -Path $snapshotPath
    } catch {
        Write-Warning ("Failed to import shared cache snapshot '{0}' from STATETRACE_SHARED_CACHE_SNAPSHOT: {1}" -f $snapshotPath, $_.Exception.Message)
        return 0
    }
    if (-not $entries) { return 0 }

    $imported = 0
    foreach ($entry in @($entries)) {
        if (-not $entry) { continue }

        $siteKey = ''
        if ($entry.PSObject.Properties.Name -contains 'Site') {
            $siteKey = ('' + $entry.Site).Trim()
        } elseif ($entry.PSObject.Properties.Name -contains 'SiteKey') {
            $siteKey = ('' + $entry.SiteKey).Trim()
        }
        if ([string]::IsNullOrWhiteSpace($siteKey)) { continue }

        $entryPayload = $null
        if ($entry.PSObject.Properties.Name -contains 'Entry') {
            $entryPayload = $entry.Entry
        }
        if (-not $entryPayload) { continue }

        $normalizedEntry = $null
        try { $normalizedEntry = Normalize-InterfaceSiteCacheEntry -Entry $entryPayload } catch { $normalizedEntry = $null }
        if (-not $normalizedEntry) { continue }

        $TargetStore[$siteKey] = $normalizedEntry
        if (-not $script:SiteInterfaceSignatureCache) {
            $script:SiteInterfaceSignatureCache = @{}
        }
        $script:SiteInterfaceSignatureCache[$siteKey] = $normalizedEntry

        $stats = Get-SharedSiteInterfaceCacheEntryStatistics -Entry $normalizedEntry
        $storeHashCode = 0
        try { $storeHashCode = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($TargetStore) } catch { $storeHashCode = 0 }
        Publish-SharedSiteInterfaceCacheEvent -SiteKey $siteKey -Operation 'Set' -EntryCount $TargetStore.Count -HostCount $stats.HostCount -TotalRows $stats.TotalRows -StoreHashCode $storeHashCode
        $imported++
    }

    if ($imported -gt 0) {
        Write-Verbose ("Imported {0} shared cache entr{1} from '{2}' via STATETRACE_SHARED_CACHE_SNAPSHOT." -f $imported, $(if ($imported -eq 1) { 'y' } else { 'ies' }), $snapshotPath)
    }

    return $imported
}

function Ensure-SharedSiteInterfaceCacheSnapshotImported {
    param(
        [System.Collections.Concurrent.ConcurrentDictionary[string, object]]$Store,
        [switch]$Force
    )

    if (-not ($Store -is [System.Collections.Concurrent.ConcurrentDictionary[string, object]])) {
        return 0
    }

    $entryCount = 0
    try { $entryCount = [int]$Store.Count } catch { $entryCount = 0 }
    if ((-not $Force.IsPresent) -and $entryCount -gt 0) {
        return 0
    }

    $imported = Import-SharedSiteInterfaceCacheSnapshotFromEnv -TargetStore $Store
    if ($imported -gt 0) {
        $storeHashCode = 0
        try { $storeHashCode = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Store) } catch { $storeHashCode = 0 }
        $postImportCount = 0
        try { $postImportCount = [int]$Store.Count } catch { $postImportCount = $entryCount }
        Publish-SharedSiteInterfaceCacheStoreState -Operation 'SnapshotImported' -EntryCount $postImportCount -StoreHashCode $storeHashCode
    }

    return $imported
}

if (-not ('StateTrace.Repository.SharedSiteInterfaceCacheHolder' -as [type])) {
    Add-Type -TypeDefinition @"
namespace StateTrace.Repository
{
    using System;
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
"@ -Language CSharp
}

function Initialize-SharedSiteInterfaceCacheStore {
    $domain = [System.AppDomain]::CurrentDomain
    $storeKey = $script:SharedSiteInterfaceCacheKey
    $store = $null
    $createdNewStore = $false
    $adoptedExistingStore = $false

    try {
        $store = $domain.GetData($storeKey)
    } catch {
        $store = $null
    }

    if (-not ($store -is [System.Collections.Concurrent.ConcurrentDictionary[string, object]])) {
        $existing = $null
        try { $existing = [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::GetStore() } catch { $existing = $null }
        if ($existing -is [System.Collections.Concurrent.ConcurrentDictionary[string, object]]) {
            try {
                $domain.SetData($storeKey, $existing)
                $store = $domain.GetData($storeKey)
            } catch {
                $store = $existing
            }
            if ($store -is [System.Collections.Concurrent.ConcurrentDictionary[string, object]]) {
                $adoptedExistingStore = $true
            }
        }
    }

    if (-not ($store -is [System.Collections.Concurrent.ConcurrentDictionary[string, object]])) {
        $newStore = New-Object 'System.Collections.Concurrent.ConcurrentDictionary[string, object]' ([System.StringComparer]::OrdinalIgnoreCase)
        try {
            $domain.SetData($storeKey, $newStore)
            $store = $domain.GetData($storeKey)
        } catch {
            $store = $null
        }
        if (-not ($store -is [System.Collections.Concurrent.ConcurrentDictionary[string, object]])) {
            $store = $newStore
        }
        $createdNewStore = $true
    }

    if ($store -is [System.Collections.Concurrent.ConcurrentDictionary[string, object]]) {
        try { [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::SetStore($store) } catch { }
        $storeHashCode = 0
        $entryCount = 0
        try { $storeHashCode = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($store) } catch { $storeHashCode = 0 }
        try { $entryCount = [int]$store.Count } catch { $entryCount = 0 }
        $operation = if ($createdNewStore) { 'InitNewStore' } elseif ($adoptedExistingStore) { 'InitAdoptedStore' } else { 'InitReuseStore' }
        Publish-SharedSiteInterfaceCacheStoreState -Operation $operation -EntryCount $entryCount -StoreHashCode $storeHashCode

        if ($entryCount -eq 0) {
            [void](Ensure-SharedSiteInterfaceCacheSnapshotImported -Store $store -Force)
        }
    }

    return $store
}

function Get-SharedSiteInterfaceCacheStore {
    $store = $null
    if (Get-Variable -Scope Script -Name SharedSiteInterfaceCache -ErrorAction SilentlyContinue) {
        $store = $script:SharedSiteInterfaceCache
    }

    $storeKey = $script:SharedSiteInterfaceCacheKey
    $domainStore = $null
    $holderStore = $null
    try { $domainStore = [System.AppDomain]::CurrentDomain.GetData($storeKey) } catch { $domainStore = $null }
    try { $holderStore = [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::GetStore() } catch { $holderStore = $null }

    $bestStore = $null
    $bestCount = -1
    foreach ($candidate in @($store, $domainStore, $holderStore)) {
        if (-not ($candidate -is [System.Collections.Concurrent.ConcurrentDictionary[string, object]])) {
            continue
        }
        $candidateCount = 0
        try { $candidateCount = [int]$candidate.Count } catch { $candidateCount = 0 }
        if ($candidateCount -gt $bestCount) {
            $bestCount = $candidateCount
            $bestStore = $candidate
        }
    }

    if ($bestStore) {
        if (-not [object]::ReferenceEquals($store, $bestStore)) {
            $script:SharedSiteInterfaceCache = $bestStore
        }
        try { [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::SetStore($bestStore) } catch { }
        if (-not [object]::ReferenceEquals($domainStore, $bestStore)) {
            try { [System.AppDomain]::CurrentDomain.SetData($storeKey, $bestStore) } catch { }
        }
        if ($bestStore -is [System.Collections.Concurrent.ConcurrentDictionary[string, object]]) {
            [void](Ensure-SharedSiteInterfaceCacheSnapshotImported -Store $bestStore)
        }
        return $bestStore
    }

    if (-not ($store -is [System.Collections.Concurrent.ConcurrentDictionary[string, object]])) {
        $store = Initialize-SharedSiteInterfaceCacheStore
        $script:SharedSiteInterfaceCache = $store
    }
    if ($store -is [System.Collections.Concurrent.ConcurrentDictionary[string, object]]) {
        try { [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::SetStore($store) } catch { }
        [void](Ensure-SharedSiteInterfaceCacheSnapshotImported -Store $store)
    }

    return $store
}

if (-not (Get-Variable -Scope Script -Name SharedSiteInterfaceCache -ErrorAction SilentlyContinue)) {
    $script:SharedSiteInterfaceCache = Initialize-SharedSiteInterfaceCacheStore
} elseif (-not ($script:SharedSiteInterfaceCache -is [System.Collections.Concurrent.ConcurrentDictionary[string, object]])) {
    $script:SharedSiteInterfaceCache = Initialize-SharedSiteInterfaceCacheStore
}

if ($script:SharedSiteInterfaceCache -is [System.Collections.Concurrent.ConcurrentDictionary[string, object]]) {
    [void](Ensure-SharedSiteInterfaceCacheSnapshotImported -Store $script:SharedSiteInterfaceCache)
}

function Copy-InterfaceCacheEntryObject {
    param(
        [Parameter(Mandatory)][StateTrace.Models.InterfaceCacheEntry]$Source
    )

    $clone = [StateTrace.Models.InterfaceCacheEntry]::new()
    $clone.Name       = $Source.Name
    $clone.Status     = $Source.Status
    $clone.VLAN       = $Source.VLAN
    $clone.Duplex     = $Source.Duplex
    $clone.Speed      = $Source.Speed
    $clone.Type       = $Source.Type
    $clone.Learned    = $Source.Learned
    $clone.AuthState  = $Source.AuthState
    $clone.AuthMode   = $Source.AuthMode
    $clone.AuthClient = $Source.AuthClient
    $clone.Template   = $Source.Template
    $clone.Config     = $Source.Config
    $clone.PortSort   = $Source.PortSort
    $clone.PortColor  = $Source.PortColor
    $clone.StatusTag  = $Source.StatusTag
    $clone.ToolTip    = $Source.ToolTip
    $clone.Signature  = $Source.Signature
    return $clone
}

function Copy-InterfaceSiteCacheValue {
    param($Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) { return '' + $Value }
    if ($Value -is [datetime]) { return [datetime]$Value }
    if ($Value -is [System.ValueType]) { return $Value }
    if ($Value -is [StateTrace.Models.InterfaceCacheEntry]) {
        return Copy-InterfaceCacheEntryObject -Source $Value
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $result = New-Object 'System.Collections.Hashtable' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($key in $Value.Keys) {
            $result[$key] = Copy-InterfaceSiteCacheValue -Value $Value[$key]
        }
        return $result
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        if ($Value -is [string]) { return '' + $Value }
        $list = New-Object 'System.Collections.Generic.List[object]'
        foreach ($item in $Value) {
            $list.Add((Copy-InterfaceSiteCacheValue -Value $item)) | Out-Null
        }
        return $list.ToArray()
    }
    if ($Value -is [psobject]) {
        $clone = [pscustomobject]@{}
        foreach ($prop in $Value.PSObject.Properties) {
            $clone | Add-Member -NotePropertyName $prop.Name -NotePropertyValue (Copy-InterfaceSiteCacheValue -Value $prop.Value) -Force
        }
        return $clone
    }
    return $Value
}

function Copy-InterfaceCacheHostMap {
    param($HostMap)

    if (-not $HostMap) { return $null }

    $clone = New-Object 'System.Collections.Hashtable' ([System.StringComparer]::OrdinalIgnoreCase)

    $hostEnumerator = $null
    try { $hostEnumerator = $HostMap.GetEnumerator() } catch { $hostEnumerator = $null }
    if (-not $hostEnumerator) { return $null }

    while ($hostEnumerator.MoveNext()) {
        $hostEntry = $hostEnumerator.Current
        $rawHostKey = $null
        $hostPorts = $null
        if ($hostEntry -is [System.Collections.DictionaryEntry]) {
            $rawHostKey = $hostEntry.Key
            $hostPorts = $hostEntry.Value
        } else {
            try { $rawHostKey = $hostEntry.Key } catch { $rawHostKey = $null }
            try { $hostPorts = $hostEntry.Value } catch { $hostPorts = $null }
        }

        $hostKey = if ($rawHostKey) { ('' + $rawHostKey).Trim() } else { '' }
        if ([string]::IsNullOrWhiteSpace($hostKey)) { continue }

        $portClone = New-Object 'System.Collections.Hashtable' ([System.StringComparer]::OrdinalIgnoreCase)
        if ($hostPorts) {
            $portEnumerator = $null
            try { $portEnumerator = $hostPorts.GetEnumerator() } catch { $portEnumerator = $null }
            if ($portEnumerator) {
                while ($portEnumerator.MoveNext()) {
                    $portEntry = $portEnumerator.Current
                    $rawPortKey = $null
                    $entryValue = $null
                    if ($portEntry -is [System.Collections.DictionaryEntry]) {
                        $rawPortKey = $portEntry.Key
                        $entryValue = $portEntry.Value
                    } else {
                        try { $rawPortKey = $portEntry.Key } catch { $rawPortKey = $null }
                        try { $entryValue = $portEntry.Value } catch { $entryValue = $null }
                    }

                    $portKey = if ($rawPortKey) { ('' + $rawPortKey).Trim() } else { '' }
                    if ([string]::IsNullOrWhiteSpace($portKey)) { continue }
                    if ($null -eq $entryValue) { continue }

                    if ($entryValue -is [StateTrace.Models.InterfaceCacheEntry]) {
                        $portClone[$portKey] = Copy-InterfaceCacheEntryObject -Source $entryValue
                    } else {
                        try {
                            $converted = ConvertTo-InterfaceCacheEntryObject -InputObject $entryValue
                            if ($converted) {
                                $portClone[$portKey] = $converted
                            }
                        } catch {
                            continue
                        }
                    }
                }
            }
        }

        $clone[$hostKey] = $portClone
    }

    return $clone
}

function ConvertTo-InterfaceCacheHostMapDictionary {
    param($HostMap)

    $typedHostMap = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.Dictionary[string,StateTrace.Models.InterfaceCacheEntry]]' ([System.StringComparer]::OrdinalIgnoreCase)

    if (-not $HostMap) { return $typedHostMap }

    $normalizedHostMap = Copy-InterfaceCacheHostMap -HostMap $HostMap
    if (-not ($normalizedHostMap -is [System.Collections.IDictionary])) { return $typedHostMap }

    foreach ($hostKey in @($normalizedHostMap.Keys)) {
        $normalizedHostKey = if ($hostKey) { ('' + $hostKey).Trim() } else { '' }
        if ([string]::IsNullOrWhiteSpace($normalizedHostKey)) { continue }

        $portMap = $normalizedHostMap[$hostKey]
        $typedPortMap = New-Object 'System.Collections.Generic.Dictionary[string,StateTrace.Models.InterfaceCacheEntry]' ([System.StringComparer]::OrdinalIgnoreCase)
        if ($portMap -is [System.Collections.IDictionary]) {
            foreach ($portKey in @($portMap.Keys)) {
                $normalizedPortKey = if ($portKey) { ('' + $portKey).Trim() } else { '' }
                if ([string]::IsNullOrWhiteSpace($normalizedPortKey)) { continue }
                $portEntry = $portMap[$portKey]
                $typedEntry = $null
                if ($portEntry -is [StateTrace.Models.InterfaceCacheEntry]) {
                    $typedEntry = $portEntry
                } elseif ($null -ne $portEntry) {
                    try {
                        $typedEntry = ConvertTo-InterfaceCacheEntryObject -InputObject $portEntry
                    } catch {
                        $typedEntry = $null
                    }
                }
                if ($typedEntry) {
                    $typedPortMap[$normalizedPortKey] = $typedEntry
                }
            }
        }
        $typedHostMap[$normalizedHostKey] = $typedPortMap
    }

    return $typedHostMap
}

function Normalize-InterfaceSiteCacheEntry {
    param([Parameter()][object]$Entry)

    if (-not $Entry) { return $null }

    $clone = Clone-InterfaceSiteCacheEntry -Entry $Entry
    if (-not $clone) { return $null }

    $hostMapSource = $null
    if ($Entry.PSObject.Properties.Name -contains 'HostMap') {
        $hostMapSource = $Entry.HostMap
    } elseif ($clone.PSObject.Properties.Name -contains 'HostMap') {
        $hostMapSource = $clone.HostMap
    }

    $typedHostMap = ConvertTo-InterfaceCacheHostMapDictionary -HostMap $hostMapSource
    $clone | Add-Member -NotePropertyName 'HostMap' -NotePropertyValue $typedHostMap -Force

    $hostCount = 0
    $totalRows = 0
    if ($typedHostMap) {
        try { $hostCount = [int]$typedHostMap.Count } catch { $hostCount = 0 }
        foreach ($portCollection in $typedHostMap.Values) {
            if ($portCollection -is [System.Collections.IDictionary] -or $portCollection -is [System.Collections.ICollection]) {
                try { $totalRows += [int]$portCollection.Count } catch { }
            }
        }
    }

    $clone | Add-Member -NotePropertyName 'HostCount' -NotePropertyValue $hostCount -Force
    $clone | Add-Member -NotePropertyName 'TotalRows' -NotePropertyValue $totalRows -Force

    return $clone
}

function Merge-InterfaceSiteCacheEntry {
    param(
        [pscustomobject]$Existing,
        [pscustomobject]$Incoming
    )

    $normalizedIncoming = Normalize-InterfaceSiteCacheEntry -Entry $Incoming
    if (-not $normalizedIncoming) {
        return (Normalize-InterfaceSiteCacheEntry -Entry $Existing)
    }

    $normalizedExisting = Normalize-InterfaceSiteCacheEntry -Entry $Existing
    if (-not $normalizedExisting) {
        return $normalizedIncoming
    }

    $result = Clone-InterfaceSiteCacheEntry -Entry $normalizedExisting
    if (-not $result) {
        $result = [pscustomobject]@{}
    }

    $mergedHostMap = ConvertTo-InterfaceCacheHostMapDictionary -HostMap $result.HostMap
    if (-not $mergedHostMap) {
        $mergedHostMap = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.Dictionary[string,StateTrace.Models.InterfaceCacheEntry]]' ([System.StringComparer]::OrdinalIgnoreCase)
    }

    $incomingHostMap = $normalizedIncoming.HostMap
    if ($incomingHostMap -is [System.Collections.IDictionary]) {
        foreach ($incomingHostKey in @($incomingHostMap.Keys)) {
            $normalizedHostKey = if ($incomingHostKey) { ('' + $incomingHostKey).Trim() } else { '' }
            if ([string]::IsNullOrWhiteSpace($normalizedHostKey)) { continue }

            $incomingPorts = $incomingHostMap[$incomingHostKey]
            if (-not $incomingPorts) {
                $null = $mergedHostMap.Remove($normalizedHostKey)
                continue
            }

            $fragmentSource = New-Object 'System.Collections.Hashtable' ([System.StringComparer]::OrdinalIgnoreCase)
            $fragmentSource[$normalizedHostKey] = $incomingPorts
            $typedFragment = ConvertTo-InterfaceCacheHostMapDictionary -HostMap $fragmentSource

            if ($typedFragment -and $typedFragment.ContainsKey($normalizedHostKey)) {
                $mergedHostMap[$normalizedHostKey] = $typedFragment[$normalizedHostKey]
            } else {
                $null = $mergedHostMap.Remove($normalizedHostKey)
            }
        }
    }

    $result | Add-Member -NotePropertyName 'HostMap' -NotePropertyValue $mergedHostMap -Force

    foreach ($prop in $normalizedIncoming.PSObject.Properties) {
        if ($prop.Name -eq 'HostMap') { continue }
        $result | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
    }

    $hostCount = 0
    $totalRows = 0
    if ($mergedHostMap) {
        try { $hostCount = [int]$mergedHostMap.Count } catch { $hostCount = 0 }
        foreach ($portCollection in $mergedHostMap.Values) {
            if ($portCollection -is [System.Collections.IDictionary] -or $portCollection -is [System.Collections.ICollection]) {
                try { $totalRows += [int]$portCollection.Count } catch { }
            }
        }
    }

    $result | Add-Member -NotePropertyName 'HostCount' -NotePropertyValue $hostCount -Force
    $result | Add-Member -NotePropertyName 'TotalRows' -NotePropertyValue $totalRows -Force

    return $result
}

function Clone-InterfaceSiteCacheEntry {
    param([pscustomobject]$Entry)

    if (-not $Entry) { return $null }
    $clone = [pscustomobject]@{}
    foreach ($prop in $Entry.PSObject.Properties) {
        $name = $prop.Name
        switch ($name) {
            'HostMap' {
                $clone | Add-Member -NotePropertyName 'HostMap' -NotePropertyValue (Copy-InterfaceCacheHostMap -HostMap $prop.Value) -Force
            }
            default {
                $clone | Add-Member -NotePropertyName $name -NotePropertyValue (Copy-InterfaceSiteCacheValue -Value $prop.Value) -Force
            }
        }
    }
    return $clone
}

function Get-SharedSiteInterfaceCacheEntry {
    param([Parameter(Mandatory)][string]$SiteKey)

    $key = ('' + $SiteKey).Trim()
    if ([string]::IsNullOrWhiteSpace($key)) { return $null }
    $store = Get-SharedSiteInterfaceCacheStore
    $storeHashCode = 0
    if ($store) {
        try { $storeHashCode = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($store) } catch { $storeHashCode = 0 }
    }
    if (-not ($store -is [System.Collections.Concurrent.ConcurrentDictionary[string, object]])) {
        Publish-SharedSiteInterfaceCacheEvent -SiteKey $key -Operation 'GetMiss' -EntryCount 0 -StoreHashCode $storeHashCode
        return $null
    }
    $stored = $null
    $entryCount = 0
    try { $entryCount = [int]$store.Count } catch { $entryCount = 0 }
    if ($store.TryGetValue($key, [ref]$stored) -and $stored) {
        $clone = Normalize-InterfaceSiteCacheEntry -Entry $stored
        $stats = Get-SharedSiteInterfaceCacheEntryStatistics -Entry $clone
        Publish-SharedSiteInterfaceCacheEvent -SiteKey $key -Operation 'GetHit' -EntryCount $entryCount -HostCount $stats.HostCount -TotalRows $stats.TotalRows -StoreHashCode $storeHashCode
        return $clone
    }
    Publish-SharedSiteInterfaceCacheEvent -SiteKey $key -Operation 'GetMiss' -EntryCount $entryCount -StoreHashCode $storeHashCode
    return $null
}

function Convert-InterfaceCacheEntryToExportObject {
    param($Entry)

    if (-not $Entry) { return $null }

    $export = [pscustomobject]@{}
    $source = $Entry
    $psObject = $null
    try { $psObject = $source.PSObject } catch { $psObject = $null }

    if ($source -is [System.Collections.IDictionary]) {
        foreach ($key in @($source.Keys)) {
            $export | Add-Member -NotePropertyName $key -NotePropertyValue $source[$key] -Force
        }
    } elseif ($psObject) {
        foreach ($prop in $psObject.Properties) {
            $export | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
        }
    }

    return $export
}

function ConvertTo-KeyValueEntryList {
    param($Source)

    $entries = New-Object 'System.Collections.Generic.List[psobject]'
    if (-not $Source) { return $entries }

    if ($Source -is [System.Collections.IDictionary]) {
        foreach ($key in @($Source.Keys)) {
            $entries.Add([pscustomobject]@{
                    Key   = $key
                    Value = $Source[$key]
                }) | Out-Null
        }
        return $entries
    }

    if ($Source -is [System.Collections.IEnumerable]) {
        foreach ($item in $Source) {
            if (-not $item) { continue }
            $entryKey = $null
            $entryValue = $null

            if ($item -is [System.Collections.DictionaryEntry]) {
                $entryKey = $item.Key
                $entryValue = $item.Value
            } else {
                $psEntry = $null
                try { $psEntry = $item.PSObject } catch { $psEntry = $null }
                if ($psEntry -and $psEntry.Properties['Key']) {
                    $entryKey = $psEntry.Properties['Key'].Value
                } elseif ($item -isnot [string]) {
                    try { $entryKey = $item.Key } catch { $entryKey = $null }
                }
                if ($psEntry -and $psEntry.Properties['Value']) {
                    $entryValue = $psEntry.Properties['Value'].Value
                } elseif ($item -isnot [string]) {
                    try { $entryValue = $item.Value } catch { $entryValue = $null }
                }
            }

            if ($null -eq $entryKey) { continue }
            $entries.Add([pscustomobject]@{
                    Key   = $entryKey
                    Value = $entryValue
                }) | Out-Null
        }
    }

    return $entries
}

function Convert-InterfaceSiteCacheHostMapToExportMap {
    param($HostMap)

    $exportMap = New-Object 'System.Collections.Hashtable' ([System.StringComparer]::OrdinalIgnoreCase)
    if (-not $HostMap) { return $exportMap }

    $hostEntries = ConvertTo-KeyValueEntryList -Source $HostMap
    foreach ($hostEntry in $hostEntries) {
        if (-not $hostEntry) { continue }
        $normalizedHostKey = if ($hostEntry.Key) { ('' + $hostEntry.Key).Trim() } else { '' }
        if ([string]::IsNullOrWhiteSpace($normalizedHostKey)) { continue }

        $ports = $hostEntry.Value
        $exportPorts = New-Object 'System.Collections.Hashtable' ([System.StringComparer]::OrdinalIgnoreCase)

        $portEntries = ConvertTo-KeyValueEntryList -Source $ports
        if ($portEntries.Count -gt 0) {
            foreach ($portEntry in $portEntries) {
                if (-not $portEntry) { continue }
                $normalizedPortKey = if ($portEntry.Key) { ('' + $portEntry.Key).Trim() } else { '' }
                if ([string]::IsNullOrWhiteSpace($normalizedPortKey)) { continue }
                $exportPorts[$normalizedPortKey] = Convert-InterfaceCacheEntryToExportObject -Entry $portEntry.Value
            }
        } elseif ($ports -is [System.Collections.IEnumerable] -and -not ($ports -is [string])) {
            foreach ($portEntry in $ports) {
                if (-not $portEntry) { continue }
                $portName = $null
                $portPsObject = $null
                try { $portPsObject = $portEntry.PSObject } catch { $portPsObject = $null }
                if ($portPsObject -and $portPsObject.Properties['Port']) {
                    $portName = '' + $portPsObject.Properties['Port'].Value
                }
                if ([string]::IsNullOrWhiteSpace($portName)) { continue }
                $normalizedPortName = $portName.Trim()
                if ([string]::IsNullOrWhiteSpace($normalizedPortName)) { continue }
                $exportPorts[$normalizedPortName] = Convert-InterfaceCacheEntryToExportObject -Entry $portEntry
            }
        }

        $exportMap[$normalizedHostKey] = $exportPorts
    }

    return $exportMap
}

function Convert-SharedSiteCacheEntryToExportObject {
    param($Entry)

    if (-not $Entry) { return $null }

    $export = [pscustomobject]@{}
    $psObject = $null
    try { $psObject = $Entry.PSObject } catch { $psObject = $null }

    if ($psObject) {
        foreach ($prop in $psObject.Properties) {
            if ($prop.Name -eq 'HostMap') { continue }
            $export | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
        }
    }

    $hostMapValue = $null
    if ($psObject -and $psObject.Properties['HostMap']) {
        $hostMapValue = $psObject.Properties['HostMap'].Value
    }

    $exportHostMap = Convert-InterfaceSiteCacheHostMapToExportMap -HostMap $hostMapValue
    $export | Add-Member -NotePropertyName 'HostMap' -NotePropertyValue $exportHostMap -Force

    $hostCount = 0
    try { $hostCount = [int]$exportHostMap.Count } catch { $hostCount = 0 }
    $totalRows = 0
    foreach ($portCollection in $exportHostMap.Values) {
        if ($portCollection -is [System.Collections.IDictionary]) {
            try { $totalRows += [int]$portCollection.Count } catch { }
        }
    }

    if (-not ($export.PSObject.Properties.Name -contains 'HostCount')) {
        $export | Add-Member -NotePropertyName 'HostCount' -NotePropertyValue $hostCount -Force
    }
    if (-not ($export.PSObject.Properties.Name -contains 'TotalRows')) {
        $export | Add-Member -NotePropertyName 'TotalRows' -NotePropertyValue $totalRows -Force
    }

    return $export
}

function Get-SharedSiteInterfaceCacheSnapshotEntries {
    $snapshot = $null
    try { $snapshot = [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::GetSnapshot() } catch { $snapshot = $null }
    $result = New-Object 'System.Collections.Generic.List[psobject]'
    if ($snapshot -is [System.Collections.IDictionary]) {
        foreach ($siteKey in @($snapshot.Keys)) {
            if ([string]::IsNullOrWhiteSpace($siteKey)) { continue }
            $entryValue = $snapshot[$siteKey]
            if (-not $entryValue) { continue }
            $clone = $null
            try { $clone = Clone-InterfaceSiteCacheEntry -Entry $entryValue } catch { $clone = $null }
            if (-not $clone) { continue }

            $exportEntry = $null
            try { $exportEntry = Convert-SharedSiteCacheEntryToExportObject -Entry $clone } catch { $exportEntry = $null }
            if ($exportEntry) {
                $result.Add([pscustomobject]@{
                        Site  = $siteKey
                        Entry = $exportEntry
                    }) | Out-Null
            }
        }
    }
    return ,$result.ToArray()
}

function Set-SharedSiteInterfaceCacheEntry {
    param(
        [Parameter(Mandatory)][string]$SiteKey,
        [pscustomobject]$Entry
    )

    $key = ('' + $SiteKey).Trim()
    if ([string]::IsNullOrWhiteSpace($key)) { return }
    $store = Get-SharedSiteInterfaceCacheStore
    if (-not ($store -is [System.Collections.Concurrent.ConcurrentDictionary[string, object]])) { return }
    $storeHashCode = 0
    try { $storeHashCode = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($store) } catch { $storeHashCode = 0 }
    if ($Entry) {
        $clone = Normalize-InterfaceSiteCacheEntry -Entry $Entry
        $updated = $store.AddOrUpdate(
            $key,
            $clone,
            {
                param($k, $existing)
                $merged = Merge-InterfaceSiteCacheEntry -Existing $existing -Incoming $clone
                if ($merged) { return $merged }
                return $clone
            }
        )
        $normalized = Normalize-InterfaceSiteCacheEntry -Entry $updated
        $stats = Get-SharedSiteInterfaceCacheEntryStatistics -Entry $normalized
        $entryCount = 0
        try { $entryCount = [int]$store.Count } catch { $entryCount = 0 }
        Publish-SharedSiteInterfaceCacheEvent -SiteKey $key -Operation 'Set' -EntryCount $entryCount -HostCount $stats.HostCount -TotalRows $stats.TotalRows -StoreHashCode $storeHashCode
        try {
            $snapshotStore = [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::GetSnapshot()
            if (-not ($snapshotStore -is [System.Collections.Concurrent.ConcurrentDictionary[string, object]])) {
                $snapshotStore = New-Object 'System.Collections.Concurrent.ConcurrentDictionary[string, object]' ([System.StringComparer]::OrdinalIgnoreCase)
                [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::SetSnapshot($snapshotStore)
            }
            if ($snapshotStore) {
                $snapshotClone = Clone-InterfaceSiteCacheEntry -Entry $normalized
                if ($snapshotClone) {
                    $null = $snapshotStore.AddOrUpdate(
                        $key,
                        $snapshotClone,
                        {
                            param($k, $existingSnapshot)
                            $snapshotClone
                        }
                    )
                }
            }
        } catch { }
    } else {
        $removed = $null
        $store.TryRemove($key, [ref]$removed) | Out-Null
        $entryCount = 0
        try { $entryCount = [int]$store.Count } catch { $entryCount = 0 }
        $removedStats = if ($removed) { Get-SharedSiteInterfaceCacheEntryStatistics -Entry $removed } else { [pscustomobject]@{ HostCount = 0; TotalRows = 0 } }
        Publish-SharedSiteInterfaceCacheEvent -SiteKey $key -Operation 'Remove' -EntryCount $entryCount -HostCount $removedStats.HostCount -TotalRows $removedStats.TotalRows -StoreHashCode $storeHashCode
        try {
            $snapshotStore = [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::GetSnapshot()
            if ($snapshotStore -is [System.Collections.Concurrent.ConcurrentDictionary[string, object]]) {
                $null = $snapshotStore.TryRemove($key, [ref]([object]$null))
            }
        } catch { }
    }
}

if (-not (Get-Variable -Scope Global -Name DeviceInterfaceCache -ErrorAction SilentlyContinue)) {
    $global:DeviceInterfaceCache = @{}
}

if (-not (Get-Variable -Scope Global -Name AllInterfaces -ErrorAction SilentlyContinue)) {
    $global:AllInterfaces = New-Object 'System.Collections.Generic.List[object]'
}

if (-not (Get-Variable -Scope Global -Name LoadedSiteZones -ErrorAction SilentlyContinue)) {
    $global:LoadedSiteZones = @{}
}

if (-not (Get-Variable -Scope Script -Name InterfacePortStreamStore -ErrorAction SilentlyContinue)) {
    $script:InterfacePortStreamStore = @{}
}

if (-not (Get-Variable -Scope Script -Name InterfacePortStreamChunkSize -ErrorAction SilentlyContinue)) {
    $script:InterfacePortStreamChunkSize = 24
}

function Set-InterfacePortStreamChunkSize {
    [CmdletBinding()]
    param(
        [int]$ChunkSize,
        [switch]$Reset
    )

    $defaultChunkSize = 24
    $targetSize = $defaultChunkSize

    if (-not $Reset -and $PSBoundParameters.ContainsKey('ChunkSize') -and $ChunkSize -gt 0) {
        $targetSize = [int]$ChunkSize
    }

    $script:InterfacePortStreamChunkSize = $targetSize
    return $script:InterfacePortStreamChunkSize
}

if (-not (Get-Variable -Scope Script -Name LastInterfacePortStreamMetrics -ErrorAction SilentlyContinue)) {
    $script:LastInterfacePortStreamMetrics = $null
}

if (-not (Get-Variable -Scope Script -Name LastInterfacePortDispatchMetrics -ErrorAction SilentlyContinue)) {
    $script:LastInterfacePortDispatchMetrics = $null
}

if (-not (Get-Variable -Scope Script -Name LastInterfacePortQueueMetrics -ErrorAction SilentlyContinue)) {
    $script:LastInterfacePortQueueMetrics = $null
}

if (-not (Get-Variable -Scope Script -Name LastInterfaceSiteCacheMetrics -ErrorAction SilentlyContinue)) {
    $script:LastInterfaceSiteCacheMetrics = $null
}

if (-not (Get-Variable -Scope Script -Name LastInterfaceSiteHydrationMetrics -ErrorAction SilentlyContinue)) {
    $script:LastInterfaceSiteHydrationMetrics = $null
}

function Publish-InterfaceSiteCacheTelemetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SiteKey,
        [Parameter(Mandatory)][pscustomobject]$Metrics,
        [Parameter()][int]$HostCount = 0,
        [Parameter()][int]$TotalRows = 0,
        [Parameter()][bool]$Refreshed = $false
    )

    $materializePortSortHitRatio = $null
    try {
        $portSortTotal = [double]([long][Math]::Max(0, $Metrics.HydrationMaterializePortSortCacheHits) + [long][Math]::Max(0, $Metrics.HydrationMaterializePortSortCacheMisses))
        if ($portSortTotal -gt 0) {
            $materializePortSortHitRatio = [Math]::Round(([double][Math]::Max(0, $Metrics.HydrationMaterializePortSortCacheHits) / $portSortTotal), 6)
        }
    } catch {
        $materializePortSortHitRatio = $null
    }

    $materializeTemplateCacheHitRatio = $null
    try {
        $templateCacheTotal = [double]([long][Math]::Max(0, $Metrics.HydrationMaterializeTemplateCacheHitCount) + [long][Math]::Max(0, $Metrics.HydrationMaterializeTemplateCacheMissCount))
        if ($templateCacheTotal -gt 0) {
            $materializeTemplateCacheHitRatio = [Math]::Round(([double][Math]::Max(0, $Metrics.HydrationMaterializeTemplateCacheHitCount) / $templateCacheTotal), 6)
        }
    } catch {
        $materializeTemplateCacheHitRatio = $null
    }

    try {
        TelemetryModule\Write-StTelemetryEvent -Name 'InterfaceSiteCacheMetrics' -Payload @{
            Site                             = $SiteKey
            CacheStatus                      = $Metrics.CacheStatus
            Refreshed                        = $Refreshed
            HydrationDurationMs              = $Metrics.HydrationDurationMs
            SnapshotDurationMs               = $Metrics.HydrationSnapshotMs
            RecordsetDurationMs              = $Metrics.HydrationSnapshotRecordsetDurationMs
            RecordsetProjectDurationMs       = $Metrics.HydrationSnapshotProjectDurationMs
            BuildDurationMs                  = $Metrics.HydrationBuildMs
            HostMapDurationMs                = $Metrics.HydrationHostMapDurationMs
            HostMapSignatureMatchCount       = $Metrics.HydrationHostMapSignatureMatchCount
            HostMapSignatureRewriteCount     = $Metrics.HydrationHostMapSignatureRewriteCount
            HostMapSignatureMismatchSamples  = $Metrics.HydrationHostMapSignatureMismatchSamples
            HostMapEntryAllocationCount      = $Metrics.HydrationHostMapEntryAllocationCount
            HostMapEntryPoolReuseCount       = $Metrics.HydrationHostMapEntryPoolReuseCount
            HostMapLookupCount               = $Metrics.HydrationHostMapLookupCount
            HostMapLookupMissCount           = $Metrics.HydrationHostMapLookupMissCount
            HostMapCandidateMissingCount     = $Metrics.HydrationHostMapCandidateMissingCount
            HostMapCandidateSignatureMissingCount = $Metrics.HydrationHostMapCandidateSignatureMissingCount
            HostMapCandidateSignatureMismatchCount = $Metrics.HydrationHostMapCandidateSignatureMismatchCount
            HostMapCandidateMissingSamples   = $Metrics.HydrationHostMapCandidateMissingSamples
            HostMapCandidateFromPreviousCount = $Metrics.HydrationHostMapCandidateFromPreviousCount
            HostMapCandidateFromPoolCount    = $Metrics.HydrationHostMapCandidateFromPoolCount
            HostMapCandidateInvalidCount     = $Metrics.HydrationHostMapCandidateInvalidCount
            PreviousHostCount                = $Metrics.HydrationPreviousHostCount
            PreviousPortCount                = $Metrics.HydrationPreviousPortCount
            PreviousHostSample               = $Metrics.HydrationPreviousHostSample
            PreviousSnapshotStatus           = $Metrics.HydrationPreviousSnapshotStatus
            PreviousSnapshotHostMapType      = $Metrics.HydrationPreviousSnapshotHostMapType
            PreviousSnapshotHostCount        = $Metrics.HydrationPreviousSnapshotHostCount
            PreviousSnapshotPortCount        = $Metrics.HydrationPreviousSnapshotPortCount
            PreviousSnapshotException        = $Metrics.HydrationPreviousSnapshotException
            SortDurationMs                   = $Metrics.HydrationSortDurationMs
            QueryDurationMs                  = $Metrics.HydrationQueryDurationMs
            ExecuteDurationMs                = $Metrics.HydrationExecuteDurationMs
            MaterializeDurationMs            = $Metrics.HydrationMaterializeDurationMs
            MaterializeProjectionDurationMs  = $Metrics.HydrationMaterializeProjectionDurationMs
            MaterializePortSortDurationMs    = $Metrics.HydrationMaterializePortSortDurationMs
            MaterializePortSortCacheHits     = $Metrics.HydrationMaterializePortSortCacheHits
            MaterializePortSortCacheMisses   = $Metrics.HydrationMaterializePortSortCacheMisses
            MaterializePortSortCacheSize     = $Metrics.HydrationMaterializePortSortCacheSize
            MaterializePortSortCacheHitRatio = $materializePortSortHitRatio
            MaterializeTemplateDurationMs    = $Metrics.HydrationMaterializeTemplateDurationMs
            MaterializeTemplateLookupDurationMs = $Metrics.HydrationMaterializeTemplateLookupDurationMs
            MaterializeTemplateApplyDurationMs = $Metrics.HydrationMaterializeTemplateApplyDurationMs
            MaterializeTemplateCacheHits     = $Metrics.HydrationMaterializeTemplateCacheHitCount
            MaterializeTemplateCacheMisses   = $Metrics.HydrationMaterializeTemplateCacheMissCount
            MaterializeTemplateCacheHitRatio = $materializeTemplateCacheHitRatio
            MaterializeObjectDurationMs      = $Metrics.HydrationMaterializeObjectDurationMs
            TemplateDurationMs               = $Metrics.HydrationTemplateDurationMs
            QueryAttempts                    = $Metrics.HydrationQueryAttempts
            ExclusiveRetryCount              = $Metrics.HydrationExclusiveRetryCount
            ExclusiveWaitDurationMs          = $Metrics.HydrationExclusiveWaitDurationMs
            Provider                         = $Metrics.HydrationProvider
            ResultRowCount                   = $Metrics.HydrationResultRowCount
            HostCount                        = $HostCount
            TotalRows                        = $TotalRows
        }
    } catch { }
}

function Get-SharedSiteInterfaceCacheEntryStatistics {
    param([pscustomobject]$Entry)

    $hostCount = 0
    $totalRows = 0

    if ($Entry) {
        if ($Entry.PSObject.Properties.Name -contains 'HostCount') {
            try { $hostCount = [int]$Entry.HostCount } catch { $hostCount = 0 }
        }
        if ($Entry.PSObject.Properties.Name -contains 'TotalRows') {
            try { $totalRows = [int]$Entry.TotalRows } catch { $totalRows = 0 }
        }
        if ($Entry.PSObject.Properties.Name -contains 'HostMap') {
            $hostMap = $Entry.HostMap
            if ($hostMap -is [System.Collections.IDictionary]) {
                if ($hostCount -le 0) {
                    try { $hostCount = [int]$hostMap.Count } catch { $hostCount = 0 }
                }
                if ($totalRows -le 0) {
                    foreach ($hostEntry in @($hostMap.GetEnumerator())) {
                        $ports = $hostEntry.Value
                        if ($ports -is [System.Collections.IDictionary] -or $ports -is [System.Collections.ICollection]) {
                            try { $totalRows += [int]$ports.Count } catch { }
                        }
                    }
                }
            } elseif ($hostMap -is [System.Collections.IEnumerable]) {
                $enumeratedRows = 0
                $enumeratedHosts = 0
                foreach ($hostEntry in $hostMap) {
                    $hostValue = $null
                    if ($hostEntry -is [System.Collections.DictionaryEntry]) {
                        $hostValue = $hostEntry.Value
                    } else {
                        try { $hostValue = $hostEntry.Value } catch { $hostValue = $null }
                    }
                    $enumeratedHosts++
                    if ($hostValue -is [System.Collections.IDictionary] -or $hostValue -is [System.Collections.ICollection]) {
                        try { $enumeratedRows += [int]$hostValue.Count } catch { }
                    }
                }
                if ($hostCount -le 0 -and $enumeratedHosts -gt 0) {
                    $hostCount = $enumeratedHosts
                }
                if ($totalRows -le 0 -and $enumeratedRows -gt 0) {
                    $totalRows = $enumeratedRows
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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SiteKey,
        [Parameter(Mandatory)][string]$Operation,
        [int]$EntryCount = 0,
        [int]$HostCount = 0,
        [int]$TotalRows = 0,
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

    $processId = 0
    try { $processId = [System.Diagnostics.Process]::GetCurrentProcess().Id } catch { $processId = 0 }

    $threadId = 0
    try { $threadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId } catch { $threadId = 0 }

    try {
        TelemetryModule\Write-StTelemetryEvent -Name 'InterfaceSiteCacheSharedStore' -Payload @{
            Site       = $SiteKey
            Operation  = $Operation
            RunspaceId = $runspaceId
            EntryCount = $EntryCount
            HostCount  = $HostCount
            TotalRows  = $TotalRows
            StoreHashCode = $StoreHashCode
            AppDomainId   = $appDomainId
            AppDomainName = $appDomainName
            ProcessId     = $processId
            ThreadId      = $threadId
        }
    } catch { }
}

function Publish-InterfaceSiteCacheReuseState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SiteKey,
        [Parameter()][psobject]$Entry
    )

    $hostCount = 0
    $totalRows = 0
    $hostMapType = ''
    $keysSample = ''
    $entryType = ''

    if ($Entry) {
        try { $entryType = $Entry.GetType().FullName } catch { $entryType = '' }
        $hostMap = $null
        if ($Entry.PSObject.Properties.Name -contains 'HostMap') {
            $hostMap = $Entry.HostMap
        }

        if ($hostMap) {
            try { $hostMapType = $hostMap.GetType().FullName } catch { $hostMapType = '' }

            if ($hostMap -is [System.Collections.IDictionary]) {
                try { $hostCount = [int]$hostMap.Count } catch { $hostCount = 0 }

                $sampleKeys = New-Object 'System.Collections.Generic.List[string]'
                foreach ($key in @($hostMap.Keys)) {
                    if ($sampleKeys.Count -ge 5) { break }
                    if ($null -eq $key) { continue }
                    $sampleKeys.Add(('' + $key)) | Out-Null

                    $portCollection = $hostMap[$key]
                    if ($portCollection -is [System.Collections.IDictionary] -or $portCollection -is [System.Collections.ICollection]) {
                        try { $totalRows += [int]$portCollection.Count } catch { }
                    }
                }
                if ($sampleKeys.Count -gt 0) {
                    $keysSample = [string]::Join(',', $sampleKeys.ToArray())
                }
            } elseif ($hostMap -is [System.Collections.ICollection]) {
                try { $hostCount = [int]$hostMap.Count } catch { $hostCount = 0 }
            }
        }

        if (($Entry.PSObject.Properties.Name -contains 'TotalRows') -and (-not $totalRows -or $totalRows -le 0)) {
            try { $totalRows = [int]$Entry.TotalRows } catch { }
        }
    }

    try {
        TelemetryModule\Write-StTelemetryEvent -Name 'InterfaceSiteCacheReuseState' -Payload @{
            Site       = $SiteKey
            HostCount  = $hostCount
            TotalRows  = $totalRows
            HostMapType= $hostMapType
            KeysSample = $keysSample
            EntryType  = $entryType
        }
    } catch { }
}

if (-not (Get-Variable -Scope Script -Name TemplateLookupCache -ErrorAction SilentlyContinue)) {
    $script:TemplateLookupCache = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
}
if (-not (Get-Variable -Scope Script -Name TemplateHintCache -ErrorAction SilentlyContinue)) {
    $script:TemplateHintCache = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.Dictionary[string,StateTrace.Models.InterfaceTemplateHint]]' ([System.StringComparer]::OrdinalIgnoreCase)
}
if (-not (Get-Variable -Scope Script -Name InterfaceCacheHydrationTracker -ErrorAction SilentlyContinue)) {
    $script:InterfaceCacheHydrationTracker = @{}
}

function Ensure-InterfaceModuleBridge {
    [CmdletBinding()]
    param()

    $commandName = 'InterfaceModule\New-InterfaceObjectsFromDbRow'
    try {
        if (Get-Command -Name $commandName -ErrorAction SilentlyContinue) { return $true }
    } catch { }

    $interfaceModule = $null
    try { $interfaceModule = Get-Module -Name 'InterfaceModule' -ErrorAction SilentlyContinue } catch { $interfaceModule = $null }
    if ($interfaceModule) {
        try {
            if (Get-Command -Name $commandName -ErrorAction SilentlyContinue) { return $true }
        } catch { }
    }

    $candidatePath = $null
    try {
        $candidatePath = Join-Path $script:ModuleRootPath 'Modules\InterfaceModule.psm1'
    } catch {
        $candidatePath = $null
    }
    if (-not $candidatePath) {
        try {
            $candidatePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'InterfaceModule.psm1'
        } catch {
            $candidatePath = $null
        }
    }

    if (-not ($candidatePath -and (Test-Path -LiteralPath $candidatePath))) { return $false }

    try {
        Import-Module -Name $candidatePath -Global -ErrorAction Stop | Out-Null
    } catch {
        Write-Verbose ("[DeviceRepository] Failed to import InterfaceModule from '{0}': {1}" -f $candidatePath, $_.Exception.Message)
        return $false
    }

    try {
        if (Get-Command -Name $commandName -ErrorAction SilentlyContinue) { return $true }
    } catch { }
    return $false
}

function ConvertTo-InterfacePortRecordsFallback {
    [CmdletBinding()]
    param(
        [Parameter()][object]$Data,
        [Parameter(Mandatory)][string]$Hostname
    )

    $list = New-Object 'System.Collections.Generic.List[object]'
    if (-not $Data) { return $list }

    $rows = @()
    if ($Data -is [System.Data.DataTable]) {
        $rows = @($Data.Rows)
    } elseif ($Data -is [System.Data.DataView]) {
        $rows = @($Data)
    } elseif ($Data -is [System.Collections.IEnumerable] -and -not ($Data -is [string])) {
        if ($Data -is [System.Array]) {
            $rows = $Data
        } else {
            $rows = @($Data)
        }
    } else {
        $rows = @($Data)
    }

    foreach ($row in $rows) {
        if ($null -eq $row) { continue }

        $getValue = {
            param($source, [string]$name)
            if (-not $source) { return '' }
            try {
                if ($source -is [System.Collections.IDictionary]) {
                    if ($source.Contains($name)) {
                        $val = $source[$name]
                        if ($null -eq $val -or $val -eq [System.DBNull]::Value) { return '' }
                        return '' + $val
                    }
                } elseif ($source.PSObject -and $source.PSObject.Properties[$name]) {
                    $val = $source.$name
                    if ($null -eq $val -or $val -eq [System.DBNull]::Value) { return '' }
                    return '' + $val
                }
            } catch {
                return ''
            }
            return ''
        }

        $portValue   = & $getValue $row 'Port'
        $nameValue   = & $getValue $row 'Name'
        $statusValue = & $getValue $row 'Status'
        $vlanValue   = & $getValue $row 'VLAN'
        $duplexValue = & $getValue $row 'Duplex'
        $speedValue  = & $getValue $row 'Speed'
        $typeValue   = & $getValue $row 'Type'
        $learnedValue= & $getValue $row 'LearnedMACs'
        $authState   = & $getValue $row 'AuthState'
        $authMode    = & $getValue $row 'AuthMode'
        $authClient  = & $getValue $row 'AuthClientMAC'
        $authTemplate= & $getValue $row 'AuthTemplate'
        $configValue = & $getValue $row 'Config'
        $cfgStatus   = & $getValue $row 'ConfigStatus'
        $portColor   = & $getValue $row 'PortColor'
        $tooltipValue= & $getValue $row 'ToolTip'

        $portSortKey = '99-UNK-99999-99999-99999-99999-99999'
        try {
            if (Get-Command -Name 'InterfaceModule\Get-PortSortKey' -ErrorAction SilentlyContinue) {
                if (-not [string]::IsNullOrWhiteSpace($portValue)) {
                    $portSortKey = InterfaceModule\Get-PortSortKey -Port $portValue
                }
            }
        } catch { }

        $signatureValues = @(
            $Hostname,
            $portValue,
            $nameValue,
            $statusValue,
            $vlanValue,
            $duplexValue,
            $speedValue,
            $typeValue,
            $learnedValue,
            $authState,
            $authMode,
            $authClient,
            $authTemplate,
            $configValue,
            $cfgStatus,
            $portColor
        )
        $cacheSignature = ConvertTo-InterfaceCacheSignature -Values $signatureValues

        $record = [StateTrace.Models.InterfacePortRecord]::new()
        $record.Hostname      = $Hostname
        $record.Port          = $portValue
        $record.PortSort      = $portSortKey
        $record.Name          = $nameValue
        $record.Status        = $statusValue
        $record.VLAN          = $vlanValue
        $record.Duplex        = $duplexValue
        $record.Speed         = $speedValue
        $record.Type          = $typeValue
        $record.LearnedMACs   = $learnedValue
        $record.AuthState     = $authState
        $record.AuthMode      = $authMode
        $record.AuthClientMAC = $authClient
        $record.AuthTemplate  = $authTemplate
        $record.Config        = $configValue
        $record.ConfigStatus  = $cfgStatus
        $record.PortColor     = $portColor
        $record.ToolTip       = $tooltipValue
        $record.CacheSignature= $cacheSignature
        $record.IsSelected    = $false

        try { $record.Site = '' } catch { }
        try { $record.Building = '' } catch { }
        try { $record.Room = '' } catch { }
        try { $record.Zone = '' } catch { }

        if (-not [string]::IsNullOrWhiteSpace($configValue) -and [string]::IsNullOrWhiteSpace($tooltipValue)) {
            $record.ToolTip = "AuthTemplate: $authTemplate`r`n`r`n$configValue"
        }
        $list.Add($record) | Out-Null
    }

    return $list
}

function script:Get-TemplateLookupForVendor {
    param(
        [Parameter(Mandatory)][string]$Vendor,
        [Parameter(Mandatory)][string]$TemplatesPath
    )

    $vendorKey = if ([string]::IsNullOrWhiteSpace($Vendor)) { 'Cisco' } else { $Vendor }
    $templatesRoot = $TemplatesPath
    try { $templatesRoot = [System.IO.Path]::GetFullPath($TemplatesPath) } catch { }
    $cacheKey = "{0}::{1}" -f $vendorKey, $templatesRoot

    if ($script:TemplateLookupCache.ContainsKey($cacheKey)) {
        return $script:TemplateLookupCache[$cacheKey]
    }

    $lookup = $null
    try {
        $templateData = TemplatesModule\Get-ConfigurationTemplateData -Vendor $vendorKey -TemplatesPath $TemplatesPath
        if ($templateData -and $templateData.Exists -and $templateData.Lookup) {
            $lookup = $templateData.Lookup
        }
    } catch {
        $lookup = $null
    }

    $script:TemplateLookupCache[$cacheKey] = $lookup
    return $lookup
}

function script:Get-TemplateHintCacheForVendor {
    param(
        [Parameter(Mandatory)][string]$Vendor,
        [Parameter(Mandatory)][string]$TemplatesPath
    )

    $vendorKey = if ([string]::IsNullOrWhiteSpace($Vendor)) { 'Cisco' } else { $Vendor }
    $templatesRoot = $TemplatesPath
    try { $templatesRoot = [System.IO.Path]::GetFullPath($TemplatesPath) } catch { }
    $cacheKey = "{0}::{1}" -f $vendorKey, $templatesRoot

    $hintDictionary = $null
    if ($script:TemplateHintCache.TryGetValue($cacheKey, [ref]$hintDictionary)) {
        return $hintDictionary
    }

    $hintDictionary = New-Object 'System.Collections.Generic.Dictionary[string,StateTrace.Models.InterfaceTemplateHint]' ([System.StringComparer]::OrdinalIgnoreCase)
    $script:TemplateHintCache[$cacheKey] = $hintDictionary
    return $hintDictionary
}

function Get-DataDirectoryPath {
    [CmdletBinding()]
    param()
    if (-not (Get-Variable -Scope Script -Name DataDirPath -ErrorAction SilentlyContinue)) {
        if (-not (Get-Variable -Scope Script -Name ModuleRootPath -ErrorAction SilentlyContinue)) {
            try {
                $script:ModuleRootPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
            } catch {
                $script:ModuleRootPath = Split-Path -Parent $PSScriptRoot
            }
        }
        $rootPath = if ($script:ModuleRootPath) { $script:ModuleRootPath } else { Split-Path -Parent $PSScriptRoot }
        $script:DataDirPath = Join-Path $rootPath 'Data'
    }
    return $script:DataDirPath
}

function Get-SiteFromHostname {
    [CmdletBinding()]
    param(
        [string]$Hostname,
        [int]$FallbackLength = 0
    )

    if ([string]::IsNullOrWhiteSpace($Hostname)) { return 'Unknown' }

    $clean = ('' + $Hostname).Trim()
    if ($clean -like 'SSH@*') { $clean = $clean.Substring(4) }
    $clean = $clean.Trim()

    if ($clean -match '^(?<site>[^-]+)-') {
        return $matches['site']
    }

    if ($FallbackLength -gt 0 -and $clean.Length -ge $FallbackLength) {
        return $clean.Substring(0, $FallbackLength)
    }

    return $clean
}


function Get-DbPathForSite {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Site)

    $siteCode = ('' + $Site).Trim()
    if ([string]::IsNullOrWhiteSpace($siteCode)) { $siteCode = 'Unknown' }

    $dataDir = Get-DataDirectoryPath
    $prefix = $siteCode
    $dashIndex = $prefix.IndexOf('-')
    if ($dashIndex -gt 0) { $prefix = $prefix.Substring(0, $dashIndex) }

    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    foreach ($ch in $invalidChars) {
        $prefix = $prefix.Replace([string]$ch, '_')
    }
    if ([string]::IsNullOrWhiteSpace($prefix)) { $prefix = 'Unknown' }

    $modernDir = Join-Path $dataDir $prefix
    $modernPath = Join-Path $modernDir ("{0}.accdb" -f $siteCode)
    $legacyPath = Join-Path $dataDir ("{0}.accdb" -f $siteCode)

    if (Test-Path -LiteralPath $modernPath) { return $modernPath }
    if (Test-Path -LiteralPath $legacyPath) { return $legacyPath }

    return $modernPath
}

function Get-DbPathForHost {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Hostname)
    $site = Get-SiteFromHostname -Hostname $Hostname
    return Get-DbPathForSite -Site $site
}

function Get-AllSiteDbPaths {
    [CmdletBinding()]
    param()
    $dataDir = Get-DataDirectoryPath
    if (-not (Test-Path $dataDir)) { return @() }
    $files = Get-ChildItem -Path $dataDir -Filter '*.accdb' -File -Recurse
    $list = New-Object 'System.Collections.Generic.List[string]'
    foreach ($f in $files) { [void]$list.Add($f.FullName) }
    return $list.ToArray()
}

function Clear-SiteInterfaceCache {
    [CmdletBinding()]
    param(
        [string]$Reason = 'Unspecified'
    )

    $storeKey = $script:SharedSiteInterfaceCacheKey
    $store = Get-SharedSiteInterfaceCacheStore

    $callerFunction = 'Unknown'
    $callerScript = ''
    $callerLine = 0
    $invocationName = ''
    $callStackDepth = 0

    try {
        $stack = @(Get-PSCallStack)
        if ($stack) {
            $callStackDepth = $stack.Count
            foreach ($frame in $stack) {
                if (-not $frame) { continue }
                $frameFunction = ''
                try { $frameFunction = $frame.FunctionName } catch { $frameFunction = '' }
                if ([System.StringComparer]::OrdinalIgnoreCase.Equals($frameFunction, 'Clear-SiteInterfaceCache')) {
                    continue
                }
                if (-not [string]::IsNullOrWhiteSpace($frameFunction)) {
                    $callerFunction = $frameFunction
                }
                $frameScript = ''
                try { $frameScript = $frame.ScriptName } catch { $frameScript = '' }
                if (-not [string]::IsNullOrWhiteSpace($frameScript)) {
                    try { $callerScript = [System.IO.Path]::GetFileName($frameScript) } catch { $callerScript = $frameScript }
                }
                try {
                    if ($frame.ScriptLineNumber -gt 0) {
                        $callerLine = [int]$frame.ScriptLineNumber
                    }
                } catch {
                    $callerLine = 0
                }
                break
            }
        }
    } catch {
        $callStackDepth = 0
    }

    try { $invocationName = '' + $PSCmdlet.MyInvocation.InvocationName } catch { $invocationName = '' }

    Publish-SharedSiteInterfaceCacheClearInvocation -Reason $Reason -CallerFunction $callerFunction -CallerScript $callerScript -CallerLine $callerLine -InvocationName $invocationName -CallStackDepth $callStackDepth

    try {
        $script:SiteInterfaceCache = @{}
    } catch {
        Set-Variable -Name SiteInterfaceCache -Scope Script -Value @{}
    }
    try { 
        $script:SiteInterfaceSignatureCache = @{} 
    } catch { 
        Set-Variable -Name SiteInterfaceSignatureCache -Scope Script -Value @{} 
    } 
    try { 
        $script:InterfaceCacheHydrationTracker = @{} 
    } catch { 
        Set-Variable -Name InterfaceCacheHydrationTracker -Scope Script -Value @{} 
    } 
    $script:LastInterfaceSiteCacheMetrics = $null 

    $targetStore = $script:SharedSiteInterfaceCache
    if (-not ($targetStore -is [System.Collections.Concurrent.ConcurrentDictionary[string, object]])) {
        $targetStore = $store
    }
    $preClearHash = 0
    $preClearCount = 0
    if ($targetStore -is [System.Collections.Concurrent.ConcurrentDictionary[string, object]]) {
        try { $preClearHash = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($targetStore) } catch { $preClearHash = 0 }
        try { $preClearCount = [int]$targetStore.Count } catch { $preClearCount = 0 }
        Publish-SharedSiteInterfaceCacheStoreState -Operation 'ClearRequested' -EntryCount $preClearCount -StoreHashCode $preClearHash
    }

    if ($targetStore -is [System.Collections.Concurrent.ConcurrentDictionary[string, object]]) {
        try { $targetStore.Clear() } catch { }
        $script:SharedSiteInterfaceCache = $targetStore
    } else {
        $script:SharedSiteInterfaceCache = Initialize-SharedSiteInterfaceCacheStore
        if ($script:SharedSiteInterfaceCache -is [System.Collections.Concurrent.ConcurrentDictionary[string, object]]) {
            try { $script:SharedSiteInterfaceCache.Clear() } catch { }
        }
    }

    if ($script:SharedSiteInterfaceCache -is [System.Collections.Concurrent.ConcurrentDictionary[string, object]]) {
        try { [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::SetStore($script:SharedSiteInterfaceCache) } catch { }
        try { [System.AppDomain]::CurrentDomain.SetData($storeKey, $script:SharedSiteInterfaceCache) } catch { }

        $postClearHash = 0
        $postClearCount = 0
        try { $postClearHash = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($script:SharedSiteInterfaceCache) } catch { $postClearHash = 0 }
        try { $postClearCount = [int]$script:SharedSiteInterfaceCache.Count } catch { $postClearCount = 0 }
        Publish-SharedSiteInterfaceCacheStoreState -Operation 'Cleared' -EntryCount $postClearCount -StoreHashCode $postClearHash
    } else {
        try { [StateTrace.Repository.SharedSiteInterfaceCacheHolder]::ClearStore() } catch { }
    }
}

function Get-InterfaceSiteCacheSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Site
    )

    $siteKey = ('' + $Site).Trim()
    if ([string]::IsNullOrWhiteSpace($siteKey)) {
        return [pscustomobject]@{
            Site          = ''
            CacheExists   = $false
            CacheStatus   = ''
            HostCount     = 0
            TotalRows     = 0
            CachedAt      = $null
            HostMapType   = ''
            EntryType     = ''
        }
    }

    $entry = $null
    if ($script:SiteInterfaceSignatureCache -and $script:SiteInterfaceSignatureCache.ContainsKey($siteKey)) {
        $entry = $script:SiteInterfaceSignatureCache[$siteKey]
    }

    $cacheStatus = ''
    $cachedAt = $null
    $hostCount = 0
    $totalRows = 0
    $hostMapType = ''
    $entryType = ''

    if ($entry) {
        if ($entry.PSObject.Properties.Name -contains 'CacheStatus') {
            $cacheStatus = '' + $entry.CacheStatus
        }
        if ($entry.PSObject.Properties.Name -contains 'CachedAt') {
            try { $cachedAt = [datetime]$entry.CachedAt } catch { $cachedAt = $null }
        }
        $entryType = $entry.GetType().FullName

        $hostMap = $null
        if ($entry.PSObject.Properties.Name -contains 'HostMap') {
            $hostMap = $entry.HostMap
        }

        if ($hostMap -is [System.Collections.IDictionary]) {
            $hostCount = $hostMap.Count
            $hostMapType = $hostMap.GetType().FullName
            $calculatedTotal = 0
            foreach ($hostEntry in @($hostMap.GetEnumerator())) {
                $portMap = $hostEntry.Value
                if ($portMap -is [System.Collections.IDictionary] -or $portMap -is [System.Collections.ICollection]) {
                    try { $calculatedTotal += $portMap.Count } catch { }
                }
            }
            $totalRows = $calculatedTotal
        } elseif ($hostMap) {
            $hostMapType = $hostMap.GetType().FullName
        }

        if ($entry.PSObject.Properties.Name -contains 'HostCount') {
            try {
                $hostCount = [int]$entry.HostCount
            } catch { }
        }

        if ($entry.PSObject.Properties.Name -contains 'TotalRows') {
            try {
                $totalRows = [int]$entry.TotalRows
            } catch { }
        }
    }

    return [pscustomobject]@{
        Site        = $siteKey
        CacheExists = [bool]$entry
        CacheStatus = $cacheStatus
        HostCount   = $hostCount
        TotalRows   = $totalRows
        CachedAt    = $cachedAt
        HostMapType = $hostMapType
        EntryType   = $entryType
    }
}

function Test-IsAdodbConnectionInternal {
    [CmdletBinding()]
    param([Parameter()][object]$Connection)

    if ($null -eq $Connection) { return $false }
    if ($Connection -is [System.__ComObject]) { return $true }
    try {
        foreach ($name in $Connection.PSObject.TypeNames) {
            if ($name -eq 'ADODB.Connection') { return $true }
        }
    } catch { }
    return $false
}

function Invoke-WithAccessExclusiveRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Context,
        [Parameter(Mandatory)][ScriptBlock]$Operation,
        [int]$MaxAttempts = 5,
        [int]$RetryDelayMilliseconds = 100,
        [ref]$TelemetrySink
    )

    $attempt = 0
    $exclusiveRetryCount = 0
    $totalWaitMilliseconds = 0.0
    $operationStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($attempt -lt $MaxAttempts) {
        try {
            $result = & $Operation
            if ($operationStopwatch.IsRunning) { $operationStopwatch.Stop() }
            if ($TelemetrySink) {
                $TelemetrySink.Value = [PSCustomObject]@{
                    Attempts                = $attempt + 1
                    ExclusiveRetries        = $exclusiveRetryCount
                    ExclusiveWaitDurationMs = [Math]::Round($totalWaitMilliseconds, 3)
                    DurationMs              = [Math]::Round($operationStopwatch.Elapsed.TotalMilliseconds, 3)
                    Succeeded               = $true
                }
            }
            return $result
        } catch {
            $attempt++
            $message = $_.Exception.Message
            $hresultText = $null
            try { $hresultText = ('0x{0:X8}' -f $_.Exception.HResult) } catch { $hresultText = $null }

            $isExclusiveLock = $false
            if ($message -and $message -match 'already opened exclusively') {
                $isExclusiveLock = $true
            }

            if ($isExclusiveLock -and $attempt -lt $MaxAttempts) {
                $delay = [Math]::Min(500, $RetryDelayMilliseconds * $attempt)
                $totalWaitMilliseconds += $delay
                $exclusiveRetryCount++
                Start-Sleep -Milliseconds $delay
                continue
            }

            if ($TelemetrySink) {
                if ($operationStopwatch.IsRunning) { $operationStopwatch.Stop() }
                $TelemetrySink.Value = [PSCustomObject]@{
                    Attempts                = $attempt
                    ExclusiveRetries        = $exclusiveRetryCount
                    ExclusiveWaitDurationMs = [Math]::Round($totalWaitMilliseconds, 3)
                    DurationMs              = [Math]::Round($operationStopwatch.Elapsed.TotalMilliseconds, 3)
                    Succeeded               = $false
                    Message                 = $message
                    Context                 = $Context
                }
            }

            $detailParts = @()
            if ($message) { $detailParts += $message }
            if ($hresultText) { $detailParts += "HRESULT=$hresultText" }
            $detailText = if ($detailParts.Count -gt 0) { [string]::Join(' ; ', $detailParts) } else { 'No diagnostic details available.' }
            Write-Warning ("{0}: {1}" -f $Context, $detailText)
            break
        }
    }

    if ($TelemetrySink -and -not $TelemetrySink.Value) {
        if ($operationStopwatch.IsRunning) { $operationStopwatch.Stop() }
        $TelemetrySink.Value = [PSCustomObject]@{
            Attempts                = $attempt
            ExclusiveRetries        = $exclusiveRetryCount
            ExclusiveWaitDurationMs = [Math]::Round($totalWaitMilliseconds, 3)
            DurationMs              = [Math]::Round($operationStopwatch.Elapsed.TotalMilliseconds, 3)
            Succeeded               = $false
        }
    }

    return $null
}

function ConvertTo-InterfaceCacheSignature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IEnumerable]$Values
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
        [void]$builder.Append($text)
    }

    return $builder.ToString()
}

function ConvertTo-InterfaceCacheEntryObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$InputObject
    )

    if ($null -eq $InputObject) { return $null }

    if ($InputObject -is [StateTrace.Models.InterfaceCacheEntry]) {
        return $InputObject
    }

    $getRawValue = {
        param(
            [object]$Source,
            [string[]]$CandidateNames
        )

        if ($null -eq $Source) { return $null }

        foreach ($candidate in $CandidateNames) {
            if ([string]::IsNullOrWhiteSpace($candidate)) { continue }

            if ($Source -is [System.Collections.IDictionary]) {
                if ($Source.Contains($candidate)) {
                    return $Source[$candidate]
                }
            }

            $psObject = $null
            try { $psObject = $Source.PSObject } catch { $psObject = $null }
            if ($psObject) {
                $prop = $psObject.Properties[$candidate]
                if ($prop) { return $prop.Value }
            }

            try {
                $propertyInfo = $Source.GetType().GetProperty($candidate)
                if ($propertyInfo -and $propertyInfo.CanRead) {
                    return $propertyInfo.GetValue($Source, $null)
                }
            } catch { }
        }

        return $null
    }

    $toString = {
        param($Value)
        if ($null -eq $Value -or $Value -eq [System.DBNull]::Value) { return '' }
        return '' + $Value
    }

    $nameValue = & $toString (& $getRawValue $InputObject @('Name'))
    $statusValue = & $toString (& $getRawValue $InputObject @('Status'))
    $vlanValue = & $toString (& $getRawValue $InputObject @('VLAN', 'Vlan'))
    $duplexValue = & $toString (& $getRawValue $InputObject @('Duplex'))
    $speedValue = & $toString (& $getRawValue $InputObject @('Speed'))
    $typeValue = & $toString (& $getRawValue $InputObject @('Type'))

    $rawLearned = & $getRawValue $InputObject @('Learned', 'LearnedMACs')
    if ($null -eq $rawLearned -or $rawLearned -eq [System.DBNull]::Value) {
        $learnedValue = ''
    } elseif ($rawLearned -is [string]) {
        $learnedValue = $rawLearned
    } elseif ($rawLearned -is [System.Collections.IEnumerable] -and -not ($rawLearned -is [string])) {
        $macList = New-Object 'System.Collections.Generic.List[string]'
        foreach ($mac in $rawLearned) {
            if ($mac) { $macList.Add(('' + $mac)) | Out-Null }
        }
        $learnedValue = [string]::Join(',', $macList.ToArray())
    } else {
        $learnedValue = '' + $rawLearned
    }

    $authStateValue = & $toString (& $getRawValue $InputObject @('AuthState'))
    $authModeValue = & $toString (& $getRawValue $InputObject @('AuthMode'))
    $authClientValue = & $toString (& $getRawValue $InputObject @('AuthClient', 'AuthClientMAC', 'AuthClientMac'))
    $templateValue = & $toString (& $getRawValue $InputObject @('Template', 'AuthTemplate'))
    $configValue = & $toString (& $getRawValue $InputObject @('Config'))
    $portSortValue = & $toString (& $getRawValue $InputObject @('PortSort'))
    if ([string]::IsNullOrWhiteSpace($portSortValue)) {
        $portSortValue = '99-UNK-99999-99999-99999-99999-99999'
        if (-not [string]::IsNullOrWhiteSpace($nameValue)) {
            $getPortSortCommand = $null
            try { $getPortSortCommand = Get-Command -Name 'InterfaceModule\Get-PortSortKey' -ErrorAction SilentlyContinue } catch { $getPortSortCommand = $null }
            if ($getPortSortCommand) {
                try {
                    $computedPortSort = InterfaceModule\Get-PortSortKey -Port $nameValue
                    if (-not [string]::IsNullOrWhiteSpace($computedPortSort)) {
                        $portSortValue = $computedPortSort
                    }
                } catch {
                    # fall back to the default PortSort placeholder when the computation fails
                }
            }
        }
    }
    $portColorValue = & $toString (& $getRawValue $InputObject @('PortColor'))
    $statusTagValue = & $toString (& $getRawValue $InputObject @('StatusTag', 'ConfigStatus'))
    $toolTipValue = & $toString (& $getRawValue $InputObject @('ToolTip'))

    $signatureValue = $null
    $rawSignature = & $getRawValue $InputObject @('Signature', 'CacheSignature')
    if ($null -ne $rawSignature -and $rawSignature -ne [System.DBNull]::Value) {
        $signatureValue = '' + $rawSignature
    }
    if ([string]::IsNullOrWhiteSpace($signatureValue)) {
        $signatureValue = ConvertTo-InterfaceCacheSignature -Values @(
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
    }

    $entry = [StateTrace.Models.InterfaceCacheEntry]::new()
    $entry.Name = $nameValue
    $entry.Status = $statusValue
    $entry.VLAN = $vlanValue
    $entry.Duplex = $duplexValue
    $entry.Speed = $speedValue
    $entry.Type = $typeValue
    $entry.Learned = $learnedValue
    $entry.AuthState = $authStateValue
    $entry.AuthMode = $authModeValue
    $entry.AuthClient = $authClientValue
    $entry.Template = $templateValue
    $entry.Config = $configValue
    $entry.PortSort = $portSortValue
    $entry.PortColor = $portColorValue
    $entry.StatusTag = $statusTagValue
    $entry.ToolTip = $toolTipValue
    $entry.Signature = $signatureValue

    return $entry
}

function Get-InterfaceSiteCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Site,
        [switch]$Refresh,
        [object]$Connection
    )

    $siteKey = ('' + $Site).Trim()
    if ([string]::IsNullOrWhiteSpace($siteKey)) {
        $script:LastInterfaceSiteCacheMetrics = $null
        return $null
    }

    $metrics = [pscustomobject]@{
        Site                     = $siteKey
        CacheStatus              = 'Unknown'
        Refreshed                = [bool]$Refresh
        HydrationDurationMs      = 0.0
        HydrationSnapshotMs      = 0.0
        HydrationSnapshotRecordsetDurationMs = 0.0
        HydrationSnapshotProjectDurationMs = 0.0
        HydrationBuildMs         = 0.0
        HydrationHostMapDurationMs = 0.0
        HydrationHostMapSignatureMatchCount   = 0L
        HydrationHostMapSignatureRewriteCount = 0L
        HydrationHostMapEntryAllocationCount  = 0L
        HydrationHostMapEntryPoolReuseCount   = 0L
        HydrationSortDurationMs   = 0.0
        HydrationQueryDurationMs      = 0.0
        HydrationExecuteDurationMs    = 0.0
        HydrationHostMapLookupCount             = 0L
        HydrationHostMapLookupMissCount         = 0L
        HydrationHostMapCandidateMissingCount   = 0L
        HydrationHostMapCandidateSignatureMissingCount = 0L
        HydrationHostMapCandidateSignatureMismatchCount = 0L
        HydrationHostMapCandidateFromPreviousCount      = 0L
        HydrationHostMapCandidateFromPoolCount          = 0L
        HydrationHostMapCandidateInvalidCount           = 0L
        HydrationHostMapSignatureMismatchSamples        = @()
        HydrationHostMapCandidateMissingSamples         = @()
        HydrationPreviousHostCount        = 0
        HydrationPreviousPortCount        = 0
        HydrationPreviousHostSample       = ''
        HydrationPreviousSnapshotStatus      = 'CacheEntryMissing'
        HydrationPreviousSnapshotHostMapType = ''
        HydrationPreviousSnapshotHostCount   = 0
        HydrationPreviousSnapshotPortCount   = 0
        HydrationPreviousSnapshotException   = ''
        HydrationMaterializeDurationMs= 0.0
        HydrationMaterializeProjectionDurationMs = 0.0
        HydrationMaterializePortSortDurationMs   = 0.0
        HydrationMaterializePortSortCacheHits    = 0
        HydrationMaterializePortSortCacheMisses  = 0
        HydrationMaterializePortSortCacheSize    = 0
        HydrationMaterializePortSortUniquePortCount = 0
        HydrationMaterializePortSortMissSamples   = @()
        HydrationMaterializeTemplateDurationMs   = 0.0
        HydrationMaterializeTemplateLookupDurationMs = 0.0
        HydrationMaterializeTemplateApplyDurationMs = 0.0
        HydrationMaterializeObjectDurationMs     = 0.0
        HydrationMaterializeTemplateCacheHitCount = 0
        HydrationMaterializeTemplateCacheMissCount = 0
        HydrationMaterializeTemplateReuseCount    = 0
        HydrationMaterializeTemplateApplyCount = 0
        HydrationMaterializeTemplateDefaultedCount = 0
        HydrationMaterializeTemplateAuthTemplateMissingCount = 0
        HydrationMaterializeTemplateNoTemplateMatchCount = 0
        HydrationMaterializeTemplateHintAppliedCount = 0
        HydrationMaterializeTemplateSetPortColorCount = 0
        HydrationMaterializeTemplateSetConfigStatusCount = 0
        HydrationMaterializeTemplateApplySamples = @()
        HydrationTemplateDurationMs   = 0.0
        HydrationQueryAttempts        = 0
        HydrationExclusiveRetryCount  = 0
        HydrationExclusiveWaitDurationMs = 0.0
        HydrationProvider             = 'Unknown'
        HydrationResultRowCount       = 0
        HostCount                = 0
        TotalRows                = 0
        CachedAt                 = $null
        Timestamp                = Get-Date
    }
    $hydrationDetail = $null
    $previousSignatureEntry = $null
    $scriptCacheEntryFound = $false
    $scriptCacheStats = $null
    if ($script:SiteInterfaceSignatureCache -and $script:SiteInterfaceSignatureCache.ContainsKey($siteKey)) {
        $scriptCacheEntryFound = $true
        try {
            $scriptCacheCandidate = $script:SiteInterfaceSignatureCache[$siteKey]
            if ($scriptCacheCandidate) {
                $scriptCacheStats = Get-SharedSiteInterfaceCacheEntryStatistics -Entry $scriptCacheCandidate
                $previousSignatureEntry = $scriptCacheCandidate
            }
        } catch {
            $scriptCacheStats = $null
            try { $previousSignatureEntry = $script:SiteInterfaceSignatureCache[$siteKey] } catch { $previousSignatureEntry = $null }
        }
    }
    $sharedStoreEntryFound = $false
    $sharedStoreStats = $null
    $adoptedFromSharedStore = $false
    $sharedEntry = $null
    try {
        $sharedEntry = Get-SharedSiteInterfaceCacheEntry -SiteKey $siteKey
    } catch {
        $sharedEntry = $null
    }
    if ($sharedEntry) {
        $sharedStoreEntryFound = $true
        try { $sharedStoreStats = Get-SharedSiteInterfaceCacheEntryStatistics -Entry $sharedEntry } catch { $sharedStoreStats = $null }
        if (-not ($sharedEntry.PSObject.Properties.Name -contains 'CacheStatus')) {
            $sharedEntry | Add-Member -NotePropertyName 'CacheStatus' -NotePropertyValue 'SharedOnly' -Force
        } elseif ([string]::IsNullOrWhiteSpace(('' + $sharedEntry.CacheStatus))) {
            $sharedEntry.CacheStatus = 'SharedOnly'
        }
        $script:SiteInterfaceSignatureCache[$siteKey] = $sharedEntry
        $previousSignatureEntry = $sharedEntry
        $adoptedFromSharedStore = $true
        $scriptCacheEntryFound = $true
        if ($sharedStoreStats) {
            $scriptCacheStats = $sharedStoreStats
        } else {
            $scriptCacheStats = $null
        }
    }
    try {
        $reusePayload = @{
            Site                     = $siteKey
            Refresh                  = [bool]$Refresh
            ScriptCacheEntryFound    = $scriptCacheEntryFound
            SharedStoreEntryFound    = $sharedStoreEntryFound
            AdoptedFromSharedStore   = $adoptedFromSharedStore
        }
        $currentRunspace = $null
        try { $currentRunspace = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace } catch { $currentRunspace = $null }
        if ($currentRunspace) {
            try { $reusePayload.RunspaceId = $currentRunspace.InstanceId.ToString() } catch { }
        }
        if ($scriptCacheStats) {
            $reusePayload.ScriptCacheHostCount  = [int]$scriptCacheStats.HostCount
            $reusePayload.ScriptCacheTotalRows  = [int]$scriptCacheStats.TotalRows
        }
        if ($sharedStoreStats) {
            $reusePayload.SharedStoreHostCount  = [int]$sharedStoreStats.HostCount
            $reusePayload.SharedStoreTotalRows  = [int]$sharedStoreStats.TotalRows
        }
        TelemetryModule\Write-StTelemetryEvent -Name 'InterfaceSiteCacheReuseAttempt' -Payload $reusePayload
    } catch { }

    $previousSnapshotStatus = 'CacheEntryMissing'
    $previousSnapshotHostMapType = ''
    $previousSnapshotHostCount = 0
    $previousSnapshotPortCount = 0
    $previousSnapshotException = ''

    if (-not $Refresh -and $previousSignatureEntry) {
        $cachedEntry = $previousSignatureEntry
        $cacheStatusForReuse = $null
        if ($cachedEntry -and $cachedEntry.PSObject.Properties.Name -contains 'CacheStatus') {
            $cacheStatusForReuse = ('' + $cachedEntry.CacheStatus).Trim()
        }
        if ([string]::IsNullOrWhiteSpace($cacheStatusForReuse)) {
            if ($adoptedFromSharedStore) {
                $cacheStatusForReuse = 'SharedOnly'
            } else {
                $cacheStatusForReuse = 'Hit'
            }
        }
        if ($cachedEntry) {
            $metrics.CacheStatus = $cacheStatusForReuse
            $metrics.HydrationProvider = 'Cache'
            if ($cachedEntry.PSObject.Properties.Name -contains 'TotalRows') {
                $metrics.TotalRows = [int]$cachedEntry.TotalRows
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HostMap') {
                $hostMapRef = $cachedEntry.HostMap
                if ($hostMapRef -is [System.Collections.IDictionary]) {
                    $metrics.HostCount = $hostMapRef.Count
                }
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationDurationMs') {
                $metrics.HydrationDurationMs = [double]$cachedEntry.HydrationDurationMs
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationSnapshotDurationMs') {
                $metrics.HydrationSnapshotMs = [double]$cachedEntry.HydrationSnapshotDurationMs
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationSnapshotRecordsetDurationMs') {
                $metrics.HydrationSnapshotRecordsetDurationMs = [double]$cachedEntry.HydrationSnapshotRecordsetDurationMs
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationSnapshotProjectDurationMs') {
                $metrics.HydrationSnapshotProjectDurationMs = [double]$cachedEntry.HydrationSnapshotProjectDurationMs
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationBuildDurationMs') {
                $metrics.HydrationBuildMs = [double]$cachedEntry.HydrationBuildDurationMs
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationHostMapDurationMs') {
                $metrics.HydrationHostMapDurationMs = [double]$cachedEntry.HydrationHostMapDurationMs
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationHostMapSignatureMatchCount') {
                $metrics.HydrationHostMapSignatureMatchCount = [long]$cachedEntry.HydrationHostMapSignatureMatchCount
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationHostMapSignatureRewriteCount') {
                $metrics.HydrationHostMapSignatureRewriteCount = [long]$cachedEntry.HydrationHostMapSignatureRewriteCount
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationHostMapEntryAllocationCount') {
                $metrics.HydrationHostMapEntryAllocationCount = [long]$cachedEntry.HydrationHostMapEntryAllocationCount
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationHostMapEntryPoolReuseCount') {
                $metrics.HydrationHostMapEntryPoolReuseCount = [long]$cachedEntry.HydrationHostMapEntryPoolReuseCount
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationHostMapLookupCount') {
                $metrics.HydrationHostMapLookupCount = [long]$cachedEntry.HydrationHostMapLookupCount
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationHostMapLookupMissCount') {
                $metrics.HydrationHostMapLookupMissCount = [long]$cachedEntry.HydrationHostMapLookupMissCount
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationHostMapCandidateMissingCount') {
                $metrics.HydrationHostMapCandidateMissingCount = [long]$cachedEntry.HydrationHostMapCandidateMissingCount
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationHostMapCandidateSignatureMissingCount') {
                $metrics.HydrationHostMapCandidateSignatureMissingCount = [long]$cachedEntry.HydrationHostMapCandidateSignatureMissingCount
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationHostMapCandidateSignatureMismatchCount') {
                $metrics.HydrationHostMapCandidateSignatureMismatchCount = [long]$cachedEntry.HydrationHostMapCandidateSignatureMismatchCount
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationHostMapCandidateFromPreviousCount') {
                $metrics.HydrationHostMapCandidateFromPreviousCount = [long]$cachedEntry.HydrationHostMapCandidateFromPreviousCount
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationHostMapCandidateFromPoolCount') {
                $metrics.HydrationHostMapCandidateFromPoolCount = [long]$cachedEntry.HydrationHostMapCandidateFromPoolCount
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationHostMapCandidateInvalidCount') {
                $metrics.HydrationHostMapCandidateInvalidCount = [long]$cachedEntry.HydrationHostMapCandidateInvalidCount
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationSortDurationMs') {
                $metrics.HydrationSortDurationMs = [double]$cachedEntry.HydrationSortDurationMs
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationQueryDurationMs') {
                $metrics.HydrationQueryDurationMs = [double]$cachedEntry.HydrationQueryDurationMs
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationExecuteDurationMs') {
                $metrics.HydrationExecuteDurationMs = [double]$cachedEntry.HydrationExecuteDurationMs
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationMaterializeDurationMs') {
                $metrics.HydrationMaterializeDurationMs = [double]$cachedEntry.HydrationMaterializeDurationMs
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationMaterializeProjectionDurationMs') {
                $metrics.HydrationMaterializeProjectionDurationMs = [double]$cachedEntry.HydrationMaterializeProjectionDurationMs
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationMaterializePortSortDurationMs') {
                $metrics.HydrationMaterializePortSortDurationMs = [double]$cachedEntry.HydrationMaterializePortSortDurationMs
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationMaterializePortSortCacheHits') {
                $metrics.HydrationMaterializePortSortCacheHits = [long]$cachedEntry.HydrationMaterializePortSortCacheHits
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationMaterializePortSortCacheMisses') {
                $metrics.HydrationMaterializePortSortCacheMisses = [long]$cachedEntry.HydrationMaterializePortSortCacheMisses
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationMaterializePortSortCacheSize') {
                $metrics.HydrationMaterializePortSortCacheSize = [long]$cachedEntry.HydrationMaterializePortSortCacheSize
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationMaterializePortSortUniquePortCount') {
                $metrics.HydrationMaterializePortSortUniquePortCount = [long]$cachedEntry.HydrationMaterializePortSortUniquePortCount
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationMaterializePortSortMissSamples') {
                $metrics.HydrationMaterializePortSortMissSamples = @($cachedEntry.HydrationMaterializePortSortMissSamples)
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateDurationMs') {
                $metrics.HydrationMaterializeTemplateDurationMs = [double]$cachedEntry.HydrationMaterializeTemplateDurationMs
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateLookupDurationMs') {
                $metrics.HydrationMaterializeTemplateLookupDurationMs = [double]$cachedEntry.HydrationMaterializeTemplateLookupDurationMs
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateApplyDurationMs') {
                $metrics.HydrationMaterializeTemplateApplyDurationMs = [double]$cachedEntry.HydrationMaterializeTemplateApplyDurationMs
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationMaterializeObjectDurationMs') {
                $metrics.HydrationMaterializeObjectDurationMs = [double]$cachedEntry.HydrationMaterializeObjectDurationMs
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateCacheHitCount') {
                $metrics.HydrationMaterializeTemplateCacheHitCount = [long]$cachedEntry.HydrationMaterializeTemplateCacheHitCount
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateCacheMissCount') {
                $metrics.HydrationMaterializeTemplateCacheMissCount = [long]$cachedEntry.HydrationMaterializeTemplateCacheMissCount
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateReuseCount') {
                $metrics.HydrationMaterializeTemplateReuseCount = [long]$cachedEntry.HydrationMaterializeTemplateReuseCount
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateApplyCount') {
                $metrics.HydrationMaterializeTemplateApplyCount = [long]$cachedEntry.HydrationMaterializeTemplateApplyCount
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateDefaultedCount') {
                $metrics.HydrationMaterializeTemplateDefaultedCount = [long]$cachedEntry.HydrationMaterializeTemplateDefaultedCount
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateAuthTemplateMissingCount') {
                $metrics.HydrationMaterializeTemplateAuthTemplateMissingCount = [long]$cachedEntry.HydrationMaterializeTemplateAuthTemplateMissingCount
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateNoTemplateMatchCount') {
                $metrics.HydrationMaterializeTemplateNoTemplateMatchCount = [long]$cachedEntry.HydrationMaterializeTemplateNoTemplateMatchCount
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateHintAppliedCount') {
                $metrics.HydrationMaterializeTemplateHintAppliedCount = [long]$cachedEntry.HydrationMaterializeTemplateHintAppliedCount
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateSetPortColorCount') {
                $metrics.HydrationMaterializeTemplateSetPortColorCount = [long]$cachedEntry.HydrationMaterializeTemplateSetPortColorCount
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateSetConfigStatusCount') {
                $metrics.HydrationMaterializeTemplateSetConfigStatusCount = [long]$cachedEntry.HydrationMaterializeTemplateSetConfigStatusCount
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationMaterializeTemplateApplySamples') {
                $metrics.HydrationMaterializeTemplateApplySamples = @($cachedEntry.HydrationMaterializeTemplateApplySamples)
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationTemplateDurationMs') {
                $metrics.HydrationTemplateDurationMs = [double]$cachedEntry.HydrationTemplateDurationMs
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationQueryAttempts') {
                $metrics.HydrationQueryAttempts = [int]$cachedEntry.HydrationQueryAttempts
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationExclusiveRetryCount') {
                $metrics.HydrationExclusiveRetryCount = [int]$cachedEntry.HydrationExclusiveRetryCount
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationExclusiveWaitDurationMs') {
                $metrics.HydrationExclusiveWaitDurationMs = [double]$cachedEntry.HydrationExclusiveWaitDurationMs
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationProvider') {
                $providerValue = '' + $cachedEntry.HydrationProvider
                if (-not [string]::IsNullOrWhiteSpace($providerValue)) {
                    $metrics.HydrationProvider = $providerValue
                }
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationHostMapSignatureMismatchSamples') {
                $samplesValue = $cachedEntry.HydrationHostMapSignatureMismatchSamples
                if ($null -ne $samplesValue) {
                    if ($samplesValue -is [System.Collections.IEnumerable] -and -not ($samplesValue -is [string])) {
                        $sampleList = New-Object 'System.Collections.Generic.List[object]'
                        foreach ($sample in $samplesValue) {
                            $sampleList.Add($sample) | Out-Null
                        }
                        $metrics.HydrationHostMapSignatureMismatchSamples = @($sampleList.ToArray())
                    } else {
                        $metrics.HydrationHostMapSignatureMismatchSamples = @($samplesValue)
                    }
                } else {
                    $metrics.HydrationHostMapSignatureMismatchSamples = @()
                }
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationHostMapCandidateMissingSamples') {
                $samplesValue = $cachedEntry.HydrationHostMapCandidateMissingSamples
                if ($null -ne $samplesValue) {
                    if ($samplesValue -is [System.Collections.IEnumerable] -and -not ($samplesValue -is [string])) {
                        $sampleList = New-Object 'System.Collections.Generic.List[object]'
                        foreach ($sample in $samplesValue) {
                            $sampleList.Add($sample) | Out-Null
                        }
                        $metrics.HydrationHostMapCandidateMissingSamples = @($sampleList.ToArray())
                    } else {
                        $metrics.HydrationHostMapCandidateMissingSamples = @($samplesValue)
                    }
                } else {
                    $metrics.HydrationHostMapCandidateMissingSamples = @()
                }
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationPreviousHostCount') {
                try { $metrics.HydrationPreviousHostCount = [int]$cachedEntry.HydrationPreviousHostCount } catch { $metrics.HydrationPreviousHostCount = 0 }
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationPreviousPortCount') {
                try { $metrics.HydrationPreviousPortCount = [int]$cachedEntry.HydrationPreviousPortCount } catch { $metrics.HydrationPreviousPortCount = 0 }
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationPreviousHostSample') {
                $metrics.HydrationPreviousHostSample = '' + $cachedEntry.HydrationPreviousHostSample
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationPreviousSnapshotStatus') {
                $metrics.HydrationPreviousSnapshotStatus = '' + $cachedEntry.HydrationPreviousSnapshotStatus
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationPreviousSnapshotHostMapType') {
                $metrics.HydrationPreviousSnapshotHostMapType = '' + $cachedEntry.HydrationPreviousSnapshotHostMapType
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationPreviousSnapshotHostCount') {
                try { $metrics.HydrationPreviousSnapshotHostCount = [int]$cachedEntry.HydrationPreviousSnapshotHostCount } catch { $metrics.HydrationPreviousSnapshotHostCount = 0 }
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationPreviousSnapshotPortCount') {
                try { $metrics.HydrationPreviousSnapshotPortCount = [int]$cachedEntry.HydrationPreviousSnapshotPortCount } catch { $metrics.HydrationPreviousSnapshotPortCount = 0 }
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationPreviousSnapshotException') {
                $metrics.HydrationPreviousSnapshotException = '' + $cachedEntry.HydrationPreviousSnapshotException
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'HydrationResultRowCount') {
                $metrics.HydrationResultRowCount = [int]$cachedEntry.HydrationResultRowCount
            }
            if ($cachedEntry.PSObject.Properties.Name -contains 'CachedAt') {
                $metrics.CachedAt = $cachedEntry.CachedAt
            }
        } else {
            $metrics.CacheStatus = $cacheStatusForReuse
            $metrics.HydrationProvider = 'Cache'
        }

        $reuseHostCount = 0
        $reusePortCount = 0
        $reuseHostSampleValues = New-Object 'System.Collections.Generic.List[string]'
        $cachedHostMap = $null
        $cachedHostMapType = ''
        if ($cachedEntry -and $cachedEntry.PSObject.Properties.Name -contains 'HostMap') {
            $cachedHostMap = $cachedEntry.HostMap
        }
        if ($cachedHostMap) {
            try { $cachedHostMapType = '' + $cachedHostMap.GetType().FullName } catch { $cachedHostMapType = '' }
        }
        if ($cachedHostMap -is [System.Collections.IDictionary]) {
            foreach ($hostKeyCandidate in @($cachedHostMap.Keys)) {
                $normalizedHostKey = if ($hostKeyCandidate) { ('' + $hostKeyCandidate).Trim() } else { '' }
                if ([string]::IsNullOrWhiteSpace($normalizedHostKey)) { continue }
                if ($reuseHostSampleValues.Count -lt 5) {
                    $reuseHostSampleValues.Add($normalizedHostKey) | Out-Null
                }
                $reuseHostCount++
                $portEntries = $cachedHostMap[$hostKeyCandidate]
                if ($portEntries -is [System.Collections.IDictionary]) {
                    try { $reusePortCount += [int]$portEntries.Count } catch { }
                } elseif ($portEntries -is [System.Collections.ICollection]) {
                    try { $reusePortCount += [int]$portEntries.Count } catch { }
                }
            }
        } elseif ($cachedHostMap -is [System.Collections.ICollection]) {
            foreach ($entry in $cachedHostMap) {
                if ($entry) { $reusePortCount++ }
            }
        }

        if ($reusePortCount -le 0 -and $cachedEntry -and $cachedEntry.PSObject.Properties.Name -contains 'TotalRows') {
            try { $reusePortCount = [int][Math]::Max(0, $cachedEntry.TotalRows) } catch { $reusePortCount = 0 }
        }
        if ($reuseHostCount -le 0 -and $cachedEntry -and $cachedEntry.PSObject.Properties.Name -contains 'HostCount') {
            try { $reuseHostCount = [int][Math]::Max(0, $cachedEntry.HostCount) } catch { }
        }
        if ($reuseHostCount -le 0 -and $metrics.HostCount -gt 0) {
            $reuseHostCount = [int][Math]::Max(0, $metrics.HostCount)
        }
        if ($reuseHostCount -gt 0 -and ([int]$metrics.HostCount) -lt $reuseHostCount) {
            $metrics.HostCount = $reuseHostCount
        }
        if ($reusePortCount -gt 0 -and ([int]$metrics.TotalRows) -lt $reusePortCount) {
            $metrics.TotalRows = $reusePortCount
        }

        $metrics.CacheStatus = $cacheStatusForReuse
        $metrics.HydrationProvider = 'Cache'
        $metrics.HydrationDurationMs = 0.0
        $metrics.HydrationSnapshotMs = 0.0
        $metrics.HydrationSnapshotRecordsetDurationMs = 0.0
        $metrics.HydrationSnapshotProjectDurationMs = 0.0
        $metrics.HydrationBuildMs = 0.0
        $metrics.HydrationHostMapDurationMs = 0.0
        $metrics.HydrationHostMapSignatureMatchCount = [long][Math]::Max(0, $reusePortCount)
        $metrics.HydrationHostMapSignatureRewriteCount = 0L
        $metrics.HydrationHostMapEntryAllocationCount = 0L
        $metrics.HydrationHostMapEntryPoolReuseCount = 0L
        $metrics.HydrationHostMapLookupCount = [long][Math]::Max(0, $reusePortCount)
        $metrics.HydrationHostMapLookupMissCount = 0L
        $metrics.HydrationHostMapCandidateMissingCount = 0L
        $metrics.HydrationHostMapCandidateSignatureMissingCount = 0L
        $metrics.HydrationHostMapCandidateSignatureMismatchCount = 0L
        $metrics.HydrationHostMapCandidateFromPreviousCount = [long][Math]::Max(0, $reusePortCount)
        $metrics.HydrationHostMapCandidateFromPoolCount = 0L
        $metrics.HydrationHostMapCandidateInvalidCount = 0L
        $metrics.HydrationHostMapCandidateMissingSamples = @()
        $metrics.HydrationHostMapSignatureMismatchSamples = @()
        $metrics.HydrationSortDurationMs = 0.0
        $metrics.HydrationQueryDurationMs = 0.0
        $metrics.HydrationExecuteDurationMs = 0.0
        $metrics.HydrationMaterializeDurationMs = 0.0
        $metrics.HydrationMaterializeProjectionDurationMs = 0.0
        $metrics.HydrationMaterializePortSortDurationMs = 0.0
        $metrics.HydrationMaterializePortSortCacheHits = 0L
        $metrics.HydrationMaterializePortSortCacheMisses = 0L
        $metrics.HydrationMaterializePortSortCacheSize = 0L
        $metrics.HydrationMaterializePortSortUniquePortCount = 0L
        $metrics.HydrationMaterializePortSortMissSamples = @()
        $metrics.HydrationMaterializeTemplateDurationMs = 0.0
        $metrics.HydrationMaterializeTemplateLookupDurationMs = 0.0
        $metrics.HydrationMaterializeTemplateApplyDurationMs = 0.0
        $metrics.HydrationMaterializeObjectDurationMs = 0.0
        $metrics.HydrationMaterializeTemplateCacheHitCount = 0L
        $metrics.HydrationMaterializeTemplateCacheMissCount = 0L
        $metrics.HydrationMaterializeTemplateReuseCount = 0L
        $metrics.HydrationMaterializeTemplateApplyCount = 0L
        $metrics.HydrationMaterializeTemplateDefaultedCount = 0L
        $metrics.HydrationMaterializeTemplateAuthTemplateMissingCount = 0L
        $metrics.HydrationMaterializeTemplateNoTemplateMatchCount = 0L
        $metrics.HydrationMaterializeTemplateHintAppliedCount = 0L
        $metrics.HydrationMaterializeTemplateSetPortColorCount = 0L
        $metrics.HydrationMaterializeTemplateSetConfigStatusCount = 0L
        $metrics.HydrationMaterializeTemplateApplySamples = @()
        $metrics.HydrationTemplateDurationMs = 0.0
        $metrics.HydrationQueryAttempts = 0
        $metrics.HydrationExclusiveRetryCount = 0
        $metrics.HydrationExclusiveWaitDurationMs = 0.0
        if ($reusePortCount -gt 0) {
            $metrics.HydrationResultRowCount = [int]$reusePortCount
        } else {
            $metrics.HydrationResultRowCount = 0
        }
        $metrics.HydrationPreviousHostCount = [int][Math]::Max(0, $reuseHostCount)
        $metrics.HydrationPreviousPortCount = [int][Math]::Max(0, $reusePortCount)
        $metrics.HydrationPreviousHostSample = if ($reuseHostSampleValues.Count -gt 0) { [string]::Join(',', $reuseHostSampleValues.ToArray()) } else { '' }
        $metrics.HydrationPreviousSnapshotStatus = 'CacheHit'
        $metrics.HydrationPreviousSnapshotHostMapType = $cachedHostMapType
        $metrics.HydrationPreviousSnapshotHostCount = [int][Math]::Max(0, $reuseHostCount)
        $metrics.HydrationPreviousSnapshotPortCount = [int][Math]::Max(0, $reusePortCount)
        $metrics.HydrationPreviousSnapshotException = ''
        $metrics.TotalRows = [int][Math]::Max(0, $reusePortCount)
        $metrics.HostCount = [int][Math]::Max(0, $reuseHostCount)

        $hostMapForTotals = $null
        if ($cachedEntry -and $cachedEntry.PSObject.Properties.Name -contains 'HostMap') {
            $hostMapForTotals = $cachedEntry.HostMap
        }

        $hostCount = 0
        if ($metrics.HostCount -gt 0) {
            $hostCount = [int]$metrics.HostCount
        } elseif ($cachedEntry -and $cachedEntry.PSObject.Properties.Name -contains 'HostCount') {
            try { $hostCount = [int]$cachedEntry.HostCount } catch { $hostCount = 0 }
        } elseif ($hostMapForTotals -is [System.Collections.IDictionary]) {
            try { $hostCount = [int]$hostMapForTotals.Count } catch { $hostCount = 0 }
        }

        $totalRows = 0
        if ($metrics.TotalRows -gt 0) {
            $totalRows = [int]$metrics.TotalRows
        } elseif ($cachedEntry -and $cachedEntry.PSObject.Properties.Name -contains 'TotalRows') {
            try { $totalRows = [int]$cachedEntry.TotalRows } catch { $totalRows = 0 }
        } elseif ($hostMapForTotals -is [System.Collections.IDictionary]) {
            foreach ($hostEntry in @($hostMapForTotals.GetEnumerator())) {
                $portMap = $hostEntry.Value
                if ($portMap -is [System.Collections.ICollection]) {
                    $totalRows += $portMap.Count
                } elseif ($portMap -is [System.Collections.IDictionary]) {
                    $totalRows += $portMap.Count
                }
            }
        }

        if ($metrics.HydrationResultRowCount -le 0 -and $totalRows -gt 0) {
            $metrics.HydrationResultRowCount = $totalRows
        }
        $metrics.HostCount = $hostCount
        $metrics.TotalRows = $totalRows

        $script:LastInterfaceSiteCacheMetrics = $metrics
        Publish-InterfaceSiteCacheTelemetry -SiteKey $siteKey -Metrics $metrics -HostCount $hostCount -TotalRows $totalRows -Refreshed ([bool]$Refresh)
        Publish-InterfaceSiteCacheReuseState -SiteKey $siteKey -Entry $cachedEntry
        return $cachedEntry
    }

    $hydrateStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $snapshot = $null
    $snapshotStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $snapshot = Get-InterfacesForSite -Site $siteKey -Connection $Connection
    } catch {
        $snapshot = $null
    } finally {
        $snapshotStopwatch.Stop()
    }
    try {
        $hydrationDetail = Get-LastInterfaceSiteHydrationMetrics
    } catch {
        $hydrationDetail = $null
    }
    $snapshotDurationMs = [Math]::Round($snapshotStopwatch.Elapsed.TotalMilliseconds, 3)

    $hostDictionaryPool = [System.Collections.Stack]::new()
    $entryPool = [System.Collections.Stack]::new()
    $previousHostEntries = $null
    $previousHostSignatureSnapshot = $null
    $previousHostEntryCount = 0
    $previousHostPortCount = 0
    $previousHostSampleValues = New-Object 'System.Collections.Generic.List[string]'
    $hostMap = $null
    if ($previousSignatureEntry) {
        $previousSnapshotStatus = 'HostMapMissing'
    }

    if ($previousSignatureEntry -and $previousSignatureEntry.PSObject.Properties.Name -contains 'HostMap') {
        $existingHostMap = $previousSignatureEntry.HostMap
        if ($existingHostMap) {
            try { $previousSnapshotHostMapType = '' + $existingHostMap.GetType().FullName } catch { $previousSnapshotHostMapType = '' }
        }
        if ($existingHostMap -is [System.Collections.IDictionary]) {
            try { $previousSnapshotHostCount = [int]$existingHostMap.Count } catch { $previousSnapshotHostCount = 0 }
            $previousHostEntries = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.Dictionary[string,StateTrace.Models.InterfaceCacheEntry]]' ([System.StringComparer]::OrdinalIgnoreCase)
            $previousHostSignatureSnapshot = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.Dictionary[string,string]]' ([System.StringComparer]::OrdinalIgnoreCase)
            try {
                $previousSnapshotStatus = 'Enumerating'
                foreach ($existingHostEntry in @($existingHostMap.GetEnumerator())) {
                    $existingHostKey = if ($existingHostEntry.Key) { ('' + $existingHostEntry.Key).Trim() } else { '' }
                    if ([string]::IsNullOrWhiteSpace($existingHostKey)) { continue }
                    $existingPortMap = $existingHostEntry.Value
                    if ($existingPortMap -is [System.Collections.IDictionary]) {
                        try {
                            $previousSnapshotPortCount += [int]$existingPortMap.Count
                        } catch { }
                    } elseif ($existingPortMap -is [System.Collections.ICollection]) {
                        try {
                            $previousSnapshotPortCount += [int]$existingPortMap.Count
                        } catch { }
                    }
                    if ($existingPortMap -is [System.Collections.IDictionary]) {
                        $portEntries = New-Object 'System.Collections.Generic.Dictionary[string,StateTrace.Models.InterfaceCacheEntry]' ([System.StringComparer]::OrdinalIgnoreCase)
                        $signatureEntries = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::OrdinalIgnoreCase)
                        foreach ($existingPortEntry in @($existingPortMap.GetEnumerator())) {
                            $existingPortKey = if ($existingPortEntry.Key) { ('' + $existingPortEntry.Key).Trim() } else { '' }
                            if ([string]::IsNullOrWhiteSpace($existingPortKey)) { continue }
                            $previousEntry = $existingPortEntry.Value
                            $typedPreviousEntry = $null
                            if ($previousEntry -is [StateTrace.Models.InterfaceCacheEntry]) {
                                $typedPreviousEntry = $previousEntry
                            } elseif ($null -ne $previousEntry) {
                                try {
                                    $typedPreviousEntry = ConvertTo-InterfaceCacheEntryObject -InputObject $previousEntry
                                } catch {
                                    $typedPreviousEntry = $null
                                }
                            }
                            if ($typedPreviousEntry) {
                                $portEntries[$existingPortKey] = $typedPreviousEntry
                                if ($null -ne $typedPreviousEntry.Signature) {
                                    $signatureEntries[$existingPortKey] = '' + $typedPreviousEntry.Signature
                                } else {
                                    $signatureEntries[$existingPortKey] = $null
                                }
                            }
                        }
                        if ($portEntries.Count -gt 0) {
                            $previousHostEntries[$existingHostKey] = $portEntries
                        } else {
                            $previousHostEntries[$existingHostKey] = New-Object 'System.Collections.Generic.Dictionary[string,StateTrace.Models.InterfaceCacheEntry]' ([System.StringComparer]::OrdinalIgnoreCase)
                        }
                        $previousHostSignatureSnapshot[$existingHostKey] = $signatureEntries
                        if (-not [string]::IsNullOrWhiteSpace($existingHostKey) -and $previousHostSampleValues.Count -lt 5) {
                            $previousHostSampleValues.Add($existingHostKey) | Out-Null
                        }
                        if ($portEntries -is [System.Collections.IDictionary]) {
                            $previousHostPortCount += $portEntries.Count
                        } elseif ($portEntries -is [System.Collections.ICollection]) {
                            $previousHostPortCount += $portEntries.Count
                        }
                        try { $existingPortMap.Clear() } catch { }
                        $hostDictionaryPool.Push($existingPortMap)
                    }
                }
                if ($previousHostEntries.Count -gt 0 -or $previousHostSignatureSnapshot.Count -gt 0) {
                    $previousSnapshotStatus = 'Converted'
                } else {
                    $previousSnapshotStatus = 'EnumeratedZero'
                }
            } catch {
                $previousSnapshotStatus = 'EnumerationFailed'
                $previousSnapshotException = $_.Exception.Message
            }
            try { $existingHostMap.Clear() } catch { }
            if ($existingHostMap -is [System.Collections.IDictionary]) {
                $hostMap = $existingHostMap
            }
            if ($previousHostEntries) {
                $previousHostEntryCount = $previousHostEntries.Count
            }
        } elseif ($null -eq $existingHostMap) {
            $previousSnapshotStatus = 'HostMapNull'
        } else {
            $previousSnapshotStatus = 'HostMapUnsupported'
        }
    }
    if (-not $hostMap) {
        $hostMap = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.Dictionary[string,StateTrace.Models.InterfaceCacheEntry]]' ([System.StringComparer]::OrdinalIgnoreCase)
    }
    $previousHostSampleText = if ($previousHostSampleValues.Count -gt 0) { [string]::Join(',', $previousHostSampleValues.ToArray()) } else { '' }

    $totalRows = 0
    $buildStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $hostMapStopwatch = $null
    $hostMapDurationMs = 0.0
    $hostMapSignatureMatchCount = 0L
    $hostMapSignatureRewriteCount = 0L
    $hostMapEntryAllocationCount = 0L
    $hostMapEntryPoolReuseCount = 0L
    $hostMapLookupCount = 0L
    $hostMapLookupMissCount = 0L
    $hostMapCandidateMissingCount = 0L
    $hostMapCandidateSignatureMissingCount = 0L
    $hostMapCandidateSignatureMismatchCount = 0L
    $hostMapCandidateFromPreviousCount = 0L
    $hostMapCandidateFromPoolCount = 0L
    $hostMapCandidateInvalidCount = 0L
    $hostMapSignatureMismatchSamples = New-Object 'System.Collections.Generic.List[object]'
    $hostMapCandidateMissingSamples = New-Object 'System.Collections.Generic.List[object]'
    if ($snapshot) {
        $materializePortSortCacheHits = 0L
        $materializePortSortCacheMisses = 0L
        $materializePortSortCacheSize = 0L
        $portSortUniquePorts = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        $portSortMissSamples = New-Object 'System.Collections.Generic.List[object]'
        $portSortMissSampleLimit = 20
        $templateApplyCandidateCount = 0L
        $templateApplyDefaultedCount = 0L
        $templateApplyAuthTemplateMissingCount = 0L
        $templateApplyNoTemplateMatchCount = 0L
        $templateApplyHintAppliedCount = 0L
        $templateApplySetPortColorCount = 0L
        $templateApplySetConfigStatusCount = 0L
        $templateApplySamples = New-Object 'System.Collections.Generic.List[object]'
        $templateApplySampleLimit = 20
        $templatesDir = Join-Path $PSScriptRoot '..\Templates'
        $templateLookups = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
        $templateHintCaches = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.Dictionary[string,StateTrace.Models.InterfaceTemplateHint]]' ([System.StringComparer]::OrdinalIgnoreCase)
        $templatesStopwatch = [System.Diagnostics.Stopwatch]::new()
        $templateLoadDuration = 0.0
        $materializeStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $projectionStopwatch = [System.Diagnostics.Stopwatch]::new()
        $portSortStopwatch = [System.Diagnostics.Stopwatch]::new()
        $templateResolveStopwatch = [System.Diagnostics.Stopwatch]::new()
        $objectBuildStopwatch = [System.Diagnostics.Stopwatch]::new()
        $materializeProjectionDuration = 0.0
        $materializePortSortDuration = 0.0
        $materializeTemplateDuration = 0.0
        $materializeTemplateLookupDuration = 0.0
        $materializeTemplateApplyDuration = 0.0
        $materializeObjectDuration = 0.0
        $templateLookupStopwatch = [System.Diagnostics.Stopwatch]::new()
        $templateApplyStopwatch = [System.Diagnostics.Stopwatch]::new()
        $templateHintCacheHitCount = 0L
        $templateHintCacheMissCount = 0L
        $defaultPortSortValue = '99-UNK-99999-99999-99999-99999-99999'

        $hostMapStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        foreach ($row in $snapshot) {
            if ($null -eq $row) { continue }

            $port = ''
            $portSort = $null
            $portSortAdded = $false
            $hostKey = ''
            $portKey = ''
            $nameValue = ''
            $statusValue = ''
            $vlanValue = ''
            $duplexValue = ''
            $speedValue = ''
            $typeValue = ''
            $learnedValue = ''
            $authStateValue = ''
            $authModeValue = ''
            $authClientValue = ''
            $templateValue = ''
            $configValue = ''
            $portColorValue = ''
            $statusTagValue = ''
            $toolTipValue = ''

            if ($row -is [StateTrace.Models.InterfacePortRecord]) {
                $typedRow = [StateTrace.Models.InterfacePortRecord]$row
                $hostKey = [string]$typedRow.Hostname
                if ($hostKey) { $hostKey = $hostKey.Trim() }
                if ([string]::IsNullOrWhiteSpace($hostKey)) { continue }

                $portKey = [string]$typedRow.Port
                if ($portKey) { $portKey = $portKey.Trim() }
                if ([string]::IsNullOrWhiteSpace($portKey)) { continue }

                $nameValue = [string]$typedRow.Name
                $statusValue = [string]$typedRow.Status
                $vlanValue = [string]$typedRow.VLAN
                $duplexValue = [string]$typedRow.Duplex
                $speedValue = [string]$typedRow.Speed
                $typeValue = [string]$typedRow.Type
                $learnedValue = [string]$typedRow.LearnedMACs
                $authStateValue = [string]$typedRow.AuthState
                $authModeValue = [string]$typedRow.AuthMode
                $authClientValue = [string]$typedRow.AuthClientMAC
                $templateValue = [string]$typedRow.AuthTemplate
                $configValue = [string]$typedRow.Config
                $portColorValue = [string]$typedRow.PortColor
                $statusTagValue = [string]$typedRow.ConfigStatus
                $toolTipValue = [string]$typedRow.ToolTip
                $signature = [string]$typedRow.CacheSignature
                if ([string]::IsNullOrWhiteSpace($signature)) {
                    $signature = ConvertTo-InterfaceCacheSignature -Values @(
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
                }
            } else {
                $properties = $row.PSObject.Properties
                $hostProp = $properties['Hostname']
                if (-not $hostProp) { continue }
                $hostNameRaw = '' + $hostProp.Value
                if ([string]::IsNullOrWhiteSpace($hostNameRaw)) { continue }
                $hostKey = $hostNameRaw.Trim()

                $portProp = $properties['Port']
                if (-not $portProp) { continue }
                $portRaw = '' + $portProp.Value
                if ([string]::IsNullOrWhiteSpace($portRaw)) { continue }
                $portKey = $portRaw.Trim()

                $nameProp = $properties['Name']
                if ($nameProp) { $nameValue = '' + $nameProp.Value }

                $statusProp = $properties['Status']
                if ($statusProp) { $statusValue = '' + $statusProp.Value }

                $vlanProp = $properties['VLAN']
                if ($vlanProp) { $vlanValue = '' + $vlanProp.Value }

                $duplexProp = $properties['Duplex']
                if ($duplexProp) { $duplexValue = '' + $duplexProp.Value }

                $speedProp = $properties['Speed']
                if ($speedProp) { $speedValue = '' + $speedProp.Value }

                $typeProp = $properties['Type']
                if ($typeProp) { $typeValue = '' + $typeProp.Value }

                $learnedProp = $properties['LearnedMACs']
                if ($learnedProp) {
                    $rawLearned = $learnedProp.Value
                    if ($rawLearned -is [string]) {
                        $learnedValue = $rawLearned
                    } elseif ($rawLearned -is [System.Collections.IEnumerable]) {
                        $macList = New-Object 'System.Collections.Generic.List[string]'
                        foreach ($mac in $rawLearned) {
                            if ($mac) {
                                $macList.Add(('' + $mac)) | Out-Null
                            }
                        }
                        $learnedValue = [string]::Join(',', $macList.ToArray())
                    } elseif ($null -ne $rawLearned) {
                        $learnedValue = '' + $rawLearned
                    }
                }

                $authStateProp = $properties['AuthState']
                if ($authStateProp) { $authStateValue = '' + $authStateProp.Value }

                $authModeProp = $properties['AuthMode']
                if ($authModeProp) { $authModeValue = '' + $authModeProp.Value }

                $authClientProp = $properties['AuthClientMAC']
                if ($authClientProp) { $authClientValue = '' + $authClientProp.Value }

                $templateProp = $properties['AuthTemplate']
                if ($templateProp) { $templateValue = '' + $templateProp.Value }

                $configProp = $properties['Config']
                if ($configProp) { $configValue = '' + $configProp.Value }

                $portColorProp = $properties['PortColor']
                if ($portColorProp) { $portColorValue = '' + $portColorProp.Value }

                $configStatusProp = $properties['ConfigStatus']
                if ($configStatusProp) { $statusTagValue = '' + $configStatusProp.Value }

                $toolTipProp = $properties['ToolTip']
                if ($toolTipProp) { $toolTipValue = '' + $toolTipProp.Value }

                $signature = ConvertTo-InterfaceCacheSignature -Values @(
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
            }

            if ([string]::IsNullOrWhiteSpace($hostKey) -or [string]::IsNullOrWhiteSpace($portKey)) {
                continue
            }

        $cachedPortEntry = $null
        $hostPorts = $null
        $hostMapLookupCount++
        if (-not $hostMap.TryGetValue($hostKey, [ref]$hostPorts)) {
            $hostMapLookupMissCount++
            $hostPortsCandidate = $null
            if ($hostDictionaryPool.Count -gt 0) {
                $hostPortsCandidate = $hostDictionaryPool.Pop()
            }
            if ($hostPortsCandidate -and $hostPortsCandidate -is [System.Collections.IDictionary]) {
                    try { $hostPortsCandidate.Clear() } catch { }
                    $hostPorts = $hostPortsCandidate
                }
            if (-not $hostPorts) {
                $hostPorts = New-Object 'System.Collections.Generic.Dictionary[string,StateTrace.Models.InterfaceCacheEntry]' ([System.StringComparer]::OrdinalIgnoreCase)
            }
            $hostMap[$hostKey] = $hostPorts
        }

        $rowObject = $null
        $allocatedNewEntry = $false
        $previousPortEntries = $null
        $candidateSource = $null
        $previousHostEntryWasPresent = $false
        $previousPortEntryWasPresent = $false
        if ($previousHostEntries -and $previousHostEntries.TryGetValue($hostKey, [ref]$previousPortEntries)) {
            $previousHostEntryWasPresent = $true
            $existingPortEntry = $null
            if ($previousPortEntries.TryGetValue($portKey, [ref]$existingPortEntry)) {
                $previousPortEntryWasPresent = $true
                if ($existingPortEntry -is [StateTrace.Models.InterfaceCacheEntry]) {
                    $rowObject = $existingPortEntry
                    $cachedPortEntry = $existingPortEntry
                    $candidateSource = 'Previous'
                } elseif ($null -ne $existingPortEntry) {
                    $hostMapCandidateInvalidCount++
                }
                $previousPortEntries.Remove($portKey) | Out-Null
            }
            if (-not $rowObject -and $previousPortEntries.Count -gt 0) {
                foreach ($previousPortKey in @($previousPortEntries.Keys)) {
                    $existingPortEntry = $previousPortEntries[$previousPortKey]
                    $previousPortEntries.Remove($previousPortKey) | Out-Null
                    if ($existingPortEntry -is [StateTrace.Models.InterfaceCacheEntry]) {
                        $rowObject = $existingPortEntry
                        $hostMapEntryPoolReuseCount++
                        $candidateSource = 'Previous'
                        break
                    } elseif ($null -ne $existingPortEntry) {
                        $hostMapCandidateInvalidCount++
                    }
                }
            }
            if ($previousPortEntries.Count -eq 0) {
                $previousHostEntries.Remove($hostKey) | Out-Null
            } else {
                $previousHostEntries[$hostKey] = $previousPortEntries
            }
        }

        if (-not $rowObject -and $entryPool.Count -gt 0) {
            $candidate = $entryPool.Pop()
            if ($candidate -is [StateTrace.Models.InterfaceCacheEntry]) {
                $rowObject = $candidate
                $hostMapEntryPoolReuseCount++
                $candidateSource = 'Pool'
            } elseif ($null -ne $candidate) {
                $hostMapCandidateInvalidCount++
            }
        }

        $candidateWasReused = $false
        $signatureComparisonKind = 'New'
        $previousSignatureValue = $null
        if ($rowObject) {
            $candidateWasReused = $true
            $signatureComparisonKind = 'Rewrite'
            $prevSignatureRaw = $rowObject.Signature
            if ($null -ne $prevSignatureRaw) {
                $previousSignatureValue = '' + $prevSignatureRaw
            }
            if ($candidateSource -eq 'Previous') {
                $hostMapCandidateFromPreviousCount++
            } elseif ($candidateSource -eq 'Pool') {
                $hostMapCandidateFromPoolCount++
            }
        } else {
            $hostMapCandidateMissingCount++
            if ($hostMapCandidateMissingSamples.Count -lt 5) {
                $cachedSnapshotPortEntries = $null
                $cachedPortCount = 0
                $cachedPortSample = @()
                $cachedSignature = $null
                $missingReason = 'HostSnapshotMissing'
                if ($previousHostSignatureSnapshot -and $previousHostSignatureSnapshot.TryGetValue($hostKey, [ref]$cachedSnapshotPortEntries)) {
                    if ($cachedSnapshotPortEntries -is [System.Collections.IDictionary]) {
                        $cachedPortCount = $cachedSnapshotPortEntries.Count
                        $missingReason = 'PortSnapshotMissing'
                        $cachedPortSample = @()
                        $sampledPortCount = 0
                        foreach ($cachedPortKey in $cachedSnapshotPortEntries.Keys) {
                            if ($sampledPortCount -ge 5) { break }
                            if ($null -ne $cachedPortKey) {
                                $cachedPortSample += ('' + $cachedPortKey)
                                $sampledPortCount++
                            }
                        }
                        if ($cachedSnapshotPortEntries -is [System.Collections.Generic.Dictionary[string,string]]) {
                            $snapshotSignature = $null
                            if ($cachedSnapshotPortEntries.TryGetValue($portKey, [ref]$snapshotSignature)) {
                                $missingReason = 'SignaturePersisted'
                                if ($null -ne $snapshotSignature) {
                                    $cachedSignature = '' + $snapshotSignature
                                }
                            }
                        } elseif ($cachedSnapshotPortEntries.Contains($portKey)) {
                            $missingReason = 'SignaturePersisted'
                            $snapshotSignature = $cachedSnapshotPortEntries[$portKey]
                            if ($null -ne $snapshotSignature) {
                                $cachedSignature = '' + $snapshotSignature
                            }
                        }
                    }
                } elseif ($previousHostEntryWasPresent) {
                    $missingReason = 'PreviousHostCleared'
                }

                $previousRemainingPortCount = 0
                if ($previousPortEntries -is [System.Collections.IDictionary]) {
                    $previousRemainingPortCount = $previousPortEntries.Count
                }

                $hostMapCandidateMissingSamples.Add([pscustomobject]@{
                        Hostname                  = $hostKey
                        Port                      = $portKey
                        Reason                    = $missingReason
                        PreviousHostEntryPresent  = [bool]$previousHostEntryWasPresent
                        PreviousPortEntryPresent  = [bool]$previousPortEntryWasPresent
                        CachedPortCount           = [int]$cachedPortCount
                        CachedPortSample          = if ($cachedPortSample.Count -gt 0) { [string]::Join(',', $cachedPortSample) } else { '' }
                        CachedSignature           = $cachedSignature
                        PreviousRemainingPortCount = [int]$previousRemainingPortCount
                        CandidateSource           = if ($candidateSource) { $candidateSource } else { '' }
                    }) | Out-Null
            }

            $rowObject = [StateTrace.Models.InterfaceCacheEntry]::new()
            $allocatedNewEntry = $true
        }

        $shouldRewrite = $true
        if ($candidateWasReused) {
            if ([string]::IsNullOrWhiteSpace($rowObject.Signature)) {
                $hostMapCandidateSignatureMissingCount++
                $signatureComparisonKind = 'SignatureMissing'
            } elseif ([System.StringComparer]::Ordinal.Equals($rowObject.Signature, $signature)) {
                $shouldRewrite = $false
                $signatureComparisonKind = 'Match'
            } else {
                $hostMapCandidateSignatureMismatchCount++
                $signatureComparisonKind = 'Mismatch'
            }
        }

        if ($shouldRewrite) {
            $hostMapSignatureRewriteCount++
            if ($candidateWasReused -and $signatureComparisonKind -eq 'Mismatch' -and $hostMapSignatureMismatchSamples.Count -lt 5) {
                $newSignatureValue = $null
                if ($null -ne $signature) {
                    $newSignatureValue = '' + $signature
                }
                $hostMapSignatureMismatchSamples.Add([pscustomobject]@{
                    Hostname          = $hostKey
                    Port              = $portKey
                    PreviousSignature = $previousSignatureValue
                    NewSignature      = $newSignatureValue
                }) | Out-Null
            }
            $rowObject.Name = $nameValue
            $rowObject.Status = $statusValue
            $rowObject.VLAN = $vlanValue
            $rowObject.Duplex = $duplexValue
            $rowObject.Speed = $speedValue
            $rowObject.Type = $typeValue
            $rowObject.Learned = $learnedValue
            $rowObject.AuthState = $authStateValue
            $rowObject.AuthMode = $authModeValue
            $rowObject.AuthClient = $authClientValue
            $rowObject.Template = $templateValue
            $rowObject.Config = $configValue
            $rowObject.PortColor = $portColorValue
            $rowObject.StatusTag = $statusTagValue
            $rowObject.ToolTip = $toolTipValue
            $rowObject.Signature = $signature
        } else {
            $hostMapSignatureMatchCount++
        }

        $needPortSortComputation = $shouldRewrite
        if (-not $needPortSortComputation) {
            if ([string]::IsNullOrWhiteSpace($rowObject.PortSort)) {
                $needPortSortComputation = $true
            } else {
                $portSort = $rowObject.PortSort
            }
        }

        if ($needPortSortComputation) {
            $portSortStopwatch.Restart()
            if (-not [string]::IsNullOrWhiteSpace($port)) {
                $portSort = InterfaceModule\Get-PortSortKey -Port $port
            } else {
                $portSort = $defaultPortSortValue
            }
            $portSortStopwatch.Stop()
            $materializePortSortDuration += $portSortStopwatch.Elapsed.TotalMilliseconds
            if ($portSortAdded -and $portSortMissSamples.Count -lt $portSortMissSampleLimit) {
                $portSortMissSamples.Add([pscustomobject]@{
                        Port     = $port
                        PortSort = $portSort
                    }) | Out-Null
            }
            $rowObject.PortSort = $portSort
        }

        if ([string]::IsNullOrWhiteSpace($portSort)) {
            if ([string]::IsNullOrWhiteSpace($rowObject.PortSort)) {
                $portSort = $defaultPortSortValue
                $rowObject.PortSort = $portSort
            } else {
                $portSort = $rowObject.PortSort
            }
        }

        if ($allocatedNewEntry) {
            $hostMapEntryAllocationCount++
        }

        $hostPorts[$portKey] = $rowObject
        $totalRows++
        }
        if ($hostMapStopwatch) {
            $hostMapStopwatch.Stop()
            $hostMapDurationMs = [Math]::Round($hostMapStopwatch.Elapsed.TotalMilliseconds, 3)
        }
    }
    $buildStopwatch.Stop()
    $buildDurationMs = [Math]::Round($buildStopwatch.Elapsed.TotalMilliseconds, 3)
    $hydrateStopwatch.Stop()
    $hydrationDurationMs = [Math]::Round($hydrateStopwatch.Elapsed.TotalMilliseconds, 3)

    if ($hydrationDetail -and $hydrationDetail.Site -and [System.StringComparer]::OrdinalIgnoreCase.Equals($hydrationDetail.Site, $siteKey)) {
        if ($hydrationDetail.PSObject.Properties.Name -contains 'Provider') {
            $providerValue = '' + $hydrationDetail.Provider
            if (-not [string]::IsNullOrWhiteSpace($providerValue)) {
                $metrics.HydrationProvider = $providerValue
            }
        }
        if ($hydrationDetail.PSObject.Properties.Name -contains 'QueryDurationMs') {
            $metrics.HydrationQueryDurationMs = [Math]::Round([double]$hydrationDetail.QueryDurationMs, 3)
        }
        if ($hydrationDetail.PSObject.Properties.Name -contains 'ExecuteDurationMs') {
            $metrics.HydrationExecuteDurationMs = [Math]::Round([double]$hydrationDetail.ExecuteDurationMs, 3)
        }
        if ($hydrationDetail.PSObject.Properties.Name -contains 'RecordsetEnumerateDurationMs') {
            $metrics.HydrationSnapshotRecordsetDurationMs = [Math]::Round([double]$hydrationDetail.RecordsetEnumerateDurationMs, 3)
        }
        if ($hydrationDetail.PSObject.Properties.Name -contains 'RecordsetProjectDurationMs') {
            $metrics.HydrationSnapshotProjectDurationMs = [Math]::Round([double]$hydrationDetail.RecordsetProjectDurationMs, 3)
        }
        if ($hydrationDetail.PSObject.Properties.Name -contains 'MaterializeDurationMs') {
            $metrics.HydrationMaterializeDurationMs = [Math]::Round([double]$hydrationDetail.MaterializeDurationMs, 3)
        }
        if ($hydrationDetail.PSObject.Properties.Name -contains 'MaterializeProjectionDurationMs') {
            $metrics.HydrationMaterializeProjectionDurationMs = [Math]::Round([double]$hydrationDetail.MaterializeProjectionDurationMs, 3)
        }
        if ($hydrationDetail.PSObject.Properties.Name -contains 'MaterializePortSortDurationMs') {
            $metrics.HydrationMaterializePortSortDurationMs = [Math]::Round([double]$hydrationDetail.MaterializePortSortDurationMs, 3)
        }
        if ($hydrationDetail.PSObject.Properties.Name -contains 'MaterializePortSortCacheHitCount') {
            $metrics.HydrationMaterializePortSortCacheHits = [long][Math]::Max(0, $hydrationDetail.MaterializePortSortCacheHitCount)
        }
        if ($hydrationDetail.PSObject.Properties.Name -contains 'MaterializePortSortCacheMissCount') {
            $metrics.HydrationMaterializePortSortCacheMisses = [long][Math]::Max(0, $hydrationDetail.MaterializePortSortCacheMissCount)
        }
        if ($hydrationDetail.PSObject.Properties.Name -contains 'MaterializePortSortCacheSize') {
            $metrics.HydrationMaterializePortSortCacheSize = [long][Math]::Max(0, $hydrationDetail.MaterializePortSortCacheSize)
        }
        if ($hydrationDetail.PSObject.Properties.Name -contains 'MaterializePortSortUniquePortCount') {
            $metrics.HydrationMaterializePortSortUniquePortCount = [long][Math]::Max(0, $hydrationDetail.MaterializePortSortUniquePortCount)
        }
        if ($hydrationDetail.PSObject.Properties.Name -contains 'MaterializePortSortMissSamples') {
            $metrics.HydrationMaterializePortSortMissSamples = @($hydrationDetail.MaterializePortSortMissSamples)
        }
        if ($hydrationDetail.PSObject.Properties.Name -contains 'MaterializeTemplateDurationMs') {
            $metrics.HydrationMaterializeTemplateDurationMs = [Math]::Round([double]$hydrationDetail.MaterializeTemplateDurationMs, 3)
        }
        if ($hydrationDetail.PSObject.Properties.Name -contains 'MaterializeTemplateLookupDurationMs') {
            $metrics.HydrationMaterializeTemplateLookupDurationMs = [Math]::Round([double]$hydrationDetail.MaterializeTemplateLookupDurationMs, 3)
        }
        if ($hydrationDetail.PSObject.Properties.Name -contains 'MaterializeTemplateApplyDurationMs') {
            $metrics.HydrationMaterializeTemplateApplyDurationMs = [Math]::Round([double]$hydrationDetail.MaterializeTemplateApplyDurationMs, 3)
        }
        if ($hydrationDetail.PSObject.Properties.Name -contains 'MaterializeObjectDurationMs') {
            $metrics.HydrationMaterializeObjectDurationMs = [Math]::Round([double]$hydrationDetail.MaterializeObjectDurationMs, 3)
        }
        if ($hydrationDetail.PSObject.Properties.Name -contains 'MaterializeTemplateApplyCount') {
            $metrics.HydrationMaterializeTemplateApplyCount = [long][Math]::Max(0, $hydrationDetail.MaterializeTemplateApplyCount)
        }
        if ($hydrationDetail.PSObject.Properties.Name -contains 'MaterializeTemplateDefaultedCount') {
            $metrics.HydrationMaterializeTemplateDefaultedCount = [long][Math]::Max(0, $hydrationDetail.MaterializeTemplateDefaultedCount)
        }
        if ($hydrationDetail.PSObject.Properties.Name -contains 'MaterializeTemplateAuthTemplateMissingCount') {
            $metrics.HydrationMaterializeTemplateAuthTemplateMissingCount = [long][Math]::Max(0, $hydrationDetail.MaterializeTemplateAuthTemplateMissingCount)
        }
        if ($hydrationDetail.PSObject.Properties.Name -contains 'MaterializeTemplateNoTemplateMatchCount') {
            $metrics.HydrationMaterializeTemplateNoTemplateMatchCount = [long][Math]::Max(0, $hydrationDetail.MaterializeTemplateNoTemplateMatchCount)
        }
        if ($hydrationDetail.PSObject.Properties.Name -contains 'MaterializeTemplateHintAppliedCount') {
            $metrics.HydrationMaterializeTemplateHintAppliedCount = [long][Math]::Max(0, $hydrationDetail.MaterializeTemplateHintAppliedCount)
        }
        if ($hydrationDetail.PSObject.Properties.Name -contains 'MaterializeTemplateSetPortColorCount') {
            $metrics.HydrationMaterializeTemplateSetPortColorCount = [long][Math]::Max(0, $hydrationDetail.MaterializeTemplateSetPortColorCount)
        }
        if ($hydrationDetail.PSObject.Properties.Name -contains 'MaterializeTemplateSetConfigStatusCount') {
            $metrics.HydrationMaterializeTemplateSetConfigStatusCount = [long][Math]::Max(0, $hydrationDetail.MaterializeTemplateSetConfigStatusCount)
        }
        if ($hydrationDetail.PSObject.Properties.Name -contains 'MaterializeTemplateApplySamples') {
            $metrics.HydrationMaterializeTemplateApplySamples = @($hydrationDetail.MaterializeTemplateApplySamples)
        }
        if ($hydrationDetail.PSObject.Properties.Name -contains 'MaterializeTemplateCacheHitCount') {
            $metrics.HydrationMaterializeTemplateCacheHitCount = [long][Math]::Max(0, $hydrationDetail.MaterializeTemplateCacheHitCount)
        }
        if ($hydrationDetail.PSObject.Properties.Name -contains 'MaterializeTemplateCacheMissCount') {
            $metrics.HydrationMaterializeTemplateCacheMissCount = [long][Math]::Max(0, $hydrationDetail.MaterializeTemplateCacheMissCount)
        }
        if ($hydrationDetail.PSObject.Properties.Name -contains 'MaterializeTemplateReuseCount') {
            $metrics.HydrationMaterializeTemplateReuseCount = [long][Math]::Max(0, $hydrationDetail.MaterializeTemplateReuseCount)
        }
        if ($hydrationDetail.PSObject.Properties.Name -contains 'TemplateLoadDurationMs') {
            $metrics.HydrationTemplateDurationMs = [Math]::Round([double]$hydrationDetail.TemplateLoadDurationMs, 3)
        }
        if ($hydrationDetail.PSObject.Properties.Name -contains 'SortDurationMs') {
            $metrics.HydrationSortDurationMs = [Math]::Round([double]$hydrationDetail.SortDurationMs, 3)
        }
        if ($hydrationDetail.PSObject.Properties.Name -contains 'QueryAttempts') {
            $metrics.HydrationQueryAttempts = [int]$hydrationDetail.QueryAttempts
        }
        if ($hydrationDetail.PSObject.Properties.Name -contains 'ExclusiveRetryCount') {
            $metrics.HydrationExclusiveRetryCount = [int]$hydrationDetail.ExclusiveRetryCount
        }
        if ($hydrationDetail.PSObject.Properties.Name -contains 'ExclusiveWaitDurationMs') {
            $metrics.HydrationExclusiveWaitDurationMs = [Math]::Round([double]$hydrationDetail.ExclusiveWaitDurationMs, 3)
        }
        if ($hydrationDetail.PSObject.Properties.Name -contains 'ResultRowCount') {
            $metrics.HydrationResultRowCount = [int]$hydrationDetail.ResultRowCount
        }
    } elseif ($metrics.HydrationProvider -eq 'Unknown') {
        $metrics.HydrationProvider = if ($Refresh) { 'Refresh' } else { 'Hydrate' }
    }
    $metrics.HydrationHostMapDurationMs = $hostMapDurationMs
    $metrics.HydrationHostMapSignatureMatchCount = $hostMapSignatureMatchCount
    $metrics.HydrationHostMapSignatureRewriteCount = $hostMapSignatureRewriteCount
    $metrics.HydrationHostMapEntryAllocationCount = $hostMapEntryAllocationCount
    $metrics.HydrationHostMapEntryPoolReuseCount = $hostMapEntryPoolReuseCount
    $metrics.HydrationHostMapLookupCount = $hostMapLookupCount
    $metrics.HydrationHostMapLookupMissCount = $hostMapLookupMissCount
    $metrics.HydrationHostMapCandidateMissingCount = $hostMapCandidateMissingCount
    $metrics.HydrationHostMapCandidateSignatureMissingCount = $hostMapCandidateSignatureMissingCount
    $metrics.HydrationHostMapCandidateSignatureMismatchCount = $hostMapCandidateSignatureMismatchCount
    $metrics.HydrationHostMapCandidateFromPreviousCount = $hostMapCandidateFromPreviousCount
    $metrics.HydrationHostMapCandidateFromPoolCount = $hostMapCandidateFromPoolCount
    $metrics.HydrationHostMapCandidateInvalidCount = $hostMapCandidateInvalidCount
    $metrics.HydrationHostMapCandidateMissingSamples = $hostMapCandidateMissingSamples.ToArray()
    $metrics.HydrationHostMapSignatureMismatchSamples = $hostMapSignatureMismatchSamples.ToArray()
    $metrics.HydrationPreviousHostCount = $previousHostEntryCount
    $metrics.HydrationPreviousPortCount = $previousHostPortCount
    $metrics.HydrationPreviousHostSample = $previousHostSampleText
    $metrics.HydrationPreviousSnapshotStatus = $previousSnapshotStatus
    $metrics.HydrationPreviousSnapshotHostMapType = $previousSnapshotHostMapType
    $metrics.HydrationPreviousSnapshotHostCount = $previousSnapshotHostCount
    $metrics.HydrationPreviousSnapshotPortCount = $previousSnapshotPortCount
    if ([string]::IsNullOrWhiteSpace($previousSnapshotException)) {
        $metrics.HydrationPreviousSnapshotException = ''
    } else {
        $trimmedException = $previousSnapshotException
        if ($trimmedException.Length -gt 512) {
            $trimmedException = $trimmedException.Substring(0, 512)
        }
        $metrics.HydrationPreviousSnapshotException = $trimmedException
    }

    $cacheStatus = if ($Refresh) { 'Refreshed' } else { 'Hydrated' }
    $cachedAt = Get-Date
    $entry = [PSCustomObject]@{
        HostMap                       = $hostMap
        TotalRows                     = $totalRows
        CachedAt                      = $cachedAt
        CacheStatus                   = $cacheStatus
        HydrationDurationMs           = $hydrationDurationMs
        HydrationSnapshotDurationMs   = $snapshotDurationMs
        HydrationSnapshotRecordsetDurationMs = $metrics.HydrationSnapshotRecordsetDurationMs
        HydrationSnapshotProjectDurationMs = $metrics.HydrationSnapshotProjectDurationMs
        HydrationBuildDurationMs      = $buildDurationMs
        HydrationHostMapDurationMs    = $metrics.HydrationHostMapDurationMs
        HydrationHostMapSignatureMatchCount   = $metrics.HydrationHostMapSignatureMatchCount
        HydrationHostMapSignatureRewriteCount = $metrics.HydrationHostMapSignatureRewriteCount
        HydrationHostMapEntryAllocationCount  = $metrics.HydrationHostMapEntryAllocationCount
        HydrationHostMapEntryPoolReuseCount   = $metrics.HydrationHostMapEntryPoolReuseCount
        HydrationHostMapLookupCount           = $metrics.HydrationHostMapLookupCount
        HydrationHostMapLookupMissCount       = $metrics.HydrationHostMapLookupMissCount
        HydrationHostMapCandidateMissingCount = $metrics.HydrationHostMapCandidateMissingCount
        HydrationHostMapCandidateSignatureMissingCount = $metrics.HydrationHostMapCandidateSignatureMissingCount
        HydrationHostMapCandidateSignatureMismatchCount = $metrics.HydrationHostMapCandidateSignatureMismatchCount
        HydrationHostMapCandidateFromPreviousCount = $metrics.HydrationHostMapCandidateFromPreviousCount
        HydrationHostMapCandidateFromPoolCount     = $metrics.HydrationHostMapCandidateFromPoolCount
        HydrationHostMapCandidateInvalidCount      = $metrics.HydrationHostMapCandidateInvalidCount
        HydrationHostMapCandidateMissingSamples    = $metrics.HydrationHostMapCandidateMissingSamples
        HydrationHostMapSignatureMismatchSamples   = $metrics.HydrationHostMapSignatureMismatchSamples
        HydrationPreviousHostCount    = $metrics.HydrationPreviousHostCount
        HydrationPreviousPortCount    = $metrics.HydrationPreviousPortCount
        HydrationPreviousHostSample   = $metrics.HydrationPreviousHostSample
        HydrationPreviousSnapshotStatus      = $metrics.HydrationPreviousSnapshotStatus
        HydrationPreviousSnapshotHostMapType = $metrics.HydrationPreviousSnapshotHostMapType
        HydrationPreviousSnapshotHostCount   = $metrics.HydrationPreviousSnapshotHostCount
        HydrationPreviousSnapshotPortCount   = $metrics.HydrationPreviousSnapshotPortCount
        HydrationPreviousSnapshotException   = $metrics.HydrationPreviousSnapshotException
        HydrationSortDurationMs       = $metrics.HydrationSortDurationMs
        HydrationQueryDurationMs      = $metrics.HydrationQueryDurationMs
        HydrationExecuteDurationMs    = $metrics.HydrationExecuteDurationMs
        HydrationMaterializeDurationMs= $metrics.HydrationMaterializeDurationMs
        HydrationMaterializeProjectionDurationMs = $metrics.HydrationMaterializeProjectionDurationMs
        HydrationMaterializePortSortDurationMs   = $metrics.HydrationMaterializePortSortDurationMs
        HydrationMaterializePortSortCacheHits    = $metrics.HydrationMaterializePortSortCacheHits
        HydrationMaterializePortSortCacheMisses  = $metrics.HydrationMaterializePortSortCacheMisses
        HydrationMaterializePortSortCacheSize    = $metrics.HydrationMaterializePortSortCacheSize
        HydrationMaterializePortSortUniquePortCount = $metrics.HydrationMaterializePortSortUniquePortCount
        HydrationMaterializePortSortMissSamples   = $metrics.HydrationMaterializePortSortMissSamples
        HydrationMaterializeTemplateDurationMs   = $metrics.HydrationMaterializeTemplateDurationMs
        HydrationMaterializeTemplateLookupDurationMs = $metrics.HydrationMaterializeTemplateLookupDurationMs
        HydrationMaterializeTemplateApplyDurationMs = $metrics.HydrationMaterializeTemplateApplyDurationMs
        HydrationMaterializeObjectDurationMs     = $metrics.HydrationMaterializeObjectDurationMs
        HydrationMaterializeTemplateCacheHitCount = $metrics.HydrationMaterializeTemplateCacheHitCount
        HydrationMaterializeTemplateCacheMissCount = $metrics.HydrationMaterializeTemplateCacheMissCount
        HydrationMaterializeTemplateReuseCount = $metrics.HydrationMaterializeTemplateReuseCount
        HydrationMaterializeTemplateApplyCount = $metrics.HydrationMaterializeTemplateApplyCount
        HydrationMaterializeTemplateDefaultedCount = $metrics.HydrationMaterializeTemplateDefaultedCount
        HydrationMaterializeTemplateAuthTemplateMissingCount = $metrics.HydrationMaterializeTemplateAuthTemplateMissingCount
        HydrationMaterializeTemplateNoTemplateMatchCount = $metrics.HydrationMaterializeTemplateNoTemplateMatchCount
        HydrationMaterializeTemplateHintAppliedCount = $metrics.HydrationMaterializeTemplateHintAppliedCount
        HydrationMaterializeTemplateSetPortColorCount = $metrics.HydrationMaterializeTemplateSetPortColorCount
        HydrationMaterializeTemplateSetConfigStatusCount = $metrics.HydrationMaterializeTemplateSetConfigStatusCount
        HydrationMaterializeTemplateApplySamples = $metrics.HydrationMaterializeTemplateApplySamples
        HydrationTemplateDurationMs   = $metrics.HydrationTemplateDurationMs
        HydrationQueryAttempts        = $metrics.HydrationQueryAttempts
        HydrationExclusiveRetryCount  = $metrics.HydrationExclusiveRetryCount
        HydrationExclusiveWaitDurationMs = $metrics.HydrationExclusiveWaitDurationMs
        HydrationProvider             = $metrics.HydrationProvider
        HydrationResultRowCount       = if ($metrics.HydrationResultRowCount -gt 0) { [int]$metrics.HydrationResultRowCount } else { $totalRows }
        HostCount                     = $hostMap.Count
    }
    $script:SiteInterfaceSignatureCache[$siteKey] = $entry
    Set-SharedSiteInterfaceCacheEntry -SiteKey $siteKey -Entry $entry

    $metrics.CacheStatus = $cacheStatus
    $metrics.HydrationDurationMs = $hydrationDurationMs
    $metrics.HydrationSnapshotMs = $snapshotDurationMs
    $metrics.HydrationBuildMs = $buildDurationMs
    $metrics.HostCount = $entry.HostCount
    $metrics.TotalRows = $totalRows
    $metrics.CachedAt = $cachedAt
    if ($metrics.HydrationResultRowCount -le 0) {
        $metrics.HydrationResultRowCount = $totalRows
    }
    if ($metrics.HydrationQueryAttempts -le 0 -and -not [System.StringComparer]::OrdinalIgnoreCase.Equals($metrics.HydrationProvider, 'Cache')) {
        $metrics.HydrationQueryAttempts = 1
    }
    $script:LastInterfaceSiteCacheMetrics = $metrics

    Publish-InterfaceSiteCacheTelemetry -SiteKey $siteKey -Metrics $metrics -HostCount $entry.HostCount -TotalRows $totalRows -Refreshed ([bool]$Refresh)

    return $entry
}

function Set-InterfaceSiteCacheHost {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Site,
        [Parameter(Mandatory)][string]$Hostname,
        [Parameter(Mandatory)][System.Collections.IDictionary]$RowsByPort
    )

    $siteKey = ('' + $Site).Trim()
    if ([string]::IsNullOrWhiteSpace($siteKey)) { return }

    $hostKey = ('' + $Hostname).Trim()
    if ([string]::IsNullOrWhiteSpace($hostKey)) { return }

    $entry = $null
    if ($script:SiteInterfaceSignatureCache.ContainsKey($siteKey)) {
        $entry = $script:SiteInterfaceSignatureCache[$siteKey]
    } else {
        $entry = [PSCustomObject]@{
            HostMap   = @{}
            TotalRows = 0
            HostCount = 0
            CachedAt  = Get-Date
        }
        $script:SiteInterfaceSignatureCache[$siteKey] = $entry
        Set-SharedSiteInterfaceCacheEntry -SiteKey $siteKey -Entry $entry
    }
    $previousHostCount = 0
    if ($entry.PSObject.Properties.Name -contains 'HostCount') {
        try { $previousHostCount = [int]$entry.HostCount } catch { $previousHostCount = 0 }
    }
    $previousPortCount = 0
    if ($entry.PSObject.Properties.Name -contains 'TotalRows') {
        try { $previousPortCount = [int]$entry.TotalRows } catch { $previousPortCount = 0 }
    }

    $existingHostMap = $entry.HostMap
    $originalHostMapReference = $existingHostMap
    $previousHostMapType = ''
    $previousHostMapWasTyped = $false
    if ($existingHostMap) {
        try { $previousHostMapType = '' + $existingHostMap.GetType().FullName } catch { $previousHostMapType = '' }
        if ($existingHostMap -is [System.Collections.Generic.Dictionary[string,System.Collections.Generic.Dictionary[string,StateTrace.Models.InterfaceCacheEntry]]]) {
            $previousHostMapWasTyped = $true
        }
    }
    $typedHostMap = $null
    if ($existingHostMap -is [System.Collections.Generic.Dictionary[string,System.Collections.Generic.Dictionary[string,StateTrace.Models.InterfaceCacheEntry]]]) {
        $typedHostMap = $existingHostMap
    } else {
        $typedHostMap = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.Dictionary[string,StateTrace.Models.InterfaceCacheEntry]]' ([System.StringComparer]::OrdinalIgnoreCase)
        if ($existingHostMap -is [System.Collections.IDictionary]) {
            foreach ($existingHostKey in @($existingHostMap.Keys)) {
                $normalizedExistingHostKey = if ($existingHostKey) { ('' + $existingHostKey).Trim() } else { '' }
                if ([string]::IsNullOrWhiteSpace($normalizedExistingHostKey)) { continue }
                $existingPortMap = $existingHostMap[$existingHostKey]
                $typedPortMap = $null
                if ($existingPortMap -is [System.Collections.Generic.Dictionary[string,StateTrace.Models.InterfaceCacheEntry]]) {
                    $typedPortMap = $existingPortMap
                } elseif ($existingPortMap -is [System.Collections.IDictionary]) {
                    $typedPortMap = New-Object 'System.Collections.Generic.Dictionary[string,StateTrace.Models.InterfaceCacheEntry]' ([System.StringComparer]::OrdinalIgnoreCase)
                    foreach ($existingPortKey in @($existingPortMap.Keys)) {
                        $normalizedExistingPortKey = if ($existingPortKey) { ('' + $existingPortKey).Trim() } else { '' }
                        if ([string]::IsNullOrWhiteSpace($normalizedExistingPortKey)) { continue }
                        $typedPortMap[$normalizedExistingPortKey] = $existingPortMap[$existingPortKey]
                    }
                }
                if ($typedPortMap) {
                    $typedHostMap[$normalizedExistingHostKey] = $typedPortMap
                }
            }
        }
        $entry.HostMap = $typedHostMap
    }

    $normalizedRows = New-Object 'System.Collections.Generic.Dictionary[string,StateTrace.Models.InterfaceCacheEntry]' ([System.StringComparer]::OrdinalIgnoreCase)
    if ($RowsByPort) {
        foreach ($key in $RowsByPort.Keys) {
            $portKey = ('' + $key).Trim()
            if ([string]::IsNullOrWhiteSpace($portKey)) { continue }
            $value = $RowsByPort[$key]
            if ($null -eq $value) { continue }

            $cacheEntry = $null
            try {
                $cacheEntry = ConvertTo-InterfaceCacheEntryObject -InputObject $value
            } catch {
                $cacheEntry = $null
            }

            if ($cacheEntry) {
                $normalizedRows[$portKey] = $cacheEntry
            }
        }
    }

    $persistedPortCount = [int]$normalizedRows.Count
    $typedHostMap[$hostKey] = $normalizedRows
    $entry.CachedAt = Get-Date

    $total = 0
    foreach ($hostEntry in $entry.HostMap.Values) {
        if ($hostEntry -is [System.Collections.IDictionary]) {
            $total += $hostEntry.Count
        } elseif ($hostEntry -is [System.Collections.ICollection]) {
            $total += $hostEntry.Count
        }
    }
    $entry.TotalRows = $total
    $entry.HostCount = $entry.HostMap.Count
    Set-SharedSiteInterfaceCacheEntry -SiteKey $siteKey -Entry $entry

    $typedHostMapType = ''
    try { if ($typedHostMap) { $typedHostMapType = '' + $typedHostMap.GetType().FullName } } catch { $typedHostMapType = '' }
    $typedHostMapIsTyped = $typedHostMap -is [System.Collections.Generic.Dictionary[string,System.Collections.Generic.Dictionary[string,StateTrace.Models.InterfaceCacheEntry]]]
    $convertedToTyped = $typedHostMapIsTyped -and (-not $previousHostMapWasTyped)
    $hostMapReused = [object]::ReferenceEquals($typedHostMap, $originalHostMapReference)
    $entryHostCount = [int]$entry.HostCount
    $entryTotalRows = [int]$entry.TotalRows
    $hostCountDelta = $entryHostCount - $previousHostCount
    $portCountDelta = $entryTotalRows - $previousPortCount
    try {
        TelemetryModule\Write-StTelemetryEvent -Name 'InterfaceSiteCacheHostPersisted' -Payload @{
            Site                      = $siteKey
            Hostname                  = $hostKey
            PreviousHostMapType       = $previousHostMapType
            PreviousHostMapWasTyped   = [bool]$previousHostMapWasTyped
            PreviousHostCount         = $previousHostCount
            PreviousPortCount         = $previousPortCount
            ConvertedToTyped          = [bool]$convertedToTyped
            HostMapReused             = [bool]$hostMapReused
            TypedHostMapType          = $typedHostMapType
            PersistedPortCount        = $persistedPortCount
            EntryHostCount            = $entryHostCount
            EntryHostCountDelta       = $hostCountDelta
            EntryTotalRows            = $entryTotalRows
            EntryTotalRowsDelta       = $portCountDelta
            SharedStoreUpdated        = $true
        }
    } catch { }
}

function Get-InterfacePortBatchChunkSize {
    [CmdletBinding()]
    param()

    $size = 24
    try {
        if ($script:InterfacePortStreamChunkSize -is [int] -and $script:InterfacePortStreamChunkSize -gt 0) {
            $size = [int]$script:InterfacePortStreamChunkSize
        } elseif ($script:InterfacePortStreamChunkSize) {
            $candidate = [int]$script:InterfacePortStreamChunkSize
            if ($candidate -gt 0) { $size = $candidate }
        }
    } catch {
        $size = 24
    }

    if ($size -le 0) { $size = 24 }
    return $size
}

function Set-InterfacePortStreamData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [Parameter(Mandatory)][datetime]$RunDate,
        [Parameter(Mandatory)][System.Collections.IEnumerable]$InterfaceRows,
        [string]$BatchId
    )

    $hostKey = ('' + $Hostname).Trim()
    if ([string]::IsNullOrWhiteSpace($hostKey)) { return }

    $normalizedBatchId = $BatchId
    if ([string]::IsNullOrWhiteSpace($normalizedBatchId)) {
        $normalizedBatchId = [guid]::NewGuid().ToString()
    }

    $rowsList = New-Object 'System.Collections.Generic.List[psobject]'
    $rowsReused = 0
    $rowsCloned = 0
    $runDateText = $RunDate.ToString('yyyy-MM-dd HH:mm:ss')

    $cloneStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    foreach ($row in $InterfaceRows) {
        if ($null -eq $row) { continue }

        $clone = $null
        if ($row -is [psobject]) {
            $clone = $row
            $rowsReused++
        } elseif ($row -is [System.Collections.IDictionary]) {
            $rowsCloned++
            $clone = [PSCustomObject]@{}
            foreach ($key in $row.Keys) {
                $clone | Add-Member -NotePropertyName $key -NotePropertyValue $row[$key] -Force
            }
        } else {
            $rowsCloned++
            $clone = New-Object psobject
            try {
                foreach ($prop in $row.PSObject.Properties) {
                    $clone | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
                }
            } catch {
                $clone = [PSCustomObject]@{}
            }
        }

        $hostnameProp = $clone.PSObject.Properties['Hostname']
        if ($hostnameProp) {
            if ([string]::IsNullOrWhiteSpace(('' + $hostnameProp.Value))) {
                $hostnameProp.Value = $hostKey
            }
        } else {
            $clone | Add-Member -NotePropertyName Hostname -NotePropertyValue $hostKey -Force
        }

        if (-not $clone.PSObject.Properties['IsSelected']) {
            $clone | Add-Member -NotePropertyName IsSelected -NotePropertyValue $false -Force
        }

        $rowsList.Add($clone) | Out-Null
    }
    $cloneStopwatch.Stop()
    $cloneDurationMs = [Math]::Round($cloneStopwatch.Elapsed.TotalMilliseconds, 3)

    $stateStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $state = [PSCustomObject]@{
        Hostname       = $hostKey
        RunDate        = $RunDate
        BatchId        = $normalizedBatchId
        SourceRows     = $rowsList
        Queue          = $null
        TotalPorts     = [int]$rowsList.Count
        PortsDelivered = 0
        Completed      = ($rowsList.Count -eq 0)
        Created        = Get-Date
        Source         = 'parser'
        BatchCount     = 0
    }
    $script:InterfacePortStreamStore[$hostKey] = $state
    $stateStopwatch.Stop()
    $stateDurationMs = [Math]::Round($stateStopwatch.Elapsed.TotalMilliseconds, 3)

    $script:LastInterfacePortStreamMetrics = [pscustomobject]@{
        Hostname                   = $hostKey
        BatchId                    = $normalizedBatchId
        RunDate                    = $runDateText
        RowsReceived               = [int]$rowsList.Count
        StreamCloneDurationMs      = $cloneDurationMs
        StreamStateUpdateDurationMs= $stateDurationMs
        RowsReused                 = $rowsReused
        RowsCloned                 = $rowsCloned
    }

    $script:LastInterfacePortQueueMetrics = $null

    try {
        TelemetryModule\Write-StTelemetryEvent -Name 'InterfacePortStreamMetrics' -Payload @{
            Hostname = $hostKey
            BatchId  = $normalizedBatchId
            RunDate  = $runDateText
            RowsReceived = [int]$rowsList.Count
            RowsReused   = $rowsReused
            RowsCloned   = $rowsCloned
            StreamCloneDurationMs       = $cloneDurationMs
            StreamStateUpdateDurationMs = $stateDurationMs
        }
    } catch { }
}

function Initialize-InterfacePortStream {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [int]$ChunkSize
    )

    $hostKey = ('' + $Hostname).Trim()
    if ([string]::IsNullOrWhiteSpace($hostKey)) { return }
    $chunkSource = 'Override'
    if ($ChunkSize -and $ChunkSize -gt 0) {
        $chunk = [int]$ChunkSize
    } else {
        $chunk = Get-InterfacePortBatchChunkSize
        $chunkSource = 'Default'
    }
    if ($chunk -le 0) { $chunk = 24 }
    $baseChunk = $chunk

    $state = $null
    if ($script:InterfacePortStreamStore.ContainsKey($hostKey)) {
        $state = $script:InterfacePortStreamStore[$hostKey]
    }

    if (-not $state) {
        $interfaces = Get-InterfaceInfo -Hostname $hostKey
        if (-not $interfaces) { $interfaces = @() }
        $list = New-Object 'System.Collections.Generic.List[psobject]'
        foreach ($item in $interfaces) {
            if ($null -eq $item) { continue }
            if ($item -is [psobject]) {
                $list.Add($item) | Out-Null
            } elseif ($item -is [System.Collections.IDictionary]) {
                $clone = [PSCustomObject]@{}
                foreach ($key in $item.Keys) {
                    $clone | Add-Member -NotePropertyName $key -NotePropertyValue $item[$key] -Force
                }
                $list.Add($clone) | Out-Null
            } else {
                $list.Add([PSCustomObject]$item) | Out-Null
            }
        }

        $state = [PSCustomObject]@{
            Hostname       = $hostKey
            RunDate        = Get-Date
            BatchId        = [guid]::NewGuid().ToString()
            SourceRows     = $list
            Queue          = $null
            TotalPorts     = [int]$list.Count
            PortsDelivered = 0
            Completed      = ($list.Count -eq 0)
            Created        = Get-Date
            Source         = 'repository'
            BatchCount     = 0
        }

        $script:InterfacePortStreamStore[$hostKey] = $state
    }

    $rows = $state.SourceRows
    if (-not $rows) { $rows = @() }

    $queueStartTimestamp = Get-Date
    $queueStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $index = 0
    $materialized = @()
    if ($rows -is [System.Collections.IList]) {
        $materialized = $rows
    } else {
        $materialized = @($rows)
    }

    $total = if ($materialized) { [int]$materialized.Count } else { 0 }
    if ($total -gt 0 -and (-not $ChunkSize -or $ChunkSize -le 0)) {
        $target = [int][Math]::Ceiling($total / 6.0)
        if ($target -lt 1) { $target = 1 }
        $minChunk = [Math]::Max($baseChunk, 24)
        $maxChunk = [Math]::Max(120, $minChunk)
        $dynamicChunk = [Math]::Min($maxChunk, [Math]::Max($minChunk, $target))
        if ($dynamicChunk -gt $total) { $dynamicChunk = $total }
        if ($dynamicChunk -lt 1) { $dynamicChunk = 1 }
        if ($dynamicChunk -ne $chunk) {
            $chunk = $dynamicChunk
            $chunkSource = 'Dynamic'
        }
    }
    $queue = New-Object 'System.Collections.Generic.Queue[psobject]'
    if ($total -gt 0 -and $chunk -gt 0) {
        $batchCount = [int][Math]::Ceiling($total / [double]$chunk)
        $ordinal = 0
        while ($index -lt $materialized.Count) {
            $take = [Math]::Min($chunk, $materialized.Count - $index)
            $segment = New-Object 'System.Collections.Generic.List[psobject]' $take
            for ($i = 0; $i -lt $take; $i++) {
                $segment.Add($materialized[$index + $i]) | Out-Null
            }
            $ordinal++
            $queue.Enqueue([PSCustomObject]@{
                Hostname         = $hostKey
                BatchId          = $state.BatchId
                BatchOrdinal     = $ordinal
                BatchCount       = $batchCount
                Ports            = $segment
                PortsCommitted   = [int]$segment.Count
                TotalPorts       = $total
                PortsDelivered   = 0
                BatchesRemaining = [int]($batchCount - $ordinal)
                RunDate          = $state.RunDate
            })
            $index += $take
        }
        $state.BatchCount = $batchCount
    } else {
        $state.BatchCount = 0
    }

    $state.Queue = $queue
    $queueStopwatch.Stop()
    $queueBuildDurationMs = [Math]::Round($queueStopwatch.Elapsed.TotalMilliseconds, 3)
    $queueBuildDelayMs = 0.0
    if ($state.PSObject.Properties.Name -contains 'Created' -and $state.Created) {
        try {
            $queueBuildDelayMs = [Math]::Round(($queueStartTimestamp - $state.Created).TotalMilliseconds, 3)
        } catch {
            $queueBuildDelayMs = 0.0
        }
        if ($queueBuildDelayMs -lt 0) { $queueBuildDelayMs = 0.0 }
    }
    try {
        $initializedAt = Get-Date
        if ($state.PSObject.Properties['QueueInitializedAt']) {
            $state.QueueInitializedAt = $initializedAt
        } else {
            $state | Add-Member -NotePropertyName QueueInitializedAt -NotePropertyValue $initializedAt -Force
        }
    } catch { }
    $state.TotalPorts = $total
    $state.PortsDelivered = 0
    $state.Completed = ($queue.Count -eq 0)

    $script:LastInterfacePortQueueMetrics = [pscustomobject]@{
        Hostname             = $hostKey
        BatchId              = $state.BatchId
        QueueBuildDurationMs = $queueBuildDurationMs
        QueueBuildDelayMs    = $queueBuildDelayMs
        BatchCount           = [int]$state.BatchCount
        TotalPorts           = [int]$state.TotalPorts
        ChunkSize            = $chunk
        ChunkSource          = $chunkSource
    }

    try {
        TelemetryModule\Write-StTelemetryEvent -Name 'InterfacePortQueueMetrics' -Payload @{
            Hostname             = $hostKey
            BatchId              = $state.BatchId
            QueueBuildDurationMs = $queueBuildDurationMs
            QueueBuildDelayMs    = $queueBuildDelayMs
            BatchCount           = [int]$state.BatchCount
            TotalPorts           = [int]$state.TotalPorts
            ChunkSize            = $chunk
            ChunkSource          = $chunkSource
        }
    } catch { }
}

function Get-InterfacePortStreamStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Hostname)

    $hostKey = ('' + $Hostname).Trim()
    if ([string]::IsNullOrWhiteSpace($hostKey)) { return $null }

    if (-not $script:InterfacePortStreamStore.ContainsKey($hostKey)) { return $null }
    $state = $script:InterfacePortStreamStore[$hostKey]
    if (-not $state) { return $null }

    $remaining = 0
    if ($state.Queue) { $remaining = $state.Queue.Count }

    return [PSCustomObject]@{
        Hostname        = $hostKey
        TotalPorts      = [int]$state.TotalPorts
        PortsDelivered  = [int]$state.PortsDelivered
        BatchesRemaining= [int]$remaining
        Completed       = [bool]$state.Completed
        BatchCount      = [int]$state.BatchCount
    }
}

function Get-InterfacePortBatch {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Hostname)

    $hostKey = ('' + $Hostname).Trim()
    if ([string]::IsNullOrWhiteSpace($hostKey)) { return $null }
    if (-not $script:InterfacePortStreamStore.ContainsKey($hostKey)) { return $null }

    $state = $script:InterfacePortStreamStore[$hostKey]
    if (-not $state -or -not $state.Queue -or $state.Queue.Count -eq 0) { return $null }

    $batch = $state.Queue.Dequeue()
    if (-not $batch) { return $null }

    $ports = $batch.Ports
    $portCount = if ($ports -is [System.Collections.ICollection]) { [int]$ports.Count } else { @($ports).Count }
    $state.PortsDelivered += $portCount
    $remaining = if ($state.Queue) { [int]$state.Queue.Count } else { 0 }
    if ($remaining -le 0) { $state.Completed = $true }

    return [PSCustomObject]@{
        Hostname         = $hostKey
        BatchId          = $batch.BatchId
        BatchOrdinal     = $batch.BatchOrdinal
        BatchCount       = $batch.BatchCount
        Ports            = $ports
        PortsCommitted   = $portCount
        TotalPorts       = [int]$state.TotalPorts
        PortsDelivered   = [int]$state.PortsDelivered
        BatchesRemaining = $remaining
        RunDate          = $state.RunDate
        Completed        = ($remaining -eq 0)
    }
}

function Clear-InterfacePortStream {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Hostname)

    $hostKey = ('' + $Hostname).Trim()
    if ([string]::IsNullOrWhiteSpace($hostKey)) { return }
    if ($script:InterfacePortStreamStore.ContainsKey($hostKey)) {
        $script:InterfacePortStreamStore.Remove($hostKey) | Out-Null
    }
    if ($script:LastInterfacePortQueueMetrics -and $script:LastInterfacePortQueueMetrics.Hostname -eq $hostKey) {
        $script:LastInterfacePortQueueMetrics = $null
    }
}

function Get-LastInterfacePortStreamMetrics {
    [CmdletBinding()]
    param()

    return $script:LastInterfacePortStreamMetrics
}

function Get-LastInterfacePortQueueMetrics {
    [CmdletBinding()]
    param()

    return $script:LastInterfacePortQueueMetrics
}

function Get-LastInterfaceSiteCacheMetrics {
    [CmdletBinding()]
    param()

    return $script:LastInterfaceSiteCacheMetrics
}

function Get-LastInterfaceSiteHydrationMetrics {
    [CmdletBinding()]
    param()

    return $script:LastInterfaceSiteHydrationMetrics
}

function Set-InterfacePortDispatchMetrics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [string]$BatchId,
        [int]$BatchOrdinal,
        [int]$BatchCount,
        [int]$BatchSize,
        [int]$PortsDelivered,
        [int]$TotalPorts,
        [double]$DispatcherDurationMs,
        [double]$AppendDurationMs,
        [double]$IndicatorDurationMs
    )

    $hostKey = ('' + $Hostname).Trim()
    if ([string]::IsNullOrWhiteSpace($hostKey)) { return }

    $normalizedBatchId = $null
    if (-not [string]::IsNullOrWhiteSpace($BatchId)) {
        $normalizedBatchId = ('' + $BatchId).Trim()
    }

    $payload = [pscustomobject]@{
        Hostname             = $hostKey
        BatchId              = $normalizedBatchId
        BatchOrdinal         = if ($BatchOrdinal -gt 0) { [int]$BatchOrdinal } else { 0 }
        BatchCount           = if ($BatchCount -gt 0) { [int]$BatchCount } else { 0 }
        BatchSize            = if ($BatchSize -gt 0) { [int]$BatchSize } else { 0 }
        PortsDelivered       = if ($PortsDelivered -gt 0) { [int]$PortsDelivered } else { 0 }
        TotalPorts           = if ($TotalPorts -gt 0) { [int]$TotalPorts } else { 0 }
        DispatcherDurationMs = if ($PSBoundParameters.ContainsKey('DispatcherDurationMs')) { [Math]::Round([double]$DispatcherDurationMs, 3) } else { 0.0 }
        AppendDurationMs     = if ($PSBoundParameters.ContainsKey('AppendDurationMs')) { [Math]::Round([double]$AppendDurationMs, 3) } else { 0.0 }
        IndicatorDurationMs  = if ($PSBoundParameters.ContainsKey('IndicatorDurationMs')) { [Math]::Round([double]$IndicatorDurationMs, 3) } else { 0.0 }
    }

    $script:LastInterfacePortDispatchMetrics = $payload

    try {
        TelemetryModule\Write-StTelemetryEvent -Name 'InterfacePortDispatchMetrics' -Payload @{
            Hostname             = $payload.Hostname
            BatchId              = $payload.BatchId
            BatchOrdinal         = $payload.BatchOrdinal
            BatchCount           = $payload.BatchCount
            BatchSize            = $payload.BatchSize
            PortsDelivered       = $payload.PortsDelivered
            TotalPorts           = $payload.TotalPorts
            DispatcherDurationMs = $payload.DispatcherDurationMs
            AppendDurationMs     = $payload.AppendDurationMs
            IndicatorDurationMs  = $payload.IndicatorDurationMs
        }
    } catch { }
}

function Get-LastInterfacePortDispatchMetrics {
    [CmdletBinding()]
    param()

    return $script:LastInterfacePortDispatchMetrics
}

function Import-DatabaseModule {
    [CmdletBinding()]
    param()
    try {
        # Check by module name rather than path; avoids multiple loads when
        # different relative paths point at the same module.  If DatabaseModule
        # isn't loaded yet, attempt to import it from this folder.  The
        # Force/Global flags mirror the original behaviour but only run once.
        if (-not (Get-Module -Name DatabaseModule)) {
            $dbModulePath = Join-Path $PSScriptRoot 'DatabaseModule.psm1'
            if (Test-Path $dbModulePath) {
                Import-Module $dbModulePath -Force -Global -ErrorAction SilentlyContinue | Out-Null
            }
        }
    } catch {
        # Swallow any import errors; downstream functions will handle missing cmdlets.
    }
}

# Retrieve the currently selected site, building and room from the main


function Update-SiteZoneCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Site,
        [string]$Zone
    )
    if ([string]::IsNullOrWhiteSpace($Site)) { return }
    $zoneKey = if ([string]::IsNullOrWhiteSpace($Zone) -or ($Zone -ieq 'All Zones')) { '' } else { '' + $Zone }
    $key = "$Site|$zoneKey"
    if ($global:LoadedSiteZones.ContainsKey($key)) { return }
    $global:LoadedSiteZones[$key] = $true

    $hostNames = @()
    try {
        if ($global:DeviceMetadata) {
            foreach ($entry in $global:DeviceMetadata.GetEnumerator()) {
                $hn = $entry.Key
                $meta = $entry.Value
                if ($meta.Site -and $meta.Site -ne $Site) { continue }
                if ($zoneKey -ne '') {
                    $mZone = $null
                    try {
                        if ($meta.PSObject.Properties['Zone']) { $mZone = '' + $meta.Zone }
                    } catch {
                        $mZone = $null
                    }
                    if ($mZone -and $mZone -ne $zoneKey) { continue }
                }
                $hostNames += $hn
            }
        } elseif (Get-Command -Name Get-InterfaceHostnames -ErrorAction SilentlyContinue) {
            $names = Get-InterfaceHostnames -Site $Site
            foreach ($n in $names) {
                if ($zoneKey -ne '') {
                    $parts = ($n -split '-')
                    if ($parts.Count -ge 2) {
                        $zonePart = $parts[1]
                        if ($zonePart -ne $zoneKey) { continue }
                    }
                }
                $hostNames += $n
            }
        }
    } catch {
        return
    }

    if (-not $hostNames -or $hostNames.Count -eq 0) { return }

    $newRows = New-Object 'System.Collections.Generic.List[object]'
    foreach ($hn in $hostNames) {
        if ($global:DeviceInterfaceCache.ContainsKey($hn)) { continue }
        try {
            $ifaceList = Get-InterfaceInfo -Hostname $hn
            if ($ifaceList) {
                foreach ($row in $ifaceList) { [void]$newRows.Add($row) }
            }
        } catch {
        }
    }

    if ($newRows.Count -gt 0) {
        try {
            if (-not $global:AllInterfaces) {
                $global:AllInterfaces = $newRows
            } else {
                foreach ($r in $newRows) { [void]$global:AllInterfaces.Add($r) }
            }
        } catch {
        }
    }
}
function Invoke-ParallelDbQuery {
    [CmdletBinding()]
    param(
        [string[]]$DbPaths,
        [string]$Sql
    )
    if (-not $DbPaths -or $DbPaths.Count -eq 0) {
        return @()
    }
    try { Import-DatabaseModule } catch {}
    $modulePath = Join-Path $PSScriptRoot 'DatabaseModule.psm1'
    $maxThreads = [Math]::Max(1, [Environment]::ProcessorCount)
    $pool = [runspacefactory]::CreateRunspacePool(1, $maxThreads)
    $pool.Open()
    $jobs = @()
    foreach ($dbPath in $DbPaths) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool
        $null = $ps.AddScript({
            param($dbPathArg, $sqlArg, $modPath)
            try { Import-Module -Name $modPath -DisableNameChecking -Force } catch {}
            try {
                return Invoke-DbQuery -DatabasePath $dbPathArg -Sql $sqlArg
            } catch {
                return $null
            }
        }).AddArgument($dbPath).AddArgument($Sql).AddArgument($modulePath)
        $job = [pscustomobject]@{ PS = $ps; AsyncResult = $ps.BeginInvoke() }
        $jobs += $job
    }
    $results = New-Object 'System.Collections.Generic.List[object]'
    foreach ($job in $jobs) {
        try {
            $dt = $job.PS.EndInvoke($job.AsyncResult)
            if ($dt) { [void]$results.Add($dt) }
        } catch {}
        finally {
            $job.PS.Dispose()
        }
    }
    $pool.Close()
    $pool.Dispose()
    return $results.ToArray()
}
function Get-GlobalInterfaceSnapshot {
    [CmdletBinding()]
    param(
        [string]$Site,
        [string]$ZoneSelection,
        [string]$ZoneToLoad
    )

    $siteValue = if ($Site) { '' + $Site } else { '' }
    $zoneSelectionValue = if ($ZoneSelection) { '' + $ZoneSelection } else { '' }
    $zoneLoadValue = if ($PSBoundParameters.ContainsKey('ZoneToLoad')) { '' + $ZoneToLoad } else { '' }

    $interfaces = New-Object 'System.Collections.Generic.List[object]'
    $appendRows = {
        param($hostname, $rows)
        if (-not $rows) { return }
        foreach ($row in $rows) {
            if (-not $row) { continue }
            try {
                if (-not $row.PSObject.Properties['Hostname']) {
                    $row | Add-Member -NotePropertyName Hostname -NotePropertyValue ($hostname) -ErrorAction SilentlyContinue
                }
            } catch {}
            try {
                if (-not $row.PSObject.Properties['IsSelected']) {
                    $row | Add-Member -NotePropertyName IsSelected -NotePropertyValue $false -ErrorAction SilentlyContinue
                }
            } catch {}
            [void]$interfaces.Add($row)
        }
    }

    if ([string]::IsNullOrWhiteSpace($siteValue) -or [System.StringComparer]::OrdinalIgnoreCase.Equals($siteValue, 'All Sites')) {
        foreach ($kv in $global:DeviceInterfaceCache.GetEnumerator()) {
            & $appendRows $kv.Key $kv.Value
        }
    } else {
        $loadArg = $zoneLoadValue
        try { Update-SiteZoneCache -Site $siteValue -Zone $loadArg | Out-Null } catch {}
        foreach ($kv in $global:DeviceInterfaceCache.GetEnumerator()) {
            $hostname = $kv.Key
            $rows = $kv.Value
            if (-not $rows) { continue }
            $parts = ('' + $hostname) -split '-'
            $sitePart = if ($parts.Length -ge 1) { $parts[0] } else { '' }
            if ([System.StringComparer]::OrdinalIgnoreCase.Compare($sitePart, $siteValue) -ne 0) { continue }
            $zonePart = if ($parts.Length -ge 2) { $parts[1] } else { '' }

            if (-not [string]::IsNullOrWhiteSpace($zoneSelectionValue) -and -not [System.StringComparer]::OrdinalIgnoreCase.Equals($zoneSelectionValue, 'All Zones')) {
                if ([System.StringComparer]::OrdinalIgnoreCase.Compare($zonePart, $zoneSelectionValue) -ne 0) { continue }
            } elseif (-not [string]::IsNullOrWhiteSpace($loadArg)) {
                if ([System.StringComparer]::OrdinalIgnoreCase.Compare($zonePart, $loadArg) -ne 0) { continue }
            }

            & $appendRows $hostname $rows
        }
    }

    return ,($interfaces.ToArray())
}

function Update-GlobalInterfaceList {
    [CmdletBinding()]
    param(
        [string]$Site,
        [string]$ZoneSelection,
        [string]$ZoneToLoad
    )

    $snapshot = Get-GlobalInterfaceSnapshot @PSBoundParameters
    if ($snapshot -and $snapshot.Length -gt 0) {
        $global:AllInterfaces = [System.Collections.Generic.List[object]]::new($snapshot)
    } else {
        $global:AllInterfaces = [System.Collections.Generic.List[object]]::new()
    }
    return $global:AllInterfaces
}

function Get-InterfacesForSite {
    [CmdletBinding()]
    param(
        [string]$Site,
        [string]$ZoneSelection,
        [string]$ZoneToLoad,
        [object]$Connection
    )

    $snapshot = Get-GlobalInterfaceSnapshot @PSBoundParameters
    if ($snapshot -and $snapshot.Length -gt 0) {
        $global:AllInterfaces = [System.Collections.Generic.List[object]]::new($snapshot)
    } else {
        $global:AllInterfaces = [System.Collections.Generic.List[object]]::new()
    }
    return $global:AllInterfaces
}

function Get-InterfacesForSite {
    [CmdletBinding()]
    param(
        [string]$Site,
        [object]$Connection
    )

    $siteName = if ($Site) { '' + $Site } else { '' }
    if ([string]::IsNullOrWhiteSpace($siteName) -or
        ([System.StringComparer]::OrdinalIgnoreCase.Equals($siteName, 'All Sites')) -or
        ([System.StringComparer]::OrdinalIgnoreCase.Equals($siteName, 'All')))
    {
        $combined = New-Object 'System.Collections.Generic.List[object]'
        $dbPaths = Get-AllSiteDbPaths
        foreach ($p in $dbPaths) {
            $code = ''
            try { $code = [System.IO.Path]::GetFileNameWithoutExtension($p) } catch { $code = '' }
            if (-not [string]::IsNullOrWhiteSpace($code)) {
                $siteList = Get-InterfacesForSite -Site $code -Connection $Connection
                if ($siteList) {
                    foreach ($item in $siteList) { [void]$combined.Add($item) }
                }
            }
        }
        $comparison = [System.Comparison[object]]{
            param($a, $b)
            $hnc = [System.StringComparer]::OrdinalIgnoreCase.Compare($a.Hostname, $b.Hostname)
            if ($hnc -ne 0) { return $hnc }
            return [System.StringComparer]::Ordinal.Compare($a.PortSort, $b.PortSort)
        }
        try { $combined.Sort($comparison) } catch {}

        $script:LastInterfaceSiteHydrationMetrics = [PSCustomObject]@{
            Site                    = $siteName
            Provider                = 'Aggregate'
            QueryAttempts           = 0
            QueryDurationMs         = 0.0
            ExclusiveRetryCount     = 0
            ExclusiveWaitDurationMs = 0.0
            ExecuteDurationMs       = 0.0
            MaterializeDurationMs   = 0.0
            TemplateLoadDurationMs  = 0.0
            ResultRowCount          = [int]$combined.Count
            Succeeded               = $true
            Timestamp               = Get-Date
        }

        return $combined
    }

    $siteCode = $siteName.Trim()
    if ([string]::IsNullOrWhiteSpace($siteCode)) {
        $script:LastInterfaceSiteHydrationMetrics = [PSCustomObject]@{
            Site                    = $siteName
            Provider                = 'InvalidSite'
            QueryAttempts           = 0
            QueryDurationMs         = 0.0
            ExclusiveRetryCount     = 0
            ExclusiveWaitDurationMs = 0.0
            ExecuteDurationMs       = 0.0
            MaterializeDurationMs   = 0.0
            TemplateLoadDurationMs  = 0.0
            ResultRowCount          = 0
            Succeeded               = $false
            Timestamp               = Get-Date
        }
        return (New-Object 'System.Collections.Generic.List[object]')
    }

    $hydrationDetail = [PSCustomObject]@{
        Site                    = $siteCode
        Provider                = 'Unknown'
        QueryAttempts           = 0
        QueryDurationMs         = 0.0
        ExclusiveRetryCount     = 0
        ExclusiveWaitDurationMs = 0.0
        ExecuteDurationMs       = 0.0
        MaterializeDurationMs   = 0.0
        TemplateLoadDurationMs  = 0.0
        ResultRowCount          = 0
        Succeeded               = $false
        Timestamp               = Get-Date
    }

    try {
        if ($script:SiteInterfaceCache.ContainsKey($siteCode)) {
            $entry = $script:SiteInterfaceCache[$siteCode]
            if ($entry -and $entry.PSObject.Properties['List'] -and $entry.PSObject.Properties['DbTime']) {
                $dbPath = Get-DbPathForSite -Site $siteCode
                $currentTime = $null
                try { $currentTime = (Get-Item -LiteralPath $dbPath).LastWriteTime } catch {}
                if ($currentTime -and ($entry.DbTime -eq $currentTime)) {
                    $hydrationDetail.Provider = 'Cache'
                    $hydrationDetail.ResultRowCount = if ($entry.List) { [int]$entry.List.Count } else { 0 }
                    $hydrationDetail.Succeeded = $true
                    $script:LastInterfaceSiteHydrationMetrics = $hydrationDetail
                    return $entry.List
                }
            }
        }
    } catch {}

    $dbFile = Get-DbPathForSite -Site $siteCode
    if (-not (Test-Path $dbFile)) {
        $hydrationDetail.Provider = 'MissingDatabase'
        $hydrationDetail.Succeeded = $true
        $script:LastInterfaceSiteHydrationMetrics = $hydrationDetail
        return (New-Object 'System.Collections.Generic.List[object]')
    }

    $siteEsc = $siteCode
    $siteAliasEsc = $null
    $sitePredicate = $null
    try {
        Import-DatabaseModule
        $siteEsc = DatabaseModule\Get-SqlLiteral -Value $siteCode
        $siteAlphaPrefix = ($siteCode -replace '[^A-Za-z]').Trim()
        if (-not [string]::IsNullOrWhiteSpace($siteAlphaPrefix) -and
            -not [System.StringComparer]::OrdinalIgnoreCase.Equals($siteAlphaPrefix, $siteCode)) {
            $siteAliasEsc = DatabaseModule\Get-SqlLiteral -Value $siteAlphaPrefix
        }
    } catch {
        $siteEsc = $siteCode -replace "'", "''"
        $siteAlphaPrefix = ($siteCode -replace '[^A-Za-z]').Trim()
        if (-not [string]::IsNullOrWhiteSpace($siteAlphaPrefix) -and
            -not [System.StringComparer]::OrdinalIgnoreCase.Equals($siteAlphaPrefix, $siteCode)) {
            $siteAliasEsc = $siteAlphaPrefix -replace "'", "''"
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($siteAliasEsc)) {
        $sitePredicate = "IN ('{0}','{1}')" -f $siteEsc, $siteAliasEsc
    } else {
        $sitePredicate = "= '$siteEsc'"
    }
    $sqlSite = @"
SELECT i.Hostname, i.Port, i.Name, i.Status, i.VLAN, i.Duplex, i.Speed, i.Type,
       i.LearnedMACs, i.AuthState, i.AuthMode, i.AuthClientMAC,
       ds.Site, ds.Building, ds.Room, ds.Make,
       i.AuthTemplate, i.Config, i.ConfigStatus, i.PortColor, i.ToolTip
FROM Interfaces AS i
LEFT JOIN DeviceSummary AS ds ON i.Hostname = ds.Hostname
WHERE ds.Site $sitePredicate
ORDER BY i.Hostname, i.Port
"@

    $rows = New-Object 'System.Collections.Generic.List[object]'
    $rowsAreOrdered = $false

    $dataSet = $null
    $estimatedRowTotal = 0
    $useAdodbConnection = Test-IsAdodbConnectionInternal -Connection $Connection
    $recordsetEnumerateDurationMs = 0.0
    $recordsetProjectDurationMs = 0.0
    if ($useAdodbConnection) {
        $hydrationDetail.Provider = 'ADODB'
        $recordset = $null
        $rowsFromConnection = New-Object 'System.Collections.Generic.List[object]'
        $executeStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $recordset = $Connection.Execute($sqlSite)
        } catch {
            $rowsFromConnection.Clear() | Out-Null
        } finally {
            $executeStopwatch.Stop()
            $hydrationDetail.ExecuteDurationMs = [Math]::Round($executeStopwatch.Elapsed.TotalMilliseconds, 3)
        }

        $rawRows = $null
        $fieldNames = @()
        $rowCount = 0
        $recordsetEnumerateDurationMs = 0.0
        try {
            if ($recordset -and $recordset.State -eq 1) {
                $enumerateStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                try {
                    try {
                        $rawRows = $recordset.GetRows()
                    } catch {
                        $rawRows = $null
                    }
                    $fieldCount = 0
                    try {
                        $fieldCount = $recordset.Fields.Count
                    } catch {
                        $fieldCount = 0
                    }
                    if ($fieldCount -gt 0) {
                        $fieldNames = New-Object string[] $fieldCount
                        for ($fieldIndex = 0; $fieldIndex -lt $fieldCount; $fieldIndex++) {
                            $fieldName = ''
                            try {
                                $fieldName = '' + $recordset.Fields.Item($fieldIndex).Name
                            } catch {
                                $fieldName = ''
                            }
                            $fieldNames[$fieldIndex] = $fieldName
                        }
                    } else {
                        $fieldNames = @()
                    }
                    if ($rawRows -and ($rawRows.Rank -ge 2)) {
                        $rowUpper = $rawRows.GetUpperBound(1)
                        if ($rowUpper -ge 0) {
                            $rowCount = $rowUpper + 1
                        }
                    }
                } finally {
                    $enumerateStopwatch.Stop()
                    $recordsetEnumerateDurationMs = [Math]::Round($enumerateStopwatch.Elapsed.TotalMilliseconds, 3)
                    $hydrationDetail | Add-Member -NotePropertyName RecordsetEnumerateDurationMs -NotePropertyValue $recordsetEnumerateDurationMs -Force
                    $hydrationDetail.QueryDurationMs = [Math]::Round($hydrationDetail.ExecuteDurationMs + $recordsetEnumerateDurationMs, 3)
                }
            } elseif ($hydrationDetail.QueryDurationMs -le 0) {
                $hydrationDetail.QueryDurationMs = $hydrationDetail.ExecuteDurationMs
            }
        } finally {
            if ($recordset) {
                try { $recordset.Close() } catch {}
            }
        }

        if ($rowCount -gt 0) {
            $estimatedRowTotal = [int][Math]::Max($estimatedRowTotal, $rowCount)
        }

        if ($rowCount -gt 0 -and $fieldNames -and $fieldNames.Length -gt 0 -and $rawRows) {
            $fieldIndexByName = @{}
            for ($fieldIndex = 0; $fieldIndex -lt $fieldNames.Length; $fieldIndex++) {
                $fieldName = $fieldNames[$fieldIndex]
                if (-not [string]::IsNullOrWhiteSpace($fieldName)) {
                    $fieldIndexByName[$fieldName.ToLowerInvariant()] = $fieldIndex
                }
            }

            $idxHostname      = if ($fieldIndexByName.ContainsKey('hostname'))      { [int]$fieldIndexByName['hostname'] }      else { -1 }
            $idxPort          = if ($fieldIndexByName.ContainsKey('port'))          { [int]$fieldIndexByName['port'] }          else { -1 }
            $idxName          = if ($fieldIndexByName.ContainsKey('name'))          { [int]$fieldIndexByName['name'] }          else { -1 }
            $idxStatus        = if ($fieldIndexByName.ContainsKey('status'))        { [int]$fieldIndexByName['status'] }        else { -1 }
            $idxVlan          = if ($fieldIndexByName.ContainsKey('vlan'))          { [int]$fieldIndexByName['vlan'] }          else { -1 }
            $idxDuplex        = if ($fieldIndexByName.ContainsKey('duplex'))        { [int]$fieldIndexByName['duplex'] }        else { -1 }
            $idxSpeed         = if ($fieldIndexByName.ContainsKey('speed'))         { [int]$fieldIndexByName['speed'] }         else { -1 }
            $idxType          = if ($fieldIndexByName.ContainsKey('type'))          { [int]$fieldIndexByName['type'] }          else { -1 }
            $idxLearned       = if ($fieldIndexByName.ContainsKey('learnedmacs'))   { [int]$fieldIndexByName['learnedmacs'] }   else { -1 }
            $idxAuthState     = if ($fieldIndexByName.ContainsKey('authstate'))     { [int]$fieldIndexByName['authstate'] }     else { -1 }
            $idxAuthMode      = if ($fieldIndexByName.ContainsKey('authmode'))      { [int]$fieldIndexByName['authmode'] }      else { -1 }
            $idxAuthClient    = if ($fieldIndexByName.ContainsKey('authclientmac')) { [int]$fieldIndexByName['authclientmac'] } else { -1 }
            $idxSite          = if ($fieldIndexByName.ContainsKey('site'))          { [int]$fieldIndexByName['site'] }          else { -1 }
            $idxBuilding      = if ($fieldIndexByName.ContainsKey('building'))      { [int]$fieldIndexByName['building'] }      else { -1 }
            $idxRoom          = if ($fieldIndexByName.ContainsKey('room'))          { [int]$fieldIndexByName['room'] }          else { -1 }
            $idxMake          = if ($fieldIndexByName.ContainsKey('make'))          { [int]$fieldIndexByName['make'] }          else { -1 }
            $idxAuthTemplate  = if ($fieldIndexByName.ContainsKey('authtemplate'))  { [int]$fieldIndexByName['authtemplate'] }  else { -1 }
            $idxConfig        = if ($fieldIndexByName.ContainsKey('config'))        { [int]$fieldIndexByName['config'] }        else { -1 }
            $idxConfigStatus  = if ($fieldIndexByName.ContainsKey('configstatus'))  { [int]$fieldIndexByName['configstatus'] }  else { -1 }
            $idxPortColor     = if ($fieldIndexByName.ContainsKey('portcolor'))     { [int]$fieldIndexByName['portcolor'] }     else { -1 }
            $idxToolTip       = if ($fieldIndexByName.ContainsKey('tooltip'))       { [int]$fieldIndexByName['tooltip'] }       else { -1 }

            $rowsFromConnection = New-Object 'System.Collections.Generic.List[object]' $rowCount
            $recordsetProjectStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            for ($rowIndex = 0; $rowIndex -lt $rowCount; $rowIndex++) {
                $hostnameVal = ''
                if ($idxHostname -ge 0) {
                    $rawValue = $rawRows.GetValue($idxHostname, $rowIndex)
                    if ($null -ne $rawValue -and $rawValue -ne [System.DBNull]::Value) { $hostnameVal = '' + $rawValue }
                }

                $portVal = ''
                if ($idxPort -ge 0) {
                    $rawValue = $rawRows.GetValue($idxPort, $rowIndex)
                    if ($null -ne $rawValue -and $rawValue -ne [System.DBNull]::Value) { $portVal = '' + $rawValue }
                }

                $nameVal = ''
                if ($idxName -ge 0) {
                    $rawValue = $rawRows.GetValue($idxName, $rowIndex)
                    if ($null -ne $rawValue -and $rawValue -ne [System.DBNull]::Value) { $nameVal = '' + $rawValue }
                }

                $statusVal = ''
                if ($idxStatus -ge 0) {
                    $rawValue = $rawRows.GetValue($idxStatus, $rowIndex)
                    if ($null -ne $rawValue -and $rawValue -ne [System.DBNull]::Value) { $statusVal = '' + $rawValue }
                }

                $vlanVal = ''
                if ($idxVlan -ge 0) {
                    $rawValue = $rawRows.GetValue($idxVlan, $rowIndex)
                    if ($null -ne $rawValue -and $rawValue -ne [System.DBNull]::Value) { $vlanVal = '' + $rawValue }
                }

                $duplexVal = ''
                if ($idxDuplex -ge 0) {
                    $rawValue = $rawRows.GetValue($idxDuplex, $rowIndex)
                    if ($null -ne $rawValue -and $rawValue -ne [System.DBNull]::Value) { $duplexVal = '' + $rawValue }
                }

                $speedVal = ''
                if ($idxSpeed -ge 0) {
                    $rawValue = $rawRows.GetValue($idxSpeed, $rowIndex)
                    if ($null -ne $rawValue -and $rawValue -ne [System.DBNull]::Value) { $speedVal = '' + $rawValue }
                }

                $typeVal = ''
                if ($idxType -ge 0) {
                    $rawValue = $rawRows.GetValue($idxType, $rowIndex)
                    if ($null -ne $rawValue -and $rawValue -ne [System.DBNull]::Value) { $typeVal = '' + $rawValue }
                }

                $learnedVal = ''
                if ($idxLearned -ge 0) {
                    $rawValue = $rawRows.GetValue($idxLearned, $rowIndex)
                    if ($null -ne $rawValue -and $rawValue -ne [System.DBNull]::Value) { $learnedVal = '' + $rawValue }
                }

                $authStateVal = ''
                if ($idxAuthState -ge 0) {
                    $rawValue = $rawRows.GetValue($idxAuthState, $rowIndex)
                    if ($null -ne $rawValue -and $rawValue -ne [System.DBNull]::Value) { $authStateVal = '' + $rawValue }
                }

                $authModeVal = ''
                if ($idxAuthMode -ge 0) {
                    $rawValue = $rawRows.GetValue($idxAuthMode, $rowIndex)
                    if ($null -ne $rawValue -and $rawValue -ne [System.DBNull]::Value) { $authModeVal = '' + $rawValue }
                }

                $authClientVal = ''
                if ($idxAuthClient -ge 0) {
                    $rawValue = $rawRows.GetValue($idxAuthClient, $rowIndex)
                    if ($null -ne $rawValue -and $rawValue -ne [System.DBNull]::Value) { $authClientVal = '' + $rawValue }
                }

                $siteVal = ''
                if ($idxSite -ge 0) {
                    $rawValue = $rawRows.GetValue($idxSite, $rowIndex)
                    if ($null -ne $rawValue -and $rawValue -ne [System.DBNull]::Value) { $siteVal = '' + $rawValue }
                }

                $buildingVal = ''
                if ($idxBuilding -ge 0) {
                    $rawValue = $rawRows.GetValue($idxBuilding, $rowIndex)
                    if ($null -ne $rawValue -and $rawValue -ne [System.DBNull]::Value) { $buildingVal = '' + $rawValue }
                }

                $roomVal = ''
                if ($idxRoom -ge 0) {
                    $rawValue = $rawRows.GetValue($idxRoom, $rowIndex)
                    if ($null -ne $rawValue -and $rawValue -ne [System.DBNull]::Value) { $roomVal = '' + $rawValue }
                }

                $makeVal = ''
                if ($idxMake -ge 0) {
                    $rawValue = $rawRows.GetValue($idxMake, $rowIndex)
                    if ($null -ne $rawValue -and $rawValue -ne [System.DBNull]::Value) { $makeVal = '' + $rawValue }
                }

                $authTemplateVal = ''
                if ($idxAuthTemplate -ge 0) {
                    $rawValue = $rawRows.GetValue($idxAuthTemplate, $rowIndex)
                    if ($null -ne $rawValue -and $rawValue -ne [System.DBNull]::Value) { $authTemplateVal = '' + $rawValue }
                }

                $configVal = ''
                if ($idxConfig -ge 0) {
                    $rawValue = $rawRows.GetValue($idxConfig, $rowIndex)
                    if ($null -ne $rawValue -and $rawValue -ne [System.DBNull]::Value) { $configVal = '' + $rawValue }
                }

                $configStatusVal = ''
                if ($idxConfigStatus -ge 0) {
                    $rawValue = $rawRows.GetValue($idxConfigStatus, $rowIndex)
                    if ($null -ne $rawValue -and $rawValue -ne [System.DBNull]::Value) { $configStatusVal = '' + $rawValue }
                }

                $portColorVal = ''
                if ($idxPortColor -ge 0) {
                    $rawValue = $rawRows.GetValue($idxPortColor, $rowIndex)
                    if ($null -ne $rawValue -and $rawValue -ne [System.DBNull]::Value) { $portColorVal = '' + $rawValue }
                }

                $toolTipVal = ''
                if ($idxToolTip -ge 0) {
                    $rawValue = $rawRows.GetValue($idxToolTip, $rowIndex)
                    if ($null -ne $rawValue -and $rawValue -ne [System.DBNull]::Value) { $toolTipVal = '' + $rawValue }
                }

                $rowObj = [PSCustomObject]@{
                    Hostname      = $hostnameVal
                    Port          = $portVal
                    Name          = $nameVal
                    Status        = $statusVal
                    VLAN          = $vlanVal
                    Duplex        = $duplexVal
                    Speed         = $speedVal
                    Type          = $typeVal
                    LearnedMACs   = $learnedVal
                    AuthState     = $authStateVal
                    AuthMode      = $authModeVal
                    AuthClientMAC = $authClientVal
                    Site          = $siteVal
                    Building      = $buildingVal
                    Room          = $roomVal
                    Make          = $makeVal
                    AuthTemplate  = $authTemplateVal
                    Config        = $configVal
                    ConfigStatus  = $configStatusVal
                    PortColor     = $portColorVal
                    ToolTip       = $toolTipVal
                }
                [void]$rowsFromConnection.Add($rowObj)
            }
            if ($recordsetProjectStopwatch) {
                $recordsetProjectStopwatch.Stop()
                $recordsetProjectDurationMs = [Math]::Round($recordsetProjectStopwatch.Elapsed.TotalMilliseconds, 3)
            }

            $hydrationDetail.QueryAttempts = 1
            $hydrationDetail.ResultRowCount = $rowCount
            $dataSet = $rowsFromConnection
        } elseif ($hydrationDetail.QueryDurationMs -le 0) {
            $hydrationDetail.QueryDurationMs = $hydrationDetail.ExecuteDurationMs
        }
    }

    if ($useAdodbConnection -and -not ($hydrationDetail.PSObject.Properties.Name -contains 'RecordsetEnumerateDurationMs')) {
        $hydrationDetail | Add-Member -NotePropertyName RecordsetEnumerateDurationMs -NotePropertyValue $recordsetEnumerateDurationMs -Force
    }
    if (-not ($hydrationDetail.PSObject.Properties.Name -contains 'RecordsetProjectDurationMs')) {
        $hydrationDetail | Add-Member -NotePropertyName 'RecordsetProjectDurationMs' -NotePropertyValue $recordsetProjectDurationMs -Force
    }

    if (-not $dataSet) {
        $hydrationDetail.Provider = 'AccessRetry'
        $retryTelemetry = $null
        $fallbackStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $dataSet = Invoke-WithAccessExclusiveRetry -Context "Failed to query interfaces for site '$siteCode'" -MaxAttempts 5 -RetryDelayMilliseconds 100 -Operation {
            Invoke-DbQuery -DatabasePath $dbFile -Sql $sqlSite
            } -TelemetrySink ([ref]$retryTelemetry)
        } finally {
            $fallbackStopwatch.Stop()
        }

        if ($retryTelemetry) {
            $hydrationDetail.QueryAttempts = if ($retryTelemetry.PSObject.Properties.Name -contains 'Attempts') { [int]$retryTelemetry.Attempts } else { 0 }
            $hydrationDetail.ExclusiveRetryCount = if ($retryTelemetry.PSObject.Properties.Name -contains 'ExclusiveRetries') { [int]$retryTelemetry.ExclusiveRetries } else { 0 }
            if ($retryTelemetry.PSObject.Properties.Name -contains 'ExclusiveWaitDurationMs') {
                $hydrationDetail.ExclusiveWaitDurationMs = [Math]::Round([double]$retryTelemetry.ExclusiveWaitDurationMs, 3)
            }
            if ($retryTelemetry.PSObject.Properties.Name -contains 'DurationMs') {
                $hydrationDetail.QueryDurationMs = [Math]::Round([double]$retryTelemetry.DurationMs, 3)
                $hydrationDetail.ExecuteDurationMs = $hydrationDetail.QueryDurationMs
            } else {
                $hydrationDetail.QueryDurationMs = [Math]::Round($fallbackStopwatch.Elapsed.TotalMilliseconds, 3)
                $hydrationDetail.ExecuteDurationMs = $hydrationDetail.QueryDurationMs
            }
            if ($retryTelemetry.PSObject.Properties.Name -contains 'Succeeded' -and -not [bool]$retryTelemetry.Succeeded) {
                $hydrationDetail.Succeeded = $false
            }
        } else {
            $hydrationDetail.QueryAttempts = 1
            $hydrationDetail.QueryDurationMs = [Math]::Round($fallbackStopwatch.Elapsed.TotalMilliseconds, 3)
            $hydrationDetail.ExecuteDurationMs = $hydrationDetail.QueryDurationMs
        }
    }

    if ($dataSet) {
        $enum = $null
        if ($dataSet -is [System.Data.DataTable]) {
            $enum = $dataSet.Rows
        } elseif ($dataSet -is [System.Data.DataView]) {
            $enum = $dataSet
        } elseif ($dataSet -is [System.Collections.IEnumerable]) {
            $enum = $dataSet
        }

        $materializePortSortCacheHits = 0L
        $materializePortSortCacheMisses = 0L
        $materializePortSortCacheSize = 0L
        $portSortUniquePorts = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        $portSortMissSamples = New-Object 'System.Collections.Generic.List[object]'
        $portSortMissSampleLimit = 20
        $templateApplyCandidateCount = 0L
        $templateApplyDefaultedCount = 0L
        $templateApplyAuthTemplateMissingCount = 0L
        $templateApplyNoTemplateMatchCount = 0L
        $templateApplyHintAppliedCount = 0L
        $templateApplySetPortColorCount = 0L
        $templateApplySetConfigStatusCount = 0L
        $templateApplySamples = New-Object 'System.Collections.Generic.List[object]'
        $templateApplySampleLimit = 20

        if ($enum) {
            if ($estimatedRowTotal -le 0) {
                try {
                    if ($enum -is [System.Collections.ICollection]) {
                        $estimatedRowTotal = [int][Math]::Max($estimatedRowTotal, $enum.Count)
                    }
                } catch { $estimatedRowTotal = 0 }
            }
            if ($estimatedRowTotal -gt 0 -and ($rows -is [System.Collections.Generic.List[object]])) {
                try {
                    if ($rows.Count -eq 0) {
                        $rows = [System.Collections.Generic.List[object]]::new($estimatedRowTotal)
                    } elseif ($rows.Capacity -lt $estimatedRowTotal) {
                        $rows.Capacity = $estimatedRowTotal
                    }
                } catch { }
            }

            $portSortCacheHitsBaseline = 0L
            $portSortCacheMissBaseline = 0L
            try {
                $portSortCacheStart = InterfaceModule\Get-PortSortCacheStatistics
                if ($portSortCacheStart) {
                    if ($portSortCacheStart.PSObject.Properties.Name -contains 'Hits') {
                        $portSortCacheHitsBaseline = [long]$portSortCacheStart.Hits
                    }
                    if ($portSortCacheStart.PSObject.Properties.Name -contains 'Misses') {
                        $portSortCacheMissBaseline = [long]$portSortCacheStart.Misses
                    }
                    if ($portSortCacheStart.PSObject.Properties.Name -contains 'EntryCount') {
                        $materializePortSortCacheSize = [long][Math]::Max($materializePortSortCacheSize, [long]$portSortCacheStart.EntryCount)
                    }
                }
            } catch { }

            $templatesDir = Join-Path $PSScriptRoot '..\Templates'
            $templateLookups = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
            $templateHintCaches = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.Dictionary[string,StateTrace.Models.InterfaceTemplateHint]]' ([System.StringComparer]::OrdinalIgnoreCase)
            $templatesStopwatch = [System.Diagnostics.Stopwatch]::new()
            $templateLoadDuration = 0.0

            $materializeStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $projectionStopwatch = [System.Diagnostics.Stopwatch]::new()
            $portSortStopwatch = [System.Diagnostics.Stopwatch]::new()
            $templateResolveStopwatch = [System.Diagnostics.Stopwatch]::new()
            $objectBuildStopwatch = [System.Diagnostics.Stopwatch]::new()
            $materializeProjectionDuration = 0.0
            $materializePortSortDuration = 0.0
            $materializeTemplateDuration = 0.0
            $materializeTemplateLookupDuration = 0.0
            $materializeTemplateApplyDuration = 0.0
            $materializeObjectDuration = 0.0
            $templateLookupStopwatch = [System.Diagnostics.Stopwatch]::new()
            $templateApplyStopwatch = [System.Diagnostics.Stopwatch]::new()
            $templateHintCacheHitCount = 0L
            $templateHintCacheMissCount = 0L
            $metrics = [pscustomobject]@{ HydrationMaterializeTemplateReuseCount = 0 }

            $lastHostname = $null
            $lastZoneValue = ''
            $lastSiteValue = $siteCode
            $lastBuildingValue = ''
            $lastRoomValue = ''
            $lastVendorValue = 'Cisco'
            $lastMakeValue = ''
            $defaultPortSortValue = '99-UNK-99999-99999-99999-99999-99999'

            foreach ($row in $enum) {
                if ($null -eq $row) { continue }

                $cachedPortEntry = $null
                $projectionStopwatch.Restart()
                $hn = [string]$row.Hostname
                if ($hn) { $hn = $hn.Trim() }
                if ([string]::IsNullOrWhiteSpace($hn)) {
                    $projectionStopwatch.Stop()
                    $materializeProjectionDuration += $projectionStopwatch.Elapsed.TotalMilliseconds
                    continue
                }

                if (-not $lastHostname -or -not [System.StringComparer]::Ordinal.Equals($hn, $lastHostname)) {
                    $lastHostname = $hn
                    $lastZoneValue = ''
                    try {
                        $parts = $hn.Split('-', [System.StringSplitOptions]::RemoveEmptyEntries)
                        if ($parts.Length -ge 2) { $lastZoneValue = $parts[1] }
                    } catch {
                        $lastZoneValue = ''
                    }

                    $siteCandidate = [string]$row.Site
                    if ([string]::IsNullOrWhiteSpace($siteCandidate)) {
                        $siteCandidate = $siteCode
                    }
                    $lastSiteValue = $siteCandidate

                    $lastBuildingValue = [string]$row.Building
                    $lastRoomValue = [string]$row.Room

                    $lastMakeValue = [string]$row.Make
                    $lastVendorValue = 'Cisco'
                    if (-not [string]::IsNullOrWhiteSpace($lastMakeValue)) {
                        if ($lastMakeValue -match '(?i)brocade') { $lastVendorValue = 'Brocade' }
                        elseif ($lastMakeValue -match '(?i)arista') { $lastVendorValue = 'Arista' }
                    }
                } else {
                    $tmpBuilding = [string]$row.Building
                    if (-not [string]::IsNullOrWhiteSpace($tmpBuilding)) {
                        $lastBuildingValue = $tmpBuilding
                    }
                    $tmpRoom = [string]$row.Room
                    if (-not [string]::IsNullOrWhiteSpace($tmpRoom)) {
                        $lastRoomValue = $tmpRoom
                    }
                    $tmpSite = [string]$row.Site
                    if (-not [string]::IsNullOrWhiteSpace($tmpSite)) {
                        $lastSiteValue = $tmpSite
                    }
                    $tmpMake = [string]$row.Make
                    if (-not [string]::IsNullOrWhiteSpace($tmpMake) -and -not [System.StringComparer]::OrdinalIgnoreCase.Equals($tmpMake, $lastMakeValue)) {
                        $lastMakeValue = $tmpMake
                        if ($lastMakeValue -match '(?i)brocade') { $lastVendorValue = 'Brocade' }
                        elseif ($lastMakeValue -match '(?i)arista') { $lastVendorValue = 'Arista' }
                        else { $lastVendorValue = 'Cisco' }
                    }
                }

                $port = [string]$row.Port
                $name = [string]$row.Name
                $status = [string]$row.Status
                $vlan = [string]$row.VLAN
                $duplex = [string]$row.Duplex
                $speed = [string]$row.Speed
                $type = [string]$row.Type
                $lm = [string]$row.LearnedMACs
                $aState = [string]$row.AuthState
                $aMode = [string]$row.AuthMode
                $aMAC = [string]$row.AuthClientMAC
                $authTmpl = [string]$row.AuthTemplate
                $cfgVal = [string]$row.Config
                $cfgStatVal = [string]$row.ConfigStatus
                $portColorVal = [string]$row.PortColor
                $tipVal = [string]$row.ToolTip
                $siteVal = $lastSiteValue
                $bld = $lastBuildingValue
                $room = $lastRoomValue
                $zoneValIf = $lastZoneValue
                $vendor = $lastVendorValue
                $projectionStopwatch.Stop()
                $materializeProjectionDuration += $projectionStopwatch.Elapsed.TotalMilliseconds

                $portSort = $null
                $portSortAdded = $false
                if (-not [string]::IsNullOrWhiteSpace($port)) {
                    $portSortAdded = $portSortUniquePorts.Add($port)
                }

                $templateResolveStopwatch.Restart()

                $tmplLookup = $null
                if (-not $templateLookups.TryGetValue($vendor, [ref]$tmplLookup)) {
                    $templatesStopwatch.Restart()
                    $tmplLookup = script:Get-TemplateLookupForVendor -Vendor $vendor -TemplatesPath $templatesDir
                    $templatesStopwatch.Stop()
                    $templateLoadDuration += $templatesStopwatch.Elapsed.TotalMilliseconds
                    $templateLookups[$vendor] = $tmplLookup
                }

                $vendorHintCache = $null
                if (-not $templateHintCaches.TryGetValue($vendor, [ref]$vendorHintCache)) {
                    $vendorHintCache = script:Get-TemplateHintCacheForVendor -Vendor $vendor -TemplatesPath $templatesDir
                    $templateHintCaches[$vendor] = $vendorHintCache
                }

                $tipCore = ($tipVal.TrimEnd())
                if (-not $tipCore) {
                    if ($cfgVal -and ($cfgVal.Trim() -ne '')) {
                        $tipCore = "AuthTemplate: $authTmpl`r`n`r`n$cfgVal"
                    } elseif ($authTmpl) {
                        $tipCore = "AuthTemplate: $authTmpl"
                    } else {
                        $tipCore = ''
                    }
                }

                $finalPortColor = $portColorVal
                $finalCfgStatus = $cfgStatVal
                $hasPortColor = -not [string]::IsNullOrWhiteSpace($finalPortColor)
                $hasCfgStatus = -not [string]::IsNullOrWhiteSpace($finalCfgStatus)
                if ((-not $hasPortColor -or -not $hasCfgStatus) -and $cachedPortEntry -and ($cachedPortEntry -is [StateTrace.Models.InterfaceCacheEntry])) {
                    $reuseTemplateMatches = $true
                    if (-not [string]::IsNullOrWhiteSpace($authTmpl)) {
                        try {
                            if (-not [string]::IsNullOrWhiteSpace($cachedPortEntry.Template) -and -not [System.StringComparer]::OrdinalIgnoreCase.Equals($cachedPortEntry.Template, $authTmpl)) {
                                $reuseTemplateMatches = $false
                            }
                        } catch {
                            $reuseTemplateMatches = $false
                        }
                    }
                    if ($reuseTemplateMatches) {
                        $templateReuseApplied = $false
                        if (-not $hasPortColor) {
                            $cachedColor = ''
                            try { $cachedColor = '' + $cachedPortEntry.PortColor } catch { $cachedColor = '' }
                            if (-not [string]::IsNullOrWhiteSpace($cachedColor)) {
                                $finalPortColor = $cachedColor
                                $hasPortColor = -not [string]::IsNullOrWhiteSpace($finalPortColor)
                                if ($hasPortColor) { $templateReuseApplied = $true }
                            }
                        }
                        if (-not $hasCfgStatus) {
                            $cachedStatus = ''
                            if ($cachedPortEntry.PSObject.Properties.Name -contains 'StatusTag') {
                                try { $cachedStatus = '' + $cachedPortEntry.StatusTag } catch { $cachedStatus = '' }
                            } elseif ($cachedPortEntry.PSObject.Properties.Name -contains 'ConfigStatus') {
                                try { $cachedStatus = '' + $cachedPortEntry.ConfigStatus } catch { $cachedStatus = '' }
                            }
                            if (-not [string]::IsNullOrWhiteSpace($cachedStatus)) {
                                $finalCfgStatus = $cachedStatus
                                $hasCfgStatus = -not [string]::IsNullOrWhiteSpace($finalCfgStatus)
                                if ($hasCfgStatus) { $templateReuseApplied = $true }
                            }
                        }
                        if ($templateReuseApplied) {
                            $metrics.HydrationMaterializeTemplateReuseCount++
                        }
                    }
                }
                if (-not $hasPortColor -or -not $hasCfgStatus) {
                    $templateApplyCandidateCount++
                    $templateApplyStopwatch.Restart()
                    $applyReason = 'Unknown'
                    $hintSource = 'None'
                    if ([string]::IsNullOrWhiteSpace($authTmpl)) {
                        $templateApplyDefaultedCount++
                        $templateApplyAuthTemplateMissingCount++
                        $applyReason = 'NoAuthTemplate'
                        if (-not $hasPortColor) { $finalPortColor = 'Gray' }
                        if (-not $hasCfgStatus) { $finalCfgStatus = 'Unknown' }
                    } else {
                        $hint = $null
                        $hintFromCache = $false
                        $hintSource = 'Lookup'
                        $templateLookupStopwatch.Restart()
                        if ($vendorHintCache -and $vendorHintCache.TryGetValue($authTmpl, [ref]$hint)) {
                            $hintFromCache = $true
                            $hintSource = 'Cache'
                        } else {
                            $hint = [StateTrace.Models.InterfaceTemplateHint]::new()
                            $match = $null
                            if ($tmplLookup -and $tmplLookup -is [System.Collections.Generic.Dictionary[string,object]]) {
                                $tmpMatch = $null
                                if ($tmplLookup.TryGetValue($authTmpl, [ref]$tmpMatch)) { $match = $tmpMatch }
                            } elseif ($tmplLookup -and $tmplLookup.ContainsKey($authTmpl)) {
                                $match = $tmplLookup[$authTmpl]
                            }

                            $colorFromTemplate = 'Gray'
                            if ($match) {
                                try {
                                    $colorProp = $match.PSObject.Properties['color']
                                    if ($colorProp -and $colorProp.Value) { $colorFromTemplate = [string]$colorProp.Value }
                                } catch {
                                    $colorFromTemplate = 'Gray'
                                }
                            }

                            if ($match) {
                                $hint.PortColor = $colorFromTemplate
                                $hint.ConfigStatus = 'Match'
                                $hint.HasTemplate = $true
                            } else {
                                $hint.PortColor = 'Gray'
                                $hint.ConfigStatus = 'Mismatch'
                                $hint.HasTemplate = $false
                            }
                            if ($vendorHintCache) {
                                $vendorHintCache[$authTmpl] = $hint
                            }
                        }
                        $templateLookupStopwatch.Stop()
                        $materializeTemplateLookupDuration += $templateLookupStopwatch.Elapsed.TotalMilliseconds
                        if ($hintFromCache) {
                            $templateHintCacheHitCount++
                        } else {
                            $templateHintCacheMissCount++
                        }
                        if ($hint -and $hint.HasTemplate) {
                            $templateApplyHintAppliedCount++
                            $applyReason = 'TemplateMatched'
                        } else {
                            $templateApplyDefaultedCount++
                            $templateApplyNoTemplateMatchCount++
                            $applyReason = 'TemplateNotFound'
                        }

                        if (-not $hasPortColor) { $finalPortColor = $hint.PortColor }
                        if (-not $hasCfgStatus) { $finalCfgStatus = $hint.ConfigStatus }
                    }
                    if (-not $hasPortColor -and -not [string]::IsNullOrWhiteSpace($finalPortColor)) {
                        $templateApplySetPortColorCount++
                    }
                    if (-not $hasCfgStatus -and -not [string]::IsNullOrWhiteSpace($finalCfgStatus)) {
                        $templateApplySetConfigStatusCount++
                    }
                    if ($templateApplySamples.Count -lt $templateApplySampleLimit) {
                        $templateApplySamples.Add([pscustomobject]@{
                            Port            = $port
                            AuthTemplate    = $authTmpl
                            Reason          = $applyReason
                            HintSource      = $hintSource
                            PortColorSet    = (-not $hasPortColor)
                            ConfigStatusSet = (-not $hasCfgStatus)
                        }) | Out-Null
                    }
                    $templateApplyStopwatch.Stop()
                    $materializeTemplateApplyDuration += $templateApplyStopwatch.Elapsed.TotalMilliseconds
                }
        $templateResolveStopwatch.Stop()
        $materializeTemplateDuration += $templateResolveStopwatch.Elapsed.TotalMilliseconds

        $cacheSignature = ConvertTo-InterfaceCacheSignature -Values @(
            $name,
            $status,
            $vlan,
            $duplex,
            $speed,
            $type,
            $lm,
            $aState,
            $aMode,
            $aMAC,
            $authTmpl,
            $cfgVal,
            $finalPortColor,
            $finalCfgStatus,
            $tipCore
        )

        $objectBuildStopwatch.Restart()
        $record = [StateTrace.Models.InterfacePortRecord]::new()
        $record.Hostname = $hn
        $record.Port = $port
        $record.PortSort = $portSort
                $record.Name = $name
                $record.Status = $status
                $record.VLAN = $vlan
                $record.Duplex = $duplex
                $record.Speed = $speed
                $record.Type = $type
                $record.LearnedMACs = $lm
                $record.AuthState = $aState
                $record.AuthMode = $aMode
                $record.AuthClientMAC = $aMAC
                $record.Site = $siteVal
                $record.Building = $bld
                $record.Room = $room
                $record.Zone = $zoneValIf
                $record.AuthTemplate = $authTmpl
        $record.Config = $cfgVal
        $record.ConfigStatus = $finalCfgStatus
        $record.PortColor = $finalPortColor
        $record.ToolTip = $tipCore
        $record.CacheSignature = $cacheSignature
        $record.IsSelected = $false
                [void]$rows.Add($record)
                $objectBuildStopwatch.Stop()
                $materializeObjectDuration += $objectBuildStopwatch.Elapsed.TotalMilliseconds
            }
            $rowsAreOrdered = $true
            $hydrationDetail.TemplateLoadDurationMs = [Math]::Round($templateLoadDuration, 3)
            try {
                $portSortCacheEnd = InterfaceModule\Get-PortSortCacheStatistics
                if ($portSortCacheEnd) {
                    if ($portSortCacheEnd.PSObject.Properties.Name -contains 'Hits') {
                        $materializePortSortCacheHits = [long][Math]::Max(0, [long]$portSortCacheEnd.Hits - $portSortCacheHitsBaseline)
                    }
                    if ($portSortCacheEnd.PSObject.Properties.Name -contains 'Misses') {
                        $materializePortSortCacheMisses = [long][Math]::Max(0, [long]$portSortCacheEnd.Misses - $portSortCacheMissBaseline)
                    }
                    if ($portSortCacheEnd.PSObject.Properties.Name -contains 'EntryCount') {
                        $materializePortSortCacheSize = [long][Math]::Max(0, [long]$portSortCacheEnd.EntryCount)
                    }
                }
            } catch { }

            $materializeStopwatch.Stop()
            $hydrationDetail.MaterializeDurationMs = [Math]::Round($materializeStopwatch.Elapsed.TotalMilliseconds, 3)
            $hydrationDetail | Add-Member -NotePropertyName MaterializeProjectionDurationMs -NotePropertyValue ([Math]::Round($materializeProjectionDuration, 3)) -Force
            $hydrationDetail | Add-Member -NotePropertyName MaterializePortSortDurationMs -NotePropertyValue ([Math]::Round($materializePortSortDuration, 3)) -Force
            $hydrationDetail | Add-Member -NotePropertyName MaterializeTemplateDurationMs -NotePropertyValue ([Math]::Round($materializeTemplateDuration, 3)) -Force
            $hydrationDetail | Add-Member -NotePropertyName MaterializeTemplateLookupDurationMs -NotePropertyValue ([Math]::Round($materializeTemplateLookupDuration, 3)) -Force
            $hydrationDetail | Add-Member -NotePropertyName MaterializeTemplateApplyDurationMs -NotePropertyValue ([Math]::Round($materializeTemplateApplyDuration, 3)) -Force
            $hydrationDetail | Add-Member -NotePropertyName MaterializeObjectDurationMs -NotePropertyValue ([Math]::Round($materializeObjectDuration, 3)) -Force
            $hydrationDetail | Add-Member -NotePropertyName MaterializeTemplateCacheHitCount -NotePropertyValue ([long][Math]::Max(0, $templateHintCacheHitCount)) -Force
            $hydrationDetail | Add-Member -NotePropertyName MaterializeTemplateCacheMissCount -NotePropertyValue ([long][Math]::Max(0, $templateHintCacheMissCount)) -Force
            if ($hydrationDetail.QueryDurationMs -le 0) {
                $hydrationDetail.QueryDurationMs = $hydrationDetail.MaterializeDurationMs
            }
        }
    }

    $hydrationDetail | Add-Member -NotePropertyName MaterializePortSortCacheHitCount -NotePropertyValue ([long][Math]::Max(0, $materializePortSortCacheHits)) -Force
    $hydrationDetail | Add-Member -NotePropertyName MaterializePortSortCacheMissCount -NotePropertyValue ([long][Math]::Max(0, $materializePortSortCacheMisses)) -Force
    $hydrationDetail | Add-Member -NotePropertyName MaterializePortSortCacheSize -NotePropertyValue ([long][Math]::Max(0, $materializePortSortCacheSize)) -Force
    $hydrationDetail | Add-Member -NotePropertyName MaterializePortSortUniquePortCount -NotePropertyValue ([long][Math]::Max(0, $portSortUniquePorts.Count)) -Force
    $hydrationDetail | Add-Member -NotePropertyName MaterializePortSortMissSamples -NotePropertyValue ($portSortMissSamples.ToArray()) -Force
    $hydrationDetail | Add-Member -NotePropertyName MaterializeTemplateReuseCount -NotePropertyValue ([long][Math]::Max(0, $metrics.HydrationMaterializeTemplateReuseCount)) -Force
    $hydrationDetail | Add-Member -NotePropertyName MaterializeTemplateApplyCount -NotePropertyValue ([long][Math]::Max(0, $templateApplyCandidateCount)) -Force
    $hydrationDetail | Add-Member -NotePropertyName MaterializeTemplateDefaultedCount -NotePropertyValue ([long][Math]::Max(0, $templateApplyDefaultedCount)) -Force
    $hydrationDetail | Add-Member -NotePropertyName MaterializeTemplateAuthTemplateMissingCount -NotePropertyValue ([long][Math]::Max(0, $templateApplyAuthTemplateMissingCount)) -Force
    $hydrationDetail | Add-Member -NotePropertyName MaterializeTemplateNoTemplateMatchCount -NotePropertyValue ([long][Math]::Max(0, $templateApplyNoTemplateMatchCount)) -Force
    $hydrationDetail | Add-Member -NotePropertyName MaterializeTemplateHintAppliedCount -NotePropertyValue ([long][Math]::Max(0, $templateApplyHintAppliedCount)) -Force
    $hydrationDetail | Add-Member -NotePropertyName MaterializeTemplateSetPortColorCount -NotePropertyValue ([long][Math]::Max(0, $templateApplySetPortColorCount)) -Force
    $hydrationDetail | Add-Member -NotePropertyName MaterializeTemplateSetConfigStatusCount -NotePropertyValue ([long][Math]::Max(0, $templateApplySetConfigStatusCount)) -Force
    $hydrationDetail | Add-Member -NotePropertyName MaterializeTemplateApplySamples -NotePropertyValue ($templateApplySamples.ToArray()) -Force

    $comparison2 = [System.Comparison[object]]{
        param($a, $b)
        $hnc2 = [System.StringComparer]::OrdinalIgnoreCase.Compare($a.Hostname, $b.Hostname)
        if ($hnc2 -ne 0) { return $hnc2 }
        return [System.StringComparer]::Ordinal.Compare($a.PortSort, $b.PortSort)
    }
    $sortDurationMs = 0.0
    $sortStopwatch = $null
    try {
        if ($rows -and -not $rowsAreOrdered) {
            $sortStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $rows.Sort($comparison2)
        }
    } catch {
    } finally {
        if ($sortStopwatch) {
            $sortStopwatch.Stop()
            $sortDurationMs = [Math]::Round($sortStopwatch.Elapsed.TotalMilliseconds, 3)
        }
    }
    if ($hydrationDetail) {
        try {
            $hydrationDetail | Add-Member -NotePropertyName SortDurationMs -NotePropertyValue $sortDurationMs -Force
        } catch {}
    }

    $dbTime = $null
    try { $dbTime = (Get-Item -LiteralPath $dbFile).LastWriteTime } catch {}
    try {
        $script:SiteInterfaceCache[$siteCode] = [PSCustomObject]@{
            List   = $rows
            DbTime = $dbTime
        }
    } catch {}
    if ($hydrationDetail.QueryAttempts -le 0 -and -not [System.StringComparer]::OrdinalIgnoreCase.Equals($hydrationDetail.Provider, 'Cache')) {
        $hydrationDetail.QueryAttempts = 1
    }
    $hydrationDetail.ResultRowCount = [int]$rows.Count
    if ($hydrationDetail.MaterializeDurationMs -le 0 -and $rows.Count -gt 0) {
        $hydrationDetail.MaterializeDurationMs = [Math]::Round($hydrationDetail.QueryDurationMs, 3)
    }
    $hydrationDetail.Succeeded = $true
    $script:LastInterfaceSiteHydrationMetrics = $hydrationDetail
    return $rows
}

function Get-InterfaceInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [string]$TemplatesPath = (Join-Path $PSScriptRoot '..\Templates')
    )
        # Check if this host's interface details are already available in the in-memory cache.  When available,
        # simply return the cached list to avoid re-querying the database.  Ensure that any returned objects
        # expose the expected properties (Hostname, Port, IsSelected, etc.) by adding them on the fly when
        # missing.  Without this defensive injection, callers like Get-SelectedInterfaceRows may receive
        # non-PSCustomObject types (e.g. DataRow) that do not have PSObject.Properties defined, which
        # manifests as black boxes in the Interfaces grid or errors when accessing the Hostname property.
        try {
            if ($global:DeviceInterfaceCache -and $global:DeviceInterfaceCache.ContainsKey($Hostname)) {
                $cached = $global:DeviceInterfaceCache[$Hostname]
                $cachedCount = 0
                if ($cached -is [System.Collections.ICollection]) {
                    try { $cachedCount = [int]$cached.Count } catch { $cachedCount = 0 }
                } elseif ($cached) {
                    $cachedCount = @($cached).Count
                }
                if ($cachedCount -gt 0) {
                    foreach ($o in $cached) {
                        if ($null -eq $o) { continue }
                        try {
                            if (-not $o.PSObject.Properties['Hostname']) {
                                $o | Add-Member -NotePropertyName Hostname -NotePropertyValue ($Hostname) -ErrorAction SilentlyContinue
                            }
                        } catch {}
                        try {
                            if (-not $o.PSObject.Properties['IsSelected']) {
                                $o | Add-Member -NotePropertyName IsSelected -NotePropertyValue $false -ErrorAction SilentlyContinue
                            }
                        } catch {}
                    }
                    try {
                        if ($cachedCount -gt 0) {
                            $script:InterfaceCacheHydrationTracker[$Hostname] = $true
                        } else {
                            $script:InterfaceCacheHydrationTracker.Remove($Hostname) | Out-Null
                        }
                    } catch {}
                    return $cached
                } else {
                    $hydrated = $false
                    try {
                        if ($script:InterfaceCacheHydrationTracker.ContainsKey($Hostname)) {
                            $hydrated = [bool]$script:InterfaceCacheHydrationTracker[$Hostname]
                        }
                    } catch { $hydrated = $false }
                    if ($hydrated) {
                        return $cached
                    }
                }
            }
        } catch {}
    # Determine the per-site database path and return empty list if missing.
    $dbPath = Get-DbPathForHost $Hostname
    if (-not (Test-Path $dbPath)) { return @() }
    try {
        # Ensure the database module is loaded once rather than on every call.
        Import-DatabaseModule
        $escHost = $Hostname
        try {
            $escHost = DatabaseModule\Get-SqlLiteral -Value $Hostname
        } catch {
            $escHost = $Hostname -replace "'", "''"
        }
        $sql = "SELECT Port, Name, Status, VLAN, Duplex, Speed, Type, LearnedMACs, AuthState, AuthMode, AuthClientMAC, AuthTemplate, Config, ConfigStatus, PortColor, ToolTip FROM Interfaces WHERE Hostname = '$escHost' ORDER BY Port"
        $dt = Invoke-DbQuery -DatabasePath $dbPath -Sql $sql
        # Convert rows into interface objects.  Prefer the shared InterfaceModule helper, but when
        # it is unavailable fall back to a lightweight in-module projection so callers still
        # receive data instead of an empty list.
        $conversionSucceeded = $false
        $objs = @()
        try {
            if (Get-Command -Name 'InterfaceModule\New-InterfaceObjectsFromDbRow' -ErrorAction SilentlyContinue) {
                $objs = InterfaceModule\New-InterfaceObjectsFromDbRow -Data $dt -Hostname $Hostname -TemplatesPath $TemplatesPath
                $conversionSucceeded = $true
            } elseif (Ensure-InterfaceModuleBridge) {
                $objs = InterfaceModule\New-InterfaceObjectsFromDbRow -Data $dt -Hostname $Hostname -TemplatesPath $TemplatesPath
                $conversionSucceeded = $true
            }
        } catch {
            Write-Verbose ("[DeviceRepository] InterfaceModule conversion failed for '{0}': {1}" -f $Hostname, $_.Exception.Message)
            $conversionSucceeded = $false
            $objs = @()
        }
        if (-not $conversionSucceeded) {
            $objs = ConvertTo-InterfacePortRecordsFallback -Data $dt -Hostname $Hostname
        }
            # For each returned object ensure expected properties exist.  This is necessary when the
            # database contains incomplete rows or when InterfaceModule\New-InterfaceObjectsFromDbRow returns an object
            # without IsSelected (should not happen, but defensive programming).  Add any missing
            # Hostname/IsSelected/Site/Zone/Building/Room properties before caching.
            if ($objs) {
                foreach ($oo in $objs) {
                    if ($null -eq $oo) { continue }
                    try {
                        if (-not $oo.PSObject.Properties['Hostname']) {
                            $oo | Add-Member -NotePropertyName Hostname -NotePropertyValue ($Hostname) -ErrorAction SilentlyContinue
                        }
                    } catch {}
                    try {
                        if (-not $oo.PSObject.Properties['IsSelected']) {
                            $oo | Add-Member -NotePropertyName IsSelected -NotePropertyValue $false -ErrorAction SilentlyContinue
                        }
                    } catch {}
                    # Inject location metadata for summary filtering.  When the Site/Zone/Building/Room
                    # properties are absent, derive them from DeviceMetadata or by parsing the hostname.
                    try {
                        $needSite    = (-not $oo.PSObject.Properties['Site'])
                        $needZone    = (-not $oo.PSObject.Properties['Zone'])
                        $needBld     = (-not $oo.PSObject.Properties['Building'])
                        $needRoom    = (-not $oo.PSObject.Properties['Room'])
                        if ($needSite -or $needZone -or $needBld -or $needRoom) {
                            $meta = $null
                            try {
                                if ($global:DeviceMetadata -and $global:DeviceMetadata.ContainsKey($Hostname)) {
                                    $meta = $global:DeviceMetadata[$Hostname]
                                }
                            } catch {}
                            $siteVal = ''
                            $zoneVal = ''
                            $bldVal  = ''
                            $roomVal = ''
                            if ($meta) {
                                try { $siteVal = '' + $meta.Site } catch {}
                                try { $bldVal  = '' + $meta.Building } catch {}
                                try { $roomVal = '' + $meta.Room } catch {}
                                # Zone may be stored as a property or may need to be parsed
                                if ($meta.PSObject.Properties['Zone']) {
                                    try { $zoneVal = '' + $meta.Zone } catch {}
                                }
                            }
                            # Parse hostname to derive site and zone when not found in metadata
                            if (-not $siteVal -or $siteVal -eq '') {
                                $partsHN = ('' + $Hostname) -split '-'
                                if ($partsHN.Length -ge 1) { $siteVal = '' + $partsHN[0] }
                                if ($partsHN.Length -ge 2) { if (-not $zoneVal -or $zoneVal -eq '') { $zoneVal = '' + $partsHN[1] } }
                            }
                            # When zone is still unknown, leave as empty string
                            if ($needSite)    { $oo | Add-Member -NotePropertyName Site     -NotePropertyValue $siteVal -ErrorAction SilentlyContinue }
                            if ($needZone)    { $oo | Add-Member -NotePropertyName Zone     -NotePropertyValue $zoneVal -ErrorAction SilentlyContinue }
                            if ($needBld)     { $oo | Add-Member -NotePropertyName Building -NotePropertyValue $bldVal  -ErrorAction SilentlyContinue }
                            if ($needRoom)    { $oo | Add-Member -NotePropertyName Room     -NotePropertyValue $roomVal -ErrorAction SilentlyContinue }
                        }
                    } catch {}
                }
            }
            # Update the global cache with the loaded objects for this host.
            try {
                if (-not $global:DeviceInterfaceCache) { $global:DeviceInterfaceCache = @{} }
                $listCache = New-Object 'System.Collections.Generic.List[object]'
                if ($objs) {
                    foreach ($o in $objs) { [void]$listCache.Add($o) }
                }
                $global:DeviceInterfaceCache[$Hostname] = $listCache
                $hydrated = $listCache.Count -gt 0
                try {
                    if ($hydrated) {
                        $script:InterfaceCacheHydrationTracker[$Hostname] = $true
                    } else {
                        $script:InterfaceCacheHydrationTracker.Remove($Hostname) | Out-Null
                    }
                } catch {
                    $script:InterfaceCacheHydrationTracker = @{}
                    if ($hydrated) { $script:InterfaceCacheHydrationTracker[$Hostname] = $true }
                }
            } catch {}
            return $objs
    } catch {
        Write-Warning ("Failed to load interface information from database for {0}: {1}" -f $Hostname, $_.Exception.Message)
        return @()
    }
}


function Get-InterfaceConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]  $Hostname,
        [Parameter(Mandatory)][string[]]$Interfaces,
        [Parameter(Mandatory)][string]  $TemplateName,
        [hashtable]$NewNames,
        [hashtable]$NewVlans,
        [string]$TemplatesPath = (Join-Path $PSScriptRoot '..\Templates')
    )
    # Determine the per-site database path for this host; return empty list if missing
    $dbPath = Get-DbPathForHost $Hostname
    if (-not (Test-Path $dbPath)) { return @() }
    $debug = ($Global:StateTraceDebug -eq $true)
    try {
        # Ensure the database module is loaded once rather than on every call.
        Import-DatabaseModule
        $escHost = $Hostname
        try {
            $escHost = DatabaseModule\Get-SqlLiteral -Value $Hostname
        } catch {
            $escHost = $Hostname -replace "'", "''"
        }
        $vendor = 'Cisco'
        try {
            $mkDt = Invoke-DbQuery -DatabasePath $dbPath -Sql "SELECT Make FROM DeviceSummary WHERE Hostname = '$escHost'"
            if ($mkDt) {
                if ($mkDt -is [System.Data.DataTable]) {
                    if ($mkDt.Rows.Count -gt 0) {
                        $mk = $mkDt.Rows[0].Make
                        if ($mk -match '(?i)brocade') { $vendor = 'Brocade' }
                    }
                } else {
                    $mkRow = $mkDt | Select-Object -First 1
                    if ($mkRow -and $mkRow.PSObject.Properties['Make']) {
                        $mk = $mkRow.Make
                        if ($mk -match '(?i)brocade') { $vendor = 'Brocade' }
                    }
                }
            }
        } catch {}
        $templateData = TemplatesModule\Get-ConfigurationTemplateData -Vendor $vendor -TemplatesPath $TemplatesPath
        if (-not $templateData.Exists) { throw "Template file missing: $($templateData.Path)" }
        $templates = $templateData.Templates
        $templateLookup = $templateData.Lookup
        $tmpl = $null
        if ($templateLookup -and $templateLookup.ContainsKey($TemplateName)) {
            $tmpl = $templateLookup[$TemplateName]
        }
        if (-not $tmpl) { throw "Template '$TemplateName' not found in ${vendor}.json" }
        # --- Batched query instead of N+1 per-port lookups ---
        $oldConfigs = @{}
        # Build a normalized list of ports without using ForEach-Object pipelines for better performance
        $portsList = New-Object 'System.Collections.Generic.List[string]'
        foreach ($p in $Interfaces) {
            if ($p -ne $null) {
                [void]$portsList.Add($p.ToString())
            }
        }
        if ($portsList.Count -gt 0) {
            # Escape single quotes and build IN list using typed lists
            $portItems = New-Object 'System.Collections.Generic.List[string]'
            foreach ($item in $portsList) {
                $escaped = $item
                try {
                    $escaped = DatabaseModule\Get-SqlLiteral -Value $item
                } catch {
                    $escaped = $item -replace "'", "''"
                }
                [void]$portItems.Add("'" + $escaped + "'")
            }
            $inList = [string]::Join(", ", $portItems.ToArray())
            $sqlCfgAll = "SELECT Hostname, Port, Config FROM Interfaces WHERE Hostname = '$escHost' AND Port IN ($inList)"
            $session = $null
            try {
                if (Test-Path $dbPath) { $session = Open-DbReadSession -DatabasePath $dbPath }
            } catch {}
            try {
                $dtAll = if ($session) {
                    Invoke-DbQuery -DatabasePath $dbPath -Sql $sqlCfgAll -Session $session
                } else {
                    Invoke-DbQuery -DatabasePath $dbPath -Sql $sqlCfgAll
                }
                if ($dtAll) {
                    $rows = @()
                    if ($dtAll -is [System.Data.DataTable]) { $rows = $dtAll.Rows }
                    elseif ($dtAll -is [System.Collections.IEnumerable]) { $rows = $dtAll }
                    foreach ($row in $rows) {
                        $portVal = $row.Port
                        $cfgText = $row.Config
                        $oldConfigs[$portVal] = if ($cfgText) { $cfgText -split "`n" } else { @() }
                    }
                }
            } finally {
                if ($session) { Close-DbReadSession -Session $session }
            }
        }
        foreach ($p in $Interfaces) {
            if (-not $oldConfigs.ContainsKey($p)) { $oldConfigs[$p] = @() }
        }
        # --- End batched lookup ---
        $outLines = foreach ($port in $Interfaces) {
            "interface $port"
            # Use a typed list instead of a PowerShell array when building the set of
            $pending = New-Object 'System.Collections.Generic.List[string]'
            $nameOverride = if ($NewNames.ContainsKey($port)) { $NewNames[$port] } else { $null }
            $vlanOverride = if ($NewVlans.ContainsKey($port)) { $NewVlans[$port] } else { $null }
            if ($nameOverride) {
                $val = if ($vendor -eq 'Cisco') { "description $nameOverride" } else { "port-name $nameOverride" }
                [void]$pending.Add($val)
            }
            if ($vlanOverride) {
                $val2 = if ($vendor -eq 'Cisco') { "switchport access vlan $vlanOverride" } else { "auth-default-vlan $vlanOverride" }
                [void]$pending.Add($val2)
            }
            foreach ($cmd in $tmpl.required_commands) { [void]$pending.Add($cmd.Trim()) }
            if ($oldConfigs.ContainsKey($port)) {
                foreach ($oldLine in $oldConfigs[$port]) {
                    $trimOld  = $oldLine.Trim()
                    if (-not $trimOld) { continue }
                    # Skip interface and exit lines using case-insensitive comparisons
                    if ($trimOld.StartsWith('interface', [System.StringComparison]::OrdinalIgnoreCase) -or
                        $trimOld.Equals('exit', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                    $existsInNew = $false
                    foreach ($newCmd in $pending) {
                        # Check if the existing command matches any pending command using
                        $cmdTrim = $newCmd.Trim()
                        if ($trimOld.StartsWith($cmdTrim, [System.StringComparison]::OrdinalIgnoreCase)) { $existsInNew = $true; break }
                    }
                    if ($existsInNew) { continue }
                    if ($vendor -eq 'Cisco') {
                        # Remove legacy authentication commands.  Compare prefixes
                        if ($trimOld.StartsWith('authentication', [System.StringComparison]::OrdinalIgnoreCase) -or
                            $trimOld.StartsWith('dot1x',        [System.StringComparison]::OrdinalIgnoreCase) -or
                            $trimOld.Equals('mab',             [System.StringComparison]::OrdinalIgnoreCase)) {
                            " no $trimOld"
                        }
                    } else {
                        # For non-Cisco vendors, remove specific dot1x/mac-authentication lines.
                        if ($trimOld -match '(?i)^dot1x\s+port-control\s+auto' -or
                            $trimOld -match '(?i)^mac-authentication\s+enable') {
                            " no $trimOld"
                        }
                    }
                }
            }
            if ($nameOverride) {
                $(if ($vendor -eq 'Cisco') { " description $nameOverride" } else { " port-name $nameOverride" })
            }
            if ($vlanOverride) {
                $(if ($vendor -eq 'Cisco') { " switchport access vlan $vlanOverride" } else { " auth-default-vlan $vlanOverride" })
            }
            foreach ($cmd in $tmpl.required_commands) { $cmd }
            'exit'
            ''
        }
        return $outLines
    } catch {
        Write-Warning ("Failed to build interface configuration from database for {0}: {1}" -f $Hostname, $_.Exception.Message)
        return @()
    }
}

function Get-InterfacesForHostsBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [Parameter(Mandatory)][string[]]$Hostnames
    )
    if (-not $Hostnames -or $Hostnames.Count -eq 0) {
        return (New-Object System.Data.DataTable)
    }

    $seen = @{}
    $cleanList = New-Object 'System.Collections.Generic.List[string]'
    foreach ($h in $Hostnames) {
        if ($null -ne $h) {
            $t = ('' + $h).Trim()
            if ($t -and -not $seen.ContainsKey($t)) {
                $seen[$t] = $true
                [void]$cleanList.Add($t)
            }
        }
    }

    $cleanHosts = $cleanList.ToArray()
    if (-not $cleanHosts -or $cleanHosts.Count -eq 0) {
        return (New-Object System.Data.DataTable)
    }

    Import-DatabaseModule
    $listItems = New-Object 'System.Collections.Generic.List[string]'
    foreach ($host in $cleanHosts) {
        if ($host -ne $null) {
            $escaped = $host
            try {
                $escaped = DatabaseModule\Get-SqlLiteral -Value $host
            } catch {
                $escaped = $host -replace "'", "''"
            }
            [void]$listItems.Add("'" + $escaped + "'")
        }
    }

    $inList = [string]::Join(',', $listItems.ToArray())
    if ([string]::IsNullOrWhiteSpace($inList)) {
        return (New-Object System.Data.DataTable)
    }

    $sql = @"
SELECT
    i.Hostname,
    i.Port,
    i.Name,
    i.Status,
    i.VLAN,
    i.Duplex,
    i.Speed,
    i.Type,
    i.LearnedMACs,
    i.AuthState,
    i.AuthMode,
    i.AuthClientMAC,
    ds.Site,
    ds.Building,
    ds.Room,
    ds.Make,
    ds.AuthBlock
FROM Interfaces AS i
LEFT JOIN DeviceSummary AS ds ON i.Hostname = ds.Hostname
WHERE i.Hostname IN ($inList)
ORDER BY i.Hostname, i.Port
"@

    $session = $null
    try {
        $session = Open-DbReadSession -DatabasePath $DatabasePath
    } catch {
        $session = $null
    }

    try {
        if ($session) {
            return Invoke-DbQuery -DatabasePath $DatabasePath -Sql $sql -Session $session
        } else {
            return Invoke-DbQuery -DatabasePath $DatabasePath -Sql $sql
        }
    } finally {
        if ($session) { Close-DbReadSession -Session $session }
    }
}
function Get-SpanningTreeInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Hostname
    )

    $hostTrim = ('' + $Hostname).Trim()
    if ([string]::IsNullOrWhiteSpace($hostTrim)) { return @() }

    Import-DatabaseModule

    $dbPath = $null
    try { $dbPath = Get-DbPathForHost -Hostname $hostTrim } catch { $dbPath = $null }
    if (-not $dbPath -or -not (Test-Path -LiteralPath $dbPath)) { return @() }

    $escHost = $hostTrim -replace "'", "''"
    $sql = "SELECT Vlan, RootSwitch, RootPort, Role, Upstream, LastUpdated FROM SpanInfo WHERE Hostname = '$escHost' ORDER BY Vlan, RootPort, Role, Upstream"

    $session = $null
    try { $session = Open-DbReadSession -DatabasePath $dbPath } catch { $session = $null }

    try {
        if ($session) {
            $data = Invoke-DbQuery -DatabasePath $dbPath -Sql $sql -Session $session
        } else {
            $data = Invoke-DbQuery -DatabasePath $dbPath -Sql $sql
        }
    } finally {
        if ($session) { Close-DbReadSession -Session $session }
    }

    if (-not $data) { return @() }

    $rows = @()
    if ($data -is [System.Data.DataTable]) {
        $rows = $data.Rows
    } elseif ($data -is [System.Collections.IEnumerable]) {
        $rows = @($data)
    }

    if (-not $rows -or $rows.Count -eq 0) { return @() }

    $list = New-Object 'System.Collections.Generic.List[object]'
    foreach ($row in $rows) {
        if (-not $row) { continue }

        $vlan = ''
        $rootSwitch = ''
        $rootPort = ''
        $role = ''
        $upstream = ''
        $lastUpdated = ''

        try {
            if ($row -is [System.Data.DataRow]) {
                $vlan = '' + ($row['Vlan'])
                $rootSwitch = '' + ($row['RootSwitch'])
                $rootPort = '' + ($row['RootPort'])
                $role = '' + ($row['Role'])
                $upstream = '' + ($row['Upstream'])
                if ($row.Table.Columns.Contains('LastUpdated')) {
                    $lastUpdated = '' + ($row['LastUpdated'])
                }
            } elseif ($row.PSObject) {
                if ($row.PSObject.Properties['Vlan']) { $vlan = '' + $row.Vlan }
                if ($row.PSObject.Properties['RootSwitch']) { $rootSwitch = '' + $row.RootSwitch }
                if ($row.PSObject.Properties['RootPort']) { $rootPort = '' + $row.RootPort }
                if ($row.PSObject.Properties['Role']) { $role = '' + $row.Role }
                if ($row.PSObject.Properties['Upstream']) { $upstream = '' + $row.Upstream }
                if ($row.PSObject.Properties['LastUpdated']) { $lastUpdated = '' + $row.LastUpdated }
            }
        } catch {}

        if ($lastUpdated) {
            $parsed = [datetime]::MinValue
            if ([DateTime]::TryParse($lastUpdated, [ref]$parsed)) {
                $lastUpdated = $parsed.ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss')
            } else {
                $lastUpdated = ''
            }
        }

        $obj = [PSCustomObject]@{
            VLAN        = $vlan
            RootSwitch  = $rootSwitch
            RootPort    = $rootPort
            Role        = $role
            Upstream    = $upstream
            LastUpdated = $lastUpdated
        }
        [void]$list.Add($obj)
    }


    try {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $debugDir = Join-Path $projectRoot 'Logs\Debug'
        if (-not (Test-Path $debugDir)) { New-Item -ItemType Directory -Path $debugDir -Force | Out-Null }
        $logPath = Join-Path $debugDir 'SpanDebug.log'
        $rowCount = $list.Count
        $timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
        $line = ("{0} Host={1} Rows={2}" -f $timestamp, $hostTrim, $rowCount)
        Add-Content -Path $logPath -Value $line -Encoding UTF8
    } catch { }

    return $list.ToArray()
}
Export-ModuleMember -Function Get-DataDirectoryPath, Get-SiteFromHostname, Get-DbPathForSite, Get-DbPathForHost, Get-AllSiteDbPaths, Clear-SiteInterfaceCache, Get-InterfaceSiteCache, Get-InterfaceSiteCacheSummary, Get-SharedSiteInterfaceCacheEntry, Set-InterfaceSiteCacheHost, Get-InterfacePortBatchChunkSize, Set-InterfacePortStreamChunkSize, Set-InterfacePortStreamData, Initialize-InterfacePortStream, Get-InterfacePortStreamStatus, Get-InterfacePortBatch, Get-LastInterfacePortStreamMetrics, Get-LastInterfacePortQueueMetrics, Get-LastInterfaceSiteCacheMetrics, Get-LastInterfaceSiteHydrationMetrics, Set-InterfacePortDispatchMetrics, Get-LastInterfacePortDispatchMetrics, Clear-InterfacePortStream, Update-SiteZoneCache, Get-GlobalInterfaceSnapshot, Update-GlobalInterfaceList, Get-InterfacesForSite, Get-InterfaceInfo, Get-InterfaceConfiguration, Get-SpanningTreeInfo, Get-InterfacesForHostsBatch, Invoke-ParallelDbQuery, Import-DatabaseModule


