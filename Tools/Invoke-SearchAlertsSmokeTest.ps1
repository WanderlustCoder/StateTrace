<#
.SYNOPSIS
Headless smoke test for Search Interfaces + Alerts views.

.DESCRIPTION
Loads Search/Alerts views into a hidden WPF window, binds interface data from Access,
triggers async refresh, and asserts the grids are populated or bound.

.EXAMPLE
pwsh -NoLogo -STA -File Tools\Invoke-SearchAlertsSmokeTest.ps1 -SiteFilter WLLS -PassThru
#>
[CmdletBinding()]
param(
    [string]$RepositoryRoot,
    [string[]]$Hostnames,
    [string[]]$SiteFilter = @(),
    [int]$MaxHosts = 3,
    [string]$SearchTerm = '',
    [int]$TimeoutSeconds = 20,
    [int]$NoProgressTimeoutSeconds = 5,
    [switch]$RequireAlerts,
    [switch]$EnableDiagnostics,
    [switch]$ForceExit,
    [switch]$PassThru,
    [switch]$AsJson
)

Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..'))
}

if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne [System.Threading.ApartmentState]::STA) {
    throw "Invoke-SearchAlertsSmokeTest.ps1 must run in STA mode. Re-run with 'pwsh -STA -File Tools\Invoke-SearchAlertsSmokeTest.ps1 ...'."
}

$SiteFilter = if ($SiteFilter -and $SiteFilter.Count -eq 1) {
    @($SiteFilter[0] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
} else {
    @($SiteFilter)
}

$repoRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$modulesDir = Join-Path $repoRoot 'Modules'
$mainDir = Join-Path $repoRoot 'Main'

Add-Type -AssemblyName PresentationFramework -ErrorAction Stop

$moduleLoaderPath = Join-Path $modulesDir 'ModuleLoaderModule.psm1'
if (-not (Test-Path -LiteralPath $moduleLoaderPath)) {
    throw "Module loader not found at '$moduleLoaderPath'."
}
Import-Module -Name $moduleLoaderPath -Force -ErrorAction Stop | Out-Null
ModuleLoaderModule\Import-StateTraceModulesFromManifest -RepositoryRoot $repoRoot | Out-Null

if (-not [System.Windows.Application]::Current) {
    $app = New-Object System.Windows.Application
    $app.ShutdownMode = 'OnExplicitShutdown'
}

if ($EnableDiagnostics) {
    $global:StateTraceDebug = $true
    $VerbosePreference = 'Continue'
}

function Get-SitePrefix {
    param([string]$Hostname)
    if ([string]::IsNullOrWhiteSpace($Hostname)) { return '(unknown)' }
    $segments = $Hostname.Split('-', 2, [System.StringSplitOptions]::RemoveEmptyEntries)
    if ($segments.Count -gt 0) { return $segments[0] }
    return $Hostname
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

function Invoke-DispatcherPump {
    param([int]$Milliseconds = 100)
    $frame = New-Object System.Windows.Threading.DispatcherFrame
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds([math]::Max(10, $Milliseconds))
    $timer.Add_Tick({
        param($sender,$args)
        $sender.Stop()
        $frame.Continue = $false
    })
    $timer.Start()
    [System.Windows.Threading.Dispatcher]::PushFrame($frame)
}

function Get-CollectionCount {
    param([object]$Items)
    if ($null -eq $Items) { return 0 }
    try {
        if ($Items -is [System.Collections.ICollection]) { return [int]$Items.Count }
    } catch { }
    try {
        return @($Items).Count
    } catch { return 0 }
}

function Wait-ForGridUpdate {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.DataGrid]$Grid,
        [object]$InitialItems,
        [int]$TimeoutMs,
        [int]$RequireCount,
        [int]$NoProgressMs
    )

    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $items = $null
    $count = 0
    $timedOut = $false
    $noProgress = $false
    $lastItems = $InitialItems
    $initialCount = Get-CollectionCount -Items $InitialItems
    $lastCount = $initialCount
    $lastChangeMs = 0

    $effectiveNoProgressMs = 0
    if ($NoProgressMs -gt 0) {
        $effectiveNoProgressMs = [Math]::Max(1000, $NoProgressMs)
    }

    while ($watch.ElapsedMilliseconds -lt $TimeoutMs) {
        Invoke-DispatcherPump -Milliseconds 120
        $items = $Grid.ItemsSource
        $count = Get-CollectionCount -Items $items

        $changed = (-not [object]::ReferenceEquals($items, $lastItems)) -or ($count -ne $lastCount)
        if ($changed) {
            $lastItems = $items
            $lastCount = $count
            $lastChangeMs = $watch.ElapsedMilliseconds
        }

        if (-not [object]::ReferenceEquals($items, $InitialItems)) {
            if ($RequireCount -le 0 -or $count -ge $RequireCount) {
                break
            }
        }

        if ($effectiveNoProgressMs -gt 0 -and ($watch.ElapsedMilliseconds - $lastChangeMs) -ge $effectiveNoProgressMs) {
            $noProgress = $true
            break
        }
    }

    $watch.Stop()
    if ($watch.ElapsedMilliseconds -ge $TimeoutMs) {
        $timedOut = $true
    }
    $changed = (-not [object]::ReferenceEquals($items, $InitialItems)) -or ($count -ne $initialCount)
    return [pscustomobject]@{
        Items             = $items
        Count             = $count
        Elapsed           = [math]::Round($watch.Elapsed.TotalMilliseconds, 3)
        TimedOut          = $timedOut
        NoProgressTimeout = $noProgress
        Changed           = $changed
    }
}

