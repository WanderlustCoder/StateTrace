[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('ParserRegression', 'UIFailure', 'RoutingBacklog', 'SharedCacheRefresh',
                 'PortBatchMissing', 'DispatcherThroughput', 'RollbackExecution')]
    [string]$Scenario,

    [string]$DrillId,

    [string]$Lead,

    [string[]]$Participants,

    [switch]$RecordResults,

    [string]$OutputPath,

    [switch]$PassThru
)

<#
.SYNOPSIS
Executes or records an incident drill for ST-R-001 drill cadence.

.DESCRIPTION
Supports drill execution workflow:
- Initialize a drill with timing capture
- Simulate scenario triggers (optional)
- Record drill results with timings and gaps

.PARAMETER Scenario
The drill scenario type.

.PARAMETER DrillId
Optional drill ID. Defaults to DRILL-<date>-<sequence>.

.PARAMETER Lead
Name of the drill lead.

.PARAMETER Participants
List of drill participants.

.PARAMETER RecordResults
If set, prompts for drill results and saves to output.

.PARAMETER OutputPath
Path to save drill results. Defaults to Logs/Drills/<DrillId>.json.

.PARAMETER PassThru
Returns the drill result as an object.

.EXAMPLE
pwsh Tools\Invoke-IncidentDrill.ps1 -Scenario ParserRegression -Lead "John" -RecordResults

.EXAMPLE
pwsh Tools\Invoke-IncidentDrill.ps1 -Scenario RoutingBacklog -DrillId DRILL-2026-01-001 -PassThru
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$datePrefix = Get-Date -Format 'yyyy-MM-dd'

# Generate drill ID if not provided
if ([string]::IsNullOrWhiteSpace($DrillId)) {
    $drillDir = Join-Path -Path $repositoryRoot -ChildPath 'Logs\Drills'
    $existingDrills = @()
    if (Test-Path -LiteralPath $drillDir) {
        $existingDrills = Get-ChildItem -Path $drillDir -Filter "DRILL-$datePrefix-*.json" -File
    }
    $sequence = $existingDrills.Count + 1
    $DrillId = "DRILL-{0}-{1:D3}" -f $datePrefix, $sequence
}

# Scenario metadata
$scenarioMeta = @{
    'ParserRegression' = @{
        Description = 'Simulated parser failure via corrupted fixture file'
        Runbook = $null
        SuccessCriteria = @(
            'Identify failure within 5 minutes',
            'Locate offending host/log within 10 minutes',
            'Rollback or fix applied within 15 minutes',
            'Telemetry bundle captured'
        )
    }
    'UIFailure' = @{
        Description = 'Simulated WPF crash or frozen UI'
        Runbook = $null
        SuccessCriteria = @(
            'Identify UI failure from telemetry within 5 minutes',
            'Capture diagnostic logs within 10 minutes',
            'Restart or recover UI within 10 minutes'
        )
    }
    'RoutingBacklog' = @{
        Description = 'Artificially delayed dispatcher queue'
        Runbook = 'docs/runbooks/Incident_INC0001_RoutingQueueDelay.md'
        SuccessCriteria = @(
            'Identify queue delay spike within 5 minutes',
            'Run Analyze-DispatcherGaps within 10 minutes',
            'Document findings within 15 minutes'
        )
    }
    'SharedCacheRefresh' = @{
        Description = 'Simulated cache miss storm'
        Runbook = 'docs/runbooks/Incident_INC0002_SharedCacheRefresh.md'
        SuccessCriteria = @(
            'Identify AccessRefresh spike within 5 minutes',
            'Run shared-cache diagnostics within 10 minutes',
            'Determine root cause within 15 minutes'
        )
    }
    'PortBatchMissing' = @{
        Description = 'Suppressed PortBatchReady events'
        Runbook = 'docs/runbooks/Incident_INC0003_PortBatchMissing.md'
        SuccessCriteria = @(
            'Identify missing events within 5 minutes',
            'Run synthesis/recovery within 10 minutes'
        )
    }
    'DispatcherThroughput' = @{
        Description = 'Throttled dispatcher via settings'
        Runbook = 'docs/runbooks/Incident_INC0006_DispatcherThroughputDrop.md'
        SuccessCriteria = @(
            'Identify throughput drop within 5 minutes',
            'Correlate with scheduler metrics within 10 minutes'
        )
    }
    'RollbackExecution' = @{
        Description = 'Practice full rollback workflow'
        Runbook = 'docs/plans/PlanR_IncidentResponse.md'
        SuccessCriteria = @(
            'Create rollback bundle within 5 minutes',
            'Verify bundle contents within 5 minutes',
            'Practice restore steps'
        )
    }
}

$meta = $scenarioMeta[$Scenario]

