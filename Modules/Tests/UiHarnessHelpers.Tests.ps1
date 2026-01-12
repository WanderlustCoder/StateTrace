Set-StrictMode -Version Latest

$repoRoot = Resolve-Path -Path (Join-Path -Path (Split-Path -Parent $PSCommandPath) -ChildPath '..\..')
$helpersPath = Join-Path -Path $repoRoot -ChildPath 'Tools\UiHarnessHelpers.ps1'
. $helpersPath

# LANDMARK: ST-D-008 UI smoke report tests
Describe 'New-StateTraceUiSmokeReport' {
    It 'writes a UI smoke report with the expected sections' {
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'UI-Smoke.md'
        $portBatchSummary = [pscustomobject]@{
            EventCount         = 3
            UniqueHosts        = 2
            TotalPorts         = 10
            PortsPerMinute     = 1200
            BatchIntervalP95Ms = 450
        }
        $spanSummary = [pscustomobject]@{
            Status      = 'Pass'
            Hostname    = 'BOYO-A01'
            Rows        = 5
            UsedLastRow = $true
            StatusText  = 'Rows: 5'
        }
        $templateLines = @(
            'Templates tab: load template',
            'Helper overlay notes'
        )

        New-StateTraceUiSmokeReport -OutputPath $outputPath `
            -ChecklistPath 'docs/UI_Smoke_Checklist.md' `
            -PortBatchReportPath 'Logs/Reports/PortBatchReady-smoke.json' `
            -PortBatchSummary $portBatchSummary `
            -SpanSummary $spanSummary `
            -TemplateHelperReportPath 'Logs/Reports/TemplateHelperCatalog.md' `
            -TemplateHelperLines $templateLines | Out-Null

        $content = Get-Content -LiteralPath $outputPath
        $contentText = $content -join [Environment]::NewLine
        $contentText | Should Match '## PortBatchReady summary'
        $contentText | Should Match 'EventCount: 3'
        $contentText | Should Match '## Span snapshot stats'
        $contentText | Should Match 'Rows: 5'
        $contentText | Should Match '## Template/helper notes'
        $contentText | Should Match 'Templates tab: load template'
    }
}
