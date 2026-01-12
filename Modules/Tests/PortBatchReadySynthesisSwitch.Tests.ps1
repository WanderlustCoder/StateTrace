Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$scriptPaths = @(
    'Tools\Invoke-StateTracePipeline.ps1',
    'Tools\Invoke-StateTraceVerification.ps1',
    'Tools\Invoke-WarmRunTelemetry.ps1',
    'Tools\Invoke-WarmRunRegression.ps1'
) | ForEach-Object { Join-Path -Path $repoRoot -ChildPath $_ }

Describe 'ForcePortBatchReadySynthesis switch' {
    It 'is exposed by each harness entrypoint' {
        foreach ($path in $scriptPaths) {
            (Test-Path -LiteralPath $path) | Should Be $true
            $command = Get-Command -CommandType ExternalScript -Name $path
            $command.Parameters.ContainsKey('ForcePortBatchReadySynthesis') | Should Be $true
        }
    }

    It 'does not default to true' {
        foreach ($path in $scriptPaths) {
            # LANDMARK: PortBatchReady synthesis - verify default remains opt-in
            $content = Get-Content -LiteralPath $path -Raw
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$tokens, [ref]$errors)
            $errorCount = if ($errors) { $errors.Count } else { 0 }
            $errorCount | Should Be 0

            $parameter = $ast.ParamBlock.Parameters |
                Where-Object { $_.Name.VariablePath.UserPath -eq 'ForcePortBatchReadySynthesis' } |
                Select-Object -First 1
            $parameter | Should Not BeNullOrEmpty

            $paramBlockText = $ast.ParamBlock.Extent.Text
            $pattern = 'ForcePortBatchReadySynthesis\s*=\s*\$true'
            ([regex]::IsMatch($paramBlockText, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) | Should Be $false
        }
    }
}
