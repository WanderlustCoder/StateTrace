param(
    [switch]$InstallPython = $true,
    [switch]$InstallGraphviz = $true,
    [switch]$InstallGit = $true,
    # ST-K-002: Validation-only mode (no installs)
    [switch]$ValidateOnly,
    # ST-K-002: Output session log path
    [string]$SessionLogPath
)

<#
.SYNOPSIS
Bootstraps and validates a developer workstation for StateTrace development.

.DESCRIPTION
Validates execution policy, required PowerShell modules, and tracked fixture seeds.
Optionally installs pinned tool versions via winget. Emits remediation steps for any
failures and can log validation results to docs/agents/sessions/.

.PARAMETER ValidateOnly
ST-K-002: Run validation checks only without installing any software.

.PARAMETER SessionLogPath
ST-K-002: Path to write validation/bootstrap session log (JSON).

.EXAMPLE
pwsh Tools\Bootstrap-DevSeat.ps1 -ValidateOnly
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot

# ST-K-002: Validation results collector
$script:ValidationResults = [System.Collections.Generic.List[pscustomobject]]::new()
$script:RemediationSteps = [System.Collections.Generic.List[string]]::new()

function Add-ValidationResult {
    param(
        [string]$Check,
        [bool]$Passed,
        [string]$Details,
        [string]$Remediation
    )
    $script:ValidationResults.Add([pscustomobject]@{
        Check = $Check
        Passed = $Passed
        Details = $Details
        Remediation = $Remediation
    })
    if (-not $Passed -and $Remediation) {
        $script:RemediationSteps.Add($Remediation)
    }
}

# ST-K-002: Validate execution policy
function Test-ExecutionPolicy {
    $policy = Get-ExecutionPolicy -Scope CurrentUser
    $acceptable = @('RemoteSigned', 'Unrestricted', 'Bypass')
    $passed = $acceptable -contains $policy
    Add-ValidationResult -Check 'ExecutionPolicy' -Passed $passed `
        -Details "CurrentUser policy: $policy" `
        -Remediation "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser"
    return $passed
}

# ST-K-002: Validate required PowerShell modules
function Test-RequiredModules {
    $requiredModules = @(
        @{ Name = 'Pester'; MinVersion = '3.4.0' }
    )
    $allPassed = $true
    foreach ($mod in $requiredModules) {
        $installed = Get-Module -ListAvailable -Name $mod.Name | Sort-Object Version -Descending | Select-Object -First 1
        if ($installed) {
            $passed = $installed.Version -ge [version]$mod.MinVersion
            Add-ValidationResult -Check "Module:$($mod.Name)" -Passed $passed `
                -Details "Found version $($installed.Version), required >= $($mod.MinVersion)" `
                -Remediation "Install-Module -Name $($mod.Name) -MinimumVersion $($mod.MinVersion) -Scope CurrentUser -Force"
        } else {
            Add-ValidationResult -Check "Module:$($mod.Name)" -Passed $false `
                -Details "Not installed" `
                -Remediation "Install-Module -Name $($mod.Name) -MinimumVersion $($mod.MinVersion) -Scope CurrentUser -Force"
            $allPassed = $false
        }
    }
    return $allPassed
}

# ST-K-002: Validate tracked fixture seeds
function Test-FixtureSeeds {
    $requiredFixtures = @(
        'Tests/Fixtures/CISmoke/IngestionMetrics.json',
        'Tests/Fixtures/CISmoke/WarmRunTelemetry.json',
        'Tests/Fixtures/manifests/CISmoke.json'
    )
    $allPassed = $true
    foreach ($fixture in $requiredFixtures) {
        $fullPath = Join-Path -Path $repositoryRoot -ChildPath $fixture
        $exists = Test-Path -LiteralPath $fullPath
        Add-ValidationResult -Check "Fixture:$fixture" -Passed $exists `
            -Details $(if ($exists) { "Present" } else { "Missing" }) `
            -Remediation "git checkout -- $fixture"
        if (-not $exists) { $allPassed = $false }
    }
    return $allPassed
}

# ST-K-002: Run all validation checks
Write-Host "Running developer seat validation checks..." -ForegroundColor Cyan

$execPolicyOk = Test-ExecutionPolicy
$modulesOk = Test-RequiredModules
$fixturesOk = Test-FixtureSeeds

$overallPassed = $execPolicyOk -and $modulesOk -and $fixturesOk

# Display results
Write-Host "`nValidation Results:" -ForegroundColor White
foreach ($result in $script:ValidationResults) {
    $color = if ($result.Passed) { 'Green' } else { 'Red' }
    $status = if ($result.Passed) { '[PASS]' } else { '[FAIL]' }
    Write-Host "  $status $($result.Check): $($result.Details)" -ForegroundColor $color
}

if ($script:RemediationSteps.Count -gt 0) {
    Write-Host "`nRemediation Steps:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $script:RemediationSteps.Count; $i++) {
        Write-Host "  $($i + 1). $($script:RemediationSteps[$i])" -ForegroundColor Yellow
    }
}

# ST-K-002: Write session log
if ($SessionLogPath) {
    $sessionDir = Split-Path -Path $SessionLogPath -Parent
    if ($sessionDir -and -not (Test-Path -LiteralPath $sessionDir)) {
        New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null
    }
    $sessionLog = [pscustomobject]@{
        Timestamp = (Get-Date).ToString('o')
        OverallPassed = $overallPassed
        ValidationResults = $script:ValidationResults
        RemediationSteps = $script:RemediationSteps
        PSVersion = $PSVersionTable.PSVersion.ToString()
        OSVersion = [System.Environment]::OSVersion.VersionString
    }
    $sessionLog | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $SessionLogPath -Encoding utf8
    Write-Host "`nSession log written to: $SessionLogPath" -ForegroundColor DarkCyan
}

if ($ValidateOnly) {
    if ($overallPassed) {
        Write-Host "`nValidation passed - dev seat ready." -ForegroundColor Green
    } else {
        Write-Host "`nValidation failed - see remediation steps above." -ForegroundColor Red
    }
    return
}

# Original install logic (requires explicit env var)
if (-not $env:STATETRACE_AGENT_ALLOW_INSTALL) {
    if (-not $overallPassed) {
        throw "Validation failed and install capability is disabled. Set STATETRACE_AGENT_ALLOW_INSTALL=1 to proceed with installs."
    }
    Write-Host "`nValidation passed. Skipping installs (STATETRACE_AGENT_ALLOW_INSTALL not set)." -ForegroundColor Green
    return
}

Write-Host "`nBootstrapping dev seat with pinned tools..." -ForegroundColor Cyan

function Install-WithWinget {
    param([string]$Id, [string]$Version)
    $args = @("install","--id",$Id,"--exact","--source","winget","--accept-package-agreements","--accept-source-agreements")
    if ($Version) { $args += @("--version",$Version) }
    Write-Host ("winget " + ($args -join ' '))
    winget @args
}

# Python (for scripts/metrics tooling)
if ($InstallPython) {
    Install-WithWinget -Id "Python.Python.3.11" -Version "3.11.9"
}

# Graphviz (for diagrams)
if ($InstallGraphviz) {
    Install-WithWinget -Id "Graphviz.Graphviz" -Version "12.2.0"
}

# Git (for tooling and submodules)
if ($InstallGit) {
    Install-WithWinget -Id "Git.Git" -Version "2.46.0"
}

Write-Host "Bootstrap complete." -ForegroundColor Green
