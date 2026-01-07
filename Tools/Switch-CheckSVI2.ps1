# Check SVI status - improved reading
$port = New-Object System.IO.Ports.SerialPort 'COM8', 9600, 'None', 8, 'One'
$port.DtrEnable = $true
$port.RtsEnable = $true
$port.ReadTimeout = 1000
$port.Open()

$CR = [char]13

function Send-Command {
    param([string]$cmd, [int]$wait = 3000)
    Write-Host ">>> $cmd" -ForegroundColor Yellow
    $port.DiscardInBuffer()
    $port.Write("$cmd$CR")
    Start-Sleep -Milliseconds $wait

    $output = ""
    $lastRead = Get-Date
    do {
        $chunk = $port.ReadExisting()
        if ($chunk) {
            $output += $chunk
            $lastRead = Get-Date
        }
        Start-Sleep -Milliseconds 200
    } while (((Get-Date) - $lastRead).TotalMilliseconds -lt 1500)

    return $output
}

try {
    $null = $port.ReadExisting()

    Write-Host (Send-Command "" 1000)
    Write-Host (Send-Command "enable" 1000)
    Write-Host (Send-Command "terminal length 0" 1000)

    Write-Host "`n=== show ip interface brief ===" -ForegroundColor Cyan
    Write-Host (Send-Command "show ip interface brief" 4000)

    Write-Host "`n=== show interfaces vlan 1 ===" -ForegroundColor Cyan
    Write-Host (Send-Command "show interfaces vlan 1" 4000)
}
finally {
    $port.Close()
}
