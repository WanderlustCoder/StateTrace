[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')),
    [string]$Hostname,
    [int]$SampleCount = 5,
    [switch]$PassThru
)

Set-StrictMode -Version Latest

if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne [System.Threading.ApartmentState]::STA) {
    throw "Invoke-SpanViewSmokeTest.ps1 must run in STA mode. Re-run with 'pwsh -STA -File Tools\Invoke-SpanViewSmokeTest.ps1'."
}

$repoRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$modulesDir = Join-Path $repoRoot 'Modules'
$mainDir    = Join-Path $repoRoot 'Main'

Add-Type -AssemblyName PresentationFramework -ErrorAction Stop

$moduleLoaderPath = Join-Path $modulesDir 'ModuleLoaderModule.psm1'
if (-not (Test-Path -LiteralPath $moduleLoaderPath)) {
    throw "Module loader not found at $moduleLoaderPath"
}
Import-Module -Name $moduleLoaderPath -Force -ErrorAction Stop | Out-Null
ModuleLoaderModule\Import-StateTraceModulesFromManifest -RepositoryRoot $repoRoot | Out-Null

function Resolve-SpanHost {
    param([string]$PreferredHost)

    if ($PreferredHost) {
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
        Title="Span View Smoke Test"
        Height="400"
        Width="600"
        WindowStartupLocation="CenterScreen"
        Visibility="Hidden">
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <TextBlock Text="Span View Smoke Test Host"
                   Margin="10"
                   FontWeight="Bold"/>
        <ContentControl x:Name="SpanHost"
                        Grid.Row="1"/>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlTextReader (New-Object System.IO.StringReader($windowXaml))
$window = [Windows.Markup.XamlReader]::Load($reader)

SpanViewModule\New-SpanView -Window $window -ScriptDir $mainDir
SpanViewModule\Get-SpanInfo -Hostname $targetHost

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

Invoke-DispatcherPump -Milliseconds 150

$snapshot = SpanViewModule\Get-SpanViewSnapshot -IncludeRows -SampleCount $SampleCount

# LANDMARK: ST-D-007 span usage vlan count
$usageVlanCount = 0
try {
    $usageRows = DeviceRepositoryModule\Get-SpanningTreeInfo -Hostname $targetHost
    if (-not $usageRows) { $usageRows = @() }
    $usageVlanCount = @(
        @($usageRows) |
            Where-Object { $_ -and $_.PSObject.Properties['VLAN'] -and ('' + $_.VLAN).Trim() -ne '' } |
            ForEach-Object { '' + $_.VLAN } |
            Select-Object -Unique
    ).Count
} catch { $usageVlanCount = 0 }

$result = [pscustomobject]@{
    Hostname      = $targetHost
    RowCount      = $snapshot.RowCount
    CachedRowCount= $snapshot.CachedRowCount
    SelectedVlan  = $snapshot.SelectedVlan
    LastRefreshed = $snapshot.LastRefreshed
    StatusText    = $snapshot.StatusText
    UsedLastRows  = $snapshot.UsedLastRows
    SampleRows    = $snapshot.SampleRows
    Success       = ($snapshot.RowCount -gt 0)
}

# LANDMARK: ST-D-007 span usage telemetry
try {
    TelemetryModule\Write-StTelemetryEvent -Name 'UserAction' -Payload @{
        Action    = 'SpanViewUsage'
        Hostname  = $targetHost
        VlanCount = $usageVlanCount
        RowsBound = $snapshot.RowCount
        Timestamp = (Get-Date).ToString('o')
    }
    TelemetryModule\Save-StTelemetryBuffer | Out-Null
} catch [System.Management.Automation.CommandNotFoundException] {
} catch { }

if ($PassThru) {
    $result
}

if (-not $result.Success) {
    throw "Span View smoke test failed: no data bound for host '$($result.Hostname)'."
}
