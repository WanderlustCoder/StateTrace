# LANDMARK: Queue gate harness policy tests - verify auto-run decision
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$scriptPath = Join-Path -Path $repoRoot -ChildPath 'Tools\Invoke-StateTraceVerification.ps1'

Describe 'Verification queue delay harness policy' {
    BeforeAll {
        $previousSkip = $null
        if (Test-Path -LiteralPath variable:global:StateTraceVerificationSkipMain) {
            $previousSkip = Get-Variable -Name 'StateTraceVerificationSkipMain' -Scope Global -ValueOnly
        }
        Set-Variable -Name 'StateTraceVerificationSkipMain' -Scope Global -Value $true
        . $scriptPath
        if ($null -ne $previousSkip) {
            Set-Variable -Name 'StateTraceVerificationSkipMain' -Scope Global -Value $previousSkip
        } else {
            Remove-Variable -Name 'StateTraceVerificationSkipMain' -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'requests the queue delay harness when metrics path is not supplied' {
        $policy = Resolve-QueueDelayHarnessPolicy -SkipQueueDelayEvaluation:$false -QueueMetricsPath $null
        $policy.ShouldRun | Should Be $true
    }

    It 'does not request the queue delay harness when evaluation is skipped' {
        $policy = Resolve-QueueDelayHarnessPolicy -SkipQueueDelayEvaluation:$true -QueueMetricsPath $null
        $policy.ShouldRun | Should Be $false
    }

    It 'does not request the queue delay harness when QueueMetricsPath is provided' {
        $policy = Resolve-QueueDelayHarnessPolicy -SkipQueueDelayEvaluation:$false -QueueMetricsPath 'Logs\IngestionMetrics\2025-12-24.json'
        $policy.ShouldRun | Should Be $false
    }
}
