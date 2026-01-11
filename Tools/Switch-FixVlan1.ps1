# Fix VLAN 1 IP address
param(
    [string]$SerialPort = $env:STATETRACE_SERIAL_PORT
)

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
    Send-Command "interface vlan 1" 500
    Send-Command "ip address 192.168.1.1 255.255.255.0" 1000
    Send-Command "no shutdown" 500
    Send-Command "exit" 300
    Send-Command "end" 500

    Write-Host "`n=== Verifying ===" -ForegroundColor Cyan
    Send-Command "show ip interface vlan 1" 3000

    Write-Host "`n=== Saving ===" -ForegroundColor Cyan
    Send-Command "write memory" 5000
}
finally {
    $port.Close()
}




