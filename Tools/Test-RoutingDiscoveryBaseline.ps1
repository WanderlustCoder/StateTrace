[CmdletBinding()]
param(
    [string]$HostListPath,
    [string]$BalancedHostListPath,
    [string]$OutputPath,
    [switch]$UpdateLatest,
    [switch]$PassThru,
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RepoPath {
    param(
        [string]$PathValue,
        [string]$RepoRoot
    )
    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $null
    }
    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return $PathValue
    }
    return (Join-Path -Path $RepoRoot -ChildPath $PathValue)
}

function Get-HostEntries {
    param(
        [string]$PathValue
    )
    if (-not (Test-Path -LiteralPath $PathValue)) {
        return [pscustomobject]@{
            Exists  = $false
            Hosts   = @()
            Duplicates = @()
        }
    }

    $raw = Get-Content -LiteralPath $PathValue -ErrorAction Stop |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') }

    $groups = $raw | Group-Object -CaseSensitive:$false
    $duplicates = @($groups | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })

    return [pscustomobject]@{
        Exists  = $true
        Hosts   = @($raw)
        Duplicates = $duplicates
    }
}

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$defaultHostList = Join-Path -Path $repoRoot -ChildPath 'Data\RoutingHosts.txt'
$defaultBalancedList = Join-Path -Path $repoRoot -ChildPath 'Data\RoutingHosts_Balanced.txt'
$defaultOutput = Join-Path -Path $repoRoot -ChildPath ("Logs\Reports\RoutingDiscoveryBaseline-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$latestOutput = Join-Path -Path $repoRoot -ChildPath 'Logs\Reports\RoutingDiscoveryBaseline-latest.json'

$hostPathValue = if ([string]::IsNullOrWhiteSpace($HostListPath)) { $defaultHostList } else { $HostListPath }
$balancedPathValue = if ([string]::IsNullOrWhiteSpace($BalancedHostListPath)) { $defaultBalancedList } else { $BalancedHostListPath }
$outputPathValue = if ([string]::IsNullOrWhiteSpace($OutputPath)) { $defaultOutput } else { $OutputPath }

$resolvedHostList = Resolve-RepoPath -PathValue $hostPathValue -RepoRoot $repoRoot
$resolvedBalancedList = Resolve-RepoPath -PathValue $balancedPathValue -RepoRoot $repoRoot
$resolvedOutput = Resolve-RepoPath -PathValue $outputPathValue -RepoRoot $repoRoot

# LANDMARK: Routing discovery baseline - validate routing host lists and emit summary
$hostList = Get-HostEntries -PathValue $resolvedHostList
$balancedList = Get-HostEntries -PathValue $resolvedBalancedList

$errors = @()
if (-not $hostList.Exists) { $errors += "HostListMissing:$resolvedHostList" }
if ($hostList.Exists -and $hostList.Hosts.Count -eq 0) { $errors += 'HostListEmpty' }
if ($hostList.Duplicates.Count -gt 0) { $errors += ('HostListDuplicates:' + ($hostList.Duplicates -join ',')) }

if (-not $balancedList.Exists) { $errors += "BalancedHostListMissing:$resolvedBalancedList" }
if ($balancedList.Exists -and $balancedList.Hosts.Count -eq 0) { $errors += 'BalancedHostListEmpty' }
if ($balancedList.Duplicates.Count -gt 0) { $errors += ('BalancedHostListDuplicates:' + ($balancedList.Duplicates -join ',')) }

$hostSet = @()
if ($hostList.Hosts.Count -gt 0) {
    $hostSet = @($hostList.Hosts | ForEach-Object { $_.ToUpperInvariant() } | Sort-Object -Unique)
}
$balancedSet = @()
if ($balancedList.Hosts.Count -gt 0) {
    $balancedSet = @($balancedList.Hosts | ForEach-Object { $_.ToUpperInvariant() } | Sort-Object -Unique)
}

$missingInBalanced = @()
$extraInBalanced = @()
if ($hostSet.Count -gt 0 -and $balancedSet.Count -gt 0) {
    $missingInBalanced = @($hostSet | Where-Object { $balancedSet -notcontains $_ })
    $extraInBalanced = @($balancedSet | Where-Object { $hostSet -notcontains $_ })
    if ($missingInBalanced.Count -gt 0) { $errors += ('BalancedListMissingHosts:' + ($missingInBalanced -join ',')) }
    if ($extraInBalanced.Count -gt 0) { $errors += ('BalancedListExtraHosts:' + ($extraInBalanced -join ',')) }
}

function Get-SiteCounts {
    param([string[]]$Hosts)
    if (-not $Hosts) {
        return @()
    }
    return @($Hosts) |
        ForEach-Object { ($_ -split '-')[0].ToUpperInvariant() } |
        Group-Object |
        Sort-Object Name |
        ForEach-Object { [pscustomobject]@{ Site = $_.Name; Count = $_.Count } }
}

$summary = [ordered]@{
    Timestamp = (Get-Date).ToString('o')
    HostList = [ordered]@{
        Path = $resolvedHostList
        Count = $hostList.Hosts.Count
        UniqueCount = $hostSet.Count
        DuplicateHosts = $hostList.Duplicates
        SiteCounts = Get-SiteCounts -Hosts $hostList.Hosts
    }
    BalancedHostList = [ordered]@{
        Path = $resolvedBalancedList
        Count = $balancedList.Hosts.Count
        UniqueCount = $balancedSet.Count
        DuplicateHosts = $balancedList.Duplicates
        MissingHosts = $missingInBalanced
        ExtraHosts = $extraInBalanced
        SiteCounts = Get-SiteCounts -Hosts $balancedList.Hosts
    }
    Errors = $errors
    Passed = ($errors.Count -eq 0)
}

$outputDirectory = Split-Path -Path $resolvedOutput -Parent
if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $resolvedOutput -Encoding utf8

if ($UpdateLatest -or -not $OutputPath) {
    Copy-Item -LiteralPath $resolvedOutput -Destination $latestOutput -Force
}

if (-not $Quiet) {
    Write-Host ("Routing discovery baseline summary written to {0}" -f $resolvedOutput) -ForegroundColor DarkCyan
    if ($UpdateLatest -or -not $OutputPath) {
        Write-Host ("Routing discovery baseline latest summary updated at {0}" -f $latestOutput) -ForegroundColor DarkCyan
    }
}

if (-not $summary.Passed) {
    throw ("Routing discovery baseline failed: {0}" -f ($errors -join '; '))
}

if ($PassThru) {
    return [pscustomobject]$summary
}
