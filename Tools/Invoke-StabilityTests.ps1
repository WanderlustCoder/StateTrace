<#
.SYNOPSIS
Runs stability tests for CI/CD pipelines.

.DESCRIPTION
Executes fixture validation, telemetry validation, and optional
memory/handle leak tests. Designed for scheduled CI runs.

.PARAMETER Mode
Test mode: Quick (5 min), Standard (1 hour), Extended (24 hours)

.PARAMETER OutputPath
Path for test results.

.PARAMETER FailOnWarnings
Treat warnings as failures.

.EXAMPLE
.\Invoke-StabilityTests.ps1 -Mode Quick

.EXAMPLE
.\Invoke-StabilityTests.ps1 -Mode Extended -OutputPath .\Results
#>

[CmdletBinding()]
param(
    [ValidateSet('Quick', 'Standard', 'Extended')]
    [string]$Mode = 'Quick',

    [string]$OutputPath,

    [switch]$FailOnWarnings
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$projectRoot = Split-Path -Parent $PSScriptRoot

# Import modules
Import-Module (Join-Path $projectRoot 'Modules\StabilityTestModule.psm1') -Force

if (-not $OutputPath) {
    $OutputPath = Join-Path $projectRoot "Logs\StabilityTests\CI-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
}

if (-not (Test-Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

$overallResult = @{
    Mode = $Mode
    StartTime = [datetime]::UtcNow.ToString('o')
    OutputPath = $OutputPath
    Tests = @{}
    OverallStatus = 'Unknown'
    FailureCount = 0
    WarningCount = 0
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  StateTrace Stability Tests" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Mode: $Mode"
Write-Host "Output: $OutputPath`n"

#region Test 1: Fixture Freshness

Write-Host "[1/5] Testing fixture freshness..." -ForegroundColor Yellow

try {
    $freshnessResult = Test-FixtureFreshness -MaxAgeDays 90
    $overallResult.Tests['FixtureFreshness'] = $freshnessResult

    if ($freshnessResult.Status -eq 'Pass') {
        Write-Host "  PASS: $($freshnessResult.FreshFixtures)/$($freshnessResult.TotalFixtures) fixtures are fresh" -ForegroundColor Green
    } elseif ($freshnessResult.Status -eq 'Warning') {
        Write-Host "  WARNING: $($freshnessResult.StaleFixtures) stale fixtures (>90 days old)" -ForegroundColor Yellow
        $overallResult.WarningCount++
    } else {
        Write-Host "  FAIL: Too many stale fixtures ($($freshnessResult.FreshnessPercent)% fresh)" -ForegroundColor Red
        $overallResult.FailureCount++
    }
} catch {
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    $overallResult.FailureCount++
}

#endregion

#region Test 2: Fixture Schema Compliance

Write-Host "[2/5] Testing fixture schema compliance..." -ForegroundColor Yellow

try {
    $schemaResult = Test-FixtureSchemaCompliance
    $overallResult.Tests['FixtureSchema'] = $schemaResult

    if ($schemaResult.Status -eq 'Pass') {
        Write-Host "  PASS: All $($schemaResult.TotalChecked) fixtures are valid" -ForegroundColor Green
    } else {
        Write-Host "  FAIL: $($schemaResult.Failed) invalid fixtures" -ForegroundColor Red
        $overallResult.FailureCount++
    }
} catch {
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    $overallResult.FailureCount++
}

#endregion

#region Test 3: Telemetry Field Validation

Write-Host "[3/5] Validating telemetry fields..." -ForegroundColor Yellow

try {
    $telemetryResult = Test-TelemetryFields -Last 500
    $overallResult.Tests['TelemetryFields'] = $telemetryResult

    if ($telemetryResult.Status -eq 'Pass') {
        Write-Host "  PASS: $($telemetryResult.ValidationRate)% validation rate" -ForegroundColor Green
    } elseif ($telemetryResult.Status -eq 'Warning') {
        Write-Host "  WARNING: $($telemetryResult.ValidationRate)% validation rate" -ForegroundColor Yellow
        $overallResult.WarningCount++
    } else {
        Write-Host "  FAIL: Only $($telemetryResult.ValidationRate)% valid events" -ForegroundColor Red
        $overallResult.FailureCount++
    }
} catch {
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    $overallResult.FailureCount++
}

#endregion

#region Test 4: Memory Leak Detection

Write-Host "[4/5] Testing for memory leaks..." -ForegroundColor Yellow

$memoryDuration = switch ($Mode) {
    'Quick' { 2 }
    'Standard' { 15 }
    'Extended' { 60 }
}

try {
    $memoryResult = Test-MemoryLeak -DurationMinutes $memoryDuration -SampleIntervalSeconds 30
    $overallResult.Tests['MemoryLeak'] = @{
        LeakDetected = $memoryResult.LeakDetected
        GrowthPercent = $memoryResult.GrowthPercent
        BaselineMB = $memoryResult.BaselineMemoryMB
        FinalMB = $memoryResult.FinalMemoryMB
    }

    if (-not $memoryResult.LeakDetected) {
        Write-Host "  PASS: No significant memory leak (Growth: $($memoryResult.GrowthPercent)%)" -ForegroundColor Green
    } else {
        Write-Host "  WARNING: Potential memory leak detected (Growth: $($memoryResult.GrowthPercent)%)" -ForegroundColor Yellow
        $overallResult.WarningCount++
    }
} catch {
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    $overallResult.WarningCount++
}

#endregion

#region Test 5: Handle Leak Detection

Write-Host "[5/5] Testing for handle leaks..." -ForegroundColor Yellow

try {
    $handleResult = Test-HandleLeak -DurationMinutes $memoryDuration -SampleIntervalSeconds 30
    $overallResult.Tests['HandleLeak'] = @{
        LeakDetected = $handleResult.LeakDetected
        GrowthPercent = $handleResult.GrowthPercent
        BaselineHandles = $handleResult.BaselineHandles
        FinalHandles = $handleResult.FinalHandles
    }

    if (-not $handleResult.LeakDetected) {
        Write-Host "  PASS: No significant handle leak (Growth: $($handleResult.GrowthPercent)%)" -ForegroundColor Green
    } else {
        Write-Host "  WARNING: Potential handle leak detected (Growth: $($handleResult.GrowthPercent)%)" -ForegroundColor Yellow
        $overallResult.WarningCount++
    }
} catch {
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    $overallResult.WarningCount++
}

#endregion

#region Summary

$overallResult.EndTime = [datetime]::UtcNow.ToString('o')

if ($FailOnWarnings) {
    $overallResult.OverallStatus = if ($overallResult.FailureCount -eq 0 -and $overallResult.WarningCount -eq 0) { 'Pass' } else { 'Fail' }
} else {
    $overallResult.OverallStatus = if ($overallResult.FailureCount -eq 0) { 'Pass' } else { 'Fail' }
}

# Save report
$reportPath = Join-Path $OutputPath 'StabilityTestReport.json'
$overallResult | ConvertTo-Json -Depth 10 | Set-Content -Path $reportPath -Encoding UTF8

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Status: $($overallResult.OverallStatus)" -ForegroundColor $(if ($overallResult.OverallStatus -eq 'Pass') { 'Green' } else { 'Red' })
Write-Host "Failures: $($overallResult.FailureCount)"
Write-Host "Warnings: $($overallResult.WarningCount)"
Write-Host "Report: $reportPath`n"

# Exit with appropriate code
if ($overallResult.OverallStatus -eq 'Pass') {
    exit 0
} else {
    exit 1
}

#endregion
