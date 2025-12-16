[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')),
    [string[]]$Hostnames,
    [string[]]$SiteFilter = @(),
    [int]$MaxHosts = 12,
    [string]$OutputPath,
    [string]$SummaryPath,
    [switch]$PassThru
)

<#
.SYNOPSIS
Runs the Interfaces view (WPF) headlessly so incremental-loading UI evidence can be captured without an interactive desktop.

.DESCRIPTION
Loads the Interfaces view inside a hidden window, cycles through the requested host list,
and streams interface batches exactly as `Main/MainWindow.ps1` would. Each host load
binds the view, drives `DeviceRepositoryModule\Initialize-InterfacePortStream`,
and appends the batches via the WPF dispatcher so telemetry (`PortBatchReady`,
`InterfaceSyncTiming`, `DeviceDetailsLoadMetrics`) is captured along the normal UI path.

.EXAMPLE
pwsh -NoLogo -STA -File Tools\Invoke-InterfacesViewChecklist.ps1 -SiteFilter WLLS,BOYO -MaxHosts 10 -OutputPath Logs\Reports\InterfacesViewChecklist.json
#>

Set-StrictMode -Version Latest
$scriptWatch = [System.Diagnostics.Stopwatch]::StartNew()
$firstRenderMs = $null

if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne [System.Threading.ApartmentState]::STA) {
    throw "Invoke-InterfacesViewChecklist.ps1 must run in STA mode. Re-run with 'pwsh -NoLogo -STA -File Tools\Invoke-InterfacesViewChecklist.ps1 ...'."
}

$SiteFilter = if ($SiteFilter -and $SiteFilter.Count -eq 1) {
    @($SiteFilter[0] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
} else {
    @($SiteFilter)
}

$repoRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$modulesDir = Join-Path $repoRoot 'Modules'
$moduleLoaderPath = Join-Path $modulesDir 'ModuleLoaderModule.psm1'
if (-not (Test-Path -LiteralPath $moduleLoaderPath)) {
    throw "Module loader not found at '$moduleLoaderPath'."
}
Import-Module -Name $moduleLoaderPath -Force -ErrorAction Stop | Out-Null
ModuleLoaderModule\Import-StateTraceModulesFromManifest -RepositoryRoot $repoRoot | Out-Null

Add-Type -AssemblyName PresentationFramework -ErrorAction Stop

if (-not [System.Windows.Application]::Current) {
    $app = New-Object System.Windows.Application
    $app.ShutdownMode = 'OnExplicitShutdown'
}

$windowXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Interfaces Checklist"
        Height="620"
        Width="960"
        Visibility="Hidden"
        ShowInTaskbar="False">
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <TextBlock x:Name="StatusText"
                   Margin="10"
                   FontSize="14"
                   FontWeight="Bold"
                   Text="Interfaces view automation"/>
        <ContentControl x:Name="InterfacesHost"
                        Grid.Row="1"/>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlTextReader (New-Object System.IO.StringReader($windowXaml))
$window = [Windows.Markup.XamlReader]::Load($reader)
Set-Variable -Scope Global -Name window -Value $window -Force

InterfaceModule\New-InterfacesView -Window $window

$routingHostsPaths = @(
    (Join-Path $repoRoot 'Data\RoutingHosts_Balanced.txt'),
    (Join-Path $repoRoot 'Data\RoutingHosts.txt')
)

function Get-HostsFromRoutingFiles {
    $hosts = @()
    foreach ($path in $routingHostsPaths) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $entries = Get-Content -LiteralPath $path | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        if ($entries) {
            $hosts = $entries
            break
        }
    }
    return @($hosts)
}

function Get-SitePrefix {
    param([string]$Hostname)
    if ([string]::IsNullOrWhiteSpace($Hostname)) { return '(unknown)' }
    $segments = $Hostname.Split('-', 2, [System.StringSplitOptions]::RemoveEmptyEntries)
    if ($segments.Count -gt 0) { return $segments[0] }
    return $Hostname
}

