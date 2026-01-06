# Test-LogParser.ps1 - Test StateTrace parser on the live switch log
$ErrorActionPreference = 'Stop'

# Import modules
$modulesPath = Split-Path $PSScriptRoot -Parent | Join-Path -ChildPath 'Modules'
Import-Module (Join-Path $modulesPath 'DeviceParsingCommon.psm1') -Force
Import-Module (Join-Path $modulesPath 'DeviceLogParserModule.psm1') -Force
Import-Module (Join-Path $modulesPath 'CiscoModule.psm1') -Force

$logPath = 'C:\Users\Werem\Projects\StateTrace\Tests\Fixtures\LiveSwitch\LAB-C9200L-AS-01.log'
$lines = Get-Content -Path $logPath

Write-Host 'Parsing log file...' -ForegroundColor Cyan
$result = CiscoModule\Get-CiscoDeviceFacts -Lines $lines

Write-Host "`nParsed Device Info:" -ForegroundColor Green
Write-Host "  Hostname: $($result.Hostname)"
Write-Host "  Make: $($result.Make)"
Write-Host "  Model: $($result.Model)"
Write-Host "  Version: $($result.Version)"
Write-Host "  Uptime: $($result.Uptime)"
Write-Host "  Location: $($result.Location)"
Write-Host "  Interface Count: $($result.InterfaceCount)"

Write-Host "`nInterfaces Summary:" -ForegroundColor Green
$result.InterfacesCombined | Format-Table Port, Name, Status, VLAN, Speed, Type -AutoSize

Write-Host "`nSpanning Tree VLANs:" -ForegroundColor Green
if ($result.SpanInfo) {
    $result.SpanInfo | Format-Table VLAN, RootBridge, LocalBridge, RootPort -AutoSize
}

Write-Host "`nParser test complete!" -ForegroundColor Cyan
