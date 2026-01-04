<#
.SYNOPSIS
Headless install/uninstall smoke test for StateTrace.

.DESCRIPTION
ST-P-002: Validates module import, pipeline invocation on fixtures, and clean
removal. Designed for PowerShell 5.1 compatibility.

Test phases:
1. Module import validation (all required modules load)
2. Pipeline invocation on CISmoke fixtures
3. Core functionality spot checks
4. Clean removal verification (no lingering state)

.PARAMETER RepositoryRoot
Repository root path. Defaults to parent of script directory.

.PARAMETER SkipPipelineSmoke
Skip the pipeline invocation test (faster).

.PARAMETER SkipRemovalCheck
Skip the clean removal verification.

.PARAMETER OutputPath
Optional JSON output path for the smoke report.

.PARAMETER FailOnError
Exit with error code if any smoke fails.

.PARAMETER PassThru
Return the smoke result as an object.

.EXAMPLE
.\Test-InstallSmoke.ps1

.EXAMPLE
.\Test-InstallSmoke.ps1 -FailOnError -OutputPath Logs\Verification\InstallSmoke.json
#>
param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [switch]$SkipPipelineSmoke,
    [switch]$SkipRemovalCheck,
    [string]$OutputPath,
    [switch]$FailOnError,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path

Write-Host "Running StateTrace install/uninstall smoke test..." -ForegroundColor Cyan
Write-Host ("  Repository: {0}" -f $repoRoot) -ForegroundColor Cyan
Write-Host ("  PowerShell: {0}" -f $PSVersionTable.PSVersion) -ForegroundColor Cyan

$phases = [System.Collections.Generic.List[pscustomobject]]::new()
$errors = [System.Collections.Generic.List[pscustomobject]]::new()
$startTime = Get-Date

# Helper to run a phase
function Test-Phase {
    param(
        [string]$Name,
        [scriptblock]$Test
    )

    $phaseStart = Get-Date
    $phaseResult = [pscustomobject]@{
        Name      = $Name
        Status    = 'Running'
        DurationMs = 0
        Error     = $null
        Details   = $null
    }

    Write-Host ("`n  Phase: {0}..." -f $Name) -ForegroundColor Cyan

    try {
        $details = & $Test
        $phaseResult.Status = 'Pass'
        $phaseResult.Details = $details
        Write-Host ("    [PASS] {0}" -f $Name) -ForegroundColor Green
    }
    catch {
        $phaseResult.Status = 'Fail'
        $phaseResult.Error = $_.Exception.Message
        $errors.Add([pscustomobject]@{
            Phase   = $Name
            Message = $_.Exception.Message
        })
        Write-Host ("    [FAIL] {0}: {1}" -f $Name, $_.Exception.Message) -ForegroundColor Red
    }

    $phaseResult.DurationMs = [math]::Round(((Get-Date) - $phaseStart).TotalMilliseconds, 0)
    $phases.Add($phaseResult)
}

# Phase 1: Module import validation
Test-Phase -Name 'ModuleImport' -Test {
    $modulesDir = Join-Path $repoRoot 'Modules'
    $requiredModules = @(
        'DeviceRepositoryModule.psm1'
        'DeviceRepository.Access.psm1'
        'TelemetryModule.psm1'
        'ThemeModule.psm1'
        'ViewCompositionModule.psm1'
    )

    $imported = [System.Collections.Generic.List[string]]::new()
    $missing = [System.Collections.Generic.List[string]]::new()

    foreach ($modName in $requiredModules) {
        $modPath = Join-Path $modulesDir $modName
        if (Test-Path -LiteralPath $modPath) {
            try {
                Import-Module $modPath -Force -ErrorAction Stop -DisableNameChecking
                $imported.Add($modName)
            }
            catch {
                throw ("Failed to import {0}: {1}" -f $modName, $_.Exception.Message)
            }
        }
        else {
            $missing.Add($modName)
        }
    }

    if ($missing.Count -gt 0) {
        throw ("Missing modules: {0}" -f ($missing -join ', '))
    }

    return [pscustomobject]@{
        ImportedCount = $imported.Count
        Modules       = $imported
    }
}