function Get-SiteFreshnessInfo {
    param([string]$Site, [string]$RepoRoot)
    if ([string]::IsNullOrWhiteSpace($Site)) { return $null }
    $historyPath = Join-Path $RepoRoot "Data\\IngestionHistory\\$Site.json"
    if (-not (Test-Path -LiteralPath $historyPath)) { return $null }
    $entries = $null
    try { $entries = Get-Content -LiteralPath $historyPath -Raw | ConvertFrom-Json } catch { $entries = $null }
    if (-not $entries) { return $null }
    $latest = $entries | Where-Object { $_.LastIngestedUtc } | Sort-Object { $_.LastIngestedUtc } -Descending | Select-Object -First 1
    if (-not $latest) { return $null }
    $ingested = $null
    try { $ingested = [datetime]::Parse($latest.LastIngestedUtc).ToUniversalTime() } catch { $ingested = $null }
    if (-not $ingested) { return $null }
    $source = $null
    if ($latest.PSObject.Properties.Name -contains 'SiteCacheProvider') { $source = $latest.SiteCacheProvider }
    if (-not $source -and ($latest.PSObject.Properties.Name -contains 'CacheStatus')) { $source = $latest.CacheStatus }
    if (-not $source -and ($latest.PSObject.Properties.Name -contains 'Source')) { $source = $latest.Source }
    if (-not $source) { $source = 'History' }

    $age = [datetime]::UtcNow - $ingested
    $ageText = if ($age.TotalMinutes -lt 1) {
        '<1 min ago'
    } elseif ($age.TotalHours -lt 1) {
        ('{0:F0} min ago' -f [math]::Floor($age.TotalMinutes))
    } elseif ($age.TotalDays -lt 1) {
        ('{0:F1} h ago' -f $age.TotalHours)
    } else {
        ('{0:F1} d ago' -f $age.TotalDays)
    }

    return [pscustomobject]@{
        Site             = $Site
        LastIngestedUtc  = $ingested
        LastIngestedLocal= $ingested.ToLocalTime()
        Age              = $ageText
        Source           = $source
        HistoryPath      = $historyPath
    }
}

