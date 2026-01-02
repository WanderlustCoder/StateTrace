[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SummaryPath,
    [Parameter(Mandatory = $true)]
    [string]$OutputZipPath,
    [string]$RootPath,
    [switch]$IncludeReferencedArtifacts = $true,
    [switch]$AllowMissingArtifacts,
    [switch]$PassThru,
    [switch]$UpdateLatest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$latestPointerPath = Join-Path -Path $repoRoot -ChildPath 'Logs/Reports/RoutingBundles/RoutingBundle-latest.json'

function Ensure-Directory {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $directory = Split-Path -Parent $Path
    if ([string]::IsNullOrWhiteSpace($directory)) { return }
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
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
    if ($Value -match '^[a-zA-Z]+://') { return $false }
    if ($Value -match '[\\/]' -or $Value -match '\.(json|md|txt|log|csv|zip)$') {
        return $true
    }
    return $false
}

function Test-TokenMatch {
    param(
        [string]$Name,
        [string[]]$Tokens
    )
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    foreach ($token in $Tokens) {
        if ($Name.IndexOf($token, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
        }
    }
    return $false
}

function Collect-PathsByToken {
    param(
        [object]$Object,
        [string[]]$Tokens,
        [System.Collections.Generic.List[string]]$Collector,
        [System.Collections.Generic.HashSet[int]]$Visited
    )
    if ($null -eq $Object) { return }
    if ($Object -is [string] -or $Object -is [ValueType]) { return }

    if (-not $Visited) {
        $Visited = New-Object System.Collections.Generic.HashSet[int]
    }
    $objectId = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Object)
    if ($Visited.Contains($objectId)) { return }
    $Visited.Add($objectId) | Out-Null

    if ($Object -is [System.Collections.IDictionary]) {
        foreach ($key in $Object.Keys) {
            $value = $Object[$key]
            if ((Test-TokenMatch -Name $key -Tokens $Tokens) -and $value -is [string] -and (Test-PathLike -Value $value)) {
                $Collector.Add($value) | Out-Null
            }
            Collect-PathsByToken -Object $value -Tokens $Tokens -Collector $Collector -Visited $Visited
        }
        return
    }

    if ($Object -is [System.Array]) {
        foreach ($item in $Object) {
            Collect-PathsByToken -Object $item -Tokens $Tokens -Collector $Collector -Visited $Visited
        }
        return
    }

    foreach ($prop in $Object.PSObject.Properties) {
        $name = $prop.Name
        $value = $prop.Value
        if ((Test-TokenMatch -Name $name -Tokens $Tokens) -and $value -is [string] -and (Test-PathLike -Value $value)) {
            $Collector.Add($value) | Out-Null
        }
        Collect-PathsByToken -Object $value -Tokens $Tokens -Collector $Collector -Visited $Visited
    }
}

function Resolve-RootPath {
    param(
        [string]$Path,
        [string]$RepoRoot
    )
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path -Path $RepoRoot -ChildPath $Path))
}

function Resolve-CandidatePath {
    param(
        [string]$CandidatePath,
        [string]$Root
    )
    if ([string]::IsNullOrWhiteSpace($CandidatePath)) { return $null }
    if ($CandidatePath -match '^[a-zA-Z]+://') {
        throw "Referenced path '$CandidatePath' is not a local file path."
    }
    if ([System.IO.Path]::IsPathRooted($CandidatePath)) {
        return [System.IO.Path]::GetFullPath($CandidatePath)
    }
    return [System.IO.Path]::GetFullPath((Join-Path -Path $Root -ChildPath $CandidatePath))
}

