<# 
.SYNOPSIS
Collects a headless snapshot of location dropdown inputs without loading interfaces.

.DESCRIPTION
Mimics the MainWindow startup path (location loading only). It:
- Imports catalog/filter/view modules.
- Forces InterfacesLoadAllowed = $false and clears DeviceMetadata.
- Hydrates location entries via Get-DeviceLocationEntries.
- Runs Initialize-DeviceFilters/Update-DeviceFilter against a dummy window/controls.
- Records site/zone/building/room/host lists and the AllInterfaces count.
Outputs to Logs/Diagnostics/LocationStartupSnapshot-<timestamp>.txt.
#>
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-DummyWindow {
    $controls = @{
        SiteDropdown     = New-Object System.Windows.Controls.ComboBox
        ZoneDropdown     = New-Object System.Windows.Controls.ComboBox
        BuildingDropdown = New-Object System.Windows.Controls.ComboBox
        RoomDropdown     = New-Object System.Windows.Controls.ComboBox
        HostnameDropdown = New-Object System.Windows.Controls.ComboBox
    }
    $win = New-Object psobject
    $win | Add-Member ScriptMethod FindName {
        param($name)
        if ($controls.ContainsKey($name)) { return $controls[$name] }
        return $null
    }
    return @{
        Window   = $win
        Controls = $controls
    }
}

Add-Type -AssemblyName PresentationFramework

$repoRoot = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $repoRoot 'Logs\Diagnostics'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logPath = Join-Path $logDir ("LocationStartupSnapshot-{0:yyyyMMdd-HHmmss}.txt" -f (Get-Date))

Import-Module (Join-Path $repoRoot 'Modules\DeviceCatalogModule.psm1') -Force
Import-Module (Join-Path $repoRoot 'Modules\FilterStateModule.psm1')   -Force
Import-Module (Join-Path $repoRoot 'Modules\ViewStateService.psm1')    -Force

$global:DeviceMetadata = $null
$global:InterfacesLoadAllowed = $false
$global:DeviceLocationEntries = @()

$locationEntries = @()
try { $locationEntries = DeviceCatalogModule\Get-DeviceLocationEntries } catch { $locationEntries = @() }
$global:DeviceLocationEntries = $locationEntries

$dummy = New-DummyWindow
$window   = $dummy.Window
$controls = $dummy.Controls

FilterStateModule\Initialize-DeviceFilters -Window $window -LocationEntries $locationEntries
FilterStateModule\Update-DeviceFilter

$siteItems     = @($controls['SiteDropdown'].ItemsSource)
$zoneItems     = @($controls['ZoneDropdown'].ItemsSource)
$buildingItems = @($controls['BuildingDropdown'].ItemsSource)
$roomItems     = @($controls['RoomDropdown'].ItemsSource)
$hostItems     = @($controls['HostnameDropdown'].ItemsSource)

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("Location entries count: {0}" -f $locationEntries.Count) | Out-Null
$lines.Add("Location entries: " + (($locationEntries | ForEach-Object { "Site=$($_.Site);Zone=$($_.Zone);Building=$($_.Building);Room=$($_.Room)" }) -join ' | ')) | Out-Null
$lines.Add("Sites dropdown: "     + ($siteItems     -join ', ')) | Out-Null
$lines.Add("Zones dropdown: "     + ($zoneItems     -join ', ')) | Out-Null
$lines.Add("Buildings dropdown: " + ($buildingItems -join ', ')) | Out-Null
$lines.Add("Rooms dropdown: "     + ($roomItems     -join ', ')) | Out-Null
$lines.Add("Hosts dropdown: "     + ($hostItems     -join ', ')) | Out-Null
$lines.Add("Interfaces count: {0}" -f ($global:AllInterfaces | ForEach-Object { $_ } | Measure-Object | Select-Object -ExpandProperty Count)) | Out-Null

$lines | Out-File -LiteralPath $logPath -Encoding UTF8

Write-Host "Location startup snapshot written to $logPath"
