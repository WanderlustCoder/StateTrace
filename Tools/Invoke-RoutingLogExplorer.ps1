[CmdletBinding()]
param(
    [string]$RootPath = 'Logs/Reports',
    [string]$IndexPath,
    [switch]$RebuildIndex,
    [switch]$UseLatestPointers = $true,
    [ValidateSet('RoutingValidationRun','RoutingDiscoveryPipeline','RoutingRealDeviceEvidence','RoutingDiff','Unknown')]
    [string]$Type,
    [string]$Status,
    [string]$Site,
    [string]$Hostname,
    [string]$Vendor,
    [string]$Vrf,
    [int]$Top = 20,
    [switch]$ListOnly,
    [switch]$Latest,
    [int]$Select,
    [string]$Path,
    [switch]$CompareWithPrevious,
    [switch]$CompareLatestTwo,
    [ValidateSet('SameType','AnyType')]
    [string]$CompareScope = 'SameType',
    [string]$DiffOutputPath,
    [string]$DiffMarkdownPath,
    [switch]$DiffUpdateLatest,
    [switch]$ExportBundle,
    [string]$BundleZipPath,
    [switch]$BundleUpdateLatest,
    [switch]$BundleAllowMissingArtifacts,
    [switch]$BundleIncludeReferencedArtifacts = $true,
    [switch]$ExportDiffBundle,
    [string]$DiffBundleZipPath,
    [ValidateSet('Console','Markdown')]
    [string]$Format = 'Console',
    [string]$OutputPath,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$summaryToolPath = Join-Path -Path $PSScriptRoot -ChildPath 'Show-RoutingLogSummary.ps1'
$indexToolPath = Join-Path -Path $PSScriptRoot -ChildPath 'Build-RoutingLogIndex.ps1'
$diffToolPath = Join-Path -Path $PSScriptRoot -ChildPath 'Compare-RouteHealthSnapshots.ps1'
$bundleToolPath = Join-Path -Path $PSScriptRoot -ChildPath 'Export-RoutingOfflineBundle.ps1'
$latestIndexPath = Join-Path -Path $repoRoot -ChildPath 'Logs/Reports/RoutingLogIndex/RoutingLogIndex-latest.json'

function Ensure-Directory {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Convert-ToExplorerType {
    param([string]$InputType)
    switch ($InputType) {
        'RoutingValidationRunSummary' { return 'RoutingValidationRun' }
        'RoutingDiscoveryPipelineSummary' { return 'RoutingDiscoveryPipeline' }
        'RoutingRealDeviceEvidence' { return 'RoutingRealDeviceEvidence' }
        'RoutingDiff' { return 'RoutingDiff' }
        'Unknown' { return 'Unknown' }
        default { return $InputType }
    }
}

function Get-SortTimestamp {
    param([string]$Timestamp)
    $parsed = [datetime]::MinValue
    if ([datetime]::TryParse([string]$Timestamp, [ref]$parsed)) {
        return $parsed
    }
    return [datetime]::MinValue
}

function Get-ShortPath {
    param(
        [string]$Path,
        [int]$MaxLength = 120
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    if ($Path.Length -le $MaxLength) { return $Path }
    $suffixLength = [Math]::Max(1, $MaxLength - 3)
    return ('...' + $Path.Substring($Path.Length - $suffixLength))
}

function Resolve-EntryPath {
    param(
        [string]$EntryPath,
        [string]$RepoRoot
    )
    if ([string]::IsNullOrWhiteSpace($EntryPath)) { return $EntryPath }
    if ([System.IO.Path]::IsPathRooted($EntryPath)) { return $EntryPath }
    return (Join-Path -Path $RepoRoot -ChildPath $EntryPath)
}

function Test-UnderRoot {
    param(
        [string]$Root,
        [string]$Path
    )
    $normalizedRoot = ([System.IO.Path]::GetFullPath($Root)).TrimEnd('\')
    $normalizedPath = ([System.IO.Path]::GetFullPath($Path)).TrimEnd('\')
    $prefix = '{0}\' -f $normalizedRoot
    return $normalizedPath.Equals($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        $normalizedPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-CommonRoot {
    param(
        [string]$Left,
        [string]$Right
    )
    $leftFull = ([System.IO.Path]::GetFullPath($Left)).TrimEnd('\')
    $rightFull = ([System.IO.Path]::GetFullPath($Right)).TrimEnd('\')
    $leftParts = $leftFull -split '\\'
    $rightParts = $rightFull -split '\\'
    $max = [Math]::Min($leftParts.Count, $rightParts.Count)
    $common = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $max; $i++) {
        if ($leftParts[$i].Equals($rightParts[$i], [System.StringComparison]::OrdinalIgnoreCase)) {
            $common.Add($leftParts[$i]) | Out-Null
        } else {
            break
        }
    }
    if ($common.Count -eq 0) {
        throw "Paths '$Left' and '$Right' do not share a common root."
    }
    $root = ($common -join '\')
    if ($root.EndsWith(':')) {
        $root += '\'
    }
    return $root
}

function Resolve-BundleContext {
    param(
        [string]$SummaryPath,
        [string]$RepoRoot,
        [switch]$PreferRepoRoot
    )
    $resolvedSummary = Resolve-EntryPath -EntryPath $SummaryPath -RepoRoot $RepoRoot
    $resolvedRepoRoot = [System.IO.Path]::GetFullPath($RepoRoot)
    if (Test-UnderRoot -Root $resolvedRepoRoot -Path $resolvedSummary) {
        return [pscustomobject]@{
            SummaryPath = $resolvedSummary
            RootPath    = $resolvedRepoRoot
        }
    }
    if ($PreferRepoRoot.IsPresent) {
        $commonRoot = Get-CommonRoot -Left $resolvedSummary -Right $resolvedRepoRoot
        return [pscustomobject]@{
            SummaryPath = $resolvedSummary
            RootPath    = $commonRoot
        }
    }
    return [pscustomobject]@{
        SummaryPath = $resolvedSummary
        RootPath    = (Split-Path -Parent $resolvedSummary)
    }
}

function Get-DefaultBundleZipPath {
    param(
        [string]$Prefix,
        [string]$RepoRoot,
        [string]$Timestamp
    )
    $stamp = if ([string]::IsNullOrWhiteSpace($Timestamp)) {
        Get-Date -Format 'yyyyMMdd-HHmmss'
    } else {
        $Timestamp
    }
    return (Join-Path -Path $RepoRoot -ChildPath ("Logs/Reports/RoutingBundles/{0}-{1}.zip" -f $Prefix, $stamp))
}

# LANDMARK: Explorer bundle export - invoke Export-RoutingOfflineBundle with defaults and pass-through switches
function Invoke-BundleExport {
    param(
        [string]$SummaryPath,
        [string]$BundleZipPath,
        [string]$RepoRoot,
        [switch]$PreferRepoRoot,
        [string]$BannerLabel
    )
    if (-not (Test-Path -LiteralPath $bundleToolPath)) {
        throw "Routing bundle export tool not found at '$bundleToolPath'."
    }
    $bundleContext = Resolve-BundleContext -SummaryPath $SummaryPath -RepoRoot $RepoRoot -PreferRepoRoot:$PreferRepoRoot
    $bundleParams = @{
        SummaryPath               = $bundleContext.SummaryPath
        OutputZipPath             = $BundleZipPath
        RootPath                  = $bundleContext.RootPath
        IncludeReferencedArtifacts = [bool]$BundleIncludeReferencedArtifacts
        PassThru                  = $true
    }
    if ($BundleAllowMissingArtifacts.IsPresent) {
        $bundleParams['AllowMissingArtifacts'] = $true
    }
    if ($BundleUpdateLatest.IsPresent) {
        $bundleParams['UpdateLatest'] = $true
    }
    $bundleSummary = & $bundleToolPath @bundleParams
    Write-Host "[Routing] Bundle export" -ForegroundColor Cyan
    if ($BannerLabel) {
        Write-Host ("  {0}: {1}" -f $BannerLabel, $bundleContext.SummaryPath)
    } else {
        Write-Host ("  Summary: {0}" -f $bundleContext.SummaryPath)
    }
    Write-Host ("  Zip: {0}" -f $BundleZipPath)
    if ($bundleSummary) {
        Write-Host ("  Included: {0}; Missing: {1}" -f $bundleSummary.IncludedCount, $bundleSummary.MissingCount)
    }
    return $bundleSummary
}

function Get-FilterSummary {
    param(
        [string]$Type,
        [string]$Status,
        [string]$Site,
        [string]$Hostname,
        [string]$Vendor,
        [string]$Vrf
    )
    $parts = New-Object System.Collections.Generic.List[string]
    if ($Type) { $parts.Add("Type=$Type") }
    if ($Status) { $parts.Add("Status=$Status") }
    if ($Site) { $parts.Add("Site=$Site") }
    if ($Hostname) { $parts.Add("Hostname=$Hostname") }
    if ($Vendor) { $parts.Add("Vendor=$Vendor") }
    if ($Vrf) { $parts.Add("Vrf=$Vrf") }
    if ($parts.Count -eq 0) { return 'None' }
    return ($parts -join '; ')
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

function Test-PathLike {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    if ($Value -match '[\\/]' -or $Value -match '\.json$' -or $Value -match '\.md$') {
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

function Resolve-TargetIdentityFromSummary {
    param([object]$Summary)
    $site = Get-StringProperty -Object $Summary -Name 'Site'
    $hostname = Get-StringProperty -Object $Summary -Name 'Hostname'
    $vrf = Get-StringProperty -Object $Summary -Name 'Vrf'
    $captureMetadata = Get-OptionalProperty -Object $Summary -Name 'CaptureMetadata'
    if ($captureMetadata) {
        if (-not $site) { $site = Get-StringProperty -Object $captureMetadata -Name 'Site' }
        if (-not $hostname) { $hostname = Get-StringProperty -Object $captureMetadata -Name 'Hostname' }
        if (-not $vrf) { $vrf = Get-StringProperty -Object $captureMetadata -Name 'Vrf' }
    }
    $hostSummaries = Get-OptionalProperty -Object $Summary -Name 'HostSummaries'
    if (-not $hostname -and $hostSummaries) {
        $hosts = @($hostSummaries)
        if ($hosts.Count -eq 1) {
            $hostname = Get-StringProperty -Object $hosts[0] -Name 'Hostname'
        }
    }
    return [pscustomobject]@{
        Site     = $site
        Hostname = $hostname
        Vrf      = $vrf
    }
}

function Resolve-TargetIdentity {
    param(
        [object]$Entry,
        [object]$Summary,
        [string]$EntryPath,
        [switch]$RequireComplete
    )
    $site = $Entry.Site
    $hostname = $Entry.Hostname
    $vrf = $Entry.Vrf
    if (-not $site -or -not $hostname -or -not $vrf) {
        if (-not $Summary) {
            $Summary = Read-JsonFile -Path $EntryPath -Label 'Routing summary'
        }
        $summaryTarget = Resolve-TargetIdentityFromSummary -Summary $Summary
        if (-not $site) { $site = $summaryTarget.Site }
        if (-not $hostname) { $hostname = $summaryTarget.Hostname }
        if (-not $vrf) { $vrf = $summaryTarget.Vrf }
    }
    if ($RequireComplete.IsPresent) {
        if ([string]::IsNullOrWhiteSpace($site) -or
            [string]::IsNullOrWhiteSpace($hostname) -or
            [string]::IsNullOrWhiteSpace($vrf)) {
            throw ("Unable to resolve target identity for entry '{0}'. Site='{1}' Hostname='{2}' Vrf='{3}'. Use -Path to bypass index." -f $EntryPath, $site, $hostname, $vrf)
        }
    }
    return [pscustomobject]@{
        Site     = $site
        Hostname = $hostname
        Vrf      = $vrf
        Summary  = $Summary
    }
}

function Test-TargetMatch {
    param(
        [object]$Left,
        [object]$Right
    )
    return ($Left.Site -eq $Right.Site -and $Left.Hostname -eq $Right.Hostname -and $Left.Vrf -eq $Right.Vrf)
}

function Resolve-ArtifactPaths {
    param(
        [object]$Summary,
        [string]$EntryPath,
        [string]$RepoRoot
    )
    $routeHealthPath = $null
    $routeRecordsPath = $null

    $routeHealthPath = Get-StringProperty -Object $Summary -Name 'RouteHealthSnapshotPath'
    $artifactPaths = Get-OptionalProperty -Object $Summary -Name 'ArtifactPaths'
    if (-not $routeHealthPath -and $artifactPaths) {
        $routeHealthPath = Get-StringProperty -Object $artifactPaths -Name 'RouteHealthSnapshotPath'
    }
    $routeHealthSnapshot = Get-OptionalProperty -Object $Summary -Name 'RouteHealthSnapshot'
    if (-not $routeHealthPath -and $routeHealthSnapshot) {
        $routeHealthPath = Get-StringProperty -Object $routeHealthSnapshot -Name 'RouteHealthSnapshotPath'
        if (-not $routeHealthPath) {
            $routeHealthPath = Get-StringProperty -Object $routeHealthSnapshot -Name 'Path'
        }
    }

    $routeRecordsPath = Get-StringProperty -Object $Summary -Name 'RouteRecordsPath'
    if (-not $routeRecordsPath -and $artifactPaths) {
        $routeRecordsPath = Get-StringProperty -Object $artifactPaths -Name 'RouteRecordsPath'
    }
    $routeRecords = Get-OptionalProperty -Object $Summary -Name 'RouteRecords'
    if (-not $routeRecordsPath -and $routeRecords) {
        $routeRecordsPath = Get-StringProperty -Object $routeRecords -Name 'RouteRecordsPath'
        if (-not $routeRecordsPath) {
            $routeRecordsPath = Get-StringProperty -Object $routeRecords -Name 'Path'
        }
    }

    if (-not $routeHealthPath) {
        $routeHealthPath = Find-PathByPropertyToken -Object $Summary -Token 'RouteHealthSnapshot'
    }
    if (-not $routeRecordsPath) {
        $routeRecordsPath = Find-PathByPropertyToken -Object $Summary -Token 'RouteRecords'
    }

    if ([string]::IsNullOrWhiteSpace($routeHealthPath)) {
        throw "Entry '$EntryPath' is missing RouteHealthSnapshotPath. Ensure the summary includes a RouteHealthSnapshot path or use -Path to bypass index."
    }

    $resolvedHealth = Resolve-EntryPath -EntryPath $routeHealthPath -RepoRoot $RepoRoot
    $resolvedRecords = if ($routeRecordsPath) {
        Resolve-EntryPath -EntryPath $routeRecordsPath -RepoRoot $RepoRoot
    } else {
        $null
    }

    return [pscustomobject]@{
        RouteHealthSnapshotPath = $resolvedHealth
        RouteRecordsPath        = $resolvedRecords
    }
}

$selectProvided = $PSBoundParameters.ContainsKey('Select')
$latestRequested = $Latest.IsPresent -or $CompareLatestTwo.IsPresent
$compareRequested = $CompareWithPrevious.IsPresent -or $CompareLatestTwo.IsPresent
$exportBundleRequested = $ExportBundle.IsPresent
$exportDiffBundleRequested = $ExportDiffBundle.IsPresent

# LANDMARK: Explorer ergonomics - Latest selection semantics and mutual exclusivity validation
if ($selectProvided -and $latestRequested) {
    throw "Select cannot be combined with -Latest or -CompareLatestTwo. Choose one selection method."
}
if ($CompareWithPrevious.IsPresent -and $CompareLatestTwo.IsPresent) {
    throw "CompareLatestTwo cannot be combined with CompareWithPrevious. Choose one compare mode."
}
if ($Latest.IsPresent -and $ListOnly.IsPresent) {
    throw "Latest cannot be used with -ListOnly. Remove -ListOnly to render the newest entry."
}
if ($CompareLatestTwo.IsPresent -and $ListOnly.IsPresent) {
    throw "CompareLatestTwo cannot be used with -ListOnly. Remove -ListOnly to run the comparison."
}
if ($exportBundleRequested -and $ListOnly.IsPresent) {
    throw "ExportBundle cannot be used with -ListOnly. Remove -ListOnly to export a selected summary."
}
if ($exportDiffBundleRequested -and $ListOnly.IsPresent) {
    throw "ExportDiffBundle cannot be used with -ListOnly. Remove -ListOnly to run the comparison."
}
if ($exportDiffBundleRequested -and -not $compareRequested) {
    throw "ExportDiffBundle requires compare mode. Use -CompareWithPrevious or -CompareLatestTwo."
}

if (-not [string]::IsNullOrWhiteSpace($Path)) {
    if ($compareRequested -or $latestRequested) {
        throw "Path cannot be combined with compare or latest selection switches. Remove -Path to use -CompareWithPrevious/-CompareLatestTwo/-Latest."
    }
    if (-not (Test-Path -LiteralPath $summaryToolPath)) {
        throw "Routing log summary tool not found at '$summaryToolPath'."
    }
    if ($Format -eq 'Markdown' -and [string]::IsNullOrWhiteSpace($OutputPath)) {
        throw "OutputPath is required when Format is 'Markdown'."
    }
    # LANDMARK: Explorer bundle export - resolve selected summary path across Path/Select/Latest flows
    $selectedSummaryPath = Resolve-EntryPath -EntryPath $Path -RepoRoot $repoRoot
    $summaryParams = @{
        Path = $selectedSummaryPath
        Format = $Format
        PassThru = $PassThru.IsPresent
    }
    if ($Format -eq 'Markdown') {
        $summaryParams['OutputPath'] = $OutputPath
    }
    $summary = & $summaryToolPath @summaryParams
    if ($exportBundleRequested) {
        if ([string]::IsNullOrWhiteSpace($BundleZipPath)) {
            $BundleZipPath = Get-DefaultBundleZipPath -Prefix 'RoutingBundle-Explorer' -RepoRoot $repoRoot
        }
        Invoke-BundleExport -SummaryPath $selectedSummaryPath -BundleZipPath $BundleZipPath -RepoRoot $repoRoot -BannerLabel 'Summary' | Out-Null
    }
    if ($PassThru.IsPresent) {
        return $summary
    }
    return
}

if ($CompareWithPrevious.IsPresent -and -not $selectProvided) {
    throw "CompareWithPrevious requires -Select. Use -CompareLatestTwo to auto-select the newest entry."
}

if (($selectProvided -or $latestRequested) -and $Format -eq 'Markdown' -and [string]::IsNullOrWhiteSpace($OutputPath)) {
    throw "OutputPath is required when Format is 'Markdown'."
}

# LANDMARK: Routing log explorer - load/build index and apply stable filtering/sorting
$indexObject = $null
$resolvedIndexPath = $null
if ($RebuildIndex.IsPresent) {
    if (-not (Test-Path -LiteralPath $indexToolPath)) {
        throw "Routing log index tool not found at '$indexToolPath'."
    }
    if ([string]::IsNullOrWhiteSpace($IndexPath)) {
        $IndexPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("RoutingLogIndex-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    }
    $indexObject = & $indexToolPath -RootPath $RootPath -OutputPath $IndexPath -Recurse -UseLatestPointers:$UseLatestPointers -PassThru
    $resolvedIndexPath = $IndexPath
} else {
    if (-not [string]::IsNullOrWhiteSpace($IndexPath)) {
        if (-not (Test-Path -LiteralPath $IndexPath)) {
            throw "IndexPath '$IndexPath' was not found."
        }
        $resolvedIndexPath = $IndexPath
    } elseif (Test-Path -LiteralPath $latestIndexPath) {
        $resolvedIndexPath = $latestIndexPath
    } else {
        if (-not (Test-Path -LiteralPath $indexToolPath)) {
            throw "Routing log index tool not found at '$indexToolPath'."
        }
        $IndexPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("RoutingLogIndex-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        $indexObject = & $indexToolPath -RootPath $RootPath -OutputPath $IndexPath -Recurse -UseLatestPointers:$UseLatestPointers -PassThru
        $resolvedIndexPath = $IndexPath
    }
}

if (-not $indexObject) {
    $indexObject = Get-Content -LiteralPath $resolvedIndexPath -Raw | ConvertFrom-Json -ErrorAction Stop
}
if (-not $indexObject.Entries) {
    throw "Index '$resolvedIndexPath' does not contain Entries."
}

$sequence = 0
$entries = foreach ($entry in $indexObject.Entries) {
    $mappedType = Convert-ToExplorerType -InputType $entry.Type
    [pscustomobject]@{
        Sequence      = $sequence
        Type          = $mappedType
        Timestamp     = $entry.Timestamp
        Status        = $entry.Status
        Site          = $entry.Site
        Vendor        = $entry.Vendor
        Vrf           = $entry.Vrf
        Hostname      = Get-OptionalProperty -Object $entry -Name 'Hostname'
        Path          = Resolve-EntryPath -EntryPath $entry.Path -RepoRoot $repoRoot
        SortTimestamp = Get-SortTimestamp -Timestamp $entry.Timestamp
    }
    $sequence++
}

if ($Type) { $entries = $entries | Where-Object { $_.Type -eq $Type } }
if ($Status) { $entries = $entries | Where-Object { $_.Status -eq $Status } }
if ($Site) { $entries = $entries | Where-Object { $_.Site -eq $Site } }
# LANDMARK: Explorer ergonomics - Hostname filter and stable case-insensitive matching
if ($Hostname) {
    $entries = $entries | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Hostname) -and $_.Hostname -ieq $Hostname }
}
if ($Vendor) { $entries = $entries | Where-Object { $_.Vendor -eq $Vendor } }
if ($Vrf) { $entries = $entries | Where-Object { $_.Vrf -eq $Vrf } }

$entries = $entries | Sort-Object @{Expression = 'SortTimestamp'; Descending = $true}, @{Expression = 'Path'; Descending = $false}, @{Expression = 'Sequence'; Descending = $false}

$selectionIndex = $null
if ($selectProvided) {
    $selectionIndex = $Select
} elseif ($latestRequested) {
    $selectionIndex = 0
}

if ($null -eq $selectionIndex) {
    # LANDMARK: Routing log explorer - list projection and deterministic selection semantics
    $listEntries = if ($Top -gt 0) { $entries | Select-Object -First $Top } else { @() }
    $listRows = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $listEntries.Count; $i++) {
        $item = $listEntries[$i]
        $listRows.Add([pscustomobject]@{
            Index     = $i
            Timestamp = $item.Timestamp
            Type      = $item.Type
            Status    = $item.Status
            Site      = $item.Site
            Vendor    = $item.Vendor
            Vrf       = $item.Vrf
            Path      = $item.Path
        })
    }
    if ($listRows.Count -gt 0) {
        $listRows | Select-Object Index, Timestamp, Type, Status, Site, Vendor, Vrf, @{Name = 'Path'; Expression = { Get-ShortPath -Path $_.Path }} | Format-Table -AutoSize | Out-String | Write-Host
    } else {
        Write-Host 'No routing summaries matched the supplied filters.'
    }
    if ($PassThru.IsPresent) {
        return $listRows
    }
    return
}

if (-not $entries -or $entries.Count -eq 0) {
    throw 'No routing summaries matched the supplied filters.'
}

if ($selectionIndex -lt 0 -or $selectionIndex -ge $entries.Count) {
    throw ("Select index {0} is out of range. Valid range: 0..{1}. Use -ListOnly to review matching entries." -f $selectionIndex, ($entries.Count - 1))
}

$selectedEntry = $entries[$selectionIndex]
if (-not (Test-Path -LiteralPath $selectedEntry.Path)) {
    throw "Selected summary path '$($selectedEntry.Path)' was not found."
}
# LANDMARK: Explorer bundle export - resolve selected summary path across Path/Select/Latest flows
$selectedSummaryPath = $selectedEntry.Path

# LANDMARK: Explorer compare mode - resolve previous entry by target identity and stable timestamp ordering
$previousEntry = $null
$previousSummaryPayload = $null
$selectedSummaryPayload = $null
$diffResult = $null
$diffTimestamp = $null
if ($compareRequested) {
    if (-not (Test-Path -LiteralPath $diffToolPath)) {
        throw "Routing diff tool not found at '$diffToolPath'."
    }
    # LANDMARK: Explorer ergonomics - CompareLatestTwo uses newest entry then resolves previous by target identity
    $selectedSummaryPayload = Read-JsonFile -Path $selectedEntry.Path -Label 'Selected routing summary'
    $selectedTarget = Resolve-TargetIdentity -Entry $selectedEntry -Summary $selectedSummaryPayload -EntryPath $selectedEntry.Path -RequireComplete

    foreach ($candidate in $entries) {
        if ($candidate.SortTimestamp -ge $selectedEntry.SortTimestamp) { continue }
        if ($CompareScope -eq 'SameType' -and $candidate.Type -ne $selectedEntry.Type) { continue }
        $candidateTarget = Resolve-TargetIdentity -Entry $candidate -Summary $null -EntryPath $candidate.Path
        if (-not [string]::IsNullOrWhiteSpace($candidateTarget.Site) -and
            -not [string]::IsNullOrWhiteSpace($candidateTarget.Hostname) -and
            -not [string]::IsNullOrWhiteSpace($candidateTarget.Vrf) -and
            (Test-TargetMatch -Left $candidateTarget -Right $selectedTarget)) {
            $previousEntry = $candidate
            $previousSummaryPayload = $candidateTarget.Summary
            break
        }
    }

    if (-not $previousEntry) {
        throw ("No previous entry found for target Site='{0}' Hostname='{1}' Vrf='{2}' with CompareScope={3}." -f `
            $selectedTarget.Site, $selectedTarget.Hostname, $selectedTarget.Vrf, $CompareScope)
    }

    if (-not $previousSummaryPayload) {
        $previousSummaryPayload = Read-JsonFile -Path $previousEntry.Path -Label 'Previous routing summary'
    }

    # LANDMARK: Explorer compare mode - extract RouteHealthSnapshot/RouteRecords paths from summaries safely
    $selectedArtifacts = Resolve-ArtifactPaths -Summary $selectedSummaryPayload -EntryPath $selectedEntry.Path -RepoRoot $repoRoot
    $previousArtifacts = Resolve-ArtifactPaths -Summary $previousSummaryPayload -EntryPath $previousEntry.Path -RepoRoot $repoRoot

    if ([string]::IsNullOrWhiteSpace($DiffOutputPath) -or [string]::IsNullOrWhiteSpace($DiffMarkdownPath)) {
        $diffTimestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        if ([string]::IsNullOrWhiteSpace($DiffOutputPath)) {
            $DiffOutputPath = Join-Path -Path $repoRoot -ChildPath ("Logs/Reports/RoutingDiff/RoutingDiff-{0}.json" -f $diffTimestamp)
        }
        if ([string]::IsNullOrWhiteSpace($DiffMarkdownPath)) {
            $DiffMarkdownPath = Join-Path -Path $repoRoot -ChildPath ("Logs/Reports/RoutingDiff/RoutingDiff-{0}.md" -f $diffTimestamp)
        }
    }

    $diffParams = @{
        OldSnapshotPath = $previousArtifacts.RouteHealthSnapshotPath
        NewSnapshotPath = $selectedArtifacts.RouteHealthSnapshotPath
        OutputPath      = $DiffOutputPath
        PassThru        = $true
    }
    if ($previousArtifacts.RouteRecordsPath -and $selectedArtifacts.RouteRecordsPath) {
        $diffParams['OldRouteRecordsPath'] = $previousArtifacts.RouteRecordsPath
        $diffParams['NewRouteRecordsPath'] = $selectedArtifacts.RouteRecordsPath
    }
    if (-not [string]::IsNullOrWhiteSpace($DiffMarkdownPath)) {
        $diffParams['MarkdownPath'] = $DiffMarkdownPath
    }
    if ($DiffUpdateLatest.IsPresent) {
        $diffParams['UpdateLatest'] = $true
    }

    # LANDMARK: Explorer compare mode - invoke Compare-RouteHealthSnapshots and surface diff outputs
    $diffResult = & $diffToolPath @diffParams
    Write-Host "[Routing] Compare diff" -ForegroundColor Cyan
    Write-Host ("  Selected : {0}" -f $selectedEntry.Path)
    Write-Host ("  Previous : {0}" -f $previousEntry.Path)
    Write-Host ("  Diff JSON: {0}" -f $DiffOutputPath)
    if (-not [string]::IsNullOrWhiteSpace($DiffMarkdownPath)) {
        Write-Host ("  Diff MD  : {0}" -f $DiffMarkdownPath)
    }
    if ($diffResult.Changes -and $diffResult.Changes.Health -and $diffResult.Changes.Health.HealthState) {
        $healthChange = $diffResult.Changes.Health.HealthState
        Write-Host ("  HealthState: {0} -> {1}" -f $healthChange.Old, $healthChange.New)
    }

    if ($exportDiffBundleRequested) {
        if ([string]::IsNullOrWhiteSpace($DiffBundleZipPath)) {
            $DiffBundleZipPath = Get-DefaultBundleZipPath -Prefix 'RoutingBundle-Diff' -RepoRoot $repoRoot -Timestamp $diffTimestamp
        }
        # LANDMARK: Explorer bundle export - export diff bundle from generated diff outputs
        Invoke-BundleExport -SummaryPath $DiffOutputPath -BundleZipPath $DiffBundleZipPath -RepoRoot $repoRoot -PreferRepoRoot -BannerLabel 'Diff JSON' | Out-Null
    }
}

# LANDMARK: Routing log explorer - render selected summary via Show-RoutingLogSummary with markdown support
if (-not (Test-Path -LiteralPath $summaryToolPath)) {
    throw "Routing log summary tool not found at '$summaryToolPath'."
}

$summaryResult = $null
if ($Format -eq 'Markdown') {
    Ensure-Directory -Path (Split-Path -Parent $OutputPath)
    $tempPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("RoutingLogExplorerSummary-{0}.md" -f [Guid]::NewGuid().ToString('N'))
    $summary = & $summaryToolPath -Path $selectedEntry.Path -Format Markdown -OutputPath $tempPath -PassThru
    $summaryLines = Get-Content -LiteralPath $tempPath
    Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue

    $reportLines = New-Object System.Collections.Generic.List[string]
    $reportLines.Add('# Routing Log Explorer Report')
    $reportLines.Add('')
    $reportLines.Add(('- GeneratedAt: {0}' -f (Get-Date -Format o)))
    $reportLines.Add(('- RootPath: `{0}`' -f $RootPath))
    $reportLines.Add(('- IndexPath: `{0}`' -f $resolvedIndexPath))
    $reportLines.Add(('- Filters: {0}' -f (Get-FilterSummary -Type $Type -Status $Status -Site $Site -Hostname $Hostname -Vendor $Vendor -Vrf $Vrf)))
    $reportLines.Add('')
    $reportLines.Add('## Selected Entry')
    $reportLines.Add('')
    $reportLines.Add(('- Index: {0}' -f $selectionIndex))
    $reportLines.Add(('- Timestamp: {0}' -f $selectedEntry.Timestamp))
    $reportLines.Add(('- Type: {0}' -f $selectedEntry.Type))
    $reportLines.Add(('- Status: {0}' -f $selectedEntry.Status))
    $reportLines.Add(('- Site: {0}' -f $selectedEntry.Site))
    $reportLines.Add(('- Vendor: {0}' -f $selectedEntry.Vendor))
    $reportLines.Add(('- Vrf: {0}' -f $selectedEntry.Vrf))
    $reportLines.Add(('- Path: `{0}`' -f $selectedEntry.Path))
    $reportLines.Add('')
    foreach ($line in $summaryLines) {
        $reportLines.Add($line)
    }
    $reportLines | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    $summaryResult = $summary
} else {
    $summaryResult = & $summaryToolPath -Path $selectedEntry.Path -Format $Format -PassThru:$PassThru.IsPresent
}
if ($exportBundleRequested) {
    if ([string]::IsNullOrWhiteSpace($BundleZipPath)) {
        $BundleZipPath = Get-DefaultBundleZipPath -Prefix 'RoutingBundle-Explorer' -RepoRoot $repoRoot
    }
    Invoke-BundleExport -SummaryPath $selectedSummaryPath -BundleZipPath $BundleZipPath -RepoRoot $repoRoot -BannerLabel 'Summary' | Out-Null
}
if ($PassThru.IsPresent) {
    return $summaryResult
}
