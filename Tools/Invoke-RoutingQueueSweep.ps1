[CmdletBinding()]
param(
    [string[]]$Hosts,
    [string]$HostListPath,
    [string]$BalancedHostListPath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'Data\RoutingHosts_Balanced.txt'),
    [switch]$UseBalancedHostOrder,
    [string]$OutputDirectory = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'Logs\DispatchHarness'),
    [string]$PowerShellPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe",
    [double]$QueueDelayWarningMs = 120,
    [double]$QueueDelayCriticalMs = 200,
    [string]$SummaryPath,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path $PSScriptRoot -Parent

function Get-SitePrefix {
    param([string]$Hostname)
    if ([string]::IsNullOrWhiteSpace($Hostname)) { return '(unknown)' }
    return $Hostname.Split('-', 2, [System.StringSplitOptions]::RemoveEmptyEntries)[0]
}

function Resolve-Hosts {
    param(
        [string[]]$InlineHosts,
        [string]$ListPath,
        [switch]$Balance
    )

    $final = New-Object System.Collections.Generic.List[string]

    if ($ListPath) {
        $resolved = Resolve-Path -LiteralPath $ListPath -ErrorAction Stop
        foreach ($line in Get-Content -LiteralPath $resolved.Path) {
            $trimmed = ('' + $line).Trim()
            if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
                $final.Add($trimmed)
            }
        }
    }

    if ($InlineHosts) {
        foreach ($hostName in $InlineHosts) {
            $trimmed = ('' + $hostName).Trim()
            if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
                $final.Add($trimmed)
            }
        }
    }

    $unique = $final | Select-Object -Unique
    if (-not $unique -or $unique.Count -eq 0) {
        throw 'Provide at least one hostname via -Hosts or -HostListPath.'
    }

    if ($Balance) {
        $grouped = $unique | Group-Object { Get-SitePrefix -Hostname $_ }
        $siteOrder = ($grouped | Sort-Object Name).Name
        $queues = @{}
        foreach ($group in $grouped) {
            $queues[$group.Name] = [System.Collections.Queue]::new()
            foreach ($entry in $group.Group) {
                $queues[$group.Name].Enqueue($entry)
            }
        }

        $balanced = New-Object System.Collections.Generic.List[string]
        while ($true) {
            $progressed = $false
            foreach ($siteName in $siteOrder) {
                $queue = $queues[$siteName]
                if ($null -ne $queue -and $queue.Count -gt 0) {
                    $balanced.Add($queue.Dequeue()) | Out-Null
                    $progressed = $true
                }
            }
            if (-not $progressed) { break }
        }
        return $balanced
    }

    return $unique
}

$balanceHosts = $UseBalancedHostOrder
if ($UseBalancedHostOrder -and -not $HostListPath -and -not $Hosts) {
    if (Test-Path -LiteralPath $BalancedHostListPath) {
        $HostListPath = $BalancedHostListPath
        $balanceHosts = $false
        Write-Verbose ("Using pre-generated balanced host list '{0}'" -f $BalancedHostListPath)
    }
    else {
        throw "Balanced host list '$BalancedHostListPath' not found; provide -HostListPath or -Hosts."
    }
}

if (-not (Test-Path -LiteralPath $PowerShellPath)) {
    throw ("PowerShell executable '{0}' was not found. Use -PowerShellPath to provide a valid Windows PowerShell path." -f $PowerShellPath)
}

$resolvedTargets = Resolve-Hosts -InlineHosts $Hosts -ListPath $HostListPath -Balance:$balanceHosts

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$results = New-Object System.Collections.Generic.List[object]

foreach ($targetHost in $resolvedTargets) {
    $safeName = $targetHost
    [System.IO.Path]::GetInvalidFileNameChars() | ForEach-Object { $safeName = $safeName -replace [Regex]::Escape($_), '-' }
    $logPath = Join-Path -Path $OutputDirectory -ChildPath ("{0}-{1}.log" -f $safeName, $timestamp)

    $args = @(
        '-NoLogo',
        '-STA',
        '-File',
        (Join-Path -Path $repoRoot -ChildPath 'Tools\Invoke-InterfaceDispatchHarness.ps1'),
        '-Hostname', $targetHost,
        '-QueueDelayWarningMs', $QueueDelayWarningMs,
        '-QueueDelayCriticalMs', $QueueDelayCriticalMs,
        '-Verbose'
    )

    $output = & $PowerShellPath @args 2>&1
    $output | Set-Content -LiteralPath $logPath -Encoding utf8
    $exitCode = $LASTEXITCODE

    $delayLine = $output | Select-String -Pattern 'Queue build delay for'
    $delayMs = $null
    $durationMs = $null
    if ($delayLine) {
        $match = [regex]::Match($delayLine[-1], "Queue build delay for '(.+?)':\s+([0-9\.\-]+)\s+ms\s+\(duration\s+([0-9\.\-]+)\s+ms")
        if ($match.Success) {
            $delayMs = [double]$match.Groups[2].Value
            $durationMs = [double]$match.Groups[3].Value
        }
    }

    $results.Add([pscustomobject]@{
            Hostname      = $targetHost
            LogPath       = $logPath
            QueueDelayMs  = $delayMs
            DurationMs    = $durationMs
            ExitCode      = $exitCode
        }) | Out-Null

    if ($exitCode -ne 0) {
        Write-Warning ("Dispatcher harness for '{0}' exited with code {1}; see {2}." -f $targetHost, $exitCode, $logPath)
    } elseif ($delayMs -ne $null) {
        $durationDisplay = if ($durationMs -ne $null) { ('{0:N3}' -f $durationMs) } else { 'n/a' }
        Write-Host ("[{0}] Queue delay {1:N3} ms (duration {2})" -f $targetHost, $delayMs, $durationDisplay) -ForegroundColor Green
    } else {
        Write-Warning ("Dispatcher harness for '{0}' completed but did not emit a queue-delay line; see {1}." -f $targetHost, $logPath)
    }
}

if (-not $SummaryPath) {
    $summaryName = "RoutingQueueSweep-{0}.json" -f $timestamp
    $SummaryPath = Join-Path -Path $OutputDirectory -ChildPath $summaryName
}
$results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $SummaryPath -Encoding utf8
Write-Host ("Sweep summary written to {0}" -f (Resolve-Path -LiteralPath $SummaryPath)) -ForegroundColor DarkCyan

if ($PassThru) {
    return $results
}
else {
    $results | Format-Table -AutoSize
}
