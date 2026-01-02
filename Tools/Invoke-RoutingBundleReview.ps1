[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BundleZipPath,
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceRoot,
    [string]$Timestamp,
    [switch]$Overwrite,
    [switch]$SkipValidation,
    [switch]$AllowExtraFiles,
    [switch]$SkipIndex,
    [switch]$SkipRender,
    [switch]$RunExplorer,
    [ValidateSet('Console','Markdown')]
    [string]$RenderFormat = 'Markdown',
    [string]$RenderOutputPath,
    [string]$OutputSummaryPath,
    [switch]$UpdateLatest,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$latestPointerPath = Join-Path -Path $repoRoot -ChildPath 'Logs/Reports/RoutingBundles/RoutingBundleReview-latest.json'
$timestampValue = if ([string]::IsNullOrWhiteSpace($Timestamp)) { Get-Date -Format 'yyyyMMdd-HHmmss' } else { $Timestamp }

function Ensure-Directory {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $directory = Split-Path -Parent $Path
    if ([string]::IsNullOrWhiteSpace($directory)) { return }
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
}

function Resolve-RepoPath {
    param(
        [string]$Path,
        [string]$RepoRoot
    )
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path -Path $RepoRoot -ChildPath $Path))
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

function Assert-UnderRoot {
    param(
        [string]$Root,
        [string]$Path,
        [string]$Label
    )
    if (-not (Test-UnderRoot -Root $Root -Path $Path)) {
        throw "$Label '$Path' must be under OutputsRoot '$Root'."
    }
}

function Normalize-RelativePath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    $normalized = $Path -replace '/', '\'
    return $normalized.TrimStart('\').TrimStart('/')
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
    if (-not $Object) { return $null }
    $props = Get-PropertyNames -Object $Object
    if ($props -contains 'HostSummaries') { return 'RoutingValidationRunSummary' }
    if ($props -contains 'CaptureMetadata' -and $props -contains 'ArtifactPaths') { return 'RoutingDiscoveryPipelineSummary' }
    if ($props -contains 'EvidencePath' -and $props -contains 'Validation') { return 'RoutingRealDeviceEvidence' }
    if ($props -contains 'Old' -and $props -contains 'New' -and $props -contains 'Changes') { return 'RoutingDiff' }
    return $null
}

if (-not (Test-Path -LiteralPath $BundleZipPath)) {
    throw "BundleZipPath '$BundleZipPath' was not found."
}
if ([System.IO.Path]::GetExtension($BundleZipPath) -ne '.zip') {
    throw "BundleZipPath '$BundleZipPath' must be a .zip file."
}

$resolvedBundleZipPath = Resolve-RepoPath -Path $BundleZipPath -RepoRoot $repoRoot
$resolvedWorkspaceRoot = Resolve-RepoPath -Path $WorkspaceRoot -RepoRoot $repoRoot
$expandedRoot = Join-Path -Path $resolvedWorkspaceRoot -ChildPath 'Expanded'
$outputsRoot = Join-Path -Path $resolvedWorkspaceRoot -ChildPath 'Outputs'

# LANDMARK: Bundle review - workspace preparation and overwrite safety
if (Test-Path -LiteralPath $resolvedWorkspaceRoot) {
    $workspaceItem = Get-Item -LiteralPath $resolvedWorkspaceRoot -ErrorAction Stop
    if (-not $workspaceItem.PSIsContainer) {
        throw "WorkspaceRoot '$resolvedWorkspaceRoot' must be a directory."
    }
    $existingItem = Get-ChildItem -LiteralPath $resolvedWorkspaceRoot -Force | Select-Object -First 1
    if ($existingItem) {
        if (-not $Overwrite.IsPresent) {
            throw "WorkspaceRoot '$resolvedWorkspaceRoot' is not empty. Use -Overwrite to clear it."
        }
        Get-ChildItem -LiteralPath $resolvedWorkspaceRoot -Force | Remove-Item -Recurse -Force
    }
} else {
    New-Item -ItemType Directory -Path $resolvedWorkspaceRoot -Force | Out-Null
}

if (-not (Test-Path -LiteralPath $expandedRoot)) {
    New-Item -ItemType Directory -Path $expandedRoot -Force | Out-Null
}
if (-not (Test-Path -LiteralPath $outputsRoot)) {
    New-Item -ItemType Directory -Path $outputsRoot -Force | Out-Null
}

