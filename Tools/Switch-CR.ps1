# Switch-CR.ps1 - Send CR like PuTTY does
param(
    [string]$SerialPort = $env:STATETRACE_SERIAL_PORT
)

if ([string]::IsNullOrWhiteSpace($SerialPort)) {
    throw 'SerialPort is required. Provide -SerialPort or set STATETRACE_SERIAL_PORT.'
}
$port = New-Object System.IO.Ports.SerialPort $SerialPort, 9600, 'None', 8, 'One'
$port.DtrEnable = $true
$port.RtsEnable = $true
$port.Open()

# Send just CR (carriage return) - ASCII 13
Write-Host 'Sending CR...'
$port.Write([char]13)
Start-Sleep -Seconds 2
$output = $port.ReadExisting()
Write-Host "Output1: [$output]"

# Send another CR
$port.Write([char]13)
Start-Sleep -Seconds 2
$output = $port.ReadExisting()
Write-Host "Output2: [$output]"

# Try enable command with CR
Write-Host 'Sending enable...'
$port.Write("enable$([char]13)")
Start-Sleep -Seconds 2
$output = $port.ReadExisting()
Write-Host "After enable: [$output]"

# Try show version
Write-Host 'Sending show version...'
$port.Write("show version$([char]13)")
Start-Sleep -Seconds 4
$output = $port.ReadExisting()
Write-Host "show version output:"
Write-Host $output

$port.Close()




