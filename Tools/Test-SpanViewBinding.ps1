[CmdletBinding()]
param(
    [string]$RepositoryRoot,
    [string]$Hostname = 'LABS-A01-AS-01',
    [int]$SampleCount = 5,
    [int]$TimeoutSeconds = 20,
    [int]$NoProgressTimeoutSeconds = 5,
    [switch]$PassThru,
    [switch]$AsJson,
    [switch]$EmitDiagnostics,
    [switch]$SimulateSpanViewFailure
)

Set-StrictMode -Version Latest

$helperPath = Join-Path $PSScriptRoot 'UiHarnessHelpers.ps1'
if (-not (Test-Path -LiteralPath $helperPath)) {
    throw "UI harness helpers missing at $helperPath"
}
. $helperPath

# LANDMARK: Span harness preflight - fail gracefully when desktop/STA is unavailable
$preflight = Test-StateTraceUiHarnessPreflight -RequireDesktop -RequireSta

# LANDMARK: SpanView diagnostics - capture root exception and environment details
function Convert-SpanExceptionDetail {
    param([Exception]$Exception)

    if (-not $Exception) { return @() }

    $items = [System.Collections.Generic.List[pscustomobject]]::new()
    $current = $Exception
    $depth = 0
    while ($current -and $depth -lt 6) {
        $detail = [ordered]@{
            Type       = $current.GetType().FullName
            Message    = $current.Message
            HResult    = $current.HResult
            Source     = $current.Source
            StackTrace = $current.StackTrace
        }
        if ($detail.Type -eq 'System.Windows.Markup.XamlParseException') {
            try { $detail.LineNumber = $current.LineNumber } catch { }
            try { $detail.LinePosition = $current.LinePosition } catch { }
            try { $detail.BaseUri = if ($current.BaseUri) { $current.BaseUri.ToString() } else { '' } } catch { }
        }
        if ($detail.Type -in @('System.IO.FileNotFoundException','System.IO.FileLoadException')) {
            try { $detail.FileName = $current.FileName } catch { }
            try { $detail.FusionLog = $current.FusionLog } catch { }
        }
        $items.Add([pscustomobject]$detail)
        $current = $current.InnerException
        $depth++
    }

    return $items
}

function Test-SpanHarnessWpfAssemblies {
    $results = [ordered]@{}
    foreach ($name in @('PresentationFramework','PresentationCore','WindowsBase')) {
        try {
            Add-Type -AssemblyName $name -ErrorAction Stop
            $results["${name}Loaded"] = $true
        } catch {
            $results["${name}Loaded"] = $false
            $results["${name}Error"] = $_.Exception.Message
        }
    }
    return [pscustomobject]$results
}

function Get-SpanHarnessEnvironment {
    param(
        [object]$WpfAssemblies,
        [bool]$ApplicationCreated
    )

    $osVersion = ''
    try { $osVersion = [Environment]::OSVersion.VersionString } catch { }
    $apartmentState = ''
    try { $apartmentState = [System.Threading.Thread]::CurrentThread.ApartmentState.ToString() } catch { }
    $userInteractive = $null
    try { $userInteractive = [Environment]::UserInteractive } catch { $userInteractive = $false }

    $hasApp = $false
    try { $hasApp = [bool][System.Windows.Application]::Current } catch { $hasApp = $false }

    return [pscustomobject]@{
        PSVersion          = $PSVersionTable.PSVersion.ToString()
        PSEdition          = $PSVersionTable.PSEdition
        OSVersion          = $osVersion
        UserInteractive    = $userInteractive
        ApartmentState     = $apartmentState
        WpfAssemblies      = $WpfAssemblies
        ApplicationCreated = $ApplicationCreated
        HasWpfApplication  = $hasApp
    }
}

