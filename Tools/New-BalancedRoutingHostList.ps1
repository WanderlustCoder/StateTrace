[CmdletBinding()]
param(
    [string]$InputPath = (Join-Path -Path $PSScriptRoot -ChildPath '..\Data\RoutingHosts.txt'),
    [string]$OutputPath = (Join-Path -Path $PSScriptRoot -ChildPath '..\Data\RoutingHosts_Balanced.txt'),
    [string[]]$SiteOrder,
    [switch]$PassThru
)

<#
.SYNOPSIS
Generates a round-robin routing host order so sweeps alternate sites.

.DESCRIPTION
Reads `Data\RoutingHosts.txt` (or a custom file), groups hosts by their site prefix (up to the first dash), and emits a
balanced list by walking the site groups in order. Each pass dequeues one host per site, ensuring sweeps no longer run
all WLLS entries before BOYO. Use `-SiteOrder` to force a custom rotation (default is alphabetical). Writes the new
order to `Data\RoutingHosts_Balanced.txt` by default.

.EXAMPLE
pwsh Tools\New-BalancedRoutingHostList.ps1

Creates `Data\RoutingHosts_Balanced.txt` with the balanced order and prints the first few hosts.

.EXAMPLE
pwsh Tools\New-BalancedRoutingHostList.ps1 -SiteOrder WLLS,BOYO -OutputPath Data\RoutingHosts_Fair.txt -PassThru

Generates a WLLS→BOYO rotation, writes it to `Data\RoutingHosts_Fair.txt`, and returns the ordered list to the pipeline.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

trap {
    Write-Error ("[BalancedHosts] Line {0}: {1}" -f $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message)
    break
}

function Get-SitePrefix {
    param([string]$Hostname)
    if ([string]::IsNullOrWhiteSpace($Hostname)) { return '(unknown)' }
    $parts = $Hostname.Split('-', 2, [System.StringSplitOptions]::RemoveEmptyEntries)
    if ($parts.Count -gt 0) { return $parts[0] }
    return $Hostname
}

if (-not (Test-Path -LiteralPath $InputPath)) {
    throw "Input host file '$InputPath' not found."
}

$hostEntries = @(Get-Content -LiteralPath $InputPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($hostEntries.Count -eq 0) {
    throw "Input host file '$InputPath' does not contain any host entries."
}

$grouped = $hostEntries | Group-Object { Get-SitePrefix -Hostname $_ }

if ($SiteOrder -and $SiteOrder.Count -eq 1) {
    $SiteOrder = $SiteOrder[0] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

$orderedSiteNames = if ($SiteOrder -and $SiteOrder.Count -gt 0) {
    @($SiteOrder)
}
else {
    @(($grouped | Sort-Object Name).Name)
}

Write-Verbose ("Site rotation order: {0}" -f ($orderedSiteNames -join ','))
Write-Verbose ("Site order array type: {0}" -f $orderedSiteNames.GetType().FullName)

$queues = @{}
foreach ($group in $grouped) {
    $queues[$group.Name] = [System.Collections.Queue]::new()
    foreach ($entry in $group.Group) {
        $queues[$group.Name].Enqueue($entry)
    }
}

function Invoke-RoundRobin {
    param([string[]]$SiteNames, [hashtable]$SiteQueues)

    $orderedList = [System.Collections.Generic.List[string]]::new()
    while ($true) {
        $progressed = $false
        foreach ($site in $SiteNames) {
            $queue = $SiteQueues[$site]
            if ($null -ne $queue -and $queue.Count -gt 0) {
                $orderedList.Add($queue.Dequeue()) | Out-Null
                $progressed = $true
            }
        }

        if (-not $progressed) { break }
    }
    return $orderedList
}

function Invoke-SegmentedDistribution {
    param(
        [string[]]$SiteNames,
        [hashtable]$SiteQueues
    )

    $primarySite = $SiteNames[0]
    $otherSites = @($SiteNames | Where-Object { $_ -ne $primarySite })
    $primaryQueue = $SiteQueues[$primarySite]
    $primaryCount = if ($primaryQueue) { $primaryQueue.Count } else { 0 }
    $otherHostQueue = [System.Collections.Queue]::new()
    $otherTotal = 0

    foreach ($site in $otherSites) {
        $queue = $SiteQueues[$site]
        if (-not $queue) { continue }
        $otherTotal += $queue.Count
        while ($queue.Count -gt 0) {
            $otherHostQueue.Enqueue($queue.Dequeue())
        }
    }

    $segmentCount = if ($otherTotal -gt 0) { $otherTotal + 1 } else { 1 }
    $baseSegmentSize = if ($segmentCount -gt 0) { [math]::Floor($primaryCount / $segmentCount) } else { $primaryCount }
    $remainder = if ($segmentCount -gt 0) { $primaryCount % $segmentCount } else { 0 }

    $segments = [System.Collections.ArrayList]::new()
    for ($i = 0; $i -lt $segmentCount; $i++) {
        $segment = [System.Collections.ArrayList]::new()
        $segmentSize = $baseSegmentSize
        if ($i -lt $remainder) { $segmentSize++ }
        for ($j = 0; $j -lt $segmentSize; $j++) {
            if ($primaryQueue -and $primaryQueue.Count -gt 0) {
                [void]$segment.Add($primaryQueue.Dequeue())
            }
        }
        [void]$segments.Add($segment)
    }

    $orderedList = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $segments.Count; $i++) {
        foreach ($segmentEntry in $segments[$i]) {
            $orderedList.Add([string]$segmentEntry) | Out-Null
        }

        if ($otherHostQueue.Count -gt 0) {
            $nextOther = [string]$otherHostQueue.Dequeue()
            $orderedList.Add($nextOther) | Out-Null
        }
    }

    while ($otherHostQueue.Count -gt 0) {
        $nextOther = [string]$otherHostQueue.Dequeue()
        $orderedList.Add($nextOther) | Out-Null
    }

    return $orderedList
}

$result = $null
$primarySiteName = $orderedSiteNames[0]
$otherSiteNames = @($orderedSiteNames | Where-Object { $_ -ne $primarySiteName })
$otherSiteCount = $otherSiteNames.Count
$primaryQueue = $queues[$primarySiteName]
$primaryCount = if ($primaryQueue) { $primaryQueue.Count } else { 0 }
$otherTotalCount = 0
foreach ($site in $otherSiteNames) {
    $queue = $queues[$site]
    if ($queue) { $otherTotalCount += $queue.Count }
}

if ($otherSiteCount -gt 0 -and $primaryCount -gt ($otherTotalCount + 1)) {
    Write-Verbose ("Primary site '{0}' has {1} hosts versus {2} across other sites; applying segmented distribution." -f `
            $primarySiteName, $primaryCount, $otherTotalCount)
    $result = Invoke-SegmentedDistribution -SiteNames $orderedSiteNames -SiteQueues $queues
}
else {
    $result = Invoke-RoundRobin -SiteNames $orderedSiteNames -SiteQueues $queues
}

if ($result.Count -ne $hostEntries.Count) {
    throw "Balanced list generated only $($result.Count) entries (expected $($hostEntries.Count))."
}

$outputDir = Split-Path -Path $OutputPath -Parent
if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}
$result | Set-Content -LiteralPath $OutputPath -Encoding ascii
Write-Host ("Balanced host list written to {0}" -f (Resolve-Path -LiteralPath $OutputPath)) -ForegroundColor DarkCyan

Write-Host "Preview (first 12 hosts):" -ForegroundColor Cyan
$result | Select-Object -First 12 | ForEach-Object { Write-Host $_ }

if ($PassThru) {
    return $result
}