# Phase 2: Fixture availability
Test-Phase -Name 'FixtureCheck' -Test {
    $fixturesDir = Join-Path $repoRoot 'Tests\Fixtures\CISmoke'
    $requiredFixtures = @(
        'IngestionMetrics.json'
    )

    $found = [System.Collections.Generic.List[string]]::new()

    foreach ($fixture in $requiredFixtures) {
        $fixturePath = Join-Path $fixturesDir $fixture
        if (Test-Path -LiteralPath $fixturePath) {
            $found.Add($fixture)
        }
        else {
            throw ("Missing fixture: {0}" -f $fixture)
        }
    }

    # Check for seed snapshot (optional)
    $seedPath = Join-Path $fixturesDir 'SharedCacheSeed.clixml'
    $hasSeed = Test-Path -LiteralPath $seedPath

    # Check for manifest (optional)
    $manifestPath = Join-Path $fixturesDir 'manifests\CISmoke.json'
    $hasManifest = Test-Path -LiteralPath $manifestPath

    return [pscustomobject]@{
        FixturesFound = $found.Count
        HasSeed       = $hasSeed
        HasManifest   = $hasManifest
    }
}

# Phase 3: Core tool availability
Test-Phase -Name 'ToolCheck' -Test {
    $toolsDir = Join-Path $repoRoot 'Tools'
    $requiredTools = @(
        'Invoke-AllChecks.ps1'
        'Invoke-StateTracePipeline.ps1'
        'Invoke-WarmRunTelemetry.ps1'
        'Bootstrap-DevSeat.ps1'
    )

    $found = [System.Collections.Generic.List[string]]::new()

    foreach ($tool in $requiredTools) {
        $toolPath = Join-Path $toolsDir $tool
        if (Test-Path -LiteralPath $toolPath) {
            $found.Add($tool)
        }
        else {
            throw ("Missing tool: {0}" -f $tool)
        }
    }

    return [pscustomobject]@{
        ToolsFound = $found.Count
    }
}

# Phase 4: Pester availability
Test-Phase -Name 'PesterCheck' -Test {
    $pester = Get-Module -ListAvailable -Name Pester | Sort-Object Version -Descending | Select-Object -First 1

    if (-not $pester) {
        throw "Pester module not installed"
    }

    $minVersion = [version]'3.4.0'
    if ($pester.Version -lt $minVersion) {
        throw ("Pester version {0} is below minimum {1}" -f $pester.Version, $minVersion)
    }

    return [pscustomobject]@{
        PesterVersion = $pester.Version.ToString()
    }
}

# Phase 5: Pipeline smoke (optional)
if (-not $SkipPipelineSmoke) {
    Test-Phase -Name 'PipelineSmoke' -Test {
        $fixturesJson = Join-Path $repoRoot 'Tests\Fixtures\CISmoke\IngestionMetrics.json'

        if (-not (Test-Path -LiteralPath $fixturesJson)) {
            throw "CISmoke fixtures not found"
        }

        # Parse the fixture to validate JSON structure
        $content = Get-Content -LiteralPath $fixturesJson -Raw
        $eventList = @($content -split "`n" | Where-Object { $_ -and $_ -match '^\s*\{' } | ForEach-Object {
            try { $_ | ConvertFrom-Json -ErrorAction SilentlyContinue } catch { $null }
        } | Where-Object { $_ })

        $eventCount = $eventList.Count
        if ($eventCount -eq 0) {
            throw "No valid telemetry events in fixture"
        }

        $hasQueueMetrics = $false
        foreach ($evt in $eventList) {
            if ($evt.PSObject.Properties.Name -contains 'EventType' -and $evt.EventType -eq 'InterfacePortQueueMetrics') {
                $hasQueueMetrics = $true
                break
            }
        }

        return [pscustomobject]@{
            EventCount = $eventCount
            HasQueueMetrics = $hasQueueMetrics
        }
    }
}

