[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RootPath,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,
    [switch]$Recurse = $true,
    [switch]$UseLatestPointers,
    [switch]$IncludeUnknown,
    [switch]$UpdateLatest,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$latestPointerPath = Join-Path -Path $repoRoot -ChildPath 'Logs/Reports/RoutingLogIndex/RoutingLogIndex-latest.json'

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
    if ($props -contains $Name) { return $Object.$Name }
    return $null
}

function Get-SummaryType {
    param([object]$Object)
    if ($null -eq $Object) { return $null }
    $props = Get-PropertyNames -Object $Object
    if ($props -contains 'HostSummaries') { return 'RoutingValidationRunSummary' }
    if ($props -contains 'CaptureMetadata' -and $props -contains 'ArtifactPaths') { return 'RoutingDiscoveryPipelineSummary' }
    if ($props -contains 'EvidencePath' -and $props -contains 'Validation') { return 'RoutingRealDeviceEvidence' }
    if ($props -contains 'Old' -and $props -contains 'New' -and $props -contains 'Changes') { return 'RoutingDiff' }
    return $null
}

function Get-TimestampFromPath {
    param([string]$Path)
    $name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    if ($name -match '(\d{8}-\d{6})') {
        $raw = $Matches[1]
        $parsed = [datetime]::ParseExact($raw, 'yyyyMMdd-HHmmss', $null)
        return $parsed.ToString('o')
    }
    if ($name -match '(\d{8})') {
        $raw = $Matches[1]
        $parsed = [datetime]::ParseExact($raw, 'yyyyMMdd', $null)
        return $parsed.ToString('o')
    }
    return $null
}

function Try-ParseTimestamp {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $parsed = [datetime]::MinValue
    if ([datetime]::TryParse([string]$Value, [ref]$parsed)) {
        return $parsed.ToString('o')
    }
    return $null
}

function Resolve-EntryTimestamp {
    param(
        [string]$Path,
        [object]$Payload
    )
    $timestamp = Get-TimestampFromPath -Path $Path
    if ($timestamp) { return $timestamp }
    foreach ($field in @('Timestamp','GeneratedAt','CapturedAt')) {
        $value = Get-OptionalProperty -Object $Payload -Name $field
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $parsed = Try-ParseTimestamp -Value $value
            if ($parsed) { return $parsed }
        }
    }
    return [System.IO.Path]::GetFileName($Path)
}

function Resolve-DiffTimestamp {
    param(
        [string]$Path,
        [object]$Payload
    )
    $newBlock = Get-OptionalProperty -Object $Payload -Name 'New'
    $capturedAt = Get-OptionalProperty -Object $newBlock -Name 'CapturedAt'
    $parsed = Try-ParseTimestamp -Value $capturedAt
    if ($parsed) { return $parsed }
    $parsed = Try-ParseTimestamp -Value (Get-OptionalProperty -Object $Payload -Name 'NewCapturedAt')
    if ($parsed) { return $parsed }
    $parsed = Try-ParseTimestamp -Value (Get-OptionalProperty -Object $Payload -Name 'GeneratedAt')
    if ($parsed) { return $parsed }
    return Resolve-EntryTimestamp -Path $Path -Payload $Payload
}

function Get-SortTimestamp {
    param([string]$Timestamp)
    $parsed = [datetime]::MinValue
    if ([datetime]::TryParse([string]$Timestamp, [ref]$parsed)) {
        return $parsed
    }
    return [datetime]::MinValue
}

if (-not (Test-Path -LiteralPath $RootPath)) {
    throw "RootPath '$RootPath' was not found."
}

$rootItem = Get-Item -LiteralPath $RootPath -ErrorAction Stop
$files = @()
if (-not $rootItem.PSIsContainer) {
    $files = @($rootItem)
} else {
    $files = Get-ChildItem -LiteralPath $RootPath -File -Recurse:$Recurse
    $files = $files | Where-Object {
        $_.Name -like 'RoutingValidationRunSummary-*.json' -or
        $_.Name -like 'RoutingDiscoveryPipelineSummary-*.json' -or
        $_.Name -like 'RoutingRealDeviceEvidence*.json' -or
        $_.Name -like 'RoutingDiff-*.json'
    }
    if (-not $UseLatestPointers.IsPresent) {
        $files = $files | Where-Object { $_.Name -notlike '*-latest.json' }
    }
    $files = @($files)
}

