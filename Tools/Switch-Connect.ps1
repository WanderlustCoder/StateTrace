# Switch-Connect.ps1 - Connect to switch and handle initial config dialog
$port = New-Object System.IO.Ports.SerialPort 'COM8', 9600, 'None', 8, 'One'
$port.ReadTimeout = 10000
$port.WriteTimeout = 3000
$port.DtrEnable = $true
$port.RtsEnable = $true

try {
    $port.Open()
    Write-Host "Port opened - waiting for any output..."

    # Long initial wait to catch any pending output
    Start-Sleep -Seconds 2
    $output = $port.ReadExisting()
    if ($output) { Write-Host "Buffer: $output" }

    # Send break character (Ctrl+C) to interrupt anything
    $port.Write([char]3)  # Ctrl+C
    Start-Sleep -Milliseconds 500

    # Send several enters
    for ($i = 0; $i -lt 5; $i++) {
        $port.WriteLine("")
        Start-Sleep -Milliseconds 300
    }

    Start-Sleep -Seconds 3
    $output = $port.ReadExisting()
    Write-Host "After enters: [$output]"

    # Try typing "no" in case we're at initial config dialog
    $port.WriteLine("no")
    Start-Sleep -Seconds 2
    $output = $port.ReadExisting()
    Write-Host "After no: [$output]"

    # Hit enter again
    $port.WriteLine("")
    Start-Sleep -Seconds 2
    $output = $port.ReadExisting()
    Write-Host "After enter: [$output]"

    # Try enable command
    $port.WriteLine("enable")
    Start-Sleep -Seconds 1
    $output = $port.ReadExisting()
    Write-Host "After enable: [$output]"

    # If password prompt, try empty
    if ($output -match "Password") {
        $port.WriteLine("")
        Start-Sleep -Seconds 1
        $output = $port.ReadExisting()
        Write-Host "After password: [$output]"
    }

    # Now try a command
    $port.WriteLine("show clock")
    Start-Sleep -Seconds 2
    $output = $port.ReadExisting()
    Write-Host "show clock: [$output]"

}
catch {
    Write-Error "Error: $($_.Exception.Message)"
}
finally {
    if ($port.IsOpen) { $port.Close() }
}
