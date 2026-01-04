[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')),
    [switch]$SkipPester,
    [switch]$RunDecompositionTests,
    [switch]$SkipUnusedExportLint,
    [string[]]$UnusedExportAllowlist = @(),
    [switch]$SkipSpanHarness,
    [string]$SpanHostname = '',
    [int]$SpanSampleCount = 5,
    [switch]$SkipSearchAlertsHarness,
    [string[]]$SearchAlertsHostnames = @(),
    [string[]]$SearchAlertsSiteFilter = @(),
    [int]$SearchAlertsMaxHosts = 3,
    [int]$SearchAlertsTimeoutSeconds = 20,
    [switch]$SearchAlertsRequireAlerts,
    [switch]$SkipNetOpsLint,
    [switch]$RequireNetOpsEvidence,
    [string]$NetOpsSessionLogPath,
    [int]$NetOpsEvidenceMaxHours = 12,
    [string]$DocSyncTaskId,
    [string]$DocSyncSessionLogPath,
    [string]$DocSyncPlanPath,
    [string]$DocSyncOutputPath,
    [switch]$DocSyncRequireBacklogEntry,
    [switch]$RequireDocSyncChecklist,
    [string]$TelemetryBundlePath,
    [string[]]$TelemetryBundleArea = @('Telemetry','Routing'),
    [switch]$RequireTelemetryBundleReady,
    [switch]$RequireTelemetryIntegrity
)

Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
Push-Location $repoRoot

$uiHelperPath = Join-Path $repoRoot 'Tools\UiHarnessHelpers.ps1'
if (-not (Test-Path -LiteralPath $uiHelperPath)) {
    throw "UI harness helpers missing at $uiHelperPath"
}
. $uiHelperPath

