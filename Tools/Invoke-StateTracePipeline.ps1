param(
    [switch]$SkipTests,
    [switch]$SkipParsing,
    [string]$DatabasePath,
    [int]$ThreadCeilingOverride,
    [int]$MaxWorkersPerSiteOverride,
    [int]$MaxActiveSitesOverride,
    [int]$JobsPerThreadOverride,
    [int]$MinRunspacesOverride,
    [switch]$VerboseParsing,
    [switch]$ResetExtractedLogs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$modulesPath = Join-Path -Path $repositoryRoot -ChildPath 'Modules'
$testsPath = Join-Path -Path $modulesPath -ChildPath 'Tests'
$parserWorkerModule = Join-Path -Path $modulesPath -ChildPath 'ParserWorker.psm1'

$pathSeparator = [System.IO.Path]::PathSeparator
$resolvedModulesPath = [System.IO.Path]::GetFullPath($modulesPath)
$modulePathEntries = @()
if ($env:PSModulePath) {
    $modulePathEntries = $env:PSModulePath -split [System.IO.Path]::PathSeparator
}
$alreadyPresent = $false
foreach ($entry in $modulePathEntries) {
    if (-not [string]::IsNullOrWhiteSpace($entry)) {
        $normalizedEntry = [System.IO.Path]::GetFullPath($entry)
        if ([System.StringComparer]::OrdinalIgnoreCase.Equals($normalizedEntry.TrimEnd('\'), $resolvedModulesPath.TrimEnd('\'))) {
            $alreadyPresent = $true
            break
        }
    }
}
if (-not $alreadyPresent) {
    if ([string]::IsNullOrWhiteSpace($env:PSModulePath)) {
        $env:PSModulePath = $resolvedModulesPath
    } else {
        $env:PSModulePath = $resolvedModulesPath + $pathSeparator + $env:PSModulePath
    }
}

if (-not $SkipTests) {
    if (-not (Test-Path -LiteralPath $testsPath)) {
        throw "Pester test directory not found at $testsPath"
    }

    if (-not (Get-Command -Name Invoke-Pester -ErrorAction SilentlyContinue)) {
        throw 'Invoke-Pester is not available in the current session.'
    }

    Write-Host 'Running Pester tests (Modules/Tests)...' -ForegroundColor Cyan
    $pesterResult = Invoke-Pester -Path $testsPath -PassThru
    if ($null -ne $pesterResult -and $pesterResult.FailedCount -gt 0) {
        throw "Pester reported $($pesterResult.FailedCount) failing tests."
    }
    Write-Host 'Pester tests completed successfully.' -ForegroundColor Green
}

if ($SkipParsing) {
    if ($VerboseParsing) {
        Write-Host 'Skipping ingestion run because -SkipParsing was supplied.' -ForegroundColor Yellow
    }
    return
}

# Load modules from manifest so module-qualified calls resolve during ingestion
$manifestPath = Join-Path -Path $modulesPath -ChildPath 'ModulesManifest.psd1'
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Module manifest not found at $manifestPath"
}

if (Get-Command -Name Import-PowerShellDataFile -ErrorAction SilentlyContinue) {
    $manifest = Import-PowerShellDataFile -Path $manifestPath
} else {
    $manifest = . $manifestPath
}

$modulesToImport = @()
if ($manifest -is [hashtable] -and $manifest.ContainsKey('ModulesToImport') -and $manifest['ModulesToImport']) {
    $modulesToImport = $manifest['ModulesToImport']
} elseif ($manifest -is [hashtable] -and $manifest.ContainsKey('Modules') -and $manifest['Modules']) {
    $modulesToImport = $manifest['Modules']
} else {
    throw 'No modules defined in ModulesManifest.psd1.'
}

foreach ($moduleEntry in $modulesToImport) {
    if ([string]::IsNullOrWhiteSpace($moduleEntry)) { continue }
    if ([System.StringComparer]::OrdinalIgnoreCase.Equals($moduleEntry.Trim(), 'ParserWorker.psm1')) { continue }
    $candidatePath = if ([System.IO.Path]::IsPathRooted($moduleEntry)) {
        $moduleEntry
    } else {
        Join-Path -Path $modulesPath -ChildPath $moduleEntry
    }
    if (-not (Test-Path -LiteralPath $candidatePath)) {
        throw "Module entry '$moduleEntry' not found at $candidatePath"
    }
    Import-Module -Name $candidatePath -Force -ErrorAction Stop | Out-Null
}

if (-not (Test-Path -LiteralPath $parserWorkerModule)) {
    throw "ParserWorker module not found at $parserWorkerModule"
}

if ($ResetExtractedLogs) {
    $extractedRoot = Join-Path -Path $repositoryRoot -ChildPath 'Logs'
    $extractedPath = Join-Path -Path $extractedRoot -ChildPath 'Extracted'
    if (Test-Path -LiteralPath $extractedPath) {
        Write-Host "Resetting extracted log slices under ${extractedPath}..." -ForegroundColor Yellow
        try {
            Get-ChildItem -LiteralPath $extractedPath -Force -Recurse | Remove-Item -Force -Recurse
        } catch {
            Write-Warning "Failed to reset extracted logs in ${extractedPath}: $($_.Exception.Message)"
        }
    } elseif ($VerboseParsing) {
        Write-Host "No extracted log directory found at ${extractedPath}; skipping reset." -ForegroundColor Yellow
    }
}
Write-Host 'Starting ingestion run via Invoke-StateTraceParsing -Synchronous...' -ForegroundColor Cyan
$module = Import-Module -Name $parserWorkerModule -PassThru -Force -ErrorAction Stop

$invokeParams = @{ Synchronous = $true }
if ($PSBoundParameters.ContainsKey('DatabasePath')) {
    $invokeParams['DatabasePath'] = $DatabasePath
}
if ($PSBoundParameters.ContainsKey('ThreadCeilingOverride')) {
    $invokeParams['ThreadCeilingOverride'] = $ThreadCeilingOverride
}
if ($PSBoundParameters.ContainsKey('MaxWorkersPerSiteOverride')) {
    $invokeParams['MaxWorkersPerSiteOverride'] = $MaxWorkersPerSiteOverride
}
if ($PSBoundParameters.ContainsKey('MaxActiveSitesOverride')) {
    $invokeParams['MaxActiveSitesOverride'] = $MaxActiveSitesOverride
}
if ($PSBoundParameters.ContainsKey('JobsPerThreadOverride')) {
    $invokeParams['JobsPerThreadOverride'] = $JobsPerThreadOverride
}
if ($PSBoundParameters.ContainsKey('MinRunspacesOverride')) {
    $invokeParams['MinRunspacesOverride'] = $MinRunspacesOverride
}

try {
    if ($VerboseParsing) {
        Invoke-StateTraceParsing @invokeParams -Verbose
    } else {
        Invoke-StateTraceParsing @invokeParams
    }
} finally {
    if ($module) {
        Remove-Module -ModuleInfo $module -Force -ErrorAction SilentlyContinue
    }
}

Write-Host 'Ingestion run completed.' -ForegroundColor Green