$validationOutputPath = Join-Path -Path $outputsRoot -ChildPath ("RoutingBundleValidation-{0}.json" -f $timestampValue)
$expandSummaryPath = Join-Path -Path $outputsRoot -ChildPath ("RoutingBundleExpandedSummary-{0}.json" -f $timestampValue)
$indexOutputPath = Join-Path -Path $outputsRoot -ChildPath ("RoutingLogIndex-{0}.json" -f $timestampValue)
$indexLatestPath = Join-Path -Path $outputsRoot -ChildPath 'RoutingLogIndex-latest.json'
$renderLatestPath = Join-Path -Path $outputsRoot -ChildPath 'RoutingBundlePrimarySummary-latest.md'
$explorerOutputPath = Join-Path -Path $outputsRoot -ChildPath 'RoutingLogExplorer-latest.md'
$explorerLogPath = Join-Path -Path $outputsRoot -ChildPath 'RoutingLogExplorer-latest.log'

if ([string]::IsNullOrWhiteSpace($OutputSummaryPath)) {
    $OutputSummaryPath = Join-Path -Path $outputsRoot -ChildPath ("RoutingBundleReview-{0}.json" -f $timestampValue)
}
if (-not $SkipRender.IsPresent -and $RenderFormat -eq 'Markdown' -and [string]::IsNullOrWhiteSpace($RenderOutputPath)) {
    $RenderOutputPath = Join-Path -Path $outputsRoot -ChildPath ("RoutingBundlePrimarySummary-{0}.md" -f $timestampValue)
}

$resolvedValidationOutputPath = Resolve-RepoPath -Path $validationOutputPath -RepoRoot $repoRoot
$resolvedExpandSummaryPath = Resolve-RepoPath -Path $expandSummaryPath -RepoRoot $repoRoot
$resolvedIndexOutputPath = Resolve-RepoPath -Path $indexOutputPath -RepoRoot $repoRoot
$resolvedIndexLatestPath = Resolve-RepoPath -Path $indexLatestPath -RepoRoot $repoRoot
$resolvedRenderLatestPath = Resolve-RepoPath -Path $renderLatestPath -RepoRoot $repoRoot
$resolvedExplorerOutputPath = Resolve-RepoPath -Path $explorerOutputPath -RepoRoot $repoRoot
$resolvedExplorerLogPath = Resolve-RepoPath -Path $explorerLogPath -RepoRoot $repoRoot
$resolvedSummaryOutputPath = Resolve-RepoPath -Path $OutputSummaryPath -RepoRoot $repoRoot
$resolvedRenderOutputPath = if ([string]::IsNullOrWhiteSpace($RenderOutputPath)) { $null } else { Resolve-RepoPath -Path $RenderOutputPath -RepoRoot $repoRoot }

Assert-UnderRoot -Root $outputsRoot -Path $resolvedValidationOutputPath -Label 'ValidationOutputPath'
Assert-UnderRoot -Root $outputsRoot -Path $resolvedExpandSummaryPath -Label 'ExpandSummaryPath'
Assert-UnderRoot -Root $outputsRoot -Path $resolvedIndexOutputPath -Label 'IndexOutputPath'
Assert-UnderRoot -Root $outputsRoot -Path $resolvedIndexLatestPath -Label 'IndexLatestPath'
Assert-UnderRoot -Root $outputsRoot -Path $resolvedRenderLatestPath -Label 'RenderLatestPath'
Assert-UnderRoot -Root $outputsRoot -Path $resolvedExplorerOutputPath -Label 'ExplorerOutputPath'
Assert-UnderRoot -Root $outputsRoot -Path $resolvedExplorerLogPath -Label 'ExplorerLogPath'
Assert-UnderRoot -Root $outputsRoot -Path $resolvedSummaryOutputPath -Label 'OutputSummaryPath'
if ($resolvedRenderOutputPath) {
    Assert-UnderRoot -Root $outputsRoot -Path $resolvedRenderOutputPath -Label 'RenderOutputPath'
}

if ($RunExplorer.IsPresent -and $SkipIndex.IsPresent) {
    throw "RunExplorer cannot be used with -SkipIndex. Remove -SkipIndex to build the workspace index."
}

$warnings = New-Object System.Collections.Generic.List[string]
$status = 'Pass'
$validated = $false
$validationResult = $null
$expandResult = $null
$manifestPath = Join-Path -Path $expandedRoot -ChildPath 'BundleManifest.json'
$manifestSummaryPath = $null
$primarySummaryRelativePath = $null
$primarySummaryExtractedPath = $null
$primarySummaryType = $null
$indexBuilt = $false
$rendered = $false
$indexLatestPathValue = $null
$renderLatestPathValue = $null
$explorerCommand = $null
$explorerInvoked = $false
$explorerStatus = $null
$failureMessage = $null