$finalResult = $null
$failure = $null
$windowRef = $null
try {
        $targetHosts = @(Resolve-TargetHosts -ExplicitHosts $Hostnames -SiteFilter $SiteFilter -MaxHosts $MaxHosts)

        $allInterfaces = [System.Collections.Generic.List[object]]::new()
        $hostSummaries = [System.Collections.Generic.List[pscustomobject]]::new()

        foreach ($targetHost in $targetHosts) {
            $rows = $null
            try { $rows = DeviceRepositoryModule\Get-InterfaceInfo -Hostname $targetHost } catch { $rows = $null }
            $rowCount = Get-CollectionCount -Items $rows
            if ($rows) {
                foreach ($row in @($rows)) {
                    if ($row) { $allInterfaces.Add($row) | Out-Null }
                }
            }
            $hostSummaries.Add([pscustomobject]@{
                Hostname       = $targetHost
                Site           = Get-SitePrefix $targetHost
                InterfaceCount = $rowCount
            }) | Out-Null
        }

        if ($allInterfaces.Count -le 0) {
            throw "Search/Alerts smoke test failed: no interfaces were loaded for hosts '$($targetHosts -join ', ')'."
        }

        $windowXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Search/Alerts Smoke Test"
        Height="600"
        Width="980"
        Visibility="Hidden"
        ShowInTaskbar="False">
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>
    <TextBlock Text="Search/Alerts Smoke Test Host" Margin="10" FontWeight="Bold"/>
    <Grid Grid.Row="1">
      <Grid.RowDefinitions>
        <RowDefinition Height="*"/>
        <RowDefinition Height="*"/>
      </Grid.RowDefinitions>
      <ContentControl Name="SearchInterfacesHost" Grid.Row="0"/>
      <ContentControl Name="AlertsHost" Grid.Row="1"/>
    </Grid>
  </Grid>
</Window>
"@

        $reader = New-Object System.Xml.XmlTextReader (New-Object System.IO.StringReader($windowXaml))
        $window = [Windows.Markup.XamlReader]::Load($reader)
        $windowRef = $window
        Set-Variable -Scope Global -Name window -Value $window -Force

        $global:InterfacesLoadAllowed = $true
        $global:AllInterfaces = $allInterfaces

        SearchInterfacesViewModule\New-SearchInterfacesView -Window $window -ScriptDir $mainDir
        AlertsViewModule\New-AlertsView -Window $window -ScriptDir $mainDir

        $searchGrid = $window.FindName('SearchInterfacesGrid')
        if (-not $searchGrid) {
            $searchHost = $window.FindName('SearchInterfacesHost')
            if ($searchHost -and $searchHost.Content) {
                $searchGrid = $searchHost.Content.FindName('SearchInterfacesGrid')
            }
        }
        if (-not $searchGrid) { throw "SearchInterfacesGrid not found in SearchInterfaces view." }

        $searchBox = $window.FindName('SearchBox')
        if (-not $searchBox) {
            $searchHost = $window.FindName('SearchInterfacesHost')
            if ($searchHost -and $searchHost.Content) {
                $searchBox = $searchHost.Content.FindName('SearchBox')
            }
        }
        if ($searchBox) {
            $searchBox.Text = $SearchTerm
        }

        $alertsGrid = $window.FindName('AlertsGrid')
        if (-not $alertsGrid) {
            $alertsHost = $window.FindName('AlertsHost')
            if ($alertsHost -and $alertsHost.Content) {
                $alertsGrid = $alertsHost.Content.FindName('AlertsGrid')
            }
        }
        if (-not $alertsGrid) { throw "AlertsGrid not found in Alerts view." }

        $initialSearchItems = $searchGrid.ItemsSource
        $initialAlertsItems = $alertsGrid.ItemsSource

        DeviceInsightsModule\Update-SearchGridAsync -Interfaces $allInterfaces
        DeviceInsightsModule\Update-AlertsAsync -Interfaces $allInterfaces

        $timeoutMs = [Math]::Max(1000, ($TimeoutSeconds * 1000))
        $noProgressMs = if ($NoProgressTimeoutSeconds -gt 0) { [Math]::Max(1000, ($NoProgressTimeoutSeconds * 1000)) } else { 0 }
        $requireSearchCount = if ([string]::IsNullOrWhiteSpace($SearchTerm)) { 1 } else { 0 }

        $searchState = Wait-ForGridUpdate -Grid $searchGrid -InitialItems $initialSearchItems -TimeoutMs $timeoutMs -RequireCount $requireSearchCount -NoProgressMs $noProgressMs
        $alertsState = Wait-ForGridUpdate -Grid $alertsGrid -InitialItems $initialAlertsItems -TimeoutMs $timeoutMs -RequireCount 0 -NoProgressMs $noProgressMs

        $searchChanged = [bool]$searchState.Changed
        $alertsChanged = [bool]$alertsState.Changed

        $searchSample = @()
        if ($searchState.Items) {
            try { $searchSample = @($searchState.Items | Select-Object -First 5 | ForEach-Object { $_.Port }) } catch { $searchSample = @() }
        }
        $alertsSample = @()
        if ($alertsState.Items) {
            try { $alertsSample = @($alertsState.Items | Select-Object -First 5 | ForEach-Object { $_.Port }) } catch { $alertsSample = @() }
        }

        $searchBound = [bool]$searchChanged
        $alertsBound = [bool]$alertsChanged

        $searchSuccess = $searchBound -and ($searchState.Count -ge $requireSearchCount) -and (-not $searchState.TimedOut) -and (-not $searchState.NoProgressTimeout)
        $alertsSuccess = $alertsBound -and (-not $RequireAlerts.IsPresent -or ($alertsState.Count -gt 0)) -and (-not $alertsState.TimedOut) -and (-not $alertsState.NoProgressTimeout)

        $finalResult = [pscustomobject]@{
            HostsAttempted     = $targetHosts.Count
            HostSummaries      = $hostSummaries
            InterfacesLoaded   = $allInterfaces.Count
            SearchTerm         = $SearchTerm
            SearchResultsBound = $searchBound
            SearchCount        = $searchState.Count
            SearchElapsedMs    = $searchState.Elapsed
            SearchTimedOut     = [bool]$searchState.TimedOut
            SearchNoProgressTimeout = [bool]$searchState.NoProgressTimeout
            SearchSamplePorts  = $searchSample
            AlertsResultsBound = $alertsBound
            AlertsCount        = $alertsState.Count
            AlertsElapsedMs    = $alertsState.Elapsed
            AlertsTimedOut     = [bool]$alertsState.TimedOut
            AlertsNoProgressTimeout = [bool]$alertsState.NoProgressTimeout
            AlertsSamplePorts  = $alertsSample
            Success            = ($searchSuccess -and $alertsSuccess)
        }

        $moduleDiag = $null
        try {
            $module = Get-Module DeviceInsightsModule
            if ($module) {
                $queue = $module.SessionState.PSVariable.GetValue('InsightsWorkerQueue')
                $queueCount = 0
                try { if ($queue) { $queueCount = $queue.Count } } catch { $queueCount = 0 }
                $applyCounter = $module.SessionState.PSVariable.GetValue('InsightsApplyCounter')
                $latestRequestId = $module.SessionState.PSVariable.GetValue('InsightsLatestRequestId')
                $workerThread = $module.SessionState.PSVariable.GetValue('InsightsWorkerThread')
                $workerAlive = $false
                try { if ($workerThread) { $workerAlive = [bool]$workerThread.IsAlive } } catch { $workerAlive = $false }
                $moduleDiag = [pscustomobject]@{
                    LatestRequestId  = $latestRequestId
                    ApplyCounter     = $applyCounter
                    WorkerQueueCount = $queueCount
                    WorkerThreadAlive= $workerAlive
                }
            }
        } catch { $moduleDiag = $null }
        if ($moduleDiag) {
            $finalResult | Add-Member -NotePropertyName InsightsDiagnostics -NotePropertyValue $moduleDiag -Force
        }

        if (-not $finalResult.Success) {
            $alertDetail = if ($RequireAlerts) { "AlertsCount=$($finalResult.AlertsCount)" } else { "AlertsBound=$($finalResult.AlertsResultsBound)" }
            $timeoutDetail = @()
            if ($finalResult.SearchTimedOut) { $timeoutDetail += 'SearchTimedOut' }
            if ($finalResult.SearchNoProgressTimeout) { $timeoutDetail += 'SearchNoProgress' }
            if ($finalResult.AlertsTimedOut) { $timeoutDetail += 'AlertsTimedOut' }
            if ($finalResult.AlertsNoProgressTimeout) { $timeoutDetail += 'AlertsNoProgress' }
            $timeoutText = if ($timeoutDetail.Count -gt 0) { (' Timeouts=' + ($timeoutDetail -join ',')) } else { '' }
            $failure = ("Search/Alerts smoke test failed: SearchCount={0}, SearchBound={1}, {2}.{3}" -f $finalResult.SearchCount, $finalResult.SearchResultsBound, $alertDetail, $timeoutText)
        }
} catch {
    $failure = $_
} finally {
    try {
        if ($windowRef) {
            try { $windowRef.Close() } catch { }
        }
        if ([System.Windows.Application]::Current) {
            try { [System.Windows.Application]::Current.Dispatcher.InvokeShutdown() } catch { }
            try { [System.Windows.Application]::Current.Shutdown() } catch { }
        }
    } catch { }
}

if ($failure) {
    Write-Error $failure
    if ($ForceExit) {
        [System.Environment]::Exit(1)
    }
    throw $failure
}

if ($finalResult) {
    if ($AsJson) {
        $finalResult | ConvertTo-Json -Depth 6 -Compress | Write-Output
    } elseif ($PassThru) {
        $finalResult
    }
}

if ($ForceExit) {
    [System.Environment]::Exit(0)
}
