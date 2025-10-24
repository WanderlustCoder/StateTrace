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
    [switch]$ResetExtractedLogs,
    [switch]$PreserveModuleSession,
    [switch]$RunWarmRunRegression,
    [string]$WarmRunRegressionOutputPath
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

function Invoke-WarmRunRegressionInternal {
    $warmRunRegressionScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Invoke-WarmRunRegression.ps1'
    if (-not (Test-Path -LiteralPath $warmRunRegressionScript)) {
        throw "Warm-run regression script not found at $warmRunRegressionScript"
    }

    $pwshCommand = Get-Command -Name 'pwsh' -ErrorAction Stop
    $pwshExecutable = $pwshCommand.Source
    $argumentList = @('-NoLogo','-NoProfile','-File',$warmRunRegressionScript)
    if ($VerboseParsing) {
        $argumentList += '-VerboseParsing'
    }
    if ($ResetExtractedLogs) {
        $argumentList += '-ResetExtractedLogs'
    }
    if (-not [string]::IsNullOrWhiteSpace($WarmRunRegressionOutputPath)) {
        $resolvedOutput = $WarmRunRegressionOutputPath
        try {
            $resolvedOutput = (Resolve-Path -LiteralPath $WarmRunRegressionOutputPath -ErrorAction Stop).Path
        } catch {
            $resolvedOutput = [System.IO.Path]::GetFullPath((Join-Path -Path (Get-Location) -ChildPath $WarmRunRegressionOutputPath))
        }
        $argumentList += @('-OutputPath', $resolvedOutput)
    }

    Write-Host 'Running preserved-session warm-run regression...' -ForegroundColor Cyan
    & $pwshExecutable @argumentList
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Warm-run regression failed with exit code $exitCode."
    }
    Write-Host 'Warm-run regression completed successfully.' -ForegroundColor Green
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
    if ($RunWarmRunRegression) {
        Invoke-WarmRunRegressionInternal
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
    $moduleName = [System.IO.Path]::GetFileNameWithoutExtension($candidatePath)
    $loadedModule = $null
    if (-not [string]::IsNullOrWhiteSpace($moduleName)) {
        $loadedModule = Get-Module -Name $moduleName -ErrorAction SilentlyContinue
    }
    if ($PreserveModuleSession -and $loadedModule) {
        continue
    }
    $importArgs = @{
        Name        = $candidatePath
        ErrorAction = 'Stop'
    }
    if (-not $PreserveModuleSession -or -not $loadedModule) {
        $importArgs['Force'] = $true
    }
    Import-Module @importArgs | Out-Null
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
$parserWorkerName = [System.IO.Path]::GetFileNameWithoutExtension($parserWorkerModule)
$existingParserWorker = $null
if (-not [string]::IsNullOrWhiteSpace($parserWorkerName)) {
    $existingParserWorker = Get-Module -Name $parserWorkerName -ErrorAction SilentlyContinue
}
$module = $null
if ($PreserveModuleSession -and $existingParserWorker) {
    $module = $existingParserWorker
} else {
    $parserImportArgs = @{
        Name        = $parserWorkerModule
        ErrorAction = 'Stop'
        PassThru    = $true
    }
    if (-not $PreserveModuleSession -or -not $existingParserWorker) {
        $parserImportArgs['Force'] = $true
    }
    $module = Import-Module @parserImportArgs
}

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
if ($PreserveModuleSession) {
    $invokeParams['PreserveRunspace'] = $true
}

try {
    if ($VerboseParsing) {
        Invoke-StateTraceParsing @invokeParams -Verbose
    } else {
        Invoke-StateTraceParsing @invokeParams
    }
} finally {
    if ($module -and -not $PreserveModuleSession) {
        Remove-Module -ModuleInfo $module -Force -ErrorAction SilentlyContinue
    }
}

Write-Host 'Ingestion run completed.' -ForegroundColor Green

if ($RunWarmRunRegression) {
    Invoke-WarmRunRegressionInternal
}