# LANDMARK: Bundle review - validate then expand with offline-only guarantees
if (-not $SkipValidation.IsPresent) {
    $validated = $true
    $validatorPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Test-RoutingOfflineBundle.ps1'
    if (-not (Test-Path -LiteralPath $validatorPath)) {
        $status = 'Fail'
        $failureMessage = "Routing bundle validation tool not found at '$validatorPath'."
    } else {
        try {
            $validationResult = & $validatorPath -BundleZipPath $resolvedBundleZipPath -OutputPath $resolvedValidationOutputPath -AllowExtraFiles:$AllowExtraFiles.IsPresent -PassThru
            if ($validationResult.Status -ne 'Pass') {
                $status = 'Fail'
                $failureMessage = "Bundle validation failed with status '$($validationResult.Status)'."
            }
        } catch {
            $status = 'Fail'
            $failureMessage = "Bundle validation failed: $($_.Exception.Message)"
        }
    }
} else {
    $warnings.Add('Validation skipped.') | Out-Null
}

if ($status -eq 'Pass') {
    $expanderPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Expand-RoutingOfflineBundle.ps1'
    if (-not (Test-Path -LiteralPath $expanderPath)) {
        $status = 'Fail'
        $failureMessage = "Routing bundle expand tool not found at '$expanderPath'."
    } else {
        try {
            $expandResult = & $expanderPath -BundleZipPath $resolvedBundleZipPath -OutputRoot $expandedRoot -Overwrite:$Overwrite.IsPresent -SkipValidation:$SkipValidation.IsPresent -AllowExtraFiles:$AllowExtraFiles.IsPresent -ValidationOutputPath $resolvedValidationOutputPath -SummaryPath $resolvedExpandSummaryPath -PassThru
            if ($expandResult.Status -ne 'Pass') {
                $status = 'Fail'
                $failureMessage = "Bundle expand failed with status '$($expandResult.Status)'."
            }
        } catch {
            $status = 'Fail'
            $failureMessage = "Bundle expand failed: $($_.Exception.Message)"
        }
    }
}

# LANDMARK: Bundle review - locate primary summary via BundleManifest (robust fallback)
if ($status -eq 'Pass') {
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        $status = 'Fail'
        $failureMessage = "BundleManifest.json not found under '$expandedRoot'."
    } else {
        $manifest = $null
        try {
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -ErrorAction Stop
        } catch {
            $status = 'Fail'
            $failureMessage = "Failed to parse BundleManifest.json under '$expandedRoot'."
        }

        if ($status -eq 'Pass') {
            $includedFiles = @($manifest.IncludedFiles)
            if (-not $manifest.SummaryPath) {
                $status = 'Fail'
                $failureMessage = 'BundleManifest.json does not include SummaryPath.'
            } else {
                $summaryPathValue = [string]$manifest.SummaryPath
                $manifestSummaryPath = $summaryPathValue
                $primaryEntry = $includedFiles | Where-Object {
                    $_.SourcePath -and [string]$_.SourcePath -eq $summaryPathValue
                } | Select-Object -First 1

                if (-not $primaryEntry) {
                    $summaryLeaf = Split-Path -Path $summaryPathValue -Leaf
                    if (-not [string]::IsNullOrWhiteSpace($summaryLeaf)) {
                        $primaryEntry = $includedFiles | Where-Object {
                            $_.RelativePath -and ([string]$_.RelativePath -replace '\\','/').EndsWith($summaryLeaf, [System.StringComparison]::OrdinalIgnoreCase)
                        } | Select-Object -First 1
                    }
                    if ($primaryEntry) {
                        $warnings.Add("Primary summary matched by leaf name '$summaryLeaf' (SourcePath did not match).") | Out-Null
                    }
                }

                if (-not $primaryEntry) {
                    $status = 'Fail'
                    $failureMessage = "Primary summary referenced by manifest was not found in IncludedFiles. SummaryPath: '$summaryPathValue'."
                } else {
                    $primarySummaryRelativePath = Normalize-RelativePath -Path ([string]$primaryEntry.RelativePath)
                    $primarySummaryExtractedPath = Join-Path -Path $expandedRoot -ChildPath $primarySummaryRelativePath
                    if (-not (Test-Path -LiteralPath $primarySummaryExtractedPath)) {
                        $status = 'Fail'
                        $failureMessage = "Primary summary was not found at '$primarySummaryExtractedPath'."
                    }
                }
            }
        }
    }
}

if ($status -eq 'Pass' -and $primarySummaryExtractedPath) {
    try {
        $primaryPayload = Get-Content -LiteralPath $primarySummaryExtractedPath -Raw | ConvertFrom-Json -ErrorAction Stop
        $primarySummaryType = Get-SummaryType -Object $primaryPayload
    } catch {
        $warnings.Add("Failed to parse primary summary for type detection: $($_.Exception.Message)") | Out-Null
    }
}

