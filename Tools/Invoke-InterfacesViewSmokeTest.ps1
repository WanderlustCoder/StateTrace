[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')),
    [string]$Hostname,
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

$manifestPath = Join-Path $modulesDir 'ModulesManifest.psd1'
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Module manifest not found at $manifestPath"
}

if (Get-Command -Name Import-PowerShellDataFile -ErrorAction SilentlyContinue) {
    $manifest = Import-PowerShellDataFile -Path $manifestPath
} else {
    $manifest = . $manifestPath
}

$moduleList = @()
if ($manifest -and ($manifest -is [System.Collections.IDictionary]) -and $manifest.Contains('ModulesToImport')) {
    $moduleList = @($manifest['ModulesToImport'])
} elseif ($manifest -and ($manifest -is [System.Collections.IDictionary]) -and $manifest.Contains('Modules')) {
    $moduleList = @($manifest['Modules'])
} else {
    throw "ModulesManifest.psd1 does not define ModulesToImport or Modules entries."
}

foreach ($moduleName in $moduleList) {
    $modulePath = Join-Path $modulesDir $moduleName
    if (-not (Test-Path -LiteralPath $modulePath)) {
        throw "Module '$moduleName' missing at $modulePath"
    }
    Import-Module -Name $modulePath -Global -ErrorAction Stop
}

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
    } catch { }

    $dbPaths = DeviceRepositoryModule\Get-AllSiteDbPaths
    foreach ($dbPath in $dbPaths) {
        try {
            $hostname = (Split-Path -Leaf $dbPath) -replace '\.accdb$',''
            $rows = DeviceRepositoryModule\Get-InterfaceInfo -Hostname $hostname
            if ($rows -and $rows.Count -gt 0) {
                return $hostname
            }
        } catch { }
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

DeviceRepositoryModule\Initialize-InterfacePortStream -Hostname $targetHost
while ($true) {
    $batch = DeviceRepositoryModule\Get-InterfacePortBatch -Hostname $targetHost
    if (-not $batch) { break }
    foreach ($row in @($batch.Ports)) {
        $collection.Add($row) | Out-Null
    }
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
