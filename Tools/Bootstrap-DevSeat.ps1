<#
.SYNOPSIS
Bootstraps a developer workstation for StateTrace development.

.DESCRIPTION
Installs required PowerShell modules, validates prerequisites, configures
development environment, and runs initial smoke tests.

.PARAMETER SkipModuleInstall
Skip PowerShell module installation (useful if already installed).

.PARAMETER SkipGitHooks
Skip Git pre-commit hook installation.

.PARAMETER SkipValidation
Skip environment validation tests.

.PARAMETER Verbose
Show detailed progress information.

.EXAMPLE
.\Bootstrap-DevSeat.ps1

.EXAMPLE
.\Bootstrap-DevSeat.ps1 -SkipModuleInstall -Verbose
#>

[CmdletBinding()]
param(
    [switch]$SkipModuleInstall,
    [switch]$SkipGitHooks,
    [switch]$SkipValidation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot

# Banner
Write-Host @"

╔═══════════════════════════════════════════════════════════════╗
║           StateTrace Developer Workstation Bootstrap          ║
╚═══════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

$results = [ordered]@{
    PowerShellVersion = $false
    RequiredModules = $false
    DatabaseProvider = $false
    GitConfiguration = $false
    PreCommitHooks = $false
    ProjectStructure = $false
    SmokeTests = $false
}

# Step 1: Check PowerShell Version
Write-Host "[1/7] Checking PowerShell Version..." -ForegroundColor Yellow

$psVersion = $PSVersionTable.PSVersion
Write-Host "  PowerShell $($psVersion.Major).$($psVersion.Minor)" -NoNewline

if ($psVersion.Major -ge 5) {
    Write-Host " ✓" -ForegroundColor Green
    $results.PowerShellVersion = $true
} else {
    Write-Host " ✗ (Requires 5.1+)" -ForegroundColor Red
    Write-Warning "StateTrace requires PowerShell 5.1 or later. Please upgrade."
}

# Step 2: Install Required Modules
Write-Host "`n[2/7] PowerShell Modules..." -ForegroundColor Yellow

$requiredModules = @(
    @{ Name = 'Pester'; MinVersion = '5.0.0' }
    @{ Name = 'PSScriptAnalyzer'; MinVersion = '1.20.0' }
)

$allModulesOk = $true

foreach ($mod in $requiredModules) {
    $installed = Get-Module -ListAvailable -Name $mod.Name |
        Where-Object { $_.Version -ge [version]$mod.MinVersion } |
        Select-Object -First 1

    if ($installed) {
        Write-Host "  $($mod.Name) v$($installed.Version) ✓" -ForegroundColor Green
    } elseif (-not $SkipModuleInstall.IsPresent) {
        Write-Host "  Installing $($mod.Name)..." -ForegroundColor Gray
        try {
            Install-Module -Name $mod.Name -MinimumVersion $mod.MinVersion -Force -Scope CurrentUser -AllowClobber
            Write-Host "  $($mod.Name) installed ✓" -ForegroundColor Green
        } catch {
            Write-Host "  $($mod.Name) FAILED: $_" -ForegroundColor Red
            $allModulesOk = $false
        }
    } else {
        Write-Host "  $($mod.Name) missing (skipped install)" -ForegroundColor Yellow
        $allModulesOk = $false
    }
}

$results.RequiredModules = $allModulesOk

# Step 3: Check Database Provider
Write-Host "`n[3/7] Database Provider (Access/OLEDB)..." -ForegroundColor Yellow

$aceProvider = $null
try {
    $providers = (New-Object System.Data.OleDb.OleDbEnumerator).GetElements() |
        Where-Object { $_.SOURCES_NAME -match 'ACE|Jet' }

    if ($providers) {
        $aceProvider = $providers | Select-Object -First 1
        Write-Host "  Found: $($aceProvider.SOURCES_NAME) ✓" -ForegroundColor Green
        $results.DatabaseProvider = $true
    }
} catch {
    # OleDb enumeration not available
}

if (-not $aceProvider) {
    Write-Host "  No ACE/Jet OLEDB provider found" -ForegroundColor Yellow
    Write-Host "  Download: https://www.microsoft.com/en-us/download/details.aspx?id=54920" -ForegroundColor Gray
    Write-Host "  (Microsoft Access Database Engine 2016 Redistributable)" -ForegroundColor Gray
}

# Step 4: Git Configuration
Write-Host "`n[4/7] Git Configuration..." -ForegroundColor Yellow

$gitOk = $true

# Check if this is a git repo
if (Test-Path (Join-Path $projectRoot '.git')) {
    Write-Host "  Git repository ✓" -ForegroundColor Green

    # Check git user config
    $gitUser = git config user.name 2>$null
    $gitEmail = git config user.email 2>$null

    if ($gitUser -and $gitEmail) {
        Write-Host "  User: $gitUser <$gitEmail> ✓" -ForegroundColor Green
    } else {
        Write-Host "  Git user not configured" -ForegroundColor Yellow
        Write-Host "  Run: git config user.name 'Your Name'" -ForegroundColor Gray
        Write-Host "  Run: git config user.email 'your@email.com'" -ForegroundColor Gray
        $gitOk = $false
    }
} else {
    Write-Host "  Not a git repository" -ForegroundColor Red
    $gitOk = $false
}

$results.GitConfiguration = $gitOk

# Step 5: Pre-commit Hooks
Write-Host "`n[5/7] Pre-commit Hooks..." -ForegroundColor Yellow

$hookPath = Join-Path $projectRoot '.git\hooks\pre-commit'
$hookInstaller = Join-Path $projectRoot 'Tools\Install-PreCommitHooks.ps1'

if (Test-Path $hookPath) {
    Write-Host "  Pre-commit hook installed ✓" -ForegroundColor Green
    $results.PreCommitHooks = $true
} elseif (-not $SkipGitHooks.IsPresent) {
    if (Test-Path $hookInstaller) {
        Write-Host "  Installing pre-commit hooks..." -ForegroundColor Gray
        try {
            & $hookInstaller -Force
            $results.PreCommitHooks = $true
            Write-Host "  Pre-commit hooks installed ✓" -ForegroundColor Green
        } catch {
            Write-Host "  Hook installation failed: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "  Hook installer not found" -ForegroundColor Yellow
    }
} else {
    Write-Host "  Pre-commit hooks skipped" -ForegroundColor Yellow
}

# Step 6: Project Structure
Write-Host "`n[6/7] Project Structure..." -ForegroundColor Yellow

$requiredDirs = @(
    'Data'
    'Logs'
    'Modules'
    'Views'
    'Themes'
    'Tools'
    'Tests'
)

$structureOk = $true
foreach ($dir in $requiredDirs) {
    $path = Join-Path $projectRoot $dir
    if (Test-Path $path) {
        Write-Host "  $dir/ ✓" -ForegroundColor Green
    } else {
        Write-Host "  $dir/ missing - creating..." -ForegroundColor Yellow
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
}

# Create default settings if missing
$settingsPath = Join-Path $projectRoot 'Data\StateTraceSettings.json'
if (-not (Test-Path $settingsPath)) {
    Write-Host "  Creating default StateTraceSettings.json..." -ForegroundColor Yellow
    $defaultSettings = @{
        Theme = 'base'
        LastSite = ''
        RecentFiles = @()
        WindowState = @{
            Width = 1400
            Height = 900
            Left = 100
            Top = 100
            IsMaximized = $false
        }
        FilterPresets = @()
        ColumnOrder = @{}
        CacheTTLMinutes = 30
    }
    $defaultSettings | ConvertTo-Json -Depth 5 | Set-Content -Path $settingsPath -Encoding UTF8
}

$results.ProjectStructure = $structureOk

# Step 7: Smoke Tests
Write-Host "`n[7/7] Smoke Tests..." -ForegroundColor Yellow

if (-not $SkipValidation.IsPresent) {
    $smokeTestOk = $true

    # Test module imports
    $modules = Get-ChildItem -Path (Join-Path $projectRoot 'Modules') -Filter '*.psm1' -File |
        Where-Object { $_.Name -notmatch '\.Tests\.' }

    $importErrors = 0
    foreach ($mod in $modules) {
        try {
            Import-Module $mod.FullName -Force -DisableNameChecking -ErrorAction Stop
            Remove-Module -Name $mod.BaseName -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Host "  $($mod.Name) import failed: $_" -ForegroundColor Red
            $importErrors++
            $smokeTestOk = $false
        }
    }

    if ($importErrors -eq 0) {
        Write-Host "  Module imports ($($modules.Count) modules) ✓" -ForegroundColor Green
    }

    # Validate XAML files
    $xamlFiles = Get-ChildItem -Path (Join-Path $projectRoot 'Views') -Filter '*.xaml' -File -ErrorAction SilentlyContinue
    $xamlErrors = 0
    foreach ($xaml in $xamlFiles) {
        try {
            [xml]$content = Get-Content -Path $xaml.FullName -Raw -ErrorAction Stop
        } catch {
            Write-Host "  $($xaml.Name) parse error: $_" -ForegroundColor Red
            $xamlErrors++
            $smokeTestOk = $false
        }
    }

    if ($xamlErrors -eq 0 -and $xamlFiles.Count -gt 0) {
        Write-Host "  XAML validation ($($xamlFiles.Count) files) ✓" -ForegroundColor Green
    }

    # Validate JSON configs
    $jsonFiles = @(
        'Data\StateTraceSettings.json'
    ) + (Get-ChildItem -Path (Join-Path $projectRoot 'Themes') -Filter '*.json' -File -ErrorAction SilentlyContinue | ForEach-Object { "Themes\$($_.Name)" })

    $jsonErrors = 0
    foreach ($jsonFile in $jsonFiles) {
        $path = Join-Path $projectRoot $jsonFile
        if (Test-Path $path) {
            try {
                Get-Content -Path $path -Raw | ConvertFrom-Json | Out-Null
            } catch {
                Write-Host "  $jsonFile parse error: $_" -ForegroundColor Red
                $jsonErrors++
                $smokeTestOk = $false
            }
        }
    }

    if ($jsonErrors -eq 0) {
        Write-Host "  JSON validation ✓" -ForegroundColor Green
    }

    $results.SmokeTests = $smokeTestOk
} else {
    Write-Host "  Skipped" -ForegroundColor Yellow
}

# Summary
Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "                         SUMMARY                                " -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

$passCount = ($results.Values | Where-Object { $_ -eq $true }).Count
$totalCount = $results.Count

foreach ($item in $results.GetEnumerator()) {
    $status = if ($item.Value) { "✓ PASS" } else { "✗ FAIL" }
    $color = if ($item.Value) { "Green" } else { "Red" }
    Write-Host "  $($item.Key.PadRight(20)) $status" -ForegroundColor $color
}

Write-Host ""
if ($passCount -eq $totalCount) {
    Write-Host "  All checks passed! Your environment is ready." -ForegroundColor Green
    Write-Host ""
    Write-Host "  Next steps:" -ForegroundColor Cyan
    Write-Host "    1. Open StateTrace.sln in your IDE" -ForegroundColor Gray
    Write-Host "    2. Run: .\Tools\Invoke-CIHarness.ps1" -ForegroundColor Gray
    Write-Host "    3. Run: .\Main\MainWindow.ps1" -ForegroundColor Gray
} else {
    Write-Host "  $passCount/$totalCount checks passed." -ForegroundColor Yellow
    Write-Host "  Please address the issues above before developing." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  Documentation: docs/Developer_Onboarding.md" -ForegroundColor Gray
Write-Host "  Troubleshooting: docs/troubleshooting/Common_Failures.md" -ForegroundColor Gray
Write-Host ""

# Return results for automation
return [PSCustomObject]$results