function Get-SpanModuleInfo {
    $module = Get-Module -Name SpanViewModule -ErrorAction SilentlyContinue
    if (-not $module) { return $null }

    $scriptBlock = {
        $itemList = [System.Collections.Generic.List[object]]::new()
        $tagList  = [System.Collections.Generic.List[object]]::new()
        if ($script:SpanGridControl) {
            if ($script:SpanGridControl.ItemsSource) {
                foreach ($row in $script:SpanGridControl.ItemsSource) { $itemList.Add($row) }
            }
            if ($script:SpanGridControl.Tag) {
                foreach ($row in $script:SpanGridControl.Tag) { $tagList.Add($row) }
            }
        }
        [pscustomobject]@{
            ItemsSourceCount = $itemList.Count
            TagCount         = $tagList.Count
            StatusLabel      = if ($script:SpanStatusLabel) { $script:SpanStatusLabel.Text } else { '' }
            TagSnapshot      = $tagList
            ViewControlType  = if ($script:SpanViewControl) { $script:SpanViewControl.GetType().FullName } else { '' }
            ViewControlHash  = if ($script:SpanViewControl) { $script:SpanViewControl.GetHashCode() } else { 0 }
            GridControlType  = if ($script:SpanGridControl) { $script:SpanGridControl.GetType().FullName } else { '' }
            GridControlHash  = if ($script:SpanGridControl) { $script:SpanGridControl.GetHashCode() } else { 0 }
        }
    }

    try {
        if (Get-Command -Name InModuleScope -ErrorAction SilentlyContinue) {
            return InModuleScope -ModuleName SpanViewModule $scriptBlock
        }
        return & $module $scriptBlock
    } catch {
        return $null
    }
}

function Get-SpanViewCompositionFailure {
    $module = Get-Module -Name ViewCompositionModule -ErrorAction SilentlyContinue
    if (-not $module) { return $null }
    try { return & $module { $script:LastSetStViewFailure } } catch { return $null }
}

function Get-SpanModuleGlobalView {
    $module = Get-Module -Name SpanViewModule -ErrorAction SilentlyContinue
    if (-not $module) { return $null }
    try { return & $module { Get-GlobalSpanView } } catch { return $null }
}

function Get-SpanModuleViewControl {
    $module = Get-Module -Name SpanViewModule -ErrorAction SilentlyContinue
    if (-not $module) { return $null }
    try { return & $module { $script:SpanViewControl } } catch { return $null }
}

function Write-SpanHarnessOutput {
    param(
        [Parameter(Mandatory)][object]$Result,
        [switch]$AsJson,
        [switch]$PassThru
    )

    if ($PassThru) { return $Result }
    if ($AsJson) {
        $Result | ConvertTo-Json -Depth 6 | Write-Output
        return
    }
    $Result | Format-List
}

$diagnostics = $null
if ($EmitDiagnostics) {
    $diagnostics = [ordered]@{
        Environment = Get-SpanHarnessEnvironment -WpfAssemblies $null -ApplicationCreated:$false
    }
}

if ($preflight.Status -ne 'Ready') {
    $result = [pscustomobject]@{
        HarnessName = 'SpanView'
        Status      = $preflight.Status
        Reason      = $preflight.Reason
        Details     = $preflight.Details
        Hostname    = $Hostname
        Timestamp   = (Get-Date).ToString('o')
    }
    if ($diagnostics) { $result | Add-Member -NotePropertyName Diagnostics -NotePropertyValue $diagnostics }
    Write-SpanHarnessOutput -Result $result -AsJson:$AsJson -PassThru:$PassThru 
    return
}

# LANDMARK: Span harness repository root - handle empty PSScriptRoot in Windows PowerShell
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $basePath = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($basePath)) {
        $basePath = (Get-Location).Path
    }
    $RepositoryRoot = Join-Path $basePath '..'
}

$repoRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$modulesDir = Join-Path $repoRoot 'Modules'
$mainDir    = Join-Path $repoRoot 'Main'

$wpfAssemblies = Test-SpanHarnessWpfAssemblies
if ($diagnostics) {
    $diagnostics.Environment = Get-SpanHarnessEnvironment -WpfAssemblies $wpfAssemblies -ApplicationCreated:$false
}
if (-not $wpfAssemblies.PresentationFrameworkLoaded) {
    $result = [pscustomobject]@{
        HarnessName    = 'SpanView'
        Status         = 'RequiresPrereq'
        Reason         = 'WpfAssembliesUnavailable'
        FailureMessage = 'PresentationFramework failed to load.'
        Hostname       = $Hostname
        Timestamp      = (Get-Date).ToString('o')
    }
    if ($diagnostics) { $result | Add-Member -NotePropertyName Diagnostics -NotePropertyValue $diagnostics }
    Write-SpanHarnessOutput -Result $result -AsJson:$AsJson -PassThru:$PassThru
    return
}

