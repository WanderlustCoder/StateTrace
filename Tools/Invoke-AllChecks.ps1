[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')),
    [switch]$SkipPester,
    [switch]$SkipSpanHarness,
    [string]$SpanHostname = 'LABS-A01-AS-01',
    [int]$SpanSampleCount = 5
)

Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
Push-Location $repoRoot

$results = @()
try {
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
}
finally {
    Pop-Location
}

Write-Host "===> Check summary" -ForegroundColor Green
$results | Format-Table -AutoSize
