<#
.SYNOPSIS
Runs daily fleet health checks with configurable thresholds.

.DESCRIPTION
Executes comprehensive health checks across fleet devices, databases,
and telemetry. Outputs results to file and optionally sends alerts.

.PARAMETER OutputPath
Path for health check results.

.PARAMETER Sites
Specific sites to check. If not specified, checks all sites.

.PARAMETER FailOnWarnings
Treat warnings as failures (exit code 1).

.PARAMETER SendAlerts
Send email alerts on failures.

.PARAMETER AlertEmail
Email address for alerts.

.EXAMPLE
.\Invoke-DailyHealthCheck.ps1

.EXAMPLE
.\Invoke-DailyHealthCheck.ps1 -Sites WLLS,BOYO -FailOnWarnings
#>

[CmdletBinding()]
param(
    [string]$OutputPath,

    [string[]]$Sites,

    [switch]$FailOnWarnings,

    [switch]$SendAlerts,

    [string]$AlertEmail,

    [switch]$IncludeDetails
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$projectRoot = Split-Path -Parent $PSScriptRoot

# Import modules
Import-Module (Join-Path $projectRoot 'Modules\FleetHealthModule.psm1') -Force

# Try to import optional modules
$optionalModules = @(
    'DatabaseConcurrencyModule',
    'TelemetrySchemaModule',
    'StabilityTestModule'
)

foreach ($mod in $optionalModules) {
    $modPath = Join-Path $projectRoot "Modules\$mod.psm1"
    if (Test-Path $modPath) {
        Import-Module $modPath -Force -ErrorAction SilentlyContinue
    }
}

if (-not $OutputPath) {
    $OutputPath = Join-Path $projectRoot "Logs\HealthChecks\$(Get-Date -Format 'yyyy-MM-dd')"
}

if (-not (Test-Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  StateTrace Daily Health Check" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "Output: $OutputPath`n"

#region Run Health Checks

$results = @{
    Timestamp = [datetime]::UtcNow.ToString('o')
    Hostname = $env:COMPUTERNAME
    Checks = @()
    Summary = @{
        Total = 0
        Passed = 0
        Warning = 0
        Critical = 0
    }
    OverallStatus = 'Unknown'
}

# 1. Fleet Health Summary
Write-Host "[1/4] Running fleet health check..." -ForegroundColor Yellow

try {
    $fleetHealth = Invoke-FleetHealthCheck -Sites $Sites -IncludeDetails:$IncludeDetails
    $results.Checks += @{
        Name = 'FleetHealth'
        Status = $fleetHealth.OverallStatus
        Duration = 0
        Details = $fleetHealth
    }

    $statusColor = switch ($fleetHealth.OverallStatus) {
        'Healthy' { 'Green' }
        'Warning' { 'Yellow' }
        'Critical' { 'Red' }
        default { 'Gray' }
    }
    Write-Host "  Status: $($fleetHealth.OverallStatus)" -ForegroundColor $statusColor
    Write-Host "  Checks: $($fleetHealth.Summary.Passed) passed, $($fleetHealth.Summary.Warning) warnings, $($fleetHealth.Summary.Critical) critical"

    $results.Summary.Total++
    switch ($fleetHealth.OverallStatus) {
        'Healthy' { $results.Summary.Passed++ }
        'Warning' { $results.Summary.Warning++ }
        'Critical' { $results.Summary.Critical++ }
    }
} catch {
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    $results.Checks += @{
        Name = 'FleetHealth'
        Status = 'Error'
        Error = $_.Exception.Message
    }
    $results.Summary.Critical++
    $results.Summary.Total++
}

# 2. Database Integrity
Write-Host "[2/4] Checking database integrity..." -ForegroundColor Yellow

try {
    $dataPath = Join-Path $projectRoot 'Data'
    $databases = Get-ChildItem -Path $dataPath -Filter '*.accdb' -Recurse -ErrorAction SilentlyContinue

    $dbResults = @{
        TotalDatabases = @($databases).Count
        HealthyDatabases = 0
        UnhealthyDatabases = 0
        Details = @()
    }

    foreach ($db in $databases) {
        $dbHealth = @{ Path = $db.FullName; Status = 'Unknown' }

        if (Get-Command -Name 'Test-DatabaseHealth' -ErrorAction SilentlyContinue) {
            $health = Test-DatabaseHealth -DatabasePath $db.FullName -ErrorAction SilentlyContinue
            if ($health.Healthy) {
                $dbHealth.Status = 'Healthy'
                $dbResults.HealthyDatabases++
            } else {
                $dbHealth.Status = 'Unhealthy'
                $dbHealth.Errors = $health.Errors
                $dbResults.UnhealthyDatabases++
            }
        } else {
            $dbHealth.Status = 'Skipped'
        }

        $dbResults.Details += $dbHealth
    }

    $dbStatus = if ($dbResults.UnhealthyDatabases -gt 0) { 'Warning' } else { 'Healthy' }
    $results.Checks += @{
        Name = 'DatabaseIntegrity'
        Status = $dbStatus
        Details = $dbResults
    }

    Write-Host "  Databases: $($dbResults.HealthyDatabases)/$($dbResults.TotalDatabases) healthy" -ForegroundColor $(if ($dbStatus -eq 'Healthy') { 'Green' } else { 'Yellow' })

    $results.Summary.Total++
    if ($dbStatus -eq 'Healthy') { $results.Summary.Passed++ } else { $results.Summary.Warning++ }
} catch {
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    $results.Checks += @{
        Name = 'DatabaseIntegrity'
        Status = 'Error'
        Error = $_.Exception.Message
    }
    $results.Summary.Warning++
    $results.Summary.Total++
}

# 3. Telemetry Validation
Write-Host "[3/4] Validating telemetry..." -ForegroundColor Yellow

try {
    $telemetryDir = Join-Path $projectRoot 'Logs\IngestionMetrics'
    $recentFiles = Get-ChildItem -Path $telemetryDir -Filter '*.json' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 3

    $telemetryResults = @{
        FilesChecked = @($recentFiles).Count
        TotalEvents = 0
        ValidEvents = 0
        ValidationRate = 0
    }

    if (Get-Command -Name 'Test-TelemetryFile' -ErrorAction SilentlyContinue) {
        foreach ($file in $recentFiles) {
            $validation = Test-TelemetryFile -Path $file.FullName -ErrorAction SilentlyContinue
            $telemetryResults.TotalEvents += $validation.TotalEvents
            $telemetryResults.ValidEvents += $validation.ValidEvents
        }

        if ($telemetryResults.TotalEvents -gt 0) {
            $telemetryResults.ValidationRate = [math]::Round(($telemetryResults.ValidEvents / $telemetryResults.TotalEvents) * 100, 2)
        }
    }

    $telemetryStatus = if ($telemetryResults.ValidationRate -ge 95) { 'Healthy' }
        elseif ($telemetryResults.ValidationRate -ge 80) { 'Warning' }
        else { 'Critical' }

    $results.Checks += @{
        Name = 'TelemetryValidation'
        Status = $telemetryStatus
        Details = $telemetryResults
    }

    Write-Host "  Validation rate: $($telemetryResults.ValidationRate)% ($($telemetryResults.TotalEvents) events)" -ForegroundColor $(
        switch ($telemetryStatus) { 'Healthy' { 'Green' } 'Warning' { 'Yellow' } default { 'Red' } }
    )

    $results.Summary.Total++
    switch ($telemetryStatus) {
        'Healthy' { $results.Summary.Passed++ }
        'Warning' { $results.Summary.Warning++ }
        'Critical' { $results.Summary.Critical++ }
    }
} catch {
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    $results.Checks += @{
        Name = 'TelemetryValidation'
        Status = 'Error'
        Error = $_.Exception.Message
    }
    $results.Summary.Warning++
    $results.Summary.Total++
}

# 4. Fixture Freshness
Write-Host "[4/4] Checking fixture freshness..." -ForegroundColor Yellow

try {
    $fixturesPath = Join-Path $projectRoot 'Tests\Fixtures'

    if (Get-Command -Name 'Test-FixtureFreshness' -ErrorAction SilentlyContinue) {
        $freshness = Test-FixtureFreshness -FixturePath $fixturesPath -ErrorAction SilentlyContinue

        $results.Checks += @{
            Name = 'FixtureFreshness'
            Status = $freshness.Status
            Details = @{
                TotalFixtures = $freshness.TotalFixtures
                FreshFixtures = $freshness.FreshFixtures
                StaleFixtures = $freshness.StaleFixtures
                FreshnessPercent = $freshness.FreshnessPercent
            }
        }

        Write-Host "  Freshness: $($freshness.FreshnessPercent)% ($($freshness.FreshFixtures)/$($freshness.TotalFixtures) fresh)" -ForegroundColor $(
            switch ($freshness.Status) { 'Pass' { 'Green' } 'Warning' { 'Yellow' } default { 'Red' } }
        )

        $results.Summary.Total++
        switch ($freshness.Status) {
            'Pass' { $results.Summary.Passed++ }
            'Warning' { $results.Summary.Warning++ }
            'Fail' { $results.Summary.Critical++ }
        }
    } else {
        Write-Host "  Skipped (StabilityTestModule not loaded)" -ForegroundColor Gray
        $results.Checks += @{
            Name = 'FixtureFreshness'
            Status = 'Skipped'
        }
    }
} catch {
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    $results.Checks += @{
        Name = 'FixtureFreshness'
        Status = 'Error'
        Error = $_.Exception.Message
    }
    $results.Summary.Warning++
    $results.Summary.Total++
}

#endregion

#region Determine Overall Status

if ($results.Summary.Critical -gt 0) {
    $results.OverallStatus = 'Critical'
} elseif ($results.Summary.Warning -gt 0) {
    $results.OverallStatus = 'Warning'
} else {
    $results.OverallStatus = 'Healthy'
}

#endregion

#region Save Results

$reportPath = Join-Path $OutputPath 'HealthCheckReport.json'
$results | ConvertTo-Json -Depth 10 | Set-Content -Path $reportPath -Encoding UTF8

# Generate markdown summary
$mdReport = @"
# Daily Health Check Report

**Generated:** $($results.Timestamp)
**Host:** $($results.Hostname)
**Status:** $($results.OverallStatus)

---

## Summary

| Metric | Value |
|--------|-------|
| Total Checks | $($results.Summary.Total) |
| Passed | $($results.Summary.Passed) |
| Warnings | $($results.Summary.Warning) |
| Critical | $($results.Summary.Critical) |

---

## Check Details

"@

foreach ($check in $results.Checks) {
    $mdReport += "### $($check.Name)`n"
    $mdReport += "**Status:** $($check.Status)`n`n"
    if ($check.Error) {
        $mdReport += "**Error:** $($check.Error)`n`n"
    }
}

$mdPath = Join-Path $OutputPath 'HealthCheckReport.md'
$mdReport | Set-Content -Path $mdPath -Encoding UTF8

#endregion

#region Output Summary

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Health Check Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$statusColor = switch ($results.OverallStatus) {
    'Healthy' { 'Green' }
    'Warning' { 'Yellow' }
    'Critical' { 'Red' }
    default { 'Gray' }
}

Write-Host "Status: $($results.OverallStatus)" -ForegroundColor $statusColor
Write-Host "Passed: $($results.Summary.Passed)/$($results.Summary.Total)"
Write-Host "Warnings: $($results.Summary.Warning)"
Write-Host "Critical: $($results.Summary.Critical)"
Write-Host "Report: $reportPath`n"

#endregion

#region Send Alerts

if ($SendAlerts -and $results.OverallStatus -ne 'Healthy') {
    if ($AlertEmail) {
        Write-Host "Alert notifications configured but email sending not implemented" -ForegroundColor Yellow
        # Future: Send-MailMessage or webhook integration
    }
}

#endregion

#region Exit Code

if ($results.OverallStatus -eq 'Critical') {
    exit 2
} elseif ($results.OverallStatus -eq 'Warning' -and $FailOnWarnings) {
    exit 1
} else {
    exit 0
}

#endregion