$applicationCreated = $false
if (-not [System.Windows.Application]::Current) {
    $script:harnessApp = New-Object System.Windows.Application
    $script:harnessApp.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown
    $applicationCreated = $true
}
if ($diagnostics) {
    $diagnostics.Environment = Get-SpanHarnessEnvironment -WpfAssemblies $wpfAssemblies -ApplicationCreated:$applicationCreated
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

$spanInitError = $null
try {
    # LANDMARK: SpanView diagnostics - simulate init failure for test coverage
    if ($SimulateSpanViewFailure) {
        throw [System.InvalidOperationException]::new('Simulated span view initialization failure.')
    }
    SpanViewModule\New-SpanView -Window $window -ScriptDir $mainDir
} catch {
    $spanInitError = $_.Exception
}

$spanInfoError = $null
if (-not $spanInitError) {
    try {
        SpanViewModule\Get-SpanInfo -Hostname $targetHost
    } catch {
        $spanInfoError = $_.Exception
    }
}

if ($diagnostics) {
    $globalSpanVar = Get-Variable -Name spanView -Scope Global -ErrorAction SilentlyContinue
    $globalSpanView = if ($globalSpanVar) { $globalSpanVar.Value } else { $null }
    $moduleSpanView = Get-SpanModuleGlobalView
    $diagnostics.SpanView = [pscustomobject]@{
        GlobalSpanViewPresent = [bool]$globalSpanVar
        GlobalSpanViewType    = if ($globalSpanView) { $globalSpanView.GetType().FullName } else { '' }
        GlobalSpanViewHash    = if ($globalSpanView) { $globalSpanView.GetHashCode() } else { 0 }
        ModuleSpanViewType    = if ($moduleSpanView) { $moduleSpanView.GetType().FullName } else { '' }
        ModuleSpanViewHash    = if ($moduleSpanView) { $moduleSpanView.GetHashCode() } else { 0 }
        ViewCompositionFailure = Get-SpanViewCompositionFailure
        SpanInitError         = Convert-SpanExceptionDetail -Exception $spanInitError
        SpanInfoError         = Convert-SpanExceptionDetail -Exception $spanInfoError
    }
}

$spanViewSeed = $null
try {
    $seedVar = Get-Variable -Name spanView -Scope Global -ErrorAction SilentlyContinue
    if ($seedVar) { $spanViewSeed = $seedVar.Value }
} catch { }
if ($null -eq $spanViewSeed) {
    $spanViewSeed = Get-SpanModuleViewControl
}

if ($window) { $window.Show() }

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

    # LANDMARK: Span view null checks - avoid false negatives from empty WPF enumerables
    if ($null -eq $Grid) { return 0 }
    $gridRows = [System.Collections.Generic.List[object]]::new()
    if ($Grid.ItemsSource) {
        foreach ($item in $Grid.ItemsSource) { $gridRows.Add($item) }
    } elseif ($Grid.Items) {
        foreach ($item in $Grid.Items) { $gridRows.Add($item) }
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

if (-not $spanInitError) {
    while ($waitWatch.ElapsedMilliseconds -lt $timeoutMs) {
        Invoke-DispatcherPump -Milliseconds 200
        if ($null -eq $global:spanView -and $null -ne $spanViewSeed) {
            $global:spanView = $spanViewSeed
        }
        $spanView = $global:spanView
        if ($null -ne $spanView -and $null -eq $spanViewSeed) {
            $spanViewSeed = $spanView
        }
        if ($null -ne $spanView) {
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
}

if ($diagnostics -and $diagnostics.SpanView) {
    $globalSpanAfter = Get-Variable -Name spanView -Scope Global -ErrorAction SilentlyContinue
    $globalSpanAfterValue = if ($globalSpanAfter) { $globalSpanAfter.Value } else { $null }
    $moduleSpanAfterValue = Get-SpanModuleGlobalView
    $diagnostics.SpanView | Add-Member -NotePropertyName SpanViewAfterLoopPresent -NotePropertyValue ($null -ne $spanView)
    $diagnostics.SpanView | Add-Member -NotePropertyName SpanViewAfterLoopType -NotePropertyValue $(if ($null -ne $spanView) { $spanView.GetType().FullName } else { '' })
    $diagnostics.SpanView | Add-Member -NotePropertyName SpanGridAfterLoopType -NotePropertyValue $(if ($null -ne $grid) { $grid.GetType().FullName } else { '' })
    $diagnostics.SpanView | Add-Member -NotePropertyName GlobalSpanViewAfterLoopPresent -NotePropertyValue ([bool]$globalSpanAfter)
    $diagnostics.SpanView | Add-Member -NotePropertyName GlobalSpanViewAfterLoopType -NotePropertyValue $(if ($null -ne $globalSpanAfterValue) { $globalSpanAfterValue.GetType().FullName } else { '' })
    $diagnostics.SpanView | Add-Member -NotePropertyName ModuleSpanViewAfterLoopPresent -NotePropertyValue ($null -ne $moduleSpanAfterValue)
    $diagnostics.SpanView | Add-Member -NotePropertyName ModuleSpanViewAfterLoopType -NotePropertyValue $(if ($null -ne $moduleSpanAfterValue) { $moduleSpanAfterValue.GetType().FullName } else { '' })
}

$window.Hide()

$failureReason = ''
$failureMessage = ''
if ($spanInitError) {
    $failureReason = 'SpanViewInitError'
    $failureMessage = $spanInitError.Message
} elseif ($spanInfoError) {
    $failureReason = 'SpanInfoError'
    $failureMessage = $spanInfoError.Message
} elseif ($null -eq $spanView) {
    $failureReason = 'SpanViewNull'
    $failureMessage = 'Span view failed to load; global spanView is null.'
} elseif ($null -eq $grid) {
    $failureReason = 'SpanGridMissing'
    $failureMessage = 'Span grid control not found in rendered view.'
}

$statusText = ''
$statusBlock = $null
if ($null -ne $spanView) {
    $statusBlock = $spanView.FindName('SpanStatusLabel')
}
if ($statusBlock -and $statusBlock.Text) { $statusText = $statusBlock.Text }

Invoke-DispatcherPump -Milliseconds 50

$gridRowCount = 0
$gridPreview = @()
if ($null -ne $grid) {
    try { $grid.UpdateLayout() } catch {}
    $gridRows = [System.Collections.Generic.List[object]]::new()
    if ($grid.ItemsSource) {
        foreach ($item in $grid.ItemsSource) { $gridRows.Add($item) }
    } elseif ($grid.Items) {
        foreach ($item in $grid.Items) { $gridRows.Add($item) }
    }
    if ($gridRows -and $gridRows.Count -gt 0) {
        $gridRowCount = $gridRows.Count
        $gridPreview = $gridRows | Select-Object -First 3
    }
}

$moduleInfo = Get-SpanModuleInfo

$snapshotError = $null
try {
    $snapshot = SpanViewModule\Get-SpanViewSnapshot -IncludeRows -SampleCount $SampleCount
} catch {
    $snapshotError = $_.Exception
    $snapshot = $null
}
if (-not $snapshot) {
    $snapshot = [pscustomobject]@{
        RowCount       = 0
        CachedRowCount = 0
        SelectedVlan   = ''
        StatusText     = ''
        UsedLastRows   = $false
        SampleRows     = @()
    }
}
if ($diagnostics -and $diagnostics.SpanView) {
    $diagnostics.SpanView | Add-Member -NotePropertyName SnapshotError -NotePropertyValue (Convert-SpanExceptionDetail -Exception $snapshotError)
}

if ($failureReason -eq 'SpanViewNull' -and $moduleInfo -and ($moduleInfo.ViewControlType -or $moduleInfo.GridControlType)) {
    $failureReason = 'SpanViewGlobalMissing'
    $failureMessage = 'Span view controls initialized but global spanView is not set.'
}

$result = [pscustomobject]@{
    HarnessName     = 'SpanView'
    Status          = if ($failureReason) { 'Fail' } else { 'Pass' }
    Reason          = $failureReason
    FailureMessage  = $failureMessage
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
    Timestamp        = (Get-Date).ToString('o')
}
if ($diagnostics) { $result | Add-Member -NotePropertyName Diagnostics -NotePropertyValue $diagnostics }

if (-not $failureReason -and $result.GridRowCount -le 0 -and $snapshot.RowCount -le 0) {
    $failureReason = 'SpanGridEmpty'
    $failureMessage = 'Span grid still empty after binding attempt.'
    $result.Status = 'Fail'
    $result.Reason = $failureReason
    $result.FailureMessage = $failureMessage
    try {
        $logTail = Get-Content (Join-Path $repoRoot 'Logs\Debug\SpanDebug.log') -Tail 40 -ErrorAction Stop
        Write-Warning ("SpanDebug.log tail:`n{0}" -f ($logTail -join [Environment]::NewLine))
    } catch {}
}

$exitCode = if ($result.Status -eq 'Pass') { 0 } else { 1 }

try {
    Write-SpanHarnessOutput -Result $result -AsJson:$AsJson -PassThru:$PassThru
} finally {
    if ($script:harnessApp) {
        try { $script:harnessApp.Shutdown() } catch {}
    }
}

if ($exitCode -ne 0 -and -not $PassThru) {
    exit $exitCode
}
