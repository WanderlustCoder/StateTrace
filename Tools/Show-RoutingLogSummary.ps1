[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Path,
    [switch]$UseLatest,
    [ValidateSet('Console','Markdown','Csv')][string]$Format = 'Console',
    [string]$OutputPath,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Ensure-Directory {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Resolve-SummaryPath {
    param(
        [string]$InputPath,
        [switch]$UseLatest
    )
    if (-not (Test-Path -LiteralPath $InputPath)) {
        throw "Path '$InputPath' was not found."
    }
    $item = Get-Item -LiteralPath $InputPath -ErrorAction Stop
    if (-not $item.PSIsContainer) {
        return (Resolve-Path -LiteralPath $item.FullName -ErrorAction Stop).Path
    }
    if (-not $UseLatest.IsPresent) {
        throw "Path '$InputPath' is a directory. Provide a summary file path or use -UseLatest."
    }

    $latestNames = @(
        'RoutingValidationRunSummary-latest.json',
        'RoutingDiscoveryPipelineSummary-latest.json',
        'RoutingDiff-latest.json'
    )
    $candidates = foreach ($name in $latestNames) {
        $candidate = Join-Path -Path $item.FullName -ChildPath $name
        if (Test-Path -LiteralPath $candidate) {
            (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path
        }
    }
    if (-not $candidates -or $candidates.Count -eq 0) {
        throw "UseLatest requested but no latest summary files were found under '$InputPath'."
    }
    if ($candidates.Count -gt 1) {
        $ordered = $candidates | Sort-Object { (Get-Item -LiteralPath $_).LastWriteTime } -Descending
        Write-Warning ("Multiple latest summary files found under '{0}'; using '{1}'." -f $InputPath, $ordered[0])
        return $ordered[0]
    }
    return $candidates[0]
}

function Get-PropertyNames {
    param([object]$Object)
    if ($null -eq $Object) { return @() }
    return @($Object.PSObject.Properties | ForEach-Object { $_.Name })
}

function Get-SummaryType {
    param([object]$Object)
    if (-not $Object) { return $null }
    $props = Get-PropertyNames -Object $Object
    if ($props -contains 'HostSummaries') { return 'RoutingValidationRunSummary' }
    if ($props -contains 'CaptureMetadata' -and $props -contains 'ArtifactPaths') { return 'RoutingDiscoveryPipelineSummary' }
    if ($props -contains 'Old' -and $props -contains 'New' -and $props -contains 'Changes') { return 'RoutingDiff' }
    return $null
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

function Get-StringProperty {
    param(
        [object]$Object,
        [string]$Name
    )
    $value = Get-OptionalProperty -Object $Object -Name $Name
    if ($value -is [string] -and -not [string]::IsNullOrWhiteSpace($value)) {
        return $value
    }
    return $null
}

function Test-PathLike {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    if ($Value -match '[\\/]' -or $Value -match '\.md$' -or $Value -match '\.markdown$') {
        return $true
    }
    return $false
}

function Find-PathByPropertyToken {
    param(
        [object]$Object,
        [string]$Token,
        [System.Collections.Generic.HashSet[int]]$Visited
    )
    if ($null -eq $Object) { return $null }
    if ($Object -is [string] -or $Object -is [ValueType]) { return $null }

    if (-not $Visited) {
        $Visited = New-Object System.Collections.Generic.HashSet[int]
    }
    $objectId = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Object)
    if ($Visited.Contains($objectId)) { return $null }
    $Visited.Add($objectId) | Out-Null

    $tokenPattern = "*$Token*"
    if ($Object -is [System.Collections.IDictionary]) {
        foreach ($key in $Object.Keys) {
            $value = $Object[$key]
            if ($key -like $tokenPattern -and $value -is [string] -and (Test-PathLike -Value $value)) {
                return $value
            }
            $found = Find-PathByPropertyToken -Object $value -Token $Token -Visited $Visited
            if ($found) { return $found }
        }
        return $null
    }

    if ($Object -is [System.Array]) {
        foreach ($item in $Object) {
            $found = Find-PathByPropertyToken -Object $item -Token $Token -Visited $Visited
            if ($found) { return $found }
        }
        return $null
    }

    foreach ($prop in $Object.PSObject.Properties) {
        $name = $prop.Name
        $value = $prop.Value
        if ($name -like $tokenPattern -and $value -is [string] -and (Test-PathLike -Value $value)) {
            return $value
        }
        $found = Find-PathByPropertyToken -Object $value -Token $Token -Visited $Visited
        if ($found) { return $found }
    }
    return $null
}

function Resolve-DiffIdentity {
    param([object]$Payload)
    $newBlock = Get-OptionalProperty -Object $Payload -Name 'New'
    $oldBlock = Get-OptionalProperty -Object $Payload -Name 'Old'
    $site = Get-StringProperty -Object $newBlock -Name 'Site'
    if (-not $site) { $site = Get-StringProperty -Object $oldBlock -Name 'Site' }
    $hostname = Get-StringProperty -Object $newBlock -Name 'Hostname'
    if (-not $hostname) { $hostname = Get-StringProperty -Object $oldBlock -Name 'Hostname' }
    $vrf = Get-StringProperty -Object $newBlock -Name 'Vrf'
    if (-not $vrf) { $vrf = Get-StringProperty -Object $oldBlock -Name 'Vrf' }
    return [pscustomobject]@{
        Site     = $site
        Hostname = $hostname
        Vrf      = $vrf
        Old      = $oldBlock
        New      = $newBlock
    }
}

function Resolve-DiffHealthChanges {
    param([object]$Payload)
    $changes = Get-OptionalProperty -Object $Payload -Name 'Changes'
    $health = if ($changes) { Get-OptionalProperty -Object $changes -Name 'Health' } else { $null }
    $identity = Resolve-DiffIdentity -Payload $Payload
    $oldBlock = $identity.Old
    $newBlock = $identity.New
    $fields = @('PrimaryRouteStatus','SecondaryRouteStatus','HealthState','HealthScore','DetectionLatencyMs')
    $healthChanges = [ordered]@{}
    foreach ($field in $fields) {
        $change = if ($health) { Get-OptionalProperty -Object $health -Name $field } else { $null }
        if ($change) {
            $healthChanges[$field] = [ordered]@{
                Old = Get-OptionalProperty -Object $change -Name 'Old'
                New = Get-OptionalProperty -Object $change -Name 'New'
            }
            continue
        }
        $oldValue = Get-OptionalProperty -Object $oldBlock -Name $field
        $newValue = Get-OptionalProperty -Object $newBlock -Name $field
        if ($null -ne $oldValue -or $null -ne $newValue) {
            $healthChanges[$field] = [ordered]@{
                Old = $oldValue
                New = $newValue
            }
        }
    }
    return $healthChanges
}

function Resolve-DiffCounts {
    param([object]$Payload)
    $countsBlock = Get-OptionalProperty -Object $Payload -Name 'Counts'
    $changesBlock = Get-OptionalProperty -Object $Payload -Name 'Changes'
    $added = if ($countsBlock -and (Get-PropertyNames -Object $countsBlock) -contains 'Added') {
        [int]$countsBlock.Added
    } elseif ($changesBlock -and (Get-OptionalProperty -Object $changesBlock -Name 'AddedRouteRecordIds')) {
        @($changesBlock.AddedRouteRecordIds).Count
    } else { $null }
    $removed = if ($countsBlock -and (Get-PropertyNames -Object $countsBlock) -contains 'Removed') {
        [int]$countsBlock.Removed
    } elseif ($changesBlock -and (Get-OptionalProperty -Object $changesBlock -Name 'RemovedRouteRecordIds')) {
        @($changesBlock.RemovedRouteRecordIds).Count
    } else { $null }
    $unchanged = if ($changesBlock -and (Get-PropertyNames -Object $changesBlock) -contains 'UnchangedCount') {
        [int]$changesBlock.UnchangedCount
    } else { $null }
    $changedRoutes = if ($countsBlock -and (Get-PropertyNames -Object $countsBlock) -contains 'ChangedRoutes') {
        [int]$countsBlock.ChangedRoutes
    } elseif ($changesBlock -and (Get-OptionalProperty -Object $changesBlock -Name 'ChangedRoutes')) {
        @($changesBlock.ChangedRoutes).Count
    } else { $null }
    return [pscustomobject]@{
        Added         = $added
        Removed       = $removed
        Unchanged     = $unchanged
        ChangedRoutes = $changedRoutes
    }
}

function Get-HostRowsFromValidation {
    param([object]$Summary)
    $rows = [System.Collections.Generic.List[pscustomobject]]::new()
    if ($null -ne $Summary.HostSummaries) {
        foreach ($hostItem in $Summary.HostSummaries) {
            $rows.Add([pscustomobject]@{
                Hostname              = $hostItem.Hostname
                Status                = $hostItem.Status
                IngestionSummaryPath  = $hostItem.IngestionSummaryPath
                PipelineSummaryPath   = $hostItem.PipelineSummaryPath
            })
        }
    }
    return ($rows | Sort-Object Hostname)
}

function Get-HostRowsFromPipeline {
    param(
        [object]$Summary,
        [string]$SourcePath
    )
    $pipelinePath = $null
    if ($Summary.ArtifactPaths) {
        $artifactProps = Get-PropertyNames -Object $Summary.ArtifactPaths
        if ($artifactProps -contains 'PipelineSummaryPath') {
            $pipelinePath = $Summary.ArtifactPaths.PipelineSummaryPath
        }
    }
    if (-not $pipelinePath) { $pipelinePath = $SourcePath }
    $ingestPath = $null
    if ($Summary.ArtifactPaths) {
        $artifactProps = Get-PropertyNames -Object $Summary.ArtifactPaths
        if ($artifactProps -contains 'RouteRecordsSummaryPath') {
            $ingestPath = $Summary.ArtifactPaths.RouteRecordsSummaryPath
        }
    }
    $hostname = $null
    if ($Summary.CaptureMetadata) {
        $metaProps = Get-PropertyNames -Object $Summary.CaptureMetadata
        if ($metaProps -contains 'Hostname') {
            $hostname = $Summary.CaptureMetadata.Hostname
        }
    }
    return @([pscustomobject]@{
        Hostname              = $hostname
        Status                = $Summary.Status
        IngestionSummaryPath  = $ingestPath
        PipelineSummaryPath   = $pipelinePath
    })
}

if ($Format -ne 'Console' -and [string]::IsNullOrWhiteSpace($OutputPath)) {
    throw "OutputPath is required when Format is '$Format'."
}

$summaryPath = Resolve-SummaryPath -InputPath $Path -UseLatest:$UseLatest
$payload = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json -ErrorAction Stop
$summaryType = Get-SummaryType -Object $payload
if (-not $summaryType) {
    throw "Unsupported summary format in '$summaryPath'. Expected RoutingValidationRunSummary, RoutingDiscoveryPipelineSummary, or RoutingDiff."
}

if ($summaryType -eq 'RoutingDiff') {
    # LANDMARK: Routing summary render - support RoutingDiff JSON for Console/Markdown output
    $identity = Resolve-DiffIdentity -Payload $payload
    $healthChanges = Resolve-DiffHealthChanges -Payload $payload
    $counts = Resolve-DiffCounts -Payload $payload
    $oldCapturedAt = Get-OptionalProperty -Object $identity.Old -Name 'CapturedAt'
    $newCapturedAt = Get-OptionalProperty -Object $identity.New -Name 'CapturedAt'
    $summary = [pscustomobject]@{
        SummaryType   = $summaryType
        SourcePath    = $summaryPath
        Status        = $payload.Status
        Site          = $identity.Site
        Hostname      = $identity.Hostname
        Vrf           = $identity.Vrf
        OldCapturedAt = $oldCapturedAt
        NewCapturedAt = $newCapturedAt
        HealthChanges = $healthChanges
        Counts        = $counts
        Raw           = $payload
    }

    if ($Format -eq 'Console') {
        Write-Host "[Routing] Diff Summary" -ForegroundColor Cyan
        Write-Host ("  Source : {0}" -f $summaryPath)
        Write-Host ("  Status : {0}" -f $summary.Status)
        if ($summary.Site) { Write-Host ("  Site   : {0}" -f $summary.Site) }
        if ($summary.Hostname) { Write-Host ("  Hostname: {0}" -f $summary.Hostname) }
        if ($summary.Vrf) { Write-Host ("  Vrf    : {0}" -f $summary.Vrf) }
        if ($summary.OldCapturedAt) { Write-Host ("  OldCapturedAt: {0}" -f $summary.OldCapturedAt) }
        if ($summary.NewCapturedAt) { Write-Host ("  NewCapturedAt: {0}" -f $summary.NewCapturedAt) }
        foreach ($field in $summary.HealthChanges.Keys) {
            $value = $summary.HealthChanges[$field]
            Write-Host ("  {0}: {1} -> {2}" -f $field, $value.Old, $value.New)
        }
        if ($null -ne $counts.Added -or $null -ne $counts.Removed -or $null -ne $counts.Unchanged) {
            Write-Host ("  RouteRecordIds: Added {0}, Removed {1}, Unchanged {2}" -f $counts.Added, $counts.Removed, $counts.Unchanged)
        }
        if ($null -ne $counts.ChangedRoutes) {
            Write-Host ("  ChangedRoutes: {0}" -f $counts.ChangedRoutes)
        }
    } elseif ($Format -eq 'Markdown') {
        Ensure-Directory -Path (Split-Path -Parent $OutputPath)
        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add('# Routing Diff')
        $lines.Add('')
        $lines.Add(('- Source: `{0}`' -f $summaryPath))
        $lines.Add(('- Status: {0}' -f $summary.Status))
        if ($summary.Site) { $lines.Add(('- Site: {0}' -f $summary.Site)) }
        if ($summary.Hostname) { $lines.Add(('- Hostname: {0}' -f $summary.Hostname)) }
        if ($summary.Vrf) { $lines.Add(('- Vrf: {0}' -f $summary.Vrf)) }
        if ($summary.OldCapturedAt) { $lines.Add(('- OldCapturedAt: {0}' -f $summary.OldCapturedAt)) }
        if ($summary.NewCapturedAt) { $lines.Add(('- NewCapturedAt: {0}' -f $summary.NewCapturedAt)) }
        $lines.Add('')
        $lines.Add('## Health changes')
        $lines.Add('')
        $lines.Add('| Field | Old | New |')
        $lines.Add('| --- | --- | --- |')
        foreach ($field in $summary.HealthChanges.Keys) {
            $value = $summary.HealthChanges[$field]
            $lines.Add(('| {0} | {1} | {2} |' -f $field, $value.Old, $value.New))
        }
        $lines.Add('')
        $lines.Add('## Route record deltas')
        $lines.Add('')
        if ($null -ne $counts.Added) { $lines.Add(('- Added: {0}' -f $counts.Added)) }
        if ($null -ne $counts.Removed) { $lines.Add(('- Removed: {0}' -f $counts.Removed)) }
        if ($null -ne $counts.Unchanged) { $lines.Add(('- Unchanged: {0}' -f $counts.Unchanged)) }
        if ($null -ne $counts.ChangedRoutes) { $lines.Add(('- Changed routes: {0}' -f $counts.ChangedRoutes)) }
        $markdownPath = Get-StringProperty -Object $payload -Name 'MarkdownPath'
        if (-not $markdownPath) {
            $markdownPath = Find-PathByPropertyToken -Object $payload -Token 'Markdown'
        }
        if ($markdownPath -and (Test-Path -LiteralPath $markdownPath)) {
            $lines.Add('')
            $lines.Add(('- See also: `{0}`' -f $markdownPath))
        }
        $lines | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    } else {
        Ensure-Directory -Path (Split-Path -Parent $OutputPath)
        $primaryChange = $summary.HealthChanges['PrimaryRouteStatus']
        $secondaryChange = $summary.HealthChanges['SecondaryRouteStatus']
        $stateChange = $summary.HealthChanges['HealthState']
        $csvRows = @([pscustomobject]@{
            SummaryType          = $summaryType
            SourcePath           = $summaryPath
            Status               = $summary.Status
            Site                 = $summary.Site
            Hostname             = $summary.Hostname
            Vrf                  = $summary.Vrf
            OldCapturedAt        = $summary.OldCapturedAt
            NewCapturedAt        = $summary.NewCapturedAt
            PrimaryRouteStatusOld = if ($primaryChange) { $primaryChange.Old } else { $null }
            PrimaryRouteStatusNew = if ($primaryChange) { $primaryChange.New } else { $null }
            SecondaryRouteStatusOld = if ($secondaryChange) { $secondaryChange.Old } else { $null }
            SecondaryRouteStatusNew = if ($secondaryChange) { $secondaryChange.New } else { $null }
            HealthStateOld       = if ($stateChange) { $stateChange.Old } else { $null }
            HealthStateNew       = if ($stateChange) { $stateChange.New } else { $null }
            AddedRouteRecordIds  = $counts.Added
            RemovedRouteRecordIds = $counts.Removed
            UnchangedRouteRecordIds = $counts.Unchanged
            ChangedRoutes        = $counts.ChangedRoutes
        })
        $csvRows | ConvertTo-Csv -NoTypeInformation | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    }

    if ($PassThru.IsPresent) {
        return $summary
    }
    return
}

# LANDMARK: Offline routing log viewer - detect supported summary types and parse safely
$mode = Get-OptionalProperty -Object $payload -Name 'Mode'
$site = Get-OptionalProperty -Object $payload -Name 'Site'
$vendor = Get-OptionalProperty -Object $payload -Name 'Vendor'
$vrf = Get-OptionalProperty -Object $payload -Name 'Vrf'
$hostRows = @()
switch ($summaryType) {
    'RoutingValidationRunSummary' {
        $hostRows = Get-HostRowsFromValidation -Summary $payload
    }
    'RoutingDiscoveryPipelineSummary' {
        $hostRows = Get-HostRowsFromPipeline -Summary $payload -SourcePath $summaryPath
        if ($payload.CaptureMetadata) {
            $site = Get-OptionalProperty -Object $payload.CaptureMetadata -Name 'Site'
            $vrf = Get-OptionalProperty -Object $payload.CaptureMetadata -Name 'Vrf'
        }
    }
}

# LANDMARK: Offline routing log viewer - derived stats and host table projection
$hostCount = $hostRows.Count
$passCount = ($hostRows | Where-Object { $_.Status -eq 'Pass' }).Count
$failCount = $hostCount - $passCount
$summary = [pscustomobject]@{
    SummaryType    = $summaryType
    SourcePath     = $summaryPath
    Status         = $payload.Status
    Mode           = $mode
    Site           = $site
    Vendor         = $vendor
    Vrf            = $vrf
    HostCount      = $hostCount
    HostPassCount  = $passCount
    HostFailCount  = $failCount
    HostSummaries  = $hostRows
    Raw            = $payload
}

if ($Format -eq 'Console') {
    Write-Host "[Routing] Summary" -ForegroundColor Cyan
    Write-Host ("  Source : {0}" -f $summaryPath)
    Write-Host ("  Type   : {0}" -f $summaryType)
    Write-Host ("  Status : {0}" -f $summary.Status)
    if ($summary.Mode) { Write-Host ("  Mode   : {0}" -f $summary.Mode) }
    if ($summary.Site) { Write-Host ("  Site   : {0}" -f $summary.Site) }
    if ($summary.Vendor) { Write-Host ("  Vendor : {0}" -f $summary.Vendor) }
    if ($summary.Vrf) { Write-Host ("  Vrf    : {0}" -f $summary.Vrf) }
    Write-Host ("  Hosts  : {0} (Pass {1}, Fail {2})" -f $hostCount, $passCount, $failCount)
    if ($hostRows.Count -gt 0) {
        $hostRows | Select-Object Hostname, Status, IngestionSummaryPath, PipelineSummaryPath | Format-Table -AutoSize | Out-String | Write-Host
    }
} elseif ($Format -eq 'Markdown') {
    Ensure-Directory -Path (Split-Path -Parent $OutputPath)
    # LANDMARK: Offline routing log viewer - markdown/csv emission with deterministic ordering
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# Routing Log Summary')
    $lines.Add('')
    $lines.Add(('- Source: `{0}`' -f $summaryPath))
    $lines.Add(('- Summary type: {0}' -f $summaryType))
    $lines.Add(('- Status: {0}' -f $summary.Status))
    if ($summary.Mode) { $lines.Add(('- Mode: {0}' -f $summary.Mode)) }
    if ($summary.Site) { $lines.Add(('- Site: {0}' -f $summary.Site)) }
    if ($summary.Vendor) { $lines.Add(('- Vendor: {0}' -f $summary.Vendor)) }
    if ($summary.Vrf) { $lines.Add(('- Vrf: {0}' -f $summary.Vrf)) }
    $lines.Add(('- Hosts: {0} (Pass {1}, Fail {2})' -f $hostCount, $passCount, $failCount))
    $lines.Add('')
    $lines.Add('| Hostname | Status | IngestionSummaryPath | PipelineSummaryPath |')
    $lines.Add('| --- | --- | --- | --- |')
    foreach ($row in $hostRows) {
        $lines.Add(('| {0} | {1} | {2} | {3} |' -f $row.Hostname, $row.Status, $row.IngestionSummaryPath, $row.PipelineSummaryPath))
    }
    $lines | Set-Content -LiteralPath $OutputPath -Encoding UTF8
} else {
    Ensure-Directory -Path (Split-Path -Parent $OutputPath)
    # LANDMARK: Offline routing log viewer - markdown/csv emission with deterministic ordering
    $csvRows = $hostRows | ForEach-Object {
        [pscustomobject]@{
            SummaryType           = $summaryType
            SourcePath            = $summaryPath
            Status                = $summary.Status
            Mode                  = $summary.Mode
            Site                  = $summary.Site
            Vendor                = $summary.Vendor
            Vrf                   = $summary.Vrf
            Hostname              = $_.Hostname
            HostStatus            = $_.Status
            IngestionSummaryPath  = $_.IngestionSummaryPath
            PipelineSummaryPath   = $_.PipelineSummaryPath
        }
    }
    $csvRows | ConvertTo-Csv -NoTypeInformation | Set-Content -LiteralPath $OutputPath -Encoding UTF8
}

if ($PassThru.IsPresent) {
    return $summary
}
