[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$BundleName = (Get-Date -Format 'yyyyMMdd-HHmmss'),

    [ValidateNotNullOrEmpty()]
    [string]$OutputRoot = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Logs/TelemetryBundles'),

    [switch]$AllowCustomOutputRoot,

    [string]$AreaName,

    [string[]]$ColdTelemetryPath,
    [string[]]$WarmTelemetryPath,
    [string[]]$AnalyzerPath,
    [string[]]$DiffHotspotsPath,
    [string[]]$UserActionSummaryPath,
    [string[]]$FreshnessSummaryPath,
    [string[]]$RollupPath,
    [string[]]$DocSyncPath,
    [string[]]$QueueSummaryPath,
    [string[]]$AdditionalPath,

    [string[]]$PlanReferences,
    [string[]]$TaskBoardIds,
    # LANDMARK: Telemetry bundle manifest - capture risk register references
    [string[]]$RiskRegisterEntries,
    [string]$Notes,

    [switch]$Force,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $BundleName) {
    throw 'BundleName cannot be empty.'
}

# LANDMARK: Telemetry bundle output guard - ensure bundles live under Logs/TelemetryBundles
$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$canonicalRoot = Join-Path -Path $repoRoot -ChildPath 'Logs/TelemetryBundles'
$resolvedOutputRoot = if ([System.IO.Path]::IsPathRooted($OutputRoot)) {
    [System.IO.Path]::GetFullPath($OutputRoot)
} else {
    [System.IO.Path]::GetFullPath((Join-Path -Path $repoRoot -ChildPath $OutputRoot))
}
$resolvedCanonicalRoot = [System.IO.Path]::GetFullPath($canonicalRoot)
$normalizedOutputRoot = $resolvedOutputRoot.TrimEnd('\')
$normalizedCanonicalRoot = $resolvedCanonicalRoot.TrimEnd('\')
$allowedPrefix = '{0}\\' -f $normalizedCanonicalRoot
$isUnderCanonical = $normalizedOutputRoot.Equals($normalizedCanonicalRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
    $normalizedOutputRoot.StartsWith($allowedPrefix, [System.StringComparison]::OrdinalIgnoreCase)
if (-not $AllowCustomOutputRoot -and -not $isUnderCanonical) {
    throw ("OutputRoot '{0}' must be under '{1}' unless -AllowCustomOutputRoot is specified." -f $resolvedOutputRoot, $resolvedCanonicalRoot)
}

$OutputRoot = $resolvedOutputRoot

$allArtifacts = @()
$allArtifacts += $ColdTelemetryPath
$allArtifacts += $WarmTelemetryPath
$allArtifacts += $AnalyzerPath
$allArtifacts += $DiffHotspotsPath
$allArtifacts += $UserActionSummaryPath
$allArtifacts += $FreshnessSummaryPath
$allArtifacts += $RollupPath
$allArtifacts += $DocSyncPath
$allArtifacts += $QueueSummaryPath
$allArtifacts += $AdditionalPath

if (-not $allArtifacts -or $allArtifacts.Count -eq 0) {
    throw 'Provide at least one artifact path (cold telemetry, warm telemetry, analyzer output, etc.).'
}

if (-not (Test-Path -LiteralPath $OutputRoot)) {
    $null = New-Item -ItemType Directory -Path $OutputRoot -Force
}

$bundleRoot = Join-Path -Path $OutputRoot -ChildPath $BundleName
if (Test-Path -LiteralPath $bundleRoot) {
    if (-not $Force) {
        throw "Bundle '$BundleName' already exists under '$OutputRoot'. Use -Force to add another area or overwrite."
    }
} else {
    $null = New-Item -ItemType Directory -Path $bundleRoot -Force
}

$bundleDir = $bundleRoot
if ($AreaName) {
    $bundleDir = Join-Path -Path $bundleRoot -ChildPath $AreaName
    if (-not (Test-Path -LiteralPath $bundleDir)) {
        $null = New-Item -ItemType Directory -Path $bundleDir -Force
    }
}

function Get-UniqueFileName {
    param(
        [Parameter(Mandatory = $true)][string]$BaseDirectory,
        [Parameter(Mandatory = $true)][string]$FileName
    )

    $target = $FileName
    $counter = 1
    while (Test-Path -LiteralPath (Join-Path -Path $BaseDirectory -ChildPath $target)) {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
        $ext = [System.IO.Path]::GetExtension($FileName)
        $target = "{0}-{1}{2}" -f $name, $counter, $ext
        $counter++
    }

    return $target
}

$artifactEntries = @()
$categories = @(
    @{ Name = 'ColdTelemetry'; Paths = $ColdTelemetryPath },
    @{ Name = 'WarmTelemetry'; Paths = $WarmTelemetryPath },
    @{ Name = 'SharedCacheAnalyzer'; Paths = $AnalyzerPath },
    @{ Name = 'DiffHotspots'; Paths = $DiffHotspotsPath },
    @{ Name = 'UserActionSummary'; Paths = $UserActionSummaryPath },
    @{ Name = 'FreshnessSummary'; Paths = $FreshnessSummaryPath },
    @{ Name = 'RollupCsv'; Paths = $RollupPath },
    @{ Name = 'DocSync'; Paths = $DocSyncPath },
    @{ Name = 'QueueDelaySummary'; Paths = $QueueSummaryPath },
    @{ Name = 'Additional'; Paths = $AdditionalPath }
)

foreach ($category in $categories) {
    if (-not $category.Paths) { continue }

    foreach ($path in $category.Paths) {
        if (-not $path) { continue }
        $resolved = Resolve-Path -LiteralPath $path -ErrorAction Stop
        $sourcePath = $resolved.Path
        $fileName = Split-Path -Path $sourcePath -Leaf
        $targetName = Get-UniqueFileName -BaseDirectory $bundleDir -FileName $fileName
        $destination = Join-Path -Path $bundleDir -ChildPath $targetName
        Copy-Item -LiteralPath $sourcePath -Destination $destination -Force
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash
        $sizeBytes = (Get-Item -LiteralPath $destination).Length

        $artifactEntries += [pscustomobject]@{
            Category = $category.Name
            TargetFile = $targetName
            SourcePath = $sourcePath
            Hash = $hash
            SizeBytes = $sizeBytes
        }
    }
}

if ($artifactEntries.Count -eq 0) {
    throw 'No artifacts were copied; verify the supplied paths.'
}

$createdAt = Get-Date
$manifest = [ordered]@{
    BundleName = $BundleName
    AreaName = if ($AreaName) { $AreaName } else { 'Telemetry' }
    CreatedAt = $createdAt.ToString('o')
    Hostname = $env:COMPUTERNAME
    OutputRoot = $bundleRoot
    BundlePath = $bundleDir
    PlanReferences = $PlanReferences
    TaskBoardIds = $TaskBoardIds
    RiskRegisterEntries = $RiskRegisterEntries
    Notes = $Notes
    Artifacts = $artifactEntries
}

$manifestPath = Join-Path -Path $bundleDir -ChildPath 'TelemetryBundle.json'
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

$readmeLines = @()
$readmeLines += "# Telemetry Bundle - $($manifest.BundleName)"
if ($AreaName) { $readmeLines += "**Area:** $AreaName" }
$readmeLines += "- Created: $($manifest.CreatedAt)"
$readmeLines += "- Host: $($manifest.Hostname)"
if ($PlanReferences) { $readmeLines += "- Plans: $([string]::Join(', ', $PlanReferences))" }
if ($TaskBoardIds) { $readmeLines += "- Task Board IDs: $([string]::Join(', ', $TaskBoardIds))" }
# LANDMARK: Telemetry bundle README - include risk register references when supplied
if ($RiskRegisterEntries) { $readmeLines += "- Risk Register: $([string]::Join(', ', $RiskRegisterEntries))" }
if ($Notes) { $readmeLines += "- Notes: $Notes" }
$readmeLines += ''
$readmeLines += '## Artifacts'
$readmeLines += '| Category | File | Source | Hash |'
$readmeLines += '|----------|------|--------|------|'
foreach ($entry in $artifactEntries) {
    $hashPreview = if ($entry.Hash) { $entry.Hash.Substring(0, [Math]::Min(12, $entry.Hash.Length)) } else { '' }
    $readmeLines += "| $($entry.Category) | $($entry.TargetFile) | $($entry.SourcePath) | $hashPreview |"
}
$readmeContent = [string]::Join([Environment]::NewLine, $readmeLines)
$readmePath = Join-Path -Path $bundleDir -ChildPath 'README.md'
Set-Content -LiteralPath $readmePath -Value $readmeContent -Encoding UTF8

if ($PassThru) {
    return [pscustomobject]@{
        BundleName = $BundleName
        AreaName = $AreaName
        Path = $bundleDir
        Manifest = $manifestPath
        Artifacts = $artifactEntries
    }
}
