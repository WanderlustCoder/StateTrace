[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OldSnapshotPath,
    [Parameter(Mandatory = $true)]
    [string]$NewSnapshotPath,
    [string]$OldRouteRecordsPath,
    [string]$NewRouteRecordsPath,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,
    [string]$MarkdownPath,
    [switch]$AllowDifferentTargets,
    [switch]$PassThru,
    [switch]$UpdateLatest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$latestPointerPath = Join-Path -Path $repoRoot -ChildPath 'Logs/Reports/RoutingDiff/RoutingDiff-latest.json'

function Ensure-Directory {
    param([string]$Path)
    $directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
}

function Get-PropertyNames {
    param([object]$Object)
    if ($null -eq $Object) { return @() }
    return @($Object.PSObject.Properties | ForEach-Object { $_.Name })
}

function Get-OptionalProperty {
    param(
        [object]$Object,
        [string]$Name
    )
    if ($null -eq $Object) { return $null }
    $props = Get-PropertyNames -Object $Object
    if ($props -contains $Name) {
        return $Object.$Name
    }
    return $null
}

function Read-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Label
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Label not found at '$Path'."
    }
    try {
        return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -ErrorAction Stop)
    } catch {
        throw "Failed to parse JSON for $Label at '$Path'."
    }
}

function Validate-Snapshot {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Snapshot,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    $required = @(
        'SchemaVersion',
        'CapturedAt',
        'Site',
        'Hostname',
        'Vrf',
        'PrimaryRouteStatus',
        'SecondaryRouteStatus',
        'HealthState',
        'RouteRecordIds'
    )
    $props = Get-PropertyNames -Object $Snapshot
    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($field in $required) {
        if ($props -notcontains $field) {
            $missing.Add($field) | Out-Null
            continue
        }
        $value = $Snapshot.$field
        if ($field -eq 'RouteRecordIds') {
            if ($null -eq $value -or ($value -is [string]) -or ($value -isnot [System.Collections.IEnumerable])) {
                $missing.Add($field) | Out-Null
            }
        } else {
            if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) {
                $missing.Add($field) | Out-Null
            }
        }
    }
    if ($missing.Count -gt 0) {
        throw "RouteHealthSnapshot '$Path' is missing required fields: $($missing -join ', ')."
    }
}

function Get-TargetSignature {
    param([object]$Snapshot)
    return [pscustomobject]@{
        Site     = Get-OptionalProperty -Object $Snapshot -Name 'Site'
        Hostname = Get-OptionalProperty -Object $Snapshot -Name 'Hostname'
        Vrf      = Get-OptionalProperty -Object $Snapshot -Name 'Vrf'
    }
}

function Get-UniqueIdSet {
    param(
        [string[]]$Ids,
        [string]$Label,
        [System.Collections.Generic.List[string]]$Warnings
    )
    $set = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::Ordinal)
    foreach ($id in $Ids) {
        if (-not $set.Add($id)) {
            $Warnings.Add("$Label contains duplicate RouteRecordId '$id'.") | Out-Null
        }
    }
    return ,$set
}

function Read-RouteRecords {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Label
    )
    $records = Read-JsonFile -Path $Path -Label $Label
    if ($records -isnot [System.Array]) {
        $records = @($records)
    }
    return $records
}

function Build-RecordMap {
    param(
        [object[]]$Records,
        [string]$Label,
        [System.Collections.Generic.List[string]]$Warnings
    )
    $map = @{}
    foreach ($record in $Records) {
        $recordId = Get-OptionalProperty -Object $record -Name 'RecordId'
        if ([string]::IsNullOrWhiteSpace([string]$recordId)) {
            $Warnings.Add("$Label record missing RecordId.") | Out-Null
            continue
        }
        if ($map.ContainsKey($recordId)) {
            $Warnings.Add("$Label record duplicate RecordId '$recordId'.") | Out-Null
            continue
        }
        $map[$recordId] = $record
    }
    return $map
}

