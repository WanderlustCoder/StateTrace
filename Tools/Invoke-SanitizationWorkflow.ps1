[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$IncidentId,

    [Parameter(Mandatory)]
    [string]$SourcePath,

    [string]$DestinationRoot,

    [string[]]$RedactPatterns = @('password', 'secret', 'token', 'community', 'snmpv3', 'credential'),

    [string]$ReportPath,

    [switch]$DryRun,

    [switch]$RefreshFixtures,

    [switch]$PassThru
)

<#
.SYNOPSIS
Reproducible wrapper for sanitizing incident postmortem logs (ST-F-002).

.DESCRIPTION
Wraps Tools/Sanitize-PostmortemLogs.ps1 with standardized paths and reporting:
- Destinations: Data/Postmortems/<IncidentId>/Sanitized (or Tests/Fixtures/ for refresh)
- Reports: Logs/Sanitization/<IncidentId>.json
- History: Logs/Sanitization/SanitizationHistory.csv

Use -RefreshFixtures to update test fixtures from already-sanitized postmortems.

.PARAMETER IncidentId
Unique identifier for the incident (e.g., INC2025-1103).

.PARAMETER SourcePath
Path to raw postmortem logs (offline, not committed).

.PARAMETER DestinationRoot
Override the default destination root. Defaults to Data/Postmortems.

.PARAMETER RedactPatterns
Patterns to redact. Defaults to common sensitive terms.

.PARAMETER ReportPath
Override the report output path. Defaults to Logs/Sanitization/<IncidentId>.json.

.PARAMETER DryRun
Generate report without writing sanitized files.

.PARAMETER RefreshFixtures
Copy sanitized files to Tests/Fixtures/ for test use.

.PARAMETER PassThru
Return the sanitization result as an object.

.EXAMPLE
pwsh Tools\Invoke-SanitizationWorkflow.ps1 -IncidentId INC2025-1103 -SourcePath D:\SecureDrop\INC2025-1103\Raw

.EXAMPLE
pwsh Tools\Invoke-SanitizationWorkflow.ps1 -IncidentId INC2025-1103 -SourcePath D:\SecureDrop\INC2025-1103\Raw -DryRun

.EXAMPLE
pwsh Tools\Invoke-SanitizationWorkflow.ps1 -IncidentId INC2025-1103 -SourcePath Data\Postmortems\INC2025-1103\Sanitized -RefreshFixtures
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$sanitizerScript = Join-Path -Path $PSScriptRoot -ChildPath 'Sanitize-PostmortemLogs.ps1'

if (-not (Test-Path -LiteralPath $sanitizerScript)) {
    throw "Sanitizer script not found at '$sanitizerScript'."
}

# Resolve paths
if ([string]::IsNullOrWhiteSpace($DestinationRoot)) {
    $DestinationRoot = Join-Path -Path $repositoryRoot -ChildPath 'Data\Postmortems'
}

$sanitizedPath = Join-Path -Path $DestinationRoot -ChildPath "$IncidentId\Sanitized"
$sanitizationLogDir = Join-Path -Path $repositoryRoot -ChildPath 'Logs\Sanitization'

if (-not (Test-Path -LiteralPath $sanitizationLogDir)) {
    New-Item -ItemType Directory -Path $sanitizationLogDir -Force | Out-Null
}

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Join-Path -Path $sanitizationLogDir -ChildPath "$IncidentId.json"
}

$historyPath = Join-Path -Path $sanitizationLogDir -ChildPath 'SanitizationHistory.csv'

# Initialize result object
$result = [pscustomobject]@{
    GeneratedAtUtc    = (Get-Date).ToUniversalTime().ToString('o')
    IncidentId        = $IncidentId
    SourcePath        = $SourcePath
    DestinationPath   = $sanitizedPath
    ReportPath        = $ReportPath
    RedactPatterns    = $RedactPatterns
    DryRun            = $DryRun.IsPresent
    RefreshFixtures   = $RefreshFixtures.IsPresent
    Status            = 'Unknown'
    FilesProcessed    = 0
    LinesRedacted     = 0
    FixturesRefreshed = @()
    ErrorMessage      = $null
}

Write-Host "`n=== Sanitization Workflow (ST-F-002) ===" -ForegroundColor Cyan
Write-Host ("Incident: {0}" -f $IncidentId) -ForegroundColor DarkGray
Write-Host ("Source: {0}" -f $SourcePath) -ForegroundColor DarkGray
Write-Host ("Destination: {0}" -f $sanitizedPath) -ForegroundColor DarkGray
Write-Host ""

