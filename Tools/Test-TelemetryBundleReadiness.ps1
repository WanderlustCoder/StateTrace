[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BundlePath,

    [ValidateSet('Telemetry', 'Routing')]
    [string[]]$Area,

    [switch]$IncludeReadmeHash,

    [ValidateSet('SHA1', 'SHA256', 'SHA384', 'SHA512', 'MD5')]
    [string]$HashAlgorithm = 'SHA256',

    [string]$SummaryPath,

    [switch]$PassThru
)

<#
.SYNOPSIS
Validates that telemetry bundle folders contain the required artifacts for release gating.

.DESCRIPTION
Scans the specified bundle (or bundle area) for README/manifest files plus the plan-mandated
artifacts (rollup CSVs, analyzer output, warm-run telemetry, queue summaries, dispatcher logs,
doc-sync evidence, etc.). Missing required artifacts cause the script to throw so CI/release
pipelines can block until the bundle is complete.

.EXAMPLE
pwsh Tools\Test-TelemetryBundleReadiness.ps1 -BundlePath Logs/TelemetryBundles/2025-11-13.1 -Area Telemetry,Routing

.EXAMPLE
pwsh Tools\Test-TelemetryBundleReadiness.ps1 -BundlePath Logs/TelemetryBundles/Routing-20251113/Routing
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$toolingJsonPath = Join-Path -Path $PSScriptRoot -ChildPath 'ToolingJson.psm1'
if (Test-Path -LiteralPath $toolingJsonPath) {
    Import-Module -Name $toolingJsonPath -Force
} else {
    throw "ToolingJson module not found at '$toolingJsonPath'."
}

function Resolve-AreaContexts {
    param(
        [Parameter(Mandatory = $true)][string]$BundlePath,
        [string[]]$RequestedAreas,
        [hashtable]$AreaDefinitions
    )

    if ($RequestedAreas) {
        $RequestedAreas = @($RequestedAreas)
    }

    $resolvedBundle = Resolve-Path -LiteralPath $BundlePath -ErrorAction Stop
    $bundleFullPath = $resolvedBundle.Path
    $manifestPath = Join-Path -Path $bundleFullPath -ChildPath 'TelemetryBundle.json'

    $contexts = [System.Collections.Generic.List[pscustomobject]]::new()

    if (Test-Path -LiteralPath $manifestPath) {
        $manifest = Read-ToolingJson -Path $manifestPath -Label 'Telemetry bundle manifest'
        $areaName = if ($manifest.AreaName) { $manifest.AreaName } else { 'Telemetry' }
        if ($RequestedAreas -and $RequestedAreas.Count -gt 0 -and ($RequestedAreas -notcontains $areaName)) {
            Write-Warning "Bundle path '$bundleFullPath' points to area '$areaName'. Ignoring requested areas '$($RequestedAreas -join ', ')'."
        }
        if (-not $AreaDefinitions.ContainsKey($areaName)) {
            throw "No requirement definition registered for area '$areaName'."
        }
        $contexts.Add([pscustomobject]@{
            Name = $areaName
            Path = $bundleFullPath
            Manifest = $manifest
        })
    }
    else {
        $areasToInspect = $RequestedAreas
        if (-not $areasToInspect -or $areasToInspect.Count -eq 0) {
            $areasToInspect = Get-ChildItem -LiteralPath $bundleFullPath -Directory -ErrorAction Stop |
                Where-Object { $AreaDefinitions.ContainsKey($_.Name) } |
                Select-Object -ExpandProperty Name
        }

        if (-not $areasToInspect -or $areasToInspect.Count -eq 0) {
            throw "Bundle '$bundleFullPath' does not contain any known telemetry areas (Telemetry or Routing)."
        }

        foreach ($areaName in $areasToInspect) {
            if (-not $AreaDefinitions.ContainsKey($areaName)) {
                throw "Area '$areaName' is not supported. Valid values: $($AreaDefinitions.Keys -join ', ')."
            }

            $areaPath = Join-Path -Path $bundleFullPath -ChildPath $areaName
            if (-not (Test-Path -LiteralPath $areaPath)) {
                throw "Bundle '$bundleFullPath' does not contain an '$areaName' folder."
            }

            $areaManifestPath = Join-Path -Path $areaPath -ChildPath 'TelemetryBundle.json'
            if (-not (Test-Path -LiteralPath $areaManifestPath)) {
                throw "Area '$areaName' is missing TelemetryBundle.json."
            }

            $manifest = Read-ToolingJson -Path $areaManifestPath -Label ("Telemetry bundle manifest ({0})" -f $areaName)
            $contexts.Add([pscustomobject]@{
                Name = $areaName
                Path = $areaPath
                Manifest = $manifest
            })
        }
    }

    return $contexts
}