if (-not $files -or $files.Count -eq 0) {
    throw "No routing summary JSON files were found under '$RootPath'."
}

if ($UseLatestPointers.IsPresent -and $rootItem.PSIsContainer) {
    $latestFiles = @($files | Where-Object { $_.Name -like '*-latest.json' })
    if (-not $latestFiles -or $latestFiles.Count -eq 0) {
        throw "UseLatestPointers requested but no latest summary files were found under '$RootPath'."
    }
}

# LANDMARK: Routing log index - scan known summary types and safely detect schema by keys
$entries = @()
foreach ($file in ($files | Sort-Object FullName -Unique)) {
    $payload = $null
    try {
        $payload = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        if ($IncludeUnknown.IsPresent) {
            $timestamp = Resolve-EntryTimestamp -Path $file.FullName -Payload $null
            $entries += [pscustomobject]@{
                Type                = 'Unknown'
                Timestamp           = $timestamp
                Status              = 'InvalidJson'
                Mode                = $null
                Site                = $null
                Vendor              = $null
                Vrf                 = $null
                Hostname            = $null
                HostsProcessedCount = $null
                Path                = $file.FullName
                SortTimestamp       = Get-SortTimestamp -Timestamp $timestamp
            }
            continue
        }
        throw "Failed to parse JSON in '$($file.FullName)'."
    }

    $summaryType = Get-SummaryType -Object $payload
    if (-not $summaryType) {
        if ($IncludeUnknown.IsPresent) {
            $timestamp = Resolve-EntryTimestamp -Path $file.FullName -Payload $payload
            $entries += [pscustomobject]@{
                Type                = 'Unknown'
                Timestamp           = $timestamp
                Status              = Get-OptionalProperty -Object $payload -Name 'Status'
                Mode                = Get-OptionalProperty -Object $payload -Name 'Mode'
                Site                = Get-OptionalProperty -Object $payload -Name 'Site'
                Vendor              = Get-OptionalProperty -Object $payload -Name 'Vendor'
                Vrf                 = Get-OptionalProperty -Object $payload -Name 'Vrf'
                Hostname            = $null
                HostsProcessedCount = $null
                Path                = $file.FullName
                SortTimestamp       = Get-SortTimestamp -Timestamp $timestamp
            }
            continue
        }
        throw "Unsupported routing summary schema in '$($file.FullName)'."
    }

    # LANDMARK: Routing log index - normalize timestamps and compute stable entry metadata
    $timestamp = if ($summaryType -eq 'RoutingDiff') {
        Resolve-DiffTimestamp -Path $file.FullName -Payload $payload
    } else {
        Resolve-EntryTimestamp -Path $file.FullName -Payload $payload
    }
    $status = Get-OptionalProperty -Object $payload -Name 'Status'
    $mode = Get-OptionalProperty -Object $payload -Name 'Mode'
    $site = Get-OptionalProperty -Object $payload -Name 'Site'
    $vendor = Get-OptionalProperty -Object $payload -Name 'Vendor'
    $vrf = Get-OptionalProperty -Object $payload -Name 'Vrf'
    $hostname = $null
    $hostCount = $null

    # LANDMARK: Routing log index - detect RoutingDiff summaries and extract identity/ts metadata safely
    switch ($summaryType) {
        'RoutingValidationRunSummary' {
            $hostCount = if ($payload.HostSummaries) { @($payload.HostSummaries).Count } else { 0 }
            if ($hostCount -eq 1 -and $payload.HostSummaries[0].Hostname) {
                $hostname = $payload.HostSummaries[0].Hostname
            }
        }
        'RoutingDiscoveryPipelineSummary' {
            if ($payload.CaptureMetadata) {
                $site = Get-OptionalProperty -Object $payload.CaptureMetadata -Name 'Site'
                $vendor = Get-OptionalProperty -Object $payload.CaptureMetadata -Name 'Vendor'
                $vrf = Get-OptionalProperty -Object $payload.CaptureMetadata -Name 'Vrf'
                $hostname = Get-OptionalProperty -Object $payload.CaptureMetadata -Name 'Hostname'
            }
            if ($hostname) { $hostCount = 1 }
        }
        'RoutingRealDeviceEvidence' {
            $site = Get-OptionalProperty -Object $payload -Name 'Site'
            $vendor = Get-OptionalProperty -Object $payload -Name 'Vendor'
            $vrf = Get-OptionalProperty -Object $payload -Name 'Vrf'
        }
        'RoutingDiff' {
            $newBlock = Get-OptionalProperty -Object $payload -Name 'New'
            $oldBlock = Get-OptionalProperty -Object $payload -Name 'Old'
            $site = Get-OptionalProperty -Object $newBlock -Name 'Site'
            if (-not $site) { $site = Get-OptionalProperty -Object $oldBlock -Name 'Site' }
            $hostname = Get-OptionalProperty -Object $newBlock -Name 'Hostname'
            if (-not $hostname) { $hostname = Get-OptionalProperty -Object $oldBlock -Name 'Hostname' }
            $vrf = Get-OptionalProperty -Object $newBlock -Name 'Vrf'
            if (-not $vrf) { $vrf = Get-OptionalProperty -Object $oldBlock -Name 'Vrf' }
            if ([string]::IsNullOrWhiteSpace([string]$status)) { $status = 'Unknown' }
        }
    }

    $entries += [pscustomobject]@{
        Type                = $summaryType
        Timestamp           = $timestamp
        Status              = $status
        Mode                = $mode
        Site                = $site
        Vendor              = $vendor
        Vrf                 = $vrf
        Hostname            = $hostname
        HostsProcessedCount = $hostCount
        Path                = $file.FullName
        SortTimestamp       = Get-SortTimestamp -Timestamp $timestamp
    }
}

