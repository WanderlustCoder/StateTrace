param(
    [switch]$InstallPython = $true,
    [switch]$InstallGraphviz = $true,
    [switch]$InstallGit = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $env:STATETRACE_AGENT_ALLOW_INSTALL) {
    throw "Install capability is disabled. Set STATETRACE_AGENT_ALLOW_INSTALL=1 to proceed."
}

Write-Host "Bootstrapping dev seat with pinned tools..." -ForegroundColor Cyan

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
