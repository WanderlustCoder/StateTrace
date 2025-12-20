[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')),
    [string]$Hostname = 'LABS-A01-AS-01',
    [int]$SampleCount = 5,
    [int]$TimeoutSeconds = 20,
    [int]$NoProgressTimeoutSeconds = 5,
    [switch]$PassThru,
    [switch]$AsJson
)

Set-StrictMode -Version Latest

if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne [System.Threading.ApartmentState]::STA) {
    throw "Test-SpanViewBinding.ps1 must run in STA mode. Re-run with 'pwsh -STA -File Tools\Test-SpanViewBinding.ps1'."
}

$repoRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$modulesDir = Join-Path $repoRoot 'Modules'
$mainDir    = Join-Path $repoRoot 'Main'

Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
if (-not [System.Windows.Application]::Current) {
    $script:harnessApp = New-Object System.Windows.Application
    $script:harnessApp.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown
}

$moduleLoaderPath = Join-Path $modulesDir 'ModuleLoaderModule.psm1'
if (-not (Test-Path -LiteralPath $moduleLoaderPath)) {
    throw "Module loader not found at $moduleLoaderPath"
}
Import-Module -Name $moduleLoaderPath -Force -ErrorAction Stop | Out-Null
ModuleLoaderModule\Import-StateTraceModulesFromManifest -RepositoryRoot $repoRoot -Force | Out-Null

function Resolve-SpanHost {
    param([string]$PreferredHost)

    if (-not [string]::IsNullOrWhiteSpace($PreferredHost)) {
        return $PreferredHost
    }

    try {
        $catalog = DeviceCatalogModule\Get-DeviceSummaries
        if ($catalog -and $catalog.PSObject.Properties['Hostnames']) {
            foreach ($candidate in @($catalog.Hostnames)) {
                if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
                $rows = DeviceRepositoryModule\Get-SpanningTreeInfo -Hostname $candidate
                if ($rows -and @($rows).Count -gt 0) {
                    return $candidate
                }
            }
        }
    } catch { }

    $dbPaths = DeviceRepositoryModule\Get-AllSiteDbPaths
    foreach ($dbPath in $dbPaths) {
        try {
            $hostname = (Split-Path -Leaf $dbPath) -replace '\.accdb$',''
            if ([string]::IsNullOrWhiteSpace($hostname)) { continue }
            $rows = DeviceRepositoryModule\Get-SpanningTreeInfo -Hostname $hostname
            if ($rows -and @($rows).Count -gt 0) {
                return $hostname
            }
        } catch { }
    }

    throw "Unable to locate a host with spanning-tree data. Provide -Hostname explicitly."
}

$targetHost = Resolve-SpanHost -PreferredHost $Hostname

$windowXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Span View Test"
        Width="600"
        Height="300"
        Visibility="Hidden">
    <Grid>
        <ContentControl x:Name="SpanHost"/>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlTextReader (New-Object System.IO.StringReader($windowXaml))
$window = [Windows.Markup.XamlReader]::Load($reader)

SpanViewModule\New-SpanView -Window $window -ScriptDir $mainDir
SpanViewModule\Get-SpanInfo -Hostname $targetHost
$window.Show()