# LANDMARK: Bundle review - diff-aware render and diff-only index warning refinement
# LANDMARK: Bundle review - optional index build + optional rendering with warning-only failures
if ($status -eq 'Pass' -and -not $SkipIndex.IsPresent) {
    $logsRoot = Join-Path -Path $expandedRoot -ChildPath 'Logs/Reports'
    if (Test-Path -LiteralPath $logsRoot) {
        $indexerPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Build-RoutingLogIndex.ps1'
        if (-not (Test-Path -LiteralPath $indexerPath)) {
            $warnings.Add("Routing log index tool not found at '$indexerPath'.") | Out-Null
        } else {
            try {
                $indexResult = & $indexerPath -RootPath $logsRoot -OutputPath $resolvedIndexOutputPath -Recurse -PassThru
                $indexBuilt = $true
                if ($indexResult.Entries.Count -eq 0) {
                    if ($primarySummaryType -eq 'RoutingDiff') {
                        $warnings.Add('Routing log index contained 0 entries for a RoutingDiff bundle.') | Out-Null
                    } else {
                        $warnings.Add('Routing log index contained 0 entries.') | Out-Null
                    }
                }
            } catch {
                $message = $_.Exception.Message
                if ($primarySummaryType -eq 'RoutingDiff' -and $message -match 'No routing summary JSON files') {
                    $warnings.Add('Routing log index skipped for a RoutingDiff-only bundle.') | Out-Null
                } else {
                    $warnings.Add("Routing log index build failed: $message") | Out-Null
                }
            }
        }
    } else {
        $warnings.Add("Logs/Reports not found under '$expandedRoot'; skipping index build.") | Out-Null
    }
}

if ($status -eq 'Pass' -and -not $SkipRender.IsPresent -and $primarySummaryExtractedPath) {
    $viewerPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Show-RoutingLogSummary.ps1'
    if (-not (Test-Path -LiteralPath $viewerPath)) {
        $warnings.Add("Routing log viewer not found at '$viewerPath'.") | Out-Null
    } else {
        try {
            if ($RenderFormat -eq 'Console') {
                & $viewerPath -Path $primarySummaryExtractedPath -Format Console | Out-Null
            } else {
                & $viewerPath -Path $primarySummaryExtractedPath -Format $RenderFormat -OutputPath $resolvedRenderOutputPath | Out-Null
            }
            $rendered = $true
        } catch {
            $warnings.Add("Primary summary render failed: $($_.Exception.Message)") | Out-Null
        }
    }
}

# LANDMARK: Bundle review ergonomics - write workspace-local latest pointers for index + rendered primary summary
if ($indexBuilt -and (Test-Path -LiteralPath $resolvedIndexOutputPath)) {
    Ensure-Directory -Path $resolvedIndexLatestPath
    Copy-Item -LiteralPath $resolvedIndexOutputPath -Destination $resolvedIndexLatestPath -Force
    $indexLatestPathValue = $resolvedIndexLatestPath
}
if ($rendered -and $resolvedRenderOutputPath -and (Test-Path -LiteralPath $resolvedRenderOutputPath)) {
    Ensure-Directory -Path $resolvedRenderLatestPath
    Copy-Item -LiteralPath $resolvedRenderOutputPath -Destination $resolvedRenderLatestPath -Force
    $renderLatestPathValue = $resolvedRenderLatestPath
}

# LANDMARK: Bundle review ergonomics - emit explorer next-command from workspace index latest pointer
if ($indexLatestPathValue) {
    $explorerCommand = 'pwsh -NoProfile -File Tools/Invoke-RoutingLogExplorer.ps1 -IndexPath "{0}" -Latest -Format Markdown -OutputPath "{1}" -PassThru *>&1 | Tee-Object -FilePath "{2}"' -f $indexLatestPathValue, $resolvedExplorerOutputPath, $resolvedExplorerLogPath
}