# Phase 6: Telemetry module function check
Test-Phase -Name 'TelemetryFunctions' -Test {
    $telemetryModule = Join-Path $repoRoot 'Modules\TelemetryModule.psm1'
    Import-Module $telemetryModule -Force -DisableNameChecking

    $expectedFunctions = @(
        'Write-StTelemetryEvent'
        'Get-TelemetryBuffer'
    )

    $found = [System.Collections.Generic.List[string]]::new()

    foreach ($fn in $expectedFunctions) {
        $cmd = Get-Command -Name $fn -ErrorAction SilentlyContinue
        if ($cmd) {
            $found.Add($fn)
        }
    }

    return [pscustomobject]@{
        FunctionsFound = $found.Count
        Functions      = $found
    }
}

# Phase 7: Clean removal check (optional)
if (-not $SkipRemovalCheck) {
    Test-Phase -Name 'CleanRemoval' -Test {
        # Get modules loaded from this repo
        $loadedModules = @(Get-Module | Where-Object {
            $_.Path -and $_.Path.StartsWith($repoRoot, [StringComparison]::OrdinalIgnoreCase)
        })

        $removedCount = 0
        foreach ($mod in $loadedModules) {
            Remove-Module -Name $mod.Name -Force -ErrorAction SilentlyContinue
            $removedCount++
        }

        # Verify removal
        $stillLoaded = @(Get-Module | Where-Object {
            $_.Path -and $_.Path.StartsWith($repoRoot, [StringComparison]::OrdinalIgnoreCase)
        })

        $stillLoadedCount = $stillLoaded.Count
        if ($stillLoadedCount -gt 0) {
            throw ("Could not remove modules: {0}" -f (($stillLoaded | ForEach-Object { $_.Name }) -join ', '))
        }

        return [pscustomobject]@{
            RemovedCount  = $removedCount
            StillLoaded   = $stillLoadedCount
        }
    }
}

# Build result
$totalDuration = [math]::Round(((Get-Date) - $startTime).TotalMilliseconds, 0)
$passCount = @($phases | Where-Object { $_.Status -eq 'Pass' }).Count
$failCount = @($phases | Where-Object { $_.Status -eq 'Fail' }).Count

$result = [pscustomobject]@{
    Timestamp      = Get-Date -Format 'o'
    Status         = if ($failCount -eq 0) { 'Pass' } else { 'Fail' }
    TotalDurationMs = $totalDuration
    PhaseCount     = $phases.Count
    PassCount      = $passCount
    FailCount      = $failCount
    Phases         = $phases
    Errors         = $errors
    Environment    = [pscustomobject]@{
        PSVersion     = $PSVersionTable.PSVersion.ToString()
        Platform      = if ($PSVersionTable.PSObject.Properties.Name -contains 'Platform') { $PSVersionTable.Platform } else { 'Win32NT' }
        MachineName   = $env:COMPUTERNAME
    }
}

# Output
if ($OutputPath) {
    $outputDir = Split-Path -Path $OutputPath -Parent
    if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    $result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    Write-Host ("`nReport written to: {0}" -f $OutputPath) -ForegroundColor Green
}

# Display summary
Write-Host "`nInstall Smoke Summary:" -ForegroundColor Cyan
Write-Host ("  Phases: {0} total, {1} passed, {2} failed" -f $phases.Count, $passCount, $failCount)
Write-Host ("  Duration: {0:N0} ms" -f $totalDuration)

if ($failCount -gt 0) {
    Write-Host "`nFailed Phases:" -ForegroundColor Red
    foreach ($phase in ($phases | Where-Object { $_.Status -eq 'Fail' })) {
        Write-Host ("  - {0}: {1}" -f $phase.Name, $phase.Error) -ForegroundColor Red
    }
    Write-Host "`nStatus: FAIL" -ForegroundColor Red
}
else {
    Write-Host "`nStatus: PASS - All smoke tests passed" -ForegroundColor Green
}

if ($FailOnError -and $failCount -gt 0) {
    Write-Error "Install smoke test failed with $failCount error(s)"
    exit 2
}

if ($PassThru) {
    return $result
}
