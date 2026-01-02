[CmdletBinding()]
param(
    [string]$OutputRoot,
    [string]$Timestamp,
    [switch]$UpdateLatest,
    [switch]$PassThru,
    [switch]$Overwrite
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path -Path $repoRoot -ChildPath 'Logs/Reports/RoutingOfflineDemo'
}
if ([string]::IsNullOrWhiteSpace($Timestamp)) {
    $Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
}

function Resolve-RepoPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PathValue,
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )
    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }
    return [System.IO.Path]::GetFullPath((Join-Path -Path $RepoRoot -ChildPath $PathValue))
}

function Ensure-Directory {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $directory = Split-Path -Parent $Path
    if ([string]::IsNullOrWhiteSpace($directory)) { return }
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
}

function Add-Failure {
    param(
        [System.Collections.Generic.List[string]]$Errors,
        [string]$Step,
        [string]$Message,
        [ref]$FailedStep,
        [ref]$ActionableError
    )
    if ($null -eq $Errors) { return }
    $Errors.Add(("{0}: {1}" -f $Step, $Message)) | Out-Null
    if (-not $FailedStep.Value) {
        $FailedStep.Value = $Step
    }
    if (-not $ActionableError.Value) {
        $ActionableError.Value = $Message
    }
}

$resolvedOutputRoot = Resolve-RepoPath -PathValue $OutputRoot -RepoRoot $repoRoot
$runRoot = Join-Path -Path $resolvedOutputRoot -ChildPath ("Run-{0}" -f $Timestamp)
$diffRoot = Join-Path -Path $runRoot -ChildPath 'Diff'
$bundlesRoot = Join-Path -Path $runRoot -ChildPath 'Bundles'
$reviewRoot = Join-Path -Path $runRoot -ChildPath 'Review'
$outputsRoot = Join-Path -Path $runRoot -ChildPath 'Outputs'

$diffJsonPath = Join-Path -Path $diffRoot -ChildPath ("RoutingDiff-{0}.json" -f $Timestamp)
$diffMarkdownPath = Join-Path -Path $diffRoot -ChildPath ("RoutingDiff-{0}.md" -f $Timestamp)
$bundleZipPath = Join-Path -Path $bundlesRoot -ChildPath ("RoutingBundle-Diff-{0}.zip" -f $Timestamp)
$bundleValidationPath = Join-Path -Path $bundlesRoot -ChildPath ("RoutingBundleValidation-{0}.json" -f $Timestamp)
$reviewWorkspaceRoot = Join-Path -Path $reviewRoot -ChildPath 'Workspace'
$reviewOutputsRoot = Join-Path -Path $reviewWorkspaceRoot -ChildPath 'Outputs'
$reviewSummaryPath = Join-Path -Path $reviewOutputsRoot -ChildPath ("RoutingBundleReview-{0}.json" -f $Timestamp)
$reviewExplorerPath = Join-Path -Path $reviewOutputsRoot -ChildPath 'RoutingLogExplorer-latest.md'

$diffMarkdownOutputPath = Join-Path -Path $outputsRoot -ChildPath (Split-Path -Path $diffMarkdownPath -Leaf)
$reviewSummaryOutputPath = Join-Path -Path $outputsRoot -ChildPath (Split-Path -Path $reviewSummaryPath -Leaf)
$reviewExplorerOutputPath = Join-Path -Path $outputsRoot -ChildPath (Split-Path -Path $reviewExplorerPath -Leaf)

$summaryPath = Join-Path -Path $runRoot -ChildPath ("RoutingOfflineDemoSummary-{0}.json" -f $Timestamp)
$summaryLatestPath = Join-Path -Path $resolvedOutputRoot -ChildPath 'RoutingOfflineDemoSummary-latest.json'

$fixturePaths = [ordered]@{
    OldSnapshot     = Resolve-RepoPath -PathValue 'Tests/Fixtures/Routing/RouteDiff/RouteHealthSnapshot.old.json' -RepoRoot $repoRoot
    NewSnapshot     = Resolve-RepoPath -PathValue 'Tests/Fixtures/Routing/RouteDiff/RouteHealthSnapshot.new.json' -RepoRoot $repoRoot
    OldRouteRecords = Resolve-RepoPath -PathValue 'Tests/Fixtures/Routing/RouteDiff/RouteRecords.old.json' -RepoRoot $repoRoot
    NewRouteRecords = Resolve-RepoPath -PathValue 'Tests/Fixtures/Routing/RouteDiff/RouteRecords.new.json' -RepoRoot $repoRoot
}

$summary = [ordered]@{
    Timestamp               = $Timestamp
    Status                  = 'Fail'
    FixturePaths            = $fixturePaths
    DiffJsonPath            = $diffJsonPath
    DiffMarkdownPath        = $diffMarkdownPath
    BundleZipPath           = $bundleZipPath
    BundleValidationJsonPath = $bundleValidationPath
    ReviewWorkspaceRoot     = $reviewWorkspaceRoot
    ReviewSummaryJsonPath   = $reviewSummaryPath
    ExplorerMarkdownPath    = $reviewExplorerOutputPath
    NextCommands            = @()
    FailedStep              = $null
    ActionableError         = $null
}

