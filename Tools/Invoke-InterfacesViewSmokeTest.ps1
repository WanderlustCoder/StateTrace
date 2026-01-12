[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')),
    [string]$Hostname,
    [int]$TimeoutSeconds = 30,
    [int]$NoProgressTimeoutSeconds = 5,
    [int]$PollIntervalMilliseconds = 100,
    [switch]$PassThru
)

Set-StrictMode -Version Latest

if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne [System.Threading.ApartmentState]::STA) {
    throw "Invoke-InterfacesViewSmokeTest.ps1 must run in STA mode. Re-run with 'pwsh -STA -File Tools\Invoke-InterfacesViewSmokeTest.ps1'."
}

$repoRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$modulesDir = Join-Path $repoRoot 'Modules'
$viewsDir   = Join-Path $repoRoot 'Views'

Add-Type -AssemblyName PresentationFramework -ErrorAction Stop

$moduleLoaderPath = Join-Path $modulesDir 'ModuleLoaderModule.psm1'
if (-not (Test-Path -LiteralPath $moduleLoaderPath)) {
    throw "Module loader not found at $moduleLoaderPath"
}
Import-Module -Name $moduleLoaderPath -Force -ErrorAction Stop | Out-Null
ModuleLoaderModule\Import-StateTraceModulesFromManifest -RepositoryRoot $repoRoot | Out-Null

function Resolve-HostToTest {
    param([string]$PreferredHost)

    if ($PreferredHost) {
        return $PreferredHost
    }

    try {
        $catalog = DeviceCatalogModule\Get-DeviceSummaries
        if ($catalog -and $catalog.PSObject.Properties['Hostnames']) {
            $candidates = @($catalog.Hostnames)
            foreach ($candidate in $candidates) {
                if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
                $rows = DeviceRepositoryModule\Get-InterfaceInfo -Hostname $candidate
                if ($rows -and $rows.Count -gt 0) {
                    return $candidate
                }
            }
        }
    } catch { Write-Verbose "Caught exception in Invoke-InterfacesViewSmokeTest.ps1: $($_.Exception.Message)" }

    $dbPaths = DeviceRepositoryModule\Get-AllSiteDbPaths
    foreach ($dbPath in $dbPaths) {
        try {
            $hostname = (Split-Path -Leaf $dbPath) -replace '\.accdb$',''
            $rows = DeviceRepositoryModule\Get-InterfaceInfo -Hostname $hostname
            if ($rows -and $rows.Count -gt 0) {
                return $hostname
            }
        } catch { Write-Verbose "Caught exception in Invoke-InterfacesViewSmokeTest.ps1: $($_.Exception.Message)" }
    }

    throw "Unable to locate a host with interface data. Provide -Hostname explicitly."
}

$targetHost = Resolve-HostToTest -PreferredHost $Hostname

$windowXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Interfaces Smoke Test"
        Height="600"
        Width="900"
        WindowStartupLocation="CenterScreen"
        Visibility="Hidden">
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <TextBlock Text="Interfaces Smoke Test Host"
                   Margin="10"
                   FontWeight="Bold"/>
        <ContentControl x:Name="InterfacesHost"
                        Grid.Row="1"/>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlTextReader (New-Object System.IO.StringReader($windowXaml))
$window = [Windows.Markup.XamlReader]::Load($reader)

InterfaceModule\New-InterfacesView -Window $window

$dto = DeviceDetailsModule\Get-DeviceDetailsData -Hostname $targetHost
if (-not $dto) {
    throw "Get-DeviceDetailsData returned null for host '$targetHost'."
}

InterfaceModule\Set-InterfaceViewData -DeviceDetails $dto -DefaultHostname $targetHost

$collection = $dto.Interfaces
if (-not $collection) {
    $collection = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    $dto.Interfaces = $collection
}

$timeoutMs = [Math]::Max(1000, ($TimeoutSeconds * 1000))
$noProgressMs = if ($NoProgressTimeoutSeconds -gt 0) { [Math]::Max(1000, ($NoProgressTimeoutSeconds * 1000)) } else { 0 }
$pollMs = [Math]::Max(10, $PollIntervalMilliseconds)
$streamWatch = [System.Diagnostics.Stopwatch]::StartNew()
$lastProgressMs = 0

try {
    DeviceRepositoryModule\Initialize-InterfacePortStream -Hostname $targetHost
    while ($true) {
        if ($streamWatch.ElapsedMilliseconds -ge $timeoutMs) {
            throw "InterfacesView smoke test timed out after $TimeoutSeconds seconds for host '$targetHost'."
        }

        $batch = DeviceRepositoryModule\Get-InterfacePortBatch -Hostname $targetHost
        if (-not $batch) {
            $status = $null
            try { $status = DeviceRepositoryModule\Get-InterfacePortStreamStatus -Hostname $targetHost } catch { $status = $null }
            if ($status -and -not $status.Completed) {
                if ($noProgressMs -gt 0 -and ($streamWatch.ElapsedMilliseconds - $lastProgressMs) -ge $noProgressMs) {
                    throw "InterfacesView smoke test stalled for $NoProgressTimeoutSeconds seconds without batch progress (host '$targetHost')."
                }
                Start-Sleep -Milliseconds $pollMs
                continue
            }
            break
        }

        $lastProgressMs = $streamWatch.ElapsedMilliseconds
        foreach ($row in @($batch.Ports)) {
            $collection.Add($row) | Out-Null
        }
    }
} finally {
    try { DeviceRepositoryModule\Clear-InterfacePortStream -Hostname $targetHost } catch { Write-Verbose "Caught exception in Invoke-InterfacesViewSmokeTest.ps1: $($_.Exception.Message)" }
}

$grid = $global:interfacesGrid
if (-not $grid) {
    $grid = $window.FindName('InterfacesGrid')
}

$interfaceCount = 0
if ($collection -and $collection.Count -gt 0) {
    $interfaceCount = [int]$collection.Count
} elseif ($grid -and $grid.Items) {
    $interfaceCount = [int]$grid.Items.Count
}

$result = [pscustomobject]@{
    Hostname        = $targetHost
    InterfaceCount  = $interfaceCount
    Success         = ($interfaceCount -gt 0)
}

if ($PassThru) {
    $result
}

if (-not $result.Success) {
    throw "InterfacesView smoke test failed: no interfaces were bound for host '$($result.Hostname)'."
}
