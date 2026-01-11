# Configure VLAN 1 SVI for VM connectivity
param(
    [string]$SerialPort = $env:STATETRACE_SERIAL_PORT
)

if ([string]::IsNullOrWhiteSpace($SerialPort)) {
    throw 'SerialPort is required. Provide -SerialPort or set STATETRACE_SERIAL_PORT.'
}
$port = New-Object System.IO.Ports.SerialPort $SerialPort, 9600, 'None', 8, 'One'
$port.DtrEnable = $true
$port.RtsEnable = $true
$port.ReadTimeout = 5000
$port.Open()

$CR = [char]13

function Send-Command {
    param([string]$cmd, [int]$wait = 1000)
    Write-Host ">>> $cmd" -ForegroundColor Yellow
    $port.Write("$cmd$CR")
    Start-Sleep -Milliseconds $wait
    $output = $port.ReadExisting()
    if ($output) { Write-Host $output -ForegroundColor Gray }
}

try {
    $null = $port.ReadExisting()
    Send-Command "terminal length 0" 500
    Send-Command "configure terminal" 1000

    # Create SVI on VLAN 1 for VM communication
    Send-Command "interface Vlan1" 500
    Send-Command "description Lab Network - VM Access" 300
    Send-Command "ip address 192.168.1.1 255.255.255.0" 500
    Send-Command "no shutdown" 300
    Send-Command "exit" 300

    Send-Command "end" 500
    Send-Command "write memory" 3000

    Write-Host "`nVLAN 1 SVI configured: 192.168.1.1/24" -ForegroundColor Green
}
finally {
    $port.Close()
}