$errors = New-Object System.Collections.Generic.List[string]
$failedStep = $null
$actionableError = $null
$reviewSummary = $null
$explorerCommand = $null
$reviewCommand = $null
$bundleSummaryPath = $diffJsonPath
$bundleExportRoot = $repoRoot
$bundleStagingRoot = $null

$compareToolPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Compare-RouteHealthSnapshots.ps1'
$exportToolPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Export-RoutingOfflineBundle.ps1'
$validateToolPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Test-RoutingOfflineBundle.ps1'
$reviewToolPath = Join-Path -Path $repoRoot -ChildPath 'Tools/Invoke-RoutingBundleReview.ps1'

foreach ($fixtureEntry in $fixturePaths.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $fixtureEntry.Value)) {
        Add-Failure -Errors $errors -Step 'Fixtures' -Message ("Fixture missing at '{0}'." -f $fixtureEntry.Value) -FailedStep ([ref]$failedStep) -ActionableError ([ref]$actionableError)
    }
}
foreach ($toolPath in @($compareToolPath, $exportToolPath, $validateToolPath, $reviewToolPath)) {
    if (-not (Test-Path -LiteralPath $toolPath)) {
        Add-Failure -Errors $errors -Step 'Tooling' -Message ("Tool not found at '{0}'." -f $toolPath) -FailedStep ([ref]$failedStep) -ActionableError ([ref]$actionableError)
    }
}

if ($errors.Count -eq 0) {
    if (Test-Path -LiteralPath $runRoot) {
        if (-not $Overwrite.IsPresent) {
            Add-Failure -Errors $errors -Step 'InitializeRunRoot' -Message ("Run folder already exists at '{0}'. Use -Overwrite to replace it." -f $runRoot) -FailedStep ([ref]$failedStep) -ActionableError ([ref]$actionableError)
        } else {
            Remove-Item -LiteralPath $runRoot -Recurse -Force
        }
    }
}

if ($errors.Count -eq 0) {
    foreach ($path in @($diffRoot, $bundlesRoot, $reviewRoot, $outputsRoot)) {
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }
}

# LANDMARK: Offline demo - orchestrate fixtures  diff  bundle  review  explorer with deterministic run folder and summary
if ($errors.Count -eq 0) {
    try {
        & $compareToolPath `
            -OldSnapshotPath $fixturePaths.OldSnapshot `
            -NewSnapshotPath $fixturePaths.NewSnapshot `
            -OldRouteRecordsPath $fixturePaths.OldRouteRecords `
            -NewRouteRecordsPath $fixturePaths.NewRouteRecords `
            -OutputPath $diffJsonPath `
            -MarkdownPath $diffMarkdownPath | Out-Null
    } catch {
        Add-Failure -Errors $errors -Step 'Diff' -Message $_.Exception.Message -FailedStep ([ref]$failedStep) -ActionableError ([ref]$actionableError)
    }
    if (-not (Test-Path -LiteralPath $diffJsonPath)) {
        Add-Failure -Errors $errors -Step 'Diff' -Message ("Diff JSON not created at '{0}'." -f $diffJsonPath) -FailedStep ([ref]$failedStep) -ActionableError ([ref]$actionableError)
    }
    if (-not (Test-Path -LiteralPath $diffMarkdownPath)) {
        Add-Failure -Errors $errors -Step 'Diff' -Message ("Diff markdown not created at '{0}'." -f $diffMarkdownPath) -FailedStep ([ref]$failedStep) -ActionableError ([ref]$actionableError)
    }
}

if ($errors.Count -eq 0) {
    $bundleStagingRoot = Join-Path -Path $repoRoot -ChildPath ("Logs/Reports/RoutingOfflineDemo/BundleStaging/Run-{0}" -f $Timestamp)
    $bundleStagingDiffRoot = Join-Path -Path $bundleStagingRoot -ChildPath 'Diff'
    $bundleStagingDiffPath = Join-Path -Path $bundleStagingDiffRoot -ChildPath ("RoutingDiff-{0}.json" -f $Timestamp)
    try {
        Ensure-Directory -Path $bundleStagingDiffPath
        Copy-Item -LiteralPath $diffJsonPath -Destination $bundleStagingDiffPath -Force
        $bundleSummaryPath = $bundleStagingDiffPath
    } catch {
        Add-Failure -Errors $errors -Step 'BundleExport' -Message $_.Exception.Message -FailedStep ([ref]$failedStep) -ActionableError ([ref]$actionableError)
    }
}