# Validate source
if (-not (Test-Path -LiteralPath $SourcePath)) {
    $result.Status = 'Failed'
    $result.ErrorMessage = "Source path not found: $SourcePath"
    Write-Host "ERROR: $($result.ErrorMessage)" -ForegroundColor Red

    if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
        $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ReportPath -Encoding utf8
    }

    if ($PassThru.IsPresent) { return $result }
    exit 1
}

try {
    # Run the sanitizer
    Write-Host "--- Running Sanitizer ---" -ForegroundColor Yellow

    $sanitizerArgs = @{
        SourcePath      = $SourcePath
        DestinationPath = $sanitizedPath
        RedactPatterns  = $RedactPatterns
    }

    if ($DryRun.IsPresent) {
        $sanitizerArgs['DryRun'] = $true
    }

    & $sanitizerScript @sanitizerArgs

    # Read the CSV report to get stats
    $csvReportPath = Join-Path -Path $sanitizedPath -ChildPath 'sanitization-report.csv'
    if (Test-Path -LiteralPath $csvReportPath) {
        $csvData = Import-Csv -LiteralPath $csvReportPath
        $result.LinesRedacted = $csvData.Count

        # Count unique files
        $uniqueFiles = $csvData | Select-Object -ExpandProperty RelativePath -Unique
        $result.FilesProcessed = $uniqueFiles.Count
    }

    $result.Status = 'Success'
    Write-Host "`nSanitization complete." -ForegroundColor Green
    Write-Host ("  Files with redactions: {0}" -f $result.FilesProcessed) -ForegroundColor DarkGray
    Write-Host ("  Lines redacted: {0}" -f $result.LinesRedacted) -ForegroundColor DarkGray

    # Refresh fixtures if requested
    if ($RefreshFixtures.IsPresent -and -not $DryRun.IsPresent) {
        Write-Host "`n--- Refreshing Test Fixtures ---" -ForegroundColor Yellow

        $fixturesRoot = Join-Path -Path $repositoryRoot -ChildPath 'Tests\Fixtures'
        $incidentFixtureDir = Join-Path -Path $fixturesRoot -ChildPath "Postmortems\$IncidentId"

        if (-not (Test-Path -LiteralPath $incidentFixtureDir)) {
            New-Item -ItemType Directory -Path $incidentFixtureDir -Force | Out-Null
        }

        # Copy sanitized files to fixtures
        $sanitizedFiles = Get-ChildItem -LiteralPath $sanitizedPath -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne 'sanitization-report.csv' }

        foreach ($file in $sanitizedFiles) {
            $relativePath = $file.FullName.Substring($sanitizedPath.Length).TrimStart('\', '/')
            $destPath = Join-Path -Path $incidentFixtureDir -ChildPath $relativePath
            $destDir = Split-Path -Path $destPath -Parent

            if (-not (Test-Path -LiteralPath $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }

            Copy-Item -LiteralPath $file.FullName -Destination $destPath -Force
            $result.FixturesRefreshed += $relativePath
        }

        Write-Host ("  Fixtures refreshed: {0} files" -f $result.FixturesRefreshed.Count) -ForegroundColor Green
    }

    # Update history
    $historyEntry = [pscustomobject]@{
        Timestamp       = (Get-Date).ToString('o')
        IncidentId      = $IncidentId
        SourcePath      = $SourcePath
        DestinationPath = $sanitizedPath
        FilesProcessed  = $result.FilesProcessed
        LinesRedacted   = $result.LinesRedacted
        DryRun          = $DryRun.IsPresent
        Status          = $result.Status
    }

    $appendHistory = Test-Path -LiteralPath $historyPath
    $historyEntry | Export-Csv -LiteralPath $historyPath -NoTypeInformation -Append:$appendHistory

    Write-Host "`nHistory updated: $historyPath" -ForegroundColor DarkCyan

} catch {
    $result.Status = 'Failed'
    $result.ErrorMessage = $_.Exception.Message
    Write-Host "ERROR: $($result.ErrorMessage)" -ForegroundColor Red
}

# Write JSON report
if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
    try {
        $reportDir = Split-Path -Path $ReportPath -Parent
        if ($reportDir -and -not (Test-Path -LiteralPath $reportDir)) {
            New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
        }
        $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ReportPath -Encoding utf8
        Write-Host "Report saved: $ReportPath" -ForegroundColor DarkCyan
    } catch {
        Write-Warning "Failed to save report: $($_.Exception.Message)"
    }
}

Write-Host ""

if ($PassThru.IsPresent) {
    return $result
}

if ($result.Status -ne 'Success') {
    exit 1
}