function Get-MatchingFiles {
    param(
        [Parameter(Mandatory = $true)][string]$AreaPath,
        [Parameter(Mandatory = $true)][string[]]$Patterns
    )

    $matches = @()
    foreach ($pattern in $Patterns) {
        if (-not $pattern) { continue }
        $fullPattern = Join-Path -Path $AreaPath -ChildPath $pattern
        $items = Get-ChildItem -Path $fullPattern -File -ErrorAction SilentlyContinue
        if ($items) { $matches += $items }
    }

    return ($matches | Sort-Object FullName -Unique)
}

function Convert-ToRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$FullPath
    )

    $normalizedBase = $BasePath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    if ($FullPath.StartsWith($normalizedBase, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $FullPath.Substring($normalizedBase.Length).TrimStart('\', '/')
    }

    return $FullPath
}

$requirements = @{
    Telemetry = @(
        @{ Name = 'README'; Patterns = @('README.md'); Required = $true; Description = 'Bundle README file'; },
        @{ Name = 'Manifest'; Patterns = @('TelemetryBundle.json'); Required = $true; Description = 'TelemetryBundle.json manifest'; },
        @{ Name = 'Rollup CSV'; Patterns = @('IngestionMetricsSummary*.csv'); Required = $true; Description = 'Daily rollup CSV (IngestionMetricsSummary-*.csv)'; },
        @{ Name = 'Shared-cache analyzer'; Patterns = @('SharedCacheStoreState*.json'); Required = $true; Description = 'Shared cache analyzer output (SnapshotImported stats)'; },
        @{ Name = 'Site cache providers'; Patterns = @('SiteCacheProviderReasons*.json'); Required = $true; Description = 'Site cache provider reason breakdown'; },
        @{ Name = 'Warm-run telemetry'; Patterns = @('WarmRunTelemetry*.json'); Required = $true; Description = 'Warm-run telemetry summary'; },
        @{ Name = 'Diff hotspot CSV'; Patterns = @('WarmRunDiffHotspots*.csv','DiffHotspots-*.csv'); Required = $true; Description = 'Diff hotspot export'; },
        @{ Name = 'Doc-sync evidence'; Patterns = @('DocSync\DocSyncChecklist.json','DocSync\*.json','DocSync\*.md','*session*.md'); Required = $true; Description = 'Doc-sync checklist output (JSON or markdown)'; }
    );
    Routing = @(
        @{ Name = 'README'; Patterns = @('README.md'); Required = $true; Description = 'Bundle README file'; },
        @{ Name = 'Manifest'; Patterns = @('TelemetryBundle.json'); Required = $true; Description = 'TelemetryBundle.json manifest'; },
        @{ Name = 'Routing telemetry JSON'; Patterns = @('20*.json','Routing*.json'); Required = $true; Description = 'Routing ingestion telemetry (InterfaceSyncTiming / queue metrics)'; },
        @{ Name = 'Queue delay summary'; Patterns = @('QueueDelaySummary*.json'); Required = $true; Description = 'Queue delay summary JSON export'; },
        @{ Name = 'Queue delay pointer'; Patterns = @('QueueDelaySummary-latest.json'); Required = $false; WarnIfMissing = $true; Description = 'Queue delay latest pointer (QueueDelaySummary-latest.json)'; },
        @{ Name = 'Dispatcher logs'; Patterns = @('DispatcherLogs\*.log','*.log'); Required = $true; Description = 'Dispatcher harness logs per host (BOYO/WLLS)'; },
        @{ Name = 'Routing sweep summary'; Patterns = @('RoutingQueueSweep*.json'); Required = $false; WarnIfMissing = $true; Description = 'Routing queue sweep aggregate JSON'; },
        @{ Name = 'Doc-sync evidence'; Patterns = @('DocSync\DocSyncChecklist.json','DocSync\*.json','DocSync\*.md','*session*.md'); Required = $true; Description = 'Doc-sync checklist output (JSON or markdown)'; }
    )
}

$contexts = Resolve-AreaContexts -BundlePath $BundlePath -RequestedAreas $Area -AreaDefinitions $requirements

$results = [System.Collections.Generic.List[pscustomobject]]::new()
$missingRequired = $false
$areaReadmeInfo = @{}

foreach ($ctx in $contexts) {
    $areaRequirements = $requirements[$ctx.Name]
    if (-not $areaRequirements) {
        Write-Warning "No requirement set defined for area '$($ctx.Name)'; skipping."
        continue
    }

    foreach ($requirement in $areaRequirements) {
        $matches = Get-MatchingFiles -AreaPath $ctx.Path -Patterns $requirement.Patterns
        $matchList = @($matches)
        $relativeMatches = $matchList | ForEach-Object { Convert-ToRelativePath -BasePath $ctx.Path -FullPath $_.FullName }

        $status = if ($matchList.Count -gt 0) {
            'Present'
        }
        elseif ($requirement.Required) {
            $missingRequired = $true
            'Missing'
        }
        else {
            if ($requirement.WarnIfMissing) {
                Write-Warning "[$($ctx.Name)] Optional artifact '$($requirement.Name)' was not found."
            }
            'Missing (Optional)'
        }

        if ($requirement.Name -eq 'README' -and $matchList.Count -gt 0) {
            $primaryReadme = $matchList | Select-Object -First 1
            $areaReadmeInfo[$ctx.Name] = @{
                FullPath     = $primaryReadme.FullName
                RelativePath = Convert-ToRelativePath -BasePath $ctx.Path -FullPath $primaryReadme.FullName
            }
        }

        $results.Add([pscustomobject]@{
            Area = $ctx.Name
            Requirement = $requirement.Name
            Description = $requirement.Description
            Status = $status
            Files = if ($relativeMatches) { $relativeMatches -join '; ' } else { '' }
        })
    }
}

if ($IncludeReadmeHash -or $SummaryPath) {
    $readmeSummaries = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($ctx in $contexts) {
        $readmeInfo = $areaReadmeInfo[$ctx.Name]
        if (-not $readmeInfo) {
            if ($IncludeReadmeHash) {
                Write-Warning "[$($ctx.Name)] README file not found; cannot compute hash."
            }
            continue
        }

        $hash = Get-FileHash -LiteralPath $readmeInfo.FullPath -Algorithm $HashAlgorithm
        $readmeSummaries.Add([pscustomobject]@{
            Area          = $ctx.Name
            ReadmePath    = $readmeInfo.RelativePath
            HashAlgorithm = $hash.Algorithm
            Hash          = $hash.Hash
        })
    }

    if ($IncludeReadmeHash -and $readmeSummaries.Count -gt 0) {
        $hashTable = $readmeSummaries | Format-Table Area, HashAlgorithm, Hash, ReadmePath -AutoSize | Out-String
        Write-Host $hashTable
    }

    if ($SummaryPath) {
        $summaryDirectory = Split-Path -Path $SummaryPath -Parent
        if ($summaryDirectory -and -not (Test-Path -LiteralPath $summaryDirectory)) {
            New-Item -ItemType Directory -Path $summaryDirectory -Force | Out-Null
        }

        $areaSummaries = foreach ($ctx in $contexts) {
            $areaResults = $results | Where-Object { $_.Area -eq $ctx.Name }
            $readmeRecord = $readmeSummaries | Where-Object { $_.Area -eq $ctx.Name } | Select-Object -First 1
            $manifestPath = Join-Path -Path $ctx.Path -ChildPath 'TelemetryBundle.json'

            [pscustomobject]@{
                Area             = $ctx.Name
                BundlePath       = $ctx.Path
                ManifestPath     = if (Test-Path -LiteralPath $manifestPath) { Convert-ToRelativePath -BasePath $ctx.Path -FullPath $manifestPath } else { '' }
                ReadmePath       = $readmeRecord.ReadmePath
                ReadmeHash       = $readmeRecord.Hash
                HashAlgorithm    = $readmeRecord.HashAlgorithm
                RequirementState = $areaResults | Select-Object Requirement, Status, Files
            }
        }

        $areaSummaries | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $SummaryPath -Encoding utf8
        Write-Host ("Telemetry bundle summary written to {0}" -f (Resolve-Path -LiteralPath $SummaryPath)) -ForegroundColor DarkCyan
    }
}

if ($PassThru) {
    return $results
}

$table = $results | Format-Table Area, Requirement, Status, Files -AutoSize | Out-String
Write-Host $table

if ($missingRequired) {
    $missingList = $results | Where-Object { $_.Status -eq 'Missing' }
    $summary = $missingList | Format-Table Area, Requirement -AutoSize | Out-String
    throw "Telemetry bundle readiness failed. Missing required artifacts:`n$summary"
}
else {
    Write-Host "Telemetry bundle passed readiness checks." -ForegroundColor Green
}
