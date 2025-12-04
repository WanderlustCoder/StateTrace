[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')),
    [switch]$SkipPester,
    [switch]$SkipUnusedExportLint,
    [string[]]$UnusedExportAllowlist = @(),
    [switch]$SkipSpanHarness,
    [string]$SpanHostname = 'LABS-A01-AS-01',
    [int]$SpanSampleCount = 5,
    [switch]$SkipNetOpsLint,
    [switch]$RequireNetOpsEvidence,
    [string]$NetOpsSessionLogPath,
    [int]$NetOpsEvidenceMaxHours = 12,
    [string]$TelemetryBundlePath,
    [string[]]$TelemetryBundleArea = @('Telemetry','Routing'),
    [switch]$RequireTelemetryBundleReady,
    [switch]$RequireTelemetryIntegrity
)

Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
Push-Location $repoRoot

$results = @()
try {
    if (-not $SkipUnusedExportLint) {
        Write-Host "===> Running unused export lint" -ForegroundColor Cyan
        $lintScript = Join-Path $repoRoot 'Tools\Report-UnusedExports.ps1'
        if (-not (Test-Path -LiteralPath $lintScript)) {
            throw "Unused export lint script missing at $lintScript"
        }

        $reportDir = Join-Path $repoRoot 'Logs\Reports'
        if (-not (Test-Path -LiteralPath $reportDir)) {
            New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
        }
        $reportPath = Join-Path $reportDir 'UnusedExports.json'

        $lintParams = @(
            '-File', $lintScript,
            '-OutputPath', $reportPath,
            '-FailOnUnused'
        )
        if ($UnusedExportAllowlist -and $UnusedExportAllowlist.Count -gt 0) {
            $lintParams += @('-Allowlist', ($UnusedExportAllowlist -join ','))
        }

        & pwsh @lintParams
        $lintExit = $LASTEXITCODE
        if ($lintExit -ne 0) {
            throw ("Unused export lint failed with exit code {0}. See {1} for details." -f $lintExit, $reportPath)
        }

        $lintReport = $null
        try { $lintReport = Get-Content -LiteralPath $reportPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch {}
        $unusedCount = if ($lintReport) { (@($lintReport | Where-Object { -not $_.Allowlisted -and $_.ReferenceCount -le 0 })).Count } else { 0 }

        $results += [pscustomobject]@{
            Check       = 'UnusedExports'
            ReportPath  = $reportPath
            UnusedCount = $unusedCount
        }
    }

    if (-not $SkipPester) {
        Write-Host "===> Running Pester suite" -ForegroundColor Cyan
        try {
            $pester = Invoke-Pester -Path 'Modules/Tests' -Output Detailed -EnableExit:$false -PassThru
        } catch {
            throw "Invoke-Pester failed: $($_.Exception.Message)"
        }
        $pesterSummary = [pscustomobject]@{
            Check    = 'Pester'
            Passed   = ($pester.FailedCount -eq 0)
            Total    = $pester.TotalCount
            Failed   = $pester.FailedCount
            Duration = if ($pester.Time) { [math]::Round($pester.Time.TotalSeconds, 2) } else { 0 }
        }
        $results += $pesterSummary
        if ($pester.FailedCount -gt 0) {
            throw "Pester reported $($pester.FailedCount) failures."
        }
    }

    if (-not $SkipSpanHarness) {
        Write-Host "===> Running Span View binding harness" -ForegroundColor Cyan
        $harnessPath = Join-Path $repoRoot 'Tools\Test-SpanViewBinding.ps1'
        if (-not (Test-Path -LiteralPath $harnessPath)) {
            throw "Span view harness missing at $harnessPath"
        }
        $json = & pwsh.exe -NoLogo -STA -File $harnessPath -RepositoryRoot $repoRoot -Hostname $SpanHostname -SampleCount $SpanSampleCount -AsJson
        $harnessExit = $LASTEXITCODE
        if ($harnessExit -ne 0) {
            throw ("Span harness exited with code {0}: {1}" -f $harnessExit, ($json -join [Environment]::NewLine))
        }
        if (-not $json) {
            throw "Span view harness returned no data."
        }
        $jsonText = ($json -join [Environment]::NewLine)
        $spanResult = $jsonText | ConvertFrom-Json
        $spanSummary = [pscustomobject]@{
            Check       = 'SpanHarness'
            Hostname    = $spanResult.Hostname
            Rows        = $spanResult.SnapshotRowCount
            UsedLastRow = [bool]$spanResult.UsedLastRows
            StatusText  = $spanResult.StatusText
        }
        $results += $spanSummary
        if ($spanResult.SnapshotRowCount -le 0) {
            throw "Span harness found zero rows for host $SpanHostname."
        }
    }

    if (-not $SkipNetOpsLint) {
        Write-Host "===> Running NetOps evidence lint" -ForegroundColor Cyan
        $netOpsScript = Join-Path $repoRoot 'Tools\Test-NetOpsEvidence.ps1'
        if (-not (Test-Path -LiteralPath $netOpsScript)) {
            throw "NetOps lint script missing at $netOpsScript"
        }

        $netOpsParams = @{
            NetOpsDirectory = Join-Path -Path $repoRoot -ChildPath 'Logs\NetOps'
            MaxHours        = $NetOpsEvidenceMaxHours
            Quiet           = $true
            PassThru        = $true
        }
        if ($RequireNetOpsEvidence) {
            $netOpsParams['RequireEvidence'] = $true
            $netOpsParams['RequireReason'] = $true
        }
        if (-not [string]::IsNullOrWhiteSpace($NetOpsSessionLogPath)) {
            $netOpsParams['SessionLogPath'] = (Resolve-Path -LiteralPath $NetOpsSessionLogPath -ErrorAction Stop).Path
            $netOpsParams['RequireSessionReference'] = $true
        }

        $netOpsResult = & $netOpsScript @netOpsParams
        if ($netOpsResult -and $netOpsResult.OnlineModeActive) {
            Write-Host ("NetOps lint passed. Evidence: {0}" -f $netOpsResult.LatestLogPath) -ForegroundColor Green
            $results += [pscustomobject]@{
                Check            = 'NetOpsLint'
                EvidenceLog      = $netOpsResult.LatestLogPath
                ResetLog         = $netOpsResult.LatestResetLogPath
                SessionReference = $netOpsResult.SessionReferenceSatisfied
            }
        } elseif ($netOpsResult) {
            Write-Host ($netOpsResult.Message) -ForegroundColor DarkGray
            $results += [pscustomobject]@{
                Check  = 'NetOpsLint'
                Passed = $true
                Note   = $netOpsResult.Message
            }
        }
    }

    if ($TelemetryBundlePath -or $RequireTelemetryBundleReady) {
        $bundleScript = Join-Path $repoRoot 'Tools\Test-TelemetryBundleReadiness.ps1'
        if (-not (Test-Path -LiteralPath $bundleScript)) {
            throw "Telemetry bundle readiness script missing at $bundleScript"
        }

        if ([string]::IsNullOrWhiteSpace($TelemetryBundlePath)) {
            throw "Specify -TelemetryBundlePath when requesting telemetry bundle readiness checks."
        }

        $resolvedBundle = (Resolve-Path -LiteralPath $TelemetryBundlePath -ErrorAction Stop).Path
        $bundleParams = @{
            BundlePath = $resolvedBundle
            PassThru   = $true
        }
        if ($TelemetryBundleArea -and $TelemetryBundleArea.Count -gt 0) {
            $bundleParams['Area'] = $TelemetryBundleArea
        }

        $bundleResult = & $bundleScript @bundleParams
        if (-not $bundleResult) {
            throw "Telemetry bundle readiness script returned no results for '$resolvedBundle'."
        }

        $missing = $bundleResult | Where-Object { $_.Status -eq 'Missing' }
        if ($missing -and $missing.Count -gt 0) {
            $summary = $missing | Format-Table Area, Requirement -AutoSize | Out-String
            throw "Telemetry bundle readiness failed:`n$summary"
        }

        $optionalMissing = $bundleResult | Where-Object { $_.Status -like 'Missing*Optional*' }
        if ($optionalMissing -and $optionalMissing.Count -gt 0) {
            $names = $optionalMissing | ForEach-Object { '{0}:{1}' -f $_.Area, $_.Requirement }
            Write-Warning ("Telemetry bundle readiness: optional artifacts missing ({0})." -f ($names -join ', '))
        }

        $results += [pscustomobject]@{
            Check      = 'TelemetryBundle'
            BundlePath = $resolvedBundle
            Areas      = ((@($bundleResult.Area) | Sort-Object -Unique) -join ',')
            Notes      = if ($optionalMissing -and $optionalMissing.Count -gt 0) { 'Optional artifacts missing' } else { 'All required artifacts present' }
        }
    }

    if ($RequireTelemetryIntegrity) {
        Write-Host "===> Running telemetry integrity lint" -ForegroundColor Cyan
        $integrityScript = Join-Path $repoRoot 'Tools\Test-TelemetryIntegrity.ps1'
        if (-not (Test-Path -LiteralPath $integrityScript)) {
            throw "Telemetry integrity script missing at $integrityScript"
        }

        $ingestionDir = Join-Path $repoRoot 'Logs\IngestionMetrics'
        $latestMetrics = Get-ChildItem -Path $ingestionDir -Filter '*.json' -File -ErrorAction Stop |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if (-not $latestMetrics) {
            throw "Telemetry integrity lint: no ingestion metrics found under $ingestionDir"
        }

        $integrityReportDir = Join-Path $repoRoot 'Logs\Reports'
        if (-not (Test-Path -LiteralPath $integrityReportDir)) {
            New-Item -ItemType Directory -Path $integrityReportDir -Force | Out-Null
        }
        $integrityReportPath = Join-Path $integrityReportDir ("TelemetryIntegrity-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

        & pwsh -File $integrityScript -Path $latestMetrics.FullName -RequireQueueSummary -RequireInterfaceSync *> $integrityReportPath
        $integrityExit = $LASTEXITCODE
        if ($integrityExit -ne 0) {
            $preview = Get-Content -LiteralPath $integrityReportPath | Select-Object -First 20
            $previewText = ($preview -join [Environment]::NewLine)
            throw ("Telemetry integrity failed (exit {0}). See {1}.{2}{3}" -f $integrityExit, $integrityReportPath, [Environment]::NewLine, $previewText)
        }

        $results += [pscustomobject]@{
            Check      = 'TelemetryIntegrity'
            ReportPath = $integrityReportPath
            File       = $latestMetrics.FullName
        }
        Write-Host ("Telemetry integrity passed for {0} (report: {1})" -f $latestMetrics.FullName, $integrityReportPath) -ForegroundColor Green
    }
}
finally {
    Pop-Location
}

Write-Host "===> Check summary" -ForegroundColor Green
$results | Format-Table -AutoSize