$results = [System.Collections.Generic.List[pscustomobject]]::new()
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

        $results.Add([pscustomobject]@{
            Check       = 'UnusedExports'
            ReportPath  = $reportPath
            UnusedCount = $unusedCount
        })
    }

    if (-not $SkipPester) {
        Write-Host "===> Running Pester suite" -ForegroundColor Cyan
        try {
            # LANDMARK: Pester compatibility - avoid -Output on older Pester
            $pesterParams = @{
                Path       = 'Modules/Tests'
                EnableExit = $false
                PassThru   = $true
            }
            $pesterCommand = Get-Command Invoke-Pester -ErrorAction Stop
            if ($pesterCommand.Parameters.ContainsKey('Output')) {
                $pesterParams['Output'] = 'Detailed'
            }
            $pester = Invoke-Pester @pesterParams
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
        $results.Add($pesterSummary)
        if ($pester.FailedCount -gt 0) {
            throw "Pester reported $($pester.FailedCount) failures."
        }
    }

    if ($RunDecompositionTests) {
        Write-Host "===> Running decomposition shim tests" -ForegroundColor Cyan
        try {
            $decomp = Invoke-Pester -Path 'Modules/Tests' -Tag 'Decomposition' -EnableExit:$false -PassThru
        } catch {
            throw "Decomposition Pester run failed: $($_.Exception.Message)"
        }
        $results.Add([pscustomobject]@{
            Check    = 'Decomposition'
            Passed   = ($decomp.FailedCount -eq 0)
            Total    = $decomp.TotalCount
            Failed   = $decomp.FailedCount
            Duration = if ($decomp.Time) { [math]::Round($decomp.Time.TotalSeconds, 2) } else { 0 }
        })
        if ($decomp.FailedCount -gt 0) {
            throw "Decomposition Pester reported $($decomp.FailedCount) failures."
        }
    }

    if (-not $SkipSpanHarness) {
        Write-Host "===> Running Span View binding harness" -ForegroundColor Cyan
        $harnessPath = Join-Path $repoRoot 'Tools\Test-SpanViewBinding.ps1'
        if (-not (Test-Path -LiteralPath $harnessPath)) {
            throw "Span view harness missing at $harnessPath"
        }
        # LANDMARK: Span harness preflight - avoid headless crashes and point to desktop runner
        $spanPreflight = Test-StateTraceUiHarnessPreflight -RequireDesktop
        if ($spanPreflight.Status -ne 'Ready') {
            throw ("Span harness requires a desktop session ({0}). Run `Tools\Invoke-DesktopUIHarness.ps1` from an interactive desktop." -f $spanPreflight.Reason)
        }

        $spanExe = Get-Command -Name 'powershell.exe' -ErrorAction SilentlyContinue
        $spanExePath = if ($spanExe -and $spanExe.Path) { $spanExe.Path } else { 'pwsh.exe' }
        $json = & $spanExePath -NoLogo -STA -File $harnessPath -RepositoryRoot $repoRoot -Hostname $SpanHostname -SampleCount $SpanSampleCount -AsJson
        $harnessExit = $LASTEXITCODE
        if ($harnessExit -ne 0) {
            throw ("Span harness exited with code {0}: {1}" -f $harnessExit, ($json -join [Environment]::NewLine))
        }
        if (-not $json) {
            throw "Span view harness returned no data."
        }
        $jsonText = ($json -join [Environment]::NewLine)
        $spanResult = $jsonText | ConvertFrom-Json
        $spanStatus = if ($spanResult.PSObject.Properties['Status']) { $spanResult.Status } else { 'Pass' }
        if ($spanStatus -in @('RequiresDesktop','RequiresSTA')) {
            throw ("Span harness {0}. Run `Tools\Invoke-DesktopUIHarness.ps1` in an interactive desktop session." -f $spanStatus)
        }
        $spanSummary = [pscustomobject]@{
            Check       = 'SpanHarness'
            Status      = $spanStatus
            Hostname    = $spanResult.Hostname
            Rows        = $spanResult.SnapshotRowCount
            UsedLastRow = [bool]$spanResult.UsedLastRows
            StatusText  = $spanResult.StatusText
        }
        $results.Add($spanSummary)
        if ($spanStatus -ne 'Pass') {
            throw ("Span harness failed: {0}" -f $spanResult.FailureMessage)
        }
        if ($spanResult.SnapshotRowCount -le 0) {
            throw "Span harness found zero rows for host $SpanHostname."
        }
    }

    if (-not $SkipSearchAlertsHarness) {
        Write-Host "===> Running Search/Alerts smoke harness" -ForegroundColor Cyan
        $searchHarnessPath = Join-Path $repoRoot 'Tools\Invoke-SearchAlertsSmokeTest.ps1'
        if (-not (Test-Path -LiteralPath $searchHarnessPath)) {
            throw "Search/Alerts harness missing at $searchHarnessPath"
        }

        $searchArgs = @(
            '-NoLogo', '-STA',
            '-File', $searchHarnessPath,
            '-RepositoryRoot', $repoRoot,
            '-PassThru',
            '-AsJson',
            '-ForceExit',
            '-TimeoutSeconds', $SearchAlertsTimeoutSeconds,
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

        $json = & pwsh.exe @searchArgs
        $searchExit = $LASTEXITCODE
        if ($searchExit -ne 0) {
            throw ("Search/Alerts harness failed with exit code {0}: {1}" -f $searchExit, ($json -join [Environment]::NewLine))
        }
        if (-not $json) {
            throw "Search/Alerts harness returned no data."
        }

        $jsonLine = $json | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 1
        if (-not $jsonLine) {
            throw "Search/Alerts harness did not return JSON output."
        }

        $searchResult = $jsonLine | ConvertFrom-Json
        $results.Add([pscustomobject]@{
            Check       = 'SearchAlertsHarness'
            Hosts       = $searchResult.HostsAttempted
            SearchCount = $searchResult.SearchCount
            AlertsCount = $searchResult.AlertsCount
            SearchBound = [bool]$searchResult.SearchResultsBound
            AlertsBound = [bool]$searchResult.AlertsResultsBound
        })

        if (-not $searchResult.Success) {
            throw "Search/Alerts harness reported failure."
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
            $results.Add([pscustomobject]@{
                Check            = 'NetOpsLint'
                EvidenceLog      = $netOpsResult.LatestLogPath
                ResetLog         = $netOpsResult.LatestResetLogPath
                SessionReference = $netOpsResult.SessionReferenceSatisfied
            })
        } elseif ($netOpsResult) {
            Write-Host ($netOpsResult.Message) -ForegroundColor DarkGray
            $results.Add([pscustomobject]@{
                Check  = 'NetOpsLint'
                Passed = $true
                Note   = $netOpsResult.Message
            })
        }
    }

    if ($DocSyncTaskId -or $RequireDocSyncChecklist) {
        Write-Host "===> Running doc-sync checklist" -ForegroundColor Cyan
        $docSyncScript = Join-Path $repoRoot 'Tools\Test-DocSyncChecklist.ps1'
        if (-not (Test-Path -LiteralPath $docSyncScript)) {
            throw "Doc-sync checklist script missing at $docSyncScript"
        }
        if ([string]::IsNullOrWhiteSpace($DocSyncTaskId)) {
            throw "Specify -DocSyncTaskId when requesting doc-sync checks."
        }
        if ($RequireDocSyncChecklist -and [string]::IsNullOrWhiteSpace($DocSyncSessionLogPath)) {
            throw "Specify -DocSyncSessionLogPath when using -RequireDocSyncChecklist."
        }

        $docSyncParams = @{
            TaskId   = $DocSyncTaskId
            PassThru = $true
            Quiet    = $true
        }
        if ($RequireDocSyncChecklist) {
            $docSyncParams['RequireSessionLog'] = $true
        }
        if ($DocSyncRequireBacklogEntry) {
            $docSyncParams['RequireBacklogEntry'] = $true
        }
        if (-not [string]::IsNullOrWhiteSpace($DocSyncSessionLogPath)) {
            $docSyncParams['SessionLogPath'] = $DocSyncSessionLogPath
        }
        if (-not [string]::IsNullOrWhiteSpace($DocSyncPlanPath)) {
            $docSyncParams['PlanPath'] = $DocSyncPlanPath
        }

        $docSyncOutput = $DocSyncOutputPath
        if ($RequireDocSyncChecklist -and [string]::IsNullOrWhiteSpace($docSyncOutput)) {
            $docSyncOutput = Join-Path $repoRoot ("Logs\Reports\DocSyncChecklist-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        }
        if (-not [string]::IsNullOrWhiteSpace($docSyncOutput)) {
            $docSyncParams['OutputPath'] = $docSyncOutput
        }

        $docSyncResult = & $docSyncScript @docSyncParams
        $results.Add([pscustomobject]@{
            Check      = 'DocSyncChecklist'
            TaskId     = $DocSyncTaskId
            OutputPath = $docSyncOutput
            Missing    = if ($docSyncResult.Missing) { ($docSyncResult.Missing -join ', ') } else { '' }
        })
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

        $results.Add([pscustomobject]@{
            Check      = 'TelemetryBundle'
            BundlePath = $resolvedBundle
            Areas      = ((@($bundleResult.Area) | Sort-Object -Unique) -join ',')
            Notes      = if ($optionalMissing -and $optionalMissing.Count -gt 0) { 'Optional artifacts missing' } else { 'All required artifacts present' }
        })
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

        $results.Add([pscustomobject]@{
            Check      = 'TelemetryIntegrity'
            ReportPath = $integrityReportPath
            File       = $latestMetrics.FullName
        })
        Write-Host ("Telemetry integrity passed for {0} (report: {1})" -f $latestMetrics.FullName, $integrityReportPath) -ForegroundColor Green
    }
}
finally {
    Pop-Location
}

Write-Host "===> Check summary" -ForegroundColor Green
$results | Format-Table -AutoSize