function Get-RouteKey {
    param(
        [object]$Record,
        [string]$FallbackVrf,
        [string]$Label,
        [System.Collections.Generic.List[string]]$Warnings
    )
    $vrf = Get-OptionalProperty -Object $Record -Name 'Vrf'
    if ([string]::IsNullOrWhiteSpace([string]$vrf)) {
        $vrf = $FallbackVrf
    }
    $prefix = Get-OptionalProperty -Object $Record -Name 'Prefix'
    $prefixLength = Get-OptionalProperty -Object $Record -Name 'PrefixLength'
    $routeRole = Get-OptionalProperty -Object $Record -Name 'RouteRole'
    if ([string]::IsNullOrWhiteSpace([string]$vrf) -or
        [string]::IsNullOrWhiteSpace([string]$prefix) -or
        $null -eq $prefixLength -or
        [string]::IsNullOrWhiteSpace([string]$routeRole)) {
        $Warnings.Add("$Label record missing fields for diff key.") | Out-Null
        return $null
    }
    return ('{0}|{1}/{2}|{3}' -f $vrf, $prefix, $prefixLength, $routeRole)
}

function Build-KeyMap {
    param(
        [object[]]$Records,
        [string]$Label,
        [string]$FallbackVrf,
        [System.Collections.Generic.List[string]]$Warnings
    )
    $map = @{}
    foreach ($record in $Records) {
        $key = Get-RouteKey -Record $record -FallbackVrf $FallbackVrf -Label $Label -Warnings $Warnings
        if ([string]::IsNullOrWhiteSpace($key)) { continue }
        if ($map.ContainsKey($key)) {
            $Warnings.Add("$Label record duplicate diff key '$key'.") | Out-Null
            continue
        }
        $map[$key] = $record
    }
    return $map
}

function Get-RouteDetail {
    param(
        [object]$Record,
        [string]$FallbackVrf
    )
    $vrf = Get-OptionalProperty -Object $Record -Name 'Vrf'
    if ([string]::IsNullOrWhiteSpace([string]$vrf)) { $vrf = $FallbackVrf }
    return [ordered]@{
        RecordId      = Get-OptionalProperty -Object $Record -Name 'RecordId'
        Vrf           = $vrf
        Prefix        = Get-OptionalProperty -Object $Record -Name 'Prefix'
        PrefixLength  = Get-OptionalProperty -Object $Record -Name 'PrefixLength'
        NextHop       = Get-OptionalProperty -Object $Record -Name 'NextHop'
        Protocol      = Get-OptionalProperty -Object $Record -Name 'Protocol'
        RouteRole     = Get-OptionalProperty -Object $Record -Name 'RouteRole'
        RouteState    = Get-OptionalProperty -Object $Record -Name 'RouteState'
        InterfaceName = Get-OptionalProperty -Object $Record -Name 'InterfaceName'
        AdminDistance = Get-OptionalProperty -Object $Record -Name 'AdminDistance'
        Metric        = Get-OptionalProperty -Object $Record -Name 'Metric'
    }
}

function Get-ChangeSummary {
    param([object]$Detail)
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($field in @('NextHop','Protocol','RouteState','InterfaceName','AdminDistance','Metric')) {
        if ($null -ne $Detail[$field]) {
            $parts.Add(('{0}={1}' -f $field, $Detail[$field]))
        }
    }
    if ($parts.Count -eq 0) { return 'No details' }
    return ($parts -join '; ')
}

# LANDMARK: Routing diff - load and validate snapshots with target matching rules
$warnings = New-Object System.Collections.Generic.List[string]
$oldSnapshot = Read-JsonFile -Path $OldSnapshotPath -Label 'OldSnapshot'
$newSnapshot = Read-JsonFile -Path $NewSnapshotPath -Label 'NewSnapshot'
Validate-Snapshot -Snapshot $oldSnapshot -Path $OldSnapshotPath
Validate-Snapshot -Snapshot $newSnapshot -Path $NewSnapshotPath

