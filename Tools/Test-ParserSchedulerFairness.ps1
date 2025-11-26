[CmdletBinding()]
param(
    [string]$ReportPath,
    [string]$MetricsPath,
    [int]$MaxAllowedStreak = 8,
    [switch]$ThrowOnViolation,
    [switch]$PassThru
)

<#
.SYNOPSIS
Validates parser scheduler fairness by inspecting ParserSchedulerLaunch analyzer output.

.DESCRIPTION
Reads a ParserSchedulerLaunch report (JSON produced by Tools\Analyze-ParserSchedulerLaunch.ps1) and verifies that
no site exceeded the configured MaxAllowedStreak. Optionally regenerates the report on the fly when only a metrics
file is supplied. Throws when violations are present and -ThrowOnViolation is specified.

.EXAMPLE
pwsh Tools\Test-ParserSchedulerFairness.ps1 -ReportPath Logs\Reports\ParserSchedulerLaunch-2025-11-14.json -ThrowOnViolation

.EXAMPLE
pwsh Tools\Test-ParserSchedulerFairness.ps1 -MetricsPath Logs\IngestionMetrics\2025-11-14.json -MaxAllowedStreak 8
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ReportPath -and -not $MetricsPath) {
    throw 'Specify -ReportPath or -MetricsPath.'
}

if ($ReportPath -and $MetricsPath) {
    throw 'Specify either -ReportPath or -MetricsPath, not both.'
}

$reportToInspect = $ReportPath
$generatedReportPath = $null
try {
    if (-not $reportToInspect) {
        $analyzer = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'Tools\Analyze-ParserSchedulerLaunch.ps1'
        if (-not (Test-Path -LiteralPath $analyzer)) {
            throw "Unable to locate analyzer at '$analyzer'."
        }
        $generatedReportPath = [System.IO.Path]::GetTempFileName()
        & $analyzer -Path $MetricsPath -MaxAllowedStreak $MaxAllowedStreak -OutputPath $generatedReportPath | Out-Null
        $reportToInspect = $generatedReportPath
    }

    if (-not (Test-Path -LiteralPath $reportToInspect)) {
        throw "Report '$reportToInspect' was not found."
    }

    $json = Get-Content -LiteralPath $reportToInspect -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($json)) {
        throw "Report '$reportToInspect' is empty."
    }
    $report = $json | ConvertFrom-Json -Depth 6
    if (-not $report) {
        throw "Report '$reportToInspect' could not be parsed."
    }

    $violationCount = 0
    $pass = $true
    if ($report.PSObject.Properties.Name -contains 'ViolationCount') {
        $violationCount = [int]$report.ViolationCount
    } elseif ($report.Violations) {
        $violationCount = (@($report.Violations) | Measure-Object).Count
    }
    if ($report.PSObject.Properties.Name -contains 'Pass') {
        $pass = [bool]$report.Pass
    } else {
        $pass = ($violationCount -eq 0)
    }

    $result = [pscustomobject]@{
        ReportPath       = (Resolve-Path -LiteralPath $reportToInspect).Path
        Pass             = $pass
        ViolationCount   = $violationCount
        MaxObservedStreak = $report.MaxObservedStreak
        TotalLaunchEvents = $report.TotalLaunchEvents
        Violations       = @($report.Violations)
    }

    if ($pass) {
        Write-Host ("Parser scheduler fairness PASS (streak <= {0}, violations={1})." -f $MaxAllowedStreak, $violationCount) -ForegroundColor Green
    } else {
        Write-Warning ("Parser scheduler fairness FAILED: {0} violation(s) detected (max streak {1})." -f $violationCount, $report.MaxObservedStreak)
        if ($ThrowOnViolation) {
            throw ("Parser scheduler fairness failed with {0} violation(s)." -f $violationCount)
        }
    }

    if ($PassThru) {
        return $result
    }
}
finally {
    if ($generatedReportPath -and (Test-Path -LiteralPath $generatedReportPath)) {
        Remove-Item -LiteralPath $generatedReportPath -ErrorAction SilentlyContinue
    }
}