function Invoke-DispatcherPump {
    param([int]$Milliseconds = 250)
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

function Get-SpanGridRowCount {
    param([object]$Grid)

    if (-not $Grid) { return 0 }
    $gridRows = @()
    if ($Grid.ItemsSource) {
        foreach ($item in $Grid.ItemsSource) { $gridRows += $item }
    } elseif ($Grid.Items) {
        foreach ($item in $Grid.Items) { $gridRows += $item }
    }
    return $gridRows.Count
}

$timeoutMs = [Math]::Max(1000, ($TimeoutSeconds * 1000))
$noProgressMs = if ($NoProgressTimeoutSeconds -gt 0) { [Math]::Max(1000, ($NoProgressTimeoutSeconds * 1000)) } else { 0 }
$waitWatch = [System.Diagnostics.Stopwatch]::StartNew()
$lastProgressMs = 0
$lastCount = 0
$spanView = $null
$grid = $null

while ($waitWatch.ElapsedMilliseconds -lt $timeoutMs) {
    Invoke-DispatcherPump -Milliseconds 200
    $spanView = $global:spanView
    if ($spanView) {
        $grid = $spanView.FindName('SpanGrid')
    }
    $currentCount = Get-SpanGridRowCount -Grid $grid
    if ($currentCount -ne $lastCount) {
        $lastCount = $currentCount
        $lastProgressMs = $waitWatch.ElapsedMilliseconds
    }
    if ($currentCount -gt 0) { break }
    if ($noProgressMs -gt 0 -and ($waitWatch.ElapsedMilliseconds - $lastProgressMs) -ge $noProgressMs) { break }
}

$window.Hide()

if (-not $spanView) {
    throw "Span view failed to load; global spanView is null."
}

if (-not $grid) {
    throw "Span grid control not found in rendered view."
}

$statusText = ''
$statusBlock = $spanView.FindName('SpanStatusLabel')
if ($statusBlock -and $statusBlock.Text) { $statusText = $statusBlock.Text }

Invoke-DispatcherPump -Milliseconds 50

$gridRowCount = 0
$gridPreview = @()
if ($grid) {
    try { $grid.UpdateLayout() } catch {}
    $gridRows = @()
    if ($grid.ItemsSource) {
        $gridRows = @()
        foreach ($item in $grid.ItemsSource) { $gridRows += $item }
    } elseif ($grid.Items) {
        foreach ($item in $grid.Items) { $gridRows += $item }
    }
    if ($gridRows -and $gridRows.Count -gt 0) {
        $gridRowCount = $gridRows.Count
        $gridPreview = $gridRows | Select-Object -First 3
    }
}

$moduleInfo = InModuleScope SpanViewModule {
    $itemList = @()
    $tagList  = @()
    if ($script:SpanGridControl) {
        if ($script:SpanGridControl.ItemsSource) {
            foreach ($row in $script:SpanGridControl.ItemsSource) { $itemList += $row }
        }
        if ($script:SpanGridControl.Tag) {
            foreach ($row in $script:SpanGridControl.Tag) { $tagList += $row }
        }
    }
    [pscustomobject]@{
        ItemsSourceCount = $itemList.Count
        TagCount         = $tagList.Count
        StatusLabel      = if ($script:SpanStatusLabel) { $script:SpanStatusLabel.Text } else { '' }
        TagSnapshot      = $tagList
    }
}

$snapshot = SpanViewModule\Get-SpanViewSnapshot -IncludeRows -SampleCount $SampleCount

$result = [pscustomobject]@{
    Hostname         = $targetHost
    GridRowCount     = $gridRowCount
    SnapshotRowCount = $snapshot.RowCount
    SnapshotCached   = $snapshot.CachedRowCount
    SelectedVlan     = $snapshot.SelectedVlan
    StatusText       = if ($statusText) { $statusText } elseif ($moduleInfo.StatusLabel) { $moduleInfo.StatusLabel } else { $snapshot.StatusText }
    UsedLastRows     = $snapshot.UsedLastRows
    ModuleItemsCount = $moduleInfo.ItemsSourceCount
    ModuleTagCount   = $moduleInfo.TagCount
    ModuleTagPreview = $moduleInfo.TagSnapshot | Select-Object -First 3
    GridPreview      = $gridPreview
    SnapshotRows     = $snapshot.SampleRows
}

if ($result.GridRowCount -le 0 -and $snapshot.RowCount -le 0) {
    try {
        $logTail = Get-Content (Join-Path $repoRoot 'Logs\Debug\SpanDebug.log') -Tail 40 -ErrorAction Stop
        Write-Warning ("SpanDebug.log tail:`n{0}" -f ($logTail -join [Environment]::NewLine))
    } catch {}
    throw "Span grid still empty after binding attempt."
}

if ($PassThru) {
    return $result
}

try {
    if ($PassThru) {
        return $result
    }
if ($AsJson) {
    $result | ConvertTo-Json -Depth 6 | Write-Output
        return
    }
    $result | Format-List
} finally {
    if ($script:harnessApp) {
        try { $script:harnessApp.Shutdown() } catch {}
    }
}