$oldTarget = Get-TargetSignature -Snapshot $oldSnapshot
$newTarget = Get-TargetSignature -Snapshot $newSnapshot
if (-not $AllowDifferentTargets.IsPresent) {
    if ($oldTarget.Site -ne $newTarget.Site -or $oldTarget.Hostname -ne $newTarget.Hostname -or $oldTarget.Vrf -ne $newTarget.Vrf) {
        throw ("Snapshot targets do not match. Old: Site={0} Hostname={1} Vrf={2} | New: Site={3} Hostname={4} Vrf={5}. Use -AllowDifferentTargets to override." -f `
            $oldTarget.Site, $oldTarget.Hostname, $oldTarget.Vrf, $newTarget.Site, $newTarget.Hostname, $newTarget.Vrf)
    }
}

# LANDMARK: Routing diff - compute added/removed IDs and health state transitions
$oldIdsRaw = @($oldSnapshot.RouteRecordIds) | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
$newIdsRaw = @($newSnapshot.RouteRecordIds) | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
$oldIdSet = Get-UniqueIdSet -Ids $oldIdsRaw -Label 'OldSnapshot' -Warnings $warnings
$newIdSet = Get-UniqueIdSet -Ids $newIdsRaw -Label 'NewSnapshot' -Warnings $warnings
$oldIdList = @($oldIdSet) | Sort-Object
$newIdList = @($newIdSet) | Sort-Object
$addedIds = @($newIdList | Where-Object { -not $oldIdSet.Contains($_) })
$removedIds = @($oldIdList | Where-Object { -not $newIdSet.Contains($_) })
$unchangedCount = @($newIdList | Where-Object { $oldIdSet.Contains($_) }).Count

$healthChanges = [ordered]@{
    PrimaryRouteStatus   = [ordered]@{ Old = $oldSnapshot.PrimaryRouteStatus; New = $newSnapshot.PrimaryRouteStatus }
    SecondaryRouteStatus = [ordered]@{ Old = $oldSnapshot.SecondaryRouteStatus; New = $newSnapshot.SecondaryRouteStatus }
    HealthState          = [ordered]@{ Old = $oldSnapshot.HealthState; New = $newSnapshot.HealthState }
}
$oldHealthScore = Get-OptionalProperty -Object $oldSnapshot -Name 'HealthScore'
$newHealthScore = Get-OptionalProperty -Object $newSnapshot -Name 'HealthScore'
if ($null -ne $oldHealthScore -or $null -ne $newHealthScore) {
    $healthChanges['HealthScore'] = [ordered]@{ Old = $oldHealthScore; New = $newHealthScore }
}
$oldLatency = Get-OptionalProperty -Object $oldSnapshot -Name 'DetectionLatencyMs'
$newLatency = Get-OptionalProperty -Object $newSnapshot -Name 'DetectionLatencyMs'
if ($null -ne $oldLatency -or $null -ne $newLatency) {
    $healthChanges['DetectionLatencyMs'] = [ordered]@{ Old = $oldLatency; New = $newLatency }
}

# LANDMARK: Routing diff - optional route record enrichment and changed-route detection
$addedRouteRecords = [System.Collections.Generic.List[object]]::new()
$removedRouteRecords = [System.Collections.Generic.List[object]]::new()
$changedRoutes = [System.Collections.Generic.List[object]]::new()
if (-not [string]::IsNullOrWhiteSpace($OldRouteRecordsPath) -or -not [string]::IsNullOrWhiteSpace($NewRouteRecordsPath)) {
    if ([string]::IsNullOrWhiteSpace($OldRouteRecordsPath) -or [string]::IsNullOrWhiteSpace($NewRouteRecordsPath)) {
        $warnings.Add('RouteRecords enrichment requires both OldRouteRecordsPath and NewRouteRecordsPath; skipping enrichment.') | Out-Null
    } else {
        $oldRecords = Read-RouteRecords -Path $OldRouteRecordsPath -Label 'OldRouteRecords'
        $newRecords = Read-RouteRecords -Path $NewRouteRecordsPath -Label 'NewRouteRecords'
        $oldRecordMap = Build-RecordMap -Records $oldRecords -Label 'OldRouteRecords' -Warnings $warnings
        $newRecordMap = Build-RecordMap -Records $newRecords -Label 'NewRouteRecords' -Warnings $warnings
        $oldKeyMap = Build-KeyMap -Records $oldRecords -Label 'OldRouteRecords' -FallbackVrf $oldSnapshot.Vrf -Warnings $warnings
        $newKeyMap = Build-KeyMap -Records $newRecords -Label 'NewRouteRecords' -FallbackVrf $newSnapshot.Vrf -Warnings $warnings

        foreach ($id in $addedIds) {
            if ($newRecordMap.ContainsKey($id)) {
                $addedRouteRecords.Add((Get-RouteDetail -Record $newRecordMap[$id] -FallbackVrf $newSnapshot.Vrf))
            } else {
                $warnings.Add("Added RouteRecordId '$id' not found in NewRouteRecords.") | Out-Null
            }
        }
        foreach ($id in $removedIds) {
            if ($oldRecordMap.ContainsKey($id)) {
                $removedRouteRecords.Add((Get-RouteDetail -Record $oldRecordMap[$id] -FallbackVrf $oldSnapshot.Vrf))
            } else {
                $warnings.Add("Removed RouteRecordId '$id' not found in OldRouteRecords.") | Out-Null
            }
        }

        $commonKeys = $oldKeyMap.Keys | Where-Object { $newKeyMap.ContainsKey($_) } | Sort-Object
        foreach ($key in $commonKeys) {
            $oldRecord = $oldKeyMap[$key]
            $newRecord = $newKeyMap[$key]
            $fieldsChanged = New-Object System.Collections.Generic.List[string]
            foreach ($field in @('NextHop','Protocol','RouteState','InterfaceName','AdminDistance','Metric')) {
                $oldValue = Get-OptionalProperty -Object $oldRecord -Name $field
                $newValue = Get-OptionalProperty -Object $newRecord -Name $field
                if ($oldValue -ne $newValue) {
                    $fieldsChanged.Add($field) | Out-Null
                }
            }
            if ($fieldsChanged.Count -gt 0) {
                $changedRoutes.Add([ordered]@{
                    Key           = $key
                    FieldsChanged = $fieldsChanged
                    Old           = Get-RouteDetail -Record $oldRecord -FallbackVrf $oldSnapshot.Vrf
                    New           = Get-RouteDetail -Record $newRecord -FallbackVrf $newSnapshot.Vrf
                })
            }
        }
    }
}

$oldResolvedPath = (Resolve-Path -LiteralPath $OldSnapshotPath -ErrorAction Stop).Path
$newResolvedPath = (Resolve-Path -LiteralPath $NewSnapshotPath -ErrorAction Stop).Path
$status = 'Pass'

$oldBlock = [ordered]@{
    Path                 = $oldResolvedPath
    CapturedAt           = $oldSnapshot.CapturedAt
    Site                 = $oldSnapshot.Site
    Hostname             = $oldSnapshot.Hostname
    Vrf                  = $oldSnapshot.Vrf
    PrimaryRouteStatus   = $oldSnapshot.PrimaryRouteStatus
    SecondaryRouteStatus = $oldSnapshot.SecondaryRouteStatus
    HealthState          = $oldSnapshot.HealthState
}
if ($null -ne $oldHealthScore) { $oldBlock['HealthScore'] = $oldHealthScore }
if ($null -ne $oldLatency) { $oldBlock['DetectionLatencyMs'] = $oldLatency }

$newBlock = [ordered]@{
    Path                 = $newResolvedPath
    CapturedAt           = $newSnapshot.CapturedAt
    Site                 = $newSnapshot.Site
    Hostname             = $newSnapshot.Hostname
    Vrf                  = $newSnapshot.Vrf
    PrimaryRouteStatus   = $newSnapshot.PrimaryRouteStatus
    SecondaryRouteStatus = $newSnapshot.SecondaryRouteStatus
    HealthState          = $newSnapshot.HealthState
}
if ($null -ne $newHealthScore) { $newBlock['HealthScore'] = $newHealthScore }
if ($null -ne $newLatency) { $newBlock['DetectionLatencyMs'] = $newLatency }

$changesBlock = [ordered]@{
    Health              = $healthChanges
    AddedRouteRecordIds = @($addedIds)
    RemovedRouteRecordIds = @($removedIds)
    UnchangedCount    = $unchangedCount
    ChangedRoutes       = $changedRoutes
}
if ($addedRouteRecords.Count -gt 0) { $changesBlock['AddedRouteRecords'] = $addedRouteRecords }
if ($removedRouteRecords.Count -gt 0) { $changesBlock['RemovedRouteRecords'] = $removedRouteRecords }

$warningsArray = if ($warnings -is [System.Collections.Generic.List[string]]) {
    $warnings.ToArray()
} else {
    @($warnings)
}
$warningsArray = @($warningsArray)

$diff = [ordered]@{
    SchemaVersion = '1.0'
    Status        = $status
    GeneratedAt   = (Get-Date -Format o)
    Old           = $oldBlock
    New           = $newBlock
    Counts        = [ordered]@{
        Added         = @($addedIds).Count
        Removed       = @($removedIds).Count
        ChangedRoutes = @($changedRoutes).Count
    }
    Changes       = $changesBlock
    Warnings      = $warningsArray
}

# LANDMARK: Routing diff - deterministic JSON/markdown emission and latest pointer
Ensure-Directory -Path $OutputPath
$diff | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

if (-not [string]::IsNullOrWhiteSpace($MarkdownPath)) {
    Ensure-Directory -Path $MarkdownPath
    $lines = New-Object System.Collections.Generic.List[string]
    $title = '# Routing Diff Report - {0} / {1} / {2}' -f $newSnapshot.Site, $newSnapshot.Hostname, $newSnapshot.Vrf
    $lines.Add($title)
    $lines.Add('')
    $lines.Add(('- GeneratedAt: {0}' -f $diff.GeneratedAt))
    $lines.Add(('- OldSnapshotPath: `{0}`' -f $oldResolvedPath))
    $lines.Add(('- NewSnapshotPath: `{0}`' -f $newResolvedPath))
    $lines.Add(('- OldCapturedAt: {0}' -f $oldSnapshot.CapturedAt))
    $lines.Add(('- NewCapturedAt: {0}' -f $newSnapshot.CapturedAt))
    $lines.Add(('- AllowDifferentTargets: {0}' -f ($AllowDifferentTargets.IsPresent)))
    $lines.Add('')
    $lines.Add('## Health status changes')
    $lines.Add('')
    $lines.Add('| Field | Old | New |')
    $lines.Add('| --- | --- | --- |')
    foreach ($key in $healthChanges.Keys) {
        $value = $healthChanges[$key]
        $lines.Add(('| {0} | {1} | {2} |' -f $key, $value.Old, $value.New))
    }
    $lines.Add('')
    $lines.Add('## Added route records')
    $lines.Add('')
    if ($addedRouteRecords.Count -gt 0) {
        $lines.Add('| RecordId | Prefix | PrefixLength | NextHop | Protocol | RouteRole | RouteState | InterfaceName | AdminDistance | Metric |')
        $lines.Add('| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |')
        foreach ($record in $addedRouteRecords) {
            $lines.Add(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} |' -f `
                $record.RecordId, $record.Prefix, $record.PrefixLength, $record.NextHop, $record.Protocol, $record.RouteRole, $record.RouteState, $record.InterfaceName, $record.AdminDistance, $record.Metric))
        }
    } elseif ($addedIds.Count -gt 0) {
        foreach ($id in $addedIds) { $lines.Add(('- {0}' -f $id)) }
    } else {
        $lines.Add('None.')
    }
    $lines.Add('')
    $lines.Add('## Removed route records')
    $lines.Add('')
    if ($removedRouteRecords.Count -gt 0) {
        $lines.Add('| RecordId | Prefix | PrefixLength | NextHop | Protocol | RouteRole | RouteState | InterfaceName | AdminDistance | Metric |')
        $lines.Add('| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |')
        foreach ($record in $removedRouteRecords) {
            $lines.Add(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} |' -f `
                $record.RecordId, $record.Prefix, $record.PrefixLength, $record.NextHop, $record.Protocol, $record.RouteRole, $record.RouteState, $record.InterfaceName, $record.AdminDistance, $record.Metric))
        }
    } elseif ($removedIds.Count -gt 0) {
        foreach ($id in $removedIds) { $lines.Add(('- {0}' -f $id)) }
    } else {
        $lines.Add('None.')
    }
    $lines.Add('')
    $lines.Add('## Changed routes')
    $lines.Add('')
    if ($changedRoutes.Count -gt 0) {
        $lines.Add('| Key | FieldsChanged | Old | New |')
        $lines.Add('| --- | --- | --- | --- |')
        foreach ($change in ($changedRoutes | Sort-Object Key)) {
            $oldDetail = $change.Old
            $newDetail = $change.New
            $oldSummary = Get-ChangeSummary -Detail $oldDetail
            $newSummary = Get-ChangeSummary -Detail $newDetail
            $lines.Add(('| {0} | {1} | {2} | {3} |' -f $change.Key, ($change.FieldsChanged -join ', '), $oldSummary, $newSummary))
        }
    } else {
        $lines.Add('None.')
    }
    if (@($warningsArray).Count -gt 0) {
        $lines.Add('')
        $lines.Add('## Warnings')
        $lines.Add('')
        foreach ($warning in @($warningsArray)) { $lines.Add(('- {0}' -f $warning)) }
    }
    $lines | Set-Content -LiteralPath $MarkdownPath -Encoding UTF8
}

if ($UpdateLatest.IsPresent) {
    Ensure-Directory -Path $latestPointerPath
    Copy-Item -LiteralPath $OutputPath -Destination $latestPointerPath -Force
}

if ($PassThru.IsPresent) {
    return $diff
}