if ($errors.Count -eq 0) {
    try {
        & $exportToolPath -SummaryPath $bundleSummaryPath -OutputZipPath $bundleZipPath -RootPath $bundleExportRoot | Out-Null
    } catch {
        Add-Failure -Errors $errors -Step 'BundleExport' -Message $_.Exception.Message -FailedStep ([ref]$failedStep) -ActionableError ([ref]$actionableError)
    }
    if (-not (Test-Path -LiteralPath $bundleZipPath)) {
        Add-Failure -Errors $errors -Step 'BundleExport' -Message ("Bundle zip not created at '{0}'." -f $bundleZipPath) -FailedStep ([ref]$failedStep) -ActionableError ([ref]$actionableError)
    }
}

if ($errors.Count -eq 0) {
    try {
        & $validateToolPath -BundleZipPath $bundleZipPath -OutputPath $bundleValidationPath | Out-Null
    } catch {
        Add-Failure -Errors $errors -Step 'BundleValidation' -Message $_.Exception.Message -FailedStep ([ref]$failedStep) -ActionableError ([ref]$actionableError)
    }
    if (-not (Test-Path -LiteralPath $bundleValidationPath)) {
        Add-Failure -Errors $errors -Step 'BundleValidation' -Message ("Bundle validation JSON not created at '{0}'." -f $bundleValidationPath) -FailedStep ([ref]$failedStep) -ActionableError ([ref]$actionableError)
    }
}

if ($errors.Count -eq 0) {
    try {
        $reviewSummary = & $reviewToolPath `
            -BundleZipPath $bundleZipPath `
            -WorkspaceRoot $reviewWorkspaceRoot `
            -Timestamp $Timestamp `
            -OutputSummaryPath $reviewSummaryPath `
            -Overwrite `
            -RunExplorer `
            -PassThru
    } catch {
        Add-Failure -Errors $errors -Step 'BundleReview' -Message $_.Exception.Message -FailedStep ([ref]$failedStep) -ActionableError ([ref]$actionableError)
    }
    if (-not (Test-Path -LiteralPath $reviewSummaryPath)) {
        Add-Failure -Errors $errors -Step 'BundleReview' -Message ("Review summary JSON not created at '{0}'." -f $reviewSummaryPath) -FailedStep ([ref]$failedStep) -ActionableError ([ref]$actionableError)
    }
    if (-not (Test-Path -LiteralPath $reviewExplorerPath)) {
        Add-Failure -Errors $errors -Step 'BundleReview' -Message ("Explorer markdown not created at '{0}'." -f $reviewExplorerPath) -FailedStep ([ref]$failedStep) -ActionableError ([ref]$actionableError)
    }
}

if ($errors.Count -eq 0) {
    try {
        Copy-Item -LiteralPath $diffMarkdownPath -Destination $diffMarkdownOutputPath -Force
        Copy-Item -LiteralPath $reviewSummaryPath -Destination $reviewSummaryOutputPath -Force
        Copy-Item -LiteralPath $reviewExplorerPath -Destination $reviewExplorerOutputPath -Force
    } catch {
        Add-Failure -Errors $errors -Step 'Outputs' -Message $_.Exception.Message -FailedStep ([ref]$failedStep) -ActionableError ([ref]$actionableError)
    }
}

if ($errors.Count -eq 0 -and $reviewSummary) {
    $explorerCommand = $reviewSummary.ExplorerCommand
    $reviewCommand = 'pwsh -NoProfile -File Tools/Invoke-RoutingBundleReview.ps1 -BundleZipPath "{0}" -WorkspaceRoot "{1}" -Timestamp "{2}" -Overwrite -RunExplorer -PassThru' -f $bundleZipPath, $reviewWorkspaceRoot, $Timestamp
    $nextCommands = @($explorerCommand, $reviewCommand) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $summary.NextCommands = @($nextCommands)
}

$summary.Status = if ($errors.Count -eq 0) { 'Pass' } else { 'Fail' }
$summary.FailedStep = $failedStep
$summary.ActionableError = $actionableError

$summaryWriteError = $null
try {
    Ensure-Directory -Path $summaryPath
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
    if ($summary.Status -eq 'Pass' -and $UpdateLatest.IsPresent) {
        Ensure-Directory -Path $summaryLatestPath
        Copy-Item -LiteralPath $summaryPath -Destination $summaryLatestPath -Force
    }
} catch {
    $summaryWriteError = $_.Exception.Message
}

if ($summaryWriteError) {
    throw "Routing offline demo failed to write summary JSON: $summaryWriteError"
}

if ($bundleStagingRoot -and (Test-Path -LiteralPath $bundleStagingRoot)) {
    Remove-Item -LiteralPath $bundleStagingRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($summary.Status -ne 'Pass') {
    if (-not [string]::IsNullOrWhiteSpace($summary.ActionableError)) {
        throw ("Routing offline demo failed at {0}: {1}. See {2}" -f $summary.FailedStep, $summary.ActionableError, $summaryPath)
    }
    throw "Routing offline demo failed. See $summaryPath"
}

if ($PassThru.IsPresent) {
    return $summary
}