# Initialize drill result
$result = [pscustomobject]@{
    DrillId              = $DrillId
    Scenario             = $Scenario
    Description          = $meta.Description
    Runbook              = $meta.Runbook
    DrillDateUtc         = (Get-Date).ToUniversalTime().ToString('o')
    Lead                 = $Lead
    Participants         = if ($Participants) { $Participants } else { @() }
    SuccessCriteria      = $meta.SuccessCriteria
    TimingsMins          = [pscustomobject]@{
        IdentifyIssue    = 0
        LocateRootCause  = 0
        ApplyFix         = 0
        VerifyRecovery   = 0
    }
    TotalDurationMins    = 0
    SuccessCriteriaMet   = $false
    GapsIdentified       = @()
    RunbookUpdatesNeeded = @()
    Notes                = ''
    Status               = 'Pending'
}

Write-Host "`n=== Incident Drill (ST-R-001) ===" -ForegroundColor Cyan
Write-Host ("Drill ID: {0}" -f $DrillId) -ForegroundColor DarkGray
Write-Host ("Scenario: {0}" -f $Scenario) -ForegroundColor DarkGray
Write-Host ("Description: {0}" -f $meta.Description) -ForegroundColor DarkGray
if ($meta.Runbook) {
    Write-Host ("Runbook: {0}" -f $meta.Runbook) -ForegroundColor DarkGray
}
Write-Host ""

Write-Host "--- Success Criteria ---" -ForegroundColor Yellow
foreach ($criterion in $meta.SuccessCriteria) {
    Write-Host ("  - {0}" -f $criterion)
}
Write-Host ""

if ($RecordResults.IsPresent) {
    Write-Host "--- Recording Drill Results ---" -ForegroundColor Yellow

    # Collect timings
    Write-Host "Enter timing in minutes (press Enter to skip):" -ForegroundColor DarkCyan

    $identifyInput = Read-Host "  Time to identify issue"
    if ($identifyInput -match '^\d+(\.\d+)?$') {
        $result.TimingsMins.IdentifyIssue = [double]$identifyInput
    }

    $locateInput = Read-Host "  Time to locate root cause"
    if ($locateInput -match '^\d+(\.\d+)?$') {
        $result.TimingsMins.LocateRootCause = [double]$locateInput
    }

    $fixInput = Read-Host "  Time to apply fix"
    if ($fixInput -match '^\d+(\.\d+)?$') {
        $result.TimingsMins.ApplyFix = [double]$fixInput
    }

    $verifyInput = Read-Host "  Time to verify recovery"
    if ($verifyInput -match '^\d+(\.\d+)?$') {
        $result.TimingsMins.VerifyRecovery = [double]$verifyInput
    }

    $result.TotalDurationMins = $result.TimingsMins.IdentifyIssue +
                                 $result.TimingsMins.LocateRootCause +
                                 $result.TimingsMins.ApplyFix +
                                 $result.TimingsMins.VerifyRecovery

    # Success criteria
    $successInput = Read-Host "  Were all success criteria met? (y/n)"
    $result.SuccessCriteriaMet = $successInput -eq 'y'

    # Gaps
    $gapsInput = Read-Host "  Gaps identified (comma-separated, or Enter to skip)"
    if (-not [string]::IsNullOrWhiteSpace($gapsInput)) {
        $result.GapsIdentified = $gapsInput -split ',' | ForEach-Object { $_.Trim() }
    }

    # Runbook updates
    $updatesInput = Read-Host "  Runbook updates needed (comma-separated, or Enter to skip)"
    if (-not [string]::IsNullOrWhiteSpace($updatesInput)) {
        $result.RunbookUpdatesNeeded = $updatesInput -split ',' | ForEach-Object { $_.Trim() }
    }

    # Notes
    $notesInput = Read-Host "  Additional notes (or Enter to skip)"
    if (-not [string]::IsNullOrWhiteSpace($notesInput)) {
        $result.Notes = $notesInput
    }

    $result.Status = 'Completed'
    Write-Host ""
}

# Determine output path
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $drillDir = Join-Path -Path $repositoryRoot -ChildPath 'Logs\Drills'
    $OutputPath = Join-Path -Path $drillDir -ChildPath "$DrillId.json"
}

# Create output directory if needed
$outputDir = Split-Path -Path $OutputPath -Parent
if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# Save result
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding utf8

Write-Host "--- Drill Summary ---" -ForegroundColor Yellow
Write-Host ("  Drill ID: {0}" -f $result.DrillId) -ForegroundColor Green
Write-Host ("  Scenario: {0}" -f $result.Scenario)
Write-Host ("  Status: {0}" -f $result.Status)
if ($result.Status -eq 'Completed') {
    Write-Host ("  Total Duration: {0:N1} mins" -f $result.TotalDurationMins)
    Write-Host ("  Success Criteria Met: {0}" -f $result.SuccessCriteriaMet)
    if ($result.GapsIdentified.Count -gt 0) {
        Write-Host ("  Gaps Identified: {0}" -f ($result.GapsIdentified -join '; ')) -ForegroundColor Yellow
    }
}
Write-Host ("  Output: {0}" -f $OutputPath) -ForegroundColor DarkCyan
Write-Host ""

if ($PassThru.IsPresent) {
    return $result
}
