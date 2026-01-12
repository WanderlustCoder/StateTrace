# Configure RADIUS for 802.1X/MAB testing
[CmdletBinding()]
param(
    [string]$SerialPort = $env:STATETRACE_SERIAL_PORT,
    [Parameter(Mandatory)]
    [string]$RadiusServer,
    [int]$AuthPort = 1812,
    [int]$AcctPort = 1813,
    [Parameter(Mandatory)]
    [string]$SharedSecret,
    [string]$TestUsername,
    [string]$TestPassword,
    [string]$TestPort = 'GigabitEthernet1/0/2',
    [int]$TestVlan = 100,
    [switch]$SkipTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($SerialPort)) {
    throw 'SerialPort is required. Provide -SerialPort or set STATETRACE_SERIAL_PORT.'
}

$port = New-Object System.IO.Ports.SerialPort $SerialPort, 9600, 'None', 8, 'One'
$port.DtrEnable = $true
$port.RtsEnable = $true
$port.ReadTimeout = 1000
$port.Open()

$CR = [char]13

function Send-Command {
    param([string]$cmd, [int]$wait = 1500)
    Write-Host ">>> $cmd" -ForegroundColor Yellow
    $port.DiscardInBuffer()
    $port.Write("$cmd$CR")
    Start-Sleep -Milliseconds $wait
    $output = $port.ReadExisting()
    if ($output) { Write-Host $output -ForegroundColor Gray }
    return $output
}

try {
    $null = $port.ReadExisting()
    Send-Command "" 500
    Send-Command "enable" 1000
    Send-Command "configure terminal" 1000

    Write-Host "`n=== Configuring AAA ===" -ForegroundColor Cyan
    Send-Command "aaa new-model" 500
    Send-Command "aaa authentication dot1x default group radius" 500
    Send-Command "aaa authorization network default group radius" 500
    Send-Command "aaa accounting dot1x default start-stop group radius" 500

    Write-Host "`n=== Configuring RADIUS Server ===" -ForegroundColor Cyan
    Send-Command "radius server FREERADIUS" 500
    Send-Command "address ipv4 $RadiusServer auth-port $AuthPort acct-port $AcctPort" 500
    Send-Command "key $SharedSecret" 500
    Send-Command "exit" 300

    Send-Command "radius-server attribute 6 on-for-login-auth" 500
    Send-Command "radius-server attribute 8 include-in-access-req" 500
    Send-Command "radius-server attribute 25 access-request include" 500

    Write-Host "`n=== Enabling 802.1X Globally ===" -ForegroundColor Cyan
    Send-Command "dot1x system-auth-control" 500

    Write-Host "`n=== Configuring Test Port ($TestPort) ===" -ForegroundColor Cyan
    Send-Command "interface $TestPort" 500
    Send-Command "description DOT1X-TEST-PORT" 300
    Send-Command "switchport mode access" 300
    Send-Command "switchport access vlan $TestVlan" 300
    Send-Command "authentication port-control auto" 500
    Send-Command "authentication order mab dot1x" 300
    Send-Command "authentication priority dot1x mab" 300
    Send-Command "authentication host-mode multi-auth" 300
    Send-Command "mab" 300
    Send-Command "dot1x pae authenticator" 300
    Send-Command "spanning-tree portfast edge" 300
    Send-Command "exit" 300

    Send-Command "end" 500

    Write-Host "`n=== Verifying Configuration ===" -ForegroundColor Cyan
    Send-Command "show aaa servers" 3000
    Send-Command "show radius statistics" 2000

    Write-Host "`n=== Saving Configuration ===" -ForegroundColor Cyan
    Send-Command "write memory" 5000

    if (-not $SkipTest) {
        Write-Host "`n=== Testing RADIUS Connectivity ===" -ForegroundColor Cyan
        if ([string]::IsNullOrWhiteSpace($TestUsername) -or [string]::IsNullOrWhiteSpace($TestPassword)) {
            Write-Warning 'Skipping RADIUS test; provide -TestUsername and -TestPassword or use -SkipTest.'
        } else {
            Send-Command "test aaa group radius $TestUsername $TestPassword legacy" 5000
        }
    }
}
finally {
    $port.Close()
}

Write-Host "`n=== Configuration Complete ===" -ForegroundColor Green
Write-Host "RADIUS Server: ${RadiusServer}:${AuthPort}" -ForegroundColor White
Write-Host "802.1X Test Port: $TestPort (VLAN $TestVlan)" -ForegroundColor White
