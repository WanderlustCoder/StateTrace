<#
.SYNOPSIS
Runs desktop UI harnesses (Span/Search/Alerts) in sequence with logs and summary output.
.DESCRIPTION
Executes the Span view binding harness and Search/Alerts smoke harness, writing
per-harness logs plus a consolidated JSON summary under Logs/UIHarness.
.EXAMPLE
pwsh -NoProfile -STA -File Tools/Invoke-DesktopUIHarness.ps1 -SpanHostname WLLS-A01-AS-21
#>
[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')),
    [string]$SpanHostname = '',
    [int]$SpanSampleCount = 5,
    [int]$SpanTimeoutSeconds = 20,
    [int]$SpanNoProgressTimeoutSeconds = 5,
    [string[]]$SearchAlertsHostnames = @(),
    [string[]]$SearchAlertsSiteFilter = @(),
    [int]$SearchAlertsMaxHosts = 3,
    [int]$SearchAlertsTimeoutSeconds = 20,
    [int]$SearchAlertsNoProgressTimeoutSeconds = 5,
    [switch]$SearchAlertsRequireAlerts
)

Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$logDir = Join-Path $repoRoot 'Logs/UIHarness'
if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$summaryPath = Join-Path $logDir ("UIHarnessSummary-{0}.json" -f $timestamp)

$helperPath = Join-Path $repoRoot 'Tools/UiHarnessHelpers.ps1'
if (-not (Test-Path -LiteralPath $helperPath)) {
    throw "UI harness helpers missing at $helperPath"
}
. $helperPath

# LANDMARK: Desktop UI harness runner - preflight and structured summary output
$preflight = Test-StateTraceUiHarnessPreflight -RequireDesktop -RequireSta
if ($preflight.Status -ne 'Ready') {
    $blockedSummary = [pscustomobject]@{
        Timestamp = (Get-Date).ToString('o')
        Status    = $preflight.Status
        Reason    = $preflight.Reason
        Details   = $preflight.Details
        Harnesses = @(
            [pscustomobject]@{ HarnessName = 'SpanView'; Status = $preflight.Status; Reason = $preflight.Reason },
            [pscustomobject]@{ HarnessName = 'SearchAlerts'; Status = $preflight.Status; Reason = $preflight.Reason }
        )
    }
    $blockedSummary | ConvertTo-Json -Depth 6 | Set-Content -Path $summaryPath -Encoding UTF8
    Write-Host ("UI harness blocked ({0}). Summary: {1}" -f $preflight.Reason, $summaryPath) -ForegroundColor Yellow
    exit 2
}

$spanLog = Join-Path $logDir ("SpanHarness-{0}.log" -f $timestamp)
$searchLog = Join-Path $logDir ("SearchAlertsHarness-{0}.log" -f $timestamp)

$spanExe = Get-Command -Name 'powershell.exe' -ErrorAction SilentlyContinue
$spanExePath = if ($spanExe -and $spanExe.Path) { $spanExe.Path } else { 'pwsh.exe' }
$spanScript = Join-Path $repoRoot 'Tools\Test-SpanViewBinding.ps1'
$spanArgs = @(
    '-NoLogo', '-STA',
    '-File', $spanScript,
    '-RepositoryRoot', $repoRoot,
    '-Hostname', $SpanHostname,
    '-SampleCount', $SpanSampleCount,
    '-TimeoutSeconds', $SpanTimeoutSeconds,
    '-NoProgressTimeoutSeconds', $SpanNoProgressTimeoutSeconds,
    '-AsJson'
)

$spanJson = & $spanExePath @spanArgs
$spanExit = $LASTEXITCODE
$spanJsonText = if ($spanJson) { ($spanJson -join [Environment]::NewLine) } else { '' }
Set-Content -Path $spanLog -Value $spanJsonText -Encoding UTF8
$spanResult = $null
if ($spanJsonText) {
    try { $spanResult = $spanJsonText | ConvertFrom-Json -ErrorAction Stop } catch { $spanResult = $null }
}
$spanStatus = if ($spanResult -and $spanResult.PSObject.Properties['Status']) { $spanResult.Status } else { if ($spanExit -eq 0) { 'Pass' } else { 'Fail' } }
$spanSummary = [pscustomobject]@{
    HarnessName = 'SpanView'
    Status      = $spanStatus
    ExitCode    = $spanExit
    LogPath     = $spanLog
    Hostname    = if ($spanResult) { $spanResult.Hostname } else { $SpanHostname }
    Rows        = if ($spanResult) { $spanResult.SnapshotRowCount } else { 0 }
    Notes       = if ($spanResult -and $spanResult.FailureMessage) { $spanResult.FailureMessage } else { '' }
}

$searchScript = Join-Path $repoRoot 'Tools\Invoke-SearchAlertsSmokeTest.ps1'
$searchArgs = @(
    '-NoLogo', '-STA',
    '-File', $searchScript,
    '-RepositoryRoot', $repoRoot,
    '-PassThru',
    '-AsJson',
    '-ForceExit',
    '-TimeoutSeconds', $SearchAlertsTimeoutSeconds,
    '-NoProgressTimeoutSeconds', $SearchAlertsNoProgressTimeoutSeconds,
    '-MaxHosts', $SearchAlertsMaxHosts
)
if ($SearchAlertsHostnames -and $SearchAlertsHostnames.Count -gt 0) {
    $searchArgs += '-Hostnames'
    $searchArgs += $SearchAlertsHostnames
}
if ($SearchAlertsSiteFilter -and $SearchAlertsSiteFilter.Count -gt 0) {
    $searchArgs += '-SiteFilter'
    $searchArgs += $SearchAlertsSiteFilter
}
if ($SearchAlertsRequireAlerts) {
    $searchArgs += '-RequireAlerts'
}

$searchJson = & pwsh.exe @searchArgs
$searchExit = $LASTEXITCODE
$searchJsonText = if ($searchJson) { ($searchJson -join [Environment]::NewLine) } else { '' }
Set-Content -Path $searchLog -Value $searchJsonText -Encoding UTF8
$searchResult = $null
if ($searchJsonText) {
    try { $searchResult = $searchJsonText | ConvertFrom-Json -ErrorAction Stop } catch { $searchResult = $null }
}
$searchStatus = if ($searchResult) { if ($searchResult.Success) { 'Pass' } else { 'Fail' } } else { if ($searchExit -eq 0) { 'Pass' } else { 'Fail' } }
$searchSummary = [pscustomobject]@{
    HarnessName = 'SearchAlerts'
    Status      = $searchStatus
    ExitCode    = $searchExit
    LogPath     = $searchLog
    SearchCount = if ($searchResult) { $searchResult.SearchCount } else { 0 }
    AlertsCount = if ($searchResult) { $searchResult.AlertsCount } else { 0 }
    Notes       = if ($searchResult -and -not $searchResult.Success) { 'Search/Alerts harness reported failure.' } else { '' }
}

$overallStatus = if ($spanSummary.Status -eq 'Pass' -and $searchSummary.Status -eq 'Pass') { 'Pass' } else { 'Fail' }
$summary = [pscustomobject]@{
    Timestamp = (Get-Date).ToString('o')
    Status    = $overallStatus
    Harnesses = @($spanSummary, $searchSummary)
    SummaryPath = $summaryPath
}

$summary | ConvertTo-Json -Depth 6 | Set-Content -Path $summaryPath -Encoding UTF8
Write-Host ("UI harness summary: {0}" -f $summaryPath) -ForegroundColor Green

if ($overallStatus -ne 'Pass') {
    exit 1
}
