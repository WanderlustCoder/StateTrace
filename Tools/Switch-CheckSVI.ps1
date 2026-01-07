# Check SVI status
$port = New-Object System.IO.Ports.SerialPort 'COM8', 9600, 'None', 8, 'One'
$port.DtrEnable = $true
$port.RtsEnable = $true
$port.ReadTimeout = 5000
$port.Open()

$CR = [char]13

function Send-Command {
    param([string]$cmd, [int]$wait = 2000)
    $port.Write("$cmd$CR")
    Start-Sleep -Milliseconds $wait
    return $port.ReadExisting()
}

try {
    $null = $port.ReadExisting()
    $null = Send-Command "" 500
    $null = Send-Command "enable" 1000
    $null = Send-Command "terminal length 0" 500

    Write-Host "=== IP Interface Brief ===" -ForegroundColor Cyan
    Write-Host (Send-Command "show ip interface brief" 3000)

    Write-Host "=== VLAN 1 Interface ===" -ForegroundColor Cyan
    Write-Host (Send-Command "show interfaces vlan 1" 3000)

    Write-Host "=== ARP Table ===" -ForegroundColor Cyan
    Write-Host (Send-Command "show arp" 2000)
}
finally {
    $port.Close()
}
