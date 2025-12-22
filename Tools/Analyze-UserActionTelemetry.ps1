[CmdletBinding()]
param(
    [string]$Path,
    [string]$OutputPath,
    [string[]]$RequiredActions = @('ScanLogs','LoadFromDb','HelpQuickstart','InterfacesView','CompareView','SpanSnapshot')
)

<#
.SYNOPSIS
Summarizes UserAction telemetry (Plan H adoption signals).

.DESCRIPTION
Reads a telemetry JSON file (default: latest under Logs\IngestionMetrics) and
outputs counts by Action and Site for UserAction events emitted by the UI
(ScanLogs, LoadFromDb, HelpQuickstart, InterfacesView, CompareView, SpanSnapshot, etc.).

.EXAMPLE
pwsh -NoLogo -File Tools\Analyze-UserActionTelemetry.ps1 -Path Logs\IngestionMetrics\2025-11-27.json -OutputPath Logs\Reports\UserActionSummary-20251127.json
#>

Set-StrictMode -Version Latest

function Get-LatestTelemetryPath {
    $dir = Join-Path (Resolve-Path '.').Path 'Logs\IngestionMetrics'
    if (-not (Test-Path -LiteralPath $dir)) { return $null }
    return Get-ChildItem -LiteralPath $dir -Filter '*.json' -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | ForEach-Object { $_.FullName }
}

function Read-TelemetryEvents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string[]]$EventNames,
        [string]$Label = 'Telemetry'
    )

    $parsed = New-Object System.Collections.Generic.List[object]
    $parseErrors = 0
    $parsedLines = 0
    $lineAttempts = 0
    $maxLineAttempts = 10

    foreach ($line in (Get-Content -LiteralPath $Path -ReadCount 1 -ErrorAction Stop)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $lineAttempts++
        try {
            $obj = $line | ConvertFrom-Json -ErrorAction Stop
            $parsedLines++
            if (-not $EventNames -or ($EventNames -contains $obj.EventName)) {
                $null = $parsed.Add($obj)
            }
        } catch {
            $parseErrors++
            if ($parseErrors -le 3) {
                Write-Verbose ("[{0}] Skipping invalid JSON line: {1}" -f $Label, $_.Exception.Message)
            }
        }
        if ($parsedLines -eq 0 -and $lineAttempts -ge $maxLineAttempts) {
            break
        }
    }

    if ($parsedLines -gt 0) {
        if ($parseErrors -gt 0) {
            Write-Warning ("[{0}] Skipped {1} invalid JSON line(s) in {2}" -f $Label, $parseErrors, $Path)
        }
        return $parsed.ToArray()
    }

    $rawJson = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    $events = $rawJson | ConvertFrom-Json -ErrorAction Stop
    if (-not $events) {
        throw "Failed to parse telemetry at $Path."
    }
    if ($EventNames) {
        $events = @($events | Where-Object { $EventNames -contains $_.EventName })
    }
    return $events
}

if (-not $Path) {
    $Path = Get-LatestTelemetryPath
}

if (-not $Path) {
    throw "No telemetry file found. Provide -Path or ensure Logs\IngestionMetrics exists."
}

if (-not (Test-Path -LiteralPath $Path)) {
    throw "Telemetry file not found: $Path"
}

$userActions = Read-TelemetryEvents -Path $Path -EventNames @('UserAction') -Label 'UserAction'

$missingRequired = @()
foreach ($req in $RequiredActions) {
    if (-not ($userActions | Where-Object { $_.Action -eq $req })) {
        $missingRequired += $req
    }
}
$requiredCoverage = [pscustomobject]@{
    RequiredActions   = $RequiredActions
    MissingActions    = $missingRequired
    AllActionsPresent = ($missingRequired.Count -eq 0)
}

$actionGroups = $userActions | Group-Object Action | Sort-Object Count -Descending | ForEach-Object {
    [pscustomobject]@{
        Action = $_.Name
        Count  = $_.Count
    }
}

$siteGroups = $userActions | Group-Object Site | Sort-Object Count -Descending | ForEach-Object {
    [pscustomobject]@{
        Site  = $_.Name
        Count = $_.Count
    }
}

$summary = [pscustomobject]@{
    SourcePath        = (Resolve-Path -LiteralPath $Path).ProviderPath
    TotalEvents       = $userActions.Count
    Actions           = $actionGroups
    Sites             = $siteGroups
    RequiredCoverage  = $requiredCoverage
}

Write-Host ("[UserAction] Source: {0}" -f $summary.SourcePath) -ForegroundColor Cyan
Write-Host ("[UserAction] Total events: {0}" -f $summary.TotalEvents)
if ($actionGroups) {
    Write-Host "[UserAction] By action:"
    foreach ($a in $actionGroups) { Write-Host ("  {0}: {1}" -f $a.Action, $a.Count) }
}
if ($requiredCoverage) {
    if ($requiredCoverage.AllActionsPresent) {
        Write-Host "[UserAction] Coverage: all required actions present." -ForegroundColor Green
    } else {
        Write-Warning ("[UserAction] Missing required actions: {0}" -f ($requiredCoverage.MissingActions -join ', '))
    }
}
if ($siteGroups) {
    Write-Host "[UserAction] By site:"
    foreach ($s in $siteGroups) { Write-Host ("  {0}: {1}" -f $s.Site, $s.Count) }
}

if ($OutputPath) {
    $dir = Split-Path -Path $OutputPath -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding utf8
    $resolved = Resolve-Path -LiteralPath $OutputPath -ErrorAction SilentlyContinue
    $display = if ($resolved) { $resolved.ProviderPath } else { $OutputPath }
    Write-Host ("[UserAction] Summary written to {0}" -f $display) -ForegroundColor Green
}