function Resolve-TargetHosts {
    param([string[]]$ExplicitHosts, [string[]]$SiteFilter, [int]$MaxHosts)

    if ($ExplicitHosts -and $ExplicitHosts.Count -gt 0) {
        return @($ExplicitHosts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    }

    $catalog = $null
    try {
        if ($SiteFilter -and $SiteFilter.Count -gt 0) {
            $catalog = DeviceCatalogModule\Get-DeviceSummaries -SiteFilter $SiteFilter
        } else {
            $catalog = DeviceCatalogModule\Get-DeviceSummaries
        }
    } catch { $catalog = $null }
    if (-not $catalog -or -not $catalog.Hostnames) {
        throw "Device catalog did not return any hostnames. Ensure Access databases exist under Data\\<site>."
    }

    $hosts = @($catalog.Hostnames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $hosts = @($hosts)
    if ($hosts.Count -eq 0) {
        $hosts = Get-HostsFromRoutingFiles
        if ($hosts.Count -gt 0) {
            Write-Verbose "Device catalog returned no hosts; falling back to routing host list."
        }
    }

    if ($SiteFilter -and $SiteFilter.Count -gt 0 -and $hosts.Count -gt 0) {
        $filterSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($site in $SiteFilter) {
            if (-not [string]::IsNullOrWhiteSpace($site)) { $filterSet.Add($site) | Out-Null }
        }
        if ($filterSet.Count -gt 0) {
            $hosts = @($hosts | Where-Object { $filterSet.Contains((Get-SitePrefix $_)) })
        }
    }

    if ($MaxHosts -gt 0 -and $hosts.Count -gt $MaxHosts) {
        $hosts = @($hosts | Select-Object -First $MaxHosts)
    }

    $hosts = @($hosts)
    if ($hosts.Count -eq 0) {
        throw "No hostnames matched the requested filters. Provide -Hostnames explicitly or adjust -SiteFilter/-MaxHosts."
    }

    return $hosts
}

function Invoke-InterfacesViewForHost {
    param([string]$Hostname, [Windows.Window]$Window)

    $statusText = $Window.FindName('StatusText')
    if ($statusText) {
        $statusText.Text = "Loading $Hostname..."
    }

    try {
        $dto = DeviceDetailsModule\Get-DeviceDetails -Hostname $Hostname
    } catch {
        throw "Failed to load device details for '$Hostname': $($_.Exception.Message)"
    }
    if (-not $dto) {
        throw "Device details were empty for '$Hostname'."
    }

    try {
        InterfaceModule\Set-InterfaceViewData -DeviceDetails $dto -DefaultHostname $Hostname
    } catch {
        throw "Failed to bind Interfaces view for '$Hostname': $($_.Exception.Message)"
    }

    $grid = $Window.FindName('InterfacesGrid')
    $collection = $null
    if ($grid -and $grid.ItemsSource) {
        $collection = $grid.ItemsSource
    } elseif ($dto.Interfaces -and ($dto.Interfaces -is [System.Collections.IEnumerable])) {
        $collection = $dto.Interfaces
    }

    if (-not $collection) {
        $collection = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
        if ($grid) { $grid.ItemsSource = $collection }
    }

    try {
        DeviceRepositoryModule\Initialize-InterfacePortStream -Hostname $Hostname | Out-Null
    } catch {
        throw "Initialize-InterfacePortStream failed for '$Hostname': $($_.Exception.Message)"
    }

    $dispatcher = [System.Windows.Application]::Current.Dispatcher
    $batches = 0
    $portsAppended = 0
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        $batch = $null
        try { $batch = DeviceRepositoryModule\Get-InterfacePortBatch -Hostname $Hostname } catch { $batch = $null }
        if (-not $batch) {
            $status = $null
            try { $status = DeviceRepositoryModule\Get-InterfacePortStreamStatus -Hostname $Hostname } catch {}
            if ($status -and -not $status.Completed) {
                Start-Sleep -Milliseconds 50
                continue
            }
            break
        }
        $portItems = $batch.Ports
        if (-not ($portItems -is [System.Collections.IEnumerable])) {
            $portItems = @($portItems)
        }
        $rows = @($portItems | Where-Object { $_ })
        $dispatcher.Invoke([System.Action]{
            foreach ($row in $rows) { $collection.Add($row) }
        })
        $portsAppended += $rows.Count
        $batches++
        if ($batch.Completed) { break }
    }
    $watch.Stop()

    try { DeviceRepositoryModule\Clear-InterfacePortStream -Hostname $Hostname } catch {}

    $interfaceCount = 0
    try { $interfaceCount = [int]$collection.Count } catch {}
    $queueMetrics = $null
    try { $queueMetrics = DeviceRepositoryModule\Get-LastInterfacePortQueueMetrics } catch { $queueMetrics = $null }
    $dispatchMetrics = $null
    try { $dispatchMetrics = DeviceRepositoryModule\Get-LastInterfacePortDispatchMetrics } catch { $dispatchMetrics = $null }

    $queueDelay = $null
    if ($queueMetrics) {
        if ($queueMetrics.PSObject.Properties.Name -contains 'QueueDelayMs') {
            $queueDelay = [double]$queueMetrics.QueueDelayMs
        } elseif ($queueMetrics.PSObject.Properties.Name -contains 'QueueBuildDelayMs') {
            $queueDelay = [double]$queueMetrics.QueueBuildDelayMs
        }
    }

    $dispatcherDuration = $null
    if ($dispatchMetrics -and $dispatchMetrics.PSObject.Properties.Name -contains 'DispatcherDurationMs') {
        $dispatcherDuration = [double]$dispatchMetrics.DispatcherDurationMs
    }

    return [pscustomobject]@{
        Hostname           = $Hostname
        Site               = Get-SitePrefix $Hostname
        InterfacesRendered = $interfaceCount
        PortsAppended      = $portsAppended
        BatchesProcessed   = $batches
        SessionDurationMs  = [Math]::Round($watch.Elapsed.TotalMilliseconds, 3)
        QueueDelayMs       = $queueDelay
        DispatcherDurationMs = $dispatcherDuration
        Success            = ($interfaceCount -gt 0)
    }
}

$targetHosts = @(Resolve-TargetHosts -ExplicitHosts $Hostnames -SiteFilter $SiteFilter -MaxHosts $MaxHosts)
Write-Host ("[InterfacesChecklist] Running headless UI stream for {0} host(s)..." -f $targetHosts.Count) -ForegroundColor Cyan

$results = [System.Collections.Generic.List[pscustomobject]]::new()

for ($hostIndex = 0; $hostIndex -lt $targetHosts.Count; $hostIndex++) {
    $currentHost = $targetHosts[$hostIndex]
    $percentComplete = if ($targetHosts.Count -gt 0) { [Math]::Round(($hostIndex / $targetHosts.Count) * 100, 2) } else { 0 }
    $progressStatus = "Streaming {0} ({1}/{2})" -f $currentHost, ($hostIndex + 1), $targetHosts.Count
    Write-Progress -Activity "Interfaces view automation" -Status $progressStatus -PercentComplete $percentComplete
    Write-Host ("[InterfacesChecklist] {0}" -f $progressStatus) -ForegroundColor DarkCyan
    $summary = Invoke-InterfacesViewForHost -Hostname $currentHost -Window $window
    $results.Add($summary) | Out-Null
    if (-not $firstRenderMs -and $summary.Success) {
        $firstRenderMs = [Math]::Round($scriptWatch.Elapsed.TotalMilliseconds, 3)
    }
    if (-not $summary.Success) {
        Write-Warning ("Interfaces view automation reported zero interfaces for host '{0}'." -f $currentHost)
    }
}
Write-Progress -Activity "Interfaces view automation" -Completed
$scriptWatch.Stop()

if ($OutputPath) {
    $dir = Split-Path -Path $OutputPath -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $OutputPath -Encoding utf8
    $resolvedPath = Resolve-Path -LiteralPath $OutputPath -ErrorAction SilentlyContinue
    $displayPath = if ($resolvedPath) { $resolvedPath.ProviderPath } else { $OutputPath }
    Write-Host ("[InterfacesChecklist] Results written to {0}" -f $displayPath) -ForegroundColor Green
}

if ($SummaryPath) {
    $dir = Split-Path -Path $SummaryPath -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $sites = @($targetHosts | ForEach-Object { Get-SitePrefix $_ } | Sort-Object -Unique)
    $siteFreshness = @()
    foreach ($site in $sites) {
        $fresh = Get-SiteFreshnessInfo -Site $site -RepoRoot $repoRoot
        if ($fresh) { $siteFreshness += $fresh }
    }
    $summaryObject = [pscustomobject]@{
        Checklist           = 'InterfacesView'
        HostsAttempted      = $targetHosts.Count
        HostsSucceeded      = ($results | Where-Object { $_.Success }).Count
        TimeToFirstHostMs   = $firstRenderMs
        TotalDurationMs     = [Math]::Round($scriptWatch.Elapsed.TotalMilliseconds, 3)
        HostSummaries       = $results
        SiteFreshness       = $siteFreshness
    }
    $summaryObject | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $SummaryPath -Encoding utf8
    $resolvedSummary = Resolve-Path -LiteralPath $SummaryPath -ErrorAction SilentlyContinue
    $displaySummary = if ($resolvedSummary) { $resolvedSummary.ProviderPath } else { $SummaryPath }
    Write-Host ("[InterfacesChecklist] Summary written to {0}" -f $displaySummary) -ForegroundColor Green
}

if ($PassThru) {
    $results
}

try {
    [System.Windows.Application]::Current.Shutdown()
} catch { }

Write-Host "[InterfacesChecklist] Completed headless Interfaces view run." -ForegroundColor Green
