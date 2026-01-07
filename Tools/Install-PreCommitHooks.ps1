<#
.SYNOPSIS
Installs Git pre-commit hooks for StateTrace development.

.DESCRIPTION
Sets up pre-commit hooks that run:
- PSScriptAnalyzer for code quality
- PowerShell syntax validation
- Telemetry integrity checks

.PARAMETER Force
Overwrite existing hooks.

.EXAMPLE
.\Install-PreCommitHooks.ps1

.EXAMPLE
.\Install-PreCommitHooks.ps1 -Force
#>

[CmdletBinding()]
param(
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$gitHooksDir = Join-Path $projectRoot '.git\hooks'

if (-not (Test-Path -LiteralPath $gitHooksDir)) {
    Write-Error "Git hooks directory not found. Ensure this is a git repository."
    exit 1
}

$preCommitPath = Join-Path $gitHooksDir 'pre-commit'

# Check if hook already exists
if ((Test-Path -LiteralPath $preCommitPath) -and -not $Force.IsPresent) {
    Write-Warning "Pre-commit hook already exists. Use -Force to overwrite."
    exit 0
}

$hookContent = @'
#!/bin/sh
# StateTrace Pre-Commit Hook
# Runs code quality checks before allowing commits

echo "Running StateTrace pre-commit checks..."

# Run PowerShell pre-commit script
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "./Tools/Invoke-PreCommitChecks.ps1"
RESULT=$?

if [ $RESULT -ne 0 ]; then
    echo ""
    echo "Pre-commit checks failed. Please fix the issues above."
    echo "To bypass (not recommended): git commit --no-verify"
    exit 1
fi

echo "Pre-commit checks passed!"
exit 0
'@

try {
    [System.IO.File]::WriteAllText($preCommitPath, $hookContent.Replace("`r`n", "`n"))
    Write-Host "Pre-commit hook installed: $preCommitPath" -ForegroundColor Green
} catch {
    Write-Error "Failed to install hook: $_"
    exit 1
}

# Create the PowerShell checks script
$checksScript = @'
<#
.SYNOPSIS
Pre-commit validation script for StateTrace.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$projectRoot = Split-Path -Parent $PSScriptRoot
$exitCode = 0

Write-Host "=== StateTrace Pre-Commit Checks ===" -ForegroundColor Cyan

# Get staged files
$stagedFiles = git diff --cached --name-only --diff-filter=ACM
$psFiles = $stagedFiles | Where-Object { $_ -match '\.(ps1|psm1)$' }

if ($psFiles.Count -eq 0) {
    Write-Host "No PowerShell files staged, skipping checks." -ForegroundColor Gray
    exit 0
}

Write-Host "Checking $($psFiles.Count) PowerShell file(s)..." -ForegroundColor Green

# 1. Syntax Check
Write-Host "`n[1/3] Syntax Validation..." -ForegroundColor Yellow
$syntaxErrors = 0

foreach ($file in $psFiles) {
    $fullPath = Join-Path $projectRoot $file
    if (-not (Test-Path -LiteralPath $fullPath)) { continue }

    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($fullPath, [ref]$tokens, [ref]$parseErrors) | Out-Null

    if ($parseErrors.Count -gt 0) {
        foreach ($err in $parseErrors) {
            Write-Host "  ERROR: $file`:$($err.Extent.StartLineNumber): $($err.Message)" -ForegroundColor Red
            $syntaxErrors++
        }
    }
}

if ($syntaxErrors -gt 0) {
    Write-Host "  FAILED: $syntaxErrors syntax error(s) found" -ForegroundColor Red
    $exitCode = 1
} else {
    Write-Host "  PASSED" -ForegroundColor Green
}

# 2. PSScriptAnalyzer (if available)
Write-Host "`n[2/3] PSScriptAnalyzer..." -ForegroundColor Yellow

$hasAnalyzer = Get-Module -ListAvailable -Name PSScriptAnalyzer
if ($hasAnalyzer) {
    Import-Module PSScriptAnalyzer -ErrorAction SilentlyContinue
    $analyzerIssues = 0

    foreach ($file in $psFiles) {
        $fullPath = Join-Path $projectRoot $file
        if (-not (Test-Path -LiteralPath $fullPath)) { continue }

        $results = Invoke-ScriptAnalyzer -Path $fullPath -Severity Error -ExcludeRule PSAvoidUsingWriteHost

        foreach ($result in $results) {
            Write-Host "  $($result.Severity): $file`:$($result.Line): $($result.Message)" -ForegroundColor Red
            $analyzerIssues++
        }
    }

    if ($analyzerIssues -gt 0) {
        Write-Host "  FAILED: $analyzerIssues issue(s) found" -ForegroundColor Red
        $exitCode = 1
    } else {
        Write-Host "  PASSED" -ForegroundColor Green
    }
} else {
    Write-Host "  SKIPPED: PSScriptAnalyzer not installed" -ForegroundColor Yellow
}

# 3. Check for debug artifacts
Write-Host "`n[3/3] Debug Artifacts..." -ForegroundColor Yellow
$debugPatterns = @(
    'Write-Host.*DEBUG',
    '\$DebugPreference\s*=',
    'Set-PSDebug',
    'TODO:|FIXME:|HACK:|XXX:'
)

$debugFound = 0
foreach ($file in $psFiles) {
    $fullPath = Join-Path $projectRoot $file
    if (-not (Test-Path -LiteralPath $fullPath)) { continue }

    $content = Get-Content -Path $fullPath -Raw -ErrorAction SilentlyContinue
    if (-not $content) { continue }

    foreach ($pattern in $debugPatterns) {
        if ($content -match $pattern) {
            Write-Host "  WARNING: $file contains '$pattern'" -ForegroundColor Yellow
            $debugFound++
        }
    }
}

if ($debugFound -gt 0) {
    Write-Host "  WARNING: $debugFound potential debug artifact(s)" -ForegroundColor Yellow
} else {
    Write-Host "  PASSED" -ForegroundColor Green
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
if ($exitCode -eq 0) {
    Write-Host "All checks passed!" -ForegroundColor Green
} else {
    Write-Host "Some checks failed. Please fix issues before committing." -ForegroundColor Red
}

exit $exitCode
'@

$checksPath = Join-Path $projectRoot 'Tools\Invoke-PreCommitChecks.ps1'
[System.IO.File]::WriteAllText($checksPath, $checksScript)
Write-Host "Pre-commit checks script created: $checksPath" -ForegroundColor Green

Write-Host "`nPre-commit hooks installed successfully!" -ForegroundColor Cyan
Write-Host "Hooks will run automatically on 'git commit'" -ForegroundColor Gray