# LANDMARK: Bundle review one-step - run explorer using workspace index latest pointer and emit explorer outputs
if ($status -eq 'Pass' -and $RunExplorer.IsPresent) {
    $explorerInvoked = $true
    $explorerStatus = 'Fail'
    $explorerToolPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Invoke-RoutingLogExplorer.ps1'
    if (-not $indexLatestPathValue -or -not (Test-Path -LiteralPath $indexLatestPathValue)) {
        $status = 'Fail'
        $failureMessage = "RunExplorer requires a workspace index at '$resolvedIndexLatestPath'. See log: '$resolvedExplorerLogPath'."
    } elseif (-not (Test-Path -LiteralPath $explorerToolPath)) {
        $status = 'Fail'
        $failureMessage = "Routing log explorer tool not found at '$explorerToolPath'. See log: '$resolvedExplorerLogPath'."
    } else {
        try {
            Ensure-Directory -Path $resolvedExplorerLogPath
            $null = & $explorerToolPath -IndexPath $indexLatestPathValue -Latest -Format Markdown -OutputPath $resolvedExplorerOutputPath -PassThru *>&1 |
                Tee-Object -FilePath $resolvedExplorerLogPath
            if (-not (Test-Path -LiteralPath $resolvedExplorerOutputPath)) {
                $status = 'Fail'
                $failureMessage = "Explorer output was not created at '$resolvedExplorerOutputPath'. See log: '$resolvedExplorerLogPath'."
            } else {
                $explorerStatus = 'Pass'
            }
        } catch {
            $status = 'Fail'
            $failureMessage = "Explorer run failed. See log: '$resolvedExplorerLogPath'. Error: $($_.Exception.Message)"
        }
    }
}

# LANDMARK: Bundle review - deterministic review summary + latest pointer
$reviewSummary = [ordered]@{
    SchemaVersion               = '1.0'
    BundleZipPath               = $resolvedBundleZipPath
    WorkspaceRoot               = $resolvedWorkspaceRoot
    Timestamp                   = $timestampValue
    Status                      = $status
    Validated                   = $validated
    ValidationOutputPath        = if ($validated) { $resolvedValidationOutputPath } else { $null }
    ExpandedRoot                = $expandedRoot
    ExpandSummaryPath           = $resolvedExpandSummaryPath
    ManifestPath                = $manifestPath
    ManifestSummaryPath         = $manifestSummaryPath
    PrimarySummaryRelativePath  = $primarySummaryRelativePath
    PrimarySummaryExtractedPath = $primarySummaryExtractedPath
    IndexBuilt                  = $indexBuilt
    IndexOutputPath             = if ($SkipIndex.IsPresent) { $null } else { $resolvedIndexOutputPath }
    IndexLatestPath             = $indexLatestPathValue
    Rendered                    = $rendered
    RenderFormat                = if ($SkipRender.IsPresent) { $null } else { $RenderFormat }
    RenderOutputPath            = if ($SkipRender.IsPresent) { $null } else { $resolvedRenderOutputPath }
    RenderLatestPath            = $renderLatestPathValue
    ExplorerInvoked             = $explorerInvoked
    ExplorerStatus              = if ($explorerInvoked) { $explorerStatus } else { $null }
    ExplorerOutputPath          = if ($explorerInvoked) { $resolvedExplorerOutputPath } else { $null }
    ExplorerLogPath             = if ($explorerInvoked) { $resolvedExplorerLogPath } else { $null }
    ExplorerCommand             = $explorerCommand
    Warnings                    = @($warnings)
}

Ensure-Directory -Path $resolvedSummaryOutputPath
$reviewSummary | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $resolvedSummaryOutputPath -Encoding UTF8

if ($UpdateLatest.IsPresent) {
    Ensure-Directory -Path $latestPointerPath
    Copy-Item -LiteralPath $resolvedSummaryOutputPath -Destination $latestPointerPath -Force
}

Write-Host ("Bundle: {0}" -f $resolvedBundleZipPath)
Write-Host ("ExpandedRoot: {0}" -f $expandedRoot)
Write-Host ("PrimarySummary: {0}" -f $primarySummaryExtractedPath)
if ($indexBuilt) {
    Write-Host ("Index: {0}" -f $resolvedIndexOutputPath)
}
if ($rendered -and $resolvedRenderOutputPath) {
    Write-Host ("Render: {0}" -f $resolvedRenderOutputPath)
}
if ($explorerCommand) {
    Write-Host ("ExplorerCommand: {0}" -f $explorerCommand)
}
if ($explorerInvoked -and (Test-Path -LiteralPath $resolvedExplorerOutputPath)) {
    Write-Host ("ExplorerOutput: {0}" -f $resolvedExplorerOutputPath)
}
if ($explorerInvoked -and (Test-Path -LiteralPath $resolvedExplorerLogPath)) {
    Write-Host ("ExplorerLog: {0}" -f $resolvedExplorerLogPath)
}
Write-Host ("ReviewSummary: {0}" -f $resolvedSummaryOutputPath)

if ($PassThru.IsPresent) {
    $reviewSummary
}

if ($status -ne 'Pass') {
    throw $failureMessage
}
