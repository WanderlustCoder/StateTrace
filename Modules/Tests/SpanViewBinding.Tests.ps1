Set-StrictMode -Version Latest

Describe 'Test-SpanViewBinding diagnostics' {
    # LANDMARK: Span view binding tests - validate simulated init failure details
    It 'emits failure diagnostics when SpanView init is simulated to fail' {
        if (-not [Environment]::UserInteractive) {
            Set-TestInconclusive -Message 'Requires interactive desktop session.'
            return
        }

        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path -Path (Split-Path -Parent $PSCommandPath) -ChildPath '..\..'))
        $scriptPath = Join-Path -Path $repoRoot -ChildPath 'Tools\Test-SpanViewBinding.ps1'
        $powershell = Get-Command -Name 'powershell.exe' -ErrorAction SilentlyContinue
        if (-not $powershell) {
            Set-TestInconclusive -Message 'powershell.exe not available.'
            return
        }

        $args = @(
            '-NoProfile', '-STA',
            '-ExecutionPolicy', 'Bypass',
            '-File', $scriptPath,
            '-RepositoryRoot', $repoRoot,
            '-Hostname', 'TEST-SPAN',
            '-EmitDiagnostics',
            '-AsJson',
            '-SimulateSpanViewFailure'
        )

        $raw = & $powershell.Path @args
        $text = if ($raw) { $raw -join [Environment]::NewLine } else { '' }
        $text | Should Not BeNullOrEmpty

        $start = $text.IndexOf('{')
        $end = $text.LastIndexOf('}')
        ($start -ge 0 -and $end -gt $start) | Should Be $true

        $payload = $text.Substring($start, ($end - $start + 1)) | ConvertFrom-Json
        $payload.Status | Should Be 'Fail'
        $payload.Reason | Should Be 'SpanViewInitError'
        $payload.Diagnostics | Should Not BeNullOrEmpty
        $payload.Diagnostics.SpanView.SpanInitError | Should Not BeNullOrEmpty
        $payload.Diagnostics.SpanView.SpanInitError[0].Type | Should Be 'System.InvalidOperationException'
        $payload.Diagnostics.SpanView.SpanInitError[0].Message | Should Match 'Simulated span view initialization failure'
    }
}
