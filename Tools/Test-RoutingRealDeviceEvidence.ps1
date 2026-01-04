[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$EvidencePath,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,
    [switch]$UpdateLatest,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$latestPointerPath = Join-Path -Path $repoRoot -ChildPath 'Logs/Reports/RoutingRealDeviceEvidence/RoutingRealDeviceEvidence-latest.json'

function Ensure-Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    $directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
}

function Get-SectionLines {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines,
        [Parameter(Mandatory = $true)]
        [string]$SectionName
    )
    $sectionLines = [System.Collections.Generic.List[string]]::new()
    $inSection = $false
    foreach ($line in $Lines) {
        if ($line -match '^\s*##\s*(.+)$') {
            $heading = $Matches[1].Trim()
            $inSection = ($heading -ieq $SectionName)
        if (-not $inSection -and $sectionLines.Count -gt 0) {
            break
        }
        continue
        }
        if ($inSection) {
            [void]$sectionLines.Add($line)
        }
    }
    return ,$sectionLines
}

function Normalize-Value {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )
    $trimmed = $Value.Trim()
    if ($trimmed -match '<.+>') { return $null }
    if ([string]::IsNullOrWhiteSpace($trimmed)) { return $null }
    return $trimmed
}

function Resolve-ArtifactPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )
    $normalized = $Path.Trim().Trim('`', '"', '''')
    if ([string]::IsNullOrWhiteSpace($normalized)) { return $null }
    if ([System.IO.Path]::IsPathRooted($normalized)) {
        return $normalized
    }
    return (Join-Path -Path $RepoRoot -ChildPath $normalized)
}

function Test-IsRoutingValidationSummary {
    param(
        [Parameter(Mandatory = $true)]
        $Object
    )
    if ($null -eq $Object) { return $false }
    $hasStatus = $null -ne $Object.PSObject.Properties['Status']
    $hasMode = $null -ne $Object.PSObject.Properties['Mode']
    $hasHosts = $null -ne $Object.PSObject.Properties['HostSummaries']
    return ($hasStatus -and $hasMode -and $hasHosts)
}

$errors = New-Object System.Collections.Generic.List[string]
$missingSections = New-Object System.Collections.Generic.List[string]
$missingMetadata = New-Object System.Collections.Generic.List[string]
$missingArtifactEntries = New-Object System.Collections.Generic.List[string]
$missingArtifacts = New-Object System.Collections.Generic.List[string]
$foundRunSummaries = New-Object System.Collections.Generic.List[string]
$artifactPaths = [System.Collections.Generic.List[string]]::new()
$commandLines = @()
$metadata = @{
    RunDate  = $null
    Operator = $null
    Site     = $null
    Vendor   = $null
    Vrf      = $null
}

$lines = @()
if (-not (Test-Path -LiteralPath $EvidencePath)) {
    $errors.Add("EvidencePathMissing:$EvidencePath") | Out-Null
} else {
    $lines = Get-Content -LiteralPath $EvidencePath -ErrorAction Stop
}

# LANDMARK: Operator evidence validation - parse required sections and metadata from evidence markdown
$metadataLines = Get-SectionLines -Lines $lines -SectionName 'Metadata'
$commandsLines = Get-SectionLines -Lines $lines -SectionName 'Commands Executed'
$artifactLines = Get-SectionLines -Lines $lines -SectionName 'Evidence Artifacts'

$metadataLines = @($metadataLines)
$commandsLines = @($commandsLines)
$artifactLines = @($artifactLines)

if (@($metadataLines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -eq 0) {
    $missingSections.Add('Metadata') | Out-Null
}
if (@($commandsLines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -eq 0) {
    $missingSections.Add('Commands Executed') | Out-Null
}
if (@($artifactLines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -eq 0) {
    $missingSections.Add('Evidence Artifacts') | Out-Null
}

if (@($metadataLines).Count -gt 0) {
    foreach ($line in $metadataLines) {
        if ($line -match '^\s*[-*]?\s*([^:]+):\s*(.*)$') {
            $key = $Matches[1].Trim()
            $value = Normalize-Value -Value $Matches[2]
            switch -Regex ($key) {
                '^Date/time(\s*\(local\))?$' { if ($value) { $metadata.RunDate = $value } }
                '^Run\s*Date$' { if ($value) { $metadata.RunDate = $value } }
                '^Operator$' { if ($value) { $metadata.Operator = $value } }
                '^Site(\(s\))?$' { if ($value) { $metadata.Site = $value } }
                '^Vendor(\(s\))?$' { if ($value) { $metadata.Vendor = $value } }
                '^VRF(\(s\))?$' { if ($value) { $metadata.Vrf = $value } }
            }
        }
    }
}

foreach ($key in $metadata.Keys) {
    if ([string]::IsNullOrWhiteSpace($metadata[$key])) {
        $missingMetadata.Add($key) | Out-Null
    }
}

if (@($commandsLines).Count -gt 0) {
    $commandLines = $commandsLines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $commandLines = $commandLines | Where-Object { $_ -match 'pwsh|Tools[\\/]' }
    if (@($commandLines).Count -eq 0) {
        $errors.Add('CommandsExecutedMissing:No command lines detected under Commands Executed.') | Out-Null
    }
}

# LANDMARK: Operator evidence validation - validate artifact paths and detect routing validation run summaries
if (@($artifactLines).Count -gt 0) {
    foreach ($line in $artifactLines) {
        if ($line -match '^\s*[-*]\s*(.+)$') {
            $entry = $Matches[1].Trim()
            if ($entry -match ':\s*(.*)$') {
                $candidate = $Matches[1].Trim()
            } else {
                $candidate = $entry
            }
            $normalized = Normalize-Value -Value $candidate
            if ($null -eq $normalized) {
                $missingArtifactEntries.Add($entry) | Out-Null
                continue
            }
            [void]$artifactPaths.Add($normalized)
        }
    }
}

if (@($artifactPaths).Count -eq 0) {
    $errors.Add('EvidenceArtifactsMissing:No artifact paths were found under Evidence Artifacts.') | Out-Null
}

$resolvedArtifactPaths = [System.Collections.Generic.List[string]]::new()
foreach ($path in $artifactPaths) {
    $resolved = Resolve-ArtifactPath -Path $path -RepoRoot $repoRoot
    if ($null -eq $resolved) {
        $missingArtifacts.Add($path) | Out-Null
        continue
    }
    if (-not (Test-Path -LiteralPath $resolved)) {
        $missingArtifacts.Add($resolved) | Out-Null
    } else {
        [void]$resolvedArtifactPaths.Add($resolved)
        if ($resolved -match '\.json$') {
            try {
                $payload = Get-Content -LiteralPath $resolved -Raw | ConvertFrom-Json -ErrorAction Stop
                if (Test-IsRoutingValidationSummary -Object $payload) {
                    $foundRunSummaries.Add($resolved) | Out-Null
                }
            } catch {
                # ignore non-json or invalid json; still counts as an artifact path
            }
        }
    }
}

if ($foundRunSummaries.Count -eq 0) {
    $errors.Add('RoutingValidationSummaryMissing:No routing validation run summary JSON found in Evidence Artifacts.') | Out-Null
}

if ($missingSections.Count -gt 0) {
    $errors.Add("MissingSections:{0}" -f ($missingSections -join ', ')) | Out-Null
}
if ($missingMetadata.Count -gt 0) {
    $errors.Add("MissingMetadata:{0}" -f ($missingMetadata -join ', ')) | Out-Null
}
if ($missingArtifactEntries.Count -gt 0) {
    $errors.Add("MissingArtifactEntries:{0}" -f ($missingArtifactEntries -join ', ')) | Out-Null
}
if ($missingArtifacts.Count -gt 0) {
    $errors.Add("MissingArtifacts:{0}" -f ($missingArtifacts -join ', ')) | Out-Null
}

$status = if ($errors.Count -gt 0) { 'Fail' } else { 'Pass' }

$summary = [pscustomobject]@{
    Timestamp        = (Get-Date -Format o)
    Status           = $status
    EvidencePath     = if (Test-Path -LiteralPath $EvidencePath) { (Resolve-Path -LiteralPath $EvidencePath).Path } else { $EvidencePath }
    Operator         = $metadata.Operator
    RunDate          = $metadata.RunDate
    Site             = $metadata.Site
    Vendor           = $metadata.Vendor
    Vrf              = $metadata.Vrf
    ArtifactPaths    = $resolvedArtifactPaths
    Validation       = [pscustomobject]@{
        MissingSections       = $missingSections
        MissingMetadata       = $missingMetadata
        MissingCommands       = if (@($commandLines).Count -eq 0) { $true } else { $false }
        MissingArtifactEntries = $missingArtifactEntries
        MissingArtifacts      = $missingArtifacts
        FoundRunSummaries     = $foundRunSummaries
    }
    Errors           = $errors
}

Ensure-Directory -Path $OutputPath
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding utf8

if ($UpdateLatest.IsPresent) {
    # LANDMARK: Operator evidence latest pointer - deterministic surfacing output
    Ensure-Directory -Path $latestPointerPath
    Copy-Item -LiteralPath $OutputPath -Destination $latestPointerPath -Force
}

if ($summary.Status -ne 'Pass') {
    throw "Routing real device evidence validation failed. See $OutputPath"
}

if ($PassThru.IsPresent) {
    return $summary
}
