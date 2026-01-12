Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$scriptPath = Join-Path -Path $repoRoot -ChildPath 'Tools\Schedule-VerificationTask.ps1'

Describe 'Schedule-VerificationTask' {
    It 'builds a scheduled task preview in dry run' {
        $preview = & $scriptPath -TaskName 'StateTraceVerification' -StartTime '03:00' -IncludeTests -SkipParsing -DryRun

        $preview | Should Match 'schtasks\.exe'
        $preview | Should Match '/Create'
        $preview | Should Match '/TN StateTraceVerification'
        $preview | Should Match 'Invoke-StateTraceScheduledVerification\.ps1'
        $preview | Should Match '-IncludeTests'
        $preview | Should Match '-SkipParsing'
    }
}
