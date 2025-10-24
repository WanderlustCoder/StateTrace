[CmdletBinding()]
param(
    [switch]$SkipTests,
    [switch]$SkipParsing,
    [string]$DatabasePath,
    [Nullable[int]]$ThreadCeilingOverride = $null,
    [Nullable[int]]$MaxWorkersPerSiteOverride = $null,
    [Nullable[int]]$MaxActiveSitesOverride = $null,
    [Nullable[int]]$JobsPerThreadOverride = $null,
    [Nullable[int]]$MinRunspacesOverride = $null,
    [switch]$VerboseParsing,
    [switch]$ResetExtractedLogs,
    [switch]$PreserveModuleSession,
    [switch]$SkipWarmRunRegression,
    [string]$WarmRunTelemetryDirectory,
    [string]$WarmRunRegressionOutputPath,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$pipelineScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Invoke-StateTracePipeline.ps1'
if (-not (Test-Path -LiteralPath $pipelineScript)) {
    throw "Pipeline harness not found at $pipelineScript."
}

$pipelineParameters = @{}

if ($SkipTests.IsPresent) { $pipelineParameters['SkipTests'] = $true }
if ($SkipParsing.IsPresent) { $pipelineParameters['SkipParsing'] = $true }

function Resolve-OptionalPath {
    param([string]$PathValue)
    if ([string]::IsNullOrWhiteSpace($PathValue)) { return $null }
    try {
        $resolved = (Resolve-Path -LiteralPath $PathValue -ErrorAction Stop).Path
        return $resolved
    } catch {
        return [System.IO.Path]::GetFullPath((Join-Path -Path (Get-Location) -ChildPath $PathValue))
    }
}

$resolvedDatabasePath = Resolve-OptionalPath -PathValue $DatabasePath
if ($resolvedDatabasePath) {
    $pipelineParameters['DatabasePath'] = $resolvedDatabasePath
}

function Set-NumericParameter {
    param([string]$Name, [Nullable[int]]$Value)
    if ($Value -ne $null) {
        $pipelineParameters[$Name] = [int]$Value
    }
}

Set-NumericParameter -Name 'ThreadCeilingOverride' -Value $ThreadCeilingOverride
Set-NumericParameter -Name 'MaxWorkersPerSiteOverride' -Value $MaxWorkersPerSiteOverride
Set-NumericParameter -Name 'MaxActiveSitesOverride' -Value $MaxActiveSitesOverride
Set-NumericParameter -Name 'JobsPerThreadOverride' -Value $JobsPerThreadOverride
Set-NumericParameter -Name 'MinRunspacesOverride' -Value $MinRunspacesOverride

if ($VerboseParsing.IsPresent) { $pipelineParameters['VerboseParsing'] = $true }
if ($ResetExtractedLogs.IsPresent) { $pipelineParameters['ResetExtractedLogs'] = $true }
if ($PreserveModuleSession.IsPresent) { $pipelineParameters['PreserveModuleSession'] = $true }

$computedWarmRunPath = $null
if (-not $SkipWarmRunRegression.IsPresent) {
    $pipelineParameters['RunWarmRunRegression'] = $true

    $targetPath = $WarmRunRegressionOutputPath
    if ([string]::IsNullOrWhiteSpace($targetPath)) {
        $telemetryDir = $WarmRunTelemetryDirectory
        if ([string]::IsNullOrWhiteSpace($telemetryDir)) {
            $telemetryDir = Join-Path -Path $repositoryRoot -ChildPath 'Logs\IngestionMetrics'
        } else {
            $telemetryDir = Resolve-OptionalPath -PathValue $telemetryDir
        }
        if (-not (Test-Path -LiteralPath $telemetryDir)) {
            New-Item -ItemType Directory -Path $telemetryDir -Force | Out-Null
        }
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $targetPath = Join-Path -Path $telemetryDir -ChildPath ("WarmRunTelemetry-{0}.json" -f $timestamp)
    } else {
        $targetPath = Resolve-OptionalPath -PathValue $targetPath
        $targetDirectory = Split-Path -Path $targetPath -Parent
        if (-not [string]::IsNullOrWhiteSpace($targetDirectory) -and -not (Test-Path -LiteralPath $targetDirectory)) {
            New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
        }
    }

    $computedWarmRunPath = $targetPath
    $relativeOutput = $targetPath
    try {
        $candidate = [System.IO.Path]::GetRelativePath($repositoryRoot, $targetPath)
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and -not $candidate.StartsWith('..')) {
            $relativeOutput = $candidate
        }
    } catch {
        $relativeOutput = $targetPath
    }
    $pipelineParameters['WarmRunRegressionOutputPath'] = $relativeOutput
}

$argumentPreview = @()
foreach ($entry in $pipelineParameters.GetEnumerator()) {
    if ($entry.Value -is [bool]) {
        if ($entry.Value) {
            $argumentPreview += ("-{0}" -f $entry.Key)
        }
    } else {
        $argumentPreview += ("-{0}={1}" -f $entry.Key, $entry.Value)
    }
}

if ($argumentPreview.Count -gt 0) {
    Write-Host ("Pipeline arguments: {0}" -f ($argumentPreview -join ' ')) -ForegroundColor DarkGray
} else {
    Write-Host 'Pipeline arguments: (none)' -ForegroundColor DarkGray
}
Write-Host 'Starting StateTrace verification pipeline...' -ForegroundColor Cyan
try {
    & $pipelineScript @pipelineParameters
} catch {
    Write-Host 'StateTrace verification pipeline failed.' -ForegroundColor Red
    throw
}

Write-Host 'StateTrace verification pipeline completed successfully.' -ForegroundColor Green
if ($computedWarmRunPath) {
    Write-Host ("Warm-run regression telemetry stored at {0}" -f $computedWarmRunPath) -ForegroundColor DarkYellow
}

if ($PassThru.IsPresent) {
    [pscustomobject]@{
        WarmRunTelemetryPath = $computedWarmRunPath
        Parameters           = $pipelineParameters
    }
}
