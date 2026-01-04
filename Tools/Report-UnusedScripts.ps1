<#
.SYNOPSIS
Reports scripts in Tools/ that appear unused across the codebase.

.DESCRIPTION
ST-S-003: Scans Tools/ scripts and checks for references in:
- Other scripts (Tools/, Modules/, Main/)
- Documentation (docs/)
- Runbooks and plans

Reports scripts with zero or low reference counts for review.

.PARAMETER RepositoryRoot
Repository root path. Defaults to parent of script directory.

.PARAMETER ToolsPath
Path to Tools directory. Defaults to <Root>/Tools.

.PARAMETER OutputPath
Optional JSON output path. If not specified, writes to Logs/Reports/UnusedScripts-<timestamp>.json.

.PARAMETER MinReferenceCount
Scripts with references below this count are flagged. Default 1.

.PARAMETER Allowlist
Script names to exclude from unused checks (known entry points).

.PARAMETER FailOnUnused
Exit with error code if unused scripts are found.

.PARAMETER PassThru
Return the report as an object.
#>
param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$ToolsPath,
    [string]$OutputPath,
    [int]$MinReferenceCount = 1,
    [string[]]$Allowlist = @(),
    [switch]$FailOnUnused,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
if (-not $ToolsPath) {
    $ToolsPath = Join-Path $repoRoot 'Tools'
}

# Known entry points that are invoked directly (not referenced in code)
$defaultAllowlist = @(
    # Main entry points
    'Invoke-StateTracePipeline.ps1',
    'Invoke-WarmRunTelemetry.ps1',
    'Invoke-AllChecks.ps1',
    'Invoke-CIHarness.ps1',
    'Bootstrap-DevSeat.ps1',
    # UI harnesses
    'Invoke-SpanViewSmokeTest.ps1',
    'Invoke-InterfacesViewSmokeTest.ps1',
    'Invoke-InterfacesViewChecklist.ps1',
    # Telemetry and bundling
    'Publish-TelemetryBundle.ps1',
    'New-TelemetryBundle.ps1',
    'Rollup-IngestionMetrics.ps1',
    # Routing
    'Invoke-RoutingQueueSweep.ps1',
    'Invoke-RoutingValidationRun.ps1',
    'Invoke-RoutingCliCaptureSession.ps1',
    # Maintenance
    'Pack-StateTrace.ps1',
    'Clean-ArtifactsAndBundle.ps1',
    # Recently created tools
    'Report-UnusedExports.ps1',
    'Report-UnusedScripts.ps1',
    'Invoke-FeatureFlagAudit.ps1',
    'Test-SharedCacheSnapshot.ps1',
    'Test-PlanTaskBoardDrift.ps1',
    'Sync-TaskBoard.ps1',
    'New-SessionLogStub.ps1',
    'Test-TelemetryBundleReadiness.ps1',
    'Test-DependencyPreflight.ps1',
    'New-RollbackBundle.ps1',
    'Invoke-IncidentDrill.ps1',
    'Test-Accessibility.ps1'
)

$effectiveAllowlist = $defaultAllowlist + $Allowlist | Select-Object -Unique

Write-Host "Scanning Tools/ for scripts..." -ForegroundColor Cyan
$scripts = Get-ChildItem -LiteralPath $ToolsPath -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne 'Report-UnusedScripts.ps1' }

Write-Host ("Found {0} scripts in Tools/" -f $scripts.Count) -ForegroundColor Cyan

# Search roots for references
$searchRoots = @(
    (Join-Path $repoRoot 'Tools'),
    (Join-Path $repoRoot 'Modules'),
    (Join-Path $repoRoot 'Main'),
    (Join-Path $repoRoot 'docs'),
    (Join-Path $repoRoot 'Tests')
) | Where-Object { Test-Path -LiteralPath $_ }

$report = [System.Collections.Generic.List[pscustomobject]]::new()

foreach ($script in $scripts) {
    $scriptName = $script.Name
    $scriptBaseName = [System.IO.Path]::GetFileNameWithoutExtension($scriptName)

    # Build search patterns
    $patterns = @(
        [regex]::Escape($scriptName),
        [regex]::Escape($scriptBaseName)
    )

    $references = [System.Collections.Generic.List[pscustomobject]]::new()

    foreach ($root in $searchRoots) {
        $files = Get-ChildItem -LiteralPath $root -Recurse -File -Include '*.ps1','*.psm1','*.md','*.txt','*.json' -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -ne $script.FullName }

        foreach ($file in $files) {
            $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
            if (-not $content) { continue }

            foreach ($pattern in $patterns) {
                if ($content -match $pattern) {
                    $relativePath = $file.FullName.Substring($repoRoot.Length).TrimStart('\', '/')
                    $references.Add([pscustomobject]@{
                        File    = $relativePath
                        Pattern = $pattern
                    })
                    break
                }
            }
        }
    }

    # Deduplicate references by file
    $uniqueRefs = @($references | Select-Object -Property File -Unique)
    $refCount = if ($uniqueRefs) { $uniqueRefs.Count } else { 0 }

    $isAllowlisted = $effectiveAllowlist -contains $scriptName

    $report.Add([pscustomobject]@{
        Script         = $scriptName
        Path           = $script.FullName.Substring($repoRoot.Length).TrimStart('\', '/')
        ReferenceCount = $refCount
        References     = if ($uniqueRefs) { ($uniqueRefs | Select-Object -First 5 | ForEach-Object { $_.File }) -join '; ' } else { '' }
        Allowlisted    = $isAllowlisted
        PotentiallyUnused = (-not $isAllowlisted) -and ($refCount -lt $MinReferenceCount)
    })
}

# Sort by reference count
$report = $report | Sort-Object ReferenceCount, Script

$unused = @($report | Where-Object { $_.PotentiallyUnused })

$summary = [pscustomobject]@{
    Timestamp          = Get-Date -Format 'o'
    TotalScripts       = $report.Count
    AllowlistedCount   = @($report | Where-Object { $_.Allowlisted }).Count
    PotentiallyUnused  = $unused.Count
    MinReferenceCount  = $MinReferenceCount
}

$result = [pscustomobject]@{
    Summary = $summary
    Scripts = $report
}

# Output
if (-not $OutputPath) {
    $reportDir = Join-Path $repoRoot 'Logs\Reports'
    if (-not (Test-Path -LiteralPath $reportDir)) {
        New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    }
    $OutputPath = Join-Path $reportDir ("UnusedScripts-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
}

$outputDir = Split-Path -Path $OutputPath -Parent
if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host ("Script usage report written to: {0}" -f $OutputPath) -ForegroundColor Green

# Display summary
Write-Host "`nScript Usage Summary:" -ForegroundColor Cyan
Write-Host ("  Total scripts: {0}" -f $summary.TotalScripts)
Write-Host ("  Allowlisted (known entry points): {0}" -f $summary.AllowlistedCount)
Write-Host ("  Potentially unused: {0}" -f $summary.PotentiallyUnused)

if ($unused.Count -gt 0) {
    Write-Host "`nPotentially unused scripts:" -ForegroundColor Yellow
    foreach ($u in $unused | Select-Object -First 20) {
        Write-Host ("  - {0} (refs: {1})" -f $u.Script, $u.ReferenceCount) -ForegroundColor Yellow
    }
    if ($unused.Count -gt 20) {
        Write-Host ("  ... and {0} more (see report)" -f ($unused.Count - 20)) -ForegroundColor Yellow
    }
}

if ($FailOnUnused -and $unused.Count -gt 0) {
    Write-Error "Potentially unused scripts found. See report for details."
    exit 2
}

if ($PassThru) {
    return $result
}