function Test-UnderRoot {
    param(
        [string]$Root,
        [string]$Path
    )
    $normalizedRoot = $Root.TrimEnd('\')
    $normalizedPath = $Path.TrimEnd('\')
    $prefix = '{0}\' -f $normalizedRoot
    return $normalizedPath.Equals($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        $normalizedPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-RelativePathFromRoot {
    param(
        [string]$Root,
        [string]$Path
    )
    $normalizedRoot = $Root.TrimEnd('\')
    $normalizedPath = $Path.TrimEnd('\')
    $prefix = '{0}\' -f $normalizedRoot
    if ($normalizedPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $normalizedPath.Substring($prefix.Length)
    }
    throw "Path '$Path' is outside root '$Root'."
}

if (-not (Test-Path -LiteralPath $SummaryPath)) {
    throw "SummaryPath '$SummaryPath' was not found."
}
if ([System.IO.Path]::GetExtension($SummaryPath) -ne '.json') {
    throw "SummaryPath '$SummaryPath' must be a JSON file."
}

$summaryLeaf = Split-Path -Path $SummaryPath -Leaf
$validSummary = $summaryLeaf -like 'RoutingValidationRunSummary*.json' -or
    $summaryLeaf -like 'RoutingDiscoveryPipelineSummary*.json' -or
    $summaryLeaf -like 'RoutingDiff-*.json'
if (-not $validSummary) {
    throw ("SummaryPath '{0}' must be a routing summary or diff JSON (RoutingValidationRunSummary*.json, RoutingDiscoveryPipelineSummary*.json, RoutingDiff-*.json)." -f $SummaryPath)
}

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    $RootPath = $repoRoot
}
$resolvedRoot = Resolve-RootPath -Path $RootPath -RepoRoot $repoRoot

$summaryPayload = Read-JsonFile -Path $SummaryPath -Label 'Summary'

$pathTokens = @(
    'Path',
    'Log',
    'Summary',
    'Snapshot',
    'RouteRecords',
    'RouteHealthSnapshot',
    'Diff',
    'Artifacts'
)

# LANDMARK: Routing bundle export - discover artifact paths safely and deterministically
$pathCandidates = New-Object System.Collections.Generic.List[string]
$pathCandidates.Add($SummaryPath) | Out-Null
if ($IncludeReferencedArtifacts) {
    Collect-PathsByToken -Object $summaryPayload -Tokens $pathTokens -Collector $pathCandidates
}

# LANDMARK: Routing bundle export - root path enforcement and missing artifact handling
$included = New-Object System.Collections.Generic.List[object]
$missing = New-Object System.Collections.Generic.List[object]
$warnings = New-Object System.Collections.Generic.List[string]
$seen = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)

foreach ($candidate in $pathCandidates) {
    if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
    $resolved = Resolve-CandidatePath -CandidatePath $candidate -Root $resolvedRoot
    if (-not (Test-UnderRoot -Root $resolvedRoot -Path $resolved)) {
        throw "Referenced path '$candidate' resolves outside root '$resolvedRoot'."
    }
    if (-not $seen.Add($resolved)) { continue }
    if (-not (Test-Path -LiteralPath $resolved)) {
        $missingEntry = [ordered]@{
            SourcePath = $resolved
            Reason     = 'NotFound'
        }
        $missing.Add($missingEntry) | Out-Null
        $warnings.Add("Referenced path '$resolved' was not found.") | Out-Null
        if (-not $AllowMissingArtifacts.IsPresent) {
            throw "Referenced path '$resolved' was not found. Use -AllowMissingArtifacts to continue."
        }
        continue
    }
    $relative = Get-RelativePathFromRoot -Root $resolvedRoot -Path $resolved
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolved).Hash
    $sizeBytes = (Get-Item -LiteralPath $resolved).Length
    $included.Add([ordered]@{
        RelativePath = $relative
        SourcePath   = $resolved
        Sha256       = $hash
        Bytes        = $sizeBytes
    }) | Out-Null
}

$sortedIncluded = @($included | Sort-Object RelativePath)
$sortedMissing = @($missing | Sort-Object SourcePath)
$warningsArray = @($warnings)

$resolvedOutputZipPath = if ([System.IO.Path]::IsPathRooted($OutputZipPath)) {
    [System.IO.Path]::GetFullPath($OutputZipPath)
} else {
    [System.IO.Path]::GetFullPath((Join-Path -Path $repoRoot -ChildPath $OutputZipPath))
}

$stagingRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("RoutingBundle-{0}" -f [Guid]::NewGuid().ToString('N'))
try {
    if (-not (Test-Path -LiteralPath $stagingRoot)) {
        New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null
    }

    foreach ($entry in $sortedIncluded) {
        $destination = Join-Path -Path $stagingRoot -ChildPath $entry.RelativePath
        Ensure-Directory -Path $destination
        Copy-Item -LiteralPath $entry.SourcePath -Destination $destination -Force
    }

    $manifest = [ordered]@{
        SchemaVersion = '1.0'
        GeneratedAt   = (Get-Date -Format o)
        RootPath      = $resolvedRoot
        SummaryPath   = (Resolve-CandidatePath -CandidatePath $SummaryPath -Root $resolvedRoot)
        OutputZipPath = $resolvedOutputZipPath
        IncludedFiles = $sortedIncluded
        MissingFiles  = $sortedMissing
        Warnings      = $warningsArray
    }
    $manifestPath = Join-Path -Path $stagingRoot -ChildPath 'BundleManifest.json'
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    # LANDMARK: Routing bundle export - manifest hashing and zip packaging with latest pointer
    Ensure-Directory -Path $resolvedOutputZipPath
    Compress-Archive -Path (Join-Path -Path $stagingRoot -ChildPath '*') -DestinationPath $resolvedOutputZipPath -Force
} finally {
    if (Test-Path -LiteralPath $stagingRoot) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$exportSummaryPath = [System.IO.Path]::ChangeExtension($resolvedOutputZipPath, '.json')
$exportSummary = [ordered]@{
    SchemaVersion   = '1.0'
    GeneratedAt     = (Get-Date -Format o)
    SummaryPath     = (Resolve-CandidatePath -CandidatePath $SummaryPath -Root $resolvedRoot)
    RootPath        = $resolvedRoot
    OutputZipPath   = $resolvedOutputZipPath
    ManifestPath    = 'BundleManifest.json'
    IncludedCount   = $sortedIncluded.Count
    MissingCount    = $sortedMissing.Count
    Warnings        = $warningsArray
}

$exportSummary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $exportSummaryPath -Encoding UTF8

if ($UpdateLatest.IsPresent) {
    Ensure-Directory -Path $latestPointerPath
    Copy-Item -LiteralPath $exportSummaryPath -Destination $latestPointerPath -Force
}

if ($PassThru.IsPresent) {
    return $exportSummary
}