$entries = $entries | Sort-Object @{Expression = 'SortTimestamp'; Descending = $true}, @{Expression = 'Path'; Descending = $false}
$finalEntries = foreach ($entry in $entries) {
    [pscustomobject]@{
        Type                = $entry.Type
        Timestamp           = $entry.Timestamp
        Status              = $entry.Status
        Mode                = $entry.Mode
        Site                = $entry.Site
        Vendor              = $entry.Vendor
        Vrf                 = $entry.Vrf
        Hostname            = $entry.Hostname
        HostsProcessedCount = $entry.HostsProcessedCount
        Path                = $entry.Path
    }
}
$finalEntries = @($finalEntries)

$validationCount = @($finalEntries | Where-Object { $_.Type -eq 'RoutingValidationRunSummary' }).Count
$pipelineCount = @($finalEntries | Where-Object { $_.Type -eq 'RoutingDiscoveryPipelineSummary' }).Count
$evidenceCount = @($finalEntries | Where-Object { $_.Type -eq 'RoutingRealDeviceEvidence' }).Count
$diffCount = @($finalEntries | Where-Object { $_.Type -eq 'RoutingDiff' }).Count
$unknownCount = @($finalEntries | Where-Object { $_.Type -eq 'Unknown' }).Count

$index = [pscustomobject]@{
    SchemaVersion = '1.0'
    GeneratedAt   = (Get-Date -Format o)
    RootPath      = (Resolve-Path -LiteralPath $rootItem.FullName -ErrorAction Stop).Path
    Counts        = [pscustomobject]@{
        Total          = $finalEntries.Count
        ValidationRuns = $validationCount
        Pipelines      = $pipelineCount
        EvidenceRecords = $evidenceCount
        Diffs          = $diffCount
        Unknown        = $unknownCount
    }
    Entries       = $finalEntries
}

# LANDMARK: Routing log index - deterministic index emission and latest pointer update
Ensure-Directory -Path $OutputPath
$index | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

if ($UpdateLatest.IsPresent) {
    Ensure-Directory -Path $latestPointerPath
    Copy-Item -LiteralPath $OutputPath -Destination $latestPointerPath -Force
}

if ($PassThru.IsPresent) {
    return $index
}
