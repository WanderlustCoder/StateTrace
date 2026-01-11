# Switch-Init.ps1 - Initialize switch and get to enabled mode
param(
    [string]$SerialPort = $env:STATETRACE_SERIAL_PORT
)

if ([string]::IsNullOrWhiteSpace($SerialPort)) {
    throw 'SerialPort is required. Provide -SerialPort or set STATETRACE_SERIAL_PORT.'
}
$port = New-Object System.IO.Ports.SerialPort $SerialPort, 9600, 'None', 8, 'One'
$port.ReadTimeout = 5000
$port.WriteTimeout = 3000

function Send-AndRead {
    param([string]$cmd, [int]$waitMs = 2000)
    if ($cmd) { $port.WriteLine($cmd) }
    Start-Sleep -Milliseconds $waitMs
    return $port.ReadExisting()
}

try {
    $port.Open()
    Write-Host "Port opened"

    # Clear buffer and wake up
    $null = $port.ReadExisting()

    # Send multiple enters
    for ($i = 0; $i -lt 3; $i++) {
        $port.WriteLine("")
        Start-Sleep -Milliseconds 500
    }
    Start-Sleep -Seconds 2
    $output = $port.ReadExisting()
    Write-Host "Initial state:"
    Write-Host $output
    Write-Host "---"

    # Check for initial config dialog
    if ($output -match "initial configuration dialog" -or $output -match "Would you like to enter") {
        Write-Host "Detected initial config dialog, sending 'no'"
        $output = Send-AndRead "no" 3000
        Write-Host $output
    }

    # Check for Press RETURN
    if ($output -match "Press RETURN") {
        Write-Host "Sending RETURN"
        $output = Send-AndRead "" 2000
        Write-Host $output
    }

    # Try to get to enable mode
    $port.WriteLine("enable")
    Start-Sleep -Seconds 1
    $output = $port.ReadExisting()
    Write-Host "After enable:"
    Write-Host $output

    # Check for password prompt
    if ($output -match "Password:") {
        Write-Host "Password required - trying empty password"
        $output = Send-AndRead "" 2000
        Write-Host $output
    }

    # Try show version
    Write-Host "Trying show version..."
    $port.WriteLine("terminal length 0")
    Start-Sleep -Milliseconds 500
    $null = $port.ReadExisting()

    $port.WriteLine("show version")
    Start-Sleep -Seconds 3
    $output = $port.ReadExisting()
    Write-Host $output

}
catch {
    Write-Error "Error: $($_.Exception.Message)"
}
finally {
    if ($port.IsOpen) {
        $port.Close()
    }
}




