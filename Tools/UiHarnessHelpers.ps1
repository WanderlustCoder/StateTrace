Set-StrictMode -Version Latest

# LANDMARK: UI harness preflight - reusable desktop/STA readiness check
function Test-StateTraceUiHarnessPreflight {
    [CmdletBinding()]
    param(
        [switch]$RequireDesktop,
        [switch]$RequireSta,
        [object]$UserInteractiveOverride,
        [object]$ApartmentStateOverride
    )

    $details = [ordered]@{}
    $userInteractive = $null
    if ($PSBoundParameters.ContainsKey('UserInteractiveOverride')) {
        $userInteractive = [bool]$UserInteractiveOverride
    } else {
        try { $userInteractive = [Environment]::UserInteractive } catch { $userInteractive = $false }
    }

    $apartmentState = $null
    if ($PSBoundParameters.ContainsKey('ApartmentStateOverride')) {
        $apartmentState = $ApartmentStateOverride
    } else {
        try { $apartmentState = [System.Threading.Thread]::CurrentThread.ApartmentState } catch { $apartmentState = $null }
    }

    $details.UserInteractive = $userInteractive
    $details.ApartmentState = if ($apartmentState) { $apartmentState.ToString() } else { '' }

    if ($RequireDesktop -and -not $userInteractive) {
        return [pscustomobject]@{
            Status  = 'RequiresDesktop'
            Reason  = 'NonInteractiveSession'
            Details = $details
        }
    }

    if ($RequireSta -and $apartmentState -ne [System.Threading.ApartmentState]::STA) {
        return [pscustomobject]@{
            Status  = 'RequiresSTA'
            Reason  = 'ApartmentStateMismatch'
            Details = $details
        }
    }

    return [pscustomobject]@{
        Status  = 'Ready'
        Reason  = ''
        Details = $details
    }
}

# LANDMARK: ST-D-008 UI smoke report generator
function New-StateTraceUiSmokeReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        [string]$ChecklistPath,
        [string]$PortBatchReportPath,
        [pscustomobject]$PortBatchSummary,
        [string]$PortBatchNote,
        [pscustomobject]$SpanSummary,
        [string]$TemplateHelperReportPath,
        [string[]]$TemplateHelperLines = @()
    )

    $reportLines = @()
    $reportLines += '# UI smoke checklist automation report'
    $reportLines += ''
    $reportLines += ('GeneratedAtUtc: {0}' -f ([DateTime]::UtcNow.ToString('o')))
    if (-not [string]::IsNullOrWhiteSpace($ChecklistPath)) {
        $reportLines += ('ChecklistPath: {0}' -f $ChecklistPath)
    }
    $reportLines += ''

    $reportLines += '## PortBatchReady summary'
    if (-not [string]::IsNullOrWhiteSpace($PortBatchReportPath)) {
        $reportLines += ('- Source: {0}' -f $PortBatchReportPath)
    } else {
        $reportLines += '- Source: Not found'
    }
    if ($PortBatchSummary) {
        $reportLines += ('- EventCount: {0}' -f $PortBatchSummary.EventCount)
        $reportLines += ('- UniqueHosts: {0}' -f $PortBatchSummary.UniqueHosts)
        $reportLines += ('- TotalPorts: {0}' -f $PortBatchSummary.TotalPorts)
        $reportLines += ('- PortsPerMinute: {0}' -f $PortBatchSummary.PortsPerMinute)
        $reportLines += ('- BatchIntervalP95Ms: {0}' -f $PortBatchSummary.BatchIntervalP95Ms)
    } elseif (-not [string]::IsNullOrWhiteSpace($PortBatchNote)) {
        $reportLines += ('- Note: {0}' -f $PortBatchNote)
    } else {
        $reportLines += '- Note: No PortBatchReady summary available.'
    }
    $reportLines += ''

    $reportLines += '## Span snapshot stats'
    if ($SpanSummary) {
        $reportLines += ('- Status: {0}' -f $SpanSummary.Status)
        $reportLines += ('- Hostname: {0}' -f $SpanSummary.Hostname)
        $reportLines += ('- Rows: {0}' -f $SpanSummary.Rows)
        $reportLines += ('- UsedLastRow: {0}' -f $SpanSummary.UsedLastRow)
        if (-not [string]::IsNullOrWhiteSpace($SpanSummary.StatusText)) {
            $reportLines += ('- StatusText: {0}' -f $SpanSummary.StatusText)
        }
    } else {
        $reportLines += '- Note: Span harness not executed or no data available.'
    }
    $reportLines += ''

    $reportLines += '## Template/helper notes'
    if (-not [string]::IsNullOrWhiteSpace($TemplateHelperReportPath)) {
        $reportLines += ('- CatalogReport: {0}' -f $TemplateHelperReportPath)
    } else {
        $reportLines += '- CatalogReport: Not found'
    }
    if ($TemplateHelperLines -and $TemplateHelperLines.Count -gt 0) {
        $reportLines += ('- ChecklistEntries: {0}' -f $TemplateHelperLines.Count)
        foreach ($line in $TemplateHelperLines) {
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                $reportLines += ('  - {0}' -f $line.Trim())
            }
        }
    } else {
        $reportLines += '- ChecklistEntries: None found'
    }
    $reportLines += ''

    $reportDir = Split-Path -Path $OutputPath -Parent
    if (-not (Test-Path -LiteralPath $reportDir)) {
        New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
    }
    $reportLines | Set-Content -LiteralPath $OutputPath -Encoding ASCII

    return [pscustomobject]@{
        OutputPath               = $OutputPath
        PortBatchReportPath      = $PortBatchReportPath
        TemplateHelperReportPath = $TemplateHelperReportPath
    }
}
