[CmdletBinding()]
param(
    [switch]$IncludeTests,
    [switch]$SkipParsing,
    [switch]$ResetExtractedLogs,
    [switch]$PreserveModuleSession,
    [string]$WarmRunTelemetryDirectory,
    [string]$WarmRunRegressionOutputPath,
    [switch]$QuietSummary,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$verificationScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools\Invoke-StateTraceVerification.ps1'
if (-not (Test-Path -LiteralPath $verificationScript)) {
    throw "Verification harness not found at $verificationScript."
}

$verificationParameters = @{}

if (-not $IncludeTests.IsPresent) {
    $verificationParameters['SkipTests'] = $true
}

$verificationParameters['VerboseParsing'] = $true

if ($SkipParsing.IsPresent) { $verificationParameters['SkipParsing'] = $true }
if ($ResetExtractedLogs.IsPresent) { $verificationParameters['ResetExtractedLogs'] = $true }
if ($PreserveModuleSession.IsPresent) { $verificationParameters['PreserveModuleSession'] = $true }
if (-not [string]::IsNullOrWhiteSpace($WarmRunTelemetryDirectory)) {
    $verificationParameters['WarmRunTelemetryDirectory'] = $WarmRunTelemetryDirectory
}
if (-not [string]::IsNullOrWhiteSpace($WarmRunRegressionOutputPath)) {
    $verificationParameters['WarmRunRegressionOutputPath'] = $WarmRunRegressionOutputPath
}

$verificationParameters['PassThru'] = $true

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$verificationLogDir = Join-Path -Path $repositoryRoot -ChildPath 'Logs\Verification'
if (-not (Test-Path -LiteralPath $verificationLogDir)) {
    New-Item -ItemType Directory -Path $verificationLogDir -Force | Out-Null
}
$transcriptPath = Join-Path -Path $verificationLogDir -ChildPath ("StateTraceVerification-{0}.log" -f $timestamp)

Start-Transcript -Path $transcriptPath -Force | Out-Null
try {
    Write-Host ("[{0}] Starting scheduled verification run..." -f (Get-Date).ToString('u')) -ForegroundColor Cyan
    $result = & $verificationScript @verificationParameters
    Write-Host ("[{0}] Verification run completed successfully." -f (Get-Date).ToString('u')) -ForegroundColor Green

    if (-not $QuietSummary.IsPresent -and $null -ne $result) {
        $summary = $result.WarmRunSummary
        if ($null -ne $summary) {
            Write-Host 'Warm-run regression summary:' -ForegroundColor Yellow
            Write-Host ("  Telemetry Path          : {0}" -f $summary.TelemetryPath) -ForegroundColor Yellow
            Write-Host ("  Cold Avg / P95 / Max Ms : {0} / {1} / {2}" -f $summary.ColdInterfaceCallAvgMs, $summary.ColdInterfaceCallP95Ms, $summary.ColdInterfaceCallMaxMs) -ForegroundColor Yellow
            Write-Host ("  Warm Avg / P95 / Max Ms : {0} / {1} / {2}" -f $summary.WarmInterfaceCallAvgMs, $summary.WarmInterfaceCallP95Ms, $summary.WarmInterfaceCallMaxMs) -ForegroundColor Yellow
            Write-Host ("  Improvement (ms / %)    : {0} / {1}" -f $summary.ImprovementAverageMs, $summary.ImprovementPercent) -ForegroundColor Yellow
            Write-Host ("  Warm Cache Hits / Miss  : {0} / {1}" -f $summary.WarmCacheProviderHitCount, $summary.WarmCacheProviderMissCount) -ForegroundColor Yellow
            Write-Host ("  Warm Sig Miss / Rewrite : {0} / {1}" -f $summary.WarmSignatureMatchMissCount, $summary.WarmSignatureRewriteTotal) -ForegroundColor Yellow
        } else {
            Write-Warning 'Warm-run summary information was not returned; consult WarmRunTelemetry-latest-summary.json.'
        }
    }

    if ($PassThru.IsPresent) {
        $result
    }
} catch {
    Write-Host ("[{0}] Scheduled verification failed: {1}" -f (Get-Date).ToString('u'), $_.Exception.Message) -ForegroundColor Red
    throw
} finally {
    Stop-Transcript | Out-Null
    if (Test-Path -LiteralPath $transcriptPath) {
        Write-Host ("Transcript captured at {0}" -f $transcriptPath) -ForegroundColor DarkGray
    }
}
